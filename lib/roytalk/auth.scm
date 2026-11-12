;;  roytalk -- sessions, CSRF, one-time sign-in links and account resolution.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  There are no passwords. A person proves an email address by clicking a
;;  one-time link, or proves a GitHub, Google or X account through OAuth.
;;  Either way they end up with an account that has a handle and nothing else.
;;
;;  Cookies:
;;    rt_session  HttpOnly, the session secret (only its SHA-256 is stored).
;;    rt_csrf     readable by site.js, HMAC of the session; must come back in
;;                every form post (double-submit, bound to the session).
;;    rt_handle   readable by site.js, display only, so cached public pages
;;                can show "@handle" instead of "Sign in". Never trusted.
;;
;;  Token generation, cookies and the email-author policy live here; the rows
;;  live in (app models sessions), (app models login_tokens) and
;;  (app models identities).

(define-module (roytalk auth)
  #:use-module (artanis artanis)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:use-module (roytalk db)
  #:use-module (roytalk web)
  #:use-module ((app models sessions)
                #:select (account-for-session
                          create-session!
                          delete-session!
                          delete-expired-sessions!))
  #:use-module ((app models login_tokens)
                #:select ((recent-login-token-count . model-recent-login-token-count)
                          (store-login-token! . model-store-login-token!)
                          (peek-login-token . model-peek-login-token)
                          (use-login-token! . model-use-login-token!)))
  #:use-module ((app models identities)
                #:select ((resolve-identity! . model-resolve-identity!)
                          (link-identity! . model-link-identity!)))
  #:export (current-account
            account-id
            account-handle
            author?
            session-cookies
            signout-cookies
            end-session!
            csrf-token
            csrf-ok?
            issue-login-token!
            consume-login-token!
            peek-login-token
            resolve-identity!
            link-identity!
            *session-days*))

(define *session-days* 90)
(define *session-cookie* "rt_session")

(define (secret)
  (or (setting 'secret #f)
      (begin
        (format (current-error-port)
                "[roytalk] WARNING: no `secret' in prv/settings.scm, using an insecure development value.~%")
        "development-only-secret-change-me")))

(define (hmac s)
  ((module-ref (resolve-interface '(artanis security hash)) 'string->hmac-sha-256)
   (secret) s))

;; ------------------------------------------------------------------ sessions

(define (session-token rc) (cookie-ref rc *session-cookie*))

(define (current-account rc)
  "The signed-in account as an alist (id, handle, is_author, banned), or #f."
  (let ((tok (session-token rc)))
    (and tok
         (= (string-length tok) 64)
         (account-for-session rc (sha256-hex tok)))))

(define (account-id acc) (and acc (row-ref acc "id")))
(define (account-handle acc) (and acc (row-ref acc "handle")))
(define (author? acc) (and acc (row-ref acc "is_author") (not (row-ref acc "banned"))))

(define (session-cookies rc account-id handle)
  "Create a session and return the Set-Cookie headers for it."
  (let ((tok (random-token 32))
        (max-age (* *session-days* 86400)))
    (create-session! rc (sha256-hex tok) account-id *session-days*)
    (list (make-cookie *session-cookie* tok #:max-age max-age)
          (make-cookie "rt_csrf" (hmac tok) #:max-age max-age #:http-only #f)
          (make-cookie "rt_handle" (or handle "") #:max-age max-age #:http-only #f))))

(define (signout-cookies)
  (list (clear-cookie *session-cookie*) (clear-cookie "rt_csrf") (clear-cookie "rt_handle")))

(define (end-session! rc)
  (let ((tok (session-token rc)))
    (when tok
      (delete-session! rc (sha256-hex tok)))
    (signout-cookies)))

;; ------------------------------------------------------------------ CSRF

(define (csrf-token rc)
  (let ((tok (session-token rc)))
    (if tok (hmac tok) "")))

(define (csrf-ok? rc params)
  (let ((tok (session-token rc))
        (sent (form-ref params "csrf" "")))
    (and tok
         (same-origin-post? rc)
         (constant-time=? sent (hmac tok)))))

;; ------------------------------------------------------------------ email links

(define* (issue-login-token! rc email next #:key (link-account-id #f))
  "Store a one-time token for EMAIL and return the raw token for the link."
  (let ((tok (random-token 32)))
    (model-store-login-token! rc (sha256-hex tok) email (safe-next next) link-account-id)
    tok))

(define (peek-login-token rc tok)
  "The address a still-valid token is for, or #f. Does not use it up."
  (and (string? tok)
       (= (string-length tok) 64)
       (model-peek-login-token rc (sha256-hex tok))))

(define (consume-login-token! rc tok)
  "Mark the token used and return (email next link-account-id), or #f."
  (and (string? tok)
       (= (string-length tok) 64)
       (model-use-login-token! rc (sha256-hex tok))))

;; ------------------------------------------------------------------ accounts

(define (resolve-identity! rc provider subject email)
  "Find or create the account behind a verified sign-in and return its id."
  (model-resolve-identity! rc provider subject email (author-email? email)))

(define (link-identity! rc account-id provider subject email)
  "Attach a sign-in method to an existing account (from the settings page).
Returns #t, or 'taken when that method already belongs to another account."
  (model-link-identity! rc account-id provider subject email (author-email? email)))
