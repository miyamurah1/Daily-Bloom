// Wallet, inbox, theme store. Moved verbatim from src/index.js.

export function registerStoreRoutes(app, { pool, requireAuth, THEMES }) {
app.get('/api/wallet', requireAuth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT balance FROM user_tokens WHERE user_id = $1', [req.userId]);
    res.json({ balance: rows.length ? rows[0].balance : 450 });
  } catch {
    res.status(500).json({ error: 'could not load wallet' });
  }
});

app.get('/api/inbox', requireAuth, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit ?? '50', 10) || 50, 200);
    const { rows } = await pool.query(
      'SELECT * FROM inbox_messages WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2',
      [req.userId, limit]);
    res.json(rows);
  } catch {
    res.status(500).json({ error: 'could not load inbox' });
  }
});

app.patch('/api/inbox/:id', requireAuth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `UPDATE inbox_messages SET unread = COALESCE($3, unread)
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [req.params.id, req.userId, req.body?.unread ?? null],
    );
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    res.json(rows[0]);
  } catch {
    res.status(500).json({ error: 'could not update message' });
  }
});
app.get('/api/store', requireAuth, async (req, res) => {
  try {
    const { rows: owned } = await pool.query(
      'SELECT theme_id FROM owned_themes WHERE user_id = $1', [req.userId]);
    const have = new Set(owned.map((r) => r.theme_id));
    const { rows: me } = await pool.query(
      'SELECT active_theme FROM users WHERE id = $1', [req.userId]);
    const { rows: wallet } = await pool.query(
      'SELECT balance FROM user_tokens WHERE user_id = $1', [req.userId]);
    res.json({
      balance: wallet.length ? wallet[0].balance : 450,
      active: me.length ? me[0].active_theme : 'midnight',
      themes: Object.values(THEMES).map((t) => ({
        ...t,
        owned: have.has(t.id),
      })),
    });
  } catch {
    res.status(500).json({ error: 'could not load store' });
  }
});

// Buy: atomic deduct + grant. Idempotent — owning it returns ok.
app.post('/api/store/buy', requireAuth, async (req, res) => {
  try {
    const id = String(req.body?.theme_id ?? '');
    const theme = THEMES[id];
    if (!theme) return res.status(400).json({ error: 'unknown theme' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const { rows: owned } = await client.query(
        'SELECT 1 FROM owned_themes WHERE user_id = $1 AND theme_id = $2',
        [req.userId, id]);
      if (owned.length) {
        await client.query('ROLLBACK');
        return res.json({ ok: true, owned: true });
      }
      const { rows: wallet } = await client.query(
        'SELECT balance FROM user_tokens WHERE user_id = $1 FOR UPDATE',
        [req.userId]);
      const balance = wallet.length ? wallet[0].balance : 450;
      if (balance < theme.price) {
        await client.query('ROLLBACK');
        return res.status(402).json({ error: 'not enough tokens — complete tasks and flows to earn more' });
      }
      if (!wallet.length) {
        await client.query(
          'INSERT INTO user_tokens (user_id, balance) VALUES ($1, $2)',
          [req.userId, 450 - theme.price]);
      } else {
        await client.query(
          'UPDATE user_tokens SET balance = balance - $2, updated_at = now() WHERE user_id = $1',
          [req.userId, theme.price]);
      }
      await client.query(
        'INSERT INTO owned_themes (user_id, theme_id) VALUES ($1, $2)',
        [req.userId, id]);
      await client.query('COMMIT');
      res.status(201).json({ ok: true });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch {
    res.status(500).json({ error: 'could not buy theme' });
  }
});

// Equip: must own it.
app.post('/api/store/equip', requireAuth, async (req, res) => {
  try {
    const id = String(req.body?.theme_id ?? '');
    if (!THEMES[id]) return res.status(400).json({ error: 'unknown theme' });
    const { rows: owned } = await pool.query(
      'SELECT 1 FROM owned_themes WHERE user_id = $1 AND theme_id = $2',
      [req.userId, id]);
    if (!owned.length) return res.status(403).json({ error: 'buy it first' });
    await pool.query('UPDATE users SET active_theme = $2 WHERE id = $1',
      [req.userId, id]);
    res.json({ ok: true, active: id });
  } catch {
    res.status(500).json({ error: 'could not equip theme' });
  }
});

// --- Batch: delete, search, export ---

}