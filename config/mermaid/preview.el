;;; $DOOMDIR/config/mermaid/preview.el -*- lexical-binding: t; -*-
;; A Mermaid buffer's preview beside it. Loaded from config/mermaid.el.

;; THE PREVIEW (see config/mermaid.el)
(defvar-local +my/mermaid-preview--buffer nil
  "In a Mermaid buffer: its preview's buffer.")

(defvar-local +my/mermaid-preview--source nil
  "In a preview's buffer: its Mermaid buffer.")

(defvar-local +my/mermaid-preview--timer nil)

(defvar-local +my/mermaid-preview--file nil
  "In a Mermaid buffer: its preview page's file.")

(defun +my/mermaid-preview--text (&optional buffer)
  "BUFFER's (default: the current one) diagram, as it is now."
  (with-current-buffer (or buffer (current-buffer))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +my/mermaid-preview--webkit-p ()
  "Non-nil if a preview is a WebKit page here (mermaid.js there, or
downloaded now)."
  (and (+my/webkit-p) (+my/mermaid-js-ensure)))

(defun +my/mermaid-preview-live-p ()
  "Non-nil if the preview works here: the GUI, WebKit or SVG images (mmdc's)."
  (or (+my/webkit-p)
      (and (display-graphic-p) (image-type-available-p 'svg) (executable-find +my/mermaid-mmdc))))

;; ====== IN WEBKIT ======

(defun +my/mermaid-preview--url (_window)
  "The page a new view of the preview loads, written anew: the diagram as it
is now."
  (let ((src +my/mermaid-preview--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (let ((page (+my/mermaid-preview-page (+my/mermaid-preview--text))))
          (let ((coding-system-for-write 'utf-8-unix))
            (with-temp-file +my/mermaid-preview--file
              (insert page))))
        (+my/webkit-file-url +my/mermaid-preview--file)))))

(defun +my/mermaid-preview--loaded (xwidget)
  "XWIDGET's page has loaded: the diagram as it is now."
  (let ((src +my/mermaid-preview--source))
    (when (buffer-live-p src)
      (+my/webkit-execute (+my/mermaid-preview-show-script (+my/mermaid-preview--text src))
                          xwidget))))

(defun +my/mermaid-preview--background ()
  "The preview's background: the theme's."
  (car (+my/mermaid-page-colours)))

(defvar-local +my/mermaid-preview--background-cookie nil)

(defun +my/mermaid-preview--paint ()
  "What the views don't cover, in the page's colour."
  (when +my/mermaid-preview--background-cookie
    (face-remap-remove-relative +my/mermaid-preview--background-cookie))
  (let ((background (+my/mermaid-preview--background)))
    (setq +my/mermaid-preview--background-cookie
          (and (not (string-empty-p background))
               (face-remap-add-relative 'default :background background)))))

(defun +my/mermaid-preview--closed-h ()
  "The preview's pane closed (q, its tab's ✕...): its buffer's preview off."
  (let ((preview (current-buffer))
        (src +my/mermaid-preview--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (when (and +my/mermaid-preview-mode (eq +my/mermaid-preview--buffer preview))
          (setq +my/mermaid-preview--buffer nil) ; it's going already
          (+my/mermaid-preview-mode -1))))))

(define-derived-mode +my/mermaid-preview-page-mode +my/webkit-mode "Diagram"
  "A Mermaid buffer's preview, drawn by mermaid.js in WebKit (see
`+my/mermaid-preview-mode').

\\{+my/mermaid-preview-page-mode-map}"
  (setq-local +my/webkit-url-function #'+my/mermaid-preview--url
              +my/webkit-background #'+my/mermaid-preview--background)
  (add-hook '+my/webkit-load-functions #'+my/mermaid-preview--loaded nil t)
  (+my/mermaid-preview--paint)
  (add-hook 'kill-buffer-hook #'+my/mermaid-preview--closed-h nil t))

;; ====== AS AN IMAGE ======
;; Without WebKit: mmdc's SVG (mermaid/render.el), as wide as it is, at most
;; the pane's (fitted), times the zoom (+, -, 0: as the page's); an error
;; under the last drawing, wrapped to the pane's width (Mermaid's lines run to
;; 200 characters), drawn again as the pane's width changes. Scrolled in
;; pixels both ways (a tall diagram is one line: Emacs's own scrolling jumps
;; past it, to a blank pane), never past its end; drawn again (typed, zoomed,
;; resized), where it was.

(defvar-local +my/mermaid-preview--svg nil "The SVG the image preview shows.")

(defvar-local +my/mermaid-preview--error nil "The image preview's error, or nil.")

(defvar-local +my/mermaid-preview--width nil "The width it was drawn for.")

(defvar-local +my/mermaid-preview--zoom 1
  "The image preview's zoom: its fitted width times it (1: fitted).")

(defun +my/mermaid-preview--wrap (text columns)
  "TEXT, each of its lines wrapped to COLUMNS: at a space, else (a longer
word) anywhere."
  (mapconcat
   (lambda (line)
     (let ((rows nil))
       (while (> (length line) columns)
         (let ((space (string-match-p " [^ ]*\\'" (substring line 0 (1+ columns)))))
           (if (and space (> space 0))
               (progn (push (substring line 0 space) rows)
                      (setq line (substring line (1+ space))))
             (push (substring line 0 columns) rows)
             (setq line (substring line columns)))))
       (string-join (nreverse (cons line rows)) "\n")))
   (split-string text "\n")
   "\n"))

(defun +my/mermaid-preview--max-zoom (image frame)
  "The most IMAGE, fitted, is zoomed in FRAME: ten times, and no larger than
Emacs draws an image there (`max-image-size': a tall diagram's height). Ten
where its size isn't known (no FRAME, or not a GUI's)."
  (let ((size (and frame (ignore-errors (image-size image t frame))))
        (most (lambda (pixels)
                (if (floatp max-image-size) (* max-image-size pixels) max-image-size))))
    (if (or (not (consp size)) (not (numberp max-image-size)))
        10
      (max 0.1 (min 10 (* 0.99 (/ (funcall most (frame-pixel-width frame)) (float (max 1 (car size)))))
                    (* 0.99 (/ (funcall most (frame-pixel-height frame)) (float (max 1 (cdr size))))))))))

(defun +my/mermaid-preview--image (width frame)
  "The image preview's SVG for a pane WIDTH pixels wide (nil: none) in FRAME:
as wide as it is, at most the pane's (fitted), times the zoom (at most
`+my/mermaid-preview--max-zoom'). Zoomed, scaled by the zoom (Emacs's own
image scaling too) and at most the fitted width times it: the fitted width
times the zoom, the SVG drawn at that size (sharp)."
  (let* ((max-width (and width (max 50 (- width 20))))
         (fitted (create-image +my/mermaid-preview--svg 'svg nil :max-width max-width :ascent 'center)))
    (unless (= +my/mermaid-preview--zoom 1)
      (setq +my/mermaid-preview--zoom
            (min +my/mermaid-preview--zoom (+my/mermaid-preview--max-zoom fitted frame))))
    (if (= +my/mermaid-preview--zoom 1)
        fitted
      (create-image +my/mermaid-preview--svg 'svg nil
                    :scale (* +my/mermaid-preview--zoom (image-compute-scaling-factor image-scaling-factor))
                    :max-width (and max-width (round (* +my/mermaid-preview--zoom max-width)))
                    :ascent 'center))))

(defun +my/mermaid-preview--draw-image ()
  "The image preview drawn anew: its SVG, its error; scrolled where it was
\(as far as it still goes)."
  (let* ((window (get-buffer-window (current-buffer) t))
         (width (and window (window-body-width window t)))
         (y (and window (+my/mermaid-preview--y window)))
         ;; The last column is the truncation's (lines are truncated).
         (columns (if window (max 10 (1- (window-body-width window))) 80))
         (inhibit-read-only t))
    (setq +my/mermaid-preview--width width)
    (erase-buffer)
    (insert "\n")
    (when +my/mermaid-preview--svg
      (insert-image (+my/mermaid-preview--image width (and window (window-frame window))) "diagram")
      (insert "\n"))
    (when +my/mermaid-preview--error
      (insert "\n" (propertize (+my/mermaid-preview--wrap +my/mermaid-preview--error columns)
                               'face 'error)
              "\n"))
    (unless (or +my/mermaid-preview--svg +my/mermaid-preview--error)
      (insert (propertize "Drawing…" 'face 'shadow)))
    (goto-char (point-min))
    (when window
      (+my/mermaid-preview--scroll-to window y))))

(defun +my/mermaid-preview--image-fit-h (window)
  "WINDOW's size changed: the image preview drawn for its width, its scroll
kept within it."
  (with-current-buffer (window-buffer window)
    (if (eql (window-body-width window t) +my/mermaid-preview--width)
        (+my/mermaid-preview--scroll-to window (+my/mermaid-preview--y window))
      (+my/mermaid-preview--draw-image))))

;; Scrolled: how far down, in pixels, from the lines' heights (the image's
;; is one line, as tall as it); the line there the window's start, the rest
;; its vscroll (as pixel-scroll-precision-mode does: point kept there, else
;; redisplay would scroll back to it); sideways in columns (hscroll), never
;; past the widest line's right edge.

(defun +my/mermaid-preview--measure (window)
  "The image preview as WINDOW shows it, unscrolled (`window-text-pixel-size'
takes its vscroll off each height): (WIDTH . ROWS), WIDTH its widest line's,
ROWS its lines ((START . HEIGHT)...), in pixels."
  (let ((vscroll (window-vscroll window t))
        (hscroll (window-hscroll window))
        (rows nil))
    (set-window-vscroll window 0 t t)
    (set-window-hscroll window 0)
    (unwind-protect
        (save-excursion
          (goto-char (point-min))
          (while (< (point) (point-max))
            (let ((start (point)))
              (forward-line 1)
              (push (cons start (cdr (window-text-pixel-size window start (point)))) rows)))
          (cons (car (window-text-pixel-size window (point-min) (point-max) most-positive-fixnum))
                (nreverse rows)))
      (set-window-vscroll window vscroll t t)
      (set-window-hscroll window hscroll))))

(defun +my/mermaid-preview--y (window)
  "How far down WINDOW shows the image preview, in pixels."
  (let ((start (window-start window))
        (y (window-vscroll window t)))
    (dolist (row (cdr (+my/mermaid-preview--measure window)) y)
      (when (< (car row) start)
        (setq y (+ y (cdr row)))))))

(defun +my/mermaid-preview--scroll-to (window y &optional x)
  "WINDOW shows the image preview from Y pixels down and X columns across
\(nil: as it is), within it: its bottom never above the pane's, its widest
line's right edge never left of the pane's."
  (pcase-let* ((`(,width . ,rows) (+my/mermaid-preview--measure window))
               (y (max 0 (min (or y 0)
                              (- (apply #'+ (mapcar #'cdr rows)) (window-body-height window t)))))
               (top 0))
    (while (and (cdr rows) (>= y (+ top (cdar rows))))
      (setq top (+ top (cdar rows))
            rows (cdr rows)))
    (let ((start (if rows (caar rows) (point-min)))
          (vscroll (- y top)))
      (set-window-start window start (not (zerop vscroll)))
      (set-window-vscroll window vscroll t t)
      (set-window-point window start))
    (set-window-hscroll window (max 0 (min (or x (window-hscroll window))
                                           (ceiling (- width (window-body-width window t))
                                                    (frame-char-width (window-frame window))))))))

(defun +my/mermaid-preview--scroll (dy &optional dx)
  "The image preview in the selected window scrolled DY pixels down, DX
columns right."
  (let ((window (selected-window)))
    (+my/mermaid-preview--scroll-to window (+ (+my/mermaid-preview--y window) dy)
                                    (+ (window-hscroll window) (or dx 0)))))

(defun +my/mermaid-preview-image-down (&optional count)
  "j: the diagram scrolled down, as a page is."
  (interactive "p")
  (+my/mermaid-preview--scroll (* (or count 1) +my/webkit-scroll-step)))

(defun +my/mermaid-preview-image-up (&optional count)
  "k: the diagram scrolled up."
  (interactive "p")
  (+my/mermaid-preview--scroll (- (* (or count 1) +my/webkit-scroll-step))))

(defun +my/mermaid-preview--columns (pixels)
  "PIXELS as columns of the selected window's frame, at least one."
  (max 1 (round pixels (frame-char-width))))

(defun +my/mermaid-preview-image-left (&optional count)
  "h: the diagram scrolled left (wider than its pane)."
  (interactive "p")
  (+my/mermaid-preview--scroll 0 (- (* (or count 1) (+my/mermaid-preview--columns +my/webkit-scroll-step)))))

(defun +my/mermaid-preview-image-right (&optional count)
  "l: the diagram scrolled right (wider than its pane)."
  (interactive "p")
  (+my/mermaid-preview--scroll 0 (* (or count 1) (+my/mermaid-preview--columns +my/webkit-scroll-step))))

(defun +my/mermaid-preview-image-half-screen-down ()
  "C-d: half a screen down."
  (interactive)
  (+my/mermaid-preview--scroll (/ (window-body-height nil t) 2)))

(defun +my/mermaid-preview-image-half-screen-up ()
  "C-u: half a screen up."
  (interactive)
  (+my/mermaid-preview--scroll (- (/ (window-body-height nil t) 2))))

(defun +my/mermaid-preview-image-screen-down ()
  "A screen down (C-v, Space...)."
  (interactive)
  (+my/mermaid-preview--scroll (round (* 0.9 (window-body-height nil t)))))

(defun +my/mermaid-preview-image-screen-up ()
  "A screen up (M-v...)."
  (interactive)
  (+my/mermaid-preview--scroll (- (round (* 0.9 (window-body-height nil t))))))

(defun +my/mermaid-preview-image-top ()
  "gg: the diagram's top, as a page's (its left too)."
  (interactive)
  (+my/mermaid-preview--scroll-to (selected-window) 0 0))

(defun +my/mermaid-preview-image-bottom ()
  "G: the diagram's bottom, as a page's (its left too)."
  (interactive)
  (+my/mermaid-preview--scroll-to (selected-window) most-positive-fixnum 0))

;; Zoomed, the page or the image: the fitted width times the zoom,
;; from a tenth to ten times; 0 fitted again.
(defun +my/mermaid-preview--zoom-by (factor)
  "The preview's diagram zoomed by FACTOR; 0: fitted again."
  (if (derived-mode-p '+my/mermaid-preview-image-mode)
      (progn
        (setq +my/mermaid-preview--zoom
              (if (zerop factor) 1 (max 0.1 (min 10 (* +my/mermaid-preview--zoom factor)))))
        (+my/mermaid-preview--draw-image))
    (+my/webkit-execute (format "zoomBy(%s);" factor) t)))

(defun +my/mermaid-preview-zoom-in ()
  "The preview's diagram bigger."
  (interactive)
  (+my/mermaid-preview--zoom-by 1.25))

(defun +my/mermaid-preview-zoom-out ()
  "The preview's diagram smaller."
  (interactive)
  (+my/mermaid-preview--zoom-by 0.8))

(defun +my/mermaid-preview-zoom-reset ()
  "The preview's diagram as wide as it is, at most the pane's width."
  (interactive)
  (+my/mermaid-preview--zoom-by 0))

(defvar-local +my/mermaid-preview--asked nil
  "In an image preview: the callback of the drawing it asked for last.")

(defun +my/mermaid-preview--take-back ()
  "The image preview's last drawing asked for taken back: not drawn if it
hasn't started (see `+my/mermaid-render-cancel')."
  (when +my/mermaid-preview--asked
    (+my/mermaid-render-cancel +my/mermaid-preview--asked)
    (setq +my/mermaid-preview--asked nil)))

(defun +my/mermaid-preview--image-update (preview source)
  "Draw SOURCE in PREVIEW, an image preview, once mmdc has (now if it's in the
cache). The drawing asked before is taken back (one a pause in typing: not
run if it's still waiting, each run a Chrome); one finishing after a newer
one was asked is dropped."
  (let ((done (lambda (file message)
                (when (buffer-live-p preview)
                  (with-current-buffer preview
                    (when (equal source (and (buffer-live-p +my/mermaid-preview--source)
                                             (+my/mermaid-preview--text +my/mermaid-preview--source)))
                      (when file (setq +my/mermaid-preview--svg file))
                      (setq +my/mermaid-preview--error message)
                      (+my/mermaid-preview--draw-image)))))))
    (with-current-buffer preview
      (+my/mermaid-preview--take-back)
      (setq +my/mermaid-preview--asked done))
    (when-let* ((file (+my/mermaid-render source done)))
      (funcall done file nil))))

(define-derived-mode +my/mermaid-preview-image-mode special-mode "Diagram"
  "A Mermaid buffer's preview, mmdc's SVG (see `+my/mermaid-preview-mode').

\\{+my/mermaid-preview-image-mode-map}"
  (setq-local cursor-type nil
              truncate-lines t
              ;; Scrolled past point (at a line's start, see above), as
              ;; image-mode is.
              auto-hscroll-mode nil
              scroll-margin 0)
  (add-hook 'window-size-change-functions #'+my/mermaid-preview--image-fit-h nil t)
  (add-hook 'kill-buffer-hook #'+my/mermaid-preview--take-back nil t)
  (add-hook 'kill-buffer-hook #'+my/mermaid-preview--closed-h nil t))

;; ====== THE MODE ======

(defun +my/mermaid-preview--live-p ()
  "Non-nil while this Mermaid buffer's preview is open."
  (buffer-live-p +my/mermaid-preview--buffer))

(defun +my/mermaid-preview--update (buffer)
  "BUFFER's preview shows its diagram as it is now."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (+my/mermaid-preview--live-p)
        (let ((source (+my/mermaid-preview--text))
              (preview +my/mermaid-preview--buffer))
          (with-current-buffer preview
            (if (derived-mode-p '+my/mermaid-preview-page-mode)
                (+my/webkit-execute (+my/mermaid-preview-show-script source) t)
              (+my/mermaid-preview--image-update preview source))))))))

(defun +my/mermaid-preview--after-change-h (&rest _)
  "Typed: the preview redrawn once typing pauses."
  (when (timerp +my/mermaid-preview--timer)
    (cancel-timer +my/mermaid-preview--timer))
  (setq +my/mermaid-preview--timer
        (run-with-idle-timer (if (+my/mermaid-preview--webkit-buffer-p) 0.3 0.6) nil
                             #'+my/mermaid-preview--update (current-buffer))))

(defun +my/mermaid-preview--webkit-buffer-p ()
  "Non-nil if this buffer's preview is a WebKit page."
  (and (+my/mermaid-preview--live-p)
       (with-current-buffer +my/mermaid-preview--buffer
         (derived-mode-p '+my/mermaid-preview-page-mode))))

(defvar +my/focus-new-windows)          ; config/emacs.el

(defun +my/mermaid-preview--display (preview)
  "Show PREVIEW beside the Mermaid buffer, half its window's width. The cursor
stays in the Mermaid buffer: the preview follows it."
  (let ((+my/focus-new-windows nil))
    (display-buffer preview
                    `(display-buffer-in-direction
                      (direction . right)
                      (window-width . ,(/ (window-total-width) 2))))))

(defun +my/mermaid-preview--kill (preview)
  "PREVIEW killed, its panes quit as `quit-window' does: a pane made for it
closes, unless other tabs are under it (they show instead); one it took
over shows what it showed before. SPC m p and q close it so, the same."
  (let ((kill-buffer-quit-windows t)
        (kill-buffer-query-functions nil))
    (kill-buffer preview)))

(defun +my/mermaid-preview-quit ()
  "q in the preview: closed, as SPC m p in its file closes it."
  (interactive)
  (+my/mermaid-preview--kill (current-buffer)))

(defun +my/mermaid-preview--off-h ()
  "The Mermaid buffer killed, or its mode set again: its preview goes too."
  (+my/mermaid-preview-mode -1))

(define-minor-mode +my/mermaid-preview-mode
  "A Mermaid buffer's diagram drawn beside it, redrawn as you type (see THE
PREVIEW in config/mermaid.el)."
  :lighter " Preview"
  (if +my/mermaid-preview-mode
      (let* ((src (current-buffer))
             (webkit (+my/mermaid-preview--webkit-p))
             (preview (generate-new-buffer (format "Diagram: %s" (buffer-name)))))
        (setq +my/mermaid-preview--buffer preview)
        (when webkit
          (setq +my/mermaid-preview--file (make-temp-file "mermaid-preview-" nil ".html")))
        (with-current-buffer preview
          (if webkit (+my/mermaid-preview-page-mode) (+my/mermaid-preview-image-mode))
          (setq +my/mermaid-preview--source src))
        (+my/mermaid-preview--display preview)
        (unless webkit
          (with-current-buffer preview (+my/mermaid-preview--draw-image))
          (+my/mermaid-preview--update src))
        (add-hook 'after-change-functions #'+my/mermaid-preview--after-change-h nil t)
        (add-hook 'kill-buffer-hook #'+my/mermaid-preview--off-h nil t)
        (add-hook 'change-major-mode-hook #'+my/mermaid-preview--off-h nil t))
    (remove-hook 'after-change-functions #'+my/mermaid-preview--after-change-h t)
    (remove-hook 'kill-buffer-hook #'+my/mermaid-preview--off-h t)
    (remove-hook 'change-major-mode-hook #'+my/mermaid-preview--off-h t)
    (when (timerp +my/mermaid-preview--timer)
      (cancel-timer +my/mermaid-preview--timer))
    (when (+my/mermaid-preview--live-p)
      (let ((preview +my/mermaid-preview--buffer))
        (setq +my/mermaid-preview--buffer nil)
        (+my/mermaid-preview--kill preview)))
    (+my/mermaid-preview--delete-page)))

;; The WebKit preview's page is a temporary file, deleted when the preview
;; goes, or Emacs does (no buffer is killed then).
(defun +my/mermaid-preview--delete-page ()
  "This Mermaid buffer's preview page deleted (see above)."
  (when (and +my/mermaid-preview--file (file-exists-p +my/mermaid-preview--file))
    (delete-file +my/mermaid-preview--file))
  (setq +my/mermaid-preview--file nil))

(defun +my/mermaid-preview--delete-pages-h ()
  "Emacs is exiting: each preview's page deleted (see above)."
  (dolist (buffer (buffer-list))
    (when (buffer-local-value '+my/mermaid-preview--file buffer)
      (with-current-buffer buffer
        (ignore-errors (+my/mermaid-preview--delete-page))))))

(add-hook 'kill-emacs-hook #'+my/mermaid-preview--delete-pages-h)

(defun +my/mermaid-preview--shown-p ()
  "Non-nil while this Mermaid buffer's preview is open and on screen."
  (and (+my/mermaid-preview--live-p) (get-buffer-window +my/mermaid-preview--buffer t)))

(defun +my/mermaid-preview-show ()
  "The preview, on screen: opened if off, shown again if its pane was closed
\(it stays on), else nothing. In a terminal: Mermaid's Live Editor instead."
  (interactive)
  (cond ((not (+my/mermaid-preview-live-p))
         (if (display-graphic-p)
             (message "%s" +my/mermaid--install)
           (mermaid-open-browser)))
        ((not +my/mermaid-preview-mode) (+my/mermaid-preview-mode 1))
        ((not (+my/mermaid-preview--live-p)) ; its buffer gone: anew
         (+my/mermaid-preview-mode -1)
         (+my/mermaid-preview-mode 1))
        ((not (+my/mermaid-preview--shown-p))
         (+my/mermaid-preview--display +my/mermaid-preview--buffer))))

(defun +my/mermaid-preview-toggle ()
  "SPC m p: the preview closed if it's on screen, else shown."
  (interactive)
  (if (+my/mermaid-preview--shown-p)
      (+my/mermaid-preview-mode -1)
    (+my/mermaid-preview-show)))

;; THE THEME, CHANGED: each preview in the new theme's colours, in place.
(defun +my/mermaid-preview-theme-h ()
  "Each preview in the theme's colours (see above)."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (cond ((derived-mode-p '+my/mermaid-preview-page-mode)
             (+my/mermaid-preview--paint)
             (+my/webkit-execute (+my/mermaid-preview-theme-script) t))
            ((derived-mode-p '+my/mermaid-preview-image-mode)
             (+my/mermaid-preview--update +my/mermaid-preview--source))))))

(add-hook '+my/mermaid-theme-hook #'+my/mermaid-preview-theme-h)
