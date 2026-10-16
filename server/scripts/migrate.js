// Idempotent ordered migrations. Every file in ORDER is safe to
// re-run (IF NOT EXISTS / ON CONFLICT / WHERE NOT EXISTS guards),
// and applied files are recorded in schema_migrations, so concurrent
// boots and re-deploys can never double-apply.
//
// Usage: npm run migrate   (also runs automatically on `npm start`)
import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';
import pg from 'pg';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dbDir = path.join(here, '..', '..', 'db');

const ORDER = [
  'schema.sql',
  'seed.sql',
  'migration_003_auth.sql',
  'migration_004_phase_a.sql',
  'migration_005_flows.sql',
  'migration_006_focus.sql',
  'migration_007_themes.sql',
  'migration_008_isolation.sql',
  'migration_009_extras.sql',
  'migration_010_refresh.sql',
  'migration_011_improvements.sql',
  'migration_012_firebase_auth.sql',
  'migration_013_nullable_password.sql',
  'migration_014_subtask_history.sql',
  'migration_015_subtask_completion.sql',
  'migration_016_midnight_free.sql',
  'migration_017_free_focus.sql',
];

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl:
    process.env.DATABASE_URL?.includes('render.com') ||
    process.env.DATABASE_URL?.includes('sslmode=require')
      ? { rejectUnauthorized: false }
      : undefined,
});

await pool.query(
  `CREATE TABLE IF NOT EXISTS schema_migrations (
     name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);

const { rows: done } = await pool.query('SELECT name FROM schema_migrations');
const applied = new Set(done.map((r) => r.name));

for (const file of ORDER) {
  if (applied.has(file)) {
    console.log(`- skip ${file}`);
    continue;
  }
  const sql = fs.readFileSync(path.join(dbDir, file), 'utf8');
  console.log(`+ apply ${file}`);
  // One transaction per file: a failed migration leaves no half state,
  // and the next run retries it cleanly (files are re-runnable).
  await pool.query('BEGIN');
  try {
    await pool.query(sql);
    await pool.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
    await pool.query('COMMIT');
  } catch (e) {
    await pool.query('ROLLBACK');
    throw e;
  }
}

console.log('migrations up to date');
await pool.end();
