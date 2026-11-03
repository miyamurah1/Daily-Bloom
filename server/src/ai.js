// Daily Bloom AI proxy — Gemini 2.5 Flash-Lite primary, Groq fallback,
// local heuristics when no keys or both providers fail.
//
// Design: keys stay server-side, clients call POST /api/ai/* with Firebase
// auth. Every handler returns 200 with { data, model, fallback } so the app
// never breaks offline or over quota — offline-first preserved.

const GEMINI_MODEL = 'gemini-2.5-flash-lite';
const GROQ_MODEL = 'llama-3.1-8b-instant';

const DAILY_CAP = Number(process.env.AI_DAILY_CAP ?? 50);
const usageByUserDay = new Map(); // `${userId}:${day}` -> count

export function dailyKey(userId, now = new Date()) {
  return `${userId}:${now.toISOString().slice(0, 10)}`;
}

export function checkCap(userId) {
  const k = dailyKey(userId);
  const n = usageByUserDay.get(k) ?? 0;
  if (n >= DAILY_CAP) return false;
  usageByUserDay.set(k, n + 1);
  return true;
}

/// Persistent equivalent used by the API. The in-memory function above stays
/// available for pure local-heuristic tests and development helpers.
export async function checkPersistentCap(pool, userId) {
  const limit = Number.isFinite(DAILY_CAP) && DAILY_CAP > 0 ? DAILY_CAP : 50;
  const { rows } = await pool.query(
    `INSERT INTO ai_usage (user_id, day, calls)
     VALUES ($1, CURRENT_DATE, 1)
     ON CONFLICT (user_id, day) DO UPDATE
       SET calls = ai_usage.calls + 1, updated_at = now()
       WHERE ai_usage.calls < $2
     RETURNING calls`,
    [userId, limit],
  );
  return rows.length > 0;
}

export function resetCaps() {
  usageByUserDay.clear();
}

export function localFor(kind, payload) {
  if (kind === 'parse') return parseQuickAddLocal(payload.text);
  if (kind === 'breakdown') return { steps: breakdownLocal(payload.title) };
  if (kind === 'narrative') return narrativeLocal(payload);
  if (kind === 'groom') return groomLocal(payload.tasks);
  if (kind === 'ask') return askLocal(payload.question, payload.tasks);
  return planLocal(payload.tasks);
}

/// Weekly narrative from the numbers the client already has (tips +
/// stats). Bloom tone: warm, specific, one nudge. No guilt.
export function narrativeLocal({ tips = [], stats = {} } = {}) {
  const done = Number(stats.done ?? 0);
  const streak = Number(stats.streak ?? 0);
  const focus = Number(stats.focusMinutes ?? 0);
  const first = tips.length ? String(tips[0]) : null;
  const lines = [];
  if (done > 0) {
    lines.push(
      `You closed ${done} task${done === 1 ? '' : 's'} this week${streak > 1 ? ` on a ${streak}-day streak` : ''} — the garden is visibly fuller.`,
    );
  } else {
    lines.push('A quiet week — the soil is rested and ready for one small planting.');
  }
  if (focus > 0) lines.push(`You banked ${focus} focused minutes; protect that hour like a ritual.`);
  if (first) lines.push(first);
  if (!lines.length) lines.push('Small steps count — plant one bloom today.');
  return { text: lines.slice(0, 3).join(' ') };
}

