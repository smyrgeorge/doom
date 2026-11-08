;;; tests/unit/test-emacs.el -*- lexical-binding: t; -*-
;; config/emacs.el: garbage collection waits for 32 MB while idle (gcmh's low
;; threshold), instead of gcmh's 800 KB.

(+test-load "config/emacs")

;; Set before gcmh loads (Doom loads it with the first buffer).
(defconst +test-emacs--gcmh-loaded-first (featurep 'gcmh))
(require 'gcmh)

(defun +test-emacs--config-forms ()
  "The top-level forms of config.el."
  (let (forms)
    (with-temp-buffer
      (insert-file-contents (expand-file-name "config.el" +test-root))
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file)))
    (nreverse forms)))

;; ====== GARBAGE COLLECTION ======

(ert-deftest emacs/idle-threshold-32mb ()
  (should-not +test-emacs--gcmh-loaded-first)
  (should (= gcmh-low-cons-threshold (* 32 1024 1024))))

(ert-deftest emacs/gcmh-keeps-it ()
  "gcmh's own default (800 KB) doesn't replace it once gcmh loads."
  (should (= (eval (car (get 'gcmh-low-cons-threshold 'standard-value))) 800000))
  (should (= gcmh-low-cons-threshold (* 32 1024 1024))))

(ert-deftest emacs/idle-collection-leaves-32mb ()
  "After collecting while idle, the next collection waits for 32 MB."
  (let ((gc-cons-threshold gc-cons-threshold))
    (cl-letf (((symbol-function 'garbage-collect) #'ignore))
      (gcmh-idle-garbage-collect))
    (should (= gc-cons-threshold (* 32 1024 1024)))))

(ert-deftest emacs/working-threshold-unchanged ()
  "While commands run, gcmh's high threshold: not this file's."
  (should (= gcmh-high-cons-threshold (eval (car (get 'gcmh-high-cons-threshold 'standard-value))))))

(ert-deftest emacs/gcmh-mode-off-leaves-32mb ()
  (let ((gc-cons-threshold gc-cons-threshold))
    (unwind-protect
        (progn (gcmh-mode 1)
               (should (= gc-cons-threshold gcmh-high-cons-threshold))
               (gcmh-mode -1)
               (should (= gc-cons-threshold (* 32 1024 1024))))
      (gcmh-mode -1))))

(ert-deftest emacs/config-el-loads-it-first ()
  "First of the config files, so it holds from the start: after config/os.el
only, which defines functions the others use (nothing runs)."
  (let* ((forms (+test-emacs--config-forms))
         (loads (seq-filter (lambda (form) (eq (car-safe form) 'load!)) forms)))
    (should (equal (seq-take loads 2) '((load! "config/os") (load! "config/emacs"))))))
