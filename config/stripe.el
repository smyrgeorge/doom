;;; $DOOMDIR/config/stripe.el -*- lexical-binding: t; -*-
;; IntelliJ-like error stripe at the right edge of file windows. Loaded from
;; config.el.

;; ====== VARIABLES ======

;; ERROR STRIPE
;; A strip at the right edge of the window that maps the whole file onto the
;; window height, like the marks on IntelliJ's scrollbar:
;; - flycheck diagnostics (LSP included): red errors, yellow warnings (see
;;   `+my/stripe-diagnostic-levels');
;; - git changes (diff-hl), in the gutter's colours: red deleted, orange
;;   changed, green added;
;; - where several overlap, the most important wins, in that order
;;   (error > warning > deleted > changed > added > info);
;; - a light band marks the part of the file on screen, like a scrollbar thumb.
;; Click the strip to jump to that part of the file; the wheel scrolls as usual.
;; On in every file buffer in prog, text and conf modes (and so-long-mode).
;;
;; In graphical frames the strip is a column of small images in the right
;; margin, drawn to the pixel: each screen row shows its slice of the strip.
;; Rows are measured (an emoji makes its line taller), and smooth scrolling,
;; which moves the rows by part of a line, shifts the slices back by as much:
;; the marks stay still. In a terminal each row is a coloured cell.

(defvar +my/stripe-diagnostic-levels '(error warning)
  "Flycheck levels shown in the stripe; add `info' to also show hints.")

(defvar +my/stripe-mark-height 4
  "Minimum height of a mark, in pixels (graphical frames).")

;; Windows with the stripe may scroll past the end of the file only a bit: at
;; most this much empty space below the last line. In graphical frames the
;; strip maps the file plus this space onto the whole window height (like
;; IntelliJ's scrollbar), so it never shrinks: the marks stay put as the end
;; comes into view, and the band reaches the bottom when the window can't
;; scroll further. Below the last line it's drawn on an extra row (margins
;; need text to hang on). In a terminal it covers only the rows with text.
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
  "Bumped by edits that add or remove line breaks: they move the strings of
the strip (which hang on lines) up or down, so it must be redrawn before the
next redisplay, not after a pause.")

(defvar-local +my/stripe--number-cookie nil
  "Face remapping that keeps the filler's line-number column plain.")

(defvar +my/stripe--images (make-hash-table :test #'equal)
  "Row images by (PIXELS . WIDTH): many rows look alike.")

(defvar +my/stripe--palette nil
  "The colours of the images in `+my/stripe--images'.")

(defvar +my/stripe--rises (make-hash-table :test #'equal)
  "By (FONT . CHAR): how far the glyph rises above the font's ascent.")

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

(defun +my/stripe--kind-color (kind)
  (let ((face (cadr (alist-get kind +my/stripe--kinds))))
    (and (facep face) (face-foreground face nil t))))

(defun +my/stripe--key (window &optional start)
  "What WINDOW's stripe depends on. Edits within a line don't move it."
  (list (current-buffer)
        (or start (window-start window))
        (window-vscroll window t)       ; smooth scrolling: part of a row
        (window-body-height window t)
        (window-font-height window)
        (cdr (window-margins window))   ; reset when the buffer is shown again
        (bound-and-true-p flycheck-current-errors)
        +my/stripe--diff-hl-tick
        +my/stripe--line-edits))

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

;;; Graphical frames: images in the right margin, to the pixel

(defun +my/stripe--palette ()
  "The strip's colours by pixel character: blank, ?t the band, ?1..?6 the kinds."
  (append (list (cons ?\s "None")
                (cons ?t (+my/stripe--thumb-color)))
          (cl-loop for (kind priority) in +my/stripe--kinds
                   collect (cons (+ ?0 priority)
                                 (or (+my/stripe--kind-color kind) "None")))))

(defun +my/stripe--image (pixels width palette &optional ascent)
  "An image WIDTH pixels wide whose pixel rows have the colours of PIXELS
(a string of palette characters, one per pixel row). ASCENT as for images:
`center' by default (on the text's middle line)."
  (unless (equal palette +my/stripe--palette) ; new theme
    (setq +my/stripe--palette palette)
    (clrhash +my/stripe--images))
  (let* ((ascent (or ascent 'center))
         (key (list pixels width ascent)))
    (or (gethash key +my/stripe--images)
        (progn
          (when (>= (hash-table-count +my/stripe--images) 3000)
            (clrhash +my/stripe--images))
          (puthash
           key
           `(image :type xpm :scale 1 :ascent ,ascent
             :data ,(concat
                     "/* XPM */\nstatic char *stripe[] = {\n"
                     (format "\"%d %d %d 1\",\n" width (length pixels) (length palette))
                     (mapconcat (lambda (entry)
                                  (format "\"%c c %s\",\n" (car entry) (cdr entry)))
                                palette "")
                     (mapconcat (lambda (char) (format "\"%s\"" (make-string width char)))
                                pixels ",\n")
                     "};"))
           +my/stripe--images)))))

