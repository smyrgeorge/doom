;;; $DOOMDIR/config/treemacs/copy.el -*- lexical-binding: t; -*-
;; Copying the file at point. Loaded from config/treemacs.el.

;; COPY
;; Cmd+C copies the file or folder at point itself, as Finder does
;; (`+my/os-copy-file', config/emacs/os.el): pasted into Slack it's uploaded,
;; into a mail attached, into a folder copied. Its path is Option+Cmd+C's
;; (Finder's key for it), and ya's. Copied, it says so as treemacs' own copy
;; of the path does: its line flashes green and the echo area says
;; "[Treemacs] Copied file: PATH", the path in its colour.
(defun +my/treemacs-copy-file-at-point ()
  "The file or folder at point itself on the clipboard, to paste in other
apps (Cmd+C; Linux: Ctrl+Shift+C)."
  (interactive)
  (let ((path (ignore-errors (treemacs--prop-at-point :path))))
    (unless (stringp path)
      (user-error "Not a file or a folder"))
    (+my/os-copy-file path)
    (let ((folder (file-directory-p path)))
      ;; Its message is formatted twice (here and by `treemacs-log'): a % in
      ;; the path doubled, to show as one.
      (treemacs-pulse-on-success "Copied %s: %s"
        (if folder "folder" "file")
        (propertize (string-replace "%" "%%" (if folder (treemacs--add-trailing-slash path) path))
                    'face 'font-lock-string-face)))))
