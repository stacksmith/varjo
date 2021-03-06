(in-package :varjo)
(in-readtable fn:fn-reader)

;;----------------------------------------------------------------------

;;[TODO] Maybe the error should be caught and returned,
;;       in case this is a bad walk
;;{TODO} expand on this please. 'Future-you' couldnt work out what this meant
;; {TODO} you from both of your futures here. I think he was saying that
;;        the errors coming out of a special function could have been the result
;;        of the special func using #'compile-form which tried compiling a
;;        function call but while testing for the right function it threw and
;;        error. I think that is wrong as the handler-case in compiler/functions
;;        should catch those. We need to review all this stuff anyway.
;;        In the case of special funcs there should never be any ambiguity, it
;;        HAS to be the correct impl
(defun compile-special-function (func args env)
  (multiple-value-bind (code-obj new-env)
      (handler-case (apply (v-return-spec func) (cons env args))
	(varjo-error (e) (invoke-debugger e)))
    ;;(assert (node-tree code-obj))
    (values code-obj new-env)))

;;----------------------------------------------------------------------

(defun compile-progn (body env)
  (let* ((mvb (v-multi-val-base env))
	 (env (fresh-environment env :multi-val-base nil))
	 (body-objs
	  (append
	   (loop :for code :in (butlast body)
	      :collect (vbind (code-obj new-env) (compile-form code env)
			 (when new-env (setf env new-env))
			 code-obj))
	   (vbind (code-obj new-env)
	       (compile-form (last1 body)
			    (fresh-environment env :multi-val-base mvb))
	     (when new-env (setf env new-env))
	     (list code-obj)))))
    (values body-objs env)))

(defun mapcar-progn (func env list &rest more-lists)
  "Mapcar over the lists but pass the env as the first arg to the function
   on each call. If you return a new env it will be used for the remaining
   calls."
  (values (apply #'mapcar
		 (lambda (&rest args)
		   (vbind (code-obj new-env) (apply func (cons env args))
		     (when new-env (setf env new-env))
		     code-obj))
		 (cons list more-lists))
	  env))

(defun %merge-progn (code-objs starting-env final-env)
  (let* ((last-obj (last1 (remove nil code-objs))))
    (merge-obs code-objs
	       :type (code-type last-obj)
	       :current-line (current-line last-obj)
	       :to-block (merge-lines-into-block-list code-objs)
	       :multi-vals (multi-vals (last1 code-objs))
	       :flow-ids (flow-ids last-obj)
	       :node-tree (ast-node! 'progn (mapcar #'node-tree code-objs)
				     (code-type last-obj) (flow-ids last-obj)
				     starting-env final-env))))

(defmacro merge-progn (code-objs starting-env &optional final-env)
  (let ((co (gensym "code-objs"))
	(pe (gensym "potential-env"))
	(se (gensym "starting-env"))
	(fe (gensym "final-env")))
    `(vbind (,co ,pe) ,code-objs
	 (let* ((,se ,starting-env)
		(,fe ,(if final-env
			  `(or ,final-env ,pe ,se)
			  `(or ,pe ,se))))
	   (values (%merge-progn ,co ,se ,fe)
		   ,fe)))))


;;----------------------------------------------------------------------

;; %multi-env-progn functions runs each form one after the other
;; (just like progn) however, unlike progn, each form is evaluated with the
;; same environment this means that bindings in one wont be visable in another.
;; Finally the resulting environement is merged

(defun %mapcar-multi-env-progn (func env list &rest more-lists)
  (let* ((e (apply #'mapcar
		   (lambda (&rest args)
		     (vlist (apply func (cons env args))))
		   (cons list more-lists)))
	 (code-objs (mapcar #'first e))
	 (env-objs (mapcar #'second e))
	 (merged-env (reduce (lambda (_ _1) (merge-env _ _1))
			     env-objs)))
    (values code-objs merged-env)))

(defun %merge-multi-env-progn (code-objs)
  (merge-obs code-objs
	     :type (type-spec->type 'v-none)
	     :current-line nil
	     :to-block (append (mapcat #'to-block code-objs)
			       (mapcar (lambda (_) (current-line (end-line _)))
				       code-objs))
	     :to-top (mapcat #'to-top code-objs)
	     :flow-ids nil
	     :node-tree :ignored))

(defmacro merge-multi-env-progn (code-objs)
  (let ((co (gensym "code-objs"))
	(fe (gensym "final-env")))
    `(vbind (,co ,fe) ,code-objs
       (values (%merge-multi-env-progn ,co)
	       ,fe))))

