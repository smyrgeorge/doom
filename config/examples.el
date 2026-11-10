;;; $DOOMDIR/config/examples.el -*- lexical-binding: t; -*-
;; Examples of the features that need something set up to be seen. Loaded from
;; config.el; the examples themselves only when run.

;; ====== VARIABLES ======

;; EXAMPLES
;; examples/NAME.el shows a feature on files of its own, in the temp folder:
;; M-x +my/example picks one, or M-x +my/example-NAME runs it. Each opens the
;; feature as you'd come to it and leaves nothing behind (its files deleted
;; once you're done with it: its buffers closed). Its screenshot is
;; examples/NAME.png (scripts/screenshots.sh). So far:
;;   merge       conflicts resolved in three panes (config/merge.el): a temp
;;               repository merging a branch, in conflict every way
;;   pdf         a PDF in WebKit (config/pdf.el), its pages dark
;;   image       a picture in the image viewer (config/image.el), changed
;;               since git's HEAD, its version there beside it
;;   markdown    a Markdown file and its live preview (config/markdown.el)
;;   excalidraw  a drawing in Excalidraw (config/excalidraw.el)
;;   stripe      the error stripe (config/stripe.el) of a file with errors,
;;               warnings and git changes
;;   tiling      a project's files in panes laid out by the tiling strategy
;;               (config/tiling.el)
;;   banner      notices at the top of a window (config/banner.el), of each
;;               kind
;;   agent-ui    an agent's canvas (config/agent-ui.el) beside its
;;               conversation, filled in as it works
;;   issues      a small project's issues in their list (config/beads.el),
;;               tracked with bd
;;   panel       a project's panel (config/agent-ui/panels.el): this config's
;;               cpu panel, filled every second (macOS)
;; An example may define `+my/example-NAME-ready': non-nil once it's drawn
;; (a WebKit page loaded...), which the screenshots wait for.
(defvar +my/examples-dir (expand-file-name "examples/" doom-user-dir)
  "Where the examples are (see above).")

;; ====== CODE ======

(defun +my/examples ()
  "The examples' names (examples/NAME.el)."
  (and (file-directory-p +my/examples-dir)
       (mapcar #'file-name-sans-extension
               (directory-files +my/examples-dir nil "\\`[^.].*\\.el\\'"))))

(defun +my/example (name)
  "Run example NAME (see above), picked in the minibuffer."
  (interactive (list (completing-read "Example: " (+my/examples) nil t)))
  (unless (member name (+my/examples))
    (user-error "No example %s in %s" name +my/examples-dir))
  (call-interactively (intern (format "+my/example-%s" name))))

;; FOR THE EXAMPLES
(defun +my/example-folder (name)
  "A new folder for example NAME in the temp folder (by its true name)."
  (file-name-as-directory (file-truename (make-temp-file (format "%s-example-" name) t))))

(defun +my/example-write (dir file text)
  "Write TEXT (UTF-8) to FILE in DIR; its full name."
  (let ((path (expand-file-name file dir))
        (coding-system-for-write 'utf-8-unix))
    (make-directory (file-name-directory path) t)
    (write-region text nil path nil 'silent)
    path))

(defvar-local +my/example--closing nil
  "In an example's buffer: (DIR BUFFERS THEN), see
`+my/example-delete-when-closed'.")
(put '+my/example--closing 'permanent-local t)

(defun +my/example-delete-when-closed (dir buffers &optional then)
  "Delete DIR once BUFFERS are all closed (killed): the example's files go
with it. THEN, a function, is called then too. Kept through a change of
mode (a buffer going to `so-long-mode'...)."
  (let ((buffers (seq-filter #'buffer-live-p buffers)))
    (dolist (buffer buffers)
      (with-current-buffer buffer
        (setq +my/example--closing (list dir buffers then))
        (add-hook 'kill-buffer-hook #'+my/example--closed-h nil t)))))

(defun +my/example--closed-h ()
  "An example's buffer closed: the last one? Its folder deleted (see
`+my/example-delete-when-closed')."
  (pcase-let ((`(,dir ,buffers ,then) +my/example--closing))
    (unless (seq-some (lambda (buffer) (and (not (eq buffer (current-buffer))) (buffer-live-p buffer)))
                      buffers)
      (ignore-errors (delete-directory dir t))
      (when then (funcall then)))))
(put '+my/example--closed-h 'permanent-local-hook t)

;; M-x +my/example-NAME: each loads its file when first run.
(dolist (name (+my/examples))
  (autoload (intern (format "+my/example-%s" name))
            (expand-file-name name +my/examples-dir)
            (format "Example: %s (see examples/%s.el)." name name)
            t))
