;;  roytalk -- site settings.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  The domain lives in one place only: host.name in conf/artanis.conf.
;;  Everything private (OAuth secrets, mail relay, the HMAC secret) lives in
;;  prv/settings.scm, which is not served and not committed. See
;;  prv/settings.example.scm for every key.

(define-module (roytalk settings)
  #:use-module (ice-9 match)
  #:use-module (roytalk util)
  #:export (setting host-name
            site-name
            site-tagline
            author-name
            base-url
            absolute-url
            secure-cookies?
            author-email?))

(define *settings-file*
  (or (getenv "ROYTALK_SETTINGS")
      (string-append (getcwd) "/prv/settings.scm")))

(define *settings*
  (if (file-exists? *settings-file*)
      (call-with-input-file *settings-file* read)
      (begin
        (format (current-error-port)
                "[roytalk] ~a not found, running with defaults (development only).~%"
                *settings-file*)
        '())))

(define* (setting key #:optional (default #f))
  (match (assq key *settings*)
    ((_ . v) v)
    (else default)))

(define (site-name) (setting 'site-name "Roy on next generation software"))
(define (site-tagline) (setting 'site-tagline "no matter if there will be."))
(define (author-name) (setting 'author-name "Roy"))

(define (host-name)
  ;; Read lazily: (artanis config) is only loaded inside the server.
  (false-if-exception
   ((module-ref (resolve-interface '(artanis config)) 'get-conf) '(host name))))

(define (host-port)
  (false-if-exception
   ((module-ref (resolve-interface '(artanis config)) 'get-conf) '(host port))))

(define (base-url)
  "https://<host.name>, unless prv/settings.scm overrides it with base-url
(e.g. http://127.0.0.1:3000 while developing)."
  (or (setting 'base-url #f)
      (let ((h (host-name)))
        (if (and (string? h) (not (string-null? h)))
            (string-append "https://" h)
            (format #f "http://127.0.0.1:~a" (or (host-port) 3000))))))

(define (absolute-url path)
  (string-append (base-url) path))

(define (secure-cookies?)
  (string-prefix? "https://" (base-url)))

(define (author-email? email)
  (and (string? email)
       (member (string-downcase email)
               (map string-downcase (setting 'author-emails '())))
       #t))
