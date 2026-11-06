;;; tests/diff-sh-emacs.el -*- lexical-binding: t; -*-
;; The Emacs cmd/diff.sh runs in tests/unit/test-cmd.el: tests/helper.el's
;; setup, the merge's config, and each merge then done as DIFF_TEST_ACTION
;; says, a moment after it opens: "right" (Accept Right, Done) or "abort".
;; Each merge opened is noted in DIFF_TEST_LOG.

;; Never left running: first, so whatever fails after.
(run-at-time 60 nil #'kill-emacs 3)

(load (expand-file-name "helper.el" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/merge" "config/examples")

(defun +test-diff-sh--act (session)
  (when (and (buffer-live-p (+my/merge-result session)) (not (+my/merge-finished session)))
    (with-current-buffer (+my/merge-result session)
      (pcase (getenv "DIFF_TEST_ACTION")
        ("right" (+my/merge-accept-right) (+my/merge-done))
        (_ (+my/merge-abort))))))

(advice-add '+my/merge--start :filter-return
            (lambda (session)
              (when-let* ((log (getenv "DIFF_TEST_LOG")))
                (write-region (format "%s %s\n" (+my/merge-path session)
                                      (if (display-graphic-p) "gui" "tty"))
                              nil log t 'silent))
              (run-at-time 0.3 nil #'+test-diff-sh--act session)
              session)
            '((name . +test-diff-sh)))

