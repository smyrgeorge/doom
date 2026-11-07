;;; $DOOMDIR/config/treemacs.el -*- lexical-binding: t; -*-
;; Treemacs project sidebar. Loaded from config.el.

;; ====== VARIABLES ======

;; TREEMACS (project view)
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
;; each project open at its top level (treemacs's
;; own `treemacs-collapse-all-projects' folds the projects down to their names).
(defvar +my/treemacs-expand-all-warn 300
  "Ask before `treemacs-expand-all' opens more than this many folders.")

;; ====== KEY BINDINGS ======

;; Arrows in trees: ← collapses (or goes to the parent), → expands
;; a closed node, or goes to the first child of an open one; on a file in the
;; project view it opens it, on an error in the error list (SPC c X) it jumps
;; there. ↑/↓ as k/j. (treemacs-evil binds h/l and j/k but leaves the arrows as
;; evil's line motions, which in lsp-treemacs' lists could stop on the hidden
;; first line; → was RET, which there didn't expand anything.)
(map! :after treemacs-evil
      :map evil-treemacs-state-map
      [left]  #'+my/treemacs-left
      [right] #'+my/treemacs-right
      [up]    #'treemacs-previous-line
      [down]  #'treemacs-next-line)

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

(defun +my/treemacs--node ()
  "The node at point: (BUTTON STATE-NAME), BUTTON nil on a hidden one (the
invisible first line holding lsp-treemacs' lists)."
  (let ((button (ignore-errors (treemacs-current-button))))
    (when (and button (>= (or (treemacs-button-get button :depth) 0) 0))
      (list button (symbol-name (treemacs-button-get button :state))))))

(defun +my/treemacs--leaf-p (button)
  "Non-nil if BUTTON is an lsp-treemacs node without children (e.g. an error):
those say closed too."
  (let ((item (treemacs-button-get button :item)))
    (and (consp item) (keywordp (car item))
         (not (plist-get item :children))
         (not (plist-get item :children-async)))))

(defun +my/treemacs-left ()
  "← in treemacs (see the key bindings above)."
  (interactive)
  (pcase-let ((`(,button ,name) (+my/treemacs--node)))
    (cond ((null button))
          ;; treemacs' own nodes (the project view): collapse, or go to the
          ;; parent.
          ((string-match-p "\\`\\(root\\|dir\\|file\\|tag\\)-node" name)
           (treemacs-COLLAPSE-action))
          ;; Others (lsp-treemacs' lists) don't do either: close, or go up (not
          ;; to the hidden first line).
          ((string-suffix-p "-open" name) (treemacs-TAB-action))
          ((when-let* ((parent (treemacs-button-get button :parent)))
             (>= (or (treemacs-button-get parent :depth) 0) 0))
           (treemacs-goto-parent-node)))))

(defun +my/treemacs-right ()
  "→ in treemacs (see the key bindings above)."
  (interactive)
  (pcase-let ((`(,button ,name) (+my/treemacs--node)))
    (cond ((null button) (treemacs-next-line 1))
          ((or (equal name "file-node-closed")         ; open the file
               (+my/treemacs--leaf-p button))           ; go to the error
           (treemacs-RET-action))
          ((string-suffix-p "-closed" name) (treemacs-TAB-action))
          ((and (string-suffix-p "-open" name) (not (equal name "file-node-open")))
           (treemacs-next-line 1))
          (t (treemacs-RET-action)))))

;; LSP PANELS
;; SPC c X (errors) and SPC c S (symbols) open their panel at the bottom; new
;; windows get the cursor (config/window.el) but these are side windows, so it
;; stayed in the code and the arrows moved there. Go to the panel.
(defadvice! +my/lsp-treemacs-select-panel-a (&rest _)
  :after '(lsp-treemacs-errors-list lsp-treemacs-symbols)
  (when-let* ((window (seq-find (lambda (w)
                                  (member (buffer-name (window-buffer w))
                                          '("*LSP Error List*" "*LSP Symbols List*")))
                                (window-list))))
    (select-window window)
    ;; The list opens with the cursor on its hidden first line, shown on the
    ;; first visible one: ↓ then skipped that one. Onto the first visible one.
    (with-current-buffer (window-buffer window)
      (when (and (bobp) (null (+my/treemacs--node)))
        (treemacs-next-line 1)
        (set-window-point window (point))))))

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
;; follows a moment after every switch (several switches in a row: one update),
;; and shows the file there (see SELECTION).
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
             (unless (minibufferp buffer) ; e.g. M-x: stay
               ;; Treemacs itself (selected) and the home directory are
               ;; skipped there, like other buffers without a project.
               (when (bound-and-true-p treemacs-project-follow-mode)
                 (with-current-buffer buffer
                   (ignore-errors (treemacs--do-follow-project))))
               (+my/treemacs--follow-file buffer)))))))

;; SELECTION
;; The sidebar's selected node (its highlighted line, the arrow in the fringe)
;; is the open file, or the node you went to there (keys, a click): not the
;; line point happens to be on. Scrolling the sidebar moves point (Emacs keeps
;; it on screen) but not the selection, so the open file stays selected while
;; scrolled out of view. It's shown again (scrolled to) when the selected
;; window's buffer changes: a file opened, closed or switched to, a project
;; switched to; not when you click back into the same file, nor on Emacs's other
;; changes to its buffer list: treemacs followed on each of those (the git
;; poll's buffers, every few seconds), and scrolled the sidebar back to the file
;; as soon as you stopped scrolling. A key pressed in the sidebar acts on the
;; selection (it's scrolled back into view first).
(defvar-local +my/treemacs--selection nil
  "(PATH . MARKER): the sidebar's selected node, MARKER where it was last
drawn (see above).")

(defun +my/treemacs--sidebar-p ()
  "Non-nil in treemacs's sidebar (not in lsp-treemacs' lists, also treemacs)."
  (and (derived-mode-p 'treemacs-mode)
       (string-prefix-p treemacs-buffer-name-prefix (buffer-name))))

(defun +my/treemacs--path-at (pos)
  "The path of the node on POS's line, if there's one."
  (save-excursion
    (goto-char pos)
    (when-let* ((button (ignore-errors (treemacs-current-button))))
      (treemacs-button-get button :path))))

(defun +my/treemacs--select-here ()
  "Select the node at point (see above)."
  (when-let* ((path (+my/treemacs--path-at (point))))
    (setq +my/treemacs--selection (cons path (copy-marker (line-beginning-position))))))

(defun +my/treemacs--selection-start ()
  "Where the selected node's line starts, if it's drawn (its folders open)."
  (pcase +my/treemacs--selection
    (`(,path . ,marker)
     (if (and (marker-buffer marker) (equal (+my/treemacs--path-at marker) path))
         marker
       ;; Drawn anew since (a refresh, a folder opened above it): found again.
       (when-let* ((match (save-excursion
                            (goto-char (point-min))
                            (text-property-search-forward :path path #'equal))))
         (set-marker marker (save-excursion
                              (goto-char (prop-match-beginning match))
                              (line-beginning-position))))))))

(defun +my/treemacs--highlight-range ()
  "The line the sidebar highlights (`hl-line-range-function'): the
selection's, else point's (see above)."
  (let ((start (or (+my/treemacs--selection-start) (line-beginning-position))))
    (cons start (save-excursion (goto-char start) (line-beginning-position 2)))))

(defun +my/treemacs--scroll-command-p (command)
  "Non-nil if COMMAND only scrolls (the wheel's, C-d...): the selection stays."
  (and (symbolp command) (string-match-p "scroll" (symbol-name command))))

(defvar-local +my/treemacs--point-before nil
  "Point before the command running in the sidebar.")

(defun +my/treemacs--select-h ()
  "After a command in the sidebar: the node it went to is selected, if it went
somewhere (a key that moved, a click), not if it only scrolled (see above).
Not merely after any command: Emacs runs this hook again as its command loop
restarts (after C-g or an error), and selected the line a scroll had left
point on."
  (let ((before +my/treemacs--point-before))
    (setq +my/treemacs--point-before nil)
    (unless (+my/treemacs--scroll-command-p this-command)
      (when (or (mouse-event-p last-input-event)
                (and before (/= before (point))))
        (+my/treemacs--select-here)))))

(defun +my/treemacs--to-selection-h ()
  "Before a key's command in the sidebar: back to the selection if scrolled
away from it, which it acts on (a click acts where it clicks)."
  (unless (or (+my/treemacs--scroll-command-p this-command)
              (mouse-event-p last-input-event))
    (when-let* ((start (+my/treemacs--selection-start))
                ((/= start (line-beginning-position))))
      (goto-char start)
      (ignore-errors (treemacs--evade-image))))
  (setq +my/treemacs--point-before (point)))

(add-hook 'treemacs-mode-hook
          (defun +my/treemacs-selection-h ()
            (when (+my/treemacs--sidebar-p)
              (setq-local hl-line-range-function #'+my/treemacs--highlight-range)
              ;; Before hl-line's own, which then highlights the new one.
              (add-hook 'post-command-hook #'+my/treemacs--select-h -50 t)
              (add-hook 'pre-command-hook #'+my/treemacs--to-selection-h nil t))))

;; The fringe's arrow on the selection too (it's put on point's line).
(defadvice! +my/treemacs-fringe-at-selection-a (fn &rest args)
  :around #'treemacs--move-fringe-indicator-to-point
  (if-let* (((+my/treemacs--sidebar-p))
            (overlay treemacs--fringe-indicator-overlay)
            (start (+my/treemacs--selection-start)))
      (move-overlay overlay start (1+ start))
    (apply fn args)))

;; Treemacs followed the current file a moment after any change to Emacs's
;; buffer list (see above): only on a change of buffer now.
(defadvice! +my/treemacs-follow-not-on-any-buffer-a (&rest _)
  :override #'treemacs--follow-after-buffer-list-update
  nil)

(defun +my/treemacs--follow-file (buffer)
  "Show and select BUFFER's file in the sidebar, if BUFFER is new to the
selected window since the last time (see above)."
  (unless (eq buffer (frame-parameter nil '+my/treemacs-followed))
    (when (with-current-buffer buffer
            (or buffer-file-name (derived-mode-p 'dired-mode)))
      (set-frame-parameter nil '+my/treemacs-followed buffer)
      (when (bound-and-true-p treemacs-follow-mode)
        (with-current-buffer buffer
          (treemacs--follow))))))

;; Followed: the file is the selection (point is on it).
(defadvice! +my/treemacs-select-followed-a (&rest _)
  :after #'treemacs--follow
  (when-let* ((file (or buffer-file-name
                        (and (derived-mode-p 'dired-mode) (dired-current-directory))))
              ((featurep 'treemacs))
              (window (treemacs-get-local-window)))
    (with-selected-window window
      (when-let* ((path (+my/treemacs--path-at (point)))
                  ((stringp path))
                  ((ignore-errors (file-equal-p path file))))
        (+my/treemacs--select-here)
        (hl-line-highlight)))))

(add-hook 'window-buffer-change-functions #'+my/treemacs-follow-project-soon)

(add-hook 'window-selection-change-functions #'+my/treemacs-follow-project-soon)

;; FOLLOW PROJECT BUFFERS ONLY
;; The follow (above, and treemacs's own idle one) switched the sidebar to the
;; directory of any buffer selected: popups and logs too, e.g. `doom/reload''s,
;; in Doom's ~/.config/emacs. Back and forth in a moment, and switching back
;; once left the old project's root drawn on the new one's line ("doom emacs").
;; Now only buffers that belong to a project: files, dired, magit.
(defadvice! +my/treemacs-follow-project-buffers-a (fn &rest args)
  :around #'treemacs--do-follow-project
  (when (or buffer-file-name (derived-mode-p 'dired-mode 'magit-mode))
    (apply fn args)))

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
    (let ((output (generate-new-buffer " *treemacs-git-poll*"))
          ;; Started from the project: the current buffer's folder may be gone
          ;; (deleted outside Emacs), and git couldn't start there.
          (default-directory root))
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
