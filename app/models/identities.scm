;;  roytalk -- identities model: the sign-in methods behind an account.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  A new sign-in method with a verified address that another method of an
;;  account already uses joins that account, so GitHub, Google and email
;;  sign-ins of one person meet.

(import (artanis mvc model))

(create-artanis-model
 identities
 (:deps accounts)
 (id bigserial (#:primary-key))
 (account_id bigint (#:not-null))
 (provider text (#:not-null))
 (subject text (#:not-null))
 (email citext (#:null))
 (created_at timestamptz (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk util)
        (roytalk db)
        (app models accounts))

(define (mark-author-if! x account-id author-email?)
  (when author-email? (mark-author! x account-id)))

(define-public (resolve-identity! x provider subject email author-email?)
  "Find or create the account behind a verified sign-in and return its id.
EMAIL must already be verified by the provider (or #f)."
  (with-tx
   (lambda ()
     (let ((existing (qval x "SELECT account_id FROM identities
                               WHERE provider = $1 AND subject = $2" provider subject)))
       (cond
        (existing
         (when email
           (q! x "UPDATE identities SET email = $3 WHERE provider = $1 AND subject = $2"
               provider subject email))
         (mark-author-if! x existing author-email?)
         existing)
        (else
         (let* ((same-email (and email
                                 (qval x "SELECT account_id FROM identities
                                           WHERE email = $1 ORDER BY id LIMIT 1" email)))
                (fresh? (not same-email))
                (acc (or same-email (create-account! x)))
                (ins (q1 x "INSERT INTO identities (account_id, provider, subject, email)
                            VALUES ($1::bigint, $2, $3, $4)
                            ON CONFLICT (provider, subject) DO NOTHING
                        RETURNING account_id"
                         acc provider subject email)))
           (if ins
               (let ((id (row-ref ins "account_id")))
                 (mark-author-if! x id author-email?)
                 id)
               ;; Another request won the race for this sign-in method.
               (begin
                 (when fresh?
                   ;; The account made a moment ago has no references yet.
                   (q! x "DELETE FROM accounts WHERE id = $1::bigint" acc))
                 (let ((winner (qval x "SELECT account_id FROM identities
                                         WHERE provider = $1 AND subject = $2" provider subject)))
                   (when (and winner email)
                     (q! x "UPDATE identities SET email = $3 WHERE provider = $1 AND subject = $2"
                         provider subject email))
                   (mark-author-if! x winner author-email?)
                   winner))))))))))

(define-public (link-identity! x account-id provider subject email author-email?)
  "Attach a sign-in method to an existing account (from the settings page).
Returns #t, or 'taken when that method already belongs to another account."
  (with-tx
   (lambda ()
     (let ((ins (q1 x "INSERT INTO identities (account_id, provider, subject, email)
                        VALUES ($1::bigint, $2, $3, $4)
                        ON CONFLICT (provider, subject) DO NOTHING
                    RETURNING account_id"
                    account-id provider subject email)))
       (cond
        (ins
         (mark-author-if! x account-id author-email?)
         #t)
        (else
         (let ((owner (qval x "SELECT account_id FROM identities
                                WHERE provider = $1 AND subject = $2" provider subject)))
           (if (and owner (not (equal? (->str owner) (->str account-id))))
               'taken
               #t))))))))

(define-public (account-identities x account-id)
  (q x "SELECT provider, email::text AS email,
               to_char(created_at, 'FMDD Mon YYYY') AS since
          FROM identities WHERE account_id = $1::bigint ORDER BY id" account-id))
