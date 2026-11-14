;;; $DOOMDIR/config/git/magit.el -*- lexical-binding: t; -*-
;; Magit's additions: git-delta diffs, TODOs in the status buffer, the commit
;; graph drawn with lines. Loaded from config/git.el.

;; MAGIT
;; Render diffs with git-delta (brew install git-delta), without the delta
;; settings of ~/.gitconfig (--no-gitconfig): they're for the terminal (line
;; numbers, side by side), and delta applies line numbers even in
;; magit-delta's --color-only mode, writing them into the diff's text
;; ("  1 ⋮  1 │ a"), which staging or discarding a hunk (s, x) sends to git:
;; "corrupt patch". Only where delta is installed (brew install git-delta;
;; Linux: the git-delta package): without it magit-delta left every diff
;; empty.
(use-package! magit-delta
  :defer t
  :config
  (add-to-list 'magit-delta-delta-args "--no-gitconfig" t))

(defun +my/magit-delta-maybe-h ()
  "Diffs through delta, if it's installed (see above)."
  (when (executable-find "delta")
    (magit-delta-mode 1)))

(add-hook 'magit-mode-hook #'+my/magit-delta-maybe-h)

;; List TODO/FIXME/... comments of the repo in the magit status buffer (uses rg).
;; rg runs on a pty there, so it coloured its output whenever TERM allowed it
;; (terminal Emacs, or one started from a shell) and magit-todos found none in
;; it: never in colour.
(use-package! magit-todos
  :after magit
  :config
  (setq magit-todos-rg-extra-args '("--color=never"))
  (magit-todos-mode +1))

;; With --color, magit marks the graph's characters with the lane colours (or
;; `magit-log-graph'): only those are redrawn, never the commit messages.
(defun +my/magit--graph-face-p (face)
  (or (and (consp face) (keywordp (car face))) ; a lane's colour, (:foreground ..)
      (cl-some (lambda (f)
                 (or (eq f 'magit-log-graph)
                     (and (symbolp f) (string-prefix-p "ansi-color-" (symbol-name f)))
                     (and (consp f) (keywordp (car f)))))
               (ensure-list face))))

(defun +my/magit-pretty-graph-h ()
  "Draw the commit graph with box-drawing characters."
  (when (derived-mode-p 'magit-log-mode 'magit-status-mode)
    (with-silent-modifications
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward "[*|/\\\\-]" nil t)
          (let ((pos (match-beginning 0)))
            (when (+my/magit--graph-face-p (get-text-property pos 'font-lock-face))
              (put-text-property pos (1+ pos) 'display
                                 (alist-get (char-after pos) +my/magit-graph-glyphs)))))))))

(add-hook 'magit-refresh-buffer-hook #'+my/magit-pretty-graph-h)

;; The margin in a narrow pane (see config/git.el): magit sets a window's
;; margins when it shows the buffer and again whenever the window's size
;; changes (`window-configuration-change-hook'); after it, the right margin is
;; taken off if it leaves too few columns of text.
(defun +my/magit-margin-fit-a (&optional window)
  "After `magit-set-window-margins': WINDOW's right margin hidden if it leaves
fewer than `+my/magit-margin-min-text' columns of text."
  (when-let* ((window (or window (get-buffer-window)))
              ((window-live-p window))
              ((cdr (window-margins window)))
              ((< (window-body-width window) +my/magit-margin-min-text)))
    (set-window-margins window (car (window-margins window)) nil)))

(advice-add 'magit-set-window-margins :after #'+my/magit-margin-fit-a)
