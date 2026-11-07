;;; tests/helper.el -*- lexical-binding: t; -*-
;; What every test file shares. Loaded by tests/run.sh only, in a throwaway
;; Emacs (`emacs -Q --init-directory=<temp>`): Doom never loads tests/
;; (config.el only loads config/), and the tests never touch Doom's profile,
;; its state (places, history...) or a running Emacs.
;;
;; - Doom's packages come from its build folder (read-only), its macros
;;   (`after!', `defadvice!', `map!', `use-package!'...) from its own source,
;;   `modulep!' answers from this config's init.el, and Doom's folders
;;   (`doom-data-dir'...) are in the test's temp folder.
;; - `+test-load' loads config files as Doom does (with `map!' binding keys:
;;   Doom's `map!' does nothing in batch mode).
;; - Unit tests run in `emacs --batch'; end-to-end tests (tests/e2e) in a GUI
;;   Emacs, for WebKit and child frames, through `+test-e2e-run'.

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== FOLDERS ======

(defconst +test-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "tests/.")

(defconst +test-root (expand-file-name "../" +test-dir)
  "This config's folder ($DOOMDIR).")

(defconst +test-doom-emacs-dir
  (file-name-as-directory (or (getenv "DOOM_EMACS_DIR") (expand-file-name "~/.config/emacs/")))
  "Doom's own folder, read from only.")

(defconst +test-tmp
  (file-name-as-directory
   (file-truename (or (getenv "TEST_TMP") (make-temp-file "doom-tests-" t))))
  "This test run's temp folder: Doom's folders, files the tests write. Its true
name (macOS's /var is a link to /private/var): buffers visit files by theirs
(`find-file-visit-truename', as in Doom), so paths made here match them.")

(defun +test-tmp-file (name)
  "NAME in the test run's temp folder (its folders made)."
  (let ((file (expand-file-name name +test-tmp)))
    (make-directory (file-name-directory file) t)
    file))

;; Doom's packages (evil, magit, treemacs...), first as in Doom.
(let ((build (car (file-expand-wildcards
                   (expand-file-name ".local/straight/build-*/" +test-doom-emacs-dir)))))
  (when build
    (dolist (dir (nreverse (directory-files build t "\\`[^.]")))
      (when (file-directory-p dir)
        (push dir load-path)))))

;; Doom's folders, in the temp folder.
(defvar doom-emacs-dir +test-doom-emacs-dir)
(defvar doom-core-dir (expand-file-name "lisp/" +test-doom-emacs-dir))
(defvar doom-modules-dir (expand-file-name "modules/" +test-doom-emacs-dir))
(defvar doom-user-dir +test-root)
(defvar doom-local-dir (+test-tmp-file "local/"))
(defvar doom-data-dir (+test-tmp-file "local/etc/"))
(defvar doom-state-dir (+test-tmp-file "local/state/"))
(defvar doom-cache-dir (+test-tmp-file "local/cache/"))

;; What Doom has set up before a config loads: `use-package!' reads it.
(defvar doom-disabled-packages nil)

;; Nothing written outside the temp folder when Emacs exits (org-persist
;; wrote to ~/.cache once org was loaded).
(setq org-persist-directory (expand-file-name "org-persist/" doom-cache-dir))

;; The config's temp files (PDF pages, the Markdown preview's) in the test's
;; temp folder too.
(setq temporary-file-directory (+test-tmp-file "tmp/"))

;; As Doom: lsp-mode built for plists (its packages were compiled so).
(setenv "LSP_USE_PLISTS" "1")

;; As Doom: files by their true name (the temp folder is under /var, a link
;; to /private/var: a project's root and a file's name disagreed).
(setq find-file-visit-truename t
      vc-follow-symlinks t)

;; Doom's tree-sitter grammars, read from only.
(with-eval-after-load 'treesit
  (add-to-list 'treesit-extra-load-path
               (expand-file-name ".local/etc/tree-sitter/" +test-doom-emacs-dir)))

;; `cl-letf' on a built-in would compile a trampoline for it in another Emacs
;; process: slow, and a process a test didn't start.
(setq native-comp-enable-subr-trampolines nil)

;; Nor packages compiled to native code as they load, in Emacs processes of
;; their own: a test's reset killed their log buffer, their sentinels failed
;; on it, and the bell rang (macOS's alert sound) in each GUI test Emacs.
(setq native-comp-jit-compilation nil)

;; ====== DOOM ======

;; `modulep!': the modules (and flags) init.el's `doom!' block enables.
(defun +test--modules ()
  "((GROUP MODULE . FLAGS)...) from init.el's `doom!' block."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" +test-root))
    (goto-char (point-min))
    (let (form modules group)
      (condition-case nil
          (while (not (eq (car-safe form) 'doom!))
            (setq form (read (current-buffer))))
        (end-of-file (error "No doom! block in init.el")))
      (dolist (item (cdr form))
        (cond ((keywordp item) (setq group item))
              ((symbolp item) (push (list group item) modules))
              ((consp item) (push (cons group item) modules))))
      (nreverse modules))))

(defvar +test-modules (+test--modules)
  "The modules init.el enables: ((GROUP MODULE . FLAGS)...).")

(defun +test-module-p (group module &rest flags)
  "Non-nil if init.el enables GROUP MODULE, with FLAGS (a -flag: without it)."
  (when-let* ((entry (seq-find (lambda (m) (and (eq (car m) group) (eq (cadr m) module)))
                               +test-modules)))
    (seq-every-p (lambda (flag)
                   (let ((name (symbol-name flag)))
                     (if (string-prefix-p "-" name)
                         (not (memq (intern (concat "+" (substring name 1))) (cddr entry)))
                       (memq flag (cddr entry)))))
                 flags)))

(defvar +test-module-context nil
  "(GROUP MODULE) whose file `+test-load-module' is loading: `modulep!' with
flags only asks about it, as in Doom.")

(defmacro modulep! (group &optional module &rest flags)
  "Doom's `modulep!', answered from init.el (see `+test-modules'). With
flags only, about the module being loaded (`+test-module-context')."
  (cond ((keywordp group) (and (apply #'+test-module-p group module flags) t))
        (+test-module-context
         (and (apply #'+test-module-p (car +test-module-context) (cadr +test-module-context)
                     (delq nil (cons group (cons module flags))))
              t))))

;; Doom's :system feature, as doom.el announces it: (featurep :system 'macos).
(unless (featurep :system)
  (push :system features)
  (put :system 'subfeatures
       (cond ((eq system-type 'darwin) '(macos bsd))
             ((memq system-type '(cygwin windows-nt ms-dos)) '(windows))
             ((memq system-type '(gnu gnu/linux)) '(linux))
             ((memq system-type '(gnu/kfreebsd berkeley-unix)) '(linux bsd))
             ((eq system-type 'android) '(android)))))

(defun +test--no-popup-rules (&rest _)
  "Doom's `set-popup-rule!' / `set-popup-rules!': its :ui popup module isn't
loaded here, rules for its windows don't matter. (Doom's vc-gutter calls it
as diff-hl loads: the rest of its setup was skipped, an error.)"
  nil)
(unless (fboundp 'set-popup-rule!) (defalias 'set-popup-rule! #'+test--no-popup-rules))
(unless (fboundp 'set-popup-rules!) (defalias 'set-popup-rules! #'+test--no-popup-rules))

(defun +test-load-module (group module)
  "Load Doom's module GROUP MODULE (its config.el) as Doom does: its
`modulep!' about it."
  (let ((+test-module-context (list group module))
        (file (seq-find #'file-exists-p
                        (mapcar (lambda (dir)
                                  (expand-file-name (format "%s/%s/%s/config.el" dir (substring (symbol-name group) 1) module)
                                                    +test-doom-emacs-dir))
                                '("sources/doom+/modules" "modules")))))
    (unless file
      (error "No Doom module %s %s" group module))
    (load file nil t)))

;; Loaded in a running Emacs (Doom, config/compile.el compile): otherwise code
;; let-binding `byte-compile-warnings' before it's special (doom-modeline's
;; segments) fails as bytecomp loads in it.
(require 'bytecomp)

;; Doom's macros and helpers, its own source.
(load (expand-file-name "doom-lib.el" doom-core-dir) nil t)
(setq evil-want-keybinding nil              ; as Doom: evil-collection's keys
      evil-want-C-u-scroll t
      evil-want-C-i-jump t)
(require 'evil)
(evil-mode 1)
(load (expand-file-name "doom/compat/+keybinds.el" doom-modules-dir) nil t)
(load (expand-file-name "doom/compat/+use-package.el" doom-modules-dir) nil t)
(dolist (lib '("buffers" "projects" "files"))
  (load (expand-file-name (format "lib/%s.el" lib) doom-core-dir) nil t))

;; After Doom's library, which defines its own (it needs Doom's profiles).
(defun doom-profile-data-dir (&optional _profile &rest segments)
  "Doom's profile data folder (in the temp folder), SEGMENTS under it."
  (apply #'file-name-concat (+test-tmp-file "local/profile/") segments))

;; ====== NOTHING OPENS OUTSIDE ======

;; No test opens the browser: `browse-url' only records the URL (an advice, so
;; loading browse-url.el later doesn't bring the real one back, as a `defun'
;; stub let happen once: the user's browser opened a test link).
(defvar +test-browsed nil
  "The URLs `browse-url' was given, the latest first.")

(require 'browse-url)
(advice-add 'browse-url :override
            (lambda (url &rest _) (push url +test-browsed))
            '((name . +test-no-browser)))

;; ====== NO SOUND ======

;; Emacs's bell (macOS's alert sound, in the GUI Emacs of the end-to-end
;; tests) is silent: each ring is said on stderr instead, with the test it
;; rang in and how it came (an error a command signalled, say: worth a look).
(defvar +test-bells nil
  "The tests the bell rang in, the latest first.")

(defun +test--bell ()
  (let* ((test (and (fboundp 'ert-running-test) (ert-running-test)))
         (name (and test (ert-test-name test))))
    (push name +test-bells)
    (princ (format "BELL in %s:\n%s\n" (or name "no test")
                   (mapconcat (lambda (frame) (format "  %S" (cadr frame)))
                              (seq-take (backtrace-frames) 12) "\n"))
           #'external-debugging-output)))

(setq ring-bell-function #'+test--bell
      visible-bell nil)

(add-function :before command-error-function
              (lambda (data context _caller)
                (princ (format "COMMAND ERROR %S %S (last event %S)\n" data context last-input-event)
                       #'external-debugging-output))
              '((name . +test-command-errors)))

;; ====== LOADING THE CONFIG ======

(defun +test-load (&rest files)
  "Load FILES of this config (\"config/tiling\"...), as Doom does: `map!'
binds keys (Doom's does nothing in batch mode)."
  (dolist (file files)
    (let ((noninteractive nil)
          (inhibit-message t))
      (load (expand-file-name file +test-root) nil t))))

;; ====== TEST TOOLS ======

(defun +test-reset ()
  "One window, on *scratch*; the buffers tests made killed."
  (when (and (featurep 'evil) (bound-and-true-p evil-mode))
    (evil-normal-state))
  ;; Side panels first: `delete-other-windows' can't make one the only window.
  (dolist (window (window-list nil 'nomini))
    (when (window-parameter window 'window-side)
      (let ((ignore-window-parameters t))
        (ignore-errors (delete-window window)))))
  (select-window (frame-first-window))
  (delete-other-windows)
  ;; The window left may be one only its buffer goes in (a merge's bar...).
  (set-window-dedicated-p nil nil)
  (switch-to-buffer (get-buffer-create "*scratch*"))
  (dolist (buffer (buffer-list))
    ;; Killing one can kill others (a page's covers, a preview...).
    (unless (or (not (buffer-live-p buffer))
                (eq buffer (current-buffer))
                (string-prefix-p " " (buffer-name buffer))
                (member (buffer-name buffer) '("*Messages*" "*scratch*")))
      (let ((kill-buffer-query-functions nil))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(defmacro +test-with-reset (&rest body)
  "BODY from one window on *scratch*, and again after."
  (declare (indent 0))
  `(progn (+test-reset)
          (unwind-protect (progn ,@body)
            (+test-reset))))

(defun +test-buffer (name &optional content mode)
  "A buffer NAME (made anew) with CONTENT, in MODE."
  (when (get-buffer name)
    (let ((kill-buffer-query-functions nil))
      (kill-buffer name)))
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (when content (insert content))
      (goto-char (point-min))
      (when mode (funcall mode)))
    buffer))

(defun +test-file (name content)
  "Write CONTENT to NAME in the temp folder; return its path."
  (let ((file (+test-tmp-file name)))
    (with-temp-file file (insert content))
    file))

(defun +test-messages (regexp)
  "How many lines of *Messages* match REGEXP."
  (with-current-buffer (messages-buffer)
    (count-matches regexp (point-min) (point-max))))

(defun +test-clear-messages ()
  (with-current-buffer (messages-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer))))

;; PDFS
(defun +test-make-pdf (file &rest args)
  "Write a PDF to FILE: :pages (default 3) pages saying \"Page N text\",
:outline ((TITLE . PAGE)...) headings, :links ((PAGE . URL)...) a link on
that page's text. Its xref table is right (offsets counted)."
  (let* ((pages (or (plist-get args :pages) 3))
         (outline (plist-get args :outline))
         (links (plist-get args :links))
         (objects nil)
         (n 0)
         (new (lambda () (setq n (1+ n))))
         (catalog (funcall new))
         (pages-obj (funcall new))
         (font (funcall new))
         (page-objs (cl-loop repeat pages collect (funcall new)))
         (content-objs (cl-loop repeat pages collect (funcall new)))
         (link-objs (mapcar (lambda (link) (cons link (funcall new))) links))
         (outlines-obj (and outline (funcall new)))
         (item-objs (cl-loop repeat (length outline) collect (funcall new))))
    (push (cons catalog (format "<< /Type /Catalog /Pages %d 0 R%s >>" pages-obj
                                (if outline (format " /Outlines %d 0 R" outlines-obj) "")))
          objects)
    (push (cons pages-obj (format "<< /Type /Pages /Kids [%s] /Count %d >>"
                                  (mapconcat (lambda (o) (format "%d 0 R" o)) page-objs " ")
                                  pages))
          objects)
    (push (cons font "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>") objects)
    (cl-loop for page from 1 for obj in page-objs for content in content-objs
             do (let ((annots (cl-loop for (link . lobj) in link-objs
                                       when (eql (car link) page) collect (format "%d 0 R" lobj)))
                      (text (format "BT /F1 28 Tf 72 700 Td (Page %d text) Tj ET" page)))
                  (push (cons obj (format "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources << /Font << /F1 %d 0 R >> >>%s >>"
                                          pages-obj content font
                                          (if annots (format " /Annots [%s]" (string-join annots " ")) "")))
                        objects)
                  (push (cons content (format "<< /Length %d >>\nstream\n%s\nendstream" (length text) text))
                        objects)))
    (cl-loop for ((_page . url) . obj) in link-objs
             do (push (cons obj (format "<< /Type /Annot /Subtype /Link /Rect [72 690 320 730] /Border [0 0 0] /A << /S /URI /URI (%s) >> >>" url))
                      objects))
    (when outline
      (push (cons outlines-obj (format "<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count %d >>"
                                       (car item-objs) (car (last item-objs)) (length item-objs)))
            objects)
      (cl-loop for (title . page) in outline for obj in item-objs for i from 0
               do (push (cons obj (format "<< /Title (%s) /Parent %d 0 R%s%s /Dest [%d 0 R /XYZ 0 792 0] >>"
                                          title outlines-obj
                                          (if (> i 0) (format " /Prev %d 0 R" (nth (1- i) item-objs)) "")
                                          (if (< i (1- (length item-objs))) (format " /Next %d 0 R" (nth (1+ i) item-objs)) "")
                                          (nth (1- page) page-objs)))
                        objects)))
    (setq objects (sort objects (lambda (a b) (< (car a) (car b)))))
    (let ((coding-system-for-write 'no-conversion))
      (with-temp-file file
        (set-buffer-multibyte nil)
        (insert "%PDF-1.4\n")
        (let (offsets)
          (dolist (object objects)
            (push (1- (point)) offsets)
            (insert (format "%d 0 obj\n%s\nendobj\n" (car object) (cdr object))))
          (let ((xref (1- (point))))
            (insert (format "xref\n0 %d\n0000000000 65535 f \n" (1+ n)))
            (dolist (offset (nreverse offsets))
              (insert (format "%010d 00000 n \n" offset)))
            (insert (format "trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n"
                            (1+ n) catalog xref))))))
    file))

(defun +test-pdfjs-dir ()
  "A copy of PDF.js in the temp Doom's data folder, from the real one (never
downloaded by a test); nil if Doom has none."
  (let* ((version (if (boundp '+my/pdf-js-version) +my/pdf-js-version "3.11.174"))
         (name (format "pdfjs-%s" version))
         (real (expand-file-name (concat ".local/etc/" name) +test-doom-emacs-dir))
         (copy (expand-file-name name doom-data-dir)))
    (cond ((file-directory-p copy) copy)
          ((file-directory-p real) (copy-directory real copy nil t t) copy))))

;; DRAWINGS
(defun +test-excalidraw-dir ()
  "A copy of Excalidraw in the temp Doom's data folder, from the real one
(never downloaded by a test); nil if Doom has none."
  (let* ((version (if (boundp '+my/excalidraw-version) +my/excalidraw-version "0.17.6"))
         (name (format "excalidraw-%s" version))
         (real (expand-file-name (concat ".local/etc/" name) +test-doom-emacs-dir))
         (copy (expand-file-name name doom-data-dir)))
    (cond ((file-directory-p copy) copy)
          ((file-directory-p real) (copy-directory real copy nil t t) copy))))

;; ====== END TO END (GUI) ======

(defun +test--pump (seconds)
  "Up to SECONDS of Emacs at work, as its command loop would: a full redisplay
(it runs the window change functions: views start there), timers, WebKit's
events (read with the input). Not `sit-for': once a frame was made (a cover),
an input event (focus, a frame switch) stayed pending, and `sit-for' then
returned at once, without redisplaying or reading WebKit's events. Input
events are read and dropped: nothing types into a test."
  (redisplay t)
  (read-event nil nil seconds))

(defun +test-wait-for (predicate &optional timeout)
  "Wait until PREDICATE returns non-nil (timers, redisplay and WebKit's events
run meanwhile, see `+test--pump'), TIMEOUT seconds at most (default 10);
return its value, or nil if it never did."
  (let ((end (+ (float-time) (or timeout 10)))
        value)
    (while (and (not (setq value (funcall predicate)))
                (< (float-time) end))
      (+test--pump 0.05))
    value))

(defun +test-sleep (seconds)
  "Let SECONDS pass, timers, redisplay and WebKit's events running."
  (let ((end (+ (float-time) seconds)))
    (while (< (float-time) end)
      (+test--pump (min 0.05 (max 0.001 (- end (float-time))))))))

(defun +test-visible-frames ()
  "How many frames are on screen (a WebKit page's cover is one while it
loads; a window's notices frame stays, invisible, once they're gone)."
  (seq-count #'frame-visible-p (frame-list)))

(defvar +test--js-answer nil)

(defun +test--js-answered (value)
  "WebKit's answer to `+test-js' (a symbol: see config/webkit.el)."
  (setq +test--js-answer (list value)))

(defun +test-js (xwidget script &optional timeout)
  "SCRIPT's value in XWIDGET's page, waited for (no answer left pending: a
view closed while one was crashed Emacs)."
  (setq +test--js-answer nil)
  (xwidget-webkit-execute-script xwidget script #'+test--js-answered)
  (unless (+test-wait-for (lambda () +test--js-answer) (or timeout 5))
    (error "No answer from WebKit to: %s" script))
  (car +test--js-answer))

(defun +test--stderr (text)
  (princ text #'external-debugging-output))

(defun +test-e2e-run ()
  "Run this GUI Emacs's tests once it's up, report them on stderr (ERT's batch
report), and exit with their status."
  (run-at-time
   0.5 nil
   (lambda ()
     ;; On top of other windows while the tests run: macOS takes a window
     ;; covered by others as hidden, and WebKit doesn't draw there (PDF.js
     ;; renders no page). Out of the way all the same: off the screen but for
     ;; its top left corner, at the bottom right of the screen's work area
     ;; (above the Dock), not taking the keyboard. E2E_WINDOW=front: all of
     ;; it on screen, focused (to watch the tests).
     (set-frame-parameter nil 'z-group 'above)
     (set-frame-parameter nil 'fullscreen nil) ; config/window.el maximizes
     (set-frame-size nil 1000 700 t)
     (if (equal (getenv "E2E_WINDOW") "front")
         (progn (set-frame-position nil 60 60)
                (select-frame-set-input-focus (selected-frame)))
       (pcase-let ((`(,x ,y ,width ,height) (frame-monitor-workarea)))
         (set-frame-position nil (+ x width -24) (+ y height -24))))
     (+test-wait-for (lambda () (frame-visible-p (selected-frame))) 5)
     (+test-sleep 0.3)
     (let ((status 1))
       (unwind-protect
           (cl-letf* ((message-fn (symbol-function 'message))
                      ((symbol-function 'message)
                       (lambda (format-string &rest args)
                         (when format-string
                           (+test--stderr (concat (apply #'format-message format-string args) "\n")))
                         (apply message-fn format-string args))))
             (let ((stats (ert-run-tests-batch t)))
               (setq status (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))
         (kill-emacs status))))))

(provide 'test-helper)
;;; helper.el ends here