;;----------------------------------------------------------------------

(defun compile-make-var (name-string type flow-ids)
  (make-code-obj type name-string :flow-ids flow-ids :node-tree :ignored))

;;----------------------------------------------------------------------

(defun typify-code (code-obj &optional new-value)
  (let* ((prefixed-line (prefix-type-declaration code-obj))
	 (current-line
	  (if new-value
	      (%gen-assignment-string prefixed-line (current-line new-value))
	      prefixed-line))
	 (flow-ids
	  (if new-value
	      (flow-ids new-value)
	      (flow-ids code-obj)))
	 (to-block (when new-value
		     (to-block new-value)))
	 (to-top (when new-value
		   (to-top new-value))))
    (copy-code code-obj
	       :type (code-type code-obj)
	       :current-line current-line
	       :flow-ids flow-ids
	       :to-block to-block
	       :to-top to-top
	       :node-tree :ignored
	       :multi-vals nil
	       :place-tree nil)))

;;----------------------------------------------------------------------

(defun compile-let (name type-spec value-form env &optional glsl-name flow-ids)
  (let* ((value-obj (when value-form (compile-form value-form env)))
	 (glsl-name (or glsl-name (safe-glsl-name-string
				   (free-name name env)))))

    (let ((type-spec (when type-spec (type-spec->type type-spec))))
      (%validate-var-types name type-spec value-obj)
      (let* ((flow-ids
	      (or flow-ids (when value-obj (flow-ids value-obj)) (flow-id!)))
	     (let-obj
	      (if value-obj
		  (typify-code (compile-make-var glsl-name
						 (or type-spec
						     (code-type value-obj))
						 flow-ids)
			       value-obj)
		  (typify-code (compile-make-var glsl-name type-spec
						 (flow-id!))))))
	(values
	 (copy-code let-obj
		    :type (type-spec->type 'v-none)
		    :current-line nil
		    :to-block (cons-end (current-line (end-line let-obj))
					(to-block let-obj))
		    :multi-vals nil
		    :place-tree nil
		    :flow-ids flow-ids
		    :node-tree (if value-form
				   (node-tree value-obj)
				   :ignored)
		    :stemcells (append (and let-obj (stemcells let-obj))
				       (and value-obj (stemcells value-obj))))
	 (add-var name
		  (v-make-value (or type-spec (code-type value-obj))
				env
				:glsl-name glsl-name
				:flow-ids flow-ids)
		  env))))))

;;----------------------------------------------------------------------

(defmacro env-> ((env-var env) &body compiling-forms)
  "Kinda like varjo progn in that it accumulates the env and
   returns the results of all the forms and the final env.
   However it DOES NOT make a fresh environment to compile the forms in.
   It expects that each form returns a result and optionally an env"
  (let ((objs (gensym "results"))
	(obj (gensym "result"))
	(new-env (gensym "new-env")))
    `(let ((,env-var ,env)
	   (,objs nil))
       (declare (ignorable ,env-var))
       ,(reduce (lambda (_ _1)
		  `(vbind (,obj ,new-env) ,_1
		     (let ((,env-var (or ,new-env ,env-var)))
		       (declare (ignorable ,env-var))
		       (push ,obj ,objs)
		       ,_)))
		(cons `(values (reverse ,objs) ,env-var)
		      (reverse compiling-forms))))))



(defmacro with-v-let-spec (form &body body)
  (let ((var-spec (gensym "var-spec"))
	(qual (gensym "qualifiers"))
	(full-spec (gensym "form")))
    `(let* ((,full-spec ,form)
	    (,var-spec (listify (first ,full-spec)))
	    (value-form (second ,full-spec)))
       (declare (ignorable value-form))
       (destructuring-bind (name &optional type-spec ,qual) ,var-spec
	 (declare (ignore ,qual))
	 ,@body))))

;;----------------------------------------------------------------------
