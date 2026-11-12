;;  roytalk -- sponsors model: the two quiet sponsor slots.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 sponsors
 (:deps)
 (slot text (#:primary-key))
 (name text (#:not-null))
 (line text (#:not-null))
 (url text (#:not-null))
 (active boolean (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (srfi srfi-45)  ; delay, for FPRM conditions
        (artanis ssql)  ; where
        (roytalk util)
        (roytalk db))

(define-public (sponsor-for x slot)
  (let ((rows (model-conn x
               (lambda ()
                 ($sponsors 'get #:columns '(name line url)
                            #:condition (delay (where #:slot slot
                                                      #:active "true")))))))
    (let lp ((rest rows))
      (cond
       ((null? rest) #f)
       ((present? (row-ref (car rest) "name")) (car rest))
       (else (lp (cdr rest)))))))

(define-public (admin-sponsors x)
  (model-conn x
   (lambda ()
     ($sponsors 'get #:columns '(slot name line url active)
                #:order-by '(slot desc)))))

(define-public (update-sponsor! x slot name line url active?)
  (model-set! x $sponsors
              #:name name
              #:line line
              #:url url
              #:active (if active? "true" "false")
              (delay (where #:slot slot)))
  #t)
