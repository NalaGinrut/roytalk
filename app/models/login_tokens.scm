;;  roytalk -- one-time email sign-in tokens. Only a SHA-256 is stored.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 login_tokens
 (:deps accounts)
 (token_hash text (#:primary-key))
 (email citext (#:not-null))
 (next_path text (#:not-null))
 (created_at timestamptz (#:not-null))
 (expires_at timestamptz (#:not-null))
 (used_at timestamptz (#:null))
 (link_account_id bigint (#:null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

(define-public (recent-login-token-count x email)
  "How many sign-in links this address asked for in the last hour."
  (or (qval x "SELECT count(*) FROM login_tokens
                WHERE email = $1 AND created_at > now() - interval '1 hour'" email) 0))

(define-public (store-login-token! x token-hash email next link-account-id)
  (with-tx
   (lambda ()
     (q! x "INSERT INTO login_tokens (token_hash, email, next_path, expires_at, link_account_id)
             VALUES ($1, $2, $3, now() + interval '20 minutes', $4::bigint)"
         token-hash email next link-account-id)
     (q! x "DELETE FROM login_tokens WHERE expires_at < now() - interval '1 day'"))))

(define-public (peek-login-token x token-hash)
  "The address a still-valid token is for, or #f. Does not use it up."
  (qval x "SELECT email::text FROM login_tokens
            WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()" token-hash))

(define-public (use-login-token! x token-hash)
  "Mark the token used and return (email next_path link_account_id), or #f."
  (let ((row (q1 x "UPDATE login_tokens SET used_at = now()
                     WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
                 RETURNING email::text AS email, next_path, link_account_id" token-hash)))
    (and row (list (row-ref row "email")
                   (row-ref row "next_path")
                   (row-ref row "link_account_id")))))
