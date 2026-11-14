;;; $DOOMDIR/config/search/symbols.el -*- lexical-binding: t; -*-
;; Classes and Symbols: the language server's, as you type.
;; Loaded from config/search.el.

(defun +my/search-everywhere--lsp-async (workspaces token classes)
  "Async source of WORKSPACES' symbols, queried as the input changes.
CLASSES non-nil keeps only class-like kinds, nil keeps the other kinds.
TOKEN cancels the previous request; each source needs its own token, or the
Classes and Symbols requests would cancel each other."
  (consult--async-pipeline
   (consult--async-min-input)
   (consult--async-throttle)
   (lambda (sink)
     (let ((request
            (lambda (query)
              (let ((lsp--buffer-workspaces workspaces))
                (lsp-request-async
                 "workspace/symbol" (list :query query)
                 (lambda (results)
                   (funcall sink 'flush)
                   (funcall sink results)
                   (funcall sink [indicator finished]))
                 :mode 'detached :no-merge t :cancel-token token)))))
       (lambda (action)
         (pcase action
           ((pred stringp)
            (unless (string-empty-p action)
              (funcall sink [indicator running])
              (funcall request action)))
           ('destroy (lsp-cancel-request-by-token token)))
         (funcall sink action))))
   (consult--async-transform
    (lambda (results)
      (mapcan (pcase-lambda (`(,workspace . ,symbols))
                (cl-loop for info in (append symbols nil)
                         when (eq (and classes t)
                                  (and (memq (lsp:symbol-information-kind info)
                                             +my/search-everywhere--class-kinds)
                                       t))
                         collect (+my/search-everywhere--symbol-row workspace info)))
              results)))
   (consult--async-highlight)))

(defun +my/search-everywhere--symbol-row (workspace info)
  "Symbol INFO of WORKSPACE as a row of the list: its name, kind and
container first, which a narrow frame still shows, then its file and line,
which keep rows unique: \"save  Method  UserService  src/Service.kt:12\".
INFO is the row's `consult--candidate' property."
  (let* ((location (lsp:symbol-information-location info))
         (file (lsp--uri-to-path (lsp:location-uri location)))
         (root (lsp--workspace-root workspace))
         (line (1+ (lsp:position-line (lsp:range-start (lsp:location-range location)))))
         (container (lsp:symbol-information-container-name? info)))
    (propertize
     (concat (lsp:symbol-information-name info)
             (propertize (format "  %s" (alist-get (lsp:symbol-information-kind info)
                                                   lsp-symbol-kinds "Symbol"))
                         'face 'font-lock-type-face)
             (propertize (concat (and container (format "  %s" container))
                                 (format "  %s:%d"
                                         (if root (file-relative-name file root) file)
                                         line))
                         'face 'completions-annotations))
     'consult--candidate info)))

(defun +my/search-everywhere--goto-symbol (cand)
  "Open the file of symbol CAND at its position."
  (let* ((info (get-text-property 0 'consult--candidate cand))
         (location (lsp:symbol-information-location info)))
    (when (fboundp 'better-jumper-set-jump)
      (better-jumper-set-jump))         ; s-[ / C-o jumps back
    (find-file (lsp--uri-to-path (lsp:location-uri location)))
    (goto-char (lsp--position-to-point (lsp:range-start (lsp:location-range location))))
    (recenter)))
