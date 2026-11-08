;;; $DOOMDIR/config/stripe/gui.el -*- lexical-binding: t; -*-
;; The stripe in graphical frames. Loaded from config/stripe.el.

;;; Graphical frames: one image, in a child frame over the right margin

(defvar +my/stripe--frames nil
  "(WINDOW FRAME CONTENT IMAGE) for each window that shows (or showed) the
strip: FRAME, a child frame, shows its IMAGE, made from CONTENT.")

(defvar +my/stripe--sync-timer nil)

(defun +my/stripe--palette ()
  "The strip's colours by pixel character: blank, ?t the band, ?1..?6 the kinds."
  (append (list (cons ?\s "None")
                (cons ?t (+my/stripe--thumb-color)))
          (cl-loop for (kind priority) in +my/stripe--kinds
                   collect (cons (+ ?0 priority)
                                 (or (+my/stripe--kind-color kind) "None")))))

(defun +my/stripe--pixel-rank (char)
  "Which pixel character wins: marks by priority, then the band, then blank."
  (pcase char (?\s -1) (?t 0) (_ (- char ?0))))

(defun +my/stripe--last-line-shown (window start rows lines)
  "(LINE . EMPTY): the line after the last one WINDOW shows from START, ROWS
rows tall; at the end of the buffer, LINES + 1 and the empty rows below it.
Lines cut off at the window's edge (Doom's default) take a row each: counted.
Wrapped ones (Markdown, visual-line-mode) are laid out to see (a millisecond
for a window of rows: at each step of a scroll, that was most of its cost)."
  (if (or truncate-lines (truncated-partial-width-window-p window))
      (let ((after (+ (line-number-at-pos start t) rows)))
        (if (<= after lines)
            (cons after 0)
          (cons (1+ lines) (- after lines 1))))
    (save-excursion
      (goto-char start)
      (let ((moved (vertical-motion rows window)))
        (if (and (= moved rows) (< (point) (point-max)))
            (cons (line-number-at-pos (point) t) 0)
          (cons (1+ lines) (max 0 (- rows moved 1))))))))

