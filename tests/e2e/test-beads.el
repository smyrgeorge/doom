;;; tests/e2e/test-beads.el -*- lexical-binding: t; -*-
;; config/beads.el in a GUI Emacs: the issue list's notices (what it hides)
;; laid over its column titles by the banner's child frame, the titles kept in
;; the row under them. The real bd (skipped without it), in a temp git repo
;; with a temp HOME.

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(+test-load "config/childframe" "config/banner" "config/window" "config/tiling" "config/beads")
(require 'beads)

(defun +test-beads-e2e--run (program &rest args)
  (with-temp-buffer
    (unless (zerop (apply #'call-process program nil t nil args))
      (error "%s %s: %s" program (string-join args " ") (buffer-string)))))

(ert-deftest e2e-beads/the-notice-over-the-column-titles ()
  (unless (executable-find "bd")
    (ert-skip "No bd (scripts/tools.sh installs it)"))
  (+test-with-reset
    (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
           (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-repo-") t))))
           (process-environment
            (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                          "GIT_CONFIG_NOSYSTEM=1" (concat "XDG_CONFIG_HOME=" home ".config")
                          "BD_ACTOR=Tester")
                    process-environment))
           (default-directory repo))
      (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) repo)))
        (with-temp-file (expand-file-name ".gitconfig" home)
          (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                  "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
        (+test-beads-e2e--run "git" "init" "-q")
        (+test-beads-e2e--run "bd" "init" "--quiet" "--prefix" "t")
        (+test-beads-e2e--run "bd" "create" "Still open" "--quiet")
        (+test-beads-e2e--run "bd" "close" (string-trim (with-temp-buffer
                                                         (call-process "bd" nil t nil "create" "Done" "--silent")
                                                         (buffer-string)))
                              "--quiet")
        (unwind-protect
            (progn
              (+my/beads-project)
              (let* ((window (selected-window))
                     (row (+my/banner--row-height window))
                     (frame (+test-wait-for
                             (lambda ()
                               (let ((frame (nth 1 (assq window +my/banner--frames))))
                                 (and (frame-live-p frame) (+my/childframe-shown-p frame) frame)))
                             5)))
                (should (derived-mode-p 'beads-list-mode))
                (should frame)
                (should (string-match-p "1 closed issue hidden"
                                        (with-current-buffer (window-buffer (frame-root-window frame))
                                          (buffer-string))))
                ;; Over the window's top row; the header line two rows tall
                ;; once drawn (the list is shown before it's drawn: its
                ;; window's height known until then is the empty list's), the
                ;; column titles in its bottom one, visible.
                (should (+test-wait-for
                         (lambda ()
                           (and (= (cdr (frame-position frame))
                                   (+ (nth 1 (window-pixel-edges window)) (window-tab-line-height window)))
                                (= (frame-pixel-height frame) row)))
                         3))
                (should (+test-wait-for (lambda () (>= (window-header-line-height window) (* 2 row))) 3))
                (should (string-match-p "Title" (format-mode-line header-line-format nil window)))))
          (dolist (buffer (buffer-list))
            (when (string-prefix-p "*Beads" (buffer-name buffer))
              (kill-buffer buffer)))
          (+test-sleep 0.2))))))
