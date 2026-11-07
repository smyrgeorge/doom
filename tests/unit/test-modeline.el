;;; tests/unit/test-modeline.el -*- lexical-binding: t; -*-
;; config/editor/modeline.el: a space after the mode line's last item on the right,
;; in every doom-modeline layout.

(+test-load "config/editor")

;; Done once doom-modeline loads (`after!'): not loaded yet here.
(defconst +test-modeline--loaded-first (featurep 'doom-modeline))
(require 'doom-modeline)

(defconst +test-modeline--layouts
  '(main minimal special project dashboard vcs package info media message pdf
    org-src helm git-timemachine calculator speedbar)
  "doom-modeline's layouts.")

(defun +test-modeline--rhs (name)
  (nth 2 (assq name doom-modeline--modelines)))

(defmacro +test-modeline--with-layouts (layouts &rest body)
  "BODY with LAYOUTS ((NAME LHS RHS)...) defined too, removed after."
  (declare (indent 1))
  `(let ((before (copy-tree doom-modeline--modelines)))
     (unwind-protect
         (progn
           (pcase-dolist (`(,name ,lhs ,rhs) ,layouts)
             (doom-modeline-def-modeline name lhs rhs))
           ,@body)
       (setq doom-modeline--modelines before))))

;; ====== A SPACE ON THE RIGHT ======

(ert-deftest modeline/space-once-doom-modeline-loads ()
  (should-not +test-modeline--loaded-first)
  (should (equal (car (last (+test-modeline--rhs 'main))) " ")))

(ert-deftest modeline/every-layout ()
  (dolist (name +test-modeline--layouts)
    (let ((rhs (+test-modeline--rhs name)))
      (should rhs)
      (should (equal (car (last rhs)) " "))))
  ;; Any others doom-modeline has too.
  (pcase-dolist (`(,name ,_ ,rhs) doom-modeline--modelines)
    (when rhs
      (should (equal (list name (car (last rhs))) (list name " "))))))

(ert-deftest modeline/one-space ()
  "Only one, and the items kept before it."
  (pcase-dolist (`(,name ,_ ,rhs) doom-modeline--modelines)
    (when rhs
      (should-not (equal (last rhs 2) '(" " " ")))
      (should (> (length rhs) 1))
      (ignore name))))

(ert-deftest modeline/the-mode-line-ends-with-it ()
  "The layout's format (what the mode line shows) has the space last."
  (with-temp-buffer
    (let ((format (doom-modeline-format--main)))
      (should (equal (car (last (car (last format)))) " ")))))

(ert-deftest modeline/again-adds-none ()
  "Applied again (the config reloaded): no second space."
  (let ((before (copy-tree doom-modeline--modelines)))
    (+test-load "config/editor/modeline")
    (should (equal doom-modeline--modelines before))))

(ert-deftest modeline/layouts-defined-before-it-runs ()
  "A layout with items on the right gets the space; one without, or with one
already, stays as it is."
  (+test-modeline--with-layouts '((+test-a (bar buffer-info) (major-mode))
                                  (+test-b (bar buffer-info) nil)
                                  (+test-c (bar buffer-info) (major-mode " ")))
    (+test-load "config/editor/modeline")
    (should (equal (+test-modeline--rhs '+test-a) '(major-mode " ")))
    (should (equal (+test-modeline--rhs '+test-b) nil))
    (should (equal (+test-modeline--rhs '+test-c) '(major-mode " ")))
    ;; The left side untouched.
    (should (equal (nth 1 (assq '+test-a doom-modeline--modelines)) '(bar buffer-info)))
    ;; Its format redefined with it.
    (should (equal (car (last (car (last (doom-modeline-format--+test-a))))) " "))))

;; ====== LOADED ======

(defun +test-modeline--forms (file)
  "FILE's (of this config) top-level forms."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      forms)))

(ert-deftest modeline/config-el-loads-it ()
  "config.el loads the editor, which loads it."
  (should (member '(load! "config/editor") (+test-modeline--forms "config.el")))
  (should (member '(load! "editor/modeline") (+test-modeline--forms "config/editor.el"))))
