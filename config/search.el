;;; $DOOMDIR/config/search.el -*- lexical-binding: t; -*-
;; Search Everywhere (IntelliJ's double Shift) on SPC s a. Loaded from config.el.

;; SEARCH EVERYWHERE
;; One list with the tabs of IntelliJ's Search Everywhere: Classes, Files,
;; Symbols and Actions. Typing searches all of them at once; to show one tab,
;; type its key then SPC (or `<' then the key): c Classes, f Files, s Symbols,
;; a Actions. `<<' (or DEL on an empty input) goes back to all.
;; - Classes / Symbols: the language server's workspace symbols, queried as you
;;   type (from 2 characters; only in buffers with an LSP server). Classes are
;;   classes, interfaces/traits, structs, enums and objects.
;; - Files: the project's files, recently opened ones first.
;; - Actions: every command (what M-x runs), recently used ones first, with
;;   their key bindings and docs.
;; Emacs can't see a lone Shift key press on macOS, so there is no double Shift.

(defconst +my/search-everywhere--class-kinds '(5 10 11 19 23)
  "LSP SymbolKinds listed under Classes: Class, Enum, Interface, Object, Struct.")

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
                         collect (consult-lsp--symbols--transformer workspace info)))
              results)))
   (consult--async-highlight)))

(defun +my/search-everywhere--annotate-symbol (cand)
  "Show the symbol's kind and container, e.g. \"Method  UserService\"."
  (let ((info (get-text-property 0 'consult--candidate cand))
        (container (get-text-property 0 'consult--container-name cand)))
    (concat (propertize (format " %s" (alist-get (lsp:symbol-information-kind info)
                                                 lsp-symbol-kinds))
                        'face 'font-lock-type-face)
            (and container (propertize (format "  %s" container)
                                       'face 'completions-annotations)))))

(defun +my/search-everywhere--goto-symbol (cand)
  "Open the file of symbol CAND at its position."
  (let* ((info (get-text-property 0 'consult--candidate cand))
         (location (lsp:symbol-information-location info)))
    (when (fboundp 'better-jumper-set-jump)
      (better-jumper-set-jump))         ; s-[ / C-o jumps back
    (find-file (lsp--uri-to-path (lsp:location-uri location)))
    (goto-char (lsp--position-to-point (lsp:range-start (lsp:location-range location))))
    (recenter)))

(defun +my/search-everywhere--files (root)
  "ROOT's project files relative to ROOT, recently opened ones first."
  (require 'projectile)
  (let* ((root (expand-file-name root))
         (recent (cl-loop for file in (bound-and-true-p recentf-list)
                          for abs = (expand-file-name file)
                          when (and (string-prefix-p root abs) (file-exists-p abs))
                          collect (file-relative-name abs root))))
    (delete-dups (append recent (projectile-project-files root)))))

(defun +my/search-everywhere--commands ()
  "Names of all commands M-x would offer here, recently used ones first."
  (let ((buffer (current-buffer))
        (all nil))
    (mapatoms
     (lambda (sym)
       (when (and (commandp sym)
                  (or (null read-extended-command-predicate)
                      (funcall read-extended-command-predicate sym buffer)))
         (push (symbol-name sym) all))))
    (delete-dups
     (append (seq-filter (lambda (name) (commandp (intern-soft name)))
                         extended-command-history)
             (sort all #'string<)))))

(defun +my/search-everywhere--run-command (name)
  "Run command NAME as M-x would."
  (let ((command (intern name)))
    (add-to-history 'extended-command-history name)
    (setq this-command command
          real-this-command command)
    (command-execute command 'record)))

(defun +my/search-everywhere ()
  "Search classes, files, symbols and actions at once (IntelliJ's double Shift)."
  (interactive)
  (require 'consult)
  (let* ((root (doom-project-root))
         (default-directory (or root default-directory)) ; file annotations
         (completion-ignore-case t)     ; "servic" finds UserService.kt
         (workspaces (and (bound-and-true-p lsp-mode)
                          (require 'consult-lsp nil t)
                          (lsp-workspaces)))
         (symbols (lambda (name key classes token)
                    (when workspaces
                      (list :name name :narrow key :category 'consult-lsp-symbols
                            :async (+my/search-everywhere--lsp-async workspaces token classes)
                            :annotate #'+my/search-everywhere--annotate-symbol
                            :action #'+my/search-everywhere--goto-symbol)))))
    (consult--multi
     (list (funcall symbols "Classes" ?c t :+my/search-everywhere-classes)
           (when root
             (list :name "Files" :narrow ?f :category 'file :face 'consult-file
                   :items (lambda () (+my/search-everywhere--files root))
                   :action (lambda (file) (find-file (expand-file-name file root)))))
           (funcall symbols "Symbols" ?s nil :+my/search-everywhere-symbols)
           (list :name "Actions" :narrow ?a :category 'command
                 :items #'+my/search-everywhere--commands
                 :action #'+my/search-everywhere--run-command))
     :prompt "Search everywhere: "
     :require-match t
     :sort nil)))

(map! :leader :desc "Search everywhere" "s a" #'+my/search-everywhere)

;; FIND IN FILES
;; Cmd+Shift+F: search the project's files (ripgrep, through Doom's SPC s p),
;; next to Cmd+F for the current buffer. With text selected, it searches for
;; that text, like IntelliJ's Find in Files.
(map! "s-F" #'+default/search-project)
