;;; $DOOMDIR/config/treemacs.el -*- lexical-binding: t; -*-
;; Treemacs project sidebar (IntelliJ-like). Loaded from config.el.

;; ====== VARIABLES ======

;; TREEMACS (IntelliJ-like project view)
(setq +treemacs-git-mode 'deferred)     ; async git status, incl. folders (python3)

;; Treemacs hides its window from winum; number it (leftmost => SPC w 1).
(after! (treemacs winum)
  (setq winum-ignored-buffers-regexp
        (remove (regexp-quote treemacs-buffer-name-prefix)
                winum-ignored-buffers-regexp)))

;; Refresh git colors when a repo changes outside a save in Emacs, e.g. a commit
;; from the CLI or Claude Code. Watch each project's .git directory: git updates
;; its index/HEAD via lock-file renames, which kqueue does report. Also refresh
;; when Emacs regains focus, and re-check a file after it is reverted (edited
;; outside Emacs). Debounced; a short cooldown avoids a loop when `git status'
;; itself rewrites the index.
(defvar +my/treemacs--git-watches (make-hash-table :test #'equal))

(defvar +my/treemacs--refresh-timer nil)

(defvar +my/treemacs--last-refresh 0)

(defvar treemacs-silent-refresh)

;; Edits to files from outside Emacs (Claude Code, a terminal...) don't touch
;; .git, and macOS's file notifications don't report changes to a file's
;; contents: treemacs only caught up when Emacs lost and regained focus. So
;; while Emacs has focus and treemacs is shown, check each of its projects'
;; `git status' every few seconds, in the background, and refresh when it
;; changed. (--no-optional-locks: it never writes to .git, so no loop, and no
;; clash with a commit running at the same time.)
(defvar +my/treemacs-git-poll-interval 3
  "Seconds between checks of the shown projects' git status (nil: none).")

(defvar +my/treemacs--git-poll-state (make-hash-table :test #'equal)
  "Each project's last `git status' output.")

(defvar +my/treemacs--git-poll-running (make-hash-table :test #'equal)
  "Projects whose check is still running.")

;; EXPAND / COLLAPSE ALL
;; `treemacs-expand-all' (zR in treemacs) opens every folder of the project(s)
;; in the sidebar; `treemacs-collapse-all' (zM) closes them all again but keeps
;; each project open at its top level, like IntelliJ's Collapse All (treemacs's
;; own `treemacs-collapse-all-projects' folds the projects down to their names).
(defvar +my/treemacs-expand-all-warn 300
  "Ask before `treemacs-expand-all' opens more than this many folders.")

;; ====== KEY BINDINGS ======

;; Arrows mirror h/l (treemacs-evil binds h/l but leaves ←/→ as char motions).
(map! :after treemacs-evil
      :map evil-treemacs-state-map
      [left]  #'treemacs-COLLAPSE-action
      [right] #'treemacs-RET-action)

(map! :after treemacs-evil
      :map evil-treemacs-state-map
      "zR" #'treemacs-expand-all
      "zM" #'treemacs-collapse-all)

;; SINGLE CLICK
;; Open files and expand/collapse folders with one click (treemacs' default is
;; a double click). A double click then counts as one click, so it doesn't open
;; a folder and close it again.
(after! treemacs
  (define-key treemacs-mode-map [mouse-1] #'treemacs-single-click-expand-action)
  (define-key treemacs-mode-map [double-mouse-1] #'ignore))

;; ====== CODE ======

;; No mode line in the sidebar: it only said "Treemacs" and the workspace
;; ("Perspective pas-workspace").
(setq treemacs-user-mode-line-format 'none)

(after! treemacs
  (setq treemacs-is-never-other-window nil) ; reachable with SPC w w (Doom: t)
  (treemacs-follow-mode +1)             ; highlight the current file (Doom: off)
  (treemacs-project-follow-mode +1))    ; show the current buffer's project

;; PROJECT FOLLOW, RIGHT AWAY
;; `treemacs-project-follow-mode' switches to the current buffer's project only
;; after 1.5 s without any input (an idle timer): switch buffers or windows and
;; keep typing or scrolling, and treemacs went on showing the old project. Now it
;; follows a moment after every switch (several switches in a row: one update).
(defvar +my/treemacs--follow-timer nil)

(defun +my/treemacs-follow-project-soon (&rest _)
  (when (timerp +my/treemacs--follow-timer)
    (cancel-timer +my/treemacs--follow-timer))
  (setq +my/treemacs--follow-timer
        (run-at-time
         0.1 nil
         (lambda ()
           (setq +my/treemacs--follow-timer nil)
           (let ((buffer (window-buffer (selected-window))))
             (when (and (bound-and-true-p treemacs-project-follow-mode)
                        (not (minibufferp buffer))) ; e.g. M-x: stay
               ;; Treemacs itself (selected) and the home directory are
               ;; skipped there, like other buffers without a project.
               (with-current-buffer buffer
                 (ignore-errors (treemacs--do-follow-project)))))))))

(add-hook 'window-buffer-change-functions #'+my/treemacs-follow-project-soon)

(add-hook 'window-selection-change-functions #'+my/treemacs-follow-project-soon)

;; An expanded folder gets its git colours a moment later; if the tree is
;; redrawn meanwhile (a project switch, a refresh), that folder's button is gone:
;; "Error running timer `treemacs--apply-annotations-deferred':
;; (wrong-type-argument number-or-marker-p nil)". The redrawn tree gets its own
;; colours, so skip that (the git status is still cached first).
(defadvice! +my/treemacs-stale-annotations-a (fn &rest args)
  :around #'treemacs--apply-annotations-deferred
  (condition-case nil
      (apply fn args)
    (wrong-type-argument nil)))

;; Same race for the follow timer with two frames on different workspaces (e.g.
;; a terminal client next to the GUI): one frame's treemacs switched projects,
;; and the follow looked for a file in a tree not redrawn yet: "Error running
;; timer `treemacs--follow': (wrong-type-argument arrayp nil)". The next
;; follow finds it.
(defadvice! +my/treemacs-follow-guard-a (fn &rest args)
  :around #'treemacs--follow
  (condition-case nil
      (apply fn args)
    (wrong-type-argument nil)))

;; Update the saved file's git status in treemacs. macOS uses kqueue for file
;; notifications, which doesn't report in-place edits, so filewatch misses them.
(defun +my/treemacs-git-update-on-save-h ()
  (when-let* ((file buffer-file-name)
              ((featurep 'treemacs)))
    (dolist (win (window-list))
      (when (with-current-buffer (window-buffer win) (derived-mode-p 'treemacs-mode))
        (with-selected-window win
          (ignore-errors (treemacs-update-single-file-git-state file)))))))

(add-hook 'after-save-hook #'+my/treemacs-git-update-on-save-h)

;; Open treemacs the first time a project file is shown in each workspace
;; (SPC p p, SPC SPC, SPC f r, dashboard, ...). If you close it afterwards
;; (SPC o p) it stays closed for that workspace.
(defun +my/treemacs-auto-open-h (&rest _)
  (when-let* ((buf (window-buffer (selected-window)))
              ((buffer-file-name buf))
              ((with-current-buffer buf (doom-project-root)))
              (persp (and (bound-and-true-p persp-mode) (get-current-persp)))
              ((not (persp-parameter '+my/treemacs-opened persp))))
    (set-persp-parameter '+my/treemacs-opened t persp)
    (require 'treemacs)
    (when (eq (treemacs-current-visibility) 'none)
      (with-current-buffer buf
        (save-selected-window
          (treemacs-add-and-display-current-project-exclusively))))))

(add-hook 'window-buffer-change-functions #'+my/treemacs-auto-open-h)

(defun +my/treemacs-refresh-all ()
  (when (featurep 'treemacs)
    (setq +my/treemacs--last-refresh (float-time))
    ;; Quietly: no "[Treemacs] Refresh complete." on every focus / git change
    ;; (a manual refresh, g in treemacs, still says it).
    (let ((treemacs-silent-refresh t))
      (treemacs-run-in-every-buffer
       (ignore-errors
         (treemacs-without-recenter
          (treemacs--do-refresh (current-buffer) 'all)))))))

(defun +my/treemacs-schedule-refresh (&rest _)
  (when (> (- (float-time) +my/treemacs--last-refresh) 3)
    (when (timerp +my/treemacs--refresh-timer)
      (cancel-timer +my/treemacs--refresh-timer))
    (setq +my/treemacs--refresh-timer
          (run-with-timer 1 nil #'+my/treemacs-refresh-all))))

(defun +my/treemacs-watch-git-h (&rest _)
  (when-let* ((buf (window-buffer (selected-window)))
              ((buffer-file-name buf))
              (root (with-current-buffer buf (doom-project-root)))
              (git (expand-file-name ".git" root))
              ((file-directory-p git))
              ((not (gethash git +my/treemacs--git-watches))))
    (puthash git (file-notify-add-watch git '(change) #'+my/treemacs-schedule-refresh)
             +my/treemacs--git-watches)))

(add-hook 'window-buffer-change-functions #'+my/treemacs-watch-git-h)

(defun +my/treemacs--git-poll-project (root)
  "Compare ROOT's `git status' with the last one; refresh treemacs if it changed."
  (unless (gethash root +my/treemacs--git-poll-running)
    (puthash root t +my/treemacs--git-poll-running)
    (let ((output (generate-new-buffer " *treemacs-git-poll*")))
      (condition-case nil
          (make-process
           :name "treemacs-git-poll" :buffer output :noquery t
           :connection-type 'pipe
           :command (list "git" "--no-optional-locks" "-C" root
                          "status" "--porcelain" "-z")
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (remhash root +my/treemacs--git-poll-running)
               (let ((status (and (zerop (process-exit-status process))
                                  (buffer-live-p output)
                                  (with-current-buffer output (buffer-string))))
                     (old (gethash root +my/treemacs--git-poll-state 'none)))
                 (when (buffer-live-p output) (kill-buffer output))
                 (when status
                   (puthash root status +my/treemacs--git-poll-state)
                   (unless (or (eq old 'none) (equal old status))
                     ;; Not `+my/treemacs-schedule-refresh': its cooldown
                     ;; would drop a change right after another refresh.
                     (when (timerp +my/treemacs--refresh-timer)
                       (cancel-timer +my/treemacs--refresh-timer))
                     (setq +my/treemacs--refresh-timer
                           (run-with-timer 0.3 nil #'+my/treemacs-refresh-all))))))))
        (error (remhash root +my/treemacs--git-poll-running)
               (kill-buffer output))))))

(defun +my/treemacs--git-poll ()
  (when (and (featurep 'treemacs)
             (frame-focus-state)          ; focusing Emacs refreshes anyway
             (eq (treemacs-current-visibility) 'visible))
    (dolist (project (ignore-errors
                       (treemacs-workspace->projects (treemacs-current-workspace))))
      (let ((root (treemacs-project->path project)))
        (when (file-directory-p root)
          (+my/treemacs--git-poll-project root))))))

(defvar +my/treemacs--git-poll-timer nil)

(when (timerp +my/treemacs--git-poll-timer)  ; reloading this file
  (cancel-timer +my/treemacs--git-poll-timer))

(setq +my/treemacs--git-poll-timer
      (and +my/treemacs-git-poll-interval
           (run-with-timer +my/treemacs-git-poll-interval +my/treemacs-git-poll-interval
                           #'+my/treemacs--git-poll)))

(defun +my/treemacs-focus-refresh ()
  (when (frame-focus-state) (+my/treemacs-schedule-refresh)))

(add-function :after after-focus-change-function #'+my/treemacs-focus-refresh)

(add-hook 'after-revert-hook #'+my/treemacs-git-update-on-save-h)

(defun +my/treemacs--count-dirs (dir limit)
  "Count the folders under DIR (not .git), stopping once past LIMIT."
  (let ((count 0) (stack (list dir)))
    (while (and stack (<= count limit))
      (dolist (file (directory-files (pop stack) t directory-files-no-dot-files-regexp t))
        (when (and (file-directory-p file)
                   (not (file-symlink-p file))
                   (not (equal (file-name-nondirectory file) ".git")))
          (cl-incf count)
          (push file stack))))
    count))

(defun +my/treemacs--do-projects (fn)
  "Call FN with each displayed project and its root button, in treemacs."
  (require 'treemacs)
  (let ((buffer (or (treemacs-get-local-buffer)
                    (user-error "Treemacs isn't open"))))
    (with-current-buffer buffer
      (save-excursion
        (dolist (project (treemacs-workspace->projects (treemacs-current-workspace)))
          (when-let* ((pos (treemacs-project->position project)))
            (goto-char pos)
            (funcall fn project pos)))))))

(defun treemacs-expand-all ()
  "Expand every folder of the projects shown in treemacs."
  (interactive)
  (+my/treemacs--do-projects
   (lambda (project pos)
     (let ((dirs (+my/treemacs--count-dirs (treemacs-project->path project)
                                           +my/treemacs-expand-all-warn)))
       (when (or (<= dirs +my/treemacs-expand-all-warn)
                 (y-or-n-p (format "%s has more than %d folders. Expand them all? "
                                   (treemacs-project->name project)
                                   +my/treemacs-expand-all-warn)))
         ;; Close it (forgetting what was open below), then reopen recursively.
         (when (eq (treemacs-button-get pos :state) 'root-node-open)
           (treemacs--collapse-root-node pos t))
         (treemacs--expand-root-node pos t))))))

(defun treemacs-collapse-all ()
  "Collapse every folder of the projects shown in treemacs (projects stay open)."
  (interactive)
  (+my/treemacs--do-projects
   (lambda (_project pos)
     (when (eq (treemacs-button-get pos :state) 'root-node-open)
       (treemacs--collapse-root-node pos t))
     (treemacs--expand-root-node pos))))
