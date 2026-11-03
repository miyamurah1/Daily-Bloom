// AI proxy routes. Moved verbatim from src/index.js (route split).
// No logic changes.
import rateLimit from 'express-rate-limit';
import { aiComplete, checkPersistentCap, localFor } from '../ai.js';

// --- AI proxy: Gemini 2.5 Flash-Lite primary, Groq fallback, local last ---
// Keys stay server-side. Per-user daily cap degrades to local heuristics
// (200 + capped:true) instead of 429 so the app never breaks over quota.
const aiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'too many ai requests — try again in a few minutes' },
});

export function registerAiRoutes(app, { requireAuth, pool }) {
async function aiHandler(kind, req, res) {
  try {
    const taskPayload = (max) => ({
      tasks: Array.isArray(req.body?.tasks) ? req.body.tasks.slice(0, max) : [],
    });
    const payload =
      kind === 'parse'
        ? { text: req.body?.text ?? '' }
        : kind === 'breakdown'
          ? { title: req.body?.title ?? '' }
          : kind === 'narrative'
            ? {
                tips: Array.isArray(req.body?.tips) ? req.body.tips.slice(0, 10) : [],
                stats: req.body?.stats ?? {},
              }
            : kind === 'groom'
              ? taskPayload(60)
              : kind === 'ask'
                ? { question: req.body?.question ?? '', ...taskPayload(60) }
                : taskPayload(30);
    if (kind === 'parse' && !String(payload.text).trim()) {
      return res.status(400).json({ error: 'text is required' });
    }
    if (kind === 'breakdown' && !String(payload.title).trim()) {
      return res.status(400).json({ error: 'title is required' });
    }
    if (kind === 'ask' && !String(payload.question).trim()) {
      return res.status(400).json({ error: 'question is required' });
    }
    const allowed = await checkPersistentCap(pool, req.userId);
    if (!allowed) {
      return res.json({ data: localFor(kind, payload), model: 'local-heuristic', fallback: true, capped: true });
    }
    const result = await aiComplete(kind, payload);
    return res.json({ ...result, capped: false });
  } catch {
    return res.status(500).json({ error: 'ai failed' });
  }
}

app.post('/api/ai/parse', requireAuth, aiLimiter, async (req, res) => {
  await aiHandler('parse', req, res);
});

app.post('/api/ai/breakdown', requireAuth, aiLimiter, async (req, res) => {
  await aiHandler('breakdown', req, res);
});

app.post('/api/ai/plan', requireAuth, aiLimiter, async (req, res) => {
  await aiHandler('plan', req, res);
});

app.post('/api/ai/narrative', requireAuth, aiLimiter, async (req, res) => {
  await aiHandler('narrative', req, res);
});

app.post('/api/ai/groom', requireAuth, aiLimiter, async (req, res) => {
  await aiHandler('groom', req, res);
});

app.post('/api/ai/ask', requireAuth, aiLimiter, async (req, res) => {
  await aiHandler('ask', req, res);
});
}
