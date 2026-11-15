;;; $DOOMDIR/config/image/diff.el -*- lexical-binding: t; -*-
;; The image as it is in git's HEAD, beside it. Loaded from config/image.el.

(defvar image-transform-resize)

(defvar-local +my/image--head-commit nil
  "In the image as it is in git's HEAD: HEAD's commit, short.")

(defvar-local +my/image--head-buffer nil
  "The image as it is in git's HEAD, opened from this one.")

(defvar-local +my/image--head-image nil
  "In the image as it is in git's HEAD: the image's buffer, it opened from.")

(defun +my/image--git (dir &rest args)
  "git ARGS's output in DIR, as bytes; nil if it failed."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((default-directory dir)
          (coding-system-for-read 'binary))
      (and (zerop (apply #'call-process "git" nil '(t nil) nil args))
           (buffer-string)))))

(defun +my/image--head-shown-p ()
  "Non-nil if the image's HEAD version is on screen."
  (and (buffer-live-p +my/image--head-buffer)
       (get-buffer-window +my/image--head-buffer 'visible)))

(defun +my/image--close-head ()
  "Close the image's HEAD version: its buffer and the panes showing it."
  (when (buffer-live-p +my/image--head-buffer)
    (dolist (window (get-buffer-window-list +my/image--head-buffer nil t))
      (when (eq (window-deletable-p window) t)
        (delete-window window)))
    (kill-buffer +my/image--head-buffer))
  (setq +my/image--head-buffer nil)
  (force-mode-line-update t))

;; BESIDE THE IMAGE
;; HEAD takes half of the image's own pane, on its left; the other panes keep
;; their sizes. A pane narrower than twice `+my/image-diff-min-width' is split
;; across instead, HEAD above. Its own parent window (window-combination-limit),
;; so that closing HEAD gives its room back to the image's pane alone.
(defun +my/image--head-direction (window)
  "Where the image's HEAD version goes in WINDOW: left, or above in a narrow
pane (see above)."
  (if (>= (window-total-width window) (* 2 +my/image-diff-min-width)) 'left 'above))

(defun +my/image--display-head (buffer window)
  "Show BUFFER, the image's HEAD version, in half of WINDOW, the image's pane
(see above); the window it's in."
  (let ((window-combination-limit t))
    (display-buffer buffer `((display-buffer-in-direction)
                             (window . ,window)
                             (direction . ,(+my/image--head-direction window))
                             ;; Halves: not fitted to its buffer, as
                             ;; display-buffer-in-direction does.
                             (window-height . ignore)
                             (inhibit-same-window . t)))))

(defun +my/image--refit (window)
  "The image in WINDOW fitted to it again at once, if fitted (not zoomed):
image-mode refits only after `image-auto-resize-on-window-resize' idle
seconds."
  (when (window-live-p window)
    (with-selected-window window
      (when (and (+my/image--spec) (memq image-transform-resize '(t fit-window)))
        (+my/image--redisplay)))))

(defun +my/image--refit-buffer (buffer)
  "BUFFER's image fitted again at once in each window showing it (see
`+my/image--refit')."
  (when (buffer-live-p buffer)
    (mapc #'+my/image--refit (get-buffer-window-list buffer nil t))))

;; CLOSED
;; HEAD closed from its own pane (q) goes as SPC m g closes it: its pane too,
;; the image fitted to its pane, wider again, at once. Closed otherwise (its
;; tab's ✕, its pane closing with it), the image is fitted again right after
;; too, not image-mode's second later.
(defun +my/image-quit ()
  "q: close the image; its HEAD version (SPC m g) as SPC m g closes it (see
CLOSED)."
  (interactive)
  (let ((image +my/image--head-image))
    (if (not (buffer-live-p image))
        (kill-current-buffer)
      (with-current-buffer image
        (+my/image--close-head))
      (+my/image--refit-buffer image))))

(defun +my/image--head-closed-h ()
  "HEAD's buffer killed: its image's Diff button off, the image fitted again
once HEAD's pane has gone (see CLOSED)."
  (let ((image +my/image--head-image))
    (when (buffer-live-p image)
      (with-current-buffer image (force-mode-line-update t))
      (run-at-time 0 nil #'+my/image--refit-buffer image))))

(defun +my/image--same-bytes-p (bytes)
  "Non-nil if BYTES are the image's, as saved."
  (and (not (buffer-modified-p))
       (let ((file buffer-file-name))
         (with-temp-buffer
           (set-buffer-multibyte nil)
           (insert-file-contents-literally file)
           (string= (buffer-string) bytes)))))

(defun +my/image-diff ()
  "SPC m g: the image as it is in git's HEAD, in half of its pane, on its
left (above in a narrow pane), to compare; again, closed (see
config/image.el)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (if (+my/image--head-shown-p)
      (progn (+my/image--close-head)
             (+my/image--refit (selected-window)))
    (+my/image--close-head)
    (let* ((file buffer-file-name)
           (root (when-let* ((out (+my/image--git (file-name-directory file)
                                                  "rev-parse" "--show-toplevel")))
                   (file-name-as-directory (file-truename (string-trim out)))))
           (path (and root (file-relative-name (file-truename file) root)))
           (bytes (and path (+my/image--git root "show" (concat "HEAD:" path))))
           (commit (and bytes (string-trim (+my/image--git root "rev-parse" "--short" "HEAD")))))
      (cond ((not root) (user-error "Not in a git repository"))
            ((not bytes) (user-error "%s isn't in git's HEAD" path))
            ((+my/image--same-bytes-p bytes) (user-error "No change since HEAD (%s)" commit)))
      (let ((buffer (generate-new-buffer (format "%s @ HEAD" (file-name-nondirectory file))))
            (image (current-buffer))
            ;; HEAD at the image's zoom, or fitted as it is (a wheel's zoom
            ;; not drawn yet too).
            (resize (or +my/image--zoom-target image-transform-resize)))
        (with-current-buffer buffer
          (set-buffer-multibyte nil)
          (insert bytes)
          (setq default-directory (file-name-directory file))
          (image-mode)
          ;; After: image-mode kills the buffer's local variables.
          (setq +my/image--head-of file
                +my/image--head-commit commit
                +my/image--head-image image
                image-transform-resize resize)
          (set-buffer-modified-p nil)
          (setq buffer-read-only t)
          ;; Closed (q, its tab): the image's Diff button off, refitted.
          (add-hook 'kill-buffer-hook #'+my/image--head-closed-h nil t))
        (setq +my/image--head-buffer buffer)
        ;; HEAD shown at that zoom in its pane (made in the image's), the
        ;; image fitted to its new pane.
        (let* ((window (selected-window))
               (head-window (+my/image--display-head buffer window)))
          (when (window-live-p head-window)
            (with-selected-window head-window
              (+my/image--redisplay)))
          (+my/image--refit window))
        (force-mode-line-update t)))))
