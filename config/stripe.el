;;; $DOOMDIR/config/stripe.el -*- lexical-binding: t; -*-
;; IntelliJ-like error stripe at the right edge of file windows. Loaded from
;; config.el.

;; ERROR STRIPE
;; A one-column strip in the right margin that maps the whole file onto the
;; window height, like the marks on IntelliJ's scrollbar:
;; - flycheck diagnostics (LSP included): red errors, yellow warnings (see
;;   `+my/stripe-diagnostic-levels');
;; - git changes (diff-hl), in the gutter's colours: red deleted, orange
;;   changed, green added;
;; - where several fall on one row, the most important wins, in that order
;;   (error > warning > deleted > changed > added > info);
;; - a light band marks the part of the file on screen, like a scrollbar thumb.
;; Click the strip to jump to that part of the file; the wheel scrolls as usual.
;; On in every file buffer in prog, text and conf modes.

(defvar +my/stripe-diagnostic-levels '(error warning)
  "Flycheck levels shown in the stripe; add `info' to also show hints.")

(defvar-local +my/stripe--overlays nil "Overlays drawing the stripe.")
(defvar-local +my/stripe--cache nil "(KEY LINES . MARKS) for `+my/stripe--marks'.")
(defvar-local +my/stripe--diff-hl-tick 0 "Bumped whenever diff-hl redraws.")

(defconst +my/stripe--kinds
  ;; KIND    PRIORITY FACE (its foreground is the colour)
  '((error   6 flycheck-fringe-error)
    (warning 5 flycheck-fringe-warning)
    (delete  4 diff-hl-delete)
    (change  3 diff-hl-change)
    (insert  2 diff-hl-insert)
    (info    1 flycheck-fringe-info)))

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
                  (push (list line line kind) marks)))))
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
    (min lines (1+ (floor (* (+ row 0.5) lines) rows)))))

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

(defun +my/stripe--key (window &optional start)
  "What WINDOW's stripe depends on, except edits (those redraw after a pause)."
  (list (current-buffer)
        (or start (window-start window))
        (window-body-height window)
        (bound-and-true-p flycheck-current-errors)
        +my/stripe--diff-hl-tick))

