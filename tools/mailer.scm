#!/usr/bin/env -S guile --no-auto-compile -s
!#
;;  roytalk mailer -- sends the outbox, outside the web process.
;;  Copyright (C) 2026 Roy. GPLv3 or later.
;;
;;  Run from the app directory:   guile -L lib tools/mailer.scm
;;  It polls the outbox every few seconds, sends each message once through the
;;  sendmail-compatible command in prv/settings.scm (msmtp with any SMTP relay),
;;  retries failures with back-off, and never runs inside a request.
;;
;;  mail-mode log  writes messages to log/outbox/ instead (development).
;;  --once         sends what is queued and exits (for cron).

(use-modules (ice-9 popen)
             (ice-9 match)
             (ice-9 format)
             (srfi srfi-1)
             (dbi dbi)
             (roytalk settings))

(define once? (member "--once" (command-line)))

;; ------------------------------------------------------------------ config
;; The database settings come from conf/artanis.conf, the one place they live.

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
  ;; Always bind, even with no parameters: no bare query goes to the driver.
  (dbi-params-query db sql params)
  (check sql)
  (let lp ((acc '()))
    (let ((r (dbi-get_row db)))
      (if r (lp (cons r acc)) (reverse acc)))))

;; ------------------------------------------------------------------ messages

(define (header-safe s)
  ;; No header injection: a newline in a subject or address ends here.
  (list->string (filter (lambda (c) (not (memv c '(#\newline #\return)))) (string->list s))))

(define (encode-subject s)
  ;; RFC 2047 for anything beyond ASCII.
  (if (every (lambda (c) (< (char->integer c) 128)) (string->list s))
      s
      (string-append "=?UTF-8?B?" (base64 (string->utf8 s)) "?=")))

(define *b64* "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
(define (base64 bv)
  (let ((bytes ((@ (rnrs bytevectors) bytevector->u8-list) bv))
        (out (open-output-string)))
    (let lp ((bs bytes))
      (match bs
        (() #t)
        ((a . rest)
         (let* ((b (if (pair? rest) (car rest) 0))
                (c (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) 0))
                (n (+ (ash a 16) (ash b 8) c))
                (k (min 3 (1+ (length rest)))))
           (for-each (lambda (i s)
                       (write-char (if (<= i k) (string-ref *b64* (logand (ash n (- s)) 63)) #\=) out))
                     '(0 1 2 3) '(18 12 6 0))
           (lp (if (>= (length rest) 2) (cddr rest) '()))))))
    (get-output-string out)))
(define (string->utf8 s) ((@ (rnrs bytevectors) string->utf8) s))

(define (wrap76 s)
  (let lp ((i 0) (acc '()))
    (if (>= i (string-length s))
        (string-join (reverse acc) "\n")
        (lp (+ i 76) (cons (substring s i (min (string-length s) (+ i 76))) acc)))))

(define (b64-part type body)
  (string-append "Content-Type: " type "; charset=utf-8\n"
                 "Content-Transfer-Encoding: base64\n\n"
                 (wrap76 (base64 (string->utf8 body))) "\n"))

;; Each stream has its own sender and, optionally, its own SES configuration
;; set (X-SES-CONFIGURATION-SET), so the letter can be watched and paused on
;; its own and its complaints never touch sign-in mail.
(define (stream-from stream)
  (if (equal? stream "letter")
      (setting 'mail-from-letter (setting 'mail-from "nobody@localhost"))
      (setting 'mail-from-account (setting 'mail-from "nobody@localhost"))))

(define (stream-config-set stream)
  (if (equal? stream "letter")
      (setting 'ses-configuration-set-letter #f)
      (setting 'ses-configuration-set-account #f)))

(define (stream-command stream)
  (setting (if (equal? stream "letter") 'sendmail-command-letter 'sendmail-command-account)
           (setting 'sendmail-command '("/usr/sbin/sendmail" "-t"))))

(define (rfc2822-date)
  (strftime "%a, %d %b %Y %H:%M:%S +0000" (gmtime (current-time))))

(define (message row)
  (let* ((get (lambda (k) (let ((v (assoc-ref row k))) (if (string? v) v ""))))
         (stream (get "stream"))
         (html (get "body_html"))
         (extra (get "headers"))
         (cset (stream-config-set stream))
         (boundary (string-append "=_roytalk_" (number->string (random (expt 2 64) (random-state-from-platform)) 16))))
    (string-append
     "From: " (header-safe (stream-from stream)) "\n"
     "To: " (header-safe (get "to_addr")) "\n"
     "Subject: " (encode-subject (header-safe (get "subject"))) "\n"
     "Date: " (rfc2822-date) "\n"
     "MIME-Version: 1.0\n"
     (if (and (string? cset) (not (string-null? cset)))
         (string-append "X-SES-CONFIGURATION-SET: " (header-safe cset) "\n")
         "")
     (if (string-null? extra) ""
         (string-append (string-join (map header-safe (string-split extra #\newline)) "\n") "\n"))
     (if (string-null? html)
         (b64-part "text/plain" (get "body_text"))
         (string-append
          "Content-Type: multipart/alternative; boundary=\"" boundary "\"\n\n"
          "--" boundary "\n" (b64-part "text/plain" (get "body_text"))
          "--" boundary "\n" (b64-part "text/html" html)
          "--" boundary "--\n")))))

(define (send! text id stream)
  (match (setting 'mail-mode 'log)
    ('log
     (system* "mkdir" "-p" "log/outbox")
     (call-with-output-file (format #f "log/outbox/~a.eml" id)
       (lambda (p) (set-port-encoding! p "UTF-8") (display text p)))
     #t)
    (_
     (let* ((cmd (stream-command stream))
            (port (apply open-pipe* OPEN_WRITE cmd)))
       (set-port-encoding! port "UTF-8")
       (display text port)
       (zero? (status:exit-val (close-pipe port)))))))

;; ------------------------------------------------------------------ loop

(define (drain!)
  (for-each
   (lambda (row)
     (let ((id (assoc-ref row "id")))
       (if (false-if-exception (send! (message row) id (assoc-ref row "stream")))
           (rows "UPDATE outbox SET sent_at = now(), attempts = attempts + 1, last_error = NULL WHERE id = $1::bigint" id)
           (rows "UPDATE outbox SET attempts = attempts + 1, last_error = 'send failed' WHERE id = $1::bigint" id))))
   ;; Back-off: a failed message waits attempts^2 minutes; give up after 8 tries.
   (rows "SELECT id, to_addr, subject, body_text, coalesce(body_html, '') AS body_html, headers, stream FROM outbox
           WHERE sent_at IS NULL AND attempts < 8
             AND (attempts = 0 OR created_at + make_interval(mins => attempts * attempts) < now())
           ORDER BY id LIMIT 50")))

(let lp ()
  (catch #t
    drain!
    (lambda (key . args)
      (format (current-error-port) "[mailer] ~a ~s~%" key args)))
  (unless once?
    (sleep 5)
    (lp)))