function normTitle(s) {
  return String(s ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/// Backlog groom: duplicates (same normalized title, keep newest),
/// stale (open 30+ days, no due date), vague (under 12 chars).
/// Nothing is deleted here — the client confirms every group.
export function groomLocal(tasks) {
  const list = (Array.isArray(tasks) ? tasks : []).filter(
    (t) => t && t.status !== 'done',
  );
  const groups = [];
  const byTitle = new Map();
  for (const t of list) {
    const k = normTitle(t.title);
    if (!k) continue;
    if (!byTitle.has(k)) byTitle.set(k, []);
    byTitle.get(k).push(t);
  }
  for (const [k, rows] of byTitle) {
    if (rows.length < 2) continue;
    const sorted = [...rows].sort((a, b) =>
      String(a.created_at ?? '').localeCompare(String(b.created_at ?? '')),
    );
    const keep = sorted[sorted.length - 1];
    groups.push({
      kind: 'duplicates',
      title: `“${keep.title.slice(0, 60)}” appears ${rows.length}x`,
      ids: sorted.slice(0, -1).map((t) => String(t.id)),
      action: 'delete-others',
      note: 'Keep the newest, clear the copies.',
    });
    void k;
  }
  const stale = list.filter((t) => {
    if (t.due_at) return false;
    const c = t.created_at ? new Date(t.created_at).getTime() : NaN;
    return !Number.isNaN(c) && Date.now() - c > 30 * 24 * 3600 * 1000;
  });
  if (stale.length) {
    groups.push({
      kind: 'stale',
      title: `${stale.length} untouched for 30+ days`,
      ids: stale.slice(0, 20).map((t) => String(t.id)),
      action: 'defer-week',
      note: 'Give them next week or let them go.',
    });
  }
  const vague = list.filter(
    (t) => String(t.title ?? '').trim().length < 12,
  );
  if (vague.length) {
    groups.push({
      kind: 'vague',
      title: `${vague.length} need sharpening`,
      ids: vague.slice(0, 20).map((t) => String(t.id)),
      action: 'review',
      note: 'Open each and say what done looks like.',
    });
  }
  return { groups: groups.slice(0, 6) };
}

/// Ask-your-tasks: keyword scoring over title (x3), tag/folder (x2),
/// description (x1). Returns a one-line answer + ranked ids.
export function askLocal(question, tasks) {
  const words = String(question ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 2 && !/^(what|when|where|which|with|how|the|and|for|are|was|were|task|tasks|show|find|give|list|any|all|about)$/.test(w));
  const list = Array.isArray(tasks) ? tasks : [];
  if (!words.length) return { answer: 'Ask me about a tag, folder, or word in your tasks.', ids: [] };
  const scored = [];
  for (const t of list) {
    const title = String(t.title ?? '').toLowerCase();
    const tag = String(t.tag ?? '').toLowerCase();
    const folder = String(t.folder ?? '').toLowerCase();
    const desc = String(t.description ?? '').toLowerCase();
    let score = 0;
    for (const w of words) {
      if (title.includes(w)) score += 3;
      if (tag.includes(w) || folder.includes(w)) score += 2;
      if (desc.includes(w)) score += 1;
    }
    if (score > 0) scored.push({ t, score });
  }
  scored.sort((a, b) => b.score - a.score);
  const top = scored.slice(0, 5);
  if (!top.length) {
    return { answer: `Nothing matches “${String(question).slice(0, 60)}” yet.`, ids: [] };
  }
  const open = top.filter((s) => s.t.status !== 'done').length;
  return {
    answer: `${top.length} match${top.length === 1 ? '' : 'es'}${open ? `, ${open} still open` : ', all done'} — top: “${String(top[0].t.title).slice(0, 80)}”.`,
    ids: top.map((s) => String(s.t.id)),
  };
}

// ---------- Local heuristics ($0, offline) ----------

const TAG_HINTS = [
  [/work|meeting|report|email|deploy|review/i, 'Work'],
  [/home|family|mom|dad|kids|grocery|clean/i, 'Home'],
  [/health|gym|run|doctor|sleep|walk/i, 'Health'],
  [/learn|study|read|course|practice/i, 'Learning'],
  [/idea|brainstorm|draft|write/i, 'Idea'],
];

export function parseQuickAddLocal(raw) {
  const text = String(raw ?? '').trim();
  let title = text;
  let tag = 'General';
  let folder = 'Productivity';
  let priority = 'none';
  let due = null;

  const hash = text.match(/#([A-Za-z0-9_-]+)/);
  if (hash) {
    const t = hash[1];
    tag = t.charAt(0).toUpperCase() + t.slice(1);
    title = title.replace(hash[0], ' ').trim();
  } else {
    for (const [re, name] of TAG_HINTS) {
      if (re.test(title)) {
        tag = name;
        break;
      }
    }
  }

  if (/!!!|\burgent\b|\bhigh[\s-]?priority\b|\bp1\b/i.test(title)) {
    priority = 'high';
    title = title.replace(/!!!|\burgent\b|\bhigh[\s-]?priority\b|\bp1\b/gi, ' ').trim();
  }

  const now = new Date();
  const atMidnight = (d) => {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    return x;
  };
  const lower = title.toLowerCase();
  if (/\btomorrow\b/.test(lower)) {
    const d = atMidnight(now);
    d.setDate(d.getDate() + 1);
    due = d;
    title = title.replace(/tomorrow/gi, ' ').trim();
  } else if (/\btoday\b/.test(lower)) {
    due = atMidnight(now);
    title = title.replace(/today/gi, ' ').trim();
  } else if (/\bnext week\b/.test(lower)) {
    const d = atMidnight(now);
    d.setDate(d.getDate() + 7);
    due = d;
    title = title.replace(/next week/gi, ' ').trim();
  }

  const time = title.match(/\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/i);
  if (time) {
    let h = Number(time[1]);
    const m = Number(time[2] ?? 0);
    const ap = time[3].toLowerCase();
    if (ap === 'pm' && h < 12) h += 12;
    if (ap === 'am' && h === 12) h = 0;
    const base = due ?? atMidnight(now);
    base.setHours(h, m, 0, 0);
    due = base;
    title = title.replace(time[0], ' ').trim();
  }

  title = title.replace(/\s{2,}/g, ' ').trim();
  return {
    title: title || text,
    tag,
    folder,
    priority,
    due_at: due ? due.toISOString() : null,
  };
}

export function breakdownLocal(title) {
  const t = String(title ?? '').trim() || 'Task';
  const lower = t.toLowerCase();
  if (/report|essay|doc|proposal/.test(lower)) {
    return [
      { title: 'Outline the sections', minutes: 15 },
      { title: 'Draft the core content', minutes: 25 },
      { title: 'Edit + tighten', minutes: 15 },
      { title: 'Proofread + ship', minutes: 10 },
    ];
  }
  if (/clean|tidy|organize|garage|room/.test(lower)) {
    return [
      { title: 'Pick one small zone', minutes: 5 },
      { title: 'Sort into keep / toss', minutes: 20 },
      { title: 'Put away + wipe down', minutes: 15 },
    ];
  }
  return [
    { title: `Clarify done for: ${t.slice(0, 60)}`, minutes: 5 },
    { title: 'Smallest first step', minutes: 15 },
    { title: 'Main work block', minutes: 25 },
    { title: 'Review + close out', minutes: 10 },
  ];
}

export function planLocal(tasks) {
  const list = Array.isArray(tasks) ? tasks : [];
  const now = Date.now();
  const scored = list
    .filter((t) => t && t.status !== 'done')
    .map((t) => {
      let score = 0;
      const reasons = [];
      if (t.due_at) {
        const dt = new Date(t.due_at).getTime();
        if (!Number.isNaN(dt)) {
          if (dt < now) {
            score += 50;
            reasons.push('overdue');
          } else if (dt < now + 24 * 3600 * 1000) {
            score += 30;
            reasons.push('due soon');
          }
        }
      }
      if (t.priority === 'high') {
        score += 20;
        reasons.push('high priority');
      }
      if (t.status === 'in_progress') {
        score += 10;
        reasons.push('already started');
      }
      if (reasons.length === 0) reasons.push('small win');
      return { id: t.id, title: t.title, score, reason: reasons[0], energy: t.energy ?? null };
    })
    .sort((a, b) => b.score - a.score || energyRank(b.energy) - energyRank(a.energy))
    .slice(0, 3)
    .map(({ id, title, reason }) => ({ id, title, reason }));
  return { picks: scored };
}

function energyRank(level) {
  if (level === 'high') return 2;
  if (level === 'low') return 0;
  return 1;
}

// ---------- Provider calls ----------

async function withTimeout(promise, ms = 12000) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('ai timeout')), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

function cleanJson(text) {
  const s = String(text ?? '').trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  if (start >= 0 && end > start) return s.slice(start, end + 1);
  return s;
}

export async function callGemini(system, user) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error('no gemini key');
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=` +
    encodeURIComponent(key);
  const res = await withTimeout(
    fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ parts: [{ text: user }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 512,
          responseMimeType: 'application/json',
        },
      }),
    }),
  );
  if (!res.ok) throw new Error(`gemini ${res.status}`);
  const json = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
  return JSON.parse(cleanJson(text));
}

export async function callGroq(system, user) {
  const key = process.env.GROQ_API_KEY;
  if (!key) throw new Error('no groq key');
  const res = await withTimeout(
    fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        temperature: 0.2,
        max_tokens: 512,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    }),
  );
  if (!res.ok) throw new Error(`groq ${res.status}`);
  const json = await res.json();
  const text = json?.choices?.[0]?.message?.content ?? '';
  return JSON.parse(cleanJson(text));
}

function sanitizeParse(d, fallback) {
  return {
    title: String(d?.title ?? fallback?.title ?? '').trim() || String(fallback?.title ?? ''),
    tag: String(d?.tag ?? fallback?.tag ?? 'General'),
    folder: String(d?.folder ?? fallback?.folder ?? 'Productivity'),
    priority: d?.priority === 'high' ? 'high' : 'none',
    due_at: d?.due_at ?? fallback?.due_at ?? null,
  };
}

function sanitizeBreakdown(d, fallbackSteps) {
  const steps = Array.isArray(d?.steps) ? d.steps : Array.isArray(d) ? d : fallbackSteps;
  return {
    steps: steps
      .filter(Boolean)
      .slice(0, 6)
      .map((s) =>
        typeof s === 'string'
          ? { title: s.slice(0, 120), minutes: 15 }
          : {
              title: String(s.title ?? '').slice(0, 120),
              minutes: Math.min(120, Math.max(5, Number(s.minutes ?? 15))),
            },
      )
      .filter((s) => s.title),
  };
}

function sanitizePlan(d, fallback) {
  const picks = Array.isArray(d?.picks) ? d.picks : [];
  if (!picks.length) return fallback;
  return {
    picks: picks.slice(0, 3).map((p) => ({
      id: String(p.id ?? ''),
      title: String(p.title ?? ''),
      reason: String(p.reason ?? 'suggested').slice(0, 80),
    })),
  };
}

function sanitizeNarrative(d, fallback) {
  const text = String(d?.text ?? '').trim();
  if (!text) return fallback;
  return { text: text.slice(0, 600) };
}

function sanitizeGroom(d, fallback) {
  const groups = Array.isArray(d?.groups) ? d.groups : [];
  if (!groups.length) return fallback;
  return {
    groups: groups
      .slice(0, 6)
      .map((g) => ({
        kind: ['duplicates', 'stale', 'vague'].includes(g?.kind) ? g.kind : 'stale',
        title: String(g?.title ?? '').slice(0, 120),
        ids: (Array.isArray(g?.ids) ? g.ids : []).map((id) => String(id)).slice(0, 20),
        action: ['delete-others', 'defer-week', 'review'].includes(g?.action) ? g.action : 'review',
        note: String(g?.note ?? '').slice(0, 140),
      }))
      .filter((g) => g.title && g.ids.length),
  };
}

function sanitizeAsk(d, fallback) {
  const ids = Array.isArray(d?.ids) ? d.ids.map((id) => String(id)).slice(0, 5) : fallback.ids;
  const answer = String(d?.answer ?? '').trim();
  return { answer: answer ? answer.slice(0, 300) : fallback.answer, ids };
}

export async function aiComplete(kind, payload) {
  const fallbackData =
    kind === 'parse'
      ? parseQuickAddLocal(payload.text)
      : kind === 'breakdown'
        ? { steps: breakdownLocal(payload.title) }
        : kind === 'narrative'
          ? narrativeLocal(payload)
          : kind === 'groom'
            ? groomLocal(payload.tasks)
            : kind === 'ask'
              ? askLocal(payload.question, payload.tasks)
              : planLocal(payload.tasks);

  const system =
    kind === 'parse'
      ? 'Parse a task quick-add line into JSON {title, tag, folder, priority ("none"|"high"), due_at (ISO string or null)}. Strip dates/times/#tags from title. Reply JSON only.'
      : kind === 'breakdown'
        ? 'Break a task into 3-5 concrete subtasks. Reply JSON {steps:[{title, minutes 5-60}]} only.'
        : kind === 'narrative'
          ? 'Write a warm 2-3 sentence weekly review in a calm garden tone from these stats. Specific numbers, one gentle nudge, no guilt. Reply JSON {text} only.'
          : kind === 'groom'
            ? 'Find duplicate titles (kind "duplicates", action "delete-others", ids = all but newest), stale open tasks 30+ days with no due date (kind "stale", action "defer-week"), and vague titles under 12 chars (kind "vague", action "review"). Reply JSON {groups:[{kind, title, ids, action, note}]} only, max 6 groups.'
            : kind === 'ask'
              ? 'Answer the question from the task list. Reply JSON {answer (1-2 sentences), ids (up to 5 matching task ids)} only.'
              : 'Pick the top 3 tasks to do today from the JSON list. Reply JSON {picks:[{id, title, reason max 10 words}]} only. Prefer overdue, due soon, high priority, in-progress.';

  const user =
    kind === 'parse'
      ? `Line: ${JSON.stringify(String(payload.text ?? '').slice(0, 300))}`
      : kind === 'breakdown'
        ? `Task: ${JSON.stringify(String(payload.title ?? '').slice(0, 300))}`
        : kind === 'narrative'
          ? `Tips: ${JSON.stringify(payload.tips ?? []).slice(0, 1500)} Stats: ${JSON.stringify(payload.stats ?? {})}`
          : kind === 'groom'
            ? `Tasks: ${JSON.stringify((payload.tasks ?? []).slice(0, 60))}`.slice(0, 8000)
            : kind === 'ask'
              ? `Q: ${JSON.stringify(String(payload.question ?? '').slice(0, 300))} Tasks: ${JSON.stringify((payload.tasks ?? []).slice(0, 60))}`.slice(0, 8000)
              : `Tasks: ${JSON.stringify((payload.tasks ?? []).slice(0, 30))}`.slice(0, 6000);

  function finalize(data) {
    if (kind === 'parse') return sanitizeParse(data, fallbackData);
    if (kind === 'breakdown') return sanitizeBreakdown(data, fallbackData.steps);
    if (kind === 'narrative') return sanitizeNarrative(data, fallbackData);
    if (kind === 'groom') return sanitizeGroom(data, fallbackData);
    if (kind === 'ask') return sanitizeAsk(data, fallbackData);
    return sanitizePlan(data, fallbackData);
  }

  try {
    const data = await callGemini(system, user);
    return { data: finalize(data), model: GEMINI_MODEL, fallback: false };
  } catch {
    try {
      const data = await callGroq(system, user);
      return { data: finalize(data), model: GROQ_MODEL, fallback: true };
    } catch {
      return { data: fallbackData, model: 'local-heuristic', fallback: true };
    }
  }
}
