;;; $DOOMDIR/config/image/diff.el -*- lexical-binding: t; -*-
;; The image as it is in git's HEAD, beside it. Loaded from config/image.el.

(defvar-local +my/image--head-commit nil
  "In the image as it is in git's HEAD: HEAD's commit, short.")

(defvar-local +my/image--head-buffer nil
  "The image as it is in git's HEAD, opened from this one.")

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

(defun +my/image--same-bytes-p (bytes)
  "Non-nil if BYTES are the image's, as saved."
  (and (not (buffer-modified-p))
       (let ((file buffer-file-name))
         (with-temp-buffer
           (set-buffer-multibyte nil)
           (insert-file-contents-literally file)
           (string= (buffer-string) bytes)))))

(defun +my/image-diff ()
  "SPC m g: the image as it is in git's HEAD, in a pane on its left, to
compare; again, closed (see config/image.el)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (if (+my/image--head-shown-p)
      (+my/image--close-head)
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
            (image (current-buffer)))
        (with-current-buffer buffer
          (set-buffer-multibyte nil)
          (insert bytes)
          (setq default-directory (file-name-directory file))
          (image-mode)
          ;; After: image-mode kills the buffer's local variables.
          (setq +my/image--head-of file
                +my/image--head-commit commit)
          (set-buffer-modified-p nil)
          (setq buffer-read-only t)
          ;; Closed (q, its tab): the image's Diff button off.
          (add-hook 'kill-buffer-hook
                    (lambda () (when (buffer-live-p image)
                                 (with-current-buffer image (force-mode-line-update t))))
                    nil t))
        (setq +my/image--head-buffer buffer)
        (display-buffer buffer '((display-buffer-in-direction)
                                 (direction . left)
                                 (window-width . 0.5)))
        (force-mode-line-update t)))))
