;;; $DOOMDIR/config/banner/row.el -*- lexical-binding: t; -*-
;; A notice's row: its icon, message, actions and ✕. Loaded from config/banner.el.

;;; A notice's row

(defun +my/banner--face (type)
  (intern (format "+my/banner-%s" (if (assq type +my/banner-types) type 'info))))

(defun +my/banner--refocus ()
  "After a click on a notice, keyboard input stays with the window it's about."
  (when-let* ((parent (frame-parent (selected-frame))))
    (select-frame-set-input-focus parent)))

(defun +my/banner--clicked-window ()
  "The window whose notice was clicked: the one under the notices' frame
clicked (its focus is its parent's: the click doesn't select it,
config/emacs/childframe.el), or selected, or (a terminal's header line) the
one clicked."
  (let* ((window (and (mouse-event-p last-input-event)
                      (posn-window (event-start last-input-event))))
         (clicked (and (window-live-p window) (window-frame window))))
    (or (car (seq-find (lambda (entry) (memq (nth 1 entry) (list clicked (selected-frame))))
                       +my/banner--frames))
        (and (window-live-p window) window)
        (selected-window))))

(defun +my/banner--button (label function face buffer header &optional help)
  "LABEL (of FACE) calling FUNCTION in BUFFER when clicked. HEADER: it's in the
header line (a terminal's), else on a row of the notices' frame. FUNCTION runs
in the window the notice is about, the notices' frame left: run from there, an
action opening a window (e.g. Markdown's preview, beside the file) opened it
in the wrong place."
  (let ((map (make-sparse-keymap))
        (command (lambda () (interactive)
                   (let ((window (+my/banner--clicked-window)))
                     (+my/banner--refocus)
                     (when (window-live-p window)
                       (select-window window))
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer (funcall function)))))))
    (if header
        (define-key map [header-line mouse-1] command)
      (set-keymap-parent map +my/banner--row-map)
      (define-key map [mouse-1] command))
    (propertize label
                'face `(+my/banner-action ,face)
                'mouse-face 'highlight
                'pointer 'hand
                'help-echo (or help (concat "mouse-1: " (string-trim label)))
                (if header 'local-map 'keymap) map)))

(defun +my/banner--icon (type face)
  "TYPE's icon, in its colour on FACE."
  (pcase-let ((`(,_ ,icon ,colour) (or (assq type +my/banner-types)
                                       (assq 'info +my/banner-types))))
    (or (ignore-errors
          (let ((glyph (nerd-icons-codicon icon)))
            (add-face-text-property 0 (length glyph) face t glyph)
            (when (fboundp 'doom-color)
              (add-face-text-property 0 (length glyph)
                                      `(:foreground ,(doom-color colour)) nil glyph))
            glyph))
        (propertize "!" 'face face))))

;; FITTING A ROW
;; WIDTH columns: "  " icon "  " (6), the message, each action after a gap of
;; 4, then a gap and " ✕ " 4 from the edge (6). The message is cut short (…)
;; first, down to `+my/banner--least' columns. Narrower still, on the notices'
;; frame the message gets a row of its own, the actions and ✕ the next, their
;; labels cut short (…) if need be, the longest first (each one's help says it
;; whole). A terminal's header line has one row: the gaps are 2, "(N more)"
;; "+N", the message gets what's left once each label has 4 columns (10 at
;; most), the labels the rest. The ✕ always fits: what's still too wide before
;; it is cut.
(defconst +my/banner--least 10
  "The fewest columns a message is cut to before its notice takes two rows.")

(defun +my/banner--labels-width (labels &optional most gap)
  "The columns LABELS take, each after a GAP (default 4), cut to MOST columns."
  (cl-loop for label in labels
           sum (+ (or gap 4) (min (string-width label) (or most most-positive-fixnum)))))

(defun +my/banner--most (labels room &optional gap)
  "The widest a label may be for LABELS to fit in ROOM columns, each after a
GAP (default 4): nil if they fit as they are, else 1 (a … each) at the least."
  (unless (<= (+my/banner--labels-width labels nil gap) room)
    (let ((most (cl-loop for label in labels maximize (string-width label))))
      (while (and (> most 1) (> (+my/banner--labels-width labels most gap) room))
        (cl-decf most))
      most)))

(defun +my/banner--more (more &optional tight)
  "How many MORE notices there are, after a gap (none: nil); TIGHT: \"+N\"."
  (and more (> more 0) (format (if tight "  +%d" "    (%d more)") more)))

(defun +my/banner--layout (text labels width more header)
  "How a notice of TEXT and action LABELS fits WIDTH columns (nil: any), MORE
other notices mentioned: (TWO ROOM MOST TIGHT). TWO: on two rows (not in a
terminal's HEADER line); ROOM: the columns the message may take, MOST: the
widest a label may be (nil: as wide as they like); TIGHT: gaps of 2, \"+N\".
See FITTING A ROW."
  (let* ((room (and width (- width 12 (string-width (or (+my/banner--more more) ""))
                         (+my/banner--labels-width labels))))
         (least (min (string-width text) +my/banner--least)))
    (cond ((or (null width) (>= room (string-width text))) (list nil nil nil nil))
          ((or (>= room least) (null labels)) (list nil (max 0 room) nil nil))
          ((not header) (list t (- width 8) (+my/banner--most labels (- width 8)) nil))
          (t (let* ((rest (- width 12 (string-width (or (+my/banner--more more t) ""))))
                    (room (max 1 (min least (- rest (+my/banner--labels-width labels 4 2))))))
               (list nil room (+my/banner--most labels (- rest room) 2) t))))))

(defun +my/banner--rows (notices width)
  "The rows NOTICES take on a notices' frame WIDTH columns wide."
  (cl-loop for (_ text actions) in notices
           sum (if (car (+my/banner--layout text (mapcar #'car actions) width nil nil)) 2 1)))

(defun +my/banner--cut (string columns ellipsis)
  "STRING cut to COLUMNS (nil: as it is; none: empty), ending with ELLIPSIS
if cut (no space before it)."
  (cond ((null columns) string)
        ((<= columns 0) "")
        ((<= (string-width string) columns) string)
        (t (concat (string-trim-right (truncate-string-to-width string (1- columns)))
                   ellipsis))))

(defun +my/banner--row (notice buffer &optional header more width)
  "NOTICE's row, its actions run in BUFFER: on the notices' frame, or in the
header line if HEADER (then MORE: how many other notices to mention). If the
row is WIDTH columns, it fits them (a narrow window, a terminal; see FITTING A
ROW): on the notices' frame it may take two rows."
  (pcase-let* ((`(,id ,text ,actions ,type) notice)
               (face (+my/banner--face type))
               (`(,two ,room ,most ,tight)
                (+my/banner--layout text (mapcar #'car actions) width more header))
               (more-text (+my/banner--more more tight))
               (plain (lambda (string &rest props)
                        (apply #'propertize string 'face face
                               (append props (unless header
                                               (list 'keymap +my/banner--row-map))))))
               (message (+my/banner--cut text room "…"))
               ;; The whole message in the icon's and message's help: cut
               ;; short, it's read there.
               (start (concat
                       (funcall plain "  ")
                       (let ((icon (+my/banner--icon type face)))
                         (add-text-properties 0 (length icon)
                                              (append (list 'help-echo text)
                                                      (unless header (list 'keymap +my/banner--row-map)))
                                              icon)
                         icon)
                       (funcall plain (concat "  " message) 'help-echo text)))
               (end (concat
                     (mapconcat (lambda (action)
                                  (concat (funcall plain (if tight "  " "    "))
                                          (+my/banner--button
                                           (+my/banner--cut (car action) most "…")
                                           (cdr action) face buffer header
                                           (concat "mouse-1: " (string-trim (car action))))))
                                actions "")
                     (when more-text
                       (propertize more-text 'face `(shadow ,face)
                                   'help-echo (string-trim (+my/banner--more more))))))
               (close (concat
                       (funcall plain " " 'display '(space :align-to (- right 4)))
                       (+my/banner--button " ✕ " (lambda () (+my/banner-close id)) face buffer header
                                           "mouse-1: close")
                       ;; To the edge: in the header line over the right margin
                       ;; (the stripe) and fringe too, else they keep the header
                       ;; line's own colour.
                       (funcall plain " " 'display (if header
                                                       '(space :align-to (+ right right-margin right-fringe))
                                                     '(space :align-to right))))))
    (if two
        (concat start
                (funcall plain " " 'display '(space :align-to right))
                (funcall plain "\n")
                (funcall plain "  ")
                (+my/banner--cut end (- width 8) (funcall plain "…"))
                close)
      (concat start
              (+my/banner--cut end (and width (- width 12 (string-width message)))
                               (funcall plain "…"))
              close))))
