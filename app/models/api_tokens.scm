;;  roytalk -- tokens for the author's own read-only API. Only a SHA-256 is
;;  stored.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 api_tokens
 (:deps)
 (id bigserial (#:primary-key))
 (name text (#:not-null))
 (token_hash text (#:not-null #:unique))
 (created_at timestamptz (#:not-null))
 (last_used_at timestamptz (#:null))
 (revoked_at timestamptz (#:null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

(define-public (authorise-api-token! x token-hash)
  "Mark the token used and return its id, or #f when it is unknown or revoked."
  (qval x "UPDATE api_tokens SET last_used_at = now()
            WHERE token_hash = $1 AND revoked_at IS NULL RETURNING id" token-hash))

(define-public (admin-api-tokens x)
  (q x "SELECT id, name, to_char(created_at, 'FMDD Mon YYYY') AS created,
               to_char(last_used_at, 'FMDD Mon YYYY HH24:MI') AS used,
               revoked_at IS NOT NULL AS revoked
          FROM api_tokens ORDER BY id DESC"))

(define-public (create-api-token! x name token-hash)
  (model-set! x $api_tokens #:name name #:token_hash token-hash)
  #t)

(define-public (revoke-api-token! x id)
  (q! x "UPDATE api_tokens SET revoked_at = now()
          WHERE id = $1::bigint AND revoked_at IS NULL" id))
