;;; $DOOMDIR/config/editor/modeline.el -*- lexical-binding: t; -*-
;; Mode line (doom-modeline) tweaks.
;; Loaded from config/editor.el.

;; MODE LINE
;; A space after the mode line's last item on the right (e.g. flycheck's
;; checkmark), which touched the window's edge. In every layout doom-modeline
;; has (file buffers, magit, treemacs...).
(after! doom-modeline
  (dolist (modeline doom-modeline--modelines)
    (pcase-let ((`(,name ,lhs ,rhs) modeline))
      (when (and rhs (not (equal (car (last rhs)) " ")))
        (doom-modeline-def-modeline name lhs (append rhs '(" ")))))))

;; EACH WINDOW ITS OWN LAYOUT
;; doom-modeline's narrow layout (the buffer's name only, less on the right:
;; `doom-modeline--limited-width-p', in windows of
;; `doom-modeline-window-width-limit' columns or less) is a buffer's, worked
;; out from the selected window's width as windows change: a narrow pane not
;; selected got the wide layout, its path pushing the rest off. Each mode line
;; now works it out for its own window as it's drawn.
;; In the wide layout, a deep project path (Doom's: relative-from-project)
;; pushed the position and the right side off (a Kotlin file's in 100
;; columns). Each mode line now shows the path its window has room for, the
;; rest of the line whole: the path, else its folders cut to their first
;; letter (truncate-with-project: app/s/m/k/c/e/a/AgreementController.kt),
;; else the file's name.

(defvar-local +my/modeline--names nil
  "The names the mode line can show for the buffer, the longest first:
doom-modeline's (its style's), its folders shortened, the file's name (see
above). Set with doom-modeline's own.")

(defun +my/modeline-names-a (&rest _)
  "After doom-modeline worked out the buffer's name (its style's): the
shorter ones too, in `+my/modeline--names'."
  (setq +my/modeline--names
        (when-let* ((full doom-modeline--buffer-file-name))
          (cons full
                (and buffer-file-name
                     (let (names)
                       (dolist (style '(truncate-with-project file-name))
                         (when-let* ((name (ignore-errors
                                             (save-match-data
                                               (let ((doom-modeline-buffer-file-name-style style))
                                                 (doom-modeline-buffer-file-name))))))
                           (when (< (string-width name) (string-width (or (car names) full)))
                             (push name names))))
                       (nreverse names)))))))

(defun +my/modeline--string-width (string)
  "STRING's width in the mode line: pixels (a terminal's columns)."
  (let ((string (copy-sequence string)))
    (add-face-text-property 0 (length string) 'mode-line t string)
    (doom-modeline-string-pixel-width string)))

;; A layout's format (doom-modeline's) is its left side, a space up to the
;; right side (its width, worked out, in the space's `display'), the right
;; side; each side drawn in the selected window (the one whose mode line is).
(defun +my/modeline--left (format)
  "The text of FORMAT's left side, as drawn (see above)."
  (format-mode-line (car format)))

(defun +my/modeline--right (format)
  "The text of FORMAT's right side, as drawn (see above)."
  (format-mode-line (nth 2 format)))

(defun +my/modeline--room ()
  "The width the selected window's mode line has, as
`+my/modeline--string-width' counts."
  (- (window-pixel-width) (window-right-divider-width) (window-scroll-bar-width)))

(defun +my/modeline--choose (names left right)
  "The first of NAMES the selected window's mode line has room for, its
sides LEFT (showing the first of NAMES) and RIGHT; else the last one."
  (let ((room (- (+my/modeline--room) (+my/modeline--string-width right)))
        (others (- (+my/modeline--string-width left) (+my/modeline--string-width (car names)))))
    (or (seq-find (lambda (name) (<= (+ others (+my/modeline--string-width name)) room)) names)
        (car (last names)))))

(defun +my/modeline-fit-a (fn &rest args)
  "A doom-modeline layout's format (FN with ARGS) for the window whose mode
line is drawn (the selected one then): the narrow layout if it's narrow;
in the wide one, the longest name it has room for with the rest of the line
\(see above). Measuring each time took 4 times doom-modeline's own: what was
chosen is kept for the window while its width, the left side's and the
right side's are the same."
  (doom-modeline-window-size-change)
  (unless (or +my/modeline--names doom-modeline--limited-width-p)
    (doom-modeline-update-buffer-file-name))
  (let ((names (and (not doom-modeline--limited-width-p) +my/modeline--names)))
    (when names
      (setq doom-modeline--buffer-file-name (car names)))
    (let ((format (apply fn args)))
      (when (and (cdr names) (consp format) (= (length format) 3))
        (let* ((left (+my/modeline--left format))
               (key (list (current-buffer) (window-pixel-width) names (string-width left)
                          (get-text-property 0 'display (nth 1 format))))
               (kept (window-parameter nil '+my/modeline-fit)))
          (setq doom-modeline--buffer-file-name
                (if (equal (car kept) key)
                    (cdr kept)
                  (let ((name (+my/modeline--choose names left (+my/modeline--right format))))
                    (set-window-parameter nil '+my/modeline-fit (cons key name))
                    name)))))
      format)))

(defun +my/modeline-fit-layout-a (name &rest _)
  "After `doom-modeline-def-modeline' NAME: its format fitted to each
window (`+my/modeline-fit-a')."
  (advice-add (intern (format "doom-modeline-format--%s" name)) :around #'+my/modeline-fit-a))

(after! doom-modeline
  (advice-add 'doom-modeline-update-buffer-file-name :after #'+my/modeline-names-a)
  (advice-add 'doom-modeline-def-modeline :after #'+my/modeline-fit-layout-a)
  (dolist (modeline doom-modeline--modelines)
    (+my/modeline-fit-layout-a (car modeline))))
