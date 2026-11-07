;;; $DOOMDIR/config/markdown/preview.el -*- lexical-binding: t; -*-
;; The preview's pane and its mode. Loaded from config/markdown.el.

;; THE PREVIEW'S PANE
;; A WebKit page (config/webkit.el) in the page's colour (also its cover while
;; a view loads: its stylesheet comes from a CDN), each new view written anew
;; from the Markdown as it is, then scrolled to the cursor's line.
(defun +md-preview--url (_window)
  "The page a new view of the preview loads (see VIEWS in config/webkit/views.el),
written anew: the Markdown as it is now."
  (let ((src +md-preview--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (let ((page (+md-preview--page (+md-preview--fragment))))
          (with-temp-file +md-preview--file
            (insert page)))
        (+my/webkit-file-url +md-preview--file)))))

(defun +md-preview--loaded (xwidget)
  "XWIDGET's page has loaded: the Markdown as it is now (back from a link,
WebKit loads the page's file again, as it was written), at the cursor's
line."
  (let ((src +md-preview--source))
    (when (buffer-live-p src)
      (+my/webkit-execute (with-current-buffer src (+md-preview--update-script))
                          xwidget))))

(defun +md-preview--follow (url)
  "A link out of the preview, to URL: a file opens in Emacs, in the Markdown
file's pane (else beside the preview); anything else in the browser."
  (if (not (string-prefix-p "file:" url))
      (browse-url url)
    (let ((file (+my/webkit-url-file url))
          (window (and (buffer-live-p +md-preview--source)
                       (get-buffer-window +md-preview--source))))
      (if (not window)
          (find-file-other-window file)
        (select-window window)
        (find-file file)))))

(defvar +md-preview-mode)               ; below

(defun +md-preview--closed-h ()
  "The preview's pane closed (q, its tab's ✕...): its Markdown buffer's
preview off."
  (let ((preview (current-buffer))
        (src +md-preview--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (when (and +md-preview-mode (eq +md-preview--buffer preview))
          (setq +md-preview--buffer nil)  ; it's going already
          (+md-preview-mode -1))))))

(define-derived-mode +md-preview-page-mode +my/webkit-mode "Preview"
  "A Markdown buffer's live preview, in WebKit (see `+md-preview-mode').

\\{+md-preview-page-mode-map}"
  (setq-local +my/webkit-url-function #'+md-preview--url
              +my/webkit-background #'+md-preview--page-color
              +my/webkit-link-function #'+md-preview--follow)
  (add-hook '+my/webkit-load-functions #'+md-preview--loaded nil t)
  ;; What the views don't cover, in the page's colour.
  (face-remap-add-relative 'default :background (+md-preview--page-color))
  (add-hook 'kill-buffer-hook #'+md-preview--closed-h nil t))

(defvar +my/focus-new-windows)          ; config/window.el

(defun +md-preview--off-h ()
  "The Markdown buffer killed, or its mode set again (its variables, this mode's
too, gone): its preview goes too."
  (+md-preview-mode -1))

(define-minor-mode +md-preview-mode
  "Live, cursor-following markdown preview in a WebKit pane beside the file."
  :lighter " MdPrev"
  (if +md-preview-mode
      (let ((src (current-buffer))
            (preview (generate-new-buffer (format "Preview: %s" (buffer-name)))))
        (setq +md-preview--file (make-temp-file "md-preview-" nil ".html")
              +md-preview--buffer preview)
        (with-current-buffer preview
          (+md-preview-page-mode)
          (setq +md-preview--source src))
        ;; Beside the file, half its window's width (a float would be half the
        ;; frame's: in a narrow window the file was left a few columns). The
        ;; cursor stays in the Markdown buffer: the preview follows it.
        (let ((+my/focus-new-windows nil))
          (display-buffer preview
                          `(display-buffer-in-direction
                            (direction . right)
                            (window-width . ,(/ (window-total-width) 2)))))
        (add-hook 'after-change-functions #'+md-preview--after-change-h nil t)
        (add-hook 'post-command-hook #'+md-preview--post-command-h nil t)
        (add-hook 'kill-buffer-hook #'+md-preview--off-h nil t)
        (add-hook 'change-major-mode-hook #'+md-preview--off-h nil t))
    (remove-hook 'after-change-functions #'+md-preview--after-change-h t)
    (remove-hook 'post-command-hook #'+md-preview--post-command-h t)
    (remove-hook 'kill-buffer-hook #'+md-preview--off-h t)
    (remove-hook 'change-major-mode-hook #'+md-preview--off-h t)
    (when (timerp +md-preview--timer) (cancel-timer +md-preview--timer))
    (when (+md-preview--live-p)
      (let ((preview +md-preview--buffer))
        (setq +md-preview--buffer nil)
        (dolist (window (get-buffer-window-list preview nil t))
          ;; The frame's only window: it shows another buffer once the
          ;; preview is gone.
          (ignore-errors (delete-window window)))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer preview))))
    (when (and +md-preview--file (file-exists-p +md-preview--file))
      (delete-file +md-preview--file))
    (setq +md-preview--file nil +md-preview--line nil)))

(defun +my/markdown-preview-live-p ()
  "Non-nil if the live preview works here (GUI, xwidgets, pandoc)."
  (and (+my/webkit-p) (executable-find "pandoc")))

(defun +my/markdown-preview-toggle ()
  "SPC m p: live preview in Emacs (WebKit in GUI, eww in a terminal)."
  (interactive)
  (if (+my/markdown-preview-live-p)
      (+md-preview-mode 'toggle)
    (markdown-live-preview-mode 'toggle)))
