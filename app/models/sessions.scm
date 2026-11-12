;;  roytalk -- sessions model. Only the SHA-256 of the cookie value is stored.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 sessions
 (:deps accounts)
 (token_hash text (#:primary-key))
 (account_id bigint (#:not-null))
 (created_at timestamptz (#:not-null))
 (expires_at timestamptz (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

(define-public (account-for-session x token-hash)
  "The signed-in account as an alist, or #f."
  (q1 x "SELECT a.id, a.handle::text AS handle, a.is_author, a.banned
           FROM sessions s JOIN accounts a ON a.id = s.account_id
          WHERE s.token_hash = $1 AND s.expires_at > now()" token-hash))

(define-public (create-session! x token-hash account-id days)
  (q! x "INSERT INTO sessions (token_hash, account_id, expires_at)
         VALUES ($1, $2::bigint, now() + make_interval(days => $3::int))"
      token-hash account-id days)
  ;; Opportunistic clean-up; cheap with the primary key.
  (delete-expired-sessions! x))

(define-public (delete-session! x token-hash)
  (q! x "DELETE FROM sessions WHERE token_hash = $1" token-hash))

(define-public (delete-expired-sessions! x)
  (q! x "DELETE FROM sessions WHERE expires_at < now()"))

(define-public (delete-sessions-for-account! x account-id)
  (q! x "DELETE FROM sessions WHERE account_id = $1::bigint" account-id))
