// Tasks, subtasks, notes, timeline, search, export, reorder.
import { publicUser } from '../lib/auth.js';

export function registerTaskRoutes(app, { pool, requireAuth, logEvent, runRules }) {
// --- Existing app routes (now require a valid Bearer token) ---

// Kanban tasks (filterable by status and/or folder)
app.get('/api/tasks', requireAuth, async (req, res) => {
  try {
    const { status, folder } = req.query;
    const conds = ['user_id = $1'];
    const vals = [req.userId];
    if (status) { vals.push(status); conds.push(`status = $${vals.length}`); }
    if (folder) { vals.push(folder); conds.push(`folder = $${vals.length}`); }
    const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
    const { rows } = await pool.query(
      `SELECT * FROM tasks ${where} ORDER BY created_at`, vals);
    // Optional embed for the sketch-style card (main task + subtasks
    // below + timer beside): one round trip, no N+1 per card.
    const include = String(req.query.include || '');
    if (include && rows.length) {
      const ids = rows.map((t) => t.id);
      const wantSubs = include.includes('subtasks');
      const wantFocus = include.includes('focus');
      const [subs, focus] = await Promise.all([
        wantSubs
          ? pool.query(
              `SELECT * FROM subtasks WHERE task_id = ANY($1)
               ORDER BY position, created_at`,
              [ids])
          : Promise.resolve({ rows: [] }),
        wantFocus
          ? pool.query(
              `SELECT task_id,
                      COALESCE(SUM(actual_minutes),0)::int AS minutes
               FROM focus_sessions
               WHERE task_id = ANY($1) GROUP BY task_id`,
              [ids])
          : Promise.resolve({ rows: [] }),
      ]);
      const focusById = new Map(
        focus.rows.map((f) => [f.task_id, f.minutes]));
      for (const t of rows) {
        if (wantSubs) {
          t.subtasks = subs.rows.filter((s) => s.task_id === t.id);
        }
        if (wantFocus) {
          t.focus_minutes = focusById.get(t.id) ?? 0;
        }
      }
    }
    res.json(rows);
  } catch {
    res.status(500).json({ error: 'could not load tasks' });
  }
});

app.post('/api/tasks', requireAuth, async (req, res) => {
  try {
    const {
      title,
      tag = 'General',
      status = 'todo',
      folder = 'Productivity',
      avatar_label = '禅',
      description = '',
      priority = 'none',
      recurring = 'none',
      position = 0,
    } = req.body;
    if (!title || !String(title).trim()) return res.status(400).json({ error: 'title required' });
    const cleanTitle = String(title).trim().slice(0, 500);
    const cleanTag = String(tag).trim().slice(0, 60) || 'General';
    const cleanFolder = String(folder).trim().slice(0, 80) || 'Productivity';
    const cleanDesc = String(description ?? '').trim().slice(0, 5000);
    const cleanPriority = ['none', 'low', 'medium', 'high'].includes(priority) ? priority : 'none';
    const cleanRecurring = ['none', 'daily', 'weekdays', 'weekly', 'monthly'].includes(recurring) ? recurring : 'none';

    // Auto-create folder if it doesn't exist for user
    await pool.query(
      'INSERT INTO folders (name, icon, user_id) VALUES ($1, $2, $3) ON CONFLICT (user_id, name) DO NOTHING',
      [cleanFolder, 'folder', req.userId]
    );

    const clientId = typeof req.body?.client_id === 'string'
      ? req.body.client_id.slice(0, 64)
      : null;
    if (clientId) {
      const { rows: dup } = await pool.query(
        'SELECT * FROM tasks WHERE client_id = $1', [clientId]);
      if (dup.length) {
        if (dup[0].user_id !== req.userId) {
          return res.status(409).json({ error: 'duplicate request' });
        }
        return res.status(200).json(dup[0]);
      }
    }
    const hasDue = req.body && Object.prototype.hasOwnProperty.call(req.body, 'due_at');
    const due = hasDue && req.body.due_at ? req.body.due_at : null;

    const { rows } = await pool.query(
      `INSERT INTO tasks (title, tag, status, folder, avatar_label, description, priority, recurring, position, due_at, user_id, client_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`,
      [cleanTitle, cleanTag, status, cleanFolder, avatar_label, cleanDesc, cleanPriority, cleanRecurring, position, due, req.userId, clientId],
    ).catch(async (e) => {
      // Double-submit race: both requests passed the client_id dup-check
      // above, the loser hits the unique constraint — return the
      // winner's row instead of a misleading 500.
      if (e?.code !== '23505' || !clientId) throw e;
      const { rows: raced } = await pool.query(
        'SELECT * FROM tasks WHERE client_id = $1', [clientId]);
      if (!raced.length || raced[0].user_id !== req.userId) throw e;
      return { rows: raced };
    });
    await logEvent(pool, rows[0].id, req.userId, 'created', { to: rows[0].status });
    await runRules(pool, 'task_created', rows[0], req.userId);
    res.status(201).json(rows[0]);
  } catch (e) {
    console.error('[tasks] create failed:', e);
    res.status(500).json({ error: 'could not create task' });
  }
});

app.patch('/api/tasks/:id', requireAuth, async (req, res) => {
  try {
    const { status, title, tag, description, priority, folder, recurring, position } = req.body ?? {};
    const hasDue = req.body && Object.prototype.hasOwnProperty.call(req.body, 'due_at');
    const due = hasDue ? (req.body.due_at || null) : null;
    const clearDue = hasDue && req.body.due_at == null;

    const { rows: old } = await pool.query(
      'SELECT * FROM tasks WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    if (!old.length) return res.status(404).json({ error: 'not found' });
    const before = old[0];

    // If folder changed, ensure new folder exists
    if (folder && folder !== before.folder) {
      await pool.query(
        'INSERT INTO folders (name, icon, user_id) VALUES ($1, $2, $3) ON CONFLICT (user_id, name) DO NOTHING',
        [folder, 'folder', req.userId]
      );
    }

    const { rows } = await pool.query(
      `UPDATE tasks SET
         status = COALESCE($2, status),
         title = COALESCE($3, title),
         tag = COALESCE($4, tag),
         description = COALESCE($5, description),
         priority = COALESCE($6, priority),
         folder = COALESCE($7, folder),
         recurring = COALESCE($8, recurring),
         position = COALESCE($9, position),
         due_at = CASE WHEN $10 THEN NULL WHEN $11::timestamptz IS NULL THEN due_at ELSE $11::timestamptz END
       WHERE id = $1 AND user_id = $12 RETURNING *`,
      [
        req.params.id,
        status ?? null,
        title ? String(title).trim().slice(0, 500) : null,
        tag ? String(tag).trim().slice(0, 60) : null,
        description !== undefined ? String(description).slice(0, 5000) : null,
        priority ?? null,
        folder ? String(folder).trim().slice(0, 80) : null,
        recurring ?? null,
        typeof position === 'number' ? position : null,
        clearDue,
        due,
        req.userId,
      ],
    );
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    const after = rows[0];
    if (after.status !== before.status) {
      await logEvent(pool, after.id, req.userId, 'status', { from: before.status, to: after.status });
      await runRules(pool, 'task_moved', after, req.userId);
      if (after.status === 'done') {
        await runRules(pool, 'task_done', after, req.userId);
        if (after.recurring && after.recurring !== 'none') {
          let nextDue = null;
          const base = after.due_at ? new Date(after.due_at) : new Date();
          if (after.recurring === 'daily') {
            nextDue = new Date(base.getTime() + 24 * 60 * 60 * 1000);
          } else if (after.recurring === 'weekdays') {
            const day = base.getDay();
            const addDays = (day === 5) ? 3 : (day === 6) ? 2 : 1;
            nextDue = new Date(base.getTime() + addDays * 24 * 60 * 60 * 1000);
          } else if (after.recurring === 'weekly') {
            nextDue = new Date(base.getTime() + 7 * 24 * 60 * 60 * 1000);
          } else if (after.recurring === 'monthly') {
            nextDue = new Date(base);
            nextDue.setMonth(nextDue.getMonth() + 1);
          }
          if (nextDue) {
            await pool.query(
              `INSERT INTO tasks (title, tag, status, folder, avatar_label, description, priority, recurring, due_at, user_id)
               VALUES ($1, $2, 'todo', $3, $4, $5, $6, $7, $8, $9)`,
              [after.title, after.tag, after.folder, after.avatar_label, after.description, after.priority, after.recurring, nextDue, req.userId]
            );
          }
        }
      }
    }
    if (after.title !== before.title) {
      await logEvent(pool, after.id, req.userId, 'renamed', { body: after.title });
    }
    if (after.folder !== before.folder) {
      await logEvent(pool, after.id, req.userId, 'folder', { body: `${before.folder} → ${after.folder}` });
    }
    res.json(rows[0]);
  } catch (e) {
    console.error('[tasks] patch failed:', e);
    res.status(500).json({ error: 'could not update task' });
  }
});

// Phase A — history ("flow") + subtasks.

// Per-task timeline, oldest first. 404 unless the task is yours.
app.get('/api/tasks/:id/events', requireAuth, async (req, res) => {
  try {
    const { rows: own } = await pool.query(
      'SELECT id FROM tasks WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    if (!own.length) return res.status(404).json({ error: 'not found' });
    const { rows } = await pool.query(
      `SELECT * FROM task_events WHERE task_id = $1 ORDER BY created_at`, [req.params.id]);
    res.json(rows);
  } catch {
    res.status(500).json({ error: 'could not load history' });
  }
});
app.post('/api/tasks/:id/notes', requireAuth, async (req, res) => {
  try {
    const body = String(req.body?.body ?? '').trim().slice(0, 1000);
    if (!body) return res.status(400).json({ error: 'write the note first' });
    const { rows: task } = await pool.query(
      'SELECT * FROM tasks WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    if (!task.length) return res.status(404).json({ error: 'task not found' });
    const { rows } = await pool.query(
      `INSERT INTO task_events (task_id, user_id, kind, body)
       VALUES ($1, $2, 'note', $3) RETURNING *`,
      [req.params.id, req.userId, body],
    );
    await runRules(pool, 'note_added', task[0], req.userId);
    res.status(201).json(rows[0]);
  } catch {
    res.status(500).json({ error: 'could not save note' });
  }
});

// Subtasks (single-level checklist under a parent task).
app.get('/api/tasks/:id/subtasks', requireAuth, async (req, res) => {
  try {
    const { rows: own } = await pool.query(
      'SELECT id FROM tasks WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    if (!own.length) return res.status(404).json({ error: 'not found' });
    const { rows } = await pool.query(
      `SELECT * FROM subtasks WHERE task_id = $1 ORDER BY position, created_at`, [req.params.id]);
    res.json(rows);
  } catch {
    res.status(500).json({ error: 'could not load subtasks' });
  }
});

app.post('/api/tasks/:id/subtasks', requireAuth, async (req, res) => {
  try {
    const title = String(req.body?.title ?? '').trim().slice(0, 200);
    if (!title) return res.status(400).json({ error: 'title required' });
    const { rows: task } = await pool.query(
      'SELECT id FROM tasks WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    if (!task.length) return res.status(404).json({ error: 'task not found' });
    const { rows: pos } = await pool.query(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM subtasks WHERE task_id = $1', [req.params.id]);
    const { rows } = await pool.query(
      `INSERT INTO subtasks (task_id, title, position)
       VALUES ($1, $2, $3) RETURNING *`,
      [req.params.id, title, pos[0].next],
    );
    res.status(201).json(rows[0]);
  } catch {
    res.status(500).json({ error: 'could not add subtask' });
  }
});

app.patch('/api/subtasks/:id', requireAuth, async (req, res) => {
  try {
    const { title, done, position } = req.body ?? {};
    // Completion is final: read first so a done subtask can never be
    // unchecked (015). The UI confirms before checking; this guards
    // every client, including stale ones and raw API calls.
    const { rows: existing } = await pool.query(
      `SELECT s.* FROM subtasks s JOIN tasks t ON s.task_id = t.id
       WHERE s.id = $1 AND t.user_id = $2`,
      [req.params.id, req.userId],
    );
    if (!existing.length) return res.status(404).json({ error: 'not found' });
    if (done === false && existing[0].completed_at) {
      return res.status(409).json({ error: 'Subtask already done — completion is final.' });
    }
    const { rows } = await pool.query(
      `UPDATE subtasks s SET
         title = COALESCE($2, s.title),
         done = COALESCE($3, s.done),
         position = COALESCE($4, s.position),
         completed_at = CASE
           WHEN $3 = TRUE THEN COALESCE(s.completed_at, now())
           ELSE s.completed_at
         END
       FROM tasks t
       WHERE s.id = $1 AND s.task_id = t.id AND t.user_id = $5
       RETURNING s.*`,
      [req.params.id, title ?? null, done ?? null, position ?? null, req.userId],
    );
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    // Subtask ticks are history too (History screen, timelines, activity).
    if (typeof done === 'boolean') {
      await logEvent(pool, rows[0].task_id, req.userId, 'subtask', {
        to: done ? 'done' : 'todo',
        body: rows[0].title,
      });
    }
    // A completed subtask that finishes the whole checklist fires the flow.
    if (rows[0].done) {
      const { rows: open } = await pool.query(
        'SELECT id FROM subtasks WHERE task_id = $1 AND NOT done', [rows[0].task_id]);
      if (!open.length) {
        const { rows: parent } = await pool.query(
          'SELECT * FROM tasks WHERE id = $1', [rows[0].task_id]);
        if (parent.length) {
          await runRules(pool, 'subtasks_complete', parent[0], req.userId);
        }
      }
    }
    res.json(rows[0]);
  } catch (e) {
    console.error('[subtasks] patch failed:', e);
    res.status(500).json({ error: 'could not update subtask' });
  }
});

app.delete('/api/subtasks/:id', requireAuth, async (req, res) => {
  try {
    const { rowCount } = await pool.query(
      `DELETE FROM subtasks s USING tasks t
       WHERE s.id = $1 AND s.task_id = t.id AND t.user_id = $2`,
      [req.params.id, req.userId]);
    if (!rowCount) return res.status(404).json({ error: 'not found' });
    res.status(204).end();
  } catch {
    res.status(500).json({ error: 'could not delete subtask' });
  }
});
app.delete('/api/tasks/:id', requireAuth, async (req, res) => {
  try {
    const { rowCount } = await pool.query(
      'DELETE FROM tasks WHERE id = $1 AND user_id = $2', [req.params.id, req.userId]);
    if (!rowCount) return res.status(404).json({ error: 'not found' });
    res.status(204).end();
  } catch {
    res.status(500).json({ error: 'could not delete task' });
  }
});
// Batch reorder tasks
app.patch('/api/tasks-reorder', requireAuth, async (req, res) => {
  try {
    const { items } = req.body ?? {};
    if (Array.isArray(items)) {
      for (const item of items) {
        if (item.id && typeof item.position === 'number') {
          await pool.query(
            'UPDATE tasks SET position = $1 WHERE id = $2 AND user_id = $3',
            [item.position, item.id, req.userId]
          );
        }
      }
    }
    res.json({ ok: true });
  } catch {
    res.status(500).json({ error: 'could not reorder tasks' });
  }
});

app.get('/api/tasks/search', requireAuth, async (req, res) => {
  try {
    const q = String(req.query.q ?? '').trim();
    if (q.length < 2) {
      return res.status(400).json({ error: 'type at least 2 letters' });
    }
    const { rows } = await pool.query(
      `SELECT * FROM tasks
       WHERE user_id = $1 AND (title ILIKE $2 OR tag ILIKE $2 OR description ILIKE $2)
       ORDER BY created_at DESC LIMIT 30`,
      [req.userId, `%${q}%`]);
    res.json(rows);
  } catch {
    res.status(500).json({ error: 'could not search' });
  }
});

// Full account dump (the privacy policy promises export on request).
app.get('/api/export', requireAuth, async (req, res) => {
  try {
    const u = req.userId;
    const [me, tasks, folders, rules, inbox, wallet, focus] = await Promise.all([
      pool.query('SELECT * FROM users WHERE id = $1', [u]),
      pool.query('SELECT * FROM tasks WHERE user_id = $1 ORDER BY created_at', [u]),
      pool.query('SELECT * FROM folders WHERE user_id = $1 ORDER BY created_at', [u]),
      pool.query('SELECT * FROM rules WHERE user_id = $1 ORDER BY created_at', [u]),
      pool.query('SELECT * FROM inbox_messages WHERE user_id = $1 ORDER BY created_at', [u]),
      pool.query('SELECT balance FROM user_tokens WHERE user_id = $1', [u]),
      pool.query('SELECT * FROM focus_sessions WHERE user_id = $1 ORDER BY started_at', [u]),
    ]);
    const ids = tasks.rows.map((t) => t.id);
    const [subs, events] = ids.length
      ? await Promise.all([
          pool.query('SELECT * FROM subtasks WHERE task_id = ANY($1) ORDER BY position', [ids]),
          pool.query('SELECT * FROM task_events WHERE task_id = ANY($1) ORDER BY created_at', [ids]),
        ])
      : [{ rows: [] }, { rows: [] }];
    res.json({
      exported_at: new Date().toISOString(),
      user: me.rows.length ? publicUser(me.rows[0]) : null,
      wallet: wallet.rows.length ? wallet.rows[0].balance : 450,
      folders: folders.rows,
      tasks: tasks.rows.map((t) => ({
        ...t,
        subtasks: subs.rows.filter((s) => s.task_id === t.id),
        events: events.rows.filter((e) => e.task_id === t.id),
      })),
      rules: rules.rows,
      inbox: inbox.rows,
      focus_sessions: focus.rows,
    });
  } catch (err) {
    res.status(500).json({ error: 'could not export data' });
  }
});
}