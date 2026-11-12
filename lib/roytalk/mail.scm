;;  roytalk -- outgoing mail.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  The web process never talks SMTP. It renders the message from the
;;  templates in sys/mails/ and queues it in `outbox'; tools/mailer.scm (a
;;  separate process) sends it through msmtp.
;;
;;  Two streams, sent from different addresses and SES configuration sets
;;  (see prv/settings.example.scm):
;;    account  sign-in links, letter confirmation, welcome
;;    letter   the newsletter
;;
;;  Readers' addresses only ever appear as the recipient: nothing a reader
;;  typed is put in a subject or a header.

(define-module (roytalk mail)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:use-module (roytalk db)
  #:use-module (roytalk mailtpl)
  #:use-module (app models outbox)
  #:use-module (app models subscribers)
  #:export (queue-mail!
            mail-login-link!
            mail-confirm-subscription!
            mail-welcome!
            queue-letter!
            letter-excerpt))

(define* (queue-mail! x to subject text #:key (html #f) (headers "") (stream "account"))
  (enqueue-mail! x to subject text #:html html #:headers headers #:stream stream))

(define* (queue-rendered! x to feature vars #:key (raw '()) (stream "account")
                          (leave-url #f))
  ;; Mail to letter subscribers carries the one-click way out, in the footer
  ;; and in the List-Unsubscribe headers (RFC 2369, RFC 8058).
  (let ((footer-html (if leave-url
                         (string-append
                          "<p style=\"margin:0 0 10px;\">You receive this because you subscribed to the letter. "
                          "<a href=\"" (h leave-url) "\" style=\"color:#4A524C;\">Leave the list</a> with one click.</p>\n")
                         ""))
        (footer-text (if leave-url
                         (string-append "You receive this because you subscribed to the letter.\n"
                                        "Leave the list with one click: " leave-url "\n\n")
                         ""))
        (headers (if leave-url
                     (string-append "List-Unsubscribe: <" leave-url ">\n"
                                    "List-Unsubscribe-Post: List-Unsubscribe=One-Click")
                     "")))
    (call-with-values
        (lambda () (render-mail feature vars #:raw raw
                                #:footer-html footer-html #:footer-text footer-text))
      (lambda (subject html text)
        (queue-mail! x to subject text #:html html #:headers headers #:stream stream)))))

(define (leave-url token) (absolute-url (string-append "/letter/leave/" token)))

;; ------------------------------------------------------------------ account stream

(define (mail-login-link! x email token)
  (queue-rendered! x email "signin"
                   `(("link" . ,(absolute-url (string-append "/signin/email/" token))))))

(define (mail-confirm-subscription! x email token)
  (queue-rendered! x email "confirm"
                   `(("link" . ,(absolute-url (string-append "/letter/confirm/" token))))))

(define (mail-welcome! x email token)
  (queue-rendered! x email "welcome"
                   `(("archive_url" . ,(absolute-url "/archive"))
                     ("principles_url" . ,(absolute-url "/principles")))
                   #:leave-url (leave-url token)))

;; ------------------------------------------------------------------ the letter

(define *excerpt-words* 220)

(define (strip-tags s)
  (let* ((s (regexp-substitute/global #f "<[^>]*>" s 'pre "" 'post))
         (s (regexp-substitute/global #f "&nbsp;|&#160;" s 'pre " " 'post))
         (s (regexp-substitute/global #f "&lt;" s 'pre "<" 'post))
         (s (regexp-substitute/global #f "&gt;" s 'pre ">" 'post))
         (s (regexp-substitute/global #f "&quot;" s 'pre "\"" 'post))
         (s (regexp-substitute/global #f "&#39;" s 'pre "'" 'post))
         (s (regexp-substitute/global #f "&amp;" s 'pre "&" 'post)))
    s))

(define *tex-re* (make-regexp "<annotation encoding=\"application/x-tex\">([^<]*)</annotation>"))

(define (inline-math->tex p)
  ;; Mail clients do not render MathML; show the TeX source instead.
  (let lp ((i 0) (out '()))
    (let ((open (string-contains p "<math" i)))
      (if (not open)
          (string-concatenate (reverse (cons (substring p i) out)))
          (let* ((close (string-contains p "</math>" open))
                 (end (if close (+ close 7) (string-length p)))
                 (m (regexp-exec *tex-re* (substring p open end))))
            (lp end (cons (if m (string-append "<code>" (match:substring m 1) "</code>") "")
                          (cons (substring p i open) out))))))))

(define (style-inline p)
  (let* ((p (inline-math->tex p))
         (p (regexp-substitute/global #f "<a href=" p 'pre "<a style=\"color:#1E3F30;\" href=" 'post))
         (p (regexp-substitute/global #f "<code>" p 'pre
                                      "<code style=\"font-family:Menlo,Consolas,monospace;font-size:14px;background:#EAE6DA;padding:1px 4px;\">"
                                      'post)))
    p))

(define (letter-excerpt body-html)
  "The opening of an essay for the letter: its leading paragraphs, up to the
first heading, code block, formula, figure or list, and about 220 words.
Returns (html . text)."
  (let lp ((lines (string-split (->str body-html) #\newline)) (paras '()) (words 0))
    (let ((done (lambda ()
                  (let ((ps (reverse paras)))
                    (cons (string-concatenate
                           (map (lambda (p)
                                  (string-append "<p style=\"margin:0 0 18px;\">"
                                                 (style-inline p) "</p>\n"))
                                ps))
                          (string-join (map (lambda (p) (string-trim-both (strip-tags (inline-math->tex p)))) ps)
                                       "\n\n"))))))
      (cond
       ((or (null? lines) (>= words *excerpt-words*)) (done))
       (else
        (let ((line (string-trim-both (car lines))))
          (cond
           ((string-null? line) (lp (cdr lines) paras words))
           ((and (string-prefix? "<p>" line) (string-suffix? "</p>" line)
                 (not (string-contains line "<math display=\"block\"")))
            (let ((inner (substring line 3 (- (string-length line) 4))))
              (lp (cdr lines) (cons inner paras)
                  (+ words (string-count-words (strip-tags inner))))))
           (else (done)))))))))

(define (queue-letter! x post)
  "Queue the letter for POST (an alist from post-by-id) to every active
subscriber. Returns the number queued."
  (let* ((url (absolute-url (string-append "/posts/" (row-ref post "slug"))))
         (excerpt (letter-excerpt (row-ref post "body_html")))
         (tags (or (row-ref post "tags") '()))
         (eyebrow (string-join (cons (->str (row-ref post "date_long")) tags) " · "))
         (dek (->str (row-ref post "dek")))
         (vars `(("title" . ,(row-ref post "title"))
                 ("dek" . ,dek)
                 ("eyebrow" . ,eyebrow)
                 ("url" . ,url)
                 ("excerpt_text" . ,(cdr excerpt))))
         (raw `(("excerpt" . ,(car excerpt))
                ("dek_html" . ,(if (string-null? dek)
                                   ""
                                   (string-append
                                    "<p style=\"margin:0;font-family:Georgia,'Times New Roman',serif;font-style:italic;font-size:20px;line-height:1.45;color:#2C3530;\">"
                                    (h dek) "</p>")))))
         (subscribers (active-subscribers x)))
    (for-each
     (lambda (s)
       (queue-rendered! x (row-ref s "email") "letter" vars
                        #:raw raw #:stream "letter"
                        #:leave-url (leave-url (row-ref s "token"))))
     subscribers)
    (length subscribers)))
