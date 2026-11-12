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

;; Emacs's SVG library (librsvg) drops the space a <tspan> starts with, and
;; Mermaid writes each word of a label in one: "Write the code" showed as
;; "Writethecode". The SVG's root keeps them (xml:space), once mmdc wrote it.
(defun +my/mermaid-fix-svg (file)
  "FILE, an SVG mmdc wrote, made to show in Emacs (see above); a buffer
visiting it shows it anew."
  (when (and (stringp file) (string-suffix-p ".svg" file t) (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (and (re-search-forward "<svg\\b" nil t)
                 (not (looking-at "[^>]*xml:space=")))
        (insert " xml:space=\"preserve\"")
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region nil nil file nil 'silent))))
    (when-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer
        (revert-buffer t t t)))))

(defadvice! +my/mermaid-fix-compiled-svg-a (file-name)
  "The SVG mermaid-mode drew FILE-NAME into, made to show in Emacs."
  :after #'mermaid-compile-file
  (+my/mermaid-fix-svg (concat (file-name-sans-extension file-name) mermaid-output-format)))

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
