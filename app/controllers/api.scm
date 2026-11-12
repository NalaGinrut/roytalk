;; Controller api of roytalk: the author's read-only API.
;; For the author's own tools: what readers sent in and what they asked.
;; Authorization: Bearer <token from /admin/tokens>. No public API exists and
;; nothing can be posted through here.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller api) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (web request)
             (roytalk util) (roytalk db) (roytalk web)
             (app models api_tokens) (app models submissions) (app models questions))

(define (bearer rc)
  (let ((v (assq-ref (request-headers (rc-req rc)) 'authorization)))
    (cond
     ;; Guile parses the header into (bearer . "token") or similar shapes.
     ((and (pair? v) (symbol? (car v)) (string? (cdr v))) (cdr v))
     ((and (pair? v) (symbol? (car v)) (pair? (cdr v))) (->str (cadr v)))
     ((string? v) (let ((p (string-split v #\space)))
                    (and (= (length p) 2) (string-ci=? (car p) "bearer") (cadr p))))
     (else #f))))

(define (authorised? rc)
  (let ((tok (bearer rc)))
    (and (string? tok)
         (string-prefix? "rt_" tok)
         (let ((id (authorise-api-token! rc (sha256-hex tok))))
           (and id #t)))))

(define (since rc)
  ;; ?since=2026-11-01T00:00:00Z (anything PostgreSQL reads as a timestamp)
  (or (query-ref rc "since") "1970-01-01T00:00:00Z"))

(define (limit rc)
  (let ((n (string->number (or (query-ref rc "limit") "200"))))
    (if (and n (> n 0)) (min n 1000) 200)))

(define (deny)
  (emit-json '(("error" . "unauthorised")) #:status 401
             #:headers '((www-authenticate . ((bearer (realm . "roytalk")))))))

(get "/api/v1/submissions"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 120 60)
  (lambda (rc)
    (if (not (authorised? rc))
        (deny)
        (let ((rows (api-submissions rc (since rc) (limit rc))))
          (emit-json `(("items" . ,(list->vector (map (lambda (r) (map (lambda (kv) (if (cdr kv) kv (cons (car kv) 'null))) r)) rows)))
                       ("next_since" . ,(if (pair? rows) (row-ref (last rows) "created_at") 'null))))))))

(get "/api/v1/questions"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 120 60)
  (lambda (rc)
    (if (not (authorised? rc))
        (deny)
        (let ((rows (api-questions rc (since rc) (limit rc))))
          (emit-json `(("items" . ,(list->vector
                                    (map (lambda (r)
                                           (map (lambda (kv)
                                                  (cond ((equal? (car kv) "hidden") kv)
                                                        ((cdr kv) kv)
                                                        (else (cons (car kv) 'null))))
                                                r))
                                         rows)))
                       ("next_since" . ,(if (pair? rows) (row-ref (last rows) "created_at") 'null))))))))
