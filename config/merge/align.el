;;; $DOOMDIR/config/merge/align.el -*- lexical-binding: t; -*-
;; Panes lined up, numbered, scrolling together. Loaded from config/merge.el.

;; LINING UP
;; Each change takes as many rows in each pane: after it, the shorter ones get
;; filler lines (the most of the three, less their own). They're text, so that
;; any row can be scrolled to (a window can't start inside an overlay's
;; string, which can't be scrolled into either): newlines marked
;; `+my/merge-filler', read-only, skipped by the cursor, left out of what's
;; saved or copied. In the Result, they're made again after each command that
;; changed it, in the same step of its undo.
(defvar-local +my/merge--dirty nil
  "Non-nil if the pane changed since its fillers were made.")

(defun +my/merge--filler (n)
  "N filler lines."
  (propertize (make-string n ?\n)
              '+my/merge-filler t 'face '+my/merge-filler 'read-only t
              'cursor-intangible t 'rear-nonsticky t))

(defun +my/merge--height (ov)
  "The lines of OV's region (a last one without its newline counts)."
  (with-current-buffer (overlay-buffer ov)
    (count-lines (overlay-start ov) (overlay-end ov))))

(defun +my/merge--fillers-at (pos)
  "The end of the fillers at POS in the current buffer (POS if none)."
  (if (and (< pos (point-max)) (get-text-property pos '+my/merge-filler))
      (next-single-property-change pos '+my/merge-filler nil (point-max))
    pos))

(defun +my/merge--fill (ov n)
  "N filler lines after OV's region, in its buffer."
  (with-current-buffer (overlay-buffer ov)
    (let* ((pos (overlay-end ov))
           (end (+my/merge--fillers-at pos))
           (have (- end pos)))
      (unless (= have n)
        (let ((inhibit-read-only t)
              (+my/merge--aligning t))
          (save-excursion
            (if (> have n)
                (delete-region (+ pos n) end)
              (goto-char end)
              (insert (+my/merge--filler (- n have))))))))))

(defun +my/merge--align (session)
  "Line SESSION's panes up (see above)."
  (seq-doseq (chunk (+my/merge-chunks session))
    (let* ((sides (list (+my/merge-chunk-yours chunk) (+my/merge-chunk-result chunk)
                        (+my/merge-chunk-theirs chunk)))
           (heights (mapcar #'+my/merge--height sides))
           (most (apply #'max heights)))
      (cl-mapc (lambda (ov height) (+my/merge--fill ov (- most height)))
               sides heights)))
  (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
    (with-current-buffer buffer
      (setq +my/merge--dirty nil)))
  (+my/merge--renumber session))

(defun +my/merge--changed-h (&rest _)
  "The pane changed: its fillers made again after this command."
  (unless +my/merge--aligning
    (setq +my/merge--dirty t)))

(defun +my/merge--post-command-h ()
  "After a command that changed the Result (an edit, an undo): its changes'
regions where their markers are (see THE RESULT'S REGIONS, changes.el), the
panes lined up again, the changes it made done or not done shown so."
  (when-let* ((session +my/merge--session)
              ((not (+my/merge-finished session)))
              ((buffer-live-p (+my/merge-result session)))
              ((buffer-local-value '+my/merge--dirty (+my/merge-result session))))
    (with-current-buffer (+my/merge-result session)
      (seq-doseq (chunk (+my/merge-chunks session))
        (+my/merge--sync chunk))
      (+my/merge--align session)
      (+my/merge--even-rows session)
      (+my/merge--render-edited session))))

(defun +my/merge--clean (start end)
  "The text from START to END of the current buffer, without fillers."
  (let ((pos start)
        (parts nil))
    (while (< pos end)
      (let ((next (min end (next-single-property-change pos '+my/merge-filler nil end))))
        (unless (get-text-property pos '+my/merge-filler)
          (push (buffer-substring-no-properties pos next) parts))
        (setq pos next)))
    (apply #'concat (nreverse parts))))

(defun +my/merge--filter-substring (beg end &optional delete)
  "`filter-buffer-substring-function' of the panes: copies without fillers."
  (prog1 (+my/merge--clean beg end)
    (when delete
      (delete-region beg end))))

