;;;; package.lisp

(defpackage #:varjo-lang
  (:use #:cl #:rtg-math.base-maths)
  (:import-from :rtg-math :v! :m! :s~ :radians :degrees)
  (:import-from :rtg-math.base-vectors :x :y :z :w
		:v!int :v!uint :v!bool :v!double
		:v2! :v2!double :v2!int :v2!uint
		:v3! :v3!double :v3!int :v3!uint
		:v4! :v4!double :v4!int :v4!uint)
  (:import-from :rtg-math.vectors
		:swizzle
		:dot
		:normalize
		:cross)
  (:export

   ;; special functions
   :setf-1
   :%assign
   :%return
   :labels-no-implicit
   :%out
   :%if
   :switch
   :for
   :while
   :swizzle
   :%break
   :values-safe

   ;; bitwise operators
   :>>
   :<<

   ;; macros in special.lisp
   :s~

   ;; functions
   :%*
   :%+
   :%-
   :%/
   :%<
   :%<=
   :%=
   :%>
   :%>=
   :%eql
   :%equal
   :--
   :atomic-counter
   :bool
   :double
   :int
   :uint
   :v-equal
   :v-not
   :v-not-equal

   ;; struct slot names
   :near
   :far
   :diff
   ))

(defpackage #:varjo-conditions
  (:use #:cl)
  (:shadowing-import-from :varjo-lang :clamp :switch)
  (:export :missing-function-error
	   :problem-with-the-compiler
	   :cannot-compile
	   :invalid-form-list
	   :no-function-returns
	   :not-core-type-error
	   :invalid-function-return-spec
	   :unknown-type-spec
	   :duplicate-name
	   :clone-global-env-error
	   :clean-global-env-error
	   :could-not-find-function
	   :could-not-find-any
	   :no-valid-function
	   :return-type-mismatch
	   :non-place-assign
	   :setq-readonly
	   :setf-readonly
	   :setf-type-match
	   :setq-type-match
	   :cannot-not-shadow-core
	   :out-var-name-taken
	   :unknown-variable-type
	   :var-type-mismatch
	   :switch-type-error
	   :loop-will-never-halt
	   :for-loop-simple-expression
	   :for-loop-only-one-var
	   :invalid-for-loop-type
	   :no-version-in-context
	   :name-unsuitable
	   :unable-to-resolve-func-type
	   :out-var-type-mismatch
	   :fake-type-global
	   :invalid-context-symbol
	   :args-incompatible
	   :invalid-shader-stage
	   :swizzle-keyword
	   :multi-func-stemcells
	   :uniform-in-sfunc
	   :invalid-v-defun-template
	   :keyword-in-function-position
	   :invalid-symbol-macro-form
	   :stage-order-error
	   :multi-val-bind-mismatch
	   :merge-env-func-scope-mismatch
	   :merge-env-parent-mismatch
	   :env-parent-context-mismatch
	   :symbol-unidentified
	   :if-form-type-mismatch
	   :bad-make-function-args
	   :none-type-in-out-vars
	   :body-block-empty
	   :flow-ids-mandatory
	   :flow-id-must-be-specified-vv
	   :flow-id-must-be-specified-co
	   :multiple-flow-ids-regular-func
	   :if-branch-type-mismatch
	   :if-test-type-mismatch
	   :cross-scope-mutate
	   :illegal-implicit-args
	   :invalid-flow-id-multi-return
	   :loop-flow-analysis-failure
	   :invalid-env-vars
	   :values-safe-wasnt-safe

	   ;; restarts
	   :setq-supply-alternate-type
	   ))

(defpackage #:varjo
  (:use #:cl :varjo-lang :split-sequence #:alexandria #:cl-ppcre
	#:named-readtables #:varjo-conditions)
  (:import-from :rtg-math :v! :m! :s~ :radians :degrees)
  (:import-from :rtg-math.base-vectors :x :y :z :w
		:v!int :v!uint :v!bool :v!double
		:v!int :v!uint :v!bool :v!double
		:v2! :v2!double :v2!int :v2!uint
		:v3! :v3!double :v3!int :v3!uint
		:v4! :v4!double :v4!int :v4!uint)
  (:import-from :rtg-math.vectors
		:swizzle
		:dot
		:normalize
		:cross)
  (:shadowing-import-from :varjo-lang :clamp :switch)
  (:export :v-glsl-size
           :v-casts-to-p
           :v-casts-to
           :find-mutual-cast-type

           ;;type functions
           :v-spec-typep
           :type-specp
           :type->type-spec
           :type-spec->type
           :v-glsl-size
           :v-type-eq
           :v-typep
           :v-casts-to-p
           :v-casts-to
           :find-mutual-cast-type
           :v-special-functionp
           :v-errorp

           ;;type accessors
           :core-typep
           :v-argument-spec
           :v-dimensions
           :v-element-type
           :v-fake-type
           :v-glsl-name
           :v-glsl-string
           :v-payload
           :v-restriction
           :v-return-spec
           :v-signature
           :v-slots
           :v-true-type

           ;;types
           :add-type-shadow
           :un-shadow
           :v-t-type
           :v-type
           :v-stemcell
           :v-spec-type
           :v-tfd
           :v-tf
           :v-td
           :v-tb
           :v-tiu
           :v-i-ui
           :v-ti
           :v-tu
           :v-tvec
           :v-array
           :v-none
           :v-function
	   :v-user-function
           :v-struct
           :v-user-struct
           :v-error
           :v-void
           :v-bool
           :v-number
           :v-int
           :v-uint
           :v-float
           :v-short-float
           :v-double
           :v-container
           :v-matrix
           :v-mat2
           :v-mat3
           :v-mat4
           :v-mat2x2
           :v-mat2x3
           :v-mat2x4
           :v-mat3x2
           :v-mat3x3
           :v-mat3x4
           :v-mat4x2
           :v-mat4x3
           :v-mat4x4
           :v-vector
           :v-fvector
           :v-vec2
           :v-vec3
           :v-vec4
           :v-bvector
           :v-bvec2
           :v-bvec3
           :v-bvec4
           :v-uvector
           :v-uvec2
           :v-uvec3
           :v-uvec4
           :v-ivector
           :v-ivec2
           :v-ivec3
           :v-ivec4
           :v-dvector
           :v-dvec2
           :v-dvec3
           :v-dvec4
           :v-sampler
           :v-isampler-1d
           :v-isampler-1d-array
           :v-isampler-2d
           :v-isampler-2d-array
           :v-isampler-2d-ms
           :v-isampler-2d-ms-array
           :v-isampler-2d-rect
           :v-isampler-3d
           :v-isampler-buffer
           :v-isampler-cube
           :v-isampler-cube-array
           :v-sampler-1d
           :v-sampler-1d-array
           :v-sampler-1d-array-shadow
           :v-sampler-1d-shadow
           :v-sampler-2d
           :v-sampler-2d-array
           :v-sampler-2d-array-shadow
           :v-sampler-2d-ms
           :v-sampler-2d-ms-array
           :v-sampler-2d-rect
           :v-sampler-2d-rect-shadow
           :v-sampler-2d-shadow
           :v-sampler-3d
           :v-sampler-buffer
           :v-sampler-cube
           :v-sampler-cube-array
           :v-sampler-cube-array-shadow
           :v-sampler-cube-shadow
           :v-usampler-1d
           :v-usampler-1d-array
           :v-usampler-2d
           :v-usampler-2d-array
           :v-usampler-2d-ms
           :v-usampler-2d-ms-array
           :v-usampler-2d-rect
           :v-usampler-3d
           :v-usampler-buffer
           :v-usampler-cube
           :v-usampler-cube-array

           ;;definitions
           :v-defstruct
           :v-defun
           :v-defmacro
           :v-define-compiler-macro
           :add-external-function
	   :add-equivalent-name

	   ;;flow-ids
	   :flow-id!
	   :id=
	   :id~=
	   :flow-ids

	   ;;environment
	   :get-var
	   :get-base-env
	   :get-primitive-type-from-context

	   ;; ast
	   :ast-node
	   :ast-node!
	   :visit-ast-nodes
	   :filter-ast-nodes
	   :walk-ast
	   :ast->code
	   :ast-deep-replace
	   :ast-starting-env
	   :ast-ending-env
	   :ast-kind
	   :ast-kindp
	   :ast-typep
	   :ast-return-type
	   :ast-flow-id
	   :ast-flow-id-origin
	   :ast-val-origin
	   :ast-args
	   :ast-parent
	   :flow-id-origins
	   :val-origins
	   :ast-origin
	   :stemcell-origin
	   :uniform-origin
	   :ast-origin-node
	   :stemcell-origin-node
	   :uniform-origin-node
	   :uniform-origin-name
	   :origin-name

           ;;compiler
           :compile-form
           :with-stemcell-infer-hook
	   :with-constant-inject-hook
	   :safe-glsl-name-string
	   :with-v-arg

           ;;front-end
           :translate
           :rolling-translate
           :split-arguments
           :v-macroexpand-all
           :v-compiler-macroexpand-all
           :*stage-types*
	   :v-compile

           ;;compile-result
	   :glsl-code
	   :stage-type
	   :out-vars
	   :in-args
	   :uniforms
	   :implicit-uniforms
	   :context
	   :used-external-functions
	   :used-macros
	   :used-compiler-macros
	   :used-symbol-macros
	   :ast
	   :third-party-metadata

           ;;utils
           :lambda-list-split
           :pipe->))

(defpackage #:varjo.free-vars (:use #:cl))
