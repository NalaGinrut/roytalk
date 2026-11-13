;; Controller admin of roytalk: the author's desk.
;; Only accounts marked is_author (see author-emails in prv/settings.scm)
;; get in; everyone else gets a 404, so the desk does not advertise itself.
;; Copyright (C) 2026 Roy. GPLv3 or later.
(define-artanis-controller admin) ; DO NOT REMOVE THIS LINE!!!

(use-modules (srfi srfi-1)
             (ice-9 match)
             ((artanis runner) #:select (call-with-runner))
             (roytalk util) (roytalk settings) (roytalk db) (roytalk web)
             (app models posts) (app models submissions) (app models questions)
             (app models accounts) (app models tags) (app models sponsors)
             (app models subscribers) (app models outbox) (app models api_tokens)
             (app models digests)
             (roytalk views) (roytalk auth) (roytalk render))

(define (the-author rc)
  (let ((acc (current-account rc)))
    (unless (author? acc) (not-found!))
    acc))

(define (checked-form rc)
  (let ((form (form-params rc)))
    (unless (csrf-ok? rc form) (forbidden!))
    form))

(define (render-markdown md)
  (call-with-runner
   (lambda ()
     (call-with-values (lambda () (markdown->html md))
       (lambda (body toc) (cons body toc))))))

(define (parse-tags s)
  (delete-duplicates
   (filter present?
           (map (lambda (t) (clamp-string (string-downcase (strip t)) 40))
                (string-split (->str s) #\,)))))

;; ------------------------------------------------------------------ desk

(get "/admin"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "The desk")
           (page-desc "") (canonical (absolute-url "/admin")) (section "posts")
           (csrf (csrf-token rc))
           (posts (admin-posts rc))
           (new-links (new-links-count rc))
           (new-questions (new-question-count rc))
           (subscribers (active-subscriber-count rc)))
      (render "admin/index" (the-environment) #:headers (private-cache)))))

;; ------------------------------------------------------------------ writing

(define (editor-page rc post error-message)
  (let* ((acc (the-author rc))
         (page-title (if post (string-append "Edit · " (->str (row-ref post "title"))) "New piece"))
         (page-desc "") (canonical (absolute-url "/admin")) (section "posts")
         (csrf (csrf-token rc))
         (f (lambda (k) (->str (and post (row-ref post k)))))
         (tags-str (if post (string-join (or (row-ref post "tags") '()) ", ") ""))
         (submitted (or (and post (row-ref post "submitted_by_handle")) "")))
    (render "admin/edit" (the-environment) #:status (if error-message 422 200) #:headers (private-cache))))

(get "/admin/new"
  (lambda (rc) (editor-page rc #f #f)))

(get "/admin/posts/:id"
  (lambda (rc)
    (the-author rc)
    (let ((post (and (string->number (params rc "id")) (post-by-id rc (params rc "id")))))
      (unless post (not-found!))
      (editor-page rc post #f))))

(post "/admin/preview"
  (lambda (rc)
    (the-author rc)
    (let ((form (checked-form rc)))
      (let ((r (render-markdown (form-ref form "body_md" ""))))
        (emit-text (car r) #:type 'text/html #:headers (private-cache))))))

(define (save-editor-post! rc id form)
  "Insert or update from the editor form. Returns (values id error)."
  (let* ((title (strip (form-ref form "title" "")))
         (slug (slugify (let ((s (strip (form-ref form "slug" "")))) (if (string-null? s) title s))))
         (dek (strip (form-ref form "dek" "")))
         (md (form-ref form "body_md" ""))
         (source-url (strip (form-ref form "source_url" "")))
         (source-title (strip (form-ref form "source_title" "")))
         (by (strip (string-trim (form-ref form "submitted_by" "") #\@)))
         (by-id (and (present? by) (row-ref (account-by-handle rc by) "id")))
         (action (form-ref form "action" "save"))
         (clash (slug-clash? rc slug id)))
    (cond
     ((string-null? title) (values id "A title, please."))
     (clash (values id (string-append "Another piece already uses the address /posts/" slug)))
     ((and (present? source-url) (not (http-url? source-url))) (values id "The source must be an http(s) link."))
     ((and (present? by) (not by-id)) (values id (string-append "No reader is called @" by)))
     (else
      (let* ((r (render-markdown md))
             (id (save-post! rc #:id id #:slug slug #:title title #:dek dek
                             #:body-md md #:body-html (car r) #:toc-html (cdr r)
                             #:source-url source-url #:source-title source-title
                             #:submitted-by by-id
                             #:tags (parse-tags (form-ref form "tags" ""))
                             #:action action)))
        (values id #f))))))

(define (editor-post rc id)
  (the-author rc)
  (let ((form (checked-form rc)))
    (call-with-values (lambda () (save-editor-post! rc id form))
      (lambda (id err)
        (if err
            ;; Show the form again with what was typed.
            (editor-page rc
                         `(("id" . ,id) ("title" . ,(form-ref form "title" "")) ("slug" . ,(form-ref form "slug" ""))
                           ("dek" . ,(form-ref form "dek" "")) ("body_md" . ,(form-ref form "body_md" ""))
                           ("source_url" . ,(form-ref form "source_url" "")) ("source_title" . ,(form-ref form "source_title" ""))
                           ("submitted_by_handle" . ,(form-ref form "submitted_by" ""))
                           ("tags" . ,(parse-tags (form-ref form "tags" "")))
                           ("status" . ,(if id (post-status rc id) "draft")))
                         err)
            (redirect (format #f "/admin/posts/~a?saved=1" id)))))))

(post "/admin/posts" (lambda (rc) (editor-post rc #f)))

(post "/admin/posts/:id"
  (lambda (rc)
    (unless (string->number (params rc "id")) (not-found!))
    (editor-post rc (string->number (params rc "id")))))

(post "/admin/posts/:id/delete"
  (lambda (rc)
    (the-author rc)
    (checked-form rc)
    (delete-draft! rc (params rc "id"))
    (redirect "/admin")))

;; ------------------------------------------------------------------ inbox

(get "/admin/inbox"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "Inbox") (page-desc "") (canonical (absolute-url "/admin")) (section "inbox")
           (csrf (csrf-token rc))
           (show (if (equal? (query-ref rc "show") "all") "all" "new"))
           (groups (admin-inbox-groups rc show))
           (posts (post-options rc))
           (notes-of (lambda (g)
                       (let ((v ((@ (json) json-string->scm) (row-ref g "notes"))))
                         (if (vector? v) (vector->list v) '())))))
      (render "admin/inbox" (the-environment) #:headers (private-cache)))))

(post "/admin/inbox/use"
  (lambda (rc)
    (the-author rc)
    (let* ((form (checked-form rc))
           (norm (form-ref form "url_norm" ""))
           (post (post-by-id rc (or (string->number (form-ref form "post_id" "")) 0))))
      (when post
        (mark-submissions-used! rc norm (row-ref post "id")))
      (redirect "/admin/inbox"))))

(post "/admin/inbox/dismiss"
  (lambda (rc)
    (the-author rc)
    (let ((form (checked-form rc)))
      (dismiss-submissions! rc (form-ref form "url_norm" ""))
      (redirect "/admin/inbox"))))

;; ------------------------------------------------------------------ questions & readers

(get "/admin/questions"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "Questions") (page-desc "") (canonical (absolute-url "/admin")) (section "questions")
           (csrf (csrf-token rc))
           (merged-ok (query-ref rc "merged"))
           (merge-error (query-ref rc "merge_error"))
           (items (admin-question-rows rc)))
      (render "admin/questions" (the-environment) #:headers (private-cache)))))

;; The hide action is the desk's soft delete: readers stop seeing the question,
;; the author can restore it.
(post "/admin/questions/:id/hide"
  (lambda (rc)
    (the-author rc)
    (let ((form (checked-form rc)))
      (hide-question! rc (params rc "id")
                      (equal? (form-ref form "hidden" "1") "1"))
      (redirect (form-ref form "back" "/admin/questions")))))

;; Merge one question into another. One statement so the move is atomic:
;; replies follow the question they answer, and questions already merged into
;; the source point at the new target.
(post "/admin/questions/:id/merge"
  (lambda (rc)
    (the-author rc)
    (checked-form rc)
    (let* ((src-id (string->number (params rc "id")))
           (target-id (string->number (form-ref (form-params rc) "target" "")))
           (merged (and src-id target-id
                        (merge-questions! rc src-id target-id))))
      (redirect (if merged "/admin/questions?merged=1" "/admin/questions?merge_error=1")))))

(post "/admin/questions/:id/unmerge"
  (lambda (rc)
    (the-author rc)
    (checked-form rc)
    (let ((id (string->number (params rc "id"))))
      (when id
        (unmerge-question! rc id)))
    (redirect "/admin/questions")))

(get "/admin/readers"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "Readers") (page-desc "") (canonical (absolute-url "/admin")) (section "readers")
           (csrf (csrf-token rc))
           (items (admin-readers rc)))
      (render "admin/readers" (the-environment) #:headers (private-cache)))))

(post "/admin/readers/:id/ban"
  (lambda (rc)
    (let ((me (the-author rc)))
      (let* ((form (checked-form rc))
             (ban? (equal? (form-ref form "banned" "1") "1")))
        (unless (equal? (->str (account-id me)) (params rc "id"))
          (ban-account! rc (params rc "id") ban?))
        (redirect (form-ref form "back" "/admin/readers"))))))

;; ------------------------------------------------------------------ tags, sponsors, letter, tokens

(get "/admin/tags"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "Tags") (page-desc "") (canonical (absolute-url "/admin")) (section "tags")
           (csrf (csrf-token rc))
           (tags (admin-tags rc)))
      (render "admin/tags" (the-environment) #:headers (private-cache)))))

(post "/admin/tags/:id"
  (lambda (rc)
    (the-author rc)
    (let* ((form (checked-form rc))
           (name (clamp-string (string-downcase (strip (form-ref form "name" ""))) 40)))
      (cond
       ((equal? (form-ref form "action" "") "delete")
        (delete-tag! rc (params rc "id")))
       ((present? name)
        (unless (tag-name-taken? rc name (params rc "id"))
          (rename-tag! rc (params rc "id") name))))
      (redirect "/admin/tags"))))

(get "/admin/sponsors"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "Sponsors") (page-desc "") (canonical (absolute-url "/admin")) (section "sponsors")
           (csrf (csrf-token rc))
           (slots (admin-sponsors rc)))
      (render "admin/sponsors" (the-environment) #:headers (private-cache)))))

(post "/admin/sponsors/:slot"
  (lambda (rc)
    (the-author rc)
    (let ((form (checked-form rc))
          (url (strip (form-ref (form-params rc) "url" ""))))
      (update-sponsor! rc (params rc "slot")
                       (clamp-string (strip (form-ref form "name" "")) 80)
                       (clamp-string (strip (form-ref form "line" "")) 160)
                       (if (http-url? url) url "")
                       (equal? (form-ref form "active" "") "on"))
      (redirect "/admin/sponsors"))))

(get "/admin/letter"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "The letter") (page-desc "") (canonical (absolute-url "/admin")) (section "letter")
           (counts (subscriber-status-counts rc))
           (digest (last-digest rc))
           (outbox (outbox-stats rc)))
      (render "admin/letter" (the-environment) #:headers (private-cache)))))

(get "/admin/tokens"
  (lambda (rc)
    (let* ((acc (the-author rc))
           (page-title "API tokens") (page-desc "") (canonical (absolute-url "/admin")) (section "tokens")
           (csrf (csrf-token rc))
           (fresh #f)
           (tokens (admin-api-tokens rc)))
      (render "admin/tokens" (the-environment) #:headers (private-cache)))))

(post "/admin/tokens"
  (lambda (rc)
    (the-author rc)
    (let* ((form (checked-form rc))
           (name (clamp-string (strip (form-ref form "name" "")) 80))
           (tok (string-append "rt_" (random-token 32))))
      (create-api-token! rc (if (string-null? name) "unnamed" name) (sha256-hex tok))
      ;; Shown once, never stored in the clear.
      (let* ((acc (current-account rc))
             (page-title "API tokens") (page-desc "") (canonical (absolute-url "/admin")) (section "tokens")
             (csrf (csrf-token rc))
             (fresh tok)
             (tokens (admin-api-tokens rc)))
        (render "admin/tokens" (the-environment) #:headers (private-cache))))))

(post "/admin/tokens/:id/revoke"
  (lambda (rc)
    (the-author rc)
    (checked-form rc)
    (revoke-api-token! rc (params rc "id"))
    (redirect "/admin/tokens")))
