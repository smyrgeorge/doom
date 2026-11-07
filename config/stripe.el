;;; $DOOMDIR/config/stripe.el -*- lexical-binding: t; -*-
;; An error stripe at the right edge of file windows. Loaded from
;; config.el.

;; ====== VARIABLES ======

;; ERROR STRIPE
;; A strip at the right edge of the window that maps the whole file onto the
;; window height, like marks on a scrollbar:
;; - flycheck diagnostics (LSP included): red errors, yellow warnings (see
;;   `+my/stripe-diagnostic-levels');
;; - git changes (diff-hl), in the gutter's colours: red deleted, orange
;;   changed, green added;
;; - where several overlap, the most important wins, in that order
;;   (error > warning > deleted > changed > added > info);
;; - a light band marks the part of the file on screen: the scrollbar's thumb.
;; Click the strip to jump to that part of the file; drag the band to scroll;
;; the wheel over it scrolls the file. On in every file buffer in prog, text and
;; conf modes (and so-long-mode).
;;
;; In graphical frames the strip is one image, drawn to the pixel, in a small
;; frame of its own (a child frame, as the notices' are) laid over the window's
;; right margin. It was a column of images in the margin, a slice per screen
;; row: every scroll changed every row's slice, so Emacs redrew every row
;; instead of moving the text (5.8 ms a step instead of 3.3), and rows had to be
;; measured (emoji, wrapped lines, smooth scrolling's part rows, the space
;; below the last line). Now the window's rows are left alone, and the image is
;; made anew only when it changes (most scrolls move the band by less than a
;; pixel). In a terminal each row is a coloured cell in the margin.

(defvar +my/stripe-diagnostic-levels '(error warning)
  "Flycheck levels shown in the stripe; add `info' to also show hints.")

(defvar +my/stripe-mark-height 4
  "Minimum height of a mark, in pixels (graphical frames).")

(defvar +my/stripe-thumb-min-height 12
  "Minimum height of the band, in pixels: big enough to grab (graphical frames).")

;; Windows with the stripe may scroll past the end of the file only a bit: at
;; most this much empty space below the last line. In graphical frames the
;; strip maps the file plus this space onto the whole window height, so it
;; never shrinks: the marks stay put as the end
;; comes into view, and the band reaches the bottom when the window can't
;; scroll further. In a terminal it covers only the rows with text.
(defvar +my/stripe-overscroll 0.25
  "How far windows with the stripe may scroll past the end of the buffer:
a fraction of the window height (float), a number of rows (integer), 0 for
none (the last line stops at the bottom), or t for no limit.")

;; PADDING
;; File windows (those with the stripe) get a character's width of space more
;; on each side of the text: their fringes are that much wider (8 -> 16 px).
;; What's drawn in them sits in the middle: the git gutter on the left, the
;; arrows of lines cut off at the edge and flycheck's on the right.
(defvar +my/stripe-padding 1
  "Columns of space added to each fringe of file windows (nil: none).")

;; In fringes 16 px wide flycheck switches to its big (16 px) markers: keep the
;; small ones, in the middle (Doom's slim arrow for errors and warnings).
(after! flycheck
  (when (fboundp 'define-fringe-bitmap)
    (define-fringe-bitmap 'flycheck-fringe-bitmap-double-arrow-hi-res
      [16 48 112 240 112 48 16] nil nil 'center)
    (define-fringe-bitmap 'flycheck-fringe-bitmap-fixable-hi-res
      flycheck-fringe-bitmap-fixable nil nil 'center)))

(defvar +my/stripe-margin-map
  (let ((map (make-sparse-keymap)))
    (define-key map [right-margin mouse-1] #'+my/stripe-jump)
    (define-key map [right-margin down-mouse-1] #'ignore)
    map)
  "Keymap on the stripe's margin strings (terminal). A keymap on the clicked
text wins over mode keymaps, e.g. outline-minor-mode's margin buttons.")

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

(defvar-local +my/stripe--line-edits 0
  "Bumped by edits that add or remove line breaks: they move the marks and the
band (edits within a line don't: the strip isn't redrawn for those).")

(defvar +my/stripe--frames nil
  "(WINDOW FRAME CONTENT IMAGE) for each window that shows (or showed) the
strip: FRAME, a child frame, shows its IMAGE, made from CONTENT.")

(defvar +my/stripe--sync-timer nil)

;; ====== CODE ======

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
within a line don't change it."
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
               (window-tab-line-height window))
         (window-pixel-edges window)))

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

;;; Graphical frames: one image, in a child frame over the right margin

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
               (y1 (max (+ y0 +my/stripe-mark-height)
                        (round (* scale (min end lines))))))
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

(defvar +my/stripe--strip-map
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'+my/stripe-press)
    (dolist (event '(mouse-1 drag-mouse-1 double-down-mouse-1 double-mouse-1
                     triple-down-mouse-1 triple-mouse-1 down-mouse-2 mouse-2
                     down-mouse-3 mouse-3))
      (define-key map (vector event) #'ignore))
    (dolist (event '(wheel-up wheel-down wheel-left wheel-right
                     double-wheel-up double-wheel-down triple-wheel-up triple-wheel-down))
      (define-key map (vector event) #'+my/stripe-wheel))
    map)
  "Keys on the strip's image (graphical frames).")

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
  "A child frame of PARENT for a strip: no borders, never focused, its window
showing a buffer of its own."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (frame-resize-pixelwise t)
         (buffer (generate-new-buffer " *+my/stripe*"))
         (selected (selected-frame))
         (frame (make-frame
                 `((parent-frame . ,parent)
                   (+my/stripe . t)
                   (title . "stripe")
                   (fullscreen . nil)
                   (no-accept-focus . t)
                   (no-focus-on-map . t)
                   (min-width . 0)
                   (min-height . 0)
                   ;; Wide enough to take its margins off (see `+my/stripe--bare').
                   (width . 10)
                   (height . 2)
                   (border-width . 0)
                   (internal-border-width . 0)
                   (child-frame-border-width . 0)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)
                   (left-fringe . 0)
                   (right-fringe . 0)
                   (menu-bar-lines . 0)
                   (tool-bar-lines . 0)
                   (tab-bar-lines . 0)
                   (line-spacing . 0)
                   (unsplittable . t)
                   (no-other-frame . t)
                   (undecorated . t)
                   (visibility . nil)
                   (cursor-type . nil)
                   (minibuffer . ,(minibuffer-window parent))
                   (no-special-glyphs . t)
                   (desktop-dont-save . t)
                   (background-color . ,(face-background 'default parent t))))))
    (unless (eq (selected-frame) selected)
      (select-frame selected 'norecord))
    (with-current-buffer buffer
      (setq-local mode-line-format nil
                  header-line-format nil
                  tab-line-format nil
                  cursor-type nil
                  cursor-in-non-selected-windows nil
                  truncate-lines t
                  display-line-numbers nil
                  left-margin-width nil
                  right-margin-width nil
                  show-trailing-whitespace nil
                  buffer-read-only t))
    (let ((window (frame-root-window frame)))
      (dolist (parameter '(mode-line-format header-line-format tab-line-format))
        (set-window-parameter window parameter 'none))
      (set-window-buffer window buffer)
      (set-window-dedicated-p window t))
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

(defun +my/stripe--delete-frame (frame)
  (when (frame-live-p frame)
    (let ((buffer (window-buffer (frame-root-window frame))))
      (delete-frame frame t)
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun +my/stripe--show-in (window)
  "Lay WINDOW's strip frame over its right margin (made the first time), and
draw it."
  (let ((entry (assq window +my/stripe--frames)))
    (unless (and entry (frame-live-p (nth 1 entry)))
      (when entry (+my/stripe--delete-frame (nth 1 entry)))
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
  (let (wanted)
    (dolist (frame (frame-list))
      (when (and (not (frame-parent frame))
                 (display-graphic-p frame)
                 (frame-visible-p frame))
        (dolist (window (window-list frame 'nomini))
          (when (buffer-local-value '+my/stripe-mode (window-buffer window))
            (push window wanted)))))
    (setq +my/stripe--frames
          (cl-remove-if (lambda (entry)
                          (pcase-let ((`(,window ,frame) entry))
                            (cond ((not (frame-live-p frame)) t)
                                  ((memq window wanted) nil)
                                  ((window-live-p window)
                                   (make-frame-invisible frame t)
                                   nil)
                                  (t (+my/stripe--delete-frame frame) t))))
                        +my/stripe--frames))
    (dolist (window wanted)
      (condition-case err
          (+my/stripe--show-in window)
        (error (message "Stripe: %s" (error-message-string err)))))))

(defun +my/stripe--sync-soon (&rest _)
  "Sync right after this redisplay (frames can't be made during it)."
  (unless (timerp +my/stripe--sync-timer)
    (setq +my/stripe--sync-timer (run-at-time 0 nil #'+my/stripe--sync))))

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
            (when old (image-flush old t))))
        ;; Moved or resized (a notice above, a split): placed anew.
        (unless (equal (+my/stripe--geometry window) (frame-parameter frame '+my/stripe-geometry))
          (+my/stripe--sync-soon))))))

;;; Drawing

(defun +my/stripe--render (window &optional start)
  "Redraw the stripe of WINDOW, whose text starts at START."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      ;; Runs from redisplay hooks: never let an error escape into them.
      (with-demoted-errors "Stripe: %S"
        (when (bound-and-true-p +my/stripe-mode)
          (set-window-parameter window '+my/stripe-key (+my/stripe--key window start))
          (pcase-let ((`(,lines . ,marks) (+my/stripe--marks))
                      (start (or start (window-start window))))
            (if (display-graphic-p (window-frame window))
                ;; Not in windows of child frames (a strip's own, a popup's).
                (unless (frame-parent (window-frame window))
                  (when (and +my/stripe-padding (null left-fringe-width))
                    (+my/stripe--pad (window-frame window))
                    (+my/stripe--set-fringes window))
                  (+my/stripe--draw-image window start lines marks))
              (+my/stripe--draw-cells window start lines marks))))))))

(defun +my/stripe--scrolled (window start)
  "Redisplay scrolled WINDOW to START (e.g. to follow the cursor): redraw the
stripe there. Not when the window was just given the buffer
(`set-window-buffer' runs this too, before e.g. the saved place moves point):
the redraw right before it's displayed does it, at its final position. In a
graphical frame right after this redisplay: the strip's frame may be drawn
already."
  (when (eq (car-safe (window-parameter window '+my/stripe-key)) (window-buffer window))
    (if (display-graphic-p (window-frame window))
        (run-at-time 0 nil #'+my/stripe--render window)
      (+my/stripe--render window start))))

(defun +my/stripe--note-line-edit (beg end &rest _)
  "Before/after a change: count it if BEG..END holds a line break, i.e. lines
are being removed (before) or added (after)."
  (when (and (< beg end)
             (save-excursion (goto-char beg) (search-forward "\n" end t)))
    (cl-incf +my/stripe--line-edits)))

(defun +my/stripe--render-all ()
  "Redraw the stripe in every window (e.g. after a theme change: the strips'
frames take its background)."
  (dolist (entry +my/stripe--frames)
    (when (frame-live-p (nth 1 entry))
      (set-frame-parameter (nth 1 entry) 'background-color (face-background 'default nil t))))
  (dolist (window (window-list-1 nil 'nomini t))
    (+my/stripe--render window)))

;;; Scrolling past the end

(defun +my/stripe--text-rows-wanted (window)
  "How many of WINDOW's rows must show text: all but the allowed overscroll."
  (let ((rows (window-body-height window)))
    (max 1 (- rows (if (floatp +my/stripe-overscroll)
                       (floor (* rows +my/stripe-overscroll))
                     +my/stripe-overscroll)))))

;; Measured in pixels, not rows: a row showing an image (e.g. a screenshot in
;; an agent-shell reply) is as tall as many lines. Counted as one, the limit
;; came out far above the end: scrolling down to an image near the end,
;; ultra-scroll went on past it (within the image) and the limit then
;; snapped the window back up, by screens.
(defun +my/stripe--end-pixels-wanted (window)
  "How far below the top of WINDOW the end of its buffer must at least be, in
pixels: `+my/stripe--text-rows-wanted' rows, the empty line after a final
newline counting as one."
  (let ((lh (window-default-line-height window)))
    (- (* (+my/stripe--text-rows-wanted window) lh)
       (if (and (> (point-max) (point-min)) (eq (char-before (point-max)) ?\n))
           lh
         0))))

(defun +my/stripe--end-limit (window)
  "(START . VSCROLL): as far as WINDOW may scroll toward the end, the row the
allowed distance above it and how much of that row goes above the window's top
\(as ultra-scroll scrolls). Measured up from the end, as far as needed."
  (pcase-let* ((wanted (+my/stripe--end-pixels-wanted window))
               (`(,_ ,height ,start)
                (window-text-pixel-size window (cons (point-max) (- wanted))
                                        (point-max))))
    (and start (cons start (max 0 (- height wanted))))))

(defun +my/stripe--clamp-start (window)
  "Scroll WINDOW back so it doesn't show more empty space past the end than allowed."
  (unless (eq +my/stripe-overscroll t)
    (let ((start (window-start window))
          (vscroll (window-vscroll window t)))
      (when (or (> start (point-min)) (> vscroll 0))
        (pcase (+my/stripe--end-limit window)
          ((and `(,limit . ,limit-vscroll)
                (guard (or (> start limit)
                           (and (= start limit) (> vscroll limit-vscroll)))))
           (set-window-start window limit t)
           (set-window-vscroll window limit-vscroll t t)))))))

;; Redraw right before a window is displayed whenever what it shows changed
;; (scroll position, size, buffer, diagnostics, git highlights, lines added or
;; removed): every kind of scrolling and editing is caught before a stale
;; stripe can be drawn. Also limits scrolling past the end (`+my/stripe-overscroll').
(defun +my/stripe--pre-redisplay (window)
  (when (and (bound-and-true-p +my/stripe-mode) (windowp window))
    (let ((old (window-parameter window '+my/stripe-key)))
      ;; `eq' per part: the error list is compared by identity.
      (unless (and old (cl-every #'eq old (+my/stripe--key window)))
        ;; Scrolled (or edited...): hold the window within the limit before
        ;; this frame is drawn, then redraw the strip.
        (+my/stripe--clamp-start window)
        (+my/stripe--render window)))))

(defun +my/stripe--after-scroll (window start)
  "When redisplay itself scrolled WINDOW (e.g. to follow the cursor), maybe past
the end, check it right after."
  (when (and (not (eq +my/stripe-overscroll t))
             (window-live-p window)
             (<= (count-lines start (point-max)) (window-body-height window)))
    (run-at-time 0 nil (lambda ()
                         (when (window-live-p window)
                           (with-current-buffer (window-buffer window)
                             (when (bound-and-true-p +my/stripe-mode)
                               (+my/stripe--clamp-start window)
                               ;; Redraw before the next frame.
                               (set-window-parameter window '+my/stripe-key nil))))))))

(add-hook 'pre-redisplay-functions #'+my/stripe--pre-redisplay)

;;; Clicks, drags, the wheel

(defun +my/stripe--goto-line (window line)
  "Jump to LINE in WINDOW: in the middle of it, `C-o' going back."
  (select-window window)
  (when (fboundp 'better-jumper-set-jump)
    (better-jumper-set-jump))
  (goto-char (point-min))
  (forward-line (1- line))
  (recenter))

(defun +my/stripe-jump (event)
  "Jump to the part of the file at the clicked cell of the stripe (terminal)."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (geometry (and (window-live-p window)
                        (window-parameter window '+my/stripe-geometry))))
    (pcase geometry
      (`(cells ,rows ,lines)
       (when-let* ((string (posn-string posn))
                   (row (get-text-property (or (cdr string) 0) '+my/stripe-row (car string))))
         (+my/stripe--goto-line window (+my/stripe--row-to-line row lines rows)))))))

(defun +my/stripe--window-of (event)
  "The window whose strip EVENT happened on."
  (let ((window (frame-parameter (window-frame (posn-window (event-start event)))
                                 '+my/stripe-window)))
    (and (window-live-p window) window)))

(defun +my/stripe--scroll-band-to (window top scale)
  "Scroll WINDOW so the band's top is at TOP pixels of the strip, SCALE pixels
a line."
  (with-current-buffer (window-buffer window)
    (let ((line (max 1 (1+ (floor (/ (max 0 top) scale))))))
      (set-window-start window (save-excursion
                                 (goto-char (point-min))
                                 (forward-line (1- line))
                                 (point))))))

(defun +my/stripe-press (event)
  "A press on the strip: on the band, hold it (dragging scrolls); elsewhere,
jump there (the line in the middle of the window, `C-o' going back)."
  (interactive "e")
  (when-let* ((window (+my/stripe--window-of event)))
    ;; The keyboard stays with the file's frame, not the strip's.
    (select-frame-set-input-focus (window-frame window))
    (select-window window)
    (pcase (window-parameter window '+my/stripe-geometry)
      (`(pixels ,scale ,lines ,thumb)
       (let* ((posn (event-start event))
              (y (or (cdr (posn-object-x-y posn)) 0))
              (grab (and thumb (<= (car thumb) y (cdr thumb)) (- y (car thumb)))))
         (if (not grab)
             (+my/stripe--goto-line window (max 1 (min lines (1+ (floor (/ y scale))))))
           ;; Where the strip's top is on the screen: the mouse there now,
           ;; less how far down the strip it is.
           (let ((origin (- (cdr (mouse-absolute-pixel-position)) y))
                 (next nil))
             (track-mouse
               (while (progn (setq next (read-event))
                             (mouse-movement-p next))
                 (+my/stripe--scroll-band-to
                  window (- (cdr (mouse-absolute-pixel-position)) origin grab) scale)
                 (redisplay)))
             ;; Anything but the button's release goes on as input.
             (unless (memq (event-basic-type next) '(mouse-1))
               (push next unread-command-events)))))))))

(defun +my/stripe-wheel (event)
  "The wheel over the strip: it scrolls the file's window, as over its text."
  (interactive "e")
  (when-let* ((window (+my/stripe--window-of event))
              (command (with-selected-window window
                         (key-binding (vector (car event)) t))))
    (when (commandp command)
      (funcall command (append (list (car event) (posn-at-point (window-start window) window))
                               (nthcdr 2 event))))))

;;; Modes

(define-minor-mode +my/stripe-mode
  "A stripe of git changes and diagnostics at the right edge."
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map [right-margin mouse-1] #'+my/stripe-jump)
            (define-key map [right-margin down-mouse-1] #'ignore)
            ;; The fringe next to the strip (see PADDING): a click there,
            ;; just short of the strip, does nothing (not "is undefined").
            (define-key map [right-fringe mouse-1] #'ignore)
            (define-key map [right-fringe down-mouse-1] #'ignore)
            map)
  (if +my/stripe-mode
      (progn
        ;; The strip's room: its frame lies over it (a terminal: the cells).
        (setq-local right-margin-width 1)
        ;; Scrolls that redisplay itself decides on (point left the window);
        ;; everything else is caught by `+my/stripe--pre-redisplay'.
        (add-hook 'window-scroll-functions #'+my/stripe--scrolled nil t)
        (add-hook 'window-scroll-functions #'+my/stripe--after-scroll nil t)
        (add-hook 'before-change-functions #'+my/stripe--note-line-edit nil t)
        (add-hook 'after-change-functions #'+my/stripe--note-line-edit nil t)
        ;; The stripe at the very edge, the fringe (line truncation arrows)
        ;; between it and the text. Doom's vc-gutter puts fringes outside the
        ;; margins, for the git gutter's sake (at the left edge); without a
        ;; left margin, as in file windows, that changes nothing on the left.
        (setq-local fringes-outside-margins nil)
        (+my/stripe--pad)
        (dolist (window (get-buffer-window-list nil nil t))
          (set-window-margins window (car (window-margins window)) 1)
          (+my/stripe--set-fringes window)
          (+my/stripe--render window)))
    (remove-overlays (point-min) (point-max) '+my/stripe t)
    (setq +my/stripe--cache nil)
    (remove-hook 'window-scroll-functions #'+my/stripe--scrolled t)
    (remove-hook 'window-scroll-functions #'+my/stripe--after-scroll t)
    (remove-hook 'before-change-functions #'+my/stripe--note-line-edit t)
    (remove-hook 'after-change-functions #'+my/stripe--note-line-edit t)
    (kill-local-variable 'right-margin-width)
    (kill-local-variable 'fringes-outside-margins)
    (kill-local-variable 'left-fringe-width)
    (kill-local-variable 'right-fringe-width)
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-margins window (car (window-margins window)) nil)
      (+my/stripe--set-fringes window)))
  ;; The strips' frames: shown, hidden.
  (+my/stripe--sync-soon))

(defun +my/stripe--set-fringes (window)
  "Apply the buffer's fringe settings (`fringes-outside-margins', widths) to
WINDOW, which shows it already (windows take them when they start showing a
buffer)."
  (set-window-fringes window left-fringe-width right-fringe-width
                      fringes-outside-margins))

(defun +my/stripe--pad (&optional frame)
  "Widen the current buffer's fringes by `+my/stripe-padding' columns, as
measured in FRAME or else any graphical frame. With none yet (a terminal
session), it's done when a graphical window first shows the buffer."
  (when-let* ((columns +my/stripe-padding)
              (frame (or frame
                         (seq-find (lambda (f) (and (display-graphic-p f)
                                                    (not (frame-parent f))))
                                   (cons (selected-frame) (frame-list))))))
    (let ((pad (* columns (frame-char-width frame))))
      ;; The right one may be padded already (config/window.el, FRINGES).
      (setq-local left-fringe-width (+ (or (frame-parameter frame 'left-fringe) 8) pad)
                  right-fringe-width (max (or (frame-parameter frame 'right-fringe) 8)
                                          (+ 8 pad))))))

(defun +my/stripe--maybe-enable ()
  ;; `so-long-mode' (files with very long lines) replaces their mode and isn't
  ;; derived from any of these.
  (when (and buffer-file-name
             (derived-mode-p 'prog-mode 'text-mode 'conf-mode 'so-long-mode))
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
