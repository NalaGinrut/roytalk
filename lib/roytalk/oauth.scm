;;  roytalk -- OAuth 2.0 sign-in with GitHub, Google and X.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Authorization-code flow with state, plus PKCE (S256) wherever the provider
;;  supports it. Scopes are the smallest that give a stable user id and, where
;;  available, a verified email address. Nothing else is read or kept.
;;
;;  Callback URLs to register with each provider:
;;    https://<host.name>/auth/github/callback
;;    https://<host.name>/auth/google/callback
;;    https://<host.name>/auth/x/callback

(define-module (roytalk oauth)
  #:use-module (artanis artanis)
  #:use-module ((artanis runner) #:select (call-with-runner))
  #:use-module (ice-9 match)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (curl)
  #:use-module (json)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:use-module (roytalk db)
  #:use-module (app models oauth_states)
  #:export (oauth-provider?
            oauth-configured?
            oauth-start-url
            oauth-finish
            provider-label))

(define *providers* '("github" "google" "x"))

(define (oauth-provider? p) (and (member p *providers*) #t))

(define (provider-label p)
  (match p ("github" "GitHub") ("google" "Google") ("x" "X") ("email" "Email") (_ p)))

(define (client-id p) (setting (string->symbol (string-append p "-client-id")) #f))
(define (client-secret p) (setting (string->symbol (string-append p "-client-secret")) #f))

(define (oauth-configured? p)
  (and (oauth-provider? p) (present? (client-id p)) (present? (client-secret p))))

(define (callback-url p) (absolute-url (string-append "/auth/" p "/callback")))

;; ------------------------------------------------------------------ PKCE

(define *b64* "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

(define (base64url bv)
  (let* ((bytes (bytevector->u8-list bv))
         (out (open-output-string)))
    (let lp ((bs bytes))
      (match bs
        ((a b c . rest)
         (let ((n (+ (ash a 16) (ash b 8) c)))
           (for-each (lambda (s) (write-char (string-ref *b64* (logand (ash n (- s)) 63)) out)) '(18 12 6 0))
           (lp rest)))
        ((a b)
         (let ((n (+ (ash a 16) (ash b 8))))
           (for-each (lambda (s) (write-char (string-ref *b64* (logand (ash n (- s)) 63)) out)) '(18 12 6))))
        ((a)
         (let ((n (ash a 16)))
           (for-each (lambda (s) (write-char (string-ref *b64* (logand (ash n (- s)) 63)) out)) '(18 12))))
        (() #t)))
    (get-output-string out)))

(define (hex->bytevector hex)
  (u8-list->bytevector
   (let lp ((i 0) (acc '()))
     (if (>= i (string-length hex))
         (reverse acc)
         (lp (+ i 2) (cons (string->number (substring hex i (+ i 2)) 16) acc))))))

(define (pkce-challenge verifier)
  (base64url (hex->bytevector (sha256-hex verifier))))

;; ------------------------------------------------------------------ HTTP

(define (form-encode alist)
  (string-join (map (lambda (kv) (string-append (url-encode (car kv)) "=" (url-encode (cdr kv)))) alist) "&"))

(define* (http method url #:key (headers '()) (body #f) (userpwd #f))
  "Blocking HTTPS call; callers wrap it in call-with-runner. Returns (code . json-or-#f)."
  (let ((h (curl-easy-init)))
    (curl-easy-setopt h 'url url)
    (curl-easy-setopt h 'httpheader (cons* "Accept: application/json"
                                           "User-Agent: roytalk (GNU Artanis)"
                                           headers))
    (curl-easy-setopt h 'timeout 20)
    (curl-easy-setopt h 'connecttimeout 10)
    (when userpwd
      (curl-easy-setopt h 'httpauth 1) ; CURLAUTH_BASIC
      (curl-easy-setopt h 'userpwd userpwd))
    (when (eq? method 'post)
      (curl-easy-setopt h 'post #t)
      (curl-easy-setopt h 'postfields (or body "")))
    (let* ((raw (curl-easy-perform h #t))
           (code (curl-easy-getinfo h 'response-code))
           (text (and (bytevector? raw) (utf8->string raw)))
           (json (and text (false-if-exception (json-string->scm text)))))
      (cons code json))))

(define (jref obj . keys)
  (fold (lambda (k o) (and (pair? o) (let ((v (assoc-ref o k))) (if (eq? v 'null) #f v)))) obj keys))

(define (blocking thunk)
  ;; Off the event loop when running inside the server.
  (call-with-runner thunk))

;; ------------------------------------------------------------------ start

(define (oauth-start-url rc provider next link-account-id)
  "Record state and return the provider's authorization URL."
  (let* ((state (random-token 24))
         (verifier (random-token 32))
         (challenge (pkce-challenge verifier))
         (cid (client-id provider))
         (redirect (callback-url provider)))
    (store-oauth-state! rc state provider verifier (safe-next next) link-account-id)
    (match provider
      ("github"
       (string-append "https://github.com/login/oauth/authorize?"
                      (form-encode `(("client_id" . ,cid) ("redirect_uri" . ,redirect)
                                     ("scope" . "user:email") ("state" . ,state)
                                     ("allow_signup" . "true")))))
      ("google"
       (string-append "https://accounts.google.com/o/oauth2/v2/auth?"
                      (form-encode `(("client_id" . ,cid) ("redirect_uri" . ,redirect)
                                     ("response_type" . "code") ("scope" . "openid email")
                                     ("state" . ,state) ("code_challenge" . ,challenge)
                                     ("code_challenge_method" . "S256")
                                     ("prompt" . "select_account")))))
      ("x"
       (string-append "https://x.com/i/oauth2/authorize?"
                      (form-encode `(("response_type" . "code") ("client_id" . ,cid)
                                     ("redirect_uri" . ,redirect)
                                     ("scope" . "users.read tweet.read")
                                     ("state" . ,state) ("code_challenge" . ,challenge)
                                     ("code_challenge_method" . "S256"))))))))

;; ------------------------------------------------------------------ finish

(define (take-state! rc provider state)
  (and (string? state)
       (take-oauth-state! rc state provider)))

(define (github-identity code)
  (let* ((tok (http 'post "https://github.com/login/oauth/access_token"
                    #:headers '("Content-Type: application/x-www-form-urlencoded")
                    #:body (form-encode `(("client_id" . ,(client-id "github"))
                                          ("client_secret" . ,(client-secret "github"))
                                          ("code" . ,code)
                                          ("redirect_uri" . ,(callback-url "github"))))))
         (access (jref (cdr tok) "access_token")))
    (and access
         (let* ((auth (string-append "Authorization: Bearer " access))
                (user (http 'get "https://api.github.com/user" #:headers (list auth)))
                (id (jref (cdr user) "id"))
                (emails (http 'get "https://api.github.com/user/emails" #:headers (list auth)))
                (primary (and (vector? (cdr emails))
                              (find (lambda (e) (and (jref e "primary") (jref e "verified")))
                                    (vector->list (cdr emails))))))
           (and id (list (->str id) (and primary (jref primary "email"))))))))

(define (google-identity code verifier)
  (let* ((tok (http 'post "https://oauth2.googleapis.com/token"
                    #:headers '("Content-Type: application/x-www-form-urlencoded")
                    #:body (form-encode `(("client_id" . ,(client-id "google"))
                                          ("client_secret" . ,(client-secret "google"))
                                          ("code" . ,code)
                                          ("code_verifier" . ,verifier)
                                          ("grant_type" . "authorization_code")
                                          ("redirect_uri" . ,(callback-url "google"))))))
         (access (jref (cdr tok) "access_token")))
    (and access
         (let* ((info (http 'get "https://openidconnect.googleapis.com/v1/userinfo"
                            #:headers (list (string-append "Authorization: Bearer " access))))
                (sub (jref (cdr info) "sub"))
                (verified (eq? #t (jref (cdr info) "email_verified"))))
           (and sub (list sub (and verified (jref (cdr info) "email"))))))))

(define (x-identity code verifier)
  (let* ((tok (http 'post "https://api.x.com/2/oauth2/token"
                    #:headers '("Content-Type: application/x-www-form-urlencoded")
                    #:userpwd (string-append (client-id "x") ":" (client-secret "x"))
                    #:body (form-encode `(("code" . ,code)
                                          ("grant_type" . "authorization_code")
                                          ("redirect_uri" . ,(callback-url "x"))
                                          ("code_verifier" . ,verifier)))))
         (access (jref (cdr tok) "access_token")))
    (and access
         (let* ((me (http 'get "https://api.x.com/2/users/me"
                          #:headers (list (string-append "Authorization: Bearer " access))))
                (id (jref (cdr me) "data" "id")))
           ;; X does not hand out email addresses: X accounts are linked by hand.
           (and id (list id #f))))))

(define (oauth-finish rc provider code state)
  "Verify state, exchange the code and return
 (subject email next link-account-id), or #f on any failure."
  (let ((st (take-state! rc provider state)))
    (and st (string? code) (not (string-null? code))
         (let* ((verifier (row-ref st "verifier"))
                (who (false-if-exception
                      (blocking
                       (lambda ()
                         (match provider
                           ("github" (github-identity code))
                           ("google" (google-identity code verifier))
                           ("x" (x-identity code verifier))))))))
           (and who
                (list (car who) (cadr who)
                      (row-ref st "next_path")
                      (row-ref st "link_account_id")))))))
