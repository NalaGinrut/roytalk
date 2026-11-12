;;  roytalk -- submissions model: links readers send in for the author.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  The table is created by db/schema.sql; the declaration below mirrors its
;;  columns for Artanis' model layer.

(import (artanis mvc model))

;; NOTE: Artanis' macro passes (:deps ...) to process-use-modules as one
;; nested list, which only works for a single dependency. Keep it to one.
(create-artanis-model
 submissions
 (:deps accounts)
 (id bigserial (#:primary-key))
 (account_id bigint (#:not-null))
 (url text (#:not-null))
 (url_norm text (#:not-null))
 (note text (#:not-null))
 (status text (#:not-null))
 (post_id bigint (#:null))
 (created_at timestamptz (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (roytalk db))

(export submission-count-since
        submit-link!
        account-submissions
        new-links-count
        admin-inbox-groups
        mark-submissions-used!
        dismiss-submissions!
        api-submissions)

(define (submission-count-since x account-id hours)
  (or (qval x "SELECT count(*) FROM submissions WHERE account_id = $1::bigint
                AND created_at > now() - make_interval(hours => $2::int)" account-id hours) 0))

(define (submit-link! x account-id url url-norm note)
  "Send the same link again and only the note and the time are refreshed."
  (q! x "INSERT INTO submissions (account_id, url, url_norm, note)
         VALUES ($1::bigint, $2, $3, $4)
         ON CONFLICT (account_id, url_norm)
         DO UPDATE SET note = EXCLUDED.note, created_at = now()"
      account-id url url-norm note))

(define (account-submissions x account-id)
  (q x "SELECT s.id, s.url, s.note, s.status, p.slug, p.title,
               to_char(s.created_at, 'FMDD Mon YYYY') AS date_long
          FROM submissions s LEFT JOIN posts p ON p.id = s.post_id AND p.status = 'published'
         WHERE s.account_id = $1::bigint ORDER BY s.created_at DESC LIMIT 200" account-id))

(define (new-links-count x)
  (or (qval x "SELECT count(DISTINCT url_norm) FROM submissions WHERE status = 'received'") 0))

(define (admin-inbox-groups x show)
  (q x "SELECT s.url_norm, min(s.url) AS url, count(*) AS n,
               bool_or(s.status = 'used') AS used, bool_and(s.status = 'dismissed') AS dismissed,
               max(p.slug) AS slug, max(p.title) AS title,
               to_char(max(s.created_at), 'FMDD Mon') AS last_date,
               json_agg(json_build_object('handle', a.handle::text, 'note', s.note)
                        ORDER BY s.created_at)::text AS notes
          FROM submissions s JOIN accounts a ON a.id = s.account_id
          LEFT JOIN posts p ON p.id = s.post_id
         GROUP BY s.url_norm
        HAVING $1 = 'all' OR bool_and(s.status = 'received')
         ORDER BY count(*) DESC, max(s.created_at) DESC
         LIMIT 300" show))

(define (mark-submissions-used! x url-norm post-id)
  (q! x "UPDATE submissions SET status = 'used', post_id = $2::bigint
          WHERE url_norm = $1 AND status <> 'used'" url-norm post-id))

(define (dismiss-submissions! x url-norm)
  (q! x "UPDATE submissions SET status = 'dismissed'
          WHERE url_norm = $1 AND status = 'received'" url-norm))

(define (api-submissions x since limit)
  (q x "SELECT s.id, s.url, s.url_norm, s.note, s.status, a.handle::text AS handle,
               p.slug AS post_slug,
               (SELECT count(*) FROM submissions d WHERE d.url_norm = s.url_norm) AS same_link_count,
               to_char(s.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') AS created_at
          FROM submissions s JOIN accounts a ON a.id = s.account_id
          LEFT JOIN posts p ON p.id = s.post_id
         WHERE s.created_at > $1::timestamptz
         ORDER BY s.created_at LIMIT $2::int" since limit))
