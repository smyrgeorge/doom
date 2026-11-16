;;; $DOOMDIR/config/agent-workspace/doom.el -*- lexical-binding: t; -*-
;; What ties the agent workspace to this config: its keys bound in evil's
;; states too, a terminal offered to start git, the app's display rule kept
;; under Doom's popups. Loaded from config/agent-workspace.el, after the
;; app's parts.

(defvar +popup--display-buffer-alist)

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

;; THE APP'S DISPLAY RULE UNDER DOOM'S POPUPS
;; A file shown from the app goes where you came from: a rule of
;; `display-buffer-alist' (app.el, `agent-workspace--display-rule'). Doom's
;; popup mode, turned on, sets that list aside for its own rules
;; (`+popup--display-buffer-alist'), put there again each time a popup rule is
;; set (`set-popup-rule!', as a package loads); turned off, it puts back the
;; list it set aside. So the rule is in Doom's rules too, and put in the list
;; again each time popup mode turns on or off: in effect whichever came first,
;; the app or Doom's popups. (Lost, a file opened from the app opened among
;; its windows: over the agent's session in its pane, or in a bar a row high.)
(defun +my/agent-workspace--keep-display-rule ()
  "The app's display rule (`agent-workspace--display-rule') in
`display-buffer-alist', and in Doom's popup rules once they're loaded. In
`+popup-mode-hook'."
  (add-to-list 'display-buffer-alist agent-workspace--display-rule)
  (when (boundp '+popup--display-buffer-alist)
    (add-to-list '+popup--display-buffer-alist agent-workspace--display-rule)))

(+my/agent-workspace--keep-display-rule)
(add-hook '+popup-mode-hook #'+my/agent-workspace--keep-display-rule)
