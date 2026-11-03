-- Migration 019: persistent per-user AI usage caps.
-- In-memory counters reset on deploy and do not work across multiple API
-- instances, so usage is kept per user and UTC day in Postgres.

CREATE TABLE IF NOT EXISTS ai_usage (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  calls INT NOT NULL DEFAULT 0 CHECK (calls >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day)
);
