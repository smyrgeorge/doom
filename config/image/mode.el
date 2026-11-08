;;; $DOOMDIR/config/image/mode.el -*- lexical-binding: t; -*-
;; The images' toolbar and keys in image-mode buffers. Loaded from
;; config/image.el.

(defvar image--transform-smoothing)
(defvar evil-normal-state-cursor)
(defvar evil-motion-state-cursor)

(defconst +my/image--header '(:eval (+my/image--toolbar))
  "The header line, with the toolbar on.")

(defun +my/image--show-toolbar (on)
  "The toolbar in the buffer's header line ON or off, the notices kept
(config/banner.el makes room in the header line before its own content)."
  (let ((header (and on +my/image--header)))
    (if (and (fboundp '+my/banner--ours-p) (+my/banner--ours-p))
        (setq-local +my/banner--saved-header header
                    header-line-format (list (car header-line-format) header))
      (setq-local header-line-format header))))

(defun +my/image--buffers ()
  "The buffers showing an image with its toolbar."
  (seq-filter (lambda (buffer) (buffer-local-value '+my/image-mode buffer))
              (buffer-list)))

(defun +my/image-toggle-toolbar ()
  "SPC m t: the toolbar on or off, in every image (the next ones too)."
  (interactive)
  (setq +my/image-toolbar (not +my/image-toolbar))
  (dolist (buffer (+my/image--buffers))
    (with-current-buffer buffer
      (+my/image--show-toolbar +my/image-toolbar)))
  (force-mode-line-update t))

(define-minor-mode +my/image-mode
  "The toolbar and keys of an image in image-mode (see config/image.el).

\\{+my/image-mode-map}"
  :lighter nil
  (cond
   (+my/image-mode
    (+my/image--show-toolbar +my/image-toolbar)
    (when +my/image-sharp
      (setq image--transform-smoothing "none"))
    ;; A file changed on disk shown anew, the zoom kept (reverted with its
    ;; modes: image-mode's buffer-local transforms stay).
    (when (and buffer-file-name (not (file-remote-p buffer-file-name)))
      (auto-revert-mode 1))
    (add-hook 'kill-buffer-hook #'+my/image--close-head nil t)
    ;; No cursor: image-mode has none, but Evil's normal state drew its box
    ;; around the whole image (as Doom does for pdf-tools).
    (setq-local evil-normal-state-cursor (list nil)
                evil-motion-state-cursor (list nil)
                cursor-in-non-selected-windows nil)
    (when (fboundp 'evil-refresh-cursor)
      (evil-refresh-cursor))
    ;; In the middle of its windows (center.el).
    (add-hook 'window-size-change-functions #'+my/image--center-h nil t)
    (add-hook 'window-buffer-change-functions #'+my/image--center-h nil t)
    (+my/image-center))
   (t
    (+my/image--show-toolbar nil)
    (when (bound-and-true-p auto-revert-mode)
      (auto-revert-mode -1))
    (remove-hook 'kill-buffer-hook #'+my/image--close-head t)
    (dolist (variable '(evil-normal-state-cursor evil-motion-state-cursor
                        cursor-in-non-selected-windows))
      (kill-local-variable variable))
    (remove-hook 'window-size-change-functions #'+my/image--center-h t)
    (remove-hook 'window-buffer-change-functions #'+my/image--center-h t)
    (+my/image--uncenter)))
  ;; The mode's Evil keys (`map!''s :n) active at once.
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(defun +my/image-mode-maybe-h ()
  "image-mode's hook: the toolbar and keys, where the image shows (not as
text: `image-minor-mode')."
  (when (derived-mode-p 'image-mode)
    (+my/image-mode 1)))

(add-hook 'image-mode-hook #'+my/image-mode-maybe-h)
