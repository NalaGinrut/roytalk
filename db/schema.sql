-- roytalk database schema (PostgreSQL 14+).
-- Idempotent: safe to run on every deploy with
--   psql -v ON_ERROR_STOP=1 -f db/schema.sql
-- New columns are added with ADD COLUMN IF NOT EXISTS below the table they belong to.

CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------- accounts
-- An account is a handle plus one or more ways to sign in. Nothing else is kept.
CREATE TABLE IF NOT EXISTS accounts (
  id          bigserial PRIMARY KEY,
  handle      citext UNIQUE,            -- NULL until chosen on first sign-in
  is_author   boolean NOT NULL DEFAULT false,
  banned      boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- One row per sign-in method. provider: 'email' | 'github' | 'google' | 'x'.
-- subject is the provider's stable user id (the address itself for 'email').
-- email is only kept when the provider has verified it; it is what lets
-- GitHub, Google and email sign-ins land on the same account.
CREATE TABLE IF NOT EXISTS identities (
  id          bigserial PRIMARY KEY,
  account_id  bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  provider    text   NOT NULL,
  subject     text   NOT NULL,
  email       citext,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, subject)
);
CREATE INDEX IF NOT EXISTS identities_email_idx ON identities (email);
CREATE INDEX IF NOT EXISTS identities_account_idx ON identities (account_id);

-- Browser sessions. Only a SHA-256 of the cookie value is stored.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash  text PRIMARY KEY,
  account_id  bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_account_idx ON sessions (account_id);

-- One-time sign-in links sent by email. Only a SHA-256 of the token is stored.
CREATE TABLE IF NOT EXISTS login_tokens (
  token_hash  text PRIMARY KEY,
  email       citext NOT NULL,
  next_path   text   NOT NULL DEFAULT '/',
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz
);
-- Set when a signed-in person adds an email sign-in from the settings page.
ALTER TABLE login_tokens ADD COLUMN IF NOT EXISTS link_account_id bigint REFERENCES accounts(id) ON DELETE CASCADE;

