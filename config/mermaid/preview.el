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

(defun +my/mermaid-preview-zoom-in ()
  "The preview's diagram bigger."
  (interactive)
  (+my/webkit-execute "zoomBy(1.25);" t))

(defun +my/mermaid-preview-zoom-out ()
  "The preview's diagram smaller."
  (interactive)
  (+my/webkit-execute "zoomBy(0.8);" t))

(defun +my/mermaid-preview-zoom-reset ()
  "The preview's diagram as wide as it is, at most the pane's width."
  (interactive)
  (+my/webkit-execute "zoomBy(0);" t))

;; ====== AS AN IMAGE ======
;; Without WebKit: mmdc's SVG (mermaid/render.el), as wide as it is, at most
;; the pane's; an error under the last drawing.

(defvar-local +my/mermaid-preview--svg nil "The SVG the image preview shows.")

(defvar-local +my/mermaid-preview--error nil "The image preview's error, or nil.")

(defvar-local +my/mermaid-preview--width nil "The width it was drawn for.")

(defun +my/mermaid-preview--draw-image ()
  "The image preview drawn anew: its SVG, its error."
  (let* ((window (get-buffer-window (current-buffer) t))
         (width (and window (window-body-width window t)))
         (inhibit-read-only t))
    (setq +my/mermaid-preview--width width)
    (erase-buffer)
    (insert "\n")
    (when +my/mermaid-preview--svg
      (insert-image (create-image +my/mermaid-preview--svg 'svg nil
                                  :max-width (and width (max 50 (- width 20)))
                                  :ascent 'center)
                    "diagram")
      (insert "\n"))
    (when +my/mermaid-preview--error
      (insert "\n" (propertize +my/mermaid-preview--error 'face 'error) "\n"))
    (unless (or +my/mermaid-preview--svg +my/mermaid-preview--error)
      (insert (propertize "Drawing…" 'face 'shadow)))
    (goto-char (point-min))))

(defun +my/mermaid-preview--image-fit-h (window)
  "WINDOW's width changed: the image preview drawn for it."
  (with-current-buffer (window-buffer window)
    (unless (eql (window-body-width window t) +my/mermaid-preview--width)
      (+my/mermaid-preview--draw-image))))

(defun +my/mermaid-preview--image-update (preview source)
  "Draw SOURCE in PREVIEW, an image preview, once mmdc has (now if it's in the
cache); a drawing finishing after a newer one was asked is dropped."
  (let ((done (lambda (file message)
                (when (buffer-live-p preview)
                  (with-current-buffer preview
                    (when (equal source (and (buffer-live-p +my/mermaid-preview--source)
                                             (+my/mermaid-preview--text +my/mermaid-preview--source)))
                      (when file (setq +my/mermaid-preview--svg file))
                      (setq +my/mermaid-preview--error message)
                      (+my/mermaid-preview--draw-image)))))))
    (when-let* ((file (+my/mermaid-render source done)))
      (funcall done file nil))))

(define-derived-mode +my/mermaid-preview-image-mode special-mode "Diagram"
  "A Mermaid buffer's preview, mmdc's SVG (see `+my/mermaid-preview-mode').

\\{+my/mermaid-preview-image-mode-map}"
  (setq-local cursor-type nil
              truncate-lines t)
  (add-hook 'window-size-change-functions #'+my/mermaid-preview--image-fit-h nil t)
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

(defvar +my/focus-new-windows)          ; config/window.el

(defun +my/mermaid-preview--display (preview)
  "Show PREVIEW beside the Mermaid buffer, half its window's width. The cursor
stays in the Mermaid buffer: the preview follows it."
  (let ((+my/focus-new-windows nil))
    (display-buffer preview
                    `(display-buffer-in-direction
                      (direction . right)
                      (window-width . ,(/ (window-total-width) 2))))))

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
        (dolist (window (get-buffer-window-list preview nil t))
          (ignore-errors (delete-window window)))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer preview))))
    (when (and +my/mermaid-preview--file (file-exists-p +my/mermaid-preview--file))
      (delete-file +my/mermaid-preview--file))
    (setq +my/mermaid-preview--file nil)))

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