;; ROWS AS TALL
;; In the GUI a row holding an emoji (another font's glyphs) is taller than
;; the others: the rows below it in its pane drifted from the other panes'.
;; Each row taller in one pane than in another is made as tall in all three
;; (a `line-height' on its newline, an overlay's): the rows at the same pixel
;; y in the three. Only the rows holding a character past U+2000 (emoji,
;; symbols, CJK...) are measured; again once the Result changed.
(defvar-local +my/merge--tall-rows nil
  "The overlays making the pane's rows as tall as the other panes'.")

(defconst +my/merge--maybe-tall "[\u2000-\U0010FFFF]"
  "A character that may make its row taller than the default font's.")

(defvar-local +my/merge--row-heights nil
  "The pane's rows' heights measured, by their text (a hash table): each
measured once, not after each edit of the Result.")

(defun +my/merge--row-height (window line)
  "The height in pixels of row LINE (from 1) of WINDOW's buffer, nil if it
has none."
  (save-excursion
    (goto-char (point-min))
    (when (zerop (forward-line (1- line)))
      (let ((text (buffer-substring-no-properties (point) (line-end-position))))
        (unless +my/merge--row-heights
          (setq +my/merge--row-heights (make-hash-table :test #'equal)))
        (or (gethash text +my/merge--row-heights)
            (puthash text (cdr (window-text-pixel-size window (point) (line-end-position)))
                     +my/merge--row-heights))))))

(defun +my/merge--even-rows (session)
  "SESSION's panes' rows as tall in the three (see above), in the GUI."
  (let* ((buffers (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
         (windows (mapcar (lambda (buffer) (get-buffer-window buffer (+my/merge-frame session))) buffers))
         (lines nil))
    (when (and (seq-every-p #'identity windows)
               (display-graphic-p (window-frame (car windows))))
      ;; The rows holding one (by number: the same row in the three), the
      ;; heights made before forgotten.
      (dolist (buffer buffers)
        (with-current-buffer buffer
          (mapc #'delete-overlay +my/merge--tall-rows)
          (setq +my/merge--tall-rows nil)
          (save-excursion
            (goto-char (point-min))
            (let ((line 1))
              (while (not (eobp))
                (when (re-search-forward +my/merge--maybe-tall (line-end-position) t)
                  (push line lines))
                (forward-line 1)
                (cl-incf line))))))
      (dolist (line (delete-dups lines))
        (let* ((heights (cl-mapcar (lambda (buffer window)
                                     (with-current-buffer buffer (+my/merge--row-height window line)))
                                   buffers windows))
               (most (apply #'max (mapcar (lambda (height) (or height 0)) heights))))
          (cl-mapc (lambda (buffer height)
                     (when (and height (< height most))
                       (with-current-buffer buffer
                         (save-excursion
                           (goto-char (point-min))
                           (forward-line (1- line))
                           (let ((end (line-end-position)))
                             (when (< end (point-max))
                               (let ((ov (make-overlay end (1+ end))))
                                 (overlay-put ov 'line-height most)
                                 (push ov +my/merge--tall-rows))))))))
                   buffers heights))))))

;; LINE NUMBERS
;; Each pane's lines numbered as in its version, as Doom numbers a file's:
;; Emacs's own (`display-line-numbers-mode') would count the fillers. A
;; `line-prefix' on each line with its number (blank on fillers), put by
;; jit-lock on what's shown, the same width in the three; the current line's
;; in `line-number-current-line', by an overlay of its window's. The Result's
;; numbered again when an edit changed its lines. Copies and the saved file
;; are without them (`+my/merge--clean' takes no properties).
(defvar-local +my/merge--number-width 3
  "Digits of the panes' line numbers (the same in the three).")

(defvar-local +my/merge--number-lines nil
  "The pane's line count when it was last numbered.")

(defvar-local +my/merge--current-numbers nil
  "((WINDOW . OVERLAY)...): the current line's number in each window.")

(defun +my/merge--fillers-before (pos)
  "How many filler lines there are before POS (each a newline)."
  (let ((n 0)
        (p (point-min)))
    (while (< p pos)
      (let ((next (next-single-property-change p '+my/merge-filler nil pos)))
        (when (get-text-property p '+my/merge-filler)
          (cl-incf n (- next p)))
        (setq p next)))
    n))

(defun +my/merge--line-at (pos)
  "The number, in the pane's version, of POS's line; on a filler, of the next
line that isn't one."
  (save-excursion
    (goto-char pos)
    (forward-line 0)
    (- (line-number-at-pos) (+my/merge--fillers-before (point)))))

(defun +my/merge--number-string (n face)
  "Line number N as a line prefix, in FACE (N nil: blank, a filler's)."
  (let ((width +my/merge--number-width))
    (if n
        (propertize (format (format " %%%dd " width) n) 'face face)
      (make-string (+ width 2) ?\s))))

(defun +my/merge--number (start end)
  "Number the lines from START to END (jit-lock's, see above)."
  (save-excursion
    (goto-char start)
    (forward-line 0)
    (let ((from (point))
          (n (+my/merge--line-at (point))))
      (with-silent-modifications
        (while (and (< (point) end) (not (eobp)))
          (let ((bol (point))
                (next (line-beginning-position 2)))
            (if (get-text-property bol '+my/merge-filler)
                (put-text-property bol next 'line-prefix (+my/merge--number-string nil nil))
              (put-text-property bol next 'line-prefix (+my/merge--number-string n 'line-number))
              (cl-incf n))
            (goto-char next))))
      `(jit-lock-bounds ,from . ,(point)))))

