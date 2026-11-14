;;; $DOOMDIR/config/search/symbols.el -*- lexical-binding: t; -*-
;; Classes and Symbols: the language server's, as you type.
;; Loaded from config/search.el.

(defun +my/search-everywhere--symbols-requester (workspaces)
  "A function asking WORKSPACES' servers for the symbols matching a query,
once for Classes and Symbols both (each sent the same request). Called with
QUERY and CALLBACK: CALLBACK gets the servers' answer, ((WORKSPACE .
SYMBOLS)...), or `failed'; a new QUERY cancels the previous request, one
already answered is answered again. Called with `cancel', cancels it."
  (let ((token (make-symbol "search-everywhere"))
        query
        answer                          ; (ANSWER) once answered
        waiting)
    (lambda (input &optional callback)
      (let ((answered
             (lambda (result)
               (setq answer (list result))
               (when (eq result 'failed)
                 (setq query nil))        ; asked again next time
               (mapc (lambda (callback) (funcall callback result))
                     (prog1 (nreverse waiting) (setq waiting nil))))))
        (cond
         ((eq input 'cancel)
          (setq query nil waiting nil)
          (lsp-cancel-request-by-token token))
         ((not (equal input query))
          (setq query input
                answer nil
                waiting (list callback))
          (let ((lsp--buffer-workspaces workspaces)
                (failed (lambda (&rest _)
                          (when (equal query input) (funcall answered 'failed)))))
            ;; A request refused or failed ends the indicator too.
            (condition-case nil
                (lsp-request-async
                 "workspace/symbol" (list :query input)
                 (lambda (result)
                   (when (equal query input) (funcall answered result)))
                 :mode 'detached :no-merge t :cancel-token token
                 :error-handler failed)
              (error (funcall failed)))))
         (answer (funcall callback (car answer)))
         (t (push callback waiting)))))))

(defun +my/search-everywhere--lsp-async (requester classes)
  "Async source of the symbols REQUESTER finds, queried as the input changes
\(see `+my/search-everywhere--symbols-requester'). CLASSES non-nil keeps
only class-like kinds, nil keeps the other kinds."
  (consult--async-pipeline
   (consult--async-min-input)
   (consult--async-throttle)
   (lambda (sink)
     (lambda (action)
       (pcase action
         ((pred stringp)
          (unless (string-empty-p action)
            (funcall sink [indicator running])
            (funcall requester action
                     (lambda (result)
                       (if (eq result 'failed)
                           (funcall sink [indicator failed])
                         (funcall sink 'flush)
                         (funcall sink result)
                         (funcall sink [indicator finished]))))))
         ('destroy (funcall requester 'cancel)))
       (funcall sink action)))
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

(defun +my/search-everywhere--symbol-state ()
  "Preview of Classes and Symbols: the symbol's file, at the symbol, in the
pane the search started from; its buffer put back after. Files not open
are opened for the preview only, as consult's previews do."
  (let ((open (consult--temporary-files))
        (show (consult--buffer-preview))
        (jump (consult--jump-preview)))
    (lambda (action cand)
      (let ((marker (and cand (eq action 'preview)
                         (+my/search-everywhere--symbol-marker cand open))))
        (funcall show action (and marker (marker-buffer marker)))
        (funcall jump action marker)
        (unless cand
          (funcall open))))))           ; the files opened, closed

(defun +my/search-everywhere--symbol-marker (cand open)
  "Where symbol CAND is: a marker in its file's buffer, which OPEN (from
`consult--temporary-files') gives."
  (let* ((info (get-text-property 0 'consult--candidate cand))
         (location (lsp:symbol-information-location info)))
    (when-let* ((buffer (funcall open (lsp--uri-to-path (lsp:location-uri location)))))
      (with-current-buffer buffer
        (save-restriction
          (widen)
          (copy-marker (lsp--position-to-point
                        (lsp:range-start (lsp:location-range location)))))))))
