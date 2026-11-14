;;  roytalk -- Markdown to HTML, done once when the author saves.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  pandoc does the work: GitHub-flavoured Markdown plus $math$, syntax
;;  highlighting as plain <span class="..."> (LLVM IR, assembly, C, Scheme ...
;;  coloured by site.css), and math as MathML. Readers get finished HTML and no
;;  script is needed to read an essay.
;;
;;  The Markdown is the author's own text, so raw HTML in it is allowed.

(define-module (roytalk render)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 regex)
  #:use-module (roytalk util)
  #:use-module (roytalk settings)
  #:export (markdown->html))

(define *split* "<!--ROYTALK-TOC-END-->")

(define (template-file)
  ;; pandoc template: the table of contents, a marker, then the body.
  (let ((f (string-append (getcwd) "/tmp/pandoc-roytalk.html")))
    (unless (file-exists? f)
      (call-with-output-file f
        (lambda (p) (display (string-append "$toc$\n" *split* "\n$body$\n") p))))
    f))

(define (run-pandoc md)
  (let* ((pandoc (setting 'pandoc "pandoc"))
         (args (list pandoc
                     "--from=gfm+tex_math_dollars+footnotes+attributes"
                     "--to=html5"
                     "--mathml"
                     "--toc" "--toc-depth=2"
                     (string-append "--template=" (template-file))
                     "--wrap=none"
                     "--metadata=pagetitle:roytalk")))
    (call-with-values
        (lambda () (pipeline (list args)))
      (lambda (from to pids)
        ;; Never depend on the process locale: pandoc speaks UTF-8.
        (set-port-encoding! to "UTF-8")
        (set-port-encoding! from "UTF-8")
        (put-string to md)
        (close-port to)
        (let ((out (get-string-all from)))
          (close-port from)
          (for-each waitpid pids)
          out)))))

(define *languages*
  '(("llvm" . "LLVM IR") ("c" . "C") ("cpp" . "C++") ("rust" . "Rust") ("go" . "Go")
    ("scheme" . "Scheme") ("commonlisp" . "Common Lisp") ("haskell" . "Haskell")
    ("ocaml" . "OCaml") ("python" . "Python") ("bash" . "Shell") ("zig" . "Zig")
    ("gnuassembler" . "Assembly") ("nasm" . "Assembly") ("asm" . "Assembly")
    ("cuda" . "CUDA") ("javascript" . "JavaScript") ("sql" . "SQL") ("json" . "JSON")))

(define (label-code-blocks html)
  "Give each highlighted block a data-lang label, shown as its header by site.css."
  (regexp-substitute/global
   #f "<div class=\"sourceCode\" id=\"(cb[0-9]+)\"><pre class=\"sourceCode ([A-Za-z0-9_+-]+)\">" html
   'pre
   (lambda (m)
     (let* ((lang (match:substring m 2))
            (label (or (assoc-ref *languages* lang) lang)))
       (string-append "<div class=\"sourceCode\" id=\"" (match:substring m 1)
                      "\" data-lang=\"" label "\"><pre class=\"sourceCode " lang "\">")))
   'post))

;; Citations the easy way: [1] in the prose, the source on its own line at the
;; foot of the Markdown:
;;
;;     [1]: Jane Doe, *A Book*, 2020
;;
;; Pandoc footnotes do the numbering, the end list and the backlinks. A marker
;; with no entry is left untouched, so a missing source shows up as [1] rather
;; than disappearing. Links ([1](url)) and code -- fenced blocks, `spans`,
;; indented blocks -- are never rewritten; neither is anything that looks like
;; an index (arr[1]).

(define *fence-re* (make-regexp "^ {0,3}(`{3,}|~{3,})(.*)$"))
(define *def-re* (make-regexp "^([ ]{0,3}\\[)(\\^)?([0-9]+)(\\]:)[ \t]*"))
(define *marker-re* (make-regexp "\\[([0-9]+)\\]"))

(define (backtick-run-end line i)
  (let ((len (string-length line)))
    (let loop ((j i))
      (if (and (< j len) (char=? (string-ref line j) #\`))
          (loop (+ j 1))
          j))))

(define (text-segments line)
  "Index pairs of LINE that lie outside `inline code`."
  (let ((len (string-length line)))
    (let loop ((i 0) (open #f) (open-len 0) (segs '()) (start 0))
      (if (>= i len)
          (reverse (cons (cons start len) segs))
          (if (char=? (string-ref line i) #\`)
              (let ((j (backtick-run-end line i)))
                (cond
                 ((not open) (loop j i (- j i) segs start))
                 ((= (- j i) open-len)
                  (loop j #f 0 (cons (cons start open) segs) j))
                 (else (loop j open open-len segs start))))
              (loop (+ i 1) open open-len segs start))))))

(define (fence-start line)
  (let ((m (regexp-exec *fence-re* line)))
    (and m (match:substring m 1))))

(define (fence-end? line fence)
  (let ((m (regexp-exec *fence-re* line)))
    (and m (string-null? (string-trim-both (match:substring m 2)))
         (char=? (string-ref (match:substring m 1) 0)
                 (string-ref fence 0))
         (>= (string-length (match:substring m 1)) (string-length fence)))))

(define (definition-label line)
  (let ((m (regexp-exec *def-re* line)))
    (and m (match:substring m 3))))

(define (defined-labels lines)
  (let loop ((ls lines) (fence #f) (acc '()))
    (if (null? ls)
        (reverse acc)
        (let ((line (car ls)))
          (cond
           (fence
            (if (fence-end? line fence)
                (loop (cdr ls) #f acc)
                (loop (cdr ls) fence acc)))
           ((fence-start line) (loop (cdr ls) (fence-start line) acc))
           ((or (string-prefix? "    " line) (string-prefix? "\t" line))
            (loop (cdr ls) #f acc))
           ((definition-label line)
            (loop (cdr ls) #f (cons (definition-label line) acc)))
           (else (loop (cdr ls) #f acc)))))))

(define (index-like-before? ch)
  "True for the character before an index or a reference link label."
  (and ch (< (char->integer ch) 128)
       (or (char-alphabetic? ch) (char-numeric? ch)
           (char=? ch #\_) (char=? ch #\]) (char=? ch #\)))))

(define (not-a-marker-after? ch)
  (and ch (or (char=? ch #\() (char=? ch #\[) (char=? ch #\:))))

(define (rewrite-inline text defined)
  (regexp-substitute/global
   #f *marker-re* text
   'pre
   (lambda (m)
     (let* ((n (match:substring m 1))
            (s (match:start m))
            (e (match:end m))
            (prev (and (> s 0) (string-ref text (- s 1))))
            (next (and (< e (string-length text)) (string-ref text e))))
       (if (and (member n defined)
                (not (index-like-before? prev))
                (not (and prev (char=? prev #\\)))
                (not (not-a-marker-after? next)))
           (string-append "[^" n "]")
           (match:substring m))))
   'post))

(define (rewrite-line line defined)
  (let* ((m (regexp-exec *def-re* line))
         (line (if (and m (not (match:substring m 2)))
                   ;; [1]: source  ->  [^1]: source
                   (string-append (match:substring m 1) "^"
                                  (match:substring m 3) (match:substring m 4)
                                  " " (substring line (match:end m 0)))
                   line)))
    (let loop ((segs (text-segments line)) (pos 0) (parts '()))
      (if (null? segs)
          (apply string-append (reverse (cons (substring line pos) parts)))
          (let* ((seg (car segs))
                 (parts (cons (substring line pos (car seg)) parts))
                 (parts (cons (rewrite-inline (substring line (car seg) (cdr seg)) defined)
                              parts)))
            (loop (cdr segs) (cdr seg) parts))))))

(define (normalize-citations md)
  "Let [1] in the prose stand for the footnote defined by [1]: source."
  (let* ((lines (string-split md #\newline))
         (defined (defined-labels lines)))
    (let loop ((ls lines) (fence #f) (out '()))
      (if (null? ls)
          (string-join (reverse out) "\n")
          (let ((line (car ls)))
            (cond
             (fence
              (if (fence-end? line fence)
                  (loop (cdr ls) #f (cons line out))
                  (loop (cdr ls) fence (cons line out))))
             ((fence-start line)
              (loop (cdr ls) (fence-start line) (cons line out)))
             ((or (string-prefix? "    " line) (string-prefix? "\t" line))
              (loop (cdr ls) #f (cons line out)))
             (else
              (loop (cdr ls) #f (cons (rewrite-line line defined) out)))))))))

(define (markdown->html md)
  "Return (values body-html toc-html). Blocking: call it from call-with-runner."
  (let* ((out (run-pandoc (normalize-citations (->str md))))
         (i (string-contains out *split*)))
    (if i
        (values (label-code-blocks (string-trim-both (substring out (+ i (string-length *split*)))))
                (string-trim-both (substring out 0 i)))
        (values (label-code-blocks out) ""))))
