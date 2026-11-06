;;; tests/unit/test-tree-sitter.el -*- lexical-binding: t; -*-
;; config/tree-sitter.el: the enabled languages' grammars built ahead of time,
;; in a background `emacs --batch', after startup. No grammar is ever built or
;; downloaded here: `make-process' is mocked (a `true' runs instead), the build
;; script is evaluated with `treesit-install-language-grammar' mocked.

(require 'treesit)
(+test-load "config/tree-sitter")

;; Never build a grammar in the tests' Emacs.
(advice-add 'treesit-install-language-grammar :override
            (lambda (&rest args) (error "Tests never build grammars: %S" args))
            '((name . +test-tree-sitter-guard)))

;; ====== HELPERS ======

(defvar +test-tree-sitter--modes nil
  "Symbols a test gave a `+tree-sitter' property.")

(defun +test-tree-sitter--register (mode &rest grammars)
  "Register MODE for GRAMMARS, as Doom's `set-tree-sitter!' does."
  (push mode +test-tree-sitter--modes)
  (put mode '+tree-sitter (cons 'some-mode grammars)))

(defun +test-tree-sitter--profile-data-dir (&optional _profile &rest segments)
  "Doom's profile data folder, in the temp folder (helper.el's definition is
replaced by Doom's own when doom-lib.el loads)."
  (apply #'file-name-concat (+test-tmp-file "local/profile/") segments))

(defmacro +test-tree-sitter (&rest body)
  "BODY with a fresh state: no build running, no recipes, an empty
`temporary-file-directory' (the build's init folders), *Messages* and the
build buffer cleared, Doom's folders in the temp folder; registered modes
forgotten after."
  (declare (indent 0))
  `(let ((+my/tree-sitter--process nil)
         (treesit-language-source-alist nil)
         (temporary-file-directory
          (file-name-as-directory (make-temp-file (+test-tmp-file "ts-tmp/x-") t))))
     (+test-clear-messages)
     (when (get-buffer +my/tree-sitter-buffer)
       (kill-buffer +my/tree-sitter-buffer))
     (cl-letf (((symbol-function 'doom-profile-data-dir) #'+test-tree-sitter--profile-data-dir))
       (unwind-protect (progn ,@body)
         (dolist (mode +test-tree-sitter--modes)
           (put mode '+tree-sitter nil))
         (setq +test-tree-sitter--modes nil)))))

(defun +test-tree-sitter--build-dirs ()
  "The build's init folders left in `temporary-file-directory'."
  (directory-files temporary-file-directory nil "\\`tree-sitter-build-"))

(defvar +test-tree-sitter--started nil
  "The `make-process' calls of a mocked build: their plists.")

(defmacro +test-tree-sitter-with-fake-build (available &rest body)
  "BODY with `make-process' mocked: the build's arguments are recorded (in
`+test-tree-sitter--started'), and `true' runs instead, with the build's
sentinel. AVAILABLE: a form, the grammars `treesit-language-available-p' says
are there (a list, re-evaluated at each call). The build is waited for after."
  (declare (indent 1))
  `(let ((+test-tree-sitter--started nil)
         (processes nil)
         (real-make-process (symbol-function 'make-process)))
     (cl-letf (((symbol-function 'make-process)
                (lambda (&rest args)
                  (push args +test-tree-sitter--started)
                  (car (push (funcall real-make-process
                                      :name (plist-get args :name)
                                      :buffer (plist-get args :buffer)
                                      :noquery t
                                      :command (list (or (executable-find "true") "true"))
                                      :sentinel (plist-get args :sentinel))
                             processes))))
               ((symbol-function 'treesit-language-available-p)
                (lambda (grammar &rest _) (memq grammar ,available))))
       (unwind-protect (progn ,@body)
         ;; The build's end: its sentinel ran (it forgets the process).
         (let ((end (+ (float-time) 10)))
           (while (and (memq +my/tree-sitter--process processes) (< (float-time) end))
             (accept-process-output nil 0.05)))))))

(defun +test-tree-sitter--command-form (command)
  "The Lisp form the build's COMMAND evaluates (its --eval)."
  (car (read-from-string (cadr (member "--eval" command)))))

(defun +test-tree-sitter--finished-process (grammars init-dir &optional command)
  "A process that ran (and exited), with the build's properties."
  (let ((process (make-process :name "ts-test" :noquery t
                               :command (or command (list (or (executable-find "true") "true"))))))
    (while (process-live-p process) (accept-process-output process 0.05))
    (process-put process 'grammars grammars)
    (process-put process 'init-dir init-dir)
    process))

;; ====== SETTINGS ======

(ert-deftest tree-sitter/settings ()
  (should (eql (default-value '+my/tree-sitter-install-delay) 10))
  (should (equal +my/tree-sitter-buffer "*tree-sitter grammars*"))
  (should (commandp #'+my/tree-sitter-install-grammars)))

;; ====== AFTER STARTUP ======

(ert-deftest tree-sitter/startup-schedules-a-quiet-idle-build ()
  "After startup: an idle timer, once, 10 s, quietly."
  (should (memq #'+my/tree-sitter-install-later-h emacs-startup-hook))
  (let ((timer (+my/tree-sitter-install-later-h)))
    (unwind-protect
        (progn
          (should (timerp timer))
          (should (memq timer timer-idle-list))
          (should (timer--idle-delay timer))
          (should (time-equal-p (timer--time timer) 10))
          (should-not (timer--repeat-delay timer))
          (should (eq (timer--function timer) #'+my/tree-sitter-install-grammars))
          (should (equal (timer--args timer) '(quiet))))
      (cancel-timer timer))))

(ert-deftest tree-sitter/startup-delay-follows-the-setting ()
  (let ((+my/tree-sitter-install-delay 3))
    (let ((timer (+my/tree-sitter-install-later-h)))
      (unwind-protect (should (time-equal-p (timer--time timer) 3))
        (cancel-timer timer)))))

(ert-deftest tree-sitter/no-delay-no-startup-build ()
  "`+my/tree-sitter-install-delay' nil: loading the file adds no startup hook."
  (unwind-protect
      (progn
        (remove-hook 'emacs-startup-hook #'+my/tree-sitter-install-later-h)
        (let ((+my/tree-sitter-install-delay nil))
          (+test-load "config/tree-sitter"))
        (should-not (memq #'+my/tree-sitter-install-later-h emacs-startup-hook)))
    (+test-load "config/tree-sitter")
    (should (memq #'+my/tree-sitter-install-later-h emacs-startup-hook))))

;; ====== THE GRAMMARS NEEDED ======

(ert-deftest tree-sitter/grammars-of-registered-modes ()
  "Every grammar registered with `set-tree-sitter!', once, sorted."
  (+test-tree-sitter
    (let ((before (+my/tree-sitter--grammars)))
      (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-zeta '+test-ts-alpha)
      (+test-tree-sitter--register '+test-ts-two-mode '+test-ts-alpha '+test-ts-mid)
      (+test-tree-sitter--register '+test-ts-three-mode) ; no grammar
      (put '+test-ts-odd-mode '+tree-sitter t)            ; not Doom's format
      (push '+test-ts-odd-mode +test-tree-sitter--modes)
      (let ((grammars (+my/tree-sitter--grammars)))
        (should (equal grammars
                       (sort (append '(+test-ts-alpha +test-ts-mid +test-ts-zeta) before)
                             #'string<)))
        (should (equal grammars (seq-uniq grammars)))))))

(ert-deftest tree-sitter/grammars-none-registered ()
  (+test-tree-sitter
    (let ((grammars (+my/tree-sitter--grammars)))
      (should (listp grammars))
      (should-not (seq-filter (lambda (g) (string-prefix-p "+test-ts" (symbol-name g)))
                              grammars)))))

(ert-deftest tree-sitter/missing-are-the-unavailable-ones ()
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a '+test-ts-b '+test-ts-c)
    (cl-letf (((symbol-function 'treesit-language-available-p)
               (lambda (grammar &rest _)
                 (or (eq grammar '+test-ts-b)
                     (not (string-prefix-p "+test-ts" (symbol-name grammar)))))))
      (should (equal (+my/tree-sitter--missing) '(+test-ts-a +test-ts-c))))))

;; ====== RECIPES ======

(defun +test-tree-sitter--mode-file (name body)
  "A library NAME on `load-path' (a temp folder) with BODY; the folder."
  (let ((dir (file-name-directory (+test-tmp-file (format "ts-lib/%s/" name)))))
    (with-temp-file (expand-file-name (concat name ".el") dir)
      (insert ";;; -*- lexical-binding: t; -*-\n" body))
    dir))

(ert-deftest tree-sitter/recipe-already-known ()
  (+test-tree-sitter
    (setq treesit-language-source-alist '((+test-ts-known "https://example.invalid/known")))
    (should (equal (+my/tree-sitter--recipe '+test-ts-known)
                   '(+test-ts-known "https://example.invalid/known")))))

(ert-deftest tree-sitter/recipe-loads-the-autoloaded-mode ()
  "A recipe a ts-mode brings when loaded: the mode is loaded (as Doom does on
first use), without taking over file names."
  (+test-tree-sitter
    (let* ((dir (+test-tree-sitter--mode-file
                 "test-ts-foo-mode"
                 "(add-to-list 'treesit-language-source-alist '(+test-ts-foo \"https://example.invalid/foo\" \"main\"))
(add-to-list 'auto-mode-alist '(\"\\\\.foo\\\\'\" . test-ts-foo-mode))
(add-to-list 'interpreter-mode-alist '(\"foo\" . test-ts-foo-mode))
(defun test-ts-foo-mode () (interactive))
(provide 'test-ts-foo-mode)\n"))
           (load-path (cons dir load-path))
           (auto-mode-alist (copy-sequence auto-mode-alist))
           (interpreter-mode-alist (copy-sequence interpreter-mode-alist))
           (modes-before auto-mode-alist)
           (interpreters-before interpreter-mode-alist))
      (autoload 'test-ts-foo-mode "test-ts-foo-mode" nil t)
      (+test-tree-sitter--register 'test-ts-foo-mode '+test-ts-foo)
      (unwind-protect
          (progn
            (should (equal (+my/tree-sitter--recipe '+test-ts-foo)
                           '(+test-ts-foo "https://example.invalid/foo" "main")))
            (should-not (autoloadp (symbol-function 'test-ts-foo-mode)))
            (should (eq auto-mode-alist modes-before))
            (should (eq interpreter-mode-alist interpreters-before))
            (should-not (rassq 'test-ts-foo-mode auto-mode-alist)))
        (fmakunbound 'test-ts-foo-mode)
        (setq features (delq 'test-ts-foo-mode features))))))

(ert-deftest tree-sitter/recipe-other-modes-stay-unloaded ()
  "Only the modes registered for that grammar are loaded."
  (+test-tree-sitter
    (let* ((dir (+test-tree-sitter--mode-file
                 "test-ts-bar-mode"
                 "(defun test-ts-bar-mode () (interactive))\n(provide 'test-ts-bar-mode)\n"))
           (load-path (cons dir load-path)))
      (autoload 'test-ts-bar-mode "test-ts-bar-mode" nil t)
      (+test-tree-sitter--register 'test-ts-bar-mode '+test-ts-bar)
      (unwind-protect
          (progn
            (should-not (+my/tree-sitter--recipe '+test-ts-other))
            (should (autoloadp (symbol-function 'test-ts-bar-mode))))
        (fmakunbound 'test-ts-bar-mode)))))

(ert-deftest tree-sitter/recipe-loaded-modes-not-reloaded ()
  "A mode already defined (not an autoload) isn't loaded again: no recipe."
  (+test-tree-sitter
    (let ((called nil))
      (defalias 'test-ts-baz-mode (lambda () (interactive) (setq called t)))
      (+test-tree-sitter--register 'test-ts-baz-mode '+test-ts-baz)
      (unwind-protect
          (progn
            (should-not (+my/tree-sitter--recipe '+test-ts-baz))
            (should-not called))
        (fmakunbound 'test-ts-baz-mode)))))

(ert-deftest tree-sitter/recipe-broken-mode-is-no-recipe ()
  "A mode whose library fails to load: no recipe, no error."
  (+test-tree-sitter
    (let* ((dir (+test-tree-sitter--mode-file
                 "test-ts-broken-mode" "(error \"Broken library\")\n"))
           (load-path (cons dir load-path)))
      (autoload 'test-ts-broken-mode "test-ts-broken-mode" nil t)
      (+test-tree-sitter--register 'test-ts-broken-mode '+test-ts-broken)
      (unwind-protect
          (should-not (+my/tree-sitter--recipe '+test-ts-broken))
        (fmakunbound 'test-ts-broken-mode)))))

;; ====== M-x +my/tree-sitter-install-grammars ======

(ert-deftest tree-sitter/install-without-tree-sitter ()
  (+test-tree-sitter
    (cl-letf (((symbol-function 'treesit-available-p) #'ignore)
              ((symbol-function 'make-process)
               (lambda (&rest _) (error "No build without tree-sitter"))))
      (+my/tree-sitter-install-grammars 'quiet)
      (should (= (+test-messages "no tree-sitter") 0))
      (+my/tree-sitter-install-grammars)
      (should (= (+test-messages "^This Emacs has no tree-sitter$") 1))
      (should-not +my/tree-sitter--process))))

(ert-deftest tree-sitter/install-while-building ()
  "A build already running: no second one; said unless quiet."
  (+test-tree-sitter
    (let ((running (make-process :name "ts-running" :noquery t
                                 :command (list (or (executable-find "sleep") "sleep") "10"))))
      (unwind-protect
          (cl-letf (((symbol-function 'make-process)
                     (lambda (&rest _) (error "No second build"))))
            (setq +my/tree-sitter--process running)
            (+my/tree-sitter-install-grammars 'quiet)
            (should (= (+test-messages "still building") 0))
            (+my/tree-sitter-install-grammars)
            (should (= (+test-messages "^Tree-sitter grammars: still building (see \\*tree-sitter grammars\\*)$") 1))
            (should (eq +my/tree-sitter--process running))
            (should-not (+test-tree-sitter--build-dirs)))
        (delete-process running)))))

(ert-deftest tree-sitter/install-a-finished-build-is-not-running ()
  "The last build's process, exited, doesn't block a new one."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a)
    (setq treesit-language-source-alist '((+test-ts-a "https://example.invalid/a")))
    (setq +my/tree-sitter--process (+test-tree-sitter--finished-process nil nil))
    (+test-tree-sitter-with-fake-build nil
      (+my/tree-sitter-install-grammars 'quiet)
      (should (= (length +test-tree-sitter--started) 1)))))

(ert-deftest tree-sitter/install-nothing-missing ()
  "All there: no build, its init folder removed; said unless quiet."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a)
    (+test-tree-sitter-with-fake-build '(+test-ts-a)
      (+my/tree-sitter-install-grammars 'quiet)
      (should (= (+test-messages "all there") 0))
      (+my/tree-sitter-install-grammars)
      (should (= (+test-messages "^Tree-sitter grammars: all there$") 1))
      (should-not +test-tree-sitter--started)
      (should-not +my/tree-sitter--process)
      (should-not (+test-tree-sitter--build-dirs)))))

(ert-deftest tree-sitter/install-missing-without-recipe ()
  "Missing grammars nobody has a recipe for: said, even quietly; no build."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-x '+test-ts-y)
    (+test-tree-sitter-with-fake-build nil
      (+my/tree-sitter-install-grammars 'quiet)
      (should (= (+test-messages "^Tree-sitter grammars: no recipe for \\+test-ts-x, \\+test-ts-y$") 1))
      (should-not +test-tree-sitter--started)
      (should-not +my/tree-sitter--process)
      (should-not (+test-tree-sitter--build-dirs)))))

(ert-deftest tree-sitter/install-builds-in-another-emacs ()
  "The missing grammars with a recipe: built by `emacs --batch -Q' with its own
init folder (never ~/.emacs.d), into Doom's grammar folder."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a '+test-ts-b '+test-ts-c '+test-ts-ok)
    (setq treesit-language-source-alist
          '((+test-ts-a "https://example.invalid/a")
            (+test-ts-b "https://example.invalid/b" "main" "src")))
    (+test-tree-sitter-with-fake-build '(+test-ts-ok)
      (+my/tree-sitter-install-grammars 'quiet)
      (should (= (length +test-tree-sitter--started) 1))
      (let* ((args (car +test-tree-sitter--started))
             (command (plist-get args :command))
             (out-dir (doom-profile-data-dir t "tree-sitter"))
             (init-dir (process-get +my/tree-sitter--process 'init-dir)))
        (should (equal (plist-get args :name) "tree-sitter-grammars"))
        (should (equal (plist-get args :buffer) +my/tree-sitter-buffer))
        (should (eq (plist-get args :noquery) t))
        (should (eq (plist-get args :sentinel) #'+my/tree-sitter--done))
        ;; This Emacs's executable, plain, its own (temp) init folder.
        (should (equal (seq-take command 4)
                       (list (expand-file-name invocation-name invocation-directory)
                             "--batch" "-Q" (concat "--init-directory=" init-dir))))
        (should (equal (nth 4 command) "--eval"))
        (should (= (length command) 6))
        (should (file-directory-p init-dir))
        (should (string-prefix-p temporary-file-directory init-dir))
        (should (string-match-p "/tree-sitter-build-[^/]*\\'" init-dir))
        ;; Doom's grammar folder (in the tests' temp folder).
        (should (string-prefix-p (expand-file-name +test-tmp) (expand-file-name out-dir)))
        ;; The process remembers what it builds.
        (should (equal (process-get +my/tree-sitter--process 'grammars) '(+test-ts-a +test-ts-b)))
        (should (process-live-p +my/tree-sitter--process))
        ;; Said, with the grammars without a recipe.
        (should (= (+test-messages "^Building tree-sitter grammars in the background: \\+test-ts-a, \\+test-ts-b (no recipe for \\+test-ts-c)$") 1))
        ;; The build's buffer says what and where.
        (with-current-buffer +my/tree-sitter-buffer
          (should (string-match-p
                   (format "^[0-9-]+ [0-9:]+: building \\+test-ts-a \\+test-ts-b into %s$"
                           (regexp-quote out-dir))
                   (buffer-string))))))))

;; BUG fixed: the build started in the current buffer's folder, which
;; couldn't when that folder was gone (deleted outside Emacs).
(ert-deftest tree-sitter/install-from-a-buffer-whose-folder-is-gone ()
  "The build starts from its own init folder, whatever the current buffer's."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a)
    (setq treesit-language-source-alist '((+test-ts-a "https://example.invalid/a")))
    (let ((started-in nil))
      (+test-tree-sitter-with-fake-build nil
        (advice-add 'make-process :before
                    (lambda (&rest _) (push default-directory started-in))
                    '((name . +test-ts-where) (depth . -100)))
        (unwind-protect
            (with-temp-buffer
              (setq default-directory (+test-tmp-file "deleted-folder/"))
              (delete-directory default-directory)
              (+my/tree-sitter-install-grammars 'quiet))
          (advice-remove 'make-process '+test-ts-where))
        (should (= (length +test-tree-sitter--started) 1)))
      (should (= (length started-in) 1))
      (should (string-match-p "/tree-sitter-build-[^/]+/\\'" (car started-in)))
      (should (string-prefix-p (file-truename temporary-file-directory)
                               (file-truename (car started-in)))))))

(ert-deftest tree-sitter/install-message-without-unknown ()
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a)
    (setq treesit-language-source-alist '((+test-ts-a "https://example.invalid/a")))
    (+test-tree-sitter-with-fake-build nil
      (+my/tree-sitter-install-grammars)
      (should (= (+test-messages "^Building tree-sitter grammars in the background: \\+test-ts-a$") 1)))))

(ert-deftest tree-sitter/install-build-buffer-keeps-earlier-output ()
  (+test-tree-sitter
    (with-current-buffer (get-buffer-create +my/tree-sitter-buffer)
      (insert "earlier build\n")
      (setq buffer-read-only t))
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a)
    (setq treesit-language-source-alist '((+test-ts-a "https://example.invalid/a")))
    (+test-tree-sitter-with-fake-build nil
      (+my/tree-sitter-install-grammars)
      (with-current-buffer +my/tree-sitter-buffer
        (should (string-prefix-p "earlier build\n" (buffer-string)))
        (should (string-match-p "building \\+test-ts-a into" (buffer-string)))))))

(ert-deftest tree-sitter/build-script ()
  "What the other Emacs runs: the recipes, each grammar built into Doom's
folder; one failing doesn't stop the others."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a '+test-ts-b '+test-ts-c)
    (let ((recipes '((+test-ts-a "https://example.invalid/a")
                     (+test-ts-b "https://example.invalid/b" "v1.0" "src" nil nil)
                     (+test-ts-c "https://example.invalid/c"))))
      (setq treesit-language-source-alist recipes)
      (+test-tree-sitter-with-fake-build nil
        (+my/tree-sitter-install-grammars)
        (let* ((form (+test-tree-sitter--command-form
                      (plist-get (car +test-tree-sitter--started) :command)))
               (out-dir (doom-profile-data-dir t "tree-sitter"))
               (built nil))
          (+test-clear-messages)
          (let ((treesit-language-source-alist nil))
            (cl-letf (((symbol-function 'treesit-install-language-grammar)
                       (lambda (grammar dir)
                         (push (list grammar dir (assq grammar treesit-language-source-alist))
                               built)
                         (when (eq grammar '+test-ts-b) (error "Boom")))))
              (eval form t)))
          (should (equal (nreverse built)
                         (mapcar (lambda (r) (list (car r) out-dir r)) recipes)))
          (should (= (+test-messages "^Building \\+test-ts-a\\.\\.\\.$") 1))
          (should (= (+test-messages "^Built \\+test-ts-a$") 1))
          (should (= (+test-messages "^FAILED \\+test-ts-b: Boom$") 1))
          (should (= (+test-messages "^Built \\+test-ts-b$") 0))
          (should (= (+test-messages "^Built \\+test-ts-c$") 1)))))))

;; ====== THE BUILD'S END ======

(ert-deftest tree-sitter/done-all-built ()
  (+test-tree-sitter
    (let* ((init-dir (make-temp-file "tree-sitter-build-" t))
           (process (+test-tree-sitter--finished-process '(+test-ts-a +test-ts-b) init-dir)))
      (setq +my/tree-sitter--process process)
      (cl-letf (((symbol-function 'treesit-language-available-p) #'always))
        (+my/tree-sitter--done process "finished\n"))
      (should-not +my/tree-sitter--process)
      (should-not (file-exists-p init-dir))
      (should (= (+test-messages "^Tree-sitter grammars built: \\+test-ts-a, \\+test-ts-b$") 1)))))

(ert-deftest tree-sitter/done-some-failed ()
  (+test-tree-sitter
    (let ((process (+test-tree-sitter--finished-process
                    '(+test-ts-a +test-ts-b +test-ts-c) (make-temp-file "tree-sitter-build-" t))))
      (cl-letf (((symbol-function 'treesit-language-available-p)
                 (lambda (grammar &rest _) (eq grammar '+test-ts-b))))
        (+my/tree-sitter--done process "exited abnormally with code 1\n"))
      (should (= (+test-messages "^Tree-sitter grammars: 1 built, \\+test-ts-a, \\+test-ts-c failed (see \\*tree-sitter grammars\\*)$") 1))
      (should-not (+test-tree-sitter--build-dirs)))))

(ert-deftest tree-sitter/done-forgets-unavailable-answers ()
  "New grammars: config/editor.el's cache of \"not available\" is emptied (when
that file is loaded; without it, no error)."
  (+test-tree-sitter
    (cl-letf (((symbol-function 'treesit-language-available-p) #'always))
      ;; Without config/editor.el.
      (should-not (boundp '+my/treesit--available))
      (+my/tree-sitter--done (+test-tree-sitter--finished-process '(+test-ts-a) nil) "finished\n")
      ;; With it.
      (unwind-protect
          (let ((cache (make-hash-table :test #'equal)))
            (puthash '+test-ts-a nil cache)
            (set '+my/treesit--available cache)
            (+my/tree-sitter--done (+test-tree-sitter--finished-process '(+test-ts-a) nil) "finished\n")
            (should (= (hash-table-count cache) 0)))
        (makunbound '+my/treesit--available)))))

(ert-deftest tree-sitter/done-killed-build-ends-too ()
  "A build killed (signal) ends like one that exited."
  (+test-tree-sitter
    (let* ((init-dir (make-temp-file "tree-sitter-build-" t))
           (process (make-process :name "ts-killed" :noquery t
                                  :command (list (or (executable-find "sleep") "sleep") "10"))))
      (process-put process 'grammars '(+test-ts-a))
      (process-put process 'init-dir init-dir)
      (setq +my/tree-sitter--process process)
      (cl-letf (((symbol-function 'treesit-language-available-p) #'ignore))
        ;; Still running: an event that isn't its end changes nothing.
        (+my/tree-sitter--done process "open\n")
        (should (eq +my/tree-sitter--process process))
        (should (file-directory-p init-dir))
        (should (= (+test-messages "Tree-sitter grammars") 0))
        (kill-process process)
        (while (process-live-p process) (accept-process-output process 0.05))
        (should (eq (process-status process) 'signal))
        (+my/tree-sitter--done process "killed\n"))
      (should-not +my/tree-sitter--process)
      (should-not (file-exists-p init-dir))
      (should (= (+test-messages "^Tree-sitter grammars: 0 built, \\+test-ts-a failed") 1)))))

(ert-deftest tree-sitter/done-without-init-dir ()
  (+test-tree-sitter
    (cl-letf (((symbol-function 'treesit-language-available-p) #'always))
      (let ((gone (make-temp-file "tree-sitter-build-" t)))
        (delete-directory gone)
        (+my/tree-sitter--done (+test-tree-sitter--finished-process '(+test-ts-a) gone) "finished\n")
        (should (= (+test-messages "^Tree-sitter grammars built: \\+test-ts-a$") 1))
        (+test-clear-messages)
        (+my/tree-sitter--done (+test-tree-sitter--finished-process '(+test-ts-a) nil) "finished\n")
        (should (= (+test-messages "^Tree-sitter grammars built: \\+test-ts-a$") 1))))))

(ert-deftest tree-sitter/whole-build-in-the-background ()
  "From M-x to the end: the background Emacs runs (a `true' here), its
sentinel says what got built, removes its init folder and forgets it."
  (+test-tree-sitter
    (+test-tree-sitter--register '+test-ts-one-mode '+test-ts-a '+test-ts-b)
    (setq treesit-language-source-alist
          '((+test-ts-a "https://example.invalid/a") (+test-ts-b "https://example.invalid/b")))
    (let ((built nil) process)
      (+test-tree-sitter-with-fake-build built
        (+my/tree-sitter-install-grammars)
        (setq process +my/tree-sitter--process)
        (should (process-live-p process))
        (should (= (length (+test-tree-sitter--build-dirs)) 1))
        ;; What the other Emacs would build, there once it ends.
        (setq built '(+test-ts-a +test-ts-b)))
      (should-not +my/tree-sitter--process)
      (should (memq (process-status process) '(exit signal)))
      (should-not (+test-tree-sitter--build-dirs))
      (should (= (+test-messages "^Tree-sitter grammars built: \\+test-ts-a, \\+test-ts-b$") 1))
      ;; Once built, nothing's missing.
      (cl-letf (((symbol-function 'treesit-language-available-p)
                 (lambda (g &rest _) (memq g built))))
        (+test-clear-messages)
        (+my/tree-sitter-install-grammars)
        (should (= (+test-messages "^Tree-sitter grammars: all there$") 1))))))
