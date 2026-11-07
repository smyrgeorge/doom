;;; tests/unit/test-search.el -*- lexical-binding: t; -*-
;; config/search.el: SPC s a, Search Everywhere:
;; Classes, Files, Symbols and Actions in one list; Cmd+Shift+F, find in files
;; (rg through Doom's SPC s p), the selected text as the query. The language
;; server is mocked (`lsp-request-async'); `consult--multi' and `consult--grep'
;; are mocked (no minibuffer in batch).

;; ====== LOADING ======

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "consult"))))))
  (dolist (package '("consult" "consult-lsp" "lsp-mode" "projectile"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(defvar lsp-use-plists t)               ; as Doom builds lsp-mode (LSP_USE_PLISTS)

(+test-load "config/search")

(require 'consult)
(require 'lsp-mode)
(require 'consult-lsp)
(require 'projectile)
(require 'recentf)

;; Doom's Find in Files (SPC s p), from its source: what Cmd+Shift+F runs.
(defconst +test-search--doom-modules
  (seq-find #'file-directory-p
            (list (expand-file-name "sources/doom+/modules/" doom-emacs-dir)
                  doom-modules-dir)))

(defconst +test-search--doom-search
  (and +test-search--doom-modules
       (let ((files (list (expand-file-name "lib/text.el" doom-core-dir)
                          (expand-file-name "config/default/autoload/search.el" +test-search--doom-modules)
                          (expand-file-name "completion/vertico/autoload/vertico.el" +test-search--doom-modules))))
         (when (seq-every-p #'file-exists-p files)
           (dolist (file files) (load file nil t))
           t)))
  "Whether Doom's project search (`+default/search-project') is loaded.")

;; ====== HELPERS ======

(defun +test-search--dir (name &rest files)
  "A new folder NAME in the temp folder with FILES; its truename (as a
directory name)."
  (let ((dir (file-name-as-directory
              (file-truename (make-temp-file (+test-tmp-file (concat name "-")) t)))))
    (dolist (file files)
      (let ((path (expand-file-name file dir)))
        (make-directory (file-name-directory path) t)
        (with-temp-file path (insert file "\n"))))
    dir))

(defun +test-search--symbol (name kind file line character &optional container)
  "An LSP SymbolInformation: NAME of KIND in FILE at LINE, CHARACTER (0-based)."
  (let ((position (lsp-make-position :line line :character character)))
    (apply #'lsp-make-symbol-information
           :name name :kind kind
           :location (lsp-make-location
                      :uri (lsp--path-to-uri file)
                      :range (lsp-make-range :start position :end position))
           (and container (list :containerName container)))))

(defun +test-search--candidate (info &optional container)
  (propertize "candidate" 'consult--candidate info 'consult--container-name container))

(defmacro +test-search-capturing-multi (var &rest body)
  "BODY with `consult--multi' mocked: VAR gets (SOURCES OPTIONS STATE), STATE
the dynamic settings it ran with."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'consult--multi)
                (lambda (sources &rest options)
                  (setq ,var (list sources options
                                   (list :ignore-case completion-ignore-case
                                         :directory default-directory)))
                  nil)))
       ,@body)))

(defun +test-search--source (sources name)
  (seq-find (lambda (s) (equal (plist-get s :name) name)) sources))

;; ====== KEYS ======

(ert-deftest search/keys ()
  (should (eq (lookup-key doom-leader-map (kbd "s a")) #'+my/search-everywhere))
  (should (eq (lookup-key global-map (kbd "s-F")) #'+default/search-project))
  ;; Not shadowed in evil's states.
  (+test-with-reset
    (with-current-buffer (+test-buffer "code.txt" "some text\n")
      (dolist (state '(normal insert visual))
        (evil-change-state state)
        (should (eq (key-binding (kbd "s-F")) #'+default/search-project))))))

;; ====== CLASSES / SYMBOLS ======

(ert-deftest search/class-kinds ()
  "Classes: classes, enums, interfaces/traits, objects, structs."
  (should (equal +my/search-everywhere--class-kinds '(5 10 11 19 23)))
  (should (equal (mapcar (lambda (kind) (alist-get kind lsp-symbol-kinds))
                         +my/search-everywhere--class-kinds)
                 '("Class" "Enum" "Interface" "Object" "Struct"))))

(ert-deftest search/annotate-symbol ()
  "The symbol's kind and container, e.g. \"Method  UserService\"."
  (let* ((file (+test-file "search/A.kt" "x\n"))
         (method (+test-search--candidate (+test-search--symbol "save" 6 file 0 0) "UserService"))
         (class (+test-search--candidate (+test-search--symbol "UserService" 5 file 0 0))))
    (let ((annotation (+my/search-everywhere--annotate-symbol method)))
      (should (equal (substring-no-properties annotation) " Method  UserService"))
      (should (eq (get-text-property 1 'face annotation) 'font-lock-type-face))
      (should (eq (get-text-property (1- (length annotation)) 'face annotation)
                  'completions-annotations)))
    (should (equal (substring-no-properties (+my/search-everywhere--annotate-symbol class))
                   " Class"))))

(ert-deftest search/goto-symbol ()
  "Picking a symbol: its file at its position, a jump recorded first."
  (+test-with-reset
    (let* ((file (+test-file "search/Goto.kt" "line one\nline two\n    fun target() {}\nend\n"))
           (cand (+test-search--candidate (+test-search--symbol "target" 12 file 2 8)))
           (jumps 0)
           (origin (+test-buffer "origin")))
      (switch-to-buffer origin)
      (cl-letf (((symbol-function 'better-jumper-set-jump)
                 (lambda (&rest _) (should (eq (current-buffer) origin)) (cl-incf jumps))))
        (+my/search-everywhere--goto-symbol cand))
      (should (= jumps 1))
      (should (equal (file-truename buffer-file-name) (file-truename file)))
      (should (eq (window-buffer) (current-buffer)))
      (should (= (line-number-at-pos) 3))
      (should (= (current-column) 8))
      (should (looking-at "target")))))

(ert-deftest search/goto-symbol-without-better-jumper ()
  (+test-with-reset
    (let ((file (+test-file "search/NoJump.kt" "a\nb\n"))
          (fboundp (fboundp 'better-jumper-set-jump))
          (saved (and (fboundp 'better-jumper-set-jump) (symbol-function 'better-jumper-set-jump))))
      (unwind-protect
          (progn
            (fmakunbound 'better-jumper-set-jump)
            (+my/search-everywhere--goto-symbol
             (+test-search--candidate (+test-search--symbol "b" 13 file 1 0)))
            (should (equal (file-truename buffer-file-name) (file-truename file)))
            (should (= (line-number-at-pos) 2)))
        (when fboundp (fset 'better-jumper-set-jump saved))))))

;; ====== CLASSES / SYMBOLS: QUERYING THE SERVER ======

(defmacro +test-search-with-server (results &rest body)
  "BODY with the language server mocked: `lsp-request-async' records its
calls in `requests' (METHOD PARAMS WORKSPACES PLIST) and answers RESULTS (a
form: ((WORKSPACE . SYMBOLS)...)) right after; `lsp-cancel-request-by-token'
records in `cancelled'. Input is throttled by timers: `+test-search--feed'."
  (declare (indent 1))
  `(let ((requests nil)
         (cancelled nil)
         (consult-async-min-input 2)
         (consult-async-input-throttle 0)
         (consult-async-input-debounce 0))
     (cl-letf (((symbol-function 'lsp-request-async)
                (lambda (method params callback &rest plist)
                  (push (list method params lsp--buffer-workspaces plist) requests)
                  ;; The answer comes later (outside the request's bindings).
                  (run-at-time 0 nil callback ,results)))
               ((symbol-function 'lsp-cancel-request-by-token)
                (lambda (token) (push token cancelled))))
       ,@body)))

(defun +test-search--feed (async input)
  "Type INPUT into ASYNC (its throttle's timer, due at once, let run)."
  (funcall async input)
  (dotimes (_ 5) (accept-process-output nil 0.01)))

(defun +test-search--async (classes token)
  "The source's async function, set up, with a sink recording into the
returned list's car (newest first)."
  (let* ((log (list nil))
         (sink (lambda (action) (push action (car log)) nil))
         (async (funcall (+my/search-everywhere--lsp-async '(ws) token classes) sink)))
    ;; Set up from the input's buffer (the minibuffer's, here a buffer).
    (with-current-buffer (get-buffer-create " *test-search-input*")
      (funcall async 'setup))
    (list log async)))

(defun +test-search--candidates (log)
  "The candidate strings the sink got (in order)."
  (seq-filter #'stringp (apply #'append (seq-filter #'consp (reverse (car log))))))

(ert-deftest search/symbols-queried-as-you-type ()
  "From 2 characters, each input asks the server (workspace/symbol, the
query, detached, unmerged, the source's own token)."
  (let* ((file (+test-search--dir "search-lsp" "src/A.kt"))
         (workspace (make-lsp--workspace :root file))
         (symbols (vector (+test-search--symbol "UserService" 5 (expand-file-name "src/A.kt" file) 0 0)
                          (+test-search--symbol "save" 6 (expand-file-name "src/A.kt" file) 3 4))))
    (+test-search-with-server (list (cons workspace symbols))
      (pcase-let ((`(,log ,async) (+test-search--async nil :tok)))
        (+test-search--feed async "U")
        (should-not requests)
        (+test-search--feed async "Us")
        (should (= (length requests) 1))
        (pcase-let ((`(,method ,params ,workspaces ,plist) (car requests)))
          (should (equal method "workspace/symbol"))
          (should (equal params '(:query "Us")))
          (should (equal workspaces '(ws)))
          (should (eq (plist-get plist :mode) 'detached))
          (should (eq (plist-get plist :no-merge) t))
          (should (eq (plist-get plist :cancel-token) :tok)))
        ;; Running, flushed, the results, finished.
        (let ((actions (reverse (car log))))
          (should (member [indicator running] actions))
          (should (member 'flush actions))
          (should (member [indicator finished] actions))
          (should (< (seq-position actions [indicator running] #'equal)
                     (seq-position actions 'flush)
                     (seq-position actions [indicator finished] #'equal))))
        ;; Symbols: not the classes.
        (let ((cands (+test-search--candidates log)))
          (should (= (length cands) 1))
          (should (string-prefix-p "save" (car cands)))
          (should (eq (get-text-property 0 'consult--candidate (car cands)) (aref symbols 1))))
        (+test-search--feed async "Use")
        (should (equal (cadr (car requests)) '(:query "Use")))
        (should (= (length requests) 2))))))

(ert-deftest search/classes-only-class-kinds ()
  "Classes keeps classes, enums, interfaces, objects, structs; across
workspaces."
  (let* ((dir (+test-search--dir "search-classes" "A.kt"))
         (file (expand-file-name "A.kt" dir))
         (ws1 (make-lsp--workspace :root dir))
         (ws2 (make-lsp--workspace :root dir))
         (results (list (cons ws1 (vector (+test-search--symbol "AClass" 5 file 0 0)
                                          (+test-search--symbol "aMethod" 6 file 1 0)
                                          (+test-search--symbol "AnEnum" 10 file 2 0)
                                          (+test-search--symbol "AnInterface" 11 file 3 0)))
                        (cons ws2 (vector (+test-search--symbol "AnObject" 19 file 4 0)
                                          (+test-search--symbol "AStruct" 23 file 5 0)
                                          (+test-search--symbol "aField" 8 file 6 0)
                                          (+test-search--symbol "aFunction" 12 file 7 0))))))
    (+test-search-with-server results
      (pcase-let ((`(,log ,async) (+test-search--async t :classes)))
        (+test-search--feed async "An")
        (should (equal (mapcar (lambda (c) (car (split-string c " ")))
                               (+test-search--candidates log))
                       '("AClass" "AnEnum" "AnInterface" "AnObject" "AStruct"))))
      (pcase-let ((`(,log ,async) (+test-search--async nil :symbols)))
        (+test-search--feed async "An")
        (should (equal (mapcar (lambda (c) (car (split-string c " ")))
                               (+test-search--candidates log))
                       '("aMethod" "aField" "aFunction")))))))

(ert-deftest search/symbols-cancelled-on-exit ()
  "Leaving (destroy) cancels the source's request, by its token."
  (+test-search-with-server nil
    (pcase-let ((`(,_log ,async) (+test-search--async nil :symbols-token)))
      (funcall async 'destroy)
      (should (equal cancelled '(:symbols-token))))))

(ert-deftest search/symbols-empty-input-asks-nothing ()
  (+test-search-with-server nil
    (pcase-let ((`(,_log ,async) (+test-search--async nil :tok)))
      (+test-search--feed async "")
      (+test-search--feed async "x")
      (should-not requests))))

;; ====== FILES ======

(ert-deftest search/files-recent-first ()
  "The project's files, those opened recently first (once each); not recent
files elsewhere (a sibling folder with the same prefix too) or gone."
  (let* ((root (+test-search--dir "search-files" "src/a.kt" "b.txt" "README.md"))
         (sibling (+test-search--dir (concat (file-name-nondirectory (directory-file-name root)) "2")
                                     "x.txt"))
         (recentf-list (list (expand-file-name "b.txt" root)
                             (expand-file-name "x.txt" sibling)
                             (expand-file-name "gone.txt" root)
                             (expand-file-name "README.md" root)
                             (expand-file-name "b.txt" root))))
    (cl-letf (((symbol-function 'projectile-project-files)
               (lambda (dir) (should (equal dir root)) '("src/a.kt" "b.txt" "README.md"))))
      (should (equal (+my/search-everywhere--files root) '("b.txt" "README.md" "src/a.kt"))))))

(ert-deftest search/files-without-recentf ()
  (let ((root (+test-search--dir "search-files-norecent" "a.txt")))
    (cl-letf (((symbol-function 'projectile-project-files) (lambda (_) '("a.txt"))))
      (let ((recentf-list nil))
        (should (equal (+my/search-everywhere--files root) '("a.txt"))))
      (let ((recentf-list '("/elsewhere/z.txt")))
        (makunbound 'recentf-list)
        (unwind-protect
            (should (equal (+my/search-everywhere--files root) '("a.txt")))
          (defvar recentf-list nil))))))

(ert-deftest search/files-of-a-real-project ()
  "With projectile (no cache, config/projectile.el's setting): git's files,
untracked ones too, ignored ones not."
  (let* ((root (+test-search--dir "search-git" "src/a.kt" "b.txt" ".gitignore"))
         (default-directory root)
         (home (+test-tmp-file "search-git-home/"))
         (process-environment (append (list (concat "HOME=" home)
                                            (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                                            "GIT_CONFIG_NOSYSTEM=1"
                                            (concat "XDG_CONFIG_HOME=" home ".config"))
                                      process-environment))
         (projectile-enable-caching nil)
         (projectile-project-root-cache (make-hash-table :test #'equal))
         (recentf-list nil))
    (with-temp-file ".gitignore" (insert "build/\n"))
    (call-process "git" nil nil nil "init" "-q")
    (make-directory "build" t)
    (with-temp-file "build/out.class" (insert "x"))
    (should (equal (sort (+my/search-everywhere--files root) #'string<)
                   '(".gitignore" "b.txt" "src/a.kt")))))

;; ====== ACTIONS ======

(defun +test-search-cmd-alpha () (interactive) (setq +test-search--ran (list 'alpha this-command real-this-command)))
(defun +test-search-cmd-beta (n) (interactive "p") (setq +test-search--ran (list 'beta n)))
(defun +test-search-not-a-command () nil)
(defvar +test-search--ran nil)

(ert-deftest search/commands-every-command-recent-first ()
  (let* ((extended-command-history '("+test-search-cmd-beta" "+test-search-not-a-command"
                                     "no-such-function-zz" "+test-search-cmd-alpha"
                                     "+test-search-cmd-beta"))
         (read-extended-command-predicate nil)
         (commands (+my/search-everywhere--commands)))
    (should (equal (seq-take commands 2) '("+test-search-cmd-beta" "+test-search-cmd-alpha")))
    (should (equal commands (seq-uniq commands)))
    (should-not (member "+test-search-not-a-command" commands))
    (should-not (member "no-such-function-zz" commands))
    (should (member "forward-char" commands))
    (should (member "+my/search-everywhere" commands))
    ;; The rest in alphabetical order.
    (let ((rest (nthcdr 2 commands)))
      (should (equal rest (sort (copy-sequence rest) #'string<))))))

(ert-deftest search/commands-as-m-x-offers-here ()
  "Only what M-x offers in this buffer (`read-extended-command-predicate'):
not a mode's commands elsewhere, recently used or not."
  (require 'dired)
  (+test-with-reset
    (let ((read-extended-command-predicate #'command-completion-default-include-p)
          (extended-command-history '("dired-do-rename" "+test-search-cmd-alpha")))
      (with-current-buffer (+test-buffer "code.txt" "x\n" #'text-mode)
        (let ((commands (+my/search-everywhere--commands)))
          (should (equal (car commands) "+test-search-cmd-alpha"))
          (should-not (member "dired-do-rename" commands))
          (should (member "forward-char" commands))))
      (with-current-buffer (dired-noselect (+test-search--dir "search-dired" "f.txt"))
        (let ((commands (+my/search-everywhere--commands)))
          (should (equal (car commands) "dired-do-rename"))))
      ;; Any other predicate.
      (let ((read-extended-command-predicate
             (lambda (sym _buffer) (not (eq sym '+test-search-cmd-alpha)))))
        (should-not (member "+test-search-cmd-alpha" (+my/search-everywhere--commands)))))))

(ert-deftest search/run-command-as-m-x ()
  "Running an action: as M-x (history, `this-command', command history)."
  (let ((extended-command-history '("forward-char"))
        (command-history nil)
        (+test-search--ran nil))
    (+my/search-everywhere--run-command "+test-search-cmd-alpha")
    (should (equal +test-search--ran '(alpha +test-search-cmd-alpha +test-search-cmd-alpha)))
    (should (equal extended-command-history '("+test-search-cmd-alpha" "forward-char")))
    (should (equal (car command-history) '(+test-search-cmd-alpha)))
    ;; Its interactive arguments.
    (+my/search-everywhere--run-command "+test-search-cmd-beta")
    (should (equal +test-search--ran '(beta 1)))
    (should (equal (car extended-command-history) "+test-search-cmd-beta"))
    (should (equal (car command-history) '(+test-search-cmd-beta 1)))))

;; ====== SPC s a ======

(ert-deftest search/everywhere-in-a-project-with-lsp ()
  "Classes, Files, Symbols, Actions; case-insensitive, from the project's root."
  (+test-with-reset
    (let* ((root (+test-search--dir "search-all" "src/A.kt" "b.txt"))
           (asyncs nil))
      (with-current-buffer (find-file-noselect (expand-file-name "src/A.kt" root))
        (setq-local lsp-mode t)
        (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) root))
                  ((symbol-function 'lsp-workspaces) (lambda () '(ws)))
                  ((symbol-function 'projectile-project-files) (lambda (_) '("src/A.kt" "b.txt")))
                  ((symbol-function '+my/search-everywhere--lsp-async)
                   (lambda (workspaces token classes)
                     (push (list workspaces token classes) asyncs)
                     (lambda (sink) sink))))
          (+test-search-capturing-multi got
            (+my/search-everywhere)
            (pcase-let ((`(,sources ,options ,state) got))
              (should (equal (mapcar (lambda (s) (plist-get s :name)) sources)
                             '("Classes" "Files" "Symbols" "Actions")))
              (should (equal (mapcar (lambda (s) (plist-get s :narrow)) sources) '(?c ?f ?s ?a)))
              (should (equal options '(:prompt "Search everywhere: " :require-match t :sort nil)))
              (should (equal state (list :ignore-case t :directory root)))
              ;; Consult takes them.
              (should (= (length (consult--multi-enabled-sources sources)) 4))
              (let ((classes (+test-search--source sources "Classes"))
                    (symbols (+test-search--source sources "Symbols"))
                    (files (+test-search--source sources "Files"))
                    (actions (+test-search--source sources "Actions")))
                (dolist (source (list classes symbols))
                  (should (eq (plist-get source :category) 'consult-lsp-symbols))
                  (should (functionp (plist-get source :async)))
                  (should (eq (plist-get source :annotate) #'+my/search-everywhere--annotate-symbol))
                  (should (eq (plist-get source :action) #'+my/search-everywhere--goto-symbol)))
                ;; Each its own token, classes or not.
                (should (equal (reverse asyncs)
                               '(((ws) :+my/search-everywhere-classes t)
                                 ((ws) :+my/search-everywhere-symbols nil))))
                (should (eq (plist-get files :category) 'file))
                (should (eq (plist-get files :face) 'consult-file))
                (should (equal (funcall (plist-get files :items)) '("src/A.kt" "b.txt")))
                (should (eq (plist-get actions :category) 'command))
                (should (eq (plist-get actions :items) #'+my/search-everywhere--commands))
                (should (eq (plist-get actions :action) #'+my/search-everywhere--run-command))
                ;; Picking a file opens it, from the root.
                (with-temp-buffer
                  (setq default-directory "/")
                  (funcall (plist-get files :action) "b.txt"))
                (should (equal (buffer-file-name (window-buffer))
                               (expand-file-name "b.txt" root)))))))))))

(ert-deftest search/everywhere-without-lsp ()
  "No language server: no Classes, no Symbols (consult skips them)."
  (+test-with-reset
    (let ((root (+test-search--dir "search-nolsp" "a.txt"))
          (required nil))
      (with-current-buffer (find-file-noselect (expand-file-name "a.txt" root))
        (setq-local lsp-mode nil)
        (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) root))
                  ((symbol-function 'lsp-workspaces) (lambda () (setq required t) '(ws))))
          (+test-search-capturing-multi got
            (+my/search-everywhere)
            (let ((sources (car got)))
              (should-not required)
              (should (equal (mapcar (lambda (s) (plist-get s :name)) (delq nil (copy-sequence sources)))
                             '("Files" "Actions")))
              (should (equal (mapcar (lambda (s) (plist-get s :name))
                                     (append (consult--multi-enabled-sources sources) nil))
                             '("Files" "Actions"))))))))))

(ert-deftest search/everywhere-outside-a-project ()
  "No project: no Files; the current folder stays."
  (+test-with-reset
    (with-current-buffer (+test-buffer "*notes*")
      (setq default-directory (file-name-as-directory (+test-tmp-file "search-noproj/")))
      (let ((dir default-directory))
        (cl-letf (((symbol-function 'doom-project-root) #'ignore))
          (+test-search-capturing-multi got
            (+my/search-everywhere)
            (should (equal (mapcar (lambda (s) (plist-get s :name))
                                   (append (consult--multi-enabled-sources (car got)) nil))
                           '("Actions")))
            (should (equal (plist-get (nth 2 got) :directory) dir))
            (should (eq (plist-get (nth 2 got) :ignore-case) t))))))))

(ert-deftest search/everywhere-is-a-command ()
  (should (commandp #'+my/search-everywhere)))

;; ====== CMD+SHIFT+F ======

(ert-deftest search/find-in-files-selected-text-is-the-query ()
  "Cmd+Shift+F: rg in the project's root; the selected text (visual state)
is the query, quoted."
  (unless +test-search--doom-search (ert-skip "Doom's search module isn't there"))
  (unless (executable-find "rg") (ert-skip "rg isn't installed"))
  (+test-with-reset
    (let ((root (+test-search--dir "search-rg" "src/A.kt"))
          (grep nil))
      (with-current-buffer (find-file-noselect (expand-file-name "src/A.kt" root))
        (switch-to-buffer (current-buffer))
        (erase-buffer)
        (insert "val total = price.times(2)\n")
        (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) root))
                  ((symbol-function 'consult--grep)
                   (lambda (prompt builder dir initial)
                     (setq grep (list prompt builder dir initial consult-ripgrep-args)))))
          ;; Selected: "price.times(2)".
          (goto-char (point-min))
          (search-forward "price")
          (evil-visual-select (match-beginning 0) (- (line-end-position) 1))
          (call-interactively (key-binding (kbd "s-F")))
          (pcase-let ((`(,_prompt ,builder ,dir ,initial ,args) grep))
            (should (eq builder #'consult--ripgrep-make-builder))
            (should (equal dir root))
            (should (string-match-p (regexp-quote (regexp-quote "price.times(2)")) initial))
            (should (string-prefix-p "rg " args)))
          ;; Nothing selected: no query.
          (setq grep nil)
          (evil-normal-state)
          (call-interactively (key-binding (kbd "s-F")))
          (should grep)
          (should-not (nth 3 grep))
          ;; C-u: ignored and hidden files too.
          (setq grep nil)
          (let ((current-prefix-arg '(4)))
            (call-interactively #'+default/search-project))
          (should (string-match-p "-uu" (nth 4 grep))))))))
