;;  roytalk -- OAuth round trips in flight: state, PKCE verifier, where to go.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 oauth_states
 (:deps accounts)
 (state text (#:primary-key))
 (provider text (#:not-null))
 (verifier text (#:not-null))
 (next_path text (#:not-null))
 (link_account_id bigint (#:null))
 (expires_at timestamptz (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

(define-public (store-oauth-state! x state provider verifier next link-account-id)
  (with-tx
   (lambda ()
     (q! x "INSERT INTO oauth_states (state, provider, verifier, next_path, link_account_id, expires_at)
             VALUES ($1, $2, $3, $4, $5::bigint, now() + interval '10 minutes')"
         state provider verifier next link-account-id)
     (q! x "DELETE FROM oauth_states WHERE expires_at < now()"))))

(define-public (take-oauth-state! x state provider)
  "Use up STATE and return verifier, next_path and link_account_id."
  (q1 x "DELETE FROM oauth_states
          WHERE state = $1 AND provider = $2 AND expires_at > now()
      RETURNING verifier, next_path, link_account_id" state provider))
