;;; tests/e2e/test-treemacs-beads.el -*- lexical-binding: t; -*-
;; The sidebar beside the issue list (config/treemacs.el, config/beads.el) in a
;; GUI Emacs: the list opened in the pane beside it (SPC o i) and closed (q),
;; the sidebar keeps its width; so too when the pane was in a column with
;; another window then (a session's over its Agent UI canvas), gone before q
;; (config/emacs/window.el). The real bd (skipped without it), in a temp git
;; repo with a temp HOME.
;; run.sh: slow (~20 s beside the others: started first).

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "treemacs"))))))
  (load (expand-file-name "treemacs/treemacs-autoloads" build) t t))
(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)

(setq treemacs-persist-file (+test-tmp-file "treemacs/persist")
      treemacs-last-error-persist-file (+test-tmp-file "treemacs/last-error"))

(+test-load "config/emacs" "config/banner" "config/editor" "config/tiling" "config/treemacs" "config/beads")

(require 'treemacs)
(require 'beads)
(treemacs-git-mode -1)
(treemacs-filewatch-mode -1)
(when (timerp +my/treemacs--git-poll-timer)
  (cancel-timer +my/treemacs--git-poll-timer))

(defun +test-treemacs-beads--run (program &rest args)
  (with-temp-buffer
    (unless (zerop (apply #'call-process program nil t nil args))
      (error "%s %s: %s" program (string-join args " ") (buffer-string)))))

(defun +test-treemacs-beads--sidebar ()
  (seq-find (lambda (window) (with-current-buffer (window-buffer window) (derived-mode-p 'treemacs-mode)))
            (window-list nil 'nomini)))

(defun +test-treemacs-beads--with-project (body)
  "Call BODY in a Beads project with an open issue, a.txt open beside the
sidebar (35 columns), the frame 200 columns wide."
  (+test-with-reset
    (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
           (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-repo-") t))))
           (process-environment
            (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                          "GIT_CONFIG_NOSYSTEM=1" (concat "XDG_CONFIG_HOME=" home ".config")
                          "BD_ACTOR=Tester")
                    process-environment))
           (default-directory repo)
           (treemacs-width 35)
           (+my/treemacs--width-set-at nil))
      (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) repo)))
        (with-temp-file (expand-file-name ".gitconfig" home)
          (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                  "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
        (+test-bd-init "--quiet" "--prefix" "t")
        (+test-treemacs-beads--run "bd" "create" "Still open" "--quiet")
        (with-temp-file (expand-file-name "a.txt" repo) (insert "a\n"))
        (set-frame-width nil 200)
        (should (+test-wait-for (lambda () (= (frame-width) 200)) 3))
        (unwind-protect
            (progn
              (find-file (expand-file-name "a.txt" repo))
              (save-selected-window
                (let ((inhibit-message t))
                  (treemacs-add-and-display-current-project-exclusively)))
              (+test-sleep 0.5)
              (should (= (window-total-width (+test-treemacs-beads--sidebar)) 35))
              (funcall body))
          (dolist (buffer (buffer-list))
            (when (with-current-buffer buffer (derived-mode-p '(treemacs-mode beads-list-mode)))
              (kill-buffer buffer)))
          (+test-e2e-frame-reset))))))

(defun +test-treemacs-beads--quit-keeps-width (sidebar)
  "q in the issue list (as its key has it): SIDEBAR still 35 columns wide,
its width not taken as set by hand."
  (call-interactively (key-binding "q"))
  (+test-sleep 1)
  (should-not (derived-mode-p 'beads-list-mode))
  (should (window-live-p sidebar))
  (should (= (window-total-width sidebar) 35))
  (should (= treemacs-width 35))
  (should-not +my/treemacs--width-set-at))

(ert-deftest e2e-treemacs-beads/the-sidebar-keeps-its-width ()
  "SPC o i in the pane beside the sidebar, then q: the sidebar as wide as it
was."
  (unless (executable-find "bd")
    (ert-skip "No bd (scripts/tools.sh installs it)"))
  (+test-treemacs-beads--with-project
   (lambda ()
     (let ((sidebar (+test-treemacs-beads--sidebar)))
       (+my/beads-project)
       (should (derived-mode-p 'beads-list-mode))
       (+test-sleep 1)
       (should (= (window-total-width sidebar) 35))
       (+test-treemacs-beads--quit-keeps-width sidebar)))))

(ert-deftest e2e-treemacs-beads/a-column-gone-before-q ()
  "SPC o i in a pane in a column with another window (a session's over its
Agent UI canvas), that window gone, then q: the pane keeps its width, the
sidebar its own (Emacs gave the pane its old height as its width)."
  (unless (executable-find "bd")
    (ert-skip "No bd (scripts/tools.sh installs it)"))
  (+test-treemacs-beads--with-project
   (lambda ()
     (let* ((sidebar (+test-treemacs-beads--sidebar))
            (pane (selected-window))
            (below (split-window pane -12 'below)))
       (set-window-buffer below (get-buffer-create "*below*"))
       (+my/beads-project)
       (should (derived-mode-p 'beads-list-mode))
       (should (eq (selected-window) pane))
       ;; Its size noted (its height: in a column), to give back once the
       ;; list is quit (a.txt's noted first: the list's the one after it).
       (should (seq-some (lambda (parameter)
                           (let ((quit (window-parameter pane parameter)))
                             (and (eq (nth 3 quit) (window-buffer pane))
                                  (integerp (nth 3 (nth 1 quit))))))
                         '(quit-restore quit-restore-prev)))
       (+test-sleep 0.5)
       (delete-window below)
       (+test-sleep 0.5)
       (should (= (window-total-width sidebar) 35))
       (let ((width (window-total-width pane)))
         (+test-treemacs-beads--quit-keeps-width sidebar)
         (should (= (window-total-width pane) width)))
       (kill-buffer "*below*")))))
