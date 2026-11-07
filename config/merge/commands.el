;;; $DOOMDIR/config/merge/commands.el -*- lexical-binding: t; -*-
;; The buttons' and keys' commands. Loaded from config/merge.el.

;; COMMANDS
(defun +my/merge--clicked-index (posn)
  "The index, in the margin's string, of the character clicked at POSN. In a
terminal's right margin, from the column: Emacs (31) draws the margin from the
text's right edge on but takes it as starting a column later, so the string's
position it gives is that of the character left of the one clicked (and a
click on the margin's first column, one on the text: see
`+my/merge--right-margin-text')."
  (let ((window (posn-window posn))
        (index (cdr (posn-string posn))))
    (if (and index (eq (posn-area posn) 'right-margin)
             (window-live-p window) (not (display-graphic-p (window-frame window))))
        (- (car (posn-x-y posn))         ; a column, from the window's left edge
           (- (nth 2 (window-body-edges window)) (nth 0 (window-edges window))))
      index)))

(defun +my/merge-click (event)
  "A click in a pane's margin: the button there."
  (interactive "e")
  (let* ((posn (event-start event))
         (string (car (posn-string posn)))
         (index (and string (+my/merge--clicked-index posn)))
         (action (and index (< -1 index (length string))
                      (get-text-property index '+my/merge-action string))))
    (when (window-live-p (posn-window posn))
      (select-window (posn-window posn)))
    (when action
      (apply #'+my/merge--decide action))))

(defun +my/merge--chunk-at (&optional pos)
  "The change at POS (point) in the current pane, or the next one on its line."
  (let ((pos (or pos (point))))
    (or (seq-some (lambda (ov) (overlay-get ov '+my/merge-chunk))
                  (overlays-at pos))
        (seq-some (lambda (ov) (overlay-get ov '+my/merge-chunk))
                  (overlays-in (line-beginning-position) (min (point-max) (1+ (line-end-position))))))))

(defun +my/merge--chunk-here ()
  (or (+my/merge--chunk-at) (user-error "No change here")))

(defun +my/merge-take-left ()
  "SPC m l: the change at point from Yours (after Theirs' if in: keep both)."
  (interactive)
  (+my/merge--decide (+my/merge--chunk-here) 'yours 'applied))

(defun +my/merge-take-right ()
  "SPC m r: the change at point from Theirs (after Yours' if in: keep both)."
  (interactive)
  (+my/merge--decide (+my/merge--chunk-here) 'theirs 'applied))

(defun +my/merge-ignore ()
  "SPC m x: ignore the change at point (both sides' not in yet)."
  (interactive)
  (let ((chunk (+my/merge--chunk-here)))
    (dolist (side '(yours theirs))
      (unless (+my/merge--state chunk side)
        (+my/merge--decide chunk side 'ignored)))))

(defun +my/merge-wand ()
  "SPC m w: the wand on the conflict at point: its sides' words merged."
  (interactive)
  (let ((chunk (+my/merge--chunk-here)))
    (unless (+my/merge-chunk-wand chunk)
      (user-error "No wand here: the sides changed the same words, or it's no conflict"))
    (+my/merge--merge-words-in chunk)))

(defun +my/merge--accept (side)
  "SIDE for every change not done yet (the other side's ignored)."
  (seq-doseq (chunk (+my/merge-chunks (+my/merge--session)))
    (unless (+my/merge--resolved-p chunk)
      (if (+my/merge--changed-p chunk side)
          (progn (unless (+my/merge--state chunk side)
                   (+my/merge--decide chunk side 'applied))
                 (unless (+my/merge--handled-p chunk (+my/merge--other side))
                   (+my/merge--decide chunk (+my/merge--other side) 'ignored)))
        (+my/merge--decide chunk (+my/merge--other side) 'ignored)))))

(defun +my/merge-accept-left ()
  "Accept Left: Yours for every change not done yet."
  (interactive)
  (+my/merge--accept 'yours))

(defun +my/merge-accept-right ()
  "Accept Right: Theirs for every change not done yet."
  (interactive)
  (+my/merge--accept 'theirs))

(defun +my/merge-apply-non-conflicting ()
  "✨ Apply non-conflicting: every change only one side made (or both the
same), not done yet."
  (interactive)
  (let ((n 0))
    (seq-doseq (chunk (+my/merge-chunks (+my/merge--session)))
      (unless (or (eq (+my/merge-chunk-kind chunk) 'conflict) (+my/merge--resolved-p chunk))
        (cl-incf n)
        (+my/merge--decide chunk (if (+my/merge--changed-p chunk 'yours) 'yours 'theirs) 'applied)))
    (message "%d change%s applied" n (if (= n 1) "" "s"))))

(defun +my/merge--goto (chunk)
  "Point at CHUNK in each pane."
  (dolist (side '(yours result theirs))
    (let ((ov (+my/merge--overlay chunk side)))
      (with-current-buffer (overlay-buffer ov)
        (goto-char (overlay-start ov))
        (when-let* ((window (get-buffer-window (current-buffer))))
          (set-window-point window (point))
          (unless (pos-visible-in-window-p (point) window)
            (with-selected-window window (recenter 3))))))))

(defun +my/merge--move (forward)
  (let* ((session (+my/merge--session))
         (side (cond ((eq (current-buffer) (+my/merge-yours session)) 'yours)
                     ((eq (current-buffer) (+my/merge-theirs session)) 'theirs)
                     (t 'result)))
         (chunks (append (+my/merge-chunks session) nil))
         (target (if forward
                     (seq-find (lambda (c) (> (overlay-start (+my/merge--overlay c side)) (line-end-position)))
                               chunks)
                   (seq-find (lambda (c) (< (overlay-start (+my/merge--overlay c side)) (line-beginning-position)))
                             (reverse chunks)))))
    (if target
        (+my/merge--goto target)
      (message "No %s change" (if forward "next" "previous")))))

(defun +my/merge-next ()
  "]c: the next change."
  (interactive)
  (+my/merge--move t))

(defun +my/merge-previous ()
  "[c: the previous change."
  (interactive)
  (+my/merge--move nil))
