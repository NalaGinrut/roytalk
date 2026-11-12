;; Controller submit of roytalk: readers send in links for the author to read.
;; The queue is private; readers only see their own submissions and whether
;; one was used.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller submit) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (roytalk util) (roytalk settings) (roytalk db) (roytalk web)
             (app models submissions) (roytalk views) (roytalk auth))

(define *min-note* 20)

(define (submit-page rc acc url note error-message done? status)
  ;; A procedure, not a macro: the template sees these parameters by name.
  (let* ((page-title (string-append "Submit a link · " (site-name)))
         (page-desc "Send in a paper or a post worth an opinion.")
         (canonical (absolute-url "/submit"))
         (csrf (if acc (csrf-token rc) "")))
    (render "submit/form" (the-environment) #:status status #:headers (private-cache))))

(get "/submit"
  (lambda (rc)
    (let ((acc (current-account rc)))
      (if (and acc (not (account-handle acc)))
          (redirect "/welcome?next=/submit")
          (let ((url (or (query-ref rc "url") ""))
                (note ""))
            (submit-page rc acc url note #f #f 200))))))

(post "/submit"
  #:rate-limit `(,(lambda (rc) (client-ip rc)) 20 3600)
  (lambda (rc)
    (let* ((form (form-params rc))
           (acc (current-account rc))
           (url (strip (clamp-string (form-ref form "url" "") 2000)))
           (note (strip (clamp-string (form-ref form "note" "") 2000))))
      (cond
       ((not acc) (redirect "/signin?next=/submit"))
       ((not (csrf-ok? rc form)) (forbidden!))
       ((row-ref acc "banned") (forbidden!))
       ((not (http-url? url))
        (submit-page rc acc url note "Please give a full http:// or https:// address." #f 422))
       ((< (string-length note) *min-note*)
        (submit-page rc acc url note "Please add a line on why it is worth reading, or what you want to know about it." #f 422))
       ((>= (submission-count-since rc (account-id acc) 24) 20)
        (submit-page rc acc url note "That is plenty for one day. Thank you; please send more tomorrow." #f 429))
       (else
        (submit-link! rc (account-id acc) url (normalize-url url) note)
        (submit-page rc acc "" "" #f #t 200))))))
