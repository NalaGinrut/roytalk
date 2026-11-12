;;  roytalk -- small formatting helpers used inside templates.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.

(define-module (roytalk views)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:export (questions-phrase
            also-asked
            plural
            checked
            selected
            when-str
            search-snippet
            qa))

(define (plural n one many)
  (let ((n (or n 0)))
    (format #f "~a ~a" n (if (= n 1) one many))))

(define (questions-phrase n)
  (let ((n (or n 0)))
    (cond ((zero? n) "no questions yet")
          ((= n 1) "1 question from a reader")
          (else (format #f "~a questions from readers" n)))))

(define (also-asked handles)
  "HTML line for readers whose merged question had the same doubt."
  (if (null? handles)
      ""
      (let* ((shown (take handles (min 5 (length handles))))
             (rest (- (length handles) (length shown)))
             (names (string-join (map (lambda (x) (string-append "@" (h x))) shown) ", ")))
        (string-append
         "Also asked by " names
         (cond ((zero? rest) ".")
               ((= rest 1) " — 1 other has the same question.")
               (else (format #f " — ~a others have the same question." rest)))))))

(define (checked x) (if x " checked" ""))
(define (selected x) (if x " selected" ""))
(define (when-str test s) (if test s ""))

(define (search-snippet s)
  "ts_headline output: escape everything, then let the <mark> pairs through."
  (let* ((e (h s))
         (e (regexp-substitute/global #f "&lt;mark&gt;" e 'pre "<mark>" 'post))
         (e (regexp-substitute/global #f "&lt;/mark&gt;" e 'pre "</mark>" 'post)))
    (string-append e " …")))

(define (qa . parts)
  "An escaped, double-quoted attribute value made from PARTS.
Artanis templates must not wrap <%= %> in quotes, so the quotes come from here:
  <a href=<%= (qa \"/posts/\" slug) %>>"
  (string-append "\"" (h (string-concatenate (map ->str parts))) "\""))
