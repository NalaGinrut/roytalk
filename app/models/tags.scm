;;  roytalk -- tags model.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(import (artanis mvc model))

(create-artanis-model
 tags
 (:deps)
 (id bigserial (#:primary-key))
 (name citext (#:not-null #:unique))) ; DO NOT REMOVE THIS LINE!!!

(import (srfi srfi-45)  ; delay, for FPRM conditions
        (artanis ssql)  ; where
        (roytalk db)
        (app models posts))

(export all-tags
        posts-by-tag
        admin-tags
        tag-name-taken?
        rename-tag!
        delete-tag!)

(define (all-tags x)
  (q x "SELECT t.name::text AS name, count(p.id) AS n
          FROM tags t
          LEFT JOIN post_tags pt ON pt.tag_id = t.id
          LEFT JOIN posts p ON p.id = pt.post_id AND p.status = 'published'
         GROUP BY t.name ORDER BY count(p.id) DESC, t.name"))

(define (posts-by-tag x tag)
  (map with-tags
       (q x (string-append "SELECT " post-columns " FROM posts p
              JOIN post_tags pt ON pt.post_id = p.id JOIN tags t ON t.id = pt.tag_id
              WHERE p.status = 'published' AND t.name = $1
              ORDER BY p.published_at DESC") tag)))

(define (admin-tags x)
  (q x "SELECT t.id, t.name::text AS name, count(pt.post_id) AS n
          FROM tags t LEFT JOIN post_tags pt ON pt.tag_id = t.id
         GROUP BY t.id ORDER BY t.name"))

(define (tag-name-taken? x name id)
  "The id of another tag already named NAME, or #f."
  (qval x "SELECT id FROM tags WHERE name = $1 AND id <> $2::bigint" name id))

(define (rename-tag! x id name)
  (model-set! x $tags #:name name (delay (where #:id id)))
  #t)

(define (delete-tag! x id)
  "Delete an unused tag; a tag still on a piece stays."
  (q! x "DELETE FROM tags WHERE id = $1::bigint
          AND NOT EXISTS (SELECT 1 FROM post_tags WHERE tag_id = $1::bigint)" id))
