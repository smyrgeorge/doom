;;; $DOOMDIR/config/markdown/browser.el -*- lexical-binding: t; -*-
;; SPC m P: the live preview's page in the browser. Loaded from
;; config/markdown.el.

;; IN THE BROWSER (see config/markdown.el)
;; The page the live preview shows (`+md-preview--page': GitHub's look in the
;; theme's colours, diagrams, alerts, math, highlighted code, the file's
;; images and links), written to a file of its own for each Markdown buffer
;; (pressed again: written anew, the same file) and opened in the browser.
;; Its diagrams are drawn as it loads (in Emacs, by the update script).
;; Needs pandoc only, not WebKit; without pandoc, markdown-mode's preview.
;; The files go as Emacs exits (a browser may still show one until then).

(defvar-local +md-browser--file nil
  "In a Markdown buffer: the page written for the browser (see above).")

(defvar +md-browser--files nil
  "The pages written for the browser, deleted as Emacs exits.")

(defun +md-browser--delete-files-h ()
  "Delete the pages written for the browser (see above)."
  (dolist (file +md-browser--files)
    (ignore-errors (delete-file file)))
  (setq +md-browser--files nil))

(add-hook 'kill-emacs-hook #'+md-browser--delete-files-h)

(defun +md-browser--write ()
  "Write the buffer's page for the browser (see above); return its file."
  (unless +md-browser--file
    (setq +md-browser--file (make-temp-file "markdown-preview-" nil ".html"))
    (push +md-browser--file +md-browser--files))
  (let ((page (+md-preview--page (+md-preview--fragment) 'browser))
        (coding-system-for-write 'utf-8))
    (with-temp-file +md-browser--file
      (insert page)))
  +md-browser--file)

(defun +my/markdown-preview-browser ()
  "Show the buffer's Markdown in the browser as the live preview shows it
\(see above); without pandoc, markdown-mode's preview."
  (interactive)
  (if (not (executable-find "pandoc"))
      (markdown-preview)
    (browse-url-of-file (+md-browser--write))))
