;;;;  -*- Mode: Lisp; Syntax: Common-Lisp; Package: C -*-
;;;;
;;;;  Copyright (c) 2009, Juan Jose Garcia-Ripoll.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.
;;;;
;;;; CMPTYPE-PROP -- Type propagation basic routines and database
;;;;

(in-package #-new-cmp "COMPILER" #+new-cmp "C-TYPES")

(defun infer-arg-and-return-types (fname forms &optional (env *cmp-env*))
  (let ((found (sys:get-sysprop fname 'C1TYPE-PROPAGATOR))
        arg-types
        (return-type '(VALUES &REST T)))
    (cond (found
           (multiple-value-setq (arg-types return-type)
             (apply found fname (mapcar #'location-primary-type forms))))
          ((multiple-value-setq (arg-types found)
             (get-arg-types fname env))
           (setf return-type (or (get-return-type fname) return-type))))
    (values arg-types return-type found)))

(defun enforce-types (fname arg-types arguments)
  (do* ((types arg-types (rest types))
        (args arguments (rest args))
        (i 1 (1+ i))
        (in-optionals nil))
       ((endp types)
        (when types
          (cmpwarn "Too many arguments passed to ~A" fname)))
    (let ((expected-type (first types)))
      (when (member expected-type '(* &rest &key &allow-other-keys) :test #'eq)
        (return))
      (when (eq expected-type '&optional)
        (when (or in-optionals (null (rest types)))
          (cmpwarn "Syntax error in type proclamation for function ~A.~&~A"
                   fname arg-types))
        (setf in-optionals t
              types (rest types)
              expected-type (first types)))
      (when (endp args)
        (unless in-optionals
          (cmpwarn "Too few arguments for proclaimed function ~A" fname))
        (return))
      (let* ((value (first args))
             (actual-type (location-primary-type value))
             (intersection (type-and actual-type expected-type)))
          (unless intersection
            (cmperr "The argument ~d of function ~a has type~&~4T~A~&instead of expected~&~4T~A"
                    i fname actual-type expected-type))
          #-new-cmp
          (when (zerop (cmp-env-optimization 'safety))
            (setf (c1form-type value) intersection))))))

(defun propagate-types (fname forms)
  (multiple-value-bind (arg-types return-type found)
      (infer-arg-and-return-types fname forms)
    (when found
      (enforce-types fname arg-types forms))
    return-type))

(defmacro def-type-propagator (fname lambda-list &body body)
  (unless (member '&rest lambda-list)
    (let ((var (gensym)))
      (setf lambda-list (append lambda-list (list '&rest var))
            body (list* `(declare (ignorable ,var)) body)))
    `(sys:put-sysprop ',fname 'C1TYPE-PROPAGATOR
                      #'(ext:lambda-block ,fname ,lambda-list ,@body))))

(defun copy-type-propagator (orig dest-list)
  (loop with function = (sys:get-sysprop orig 'C1TYPE-PROPAGATOR)
     for name in dest-list
     do (sys:put-sysprop name 'C1TYPE-PROPAGATOR function)))