(defun +my/stripe--pixels (window start lines marks)
  "(PIXELS SCALE THUMB) of WINDOW's strip from START: PIXELS a palette
character per pixel row of its text area, top to bottom; SCALE pixels per
line; THUMB the band, (TOP . BOTTOM) in pixels, nil when the file fits."
  (let* ((height (max 1 (window-body-height window t)))
         (font-height (window-font-height window))
         (rows (max 1 (window-body-height window)))
         ;; The strip maps the file plus the empty space the window may
         ;; scroll past its end: the marks don't move as the end comes into
         ;; view, and the band reaches the bottom when it can't scroll further.
         (overscroll (if (eq +my/stripe-overscroll t)
                         (1- rows)
                       (- rows (+my/stripe--text-rows-wanted window))))
         (scale (min (float font-height) (/ (float height) (+ lines overscroll))))
         (pixels (make-string height ?\s))
         (thumb nil))
    ;; The band (when the window can scroll): its first line, the part of it
    ;; scrolled away included, down to the last line shown, and the empty rows
    ;; below the end.
    (when (< scale font-height)
      (pcase-let* ((first (line-number-at-pos start t))
                   (`(,after . ,empty) (+my/stripe--last-line-shown window start rows lines))
                   (top (* scale (+ (1- first) (/ (float (window-vscroll window t)) font-height))))
                   (bottom (* scale (+ (1- after) empty)))
                   (top-y (min (max 0 (floor top)) (- height +my/stripe-thumb-min-height)))
                   (bottom-y (min height (max (round bottom) (+ top-y +my/stripe-thumb-min-height)))))
        (setq thumb (cons (max 0 top-y) bottom-y))
        (cl-loop for y from (max 0 top-y) below bottom-y
                 do (aset pixels y ?t))))
    ;; Marks: where they overlap, the highest priority wins.
    (pcase-dolist (`(,beg ,end ,kind) marks)
      (when-let* ((priority (car (alist-get kind +my/stripe--kinds))))
        (let* ((char (+ ?0 priority))
               (y0 (max 0 (min (floor (* scale (1- beg)))
                               (- height +my/stripe-mark-height))))
               (y1 (if (<= end beg)
                       (+ y0 +my/stripe-mark-height)
                     (max (+ y0 +my/stripe-mark-height)
                          (round (* scale (min end lines)))))))
          (cl-loop for y from y0 below (min height y1)
                   when (> priority (+my/stripe--pixel-rank (aref pixels y)))
                   do (aset pixels y char)))))
    (list pixels scale thumb)))

(defun +my/stripe--image (pixels width palette)
  "An image WIDTH pixels wide whose pixel rows have the colours of PIXELS (a
string of PALETTE's characters, one per pixel row)."
  (let ((rows (make-hash-table)))
    `(image :type xpm :scale 1 :ascent 100
            :data ,(concat
                    "/* XPM */\nstatic char *stripe[] = {\n"
                    (format "\"%d %d %d 1\",\n" width (length pixels) (length palette))
                    (mapconcat (lambda (entry) (format "\"%c c %s\",\n" (car entry) (cdr entry)))
                               palette "")
                    (mapconcat (lambda (char)
                                 (or (gethash char rows)
                                     (puthash char (format "\"%s\"" (make-string width char)) rows)))
                               pixels ",\n")
                    "};"))))

(defun +my/stripe--geometry (window)
  "(LEFT TOP WIDTH HEIGHT): WINDOW's right margin beside its text, in its
frame's pixels (as a child frame is placed)."
  (let* ((edges (window-pixel-edges window))
         (right (- (nth 2 edges)
                   (window-right-divider-width window)
                   (window-scroll-bar-width window)))
         (width (* (or (cdr (window-margins window)) 0)
                   (frame-char-width (window-frame window)))))
    (list (- right width)
          (nth 1 (window-inside-pixel-edges window))
          width
          (window-body-height window t))))

(defun +my/stripe--make-frame (parent)
  "A child frame of PARENT for a strip (config/childframe.el)."
  (let ((frame (+my/childframe-make
                parent "+my/stripe"
                `((+my/stripe . t)
                  (title . "stripe")
                  ;; Wide enough to take its margins off (see `+my/stripe--bare').
                  (width . 10)
                  (height . 2)
                  (background-color . ,(face-background 'default parent t))))))
    (+my/stripe--bare frame)
    frame))

;; A new frame's window first shows the current buffer: a file's, with the
;; strip's margin. Emacs changes a window's margins only if it's left at least
;; two columns wide, so in the strip's frame (a column) that margin stayed,
;; over all of it: the strip took its room and showed nothing. Taken off while
;; the frame is wider.
(defun +my/stripe--bare (frame)
  "FRAME's window all text: no margins, fringes or horizontal scroll."
  (let ((window (frame-root-window frame)))
    (unless (and (null (car (window-margins window))) (null (cdr (window-margins window)))
                 (equal (seq-take (window-fringes window) 2) '(0 0)))
      (when (< (window-total-width window) 10)
        (let ((frame-resize-pixelwise t))
          (set-frame-size frame (* 10 (frame-char-width frame)) (frame-pixel-height frame) t)
          (set-frame-parameter frame '+my/stripe-geometry nil)))   ; placed again
      (set-window-fringes window 0 0)
      (set-window-margins window 0 0))
    (set-window-hscroll window 0)))

(defun +my/stripe--show-in (window)
  "Lay WINDOW's strip frame over its right margin (made the first time), and
draw it."
  (let ((entry (assq window +my/stripe--frames)))
    (unless (and entry (frame-live-p (nth 1 entry)))
      (when entry (+my/childframe-delete (nth 1 entry)))
      (setq entry (list window (+my/stripe--make-frame (window-frame window)) nil nil))
      (setq +my/stripe--frames
            (cons entry (cl-remove window +my/stripe--frames :key #'car))))
    (let* ((frame (nth 1 entry))
           (geometry (+my/stripe--geometry window))
           (frame-resize-pixelwise t))
      (set-frame-parameter frame '+my/stripe-window window)
      (+my/stripe--bare frame)
      (if (or (<= (nth 2 geometry) 0) (<= (nth 3 geometry) 0))
          (make-frame-invisible frame t)
        (unless (equal geometry (frame-parameter frame '+my/stripe-geometry))
          (set-frame-size frame (nth 2 geometry) (nth 3 geometry) t)
          (set-frame-position frame (nth 0 geometry) (nth 1 geometry))
          (set-frame-parameter frame '+my/stripe-geometry geometry))
        (with-current-buffer (window-buffer window)
          (+my/stripe--render window))
        (unless (frame-visible-p frame)
          (make-frame-visible frame))))))

(defun +my/stripe--sync ()
  "Give each window showing a stripe its strip frame, laid over its right
margin; hide those of windows that no longer show one; delete those of
closed windows."
  (setq +my/stripe--sync-timer nil)
  (+my/childframe-sync '+my/stripe--frames
                       (lambda (window) (buffer-local-value '+my/stripe-mode (window-buffer window)))
                       #'+my/stripe--show-in "Stripe"))

(defun +my/stripe--sync-soon (&rest _)
  "Sync right after this redisplay (frames can't be made during it)."
  (+my/childframe-soon '+my/stripe--sync-timer #'+my/stripe--sync))

(defun +my/stripe--window-change-h (frame)
  ;; Windows split, closed, resized, or showing another buffer.
  (unless (frame-parent frame)
    (+my/stripe--sync-soon)))

(add-hook 'window-state-change-functions #'+my/stripe--window-change-h)

(defun +my/stripe--draw-image (window start lines marks)
  "Draw WINDOW's strip into its frame's image, if the strip changed (a frame
made first, after this redisplay, if it has none)."
  (let ((entry (assq window +my/stripe--frames)))
    (if (not (and entry (frame-live-p (nth 1 entry))))
        (+my/stripe--sync-soon)
      (pcase-let* ((frame (nth 1 entry))
                   (`(,pixels ,scale ,thumb) (+my/stripe--pixels window start lines marks))
                   (width (max 1 (* (or (cdr (window-margins window)) 1)
                                    (frame-char-width (window-frame window)))))
                   (palette (+my/stripe--palette))
                   (content (list pixels width palette)))
        (set-window-parameter window '+my/stripe-geometry (list 'pixels scale lines thumb))
        (unless (equal content (nth 2 entry))
          (let ((old (nth 3 entry))
                (image (+my/stripe--image pixels width palette)))
            (setf (nth 2 entry) content
                  (nth 3 entry) image)
            (with-current-buffer (window-buffer (frame-root-window frame))
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert (propertize " " 'display image
                                    'keymap +my/stripe--strip-map
                                    'pointer 'hand
                                    'help-echo "mouse-1: jump there; drag the band to scroll"))))
            ;; Emacs keeps each image drawn: scrolling made a new one at each
            ;; step of the band.
            (when old (image-flush old t))
            ;; Drawn anew, all of it: on macOS the strip's frame once kept
            ;; showing its old image on screen though Emacs had drawn the new
            ;; one (its glyphs had it), so the band stopped moving (seen after
            ;; Doom reloaded its config, SPC h r r). A frame 8 pixels wide,
            ;; one image: cheap.
            (redraw-frame frame)))
        ;; Moved or resized (a notice above, a split): placed anew.
        (unless (equal (+my/stripe--geometry window) (frame-parameter frame '+my/stripe-geometry))
          (+my/stripe--sync-soon))))))
