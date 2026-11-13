;;  roytalk -- monthly digests that actually went out.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  tools/digest.scm writes these rows; the desk only reads the latest one.
;;  A row exists only when a digest was sent, so "no rows this month" means
;;  the timer found nothing worth sending.

(import (artanis mvc model))

(create-artanis-model
 digests
 (:deps)
 (id bigserial (#:primary-key))
 (period_start timestamptz (#:not-null))
 (period_end timestamptz (#:not-null))
 (post_count int (#:not-null))
 (recipient_count int (#:not-null))
 (created_at timestamptz (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

(export last-digest)

(define (last-digest x)
  (q1 x "SELECT to_char(created_at, 'FMDD FMMonth YYYY') AS sent,
                post_count, recipient_count
           FROM digests ORDER BY created_at DESC LIMIT 1"))
