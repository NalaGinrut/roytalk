;; Controller posts of roytalk: the essay page, questions, replies, read counts.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller posts) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (ice-9 regex)
             (roytalk util) (roytalk settings) (roytalk db) (roytalk web)
             (app models posts) (app models questions) (app models accounts)
             (app models sponsors)
             (roytalk views) (roytalk auth))

;; ------------------------------------------------------------------ helpers

(define (html->text html)
  "Rough plain text of rendered HTML, for checking that a quote still exists."
  (let* ((s (regexp-substitute/global #f "<[^>]*>" html 'pre " " 'post))
         (s (regexp-substitute/global #f "&nbsp;|&#160;" s 'pre " " 'post))
         (s (regexp-substitute/global #f "&amp;" s 'pre "&" 'post))
         (s (regexp-substitute/global #f "&lt;" s 'pre "<" 'post))
         (s (regexp-substitute/global #f "&gt;" s 'pre ">" 'post))
         (s (regexp-substitute/global #f "&quot;|&#39;|&rsquo;|&lsquo;|&ldquo;|&rdquo;" s 'pre "'" 'post)))
    (squash s)))

(define (squash s)
  (string-trim-both (regexp-substitute/global #f "[[:space:]]+" s 'pre " " 'post)))

(define (quote-still-there? text quoted)
  (or (blank? quoted)
      (and (string-contains text (squash (regexp-substitute/global #f "[\"“”‘’]" quoted 'pre "'" 'post))) #t)))

(define (post-path slug) (string-append "/posts/" slug))

(define (signin-path next) (string-append "/signin?next=" (url-encode next)))

(define *min-whole* 40)   ; characters for a question about the whole essay
(define *min-quoted* 8)   ; characters for a question on a quoted sentence
(define *max-body* 6000)

(define (posting-problem rc acc body quoted?)
  "#f when ACC may post BODY now, else a sentence saying why not."
  (let ((n (string-length (strip body))))
    (cond
     ((not acc) "Please sign in first.")
     ((row-ref acc "banned") "This account can no longer post here.")
     ((not (account-handle acc)) "Please choose a handle first.")
     ((< n (if quoted? *min-quoted* *min-whole*))
      (if quoted?
          "That is a little short for a question."
          (format #f "A question about the whole essay needs at least ~a characters. Say what you doubt and why." *min-whole*)))
     ((> n *max-body*) (format #f "Please keep it under ~a characters." *max-body*))
     ((and (string-match "https?://" body)
           (account-created-within-day? rc (account-id acc)))
      "New accounts cannot post links during their first day. Please describe the source instead.")
     ((>= (hourly-question-count rc (account-id acc)) 10)
      "That is a lot in one hour. Please come back a little later.")
     (else #f))))

(define (article-ld post questions)
  (json-ld
   `(("@context" . "https://schema.org")
     ("@type" . "Article")
     ("headline" . ,(row-ref post "title"))
     ("description" . ,(->str (row-ref post "dek")))
     ("datePublished" . ,(->str (row-ref post "published_rfc3339")))
     ("dateModified" . ,(->str (row-ref post "updated_rfc3339")))
     ("mainEntityOfPage" . ,(absolute-url (post-path (row-ref post "slug"))))
     ("image" . ,(absolute-url "/img/og-default.webp"))
     ("keywords" . ,(string-join (row-ref post "tags") ", "))
     ("author" . (("@type" . "Person") ("name" . ,(author-name)) ("url" . ,(absolute-url "/about"))))
     ("commentCount" . ,(length questions))
     ("comment" . ,(list->vector
                    (map (lambda (q)
                           `(("@type" . "Comment")
                             ("text" . ,(row-ref q "body"))
                             ("dateCreated" . ,(->str (row-ref q "date_iso")))
                             ("author" . (("@type" . "Person") ("name" . ,(->str (row-ref q "handle")))))))
                         (take questions (min 20 (length questions)))))))))

;; ------------------------------------------------------------------ the essay

(get "/posts/:slug"
  (lambda (rc)
    (let ((post (post-by-slug rc (params rc "slug"))))
      (unless post (not-found!))
      (let* ((slug (row-ref post "slug"))
             (questions (questions-for-post rc (row-ref post "id") #f))
             (text (html->text (row-ref post "body_html")))
             (stale? (lambda (q) (not (quote-still-there? text (row-ref q "quote_exact")))))
             (page-title (string-append (row-ref post "title") " · " (site-name)))
             (page-desc (if (present? (row-ref post "dek")) (row-ref post "dek") (excerpt text 180)))
             (canonical (absolute-url (post-path slug)))
             (sponsor (sponsor-for rc "article"))
             (sponsor-class " post-sponsor")
             (views (or (row-ref post "views") 0))
             (extra-ld (article-ld post questions)))
        (render "posts/show" (the-environment) #:headers (public-cache))))))

;; A count of human reads: site.js sends this once per page view after a few
;; seconds. Crawlers rarely run scripts; known ones are dropped by User-Agent.
;; One count per address, browser and post per day, kept only in memory.
(define *seen* (make-hash-table))
(define *seen-day* #f)

(post "/posts/:slug/read"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 60 60)
  (lambda (rc)
    (let ((day (strftime "%Y-%m-%d" (gmtime (current-time))))
          (slug (params rc "slug")))
      (unless (equal? day *seen-day*)
        (set! *seen* (make-hash-table))
        (set! *seen-day* day))
      (unless (bot? rc)
        (let ((key (string-append slug "|" (client-ip rc) "|" (user-agent rc))))
          (unless (hash-ref *seen* key)
            (hash-set! *seen* key #t)
            (bump-post-views! rc slug))))
      (response-emit "" #:status 204 #:headers '((cache-control . (no-store)))))))

;; ------------------------------------------------------------------ asking

(get "/posts/:slug/ask"
  (lambda (rc)
    (let* ((post (post-by-slug rc (params rc "slug")))
           (acc (current-account rc)))
      (unless post (not-found!))
      (cond
       ((not acc) (redirect (signin-path (rc-path rc))))
       ((not (account-handle acc)) (redirect (string-append "/welcome?next=" (url-encode (rc-path rc)))))
       (else
        (let* ((slug (row-ref post "slug"))
               (page-title (string-append "Ask · " (row-ref post "title")))
               (page-desc "Ask a question about this essay.")
               (canonical (absolute-url (string-append (post-path slug) "/ask")))
               (csrf (csrf-token rc))
               (error-message #f)
               (body ""))
          (render "posts/ask" (the-environment) #:headers (private-cache))))))))

(post "/posts/:slug/questions"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 20 3600)
  (lambda (rc)
    (let* ((form (form-params rc))
           (post (post-by-slug rc (params rc "slug")))
           (acc (current-account rc)))
      (unless post (not-found!))
      (let* ((slug (row-ref post "slug"))
             (body (strip (form-ref form "body" "")))
             (exact (strip (clamp-string (form-ref form "quote_exact" "") 600)))
             (prefix (clamp-string (form-ref form "quote_prefix" "") 64))
             (suffix (clamp-string (form-ref form "quote_suffix" "") 64))
             (quoted? (present? exact)))
        (cond
         ((not acc) (redirect (signin-path (post-path slug))))
         ((not (csrf-ok? rc form)) (forbidden!))
         ((posting-problem rc acc body quoted?)
          => (lambda (problem)
               (let* ((page-title (string-append "Ask · " (row-ref post "title")))
                      (page-desc "Ask a question about this essay.")
                      (canonical (absolute-url (string-append (post-path slug) "/ask")))
                      (csrf (csrf-token rc))
                      (error-message problem))
                 (render "posts/ask" (the-environment) #:status 422 #:headers (private-cache)))))
         (else
          (let ((id (create-question! rc (row-ref post "id") (account-id acc)
                                      exact prefix suffix body)))
            (redirect (format #f "~a?q=~a#q-~a" (post-path slug) id id)))))))))

;; ------------------------------------------------------------------ replying

(get "/questions/:id/reply"
  (lambda (rc)
    (let* ((target (and (string->number (params rc "id")) (question-with-post rc (params rc "id"))))
           (acc (current-account rc)))
      (unless (and target (not (row-ref target "hidden"))) (not-found!))
      (cond
       ((not acc) (redirect (signin-path (rc-path rc))))
       ;; A merged question has no thread of its own; answer the canonical one.
       ((row-ref target "merged_into")
        (redirect (format #f "/posts/~a#q-~a"
                          (row-ref target "slug") (row-ref target "root_id"))))
       ((not (account-handle acc)) (redirect (string-append "/welcome?next=" (url-encode (rc-path rc)))))
       (else
        (let* ((page-title (string-append "Reply · " (row-ref target "title")))
               (page-desc "Reply to a question.")
               (canonical (absolute-url (rc-path rc)))
               (csrf (csrf-token rc))
               (error-message #f)
               (body ""))
          (render "posts/reply" (the-environment) #:headers (private-cache))))))))

(post "/questions/:id/replies"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 30 3600)
  (lambda (rc)
    (let* ((form (form-params rc))
           (target (and (string->number (params rc "id")) (question-with-post rc (params rc "id"))))
           (acc (current-account rc)))
      (unless (and target (not (row-ref target "hidden"))) (not-found!))
      (let* ((body (strip (form-ref form "body" "")))
             ;; Threads stay two levels deep: a reply to a reply hangs off the
             ;; question and remembers whom it answers. A merged question's
             ;; thread is the canonical question's.
             (root (or (row-ref target "parent_id") (row-ref target "root_id")))
             (reply-to (and (row-ref target "parent_id") (row-ref target "account_id"))))
        (cond
         ((not acc) (redirect (signin-path (string-append "/questions/" (params rc "id") "/reply"))))
         ((not (csrf-ok? rc form)) (forbidden!))
         ((posting-problem rc acc body #t)
          => (lambda (problem)
               (let* ((page-title (string-append "Reply · " (row-ref target "title")))
                      (page-desc "Reply to a question.")
                      (canonical (absolute-url (rc-path rc)))
                      (csrf (csrf-token rc))
                      (error-message problem))
                 (render "posts/reply" (the-environment) #:status 422 #:headers (private-cache)))))
         (else
          (let ((id (create-reply! rc (row-ref target "post_id") (account-id acc)
                                   root reply-to body)))
            (redirect (format #f "/posts/~a?q=~a#q-~a" (row-ref target "slug") id id)))))))))

(get "/q/:id"
  (lambda (rc)
    (let ((row (and (string->number (params rc "id"))
                    (question-redirect rc (params rc "id")))))
      (unless row (not-found!))
      (redirect (format #f "/posts/~a#q-~a" (row-ref row "slug") (row-ref row "root_id"))
                #:status 301))))
