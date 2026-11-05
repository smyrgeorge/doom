;;; $DOOMDIR/config/git.el -*- lexical-binding: t; -*-
;; Git diff of the current file in a side pane. Loaded from config.el.

;; ====== KEY BINDINGS ======

(map! :leader :desc "Diff file (side pane)" "g d" #'+my/git-diff-pane)

;; Esc closes the pane too (like q).
(map! :after magit-diff
      :map magit-diff-mode-map
      :n [escape] #'+my/git-diff-pane-escape)

;; ====== CODE ======

;; GIT DIFF PANE
;; SPC g d: show the current file's changes (working tree vs HEAD) in a pane on
;; the right, rendered with delta like every magit diff, and move the cursor
;; there, onto the hunk of the line you were on. From another file it switches
;; the pane to that file; in the pane, SPC g d, q or Esc closes it. The pane
;; refreshes when the file is saved. In the pane: s / u / x stage, unstage or
;; discard a hunk, RET jumps to the line.
;; Opening it saves the buffer first (magit diffs the file on disk).
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
                  (progn (set-window-buffer win buffer) win)
                (display-buffer buffer '((display-buffer-in-direction)
                                         (direction . right)
                                         (window-width . 0.5)))))))
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
