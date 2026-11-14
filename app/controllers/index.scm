;; Controller index of roytalk: home, archive, tags, search, static pages,
;; robots.txt, sitemap.xml and the 404 page.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller index) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (roytalk util) (roytalk settings) (roytalk db) (roytalk web)
             (roytalk excerpt)
             (app models posts) (app models tags) (app models sponsors)
             (roytalk views))

;; Ten pieces a page: enough for a new reader to judge the writing, short
;; enough that the page stays a page. Page one is "/", the rest "?page=N".
(define home-per-page 10)

(define (home-page-url n)
  (if (= n 1)
      (absolute-url "/")
      (absolute-url (string-append "/?page=" (number->string n)))))

(define (page-number rc)
  (let ((n (string->number (query-ref rc "page" "1"))))
    (min (if (and n (integer? n) (>= n 1)) n 1) 100000)))

(define (with-excerpt row)
  (acons "excerpt"
         (excerpt-paragraphs (row-ref row "body_html") #:max-words 80)
         row))

(get "/"
  (lambda (rc)
    (let* ((page (page-number rc))
           (posts (map with-excerpt
                       (published-posts rc #:limit home-per-page
                                           #:offset (* (1- page) home-per-page)
                                           #:with-body? #t)))
           (total (published-posts-count rc))
           (total-pages (max 1 (quotient (+ total (1- home-per-page)) home-per-page)))
           (page-title (if (= page 1)
                           (site-name)
                           (string-append "Page " (number->string page) " · " (site-name))))
           (page-desc (string-append (site-name) ", " (site-tagline)
                                     " Essays on inference engines, programming language theory, compilers and operating systems, and what the next era of software keeps from the last."))
           (canonical (home-page-url page))
           (prev-url (and (> page 1) (home-page-url (1- page))))
           (next-url (and (< page total-pages) (home-page-url (1+ page))))
           (page-label (string-append "Page " (number->string page)
                                      " of " (number->string total-pages)))
           (lead (and (pair? posts) (car posts)))
           (rest (if (pair? posts) (cdr posts) '()))
           (sponsor (sponsor-for rc "home"))
           (sponsor-class "")
           (extra-ld (json-ld `(("@context" . "https://schema.org")
                                ("@type" . "WebSite")
                                ("name" . ,(site-name))
                                ("url" . ,(absolute-url "/"))
                                ("author" . (("@type" . "Person") ("name" . ,(author-name))))))))
      ;; Past the last page there is nothing to show; say so rather than
      ;; rendering an empty home page with a pager on it.
      (when (and (> page 1) (null? posts)) (not-found!))
      (render "index/index" (the-environment) #:headers (public-cache)))))

(get "/archive"
  (lambda (rc)
    (let* ((page-title (string-append "Archive · " (site-name)))
           (page-desc "Everything published here, newest first.")
           (canonical (absolute-url "/archive"))
           (years (archive-years rc))
           (heading "Archive")
           (standfirst #f))
      (render "index/archive" (the-environment) #:headers (public-cache)))))

(get "/tags"
  (lambda (rc)
    (let* ((page-title (string-append "Tags · " (site-name)))
           (page-desc "Every tag in use.")
           (canonical (absolute-url "/tags"))
           (tags (filter (lambda (t) (> (or (row-ref t "n") 0) 0)) (all-tags rc))))
      (render "index/tags" (the-environment) #:headers (public-cache)))))

(get "/tags/:tag"
  (lambda (rc)
    (let* ((tag (params rc "tag"))
           (posts (posts-by-tag rc tag)))
      (when (null? posts) (not-found!))
      (let* ((page-title (string-append tag " · " (site-name)))
             (page-desc (string-append "Writing tagged " tag "."))
             (canonical (absolute-url (string-append "/tags/" (url-encode tag))))
             (heading tag)
             (standfirst (plural (length posts) "piece" "pieces"))
             (years (list (cons #f posts))))
        (render "index/archive" (the-environment) #:headers (public-cache))))))

(get "/search"
  (lambda (rc)
    (let* ((terms (strip (query-ref rc "q" "")))
           (results (if (string-null? terms) '() (search-posts rc (clamp-string terms 200))))
           (page-title (string-append "Search · " (site-name)))
           (page-desc "Search the writing.")
           (canonical (absolute-url "/search")))
      (render "index/search" (the-environment) #:headers (private-cache)))))

(get "/about"
  (lambda (rc)
    (let* ((page-title (string-append "About · " (site-name)))
           (page-desc "Who writes here, and the method: an inventory of what computing built, not a prophecy.")
           (canonical (absolute-url "/about")))
      (render "index/about" (the-environment) #:headers (public-cache)))))

(get "/principles"
  (lambda (rc)
    (let* ((page-title (string-append "Principles · " (site-name)))
           (page-desc "Six short promises: written by a human, grammar only, questions not applause, open to every reader, a sign-in and a handle, no promise of a reply.")
           (canonical (absolute-url "/principles")))
      (render "index/principles" (the-environment) #:headers (public-cache)))))

(get "/robots.txt"
  (lambda (rc)
    ;; Open to every reader, machines included (see the principles page).
    (emit-text (string-append
                "User-agent: *\n"
                "Allow: /\n"
                "Disallow: /admin\n"
                "Disallow: /me\n"
                "Disallow: /api/\n"
                "Disallow: /signin\n"
                "Disallow: /auth/\n"
                "\nSitemap: " (absolute-url "/sitemap.xml") "\n")
               #:headers (public-cache))))

(get "/sitemap.xml"
  (lambda (rc)
    (let* ((posts (published-posts rc #:limit 50000))
           (tags (filter (lambda (t) (> (or (row-ref t "n") 0) 0)) (all-tags rc)))
           (url (lambda (loc lastmod)
                  (string-append "<url><loc>" (h loc) "</loc>"
                                 (if lastmod (string-append "<lastmod>" lastmod "</lastmod>") "")
                                 "</url>\n"))))
      (emit-text
       (string-append
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        (url (absolute-url "/") #f)
        (url (absolute-url "/archive") #f)
        (url (absolute-url "/about") #f)
        (url (absolute-url "/principles") #f)
        (string-concatenate
         (map (lambda (p) (url (absolute-url (string-append "/posts/" (row-ref p "slug")))
                               (row-ref p "updated_rfc3339")))
              posts))
        (string-concatenate
         (map (lambda (t) (url (absolute-url (string-append "/tags/" (url-encode (row-ref t "name")))) #f))
              tags))
        "</urlset>\n")
       #:type 'application/xml
       #:headers (public-cache)))))

;; 404 for every controller. The handler is a thunk: no request is at hand,
;; so the page is self-contained.
(http-status-register!
 404
 (lambda ()
   (let* ((page-title (string-append "Not here · " (site-name)))
          (page-desc "This page does not exist.")
          (canonical (absolute-url "/")))
     (render-string "index/404" (the-environment)))))
