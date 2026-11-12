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
                     "--from=gfm+tex_math_dollars+footnotes"
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

(define (markdown->html md)
  "Return (values body-html toc-html). Blocking: call it from call-with-runner."
  (let* ((out (run-pandoc (->str md)))
         (i (string-contains out *split*)))
    (if i
        (values (label-code-blocks (string-trim-both (substring out (+ i (string-length *split*)))))
                (string-trim-both (substring out 0 i)))
        (values (label-code-blocks out) ""))))
