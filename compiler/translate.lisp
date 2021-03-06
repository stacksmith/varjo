(in-package :varjo)
(in-readtable fn:fn-reader)

;;----------------------------------------------------------------------

(defun translate (in-args uniforms context body
		  &optional (third-party-metadata (make-hash-table)))
  (flow-id-scope
    (let ((env (%make-base-environment third-party-metadata)))
      (pipe-> (in-args uniforms context body env)
	#'split-input-into-env
	#'process-context
	#'add-context-glsl-vars
	#'process-in-args
	#'process-uniforms
	(equalp #'symbol-macroexpand-pass
		#'macroexpand-pass
		#'compiler-macroexpand-pass)
	#'compile-pass
	#'make-post-process-obj
	#'check-stemcells
	#'post-process-ast
	#'filter-used-items
	#'gen-in-arg-strings
	#'gen-out-var-strings
	#'final-uniform-strings
	#'dedup-strings
	#'final-string-compose
	#'code-obj->result-object))))

;;----------------------------------------------------------------------

(defmacro with-v-arg ((&optional (name (gensym "name")) (type (gensym "type"))
				 (qualifiers (gensym "qualifiers"))
				 (glsl-name (gensym "glsl-name")))
			 arg-form &body body)
  (let ((qn (gensym "qn")))
    `(destructuring-bind (,name ,type . ,qn) ,arg-form
       (declare (ignorable ,name ,type))
       (let* ((,glsl-name (when (stringp (last1 ,qn)) (last1 ,qn)))
	      (,qualifiers (if ,glsl-name (butlast ,qn) ,qn)))
         (declare (ignorable ,qualifiers ,glsl-name))
         ,@body))))

;;----------------------------------------------------------------------


(defun check-arg-forms (in-args) (every #'check-arg-form in-args))
(defun check-arg-form (arg)
  (unless
      (and
       ;; needs to at least have name and type
       (>= (length arg) 2)
       ;; of the rest of the list it must be keyword qualifiers and optionally a
       ;; string at the end. The string is a declaration of what the name of the
       ;; var will be in glsl. This feature is intended for use only by the compiler
       ;; but I see not reason to lock this away.
       (every #'keywordp (in-arg-qualifiers arg)))
    (error "Declaration ~a is badly formed.~%Should be (-var-name- -var-type- &optional qualifiers)" arg))
  t)

;;[TODO] Move these errors vvv^^^^^
(defun check-for-dups (in-args uniforms)
  (if (intersection (mapcar #'first in-args) (mapcar #'first uniforms))
      (error "Varjo: Duplicates names found between in-args and uniforms")
      t))

;;{TODO} fix error message
(defun check-for-stage-specific-limitations (env)
  (cond ((or (and (member :vertex (v-context env))
                  (some #'third (v-raw-in-args env))))
         (error "In args to vertex shaders can not have qualifiers")))
  t)

(defun split-input-into-env (in-args uniforms context body env)
  (when (and (check-arg-forms uniforms) (check-arg-forms in-args)
             (check-for-dups in-args uniforms))
    (setf (v-raw-in-args env) in-args)
    (setf (v-raw-uniforms env) uniforms)
    (setf (v-raw-context env) context)
    (when (not context)
      (setf (v-raw-context env) *default-context*))
    (when (not (intersection *supported-versions* (v-raw-context env)))
      (push :vertex (v-raw-context env)))
    (when (check-for-stage-specific-limitations env)
      (values body env))))

;;----------------------------------------------------------------------

(defun process-context (code env)
  ;; ensure there is a version
  (unless (loop :for item :in (v-raw-context env)
             :if (find item *supported-versions*) :return item)
    (push *default-version* (v-raw-context env)))
  (let* ((raw-context (v-raw-context env))
	 (iuniforms (and (member :iuniforms raw-context)
			 (not (member :no-iuniforms raw-context))))
         (raw-context (remove-if λ(member _ '(:iuniforms :no-iuniforms))
				 raw-context)))
    (setf (v-context env)
          (loop :for item :in raw-context
             :if (find item *valid-contents-symbols*) :collect item
             :else :do (error 'invalid-context-symbol :context-symb item)))
    (setf (v-iuniforms env) iuniforms))
  (values code env))

;;----------------------------------------------------------------------

(defun add-context-glsl-vars (code env)
  (values code (add-glsl-vars env *glsl-variables*)))

;;----------------------------------------------------------------------

;; {TODO} get rid of all this ugly imperitive crap, what was I thinking?
(defun process-in-args (code env)
  "Populate in-args and create fake-structs where they are needed"
  (let ((in-args (v-raw-in-args env)))
    (loop :for in-arg :in in-args :do
       (with-v-arg (name type qualifiers declared-glsl-name) in-arg
         (let* ((type-obj (type-spec->type type))
                (glsl-name (or declared-glsl-name (safe-glsl-name-string name))))
           (if (typep type-obj 'v-struct)
               (add-in-arg-fake-struct name glsl-name type-obj qualifiers env)
               (progn
                 (%add-var name (v-make-value type-obj env :glsl-name glsl-name)
			   env)
                 (setf (v-in-args env)
                       (append (v-in-args env)
                               `((,name ,(type->type-spec type-obj) ,qualifiers
                                        ,glsl-name)))))))))
    (values code env)))

