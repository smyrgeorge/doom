;;; $DOOMDIR/config/stripe/tty.el -*- lexical-binding: t; -*-
;; The stripe in a terminal. Loaded from config/stripe.el.

;;; Terminal: coloured cells in the right margin

(defun +my/stripe--cell-rows (window start lines marks)
  "(POSITION . STRING) for each of WINDOW's rows from START: a coloured cell."
  (let* ((window-rows (max 1 (window-body-height window)))
         ;; Margin strings need text to hang on, so the stripe is drawn next
         ;; to text only; the rows below the end of the buffer keep Emacs'
         ;; usual empty-line `~'. When the end is on screen, map the whole
         ;; file onto the rows with text, so no mark (or the band) falls on
         ;; the empty rows.
         (starts (save-excursion
                   (goto-char start)
                   (let ((starts (list (point))))
                     (while (and (< (length starts) window-rows)
                                 (= (vertical-motion 1 window) 1))
                       (push (point) starts))
                     (nreverse starts))))
         (rows (length starts))
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
    ;; Thumb: the rows covering the lines on screen (long files only), from
    ;; the first line to the one on the last row (wrapped lines take several
    ;; rows, so that's not always FIRST + ROWS - 1).
    (when (> lines rows)
      (setq thumb (cons (+my/stripe--line-to-row (line-number-at-pos start t) lines rows)
                        (+my/stripe--line-to-row
                         (min lines (line-number-at-pos (car (last starts)) t))
                         lines rows))))
    (set-window-parameter window '+my/stripe-geometry (list 'cells rows lines)) ; for clicks
    (cl-loop for pos in starts
             for row from 0
             for kind = (aref cells row)
             for color = (or (and kind (+my/stripe--kind-color kind))
                             (and thumb (<= (car thumb) row (cdr thumb)) thumb-color))
             collect (cons pos
                           (propertize
                            " " 'display
                            `((margin right-margin)
                              ,(propertize " "
                                           'face (and color (list :background color))
                                           '+my/stripe-row row
                                           'keymap +my/stripe-margin-map
                                           'pointer 'hand
                                           'help-echo "mouse-1: jump to this part of the file")))))))

(defun +my/stripe--anchor (window pos)
  "Where to hang the cell of WINDOW's row starting at POS. A row that starts a
line: there. A row that continues a wrapped line (visual-line-mode, e.g.
Markdown): on its last character (the space it wraps at, or the newline).
Laying out the row before, Emacs looks ahead into this row's first word to
see whether it fits, and draws a margin string it meets there on that row
too: hung at the start of the row (or just after) the cell showed on the row
before, or on both."
  (if (or (= pos (point-min)) (eq (char-before pos) ?\n))
      pos
    (let ((next (save-excursion
                  (goto-char pos)
                  (and (= (vertical-motion 1 window) 1) (point)))))
      (cond ((null next) (point-max))   ; the last row
            ((> next (1+ pos)) (1- next))
            (t pos)))))

(defun +my/stripe--draw-cells (window start lines marks)
  "Draw WINDOW's strip as margin cells (a terminal), on overlays of its own."
  (let ((old nil))
    ;; Reuse this window's cell overlays; drop those of windows that no longer
    ;; show this buffer. Found by their property, not kept in a variable:
    ;; reverting the buffer would lose track of them.
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (overlay-get ov '+my/stripe-row)
        (let ((win (overlay-get ov 'window)))
          (cond ((eq win window) (push ov old))
                ((or (not (window-live-p win))
                     (not (eq (window-buffer win) (current-buffer))))
                 (delete-overlay ov))))))
    (pcase-dolist (`(,pos . ,string) (+my/stripe--cell-rows window start lines marks))
      (let* ((at (+my/stripe--anchor window pos))
             (ov (or (pop old) (make-overlay at at))))
        (move-overlay ov at at)
        (overlay-put ov '+my/stripe t)
        (overlay-put ov '+my/stripe-row t)
        (overlay-put ov 'window window)
        (overlay-put ov 'before-string string)))
    (mapc #'delete-overlay old)))
