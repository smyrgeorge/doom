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
(defun +my/git-diff-pane--window ()
  "Return the window in this frame showing a single-file magit diff."
  (seq-find (lambda (win)
              (with-current-buffer (window-buffer win)
                (and (derived-mode-p 'magit-diff-mode) magit-buffer-diff-files)))
            (window-list)))

(defun +my/git-diff-pane--file ()
  "The current file, relative to its repository, or nil."
  (and buffer-file-name
       (require 'magit nil t)
       (magit-toplevel)
       (magit-file-relative-name)))

(defun +my/git-diff-pane--switch (window buffer)
  "Show BUFFER, another file's diff, in WINDOW, the pane, in place of the one
it shows (see above): that one taken off its buffers (its tabs) and killed
unless shown elsewhere; quitting WINDOW closes it as before. Return WINDOW."
  (let ((old (window-buffer window)))
    (set-window-buffer window buffer)
    (unless (eq old buffer)
      (let ((quit (window-parameter window 'quit-restore)))
        (when (eq (nth 3 quit) old)
          (set-window-parameter window 'quit-restore
                                (append (seq-take quit 3) (list buffer) (nthcdr 4 quit)))))
      (set-window-prev-buffers window (seq-remove (lambda (entry) (eq (car entry) old))
                                                  (window-prev-buffers window)))
      (set-window-next-buffers window (remq old (window-next-buffers window)))
      (set-window-parameter window 'tab-line-buffers
                            (remq old (window-parameter window 'tab-line-buffers)))
      (unless (get-buffer-window old t)
        (kill-buffer old)))
    window))

(defun +my/git-diff-pane ()
  "Show the current file's git diff in a pane on the right and focus it.
In the pane itself, close it."
  (interactive)
  (if (eq (selected-window) (+my/git-diff-pane--window))
      (if (one-window-p) (quit-window) (delete-window))
    (let* ((file (or (+my/git-diff-pane--file)
                     (user-error "Not a file in a git repository")))
           (line (line-number-at-pos))
           (column (current-column))
           (win (+my/git-diff-pane--window))
           (magit-display-buffer-function
            (lambda (buffer)
              (if (window-live-p win)
                  (+my/git-diff-pane--switch win buffer)
                (display-buffer buffer '((display-buffer-in-direction)
                                         (direction . right)))))))
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
  (if (eq (selected-window) (+my/git-diff-pane--window))
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
