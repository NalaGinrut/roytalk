;;  roytalk -- posts model: the essays, their dates, tags and counters.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Dates are formatted by PostgreSQL so templates only print strings:
;;    date_long  "9 November 2026"   date_short "9 Nov"   date_iso "2026-11-09"
;;
;;  The table is created by db/schema.sql; the declaration below mirrors its
;;  columns for Artanis' model layer. The generated tsvector, citext,
;;  timestamptz defaults and indexes stay in schema.sql.

(import (artanis mvc model))

(create-artanis-model
 posts
 (:deps post_tags)
 (id bigserial (#:primary-key))
 (slug text (#:not-null #:unique))
 (title text (#:not-null))
 (dek text (#:not-null))
 (body_md text (#:not-null))
 (body_html text (#:not-null))
 (toc_html text (#:not-null))
 (source_url text (#:null))
 (source_title text (#:null))
 (submitted_by bigint (#:null))
 (status text (#:not-null))
 (published_at timestamptz (#:null))
 (updated_at timestamptz (#:not-null))
 (created_at timestamptz (#:not-null))
 (views bigint (#:not-null))
 (emailed_at timestamptz (#:null))
 (search tsvector (#:null))) ; DO NOT REMOVE THIS LINE!!!

(import (ice-9 match)
        (roytalk util)
        (roytalk db)
        (app models post_tags))

(export post-columns
        with-tags
        published-posts
        post-by-slug
        post-by-id
        feed-posts
        admin-posts
        post-options
        post-status
        slug-clash?
        insert-post!
        update-post!
        save-post!
        publish-post!
        unpublish-post!
        delete-draft!
        mark-post-emailed!
        bump-post-views!
        archive-years
        search-posts)

(define post-columns
  "p.id, p.slug, p.title, p.dek, p.status, p.views, p.source_url, p.source_title,
   to_char(p.published_at, 'FMDD FMMonth YYYY') AS date_long,
   to_char(p.published_at, 'FMDD Mon') AS date_short,
   to_char(p.published_at, 'YYYY-MM-DD') AS date_iso,
   to_char(p.published_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS published_rfc3339,
   to_char(p.updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS updated_rfc3339,
   to_char(p.published_at, 'YYYY') AS year,
   (SELECT handle::text FROM accounts WHERE id = p.submitted_by) AS submitted_by_handle,
   (SELECT count(*) FROM questions q
     WHERE q.post_id = p.id AND q.parent_id IS NULL
       AND q.merged_into IS NULL AND NOT q.hidden) AS n_questions,
   (SELECT string_agg(t.name::text, ',' ORDER BY pt.position, t.name)
      FROM post_tags pt JOIN tags t ON t.id = pt.tag_id WHERE pt.post_id = p.id) AS tag_list")

(define (with-tags row)
  (let ((tl (row-ref row "tag_list")))
    (acons "tags" (if (present? tl) (string-split tl #\,) '()) row)))

(define* (published-posts x #:key (limit 50) (offset 0))
  (map with-tags
       (q x (string-append "SELECT " post-columns " FROM posts p
              WHERE p.status = 'published'
              ORDER BY p.published_at DESC LIMIT $1::int OFFSET $2::int")
          limit offset)))

(define* (post-by-slug x slug #:key (drafts? #f))
  (let ((row (q1 x (string-append "SELECT " post-columns ", p.body_html, p.toc_html, p.body_md
                     FROM posts p WHERE p.slug = $1"
                     (if drafts? "" " AND p.status = 'published'"))
                 slug)))
    (and row (with-tags row))))

(define (post-by-id x id)
  (let ((row (q1 x (string-append "SELECT " post-columns ", p.body_md, p.body_html, p.toc_html,
                     p.submitted_by, to_char(p.emailed_at, 'FMDD Mon YYYY') AS emailed
                     FROM posts p WHERE p.id = $1::bigint") id)))
    (and row (with-tags row))))

(define (feed-posts x limit)
  (q x (string-append "SELECT " post-columns ", p.body_html FROM posts p
                       WHERE p.status = 'published'
                       ORDER BY p.published_at DESC LIMIT $1::int") limit))

(define (admin-posts x)
  (map with-tags
       (q x (string-append "SELECT " post-columns ",
                to_char(p.updated_at, 'FMDD Mon YYYY') AS updated_short,
                to_char(p.emailed_at, 'FMDD Mon') AS emailed
              FROM posts p
             ORDER BY (p.status = 'draft') DESC, p.published_at DESC NULLS FIRST, p.updated_at DESC"))))

(define (post-options x)
  (q x "SELECT id, title FROM posts ORDER BY published_at DESC NULLS FIRST LIMIT 200"))

(define (post-status x id)
  (qval x "SELECT status FROM posts WHERE id = $1::bigint" id))

(define (slug-clash? x slug id)
  "The id of another post that uses SLUG, or #f."
  (qval x "SELECT id FROM posts
            WHERE slug = $1 AND ($2::bigint IS NULL OR id <> $2::bigint)" slug id))

(define (insert-post! x slug title)
  (qval x "INSERT INTO posts (slug, title) VALUES ($1, $2) RETURNING id" slug title))

(define* (update-post! x id #:key slug title dek body-md body-html toc-html
                       source-url source-title submitted-by)
  (q! x "UPDATE posts SET slug = $2, title = $3, dek = $4, body_md = $5,
                body_html = $6, toc_html = $7, source_url = $8,
                source_title = $9, submitted_by = $10::bigint, updated_at = now()
          WHERE id = $1::bigint"
      id slug title dek body-md body-html toc-html
      (nullable source-url) (nullable source-title) submitted-by))

(define* (save-post! x #:key id slug title dek body-md body-html toc-html
                     source-url source-title submitted-by tags (action "save"))
  "Insert or update a piece and its tags in one transaction. Validation and
markdown rendering happen in the controller; this only writes."
  (with-tx
   (lambda ()
     (let ((id (or id (insert-post! x slug title))))
       (update-post! x id #:slug slug #:title title #:dek dek
                     #:body-md body-md #:body-html body-html #:toc-html toc-html
                     #:source-url source-url #:source-title source-title
                     #:submitted-by submitted-by)
       (set-post-tags! x id tags)
       (cond
        ((equal? action "publish") (publish-post! x id))
        ((equal? action "unpublish") (unpublish-post! x id))
        (else #t))
       id))))

(define (publish-post! x id)
  (q! x "UPDATE posts SET status = 'published', published_at = coalesce(published_at, now())
          WHERE id = $1::bigint" id))

(define (unpublish-post! x id)
  (q! x "UPDATE posts SET status = 'draft' WHERE id = $1::bigint" id))

(define (delete-draft! x id)
  (q! x "DELETE FROM posts WHERE id = $1::bigint AND status = 'draft'" id))

(define (mark-post-emailed! x id)
  (q! x "UPDATE posts SET emailed_at = now() WHERE id = $1::bigint" id))

(define (bump-post-views! x slug)
  (q! x "UPDATE posts SET views = views + 1 WHERE slug = $1 AND status = 'published'" slug))

(define (archive-years x)
  "((\"2026\" post ...) ...), newest first."
  (let ((posts (published-posts x #:limit 10000)))
    (let lp ((ps posts) (acc '()))
      (match ps
        (() (reverse (map (lambda (g) (cons (car g) (reverse (cdr g)))) acc)))
        ((p . rest)
         (let ((y (row-ref p "year")))
           (if (and (pair? acc) (equal? (caar acc) y))
               (lp rest (cons (cons y (cons p (cdar acc))) (cdr acc)))
               (lp rest (cons (list y p) acc)))))))))

(define (search-posts x terms)
  (map with-tags
       (q x (string-append "SELECT " post-columns ",
                ts_headline('english', p.body_md, websearch_to_tsquery('english', $1),
                            'MaxWords=30, MinWords=12, StartSel=<mark>, StopSel=</mark>') AS snippet
              FROM posts p
              WHERE p.status = 'published' AND p.search @@ websearch_to_tsquery('english', $1)
              ORDER BY ts_rank(p.search, websearch_to_tsquery('english', $1)) DESC
              LIMIT 50") terms)))
