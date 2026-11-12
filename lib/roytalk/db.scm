;;  roytalk -- thin layer over (artanis db).
;;  Copyright (C) 2026 Roy
;;  GPLv3 or later.
;;
;;  Every query is parameterised ($1, $2 ...). Rows come back as alists keyed
;;  by column name; SQL NULL is normalised to #f so templates can use plain
;;  `if'. Failures throw (DB-query #:check? #f) instead of printing and moving on.
;;
;;  Connections: each query borrows a connection from the Artanis pool and
;;  gives it back at once, also when something throws. A connection held by
;;  the request (DB-open) is only returned by the before-response hook, which
;;  does not run when a handler throws (a 404, a 403, a bug), so with
;;  db.pool = fixed a few such requests would leave the pool empty and hang
;;  the server.
;;
;;  with-tx borrows one connection for a group of statements, binds it as
;;  Artanis' current-dbconn so nested q calls use it, and returns it only
;;  after COMMIT or ROLLBACK. The transaction-control statements are sent
;;  through the same parameterised path as everything else.

(define-module (roytalk db)
  #:use-module (artanis artanis)
  #:use-module (artanis db)
  #:use-module (artanis env)
  #:use-module (srfi srfi-1)
  #:use-module (roytalk util)
  #:export (q q1 q! qval
            with-tx
            with-pool-conn
            row-ref
            model-conn
            model-set!))

(define (clean-row row)
  (map (lambda (kv)
         (if (unspecified? (cdr kv)) (cons (car kv) #f) kv))
       row))

(define (params->list params)
  (map (lambda (p)
         (cond
          ((or (not p) (unspecified? p)) '()) ; SQL NULL
          ((eq? p #t) "true")
          ((symbol? p) (symbol->string p))
          (else p)))
       params))

(define (call-with-conn x proc)
  "X is a route context (borrow a pooled connection for PROC) or a connection.
When a transaction is open, the context uses its connection instead of
borrowing another one."
  (cond
   ((not (route-context? x)) (proc x))
   ((current-dbconn) (proc (current-dbconn)))
   (else
    ;; Take the connection outside the guard: waiting for one may suspend
    ;; the task, and nothing must be released while it waits.
    (let ((conn (get-conn-from-pool!)))
      (let ((result (catch #t
                      (lambda () (proc conn))
                      (lambda (key . args)
                        (recycle-DB-conn conn)
                        (apply throw key args)))))
        (recycle-DB-conn conn)
        result)))))

(define (rows-of conn sql params)
  (map clean-row
       (DB-get-all-rows
        (DB-query conn sql #:params (params->list params) #:check? #f))))

(define (q x sql . params)
  "All rows."
  (call-with-conn x (lambda (conn) (rows-of conn sql params))))

(define (q1 x sql . params)
  "The first row, or #f."
  (let ((rows (apply q x sql params)))
    (and (pair? rows) (car rows))))

(define (qval x sql . params)
  "The first column of the first row, or #f."
  (let ((row (apply q1 x sql params)))
    (and row (pair? row) (cdar row))))

(define (q! x sql . params)
  "A statement without a result set."
  (call-with-conn x (lambda (conn) (rows-of conn sql params) #t)))

(define (with-tx thunk)
  "Run THUNK in one transaction. Nested calls join the open transaction;
there are no savepoints, so an inner failure aborts the whole transaction."
  (if (current-dbconn)
      (thunk)
      (let ((conn (get-conn-from-pool!)))
        (define (exec sql)
          ;; Same parameterised path as any other statement; no bare query.
          (DB-query conn sql #:params '() #:check? #f))
        (dynamic-wind
          (lambda () #t)
          (lambda ()
            (parameterize ((current-dbconn conn))
              (exec "BEGIN")
              (catch #t
                (lambda ()
                  (let ((result (thunk)))
                    (exec "COMMIT")
                    result))
                (lambda (key . args)
                  ;; A failed COMMIT also lands here; ROLLBACK is harmless if
                  ;; the server already ended the transaction.
                  (catch #t (lambda () (exec "ROLLBACK") #t)
                         (lambda ignored #f))
                  (apply throw key args)))))
          (lambda () (recycle-DB-conn conn))))))

(define (with-pool-conn proc)
  "For code running outside a request (background jobs)."
  (let ((conn (get-conn-from-pool!)))
    (let ((result (catch #t
                    (lambda ()
                      (parameterize ((current-dbconn conn))
                        (proc conn)))
                    (lambda (key . args)
                      (recycle-DB-conn conn)
                      (apply throw key args)))))
      (recycle-DB-conn conn)
      result)))

;; ---------------------------------------------------------- Artanis models
;; The models from create-artanis-model use Artanis' current-dbconn: they reuse
;; the request's transaction connection when there is one and otherwise borrow
;; a pooled connection for the call. These helpers let a model function keep
;; taking an rc or a bare connection like the q wrappers above.

(define (model-conn x thunk)
  "Run THUNK (which calls a $model) with X as the current connection when X is
a connection. A route context is left to FPRM, which borrows and returns a
connection itself, or reuses the transaction if one is open."
  (if (route-context? x)
      (thunk)
      (parameterize ((current-dbconn x)) (thunk))))

(define (model-set! x model . kargs)
  "Run ($MODEL 'set ...), which FPRM does not fail loudly on, and check the
result. Borrows and returns a connection exactly like q!."
  (define (run conn)
    (let ((result (parameterize ((current-dbconn conn))
                    (apply model 'set kargs))))
      (unless (db-conn-success? conn)
        (throw 'artanis-err 500 'model-set! "database write failed"))
      result))
  (cond
   ((not (route-context? x))
    (let ((result (parameterize ((current-dbconn x))
                    (apply model 'set kargs))))
      (unless (db-conn-success? x)
        (throw 'artanis-err 500 'model-set! "database write failed"))
      result))
   ((current-dbconn)
    (let ((conn (current-dbconn)))
      (let ((result (apply model 'set kargs)))
        (unless (db-conn-success? conn)
          (throw 'artanis-err 500 'model-set! "database write failed"))
        result)))
   (else
    (let ((conn (get-conn-from-pool!)))
      (let ((result (catch #t
                      (lambda () (run conn))
                      (lambda (key . args)
                        (recycle-DB-conn conn)
                        (apply throw key args)))))
        (recycle-DB-conn conn)
        result)))))

(define (row-ref row key)
  (and row (assoc-ref row key)))