(defun +my/stripe--pixel-rank (char)
  "Which pixel character wins: marks by priority, then the band, then blank."
  (pcase char (?\s -1) (?t 0) (_ (- char ?0))))

(defun +my/stripe--char-rise (font char)
  "How far CHAR's glyph in FONT rises above the font's ascent, in pixels."
  (let ((key (cons font char)))
    (or (gethash key +my/stripe--rises)
        (puthash key
                 (or (ignore-errors
                       (let ((glyph (aref (font-get-glyphs font 0 1 (string char)) 0)))
                         (and glyph (max 0 (- (aref glyph 7) (aref (query-font font) 4))))))
                     0)
                 +my/stripe--rises))))

(defun +my/stripe--first-row-rise (window beg end)
  "How much taller than its text Emacs draws the window's first row, BEG to
END: the top row grows to fit glyphs that rise above the font's ascent (so
accents aren't cut off), e.g. the box-drawing bars of indent-bars."
  (let ((font (ignore-errors (font-at beg window)))
        (rise 0))
    (when font
      (save-excursion
        (goto-char beg)
        (while (< (point) end)
          (let ((display (get-char-property (point) 'display)))
            (if (stringp display)
                (dolist (char (string-to-list display))
                  (setq rise (max rise (+my/stripe--char-rise font char))))
              (setq rise (max rise (+my/stripe--char-rise font (char-after))))))
          (forward-char 1))))
    rise))

(defun +my/stripe--layout-signature ()
  "Changes when overlays that can change the rows do (folds, code lenses...):
the number of such overlays, ours left out."
  (cl-loop for ov in (overlays-in (point-min) (point-max))
           count (and (not (overlay-get ov '+my/stripe))
                      (or (overlay-get ov 'invisible)
                          (overlay-get ov 'display)
                          (overlay-get ov 'before-string)
                          (overlay-get ov 'after-string)))))

(defun +my/stripe--rows-cache (window)
  "WINDOW's rows as measured, by row start: (NEXT-ROW-START . HEIGHT). Kept
until the text, the width, the font or the folds change, so smooth scrolling
measures only the rows it brings into view."
  (let ((key (list (current-buffer) (buffer-chars-modified-tick)
                   (window-body-width window t) (window-font-height window)
                   (+my/stripe--layout-signature)))
        (cache (window-parameter window '+my/stripe-row-cache)))
    (unless (equal (car cache) key)
      (setq cache (cons key (make-hash-table :test #'eql)))
      (set-window-parameter window '+my/stripe-row-cache cache))
    (cdr cache)))

(defun +my/stripe--row (window cache beg offset font-height)
  "(NEXT-ROW-START . HEIGHT) of WINDOW's row starting at BEG; NEXT is nil at
the end of the buffer."
  (or (gethash beg cache)
      (save-excursion
        (goto-char beg)
        (let* ((more (and (= (vertical-motion 1 window) 1)
                          (> (point) beg)
                          ;; Without a final newline the end is on the last
                          ;; line (it only looks like a row of its own when
                          ;; the filler, see `+my/stripe--filler', follows).
                          (or (< (point) (point-max)) (eq (char-before) ?\n))))
               (height (- (cdr (window-text-pixel-size window beg (point) nil nil nil more))
                          offset)))
          (puthash beg (cons (and more (point)) (if (> height 0) height font-height))
                   cache)))))

(defun +my/stripe--image-rows (window start lines marks)
  "(POSITION . STRING) for WINDOW's rows from START that show part of the strip."
  (let* ((vscroll (window-vscroll window t))
         (body (window-body-height window t))
         (font-height (window-font-height window))
         (width (* (frame-char-width (window-frame window))
                   (or (cdr (window-margins window)) 1)))
         (cache (+my/stripe--rows-cache window))
         ;; `window-text-pixel-size' counts the window's vscroll; measuring
         ;; nothing gives that offset.
         (offset (cdr (window-text-pixel-size window start start nil nil nil t)))
         ;; The rows on screen: (START TOP HEIGHT IMAGE-TOP). TOP is from the top
         ;; of the text area, negative when smooth scrolling hides part of the
         ;; first row. A row's image is a line high and sits on the baseline,
         ;; at IMAGE-TOP: lower than TOP in taller rows.
         (ended nil)                    ; reached the end of the buffer
         (rows (let ((top (- vscroll)) (beg start) rows)
                 (while (and beg (< top body))
                   (pcase-let* ((`(,next . ,height) (+my/stripe--row window cache beg offset font-height))
                                (rise (if rows 0 (+my/stripe--first-row-rise
                                                  window beg (or next (point-max)))))
                                (image-top (+ top rise (max 0 (- height font-height)))))
                     (push (list beg top (+ height rise) image-top) rows)
                     (setq top (+ top height rise)
                           beg next)))
                 (setq ended (null beg))
                 (nreverse rows)))
         (last (car (last rows)))
         (text-bottom (+ (nth 1 last) (nth 2 last)))
         ;; The empty line after the final newline (where the end of the
         ;; buffer is): shown as part of the filler, not as a line of its own.
         (phantom (and ended (= (car last) (point-max)) (> (point-max) (point-min))
                       (eq (char-before (point-max)) ?\n)))
         (filler-top (if phantom (nth 1 last) text-bottom))
         ;; The strip spans the window, and maps onto it the file plus the
         ;; empty space windows may scroll past its end: so the marks don't
         ;; move as the end comes into view, and the band reaches the bottom
         ;; when the window can't scroll further.
         (height (max 1 body))
         (overscroll (let ((window-rows (window-body-height window)))
                       (if (eq +my/stripe-overscroll t)
                           (1- window-rows)
                         (- window-rows (+my/stripe--text-rows-wanted window)))))
         (scale (min (float font-height)    ; pixels per line
                     (/ (float height) (+ lines overscroll))))
         (pixels (make-string height ?\s))
         (palette (+my/stripe--palette)))
    ;; Band (when the window can scroll): from the top of the window, the
    ;; hidden part of the first row included, down by as many lines as fit.
    (when (< scale font-height)
      (let* ((first (line-number-at-pos start t))
             (top (* scale (+ (1- first) (/ (float vscroll) (nth 2 (car rows))))))
             (shown (/ (* (float body) (1+ (- (line-number-at-pos (car last) t) first)))
                       (+ text-bottom vscroll)))
             (bottom (min height (+ top (* scale shown)))))
        (cl-loop for y from (max 0 (floor top)) below (min height (max 1 (round bottom)))
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
    (set-window-parameter window '+my/stripe-geometry (list 'pixels scale lines)) ; for clicks
    (let ((click (list 'keymap +my/stripe-margin-map
                       'pointer 'hand
                       'help-echo "mouse-1: jump to this part of the file")))
      (cons
       ;; Each row's image: its slice of the strip (rows with nothing to
       ;; show get no image).
       (cl-loop for (beg _top _height image-top) in rows
                for slice = (cl-loop with slice = (make-string font-height ?\s)
                                     for i below font-height
                                     for y = (+ image-top i)
                                     when (and (>= y 0) (< y height))
                                     do (aset slice i (aref pixels y))
                                     finally return slice)
                unless (or (string-blank-p slice)
                           (and phantom (= beg (point-max)))) ; in the filler
                collect (cons beg
                              (apply #'propertize " "
                                     'display `((margin right-margin)
                                                ,(+my/stripe--image slice width palette))
                                     click)))
       ;; Below the end of the buffer: the rest of the strip.
       (when (and ended (< filler-top body))
         (+my/stripe--filler (substring pixels (max 0 filler-top))
                             (- body filler-top) width palette font-height click
                             (and phantom
                                  (if-let* ((font (ignore-errors (font-at start window))))
                                      (aref (query-font font) 4)
                                    (- font-height 4)))))))))

(defun +my/stripe--tilde (period)
  "A fringe bitmap repeating vi-tilde-fringe's `~' every PERIOD pixels (where
Emacs marks empty lines past the end), or nil."
  (when (and indicate-empty-lines (boundp 'vi-tilde-fringe-bitmap-array))
    (let ((name (intern (format "+my/stripe--tilde-%d" period))))
      (unless (fringe-bitmap-p name)
        (let* ((bits vi-tilde-fringe-bitmap-array)
               (pad (/ (- period (length bits)) 2)) ; centred, as Emacs does
               (vector (make-vector period 0)))
          (dotimes (i (length bits))
            (when (< -1 (+ pad i) period)
              (aset vector (+ pad i) (aref bits i))))
          (define-fringe-bitmap name vector period 8 '(top t)))) ; t: repeated
      name)))

(defun +my/stripe--filler (pixels height width palette font-height click &optional ascent)
  "What follows the last line: a row HEIGHT pixels high (the rest of the
window) showing PIXELS of the strip in the margin. Margins need text to hang
on, and Emacs' own empty rows past the end have none. The row repeats the
empty-line `~' too. With ASCENT (the font's), it takes the place of the empty
line after the final newline, as in Vim: then its baseline is ASCENT pixels
down, where the cursor shows if it gets there (insert state). Otherwise it
starts after the last line, and the cursor stays on that line."
  (let* ((tilde (+my/stripe--tilde font-height))
         ;; How much of the row is above the baseline, in percent.
         (above (if ascent (max 1 (min 100 (ceiling (* 100.0 ascent) height))) 100)))
    (concat (propertize " " 'cursor t) ; else Emacs puts it after the string
            (unless ascent "\n")
            (propertize " " 'display `(space :width (1) :height (,height) :ascent ,above))
            (when tilde
              ;; Emacs draws its own `~' in the fringe face (vi-tilde-fringe
              ;; doesn't give its bitmap a face).
              (propertize " " 'display `(left-fringe ,tilde fringe)))
            (unless (string-blank-p pixels)
              (apply #'propertize " "
                     'display `((margin right-margin)
                                ,(+my/stripe--image pixels width palette above))
                     click)))))

;; Like Vim, the cursor doesn't go to the empty line after the final newline
;; (it's shown as `~', part of the filler): a click below the text lands on
;; the last line, at the clicked column; `j' there stays put; `G' and the like
;; go to the last line. Insert state may go there, to add at the end.
(defvar-local +my/stripe--point-before nil "Point before the current command.")

(defun +my/stripe--note-point ()
  (setq +my/stripe--point-before (point)))

(defun +my/stripe--leave-phantom-line ()
  (when (and (eobp) (bolp) (not (bobp))
             (or (mouse-event-p last-input-event)
                 (not (memq (bound-and-true-p evil-state) '(insert replace emacs)))))
    (let ((posn (and (mouse-event-p last-input-event) (event-end last-input-event)))
          (before +my/stripe--point-before))
      (forward-line -1)
      (cond ((and posn (eq (posn-window posn) (selected-window)) (posn-x-y posn))
             ;; Clicked below the text: that column of the last line. (Posns
             ;; count y from the text; `posn-at-x-y' from the window's top.)
             (when-let* ((row (posn-at-point (point)))
                         (pos (posn-point (posn-at-x-y (car (posn-x-y posn))
                                                       (+ (cdr (posn-x-y row))
                                                          (window-tab-line-height)
                                                          (window-header-line-height))))))
               (when (<= (point) pos (line-end-position))
                 (goto-char pos)
                 ;; Normal state: on the last character, not after it.
                 (when (and (eolp) (not (bolp))
                            (memq (bound-and-true-p evil-state) '(normal motion)))
                   (backward-char)))))
            ((and before (>= before (point)) (< before (point-max)))
             (goto-char before))          ; was on the last line: stay
            (t (back-to-indentation))))))

(defun +my/stripe--plain-last-number ()
  "The filler row belongs to the last line, so with the cursor there its
line-number column would take the current line's (darker) face all the way
down: use the plain face meanwhile. The last line is usually empty, unnumbered."
  (let* ((ov (window-parameter (selected-window) '+my/stripe-filler))
         (want (and ov (eq (overlay-buffer ov) (current-buffer))
                    (overlay-get ov 'before-string)
                    (bound-and-true-p display-line-numbers)
                    (>= (point) (save-excursion (goto-char (point-max))
                                                (line-beginning-position))))))
    (cond ((and want (not +my/stripe--number-cookie))
           (setq +my/stripe--number-cookie
                 (face-remap-add-relative 'line-number-current-line 'line-number)))
          ((and (not want) +my/stripe--number-cookie)
           (face-remap-remove-relative +my/stripe--number-cookie)
           (setq +my/stripe--number-cookie nil)))))

(defun +my/stripe--hide-filler (window)
  "Take WINDOW's filler out while rows are counted or measured: Emacs counts
it as a row of the last line (`vertical-motion') and in that line's height."
  (when-let* ((ov (window-parameter window '+my/stripe-filler)))
    (when (overlay-buffer ov)
      (overlay-put ov 'before-string nil))))

(defun +my/stripe--set-filler (window string)
  "Show STRING after the end of the buffer in WINDOW (nil: nothing)."
  (let ((ov (window-parameter window '+my/stripe-filler)))
    (when (and ov (not (eq (overlay-buffer ov) (current-buffer))))
      (delete-overlay ov)
      (setq ov nil))
    (cond (string
           (unless ov
             ;; Front-advance: stays after text typed at the end.
             (setq ov (make-overlay (point-max) (point-max) nil t nil))
             (overlay-put ov 'priority 100) ; after the last row's own string
             (overlay-put ov 'window window)
             (overlay-put ov '+my/stripe t)
             (set-window-parameter window '+my/stripe-filler ov))
           (move-overlay ov (point-max) (point-max))
           (overlay-put ov 'before-string string))
          (ov
           (delete-overlay ov)
           (set-window-parameter window '+my/stripe-filler nil)))))

;;; Drawing

(defun +my/stripe--render (window &optional start)
  "Redraw the stripe of WINDOW, whose text starts at START."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      ;; Runs from redisplay hooks: never let an error escape into them.
      (with-demoted-errors "Stripe: %S"
        (when (bound-and-true-p +my/stripe-mode)
          (set-window-parameter window '+my/stripe-key (+my/stripe--key window start))
          (pcase-let* ((`(,lines . ,marks) (+my/stripe--marks))
                       (start (or start (window-start window)))
                       (`(,strings . ,filler)
                        (if (display-graphic-p (window-frame window))
                            (progn
                              (when (and +my/stripe-padding (null left-fringe-width))
                                (+my/stripe--pad (window-frame window))
                                (+my/stripe--set-fringes window))
                              (+my/stripe--hide-filler window)
                              (+my/stripe--image-rows window start lines marks))
                          (list (+my/stripe--cell-rows window start lines marks))))
                       (old nil))
            ;; Reuse this window's row overlays; drop those of windows that
            ;; no longer show this buffer. Found by their property, not kept
            ;; in a variable: reverting the buffer would lose track of them.
            (dolist (ov (overlays-in (point-min) (point-max)))
              (when (overlay-get ov '+my/stripe-row)
                (let ((win (overlay-get ov 'window)))
                  (cond ((eq win window) (push ov old))
                        ((or (not (window-live-p win))
                             (not (eq (window-buffer win) (current-buffer))))
                         (delete-overlay ov))))))
            (pcase-dolist (`(,pos . ,string) strings)
              (let* ((at (+my/stripe--anchor window pos))
                     (ov (or (pop old) (make-overlay at at))))
                (move-overlay ov at at)
                (overlay-put ov '+my/stripe t)
                (overlay-put ov '+my/stripe-row t)
                (overlay-put ov 'window window)
                (overlay-put ov 'before-string string)))
            (mapc #'delete-overlay old)
            (+my/stripe--set-filler window filler)
            (when (eq window (selected-window))
              (+my/stripe--plain-last-number))))))))

(defun +my/stripe--anchor (window pos)
  "Where to hang the string of WINDOW's row starting at POS. A row that starts
a line: there. A row that continues a wrapped line (visual-line-mode, e.g.
Markdown): on its last character (the space it wraps at, or the newline).
Laying out the row before, Emacs looks ahead into this row's first word to
see whether it fits, and draws a margin string it meets there on that row
too: hung at the start of the row (or just after) the slice showed on the row
before, or on both."
  (if (or (= pos (point-min)) (eq (char-before pos) ?\n))
      pos
    (let ((next (or (car (gethash pos (+my/stripe--rows-cache window)))
                    (save-excursion
                      (goto-char pos)
                      (and (= (vertical-motion 1 window) 1) (point))))))
      (cond ((null next) (point-max))   ; the last row
            ((> next (1+ pos)) (1- next))
            (t pos)))))

(defun +my/stripe--note-line-edit (beg end &rest _)
  "Before/after a change: count it if BEG..END holds a line break, i.e. lines
are being removed (before) or added (after)."
  (when (and (< beg end)
             (save-excursion (goto-char beg) (search-forward "\n" end t)))
    (cl-incf +my/stripe--line-edits)))

(defun +my/stripe--render-all ()
  "Redraw the stripe in every window (e.g. after a theme change)."
  (dolist (window (window-list-1 nil 'nomini t))
    (+my/stripe--render window)))

;;; Scrolling past the end

(defun +my/stripe--text-rows-wanted (window)
  "How many of WINDOW's rows must show text: all but the allowed overscroll."
  (let ((rows (window-body-height window)))
    (max 1 (- rows (if (floatp +my/stripe-overscroll)
                       (floor (* rows +my/stripe-overscroll))
                     +my/stripe-overscroll)))))

(defun +my/stripe--past-end-p (window)
  "Non-nil if WINDOW shows more empty rows below the end than allowed."
  ;; N rows of text = the first line plus N - 1 more; smooth scrolling (a
  ;; fraction of the first row hidden above) needs one more.
  (let ((more (+ (1- (+my/stripe--text-rows-wanted window))
                 (if (> (window-vscroll window t) 0) 1 0))))
    ;; Each line takes at least a row: enough lines left settles it fast
    ;; (`vertical-motion' is slow, and this runs as windows scroll).
    (save-excursion
      (goto-char (window-start window))
      (and (progn (forward-line more) (eobp))
           (progn (goto-char (window-start window))
                  (< (vertical-motion more window) more))))))

(defun +my/stripe--clamp-start (window)
  "Scroll WINDOW back so it doesn't show more empty rows past the end than allowed."
  (when (and (not (eq +my/stripe-overscroll t))
             (or (> (window-start window) (point-min))
                 (> (window-vscroll window t) 0))
             (+my/stripe--past-end-p window))
    (let ((start (save-excursion
                   (goto-char (point-max))
                   (vertical-motion (- 1 (+my/stripe--text-rows-wanted window)) window)
                   (point))))
      (when (or (< start (window-start window))
                (and (= start (window-start window))
                     (> (window-vscroll window t) 0)))
        (set-window-start window start t)
        (set-window-vscroll window 0 t)))))

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
        ;; this frame is drawn, then redraw the strip (and the filler).
        (+my/stripe--hide-filler window)
        (+my/stripe--clamp-start window)
        (+my/stripe--render window)))))

(defun +my/stripe--after-scroll (window start)
  "When redisplay itself scrolled WINDOW (e.g. to follow the cursor), maybe past
the end, check it right after (the filler can't be taken out mid-redisplay)."
  (when (and (not (eq +my/stripe-overscroll t))
             (window-live-p window)
             (<= (count-lines start (point-max)) (window-body-height window)))
    (run-at-time 0 nil (lambda ()
                         (when (window-live-p window)
                           (with-current-buffer (window-buffer window)
                             (when (bound-and-true-p +my/stripe-mode)
                               (+my/stripe--hide-filler window)
                               (+my/stripe--clamp-start window)
                               ;; Redraw before the next frame (filler too).
                               (set-window-parameter window '+my/stripe-key nil))))))))

(add-hook 'pre-redisplay-functions #'+my/stripe--pre-redisplay)

;;; Clicks

(defun +my/stripe-jump (event)
  "Jump to the part of the file at the clicked spot of the stripe."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (geometry (and (window-live-p window)
                        (window-parameter window '+my/stripe-geometry))))
    (when geometry
      (select-window window)
      (let ((line (pcase geometry
                    ;; Images: the clicked pixel (y from the top of the text).
                    (`(pixels ,scale ,lines)
                     (when-let* ((y (cdr (posn-x-y posn))))
                       (max 1 (min lines (1+ (floor (/ y scale)))))))
                    ;; Cells: the middle of the clicked row's lines.
                    (`(cells ,rows ,lines)
                     (when-let* ((string (posn-string posn))
                                 (row (get-text-property (or (cdr string) 0)
                                                         '+my/stripe-row (car string))))
                       (+my/stripe--row-to-line row lines rows))))))
        (when line
          (when (fboundp 'better-jumper-set-jump)
            (better-jumper-set-jump))
          (goto-char (point-min))
          (forward-line (1- line))
          (recenter))))))

;;; Modes

(define-minor-mode +my/stripe-mode
  "IntelliJ-like stripe of git changes and diagnostics at the right edge."
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
        (setq-local right-margin-width 1)
        ;; Scrolls that redisplay itself decides on (point left the window);
        ;; everything else is caught by `+my/stripe--pre-redisplay'.
        (add-hook 'window-scroll-functions #'+my/stripe--render nil t)
        (add-hook 'window-scroll-functions #'+my/stripe--after-scroll nil t)
        (add-hook 'before-change-functions #'+my/stripe--note-line-edit nil t)
        (add-hook 'after-change-functions #'+my/stripe--note-line-edit nil t)
        (add-hook 'post-command-hook #'+my/stripe--plain-last-number nil t)
        (add-hook 'pre-command-hook #'+my/stripe--note-point nil t)
        (add-hook 'post-command-hook #'+my/stripe--leave-phantom-line nil t)
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
    (remove-hook 'window-scroll-functions #'+my/stripe--render t)
    (remove-hook 'window-scroll-functions #'+my/stripe--after-scroll t)
    (remove-hook 'before-change-functions #'+my/stripe--note-line-edit t)
    (remove-hook 'after-change-functions #'+my/stripe--note-line-edit t)
    (remove-hook 'post-command-hook #'+my/stripe--plain-last-number t)
    (remove-hook 'pre-command-hook #'+my/stripe--note-point t)
    (remove-hook 'post-command-hook #'+my/stripe--leave-phantom-line t)
    (when +my/stripe--number-cookie
      (face-remap-remove-relative +my/stripe--number-cookie)
      (setq +my/stripe--number-cookie nil))
    (kill-local-variable 'right-margin-width)
    (kill-local-variable 'fringes-outside-margins)
    (kill-local-variable 'left-fringe-width)
    (kill-local-variable 'right-fringe-width)
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-margins window (car (window-margins window)) nil)
      (+my/stripe--set-fringes window))))

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
