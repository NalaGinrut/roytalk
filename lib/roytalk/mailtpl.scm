;;  roytalk -- file-backed mail templates.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Same layout as NekoSense's (ashpool mail template):
;;
;;    sys/mails/base.html            the HTML shell every mail shares
;;    sys/mails/base.txt             the plain-text shell
;;    sys/mails/<feature>/en.html    the HTML body, with front matter
;;    sys/mails/<feature>/en.txt     the plain-text body
;;
;;  Front matter (en.html only):
;;
;;    ---
;;    subject: Sign in to {{site_name}}
;;    preheader: One link, valid for twenty minutes.
;;    button: Sign in
;;    button-url: {{link}}
;;    ---
;;
;;  {{name}} placeholders take values from the caller. In HTML they are
;;  escaped, except names given as raw (markup built by our own code, e.g. the
;;  essay excerpt). In text and in the subject they are inserted as they are,
;;  with line breaks removed from header fields. An unknown placeholder is an
;;  error: a typo must fail loudly instead of mailing blanks.
;;
;;  Every mail goes out as multipart/alternative, HTML and text.

(define-module (roytalk mailtpl)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:export (render-mail
            mail-root))

(define (mail-root)
  (or (getenv "ROYTALK_MAIL_ROOT")
      (string-append (getcwd) "/sys/mails")))

(define (read-file path)
  (call-with-input-file path
    (lambda (p) (set-port-encoding! p "UTF-8") (get-string-all p))))

(define (template-error fmt . args)
  (throw 'mail-template-error (apply format #f fmt args)))

(define *feature-re* (make-regexp "^[a-z][a-z0-9-]*$"))

(define (feature-file feature ext)
  (unless (regexp-exec *feature-re* feature)
    (template-error "bad feature name ~s" feature))
  (let ((f (string-append (mail-root) "/" feature "/en." ext)))
    (unless (file-exists? f) (template-error "missing template ~a" f))
    f))

;; ------------------------------------------------------------------ front matter

(define (parse-front-matter s)
  "(header-alist . body)"
  (let ((lines (string-split s #\newline)))
    (if (not (and (pair? lines) (string=? (string-trim-both (car lines)) "---")))
        (cons '() s)
        (let lp ((rest (cdr lines)) (acc '()))
          (cond
           ((null? rest) (template-error "front matter is never closed"))
           ((string=? (string-trim-both (car rest)) "---")
            (cons (reverse acc) (string-join (cdr rest) "\n")))
           ((string-null? (string-trim-both (car rest))) (lp (cdr rest) acc))
           (else
            (let* ((line (car rest))
                   (i (string-index line #\:)))
              (unless i (template-error "bad front matter line ~s" line))
              (lp (cdr rest)
                  (acons (string-trim-both (substring line 0 i))
                         (string-trim-both (substring line (1+ i)))
                         acc)))))))))

;; ------------------------------------------------------------------ placeholders

(define *name-re* (make-regexp "^[a-z][a-z0-9_]*$"))

(define (substitute s resolve)
  (let lp ((i 0) (out '()))
    (let ((open (string-contains s "{{" i)))
      (if (not open)
          (string-concatenate (reverse (cons (substring s i) out)))
          (let ((close (string-contains s "}}" (+ open 2))))
            (unless close (template-error "unterminated placeholder"))
            (let ((name (string-trim-both (substring s (+ open 2) close))))
              (unless (regexp-exec *name-re* name)
                (template-error "bad placeholder name ~s" name))
              (let ((v (resolve name)))
                (unless (string? v) (template-error "no value for {{~a}}" name))
                (lp (+ close 2) (cons v (cons (substring s i open) out))))))))))

(define (one-line s)
  (list->string (filter (lambda (c) (not (memv c '(#\newline #\return)))) (string->list (->str s)))))

(define (lookup vars name)
  (let ((v (assoc-ref vars name)))
    (and v (->str v))))

(define (html-resolver vars raw)
  (lambda (name)
    (or (lookup raw name)
        (let ((v (lookup vars name))) (and v (h v))))))

(define (text-resolver vars)
  (lambda (name) (lookup vars name)))

(define (plain-resolver vars)
  (lambda (name) (let ((v (lookup vars name))) (and v (one-line v)))))

;; ------------------------------------------------------------------ shell pieces

(define (button-html text url)
  (if (and (present? text) (present? url))
      (string-append
       "<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"margin:32px 0 0;\"><tr>"
       "<td bgcolor=\"#1E3F30\" style=\"background:#1E3F30;\">"
       "<a href=\"" (h url) "\" style=\"display:inline-block;padding:14px 26px;"
       "font-family:Georgia,'Times New Roman',serif;font-size:12px;font-weight:bold;"
       "letter-spacing:2px;text-transform:uppercase;color:#F3F0E8;text-decoration:none;\">"
       (h text) "</a></td></tr></table>")
      ""))

(define (button-text text url)
  (if (and (present? text) (present? url))
      (string-append (one-line text) ":\n" (one-line url) "\n")
      ""))

;; ------------------------------------------------------------------ render

(define* (render-mail feature vars #:key (raw '()) (footer-html "") (footer-text ""))
  "Render FEATURE with VARS (alist of name . value). RAW holds trusted HTML
values. FOOTER-* is an extra footer block (e.g. the letter's unsubscribe
line). Returns (values subject html text)."
  (let* ((common `(("site_name" . ,(site-name))
                   ("site_tagline" . ,(site-tagline))
                   ("site_url" . ,(absolute-url "/"))
                   ("site_host" . ,(host-name))
                   ("author_name" . ,(author-name))))
         (vars (append vars common))
         (parsed (parse-front-matter (read-file (feature-file feature "html"))))
         (field (lambda (k) (or (assoc-ref (car parsed) k) "")))
         (subject (substitute (field "subject") (plain-resolver vars)))
         (preheader (substitute (field "preheader") (plain-resolver vars)))
         (button (substitute (field "button") (plain-resolver vars)))
         (button-url (substitute (field "button-url") (plain-resolver vars)))
         (body-html (substitute (cdr parsed) (html-resolver vars raw)))
         (body-text (substitute (read-file (feature-file feature "txt")) (text-resolver vars)))
         (shell-vars (append `(("subject" . ,subject) ("preheader" . ,preheader)) vars))
         (shell-raw `(("content" . ,body-html)
                      ("button" . ,(button-html button button-url))
                      ("footer_extra" . ,footer-html)))
         (html (substitute (read-file (string-append (mail-root) "/base.html"))
                           (html-resolver shell-vars shell-raw)))
         (text (substitute (read-file (string-append (mail-root) "/base.txt"))
                           (text-resolver
                            (append `(("content" . ,(string-trim-both body-text))
                                      ("button" . ,(button-text button button-url))
                                      ("footer_extra" . ,footer-text))
                                    shell-vars)))))
    (values subject html text)))
