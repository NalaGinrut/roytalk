#!/usr/bin/env -S guile --no-auto-compile -s
!#
;;  roytalk digest -- the monthly letter, outside the web process.
;;  Copyright (C) 2026 Roy. GPLv3 or later.
;;
;;  Run from the app directory:   guile -L lib tools/digest.scm
;;  --dry-run   render a preview and print it; write nothing
;;  --force     send even if a digest already went out this UTC month
;;
;;  One digest a month: every piece published since the last digest (thirty
;;  days back on the first run) that has not been in one yet
;;  (posts.emailed_at IS NULL), linked back to the site. Using the previous
;;  digest's end rather than a fixed thirty-day window matters: with a
;;  monthly timer a piece published just before a thirty-day cutoff would
;;  otherwise never be selected. With nothing to send, or no active
;;  subscribers, it sends nothing and records nothing. The mails go to
;;  `outbox'; tools/mailer.scm sends them.
;;
;;  The only SQL here. It does not use the Artanis DB pool: like the mailer,
;;  it is its own process with its own connection.

(use-modules (ice-9 match)
             (ice-9 format)
             (dbi dbi)
             (artanis config)
             (roytalk settings)
             (roytalk letter)
             (roytalk digest))

(define args (cdr (command-line)))
(define dry-run? (member "--dry-run" args))
(define force? (member "--force" args))

;; ------------------------------------------------------------------ config
;; host.name lives in conf/artanis.conf; without it absolute-url() falls back
;; to 127.0.0.1:3000 in the links. init-config() would print its progress on
;; stdout, which would spoil --dry-run's preview.

(define (conf-value key)
  (call-with-input-file "conf/artanis.conf"
    (lambda (port)
      (let lp ()
        (let ((line (read-line port)))
          (cond
           ((eof-object? line) #f)
           ((string-prefix? (string-append key " = ") line)
            (string-trim-both (substring line (+ (string-length key) 3))))
           (else (lp))))))))

(define (read-line port)
  (let lp ((chars '()))
    (let ((c (read-char port)))
      (cond
       ((eof-object? c) (if (null? chars) c (list->string (reverse chars))))
       ((char=? c #\newline) (list->string (reverse chars)))
       (else (lp (cons c chars)))))))

(current-conf-file (string-append (getcwd) "/conf/artanis.conf"))
(with-output-to-string (lambda () (init-config)))

(define db
  (let ((user (conf-value "db.username"))
        (pass (conf-value "db.passwd"))
        (name (conf-value "db.name"))
        (addr (conf-value "db.addr")))
    (dbi-open "postgresql" (format #f "~a:~a:~a:tcp:~a" user pass name addr))))

(define (check what)
  (match (dbi-get_status db)
    ((0 . _) #t)
    ((code . msg) (error what msg))))

(define (rows sql . params)
  (dbi-params-query db sql params)
  (check sql)
  (let lp ((acc '()))
    (let ((r (dbi-get_row db)))
      (if r (lp (cons r acc)) (reverse acc)))))

(define (exec! sql . params)
  (dbi-params-query db sql params)
  (check sql))

(define (truthy? v)
  (or (eq? v #t) (equal? v "t") (equal? v "true")))

(define (bail msg status)
  (format (current-error-port) "[digest] ~a~%" msg)
  (exit status))

;; ------------------------------------------------------------------ queries

(define (recent-posts)
  (rows "SELECT p.id, p.slug, p.title, p.dek, p.body_html,
                to_char(p.published_at, 'FMDD FMMonth YYYY') AS date_long,
                (SELECT string_agg(t.name::text, ',' ORDER BY pt.position, t.name)
                   FROM post_tags pt JOIN tags t ON t.id = pt.tag_id
                  WHERE pt.post_id = p.id) AS tag_list
           FROM posts p
          WHERE p.status = 'published'
            AND p.emailed_at IS NULL
            AND p.published_at >= (SELECT coalesce(max(period_end), now() - interval '30 days')
                                     FROM digests)
            AND p.published_at <= now()
          ORDER BY p.published_at DESC"))

(define (active-subscribers)
  (rows "SELECT email::text AS email, token
           FROM subscribers WHERE status = 'active' ORDER BY id"))

(define (sent-this-month?)
  (pair? (rows "SELECT id FROM digests
                 WHERE date_trunc('month', created_at AT TIME ZONE 'UTC')
                     = date_trunc('month', now() AT TIME ZONE 'UTC')
                 LIMIT 1")))

(define (render-for subscribers posts)
  "One (email subject text html headers) per subscriber."
  (map (lambda (s)
         (call-with-values
             (lambda ()
               (render-digest-mail posts
                                   #:leave-url (leave-url (assoc-ref s "token"))))
           (lambda (subject html text headers)
             (list (assoc-ref s "email") subject text html headers))))
       subscribers))

;; ------------------------------------------------------------------ main

(define (main)
  (unless dry-run?
    (let ((locked (assoc-ref (or (car (rows "SELECT pg_try_advisory_lock(7440271) AS locked"))
                                 '())
                             "locked")))
      (unless (truthy? locked)
        (bail "another digest is running; stopping." 0))))

  (let ((posts (recent-posts)))
    (when (null? posts)
      (display "Nothing to send.\n")
      (exit 0))

    ;; A preview never prints a real address or a real unsubscribe token.
    (let* ((subscribers (active-subscribers))
           (recipients (if dry-run?
                           (list '(("email" . "preview") ("token" . "preview")))
                           subscribers)))
      (when (null? recipients)
        (display "No active subscribers; nothing sent.\n")
        (exit 0))

      (when (and (not dry-run?) (not force?) (sent-this-month?))
        (display "A digest already went out this month; use --force to send again.\n")
        (exit 0))

      (let ((mails (render-for recipients posts)))
        (if dry-run?
            (begin
              (for-each
               (lambda (mail)
                 (format #t "To: ~a~%Subject: ~a~%" (car mail) (cadr mail))
                 (format #t "~a~%" (caddr mail)))
               mails)
              (format (current-error-port)
                      "[digest] dry run: ~a ~a for ~a subscriber(s); the preview uses a fake unsubscribe link.~%"
                      (length posts) (if (= 1 (length posts)) "piece" "pieces")
                      (length subscribers))
              (exit 0))

            (begin
              (exec! "BEGIN")
              (catch #t
                (lambda ()
                  (for-each
                   (lambda (mail)
                     (exec! "INSERT INTO outbox (to_addr, subject, body_text, body_html, headers, stream)
                             VALUES ($1, $2, $3, $4, $5, 'letter')"
                            (list-ref mail 0) (list-ref mail 1) (list-ref mail 2)
                            (list-ref mail 3) (list-ref mail 4)))
                   mails)
                  (for-each
                   (lambda (post)
                     (exec! "UPDATE posts SET emailed_at = now() WHERE id = $1::bigint"
                            (assoc-ref post "id")))
                   posts)
                  (exec! "INSERT INTO digests (period_start, period_end, post_count, recipient_count)
                          SELECT coalesce(max(period_end), now() - interval '30 days'),
                                 now(), $1::int, $2::int
                            FROM digests"
                         (number->string (length posts))
                         (number->string (length recipients)))
                  (exec! "COMMIT"))
                (lambda (key . rest)
                  (catch #t (lambda () (exec! "ROLLBACK") #t) (lambda ignored #f))
                  (format (current-error-port) "[digest] failed: ~a ~s~%" key rest)
                  (exit 1)))
              (format #t "Queued ~a ~a for ~a recipient(s).~%"
                      (length posts) (if (= 1 (length posts)) "piece" "pieces")
                      (length recipients))))))))

(main)
