;;; $DOOMDIR/config/tiling/apps.el -*- lexical-binding: t; -*-
;; Tiling first: applications in new panes, files as tabs in the pane they're
;; opened from, a pane closed with its last tab (see TILING FIRST in
;; config/tiling.el). Loaded from config/tiling.el.

;; WHAT A BUFFER IS
(defun +my/tiling--in-magit-p (buffer)
  "Non-nil if BUFFER is magit's, or a commit message (git's, edited for it)."
  (with-current-buffer buffer
    (or (derived-mode-p 'magit-mode)
        (bound-and-true-p git-commit-mode)
        (bound-and-true-p with-editor-mode))))

(defun +my/tiling-magit-new-pane-p ()
  "In a magit buffer being shown: non-nil if it opens in a new pane (see
config/tiling.el): its status, any shown from outside magit, a commit or a
stash; not its process log."
  (and (not (derived-mode-p 'magit-process-mode))
       (or (derived-mode-p 'magit-status-mode 'magit-revision-mode 'magit-stash-mode)
           (not (+my/tiling--in-magit-p (window-buffer (selected-window)))))))

(defun +my/tiling-beads-issue-new-pane-p ()
  "In a Beads issue's buffer being shown (config/beads.el): non-nil if it opens
in a new pane: not the list's preview (P), beads.el's side window. (A second
issue goes to the first one's pane: config/beads/project.el.)"
  (not (equal (buffer-name) "*Beads Preview*")))

(defun +my/tiling--apps ()
  "The applications chosen (`+my/tiling-apps'): their modes, as
`+my/tiling-known-apps' has them (MODE, or (MODE . PREDICATE))."
  (mapcan (lambda (app)
            (when (or (eq +my/tiling-apps 'all) (memq (car app) (ensure-list +my/tiling-apps)))
              (copy-sequence (cdr app))))
          +my/tiling-known-apps))

(defun +my/tiling--check-apps ()
  "Warn of names in `+my/tiling-apps' tiling doesn't know (config.el's), the
ones it does said."
  (unless (eq +my/tiling-apps 'all)
    (when-let* ((unknown (seq-remove (lambda (name) (assq name +my/tiling-known-apps))
                                     (ensure-list +my/tiling-apps))))
      (display-warning
       'tiling
       (format "+my/tiling-apps: no application %s; it's all, or a list of: %s"
               (mapconcat (lambda (name) (format "%s" name)) unknown ", ")
               (mapconcat (lambda (app) (symbol-name (car app))) +my/tiling-known-apps ", "))))))

(+my/tiling--check-apps)

(defun +my/tiling--app (buffer)
  "BUFFER's entry among the applications chosen (`+my/tiling--apps'), if
it's one's."
  (with-current-buffer buffer
    (seq-find (lambda (app) (derived-mode-p (if (consp app) (car app) app)))
              (+my/tiling--apps))))

(defun +my/tiling-app-p (buffer)
  "Non-nil if BUFFER is an application's (see `+my/tiling-apps')."
  (and (+my/tiling--app buffer) t))

(defun +my/tiling--new-pane-p (buffer)
  "Non-nil if application BUFFER, being shown, opens in a new pane (see
`+my/tiling-known-apps')."
  (when-let* ((app (+my/tiling--app buffer)))
    (or (not (consp app))
        (with-current-buffer buffer (funcall (cdr app))))))

(defun +my/tiling--file-p (buffer)
  "Non-nil if BUFFER is a file's (or a folder's, dired); not git's own (in
.git/, a commit message, edited for git: where git opens them)."
  (with-current-buffer buffer
    (if-let* ((file buffer-file-name))
        (not (or (string-match-p "/\\.git/" file)
                 (bound-and-true-p git-commit-mode)
                 (bound-and-true-p with-editor-mode)))
      (derived-mode-p 'dired-mode))))

;; PANES
(defun +my/tiling--last-pane ()
  "The pane used last (where a file shown from a popup or a side panel
opens); nil without one."
  (car (sort (copy-sequence (+my/tiling--panes))
             (lambda (a b) (> (window-use-time a) (window-use-time b))))))

(defun +my/tiling--tab-pane (buffer)
  "A pane BUFFER is a tab of, not shown (a file over it): the current pane
first; nil if none."
  (seq-find (lambda (pane) (assq buffer (window-prev-buffers pane)))
            (let ((panes (+my/tiling--panes)))
              (if (memq (selected-window) panes)
                  (cons (selected-window) (delq (selected-window) panes))
                panes))))

(defun +my/tiling--show-file (buffer pane alist)
  "BUFFER in PANE, as a tab there (ALIST, a `display-buffer' one, without its
size). PANE taking tabs like any: Doom's terminal's was dedicated to it."
  (set-window-dedicated-p pane nil)
  (window--display-buffer buffer pane 'reuse (+my/tiling--alist alist)))

(defun +my/tiling--alist (alist)
  "ALIST, a `display-buffer' one, without where and how big its window should
be (other rules', e.g. Doom's popups': the strategy decides)."
  (seq-remove (lambda (entry)
                (memq (car-safe entry) '(window-width window-height window-size preserve-size
                                         window-parameters dedicated side slot direction)))
              alist))

(defun +my/tiling--new-pane ()
  "A new pane where the strategy puts it, with no tabs yet; nil in a frame
without panes."
  (when-let* ((panes (+my/tiling--panes)))
    (let ((new (funcall (plist-get (+my/tiling--strategy) :split) panes)))
      (set-window-prev-buffers new nil)
      (set-window-next-buffers new nil)
      (set-window-parameter new 'tab-line-buffers nil)
      new)))

(defun +my/tiling-display-buffer (buffer alist)
  "A `display-buffer' action: BUFFER in a new pane where the tiling strategy
puts it (config/tiling.el), its only tab; quitting it closes the pane. Nil
(the next action then) in a frame without panes."
  (when-let* ((new (+my/tiling--new-pane)))
    (window--display-buffer buffer new 'window (+my/tiling--alist alist))))

;; APPLICATIONS AND FILES SHOWN (`display-buffer', see config/tiling.el)
(defun +my/tiling--in-workspace (buffer)
  "BUFFER, an application shown in a pane, in the current workspace (Doom's,
persp-mode). Doom's frames only go back to its buffers (`buffer-predicate'):
Claude Code's session (SPC o c, `display-buffer') wasn't in it, so closing a
file's tab in its pane showed another file. Nothing without workspaces."
  (when (and (bound-and-true-p persp-mode)
             (fboundp 'persp-add-buffer)
             (fboundp 'get-current-persp))
    (ignore-errors (persp-add-buffer buffer (get-current-persp) nil))))

(defun +my/tiling--display (buffer alist)
  "`display-buffer-overriding-action': an application in its pane (shown, or
one of its tabs), else a new one (as the strategy puts it); a file in the current pane, as a tab, from a
popup or a side panel in the pane used last (a new pane without one). Nil
for anything else (popups, *Completions*, transient menus, git's own
files...), for a buffer shown in no window (ALIST's `allow-no-window'),
while the minibuffer is open (previews put back what they showed), and from
a command of `+my/tiling-here-commands' (Doom's SPC o T: the window you're
in): as it asks."
  (cond
   ((active-minibuffer-window) nil)
   ((alist-get 'allow-no-window alist) nil)
   ((memq this-command +my/tiling-here-commands) nil)
   ((+my/tiling-app-p buffer)
    (let ((window (cond ((get-buffer-window buffer)
                         (window--display-buffer buffer (get-buffer-window buffer) 'reuse
                                                 (+my/tiling--alist alist)))
                        ((+my/tiling--tab-pane buffer)
                         (window--display-buffer buffer (+my/tiling--tab-pane buffer) 'reuse
                                                 (+my/tiling--alist alist)))
                        ((+my/tiling--new-pane-p buffer)
                         (+my/tiling-display-buffer buffer alist)))))
      (when window
        (+my/tiling--in-workspace buffer))
      window))
   ((+my/tiling--file-p buffer)
    (let ((here (selected-window)))
      (if-let* ((pane (if (memq here (+my/tiling--panes)) here (+my/tiling--last-pane))))
          (+my/tiling--show-file buffer pane alist)
        (+my/tiling-display-buffer buffer alist))))))

(setq display-buffer-overriding-action '((+my/tiling--display)))

;; APPLICATIONS ARE DOOM'S "REAL" BUFFERS
;; As Doom has magit and the terminal: a file opened in an application's pane
;; is a tab there, the application one too, shown again when the file's tab
;; closes. Doom's frames only go back to real buffers (`buffer-predicate':
;; `doom-buffer-frame-predicate'), and tabs (config/editor/tabs.el) keep only
;; those besides files: Beads' issues and the Markdown preview weren't, so
;; their tab went once a file covered them, and closing the file's showed
;; another buffer (a file of another pane) in their place. SPC b b lists them.
(add-hook 'doom-real-buffer-functions #'+my/tiling-app-p)

;; A PANE CLOSED WITH ITS LAST TAB (see config/tiling.el)
(defun +my/tiling--last-tab-p (window buffer)
  "Non-nil if BUFFER is WINDOW's only tab (config/editor/tabs.el), or without
tabs the only live buffer it showed."
  (with-selected-window window
    (if (and (fboundp '+my/tabs-window-buffers) (bound-and-true-p tab-line-mode))
        (equal (+my/tabs-window-buffers) (list buffer))
      (not (seq-some (lambda (entry) (and (buffer-live-p (car entry)) (not (eq (car entry) buffer))))
                     (window-prev-buffers window))))))

(defun +my/tiling-close-pane-h ()
  "The buffer killed: the panes it was the last tab of close, but a frame's
last pane."
  (let ((buffer (current-buffer)))
    (dolist (window (get-buffer-window-list buffer 'nomini t))
      (when (and (window-live-p window)
                 (not (window-parameter window 'window-side))
                 (eq (window-deletable-p window) t)
                 (+my/tiling--last-tab-p window buffer))
        (delete-window window)))))

(add-hook 'kill-buffer-hook #'+my/tiling-close-pane-h)

;; SPC b k (`kill-current-buffer') on a pane's last tab: Doom's first shows
;; another buffer there (the previous one, else any), then kills it: the
;; pane, no longer showing it, stayed. Killed at once instead: its pane closes
;; (above). Elsewhere (other tabs, the frame's last pane), Doom's.
(defun +my/tiling-kill-last-tab-a (&rest _)
  "`kill-current-buffer' on its pane's last tab: killed, the pane closed (see
above). Non-nil if so (Doom's and Emacs's then skipped)."
  (let ((buffer (current-buffer))
        (window (selected-window)))
    (when (and (eq (window-buffer window) buffer)
               (memq window (+my/tiling--panes))
               (not (window-parameter window 'window-side))
               (eq (window-deletable-p window) t)
               (not (and (fboundp 'doom-fallback-buffer) (eq buffer (doom-fallback-buffer))))
               (+my/tiling--last-tab-p window buffer))
      ;; A modified file's asked about first (`kill-buffer'): no, nothing.
      (kill-buffer buffer)
      t)))

(advice-add 'kill-current-buffer :before-until #'+my/tiling-kill-last-tab-a '((depth . -90)))
