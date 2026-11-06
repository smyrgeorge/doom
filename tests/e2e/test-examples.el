;;; tests/e2e/test-examples.el -*- lexical-binding: t; -*-
;; The examples in a GUI Emacs: the merge example's panes on screen, its
;; wands in the Result's margin; Done, and its repository is gone.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/window" "config/tabs" "config/merge" "config/examples")
(global-tab-line-mode 1)

(ert-deftest e2e-examples/merge ()
  (+test-with-reset
    (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "examples-home-") t)))
           (process-environment
            (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                          "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0")
                    process-environment)))
      (with-temp-file (expand-file-name ".gitconfig" home))
      (call-interactively #'+my/example-merge)
      (+test-sleep 0.3)
      (let* ((session (buffer-local-value '+my/merge--session (current-buffer)))
             (repo (+my/merge-toplevel session))
             (result (get-buffer-window (+my/merge-result session))))
        (should (get-buffer-window (+my/merge-yours session)))
        (should (get-buffer-window (+my/merge-theirs session)))
        (should (get-buffer-window (+my/merge-bar session)))
        (should (eq (selected-window) result))
        ;; The wands, in the Result's margin.
        (should (equal (window-margins result) '(2)))
        (should (= 2 (with-current-buffer (+my/merge-result session)
                       (seq-count (lambda (ov)
                                    (equal (car-safe (get-text-property 0 'display (or (overlay-get ov 'before-string) " ")))
                                           '(margin left-margin)))
                                  (overlays-in (point-min) (point-max))))))
        (+my/merge-apply-non-conflicting)
        (+my/merge-accept-left)
        (+my/merge-done)
        (should-not (file-exists-p repo))
        (should-not (buffer-live-p (+my/merge-result session)))))))
