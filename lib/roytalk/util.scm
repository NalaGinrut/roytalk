;;  roytalk -- small helpers shared by controllers, views and tools.
;;  Copyright (C) 2026 Roy
;;  This program is free software: you can redistribute it and/or modify it
;;  under the terms of the GNU General Public License as published by the Free
;;  Software Foundation, either version 3 of the License, or (at your option)
;;  any later version.

(define-module (roytalk util)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (web uri)
  #:export (h
            ->str
            blank?
            present?
            nullable
            url-encode
            random-token
            sha256-hex
            constant-time=?
            slugify
            normalize-url
            http-url?
            safe-next
            clamp-string
            strip
            paragraphs->html
            excerpt
            valid-email?
            valid-handle?
            reserved-handle?
            string-count-words))

;; ------------------------------------------------------------------ strings

(define (->str x)
  "Anything printable to a string; #f, '() and SQL NULL become the empty string."
  (cond
   ((string? x) x)
   ((or (not x) (null? x) (unspecified? x)) "")
   ((number? x) (number->string x))
   ((symbol? x) (symbol->string x))
   (else (call-with-output-string (lambda (p) (display x p))))))

(define (h x)
  "Escape for HTML text and double-quoted attribute values.
Every value that did not come from our own templates goes through this."
  (let ((s (->str x)))
    (if (string-index s (char-set #\& #\< #\> #\" #\'))
        (call-with-output-string
          (lambda (port)
            (string-for-each
             (lambda (c)
               (case c
                 ((#\&) (display "&amp;" port))
                 ((#\<) (display "&lt;" port))
                 ((#\>) (display "&gt;" port))
                 ((#\") (display "&quot;" port))
                 ((#\') (display "&#39;" port))
                 (else (write-char c port))))
             s)))
        s)))

(define (blank? x)
  (or (not x) (unspecified? x) (null? x)
      (and (string? x) (string-null? (string-trim-both x)))))

(define (present? x) (not (blank? x)))

(define (nullable x)
  "Map Scheme falsiness and blank strings to SQL NULL for DB-query #:params."
  (if (blank? x) '() x))

(define (strip x) (string-trim-both (->str x)))

(define (clamp-string s n)
  (let ((s (->str s)))
    (if (> (string-length s) n) (substring s 0 n) s)))

(define (string-count-words s)
  (length (filter (lambda (w) (not (string-null? w)))
                  (string-split (->str s) #\space))))

(define (url-encode s)
  (uri-encode (->str s)))

;; ------------------------------------------------------------------ crypto-ish

(define (random-bytes n)
  (call-with-input-file "/dev/urandom"
    (lambda (port) (get-bytevector-n port n))
    #:binary #t))

(define (bv->hex bv)
  (string-concatenate
   (map (lambda (b) (string-pad (number->string b 16) 2 #\0))
        (bytevector->u8-list bv))))

(define* (random-token #:optional (nbytes 32))
  "A URL-safe random token from the kernel CSPRNG, as lowercase hex."
  (bv->hex (random-bytes nbytes)))

(define (sha256-hex s)
  "SHA-256 of a string, as lowercase hex. Uses coreutils' sha256sum-compatible
NSS binding from Artanis when loaded inside the server, so it is resolved lazily."
  ((module-ref (resolve-interface '(artanis security hash)) 'string->sha-256) s))

(define (constant-time=? a b)
  (and (string? a) (string? b)
       (= (string-length a) (string-length b))
       (zero? (fold (lambda (x y acc) (logior acc (logxor (char->integer x) (char->integer y))))
                    0 (string->list a) (string->list b)))))

;; ------------------------------------------------------------------ urls & names

(define (slugify s)
  (let* ((s (string-downcase (->str s)))
         (s (regexp-substitute/global #f "[^a-z0-9]+" s 'pre "-" 'post))
         (s (string-trim-both s #\-)))
    (clamp-string (if (string-null? s) "untitled" s) 80)))

(define (http-url? s)
  (let ((u (and (string? s) (string->uri (string-trim-both s)))))
    (and u (memq (uri-scheme u) '(http https)) (uri-host u)
         (not (string-null? (uri-host u))) #t)))

(define (normalize-url s)
  "A key for spotting the same link sent twice: scheme-less, lower-case host
without www., no fragment, no trailing slash, tracking parameters dropped."
  (let ((u (string->uri (string-trim-both (->str s)))))
    (if (not u)
        (string-downcase (string-trim-both (->str s)))
        (let* ((host (string-downcase (or (uri-host u) "")))
               (host (if (string-prefix? "www." host) (substring host 4) host))
               (path (string-trim-right (or (uri-path u) "") #\/))
               (query (uri-query u))
               (kept (and query
                          (filter (lambda (kv)
                                    (not (or (string-prefix? "utm_" kv)
                                             (string-prefix? "ref=" kv)
                                             (string-prefix? "fbclid=" kv)
                                             (string-prefix? "gclid=" kv))))
                                  (string-split query #\&)))))
          (string-append host path
                         (if (and kept (pair? kept))
                             (string-append "?" (string-join (sort kept string<?) "&"))
                             ""))))))

(define (safe-next s)
  "Only same-site absolute paths are allowed as a post-sign-in destination."
  (let ((s (->str s)))
    (if (and (string-prefix? "/" s)
             (not (string-prefix? "//" s))
             (not (string-index s #\\))
             (not (string-index s (char-set #\newline #\return)))
             (< (string-length s) 512))
        s
        "/")))

(define *email-re* (make-regexp "^[^@[:space:]<>\"]+@[^@[:space:]<>\"]+\\.[^@[:space:]<>\".]+$"))
(define (valid-email? s)
  (and (string? s) (< (string-length s) 255) (regexp-exec *email-re* s) #t))

(define *handle-re* (make-regexp "^[A-Za-z][A-Za-z0-9_]{1,23}$"))
(define (valid-handle? s)
  (and (string? s) (regexp-exec *handle-re* s) #t))

(define *reserved*
  '("admin" "administrator" "root" "author" "roy" "roytalk" "staff" "support"
    "help" "moderator" "mod" "system" "api" "me" "anonymous" "null" "undefined"
    "official" "team" "security" "abuse" "postmaster" "webmaster" "noreply"
    "editor" "everyone" "here"))
(define (reserved-handle? s)
  (and (member (string-downcase (->str s)) *reserved*) #t))

;; ------------------------------------------------------------------ plain text -> html

(define (paragraphs->html s)
  "Readers' text: escaped, blank lines become paragraphs, single newlines <br>,
@handles are marked up (not linked: there are no public profiles),
bare http(s) links become rel=nofollow ugc links."
  (define (inline line)
    (let* ((escaped (h line))
           (linked (regexp-substitute/global
                    #f "https?://[^[:space:]<>&\"']+[^[:space:]<>&\"'.,;:!?)]" escaped
                    'pre (lambda (m)
                           (let ((u (match:substring m)))
                             (string-append "<a href=\"" u "\" rel=\"nofollow ugc noopener\">" u "</a>")))
                    'post)))
      (regexp-substitute/global
       #f "(^|[^A-Za-z0-9_/])@([A-Za-z][A-Za-z0-9_]{1,23})" linked
       'pre 1 (lambda (m) (string-append "<span class=\"mention\">@" (match:substring m 2) "</span>")) 'post)))
  (let* ((text (regexp-substitute/global #f "\r\n?" (->str s) 'pre "\n" 'post))
         (paras (filter (lambda (p) (not (string-null? (string-trim-both p))))
                        (regexp-split "\n[ \t]*\n" text))))
    (string-concatenate
     (map (lambda (p)
            (string-append "<p>" (string-join (map inline (string-split (string-trim-both p) #\newline)) "<br>") "</p>"))
          paras))))

(define (regexp-split re s)
  (let lp ((start 0) (acc '()))
    (let ((m (string-match re s start)))
      (if m
          (lp (match:end m) (cons (substring s start (match:start m)) acc))
          (reverse (cons (substring s start) acc))))))

(define* (excerpt s #:optional (n 180))
  (let ((s (string-trim-both (->str s))))
    (if (<= (string-length s) n)
        s
        (let* ((cut (substring s 0 n))
               (sp (string-rindex cut #\space)))
          (string-append (if sp (substring cut 0 sp) cut) "…")))))
