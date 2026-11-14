;;; $DOOMDIR/config/git/diff-pane.el -*- lexical-binding: t; -*-
;; SPC g d: the current file's diff in a pane. Loaded from config/git.el.

;; GIT DIFF PANE
;; SPC g d: show the current file's changes (working tree vs HEAD) in a pane on
;; the right, rendered with delta like every magit diff, and move the cursor
;; there, onto the hunk of the line you were on. From another file it switches
;; the pane to that file; in the pane, SPC g d, q or Esc closes it. The pane
;; refreshes when the file is saved. In the pane: s / u / x stage, unstage or
;; discard a hunk, RET jumps to the line.
;; Opening it saves the buffer first (magit diffs the file on disk). The pane
;; takes half of the window it's opened from (the split does; a window-width
;; would be a share of the whole frame, taken from the windows beside it).
;; With tiling (config/tiling), the strategy places it.
;; Another file's diff takes the place of the one shown: the pane keeps one
;; diff, its only tab (magit makes a buffer per file), so q closes it.
;; The pane is found by that diff, marked as SPC g d's (a commit limited to a
;; file, from its log, is a diff of that file too, not the pane): the pane
;; showing it, or having it as a tab (a file opened over it, RET), or hidden
;; (tiling's fullscreen: brought to the front).
;; Closing it (SPC g d, Esc) closes the diff's tab (config/editor/tabs.el): the
;; pane keeps its other tabs, and closes with its last. Without tabs, the pane
;; closes; the frame's only window beside side panels (a sidebar), it shows
;; what it showed before. The diff is killed.
(defvar-local +my/git-diff-pane--diff nil
  "Non-nil in the diff buffer SPC g d shows (see above).")
(put '+my/git-diff-pane--diff 'permanent-local t)

(defun +my/git-diff-pane--buffer ()
  "The diff buffer SPC g d shows, or nil."
  (seq-find (lambda (buffer) (buffer-local-value '+my/git-diff-pane--diff buffer))
            (buffer-list)))

(defun +my/git-diff-pane--window ()
  "The window of this frame showing SPC g d's diff, or nil."
  (when-let* ((buffer (+my/git-diff-pane--buffer)))
    (get-buffer-window buffer)))

(defun +my/git-diff-pane--holder (buffer)
  "The window of this frame showing BUFFER, else one having it as a tab (a
file shown over it); nil if none."
  (or (get-buffer-window buffer)
      (seq-find (lambda (window) (assq buffer (window-prev-buffers window)))
                (window-list))))

(defun +my/git-diff-pane--file ()
  "The current file, relative to its repository, or nil."
  (and buffer-file-name
       (require 'magit nil t)
       (magit-toplevel)
       (magit-file-relative-name)))

(defun +my/git-diff-pane--switch (window buffer old)
  "Show BUFFER, another file's diff, in WINDOW, the pane, in place of OLD, the
diff it shows or has as a tab (see above): OLD taken off its buffers (its
tabs) and killed, unless shown elsewhere (then no longer the pane's);
quitting WINDOW closes it as before. Return WINDOW."
  (set-window-buffer window buffer)
  (let ((quit (window-parameter window 'quit-restore)))
    (when (eq (nth 3 quit) old)
      (set-window-parameter window 'quit-restore
                            (append (seq-take quit 3) (list buffer) (nthcdr 4 quit)))))
  (set-window-prev-buffers window (seq-remove (lambda (entry) (eq (car entry) old))
                                              (window-prev-buffers window)))
  (set-window-next-buffers window (remq old (window-next-buffers window)))
  (set-window-parameter window 'tab-line-buffers
                        (remq old (window-parameter window 'tab-line-buffers)))
  (if (get-buffer-window old t)
      (with-current-buffer old (setq +my/git-diff-pane--diff nil))
    (kill-buffer old))
  window)

(defun +my/git-diff-pane--display (buffer)
  "Show BUFFER, the diff SPC g d asked magit for, in the pane (see above): the
one holding its diff, else a new one, on the right. Its window."
  (let* ((old (or (+my/git-diff-pane--buffer) buffer))
         (window (or (+my/git-diff-pane--holder old)
                     ;; Hidden (brought to the front by tiling), or a new pane.
                     (display-buffer old '((display-buffer-in-direction)
                                           (direction . right))))))
    (with-current-buffer buffer
      (setq +my/git-diff-pane--diff t))
    (if (eq old buffer)
        (progn (set-window-buffer window buffer) window)
      (+my/git-diff-pane--switch window buffer old))))

(defun +my/git-diff-pane--close ()
  "Close the diff pane, the selected window (see above)."
  (let ((buffer (window-buffer)))
    (cond ((and (bound-and-true-p tab-line-mode) (fboundp '+my/tabs-close-current))
           (+my/tabs-close-current))
          ((eq (window-deletable-p) t)
           (delete-window))
          (t
           (quit-window)))
    (when (and (buffer-live-p buffer) (not (get-buffer-window buffer t)))
      (kill-buffer buffer))))

(defun +my/git-diff-pane ()
  "Show the current file's git diff in a pane on the right and focus it.
In the pane itself, close it."
  (interactive)
  (if (buffer-local-value '+my/git-diff-pane--diff (window-buffer))
      (+my/git-diff-pane--close)
    (let* ((file (or (+my/git-diff-pane--file)
                     (user-error "Not a file in a git repository")))
           (line (line-number-at-pos))
           (column (current-column))
           (magit-display-buffer-function #'+my/git-diff-pane--display))
      (magit-diff-buffer-file)          ; selects the pane
      ;; Put the cursor on the hunk of the line we came from. magit tries this
      ;; itself but gives up when the diff starts with a --stat summary.
      (when-let* ((pane (+my/git-diff-pane--window)))
        (with-current-buffer (window-buffer pane)
          (ignore-errors
            (magit-diff--goto-file-position file line column magit-root-section))
          (set-window-point pane (point)))))))

(defun +my/git-diff-pane-escape ()
  "Esc in the diff pane: close it. In other magit diffs, Esc as usual."
  (interactive)
  (if (buffer-local-value '+my/git-diff-pane--diff (window-buffer))
      (+my/git-diff-pane)
    (call-interactively #'doom/escape)))

(defun +my/git-diff-pane-refresh-h ()
  "Refresh the diff pane after saving the file it shows."
  (when-let* ((win (+my/git-diff-pane--window))
              (file (+my/git-diff-pane--file)))
    (with-current-buffer (window-buffer win)
      (when (equal magit-buffer-diff-files (list file))
        (magit-refresh)))))

(add-hook 'after-save-hook #'+my/git-diff-pane-refresh-h)
