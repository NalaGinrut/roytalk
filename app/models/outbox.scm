;;  roytalk -- outgoing mail queue. The web process only inserts rows;
;;  tools/mailer.scm sends them, so no request ever waits on SMTP.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 outbox
 (:deps)
 (id bigserial (#:primary-key))
 (to_addr text (#:not-null))
 (subject text (#:not-null))
 (body_text text (#:not-null))
 (headers text (#:not-null))
 (created_at timestamptz (#:not-null))
 (attempts int (#:not-null))
 (sent_at timestamptz (#:null))
 (last_error text (#:null))
 (stream text (#:not-null))
 (body_html text (#:null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk util)
        (roytalk db))

(export enqueue-mail! outbox-stats)

(define* (enqueue-mail! x to subject text #:key (html #f) (headers "") (stream "account"))
  (model-set! x $outbox
              #:to_addr to
              #:subject subject
              #:body_text text
              #:body_html (nullable html)
              #:headers headers
              #:stream stream)
  #t)

(define (outbox-stats x)
  (q1 x "SELECT count(*) FILTER (WHERE sent_at IS NULL) AS pending,
                count(*) FILTER (WHERE sent_at IS NULL AND attempts > 0) AS failing,
                count(*) FILTER (WHERE sent_at > now() - interval '1 day') AS sent_today
           FROM outbox"))
