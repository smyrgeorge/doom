;;; $DOOMDIR/config/mermaid/mode.el -*- lexical-binding: t; -*-
;; mermaid-mode's commands in the theme's colours; Org's mermaid blocks.
;; Loaded from config/mermaid.el.

;; MERMAID FILES (see config/mermaid.el)
;; Its commands run mmdc with `mermaid-flags', which name the theme's config:
;; written first (a theme switch since changed it, or a new session), and the
;; temp folder the buffer's and region's commands write to made.
(defadvice! +my/mermaid-before-mmdc-a (&rest _)
  "The theme's config written and `mermaid-tmp-dir' made, before mermaid-mode
runs mmdc."
  :before '(mermaid-compile-file mermaid-compile-buffer mermaid-compile-region
            org-babel-execute:mermaid)
  (+my/mermaid-write-config)
  (make-directory mermaid-tmp-dir t))

;; Drawing a file (the buffer's and region's write theirs first), through
;; the renderer (mermaid/render.el): in the background, Emacs never waits; its
;; SVG next to the file, opened once drawn (shown anew if it's open); an error
;; in *mmdc*. Another format than SVG (`mermaid-output-format'): mermaid-mode's
;; own way.
(defadvice! +my/mermaid-compile-file-a (fn file-name)
  "Draw FILE-NAME through the renderer (see above)."
  :around #'mermaid-compile-file
  (if (not (equal mermaid-output-format ".svg"))
      (funcall fn file-name)
    (let* ((input (expand-file-name file-name))
           (output (concat (file-name-sans-extension input) ".svg"))
           (done (lambda (file message) (+my/mermaid--compiled output file message))))
      (if-let* ((file (+my/mermaid-render (with-temp-buffer
                                            (insert-file-contents input)
                                            (buffer-string))
                                          done)))
          (funcall done file nil)
        (message "Drawing %s…" (file-name-nondirectory input))))))

(defun +my/mermaid--compiled (output file message)
  "A file drawn: FILE copied to OUTPUT, opened; or MESSAGE in *mmdc*."
  (if (not file)
      (progn
        (with-current-buffer (get-buffer-create "*mmdc*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert message "\n")))
        (display-buffer "*mmdc*")
        (message "Mermaid: %s" (car (split-string message "\n"))))
    (copy-file file output t)
    (let* ((open (find-buffer-visiting output))
           (buffer (or open (find-file-noselect output t))))
      (with-current-buffer buffer
        (when (and open (not (buffer-modified-p)))
          (revert-buffer t t t))
        (auto-revert-mode 1))
      (display-buffer buffer)
      (message nil))))

(defadvice! +my/mermaid-fix-org-svg-a (_body params)
  "The SVG an Org mermaid block drew (its :file), made to show in Emacs."
  :after #'org-babel-execute:mermaid
  (+my/mermaid-fix-svg (cdr (assq :file params))))

;; Org: a mermaid block's C-c C-c (mermaid-mode defines Org Babel's
;; org-babel-execute:mermaid). Doom loads a block's language as it runs it,
;; looking for ob-mermaid, which doesn't exist: mermaid-mode instead.
(defun +my/mermaid-org-babel-load-h (lang)
  "Load mermaid-mode for Org's mermaid blocks (LANG `mermaid')."
  (when (eq lang 'mermaid)
    (require 'mermaid-mode nil t)))

(add-hook '+org-babel-load-functions #'+my/mermaid-org-babel-load-h)