;;----------------------------------------------------------------------

(defun process-uniforms (code env)
  (let ((uniforms (v-raw-uniforms env)))
    (mapcar
     (lambda (_)
       (with-v-arg (name type qualifiers glsl-name) _
         (case-member qualifiers
           (:ubo (process-ubo-uniform name glsl-name type qualifiers env))
           (:fake (process-fake-uniform name glsl-name type qualifiers env))
           (otherwise (process-regular-uniform name glsl-name type
                                               qualifiers env)))))
     uniforms)
    (values code env)))

;; mutates env
(defun process-regular-uniform (name glsl-name type qualifiers env)
  (let* ((true-type (v-true-type (type-spec->type type))))
    (%add-var name
	      (v-make-value true-type env :glsl-name
			    (or glsl-name (safe-glsl-name-string name))
			    :read-only t)
	      env))
  (push (list name type qualifiers glsl-name) (v-uniforms env))
  env)

;; mutates env
(defun process-ubo-uniform (name glsl-name type qualifiers env)
  (let* ((true-type (v-true-type (type-spec->type type))))
    (%add-var name (v-make-value
		    true-type env
		    :glsl-name (or glsl-name (safe-glsl-name-string name))
		    :flow-ids (flow-id!) :function-scope 0 :read-only t)
	      env))
  (push (list name type qualifiers glsl-name) (v-uniforms env))
  env)

;; mutates env
(defun process-fake-uniform (name glsl-name type qualifiers env)
  (let ((type-obj (type-spec->type type)))
    (add-uniform-fake-struct name glsl-name type-obj qualifiers env))
  env)

;;----------------------------------------------------------------------

