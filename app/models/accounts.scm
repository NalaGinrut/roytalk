;;  roytalk -- accounts model.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

;; Accounts are declared here for Artanis' model layer; the table itself is
;; created by db/schema.sql (run tools/init-db.sh first). The declaration
;; mirrors the columns the model reads and writes; the richer DDL (citext,
;; timestamptz defaults, indexes) stays in schema.sql.
(create-artanis-model
 accounts
 (:deps)
 (id bigserial (#:primary-key))
 (handle citext (#:null #:unique))
 (is_author boolean (#:not-null))
 (banned boolean (#:not-null))
 (created_at timestamptz (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (srfi srfi-45)  ; delay, for FPRM conditions
        (artanis ssql)  ; where
        (roytalk db))

;; NOTE: guile-dbd-postgresql cannot convert citext columns back to Scheme
;; ("unknown field type 16391"), so a $accounts 'get that selects `handle'
;; fails after the row is fetched. Reads cast it to text and go through the
;; parameterised q helpers; writes still use the model.
(define-public (account-by-handle x handle)
  (q1 x "SELECT id, handle::text AS handle, is_author, banned, created_at
           FROM accounts WHERE handle = $1" handle))

(define-public (account-by-id x id)
  (q1 x "SELECT id, handle::text AS handle, is_author, banned, created_at
           FROM accounts WHERE id = $1::bigint" id))

(define-public (account-created-within-day? x account-id)
  (qval x "SELECT created_at > now() - interval '1 day'
            FROM accounts WHERE id = $1::bigint" account-id))

(define-public (set-handle! x account-id handle)
  "Set the handle once, while it is still empty. Returns #t when it was set."
  (qval x "UPDATE accounts SET handle = $2
            WHERE id = $1::bigint AND handle IS NULL RETURNING id" account-id handle))

(define-public (account-question-count x account-id)
  (or (qval x "SELECT count(*) FROM questions WHERE account_id = $1::bigint" account-id) 0))

(define-public (account-submission-count x account-id)
  (or (qval x "SELECT count(*) FROM submissions WHERE account_id = $1::bigint" account-id) 0))

(define-public (admin-readers x)
  (q x "SELECT a.id, a.handle::text AS handle, a.banned, a.is_author,
               to_char(a.created_at, 'FMDD Mon YYYY') AS since,
               (SELECT count(*) FROM questions q WHERE q.account_id = a.id) AS n_q,
               (SELECT count(*) FROM submissions s WHERE s.account_id = a.id) AS n_s,
               (SELECT string_agg(provider, ', ' ORDER BY id) FROM identities i WHERE i.account_id = a.id) AS via
          FROM accounts a ORDER BY a.created_at DESC LIMIT 500"))

(define-public (ban-account! x account-id banned?)
  "Ban or unban a reader. A ban also hides what they wrote and signs them out."
  (with-tx
   (lambda ()
     (q! x "UPDATE accounts SET banned = $2::boolean
             WHERE id = $1::bigint AND NOT is_author"
         account-id (if banned? "true" "false"))
     (when banned?
       (q! x "UPDATE questions SET hidden = true WHERE account_id = $1::bigint" account-id)
       (q! x "DELETE FROM sessions WHERE account_id = $1::bigint" account-id)))))

(define-public (create-account! x)
  (qval x "INSERT INTO accounts DEFAULT VALUES RETURNING id"))

(define-public (mark-author! x account-id)
  (model-set! x $accounts #:is_author "true"
              (delay (where #:id account-id)))
  #t)
