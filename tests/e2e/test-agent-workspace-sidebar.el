;;; tests/e2e/test-agent-workspace-sidebar.el -*- lexical-binding: t; -*-
;; config/agent-workspace/sidebar.el with the real treemacs in a GUI Emacs:
;; once the app is left, the crew's lanes under treemacs's window (a side
;; window of its own, as wide), drawn; treemacs closed, gone; opened again,
;; back. No agent runs: sessions are buffers.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "treemacs"))))))
  (load (expand-file-name "treemacs/treemacs-autoloads" build) t t))

(setq treemacs-persist-file (+test-tmp-file "treemacs/persist")
      treemacs-last-error-persist-file (+test-tmp-file "treemacs/last-error"))

(require 'agent-shell)
(require 'nerd-icons)
(+test-load "config/window" "config/treemacs" "config/agent-ui" "config/agent-workspace")
(require 'treemacs)
(treemacs-git-mode -1)
(treemacs-filewatch-mode -1)
(when (timerp +my/treemacs--git-poll-timer)
  (cancel-timer +my/treemacs--git-poll-timer))

(defun +test-e2e-aws--project ()
  "A git repository with a commit: its folder."
  (let ((dir (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "aws-e2e-") t)))))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    dir))

(defun +test-e2e-aws--panel ()
  (agent-workspace--sidebar-window (selected-frame)))

(defun +test-e2e-aws--tall-p (lines)
  "Non-nil if the crew under treemacs is as tall as its header line, LINES
and its padding (half a line above and under them), to the pixel."
  (when-let* ((panel (+test-e2e-aws--panel)))
    (let ((line (window-default-line-height panel)))
      (= (window-pixel-height panel)
         (+ (window-header-line-height panel) (/ line 2) (* lines line) (/ line 2)
            (window-bottom-divider-width panel))))))

(ert-deftest e2e-agent-workspace-sidebar/under-treemacs ()
  "The app left, treemacs on the crew's project: its lanes under treemacs,
as wide, drawn, as tall as the minimap's (its header line, a lane each, the
axis and legend, its padding), to the pixel. treemacs quit and shown again at once (a workspace
switch: treemacs--change-buffer-on-scope-change; its new window split from
the crew's, half each), or a border dragged: back to that height
\(doom-pbk.127). treemacs closed: gone; opened again: back."
  (let* ((project (+test-e2e-aws--project))
         (default-directory project))
    (cl-letf (((symbol-function 'agent-workspace--start)
               (lambda (agent)
                 (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                   (with-current-buffer buffer (setq agent-workspace--agent agent))
                   (setf (agent-workspace-agent-buffer agent) buffer
                         (agent-workspace-agent-state agent) 'desk)
                   (agent-workspace--changed agent 'session)
                   buffer)))
              ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
      (+test-e2e-frame-reset)
      (delete-other-windows)
      (agent-workspace-create :role "builder" :name "ada")
      (agent-workspace-create :role "investigator" :name "sam")
      (unwind-protect
          (progn
            (agent-workspace-open t)
            (agent-workspace-leave)
            (find-file (expand-file-name "README" project))
            (save-selected-window
              (let ((inhibit-message t))
                (treemacs-add-and-display-current-project-exclusively)))
            (should (+test-wait-for #'+test-e2e-aws--panel 10))
            (let ((panel (+test-e2e-aws--panel))
                  (treemacs (treemacs-get-local-window)))
              (should (eq (window-in-direction 'below treemacs t) panel))
              (should (= (window-total-width panel) (window-total-width treemacs)))
              (redisplay t)
              (should (+test-e2e-aws--tall-p 4))
              (with-current-buffer (window-buffer panel)
                (should (string-search "▌A" (buffer-string)))
                (should (string-search "▌S" (buffer-string))))
              (should (string-match-p "CREW" (format-mode-line (buffer-local-value 'header-line-format
                                                                                   (window-buffer panel))
                                                               nil panel (window-buffer panel)))))
            ;; A workspace switch: treemacs quit and shown again. Back to its
            ;; height, not half the column.
            (save-selected-window (treemacs--change-buffer-on-scope-change))
            (should (+test-wait-for (lambda () (redisplay t) (+test-e2e-aws--tall-p 4)) 5))
            ;; A border dragged: back.
            (let ((window-resize-pixelwise t))
              (window-resize (+test-e2e-aws--panel) (* 5 (frame-char-height)) nil t t))
            (should (+test-wait-for (lambda () (redisplay t) (+test-e2e-aws--tall-p 4)) 5))
            ;; treemacs closed: gone; opened again: back.
            (delete-window (treemacs-get-local-window))
            (should (+test-wait-for (lambda () (redisplay t) (not (+test-e2e-aws--panel))) 5))
            (save-selected-window
              (let ((inhibit-message t))
                (treemacs-add-and-display-current-project-exclusively)))
            (should (+test-wait-for (lambda () (redisplay t) (+test-e2e-aws--panel)) 10)))
        (when (treemacs-get-local-window) (delete-window (treemacs-get-local-window)))
        (when (agent-workspace--app project) (agent-workspace--close-app project))
        (agent-workspace-close-all)
        (agent-workspace--sidebar-sync)
        (delete-other-windows)))))
