// API integration tests. No dependencies — node:test + global fetch.
//
// Auth is Firebase in production, which tests cannot mint. The server
// exposes a test-only bypass (see requireAuth): run BOTH the api and the
// suite with the same bypass token, e.g. PowerShell:
//   $env:NODE_ENV='test'; $env:ENABLE_TEST_BYPASS='1'; $env:TEST_BYPASS_TOKEN='ci-local-secret'
//   npm run dev   (terminal 1)   +   npm test   (terminal 2)
// The hatch is closed unless ALL THREE vars are set — production is unaffected.
//
// Needs the stack up first:
//   1. docker compose up -d        (postgres on :5433)
//   2. server with bypass env       (api on :8080, in another terminal)
//   3. npm test (same env vars)
//
// Every test uses timestamped emails, and each account is deleted at
// the end, so runs never pollute each other (or your real data).
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';

const BASE = process.env.TEST_API ?? 'http://localhost:8080';
const BYPASS = process.env.TEST_BYPASS_TOKEN;
if (!BYPASS) {
  throw new Error(
    'TEST_BYPASS_TOKEN is not set — see the header comment for how to run the suite.',
  );
}
const stamp = Date.now().toString(36);

// Test "sign-in": bypass token for this address. First authed request
// auto-creates the user row (same seeds as firebase-sync).
const tokenFor = (n) => `${BYPASS}:${email(n)}`;

async function api(method, path, { token, body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    /* 204/HTML bodies */
  }
  return { status: res.status, json, headers: res.headers };
}

const email = (n) => `${n}-${stamp}@test.local`;

describe('health', () => {
  it('reports ok with a database behind it', async () => {
    const r = await api('GET', '/health');
    assert.equal(r.status, 200);
    assert.equal(r.json.ok, true);
  });
});

describe('auth', () => {
  const token = tokenFor('a');

  it('requires a token on data routes', async () => {
    const r = await api('GET', '/api/tasks');
    assert.equal(r.status, 401);
  });

  it('rejects a garbage bearer with 401', async () => {
    const r = await api('GET', '/api/tasks', { token: 'garbage' });
    assert.equal(r.status, 401);
  });

  it('loads the profile with the token (auto-creates the user)', async () => {
    const r = await api('GET', '/api/auth/me', { token });
    assert.equal(r.status, 200);
    assert.equal(r.json.user.email, email('a'));
  });

  it('deletes the account and wipes its data', async () => {
    const del = await api('DELETE', '/api/auth/account', { token });
    assert.equal(del.status, 200);
    // Bypass re-creates a FRESH row on next use — assert the wipe:
    const me = await api('GET', '/api/auth/me', { token });
    assert.equal(me.status, 200);
    const wallet = await api('GET', '/api/wallet', { token });
    assert.equal(wallet.json.balance, 450);
    await api('DELETE', '/api/auth/account', { token });
  });
});

describe('isolation + flows', () => {
  let ta, tb;

  before(async () => {
    ta = tokenFor('iso-a');
    tb = tokenFor('iso-b');
  });

  it("B cannot see A's tasks", async () => {
    await api('POST', '/api/tasks', {
      token: ta,
      body: { title: 'private probe' },
    });
    const r = await api('GET', '/api/tasks', { token: tb });
    assert.deepEqual(r.json, []);
  });

  it("B cannot move A's task (404, not 403 — no existence leak)", async () => {
    const mine = await api('GET', '/api/tasks', { token: ta });
    const id = mine.json[0].id;
    const r = await api('PATCH', `/api/tasks/${id}`, {
      token: tb,
      body: { status: 'done' },
    });
    assert.equal(r.status, 404);
  });

  it('completing a task fires the starter rule (+10 tokens, success run)', async () => {
    const mine = await api('GET', '/api/tasks', { token: ta });
    const id = mine.json[0].id;
    await api('PATCH', `/api/tasks/${id}`, {
      token: ta,
      body: { status: 'done' },
    });
    const wallet = await api('GET', '/api/wallet', { token: ta });
    assert.equal(wallet.json.balance, 460);
    const rules = await api('GET', '/api/rules', { token: ta });
    const runs = await api('GET', `/api/rules/${rules.json[0].id}/runs`, {
      token: ta,
    });
    assert.equal(runs.json[0].status, 'success');
    // cleanup: accounts cascade everything they own
    await api('DELETE', '/api/auth/account', { token: ta });
    await api('DELETE', '/api/auth/account', { token: tb });
  });
});

describe('batch: search, due dates, export, delete, sync-guard', () => {
  let t;

  before(async () => {
    t = tokenFor('batch');
    await api('POST', '/api/tasks', {
      token: t,
      body: { title: 'Batch probe one', tag: 'ZZZQ' },
    });
  });

  it('searches by title and tag, rejects short queries', async () => {
    const hits = await api('GET', '/api/tasks/search?q=zzzq', { token: t });
    assert.equal(hits.json.length, 1);
    const short = await api('GET', '/api/tasks/search?q=z', { token: t });
    assert.equal(short.status, 400);
  });

  it('sets and clears a due date', async () => {
    const mine = await api('GET', '/api/tasks', { token: t });
    const id = mine.json[0].id;
    const set = await api('PATCH', `/api/tasks/${id}`, {
      token: t,
      body: { due_at: '2026-12-31T00:00:00Z' },
    });
    assert.ok(set.json.due_at);
    const cleared = await api('PATCH', `/api/tasks/${id}`, {
      token: t,
      body: { due_at: null },
    });
    assert.equal(cleared.json.due_at, null);
  });

  it('exports the whole account', async () => {
    const r = await api('GET', '/api/export', { token: t });
    assert.equal(r.status, 200);
    assert.equal(r.json.tasks.length, 1);
    assert.equal(r.json.wallet, 450);
    assert.ok(r.json.user);
  });

  it('firebase-sync without a token is 401', async () => {
    const r = await api('POST', '/api/auth/firebase-sync', {
      body: { email: email('batch') },
    });
    assert.equal(r.status, 401);
  });

  it('subtask ticks are logged as history events', async () => {
    const mine = await api('GET', '/api/tasks', { token: t });
    const id = mine.json[0].id;
    const sub = await api('POST', `/api/tasks/${id}/subtasks`, {
      token: t,
      body: { title: 'Hist sub' },
    });
    assert.equal(sub.status, 201);
    await api('PATCH', `/api/subtasks/${sub.json.id}`, {
      token: t,
      body: { done: true },
    });
    const events = await api('GET', `/api/tasks/${id}/events`, { token: t });
    const tick = events.json.find((e) => e.kind === 'subtask');
    assert.ok(tick);
    assert.equal(tick.to_status, 'done');
    assert.equal(tick.body, 'Hist sub');
  });

  it('deletes the task, then 404s on repeat', async () => {
    const mine = await api('GET', '/api/tasks', { token: t });
    const id = mine.json[0].id;
    const del = await api('DELETE', `/api/tasks/${id}`, { token: t });
    assert.equal(del.status, 204);
    const again = await api('DELETE', `/api/tasks/${id}`, { token: t });
    assert.equal(again.status, 404);
    await api('DELETE', '/api/auth/account', { token: t });
  });
});
