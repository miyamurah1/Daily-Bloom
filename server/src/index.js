import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import pg from 'pg';
import rateLimit from 'express-rate-limit';
import { initializeApp, cert, applicationDefault } from 'firebase-admin/app';
import { publicUser, createRequireAuth } from './lib/auth.js';
import { logEvent, runRules, validRuleBody, THEMES } from './lib/engine.js';
import { levelFor, streakStats } from './lib/stats.js';
import { registerAuthRoutes } from './routes/auth.js';
import { registerTaskRoutes } from './routes/tasks.js';
import { registerRuleRoutes } from './routes/rules.js';
import { registerStoreRoutes } from './routes/store.js';
import { registerFocusRoutes } from './routes/focus.js';
import { registerInsightRoutes } from './routes/insights.js';
import { registerFolderRoutes } from './routes/folders.js';
import { registerAiRoutes } from './routes/ai.js';

// ── Firebase Admin initialisation (modular SDK — no default-import
// interop quirks) ─────────────────────────────────────────────────────────
// Credential sources, in order:
//  1. FIREBASE_SERVICE_ACCOUNT — the JSON itself (Render/Railway secrets).
//  2. GOOGLE_APPLICATION_CREDENTIALS — path to the service-account file
//     (local .env: ./firebase-service-account.json).
//  3. Application Default Credentials (Google Cloud / Cloud Run).
// Without one of these, verifyIdToken() rejects every token and the app
// sits in offline mode with firebase-sync 401s — Firebase login itself
// still succeeds, which is exactly the confusing split in the web log.
let firebaseReady = false;
let firebaseCredentialSource = 'application-default';
try {
  const saJson = process.env.FIREBASE_SERVICE_ACCOUNT;
  const saPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  let credential = null;
  if (saJson) {
    credential = cert(JSON.parse(saJson));
    firebaseCredentialSource = 'env-json';
  } else if (saPath) {
    const { readFileSync } = await import('node:fs');
    const { resolve, isAbsolute, dirname } = await import('node:path');
    const { fileURLToPath } = await import('node:url');
    const here = dirname(fileURLToPath(import.meta.url));
    const abs = isAbsolute(saPath) ? saPath : resolve(here, '..', saPath);
    credential = cert(JSON.parse(readFileSync(abs, 'utf8')));
    firebaseCredentialSource = 'file:' + abs;
  } else {
    credential = applicationDefault();
  }
  initializeApp({ credential });
  firebaseReady = true;
  console.log(
    '[firebase] Admin SDK initialised via ' + firebaseCredentialSource,
  );
} catch (e) {
  console.error('[firebase] Admin SDK init failed — auth will not work:', e?.message ?? e);
}

const { Pool } = pg;
// Render/Railway Postgres needs TLS (self-signed is fine — the wire is
// still encrypted). Local docker has no TLS. `sslmode=require` in the URL
// also works; this keeps both paths green without env juggling.
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl:
    process.env.DATABASE_URL?.includes('render.com') ||
    process.env.DATABASE_URL?.includes('sslmode=require')
      ? { rejectUnauthorized: false }
      : undefined,
});


const app = express();
// Web origins are allow-listed via CORS_ORIGIN (comma-separated). Native
// apps, curl, and Postman send no Origin and always pass; browsers pass
// only for listed origins in production. Outside production everything
// passes so local dev (emulators, web, curl) never trips the policy.
const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map((s) => s.trim())
  : ['http://localhost:3000', 'http://localhost:8080', 'http://127.0.0.1:8080'];
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, postman)
    if (!origin || allowedOrigins.includes(origin) || process.env.NODE_ENV !== 'production') {
      return callback(null, true);
    }
    return callback(new Error('Blocked by CORS policy'));
  },
  credentials: true,
}));

// Request body parsing (required for POST/PATCH route handlers)
app.use(express.json());
app.use(express.urlencoded({ extended: true }));


// Optional crash reporting (Sentry). No SENTRY_DSN = zero behavior
// change: nothing is imported, nothing leaves the server.
if (process.env.SENTRY_DSN) {
  try {
    const Sentry = await import('@sentry/node');
    Sentry.init({ dsn: process.env.SENTRY_DSN, tracesSampleRate: 0.1 });
    console.log('[sentry] crash reporting enabled');
  } catch (e) {
    console.error('[sentry] init failed:', e?.message ?? e);
  }
}

// JWT_SECRET is no longer used — Firebase ID tokens are the auth mechanism.
// bcrypt is no longer needed either (Firebase manages passwords).

// Launch hardening: slow down password guessing. 30 tries per 15 min
// per IP on the two credential endpoints; honest users never notice.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'too many attempts — try again in a few minutes' },
});

// Flood guard for every write endpoint (rules/notes/subtasks/focus
// could otherwise be script-spammed). Reads stay unlimited.
const writeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'too many writes — slow down a little' },
});
app.use((req, res, next) => {
  if (req.method === 'POST' || req.method === 'PATCH' || req.method === 'DELETE') {
    return writeLimiter(req, res, next);
  }
  next();
});

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({
      ok: true,
      firebaseReady,
      firebaseCredentialSource,
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e) });
  }
});

// --- Route modules (split from the 1,533-line monolith; same behavior) ---
const requireAuth = createRequireAuth(pool);
registerAuthRoutes(app, { pool, requireAuth, publicUser, authLimiter });
registerTaskRoutes(app, { pool, requireAuth, logEvent, runRules });
registerRuleRoutes(app, { pool, requireAuth, validRuleBody });
registerStoreRoutes(app, { pool, requireAuth, THEMES });
registerFocusRoutes(app, { pool, requireAuth, logEvent, runRules });
registerInsightRoutes(app, { pool, requireAuth, levelFor, streakStats });
registerFolderRoutes(app, { pool, requireAuth });
registerAiRoutes(app, { requireAuth });


const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`daily-bloom-api on :${port}`));
