(defpackage :endb/http
  (:use :cl)
  (:export #:make-api-handler)
  (:import-from :bordeaux-threads)
  (:import-from :lack.request)
  (:import-from :com.inuoe.jzon)
  (:import-from :trivial-utf-8)
  (:import-from :endb/sql))
(in-package :endb/http)

(defconstant +http-ok+ 200)
(defconstant +http-created+ 201)
(defconstant +http-bad-request+ 400)
(defconstant +http-not-found+ 404)
(defconstant +http-method-not-allowed+ 405)
(defconstant +http-not-acceptable+ 406)
(defconstant +http-conflict+ 409)
(defconstant +http-unsupported-media-type+ 415)
(defconstant +http-internal-server-error+ 500)

(defun %format-csv-column (col)
  (format nil (if (floatp col)
                  "~,3f"
                  "~A")
          (cond
            ((eq :null col) "NULL")
            ((eq t col) "TRUE")
            ((null col) "FALSE")
            (t col))))

(defun make-api-handler (db)
  (let ((write-lock (bt:make-lock)))
    (lambda (env)
      (let ((req (lack.request:make-request env)))
        (if (equal "/sql" (lack.request:request-path-info req))
            (if (member (lack.request:request-method req) '(:get :post))
                (if (and (eq :post (lack.request:request-method req))
                         (not (member (lack.request:request-content-type req) '("application/sql" "application/x-www-form-urlencoded") :test 'equal)))
                    (list +http-unsupported-media-type+ nil nil)
                    (let* ((write-db (endb/sql:begin-write-tx db))
                           (original-md (endb/sql/expr:db-meta-data write-db))
                           (sql (if (and (eq :post (lack.request:request-method req))
                                         (equal "application/sql" (lack.request:request-content-type req)))
                                    (trivial-utf-8:utf-8-bytes-to-string (lack.request:request-content req))
                                    (cdr (assoc "q" (lack.request:request-parameters req) :test 'equal))))
                           (accept (gethash "accept" (lack.request:request-headers req))))
                      (if sql
                          (if (member accept '("*/*" "application/json" "application/x-ndjson" "text/csv") :test 'equal)
                              (multiple-value-bind (result result-code)
                                  (endb/sql:execute-sql write-db sql)
                                (cond
                                  ((or result (and (listp result-code)
                                                   (not (null result-code))))
                                   (lambda (responder)
                                     (let ((writer (funcall responder (list +http-ok+ (list :content-type
                                                                                            (cond
                                                                                              ((equal "application/x-ndjson" accept)
                                                                                               "application/x-ndjson")
                                                                                              ((equal "text/csv" accept)
                                                                                               "text/csv")
                                                                                              (t "application/json"))))) ))
                                       (cond
                                         ((equal "application/x-ndjson" accept)
                                          (loop for row in result
                                                do (loop for column in row
                                                         for column-name in result-code
                                                         do (funcall writer (with-output-to-string (out)
                                                                              (com.inuoe.jzon:with-writer (writer :stream out)
                                                                                (com.inuoe.jzon:with-object writer
                                                                                  (com.inuoe.jzon:write-key writer column-name)
                                                                                  (com.inuoe.jzon:write-value writer column)))
                                                                              (write-char #\NewLine out))))
                                                finally (funcall writer nil :close t)))
                                         ((equal "text/csv" accept)
                                          (progn
                                            (funcall writer (format nil "~{~A~^,~}~%" result-code))
                                            (loop for row in result
                                                  do (funcall writer (format nil "~{~A~^,~}~%"
                                                                             (loop for column in row
                                                                                   collect (%format-csv-column column))))
                                                  finally (funcall writer nil :close t))))
                                         (t (progn (funcall writer "[")
                                                   (loop for row in result
                                                         do (funcall writer (com.inuoe.jzon:stringify row))
                                                         finally (funcall writer "]" :close t))))))))
                                  (result-code (if (eq :get (lack.request:request-method req))
                                                   (list +http-method-not-allowed+ nil nil)
                                                   (bt:with-lock-held (write-lock)
                                                     (if (eq original-md (endb/sql/expr:db-meta-data db))
                                                         (progn
                                                           (setf db (endb/sql:commit-write-tx db write-db))
                                                           (cond
                                                             ((equal "application/x-ndjson" accept)
                                                              (list +http-created+
                                                                    '(:content-type "application/x-ndjson")
                                                                    (list (with-output-to-string (out)
                                                                            (com.inuoe.jzon:with-writer (writer :stream out)
                                                                              (com.inuoe.jzon:write-object writer :result result-code))
                                                                            (write-char #\NewLine out)))))
                                                             ((equal "text/csv" accept)
                                                              (format nil "result~%~A~%" (%format-csv-column result-code)))
                                                             (t (list +http-created+
                                                                      '(:content-type "application/json")
                                                                      (list (com.inuoe.jzon:stringify result-code))))))
                                                         (list +http-conflict+ nil nil)))))
                                  (t (list +http-internal-server-error+ nil nil))))
                              (list +http-not-acceptable+ nil nil))
                          (list +http-bad-request+ nil nil))))
                (list +http-method-not-allowed+ nil nil))
            (list +http-not-found+ nil nil))))))
