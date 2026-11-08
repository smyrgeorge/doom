;;; $DOOMDIR/config/beads/project.el -*- lexical-binding: t; -*-
;; The project's issues: SPC o i, SPC o I. Loaded from config/beads.el.

;; THE PROJECT'S ISSUES
;; SPC o i: the issues of the project the current buffer is in (its .beads/),
;; SPC o I: a new one there (title, type, priority). A project without .beads/
;; is offered a terminal to start (see STARTING below).
(defun +my/beads--project-root ()
  "The current project's root (else this folder)."
  (file-name-as-directory (expand-file-name (or (doom-project-root) default-directory))))

(defun +my/beads-root ()
  "The current project's root, if it tracks its issues with Beads."
  (let ((root (+my/beads--project-root)))
    (and (file-directory-p (expand-file-name ".beads" root))
         root)))

;; STARTING
;; In a project without .beads/, SPC o i and SPC o I don't start tracking its
;; issues themselves: `bd init' does more than add .beads/ (it commits, with
;; what's staged; it can set the repository's git hooks and sync remote, add
;; files for agents). Asked first, they open a terminal at the project's root
;; (as SPC o t, in its pane) with `+my/beads-init-command' typed, not run:
;; read it, change it, run it (RET), then SPC o i again.
(defun +my/beads--type-when-ready (buffer text &optional tries last)
  "Type TEXT into terminal BUFFER, not run, once its shell has drawn its
prompt (its text unchanged for a moment); given up after 5 seconds."
  (when (buffer-live-p buffer)
    (let ((now (with-current-buffer buffer
                 (string-trim (buffer-substring-no-properties (point-min) (point-max)))))
          (tries (or tries 0)))
      (cond ((and (not (string-empty-p now)) (equal now last))
             (with-current-buffer buffer
               (ghostel-send-string text)))
            ((< tries 50)
             (run-at-time 0.1 nil #'+my/beads--type-when-ready buffer text (1+ tries) now))))))

(defun +my/beads-init-in-terminal (root)
  "Offer a terminal at ROOT with `+my/beads-init-command' typed (see
STARTING); its buffer, or nil if declined."
  (if (not (y-or-n-p (format "%s doesn't track its issues with Beads. Open a terminal with `%s' to run? "
                             (abbreviate-file-name root) +my/beads-init-command)))
      (progn (message "Run `%s' in %s to track its issues" +my/beads-init-command
                      (abbreviate-file-name root))
             nil)
    (unless (fboundp 'ghostel-new)
      (user-error "No terminal (ghostel): run `%s' in %s" +my/beads-init-command
                  (abbreviate-file-name root)))
    (let* ((default-directory root)
           (buffer (ghostel-new)))
      (+my/beads--type-when-ready buffer +my/beads-init-command)
      (message "Run it (RET), then SPC o i again")
      buffer)))

(defun +my/beads--root-or-terminal ()
  "The current project's root, if it tracks its issues with Beads; else a
terminal offered to start (see STARTING), and nothing more done."
  (or (+my/beads-root)
      (progn (+my/beads-init-in-terminal (+my/beads--project-root))
             nil)))

;; PANES
;; Issues are an application (config/tiling.el's TILING FIRST): SPC o i
;; opens the list in a new pane where tiling puts it (its pane, shown
;; already), not in place of the current buffer as beads.el has it; an issue
;; opened from it (RET) in a new pane too, the next ones in that pane (as its
;; tabs), not each in a new one.
(defun +my/beads-project ()
  "The current project's issues (see above)."
  (interactive)
  (when-let* ((root (+my/beads--root-or-terminal)))
    (let ((default-directory root)
          ;; beads.el shows its list with `switch-to-buffer': as `display-buffer'
          ;; would (tiling's application in a new pane).
          (switch-to-buffer-obey-display-actions t))
      ;; All of beads.el: its list uses beads.el's own (`beads-show-hint').
      (require 'beads)
      (beads-list))))

(defun +my/beads--issue-window ()
  "A window of this frame showing an issue (not the list's preview)."
  (seq-find (lambda (window)
              (with-current-buffer (window-buffer window)
                (and (derived-mode-p '(beads-detail-mode beads-detail-vui-mode))
                     (not (equal (buffer-name) "*Beads Preview*")))))
            (window-list nil 'nomini)))

(defun +my/beads-issue-pane-a (fn &rest args)
  "`beads-detail-open': an issue shown where another one is (see PANES)."
  (if-let* ((window (+my/beads--issue-window)))
      (let ((display-buffer-overriding-action
             ;; Not its size (beads.el's 40% height): the pane's.
             (list (lambda (buffer _alist)
                     (window--display-buffer buffer window 'reuse)))))
        (apply fn args))
    (apply fn args)))

(advice-add 'beads-detail-open :around #'+my/beads-issue-pane-a)

(defun +my/beads-new-issue ()
  "A new issue in the current project (see above)."
  (interactive)
  (when-let* ((root (+my/beads--root-or-terminal)))
    (let ((default-directory root))
      (require 'beads)
      (call-interactively #'beads-create-issue))))