-- OAuth round trips in flight (state, PKCE verifier, where to go afterwards,
-- and the account to link to when "link another sign-in" was used).
CREATE TABLE IF NOT EXISTS oauth_states (
  state       text PRIMARY KEY,
  provider    text NOT NULL,
  verifier    text NOT NULL,
  next_path   text NOT NULL DEFAULT '/',
  link_account_id bigint REFERENCES accounts(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL
);

-- ---------------------------------------------------------------- writing
CREATE TABLE IF NOT EXISTS posts (
  id            bigserial PRIMARY KEY,
  slug          text UNIQUE NOT NULL,
  title         text NOT NULL,
  dek           text NOT NULL DEFAULT '',     -- the standfirst under the title
  body_md       text NOT NULL DEFAULT '',     -- what the author writes
  body_html     text NOT NULL DEFAULT '',     -- rendered by pandoc at save time
  toc_html      text NOT NULL DEFAULT '',
  source_url    text,                         -- for commentary on an outside piece
  source_title  text,
  submitted_by  bigint REFERENCES accounts(id) ON DELETE SET NULL,
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  published_at  timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  views         bigint NOT NULL DEFAULT 0,
  emailed_at    timestamptz,                  -- when it went out to the letter
  search        tsvector GENERATED ALWAYS AS (
                  setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
                  setweight(to_tsvector('english', coalesce(dek,'')), 'B') ||
                  setweight(to_tsvector('english', coalesce(body_md,'')), 'C')) STORED
);
CREATE INDEX IF NOT EXISTS posts_published_idx ON posts (status, published_at DESC);
CREATE INDEX IF NOT EXISTS posts_search_idx ON posts USING gin (search);

CREATE TABLE IF NOT EXISTS tags (
  id    bigserial PRIMARY KEY,
  name  citext UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS post_tags (
  post_id  bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  tag_id   bigint NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  position int NOT NULL DEFAULT 0,
  PRIMARY KEY (post_id, tag_id)
);

-- ---------------------------------------------------------------- questions
-- A question has parent_id NULL; a reply has parent_id = the question's id.
-- Threads are two levels deep. A reply to a reply stays at the second level
-- and records whom it answers in reply_to.
-- A question may quote the sentence it questions: the quote is stored as text
-- with a little context on each side, so it can be found again after the essay
-- is edited (no character offsets).
CREATE TABLE IF NOT EXISTS questions (
  id            bigserial PRIMARY KEY,
  post_id       bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  account_id    bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  parent_id     bigint REFERENCES questions(id) ON DELETE CASCADE,
  reply_to      bigint REFERENCES accounts(id) ON DELETE SET NULL,
  quote_exact   text,
  quote_prefix  text,
  quote_suffix  text,
  body          text NOT NULL,
  hidden        boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS questions_post_idx ON questions (post_id, created_at);
CREATE INDEX IF NOT EXISTS questions_account_idx ON questions (account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS questions_created_idx ON questions (created_at);

-- A question merged into another question on the same post. Merged rows are
-- not shown on their own; the question they point at lists their askers.
-- ON DELETE SET NULL means deleting a merge target returns its merged
-- questions to the normal list.
ALTER TABLE questions ADD COLUMN IF NOT EXISTS merged_into bigint
  REFERENCES questions(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS questions_merged_idx
  ON questions (merged_into) WHERE merged_into IS NOT NULL;
ALTER TABLE questions DROP CONSTRAINT IF EXISTS questions_not_self_merged;
ALTER TABLE questions ADD CONSTRAINT questions_not_self_merged
  CHECK (merged_into IS NULL OR merged_into <> id);

-- ---------------------------------------------------------------- submissions
-- Links readers send in. The queue is private to the author.
CREATE TABLE IF NOT EXISTS submissions (
  id          bigserial PRIMARY KEY,
  account_id  bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  url         text NOT NULL,
  url_norm    text NOT NULL,          -- for counting duplicates
  note        text NOT NULL,
  status      text NOT NULL DEFAULT 'received' CHECK (status IN ('received','used','dismissed')),
  post_id     bigint REFERENCES posts(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, url_norm)
);
CREATE INDEX IF NOT EXISTS submissions_norm_idx ON submissions (url_norm);
CREATE INDEX IF NOT EXISTS submissions_created_idx ON submissions (created_at);

-- ---------------------------------------------------------------- the letter
-- Newsletter subscribers: a separate list from accounts, no sign-in needed.
CREATE TABLE IF NOT EXISTS subscribers (
  id            bigserial PRIMARY KEY,
  email         citext UNIQUE NOT NULL,
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','unsubscribed')),
  token         text UNIQUE NOT NULL,   -- for confirm and one-click unsubscribe
  created_at    timestamptz NOT NULL DEFAULT now(),
  confirmed_at  timestamptz,
  left_at       timestamptz
);

-- Outgoing mail. The web process only inserts rows; tools/mailer.scm sends them,
-- so no request ever waits on SMTP.
CREATE TABLE IF NOT EXISTS outbox (
  id          bigserial PRIMARY KEY,
  to_addr     text NOT NULL,
  subject     text NOT NULL,
  body_text   text NOT NULL,
  headers     text NOT NULL DEFAULT '',   -- extra RFC 5322 header lines
  created_at  timestamptz NOT NULL DEFAULT now(),
  attempts    int  NOT NULL DEFAULT 0,
  sent_at     timestamptz,
  last_error  text
);
CREATE INDEX IF NOT EXISTS outbox_pending_idx ON outbox (id) WHERE sent_at IS NULL;
-- stream: 'account' (sign-in links, letter confirmation and welcome) or
-- 'letter' (the newsletter). They are sent from different addresses and SES
-- configuration sets, so the newsletter's reputation can't sink sign-in mail.
ALTER TABLE outbox ADD COLUMN IF NOT EXISTS stream text NOT NULL DEFAULT 'account';
ALTER TABLE outbox ADD COLUMN IF NOT EXISTS body_html text;

-- ---------------------------------------------------------------- site
CREATE TABLE IF NOT EXISTS sponsors (
  slot     text PRIMARY KEY CHECK (slot IN ('home','article')),
  name     text NOT NULL DEFAULT '',
  line     text NOT NULL DEFAULT '',
  url      text NOT NULL DEFAULT '',
  active   boolean NOT NULL DEFAULT false
);
INSERT INTO sponsors (slot) VALUES ('home'), ('article') ON CONFLICT DO NOTHING;

-- Tokens for the author's own read-only API. Only a SHA-256 is stored.
CREATE TABLE IF NOT EXISTS api_tokens (
  id            bigserial PRIMARY KEY,
  name          text NOT NULL,
  token_hash    text UNIQUE NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_used_at  timestamptz,
  revoked_at    timestamptz
);