(defun v-symbol-macroexpand-all (form &optional (env :-GENV-))
  (cond ((null form) nil)
        ((atom form)
         (let ((sm (get-symbol-macro form env)))
	   (if sm
	       (values (first sm) `(,form))
	       form)))
        ((consp form)
	 (vbind (expanded-a found-a) (v-symbol-macroexpand-all (car form))
	   (vbind (expanded-b found-b) (v-symbol-macroexpand-all (cdr form))
	     (values (cons expanded-a expanded-b)
		     (append found-a found-b)))))))

(defun symbol-macroexpand-pass (form env)
  (vbind (form used) (v-symbol-macroexpand-all form env)
    (push used (used-symbol-macros env))
    (values form env)))

(defun dedup-used-macros (used)
  (remove-duplicates (flatten used)))

(defun dedup-used-external-functions (used)
  (remove-duplicates used))

;;----------------------------------------------------------------------

(defun v-macroexpand-all (code &optional (env :-GENV-))
  (cond ((atom code) code)
        (t (let* ((head (first code))
                  (m (get-macro head env)))
             (if m
                 (vbind (f u) (v-macroexpand-all (apply m (rest code)) env)
		   (values f (cons head u)))
                 (let ((i (mapcar λ(vlist (v-macroexpand-all _ env))
				  code)))
		   (values (mapcar #'first i) (mapcar #'second i))))))))

(defun macroexpand-pass (code env)
  (vbind (form used) (v-macroexpand-all code env)
    (push used (used-macros env))
    (values form env)))

;;----------------------------------------------------------------------

(defun v-compiler-macroexpand-all (code &optional (env :-GENV-))
  (cond ((atom code) code)
        (t (let* ((head (first code))
                  (m (get-compiler-macro head env)))
             (if m
		 (vbind (f u)
		     (v-compiler-macroexpand-all (apply m (rest code)) env)
		   (values f (cons head u)))
		 (let ((i (mapcar λ(vlist (v-compiler-macroexpand-all _ env))
				  code)))
		   (values (mapcar #'first i) (mapcar #'second i))))))))

(defun compiler-macroexpand-pass (code env)
  (vbind (form used) (v-compiler-macroexpand-all code env)
    (push used (used-compiler-macros env))
    (values form env)))

;;----------------------------------------------------------------------

(defun compile-pass (code env)
  (%make-function :main () (list code) nil env))

;;----------------------------------------------------------------------

(defclass post-compile-process ()
  ((code :initarg :code :accessor code)
   (env :initarg :env :accessor env)
   (in-args :initarg :in-args :accessor in-args)
   (out-vars :initarg :out-vars :accessor out-vars)
   (uniforms :initarg :uniforms :accessor uniforms)
   (stemcells :initarg :stemcells :accessor stemcells)
   (used-types :initarg :used-types :accessor used-types)
   (used-external-functions :initarg :used-external-functions
                            :accessor used-external-functions)
   (used-symbol-macros :initarg :used-symbol-macros
                       :accessor used-symbol-macros)
   (used-macros :initarg :used-macros :accessor used-macros)
   (used-compiler-macros :initarg :used-compiler-macros
                         :accessor used-compiler-macros)
   (ast :initarg :ast :reader ast)))

(defun make-post-process-obj (code env)
  (make-instance
   'post-compile-process :code code :env env
   :used-external-functions (dedup-used-external-functions
                             (used-external-functions env))
   :used-symbol-macros (dedup-used-macros (used-symbol-macros env))
   :used-macros (dedup-used-macros (used-macros env))
   :used-compiler-macros (dedup-used-macros (used-compiler-macros env))))

;;----------------------------------------------------------------------

(defun check-stemcells (post-proc-obj)
  "find any stemcells in the result that that the same name and
   a different type. Then remove duplicates"
  (with-slots (code) post-proc-obj
    (let ((stemcells (stemcells code)))
      (mapcar
       (lambda (x)
	 (with-slots (name (string string-name) type flow-id) x
	   (declare (ignore string flow-id))
	   (when (find-if (lambda (x)
			    (with-slots ((iname name) (itype type)) x
			      (and (equal name iname)
				     (not (equal type itype)))))
			  stemcells)
	     (error "Symbol ~a used with different implied types" name))))
       ;; {TODO} Proper error here
       stemcells)
      (setf (stemcells post-proc-obj)
	    (remove-duplicates stemcells :test #'equal
			       :key (lambda (x)
				      (slot-value x 'name))))
      post-proc-obj)))

;;----------------------------------------------------------------------

(defun post-process-ast (post-proc-obj)
  (let ((flow-origin-map (make-hash-table))
	(val-origin-map (make-hash-table))
	(node-copy-map (make-hash-table :test #'eq)))
    ;; prime maps with args (env)
    ;; {TODO} need to prime in-args & structs/array elements
    (labels ((uniform-raw (val)
	       (slot-value (first (ids (first (listify (flow-ids val)))))
			   'val)))
      (let ((env (get-base-env (env post-proc-obj))))
	(loop :for (name) :in (v-uniforms env) :do
	   (let ((key (uniform-raw (get-var name env)))
		 (val (make-uniform-origin :name name)))
	     (setf (gethash key flow-origin-map) val)
	     (setf (gethash key val-origin-map) val)))))

    (labels ((post-process-node (node walk parent &key replace-args)
	       ;; we want a new copy as we will be mutating it
	       (let ((new (copy-ast-node
			   node
			   :flow-id (ast-flow-id node)
			   :parent (gethash parent node-copy-map))))
		 ;; store the lookup tables with every node
		 (setf (slot-value new 'flow-id-origins) flow-origin-map
		       (slot-value new 'val-origins) val-origin-map)
		 (with-slots (args val-origin flow-id-origin kind) new
		   ;;    maintain the relationship between this copied
		   ;;    node and the original
		   (setf (gethash node node-copy-map) new
			 ;; walk the args. OR, if the caller pass it,
			 ;; walk the replacement args and store them instead
			 args (mapcar λ(funcall walk _ :parent node)
				      (or replace-args (ast-args node)))
			 ;;
			 val-origin (val-origins new)
			 ;; - - - - - - - - - - - - - - - - - - - - - -
			 ;; flow-id-origins gets of DESTRUCTIVELY adds
			 ;; the origin of the flow-id/s for this node.
			 ;; - - - - - - - - - - - - - - - - - - - - - -
			 ;; {TODO} redesign this madness
			 ;; - - - - - - - - - - - - - - - - - - - - - -
			 flow-id-origin (flow-id-origins new))
		   ;;
		   (when (typep (ast-kind new) 'v-function)
		     (setf kind (name (ast-kind new)))))
		 new))

	     (walk-node (node walk &key parent)
	       (cond
		 ;; remove progns with one form
		 ((and (ast-kindp node 'progn) (= (length (ast-args node)) 1))
		  (funcall walk (first (ast-args node)) :parent parent))

		 ;; splice progns into let's implicit progn
		 ((ast-kindp node 'let)
		  (let ((args (ast-args node)))
		    (post-process-node
		     node walk parent :replace-args
		     `(,(first args)
			,@(loop :for a :in (rest args)
			     :if (and (typep a 'ast-node)
				      (ast-kindp a 'progn))
			     :append (ast-args a)
			     :else :collect a)))))

		 ;; remove %return nodes
		 ((ast-kindp node '%return)
		  (funcall walk (first (ast-args node)) :parent parent))

		 (t (post-process-node node walk parent)))))

      (symbol-macrolet ((code (code post-proc-obj)))
	(let ((ast (walk-ast #'walk-node code :include-parent t)))
	  (setf code (copy-code code :node-tree ast)
		(slot-value post-proc-obj 'ast) ast)))

      post-proc-obj)))

;;----------------------------------------------------------------------

(defun filter-used-items (post-proc-obj)
  "This changes the code-object so that used-types only contains used
   'user' defined structs."
  (with-slots (code env) post-proc-obj
    (setf (used-types post-proc-obj)
	  (loop :for i :in (find-used-user-structs code env)
	     :collect (type-spec->type i :env env))))
  post-proc-obj)

;;----------------------------------------------------------------------

(defun calc-locations (types)
;;   "Takes a list of type objects and returns a list of positions
;; - usage example -
;; (let ((types (mapcar #'type-spec->type '(:mat4 :vec2 :float :mat2 :vec3))))
;;          (mapcar #'cons types (calc-positions types)))"
  (labels ((%calc-location (sizes type)
             (cons (+ (first sizes) (v-glsl-size type)) sizes)))
    (reverse (reduce #'%calc-location (butlast types) :initial-value '(0)))))


(defun gen-in-arg-strings (post-proc-obj)
  (with-slots (env) post-proc-obj
    (let* ((types (mapcar #'second (v-in-args env)))
	   (type-objs (mapcar #'type-spec->type types))
	   (locations (if (member :vertex (v-context env))
			  (calc-locations type-objs)
			  (loop for i below (length type-objs) collect nil))))
      (setf (in-args post-proc-obj)
	    (loop :for (name type-spec qualifiers glsl-name) :in (v-in-args env)
	       :for location :in locations :for type :in type-objs
	       :do (identity type-spec)
	       :collect
	       `(,name ,type ,@qualifiers ,@(list glsl-name)
		       ,(gen-in-var-string (or glsl-name name) type
					   qualifiers location))))))
  post-proc-obj)

;;----------------------------------------------------------------------

(defun dedup-out-vars (out-vars)
  (let ((seen (make-hash-table))
        (deduped nil))
    (loop :for (name qualifiers value) :in out-vars
       :do (let ((tspec (type->type-spec (v-type value))))
             (if (gethash name seen)
                 (unless (equal tspec (gethash name seen))
                   (error 'out-var-type-mismatch :var-name name
                          :var-types (list tspec (gethash name seen))))
                 (setf (gethash name seen) tspec
                       deduped (cons (list name qualifiers value)
                                     deduped)))))
    (reverse deduped)))

(defun gen-out-var-strings (post-proc-obj)
  (with-slots (code env) post-proc-obj
    (let* ((out-vars (dedup-out-vars (out-vars code)))
	   (out-types (mapcar (lambda (_)
				(v-type (third _)))
			      out-vars))
	   (locations (if (member :fragment (v-context env))
			  (calc-locations out-types)
			  (loop for i below (length out-types) collect nil))))
      (setf (out-vars post-proc-obj)
	    (loop :for (name qualifiers value) :in out-vars
	       :for type :in out-types
	       :for location :in locations
	       :collect (let ((glsl-name (v-glsl-name value)))
			  `(,name ,(type->type-spec (v-type value))
				  ,@qualifiers ,glsl-name
				  ,(gen-out-var-string glsl-name type qualifiers
						       location)))))
      post-proc-obj)))

;;----------------------------------------------------------------------

(defun merge-in-injected-uniforms (code env)
  ;; - format injected-uniforms correctly
  ;; - remove-duplicates
  ;; - find duplicate names
  ;; - boom!
  (let* ((formatted (mapcar λ`(,@_ nil nil) (injected-uniforms code)))
	 (joined (append formatted  (v-uniforms env)))
	 (dedup (remove-duplicates joined :test #'equal))
	 (names (mapcar #'first dedup))
	 (counts (mapcar λ(cons (count _ names) _) (remove-duplicates names)))
	 (issues (mapcar #'cdr (remove-if λ(<= (car _) 1) counts))))
    (when issues
      (error "Varjo: The current stage has incompatible uniforms that have been introduced by
the use of function.

The following uniforms have incompatible definitions: ~s

The full list: ~s
" issues dedup))
    dedup))


(defun final-uniform-strings (post-proc-obj)
  (with-slots (code env) post-proc-obj
    (let ((final-strings nil)
	  (structs (used-types post-proc-obj))
	  (uniforms (merge-in-injected-uniforms (code post-proc-obj) env))
	  (implicit-uniforms nil))
      (loop :for (name type qualifiers glsl-name) :in uniforms
	 :for type-obj = (type-spec->type type) :do
	 (push `(,name ,type
		       ,@qualifiers
		       ,(if (member :ubo qualifiers)
			    (write-interface-block
			     :uniform (or glsl-name (safe-glsl-name-string name))
			     (v-slots type-obj))
			    (gen-uniform-decl-string
			     (or glsl-name (safe-glsl-name-string name))
			     type-obj
			     qualifiers)))
	       final-strings)
	 (when (and (v-typep type-obj 'v-user-struct)
		    (not (find (type->type-spec type-obj) structs
			       :key #'type->type-spec :test #'equal)))
	   (push type-obj structs)))

      (loop :for s :in (stemcells post-proc-obj) :do
	 (with-slots (name string-name type) s
	   (when (eq type :|unknown-type|) (error 'symbol-unidentified :sym name))
	   (let ((type-obj (type-spec->type type)))
	     (push `(,name ,type
			   ,(gen-uniform-decl-string
			     (or string-name (error "stem cell without glsl-name"))
			     type-obj
			     nil)
			   ,string-name)
		   implicit-uniforms)

	     (when (and (v-typep type-obj 'v-user-struct)
			(not (find (type->type-spec type-obj) structs
				   :key #'type->type-spec :test #'equal)))
	       (push type-obj structs)))))

      (setf (used-types post-proc-obj) structs)
      (setf (uniforms post-proc-obj) final-strings)
      (setf (stemcells post-proc-obj) implicit-uniforms)
      post-proc-obj)))

;;----------------------------------------------------------------------

(defun dedup-strings (post-proc-obj)
  (with-slots (code) post-proc-obj
    (setf code
	  (copy-code
	   code
	   :to-top (remove-duplicates (to-top code) :test #'equal)
	   :signatures (remove-duplicates (signatures code) :test #'equal)))
    (setf (used-types post-proc-obj)
	  (remove-duplicates (mapcar #'v-signature (used-types post-proc-obj))
			     :test #'equal)))
  post-proc-obj)

;;----------------------------------------------------------------------

(defun final-string-compose (post-proc-obj)
  (values (gen-shader-string post-proc-obj)
	  post-proc-obj))

;;----------------------------------------------------------------------

(defun code-obj->result-object (final-glsl-code post-proc-obj)
  (with-slots (env) post-proc-obj
    (let* ((context (process-context-for-result (v-context env)))
	   (base-env (get-base-env env)))
      (make-instance
       'varjo-compile-result
       :glsl-code final-glsl-code
       :stage-type (find-if λ(find _ *supported-stages*) context)
       :in-args (mapcar #'butlast (in-args post-proc-obj))
       :out-vars (mapcar #'butlast (out-vars post-proc-obj))
       :uniforms (mapcar #'butlast (uniforms post-proc-obj))
       :implicit-uniforms (stemcells post-proc-obj)
       :context context
       :used-external-functions (used-external-functions post-proc-obj)
       :used-symbol-macros (used-symbol-macros post-proc-obj)
       :used-macros (used-macros post-proc-obj)
       :used-compiler-macros (used-compiler-macros post-proc-obj)
       :ast (ast post-proc-obj)
       :third-party-metadata (slot-value base-env 'third-party-metadata)))))

(defun process-context-for-result (context)
  ;; {TODO} having to remove this is probably a bug
  (remove :main context))
