;;  roytalk -- subscriber mail: the one-click way out, shared by every letter.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Pure: no database, no Artanis DB layer. The web process (welcome mail and,
;;  before the digest existed, per-piece letters) and tools/digest.scm both
;;  use this, so the unsubscribe wording and the RFC 2369 / RFC 8058 headers
;;  are written in one place.

(define-module (roytalk letter)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:use-module (roytalk mailtpl)
  #:export (leave-url
            render-letter-mail))

(define (leave-url token)
  (absolute-url (string-append "/letter/leave/" token)))

(define* (render-letter-mail feature vars #:key (raw '()) (leave-url #f))
  "Render FEATURE and, when LEAVE-URL is given, add the unsubscribe footer and
the List-Unsubscribe headers. Returns (values subject html text headers)."
  (let ((footer-html (if leave-url
                         (string-append
                          "<p style=\"margin:0 0 10px;\">You receive this because you subscribed to the letter: one digest a month. "
                          "<a href=\"" (h leave-url) "\" style=\"color:#4A524C;\">Leave the list</a> with one click.</p>\n")
                         ""))
        (footer-text (if leave-url
                         (string-append "You receive this because you subscribed to the letter: one digest a month.\n"
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
        (values subject html text headers)))))
