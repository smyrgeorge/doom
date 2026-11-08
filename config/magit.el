;;; $DOOMDIR/config/magit.el -*- lexical-binding: t; -*-
;; Magit add-ons. Loaded from config.el.

;; ====== VARIABLES ======

;; COMMIT GRAPH
;; Commits are shown as a tree, like tig: in the log (l l) and in the status
;; buffer's commit sections (SPC g g: open, 20 commits), each branch's lane in
;; its own colour, drawn with box-drawing lines instead of ASCII (`*' `|' `/'
;; `\'). The log has the date and author in the margin; the status buffer
;; doesn't: a margin takes its width from the whole window, and its diffs and
;; headers were cut where it starts (L L there shows it, for that buffer).
(defvar +my/magit-graph-glyphs
  '((?* . "●") (?| . "│") (?/ . "╱") (?\\ . "╲") (?- . "─"))
  "How the characters of git's graph are drawn.")

(after! magit-log
  (put 'magit-log-mode 'magit-log-default-arguments
       '("--graph" "--color" "-n256" "--decorate"))
  (setq magit-log-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width t 18)))

(after! magit-status
  ;; The status buffer's commit sections (recent, unpushed, unpulled): open
  ;; (magit folds "Recent commits"), with more of them.
  (put 'magit-status-mode 'magit-log-default-arguments
       '("--graph" "--color" "-n256" "--decorate"))
  ;; No margin (see above); its look, when L L shows it, the log's.
  (setq magit-status-margin '(nil "%Y-%m-%d %H:%M " magit-log-margin-width t 18)
        magit-log-section-commit-count 20)
  (add-to-list 'magit-section-initial-visibility-alist '(recent . show))
  (add-to-list 'magit-section-initial-visibility-alist '(unpushed . show)))

;; ====== CODE ======

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
