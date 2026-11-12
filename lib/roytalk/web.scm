;;  roytalk -- request and response helpers.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(define-module (roytalk web)
  #:use-module (artanis artanis)
  #:use-module (artanis env)
  #:use-module (artanis tpl)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (web uri)
  #:use-module (web request)
  #:use-module (web http)
  #:use-module (json)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:export (render
            render-string
            redirect
            emit-json
            emit-text
            not-found!
            forbidden!
            form-params
            form-ref
            query-ref
            cookie-ref
            make-cookie
            clear-cookie
            client-ip
            user-agent
            bot?
            same-origin-post?
            public-cache
            private-cache
            json-ld))

;; Guile drops the #fragment when it writes a Location header. RFC 7231
;; allows one, and we need it to land on the question just posted.
(declare-header! "Location"
  string->uri-reference
  uri-reference?
  (lambda (uri port) (display (uri->string uri) port)))

;; ------------------------------------------------------------------ rendering

;; Render app/views/<name>.html.tpl in the caller's environment.
;; It is a macro because templates see the local bindings of the handler.
(define-syntax-rule (render-string name env)
  (tpl-render-from-file
   (string-append (current-toplevel) "/app/views/" name ".html.tpl")
   env))

(define-syntax render
  (syntax-rules ()
    ((_ name env)
     (render name env #:status 200 #:headers '()))
    ((_ name env #:status status)
     (render name env #:status status #:headers '()))
    ((_ name env #:headers headers)
     (render name env #:status 200 #:headers headers))
    ((_ name env #:status status #:headers headers)
     (response-emit (render-string name env)
                    #:status status
                    #:headers (append '((content-type . (text/html (charset . "utf-8")))
                                        (x-content-type-options . "nosniff")
                                        (referrer-policy . "strict-origin-when-cross-origin"))
                                      headers)))))

(define* (redirect path #:key (status 303) (headers '()))
  "A relative Location, so it stays correct behind Cloudflare or a proxy."
  (response-emit ""
                 #:status status
                 #:headers `((location . ,(string->uri-reference path))
                             (cache-control . (no-store))
                             ,@headers)))

(define* (emit-json obj #:key (status 200) (headers '()))
  (response-emit (scm->json-string obj)
                 #:status status
                 #:headers `((content-type . (application/json (charset . "utf-8")))
                             (cache-control . (no-store))
                             ,@headers)))

(define* (emit-text s #:key (status 200) (type 'text/plain) (headers '()))
  (response-emit s #:status status
                 #:headers `((content-type . (,type (charset . "utf-8"))) ,@headers)))

(define (not-found!)
  (throw 'artanis-err 404 'not-found "Not found"))

(define (forbidden!)
  (throw 'artanis-err 403 'forbidden "Forbidden"))

;; ------------------------------------------------------------------ cache

(define (public-cache)
  ;; Same HTML for everyone, so a CDN may keep it briefly. Personal bits are
  ;; filled in by site.js from a display-only cookie.
  '((cache-control . (public (max-age . 0) (s-maxage . 60)))))

(define (private-cache)
  '((cache-control . (private no-store))))

;; ------------------------------------------------------------------ input

(define (decode-component s)
  (uri-decode (regexp-substitute/global #f "\\+" s 'pre " " 'post)))

(define (parse-urlencoded str)
  (filter-map
   (lambda (pair)
     (and (not (string-null? pair))
          (let ((i (string-index pair #\=)))
            (if i
                (cons (decode-component (substring pair 0 i))
                      (decode-component (substring pair (1+ i))))
                (cons (decode-component pair) "")))))
   (string-split str #\&)))

(define (form-params rc)
  "The urlencoded POST body as an alist. Parsed on every call, so read it once."
  (let ((body (rc-body rc)))
    (if (and (bytevector? body) (> (bytevector-length body) 0))
        (parse-urlencoded (utf8->string body))
        '())))

(define* (form-ref params key #:optional (default #f))
  (let ((v (assoc-ref params key)))
    (if (string? v) v default)))

(define* (query-ref rc key #:optional (default #f))
  (let* ((uri (request-uri (rc-req rc)))
         (qs (uri-query uri)))
    (if qs
        (let ((v (assoc-ref (parse-urlencoded qs) key)))
          (if (string? v) v default))
        default)))

(define (cookie-header rc)
  (let ((v (assq-ref (request-headers (rc-req rc)) 'cookie)))
    (cond
     ((string? v) v)
     ((pair? v) (string-join (map (lambda (x) (if (pair? x) (format #f "~a=~a" (car x) (cdr x)) (->str x))) v) "; "))
     (else ""))))

(define (cookie-ref rc name)
  (let lp ((parts (string-split (cookie-header rc) #\;)))
    (match parts
      (() #f)
      ((p . rest)
       (let* ((p (string-trim-both p))
              (i (string-index p #\=)))
         (if (and i (string=? (substring p 0 i) name))
             (uri-decode (substring p (1+ i)))
             (lp rest)))))))

(define* (make-cookie name value #:key (max-age #f) (http-only #t) (path "/"))
  (cons 'set-cookie
        (string-append name "=" (uri-encode value)
                       "; Path=" path
                       (if max-age (format #f "; Max-Age=~a" max-age) "")
                       (if http-only "; HttpOnly" "")
                       (if (secure-cookies?) "; Secure" "")
                       "; SameSite=Lax")))

(define (clear-cookie name)
  (cons 'set-cookie
        (string-append name "=; Path=/; Max-Age=0; SameSite=Lax"
                       (if (secure-cookies?) "; Secure" ""))))

(define (header rc name)
  (let ((v (assq-ref (request-headers (rc-req rc)) name)))
    (cond ((string? v) v)
          ((not v) #f)
          (else (->str v)))))

(define (client-ip rc)
  ;; Cloudflare sets CF-Connecting-IP; a plain reverse proxy sets X-Forwarded-For.
  ;; Only used for rate limiting and de-duplicating view counts, never stored.
  (or (header rc 'cf-connecting-ip)
      (let ((xff (header rc 'x-forwarded-for)))
        (and xff (string-trim-both (car (string-split xff #\,)))))
      (header rc 'x-real-ip)
      "local"))

(define (user-agent rc)
  (let ((ua (assq-ref (request-headers (rc-req rc)) 'user-agent)))
    (cond ((string? ua) ua)
          ((pair? ua) (string-join (map ->str ua) " "))
          (else ""))))

(define *bot-re*
  (make-regexp "bot|crawl|spider|slurp|fetch|preview|scan|monitor|curl|wget|python|httpclient|headless|lighthouse|facebookexternalhit|embedly|quora|pinterest|bitly|whatsapp|telegram|discord|slack|gpt|claude|perplexity|anthropic|bytespider|ccbot|cohere"
               regexp/icase))

(define (bot? rc)
  (let ((ua (user-agent rc)))
    (or (string-null? ua) (regexp-exec *bot-re* ua) #f)))

(define (same-origin-post? rc)
  "Reject cross-site form posts. Browsers send Sec-Fetch-Site and/or Origin;
when both are missing (old clients, curl) fall through to the CSRF token check."
  (let ((site (header rc 'sec-fetch-site))
        (origin (header rc 'origin)))
    (cond
     ((and site (member site '("cross-site"))) #f)
     ((and origin (not (string=? origin "null")))
      (string=? (string-trim-right origin #\/) (base-url)))
     (else #t))))

;; ------------------------------------------------------------------ structured data

(define (json-ld obj)
  "A JSON-LD <script> body that cannot close the script element early."
  (regexp-substitute/global #f "<" (scm->json-string obj) 'pre "\\u003c" 'post))
