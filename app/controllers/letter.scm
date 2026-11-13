;; Controller letter of roytalk: the newsletter (separate from accounts),
;; double opt-in and one-click unsubscribe; plus the Atom feed.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller letter) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (roytalk util) (roytalk settings) (roytalk db) (roytalk web)
             (app models posts) (app models subscribers)
             (roytalk views) (roytalk mail))

(define (simple-page rc heading text status)
  (let* ((page-title (string-append heading " · " (site-name)))
         (page-desc text)
         (canonical (absolute-url "/")))
    (render "letter/message" (the-environment) #:status status #:headers (private-cache))))

(post "/letter"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 10 3600)
  (lambda (rc)
    (let* ((form (form-params rc))
           (email (string-downcase (strip (form-ref form "email" ""))))
           (trap (form-ref form "website" "")))
      (cond
       ((not (same-origin-post? rc)) (forbidden!))
       ((not (valid-email? email))
        (simple-page rc "Not quite" "That does not look like an email address. Please go back and check it." 422))
       (else
        (when (string-null? trap)
          (let ((row (subscriber-by-email rc email)))
            (cond
             ((not row)
              (let ((tok (random-token 24)))
                (insert-subscriber! rc email tok)
                (mail-confirm-subscription! rc email tok)))
             ((member (row-ref row "status") '("pending" "unsubscribed"))
              ;; Ask again, at most once a day, so the form cannot be used to flood someone.
              (when (subscriber-can-resend? rc email)
                (mark-subscriber-pending! rc email)
                (mail-confirm-subscription! rc email (row-ref row "token"))))
             (else #t))))
        (simple-page rc "Almost there"
                     "Check your inbox: a message with a confirmation link is on its way. Nothing will be sent until you click it. After that, one digest a month."
                     200))))))

(get "/letter/confirm/:token"
  (lambda (rc)
    (let ((ok (confirm-subscriber! rc (params rc "token"))))
      ;; Welcome them once per confirmation (a second click on the link finds
      ;; the address active already and sends nothing).
      (when ok (mail-welcome! rc (row-ref ok "email") (row-ref ok "token")))
      (if (or ok (active-subscriber-token? rc (params rc "token")))
          (simple-page rc "You are on the list" "One digest a month will arrive by email, with a month of writing inside. Every letter has a link to leave." 200)
          (simple-page rc "Unknown link" "This confirmation link is not valid." 404)))))

;; One click from the letter, and RFC 8058 one-click (POST) from mail clients.
(define (unsubscribe! rc token)
  (unsubscribe-subscriber! rc token))

(get "/letter/leave/:token"
  (lambda (rc)
    (let ((known (known-subscriber-token? rc (params rc "token"))))
      (unsubscribe! rc (params rc "token"))
      (if known
          (simple-page rc "You have left the list" "No more letters will be sent to this address. You can subscribe again from the home page at any time." 200)
          (simple-page rc "Unknown link" "This link is not valid." 404)))))

(post "/letter/leave/:token"
  (lambda (rc)
    (unsubscribe! rc (params rc "token"))
    (response-emit "" #:status 204)))

;; ------------------------------------------------------------------ Atom

(define (xml s) (h s))

(get "/feed/atom"
  (lambda (rc)
    (let* ((posts (feed-posts rc 30))
           (updated (if (pair? posts) (row-ref (car posts) "updated_rfc3339") "2026-01-01T00:00:00Z")))
      (emit-text
       (string-append
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
        "<title>" (xml (site-name)) "</title>\n"
        "<subtitle>" (xml (site-tagline)) "</subtitle>\n"
        "<link rel=\"self\" href=\"" (xml (absolute-url "/feed/atom")) "\"/>\n"
        "<link rel=\"alternate\" href=\"" (xml (absolute-url "/")) "\"/>\n"
        "<id>" (xml (absolute-url "/")) "</id>\n"
        "<updated>" updated "</updated>\n"
        "<author><name>" (xml (author-name)) "</name></author>\n"
        (string-concatenate
         (map (lambda (p)
                (let ((url (absolute-url (string-append "/posts/" (row-ref p "slug")))))
                  (string-append
                   "<entry>\n"
                   "<title>" (xml (row-ref p "title")) "</title>\n"
                   "<link rel=\"alternate\" href=\"" (xml url) "\"/>\n"
                   "<id>" (xml url) "</id>\n"
                   "<published>" (row-ref p "published_rfc3339") "</published>\n"
                   "<updated>" (row-ref p "updated_rfc3339") "</updated>\n"
                   (if (present? (row-ref p "dek")) (string-append "<summary>" (xml (row-ref p "dek")) "</summary>\n") "")
                   "<content type=\"html\">" (xml (row-ref p "body_html")) "</content>\n"
                   "</entry>\n")))
              posts))
        "</feed>\n")
       #:type 'application/atom+xml
       #:headers (public-cache)))))
