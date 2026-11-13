;;  roytalk -- the opening of a rendered piece, for mail.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Pure: no database, no Artanis. Both the web process and tools/digest.scm
;;  import this, so a standalone script never pulls in the Artanis DB layer.
;;
;;  Mail clients do not render MathML, so formulas are shown as their TeX
;;  source, taken from the annotation pandoc writes next to the MathML.

(define-module (roytalk excerpt)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:export (strip-tags
            inline-math->tex
            style-inline
            letter-excerpt))

(define (strip-tags s)
  (let* ((s (regexp-substitute/global #f "<[^>]*>" s 'pre "" 'post))
         (s (regexp-substitute/global #f "&nbsp;|&#160;" s 'pre " " 'post))
         (s (regexp-substitute/global #f "&lt;" s 'pre "<" 'post))
         (s (regexp-substitute/global #f "&gt;" s 'pre ">" 'post))
         (s (regexp-substitute/global #f "&quot;" s 'pre "\"" 'post))
         (s (regexp-substitute/global #f "&#39;" s 'pre "'" 'post))
         (s (regexp-substitute/global #f "&amp;" s 'pre "&" 'post)))
    s))

(define *tex-re* (make-regexp "<annotation encoding=\"application/x-tex\">([^<]*)</annotation>"))

(define (inline-math->tex p)
  ;; Mail clients do not render MathML; show the TeX source instead.
  (let lp ((i 0) (out '()))
    (let ((open (string-contains p "<math" i)))
      (if (not open)
          (string-concatenate (reverse (cons (substring p i) out)))
          (let* ((close (string-contains p "</math>" open))
                 (end (if close (+ close 7) (string-length p)))
                 (m (regexp-exec *tex-re* (substring p open end))))
            (lp end (cons (if m (string-append "<code>" (match:substring m 1) "</code>") "")
                          (cons (substring p i open) out))))))))

(define (style-inline p)
  (let* ((p (inline-math->tex p))
         (p (regexp-substitute/global #f "<a href=" p 'pre "<a style=\"color:#1E3F30;\" href=" 'post))
         (p (regexp-substitute/global #f "<code>" p 'pre
                                      "<code style=\"font-family:Menlo,Consolas,monospace;font-size:14px;background:#EAE6DA;padding:1px 4px;\">"
                                      'post)))
    p))

(define (plain-fallback body-html max-words)
  "When a piece has no plain paragraph at all (only lists or code), fall back
to the first MAX-WORDS words of its plain text, without the code blocks."
  (let* ((s (regexp-substitute/global #f "<pre[^>]*>[^<]*</pre>" (->str body-html)
                                      'pre "" 'post))
         (text (string-trim-both (strip-tags (inline-math->tex s))))
         (words (filter (lambda (w) (not (string-null? w))) (string-split text #\space))))
    (cond
     ((null? words) "")
     ((<= (length words) max-words) (string-join words " "))
     (else (string-append (string-join (take words max-words) " ") "…")))))

(define* (letter-excerpt body-html #:key (max-words 220))
  "The opening of an essay for the letter: its leading paragraphs, up to the
first heading, code block, formula, figure or list, and about MAX-WORDS words.
The first paragraph is always kept. Returns (html . text)."
  (let lp ((lines (string-split (->str body-html) #\newline)) (paras '()) (words 0))
    (let ((done (lambda ()
                  (let ((ps (reverse paras)))
                    (if (null? ps)
                        (let ((fallback (plain-fallback body-html max-words)))
                          (if (string-null? fallback)
                              (cons "" "")
                              (cons (string-append "<p style=\"margin:0 0 18px;\">"
                                                   (h fallback) "</p>\n")
                                    fallback)))
                        (cons (string-concatenate
                               (map (lambda (p)
                                      (string-append "<p style=\"margin:0 0 18px;\">"
                                                     (style-inline p) "</p>\n"))
                                    ps))
                              (string-join (map (lambda (p) (string-trim-both (strip-tags (inline-math->tex p)))) ps)
                                           "\n\n")))))))
      (cond
       ((or (null? lines) (>= words max-words)) (done))
       (else
        (let ((line (string-trim-both (car lines))))
          (cond
           ((string-null? line) (lp (cdr lines) paras words))
           ((and (string-prefix? "<p>" line) (string-suffix? "</p>" line)
                 (not (string-contains line "<math display=\"block\"")))
            (let* ((inner (substring line 3 (- (string-length line) 4)))
                   (n (string-count-words (strip-tags inner))))
              (if (and (pair? paras) (> (+ words n) max-words))
                  (done)
                  (lp (cdr lines) (cons inner paras) (+ words n)))))
           ;; A leading heading, figure or formula is skipped: the opening
           ;; starts at the first real paragraph, where the prose does.
           ((null? paras) (lp (cdr lines) paras words))
           (else (done)))))))))