(defun +my/merge--renumber (session)
  "SESSION's panes numbered again where needed: the width, the same in the
three, changed (all of them); a pane's lines did (that pane, from the top)."
  (let* ((panes (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
         (lines (mapcar (lambda (buffer) (with-current-buffer buffer (+my/merge--line-at (point-max))))
                        panes))
         (width (max 3 (length (number-to-string (apply #'max lines))))))
    (cl-mapc (lambda (buffer count)
               (with-current-buffer buffer
                 (unless (and (eql count +my/merge--number-lines) (eql width +my/merge--number-width))
                   (setq +my/merge--number-lines count
                         +my/merge--number-width width)
                   (jit-lock-refontify))))
             panes lines)))

(defun +my/merge--current-number-h (&optional window)
  "Before a redisplay: the current line's number in WINDOW (a pane's), in
`line-number-current-line', above the one jit-lock put (see above)."
  (dolist (window (if window (list window) (window-list nil 'nomini)))
    (when-let* (((window-live-p window))
                (buffer (window-buffer window))
                (session (buffer-local-value '+my/merge--session buffer))
                ((not (+my/merge-finished session)))
                ((memq buffer (list (+my/merge-yours session) (+my/merge-result session)
                                    (+my/merge-theirs session)))))
      (with-current-buffer buffer
        (let* ((bol (save-excursion (goto-char (window-point window)) (line-beginning-position)))
               (eol (save-excursion (goto-char bol) (line-beginning-position 2)))
               (entry (assq window +my/merge--current-numbers))
               (ov (cdr entry))
               (key (list bol (buffer-modified-tick) +my/merge--number-width)))
          (unless (and ov (overlay-buffer ov) (equal (overlay-get ov '+my/merge-key) key))
            (unless (and ov (overlay-buffer ov))
              (setq ov (make-overlay bol eol))
              (overlay-put ov 'window window)
              ;; Above hl-line's (which copies the line's prefix in its face).
              (overlay-put ov 'priority 1)
              (setf (alist-get window +my/merge--current-numbers) ov))
            (move-overlay ov bol eol)
            (overlay-put ov '+my/merge-key key)
            (overlay-put ov 'line-prefix
                         (and (< bol eol) (not (get-text-property bol '+my/merge-filler))
                              (+my/merge--number-string (+my/merge--line-at bol)
                                                        'line-number-current-line)))))))))

(add-hook 'pre-redisplay-functions #'+my/merge--current-number-h)

;; SCROLLING TOGETHER
;; Lined up, the panes' rows are their lines: the pane scrolled (its first
;; line, the pixels of it scrolled off, its columns scrolled sideways) gives
;; the others theirs, before each redisplay; so whatever scrolled it: keys, the
;; wheel, the trackpad, a glide of config/editor/smooth.el's (its frames are
;; timers, each followed by a redisplay).
(defun +my/merge--view (window)
  "WINDOW's view: (FIRST-LINE VSCROLL HSCROLL)."
  (list (with-current-buffer (window-buffer window)
          (line-number-at-pos (window-start window)))
        (window-vscroll window t)
        (window-hscroll window)))

(defun +my/merge--sync-h (&optional window)
  "Before a redisplay: a pane that scrolled scrolls the others (see above)."
  (dolist (window (if window (list window) (window-list nil 'nomini)))
    (when-let* ((session (and (window-live-p window)
                              (buffer-local-value '+my/merge--session (window-buffer window))))
                ((not (+my/merge-finished session)))
                ((not (eq (window-buffer window) (+my/merge-bar session))))
                (view (+my/merge--view window))
                ((not (equal view (window-parameter window '+my/merge-view)))))
      (pcase-let ((`(,line ,vscroll ,hscroll) view))
        (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session)
                              (+my/merge-theirs session)))
          (dolist (other (get-buffer-window-list buffer 'nomini))
            (unless (eq other window)
              (set-window-start other (with-current-buffer buffer
                                        (save-excursion
                                          (goto-char (point-min))
                                          (forward-line (1- line))
                                          (point))))
              ;; Kept through redisplay (as ultra-scroll does), and point off
              ;; a first line scrolled partly off: redisplay would scroll
              ;; back to show it.
              (set-window-vscroll other vscroll t t)
              (when (> vscroll 0)
                (let ((second (with-current-buffer buffer
                                (save-excursion
                                  (goto-char (window-start other))
                                  (forward-line 1)
                                  (point)))))
                  (when (< (window-point other) second)
                    (set-window-point other second))))
              (set-window-hscroll other hscroll)
              (set-window-parameter other '+my/merge-view (+my/merge--view other)))))
        (set-window-parameter window '+my/merge-view view)))))

(add-hook 'pre-redisplay-functions #'+my/merge--sync-h)
