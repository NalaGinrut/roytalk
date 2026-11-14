;;  roytalk -- image uploads for the editor.
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Multipart is parsed by Artanis' own reader. We never trust the client's
;;  filename or Content-Type: the extension comes from the magic bytes, the
;;  name is the SHA-256 of the content, and the write is atomic. The same bytes
;;  always land on the same immutable URL, so nginx may cache uploads forever.

(define-module (roytalk upload)
  #:use-module (artanis artanis)
  #:use-module (artanis env)
  #:use-module (artanis upload)
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:export (max-image-bytes
            upload-root
            ensure-upload-dir!
            file-mfd?
            file-mfds
            mfd-by-name
            mfd-bytes
            mfd-text
            image-kind
            store-image!))

(define max-image-bytes (* 10 1024 1024))

(define (upload-root)
  (string-append (or (current-toplevel) (getcwd)) "/pub/img/upload"))

(define (ensure-upload-dir!)
  (let ((dir (upload-root)))
    (unless (file-exists? dir)
      (catch 'system-error
        (lambda () (mkdir dir #o755))
        (lambda args
          ;; Another request may have created it in the meantime.
          (unless (file-exists? dir) (apply throw args)))))
    dir))

;; ------------------------------------------------------------------ multipart

(define (file-mfd? mfd)
  (let ((name (mfd-filename mfd)))
    (and name (not (string-null? name)))))

(define (file-mfds mfds-operator)
  "File parts in the order the browser sent them (Artanis parses them in
reverse)."
  (sort (filter file-mfd? (mfds-operator-mfds mfds-operator))
        (lambda (a b) (< (mfd-begin a) (mfd-begin b)))))

(define (mfd-by-name mfds-operator name)
  "The first part called NAME, or #f. Unlike mfds-op-ref this does not throw
when the field is absent."
  (any (lambda (mfd) (and (string=? name (mfd-name mfd)) mfd))
       (mfds-operator-mfds mfds-operator)))

(define (bytevector-range bv start end)
  "Copy START..END inclusive. (rnrs bytevectors)' bytevector-copy takes no
range, unlike the R7RS one."
  (let* ((len (- end start -1))
         (out (make-bytevector len)))
    (bytevector-copy! bv start out 0 len)
    out))

(define (mfd-bytes rc mfd)
  ;; mfd-end is inclusive, unlike an ordinary Scheme range.
  (bytevector-range (rc-body rc) (mfd-begin mfd) (mfd-end mfd)))

(define (mfd-text rc mfd)
  (bytevector->string (mfd-bytes rc mfd) "utf-8"))

;; ------------------------------------------------------------------ sniffing

(define (bytes-at=? bv offset expected)
  (let ((n (bytevector-length expected)))
    (and (>= (bytevector-length bv) (+ offset n))
         (let loop ((i 0))
           (or (= i n)
               (and (= (bytevector-u8-ref bv (+ offset i))
                       (bytevector-u8-ref expected i))
                    (loop (+ i 1))))))))

(define *png-sig* #vu8(137 80 78 71 13 10 26 10))
(define *gif87* (string->utf8 "GIF87a"))
(define *gif89* (string->utf8 "GIF89a"))
(define *riff* (string->utf8 "RIFF"))
(define *webp* (string->utf8 "WEBP"))

(define (image-kind bv)
  "Return (mime . extension) for PNG, JPEG, GIF or WebP, else #f.
SVG is deliberately absent: it can carry script."
  (let ((len (bytevector-length bv)))
    (cond
     ((bytes-at=? bv 0 *png-sig*) '("image/png" . "png"))
     ((and (>= len 3)
           (= 255 (bytevector-u8-ref bv 0))
           (= 216 (bytevector-u8-ref bv 1))
           (= 255 (bytevector-u8-ref bv 2)))
      '("image/jpeg" . "jpg"))
     ((or (bytes-at=? bv 0 *gif87*) (bytes-at=? bv 0 *gif89*))
      '("image/gif" . "gif"))
     ((and (>= len 12) (bytes-at=? bv 0 *riff*) (bytes-at=? bv 8 *webp*))
      '("image/webp" . "webp"))
     (else #f))))

;; ------------------------------------------------------------------ storage

(define (write-atomically! path bv)
  "Write BV to PATH through a dot-temp in the same directory, then rename.
A reader never sees a partial image."
  (let ((tmp (string-append path "." (random-token 8) ".part")))
    (catch #t
      (lambda ()
        (call-with-output-file tmp
          (lambda (port) (put-bytevector port bv))
          #:binary #t)
        (chmod tmp #o644)
        (rename-file tmp path))
      (lambda args
        (when (file-exists? tmp) (delete-file tmp))
        (apply throw args)))))

(define (store-image! bv ext)
  "Store BV as <sha256>.<ext> under pub/img/upload. Returns (values url
deduped?) where DEDUPED? is true when the content was already there."
  (let* ((dir (ensure-upload-dir!))
         (name (string-append (sha256-hex bv) "." ext))
         (path (string-append dir "/" name))
         (url (string-append "/img/upload/" name)))
    (if (file-exists? path)
        (values url #t)
        (begin
          (write-atomically! path bv)
          (values url #f)))))
