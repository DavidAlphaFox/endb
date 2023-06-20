(defpackage :endb/sql/expr
  (:use :cl)
  (:import-from :cl-ppcre)
  (:import-from :local-time)
  (:import-from :endb/sql/parser)
  (:import-from :endb/arrow)
  (:import-from :endb/storage/buffer-pool)
  (:import-from :cl-bloom)
  (:import-from :fset)
  (:export #:sql-= #:sql-<> #:sql-is #:sql-not #:sql-and #:sql-or
           #:sql-< #:sql-<= #:sql-> #:sql->=
           #:sql-+ #:sql-- #:sql-* #:sql-/ #:sql-% #:sql-<<  #:sql->> #:sql-unary+ #:sql-unary-
           #:sql-between #:sql-in #:sql-exists #:sql-coalesce
           #:sql-union-all #:sql-union #:sql-except #:sql-intersect #:sql-scalar-subquery
           #:sql-cast #:sql-nullif #:sql-abs #:sql-date #:sql-like #:sql-substring #:sql-strftime
           #:make-sql-agg #:sql-agg-accumulate #:sql-agg-finish
           #:sql-create-table #:sql-drop-table #:sql-create-view #:sql-drop-view #:sql-create-index #:sql-drop-index #:sql-insert #:sql-delete
           #:make-db #:copy-db #:db-buffer-pool #:db-wal #:db-object-store #:db-meta-data
           #:base-table #:base-table-rows #:base-table-deleted-row-ids #:base-table-type #:base-table-columns #:base-table-visible-rows #:base-table-size #:base-table-batches
           #:view-definition #:calculate-stats
           #:sql-runtime-error))
(in-package :endb/sql/expr)

(define-condition sql-runtime-error (error)
  ((message :initarg :message :reader sql-runtime-error-message))
  (:report (lambda (condition stream)
             (write (sql-runtime-error-message condition) :stream stream))))

(defun %sql-distinct (rows &optional (distinct :distinct))
  (if (eq :distinct distinct)
      (delete-duplicates rows :test 'equal)
      rows))

(defmethod sql-= ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-= ((x (eql :null)) y)
  :null)

(defmethod sql-= (x (y (eql :null)))
  :null)

(defmethod sql-= ((x endb/arrow:arrow-date-days) (y endb/arrow:arrow-date-days))
  (= (endb/arrow:arrow-date-days-day x) (endb/arrow:arrow-date-days-day y)))

(defmethod sql-= ((x endb/arrow:arrow-time-micros) (y endb/arrow:arrow-time-micros))
  (= (endb/arrow:arrow-time-micros-us x) (endb/arrow:arrow-time-micros-us y)))

(defmethod sql-= ((x endb/arrow:arrow-timestamp-micros) (y endb/arrow:arrow-timestamp-micros))
  (= (endb/arrow:arrow-timestamp-micros-us x) (endb/arrow:arrow-timestamp-micros-us y)))

(defmethod sql-= ((x number) (y number))
  (= x y))

(defmethod sql-= (x y)
  (equal x y))

(defun sql-<> (x y)
  (sql-not (sql-= x y)))

(defmethod sql-is ((x endb/arrow:arrow-date-days) (y endb/arrow:arrow-date-days))
  (= (endb/arrow:arrow-date-days-day x) (endb/arrow:arrow-date-days-day y)))

(defmethod sql-is ((x endb/arrow:arrow-time-micros) (y endb/arrow:arrow-time-micros))
  (= (endb/arrow:arrow-time-micros-us x) (endb/arrow:arrow-time-micros-us y)))

(defmethod sql-is ((x endb/arrow:arrow-timestamp-micros) (y endb/arrow:arrow-timestamp-micros))
  (= (endb/arrow:arrow-timestamp-micros-us x) (endb/arrow:arrow-timestamp-micros-us y)))

(defmethod sql-is ((x number) (y number))
  (= x y))

(defmethod sql-is (x y)
  (equal x y))

(defmethod sql-< ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-< ((x (eql :null)) y)
  :null)

(defmethod sql-< (x (y (eql :null)))
  :null)

(defmethod sql-< ((x string) (y string))
  (not (null (string< x y))))

(defmethod sql-< ((x endb/arrow:arrow-date-days) (y endb/arrow:arrow-date-days))
  (< (endb/arrow:arrow-date-days-day x) (endb/arrow:arrow-date-days-day y)))

(defmethod sql-< ((x endb/arrow:arrow-time-micros) (y endb/arrow:arrow-time-micros))
  (< (endb/arrow:arrow-time-micros-us x) (endb/arrow:arrow-time-micros-us y)))

(defmethod sql-< ((x endb/arrow:arrow-timestamp-micros) (y endb/arrow:arrow-timestamp-micros))
  (< (endb/arrow:arrow-timestamp-micros-us x) (endb/arrow:arrow-timestamp-micros-us y)))

(defmethod sql-< ((x number) (y number))
  (< x y))

(defmethod sql-< ((x number) (y string))
  t)

(defmethod sql-< ((x string) (y number))
  nil)

(defmethod sql-<= ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-<= ((x (eql :null)) y)
  :null)

(defmethod sql-<= (x (y (eql :null)))
  :null)

(defmethod sql-<= ((x string) (y string))
  (not (null (string<= x y))))

(defmethod sql-<= ((x endb/arrow:arrow-date-days) (y endb/arrow:arrow-date-days))
  (<= (endb/arrow:arrow-date-days-day x) (endb/arrow:arrow-date-days-day y)))

(defmethod sql-<= ((x endb/arrow:arrow-time-micros) (y endb/arrow:arrow-time-micros))
  (<= (endb/arrow:arrow-time-micros-us x) (endb/arrow:arrow-time-micros-us y)))

(defmethod sql-<= ((x endb/arrow:arrow-timestamp-micros) (y endb/arrow:arrow-timestamp-micros))
  (<= (endb/arrow:arrow-timestamp-micros-us x) (endb/arrow:arrow-timestamp-micros-us y)))

(defmethod sql-<= ((x number) (y number))
  (<= x y))

(defmethod sql-<= ((x number) (y string))
  t)

(defmethod sql-<= ((x string) (y number))
  nil)

(defmethod sql-> ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-> ((x (eql :null)) y)
  :null)

(defmethod sql-> (x (y (eql :null)))
  :null)

(defmethod sql-> ((x string) (y string))
  (not (null (string> x y))))

(defmethod sql-> ((x endb/arrow:arrow-date-days) (y endb/arrow:arrow-date-days))
  (> (endb/arrow:arrow-date-days-day x) (endb/arrow:arrow-date-days-day y)))

(defmethod sql-> ((x endb/arrow:arrow-time-micros) (y endb/arrow:arrow-time-micros))
  (> (endb/arrow:arrow-time-micros-us x) (endb/arrow:arrow-time-micros-us y)))

(defmethod sql-> ((x endb/arrow:arrow-timestamp-micros) (y endb/arrow:arrow-timestamp-micros))
  (> (endb/arrow:arrow-timestamp-micros-us x) (endb/arrow:arrow-timestamp-micros-us y)))

(defmethod sql-> ((x number) (y number))
  (> x y))

(defmethod sql-> ((x number) (y string))
  nil)

(defmethod sql-> ((x string) (y number))
  t)

(defmethod sql->= ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql->= ((x (eql :null)) y)
  :null)

(defmethod sql->= (x (y (eql :null)))
  :null)

(defmethod sql->= ((x string) (y string))
  (not (null (string>= x y))))

(defmethod sql->= ((x endb/arrow:arrow-date-days) (y endb/arrow:arrow-date-days))
  (>= (endb/arrow:arrow-date-days-day x) (endb/arrow:arrow-date-days-day y)))

(defmethod sql->= ((x endb/arrow:arrow-time-micros) (y endb/arrow:arrow-time-micros))
  (>= (endb/arrow:arrow-time-micros-us x) (endb/arrow:arrow-time-micros-us y)))

(defmethod sql->= ((x endb/arrow:arrow-timestamp-micros) (y endb/arrow:arrow-timestamp-micros))
  (>= (endb/arrow:arrow-timestamp-micros-us x) (endb/arrow:arrow-timestamp-micros-us y)))

(defmethod sql->= ((x number) (y number))
  (>= x y))

(defmethod sql->= ((x number) (y string))
  nil)

(defmethod sql->= ((x string) (y number))
  t)

(defmethod sql-<< ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-<< ((x (eql :null)) y)
  :null)

(defmethod sql-<< (x (y (eql :null)))
  :null)

(defmethod sql-<< ((x number) (y number))
  (ash x y))

(defmethod sql->> ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql->> ((x (eql :null)) y)
  :null)

(defmethod sql->> (x (y (eql :null)))
  :null)

(defmethod sql->> ((x number) (y number))
  (ash x (- y)))

(defmethod sql-not ((x (eql :null)))
  :null)

(defmethod sql-not (x)
  (not x))

(defmacro sql-and (x y)
  (let ((x-sym (gensym)))
    `(let ((,x-sym ,x))
       (if (eq :null ,x-sym)
           (and ,y :null)
           (and ,x-sym ,y)))))

(defmacro sql-or (x y)
  (let ((x-sym (gensym)))
    `(let ((,x-sym ,x))
       (if (eq :null ,x-sym)
           (or ,y :null)
           (or ,x-sym ,y)))))

(defun sql-coalesce (x y &rest args)
  (let ((tail (member-if-not (lambda (x)
                               (eq :null x))
                             (cons x (cons y args)))))
    (if tail
        (first tail)
        :null)))

(defmethod sql-unary+ ((x (eql :null)))
  :null)

(defmethod sql-unary+ (x)
  x)

(defmethod sql-+ ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-+ ((x (eql :null)) (y number))
  :null)

(defmethod sql-+ ((x number) (y (eql :null)))
  :null)

(defmethod sql-+ ((x number) (y number))
  (+ x y))

(defmethod sql-+ (x (y number))
  y)

(defmethod sql-+ ((x number) y)
  x)

(defmethod sql-+ (x y)
  0)

(defmethod sql-unary- ((x (eql :null)))
  :null)

(defmethod sql-unary- (x)
  0)

(defmethod sql-unary- ((x number))
  (- x))

(defmethod sql-- ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-- ((x (eql :null)) (y number))
  :null)

(defmethod sql-- ((x number) (y (eql :null)))
  :null)

(defmethod sql-- ((x number) (y number))
  (- x y))

(defmethod sql-- (x (y number))
  (- y))

(defmethod sql-- ((x number) y)
  x)

(defmethod sql-- (x y)
  0)

(defmethod sql-* ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-* ((x (eql :null)) (y number))
  :null)

(defmethod sql-* ((x number) (y (eql :null)))
  :null)

(defmethod sql-* ((x number) (y number))
  (* x y))

(defmethod sql-* (x (y number))
  (* 0 y))

(defmethod sql-* ((x number) y)
  (* x 0))

(defmethod sql-* (x y)
  0)

(defmethod sql-/ ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-/ ((x (eql :null)) (y number))
  :null)

(defmethod sql-/ ((x number) (y (eql :null)))
  :null)

(defmethod sql-/ ((x integer) (y integer))
  (if (zerop y)
      :null
      (truncate x y)))

(defmethod sql-/ ((x number) (y number))
  (if (zerop y)
      :null
      (/ x y)))

(defmethod sql-/ (x (y number))
  (* 0 y))

(defmethod sql-/ ((x number) y)
  :null)

(defmethod sql-/ (x y)
  :null)

(defmethod sql-% ((x (eql :null)) (y (eql :null)))
  :null)

(defmethod sql-% ((x (eql :null)) (y number))
  :null)

(defmethod sql-% ((x number) (y (eql :null)))
  :null)

(defmethod sql-% ((x number) (y number))
  (if (zerop y)
      :null
      (mod x y)))

(defmethod sql-% (x (y number))
  (* 0 y))

(defmethod sql-% ((x number) y)
  :null)

(defmethod sql-% (x y)
  :null)

(defun sql-in (item xs)
  (block in
    (reduce (lambda (x y)
              (let ((result (sql-= y item)))
                (if (eq t result)
                    (return-from in result)
                    (sql-or x result))))
            xs
            :initial-value nil)))

(defun sql-between (expr lhs rhs)
  (sql-and (sql->= expr lhs) (sql-<= expr rhs)))

(defun sql-exists (rows)
  (not (null rows)))

(defun sql-union (lhs rhs)
  (%sql-distinct (nunion lhs rhs :test 'equal)))

(defun sql-union-all (lhs rhs)
  (nconc lhs rhs))

(defun sql-except (lhs rhs)
  (%sql-distinct (nset-difference lhs rhs :test 'equal)))

(defun sql-intersect (lhs rhs)
  (%sql-distinct (nintersection lhs rhs :test 'equal)))

(defmethod sql-cast ((x (eql :null)) type)
  :null)

(defmethod sql-cast (x (type (eql :varchar)))
  (prin1-to-string x))

(defmethod sql-cast ((x (eql t)) (type (eql :varchar)))
  "1")

(defmethod sql-cast ((x (eql nil)) (type (eql :varchar)))
  "0")

(defmethod sql-cast ((x integer) (type (eql :varchar)))
  (prin1-to-string x))

(defmethod sql-cast ((x string) (type (eql :varchar)))
  x)

(defmethod sql-cast ((x real) (type (eql :varchar)))
  (format nil "~F" x))

(defmethod sql-cast ((x endb/arrow:arrow-date-days) (type (eql :varchar)))
  (format nil "~A" x))

(defmethod sql-cast ((x endb/arrow:arrow-time-micros) (type (eql :varchar)))
  (format nil "~A" x))

(defmethod sql-cast ((x endb/arrow:arrow-timestamp-micros) (type (eql :varchar)))
  (format nil "~A" x))

(defmethod sql-cast ((x (eql t)) (type (eql :integer)))
  1)

(defmethod sql-cast ((x (eql nil)) (type (eql :integer)))
  0)

(defmethod sql-cast ((x string) (type (eql :integer)))
  (if (ppcre:scan "^-?\\d+$" x)
      (let ((*read-eval* nil))
        (read-from-string x))
      0))

(defmethod sql-cast ((x real) (type (eql :integer)))
  (round x))

(defmethod sql-cast ((x endb/arrow:arrow-date-days) (type (eql :integer)))
  (local-time:timestamp-year (endb/arrow::%epoch-day-to-timestamp (endb/arrow:arrow-date-days-day x))))

(defmethod sql-cast ((x number) (type (eql :signed)))
  (coerce x 'integer))

(defmethod sql-cast ((x (eql t)) (type (eql :signed)))
  1)

(defmethod sql-cast ((x (eql nil)) (type (eql :signed)))
  0)

(defmethod sql-cast ((x string) (type (eql :signed)))
  (multiple-value-bind (token-type value)
      (endb/sql/parser:read-sql-token x)
    (case token-type
      (:- (- (sql-cast (subseq x (1+ (position #\- x))) :signed)))
      ((float integer) value)
      (t 0))))

(defmethod sql-cast ((x number) (type (eql :signed)))
  x)

(defmethod sql-cast ((x (eql t)) (type (eql :decimal)))
  1)

(defmethod sql-cast ((x (eql nil)) (type (eql :decimal)))
  0)

(defmethod sql-cast ((x string) (type (eql :decimal)))
  (multiple-value-bind (token-type value)
      (endb/sql/parser:read-sql-token x)
    (case token-type
      (:- (- (sql-cast (subseq x (1+ (position #\- x))) :decimal)))
      ((float integer) value)
      (t 0))))

(defmethod sql-cast ((x number) (type (eql :decimal)))
  (coerce x 'number))

(defmethod sql-cast ((x (eql t)) (type (eql :real)))
  1.0d0)

(defmethod sql-cast ((x (eql nil)) (type (eql :real)))
  0.0d0)

(defmethod sql-cast ((x string) (type (eql :real)))
  (multiple-value-bind (token-type value)
      (endb/sql/parser:read-sql-token x)
    (case token-type
      (:- (- (sql-cast (subseq x (1+ (position #\- x))) :real)))
      (float value)
      (integer (coerce value 'double-float))
      (t 0.0d0))))

(defmethod sql-cast ((x number) (type (eql :real)))
  (coerce x 'double-float))

(defmethod sql-cast (x (type (eql :date)))
  (sql-date x))

(defun sql-nullif (x y)
  (if (eq t (sql-= x y))
      :null
      x))

(defmethod sql-abs ((x (eql :null)))
  :null)

(defmethod sql-abs ((x number))
  (abs x))

(defmethod sql-date ((x (eql :null)))
  :null)

(defmethod sql-date ((x string))
  (endb/arrow:parse-arrow-date-days x))

(defmethod sql-like ((x (eql :null)) (pattern (eql :null)))
  :null)

(defmethod sql-like ((x (eql :null)) y)
  :null)

(defmethod sql-like (x (y (eql :null)))
  :null)

(defmethod sql-like ((x string) (pattern string))
  (let ((regex (concatenate 'string "^" (ppcre:regex-replace-all "%" pattern ".*") "$")))
    (integerp (ppcre:scan regex x))))

(defmethod sql-strftime ((format (eql :null)) (x (eql :null)))
  :null)

(defmethod sql-strftime ((format (eql :null)) x)
  :null)

(defmethod sql-strftime (format (x (eql :null)))
  :null)

(defmethod sql-strftime ((format string) (x endb/arrow:arrow-date-days))
  (local-time:format-timestring nil
                                (endb/arrow::%epoch-day-to-timestamp (endb/arrow:arrow-date-days-day x))
                                :format (if (equal "%Y" format)
                                            '((:year 4))
                                            (error 'sql-runtime-error
                                                   :message (concatenate 'string "Unknown time format: " format)))))

(defmethod sql-substring ((x (eql :null)) (y (eql :null)) &optional z)
  (declare (ignore z))
  :null)

(defmethod sql-substring ((x (eql :null)) y &optional z)
  (declare (ignore z))
  :null)

(defmethod sql-substring (x (y (eql :null)) &optional z)
  (declare (ignore z))
  :null)

(defmethod sql-substring ((x string) (y number) &optional z)
  (if (eq :null z)
      :null
      (let ((y (if (plusp y)
                   (1- y)
                   (+ (length x) y)))
            (z (if z
                   (min (+ y (1- z)) (length x))
                   (length x))))
        (if (and (< y (length x))
                 (<= z (length x)))
            (subseq x y z)
            :null))))

(defun sql-scalar-subquery (rows)
  (when (> 1 (length rows))
    (error 'sql-runtime-error :message "Scalar subquery must return max one row."))
  (if (null rows)
      :null
      (caar rows)))

;; Aggregates

(defgeneric make-sql-agg (type &rest args))

(defgeneric sql-agg-accumulate (agg x))
(defgeneric sql-agg-finish (agg))

(defstruct sql-distinct (acc ()) agg)

(defmethod sql-agg-accumulate ((agg sql-distinct) x)
  (with-slots (acc) agg
    (push x acc)
    agg))

(defmethod sql-agg-finish ((agg sql-distinct))
  (with-slots (acc (inner-agg agg)) agg
    (sql-agg-finish (reduce #'sql-agg-accumulate (%sql-distinct acc :distinct)
                            :initial-value inner-agg))))

(defun %make-distinct-sql-agg (agg &optional (distinct :distinct))
  (if (eq :distinct distinct)
      (make-sql-distinct :agg agg)
      agg))

(defstruct sql-sum sum has-value-p)

(defmethod make-sql-agg ((type (eql :sum)) &key distinct)
  (%make-distinct-sql-agg (make-sql-sum) distinct))

(defmethod sql-agg-accumulate ((agg sql-sum) x)
  (with-slots (sum has-value-p) agg
    (if has-value-p
        (setf sum (sql-+ sum x))
        (setf sum x has-value-p t))
    agg))

(defmethod sql-agg-accumulate ((agg sql-sum) (x (eql :null)))
  agg)

(defmethod sql-agg-finish ((agg sql-sum))
  (with-slots (sum has-value-p) agg
    (if has-value-p
        sum
        :null)))

(defstruct (sql-total (:include sql-sum)))

(defmethod make-sql-agg ((type (eql :total)) &key distinct)
  (%make-distinct-sql-agg (make-sql-total) distinct))

(defmethod sql-agg-finish ((agg sql-total))
  (with-slots (sum has-value-p) agg
    (if has-value-p
        sum
        0.0d0)))

(defstruct sql-count (count 0 :type integer))

(defmethod make-sql-agg ((type (eql :count)) &key distinct)
  (%make-distinct-sql-agg (make-sql-count) distinct))

(defmethod sql-agg-accumulate ((agg sql-count) x)
  (incf (sql-count-count agg))
  agg)

(defmethod sql-agg-accumulate ((agg sql-count) (x (eql :null)))
  agg)

(defmethod sql-agg-finish ((agg sql-count))
  (sql-count-count agg))

(defstruct (sql-count-star (:include sql-count)))

(defmethod make-sql-agg ((type (eql :count-star)) &key distinct)
  (when distinct
    (error 'sql-runtime-error :message "COUNT(*) does not support DISTINCT."))
  (make-sql-count-star))

(defmethod sql-agg-accumulate ((agg sql-count-star) x)
  (incf (sql-count-star-count agg))
  agg)

(defstruct sql-avg sum (count 0 :type integer))

(defmethod make-sql-agg ((type (eql :avg)) &key distinct)
  (%make-distinct-sql-agg (make-sql-avg) distinct))

(defmethod sql-agg-accumulate ((agg sql-avg) x)
  (with-slots (sum count) agg
    (setf sum (sql-+ sum x))
    (incf count)
    agg))

(defmethod sql-agg-accumulate ((agg sql-avg) (x (eql :null)))
  agg)

(defmethod sql-agg-finish ((agg sql-avg))
  (with-slots (sum count) agg
    (if (zerop count)
        :null
        (sql-/ sum (coerce count 'double-float)))))

(defstruct sql-min min has-value-p)

(defmethod make-sql-agg ((type (eql :min)) &key distinct)
  (%make-distinct-sql-agg (make-sql-min) distinct))

(defmethod sql-agg-accumulate ((agg sql-min) x)
  (with-slots (min has-value-p) agg
    (if has-value-p
        (setf min (if (sql-< min x)
                      min
                      x))
        (setf min x has-value-p t))
    agg))

(defmethod sql-agg-accumulate ((agg sql-min) (x (eql :null)))
  agg)

(defmethod sql-agg-finish ((agg sql-min))
  (with-slots (min has-value-p) agg
    (if has-value-p
        min
        :null)))

(defstruct sql-max max has-value-p)

(defmethod make-sql-agg ((type (eql :max)) &key distinct)
  (%make-distinct-sql-agg (make-sql-max) distinct))

(defmethod sql-agg-accumulate ((agg sql-max) x)
  (with-slots (max has-value-p) agg
    (if has-value-p
        (setf max (if (sql-> max x)
                      max
                      x))
        (setf max x has-value-p t))
    agg))

(defmethod sql-agg-accumulate ((agg sql-max) (x (eql :null)))
  agg)

(defmethod sql-agg-finish ((agg sql-max))
  (with-slots (max has-value-p) agg
    (if has-value-p
        max
        :null)))

(defstruct sql-group_concat (acc nil :type (or null string)) (separator ",") distinct)

(defmethod make-sql-agg ((type (eql :group_concat)) &rest args)
  (multiple-value-bind (separator distinct)
      (if (= 2 (length args))
          (destructuring-bind (&key distinct)
              args
            (values "," distinct))
          (destructuring-bind (separator &key distinct)
              args
            (when distinct
              (error 'sql-runtime-error :message "GROUP_CONCAT with argument doesn't support DISTINCT."))
            (values separator distinct)))
    (%make-distinct-sql-agg (make-sql-group_concat :separator separator :distinct distinct) distinct)))

(defmethod sql-agg-accumulate ((agg sql-group_concat) x)
  (with-slots (acc separator distinct) agg
    (setf acc (cond
                ((and acc (eq :distinct distinct))
                 (concatenate 'string (sql-cast x :varchar) separator acc))
                (acc (concatenate 'string acc separator (sql-cast x :varchar)))
                (t (sql-cast x :varchar))))
    agg))

(defmethod sql-agg-accumulate ((agg sql-group_concat) (x (eql :null)))
  agg)

(defmethod sql-agg-finish ((agg sql-group_concat))
  (or (sql-group_concat-acc agg) :null))

;; Internals

(defun %sql-limit (rows limit offset)
  (subseq rows (or offset 0) (min (length rows)
                                  (if offset
                                      (+ offset limit)
                                      limit))))

(defun %sql-order-by (rows order-by)
  (labels ((asc (x y)
             (cond
               ((eq :null x) t)
               ((eq :null y) nil)
               (t (sql-< x y))))
           (desc (x y)
             (cond
               ((eq :null y) t)
               ((eq :null x) nil)
               (t (sql-> x y)))))
    (sort rows (lambda (x y)
                 (loop for (idx direction) in order-by
                       for cmp = (ecase direction
                                   ((nil :asc) #'asc)
                                   (:desc #'desc))
                       for xv = (nth (1- idx) x)
                       for yv = (nth (1- idx) y)
                       thereis (funcall cmp xv yv)
                       until (funcall cmp yv xv))))))

;; DML/DDL

;; INFORMATION_SCHEMA:

;; "main" is the default schema in SQLite and DuckDB.

;; INFORMATION_SCHEMA.COLUMNS
;; table_catalog (NULL), table_schema ("main"), table_name, column_name, ordinal_position (1-based, used by SLT and CREATE TABLE, otherwise 0)

;; SELECT column_name FROM information_schema.columns WHERE table_name = 'foo' ORDER_BY ordinal_position, column_name ;; normal usage orders by name.

;; INFORMATION_SCHEMA.TABLES
;; table_catalog (NULL), table_schema ("main"), table_name, table_type ("BASE TABLE", "VIEW")

;; INFORMATION_SCHEMA.VIEWS
;; table_catalog (NULL), table_schema ("main"), table_name, view_definition

;; Extra:

;; INFORMATION_SCHEMA.COLUMNS (type related information, for future reference)
;; column_default, is_nullable ("YES", "NO"), data_type

;; INFORMATION_SCHEMA.SCHEMATA
;; catalog_name (NULL), schema_name ("main", "information_schema"), schema_owner (NULL)

(defvar *default-schema* "main")

(defstruct db wal object-store buffer-pool (meta-data (fset:map ("_last_tx" 0))))

(defun base-table-batches (db table-name)
  (with-slots (meta-data buffer-pool) db
    (let ((table-md (fset:lookup meta-data table-name)))
      (when table-md
        (loop for arrow-file in (fset:convert 'list (fset:domain table-md))
              for arrow-file-key = (format nil "~A/~A" table-name arrow-file)
              for deletes-md = (or (fset:lookup (fset:lookup table-md arrow-file) "deletes") (fset:empty-map))
              collect (cons arrow-file (loop for batch in (endb/storage/buffer-pool:buffer-pool-get buffer-pool arrow-file-key)
                                             for batch-idx from 0
                                             collect (cons batch (or (fset:lookup deletes-md batch-idx) (fset:empty-seq))))))))))

(defun base-table-visible-rows (db table-name &key arrow-file-idx-row-id-p)
  (with-slots (meta-data) db
    (let ((table-md (fset:lookup meta-data table-name)))
      (when table-md
        (loop for (arrow-file . batches-deletes) in (base-table-batches db table-name)
              append (loop for (batch . batch-deletes) in batches-deletes
                           for batch-idx from 0
                           append (loop for row-id below (endb/arrow:arrow-length batch)
                                        unless (fset:find row-id batch-deletes)
                                          collect (if arrow-file-idx-row-id-p
                                                      (cons (list arrow-file batch-idx row-id) (endb/arrow:arrow-struct-row-get batch row-id))
                                                      (endb/arrow:arrow-struct-row-get batch row-id)))))))))

(defun base-table-type (db table-name)
  (let* ((table-row (find-if (lambda (row)
                               (equal table-name (nth 2 row)))
                             (base-table-visible-rows db "information_schema.tables"))))
    (nth 3 table-row)))

(defun view-definition (db view-name)
  (let* ((view-row (find-if (lambda (row)
                              (equal view-name (nth 2 row)))
                            (base-table-visible-rows db "information_schema.views")))
         (*read-eval* nil)
         (*read-default-float-format* 'double-float))
    (read-from-string (nth 3 view-row))))

(defun base-table-columns (db table-name)
  (cond
    ((equal "information_schema.columns" table-name)
     '("table_catalog" "table_schema" "table_name" "column_name" "ordinal_position"))
    ((equal "information_schema.tables" table-name)
     '("table_catalog" "table_schema" "table_name" "table_type"))
    ((equal "information_schema.views" table-name)
     '("table_catalog" "table_schema" "table_name" "view_definition"))
    (t (mapcar #'second (%sql-order-by (loop with rows = (base-table-visible-rows db "information_schema.columns")
                                             for (nil nil table c idx) in rows
                                             when (equal table-name table)
                                               collect (list idx c))
                                       (list (list 1 :asc) (list 2 :asc)))))))

(defun base-table-size (db table-name)
  (with-slots (meta-data) db
    (let ((table-md (fset:lookup meta-data table-name)))
      (if table-md
          (fset:reduce (lambda (acc md)
                         (+ acc (- (fset:lookup md "length")
                                   (fset:reduce (lambda (acc x)
                                                  (+ acc (fset:size x)))
                                                (fset:range (or (fset:lookup md "deletes") (fset:empty-map)))
                                                :initial-value 0))))
                       (fset:range table-md)
                       :initial-value 0)
          0))))

(defun %find-arrow-file-idx-row-id (db table-name predicate)
  (loop for (arrow-file-idx-row-id . row) in (base-table-visible-rows db table-name :arrow-file-idx-row-id-p t)
        when (funcall predicate row)
          do (return arrow-file-idx-row-id)))

(defun sql-create-table (db table-name columns)
  (unless (%find-arrow-file-idx-row-id db
                                       "information_schema.tables"
                                       (lambda (row)
                                         (equal table-name (nth 2 row))))
    (sql-insert db "information_schema.tables" (list (list :null *default-schema* table-name "BASE TABLE")))
    (sql-insert db "information_schema.columns" (loop for c in columns
                                                      for idx from 1
                                                      collect  (list :null *default-schema* table-name c idx)))
    (values nil t)))

(defun sql-drop-table (db table-name &key if-exists)
  (with-slots (meta-data) db
    (let* ((batch-file-row-id (%find-arrow-file-idx-row-id db
                                                           "information_schema.tables"
                                                           (lambda (row)
                                                             (and (equal table-name (nth 2 row)) (equal "BASE TABLE" (nth 3 row)))))))
      (when batch-file-row-id
        (sql-delete db "information_schema.tables" (list batch-file-row-id))
        (sql-delete db "information_schema.columns" (loop for c in (base-table-columns db table-name)
                                                          collect (%find-arrow-file-idx-row-id db
                                                                                               "information_schema.columns"
                                                                                               (lambda (row)
                                                                                                 (and (equal table-name (nth 2 row)) (equal c (nth 3 row)))))))

        (setf meta-data (fset:less meta-data table-name)))

      (when (or batch-file-row-id if-exists)
        (values nil t)))))

(defun sql-create-view (db view-name query)
  (unless (%find-arrow-file-idx-row-id db
                                       "information_schema.tables"
                                       (lambda (row)
                                         (equal view-name (nth 2 row))))
    (sql-insert db "information_schema.tables" (list (list :null *default-schema* view-name "VIEW")))
    (sql-insert db "information_schema.views" (list (list :null *default-schema* view-name (prin1-to-string query))))
    (values nil t)))

(defun sql-drop-view (db view-name &key if-exists)
  (let* ((batch-file-row-id (%find-arrow-file-idx-row-id db
                                                         "information_schema.tables"
                                                         (lambda (row)
                                                           (and (equal view-name (nth 2 row)) (equal "VIEW" (nth 3 row)))))))
    (when batch-file-row-id
      (sql-delete db "information_schema.tables" (list batch-file-row-id))
      (let* ((batch-file-row-id (%find-arrow-file-idx-row-id db
                                                             "information_schema.views"
                                                             (lambda (row)
                                                               (equal view-name (nth 2 row))))))
        (sql-delete db "information_schema.views" (list batch-file-row-id))))
    (when (or batch-file-row-id if-exists)
      (values nil t))))

(defun sql-create-index (db)
  (declare (ignore db))
  (values nil t))

(defun sql-drop-index (db)
  (declare (ignore db)))

(defmethod sql-agg-accumulate ((agg cl-bloom::bloom-filter) x)
  (cl-bloom:add agg x)
  agg)

(defmethod sql-agg-finish ((agg cl-bloom::bloom-filter))
  (cffi:with-pointer-to-vector-data (ptr (cl-bloom::filter-array agg))
    (endb/lib/arrow:buffer-to-vector ptr (endb/lib/arrow:vector-byte-size (cl-bloom::filter-array agg)))))

(defun calculate-stats (arrays)
  (let* ((total-length (reduce #'+ (mapcar #'endb/arrow:arrow-length arrays)))
         (bloom-order (* 8 (endb/lib/arrow:vector-byte-size #* (cl-bloom::opt-order total-length)))))
    (labels ((make-col-stats ()
               (fset:map ("count_star" (make-sql-agg :count-star))
                         ("count" (make-sql-agg :count))
                         ("min" (make-sql-agg :min))
                         ("max" (make-sql-agg :max))
                         ("bloom" (make-instance 'cl-bloom::bloom-filter :order bloom-order))))
             (calculate-col-stats (stats kv)
               (destructuring-bind (k . v)
                   kv
                 (let ((col-stats (or (fset:lookup stats k) (make-col-stats))))
                   (fset:with stats k (fset:image
                                       (lambda (agg-k agg-v)
                                         (values agg-k (sql-agg-accumulate agg-v v)))
                                       col-stats))))))
      (let ((stats (reduce
                    (lambda (stats array)
                      (reduce
                       (lambda (stats row)
                         (if (typep row 'endb/arrow:arrow-struct)
                             (reduce #'calculate-col-stats row :initial-value stats)
                             stats))
                       array
                       :initial-value stats))
                    arrays
                    :initial-value (fset:empty-map))))
        (fset:image
         (lambda (k v)
           (values k (fset:image
                      (lambda (k v)
                        (values k (sql-agg-finish v)))
                      v)))
         stats)))))

(defun sql-insert (db table-name values &key column-names)
  (with-slots (buffer-pool meta-data) db
    (let ((columns (base-table-columns db table-name)))
      (when columns
        (let* ((values (if column-names
                           (loop with idxs = (loop for column in columns
                                                   collect (position column column-names :test 'equal))
                                 for row in values
                                 collect (loop for idx in idxs
                                               collect (nth idx row)))
                           values))
               (tx-id (1+ (or (fset:lookup meta-data "_last_tx") 0)))
               (batch-file (format nil "~(~16,'0x~).arrow" tx-id))
               (batch-key (format nil "~A/~A" table-name batch-file))
               (batch (or (car (endb/storage/buffer-pool:buffer-pool-get buffer-pool batch-key))
                          (endb/arrow:make-arrow-array-for
                           (loop for c in columns
                                 collect (cons c :null))))))
          (dolist (row values)
            (endb/arrow:arrow-struct-row-push batch row))

          (endb/storage/buffer-pool:buffer-pool-put buffer-pool batch-key (list batch))

          (let* ((table-md (or (fset:lookup meta-data table-name)
                               (fset:empty-map)))
                 (batch-md (fset:map-union (or (fset:lookup table-md batch-file)
                                               (fset:empty-map))
                                           (fset:map
                                            ("length" (endb/arrow:arrow-length batch))
                                            ("stats" (calculate-stats (list batch)))))))
            (setf meta-data (fset:with meta-data table-name (fset:with table-md batch-file batch-md))))

          (values nil (length values)))))))

(defun sql-delete (db table-name new-batch-file-idx-deleted-row-ids)
  (with-slots (meta-data) db
    (let* ((table-md (reduce
                      (lambda (acc batch-file-idx-row-id)
                        (destructuring-bind (batch-file batch-idx row-id)
                            batch-file-idx-row-id
                          (let* ((batch-md (fset:lookup acc batch-file))
                                 (deletes-md (or (fset:lookup batch-md "deletes") (fset:empty-map)))
                                 (batch-deletes (or (fset:lookup deletes-md batch-idx) (fset:empty-seq))))
                            (fset:with acc batch-file (fset:with batch-md "deletes" (fset:with deletes-md batch-idx (fset:with-last batch-deletes row-id)))))))
                      new-batch-file-idx-deleted-row-ids
                      :initial-value (fset:lookup meta-data table-name))))
      (setf meta-data (fset:with meta-data table-name table-md))
      (values nil (length new-batch-file-idx-deleted-row-ids)))))
