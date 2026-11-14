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

;; EACH PROJECT ITS LIST
;; beads.el named a project's list by its folder's name alone (*Beads:
;; NAME*), and kept the list's buffer, and its folder, where bd runs: two
;; projects of the same name (~/work/api, ~/play/api) shared one list, which
;; showed the first one's issues, and c created issues there. A project's
;; list is its own now: *Beads: NAME*, or where another project's list has
;; that name, *Beads: PARENT/NAME* (else its whole path); bd run at its root.
(defun +my/beads--list-root (&optional dir)
  "The root of the project whose issues are listed from DIR (else
`default-directory'): the folder with .beads/ from there up, else DIR."
  (let ((dir (or dir default-directory)))
    (file-name-as-directory (expand-file-name (or (locate-dominating-file dir ".beads") dir)))))

(defun +my/beads--list-of-p (buffer root)
  "Whether BUFFER is the issue list of ROOT's project (where it was opened:
its folder may be bound to another for a moment)."
  (with-current-buffer buffer
    (and (derived-mode-p 'beads-list-mode)
         (equal (+my/beads--list-root (or beads-list--project-root default-directory)) root))))

(defun +my/beads-list-name (root)
  "The name of ROOT's issue list (see above): the one open for it, else the
first of *Beads: NAME*, *Beads: PARENT/NAME* and *Beads: PATH* no buffer has."
  (or (seq-some (lambda (buffer) (and (+my/beads--list-of-p buffer root) (buffer-name buffer)))
                (buffer-list))
      (let* ((dir (directory-file-name root))
             (name (file-name-nondirectory dir))
             (names (mapcar (lambda (name) (format "*Beads: %s*" name))
                            (list name
                                  (file-name-concat (file-name-nondirectory
                                                     (directory-file-name (file-name-directory dir)))
                                                    name)
                                  (abbreviate-file-name dir)))))
        (or (seq-find (lambda (name) (not (get-buffer name))) names)
            (generate-new-buffer-name (car (last names)))))))

(defun +my/beads-list-name-a (&rest _)
  "`beads-project-buffer-name': the list's name for the project of
`default-directory' (see above)."
  (+my/beads-list-name (+my/beads--list-root)))

(advice-add 'beads-project-buffer-name :override #'+my/beads-list-name-a)

;; PANES
;; Issues are an application (config/tiling.el's TILING FIRST): SPC o i
;; opens the list in a new pane where tiling puts it (its pane, shown
;; already), not in place of the current buffer as beads.el has it; an issue
;; opened from it (RET) in a new pane too, the next ones in that pane (as its
;; tabs), not each in a new one.
(defun +my/beads--show-list (root &optional filter)
  "ROOT's issue list shown (see above), with FILTER (beads.el's) if given."
  (let ((default-directory root)
        ;; beads.el shows its list with `switch-to-buffer': as `display-buffer'
        ;; would (tiling's application in a new pane).
        (switch-to-buffer-obey-display-actions t))
    ;; All of beads.el: its list uses beads.el's own (`beads-show-hint').
    (require 'beads)
    ;; Its list's bd run at its root (see EACH PROJECT ITS LIST).
    (let ((list (get-buffer-create (+my/beads-list-name root))))
      (with-current-buffer list
        (unless (derived-mode-p 'beads-list-mode)
          (beads-list-mode))
        (setq default-directory root)
        (when filter
          (setq beads-list--filter filter)))
      ;; Shown, then drawn (beads.el drew it first): for its pane's width
      ;; (config/beads/look.el).
      (switch-to-buffer list))
    (beads-list)))

(defun +my/beads-project ()
  "The current project's issues (see above)."
  (interactive)
  (when-let* ((root (+my/beads--root-or-terminal)))
    (+my/beads--show-list root)))

;; AN ISSUE'S CHILDREN (C in an issue): its project's list, filtered to them
;; (said in a notice, with Clear filter). beads.el looked for a list named
;; *Beads Issues* (none: lists are named by their project) and set a filter
;; the list never read: C failed.
(defun +my/beads-children-a (&rest _)
  "`beads-detail-view-children': the issue's children in its project's list
\(see above)."
  (let ((id (alist-get 'id (beads-detail--require-issue))))
    (require 'beads-filter)
    (+my/beads--show-list (+my/beads--list-root) (beads-filter-by-parent id))
    (message "Showing children of %s" id)))

(advice-add 'beads-detail-view-children :override #'+my/beads-children-a)

(defun +my/beads--issue-window ()
  "A window of this frame showing an issue (not the list's preview)."
  (seq-find (lambda (window)
              (with-current-buffer (window-buffer window)
                (and (derived-mode-p '(beads-detail-mode beads-detail-vui-mode))
                     (not (string-prefix-p "*Beads Preview" (buffer-name))))))
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

;; An issue's buffer is drawn (vui) inside `save-window-excursion', not to be
;; shown; but vui shows it (`switch-to-buffer') and the window it showed it in
;; (the list's pane) kept it in its history: a tab of the list's pane, where
;; the issue then opened. Drawn not shown (vui's NO-DISPLAY).
(defvar +my/beads--drawing nil
  "Non-nil while beads.el draws an issue's buffer.")

(defun +my/beads-draw-not-show-a (fn &rest args)
  (let ((+my/beads--drawing t))
    (apply fn args)))

(defun +my/beads-vui-no-display-a (args)
  "`vui-mount''s ARGS, NO-DISPLAY set while beads.el draws an issue."
  (if +my/beads--drawing
      (list (nth 0 args) (nth 1 args) t)
    args))

(advice-add 'beads-detail--render-vui :around #'+my/beads-draw-not-show-a)
(advice-add 'vui-mount :filter-args #'+my/beads-vui-no-display-a)

;; An issue's buffer notes its issue (`beads-detail-open'), then turns to vui's
;; mode to draw it: a mode change forgets a buffer's variables, so it forgot
;; which issue it shows (gr: "No issue to refresh"; Claude's bd commands
;; didn't refresh it; C-c C-a found no issue). Kept across it.
(put 'beads-detail--current-issue-id 'permanent-local t)
(put 'beads-detail--current-issue 'permanent-local t)

(defun +my/beads-new-issue ()
  "A new issue in the current project (see above)."
  (interactive)
  (when-let* ((root (+my/beads--root-or-terminal)))
    (let ((default-directory root))
      (require 'beads)
      (call-interactively #'beads-create-issue))))
