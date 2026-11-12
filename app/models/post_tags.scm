;;  roytalk -- post_tags model: which tags a piece carries, in order.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  The join table; posts depends on this model, so it must stay a leaf here
;;  (db/schema.sql owns the foreign keys and the composite primary key).

(import (artanis mvc model))

(create-artanis-model
 post_tags
 (:deps)
 (post_id bigint (#:not-null))
 (tag_id bigint (#:not-null))
 (position int (#:not-null))) ; DO NOT REMOVE THIS LINE!!!

(import (ice-9 match)
        (roytalk db))

(define-public (post-tags x post-id)
  (map (lambda (r) (row-ref r "name"))
       (q x "SELECT t.name::text AS name FROM post_tags pt JOIN tags t ON t.id = pt.tag_id
             WHERE pt.post_id = $1::bigint ORDER BY pt.position, t.name" post-id)))

(define-public (set-post-tags! x post-id names)
  "Replace the tags of POST-ID with NAMES, keeping their order."
  (with-tx
   (lambda ()
     (q! x "DELETE FROM post_tags WHERE post_id = $1::bigint" post-id)
     (let lp ((ns names) (i 0))
       (match ns
         (() #t)
         ((n . rest)
          (let ((tid (qval x "INSERT INTO tags (name) VALUES ($1)
                              ON CONFLICT (name) DO UPDATE SET name = tags.name RETURNING id" n)))
            (q! x "INSERT INTO post_tags (post_id, tag_id, position)
                   VALUES ($1::bigint, $2::bigint, $3::int)
                   ON CONFLICT DO NOTHING" post-id tid i)
            (lp rest (1+ i)))))))))
