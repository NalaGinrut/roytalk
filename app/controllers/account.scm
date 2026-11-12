;; Controller account of roytalk: sign in (email link, GitHub, Google, X),
;; first-time handle, settings, linking sign-in methods, sign out.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller account) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (roytalk util) (roytalk settings) (roytalk db) (roytalk web)
             (app models accounts)
             ((app models identities) #:select (account-identities))
             ((app models login_tokens) #:select (recent-login-token-count))
             ((app models questions) #:select (account-questions))
             ((app models submissions) #:select (account-submissions))
             (roytalk views) (roytalk auth) (roytalk oauth)
             (roytalk mail))

(define (providers) (filter oauth-configured? '("github" "google" "x")))

(define (after-sign-in rc account-id next)
  "Start a session; new accounts choose a handle first."
  (let* ((handle (row-ref (account-by-id rc account-id) "handle"))
         (cookies (session-cookies rc account-id handle)))
    (redirect (if handle next (string-append "/welcome?next=" (url-encode next)))
              #:headers cookies)))

(define (dev-mail-note email token)
  ;; While developing (mail-mode log) also print the link to the server log.
  (when (eq? (setting 'mail-mode 'log) 'log)
    (let ((port (current-error-port)))
      (format port "~%[roytalk] sign-in link for ~a: ~a~%~%" email
              (absolute-url (string-append "/signin/email/" token)))
      (force-output port))))

;; ------------------------------------------------------------------ sign in

(get "/signin"
  (lambda (rc)
    (let* ((next (safe-next (query-ref rc "next" "/")))
           (page-title (string-append "Sign in · " (site-name)))
           (page-desc "Sign in to ask questions and send in links.")
           (canonical (absolute-url "/signin"))
           (providers (providers))
           (error-message (and (query-ref rc "failed") "That did not work. Please try again.")))
      (render "account/signin" (the-environment) #:headers (private-cache)))))

(post "/signin/email"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 10 3600)
  (lambda (rc)
    (let* ((form (form-params rc))
           (email (string-downcase (strip (form-ref form "email" ""))))
           (next (safe-next (form-ref form "next" "/")))
           (trap (form-ref form "website" "")))
      (cond
       ((not (same-origin-post? rc)) (forbidden!))
       ((not (valid-email? email))
        (let* ((page-title (string-append "Sign in · " (site-name)))
               (page-desc "Sign in.")
               (canonical (absolute-url "/signin"))
               (providers (providers))
               (error-message "That does not look like an email address."))
          (render "account/signin" (the-environment) #:status 422 #:headers (private-cache))))
       (else
        ;; Same answer whatever happens, so the page tells nobody whether an
        ;; address is known. At most five links per address per hour.
        (when (and (string-null? trap)
                   (< (recent-login-token-count rc email) 5))
          (let ((tok (issue-login-token! rc email next)))
            (mail-login-link! rc email tok)
            (dev-mail-note email tok)))
        (let* ((page-title (string-append "Check your email · " (site-name)))
               (page-desc "Check your email.")
               (canonical (absolute-url "/signin")))
          (render "account/check-email" (the-environment) #:headers (private-cache))))))))

;; Opening the link only shows a button: mail scanners that prefetch links
;; must not use the one-time token up.
(get "/signin/email/:token"
  (lambda (rc)
    (let* ((token (params rc "token"))
           (email (peek-login-token rc token))
           (page-title (string-append "Sign in · " (site-name)))
           (page-desc "Sign in.")
           (canonical (absolute-url "/signin")))
      (render "account/confirm-email" (the-environment) #:headers (private-cache)))))

(post "/signin/email/:token"
  (lambda (rc)
    (let ((got (and (same-origin-post? rc) (consume-login-token! rc (params rc "token")))))
      (cond
       ((not got) (redirect "/signin?failed=1"))
       (else
        (let ((email (car got)) (next (cadr got)) (link-to (caddr got)))
          (if link-to
              (let ((r (link-identity! rc link-to "email" email email)))
                (redirect (if (eq? r 'taken) "/me?notice=taken" "/me?notice=linked")))
              (after-sign-in rc (resolve-identity! rc "email" email email) next))))))))

(get "/auth/:provider"
  (lambda (rc)
    (let ((p (params rc "provider")))
      (unless (oauth-configured? p) (not-found!))
      (redirect (oauth-start-url rc p (safe-next (query-ref rc "next" "/")) #f) #:status 302))))

(get "/auth/:provider/link"
  (lambda (rc)
    (let ((p (params rc "provider"))
          (acc (current-account rc)))
      (unless (oauth-configured? p) (not-found!))
      (if acc
          (redirect (oauth-start-url rc p "/me" (account-id acc)) #:status 302)
          (redirect "/signin?next=/me")))))

(get "/auth/:provider/callback"
  (lambda (rc)
    (let* ((p (params rc "provider"))
           (got (and (oauth-provider? p)
                     (oauth-finish rc p (query-ref rc "code") (query-ref rc "state")))))
      (cond
       ((not got) (redirect "/signin?failed=1"))
       (else
        (let ((subject (list-ref got 0)) (email (list-ref got 1))
              (next (list-ref got 2)) (link-to (list-ref got 3)))
          (if link-to
              (let ((r (link-identity! rc link-to p subject email)))
                (redirect (if (eq? r 'taken) "/me?notice=taken" "/me?notice=linked")))
              (after-sign-in rc (resolve-identity! rc p subject email) next))))))))

;; ------------------------------------------------------------------ handle

(get "/welcome"
  (lambda (rc)
    (let ((acc (current-account rc))
          (next (safe-next (query-ref rc "next" "/"))))
      (cond
       ((not acc) (redirect (string-append "/signin?next=" (url-encode next))))
       ((account-handle acc) (redirect next))
       (else
        (let* ((page-title (string-append "Choose a handle · " (site-name)))
               (page-desc "Choose a handle.")
               (canonical (absolute-url "/welcome"))
               (csrf (csrf-token rc))
               (handle "")
               (error-message #f))
          (render "account/welcome" (the-environment) #:headers (private-cache))))))))

(post "/welcome"
  (lambda (rc)
    (let* ((form (form-params rc))
           (acc (current-account rc))
           (next (safe-next (form-ref form "next" "/")))
           (handle (strip (form-ref form "handle" ""))))
      (cond
       ((not acc) (redirect "/signin"))
       ((not (csrf-ok? rc form)) (forbidden!))
       ((account-handle acc) (redirect next))
       (else
        (let ((problem
               (cond
                ((not (valid-handle? handle))
                 "2 to 24 characters: letters, digits and underscores, starting with a letter.")
                ((reserved-handle? handle) "That handle is reserved.")
                ((account-by-handle rc handle) "That handle is taken.")
                (else #f))))
          (if problem
              (let* ((page-title (string-append "Choose a handle · " (site-name)))
                     (page-desc "Choose a handle.")
                     (canonical (absolute-url "/welcome"))
                     (csrf (csrf-token rc))
                     (error-message problem))
                (render "account/welcome" (the-environment) #:status 422 #:headers (private-cache)))
              (begin
                (set-handle! rc (account-id acc) handle)
                (redirect next #:headers (list (make-cookie "rt_handle" handle
                                                            #:max-age (* *session-days* 86400)
                                                            #:http-only #f)))))))))))

;; ------------------------------------------------------------------ settings

(define (notice-text key)
  (cond ((equal? key "linked") "Done. You can now sign in that way too.")
        ((equal? key "taken") "That sign-in already belongs to another account, so it was not linked.")
        ((equal? key "email") "Check your inbox: the link adds that address to this account.")
        (else #f)))

(get "/me"
  (lambda (rc)
    (let ((acc (current-account rc)))
      (cond
       ((not acc) (redirect "/signin?next=/me"))
       ((not (account-handle acc)) (redirect "/welcome?next=/me"))
       (else
        (let* ((page-title (string-append "Your account · " (site-name)))
               (page-desc "Your account.")
               (canonical (absolute-url "/me"))
               (csrf (csrf-token rc))
               (identities (account-identities rc (account-id acc)))
               (have (map (lambda (i) (row-ref i "provider")) identities))
               (linkable (filter (lambda (p) (not (member p have))) (providers)))
               (notice (notice-text (query-ref rc "notice")))
               (n-questions (account-question-count rc (account-id acc)))
               (n-submissions (account-submission-count rc (account-id acc))))
          (render "account/me" (the-environment) #:headers (private-cache))))))))

(post "/me/email"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 5 3600)
  (lambda (rc)
    (let* ((form (form-params rc))
           (acc (current-account rc))
           (email (string-downcase (strip (form-ref form "email" "")))))
      (cond
       ((not acc) (redirect "/signin?next=/me"))
       ((not (csrf-ok? rc form)) (forbidden!))
       ((not (valid-email? email)) (redirect "/me"))
       (else
        (let ((tok (issue-login-token! rc email "/me" #:link-account-id (account-id acc))))
          (mail-login-link! rc email tok)
          (dev-mail-note email tok)
          (redirect "/me?notice=email")))))))

(get "/me/questions"
  (lambda (rc)
    (let ((acc (current-account rc)))
      (if (not acc)
          (redirect "/signin?next=/me/questions")
          (let* ((page-title (string-append "Your questions · " (site-name)))
                 (page-desc "Your questions.")
                 (canonical (absolute-url "/me/questions"))
                 (items (account-questions rc (account-id acc))))
            (render "account/my-questions" (the-environment) #:headers (private-cache)))))))

(get "/me/submissions"
  (lambda (rc)
    (let ((acc (current-account rc)))
      (if (not acc)
          (redirect "/signin?next=/me/submissions")
          (let* ((page-title (string-append "Your links · " (site-name)))
                 (page-desc "Links you sent in.")
                 (canonical (absolute-url "/me/submissions"))
                 (items (account-submissions rc (account-id acc))))
            (render "account/my-submissions" (the-environment) #:headers (private-cache)))))))

(post "/signout"
  (lambda (rc)
    (let ((form (form-params rc)))
      (if (csrf-ok? rc form)
          (redirect "/" #:headers (end-session! rc))
          (forbidden!)))))
