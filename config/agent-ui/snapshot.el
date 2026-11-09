;;; $DOOMDIR/config/agent-ui/snapshot.el -*- lexical-binding: t; -*-
;; Agent UI's elements in the conversation. Loaded from config/agent-ui.el.
;;
;; agent-shell owns its buffer's text, so an element isn't put there: it goes
;; the ways agent-shell already has.
;; - From the agent: `agent-ui snapshot ID' saves the element as it's drawn,
;;   an SVG image (its text in its colours, a chart's own SVG), in the
;;   session's .agent-shell/images/, and replies with a Markdown image link
;;   for its reply: agent-shell shows it inline, and its transcript keeps it.
;; - From you: a in a canvas puts the element at point into its session's
;;   prompt, as text the agent reads (`agent-ui-send-element').
;; No Doom here.

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'mailcap)

;; ====== VARIABLES ======

(defcustom agent-ui-snapshot-directory ".agent-shell/images/"
  "Where snapshots go, relative to the agent's directory (agent-shell's
transcripts' folder, kept out of git)."
  :type 'string :group 'agent-ui)

(defcustom agent-ui-snapshot-width 80
  "The width snapshots are drawn at, in columns."
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

(defun agent-ui-snapshot--run (text col y color bold cw lh)
  "TEXT, a run in COLOR from column COL on the line at Y, as SVG: its block
characters as rectangles (full ones joined), ░ a faint cell, the rest text."
  (let ((parts nil) (pending "") (pending-col col) (bar-start nil) (bar-cells 0))
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
                      (push (format "<text x=\"%d\" y=\"%d\" fill=\"%s\"%s>%s</text>"
                                    (+ cw (* column cw)) (+ y (round (* 0.78 lh))) color
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
      (flush-bar))
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
      (let* ((display (and (> (length line) 0) (get-text-property 0 'display line)))
             (data (and (eq (car-safe display) 'image) (eq (plist-get (cdr display) :type) 'svg)
                        (plist-get (cdr display) :data)))
             (size (and data (agent-ui-snapshot--svg-size data)))
             (file (and (eq (car-safe display) 'image) (not data)
                        (agent-ui-snapshot--image-file display))))
        (cond
         (file
          ;; An image from a file (an image element's): itself, embedded.
          (push (format "<g transform=\"translate(%d %d)\">%s</g>" pad y (car file)) parts)
          (setq width (max width (+ (* 2 pad) (cadr file))))
          (cl-incf y (cddr file)))
         (size
            ;; A chart: its own SVG, nested.
            (progn
              (push (replace-regexp-in-string "\\`<svg " (format "<svg x=\"%d\" y=\"%d\" " pad y) data) parts)
              (setq width (max width (+ (* 2 pad) (round (car size)))))
              (cl-incf y (round (cdr size)))))
         (t
          (let ((col 0)
                (spans nil))
            (dolist (run (agent-ui-snapshot--runs line))
              (push (agent-ui-snapshot--run (car run) col y
                                            (agent-ui-snapshot--color (cdr run) :foreground fg)
                                            (agent-ui-snapshot--bold-p (cdr run)) cw lh)
                    spans)
              (cl-incf col (string-width (car run))))
            (push (string-join (nreverse spans)) parts)
            (cl-incf y lh))))))
    (let ((height (+ y pad)))
      (concat (format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" font-family=\"%s\" font-size=\"%d\" xml:space=\"preserve\" style=\"white-space:pre\">"
                      width height (xml-escape-string family) (round (* 0.8 lh)))
              (format "<rect width=\"100%%\" height=\"100%%\" rx=\"6\" fill=\"%s\"/>" bg)
              (string-join (nreverse parts))
              "</svg>"))))

;; ====== A SNAPSHOT ======

(cl-defun agent-ui-snapshot (id &key canvas directory)
  "Save element ID of CANVAS as it's drawn, an SVG file in DIRECTORY's
`agent-ui-snapshot-directory' (DIRECTORY: the agent's, else the current
one). Returns (:file FILE :markdown \"![TITLE](FILE)\")."
  (let* ((element (agent-ui-get id :canvas canvas))
         (frame (selected-frame))
         (ctx (agent-ui-context :width agent-ui-snapshot-width :graphic (display-graphic-p frame)
                                :char-width (if (display-graphic-p frame) (frame-char-width frame) 8)
                                :line-height (if (display-graphic-p frame) (frame-char-height frame) 17)))
         (dir (expand-file-name agent-ui-snapshot-directory (or directory default-directory)))
         (file (expand-file-name (format "agent-ui-%s-%s.svg" id (format-time-string "%Y%m%d-%H%M%S")) dir))
         (title (or (plist-get element :title) id)))
    (make-directory dir t)
    (let ((coding-system-for-write 'utf-8))
      (write-region (agent-ui-snapshot-svg (agent-ui-render element ctx) ctx) nil file nil 'silent))
    (list :file file :markdown (format "![%s](%s)" (string-replace "]" ")" title) file))))

;; ====== INTO THE PROMPT ======

(defun agent-ui--element-at-point ()
  "The id of the element at point, in a canvas."
  (or (get-text-property (point) 'agent-ui-id)
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