(defun +my/stripe--render (window &optional start)
  "Redraw the stripe of WINDOW, whose text starts at START."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      ;; Runs from redisplay hooks: never let an error escape into them.
      (with-demoted-errors "Stripe: %S"
       (when (bound-and-true-p +my/stripe-mode)
        ;; Drop this window's old strings, and those of windows that no longer
        ;; show this buffer.
        (setq +my/stripe--overlays
              (cl-delete-if (lambda (ov)
                              (let ((win (overlay-get ov 'window)))
                                (when (or (eq win window)
                                          (not (window-live-p win))
                                          (not (eq (window-buffer win) (current-buffer))))
                                  (delete-overlay ov)
                                  t)))
                            +my/stripe--overlays))
        (set-window-parameter window '+my/stripe-key (+my/stripe--key window start))
        (pcase-let* ((`(,lines . ,marks) (+my/stripe--marks))
                     (rows (max 1 (window-body-height window)))
                     (start (or start (window-start window)))
                     (cells (make-vector rows nil))
                     (thumb-color (+my/stripe--thumb-color))
                     (thumb nil))
          ;; Marks: in each row, the highest-priority kind wins.
          (pcase-dolist (`(,beg ,end ,kind) marks)
            (when-let* ((priority (car (alist-get kind +my/stripe--kinds))))
              (cl-loop for row from (+my/stripe--line-to-row beg lines rows)
                       to (+my/stripe--line-to-row (min end lines) lines rows)
                       for old = (aref cells row)
                       when (or (null old)
                                (> priority (car (alist-get old +my/stripe--kinds))))
                       do (aset cells row kind))))
          ;; Thumb: the rows covering the lines on screen (long files only).
          (when (> lines rows)
            (let ((first (line-number-at-pos start t)))
              (setq thumb (cons (+my/stripe--line-to-row first lines rows)
                                (+my/stripe--line-to-row (min lines (+ first rows -1))
                                                         lines rows)))))
          ;; One margin string per screen row. Each carries its row, for clicks.
          (cl-flet ((margin (row)
                      (let* ((kind (aref cells row))
                             (face (cadr (alist-get kind +my/stripe--kinds)))
                             (color (if (and kind (facep face))
                                        (face-foreground face nil t)
                                      (and thumb (<= (car thumb) row (cdr thumb))
                                           thumb-color))))
                        (propertize
                         " " 'display
                         `((margin right-margin)
                           ,(propertize " "
                                        'face (and color (list :background color))
                                        '+my/stripe-row row)))))
                    (place (pos string &optional priority)
                      (let ((ov (make-overlay pos pos)))
                        (overlay-put ov 'window window)
                        (overlay-put ov 'before-string string)
                        (when priority (overlay-put ov 'priority priority))
                        (push ov +my/stripe--overlays))))
            (save-excursion
              (goto-char start)
              (let ((last (cl-loop for row below rows
                                   do (place (point) (margin row))
                                   while (= (vertical-motion 1 window) 1)
                                   finally return row)))
                ;; Past the end of the buffer there is no text to hang margin
                ;; strings on: add the remaining rows as empty display-only
                ;; lines after the last one, so the stripe stays whole. A
                ;; before-string with a higher priority comes after the last
                ;; row's own string when the last line is the empty one at
                ;; `point-max' (an after-string would come first and push that
                ;; line down); `cursor' keeps the cursor on the real last line.
                (when (< last (1- rows))
                  (place (point-max)
                         (concat (propertize "\n" 'cursor t)
                                 (mapconcat #'margin
                                            (number-sequence (1+ last) (1- rows))
                                            "\n"))
                         100)))))))))))

(defun +my/stripe--render-buffer ()
  "Redraw the stripe in every window showing the current buffer."
  (dolist (window (get-buffer-window-list nil nil t))
    (+my/stripe--render window)))

(defvar-local +my/stripe--edit-timer nil)
(defun +my/stripe--after-change (&rest _)
  "Redraw shortly after edits (lines added or removed shift the stripe)."
  (unless (timerp +my/stripe--edit-timer)
    (let ((buffer (current-buffer)))
      (setq +my/stripe--edit-timer
            (run-with-idle-timer
             0.2 nil
             (lambda ()
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (setq +my/stripe--edit-timer nil)
                   (+my/stripe--render-buffer)))))))))

(defun +my/stripe--render-all ()
  "Redraw the stripe in every window (e.g. after a theme change)."
  (dolist (window (window-list-1 nil 'nomini t))
    (+my/stripe--render window)))

;; Redraw right before a window is displayed whenever what it shows changed
;; (scroll position, size, buffer, diagnostics, git highlights). This catches
;; every kind of scrolling, including the animated ones (good-scroll and
;; ultra-scroll move the window from timers, which `window-scroll-functions'
;; doesn't reliably see), before the stale stripe can be drawn.
(defun +my/stripe--pre-redisplay (window)
  (when (and (bound-and-true-p +my/stripe-mode)
             (windowp window)
             (let ((old (window-parameter window '+my/stripe-key)))
               ;; `eq' per part: the error list is compared by identity.
               (not (and old (cl-every #'eq old (+my/stripe--key window))))))
    (+my/stripe--render window)))
(add-hook 'pre-redisplay-functions #'+my/stripe--pre-redisplay)

(defun +my/stripe-jump (event)
  "Jump to the part of the file at the clicked row of the stripe."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (string (posn-string posn))
         (row (and string (get-text-property (or (cdr string) 0) '+my/stripe-row
                                             (car string)))))
    (when (and row (window-live-p window))
      (select-window window)
      (let ((line (+my/stripe--row-to-line row (car (+my/stripe--marks))
                                           (max 1 (window-body-height window)))))
        (when (fboundp 'better-jumper-set-jump)
          (better-jumper-set-jump))
        (goto-char (point-min))
        (forward-line (1- line))
        (recenter)))))

(define-minor-mode +my/stripe-mode
  "IntelliJ-like stripe of git changes and diagnostics in the right margin."
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map [right-margin mouse-1] #'+my/stripe-jump)
            (define-key map [right-margin down-mouse-1] #'ignore)
            map)
  (if +my/stripe-mode
      (progn
        (setq-local right-margin-width 1)
        ;; Scrolls that redisplay itself decides on (point left the window);
        ;; everything else is caught by `+my/stripe--pre-redisplay'.
        (add-hook 'window-scroll-functions #'+my/stripe--render nil t)
        (add-hook 'after-change-functions #'+my/stripe--after-change nil t)
        (dolist (window (get-buffer-window-list nil nil t))
          (set-window-margins window (car (window-margins window)) 1)
          (+my/stripe--render window)))
    (mapc #'delete-overlay +my/stripe--overlays)
    (setq +my/stripe--overlays nil
          +my/stripe--cache nil)
    (kill-local-variable 'right-margin-width)
    (remove-hook 'window-scroll-functions #'+my/stripe--render t)
    (remove-hook 'after-change-functions #'+my/stripe--after-change t)
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-margins window (car (window-margins window)) nil))))

(defun +my/stripe--maybe-enable ()
  (when (and buffer-file-name (derived-mode-p 'prog-mode 'text-mode 'conf-mode))
    (+my/stripe-mode 1)))

(define-globalized-minor-mode +my/stripe-global-mode +my/stripe-mode
  +my/stripe--maybe-enable)
(+my/stripe-global-mode 1)

;; diff-hl redraws its highlights asynchronously; bumping the tick makes the
;; next redisplay redraw the stripe.
(defun +my/stripe--after-diff-hl-a (&rest _)
  (when (bound-and-true-p +my/stripe-mode)
    (cl-incf +my/stripe--diff-hl-tick)))
(advice-add 'diff-hl--update-overlays :after #'+my/stripe--after-diff-hl-a)
(advice-add 'diff-hl-remove-overlays :after #'+my/stripe--after-diff-hl-a)

(add-hook 'doom-load-theme-hook #'+my/stripe--render-all)
