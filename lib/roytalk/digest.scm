;;  roytalk -- the monthly digest letter.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Pure: no database, no Artanis DB layer. tools/digest.scm reads the posts
;;  and subscribers with its own connection, then calls render-digest-mail
;;  once per subscriber so each copy carries that subscriber's unsubscribe
;;  link.
;;
;;  A post row is an alist keyed by column name, as guile-dbi returns it:
;;  title, slug, dek, body_html, date_long and tag_list (comma separated).

(define-module (roytalk digest)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:use-module (roytalk excerpt)
  #:use-module (roytalk letter)
  #:export (digest-item-html
            digest-item-text
            render-digest-mail))

(define *excerpt-words* 80)

(define (field row key)
  (let ((v (assoc-ref row key)))
    (if (string? v) v "")))

(define (tags-of row)
  (let ((tl (field row "tag_list")))
    (if (string-null? tl) '() (string-split tl #\,))))

(define (post-url row)
  (absolute-url (string-append "/posts/" (field row "slug"))))

(define (eyebrow row)
  (string-join (cons (field row "date_long") (tags-of row)) " · "))

;; ------------------------------------------------------------------ html

(define (digest-item-html row)
  (let* ((url (post-url row))
         (dek (field row "dek"))
         (excerpt (car (letter-excerpt (field row "body_html")
                                       #:max-words *excerpt-words*))))
    (string-append
     "<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" "
     "style=\"width:100%;margin:0 0 36px;\"><tr><td>\n"
     "<p style=\"margin:0 0 8px;font-family:Arial,Helvetica,sans-serif;font-size:11px;"
     "letter-spacing:1.5px;text-transform:uppercase;color:#6C736E;\">"
     (h (eyebrow row)) "</p>\n"
     "<h2 style=\"margin:0 0 10px;font-family:Georgia,'Times New Roman',serif;"
     "font-size:24px;font-weight:normal;line-height:1.25;\">"
     "<a href=\"" (h url) "\" style=\"color:#1E3F30;text-decoration:none;\">"
     (h (field row "title")) "</a></h2>\n"
     (if (string-null? dek) ""
         (string-append
          "<p style=\"margin:0 0 14px;font-family:Georgia,'Times New Roman',serif;"
          "font-style:italic;font-size:18px;line-height:1.45;color:#2C3530;\">"
          (h dek) "</p>\n"))
     excerpt
     "<p style=\"margin:14px 0 0;\">"
     "<a href=\"" (h url) "\" style=\"font-family:Arial,Helvetica,sans-serif;font-size:12px;"
     "letter-spacing:1px;text-transform:uppercase;color:#1E3F30;\">"
     "Read the whole piece</a></p>\n"
     "</td></tr></table>\n")))

;; ------------------------------------------------------------------ text

(define (digest-item-text row)
  (let* ((url (post-url row))
         (dek (field row "dek"))
         (excerpt (cdr (letter-excerpt (field row "body_html")
                                       #:max-words *excerpt-words*))))
    (string-append
     (eyebrow row) "\n"
     (field row "title") "\n"
     url "\n\n"
     (if (string-null? dek) "" (string-append dek "\n\n"))
     (if (string-null? excerpt) "" (string-append excerpt "\n\n"))
     "Read the whole piece: " url "\n")))

;; ------------------------------------------------------------------ mail

(define* (render-digest-mail posts #:key (leave-url #f))
  "Render the digest for POSTS (a list of rows, newest first). Returns
(values subject html text headers)."
  (let* ((count (length posts))
         (noun (if (= count 1) "piece" "pieces"))
         (items-html (string-concatenate (map digest-item-html posts)))
         (items-text (string-join (map digest-item-text posts) "\n----------\n\n"))
         (vars `(("count" . ,(number->string count))
                 ("noun" . ,noun)
                 ("archive_url" . ,(absolute-url "/archive"))
                 ("items_text" . ,items-text)))
         (raw `(("items" . ,items-html))))
    (render-letter-mail "digest" vars #:raw raw #:leave-url leave-url)))
