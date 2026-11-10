;;; $DOOMDIR/config/agent-ui/elements/panel.el -*- lexical-binding: t; -*-
;; Agent UI's panel: elements laid out together. Loaded from
;; config/agent-ui/elements.el.
;;
;; CHILDREN, ordinary elements (each with its type, its title, its id),
;; laid out as a ROW (side by side, a │ between, each its share of the
;; width: WEIGHTS, equal by default) or a COLUMN (one under another), in a
;; BORDER. Panels nest: rows of columns, a dashboard. A row too narrow for
;; its children (under MIN-WIDTH each) stacks them. In the GUI, a row with an
;; image taller than a line among its children (a chart, stats' tiles) is
;; drawn as one SVG, each child's drawing in its column (their buttons not
;; clickable there); other rows, as text, images a line high (a tags
;; element's chips, a pie) in it.
;;
;;   ╭──────────────────────────────────────╮
;;   │ Build              │ Tests           │
;;   │ ████████░░  8/12   │  lexer  passed  │
;;   ╰──────────────────────────────────────╯

(require 'cl-lib)
(require 'subr-x)

(defcustom agent-ui-panel-depth 6
  "How deep panels may nest."
  :type 'natnum :group 'agent-ui)

(defun agent-ui-panel--children-check (children depth ids)
  "CHILDREN checked (their types, properties, ids: unique, with IDS so far);
an error saying which is wrong. Returns the ids seen."
  (when (> depth agent-ui-panel-depth)
    (agent-ui--fail "panel: panels nest %d deep at most" agent-ui-panel-depth))
  (cl-loop for child in children
           for i from 1
           do (unless (agent-ui--plist-p child)
                (agent-ui--fail "panel: child %d must be an element: {\"type\": ..., ...}" i))
           (let ((id (plist-get child :id)))
             (when id
               (unless (and (stringp id) (string-match-p "\\`[A-Za-z0-9_.-]+\\'" id))
                 (agent-ui--fail "panel: child %d's id is letters, digits, -, _ or ." i))
               (when (member id ids)
                 (agent-ui--fail "panel: two children are %s" (agent-ui--show-value id)))
               (push id ids)))
           (condition-case err
               (agent-ui-check (plist-get child :type) child)
             (agent-ui-error
              (agent-ui--fail "panel: child %d (%s): %s" i
                              (or (plist-get child :id) (plist-get child :type)) (agent-ui-error-message err))))
           (when (equal (format "%s" (plist-get child :type)) "panel")
             (setq ids (agent-ui-panel--children-check (plist-get child :children) (1+ depth) ids))))
  ids)

(defun agent-ui-panel--check (props)
  (let ((children (plist-get props :children))
        (weights (plist-get props :weights)))
    (agent-ui-panel--children-check children 1 nil)
    (when (and weights (not (and (= (length weights) (length children))
                                 (cl-every (lambda (w) (and (numberp w) (> w 0))) weights))))
      (agent-ui--fail "panel: weights are a positive number for each child (%d)" (length children))))
  props)

(declare-function agent-ui-snapshot--svg-size "agent-ui/snapshot")

(defun agent-ui-panel--image-size (display)
  "The size an image DISPLAY (`(image ...)', or a slice of one) is shown
at, in pixels: (W . H), whole (Emacs shows an SVG of 192.8 pixels in 192:
counted 192.8, its line came out a pixel short); nil if it can't be known."
  (pcase display
    (`((slice ,_ ,_ ,w ,h) . ,_) (cons w h))
    (`(image . ,props)
     (let ((size (if-let* ((data (plist-get props :data))
                           ((eq (plist-get props :type) 'svg)))
                     (agent-ui-snapshot--svg-size data)
                   (and (display-graphic-p) (ignore-errors (image-size display t)))))
           (scale (or (plist-get props :scale) 1)))
       (and size (cons (floor (* (car size) scale)) (floor (* (cdr size) scale))))))))

(defun agent-ui-panel--pixels (line cw)
  "How wide LINE is shown, in pixels (CW a column's): its images' widths, a
filler's (a space of a given width), CW a column for the rest; nil if an
image's width can't be known."
  (let ((pos 0) (pixels 0))
    (while (and pixels (< pos (length line)))
      (let* ((next (or (next-single-property-change pos 'display line) (length line)))
             (display (get-text-property pos 'display line)))
        (setq pixels
              (pcase display
                ((or `(image . ,_) `((slice . ,_) . ,_))
                 (let ((size (agent-ui-panel--image-size display)))
                   (and size (+ pixels (car size)))))
                (`(space :width (,width)) (+ pixels width))
                (_ (+ pixels (* cw (string-width (substring line pos next)))))))
        (setq pos next)))
    pixels))

(defun agent-ui-panel--lines (text width ctx)
  "TEXT's lines, each padded (or cut) to WIDTH columns. A line with an
image: padded after it, a space as wide as the image leaves of its last
column (shown so; a snapshot counts it in the image's columns), then
spaces; kept as it is if wider, or its width unknown."
  (let ((cw (or (plist-get ctx :char-width) 8)))
    (mapcar (lambda (line)
              (if (not (agent-ui-panel--image-p line))
                  (agent-ui-pad line width)
                (let ((pixels (agent-ui-panel--pixels line cw)))
                  (if (or (null pixels) (> pixels (* width cw)))
                      line
                    (let* ((columns (ceiling pixels cw))
                           ;; Down: rounded up, a fraction of a pixel past
                           ;; its room, it was taken for wider (its right side
                           ;; left out).
                           (filler (floor (- (* columns cw) pixels))))
                      (concat line
                              (if (> filler 0) (propertize " " 'display `(space :width (,filler))) "")
                              (make-string (- width columns) ?\s)))))))
            (split-string text "\n"))))

(defun agent-ui-panel--child (child ctx width)
  "CHILD drawn at WIDTH, its id in its context (its own buttons); its text
marked as its (`agent-ui-child'), where a deeper child hasn't marked it."
  (let ((text (agent-ui-render child (plist-put (plist-put (copy-sequence ctx) :width width)
                                                :id (or (plist-get child :id) (plist-get ctx :id))))))
    (when-let* ((id (plist-get child :id)))
      (let ((pos 0))
        (while (< pos (length text))
          (let ((next (or (next-single-property-change pos 'agent-ui-child text) (length text))))
            (unless (get-text-property pos 'agent-ui-child text)
              (put-text-property pos next 'agent-ui-child id text))
            (setq pos next)))))
    text))

(defun agent-ui-panel--line-height (line)
  "The height LINE is shown at, in pixels, if an image in it says (its
tallest's; nil if none can be known)."
  (let ((pos 0) (height nil))
    (while (< pos (length line))
      (let ((next (or (next-single-property-change pos 'display line) (length line)))
            (size (agent-ui-panel--image-size (get-text-property pos 'display line))))
        (when size (setq height (max (or height 0) (cdr size))))
        (setq pos next)))
    height))

(defun agent-ui-panel--sliced (line ctx)
  "LINE as lines a text line high each, if an SVG in it is taller: cut into
slices, one a line, the image padded (transparent) to whole lines, itself
in their middle; on the first, what's beside it, on the others its blanks.
A bordered panel's sides then are the font's │ on every line (beside a
taller line, they had gaps; drawn beside it, they didn't align). LINE
alone if it has none, or more than one, or another kind."
  (let* ((lh (plist-get ctx :line-height))
         (tall (let ((pos 0) (found nil))
                 (while (< pos (length line))
                   (let* ((next (or (next-single-property-change pos 'display line) (length line)))
                          (display (get-text-property pos 'display line))
                          (size (and (eq (car-safe display) 'image) (agent-ui-panel--image-size display))))
                     (when (and size (> (cdr size) lh)) (push (list pos next display size) found))
                     (setq pos next)))
                 found)))
    (pcase tall
      (`((,start ,end (image . ,props) (,w . ,h)))
       (if (not (and (eq (plist-get props :type) 'svg) (plist-get props :data)
                     (memql (or (plist-get props :scale) 1) '(1 1.0))))
           (list line)
         (let* ((rows (ceiling h lh))
                (padded (agent-ui-image
                         (create-image (format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\"><g transform=\"translate(0 %d)\">%s</g></svg>"
                                               w (* rows lh) (/ (- (* rows lh) h) 2) (plist-get props :data))
                                       'svg t :scale 1 :ascent 'center)))
                (before (substring line 0 start))
                (after (substring line end))
                (text (substring-no-properties line start end)))
           (cl-loop for k below rows
                    collect (concat (if (= k 0) before (make-string (string-width before) ?\s))
                                    (propertize text 'display (list (list 'slice 0 (* k lh) w lh) padded))
                                    ;; What's after it: as it is if blank (a
                                    ;; filler to its column's end, spaces).
                                    (if (or (= k 0) (string-blank-p (substring-no-properties after)))
                                        after
                                      (make-string (string-width after) ?\s)))))))
      (_ (list line)))))

(defun agent-ui-panel--side (text height ctx)
  "TEXT, a side of the border (\"│ \" or \" │\"), shown HEIGHT pixels tall
\(a character is a line's height: beside a taller image, the border had
gaps): the font's own │, as the text draws it, stretched to HEIGHT (as
thick as the others); a line where the font isn't known."
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (w (* cw (string-width text)))
         (column (string-search "│" text))
         (color (agent-ui-color 'agent-ui-muted))
         (svg (svg-create w (round height))))
    (if-let* ((size (plist-get ctx :font-size))
              (ascent (plist-get ctx :font-ascent)))
        (svg-text svg "│" :x (* cw column) :y ascent :font-size size :font-family (agent-ui--svg-font)
                  :fill color :transform (format "scale(1 %.4f)" (/ (round height) (float lh))))
      (svg-line svg (+ (* cw column) (/ cw 2.0)) 0 (+ (* cw column) (/ cw 2.0)) (round height)
                :stroke color :stroke-width 1))
    (propertize text 'face 'agent-ui-muted 'display (agent-ui-svg-image svg))))

(defun agent-ui-panel--image-p (text)
  "Whether TEXT shows an image somewhere (a chart's, stats' tiles...)."
  (text-property-not-all 0 (length text) 'display nil text))

(defun agent-ui-panel--inline-p (text width ctx)
  "Whether TEXT's images are inline: each a line high at most (a chip, a
pie), its width known, its line no wider than WIDTH columns (a line of
text is cut to them); then a row's text can hold it, its buttons kept (one
SVG for the row, they weren't clickable). Not for a chart, a graph, an
image taller than a line, nor their slices."
  (let ((cw (plist-get ctx :char-width))
        (lh (plist-get ctx :line-height)))
    (and cw lh
         (cl-every
          (lambda (line)
            (and (let ((pos 0) (ok t))
                   (while (and ok (< pos (length line)))
                     (let ((next (or (next-single-property-change pos 'display line) (length line)))
                           (display (get-text-property pos 'display line)))
                       (setq ok (pcase display
                                  ('nil t)
                                  (`(space . ,_) t)
                                  (`(image . ,_)
                                   (let ((size (agent-ui-panel--image-size display)))
                                     (and size (<= (cdr size) lh))))
                                  (_ nil))
                             pos next)))
                   ok)
                 (or (not (agent-ui-panel--image-p line))
                     (let ((pixels (agent-ui-panel--pixels line cw)))
                       (and pixels (<= pixels (* width cw)))))))
          (split-string text "\n")))))

(defun agent-ui-panel--trim-right (line)
  "LINE without its trailing spaces, but those showing something (an image
is a space with a display property: a row's SVG, an image element's)."
  (let ((end (length line)))
    (while (and (> end 0)
                (eq (aref line (1- end)) ?\s)
                (not (get-text-property (1- end) 'display line)))
      (setq end (1- end)))
    (substring line 0 end)))

(defun agent-ui-panel--svg-row (texts widths ctx border)
  "TEXTS, a row's children drawn for the GUI at WIDTHS, as one SVG image
\(a string showing it): each child its column (its SVG nested; its text as
SVG text: `agent-ui-snapshot-svg'), a line between them, the border's
sides if BORDER. Nil if `agent-ui-snapshot-svg' isn't there."
  (when (fboundp 'agent-ui-snapshot-svg)
    (let* ((cw (plist-get ctx :char-width))
           (lh (plist-get ctx :line-height))
           (left (if border 2 0))
           ;; Each child's text fitted to its column first (a long title
           ;; ran across the line between them, or over the border).
           (svgs (cl-mapcar (lambda (text w)
                              (agent-ui-snapshot-svg (string-join (agent-ui-panel--lines text w ctx) "\n")
                                                     (plist-put (copy-sequence ctx) :width w)))
                            texts widths))
           (heights (mapcar (lambda (svg) (if (string-match "height=\"\\([0-9.]+\\)\"" svg)
                                              (string-to-number (match-string 1 svg)) lh))
                            svgs))
           (height (round (apply #'max heights)))
           (width (* cw (plist-get ctx :width)))
           (muted (agent-ui-chart--color 'agent-ui-muted))
           (x left)
           (parts nil))
      (cl-loop for svg in svgs
               for w in widths
               for i from 0
               do (progn
                    ;; Its text where it'd be: past the snapshot's padding (a cell).
                    (push (replace-regexp-in-string
                           "\\`<svg xmlns=\"http://www.w3.org/2000/svg\" "
                           (format "<svg x=\"%d\" y=\"0\" " (* cw (1- x))) svg t t)
                          parts)
                    (setq x (+ x w))
                    (when (< i (1- (length widths)))
                      (push (format "<line x1=\"%.1f\" y1=\"0\" x2=\"%.1f\" y2=\"%d\" stroke=\"%s\"/>"
                                    (* cw (+ x 1.5)) (* cw (+ x 1.5)) height muted)
                            parts)
                      (setq x (+ x 3)))))
      (when border
        (dolist (side (list (* 0.5 cw) (- width (* 0.5 cw))))
          (push (format "<line x1=\"%.1f\" y1=\"0\" x2=\"%.1f\" y2=\"%d\" stroke=\"%s\"/>" side side height muted)
                parts)))
      (propertize " " 'display
                  (agent-ui-image
                   (create-image (format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\">%s</svg>"
                                         width height (string-join (nreverse parts)))
                                 'svg t :scale 1 :ascent 'center))))))

(defun agent-ui-panel--draw (props ctx)
  (let* ((children (plist-get props :children))
         (width (max 1 (plist-get ctx :width)))
         ;; A border where there's room for it and a column inside; no
         ;; child at 0 columns or less (they broke, or hung wrapping).
         (border (and (plist-get props :border) (>= width 6)))
         (inner (if border (- width 4) width))
         (n (length children))
         (weights (or (plist-get props :weights) (make-list n 1)))
         (total (float (apply #'+ weights)))
         (room (- inner (* 3 (max 0 (1- n)))))
         (widths (when children
                   (let ((ws (mapcar (lambda (w) (max 1 (floor (* room (/ w total))))) weights)))
                     ;; What rounding left over, to the last.
                     (append (butlast ws) (list (+ (car (last ws)) (- room (apply #'+ ws))))))))
         (row-image nil)
         (row (and (eq (plist-get props :layout) 'row) (> n 1)
                   (cl-every (lambda (w) (>= w (max 1 (plist-get props :min-width)))) widths)))
         ;; In the GUI, a row's children drawn for it: with images among them,
         ;; inline ones only (chips, pies) or not.
         (texts (and row children (plist-get ctx :graphic)
                     (cl-mapcar (lambda (child w) (agent-ui-panel--child child ctx w)) children widths)))
         (images (seq-some #'agent-ui-panel--image-p texts))
         (inline (and images (cl-every #'identity (cl-mapcar (lambda (text w) (agent-ui-panel--inline-p text w ctx))
                                                             texts widths))))
         (body
          (cond
           ((null children) (list (propertize "no elements" 'face 'agent-ui-muted)))
           ((and images (not inline)
                 ;; Side by side with an image taller than a line among them
                 ;; (a chart): one SVG (its children's buttons, then, not
                 ;; clickable).
                 (setq row-image (agent-ui-panel--svg-row texts widths ctx border)))
            (list row-image))
           (row
            ;; Side by side, as text: line by line, each child its width; in
            ;; the GUI with inline images (chips), as drawn for it, each line
            ;; padded to its column's pixels.
            (let* ((text-ctx (plist-put (copy-sequence ctx) :graphic nil))
                   (columns (if inline
                                (cl-mapcar (lambda (text w) (agent-ui-panel--lines text w ctx)) texts widths)
                              (cl-mapcar (lambda (child w) (agent-ui-panel--lines (agent-ui-panel--child child text-ctx w) w text-ctx))
                                         children widths)))
                   (height (apply #'max (mapcar #'length columns))))
              (cl-loop for i below height
                       collect (mapconcat #'identity
                                          (cl-mapcar (lambda (lines w) (or (nth i lines) (make-string w ?\s)))
                                                     columns widths)
                                          (propertize " │ " 'face 'agent-ui-muted)))))
           (t
            ;; One under another, a blank line between.
            (cdr (apply #'append
                        (mapcar (lambda (child) (cons (make-string inner ?\s)
                                                      (agent-ui-panel--lines (agent-ui-panel--child child ctx inner) inner ctx)))
                                children)))))))
    ;; In the GUI, a bordered line taller than a text line: cut in lines.
    (when (and border (plist-get ctx :graphic) (plist-get ctx :char-width) (plist-get ctx :line-height))
      (setq body (mapcan (lambda (line)
                           (if (and (stringp line) (not (eq line row-image)) (agent-ui-panel--image-p line))
                               (agent-ui-panel--sliced line ctx)
                             (list line)))
                         body)))
    (if (not border)
        (mapconcat #'agent-ui-panel--trim-right body "\n")
      (let ((edge (lambda (s) (propertize s 'face 'agent-ui-muted))))
        (concat (funcall edge (concat "╭" (make-string (- width 2) ?─) "╮")) "\n"
                (mapconcat (lambda (line)
                             (cond
                              ;; A row as one SVG: its sides drawn in it.
                              ((eq line row-image) line)
                              ;; Wider than its room (an image): its right side left out.
                              ((and (agent-ui-panel--image-p line)
                                    (let ((pixels (agent-ui-panel--pixels line (or (plist-get ctx :char-width) 8))))
                                      (or (null pixels) (> pixels (* inner (or (plist-get ctx :char-width) 8))))))
                               (concat (funcall edge "│ ") line))
                              ;; Taller than a line (an image): its sides as tall.
                              ((let ((height (and (plist-get ctx :graphic) (plist-get ctx :char-width)
                                                  (agent-ui-panel--image-p line)
                                                  (agent-ui-panel--line-height line))))
                                 (and height (> height (or (plist-get ctx :line-height) 16))
                                      (concat (agent-ui-panel--side "│ " height ctx) line
                                              (agent-ui-panel--side " │" height ctx)))))
                              (t
                               (concat (funcall edge "│ ") line (funcall edge " │")))))
                           body "\n")
                "\n" (funcall edge (concat "╰" (make-string (- width 2) ?─) "╯")))))))

(agent-ui-define panel
  "Elements laid out together: CHILDREN, ordinary elements (each its type,
title, id), as a ROW (side by side, each its share of the width, WEIGHTS
equal by default) or a COLUMN, in a BORDER. Panels nest (rows of
columns: a dashboard). A row too narrow (under MIN-WIDTH a child) stacks
its children. In a row with a chart or an image (in the GUI), the row is one
SVG: its children's buttons aren't clickable there (chips, a line high,
stay text)."
  :props ((children list "The elements: {\"type\": ..., \"id\": ..., ...}")
          (layout (choice row column) "Side by side (row) or one under another (column)" :default column)
          (weights list "Each child's share of a row's width (default: equal)")
          (border boolean "A border around it" :default t)
          (min-width integer "The narrowest a child of a row may be before it stacks" :default 24))
  :example (:title "Release" :layout "row"
            :children ((:id "build" :type "progress" :title "Build" :value 8 :max 12)
                       (:id "tests" :type "table" :title "Tests" :columns ("Test" "Result")
                            :rows (("lexer" "passed") ("parser" "failed")))))
  :animated (lambda (props) (seq-some #'agent-ui-animated-p (plist-get props :children)))
  :check #'agent-ui-panel--check
  :text #'agent-ui-panel--draw)
