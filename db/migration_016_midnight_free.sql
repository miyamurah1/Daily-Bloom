-- Migration 016: Midnight Tokyo becomes a free baseline theme.
--
-- Midnight is the default dark look, so it is granted to everyone
-- exactly like Edo was in 007: new rows default to it being owned,
-- and every existing user gets it backfilled. Prices live in code
-- (server THEMES); the database only tracks ownership.
-- Re-runnable (ON CONFLICT guards).

-- Everyone owns Midnight (it is free, like Edo).
INSERT INTO owned_themes (user_id, theme_id)
SELECT id, 'midnight' FROM users
ON CONFLICT DO NOTHING;

-- New users default to the dark baseline when no theme is chosen.
ALTER TABLE users
  ALTER COLUMN active_theme SET DEFAULT 'edo';
