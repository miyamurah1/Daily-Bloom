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

// Claim the daily ritual reward. The UTC day is used as the idempotency key so
// a retry after a lost response cannot mint the reward twice.
app.post('/api/wallet/daily-ritual', requireAuth, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO user_tokens (user_id, balance) VALUES ($1, 450)
       ON CONFLICT (user_id) DO NOTHING`, [req.userId]);
    const { rows: wallet } = await client.query(
      'SELECT balance FROM user_tokens WHERE user_id = $1 FOR UPDATE', [req.userId]);
    const { rows: day } = await client.query("SELECT CURRENT_DATE::text AS day");
    const key = `daily-ritual:${day[0].day}`;
    const { rows: existing } = await client.query(
      `SELECT delta FROM wallet_transactions
       WHERE user_id = $1 AND idempotency_key = $2`, [req.userId, key]);
    if (existing.length) {
      await client.query('COMMIT');
      return res.json({
        balance: wallet[0].balance,
        awarded: 0,
        alreadyClaimed: true,
      });
    }
    await client.query(
      `UPDATE user_tokens SET balance = balance + 25, updated_at = now()
       WHERE user_id = $1`, [req.userId]);
    await client.query(
      `INSERT INTO wallet_transactions (user_id, idempotency_key, delta, reason)
       VALUES ($1, $2, 25, 'daily_ritual')`, [req.userId, key]);
    const { rows: updated } = await client.query(
      'SELECT balance FROM user_tokens WHERE user_id = $1', [req.userId]);
    await client.query('COMMIT');
    return res.json({ balance: updated[0].balance, awarded: 25, alreadyClaimed: false });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[wallet] daily ritual failed:', e?.code ?? e?.message ?? e);
    return res.status(500).json({ error: 'could not claim daily ritual' });
  } finally {
    client.release();
  }
});

// Spend the fixed price of a habit thaw. The action is deliberately allow
// listed; clients cannot use this endpoint to debit or credit arbitrary sums.
app.post('/api/wallet/spend', requireAuth, async (req, res) => {
  const action = String(req.body?.action ?? '');
  const key = String(req.body?.idempotency_key ?? '').trim().slice(0, 160);
  if (action !== 'habit_unfreeze' || !key) {
    return res.status(400).json({ error: 'invalid wallet action' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO user_tokens (user_id, balance) VALUES ($1, 450)
       ON CONFLICT (user_id) DO NOTHING`, [req.userId]);
    const { rows: wallet } = await client.query(
      'SELECT balance FROM user_tokens WHERE user_id = $1 FOR UPDATE', [req.userId]);
    const { rows: existing } = await client.query(
      `SELECT delta FROM wallet_transactions
       WHERE user_id = $1 AND idempotency_key = $2`, [req.userId, key]);
    if (existing.length) {
      await client.query('COMMIT');
      return res.json({ balance: wallet[0].balance, spent: 0, alreadyApplied: true });
    }
    if (wallet[0].balance < 500) {
      await client.query('ROLLBACK');
      return res.status(402).json({ error: 'not enough tokens to unfreeze this habit' });
    }
    await client.query(
      `UPDATE user_tokens SET balance = balance - 500, updated_at = now()
       WHERE user_id = $1`, [req.userId]);
    await client.query(
      `INSERT INTO wallet_transactions (user_id, idempotency_key, delta, reason)
       VALUES ($1, $2, -500, 'habit_unfreeze')`, [req.userId, key]);
    const { rows: updated } = await client.query(
      'SELECT balance FROM user_tokens WHERE user_id = $1', [req.userId]);
    await client.query('COMMIT');
    return res.json({ balance: updated[0].balance, spent: 500, alreadyApplied: false });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[wallet] spend failed:', e?.code ?? e?.message ?? e);
    return res.status(500).json({ error: 'could not spend wallet tokens' });
  } finally {
    client.release();
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
      active: me.length ? me[0].active_theme : 'edo',
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
      // Lock the wallet before checking ownership. Otherwise two concurrent
      // buy requests can both pass the ownership check and deduct twice.
      await client.query(
        `INSERT INTO user_tokens (user_id, balance) VALUES ($1, 450)
         ON CONFLICT (user_id) DO NOTHING`, [req.userId]);
      const { rows: wallet } = await client.query(
        'SELECT balance FROM user_tokens WHERE user_id = $1 FOR UPDATE',
        [req.userId]);
      const balance = wallet[0].balance;
      // Claim ownership while the wallet row is locked. The unique key makes
      // concurrent taps deterministic: only the request that inserted the
      // ownership row may charge the balance.
      const { rows: inserted } = await client.query(
        `INSERT INTO owned_themes (user_id, theme_id)
         VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING theme_id`,
        [req.userId, id]);
      if (!inserted.length) {
        await client.query('ROLLBACK');
        return res.json({ ok: true, owned: true });
      }
      if (balance < theme.price) {
        await client.query('ROLLBACK');
        return res.status(402).json({ error: 'not enough tokens — complete tasks and flows to earn more' });
      }
      await client.query(
        'UPDATE user_tokens SET balance = balance - $2, updated_at = now() WHERE user_id = $1',
        [req.userId, theme.price]);
      await client.query(
        `INSERT INTO wallet_transactions (user_id, idempotency_key, delta, reason)
         VALUES ($1, $2, $3, 'theme_purchase')`,
        [req.userId, `theme:${id}`, -theme.price]);
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
