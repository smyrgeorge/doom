;;; tests/unit/test-libraries.el -*- lexical-binding: t; -*-
;; config/emacs/libraries.el: the functions of Emacs's libraries this config
;; uses, autoloaded (the libraries loaded when first used, not as Emacs
;; starts): each from the library that defines it. That config.el loads none
;; of them: test-config.el.

(require 'cl-lib)

(defun +test-libraries--autoloads ()
  "libraries.el's list: ((LIBRARY FUNCTION...)...)."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config/emacs/libraries.el" +test-root))
    (let ((form (read (current-buffer))))
      ;; (dolist (library '(...)) ...)
      (should (eq (car form) 'dolist))
      (cadr (cadr (cadr form))))))

(ert-deftest libraries/each-function-from-its-library ()
  "Each function named is autoloaded from its library (one Emacs hadn't
loaded yet), and is defined once that library is loaded: no name mistyped,
none from another library."
  (let ((autoloads (+test-libraries--autoloads)))
    (should (> (length autoloads) 5))
    (pcase-dolist (`(,library . ,functions) autoloads)
      (dolist (function functions)
        (let ((definition (symbol-function function)))
          (when (autoloadp definition)
            (should (equal (cadr definition) library)))))
      (require (intern library))
      (dolist (function functions)
        (should (fboundp function))
        (should-not (autoloadp (symbol-function function)))))))

(ert-deftest libraries/a-function-called-loads-its-library ()
  "A function called before its library is loaded: the library loads, the
call goes on. In a fresh Emacs (this one's tests loaded some)."
  (let ((out (with-temp-buffer
               (call-process (expand-file-name invocation-name invocation-directory) nil t nil
                             "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "libraries-home/"))
                             "-l" (expand-file-name "config/emacs/libraries.el" +test-root)
                             "--eval" (prin1-to-string
                                       '(princ (list (featurep 'svg) (featurep 'map)
                                                     (map-elt '((a . 1)) 'a)
                                                     (car (svg-create 10 10))
                                                     (featurep 'svg) (featurep 'map)))))
               (buffer-string))))
    (should (string-suffix-p "(nil nil 1 svg t t)" out))))
