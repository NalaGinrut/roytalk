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
;;    letter   the monthly digest, queued by tools/digest.scm
;;
;;  Readers' addresses only ever appear as the recipient: nothing a reader
;;  typed is put in a subject or a header.

(define-module (roytalk mail)
  #:use-module (roytalk settings)
  #:use-module (roytalk letter)
  #:use-module (app models outbox)
  #:export (queue-mail!
            mail-login-link!
            mail-confirm-subscription!
            mail-welcome!))

(define* (queue-mail! x to subject text #:key (html #f) (headers "") (stream "account"))
  (enqueue-mail! x to subject text #:html html #:headers headers #:stream stream))

(define* (queue-rendered! x to feature vars #:key (raw '()) (stream "account")
                          (leave-url #f))
  (call-with-values
      (lambda () (render-letter-mail feature vars #:raw raw #:leave-url leave-url))
    (lambda (subject html text headers)
      (queue-mail! x to subject text #:html html #:headers headers #:stream stream))))

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
