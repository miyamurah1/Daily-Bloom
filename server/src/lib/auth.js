// Firebase Auth middleware. Moved verbatim from src/index.js
// (route split) — wrapped in a pool factory. No logic changes.
import { getAuth } from 'firebase-admin/auth';

export const publicUser = (row) => ({
  id: row.id,
  uid: row.firebase_uid ?? row.uid ?? row.id,
  email: row.email,
  display_name: row.display_name ?? '',
  avatar_label: row.avatar_label ?? '禅',
  active_theme: row.active_theme ?? 'edo',
  created_at: row.created_at,
});

/// True when a Postgres error means "the database is unreachable" rather
/// than "the query was wrong". The driver's error code varies by platform
/// (ECONNREFUSED on Linux/macOS, ETIMEDOUT/EAI_AGAIN elsewhere), so the
/// message is inspected as well.
export function isDatabaseOffline(err) {
  if (!err) return false;
  const code = err.code;
  if (code === 'ECONNREFUSED' || code === 'ETIMEDOUT' || code === 'EAI_AGAIN') {
    return true;
  }
  const msg = String(err.message ?? '');
  return (
    msg.includes('ECONNREFUSED') ||
    msg.includes('Connection terminated') ||
    msg.includes('timeout exceeded') ||
    msg.includes('connect ') ||
    msg.includes('getaddrinfo')
  );
}

export function createRequireAuth(pool) {
const testBypass =
  process.env.ENABLE_TEST_BYPASS === '1' && process.env.TEST_BYPASS_TOKEN
    ? process.env.TEST_BYPASS_TOKEN
    : null;

async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, idToken] = header.split(' ');
  if (scheme !== 'Bearer' || !idToken) {
    return res.status(401).json({ error: 'authentication required' });
  }
  if (testBypass && idToken.startsWith(testBypass + ':')) {
    const testEmail = idToken
      .slice(testBypass.length + 1)
      .toLowerCase()
      .trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(testEmail)) {
      return res.status(401).json({ error: 'authentication required' });
    }
    try {
      const uid = 'test:' + testEmail;
      let rows = (
        await pool.query('SELECT id FROM users WHERE firebase_uid = $1', [uid])
      ).rows;
      if (!rows.length) {
        try {
          const created = (
            await pool.query(
              `INSERT INTO users (firebase_uid, email, display_name)
               VALUES ($1, $2, $3) RETURNING id`,
              [uid, testEmail, testEmail.split('@')[0]],
            )
          ).rows;
          rows = created;
        } catch (e) {
          // Concurrent first-request race: re-read the winner's row.
          if (e?.code !== '23505') throw e;
          rows = (
            await pool.query('SELECT id FROM users WHERE firebase_uid = $1', [
              uid,
            ])
          ).rows;
          if (!rows.length) throw e;
        }
        if (rows.length) {
          const newId = rows[0].id;
          // Seeds are idempotent: a raced retry never double-seeds.
          await pool.query(
            'INSERT INTO user_tokens (user_id, balance) VALUES ($1, 450) ON CONFLICT (user_id) DO NOTHING',
            [newId],
          );
          await pool.query(
            'INSERT INTO owned_themes (user_id, theme_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
            [newId, 'edo'],
          );
          await pool.query(
            'INSERT INTO owned_themes (user_id, theme_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
            [newId, 'midnight'],
          );
          await pool.query(
            `INSERT INTO rules (user_id, name, trigger, condition, actions)
             SELECT $1, 'Done → +10 tokens', 'task_done', '{}', $2
             WHERE NOT EXISTS (SELECT 1 FROM rules WHERE user_id = $1 AND name = 'Done → +10 tokens')`,
            [newId, JSON.stringify([{ type: 'award_tokens', amount: 10 }])],
          );
        }
      }
      req.userId = rows[0].id;
      req.firebaseUid = uid;
      return next();
    } catch (e) {
      console.error('[auth] test bypass failed:', e?.code ?? e);
      return res.status(500).json({ error: 'test sign-in failed' });
    }
  }
  try {
    const decoded = await getAuth().verifyIdToken(idToken);
    req.firebaseUid = decoded.uid;
    // Look up the DB user row by firebase_uid.
    let rows;
    try {
      ({ rows } = await pool.query(
        'SELECT id FROM users WHERE firebase_uid = $1',
        [decoded.uid],
      ));
    } catch (dbErr) {
      // The database is unreachable. Every scoped query keys on
      // `user_id UUID`, so there is no honest fallback id to hand the
      // route layer — a Firebase UID is not a UUID and Postgres would
      // reject it. Report "unavailable" instead: the app falls back to
      // its local cache and stays truthful about being offline.
      if (isDatabaseOffline(dbErr)) {
        console.warn('[auth] database offline - serving 503');
        return res.status(503).json({ error: 'database unavailable' });
      }
      throw dbErr;
    }
    if (!rows.length) {
      return res.status(401).json({ error: 'account not found — please sign in again' });
    }
    req.userId = rows[0].id;
    next();
  } catch (e) {
    console.error('[auth] token verification failed:', e?.code ?? e?.message);
    return res.status(401).json({ error: 'session expired — please log in again' });
  }
}
  return requireAuth;
}