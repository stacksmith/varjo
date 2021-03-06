(in-package :varjo)
(in-readtable fn:fn-reader)

(defmethod compile-form (code env)
  (multiple-value-bind (code-obj new-env)
      (cond ((or (null code) (eq t code)) (compile-bool code env))
            ((numberp code) (compile-number code env))
            ((symbolp code) (compile-symbol code env))
            ((and (listp code) (listp (first code)))
             (error 'invalid-form-list :code code))
            ((listp code) (compile-list-form code env))
            ((typep code 'code) code)
            ((typep code 'v-value) (%v-value->code code env))
            (t (error 'cannot-compile :code code)))
    (values code-obj (or new-env env))))

(defun expand-and-compile-form (code env)
  "Special case generally used by special functions that need to expand
   any macros in the form before compiling"
  (pipe-> (code env)
    (equal #'symbol-macroexpand-pass
           #'macroexpand-pass
           #'compiler-macroexpand-pass)
    #'compile-form))
