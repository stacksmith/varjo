(in-package :varjo-tests)

;; These two are example macros to show how to use the compiler.
;; They dont provide anything

(defmacro defshader (name args &body body)
  (declare (ignore name))
  (destructuring-bind (in-args uniforms context)
      (split-arguments args '(&uniform &context))
    `(translate ',in-args ',uniforms ',context '(progn ,@body))))

;; (defpipeline blah
;;     (:vertex ((pos :vec3) &uniform (a :float))
;;              (values (v! pos 1.0) a))
;;     (:fragment ((hmm :float))
;;                (labels ((fun ((x :float))
;;                           (* x x)))
;;                  (v! 1.0 1.0 hmm (fun a)))))

(defmacro defpipeline (name &body body)
  (declare (ignore name))
  (destructuring-bind (in-args first-uniforms first-context)
      (split-arguments (second (first body)) '(&uniform &context))
    (declare (ignore in-args))
    `(format
      nil "~{~a~%~}"
      (mapcar #'glsl-code
              (rolling-translate
               ',(mapcar (lambda (_)
                           (destructuring-bind
                                 (stage-in-args stage-uniforms stage-context)
                               (split-arguments (second _) '(&uniform &context))
                             (declare (ignore stage-context))
                             (list stage-in-args
                                   (if (equal first-uniforms stage-uniforms)
                                       stage-uniforms
                                       (concatenate 'list stage-uniforms
                                                    first-uniforms))
                                   (cons (first _) first-context)
                                   (third _))))
                         body))))))

(stefil:defsuite* test-all)
(defsuite build-tests)

(in-suite build-tests)

(deftest build-0 ()
  (finishes
    (defshader test ()
      (v! 0 0 0 0))))

(deftest build-1 ()
  (finishes
    (defshader test ()
      (v! 0 0 0 0)
      (v! 0 0 0 0))))

(deftest build-2 ()
  (finishes
    (defshader test ()
      (let ((x 1))
	(v! 0 x 1 2))
      (v! 0 0 0 0))))

(deftest build-3 ()
  (finishes
    (defshader test ()
      (let ((x 1)
	    (y 2))
	(v! x y 1 2))
      (v! 0 0 0 0))))

(deftest build-4 ()
  (finishes
    (defshader test ()
      (labels ((test () 1))
	(test))
      (v! 0 0 0 0))))

(deftest build-5 ()
  (signals varjo-conditions:could-not-find-function
    (defshader test ()
      (labels ((test () 1))
	(test))
      (v! 0 (test) 0 0))))

(deftest build-6 ()
  (signals varjo-conditions:symbol-unidentified
    (defshader test ()
      (let ((x 1)
	    (y 2))
	(v! 0 x 1 2))
      (v! 0 0 y 0))))

(deftest build-7 ()
  (finishes
    (defshader test ()
      (labels ((test () 1))
	(v! 0 (test) 0 0)))))

(deftest build-8 ()
  (finishes
    (defshader test ()
      (let ((x 2))
	(labels ((test () x))
	  (v! 0 (test) 0 0))))))

(deftest build-9 ()
  (signals varjo-conditions:setq-type-match
    (defshader test ()
      ())))

(deftest build-10 ()
  (finishes
    (defshader test ()
      (labels ((test ((x :int)) (values x 2)))
	(v! 0 (test 1))
	(v! 0 0 0 0)))))

(deftest build-11 ()
  (finishes
    (defshader test ()
      (values (v! 1 2 3 4)
	      (v! 1 2)))))

(deftest build-12 ()
  (finishes
    (defshader test ()
      (labels ((test ((x :int)) (values (v! 0 0 0 0) 2)))
	(test 1)))))

(deftest build-13 ()
  (finishes
    (defshader test ()
      (labels ((test ((x :int)) (values x 2)))
	(v! 0 (int (test 1)) 0 0)))))


(deftest build-14 ()
  (finishes
    (defshader test ()
      (values (v! 1 2 3 4)
	      (v! 1 2))
      (v! 10 20 30 40))))

(deftest build-15 ()
  (finishes
    (defshader test ()
      (labels ((test ((x :int)) (values (v! 0 0 0 0) 2)))
	(test 1)
	(v! 10 20 30 40)))))

(deftest build-16 ()
  (finishes
    (defshader test ()
      (labels ((test ((x :int)) (values x 2)))
	(v! 0 (int (test 1)) 0 0)
	(v! 10 20 30 40)))))

(deftest build-17 ()
  (finishes
    (defshader test ()
      (let ((x 1))
	(let ((y 2)
	      (z 3))
	  (v! x y z)
	  (%if (> x 2)
	       (setq x y)
	       (setq x z))
	  (v! x 2 3 4))))))

(deftest build-18 ()
  (finishes
    (defshader test ()
      (let ((x 0)
	    (z 1))
	(v! x z)
	(switch x
	  (0 (setq z 1))
	  (1 (setq z x))
	  (2 z))
	(v! x z 3 4)))))

(deftest build-19 ()
  (finishes
    (defshader test ()
      (let ((x 0)
	    (z 1))
	(v! x z)
	(while (< x 10)
	  (setq x z)
	  (setq z (+ 1 1)))
	(v! x z 3 4)))))

(deftest build-20 ()
  (finishes
    (defshader test ()
      (let ((x 1)
	    (y 2)
	    (z 3))
	(v! x y 0 0)))))

(deftest build-21 ()
  (finishes
    (defshader test ()
      (multiple-value-bind (x y) (values 1 2)
	(v! 0 0 0 0)))))

;; (defshader test ()
;;   (let ((x 1))
;;     (v! x x)
;;     (%if (> x 2)
;; 	 1
;; 	 2)
;;     (v! x 2 3 4)))
