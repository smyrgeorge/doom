;;; $DOOMDIR/config/markdown/marksman.el -*- lexical-binding: t; -*-
;; Marksman's false link warnings, dropped. Loaded from config/markdown.el.

;; MARKSMAN DIAGNOSTICS
;; Two false warnings from marksman (the Markdown language server) about links
;; that work, dropped when the link is a path to an existing file:
;; - "Ambiguous link to document": marksman takes every top-level `#' heading
;;   of a document as its title, so a link to a file with more than one, e.g.
;;   [README](the-game/README.md), was "ambiguous" though it names one file.
;;   Genuinely ambiguous links (e.g. [[README]] matching several files) are
;;   still reported.
;; - "Link to non-existent document": marksman doesn't index files git
;;   ignores, so a link to one (a report kept out of the repository) pointed
;;   "nowhere". Links to files that really are missing are still reported.
(defun +md--drop-false-link-warnings (params workspace)
  "Filter for `lsp-diagnostic-filter': see the comment above."
  (when (eq (lsp--workspace-server-id workspace) 'marksman)
    (let ((dir (file-name-directory
                (lsp--uri-to-path (lsp:publish-diagnostics-params-uri params)))))
      (setq params
            (lsp-put params :diagnostics
                     (vconcat
                      (seq-remove
                       (lambda (diagnostic)
                         (let ((message (lsp:diagnostic-message diagnostic)))
                           (and (string-match "\\`\\(?:Ambiguous link to\\|Link to non-existent\\) document '\\(.+\\)'\\'"
                                              message)
                                (file-regular-p
                                 (expand-file-name
                                  (url-unhex-string ; %20 etc.
                                   (car (split-string (match-string 1 message) "#")))
                                  dir)))))
                       (lsp:publish-diagnostics-params-diagnostics params)))))))
  params)
