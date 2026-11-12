;;  roytalk -- letter subscribers: a separate list from accounts.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 subscribers
 (:deps)
 (id bigserial (#:primary-key))
 (email citext (#:not-null #:unique))
 (status text (#:not-null))
 (token text (#:not-null #:unique))
 (created_at timestamptz (#:not-null))
 (confirmed_at timestamptz (#:null))
 (left_at timestamptz (#:null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

;; NOTE: guile-dbd-postgresql cannot convert citext columns back to Scheme
;; ("unknown field type 16391"), so reads cast `email' to text and go through
;; the parameterised q helpers; writes still use the model.
(define-public (subscriber-by-email x email)
  (q1 x "SELECT id, email::text AS email, status, token, created_at,
                confirmed_at, left_at
           FROM subscribers WHERE email = $1" email))

(define-public (insert-subscriber! x email token)
  (model-set! x $subscribers #:email email #:token token)
  #t)

(define-public (subscriber-can-resend? x email)
  "Ask again at most once a day, so the form cannot flood an address."
  (qval x "SELECT created_at < now() - interval '1 day' OR status = 'unsubscribed'
             FROM subscribers WHERE email = $1" email))

(define-public (mark-subscriber-pending! x email)
  (q! x "UPDATE subscribers SET status = 'pending', created_at = now() WHERE email = $1" email))

(define-public (confirm-subscriber! x token)
  "Activate a pending or unsubscribed address once. Returns its row when the
address became active now, so the welcome is sent once per confirmation."
  (q1 x "UPDATE subscribers SET status = 'active', confirmed_at = now(), left_at = NULL
          WHERE token = $1 AND status <> 'active' RETURNING email::text AS email, token" token))

(define-public (active-subscriber-token? x token)
  (qval x "SELECT id FROM subscribers WHERE token = $1 AND status = 'active'" token))

(define-public (known-subscriber-token? x token)
  (qval x "SELECT id FROM subscribers WHERE token = $1" token))

(define-public (unsubscribe-subscriber! x token)
  (q! x "UPDATE subscribers SET status = 'unsubscribed', left_at = now()
          WHERE token = $1 AND status <> 'unsubscribed'" token))

(define-public (active-subscribers x)
  (q x "SELECT email::text AS email, token FROM subscribers WHERE status = 'active'"))

(define-public (subscriber-status-counts x)
  (q x "SELECT status, count(*) AS n FROM subscribers GROUP BY status ORDER BY status"))

(define-public (active-subscriber-count x)
  (or (qval x "SELECT count(*) FROM subscribers WHERE status = 'active'") 0))
