-- Migration 002: folders (OBSOLETE — kept for history only).
-- schema.sql already creates the folders table + seeds the same three
-- rows, so migrate.js ORDER intentionally skips this file. Do NOT add
-- it back to ORDER (double-seed is harmless but pointless).
-- Original content below, untouched.
-- Migration 002: folders (run after schema.sql / seed.sql).
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  icon TEXT NOT NULL DEFAULT 'folder',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO folders (name, icon) VALUES
  ('Productivity', 'folder'),
  ('Self Care', 'heart'),
  ('Personal Projects', 'star')
ON CONFLICT (name) DO NOTHING;
