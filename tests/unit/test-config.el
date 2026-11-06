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

(defvar +test-config--history-before (mapcar #'car load-history))

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
  "Each file config.el names, once, in its order, config.el itself last."
  (let ((expected (append (mapcar #'+test-config--file (+test-config--loads))
                          (list (expand-file-name "config.el" +test-root)))))
    (should (equal (+test-config--loaded) expected))))

(ert-deftest config/loaded-files-exist ()
  (let ((loads (+test-config--loads)))
    (should (> (length loads) 20))
    (dolist (name loads)
      (should (string-prefix-p "config/" name))
      (should (file-exists-p (+test-config--file name))))
    ;; Each once.
    (should (equal loads (delete-dups (copy-sequence loads))))))

(ert-deftest config/disabled-files-not-loaded ()
  "config/cheatsheet and config/pdf exist but are commented out: not loaded."
  (let ((text (with-temp-buffer
                (insert-file-contents (expand-file-name "config.el" +test-root))
                (buffer-string)))
        (loaded (+test-config--loaded)))
    (dolist (name '("config/cheatsheet" "config/pdf"))
      (should (file-exists-p (+test-config--file name)))
      (should-not (member name (+test-config--loads)))
      (should-not (member (+test-config--file name) loaded))
      (should (string-match-p (format "^;;(load! \"%s\")$" (regexp-quote name)) text))))
  ;; Nothing they define is there.
  (should-not (boundp '+my/cheatsheet-file))
  (should-not (boundp '+my/pdf-wheel-zoom-step))
  (should-not (fboundp '+my/pdf-wheel-zoom)))

(ert-deftest config/pdf-module-off-like-config-pdf ()
  "config/pdf (pdf-tools zoom) is off because Doom's pdf module is: PDFs open in
WebKit (config/pdf-xwidget)."
  (should-not (+test-module-p :tools 'pdf))
  (should (member "config/pdf-xwidget" (+test-config--loads))))

(ert-deftest config/every-config-file-accounted-for ()
  "Each config/*.el is loaded or one of the disabled ones: none forgotten."
  (let ((loads (+test-config--loads)))
    (dolist (file (directory-files (expand-file-name "config/" +test-root) nil "\\.el\\'"))
      (let ((name (concat "config/" (file-name-sans-extension file))))
        (should (or (member name loads)
                    (member name '("config/cheatsheet" "config/pdf"))))))))

(ert-deftest config/files-are-lexical-and-say-so ()
  "Every config file uses lexical binding (compile.el relies on it) and its
header says config.el loads it."
  (dolist (name (append (+test-config--loads) '("config/cheatsheet" "config/pdf")))
    (with-temp-buffer
      (insert-file-contents (+test-config--file name))
      (goto-char (point-min))
      (should (looking-at-p (format ";;; \\$DOOMDIR/%s\\.el -\\*- lexical-binding: t; -\\*-"
                                    (regexp-quote name))))
      (should (re-search-forward "Loaded \\(?:last \\)?from\\(?:\n;;\\)? config\\.el"
                                 (save-excursion (forward-line 5) (point)) t))))
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
  (should (eql (font-get doom-font :size) 13))
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

(ert-deftest config/tiling-strategy-tall ()
  (should (eq +my/tiling-strategy 'tall))
  (should (eq (default-value '+my/tiling-strategy) 'tall)))

;; ====== LOAD ORDER ======

(defun +test-config--position (form)
  (seq-position (+test-config--forms) form))

(defun +test-config--load-position (name)
  (seq-position (+test-config--loads) name))

(ert-deftest config/order-settings-before-files ()
  "The settings the files read when they load come first: the tiling strategy
(config/tiling.el's defvar keeps it)."
  (should (< (+test-config--position '(setq +my/tiling-strategy 'tall))
             (+test-config--position '(load! "config/tiling"))))
  (should (< (+test-config--position '(setq-default fill-column 120))
             (+test-config--position '(load! "config/editor")))))

(ert-deftest config/order-webkit-before-its-pages ()
  "config/webkit.el, before the Markdown preview and the PDF viewer built on
it (config/markdown.el binds its clicks as it loads)."
  (should (< (+test-config--load-position "config/webkit")
             (+test-config--load-position "config/markdown")))
  (should (< (+test-config--load-position "config/webkit")
             (+test-config--load-position "config/pdf-xwidget")))
  (should (eq (lookup-key +md-preview-page-mode-map [down-mouse-1]) #'+my/webkit-mouse-select)))

(ert-deftest config/order-actions-before-pdf ()
  "config/actions.el before config/pdf-xwidget.el, which puts its provider
first in the Option+Enter menu."
  (should (< (+test-config--load-position "config/actions")
             (+test-config--load-position "config/pdf-xwidget")))
  (should (eq (car +my/context-action-providers) '+my/context-actions-pdf))
  (should (equal (cdr +my/context-action-providers)
                 '(+my/context-actions-spelling +my/context-actions-lsp +my/context-actions-claude))))

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
                +my/peek--title +my/compile-config-functions-h))
    (should (fboundp fn))))
