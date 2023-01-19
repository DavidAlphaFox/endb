(defpackage :endb/sql/parser
  (:use :cl :esrap)
  (:export #:parse-sql)
  (:import-from :esrap))
(in-package :endb/sql/parser)

(defun %remove-nil (items)
  (remove-if #'null items))

(defun %flatten-list (items)
  (if (= 1 (length items))
      items
      (cons (first items)
            (remove-if #'null
                       (apply #'concatenate 'list (second items))))))

(defrule comma
    ","
  (:constant nil))

(defrule left-brace
    "("
  (:constant nil))

(defrule right-brace
    ")"
  (:constant nil))

(defrule ws
    (+ (or #\Space #\Tab #\Newline))
  (:constant nil))

(defrule identifier
    (and (alpha-char-p character) (* (alphanumericp character)))
  (:text t)
  (:lambda (items)
    (make-symbol items)))

(defrule numeric-literal
    (+ (digit-char-p character))
  (:text t)
  (:lambda (items)
    (parse-integer items)))

(defrule string-literal
    (and "'" (* (not "'")) "'")
  (:text t)
  (:lambda (items)
    (subseq items 1 (1- (length items)))))

(defrule null-literal
    (~ "NULL")
  (:constant :sql/null))

(defrule literal-value
    (or numeric-literal
        string-literal
        null-literal))

(defrule %expr-or
    (and expr-or ws (~ "OR") ws expr-and)
  (:function %remove-nil)
  (:destructure (expr-1 or expr-2)
    (declare (ignore or))
    (list :or expr-1 expr-2)))

(defrule expr-or
    (or %expr-or expr-and))

(defrule %expr-and
    (and expr-and ws (~ "AND") ws expr-not)
  (:function %remove-nil)
  (:destructure (expr-1 and expr-2)
    (declare (ignore and))
    (list :and expr-1 expr-2)))

(defrule expr-and
    (or %expr-and expr-not))

(defrule %expr-not
    (and (~ "NOT") ws expr-boolean-primary)
  (:function %remove-nil)
  (:destructure (not expr)
    (declare (ignore not))
    (list :not expr)))

(defrule expr-not
    (or %expr-not expr-boolean-primary))

(defrule expr-compare
    (and expr-boolean-primary (? ws) (or "<>" "<=" ">=" "<"  ">" "=" ) (? ws) expr-add)
  (:function %remove-nil)
  (:destructure (expr-1 op expr-2)
    (list (intern op :keyword) expr-1 expr-2)))

(defrule expr-is
    (and expr-boolean-primary ws (and (~ "IS") (? (and ws (~ "NOT")))) ws expr-add)
  (:function %remove-nil)
  (:destructure (expr-1 is-not expr-2)
    (if (second is-not)
        (list :not (list :is expr-1 expr-2))
        (list :is expr-1 expr-2))))

(defrule expr-between
    (and expr-boolean-primary ws (and (? (and (~ "NOT") ws)) (~ "BETWEEN")) ws expr-add ws (~ "AND") ws expr-add)
  (:function %remove-nil)
  (:destructure (expr-1 not-between expr-2 and expr-3)
    (declare (ignore and))
    (if (first not-between)
        (list :not (list :between expr-1 expr-2 expr-3))
        (list :between expr-1 expr-2 expr-3))))

(defrule expr-in
    (and expr-boolean-primary ws (and (? (and (~ "NOT") ws)) (~ "IN")) (? ws) left-brace (? ws) expr-list (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (expr not-in expr-list)
    (if (first not-in)
        (list :not (list :in expr expr-list))
        (list :in expr expr-list))))

(defrule expr-exists
    (and (~ "EXISTS") (? ws) subquery)
  (:function %remove-nil)
  (:destructure (exists subquery)
    (declare (ignore exists))
    (list :exists subquery)))

(defrule expr-boolean-primary
    (or expr-compare
        expr-is
        expr-between
        expr-in
        expr-exists
        expr-add))

(defrule %expr-add
    (and expr-add (? ws) (or "+" "-") (? ws) expr-mult)
  (:function %remove-nil)
  (:destructure (expr-1 op expr-2)
    (list (intern op :keyword) expr-1 expr-2)))

(defrule expr-add
    (or %expr-add expr-mult))

(defrule %expr-mult
    (and expr-mult (? ws) (or "*" "/" "%") (? ws) expr-unary)
  (:function %remove-nil)
  (:destructure (expr-1 op expr-2)
    (list (intern op :keyword) expr-1 expr-2)))

(defrule expr-mult
    (or %expr-mult expr-unary))

(defrule %expr-unary
    (and (or "+" "-") (? ws) expr-primary)
  (:function %remove-nil)
  (:destructure (op expr)
    (list (intern op :keyword) expr)))

(defrule expr-unary
    (or %expr-unary expr-primary))

(defrule %expr-case-when
    (and (~ "WHEN") ws expr ws (~ "THEN") ws expr ws)
  (:function %remove-nil)
  (:destructure (when expr-1 then expr-2)
    (declare (ignore when then))
    (list :when expr-1 expr-2)))

(defrule %expr-case-else
    (and (~ "ELSE") ws expr ws)
  (:function %remove-nil)
  (:destructure (else expr)
    (declare (ignore else))
    (list :else expr)))

(defrule expr-case
    (and (~ "CASE") ws
         (? (and (! (~ "WHEN")) expr ws))
         (+ %expr-case-when)
         (? %expr-case-else)
         (~ "END"))
  (:destructure (case ws1 (&optional not-when expr ws2) whens else end)
    (declare (ignore case ws1 not-when ws2 end))
    (concatenate 'list
                 (list :case)
                 (when expr
                   (list expr))
                 (when whens
                   (list whens))
                 (when else
                   (list else)))))

(defrule %expr-count-star
    (and (~ "COUNT") (? ws) left-brace (? ws) star (? ws) right-brace)
  (:lambda (items)
    (declare (ignore items))
    (list :function :count-star)))

(defrule %expr-function
    (and identifier (? ws) left-brace (? ws) expr-list (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (identifier expr-list)
    (list :function (intern (string-upcase (symbol-name identifier)) :keyword) expr-list)))

(defrule %expr-function-distinct
    (and identifier (? ws) left-brace (? ws) (~ "DISTINCT") ws expr-list (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (identifier distinct expr-list)
    (declare (ignore distinct))
    (list :function (intern (string-upcase (symbol-name identifier)) :keyword) :distinct expr-list)))

(defrule expr-function
    (or %expr-count-star %expr-function-distinct %expr-function))

(defrule %expr-column
    (and identifier "." identifier)
  (:destructure (table dot column)
    (declare (ignore dot))
    (make-symbol (format nil "~A.~A"
                         (symbol-name table)
                         (symbol-name column)))))

(defrule expr-column
    (or %expr-column identifier))

(defrule subquery
    (and left-brace (? ws) select-stmt (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (select-stmt)
    (list :subquery select-stmt)))

(defrule expr-paren
    (and left-brace (? ws) expr (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (expr)
    expr))

(defrule expr-primary
    (or subquery
        expr-paren
        expr-case
        expr-function
        literal-value
        expr-column))

(defrule expr-list
    (and expr (* (and (? ws) comma (? ws) expr)))
  (:lambda (items)
    (%flatten-list items)))

(defrule expr expr-or)

(defrule column-def
    (and identifier (? (and ws identifier)) (? (and left-brace  numeric-literal right-brace)) (? (and ws (~ "PRIMARY") ws (~ "KEY"))))
  (:destructure (identifier &rest type-def)
    (declare (ignore type-def))
    identifier))

(defrule column-def-list
    (and column-def (* (and (? ws) comma (? ws) column-def)))
  (:lambda (items)
    (%flatten-list items)))

(defrule create-table-stmt
    (and (~ "CREATE") ws (~ "TABLE") ws identifier (? ws)
         left-brace (? ws) column-def-list (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (create table identifier column-def-list)
    (declare (ignore create table))
    (list :create-table identifier column-def-list)))

(defrule indexed-column
    (and identifier (? (and ws (or (~ "ASC") (~ "DESC")))))
  (:constant nil))

(defrule indexed-column-list
    (and indexed-column (* (and (? ws) comma (? ws) indexed-column)))
  (:constant nil))

(defrule create-index-stmt
    (and (~ "CREATE") ws (~ "INDEX") ws identifier ws (~ "ON") ws identifier (? ws)
         left-brace (? ws) indexed-column-list (? ws) right-brace)
  (:constant nil))

(defrule values-stmt
    (and (~ "VALUES") (? ws) left-brace (? ws) expr-list (? ws) right-brace)
  (:function %remove-nil)
  (:destructure (values expr-list)
    (declare (ignore values))
    (list :values expr-list)))

(defrule identifier-list
    (and identifier (* (and (? ws) comma (? ws) identifier)))
  (:lambda (items)
    (%flatten-list items)))

(defrule %insert-stmt
    (and (~ "INSERT") ws (~ "INTO") ws identifier (? ws) select-core)
  (:function %remove-nil)
  (:destructure (insert into identifier select)
    (declare (ignore insert into))
    (list :insert identifier select)))

(defrule %insert-stmt-identifier-list
    (and (~ "INSERT") ws (~ "INTO") ws identifier (? ws)
         left-brace (? ws) identifier-list (? ws) right-brace (? ws)
         select-core)
  (:function %remove-nil)
  (:destructure (insert into identifier identifier-list select)
    (declare (ignore insert into))
    (list :insert identifier select identifier-list)))

(defrule insert-stmt
    (or %insert-stmt %insert-stmt-identifier-list))

(defrule star
    "*"
  (:lambda (items)
    (declare (ignore items))
    (list :star)))

(defrule %table-or-subquery-table-name
    identifier
  (:lambda (table-name)
    (cons table-name table-name)))

(defrule %table-or-subquery-as-alias
    (and (or identifier subquery) ws (~ "AS") ws identifier)
  (:function %remove-nil)
  (:destructure (table-or-subquery as alias)
    (declare (ignore as))
    (cons table-or-subquery alias)))

(defrule %table-or-subquery-alias
    (and (or identifier subquery) ws (! (or (~ "ORDER") (~ "WHERE"))) identifier)
  (:function %remove-nil)
  (:destructure (table-or-subquery not-order-or-where as-identifier)
    (declare (ignore not-order-or-where))
    (cons table-or-subquery as-identifier)))

(defrule table-or-subquery
    (or %table-or-subquery-as-alias %table-or-subquery-alias %table-or-subquery-table-name))

(defrule table-subquery-list
    (and table-or-subquery (* (and (? ws) comma (? ws) table-or-subquery)))
  (:lambda (items)
    (%flatten-list items)))

(defrule from-clause
    (and (~ "FROM") ws table-subquery-list)
  (:function %remove-nil)
  (:destructure (from table-or-subquery-list)
    (declare (ignore from))
    (list :from table-or-subquery-list)))

(defrule where-clause
    (and (~ "WHERE") ws expr)
  (:function %remove-nil)
  (:destructure (where expr)
    (declare (ignore where))
    (list :where expr)))

(defrule %result-column-expr
    expr
  (:lambda (expr)
    (cons expr :sql/unassigned)))

(defrule %result-column-as
    (and expr ws (~ "AS") ws identifier)
  (:function %remove-nil)
  (:destructure (expr as as-identifier)
    (declare (ignore as))
    (cons expr as-identifier)))

(defrule %result-column-alias
    (and expr ws (! (~ "FROM")) identifier)
  (:function %remove-nil)
  (:destructure (expr not-from as-identifier)
    (declare (ignore not-from))
    (cons expr as-identifier)))

(defrule result-column
    (or star %result-column-as %result-column-alias %result-column-expr))

(defrule result-column-list
    (and result-column (* (and (? ws) comma (? ws) result-column)))
  (:lambda (items)
    (%flatten-list items)))

(defrule %select-core
    (and (~ "SELECT") (? (and ws (or (~ "ALL")
                                     (~ "DISTINCT"))))
         ws result-column-list
         (? (and ws from-clause))
         (? (and ws where-clause)))
  (:destructure (select distinct-all ws1 result-column-list (&optional ws2 from-clause) (&optional ws3 where-clause))
    (declare (ignore select ws1 ws2 ws3))
    (concatenate 'list
                 (list (if (equal "DISTINCT" (second distinct-all))
                           :select-distinct
                           :select) result-column-list)
                 (when from-clause
                   (list from-clause))
                 (when where-clause
                   (list where-clause)))))

(defrule select-core
    (or %select-core values-stmt))

(defrule %compound-select-stmt
    (and select-core ws (or (and (~ "UNION") ws (~ "ALL"))
                            (~ "UNION")
                            (~ "INTERSECT")
                            (~ "EXCEPT")) ws compound-select-stmt)
  (:function %remove-nil)
  (:destructure (select-1 op select-2)
    (list  (cond
             ((equal op '("UNION" nil "ALL")) :union-all)
             ((equal op "UNION") :union)
             ((equal op "INTERSECT") :intersect)
             ((equal op "EXCEPT") :except))
           select-1 select-2)))

(defrule compound-select-stmt
    (or %compound-select-stmt select-core))

(defrule ordering-term
    (and expr (? (and ws (or (~ "ASC") (~ "DESC")))))
  (:destructure (expr &optional ws (direction "ASC"))
    (declare (ignore ws))
    (cons expr (ecase direction
                 ("ASC" :asc)
                 ("DESC" :desc)))))

(defrule ordering-term-list
    (and ordering-term (* (and (? ws) comma (? ws) ordering-term)))
  (:lambda (items)
    (%flatten-list items)))

(defrule order-by-clause
    (and (~ "ORDER") ws (~ "BY") ws ordering-term-list)
  (:function %remove-nil)
  (:destructure (order by ordering-term-list)
    (declare (ignore order by))
    (list :order-by ordering-term-list)))

(defrule limit-clause
    (and (~ "LIMIT") ws expr (? (and (or (and ws (~ "OFFSET") ws) (and (? ws) comma (? ws))) expr)))
  (:destructure (limit ws1 expr (&optional comma offset))
    (declare (ignore limit ws1 comma))
    (if offset
        (list :limit expr offset)
        (list :limit expr))))

(defrule select-stmt
    (and compound-select-stmt (? (and ws order-by-clause)) (? (and ws limit-clause)))
  (:destructure (select (&optional ws1 order-by) (&optional ws2 limit))
    (declare (ignore ws1 ws2))
    (concatenate 'list
                 select
                 (when order-by
                   (list order-by))
                 (when limit
                   (list limit)))))

(defrule sql-stmt
    (and (? ws)
         (or create-table-stmt
             create-index-stmt
             insert-stmt
             select-stmt)
         (? ws))
  (:destructure (ws1 stmt ws2)
    (declare (ignore ws1 ws2))
    stmt))

(defun parse-sql (in)
  (esrap:parse 'sql-stmt in))
