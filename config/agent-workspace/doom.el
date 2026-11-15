;;; $DOOMDIR/config/agent-workspace/doom.el -*- lexical-binding: t; -*-
;; What ties the agent workspace to this config: its keys bound in evil's
;; states too, a terminal offered to start git. Loaded from
;; config/agent-workspace.el, after the app's parts.

(defun +my/agent-workspace-bind (map keys)
  "KEYS ((KEY . COMMAND)...) in MAP, Emacs's and evil's normal and motion
states'."
  (pcase-dolist (`(,key . ,command) keys)
    (define-key map (kbd key) command)
    (after! evil
      (evil-define-key* '(normal motion) map (kbd key) command))))

(defun +my/agent-workspace-git-init (dir reason)
  "Offer a terminal in DIR with git init typed: its project can have no crew
for REASON."
  (if (not (y-or-n-p (format "No crew in %s: %s. Open a terminal with `git init' to run? "
                             (abbreviate-file-name dir) reason)))
      (message "No crew without git: run `git init' (and a first commit) in %s" (abbreviate-file-name dir))
    (unless (fboundp 'ghostel-new)
      (user-error "No terminal (ghostel): run `git init' in %s" (abbreviate-file-name dir)))
    (let* ((default-directory dir)
           (buffer (ghostel-new)))
      (when (fboundp '+my/beads--type-when-ready)
        (+my/beads--type-when-ready buffer (if (string-prefix-p "no commit" reason)
                                               "git add -A && git commit -m 'First commit'"
                                             "git init")))
      (message "Run it (RET), then SPC o w again")
      buffer)))

