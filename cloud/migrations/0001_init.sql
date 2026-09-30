-- Users are keyed by their Sign in with Apple subject. No email or name is stored.
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT UNIQUE,
  created_at INTEGER NOT NULL
);

-- Opaque bearer tokens. Only the SHA-256 hash is stored.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL CHECK (kind IN ('access', 'refresh')),
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE INDEX sessions_user ON sessions(user_id);

-- Append-only credit ledger, in micro-dollars (1 USD = 1,000,000).
-- Balance = SUM(amount_micros). Rows are never updated or deleted.
--   grant   starter credit (+)
--   topup   paid top-up (+), unused while payments are off
--   reserve pre-authorization before a model call (-maxCostPerRun)
--   settle  release of the unused part of a reservation (+, reserved - charged)
CREATE TABLE ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL CHECK (kind IN ('grant', 'topup', 'reserve', 'settle')),
  amount_micros INTEGER NOT NULL,
  request_id TEXT,
  external_ref TEXT,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX ledger_request_kind ON ledger(request_id, kind) WHERE request_id IS NOT NULL;
CREATE UNIQUE INDEX ledger_external_ref ON ledger(external_ref) WHERE external_ref IS NOT NULL;
CREATE INDEX ledger_user_time ON ledger(user_id, created_at);

-- Metadata for each /v1/generate call. Never prompt or response content.
CREATE TABLE requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  skill_id TEXT NOT NULL,
  tier TEXT NOT NULL,
  model TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'ok', 'error', 'cancelled', 'rejected')),
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  cost_micros INTEGER,
  charged_micros INTEGER,
  latency_ms INTEGER,
  error_code TEXT,
  created_at INTEGER NOT NULL,
  finished_at INTEGER
);
CREATE INDEX requests_user_time ON requests(user_id, created_at);
