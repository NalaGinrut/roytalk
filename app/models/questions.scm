;;  roytalk -- questions model: questions, replies and merges on a post.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  A question has parent_id NULL; a reply has parent_id = the question's id.
;;  Threads are two levels deep. A merged question is folded into the question
;;  it points at (merged_into), which lists the other askers.
;;
;;  The table is created by db/schema.sql; the declaration below mirrors its
;;  columns for Artanis' model layer. Foreign keys, partial indexes and the
;;  merge CHECK stay in schema.sql.

(import (artanis mvc model))

;; NOTE: Artanis' macro passes (:deps ...) to process-use-modules as one
;; nested list, which only works for a single dependency. Keep it to one.
(create-artanis-model
 questions
 (:deps posts)
 (id bigserial (#:primary-key))
 (post_id bigint (#:not-null))
 (account_id bigint (#:not-null))
 (parent_id bigint (#:null))
 (reply_to bigint (#:null))
 (quote_exact text (#:null))
 (quote_prefix text (#:null))
 (quote_suffix text (#:null))
 (body text (#:not-null))
 (hidden boolean (#:not-null))
 (created_at timestamptz (#:not-null))
 (merged_into bigint (#:null))) ; DO NOT REMOVE THIS LINE!!!

(import (srfi srfi-1)
        (roytalk util)
        (roytalk db))

(export questions-for-post
        question-count
        question-with-post
        question-redirect
        account-questions
        create-question!
        create-reply!
        hourly-question-count
        account-question-count
        new-question-count
        admin-question-candidates
        admin-question-rows
        hide-question!
        merge-questions!
        unmerge-question!
        api-questions)

(define (asker-handles s)
  (if (present? s)
      (filter present? (string-split s #\,))
      '()))

(define (with-askers row)
  "Attach the handles merged into ROW, as a list, and the total asker count."
  (let ((others (asker-handles (row-ref row "other_handles"))))
    (acons "other_askers" others
           (acons "askers" (1+ (length others)) row))))

(define (questions-for-post x post-id include-hidden?)
  "Questions with their replies nested under \"replies\", oldest first.
Merged questions are folded into the question they point at: its
\"other_askers\" key lists their readers and \"askers\" counts everyone."
  (let* ((rows (q x "SELECT q.id, q.parent_id, q.body, q.hidden, q.quote_exact, q.quote_prefix, q.quote_suffix,
                            a.handle::text AS handle, a.is_author, a.id AS account_id,
                            (SELECT handle::text FROM accounts WHERE id = q.reply_to) AS reply_to_handle,
                            to_char(q.created_at, 'FMDD FMMonth') AS date_long,
                            to_char(q.created_at, 'YYYY-MM-DD') AS date_iso,
                            s.other_handles
                       FROM questions q JOIN accounts a ON a.id = q.account_id
                       LEFT JOIN LATERAL (
                         SELECT string_agg(m.handle, ',' ORDER BY m.first_seen) AS other_handles
                           FROM (SELECT ma.handle::text AS handle, min(mq.created_at) AS first_seen
                                   FROM questions mq JOIN accounts ma ON ma.id = mq.account_id
                                  WHERE q.parent_id IS NULL
                                    AND mq.merged_into = q.id
                                    AND mq.account_id <> q.account_id
                                    AND ($2::boolean OR NOT mq.hidden)
                                  GROUP BY ma.handle) m) s ON TRUE
                      WHERE q.post_id = $1::bigint AND ($2::boolean OR NOT q.hidden)
                        AND (q.parent_id IS NOT NULL OR q.merged_into IS NULL)
                      ORDER BY q.created_at, q.id"
                  post-id (if include-hidden? #t "false")))
         (tops (filter (lambda (r) (not (row-ref r "parent_id"))) rows)))
    (map (lambda (t)
           (with-askers
            (acons "replies"
                   (filter (lambda (r) (equal? (row-ref r "parent_id") (row-ref t "id"))) rows)
                   t)))
         tops)))

(define (question-count x post-id)
  (or (qval x "SELECT count(*) FROM questions
                WHERE post_id = $1::bigint AND parent_id IS NULL
                  AND merged_into IS NULL AND NOT hidden" post-id) 0))

(define (question-with-post x id)
  (q1 x "SELECT q.id, q.post_id, q.parent_id, q.merged_into,
                coalesce(q.merged_into, q.id) AS root_id,
                q.body, q.quote_exact, q.hidden, q.account_id,
                a.handle::text AS handle, p.slug, p.title
           FROM questions q JOIN accounts a ON a.id = q.account_id
           JOIN posts p ON p.id = q.post_id AND p.status = 'published'
          WHERE q.id = $1::bigint" id))

(define (question-redirect x id)
  (q1 x "SELECT p.slug, coalesce(q.merged_into, q.id) AS root_id
           FROM questions q JOIN posts p ON p.id = q.post_id
          WHERE q.id = $1::bigint AND p.status = 'published' AND NOT q.hidden
            AND NOT EXISTS (SELECT 1 FROM questions t
                             WHERE t.id = q.merged_into AND t.hidden)" id))

(define (account-questions x account-id)
  (q x "SELECT q.id, coalesce(q.merged_into, q.id) AS link_id,
               q.merged_into IS NOT NULL AS merged,
               q.body, q.parent_id, q.hidden, p.slug, p.title,
               to_char(q.created_at, 'FMDD Mon YYYY') AS date_long
          FROM questions q JOIN posts p ON p.id = q.post_id
         WHERE q.account_id = $1::bigint ORDER BY q.created_at DESC LIMIT 200" account-id))

(define (create-question! x post-id account-id exact prefix suffix body)
  (qval x "INSERT INTO questions (post_id, account_id, quote_exact, quote_prefix, quote_suffix, body)
           VALUES ($1::bigint, $2::bigint, $3, $4, $5, $6) RETURNING id"
        post-id account-id (nullable exact) (nullable prefix) (nullable suffix) body))

(define (create-reply! x post-id account-id parent-id reply-to body)
  (qval x "INSERT INTO questions (post_id, account_id, parent_id, reply_to, body)
           VALUES ($1::bigint, $2::bigint, $3::bigint, $4::bigint, $5) RETURNING id"
        post-id account-id parent-id reply-to body))

(define (hourly-question-count x account-id)
  (or (qval x "SELECT count(*) FROM questions WHERE account_id = $1::bigint
                AND created_at > now() - interval '1 hour'" account-id) 0))

(define (account-question-count x account-id)
  (or (qval x "SELECT count(*) FROM questions WHERE account_id = $1::bigint" account-id) 0))

(define (new-question-count x)
  (or (qval x "SELECT count(*) FROM questions
                WHERE created_at > now() - interval '7 days'") 0))

;; ------------------------------------------------------------------ the desk

(define (admin-question-candidates x)
  (q x "SELECT q.id, q.post_id, q.body, q.quote_exact, a.handle::text AS handle
          FROM questions q JOIN accounts a ON a.id = q.account_id
         WHERE q.parent_id IS NULL AND q.merged_into IS NULL AND NOT q.hidden
         ORDER BY q.created_at DESC LIMIT 500"))

(define (admin-question-rows x)
  "Every question for the desk, each live question with its merge candidates."
  (let ((candidates (admin-question-candidates x))
        (items (q x "SELECT q.id, q.post_id, q.body, q.hidden, q.parent_id, q.merged_into, q.quote_exact,
                           p.slug, p.title,
                           a.id AS account_id, a.handle::text AS handle, a.banned,
                           (SELECT count(*) FROM questions m WHERE m.merged_into = q.id) AS n_merged,
                           to_char(q.created_at, 'FMDD Mon HH24:MI') AS at
                      FROM questions q JOIN posts p ON p.id = q.post_id JOIN accounts a ON a.id = q.account_id
                     ORDER BY q.created_at DESC LIMIT 300")))
    (map (lambda (i)
           (acons "candidates"
                  (if (and (not (row-ref i "parent_id"))
                           (not (row-ref i "merged_into"))
                           (not (row-ref i "hidden")))
                      (filter (lambda (c)
                                (and (equal? (row-ref c "post_id") (row-ref i "post_id"))
                                     (not (equal? (row-ref c "id") (row-ref i "id")))))
                              candidates)
                      '())
                  i))
         items)))

(define (hide-question! x id hidden?)
  "The desk's soft delete: readers stop seeing the question, the author can
restore it."
  (q! x "UPDATE questions SET hidden = $2::boolean WHERE id = $1::bigint"
      id (if hidden? "true" "false")))

;; Merge one question into another. One statement so the move is atomic:
;; replies follow the question they answer, and questions already merged into
;; the source point at the new target.
(define (merge-questions! x src-id target-id)
  (qval x
        "WITH src AS (
           SELECT id, post_id FROM questions
            WHERE id = $1::bigint AND parent_id IS NULL
              AND merged_into IS NULL AND NOT hidden
            FOR UPDATE
         ), tgt AS (
           SELECT q.id FROM questions q
            WHERE q.id = $2::bigint AND q.parent_id IS NULL
              AND q.merged_into IS NULL AND NOT q.hidden
              AND EXISTS (SELECT 1 FROM src
                           WHERE src.post_id = q.post_id AND src.id <> q.id)
            FOR UPDATE
         ), related AS (
           SELECT id FROM src
           UNION ALL
           SELECT c.id FROM questions c JOIN src ON c.merged_into = src.id
            WHERE c.parent_id IS NULL
         ), moved AS (
           UPDATE questions r SET parent_id = (SELECT id FROM tgt)
            WHERE r.parent_id IN (SELECT id FROM related)
              AND EXISTS (SELECT 1 FROM tgt)
           RETURNING r.id
         ), retargeted AS (
           UPDATE questions c SET merged_into = (SELECT id FROM tgt)
            WHERE c.merged_into IN (SELECT id FROM src)
              AND c.parent_id IS NULL
              AND EXISTS (SELECT 1 FROM tgt)
           RETURNING c.id
         )
         UPDATE questions q SET merged_into = tgt.id
           FROM tgt
          WHERE q.id = (SELECT id FROM src)
         RETURNING q.id"
        src-id target-id))

(define (unmerge-question! x id)
  (q! x "UPDATE questions SET merged_into = NULL
          WHERE id = $1::bigint AND merged_into IS NOT NULL" id))

;; ------------------------------------------------------------------ API

(define (api-questions x since limit)
  (q x "SELECT q.id, q.parent_id, q.merged_into, q.body, q.quote_exact, q.hidden,
               a.handle::text AS handle, (SELECT handle::text FROM accounts WHERE id = q.reply_to) AS reply_to,
               p.slug AS post_slug, p.title AS post_title,
               to_char(q.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') AS created_at
          FROM questions q JOIN accounts a ON a.id = q.account_id JOIN posts p ON p.id = q.post_id
         WHERE q.created_at > $1::timestamptz
         ORDER BY q.created_at LIMIT $2::int" since limit))
