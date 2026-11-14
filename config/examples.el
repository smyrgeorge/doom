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
;;   mermaid     a Mermaid file and its preview (config/mermaid.el)
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
;;               cpu panel, filled every second
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

(defvar +my/example--folders nil
  "The examples' folders not deleted yet: (DIR THEN) each, see
`+my/example-delete-when-closed'.")

(defvar-local +my/example--closing nil
  "In an example's buffer: its folder's entry in `+my/example--folders',
\(DIR THEN).")
(put '+my/example--closing 'permanent-local t)

(defun +my/example--in-p (dir buffer)
  "Non-nil if BUFFER visits a file in DIR (a true name)."
  (when-let* ((true (buffer-local-value 'buffer-file-truename buffer)))
    (string-prefix-p dir (expand-file-name true))))

(defun +my/example--buffers (dir)
  "The live buffers of example folder DIR: given it, or visiting a file in
it."
  (seq-filter (lambda (buffer)
                (or (equal (car (buffer-local-value '+my/example--closing buffer)) dir)
                    (+my/example--in-p dir buffer)))
              (buffer-list)))

(defun +my/example--track (buffer entry)
  "BUFFER one of ENTRY's folder's (see `+my/example--folders'): its folder
deleted once it's closed, if it's the last."
  (with-current-buffer buffer
    (setq +my/example--closing entry)
    (add-hook 'kill-buffer-hook #'+my/example--closed-h nil t)))

(defun +my/example-delete-when-closed (dir buffers &optional then)
  "Delete DIR once BUFFERS are all closed (killed): the example's files go
with it. THEN, a function, is called then too. Kept through a change of
mode (a buffer going to `so-long-mode'...). Each buffer visiting a file in
DIR, now or later (J in the image example, a file opened from its
folder), counts too; none: deleted now."
  (let ((entry (list dir then)))
    (push entry +my/example--folders)
    (dolist (buffer (seq-uniq (append (seq-filter #'buffer-live-p buffers)
                                      (+my/example--buffers dir))))
      (+my/example--track buffer entry))
    (+my/example--delete-if-closed entry)))

(defun +my/example--delete-if-closed (entry &optional closing)
  "Delete ENTRY's folder (see `+my/example--folders') if none of its
buffers is left, but CLOSING (one being killed); call its THEN."
  (pcase-let ((`(,dir ,then) entry))
    (when (and (memq entry +my/example--folders)
               (not (delq closing (+my/example--buffers dir))))
      (setq +my/example--folders (delq entry +my/example--folders))
      (ignore-errors (delete-directory dir t))
      (when then (funcall then)))))

(defun +my/example--closed-h ()
  "An example's buffer closed: the last of its folder's? Its folder deleted
\(see `+my/example-delete-when-closed'). Replaced by another of its files
\(`find-alternate-file', which runs this before visiting it: J / K in the
image example), once that's open."
  (let ((entry +my/example--closing))
    (if (bound-and-true-p find-alternate-file-dont-kill-client)
        (run-at-time 0 nil #'+my/example--delete-if-closed entry)
      (+my/example--delete-if-closed entry (current-buffer)))))
(put '+my/example--closed-h 'permanent-local-hook t)

(defun +my/example--visited-h ()
  "A file visited in an example's folder: one of its buffers."
  (when-let* (((and +my/example--folders (not +my/example--closing)))
              (entry (seq-find (lambda (entry) (+my/example--in-p (car entry) (current-buffer)))
                               +my/example--folders)))
    (+my/example--track (current-buffer) entry)))

(add-hook 'find-file-hook #'+my/example--visited-h)

;; M-x +my/example-NAME: each loads its file when first run.
(dolist (name (+my/examples))
  (autoload (intern (format "+my/example-%s" name))
            (expand-file-name name +my/examples-dir)
            (format "Example: %s (see examples/%s.el)." name name)
            t))
