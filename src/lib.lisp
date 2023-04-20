(defpackage :endb/lib
  (:use :cl)
  (:export #:parse-sql #:write-arrow-array-to-ipc-buffer
           #:read-arrow-array-from-ipc-pointer #:read-arrow-array-from-ipc-buffer #:buffer-to-vector)
  (:import-from :endb/arrow)
  (:import-from :cffi)
  (:import-from :cl-ppcre)
  (:import-from :asdf)
  (:import-from :uiop))
(in-package :endb/lib)

(cffi:define-foreign-library libendb
  (t (:default "libendb")))

(defvar *initialized* nil)

(defun %init-lib ()
  (unless *initialized*
    (pushnew (or (uiop:pathname-directory-pathname (uiop:argv0))
                 (asdf:system-relative-pathname :endb "target/"))
             cffi:*foreign-library-directories*)
    (cffi:use-foreign-library libendb)
    (setf *initialized* t)))

(cffi:defcenum Keyword
  :select
  :from
  :where
  :group-by
  :having
  :order-by
  :<
  :<=
  :>
  :>=
  :=
  :<>
  :is
  :in
  :in-query
  :between
  :like
  :case
  :exists
  :scalar-subquery
  :else
  :+
  :-
  :*
  :/
  :%
  :<<
  :>>
  :and
  :or
  :not
  :function
  :aggregate-function
  :count
  :count-star
  :avg
  :sum
  :min
  :max
  :total
  :group_concat
  :cast
  :asc
  :desc
  :distinct
  :all
  :true
  :false
  :null
  :limit
  :offset
  :join
  :type
  :left
  :inner
  :on
  :except
  :intersect
  :union
  :union-all
  :values
  :insert
  :column-names
  :delete
  :update
  :create-index
  :drop-index
  :create-view
  :drop-view
  :if-exists
  :create-table
  :drop-table)

(cffi:defcenum Ast_Tag
  :List
  :KW
  :Integer
  :Float
  :Id
  :String
  :Binary)

(cffi:defcstruct Id_Union
  (start :int32)
  (end :int32))

(cffi:defcstruct String_Union
  (start :int32)
  (end :int32))

(cffi:defcstruct Binary_Union
  (start :int32)
  (end :int32))

(cffi:defcstruct Integer_Union
  (n :int64))

(cffi:defcstruct Float_Union
  (n :double))

(cffi:defcstruct KW_Union
  (kw :int32))

(cffi:defcstruct List_Union
  (cap :uint64)
  (ptr :pointer)
  (len :uint64))

(cffi:defcunion Ast_Union
  (list (:struct List_Union))
  (kw (:struct KW_Union))
  (integer (:struct Integer_Union))
  (float (:struct float_Union))
  (id (:struct Id_Union))
  (string (:struct String_Union))
  (binary (:struct Binary_Union)))

(cffi:defcstruct Ast
  (tag :int32)
  (value (:union Ast_Union)))

(cffi:defcfun "endb_ast_vec_len" :size
  (vec (:pointer (:struct List_Union))))

(cffi:defcfun "endb_ast_vec_ptr" :pointer
  (vec (:pointer (:struct List_Union))))

(cffi:defcfun "endb_ast_size" :size)

(cffi:defcfun "endb_ast_vec_element" (:pointer (:struct Ast))
  (vec (:pointer (:struct List_union)))
  (idx :size))

(cffi:defcfun "endb_parse_sql" :void
  (input (:pointer :char))
  (on_success :pointer)
  (on_error :pointer))

(defstruct ast-builder (acc (list nil)))

(defparameter kw-array (loop with kw-enum-hash = (cffi::value-keywords (cffi::parse-type 'Keyword))
                             with acc = (make-array (hash-table-count kw-enum-hash)
                                                    :element-type 'keyword
                                                    :initial-element :select)
                             for k being the hash-key
                               using (hash-value v)
                                 of kw-enum-hash
                             do (setf (aref acc k) v)
                             finally (return acc)))

(defun hex-to-binary (hex)
  (loop with acc = (make-array (/ (length hex) 2) :element-type '(unsigned-byte 8))
        with tmp = (make-string 2)
        for idx below (length hex) by 2
        for out-idx from 0
        do (setf (schar tmp 0) (aref hex idx))
           (setf (schar tmp 1) (aref hex (1+ idx)))
           (setf (aref acc out-idx) (parse-integer tmp :radix 16))
        finally (return acc)))

(defun visit-ast (input builder ast)
  (loop with queue = (list ast)
        with acc = (ast-builder-acc builder)
        with stride = (cffi:foreign-type-size '(:struct Ast))
        while queue
        for ast = (pop queue)
        do (case ast
             (:start-list (push () acc))
             (:end-list (push (pop acc) (first acc)))
             (t
              (cffi:with-foreign-slots ((tag value) ast (:struct Ast))
                (ecase tag
                  (0 (progn
                       (push :end-list queue)
                       (loop with ptr = (endb-ast-vec-ptr value)
                             for idx below (endb-ast-vec-len value)
                             for offset from 0 by stride
                             do (push (cffi:inc-pointer ptr offset) queue))
                       (push :start-list queue)))
                  (1 (cffi:with-foreign-slots ((kw) value (:struct KW_Union))
                       (push (aref kw-array kw) (first acc))))
                  (2 (cffi:with-foreign-slots ((n) value (:struct Integer_Union))
                       (push n (first acc))))
                  (3 (cffi:with-foreign-slots ((n) value (:struct Float_Union))
                       (push n (first acc))))
                  (4 (cffi:with-foreign-slots ((start end) value (:struct Id_Union))
                       (push (make-symbol (subseq input start end)) (first acc))))
                  (5 (cffi:with-foreign-slots ((start end) value (:struct String_Union))
                       (push (subseq input start end) (first acc))))
                  (6 (cffi:with-foreign-slots ((start end) value (:struct Binary_Union))
                       (push (hex-to-binary (subseq input start end)) (first acc))))))))))

(defun strip-ansi-escape-codes (s)
  (cl-ppcre:regex-replace-all "\\[3\\d(?:;\\d+;\\d+)?m(.+?)\\[0m" s "\\1"))

(define-condition sql-parse-error (error)
  ((message :initarg :message :reader sql-parse-error-message))
  (:report (lambda (condition stream)
             (write (strip-ansi-escape-codes (sql-parse-error-message condition)) :stream stream))))

(defvar *parse-sql-on-success*)

(cffi:defcallback parse-sql-on-success :void
    ((ast (:pointer (:struct Ast))))
  (funcall *parse-sql-on-success* ast))

(cffi:defcallback parse-sql-on-error :void
    ((err :string))
  (error 'sql-parse-error :message err))

(defun parse-sql (input)
  (%init-lib)
  (let* ((ast-builder (make-ast-builder))
         (*parse-sql-on-success* (lambda (ast)
                                   (visit-ast input ast-builder ast))))
    (if (typep input 'base-string)
        (cffi:with-pointer-to-vector-data (ptr input)
          (endb-parse-sql ptr (cffi:callback parse-sql-on-success) (cffi:callback parse-sql-on-error)))
        (cffi:with-foreign-string (ptr input)
          (endb-parse-sql ptr (cffi:callback parse-sql-on-success) (cffi:callback parse-sql-on-error))))
    (caar (ast-builder-acc ast-builder))))

;; (time
;;  (let ((acc))
;;    (dotimes (n 100000)
;;      (setf acc (parse-sql "SELECT a, b, 123, myfunc(b) FROM table_1 WHERE a > b AND b < 100 ORDER BY a DESC, b")))
;;    acc))

(cffi:defbitfield arrow-flags
  (:dictionary-encoded 1)
  (:nullable 2)
  (:map-keys-sorted 4))

(cffi:defcstruct ArrowSchema
  (format :pointer)
  (name :pointer)
  (metadata :pointer)
  (flags arrow-flags)
  (n_children :int64)
  (children (:pointer (:pointer (:struct ArrowSchema))))
  (dictionary (:pointer (:struct ArrowSchema)))
  (release :pointer)
  (private_data :pointer))

(defvar *arrow-schema-release*
  (lambda (c-schema)
    (cffi:with-foreign-slots ((format name n_children children release) c-schema (:struct ArrowSchema))
      (unless (cffi:null-pointer-p release)
        (cffi:foreign-free format)
        (cffi:foreign-free name)
        (unless (cffi:null-pointer-p children)
          (dotimes (n n_children)
            (let ((child-ptr (cffi:mem-aref children :pointer n)))
              (funcall *arrow-schema-release* child-ptr)
              (cffi:foreign-free child-ptr)))
          (cffi:foreign-free children))
        (setf release (cffi:null-pointer))))))

(cffi:defcallback arrow-schema-release :void
    ((schema (:pointer (:struct ArrowSchema))))
  (funcall *arrow-schema-release* schema))

(cffi:defcstruct ArrowArray
  (length :int64)
  (null_count :int64)
  (offset :int64)
  (n_buffers :int64)
  (n_children :int64)
  (buffers (:pointer (:pointer :void)))
  (children (:pointer (:pointer (:struct ArrowArray))))
  (dictionary (:pointer (:struct ArrowArray)))
  (release :pointer)
  (private_data :pointer))

(defvar *arrow-array-release*
  (lambda (c-array)
    (cffi:with-foreign-slots ((buffers n_children children release) c-array (:struct ArrowArray))
      (unless (cffi:null-pointer-p release)
        (unless (cffi:null-pointer-p buffers)
          (cffi:foreign-free buffers))
        (unless (cffi:null-pointer-p children)
          (dotimes (n n_children)
            (let ((child-ptr (cffi:mem-aref children :pointer n)))
              (funcall *arrow-array-release* child-ptr)
              (cffi:foreign-free child-ptr)))
          (cffi:foreign-free children))
        (setf release (cffi:null-pointer))))))

(cffi:defcallback arrow-array-release :void
    ((array (:pointer (:struct ArrowArray))))
  (funcall *arrow-array-release* array))

(cffi:defcstruct ArrowArrayStream
  (get_schema :pointer)
  (get_next :pointer)
  (get_last_error :pointer)
  (release :pointer)
  (private_data :pointer))

(defvar *arrow-array-stream-get-schema*)

(cffi:defcallback arrow-array-stream-get-schema :int
    ((stream (:pointer (:struct ArrowArrayStream)))
     (schema (:pointer (:struct ArrowSchema))))
  (funcall *arrow-array-stream-get-schema* stream schema))

(defvar *arrow-array-stream-get-next*)

(cffi:defcallback arrow-array-stream-get-next :int
    ((stream (:pointer (:struct ArrowArrayStream)))
     (array (:pointer (:struct ArrowArray))))
  (funcall *arrow-array-stream-get-next* stream array))

(defvar *arrow-array-stream-get-last-error*)

(cffi:defcallback arrow-array-stream-get-last-error :string
    ((stream (:pointer (:struct ArrowArrayStream))))
  (funcall *arrow-array-stream-get-last-error* stream))

(defvar *arrow-array-stream-release*
  (lambda (c-stream)
    (cffi:with-foreign-slots ((release) c-stream (:struct ArrowArrayStream))
      (unless (cffi:null-pointer-p release)
        (setf release (cffi:null-pointer))))))

(cffi:defcallback arrow-array-stream-release :void
    ((stream (:pointer (:struct ArrowArrayStream))))
  (funcall *arrow-array-stream-release* stream))

(cffi:defcallback arrow-array-stream-producer-on-error :void
    ((err :string))
  (error err))

(cffi:defcfun "endb_arrow_array_stream_producer" :void
  (stream (:pointer (:struct ArrowArrayStream)))
  (buffer-ptr :pointer)
  (buffer-size :size)
  (on-error :pointer))

(defvar *arrow-array-stream-consumer-init-stream*
  (lambda (c-stream)
    (cffi:with-foreign-slots ((get_schema get_next get_last_error release) c-stream (:struct ArrowArrayStream))
      (setf get_schema (cffi:callback arrow-array-stream-get-schema))
      (setf get_next (cffi:callback arrow-array-stream-get-next))
      (setf get_last_error (cffi:callback arrow-array-stream-get-last-error))
      (setf release (cffi:callback arrow-array-stream-release)))))

(cffi:defcallback arrow-array-stream-consumer-init-stream :void
    ((stream (:pointer (:struct ArrowArrayStream))))
  (funcall *arrow-array-stream-consumer-init-stream* stream))

(defvar *arrow-array-stream-consumer-on-success*)

(cffi:defcallback arrow-array-stream-consumer-on-success :void
    ((buffer-ptr :pointer)
     (buffer-size :size))
  (funcall *arrow-array-stream-consumer-on-success* buffer-ptr buffer-size))

(cffi:defcallback arrow-array-stream-consumer-on-error :void
    ((err :string))
  (error err))

(cffi:defcfun "endb_arrow_array_stream_consumer" :void
  (init-stream :pointer)
  (on-success :pointer)
  (on-error :pointer))

(defun export-arrow-schema (field-name array c-schema)
  (let ((ptrs))
    (labels ((track-alloc (ptr)
               (push ptr ptrs)
               ptr))
      (handler-case
          (cffi:with-foreign-slots ((format name metadata flags n_children children dictionary release) c-schema (:struct ArrowSchema))
            (setf format (track-alloc (cffi:foreign-string-alloc (endb/arrow:arrow-data-type array))))
            (setf name (track-alloc (cffi:foreign-string-alloc field-name)))
            (setf metadata (cffi:null-pointer))
            (setf flags '(:nullable))

            (let ((children-alist (endb/arrow:arrow-children array)))
              (setf n_children (length children-alist))
              (if children-alist
                  (let ((children-ptr (track-alloc (cffi:foreign-alloc :pointer :count (length children-alist)))))
                    (loop for (k . v) in children-alist
                          for n from 0
                          for schema-ptr = (track-alloc (cffi:foreign-alloc '(:struct ArrowSchema)))
                          do (export-arrow-schema k v schema-ptr)
                             (setf (cffi:mem-ref children-ptr :pointer n) schema-ptr))
                    (setf children children-ptr))
                  (setf children (cffi:null-pointer))))

            (setf dictionary (cffi:null-pointer))
            (setf release (cffi:callback arrow-schema-release)))
        (error (e)
          (dolist (ptr ptrs)
            (cffi:foreign-free ptr))
          (error e))))))

(defun export-arrow-array (array c-array)
  (let ((ptrs))
    (labels ((track-alloc (ptr)
               (push ptr ptrs)
               ptr))
      (handler-case
          (cffi:with-foreign-slots ((length null_count offset n_buffers n_children buffers children dictionary release) c-array (:struct ArrowArray))
            (setf length (endb/arrow:arrow-length array))
            (setf null_count (endb/arrow:arrow-null-count array))
            (setf offset 0)

            (let ((buffers-list (endb/arrow:arrow-buffers array)))
              (setf n_buffers (length buffers-list))
              (if buffers-list
                  (let ((buffers-ptr (track-alloc (cffi:foreign-alloc :pointer :count (length buffers-list)))))
                    (loop for b in buffers-list
                          for n from 0
                          do (if b
                                 (cffi:with-pointer-to-vector-data (ptr #+sbcl (sb-ext:array-storage-vector b)
                                                                        #-sbcl b)
                                   (setf (cffi:mem-aref buffers-ptr :pointer n) ptr))
                                 (setf (cffi:mem-aref buffers-ptr :pointer n) (cffi:null-pointer))))
                    (setf buffers buffers-ptr))
                  (setf buffers (cffi:null-pointer))))

            (let ((children-alist (endb/arrow:arrow-children array)))
              (setf n_children (length children-alist))
              (if children-alist
                  (let ((children-ptr (track-alloc (cffi:foreign-alloc :pointer :count (length children-alist)))))
                    (loop for (nil . c) in children-alist
                          for n from 0
                          for array-ptr = (track-alloc (cffi:foreign-alloc '(:struct ArrowArray)))
                          do (export-arrow-array c array-ptr)
                             (setf (cffi:mem-ref children-ptr :pointer n) array-ptr)
                             (setf children children-ptr)))
                  (setf children (cffi:null-pointer))))

            (setf dictionary (cffi:null-pointer))
            (setf release (cffi:callback arrow-array-release)))
        (error (e)
          (dolist (ptr ptrs)
            (cffi:foreign-free ptr))
          (error e))))))

(cffi:defcfun "memcpy" :pointer
  (dest :pointer)
  (src :pointer)
  (n :size))

(defun buffer-to-vector (buffer-ptr buffer-size &optional buffer)
  (let ((out (or buffer (make-array buffer-size :element-type '(unsigned-byte 8)))))
    (cffi:with-pointer-to-vector-data (out-ptr out)
      (endb/lib::memcpy out-ptr buffer-ptr buffer-size))
    out))

(defun write-arrow-array-to-ipc-buffer (array on-success)
  (%init-lib)
  (let ((last-error (cffi:null-pointer))
        (arrays (list array)))
    (unwind-protect
         (#+sbcl sb-sys:with-pinned-objects
          #+sbcl (arrays)
          #-sbcl progn
           (let* ((*arrow-array-stream-get-schema* (lambda (c-stream c-schema)
                                                     (declare (ignore c-stream))
                                                     (handler-case
                                                         (progn
                                                           (export-arrow-schema "" array c-schema)
                                                           0)
                                                       (error (e)
                                                         (unless (cffi:null-pointer-p last-error)
                                                           (cffi:foreign-free last-error))
                                                         (setf last-error (cffi:foreign-string-alloc (princ-to-string e)))
                                                         1))
                                                     0))
                  (*arrow-array-stream-get-next* (lambda (c-stream c-array)
                                                   (declare (ignore c-stream))
                                                   (if arrays
                                                       (handler-case
                                                           (progn
                                                             (export-arrow-array (pop arrays) c-array)
                                                             0)
                                                         (error (e)
                                                           (unless (cffi:null-pointer-p last-error)
                                                             (cffi:foreign-free last-error))
                                                           (setf last-error (cffi:foreign-string-alloc (princ-to-string e)))
                                                           1))
                                                       (cffi:with-foreign-slots ((release) c-array (:struct ArrowArray))
                                                         (setf release (cffi:null-pointer))
                                                         0))))
                  (*arrow-array-stream-get-last-error* (lambda (c-stream)
                                                         (declare (ignore c-stream))
                                                         last-error))
                  (*arrow-array-stream-consumer-on-success* on-success))
             (endb-arrow-array-stream-consumer (cffi:callback arrow-array-stream-consumer-init-stream)
                                               (cffi:callback arrow-array-stream-consumer-on-success)
                                               (cffi:callback arrow-array-stream-consumer-on-error))))
      (unless (cffi:null-pointer-p last-error)
        (cffi:foreign-free last-error)))))

(defstruct arrow-schema format name children)

(defun import-arrow-schema (c-schema)
  (cffi:with-foreign-slots ((format name n_children children) c-schema (:struct ArrowSchema))
    (make-arrow-schema :format (cffi:foreign-string-to-lisp format)
                       :name (cffi:foreign-string-to-lisp name)
                       :children (loop for n below n_children
                                       collect (import-arrow-schema (cffi:mem-ref children :pointer n))))))

(defun import-arrow-array (schema c-array)
  (cffi:with-foreign-slots ((length null_count n_buffers buffers n_children children) c-array (:struct ArrowArray))
    (let* ((format (arrow-schema-format schema))
           (array-class (endb/arrow:arrow-class-for-format format))
           (array-children (loop for n below n_children
                                 for schema in (arrow-schema-children schema)
                                 collect (cons (arrow-schema-name schema)
                                               (import-arrow-array schema (cffi:mem-ref children :pointer n)))))
           (array (apply #'make-instance array-class
                         (append (list :length length
                                       :null-count null_count)
                                 (when array-children
                                   (list :children array-children))))))
      (unless (cffi:null-pointer-p buffers)
        (loop for n below n_buffers
              for b in (endb/arrow:arrow-buffers array)
              for src = (cffi:mem-aref buffers :pointer n)
              when (and b (not (cffi:null-pointer-p src)))
                do (cffi:with-pointer-to-vector-data (dest b)
                     (memcpy dest src length))))
      array)))

(defun read-arrow-array-from-ipc-pointer (buffer-ptr buffer-size)
  (cffi:with-foreign-objects ((c-stream '(:struct ArrowArrayStream))
                              (c-schema '(:struct ArrowSchema))
                              (c-array '(:struct ArrowArray)))
    (endb-arrow-array-stream-producer
     c-stream
     buffer-ptr
     buffer-size
     (cffi:callback arrow-array-stream-producer-on-error))
    (cffi:with-foreign-slots ((get_schema get_next get_last_error release) c-stream (:struct ArrowArrayStream))
      (unwind-protect
           (let ((result (cffi:foreign-funcall-pointer get_schema () :pointer c-stream :pointer c-schema :int)))
             (if (zerop result)
                 (cffi:with-foreign-slots ((release) c-schema (:struct ArrowSchema))
                   (unwind-protect
                        (let ((acc)
                              (schema (import-arrow-schema c-schema)))
                          (loop
                            (let ((result (cffi:foreign-funcall-pointer get_next () :pointer c-stream :pointer c-array :int)))
                              (cffi:with-foreign-slots ((release) c-array (:struct ArrowArray))
                                (unwind-protect
                                     (if (zerop result)
                                         (if (cffi:null-pointer-p release)
                                             (return acc)
                                             (push (import-arrow-array schema c-array) acc))
                                         (error (cffi:foreign-funcall-pointer get_last_error () :pointer c-stream :string)))
                                  (unless (cffi:null-pointer-p release)
                                    (cffi:foreign-funcall-pointer release () :pointer c-array :void)))))))
                     (unless (cffi:null-pointer-p release)
                       (cffi:foreign-funcall-pointer release () :pointer c-schema :void))))
                 (error (cffi:foreign-funcall-pointer get_last_error () :pointer c-stream :string))))
        (unless (cffi:null-pointer-p release)
          (cffi:foreign-funcall-pointer release () :pointer c-stream :void))))))

(defun read-arrow-array-from-ipc-buffer (buffer)
  (%init-lib)
  (check-type buffer (vector (unsigned-byte 8)))
  (cffi:with-pointer-to-vector-data (buffer-ptr buffer)
    (read-arrow-array-from-ipc-pointer buffer-ptr (length buffer))))
