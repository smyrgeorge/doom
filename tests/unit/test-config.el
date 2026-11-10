;;; tests/unit/test-config.el -*- lexical-binding: t; -*-
;; config.el: the whole config loads, in order, without errors; the files it
;; loads exist, the disabled ones (cheatsheet, pdf) stay out; its own settings
;; (CUSTOM CONFIG); the load order the files' comments ask for; nothing from
;; tests/ is loaded.

(defvar doom-disabled-packages nil)     ; Doom's `use-package!' reads it
(setq native-comp-enable-subr-trampolines nil) ; mocking primitives compiles none

;; ====== LOADING IT ======

(defun +test-config--forms ()
  "config.el's top-level forms, in order."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (nreverse forms))))

(defun +test-config--loads ()
  "The files config.el loads (\"config/emacs\"...), in order."
  (cl-loop for form in (+test-config--forms)
           when (eq (car-safe form) 'load!) collect (cadr form)))

(defun +test-config--file (name)
  "NAME (\"config/emacs\") as a file of this config."
  (expand-file-name (concat name ".el") +test-root))

(defun +test-config--parts (name)
  "The parts file NAME (\"config/merge\") loads (\"config/merge/git\"...), in
order, theirs included: the `load!'s among its top-level forms."
  (with-temp-buffer
    (insert-file-contents (+test-config--file name))
    (let (parts)
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (eq (car-safe form) 'load!)
                (push (concat (file-name-directory name) (cadr form)) parts))))
        (end-of-file))
      (cl-loop for part in (nreverse parts)
               append (append (+test-config--parts part) (list part))))))

(defvar +test-config--history-before
  (remove (expand-file-name "config/os.el" +test-root) (mapcar #'car load-history))
  "The files loaded before config.el; but config/os.el, which tests/helper.el
loads too (config.el loads it again, first).")

(defvar +test-config--error nil "What loading config.el signalled, if anything.")

(defvar +test-config--processes nil "The programs loading config.el tried to run.")

(defvar +test-config--default-directory nil
  "`default-directory' in the buffer config.el was loaded in.")

(defvar +test-config--fill-column-buffer nil
  "`fill-column' in that buffer.")

(defvar +test-config--loaded-files nil
  "This config's files loading config.el loaded, in the order they were.")

;; Loaded once, as Doom does at startup, no program allowed to run.
(with-temp-buffer
  (cl-letf* ((record (lambda (name result)
                       (lambda (&rest args) (push (cons name args) +test-config--processes) result)))
             ((symbol-function 'make-process) (funcall record 'make-process nil))
             ((symbol-function 'start-process) (funcall record 'start-process nil))
             ((symbol-function 'start-file-process) (funcall record 'start-file-process nil))
             ((symbol-function 'call-process) (funcall record 'call-process 1))
             ((symbol-function 'process-file) (funcall record 'process-file 1))
             ((symbol-function 'make-network-process) (funcall record 'make-network-process nil)))
    (condition-case err
        (+test-load "config")
      (error (setq +test-config--error err))))
  (setq +test-config--default-directory default-directory
        +test-config--fill-column-buffer fill-column))

(let ((root (file-name-as-directory (expand-file-name +test-root))))
  (setq +test-config--loaded-files
        (cl-loop for file in (reverse (mapcar #'car load-history))
                 when (and (stringp file)
                           (string-prefix-p root file)
                           (not (member file +test-config--history-before)))
                 collect file)))

(defun +test-config--loaded ()
  "This config's files loaded by config.el, in the order they were."
  +test-config--loaded-files)

;; ====== IT LOADS ======

(ert-deftest config/loads-without-errors ()
  (should-not +test-config--error)
  (should (assoc (expand-file-name "config.el" +test-root) load-history)))

(ert-deftest config/loading-runs-no-program ()
  "Loading the config starts nothing (servers, git, Claude...): that waits
until something is used."
  (should-not +test-config--processes))

(ert-deftest config/loads-every-file-in-order ()
  "Each file config.el names, once, in its order, config.el itself last. A
file is recorded once it has loaded: its parts (config/merge/...) before it."
  (let ((expected (append (cl-loop for name in (+test-config--loads)
                                   append (mapcar #'+test-config--file
                                                  (append (+test-config--parts name) (list name))))
                          (list (expand-file-name "config.el" +test-root)))))
    (should (equal (+test-config--loaded) expected))))

(ert-deftest config/loaded-files-exist ()
  (let ((loads (+test-config--loads)))
    (should (> (length loads) 20))
    (dolist (name loads)
      (should (string-prefix-p "config/" name))
      (should (file-exists-p (+test-config--file name)))
      ;; Its parts, in its folder.
      (dolist (part (+test-config--parts name))
        (should (string-prefix-p (concat name "/") part))
        (should (file-exists-p (+test-config--file part)))))
    ;; Each once.
    (should (equal loads (delete-dups (copy-sequence loads))))))

(ert-deftest config/disabled-files-not-loaded ()
  "config/cheatsheet exists but is commented out: not loaded."
  (let ((text (with-temp-buffer
                (insert-file-contents (expand-file-name "config.el" +test-root))
                (buffer-string)))
        (loaded (+test-config--loaded)))
    (dolist (name '("config/cheatsheet"))
      (should (file-exists-p (+test-config--file name)))
      (should-not (member name (+test-config--loads)))
      (should-not (member (+test-config--file name) loaded))
      (should (string-match-p (format "^;;(load! \"%s\")$" (regexp-quote name)) text))))
  ;; Nothing it defines is there.
  (should-not (boundp '+my/cheatsheet-file)))

(ert-deftest config/pdf-module-off-our-pdf-on ()
  "Doom's pdf module (pdf-tools) is off: PDFs are this config's own viewer
(config/pdf, WebKit), loaded; pdf-tools' old setup is gone."
  (should-not (+test-module-p :tools 'pdf))
  (should (member "config/pdf" (+test-config--loads))))

(defun +test-config--el-files (dir)
  "DIR's Emacs Lisp files, not an editor's own copies while a file is edited:
lock files (.#NAME.el) and flycheck's (flycheck_NAME.el)."
  (seq-remove (lambda (file) (string-prefix-p "flycheck_" file))
              (directory-files dir nil "\\`[^.#].*\\.el\\'")))

(ert-deftest config/every-config-file-accounted-for ()
  "Each config/*.el is loaded or one of the disabled ones, and each
config/NAME/*.el a part config/NAME.el loads: none forgotten."
  (let ((loads (+test-config--loads))
        (dir (expand-file-name "config/" +test-root)))
    (dolist (file (+test-config--el-files dir))
      (let ((name (concat "config/" (file-name-sans-extension file))))
        (should (or (member name loads)
                    (member name '("config/cheatsheet"))))))
    (dolist (folder (directory-files dir nil "\\`[^.]"))
      (when (file-directory-p (expand-file-name folder dir))
        (let ((entry (concat "config/" folder)))
          (should (member entry loads))
          (dolist (file (+test-config--el-files (expand-file-name folder dir)))
            (should (member (concat entry "/" (file-name-sans-extension file))
                            (+test-config--parts entry)))))))))

(ert-deftest config/files-are-lexical-and-say-so ()
  "Every config file uses lexical binding (compile.el relies on it) and its
header says what loads it: config.el, or for a part its file (config/merge.el)."
  (dolist (name (append (+test-config--loads) '("config/cheatsheet")))
    (dolist (file (cons name (+test-config--parts name)))
      (with-temp-buffer
        (insert-file-contents (+test-config--file file))
        (goto-char (point-min))
        (should (looking-at-p (format ";;; \\$DOOMDIR/%s\\.el -\\*- lexical-binding: t; -\\*-"
                                      (regexp-quote file))))
        (should (re-search-forward
                 (format "Loaded \\(?:last \\)?from\\(?:\n;;\\)? %s\\.el"
                         (if (equal file name)
                             "config"
                           (regexp-quote (directory-file-name (file-name-directory file)))))
                 (save-excursion (forward-line 5) (point)) t)))))
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (should (looking-at-p ";;; \\$DOOMDIR/config\\.el -\\*- lexical-binding: t; -\\*-"))))

(ert-deftest config/nothing-from-tests ()
  "The config never loads anything under tests/ (only tests/run.sh does)."
  (let ((tests (file-name-as-directory (expand-file-name "tests" +test-root))))
    (dolist (file (+test-config--loaded))
      (should-not (string-prefix-p tests file)))
    (dolist (name (+test-config--loads))
      (should-not (string-match-p "\\`tests\\b\\|/tests/" name))))
  (let ((text (mapconcat (lambda (name)
                           (with-temp-buffer
                             (insert-file-contents (+test-config--file name))
                             (buffer-string)))
                         (cons "config" (+test-config--loads)) "\n")))
    (should-not (string-match-p "(load!? +\"[^\"]*tests/" text))
    (should-not (string-match-p "test-helper\\|tests/helper" text))))

(ert-deftest config/loads-again ()
  "Loaded a second time (doom/reload): no error, still one compile timer."
  (with-temp-buffer
    (+test-load "config"))
  (should (= (cl-count #'+my/compile-config-functions-h timer-idle-list
                       :key #'timer--function)
             1))
  (should (= (cl-count #'+my/compile-pending-h after-load-functions) 1)))

;; ====== CUSTOM CONFIG ======

(ert-deftest config/identity ()
  (should (equal user-full-name "Yorgos S."))
  (should (equal user-mail-address "smyrgeorge@gmail.com")))

(ert-deftest config/font-theme-line-numbers ()
  (should (fontp doom-font))
  (should (equal (format "%s" (font-get doom-font :family)) "JetBrains Mono"))
  ;; macOS: 13 px; Linux: 10 pt (the screen's DPI followed).
  (should (eql (font-get doom-font :size) (if (eq system-type 'darwin) 13 10.0)))
  (should (eq doom-theme 'doom-one))
  (should (eq display-line-numbers-type t)))

(ert-deftest config/org-directory ()
  (should (equal org-directory "~/dev/org/")))

(ert-deftest config/default-directory-home ()
  (should (equal +test-config--default-directory "~")))

(ert-deftest config/fill-column-120-everywhere ()
  "Maximum line length 120, as every buffer's default (setq-default)."
  (should (= (default-value 'fill-column) 120))
  (should (= +test-config--fill-column-buffer 120))
  (with-temp-buffer
    (should (= fill-column 120)))
  (should (member '(setq-default fill-column 120) (+test-config--forms))))

(ert-deftest config/projects-under-dev ()
  "Where Projectile finds projects: set here, config/projectile.el sets none."
  (should (equal projectile-project-search-path '("~/dev")))
  (should (member '(setq projectile-project-search-path '("~/dev")) (+test-config--forms))))

(ert-deftest config/tiling-strategy-tall ()
  (should (eq +my/tiling-strategy 'tall))
  (should (eq (default-value '+my/tiling-strategy) 'tall)))

(ert-deftest config/tiling-first ()
  "Tiling first (config/tiling/apps.el): applications in new panes."
  (should (equal display-buffer-overriding-action '((+my/tiling--display))))
  (should (eq +my/tiling-apps 'all))
  (should (memq 'ghostel-mode (+my/tiling--apps)))
  (should (memq 'agent-shell-mode (+my/tiling--apps))))

(ert-deftest config/tiling-can-be-taken-out ()
  "Tiling first lives in config/tiling.el and config/tiling/: config.el loads
it and chooses its strategy and applications; no other file uses it, so
without that `load!' each feature opens its windows as it does alone."
  (let ((dir (expand-file-name "config/" +test-root))
        (users nil))
    (dolist (file (directory-files-recursively dir "\\.el\\'"))
      (unless (string-match-p "/config/tiling\\(?:\\.el\\|/\\)" file)
        (with-temp-buffer
          (insert-file-contents file)
          (when (re-search-forward "+my/tiling" nil t)
            (push (file-relative-name file +test-root) users)))))
    (should-not users))
  (let ((forms (seq-filter (lambda (form) (string-match-p "+my/tiling" (format "%S" form)))
                           (+test-config--forms))))
    (should (equal forms '((setq +my/tiling-strategy 'tall) (setq +my/tiling-apps 'all))))))

(ert-deftest config/notifications-can-be-taken-out ()
  "Notifications live in config/notify.el and config/notify/ (the desktop's
side, `+my/os-notify', in config/os.el): config.el loads them, no other file
fires one, so without that `load!' nothing notifies and nothing breaks."
  (let ((users nil))
    (dolist (file (directory-files-recursively (expand-file-name "config/" +test-root) "\\.el\\'"))
      (unless (string-match-p "/config/notify\\(?:\\.el\\|/\\)" file)
        (with-temp-buffer
          (insert-file-contents file)
          (when (re-search-forward "+my/notify" nil t)
            (push (file-relative-name file +test-root) users)))))
    (should-not users))
  (should (equal (seq-filter (lambda (form) (string-match-p "notify" (format "%S" form)))
                             (+test-config--forms))
                 '((load! "config/notify")))))

(ert-deftest config/agent-ui-questions-focused-and-closed ()
  "Agent UI's questions take the focus, and go once answered (the library's
own default: neither)."
  (should (eq agent-ui-focus-questions t))
  (should (eq agent-ui-close-answered t)))

(ert-deftest config/pdf-dark-pages ()
  "PDFs open with dark pages (config/pdf.el's own default: light)."
  (should (eq +my/pdf-dark-pages t)))

;; ====== LOAD ORDER ======

(defun +test-config--position (form)
  (seq-position (+test-config--forms) form))

(defun +test-config--load-position (name)
  (seq-position (+test-config--loads) name))

(ert-deftest config/order-settings-before-files ()
  "The settings the files read when they load come first: the tiling strategy,
dark PDF pages, Agent UI's questions (their files' defvars keep them)."
  (should (< (+test-config--position '(setq +my/tiling-strategy 'tall))
             (+test-config--position '(load! "config/tiling"))))
  (should (< (+test-config--position '(setq +my/pdf-dark-pages t))
             (+test-config--position '(load! "config/pdf"))))
  (should (< (+test-config--position '(setq agent-ui-focus-questions t agent-ui-close-answered t))
             (+test-config--position '(load! "config/agent-ui"))))
  (should (< (+test-config--position '(setq-default fill-column 120))
             (+test-config--position '(load! "config/editor")))))

(ert-deftest config/order-webkit-before-its-pages ()
  "config/webkit.el, before the Markdown preview, the PDF viewer and drawings
built on it (config/markdown.el binds its clicks as it loads)."
  (should (< (+test-config--load-position "config/webkit")
             (+test-config--load-position "config/markdown")))
  (should (< (+test-config--load-position "config/webkit")
             (+test-config--load-position "config/pdf")))
  (should (< (+test-config--load-position "config/webkit")
             (+test-config--load-position "config/excalidraw")))
  (should (eq (lookup-key +my/excalidraw-mode-map [down-mouse-1]) #'+my/webkit-mouse-select))
  (should (eq (lookup-key +md-preview-page-mode-map [down-mouse-1]) #'+my/webkit-mouse-select)))

(ert-deftest config/order-childframe-before-its-users ()
  "config/childframe.el before the notices, the error stripe and WebKit's
cover, which make their frames with it."
  (dolist (name '("config/banner" "config/stripe" "config/webkit"))
    (should (< (+test-config--load-position "config/childframe")
               (+test-config--load-position name)))))

(ert-deftest config/order-actions-before-pdf ()
  "config/editor.el (Option+Enter's providers) before config/pdf.el, which puts
its provider first in the Option+Enter menu, and config/excalidraw.el, which
puts its last."
  (should (< (+test-config--load-position "config/editor")
             (+test-config--load-position "config/pdf")))
  (should (< (+test-config--load-position "config/editor")
             (+test-config--load-position "config/excalidraw")))
  (should (eq (car +my/context-action-providers) '+my/context-actions-pdf))
  (should (equal (cdr +my/context-action-providers)
                 '(+my/context-actions-spelling +my/context-actions-lsp +my/context-actions-claude
                   +my/context-actions-excalidraw))))

(ert-deftest config/order-window-before-tiling ()
  "Window behaviour (new windows get focus) is set up before tiling uses it."
  (should (< (+test-config--load-position "config/window")
             (+test-config--load-position "config/tiling"))))

(ert-deftest config/order-compile-last ()
  "config/compile.el is the last thing config.el does."
  (should (equal (car (last (+test-config--forms))) '(load! "config/compile")))
  (should (equal (car (last (+test-config--loaded) 2))
                 (+test-config--file "config/compile")))
  ;; So its first pass sees every config function, from the first file to
  ;; the last.
  (let ((candidates (+my/compile--candidates)))
    (should (memq '+my/tiling-split candidates))
    (should (memq '+my/context-actions candidates))
    (should (memq '+my/goto-declaration-or-usages candidates))))

(ert-deftest config/everything-defined ()
  "A command from each part of the config is there after loading."
  (dolist (fn '(+my/tiling-split +my/goto-declaration-or-usages +my/context-actions
                +my/agent-shell-claude-theme +my/lsp-gitignored-directories
                +my/peek--title +my/compile-config-functions-h +my/excalidraw-insert))
    (should (fboundp fn))))

;; ====== THE TESTS' DOOM ======

(ert-deftest config/the-tests-modulep-as-doom-s ()
  "tests/helper.el's `modulep!': a module and flags from init.el; in a
module's file (`+test-load-module'), flags only ask about that module."
  (should (modulep! :ui vc-gutter))
  (should (modulep! :ui vc-gutter +pretty))
  (should-not (modulep! :ui vc-gutter +no-such-flag))
  (should-not (eval '(modulep! +pretty) t))     ; no module being loaded
  (let ((+test-module-context '(:ui vc-gutter)))
    (should (eval '(modulep! +pretty) t))
    (should-not (eval '(modulep! +no-such-flag) t)))
  (should-error (+test-load-module :ui 'no-such-module))
  ;; Doom's :system feature.
  (should (featurep :system (if (eq system-type 'darwin) 'macos 'linux))))
