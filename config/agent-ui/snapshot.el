;;; $DOOMDIR/config/agent-ui/snapshot.el -*- lexical-binding: t; -*-
;; Agent UI's elements in the conversation. Loaded from config/agent-ui.el.
;;
;; agent-shell owns its buffer's text, so an element isn't put there: it goes
;; the ways agent-shell already has.
;; - From the agent: `agent-ui snapshot ID' saves the element as it's drawn,
;;   without its buttons (they'd do nothing in an image: they stay on the
;;   canvas), an SVG image (its text in its colours, a chart's own SVG), in the
;;   session's .agent-shell/images/, and replies with a Markdown image link
;;   for its reply: agent-shell shows it inline, and its transcript keeps it.
;; - From you: a in a canvas puts the element at point into its session's
;;   prompt, as text the agent reads (`agent-ui-send-element').
;; No Doom here.

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'mailcap)
(require 'color)

;; ====== VARIABLES ======

(defcustom agent-ui-snapshot-directory ".agent-shell/images/"
  "Where snapshots go, relative to the agent's directory (agent-shell's
transcripts' folder, kept out of git)."
  :type 'string :group 'agent-ui)

(defcustom agent-ui-snapshot-width 80
  "The width snapshots are drawn at, in columns, at most: narrower to fit
their session's window (`agent-ui-snapshot--width')."
  :type 'natnum :group 'agent-ui)

;; ====== TEXT AS SVG ======

(defun agent-ui-snapshot--color (face attribute fallback)
  "FACE's ATTRIBUTE (:foreground, :background) as a colour, FACE a face, a
list of them or a plist; FALLBACK where it has none."
  (let ((color (cond
                ((null face) nil)
                ((and (symbolp face) (facep face)) (face-attribute face attribute nil t))
                ((and (consp face) (keywordp (car face))) (plist-get face attribute))
                ((consp face) (seq-some (lambda (f) (let ((c (agent-ui-snapshot--color f attribute nil)))
                                                      (and c (not (equal c fallback)) c)))
                                        face)))))
    (if (and (stringp color) (not (string-prefix-p "unspecified" color)))
        color
      fallback)))

