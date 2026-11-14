;;; $DOOMDIR/config/stripe/marks.el -*- lexical-binding: t; -*-
;; What the stripe marks: diagnostics, TODO comments, git changes. Loaded from
;; config/stripe.el.

(defvar-local +my/stripe--cache nil "(KEY LINES . MARKS) for `+my/stripe--marks'.")

(defvar-local +my/stripe--diff-hl-tick 0 "Bumped whenever diff-hl redraws.")

(defface +my/stripe-todo '((t :inherit font-lock-keyword-face))
  "TODO comments in the stripe: its foreground is their colour.")

(defface +my/stripe-suggestion '((t :inherit shadow))
  "Suggestions (flycheck's `info': LSP hints, information) in the stripe: its
foreground is their colour.")

(defconst +my/stripe--kinds
  ;; KIND    PRIORITY FACE (its foreground is the colour)
  '((error   7 flycheck-fringe-error)
    (warning 6 flycheck-fringe-warning)
    (todo    5 +my/stripe-todo)
    (delete  4 diff-hl-delete)
    (change  3 diff-hl-change)
    (insert  2 diff-hl-insert)
    (info    1 +my/stripe-suggestion)))

(defun +my/stripe-faces-h ()
  "The marks' own colours from the theme, as IntelliJ's: TODO comments blue,
suggestions a dim warning colour (flycheck's info green is the git gutter's
added lines')."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (face-background 'default nil t))
          (blue (doom-color 'blue))
          (warning (face-foreground 'warning nil t))
          (hex (lambda (colour) (and (stringp colour) (string-prefix-p "#" colour)))))
      (when (funcall hex blue)
        (set-face-attribute '+my/stripe-todo nil :foreground blue))
      (when (and (funcall hex bg) (funcall hex warning))
        (set-face-attribute '+my/stripe-suggestion nil
                            :foreground (doom-blend warning bg 0.5))))))

(+my/stripe-faces-h)

;; Before the strips are redrawn for the new theme (`+my/stripe--render-all').
(add-hook 'doom-load-theme-hook #'+my/stripe-faces-h -50)

(defvar-local +my/stripe--line-edits 0
  "Bumped by edits that add or remove line breaks, or touch a line with a TODO
keyword: they move the marks and the band, or add or remove a TODO mark (other
edits within a line don't: the strip isn't redrawn for those).")

(defvar +my/stripe--todo-regexp nil "(KEYWORDS . REGEXP) for `+my/stripe--todo-regexp'.")

(defun +my/stripe--todo-regexp ()
  "A regexp matching `+my/stripe-todo-keywords' as words (group 1): not next to
a letter, a digit or an underscore. nil for none."
  (when +my/stripe-todo-keywords
    (unless (eq (car +my/stripe--todo-regexp) +my/stripe-todo-keywords)
      (setq +my/stripe--todo-regexp
            (cons +my/stripe-todo-keywords
                  (concat "\\(?:^\\|[^[:alnum:]_]\\)"
                          (regexp-opt +my/stripe-todo-keywords t)
                          "\\(?:[^[:alnum:]_]\\|$\\)"))))
    (cdr +my/stripe--todo-regexp)))

(defun +my/stripe--todo-match-p ()
  "Whether the TODO keyword just matched marks its line: in code (and conf
files) only in a comment, in text anywhere."
  (or (not (derived-mode-p 'prog-mode 'conf-mode))
      ;; `syntax-ppss' moves point.
      (save-excursion (save-match-data (nth 4 (syntax-ppss (match-beginning 1)))))))

(defun +my/stripe--todo-lines ()
  "The lines with a TODO keyword (see `+my/stripe-todo-keywords'), first to last."
  (when-let* ((regexp (+my/stripe--todo-regexp)))
    (save-excursion
      (goto-char (point-min))
      (let ((case-fold-search nil)
            (line 1)
            (pos (point-min))
            lines)
        (while (re-search-forward regexp nil t)
          (if (not (+my/stripe--todo-match-p))
              ;; Searched on from the keyword's end: the character after it,
              ;; part of the match, may start the next one.
              (goto-char (match-end 1))
            ;; The keyword's line (the match may end on the next one, with the
            ;; line break after the keyword).
            (goto-char (match-beginning 1))
            (setq line (+ line (count-lines pos (line-beginning-position)))
                  pos (line-beginning-position))
            (push line lines)
            ;; One mark a line.
            (forward-line 1)))
        (nreverse lines)))))

(defun +my/stripe--level (err)
  "The stripe kind of flycheck error ERR: `error', `warning' or `info'."
  (let ((severity (flycheck-error-level-severity (flycheck-error-level err))))
    (cond ((>= severity 100) 'error)
          ((>= severity 10) 'warning)
          (t 'info))))

(defun +my/stripe--marks ()
  "Return (LINES . MARKS): the buffer's line count and its marks.
Each mark is (FIRST-LINE LAST-LINE KIND). Cached until the text, the flycheck
errors or the diff-hl highlights change."
  (let ((key (list (buffer-chars-modified-tick)
                   (bound-and-true-p flycheck-current-errors)
                   +my/stripe--diff-hl-tick))
        (old (car +my/stripe--cache)))
    (unless (and old
                 (eql (nth 0 key) (nth 0 old))
                 (eq (nth 1 key) (nth 1 old))
                 (eql (nth 2 key) (nth 2 old)))
      (save-restriction
        (widen)
        (let (marks)
          (when (bound-and-true-p flycheck-mode)
            (dolist (err flycheck-current-errors)
              (let ((line (flycheck-error-line err))
                    (kind (+my/stripe--level err)))
                (when (and line (memq kind +my/stripe-diagnostic-levels))
                  ;; Line 0 (Emacs Lisp's "End of file during parsing"):
                  ;; flycheck shows it on the first.
                  (setq line (max 1 line))
                  (push (list line line kind) marks)))))
          (dolist (line (+my/stripe--todo-lines))
            (push (list line line 'todo) marks))
          (dolist (ov (overlays-in (point-min) (point-max)))
            (when (overlay-get ov 'diff-hl-hunk)
              (let ((beg (line-number-at-pos (overlay-start ov))))
                (push (list beg
                            (max beg (line-number-at-pos
                                      (max (overlay-start ov) (1- (overlay-end ov)))))
                            (overlay-get ov 'diff-hl-hunk-type))
                      marks))))
          (setq +my/stripe--cache
                (cons key (cons (line-number-at-pos (point-max)) marks))))))
    (cdr +my/stripe--cache)))

(defun +my/stripe--line-to-row (line lines rows)
  "The stripe row (0-based) of LINE in a file of LINES lines, ROWS rows high."
  (if (<= lines rows)
      (1- line)
    (min (1- rows) (/ (* (1- line) rows) lines))))

(defun +my/stripe--row-to-line (row lines rows)
  "The line a click on stripe ROW jumps to (the middle of its range)."
  (if (<= lines rows)
      (min lines (1+ row))
    ;; The lines ROW shows (see `+my/stripe--line-to-row'): the middle of the
    ;; row's span can fall on a line of the row above when few lines share it.
    (let ((first (1+ (ceiling (* row lines) rows)))
          (last (ceiling (* (1+ row) lines) rows)))
      (min lines (/ (+ first last 1) 2)))))

(defun +my/stripe--thumb-color ()
  "A colour slightly lighter (or darker) than the background."
  (let ((fg (face-foreground 'default nil t))
        (bg (face-background 'default nil t)))
    (or (and (fboundp 'doom-blend)
             (stringp fg) (string-prefix-p "#" fg)
             (stringp bg) (string-prefix-p "#" bg)
             (doom-blend fg bg 0.12))
        (and (facep 'hl-line) (face-background 'hl-line nil t))
        "gray30")))

(defun +my/stripe--kind-color (kind)
  (let ((face (cadr (alist-get kind +my/stripe--kinds))))
    (and (facep face) (face-foreground face nil t))))

(defun +my/stripe--key (window &optional start)
  "What WINDOW's stripe depends on, each part compared with `eq'. Edits
within a line don't change it. Flycheck's errors 7th, diff-hl's tick 8th:
examples/stripe.el reads them there."
  (nconc (list (current-buffer)
               (or start (window-start window))
               (window-vscroll window t)       ; smooth scrolling: part of a row
               (window-body-height window t)
               (window-font-height window)
               (cdr (window-margins window))   ; reset when the buffer is shown again
               (bound-and-true-p flycheck-current-errors)
               +my/stripe--diff-hl-tick
               +my/stripe--line-edits
               ;; Where the strip goes: the window moved, its header line grew
               ;; (a notice)...
               (window-header-line-height window)
               (window-tab-line-height window)
               ;; Scrolled sideways: a terminal's cells hang elsewhere.
               (window-hscroll window))
         (window-pixel-edges window)))

;; diff-hl redraws its highlights asynchronously; bumping the tick makes the
;; next redisplay redraw the stripe.
(defun +my/stripe--after-diff-hl-a (&rest _)
  (when (bound-and-true-p +my/stripe-mode)
    (cl-incf +my/stripe--diff-hl-tick)))

(advice-add 'diff-hl--update-overlays :after #'+my/stripe--after-diff-hl-a)

(advice-add 'diff-hl-remove-overlays :after #'+my/stripe--after-diff-hl-a)