(defun agent-ui-snapshot--bold-p (face)
  (cond ((null face) nil)
        ((and (symbolp face) (facep face)) (memq (face-attribute face :weight nil t) '(bold semi-bold extra-bold ultra-bold)))
        ((and (consp face) (keywordp (car face))) (memq (plist-get face :weight) '(bold semi-bold)))
        ((consp face) (seq-some #'agent-ui-snapshot--bold-p face))))

(defun agent-ui-snapshot--runs (line)
  "LINE's runs of the same face: (TEXT . FACE)."
  (let ((pos 0) (runs nil))
    (while (< pos (length line))
      (let ((next (or (next-single-property-change pos 'face line) (length line))))
        (push (cons (substring-no-properties line pos next) (get-text-property pos 'face line)) runs)
        (setq pos next)))
    (nreverse runs)))

(defconst agent-ui-snapshot--blocks
  '((?█ . 1.0) (?▉ . 0.875) (?▊ . 0.75) (?▋ . 0.625) (?▌ . 0.5) (?▍ . 0.375) (?▎ . 0.25) (?▏ . 0.125))
  "Block characters (a bar's), drawn as rectangles: glyphs leave gaps.")

(defconst agent-ui-snapshot--lines
  '((?─ . (left right)) (?│ . (up down)) (?┼ . (up down left right))
    (?├ . (up down right)) (?┤ . (up down left)) (?┬ . (down left right)) (?┴ . (up left right))
    (?┌ . (down right)) (?┐ . (down left)) (?└ . (up right)) (?┘ . (up left))
    (?╴ . (left)) (?╵ . (up)) (?╶ . (right)) (?╷ . (down))
    (?╭ . (curve down right)) (?╮ . (curve down left)) (?╰ . (curve up right)) (?╯ . (curve up left)))
  "Box-drawing characters (borders', tables', axes'), drawn as lines from
their cell's centre to its sides: a font's glyphs fall short of the line's
height, leaving gaps between lines, and a run of them drifts off the
columns. A corner with curve: a quarter curve between its two sides.")

(defun agent-ui-snapshot--line-path (char col y cw lh &optional height)
  "CHAR's (in `agent-ui-snapshot--lines') lines in column COL of the line
at Y: SVG path data. Its vertical ones as long as the line's HEIGHT
\(default LH: taller beside an image), its horizontal ones at LH's middle."
  (let* ((sides (cdr (assq char agent-ui-snapshot--lines)))
         (x0 (+ cw (* col cw)))
         (cx (+ x0 (/ cw 2.0)))
         (cy (+ y (/ lh 2.0)))
         (ends `((up ,cx ,y) (down ,cx ,(+ y (or height lh))) (left ,x0 ,cy) (right ,(+ x0 cw) ,cy))))
    (if (eq (car sides) 'curve)
        (pcase-let ((`(,_ ,ax ,ay) (assq (nth 1 sides) ends))
                    (`(,_ ,bx ,by) (assq (nth 2 sides) ends)))
          (format "M%.1f %.1fQ%.1f %.1f %.1f %.1f" ax ay cx cy bx by))
      (mapconcat (lambda (side)
                   (pcase-let ((`(,_ ,x ,y) (assq side ends)))
                     (format "M%.1f %.1fL%.1f %.1f" cx cy x y)))
                 sides ""))))

(defun agent-ui-snapshot--run (text col y color bold cw lh &optional height)
  "TEXT, a run in COLOR from column COL on the line at Y, as SVG: its block
characters as rectangles (full ones joined), ░ a faint cell, its
box-drawing ones as lines (`agent-ui-snapshot--lines', down to the line's
HEIGHT), the rest text."
  (let ((parts nil) (pending "") (pending-col col) (bar-start nil) (bar-cells 0) (lines ""))
    (cl-flet ((flush-text ()
                ;; Word by word, each at its column: no viewer's way with
                ;; spaces (some collapse them) moves anything.
                (let ((start 0) (column pending-col))
                  (while (string-match "[^ ]+" pending start)
                    ;; Its bounds first: escaping it changes the match data.
                    (let* ((word-start (match-beginning 0))
                           (word-end (match-end 0))
                           (word (substring pending word-start word-end)))
                      (cl-incf column (string-width (substring pending start word-start)))
                      ;; Its cells' width exactly: a font's glyphs a little
                      ;; wider than the cells would push a long run (a
                      ;; border's) past its end.
                      (push (format "<text x=\"%d\" y=\"%d\" fill=\"%s\"%s%s>%s</text>"
                                    (+ cw (* column cw)) (+ y (round (* 0.78 lh))) color
                                    (if (> (string-width word) 1)
                                        (format " textLength=\"%d\" lengthAdjust=\"spacingAndGlyphs\""
                                                (* cw (string-width word)))
                                      "")
                                    (if bold " font-weight=\"bold\"" "") (xml-escape-string word))
                            parts)
                      (cl-incf column (string-width word))
                      (setq start word-end))))
                (setq pending ""))
              (flush-bar ()
                (when bar-start
                  (push (format "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"%s\"/>"
                                (+ cw (* bar-start cw)) (+ y (round (* 0.15 lh))) (* bar-cells cw)
                                (round (* 0.7 lh)) color)
                        parts)
                  (setq bar-start nil bar-cells 0))))
      (dolist (c (string-to-list text))
        (let ((block (cdr (assq c agent-ui-snapshot--blocks))))
          (cond
           ((eql block 1.0)
            (flush-text)
            (unless bar-start (setq bar-start col))
            (cl-incf bar-cells))
           (block
            (flush-text) (flush-bar)
            (push (format "<rect x=\"%d\" y=\"%d\" width=\"%.1f\" height=\"%d\" fill=\"%s\"/>"
                          (+ cw (* col cw)) (+ y (round (* 0.15 lh))) (* block cw) (round (* 0.7 lh)) color)
                  parts))
           ((assq c agent-ui-snapshot--lines)
            (flush-text) (flush-bar)
            (setq lines (concat lines (agent-ui-snapshot--line-path c col y cw lh height))))
           ((eq c ?░)
            (flush-text) (flush-bar)
            (push (format "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"%s\" fill-opacity=\"0.25\"/>"
                          (+ cw (* col cw)) (+ y (round (* 0.15 lh))) cw (round (* 0.7 lh)) color)
                  parts))
           (t
            (flush-bar)
            (when (string-empty-p pending) (setq pending-col col))
            (setq pending (concat pending (string c))))))
        (cl-incf col (char-width c)))
      (flush-text)
      (flush-bar)
      (unless (string-empty-p lines)
        (push (format "<path d=\"%s\" stroke=\"%s\" stroke-width=\"1\" fill=\"none\"/>" lines color)
              parts)))
    (string-join (nreverse parts))))

(defun agent-ui-snapshot--svg-size (data)
  "The width and height an SVG's DATA says: (W . H)."
  (when (string-match "<svg[^>]*\\bwidth=\"\\([0-9.]+\\)\"[^>]*\\bheight=\"\\([0-9.]+\\)\"" data)
    (cons (string-to-number (match-string 1 data)) (string-to-number (match-string 2 data)))))

(defun agent-ui-snapshot--image-file (display)
  "An image DISPLAY from a file (an image element's) as an SVG <image> at its
shown size: (SVG . (W . H)); nil if it isn't one, or its size can't be had."
  (let* ((props (cdr display))
         (file (plist-get props :file))
         (size (and file (file-readable-p file) (display-graphic-p)
                    (ignore-errors (image-size display t)))))
    (when size
      (let ((mime (or (cdr (assoc (downcase (or (file-name-extension file) ""))
                                  '(("svg" . "image/svg+xml") ("png" . "image/png") ("jpg" . "image/jpeg")
                                    ("jpeg" . "image/jpeg") ("gif" . "image/gif") ("webp" . "image/webp"))))
                      (mailcap-file-name-to-mime-type file)
                      "image/png")))
        (cons (format "<image width=\"%d\" height=\"%d\" href=\"data:%s;base64,%s\"/>"
                      (car size) (cdr size) mime
                      (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally file)
                        (base64-encode-region (point-min) (point-max) t)
                        (buffer-string)))
              size)))))

(defun agent-ui-snapshot--line-height (line lh)
  "How high LINE is drawn: LH, or its tallest image's height."
  (let ((height lh) (pos 0))
    (while (< pos (length line))
      (let ((display (get-text-property pos 'display line)))
        ;; A slice of an image (a tall one in a bordered panel): its height.
        (pcase display
          (`((slice ,_ ,_ ,_ ,h) . ,_) (setq height (max height (round h)))))
        (when (eq (car-safe display) 'image)
          (let ((size (if-let* ((data (plist-get (cdr display) :data)))
                          (agent-ui-snapshot--svg-size data)
                        (and (display-graphic-p) (ignore-errors (image-size display t))))))
            (when size (setq height (max height (round (cdr size))))))))
      (setq pos (or (next-single-property-change pos 'display line) (length line))))
    height))

(defun agent-ui-snapshot-svg (text ctx)
  "TEXT, an element's drawing, as an SVG document (a string): each line in
its faces' colours, on the theme's background; a line that's an SVG image (a
chart's) that image. CTX: its :width (columns), :char-width, :line-height."
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (fg (agent-ui-snapshot--color 'default :foreground "#bbc2cf"))
         (bg (agent-ui-snapshot--color 'default :background "#282c34"))
         (family (let ((f (face-attribute 'default :family nil t)))
                   (if (and (stringp f) (not (member f '("default" "unspecified")))) f "monospace")))
         (pad cw)
         (y pad)
         (width (+ (* 2 pad) (* cw (max 1 (apply #'max (mapcar #'string-width (split-string text "\n")))))))
         (parts nil))
    (dolist (line (split-string text "\n"))
      ;; A line's parts, an image's (a chart's SVG, nested; an image file's,
      ;; embedded) or text's, each at its column: an image in a bordered
      ;; panel's line is where it's shown, beside the border.
      (let ((col 0) (height (agent-ui-snapshot--line-height line lh)) (pos 0) (spans nil))
        (while (< pos (length line))
          (let* ((next (or (next-single-property-change pos 'display line) (length line)))
                 (display (get-text-property pos 'display line))
                 (image (eq (car-safe display) 'image))
                 (data (and image (eq (plist-get (cdr display) :type) 'svg) (plist-get (cdr display) :data)))
                 (size (and data (agent-ui-snapshot--svg-size data)))
                 (file (and image (not data) (agent-ui-snapshot--image-file display)))
                 (x (+ pad (* col cw))))
            (cond
             ;; A slice of an SVG: the SVG in a box of the slice's size,
             ;; moved up to it (a box clips what's outside it).
             ((and (eq (car-safe (car-safe display)) 'slice)
                   (eq (plist-get (cdr (cadr display)) :type) 'svg))
              (pcase-let ((`(slice ,sx ,sy ,sw ,sh) (car display)))
                (push (format "<svg x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\"><g transform=\"translate(%d %d)\">%s</g></svg>"
                              x y sw sh (- sx) (- sy) (plist-get (cdr (cadr display)) :data))
                      spans)
                (cl-incf col (ceiling sw cw))))
             (size
              (push (replace-regexp-in-string "\\`<svg " (format "<svg x=\"%d\" y=\"%d\" " x y) data) spans)
              (cl-incf col (ceiling (car size) cw)))
             (file
              (push (format "<g transform=\"translate(%d %d)\">%s</g>" x y (car file)) spans)
              (cl-incf col (ceiling (cadr file) cw)))
             ;; A filler after an image, to its last column's end (a
             ;; panel's): counted in the image's columns already.
             ((eq (car-safe display) 'space))
             (t
              (dolist (run (agent-ui-snapshot--runs (substring line pos next)))
                ;; A run on a colour of its own (a GUI bar's): that colour.
                (let ((back (agent-ui-snapshot--color (cdr run) :background nil)))
                  (when (and back (not (equal back bg)))
                    (push (format "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"%s\"/>"
                                  (+ pad (* col cw)) (+ y (round (* 0.15 lh)))
                                  (* cw (string-width (car run))) (round (* 0.7 lh)) back)
                          spans)))
                (push (agent-ui-snapshot--run (car run) col y
                                              (agent-ui-snapshot--color (cdr run) :foreground fg)
                                              (agent-ui-snapshot--bold-p (cdr run)) cw lh height)
                      spans)
                (cl-incf col (string-width (car run))))))
            (setq pos next)))
        (push (string-join (nreverse spans)) parts)
        (setq width (max width (+ (* 2 pad) (* col cw))))
        (cl-incf y height)))
    (let ((height (+ y pad)))
      (concat (format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" font-family=\"%s\" font-size=\"%d\" xml:space=\"preserve\" style=\"white-space:pre\">"
                      width height (xml-escape-string family) (round (* 0.8 lh)))
              (format "<rect width=\"100%%\" height=\"100%%\" rx=\"6\" fill=\"%s\"/>" bg)
              (string-join (nreverse parts))
              "</svg>"))))

;; ====== TEXT IN A TERMINAL'S COLOURS ======

(defun agent-ui--ansi-rgb (color)
  "COLOR (#RRGGBB, or a name) as \"R;G;B\", 0 to 255; nil if unknown.
#RRGGBB read as it is: `color-name-to-rgb' gives what the selected frame
shows, a terminal's 8 colours in one."
  (cond
   ((and (stringp color) (string-match "\\`#\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\'" color))
    (mapconcat (lambda (i) (number-to-string (string-to-number (match-string i color) 16))) '(1 2 3) ";"))
   ((stringp color)
    (when-let* ((rgb (color-name-to-rgb color)))
      (mapconcat (lambda (x) (number-to-string (round (* 255 x)))) rgb ";")))))

(defun agent-ui-ansi (text)
  "TEXT with its faces as ANSI codes (24-bit colour, bold), for a terminal:
the theme's colours; text in the default face as the terminal has it."
  (let ((fg (agent-ui-snapshot--color 'default :foreground nil))
        (bg (agent-ui-snapshot--color 'default :background nil)))
    (mapconcat
     (lambda (run)
       (let* ((face (cdr run))
              (fore (agent-ui-snapshot--color face :foreground fg))
              (back (agent-ui-snapshot--color face :background bg))
              (codes (delq nil (list (and (agent-ui-snapshot--bold-p face) "1")
                                     (and fore (not (equal fore fg))
                                          (when-let* ((rgb (agent-ui--ansi-rgb fore))) (concat "38;2;" rgb)))
                                     (and back (not (equal back bg))
                                          (when-let* ((rgb (agent-ui--ansi-rgb back))) (concat "48;2;" rgb)))))))
         (if codes
             (concat "\e[" (string-join codes ";") "m" (car run) "\e[0m")
           (car run))))
     ;; Run by run, a line at a time: each run's colour ends with it, so a
     ;; line's end leaves the terminal's own.
     (let ((runs nil) (first t))
       (dolist (line (split-string text "\n"))
         (unless first (push (cons "\n" nil) runs))
         (setq first nil)
         (dolist (run (agent-ui-snapshot--runs line)) (push run runs)))
       (nreverse runs))
     "")))

;; ====== A SNAPSHOT ======

(defun agent-ui-snapshot--width (canvas)
  "The width a snapshot of CANVAS's is drawn at: `agent-ui-snapshot-width',
narrower to fit its session's window, its padding too (agent-shell scales
an image down to its window: drawn at 80 columns, a 40-column session showed
it at half size); 20 at least."
  (let* ((session (buffer-local-value 'agent-ui--session-buffer (agent-ui--buffer canvas)))
         (window (and (buffer-live-p session) (get-buffer-window session t))))
    (if window
        ;; A column short, as the canvas, and its padding's two.
        (max 20 (min agent-ui-snapshot-width (- (window-max-chars-per-line window) 3)))
      agent-ui-snapshot-width)))

(cl-defun agent-ui-snapshot (id &key canvas directory)
  "Save element ID of CANVAS as it's drawn (at `agent-ui-snapshot--width'),
an SVG file in DIRECTORY's
`agent-ui-snapshot-directory' (DIRECTORY: the agent's, else the current
one). Returns (:file FILE :markdown \"![TITLE](FILE)\")."
  (let* ((element (agent-ui-get id :canvas canvas))
         (frame (selected-frame))
         ;; Still: its buttons would do nothing in the conversation.
         (ctx (agent-ui-context :width (agent-ui-snapshot--width canvas) :graphic (display-graphic-p frame)
                                :char-width (if (display-graphic-p frame) (frame-char-width frame) 8)
                                :line-height (if (display-graphic-p frame) (frame-char-height frame) 17)
                                :still t))
         (dir (expand-file-name agent-ui-snapshot-directory (or directory default-directory)))
         (stem (format "agent-ui-%s-%s" id (format-time-string "%Y%m%d-%H%M%S")))
         ;; Two in a second (a change between them): another name, not over it.
         (file (let ((n 1) (f (expand-file-name (concat stem ".svg") dir)))
                 (while (file-exists-p f)
                   (setq f (expand-file-name (format "%s-%d.svg" stem (cl-incf n)) dir)))
                 f))
         (title (or (plist-get element :title) id)))
    (make-directory dir t)
    (let ((coding-system-for-write 'utf-8))
      ;; Drawn in its canvas, its id given: as it's shown (a bar's rate).
      (write-region (agent-ui-snapshot-svg (agent-ui--in canvas
                                             (agent-ui-render element (plist-put (copy-sequence ctx) :id id)))
                                           ctx)
                    nil file nil 'silent))
    (list :file file :markdown (format "![%s](%s)" (string-replace "]" ")" title) file))))

;; ====== INTO THE PROMPT ======

(defun agent-ui--element-at-point ()
  "The id of the element at point, in a canvas."
  (or (get-text-property (point) 'agent-ui-child)
      (get-text-property (point) 'agent-ui-id)
      (and (> (point) (point-min)) (get-text-property (1- (point)) 'agent-ui-id))
      (user-error "No element here")))

(defun agent-ui-element-as-text (id &optional canvas)
  "Element ID of CANVAS as the agent reads it in a prompt."
  (let ((element (agent-ui-get id :canvas canvas)))
    (format "Agent UI element %s (%s), as it's shown:\n```text\n%s\n```\n"
            id (plist-get element :type)
            (substring-no-properties (agent-ui-render element (agent-ui-context :width agent-ui-snapshot-width))))))

(defun agent-ui-send-element ()
  "Put the element at point into the prompt of the canvas's session, as
text the agent reads."
  (interactive)
  (let ((id (agent-ui--element-at-point))
        (shell (and (boundp 'agent-ui--session-buffer) agent-ui--session-buffer)))
    (unless (buffer-live-p shell)
      (user-error "This canvas has no agent-shell session"))
    (unless (fboundp 'agent-shell-insert)
      (user-error "agent-shell isn't loaded"))
    (agent-shell-insert :text (agent-ui-element-as-text id (current-buffer)) :shell-buffer shell)))

(declare-function agent-shell-insert "agent-shell")
(keymap-set agent-ui-canvas-mode-map "a" #'agent-ui-send-element)

;; ====== LINKS ======
;; agent-ui://canvas/NAME#ID, in the agent's reply ([the build](...)): a
;; link agent-shell draws, and opens with `browse-url'; its handler here shows
;; the canvas's pane, selected, the cursor on element ID.

(require 'url-parse)
(require 'url-util)

(defun agent-ui-link (canvas &optional id)
  "The link to CANVAS (its name) and, with ID, to its element ID."
  (concat "agent-ui://canvas/" (url-hexify-string canvas)
          (if id (concat "#" (url-hexify-string id)) "")))

(defun agent-ui-open-link (url &rest _)
  "Open URL, an agent-ui:// link (see LINKS above): its canvas's pane
shown and selected, the cursor on its element. A `browse-url' handler."
  (let* ((parsed (url-generic-parse-url url))
         (name (decode-coding-string (url-unhex-string (string-remove-prefix "/" (url-filename parsed))) 'utf-8))
         (id (and (url-target parsed)
                  (decode-coding-string (url-unhex-string (url-target parsed)) 'utf-8)))
         (canvas (get-buffer (agent-ui-canvas-buffer-name name))))
    (unless (and (equal (url-host parsed) "canvas") canvas)
      (user-error "Agent UI: no canvas %s (closed?)" name))
    (let ((window (or (get-buffer-window canvas)
                      (progn (funcall agent-ui-display-function canvas)
                             (get-buffer-window canvas)))))
      (when window
        (select-window window))
      (with-current-buffer canvas
        (let ((pos (and id (agent-ui--element-start canvas id))))
          (when pos
            (goto-char pos)
            (when window
              (set-window-point window pos)
              (set-window-start window (save-excursion (goto-char pos) (line-beginning-position)))))))
      canvas)))

(defun agent-ui--element-start (canvas id)
  "Where element ID starts in CANVAS, or nil."
  (with-current-buffer canvas
    (let ((pos (point-min)))
      ;; Its own, or a panel's child.
      (while (and pos (not (equal (get-text-property pos 'agent-ui-id) id))
                  (not (equal (get-text-property pos 'agent-ui-child) id)))
        (setq pos (next-property-change pos)))
      pos)))

(require 'browse-url)
(add-to-list 'browse-url-handlers '("\\`agent-ui:" . agent-ui-open-link))

