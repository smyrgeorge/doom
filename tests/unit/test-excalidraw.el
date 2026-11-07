;;; tests/unit/test-excalidraw.el -*- lexical-binding: t; -*-
;; config/excalidraw.el: drawings in WebKit, drawn by Excalidraw (on
;; config/webkit.el): the mode and its fallbacks, Excalidraw's install (SHA-256
;; checked), the page (its drawing, settings, folder), the drawing's changes
;; into the buffer (versions, exports asked for, the other views told), saving
;; (waiting for the last change), reverts, the pointer and errors from the
;; title, keys (as a browser's KeyboardEvent, before Evil's), copy and paste,
;; the dark canvas, links to drawings (inserting, at point, Option+Enter).
;; Batch Emacs has no GUI: WebKit is faked (`+test-exd--with-fakes');
;; drawings show in it (`+my/webkit-p' t, Excalidraw "installed": fake files)
;; unless a test says otherwise. Nothing is downloaded.

(require 'xwidget)                      ; before faking its functions
(require 'json)
(+test-load "config/childframe" "config/banner" "config/actions" "config/webkit" "config/excalidraw")
(require 'markdown-mode)
(require 'org)

;; ====== FAKE WEBKIT ======

(cl-defstruct (+test-exd--xw (:constructor +test-exd--xw-new) (:copier nil))
  "A fake WebKit view."
  buffer props uri title killed)

(defvar +test-exd--made nil "The fake views made, oldest first.")
(defvar +test-exd--scripts nil "(XWIDGET SCRIPT CALLBACK) run, oldest first.")
(defvar +test-exd--notices nil "(show ID TEXT TYPE BUFFER) or (close ID BUFFER), latest first.")

(defmacro +test-exd--with-fakes (&rest body)
  "BODY with WebKit's functions faked, downloads failing, notices recorded."
  (declare (indent 0))
  `(let ((+test-exd--made nil)
         (+test-exd--scripts nil)
         (+test-exd--notices nil))
     (cl-letf (((symbol-function 'make-xwidget)
                (lambda (_type _title _width _height &optional _arguments buffer _related)
                  (let ((xw (+test-exd--xw-new :buffer buffer)))
                    (setq +test-exd--made (append +test-exd--made (list xw)))
                    xw)))
               ((symbol-function 'xwidget-put)
                (lambda (xw property value)
                  (setf (+test-exd--xw-props xw) (plist-put (+test-exd--xw-props xw) property value))
                  value))
               ((symbol-function 'xwidget-get)
                (lambda (xw property) (plist-get (+test-exd--xw-props xw) property)))
               ((symbol-function 'xwidget-live-p) #'+test-exd--xw-p)
               ((symbol-function 'kill-xwidget) (lambda (xw) (setf (+test-exd--xw-killed xw) t)))
               ((symbol-function 'xwidget-buffer) #'+test-exd--xw-buffer)
               ((symbol-function 'set-xwidget-buffer)
                (lambda (xw buffer) (setf (+test-exd--xw-buffer xw) buffer)))
               ((symbol-function 'set-xwidget-query-on-exit-flag) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-uri)
                (lambda (xw uri) (setf (+test-exd--xw-uri xw) uri)))
               ((symbol-function 'xwidget-webkit-uri) #'+test-exd--xw-uri)
               ((symbol-function 'xwidget-webkit-title) #'+test-exd--xw-title)
               ((symbol-function 'xwidget-webkit-execute-script)
                (lambda (xw script &optional callback)
                  (setq +test-exd--scripts (append +test-exd--scripts (list (list xw script callback))))))
               ((symbol-function 'xwidget-webkit-adjust-size-to-window) #'ignore)
               ((symbol-function 'xwidget-window-inside-pixel-width) (lambda (_window) 700))
               ((symbol-function 'xwidget-window-inside-pixel-height) (lambda (_window) 500))
               ((symbol-function 'xwidget-webkit-stop-loading) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-history) #'ignore)
               ((symbol-function 'xwidget-webkit-callback) #'ignore)
               ((symbol-function '+my/banner-show)
                (lambda (id text &rest args)
                  (push (list 'show id text (plist-get args :type) (current-buffer)) +test-exd--notices)))
               ((symbol-function '+my/banner-close)
                (lambda (&optional id) (push (list 'close id (current-buffer)) +test-exd--notices)))
               ((symbol-function 'url-copy-file)
                (lambda (url &rest _) (signal 'file-error (list "A test can't download" url)))))
       ,@body)))

;; ====== TIMERS ======

(defun +test-exd--timers (function)
  (seq-filter (lambda (timer) (eq (timer--function timer) function))
              (append timer-list timer-idle-list)))

(defun +test-exd--fire (function)
  "Run the pending timers calling FUNCTION now, once; return how many."
  (let ((timers (+test-exd--timers function)))
    (mapc #'cancel-timer timers)
    (dolist (timer timers)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +test-exd--cancel-timers ()
  (dolist (timer (append timer-list timer-idle-list))
    (let ((function (timer--function timer)))
      (when (and (symbolp function)
                 (string-match-p "\\`\\+my/\\(webkit\\|excalidraw\\)" (symbol-name function)))
        (cancel-timer timer)))))

;; ====== FILES ======

(defun +test-exd--new-dir (name)
  "A new folder in the test run's temp folder, its name starting with NAME."
  (file-name-as-directory (make-temp-file (expand-file-name name (+test-tmp-file "dirs/")) t)))

(defun +test-exd--fake-excalidraw ()
  "A folder with Excalidraw's files (fakes): Excalidraw is installed."
  (let ((dir (+test-exd--new-dir "excalidraw")))
    (dolist (file +my/excalidraw-files)
      (let ((path (expand-file-name (car file) dir)))
        (make-directory (file-name-directory path) t)
        (with-temp-file path (insert "/* fake */"))))
    dir))

(defun +test-exd--text (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun +test-exd--file (name &optional content)
  "A file NAME in a folder of its own with CONTENT, by its true name; nil
CONTENT: none (a new file)."
  (let ((file (file-truename (expand-file-name name (+test-exd--new-dir "drawings")))))
    (when content
      (make-directory (file-name-directory file) t)
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file file (insert content))))
    file))

(defconst +test-exd--svg "<svg version=\"1.1\"><!-- payload-start -->eyJ9<!-- payload-end --></svg>\n"
  "A drawing's file text, as far as Emacs knows.")

;; ====== A DRAWING ======

(defmacro +test-exd (&rest body)
  "BODY with WebKit faked and drawings shown in it, Excalidraw installed in a
folder of the test's, temp files in the test's folder, the kill ring the
test's; from one window on *scratch*, and again after."
  (declare (indent 0))
  `(+test-exd--with-fakes
     (let* ((temporary-file-directory (+test-exd--new-dir "tmp"))
            (+my/webkit--watch-timer nil)
            (+my/webkit--tidy-timer nil)
            (+my/excalidraw-dir (+test-exd--fake-excalidraw))
            (+my/excalidraw-theme 'light)
            (+my/excalidraw-library-file
             (expand-file-name "library.excalidrawlib" (+test-exd--new-dir "library")))
            (kill-ring nil)
            (kill-ring-yank-pointer nil)
            (interprogram-cut-function nil)
            (interprogram-paste-function nil))
       (cl-letf (((symbol-function '+my/webkit-p) (lambda () t)))
         (unwind-protect
             (+test-with-reset
               (setq +test-exd--made nil +test-exd--scripts nil +test-exd--notices nil)
               ,@body)
           (+test-exd--cancel-timers))))))

(defun +test-exd--show (buffer &optional window)
  "Show BUFFER in WINDOW (default: the selected one), its view started as
redisplay would; return WINDOW."
  (let ((window (or window (selected-window))))
    (set-window-buffer window buffer)
    (+my/webkit--shown-h window)
    (+test-exd--fire #'+my/webkit--start)
    window))

(defun +test-exd--open (file &optional window)
  "Visit FILE and show it in WINDOW (see `+test-exd--show'); its buffer."
  (let ((buffer (find-file-noselect file)))
    (+test-exd--show buffer window)
    buffer))

(defun +test-exd--xw (buffer &optional window)
  "BUFFER's view for WINDOW (default: the selected one)."
  (with-current-buffer buffer (+my/webkit-xwidget (or window (selected-window)))))

(defun +test-exd--say (xw &rest state)
  "XW's page says STATE (a plist) in its title."
  (setf (+test-exd--xw-title xw) (concat "exd " (json-serialize state))))

(defun +test-exd--answer (xw function value)
  "WebKit answers VALUE from XW's page to FUNCTION (as its event comes in)."
  (let ((last-input-event (list 'xwidget-event 'javascript-callback xw function value)))
    (+my/webkit--callback xw 'javascript-callback)))

(defun +test-exd--asked (xw)
  "The scripts asked of XW with an answer awaited: (SCRIPT CALLBACK)..."
  (mapcar #'cdr (seq-filter (lambda (run) (and (eq (car run) xw) (nth 2 run)))
                            +test-exd--scripts)))

(defun +test-exd--run-in (xw)
  "The scripts run in XW without an answer awaited."
  (mapcar #'cadr (seq-filter (lambda (run) (and (eq (car run) xw) (not (nth 2 run))))
                             +test-exd--scripts)))

(defun +test-exd--base64 (text)
  (base64-encode-string (encode-coding-string text 'utf-8) t))

(defun +test-exd--buffer-text (buffer)
  (with-current-buffer buffer
    (buffer-substring-no-properties (point-min) (point-max))))

;; ====== THE MODE ======

(ert-deftest exd/files-open-as-drawings ()
  (dolist (name '("a.excalidraw.svg" "dir/My Drawing.excalidraw.svg" "a.excalidraw"
                  "A.EXCALIDRAW.SVG" "b.Excalidraw"))
    (should (eq (assoc-default name auto-mode-alist #'string-match-p) '+my/excalidraw-mode-maybe)))
  (dolist (name '("a.svg" "excalidraw.md" "a.excalidraw.svg.bak" "a.excalidraw.png"))
    (should-not (eq (assoc-default name auto-mode-alist #'string-match-p) '+my/excalidraw-mode-maybe))))

(ert-deftest exd/json-p ()
  (dolist (case '(("/a/b.excalidraw" . t) ("/a/b.EXCALIDRAW" . t) ("/a/b.excalidraw.svg" . nil)
                  ("/a/excalidraw/b.svg" . nil)))
    (with-temp-buffer
      (setq buffer-file-name (car case))
      (should (eq (and (+my/excalidraw--json-p) t) (cdr case)))))
  (with-temp-buffer
    (should-not (+my/excalidraw--json-p))))

(ert-deftest exd/mode ()
  (+test-exd
    (let ((buffer (+test-exd--open (+test-exd--file "the mode.excalidraw.svg" +test-exd--svg))))
      (with-current-buffer buffer
        (should (eq major-mode '+my/excalidraw-mode))
        (should (derived-mode-p '+my/webkit-mode))
        (should (equal font-lock-defaults '(nil t)))
        (should (eq revert-buffer-function #'+my/excalidraw--revert))
        (should (eq +my/webkit-url-function #'+my/excalidraw--url))
        (should (eq +my/webkit-watch-function #'+my/excalidraw--watch))
        (should (eq +my/webkit-background #'+my/excalidraw--background))
        (should (memq #'+my/excalidraw--loaded +my/webkit-load-functions))
        (should (eq (current-local-map) +my/excalidraw-mode-map))
        ;; Saved as the page made it: no final newline added, UTF-8, no undo
        ;; (Excalidraw's), read-only.
        (should-not require-final-newline)
        (should (eq (coding-system-base buffer-file-coding-system) 'utf-8))
        (should (eq buffer-undo-list t))
        (should buffer-read-only)
        ;; The file's text, hidden under the view.
        (should (equal (+test-exd--buffer-text buffer) +test-exd--svg))
        (should (equal (get-text-property 1 'display) ""))
        (should-not (buffer-modified-p))
        ;; Before the other hooks of a save.
        (should (memq #'+my/excalidraw--before-save before-save-hook))
        (should-not (memq #'+my/excalidraw--before-save (default-value 'before-save-hook)))
        (should (eq (car before-save-hook) #'+my/excalidraw--before-save))
        (dolist (hook '(change-major-mode-hook kill-buffer-hook))
          (should (memq #'+my/excalidraw--stop (symbol-value hook)))
          (should-not (memq #'+my/excalidraw--stop (default-value hook))))
        (should (eq evil-state 'normal))
        ;; A view, loading the page.
        (should (= (length +test-exd--made) 1))
        (should (string-prefix-p "file://" (+test-exd--xw-uri (car +test-exd--made))))))
    (should (eq (evil-initial-state '+my/excalidraw-mode) 'normal))))

(ert-deftest exd/a-new-file ()
  "A file not there yet: the mode, on a blank buffer (the page shows a blank
drawing)."
  (+test-exd
    (let* ((file (+test-exd--file "new.excalidraw.svg"))
           (buffer (+test-exd--open file)))
      (with-current-buffer buffer
        (should (eq major-mode '+my/excalidraw-mode))
        (should (string-blank-p (+test-exd--buffer-text buffer)))
        (should-not (buffer-modified-p))))))

(defmacro +test-exd--images (&rest body)
  "BODY where images show (`image-mode' faked: batch Emacs can't show them)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'display-images-p) (lambda (&rest _) t))
             ((symbol-function 'image-mode)
              (lambda () (kill-all-local-variables) (setq major-mode 'image-mode))))
     ,@body))

(ert-deftest exd/fallback-without-webkit ()
  "In an Emacs without xwidgets: the SVG as an image, the JSON as JSON;
nothing downloaded. In a terminal (no images): the SVG as XML."
  (+test-exd
    (cl-letf (((symbol-function '+my/webkit-p) #'ignore)
              ((symbol-function '+my/excalidraw-ensure) (lambda () (error "Asked for Excalidraw"))))
      (+test-exd--images
        (with-current-buffer (find-file-noselect (+test-exd--file "a.excalidraw.svg" +test-exd--svg))
          (should (eq major-mode 'image-mode))))
      (with-current-buffer (find-file-noselect (+test-exd--file "t.excalidraw.svg" +test-exd--svg))
        (should (derived-mode-p 'nxml-mode)))
      (with-current-buffer (find-file-noselect (+test-exd--file "b.excalidraw" "{\"type\":\"excalidraw\"}"))
        (should (derived-mode-p 'js-json-mode 'json-mode 'json-ts-mode))
        (should-not (derived-mode-p '+my/webkit-mode))))))

(ert-deftest exd/fallback-without-excalidraw ()
  "Excalidraw not there and the download failing (offline): the file's own
mode, and why."
  (+test-exd
    (let ((+my/excalidraw-dir (+test-exd--new-dir "none")))
      (+test-clear-messages)
      (+test-exd--images
        (with-current-buffer (find-file-noselect (+test-exd--file "c.excalidraw.svg" +test-exd--svg))
          (should (eq major-mode 'image-mode))))
      (should (= (+test-messages "^Drawings open as their files (no Excalidraw): ") 1)))))

;; ====== EXCALIDRAW ======

(ert-deftest exd/files-from-jsdelivr-checked ()
  (should (equal +my/excalidraw-version "0.17.6"))
  (should (equal +my/excalidraw-dir (expand-file-name "excalidraw-0.17.6/" doom-data-dir)))
  (let ((files (+my/excalidraw--files)))
    (should (= (length files) 10))
    (pcase-dolist (`(,file ,url ,sha256) files)
      (should (string-prefix-p "https://cdn.jsdelivr.net/npm/" url))
      (should (string-suffix-p (file-name-nondirectory file) url))
      (should (string-match-p "\\`[0-9a-f]\\{64\\}\\'" sha256))
      (should-not (file-name-absolute-p file)))
    ;; Excalidraw's own of its version; React 18 (its build needs it).
    (dolist (file '("react.production.min.js" "react-dom.production.min.js"
                    "excalidraw.production.min.js" "excalidraw-assets/Virgil.woff2"
                    "excalidraw-assets/Cascadia.woff2"))
      (should (assoc file files)))
    (dolist (entry files)
      (when (string-match-p "excalidraw" (car entry))
        (should (string-match-p "@excalidraw/excalidraw@0\\.17\\.6/dist/" (nth 1 entry)))))
    (should (string-match-p "react@18\\.2\\.0/umd/" (nth 1 (assoc "react.production.min.js" files))))))

(ert-deftest exd/install-and-installed-p ()
  (+test-exd
    (let* ((+my/excalidraw-dir (file-name-as-directory (expand-file-name "new" (+test-exd--new-dir "install"))))
           (bytes (make-hash-table :test #'equal))
           (+my/excalidraw-files
            (mapcar (lambda (file)
                      (let ((content (format "/* %s */" (car file))))
                        (puthash (concat "https://cdn.jsdelivr.net/npm/" (nth 1 file)) content bytes)
                        (list (car file) (nth 1 file) (secure-hash 'sha256 content))))
                    +my/excalidraw-files))
           (downloads nil))
      (should-not (+my/excalidraw-installed-p))
      (cl-letf (((symbol-function 'url-copy-file)
                 (lambda (url newname &rest _)
                   (push url downloads)
                   (with-temp-file newname (insert (gethash url bytes)))
                   t)))
        (+test-clear-messages)
        (should (+my/excalidraw-ensure))
        (should (= (length downloads) 10))
        ;; Installed: not again.
        (should (+my/excalidraw-ensure))
        (should (= (length downloads) 10)))
      (should (+my/excalidraw-installed-p))
      (should (file-exists-p (expand-file-name "excalidraw-assets/Virgil.woff2" +my/excalidraw-dir)))
      (should (= (+test-messages "^Excalidraw 0\\.17\\.6 installed in ") 1))
      (should (commandp #'+my/excalidraw-install)))))

(ert-deftest exd/install-refuses-a-wrong-file ()
  (+test-exd
    (let ((+my/excalidraw-dir (file-name-as-directory (expand-file-name "bad" (+test-exd--new-dir "install")))))
      (cl-letf (((symbol-function 'url-copy-file)
                 (lambda (_url newname &rest _) (with-temp-file newname (insert "evil")) t)))
        (+test-clear-messages)
        (should-not (+my/excalidraw-ensure))
        (should (= (+test-messages "^Drawings open as their files (no Excalidraw): Excalidraw: .* isn.t the file expected") 1)))
      (should-not (+my/excalidraw-installed-p)))))

;; ====== THE PAGE ======

(defun +test-exd--page-options (page)
  "The settings in PAGE's html, parsed."
  (should (string-match "window\\.EXD_OPTIONS = \\({.*}\\);" page))
  (json-parse-string (match-string 1 page) :object-type 'plist :false-object nil))

(ert-deftest exd/page-has-the-drawing-and-what-it-needs ()
  (+test-exd
    (let* ((text "<svg>héllo ✓</svg>")
           (buffer (+test-exd--open (+test-exd--file "page.excalidraw.svg" text))))
      (with-current-buffer buffer
        (let ((page (+my/excalidraw--page))
              (assets (+my/webkit-file-url (file-name-as-directory +my/excalidraw-dir))))
          ;; The drawing: the buffer's text, UTF-8, as base64.
          (should (string-match-p (regexp-quote (format "exd.open(\"%s\", \"\")" (+test-exd--base64 text))) page))
          (should (equal (decode-coding-string (base64-decode-string (+test-exd--base64 text)) 'utf-8) text))
          ;; Excalidraw's files, React first; then the script.
          (should (string-match-p (regexp-quote (format "window.EXCALIDRAW_ASSET_PATH = \"%s\";" assets)) page))
          (let ((react (string-search (concat assets "react.production.min.js") page))
                (dom (string-search (concat assets "react-dom.production.min.js") page))
                (excalidraw (string-search (concat assets "excalidraw.production.min.js") page))
                (script (string-search (+my/webkit-file-url (expand-file-name "config/excalidraw/excalidraw.js" doom-user-dir))
                                       page)))
            (should (and react dom excalidraw script (< react dom excalidraw script))))
          (should (string-match-p "<div id=\"app\"></div>" page))
          (should (string-match-p "height:100%;" page))
          (should (string-match-p "background:#ffffff" page))
          (should (equal (+test-exd--page-options page)
                         '(:kind "svg" :dark nil :exportDelay 300
                           :fonts "https://cdn.jsdelivr.net/npm/@excalidraw/excalidraw@0.17.6"
                           :libraryReturn "https://excalidraw.emacs.invalid/"))))))))

(ert-deftest exd/page-of-a-json-drawing-on-a-dark-canvas ()
  (+test-exd
    (let ((+my/excalidraw-theme 'dark)
          (+my/excalidraw-export-delay 50)
          (buffer (+test-exd--open (+test-exd--file "page.excalidraw" "{}"))))
      (with-current-buffer buffer
        (let ((page (+my/excalidraw--page)))
          (should (string-match-p "background:#121212" page))
          (should (equal (plist-get (+test-exd--page-options page) :kind) "json"))
          (should (eq (plist-get (+test-exd--page-options page) :dark) t))
          (should (eql (plist-get (+test-exd--page-options page) :exportDelay) 50)))))))

(ert-deftest exd/dark-canvas-follows-the-theme ()
  (let ((background-mode 'dark))
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame parameter) (and (eq parameter 'background-mode) background-mode))))
      (let ((+my/excalidraw-theme 'auto))
        (should (+my/excalidraw--dark-p))
        (should (equal (+my/excalidraw--background) "#121212"))
        (setq background-mode 'light)
        (should-not (+my/excalidraw--dark-p))
        (should (equal (+my/excalidraw--background) "#ffffff")))
      (let ((+my/excalidraw-theme 'dark))
        (should (+my/excalidraw--dark-p)))
      (setq background-mode 'dark)
      (let ((+my/excalidraw-theme 'light))
        (should-not (+my/excalidraw--dark-p))))))

(ert-deftest exd/url-the-page-in-a-folder-of-its-own ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "url.excalidraw.svg" "<svg>one</svg>")))
           (dir (buffer-local-value '+my/excalidraw--dir buffer))
           (index (expand-file-name "index.html" dir)))
      (should (file-directory-p dir))
      (should (string-prefix-p (file-name-as-directory temporary-file-directory) dir))
      (should (equal (+test-exd--xw-uri (car +test-exd--made)) (+my/webkit-file-url index)))
      (should (string-search (+test-exd--base64 "<svg>one</svg>") (+test-exd--text index)))
      ;; A new view: written anew, with the drawing as the buffer has it now.
      (with-current-buffer buffer
        (+my/webkit-set-text "<svg>two</svg>")
        (should (equal (+my/excalidraw--url (selected-window)) (+my/webkit-file-url index))))
      (should (equal (buffer-local-value '+my/excalidraw--dir buffer) dir))
      (should (string-search (+test-exd--base64 "<svg>two</svg>") (+test-exd--text index))))))

(ert-deftest exd/closing-deletes-the-page ()
  (+test-exd
    (let* ((a (+test-exd--open (+test-exd--file "a.excalidraw.svg" +test-exd--svg)))
           (b (find-file-noselect (+test-exd--file "b.excalidraw.svg" +test-exd--svg)))
           (dir-a (buffer-local-value '+my/excalidraw--dir a)))
      (+test-exd--show b)
      (let ((dir-b (buffer-local-value '+my/excalidraw--dir b)))
        (kill-buffer a)
        (should-not (file-exists-p dir-a))
        (should (+test-exd--xw-killed (car +test-exd--made)))
        ;; Another mode.
        (with-current-buffer b
          (fundamental-mode)
          (should-not +my/excalidraw--dir))
        (should-not (file-exists-p dir-b))))))

(ert-deftest exd/quitting-emacs-deletes-the-pages ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "quit.excalidraw.svg" +test-exd--svg)))
           (dir (buffer-local-value '+my/excalidraw--dir buffer)))
      (should (memq #'+my/excalidraw--cleanup-h kill-emacs-hook))
      (+my/excalidraw--cleanup-h)
      (should-not (file-exists-p dir)))))

;; ====== CHANGES INTO THE BUFFER ======

(ert-deftest exd/a-change-marks-the-buffer-modified ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "changed.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        ;; Not said yet, or nothing changed: as read.
        (should-not (+my/excalidraw--sync xw))
        (+test-exd--say xw :ready t :version 0 :exported 0)
        (+my/excalidraw--sync xw)
        (should-not (buffer-modified-p))
        (+test-exd--say xw :ready t :version 1 :exported 0)
        (should (equal (plist-get (+my/excalidraw--sync xw) :version) 1))
        (should (buffer-modified-p))
        (should (eql (xwidget-get xw 'seen) 1))
        ;; Seen: not modified again (saved meanwhile, say).
        (set-buffer-modified-p nil)
        (+my/excalidraw--sync xw)
        (should-not (buffer-modified-p))
        (+test-exd--say xw :ready t :version 2 :exported 0)
        (+my/excalidraw--sync xw)
        (should (buffer-modified-p))
        ;; Nothing exported yet: nothing asked.
        (should-not (+test-exd--asked xw))))))

(ert-deftest exd/a-new-export-is-asked-for-once ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "ask.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (+test-exd--say xw :ready t :version 3 :exported 3)
        (+my/excalidraw--sync xw)
        (should (equal (+test-exd--asked xw)
                       '(("window.exd ? exd.answer() : '0\\n'" +my/excalidraw--received))))
        ;; Awaited: not again meanwhile.
        (+my/excalidraw--sync xw)
        (+my/excalidraw--sync xw)
        (should (= (length (+test-exd--asked xw)) 1))
        (+test-exd--answer xw '+my/excalidraw--received "3\n<svg>three</svg>")
        (should (eql (xwidget-get xw 'fetched) 3))
        (should (equal (+test-exd--buffer-text buffer) "<svg>three</svg>"))
        ;; Had: not again.
        (+my/excalidraw--sync xw)
        (should (= (length (+test-exd--asked xw)) 1))
        ;; The next one.
        (+test-exd--say xw :ready t :version 4 :exported 4)
        (+my/excalidraw--sync xw)
        (should (= (length (+test-exd--asked xw)) 2))))))

(ert-deftest exd/an-export-becomes-the-text-and-the-other-views-drawing ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "split.excalidraw.svg" +test-exd--svg)))
           (w1 (selected-window))
           (w2 (+test-exd--show buffer (split-window w1 nil 'right)))
           (x1 (+test-exd--xw buffer w1))
           (x2 (+test-exd--xw buffer w2))
           (index (expand-file-name "index.html" (buffer-local-value '+my/excalidraw--dir buffer)))
           (text "<svg>ünï</svg>\n"))
      (should-not (eq x1 x2))
      (with-current-buffer buffer
        (+my/webkit-ask "window.exd ? exd.answer() : '0\\n'" #'+my/excalidraw--received x2))
      (setq +test-exd--scripts nil)
      (+test-exd--answer x2 '+my/excalidraw--received (concat "2\n" text))
      (with-current-buffer buffer
        (should (equal (+test-exd--buffer-text buffer) text))
        (should (buffer-modified-p))
        ;; Still under the views.
        (should (equal (get-text-property 1 'display) ""))
        (dolist (view +my/webkit--views)
          (should (= (overlay-end view) (point-max)))))
      (should (eql (xwidget-get x2 'fetched) 2))
      ;; The other view shows it; not the one it came from.
      (should (equal (+test-exd--run-in x1)
                     (list (format "window.exd && exd.replace(\"%s\")\n;void 0" (+test-exd--base64 text)))))
      (should-not (+test-exd--run-in x2))
      ;; A view loading the page anew gets it.
      (should (string-search (+test-exd--base64 text) (+test-exd--text index))))))

(ert-deftest exd/old-or-odd-answers-change-nothing ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "old.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (xwidget-put xw 'fetched 5))
      (dolist (answer '("5\n<svg>same version</svg>" "4\n<svg>older</svg>" "garbage" "" nil 42))
        (+test-exd--answer xw '+my/excalidraw--received answer))
      (should (equal (+test-exd--buffer-text buffer) +test-exd--svg))
      (should-not (buffer-modified-p buffer))
      (should-not +test-exd--scripts)
      (should (eql (xwidget-get xw 'fetched) 5)))))

(ert-deftest exd/an-export-with-no-text-or-the-same-only-counts ()
  "A page whose drawing another view replaced has no export of its own (an
empty text): its version is had all the same. The same text: nothing to do."
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "empty.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (+test-exd--answer xw '+my/excalidraw--received "6\n")
      (should (eql (xwidget-get xw 'fetched) 6))
      (+test-exd--answer xw '+my/excalidraw--received (concat "7\n" +test-exd--svg))
      (should (eql (xwidget-get xw 'fetched) 7))
      (should (equal (+test-exd--buffer-text buffer) +test-exd--svg))
      (should-not (buffer-modified-p buffer))
      (should-not +test-exd--scripts))))

(ert-deftest exd/an-answer-for-a-buffer-in-another-mode-is-dropped ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "gone.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (+my/webkit-ask "window.exd ? exd.answer() : '0\\n'" #'+my/excalidraw--received xw)
        (fundamental-mode))
      (+test-exd--answer xw '+my/excalidraw--received "9\n<svg>late</svg>")
      (should (equal (+test-exd--buffer-text buffer) +test-exd--svg)))))

(ert-deftest exd/a-reloaded-page-starts-at-version-0 ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "reload.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (xwidget-put xw 'seen 8)
      (xwidget-put xw 'fetched 8)
      (with-current-buffer buffer
        (let ((last-input-event (list 'xwidget-event 'load-changed xw "load-finished")))
          (+my/webkit--callback xw 'load-changed)))
      (should (eql (xwidget-get xw 'seen) 0))
      (should (eql (xwidget-get xw 'fetched) 0)))))

;; ====== SAVING ======

(defun +test-exd--page-at (xw version exported text)
  "XW's page has its drawing at VERSION, exported at EXPORTED as TEXT: it
answers Emacs's questions (through timers: while a save waits)."
  (+test-exd--say xw :ready t :version version :exported exported)
  (xwidget-put xw '+test-text text))

(defun +test-exd--page-answers ()
  "Each page answers what it was asked (as WebKit would, a moment later)."
  (let ((runs +test-exd--scripts))
    (setq +test-exd--scripts nil)
    (dolist (run runs)
      (pcase-let ((`(,xw ,script ,callback) run))
        (when callback
          (let ((state (+my/excalidraw--state xw)))
          (pcase script
            ("window.exd ? exd.flush() : '0'"
             ;; Exported now.
             (+test-exd--say xw :ready t :version (plist-get state :version)
                             :exported (plist-get state :version))
             (+test-exd--answer xw callback (number-to-string (plist-get state :version))))
            ("window.exd ? exd.answer() : '0\\n'"
             (+test-exd--answer xw callback (format "%d\n%s" (plist-get state :exported)
                                                    (xwidget-get xw '+test-text)))))))))))

(ert-deftest exd/saving-waits-for-the-last-change ()
  "The page changed, not exported yet: saving asks it for its version
(exporting it now) and waits for that export to be the buffer's text."
  (+test-exd
    (let* ((file (+test-exd--file "save.excalidraw.svg" +test-exd--svg))
           (buffer (+test-exd--open file))
           (xw (+test-exd--xw buffer))
           (timer (run-at-time 0.02 0.02 #'+test-exd--page-answers)))
      (unwind-protect
          (with-current-buffer buffer
            (+test-exd--page-at xw 5 4 "<svg>five</svg>")
            (+my/excalidraw--sync xw)
            (should (buffer-modified-p))
            (save-buffer))
        (cancel-timer timer))
      (should (equal (+test-exd--text file) "<svg>five</svg>"))
      (should-not (buffer-modified-p buffer))
      (should (eql (xwidget-get xw 'flushed) 5))
      (should (eql (xwidget-get xw 'fetched) 5)))))

(ert-deftest exd/saving-asks-every-view ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "views.excalidraw.svg" +test-exd--svg)))
           (w2 (+test-exd--show buffer (split-window nil nil 'right)))
           (x1 (+test-exd--xw buffer (frame-first-window)))
           (x2 (+test-exd--xw buffer w2)))
      (with-current-buffer buffer
        (cl-letf (((symbol-function '+my/webkit-wait) (lambda (&rest _) t)))
          (+my/excalidraw--before-save)))
      (dolist (xw (list x1 x2))
        (should (equal (+test-exd--asked xw) '(("window.exd ? exd.flush() : '0'" +my/excalidraw--flushed))))))))

(ert-deftest exd/in-buffer-p ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "in.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        ;; Not answered yet.
        (should-not (+my/excalidraw--in-buffer-p xw))
        (+test-exd--answer xw '+my/excalidraw--flushed "3")
        (should (eql (xwidget-get xw 'flushed) 3))
        (should-not (+my/excalidraw--in-buffer-p xw))
        (xwidget-put xw 'fetched 3)
        (should (+my/excalidraw--in-buffer-p xw))
        ;; A page not ready says 0.
        (+test-exd--answer xw '+my/excalidraw--flushed "0")
        (should (+my/excalidraw--in-buffer-p xw))
        (+test-exd--answer xw '+my/excalidraw--flushed nil)
        (should (eql (xwidget-get xw 'flushed) 0))))))

(ert-deftest exd/saving-gives-up-after-5-seconds ()
  (+test-exd
    (let* ((file (+test-exd--file "slow.excalidraw.svg" +test-exd--svg))
           (buffer (+test-exd--open file))
           (waited nil))
      (with-current-buffer buffer
        (cl-letf (((symbol-function '+my/webkit-wait)
                   (lambda (_predicate seconds) (push seconds waited) nil)))
          (+test-clear-messages)
          (set-buffer-modified-p t)
          (save-buffer)))
      (should (equal waited '(5)))
      (should (= (+test-messages "^The drawing.s last change didn.t come from its page: saved without it$") 1))
      (should (equal (+test-exd--text file) +test-exd--svg)))))

(ert-deftest exd/saving-without-a-view ()
  (+test-exd
    (let* ((file (+test-exd--file "hidden.excalidraw.svg" +test-exd--svg))
           (buffer (find-file-noselect file)))
      (with-current-buffer buffer
        (cl-letf (((symbol-function '+my/webkit-wait) (lambda (&rest _) (error "Waited"))))
          (+my/excalidraw--before-save))))))

(ert-deftest exd/saved-as-the-page-made-it ()
  "No final newline added, UTF-8, the buffer read-only."
  (+test-exd
    (let* ((file (+test-exd--file "exact.excalidraw.svg" +test-exd--svg))
           (buffer (+test-exd--open file)))
      (with-current-buffer buffer
        (cl-letf (((symbol-function '+my/webkit-wait) (lambda (&rest _) t)))
          (+my/webkit-set-text "<svg>ü — no newline</svg>")
          (save-buffer)))
      (should (equal (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally file)
                       (buffer-string))
                     (encode-coding-string "<svg>ü — no newline</svg>" 'utf-8))))))

(ert-deftest exd/a-new-drawing-saved-once-made ()
  "Inserted (see INSERTING): saved once its page has made it."
  (+test-exd
    (let* ((file (+test-exd--file "made.excalidraw.svg"))
           (buffer (+test-exd--open file))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (setq +my/excalidraw--save-new t))
      (+test-exd--answer xw '+my/excalidraw--received "1\n<svg>blank</svg>")
      (should (buffer-modified-p buffer))
      (should-not (buffer-local-value '+my/excalidraw--save-new buffer))
      (cl-letf (((symbol-function '+my/webkit-wait) (lambda (&rest _) t)))
        (should (= (+test-exd--fire #'+my/excalidraw--save) 1)))
      (should (equal (+test-exd--text file) "<svg>blank</svg>"))
      (should-not (buffer-modified-p buffer))
      ;; Once.
      (+test-exd--answer xw '+my/excalidraw--received "2\n<svg>more</svg>")
      (should-not (+test-exd--timers #'+my/excalidraw--save))
      ;; A buffer killed meanwhile: nothing.
      (let ((dead (get-buffer-create "dead")))
        (kill-buffer dead)
        (+my/excalidraw--save dead)))))

;; ====== REVERTS ======

(ert-deftest exd/revert-shows-the-file-anew ()
  (+test-exd
    (let* ((file (+test-exd--file "revert.excalidraw.svg" +test-exd--svg))
           (buffer (+test-exd--open file))
           (w2 (+test-exd--show buffer (split-window nil nil 'right)))
           (x1 (+test-exd--xw buffer (frame-first-window)))
           (x2 (+test-exd--xw buffer w2))
           (new "<svg>changed on disk ✓</svg>"))
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file file (insert new)))
      (setq +test-exd--scripts nil)
      (with-current-buffer buffer
        (revert-buffer t t)
        (should (equal (+test-exd--buffer-text buffer) new))
        (should-not (buffer-modified-p))
        (should (verify-visited-file-modtime buffer))
        (should (equal (get-text-property 1 'display) "")))
      ;; Every view shows it.
      (dolist (xw (list x1 x2))
        (should (equal (+test-exd--run-in xw)
                       (list (format "window.exd && exd.replace(\"%s\")\n;void 0" (+test-exd--base64 new))))))
      (should (string-search (+test-exd--base64 new)
                             (+test-exd--text (expand-file-name "index.html" (buffer-local-value '+my/excalidraw--dir buffer))))))))

(ert-deftest exd/revert-of-a-changed-drawing-asks ()
  (+test-exd
    (let* ((file (+test-exd--file "asks.excalidraw.svg" +test-exd--svg))
           (buffer (+test-exd--open file))
           (asked nil))
      (with-current-buffer buffer
        (+my/webkit-set-text "<svg>mine</svg>")
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (prompt) (push prompt asked) nil)))
          (should-error (revert-buffer t nil) :type 'user-error)
          (should (equal (+test-exd--buffer-text buffer) "<svg>mine</svg>"))
          (should (equal asked '("Discard the drawing's changes, read asks.excalidraw.svg again? "))))
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
          (revert-buffer t nil)
          (should (equal (+test-exd--buffer-text buffer) +test-exd--svg)))
        ;; Not changed: not asked.
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) (error "Asked"))))
          (revert-buffer t nil))))))

(ert-deftest exd/revert-to-an-empty-file ()
  (+test-exd
    (let* ((file (+test-exd--file "emptied.excalidraw.svg" +test-exd--svg))
           (buffer (+test-exd--open file)))
      (with-temp-file file)
      (with-current-buffer buffer
        (revert-buffer t t)
        (should (equal (+test-exd--buffer-text buffer) " "))
        (should-not (buffer-modified-p))))))

;; ====== WATCHING ======

(ert-deftest exd/watch-pointer ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "pointer.excalidraw.svg" +test-exd--svg)))
           (window (selected-window))
           (xw (+test-exd--xw buffer))
           (pointers nil))
      (cl-letf (((symbol-function '+my/webkit-pointer) (lambda (w shape) (push (cons w shape) pointers))))
        (with-current-buffer buffer
          (+my/excalidraw--watch window xw)          ; nothing said: nothing
          (should-not pointers)
          (dolist (cursor '("hand" "text" "arrow" "other"))
            (+test-exd--say xw :ready t :version 0 :exported 0 :cursor cursor)
            (+my/excalidraw--watch window xw))))
      (should (equal (nreverse pointers)
                     (list (cons window 'hand) (cons window 'text) (cons window 'arrow) (cons window 'arrow)))))))

(ert-deftest exd/watch-takes-in-changes ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "watch.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (+test-exd--say xw :ready t :version 2 :exported 2)
      (with-current-buffer buffer
        (+my/excalidraw--watch (selected-window) xw))
      (should (buffer-modified-p buffer))
      (should (= (length (+test-exd--asked xw)) 1)))))

(ert-deftest exd/errors-in-a-notice ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "bad.excalidraw.svg" "<svg>not one</svg>")))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (+test-exd--say xw :ready t :version 0 :exported 0 :error "Not a drawing Excalidraw opens (no scene)")
        (+my/excalidraw--watch (selected-window) xw)
        (+my/excalidraw--watch (selected-window) xw)    ; once
        (should (equal +test-exd--notices
                       (list (list 'show 'excalidraw
                                   "Not a drawing Excalidraw opens (no scene): shown blank, saving replaces the file with what you draw"
                                   'error buffer))))
        (+test-exd--say xw :ready t :version 1 :exported 0 :error "Export: TypeError")
        (+my/excalidraw--watch (selected-window) xw)
        (should (equal (car +test-exd--notices)
                       (list 'show 'excalidraw "The drawing can't be saved: Export: TypeError" 'error buffer)))
        (+test-exd--say xw :ready t :version 1 :exported 1)
        (+my/excalidraw--watch (selected-window) xw)
        (should (equal (car +test-exd--notices) (list 'close 'excalidraw buffer)))
        (should (= (length +test-exd--notices) 3))))))

;; ====== KEYS ======

(defun +test-exd--init (event)
  (when-let* ((json (+my/excalidraw--key-init event)))
    (json-parse-string json :object-type 'plist :false-object nil)))

(defun +test-exd--expect (event key code &rest modifiers)
  (should (equal (+test-exd--init event)
                 (list :key key :code code
                       :shiftKey (and (memq :shift modifiers) t)
                       :metaKey (and (memq :meta modifiers) t)
                       :altKey (and (memq :alt modifiers) t)
                       :ctrlKey (and (memq :ctrl modifiers) t)))))

(ert-deftest exd/keys-as-a-browser-gives-them ()
  ;; Letters, digits.
  (+test-exd--expect ?r "r" "KeyR")
  (+test-exd--expect ?R "R" "KeyR" :shift)
  (+test-exd--expect ?z "z" "KeyZ")
  (+test-exd--expect ?0 "0" "Digit0")
  (+test-exd--expect ?9 "9" "Digit9")
  ;; Shifted: the character, its key's code.
  (+test-exd--expect ?! "!" "Digit1" :shift)
  (+test-exd--expect ?@ "@" "Digit2" :shift)
  (+test-exd--expect ?\) ")" "Digit0" :shift)
  (+test-exd--expect ?_ "_" "Minus" :shift)
  (+test-exd--expect ?+ "+" "Equal" :shift)
  (+test-exd--expect ?{ "{" "BracketLeft" :shift)
  (+test-exd--expect ?} "}" "BracketRight" :shift)
  (+test-exd--expect ?| "|" "Backslash" :shift)
  (+test-exd--expect ?: ":" "Semicolon" :shift)
  (+test-exd--expect ?\" "\"" "Quote" :shift)
  (+test-exd--expect ?< "<" "Comma" :shift)
  (+test-exd--expect ?> ">" "Period" :shift)
  (+test-exd--expect ?? "?" "Slash" :shift)
  (+test-exd--expect ?~ "~" "Backquote" :shift)
  ;; Unshifted punctuation.
  (+test-exd--expect ?- "-" "Minus")
  (+test-exd--expect ?= "=" "Equal")
  (+test-exd--expect ?\[ "[" "BracketLeft")
  (+test-exd--expect ?\] "]" "BracketRight")
  (+test-exd--expect ?\\ "\\" "Backslash")
  (+test-exd--expect ?\; ";" "Semicolon")
  (+test-exd--expect ?' "'" "Quote")
  (+test-exd--expect ?, "," "Comma")
  (+test-exd--expect ?. "." "Period")
  (+test-exd--expect ?/ "/" "Slash")
  (+test-exd--expect ?` "`" "Backquote")
  ;; Another character: no code.
  (+test-exd--expect ?é "é" "")
  ;; Function keys, as characters or symbols.
  (dolist (enter '(13 return))
    (+test-exd--expect enter "Enter" "Enter"))
  (dolist (tab '(9 tab))
    (+test-exd--expect tab "Tab" "Tab"))
  (+test-exd--expect 'backtab "Tab" "Tab" :shift)
  (dolist (escape '(27 escape))
    (+test-exd--expect escape "Escape" "Escape"))
  (dolist (backspace '(127 backspace))
    (+test-exd--expect backspace "Backspace" "Backspace"))
  (dolist (delete '(delete deletechar))
    (+test-exd--expect delete "Delete" "Delete"))
  (+test-exd--expect 'left "ArrowLeft" "ArrowLeft")
  (+test-exd--expect 'right "ArrowRight" "ArrowRight")
  (+test-exd--expect 'up "ArrowUp" "ArrowUp")
  (+test-exd--expect 'down "ArrowDown" "ArrowDown")
  (+test-exd--expect 'S-left "ArrowLeft" "ArrowLeft" :shift)
  ;; Cmd (meta), Option (alt), Control.
  (let ((key (lambda (description) (aref (kbd description) 0))))
    (+test-exd--expect (funcall key "s-z") "z" "KeyZ" :meta)
    (+test-exd--expect (funcall key "s-Z") "Z" "KeyZ" :meta :shift)
    (+test-exd--expect (funcall key "s-=") "=" "Equal" :meta)
    (+test-exd--expect (funcall key "s-<") "<" "Comma" :meta :shift)
    (+test-exd--expect (funcall key "s-M-[") "[" "BracketLeft" :meta :alt)
    (+test-exd--expect (funcall key "M-z") "z" "KeyZ" :alt)
    (+test-exd--expect (funcall key "C-a") "a" "KeyA" :ctrl)
    (+test-exd--expect (funcall key "s-<return>") "Enter" "Enter" :meta)
    (+test-exd--expect (funcall key "s-RET") "Enter" "Enter" :meta)
    (+test-exd--expect (funcall key "s-S-<up>") "ArrowUp" "ArrowUp" :meta :shift))
  ;; Not keys Excalidraw has.
  (dolist (event '(f5 mouse-1 home (mouse-1 nil)))
    (should-not (+test-exd--init event))))

(ert-deftest exd/key-goes-to-the-selected-view ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "key.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (let ((last-command-event ?r))
          (+my/excalidraw-key))
        (let ((last-command-event 'f5))
          (+my/excalidraw-key)))
      (should (equal (+test-exd--run-in xw)
                     (list (concat "window.exd && exd.key(" (+my/excalidraw--key-init ?r) ")\n;void 0"))))
      (should (commandp #'+my/excalidraw-key)))))

(ert-deftest exd/keys-for-the-page ()
  "What Excalidraw's keys type, but SPC (Doom's leader) and : (Evil's command
line); Esc, Enter, Tab, Delete, the arrows; its Cmd and Option keys."
  (let ((map +my/excalidraw-mode-map))
    (dolist (char (number-sequence 33 126))
      (unless (eq char ?:)
        (should (eq (lookup-key map (vector char)) #'+my/excalidraw-key))))
    ;; (special-mode's, which the map's parents have, behind the leader.)
    (should-not (eq (lookup-key map (kbd "SPC")) #'+my/excalidraw-key))
    (should-not (lookup-key map ":"))
    (dolist (key '("<escape>" "RET" "<return>" "TAB" "<tab>" "<backtab>" "DEL" "<backspace>" "<delete>"
                   "<deletechar>" "<left>" "<right>" "<up>" "<down>" "S-<left>" "S-<down>"
                   "s-z" "s-Z" "s-y" "s-a" "s-d" "s-g" "s-G" "s-=" "s-+" "s--" "s-0" "s-'" "s-k" "s-L"
                   "s-<" "s->" "s-[" "s-]" "s-M-[" "s-M-]" "s-S-<up>" "s-M-c" "s-M-v" "s-<return>"
                   "M-z" "M-r"))
      (should (eq (lookup-key map (kbd key)) #'+my/excalidraw-key)))
    ;; Copy and paste through Emacs.
    (should (eq (lookup-key map (kbd "s-c")) #'+my/excalidraw-copy))
    (should (eq (lookup-key map (kbd "s-x")) #'+my/excalidraw-cut))
    (should (eq (lookup-key map (kbd "s-v")) #'+my/excalidraw-paste))
    ;; Emacs's own.
    (dolist (key '("s-s" "s-w" "s-1" "M-x" "C-x" "C-g" "M-RET" "C-c"))
      (should-not (lookup-key map (kbd key))))
    ;; The page's JavaScript gets characters, not UTF-8 bytes.
    (should (multibyte-string-p (+my/excalidraw--key-init ?é)))
    (should (equal (+my/excalidraw--json "é") "\"é\""))
    ;; Clicks are WebKit's.
    (should (eq (lookup-key map [down-mouse-1]) #'+my/webkit-mouse-select))
    (should (eq (lookup-key map [drag-mouse-1]) #'ignore))
    ;; SPC m.
    (pcase-dolist (`(,key . ,command) '(("d" . +my/excalidraw-toggle-dark) ("r" . revert-buffer)))
      (should (eq (lookup-key (evil-get-auxiliary-keymap map 'normal) (kbd (concat "SPC m " key)))
                  command)))))

(ert-deftest exd/keys-before-evils ()
  "In normal state, the drawing's keys come before Evil's and its packages'
(evil-snipe's f, t, s...); Emacs's and Doom's leader still work."
  (+test-exd
    (let ((snipe (require 'evil-snipe nil t))
          (buffer (+test-exd--open (+test-exd--file "evil.excalidraw.svg" +test-exd--svg))))
      (when snipe
        (evil-snipe-mode 1)
        (evil-snipe-override-mode 1))
      (unwind-protect
          (with-current-buffer buffer
            (evil-normal-state)
            (evil-normalize-keymaps)
            (dolist (key '("f" "t" "s" "S" "x" "i" "a" "o" "v" "d" "u" "0" "1" "g" "G" "q" "/" "?"
                           "<escape>" "<left>" "RET" "DEL"))
              (should (eq (key-binding (kbd key)) #'+my/excalidraw-key)))
            (should (eq (key-binding (kbd ":")) #'evil-ex))
            (should (eq (key-binding (kbd "s-c")) #'+my/excalidraw-copy))
            (should-not (eq (key-binding (kbd "M-x")) #'+my/excalidraw-key)))
        (when snipe
          (evil-snipe-mode -1)
          (evil-snipe-override-mode -1))))))

;; ====== COPY AND PASTE ======

(ert-deftest exd/copy-and-cut-ask-the-page ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "copy.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (+my/excalidraw-copy)
        (+my/excalidraw-cut))
      (should (equal (+test-exd--asked xw)
                     '(("window.exd ? exd.copy() : ''" +my/excalidraw--copied)
                       ("window.exd ? exd.cut() : ''" +my/excalidraw--copied))))
      (dolist (command '(+my/excalidraw-copy +my/excalidraw-cut +my/excalidraw-paste))
        (should (commandp command))))))

(ert-deftest exd/copied-into-the-kill-ring ()
  (let* ((kill-ring nil)
        (kill-ring-yank-pointer nil)
        (cut nil)
        (interprogram-cut-function (lambda (text) (push text cut)))
        (interprogram-paste-function nil)
        (clipboard "{\"type\":\"excalidraw/clipboard\",\"elements\":[{\"id\":\"a\"}],\"files\":{}}"))
    (+test-clear-messages)
    (+my/excalidraw--copied clipboard)
    (should (equal kill-ring (list clipboard)))
    (should (equal cut (list clipboard)))
    (should (= (+test-messages "^Copied the selection$") 1))
    (dolist (nothing '("" nil 42))
      (+my/excalidraw--copied nothing))
    (should (= (length kill-ring) 1))
    (should (= (+test-messages "^Nothing selected") 1)))) ; [3 times]

(ert-deftest exd/paste-gives-the-page-the-kill ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "paste.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (with-current-buffer buffer
        (+test-clear-messages)
        (+my/excalidraw-paste)
        (should (= (+test-messages "^Nothing to paste$") 1))
        (kill-new (propertize "a \"quoted\"\nline ✓" 'face 'bold))
        (+my/excalidraw-paste))
      (should (equal (+test-exd--run-in xw)
                     (list "window.exd && exd.paste(\"a \\\"quoted\\\"\\nline ✓\")\n;void 0"))))))

(ert-deftest exd/dark-canvas-toggled-for-all-drawings ()
  (+test-exd
    (let* ((a (+test-exd--open (+test-exd--file "a.excalidraw.svg" +test-exd--svg)))
           (b (+test-exd--open (+test-exd--file "b.excalidraw" "{}") (split-window nil nil 'right)))
           (xa (car +test-exd--made))
           (xb (cadr +test-exd--made))
           (+my/excalidraw-theme 'light))
      (+test-clear-messages)
      (with-current-buffer a
        (+my/excalidraw-toggle-dark))
      (should (eq +my/excalidraw-theme 'dark))
      (dolist (xw (list xa xb))
        (should (equal (+test-exd--run-in xw) '("window.exd && exd.set({dark: true})\n;void 0"))))
      (should (= (+test-messages "^Dark canvas on$") 1))
      (setq +test-exd--scripts nil)
      (with-current-buffer b
        (+my/excalidraw-toggle-dark))
      (should (eq +my/excalidraw-theme 'light))
      (should (equal (+test-exd--run-in xa) '("window.exd && exd.set({dark: false})\n;void 0")))
      (should (= (+test-messages "^Dark canvas off$") 1)))))

;; ====== LIBRARIES ======

(defconst +test-exd--library
  "{\"type\":\"excalidrawlib\",\"version\":2,\"source\":\"test\",\"libraryItems\":[{\"id\":\"box\",\"status\":\"published\",\"elements\":[]}]}"
  "An .excalidrawlib's text, as far as Emacs knows.")

(defconst +test-exd--users-link
  "file:///var/folders/v7/T/excalidraw-B86b1Y/index.html#addLibrary=https%3A%2F%2Flibraries.excalidraw.com%2Flibraries%2Fyouritjang%2Fsoftware-architecture.excalidrawlib&token=uyLOdhnI3kDdaV1riWrNf"
  "Where libraries.excalidraw.com's \"Add to Excalidraw\" sent a library, in the browser.")

(ert-deftest exd/versioned-answers ()
  (should (equal (+my/excalidraw--versioned "3\n{}") '(3 . "{}")))
  (should (equal (+my/excalidraw--versioned "12\n") '(12 . "")))
  (should (equal (+my/excalidraw--versioned "0\na\nb") '(0 . "a\nb")))
  (dolist (odd '("x\n{}" "\n{}" "3" "" nil 42 "-1\n{}"))
    (should-not (+my/excalidraw--versioned odd))))

(ert-deftest exd/library-in-a-link ()
  (should (equal (+my/excalidraw--library-in +test-exd--users-link)
                 "https://libraries.excalidraw.com/libraries/youritjang/software-architecture.excalidrawlib"))
  (should (equal (+my/excalidraw--library-in "https://excalidraw.emacs.invalid/#addLibrary=file%3A%2F%2F%2Ftmp%2Fa.excalidrawlib")
                 "file:///tmp/a.excalidrawlib"))
  (should (equal (+my/excalidraw--library-in "https://x/?addLibrary=https%3A%2F%2Fa%2Fb.excalidrawlib&token=1")
                 "https://a/b.excalidrawlib"))
  (dolist (none '("https://libraries.excalidraw.com/?target=_excalidraw&referrer=x" "a.excalidrawlib" nil))
    (should-not (+my/excalidraw--library-in none))))

(ert-deftest exd/library-p ()
  (should (+my/excalidraw--library-p +test-exd--library))
  (should (+my/excalidraw--library-p "{\"type\":\"excalidrawlib\",\"version\":1,\"library\":[[]]}"))
  (dolist (other '("{\"type\":\"excalidraw\",\"elements\":[]}" "[1,2]" "garbage" ""))
    (should-not (+my/excalidraw--library-p other))))

(defmacro +test-exd--with-web (responses &rest body)
  "BODY with `url-retrieve-synchronously' answering from RESPONSES, ((URL . HTTP-TEXT)...);
the URLs asked for in `fetched'."
  (declare (indent 1))
  `(let ((fetched nil))
     (cl-letf (((symbol-function 'url-retrieve-synchronously)
                (lambda (url &rest _)
                  (push url fetched)
                  (when-let* ((response (cdr (assoc url ,responses))))
                    (let ((buffer (generate-new-buffer " *http*")))
                      (with-current-buffer buffer
                        (set-buffer-multibyte nil)
                        (insert (encode-coding-string response 'utf-8)))
                      buffer)))))
       ,@body)))

(ert-deftest exd/fetch-a-library ()
  (+test-exd--with-web `(("https://ok/a.excalidrawlib" . ,(concat "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"name\":\"ü\"}"))
                         ("https://gone/a.excalidrawlib" . "HTTP/1.1 404 Not Found\r\n\r\nNo"))
    (should (equal (+my/excalidraw--fetch "https://ok/a.excalidrawlib") "{\"name\":\"ü\"}"))
    (should (equal fetched '("https://ok/a.excalidrawlib")))
    (let ((err (should-error (+my/excalidraw--fetch "https://gone/a.excalidrawlib") :type 'user-error)))
      (should (string-match-p "404 Not Found" (cadr err))))
    (should-error (+my/excalidraw--fetch "https://offline/a.excalidrawlib") :type 'user-error))
  ;; A file, by its name or file:// URL.
  (let ((file (expand-file-name "my lib.excalidrawlib" (+test-exd--new-dir "fetch"))))
    (with-temp-file file (insert "{\"library\":[]}"))
    (should (equal (+my/excalidraw--fetch file) "{\"library\":[]}"))
    (should (equal (+my/excalidraw--fetch (+my/webkit-file-url file)) "{\"library\":[]}"))
    (should-error (+my/excalidraw--fetch (concat file ".missing")) :type 'user-error)))

(ert-deftest exd/add-a-library-to-an-open-drawing ()
  "The user's link (libraries.excalidraw.com's, in the browser): its library
downloaded, merged in the drawing's page."
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "lib.excalidraw.svg" +test-exd--svg)))
           (xw (+test-exd--xw buffer)))
      (+test-exd--with-web `(("https://libraries.excalidraw.com/libraries/youritjang/software-architecture.excalidrawlib"
                              . ,(concat "HTTP/1.1 200 OK\r\n\r\n" +test-exd--library)))
        (with-temp-buffer                 ; from anywhere: the drawing on screen
          (+my/excalidraw-add-library (concat "  " +test-exd--users-link "\n"))))
      (should (equal (+test-exd--run-in xw)
                     (list (format "window.exd && exd.addLibrary(\"%s\")\n;void 0"
                                   (+test-exd--base64 +test-exd--library))))))))

(ert-deftest exd/add-a-library-needs-a-drawing-and-a-library ()
  (+test-exd
    (let ((file (expand-file-name "not.excalidrawlib" (+test-exd--new-dir "notlib"))))
      (with-temp-file file (insert "{\"type\":\"excalidraw\"}"))
      (should-error (+my/excalidraw-add-library file) :type 'user-error)   ; no drawing
      (+test-exd--open (+test-exd--file "need.excalidraw.svg" +test-exd--svg))
      (let ((err (should-error (+my/excalidraw-add-library file) :type 'user-error)))
        (should (string-match-p "Not an Excalidraw library" (cadr err))))
      (should-not (+test-exd--run-in (car +test-exd--made))))
    (should (commandp #'+my/excalidraw-add-library))))

(ert-deftest exd/add-a-library-guesses-from-the-kill-ring ()
  (let ((kill-ring nil) (kill-ring-yank-pointer nil) (interprogram-paste-function nil))
    (should-not (+my/excalidraw--library-guess))
    (kill-new "some words")
    (should-not (+my/excalidraw--library-guess))
    (kill-new (concat +test-exd--users-link "\n"))
    (should (equal (+my/excalidraw--library-guess) +test-exd--users-link))
    (kill-new "https://x/y.excalidrawlib")
    (should (equal (+my/excalidraw--library-guess) "https://x/y.excalidrawlib"))))

(ert-deftest exd/a-library-change-is-kept-and-shown-in-every-drawing ()
  "A page's library changed: asked for, kept in the file, given to the other
pages (this drawing's, the others'), not the one it came from."
  (+test-exd
    (let* ((a (+test-exd--open (+test-exd--file "a.excalidraw.svg" +test-exd--svg)))
           (w2 (split-window nil nil 'right))
           (b (+test-exd--open (+test-exd--file "b.excalidraw.svg" +test-exd--svg) w2))
           (xa (+test-exd--xw a (frame-first-window)))
           (xb (+test-exd--xw b w2))
           (xa2 (+test-exd--xw a (+test-exd--show a (split-window w2 nil 'below)))))
      (+test-exd--say xa :ready t :version 0 :exported 0 :library 2)
      (with-current-buffer a (+my/excalidraw--sync xa))
      (should (equal (+test-exd--asked xa)
                     '(("window.exd ? exd.library() : '0\\n'" +my/excalidraw--library-received))))
      (setq +test-exd--scripts nil)
      (+test-exd--answer xa '+my/excalidraw--library-received (concat "2\n" +test-exd--library))
      (should (equal (+test-exd--text +my/excalidraw-library-file) +test-exd--library))
      (should (eql (xwidget-get xa 'library) 2))
      (let ((script (format "window.exd && exd.setLibrary(\"%s\")\n;void 0" (+test-exd--base64 +test-exd--library))))
        (should (equal (+test-exd--run-in xb) (list script)))
        (should (equal (+test-exd--run-in xa2) (list script)))
        (should-not (+test-exd--run-in xa)))
      ;; Had: not asked again; the same library again, or an older one: nothing.
      (setq +test-exd--scripts nil)
      (with-current-buffer a (+my/excalidraw--sync xa))
      (should-not +test-exd--scripts)
      (+test-exd--answer xb '+my/excalidraw--library-received (concat "1\n" +test-exd--library))
      (+test-exd--answer xa '+my/excalidraw--library-received "1\n{\"older\":true}")
      (should-not +test-exd--scripts)
      (should (equal (+test-exd--text +my/excalidraw-library-file) +test-exd--library))
      ;; A page reloaded starts at 0.
      (with-current-buffer a (+my/excalidraw--loaded xa))
      (should (eql (xwidget-get xa 'library) 0)))))

(ert-deftest exd/pages-start-with-the-library ()
  (+test-exd
    (make-directory (file-name-directory +my/excalidraw-library-file) t)
    (with-temp-file +my/excalidraw-library-file (insert +test-exd--library))
    (with-current-buffer (+test-exd--open (+test-exd--file "start.excalidraw.svg" +test-exd--svg))
      (should (string-search (format ", \"%s\");" (+test-exd--base64 +test-exd--library))
                             (+my/excalidraw--page))))))

(ert-deftest exd/libraries-site-in-emacs ()
  "A link out of the page to libraries.excalidraw.com (Browse libraries): the
site in Emacs, in the drawing's window; others: the browser."
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "browse.excalidraw.svg" +test-exd--svg)))
           (+test-browsed nil))
      (with-current-buffer buffer
        (+my/excalidraw--link-out "https://libraries.excalidraw.com/?target=_blank&referrer=x")
        (+my/excalidraw--link-out "https://example.com/elsewhere"))
      (should (equal +test-browsed '("https://example.com/elsewhere")))
      (let ((timer (car (+test-exd--timers #'+my/excalidraw-browse-libraries))))
        (should (equal (timer--args timer)
                       (list "https://libraries.excalidraw.com/?target=_blank&referrer=x" buffer)))))))

(ert-deftest exd/libraries-url ()
  (let ((+my/excalidraw-theme 'dark))
    (should (equal (+my/excalidraw--libraries-url)
                   "https://libraries.excalidraw.com/?target=_excalidraw&referrer=https%3A%2F%2Fexcalidraw.emacs.invalid%2F&useHash=true&token=emacs&theme=dark&version=2"))))

(ert-deftest exd/browse-libraries-watches-the-site ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "site.excalidraw.svg" +test-exd--svg)))
           (window (selected-window))
           (site (+test-exd--xw-new :buffer (get-buffer-create "*site*")))
           (opened nil))
      (cl-letf (((symbol-function 'xwidget-webkit-new-session)
                 (lambda (url) (push url opened) (switch-to-buffer (+test-exd--xw-buffer site))))
                ((symbol-function 'xwidget-webkit-current-session) (lambda () site)))
        (should-error (with-temp-buffer (+my/excalidraw-browse-libraries)) :type 'user-error)
        (with-current-buffer buffer
          (should (eq (+my/excalidraw-browse-libraries) site))))
      (should (equal opened (list (+my/excalidraw--libraries-url))))
      (should (eq (xwidget-get site 'callback) #'+my/excalidraw--libraries-callback))
      (should (eq (xwidget-get site '+my/excalidraw-drawing) buffer))
      (should (eq (xwidget-get site '+my/excalidraw-window) window))
      ;; Its title watched (see LIBRARIES).
      (let ((timer (xwidget-get site '+my/excalidraw-watch)))
        (should (timerp timer))
        (should (eq (timer--function timer) #'+my/excalidraw--libraries-watch))
        (should (equal (timer--args timer) (list site))))
      (should (eq (window-buffer window) (get-buffer "*site*")))
      ;; A notice above it says what to do, and goes back.
      (should (equal (car +test-exd--notices)
                     (list 'show 'excalidraw-libraries
                           "Pick a library: its \"Add to Excalidraw\" adds it to your drawings' library"
                           nil (get-buffer "*site*"))))
      (should (eq (lookup-key (evil-get-auxiliary-keymap +my/excalidraw-mode-map 'normal) (kbd "SPC m l"))
                  #'+my/excalidraw-browse-libraries)))))

(ert-deftest exd/libraries-site-told-to-say-the-link-clicked ()
  "Once the site has loaded (each time): told to say its Add to Excalidraw
link clicked in its title."
  (+test-exd
    (let ((site (+test-exd--xw-new :buffer (get-buffer-create "*site*") :uri "https://libraries.excalidraw.com/")))
      (cl-letf (((symbol-function 'xwidget-webkit-callback) #'ignore))
        (dolist (status '("load-started" "load-committed"))
          (let ((last-input-event (list 'xwidget-event 'load-changed site status)))
            (+my/excalidraw--libraries-callback site 'load-changed)))
        (should-not +test-exd--scripts)
        (dotimes (_ 2)
          (let ((last-input-event (list 'xwidget-event 'load-changed site "load-finished")))
            (+my/excalidraw--libraries-callback site 'load-changed))))
      (should (equal +test-exd--scripts (list (list site +my/excalidraw--libraries-script nil)
                                              (list site +my/excalidraw--libraries-script nil)))))))

(ert-deftest exd/libraries-site-title-watched ()
  "The site's title says a link clicked: the library added after this event,
once, the watch stopped; the site closed: the watch stopped."
  (+test-exd
    (let* ((site (+test-exd--xw-new :buffer (get-buffer-create "*site*") :title "Excalidraw Libraries"))
           (timer (run-with-timer 60 60 #'ignore)))
      (xwidget-put site '+my/excalidraw-watch timer)
      (+my/excalidraw--libraries-watch site)
      (should (memq timer timer-list))
      (should-not (+test-exd--timers #'+my/excalidraw--library-chosen))
      (setf (+test-exd--xw-title site)
            "exd-library https://excalidraw.emacs.invalid/#addLibrary=https%3A%2F%2Flibraries.excalidraw.com%2Flibraries%2Fa%2Fb.excalidrawlib&token=x")
      (+my/excalidraw--libraries-watch site)
      (+my/excalidraw--libraries-watch site)
      (should-not (memq timer timer-list))
      (let ((chosen (+test-exd--timers #'+my/excalidraw--library-chosen)))
        (should (= (length chosen) 1))
        (should (equal (timer--args (car chosen))
                       (list site "https://libraries.excalidraw.com/libraries/a/b.excalidrawlib")))))
    ;; Closed meanwhile.
    (let* ((buffer (get-buffer-create "*closed site*"))
           (site (+test-exd--xw-new :buffer buffer :title "Excalidraw Libraries"))
           (timer (run-with-timer 60 60 #'ignore)))
      (xwidget-put site '+my/excalidraw-watch timer)
      (kill-buffer buffer)
      (+my/excalidraw--libraries-watch site)
      (should-not (memq timer timer-list)))))

(ert-deftest exd/libraries-site-back-to-the-drawing ()
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "back.excalidraw.svg" +test-exd--svg)))
           (window (selected-window))
           (site-buffer (get-buffer-create "*site*"))
           (site (+test-exd--xw-new :buffer site-buffer)))
      (xwidget-put site '+my/excalidraw-drawing buffer)
      (xwidget-put site '+my/excalidraw-window window)
      (set-window-buffer window site-buffer)
      (xwidget-put site '+my/excalidraw-watch (run-with-timer 60 60 #'ignore))
      (cl-letf (((symbol-function 'xwidget-webkit-current-session) (lambda () site)))
        (with-current-buffer site-buffer
          (should (commandp #'+my/excalidraw-libraries-back))
          (+my/excalidraw-libraries-back)))
      (should-not (memq (xwidget-get site '+my/excalidraw-watch) timer-list))
      (should (eq (window-buffer window) buffer))
      (should-not (buffer-live-p site-buffer))
      (should-not (+test-exd--timers #'+my/excalidraw--library-chosen)))))

(ert-deftest exd/libraries-site-add-to-excalidraw ()
  "The site on its way to a library to add: stopped, back to the drawing, the
site closed, the library added (once); its other events as usual."
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "added.excalidraw.svg" +test-exd--svg)))
           (window (selected-window))
           (site-buffer (get-buffer-create "*site*"))
           (site (+test-exd--xw-new :buffer site-buffer :uri "https://libraries.excalidraw.com/"))
           (usual nil) (stopped nil) (added nil))
      (xwidget-put site '+my/excalidraw-drawing buffer)
      (xwidget-put site '+my/excalidraw-window window)
      (set-window-buffer window site-buffer)
      (cl-letf (((symbol-function 'xwidget-webkit-callback) (lambda (xw type) (push (list xw type) usual)))
                ((symbol-function 'xwidget-webkit-stop-loading) (lambda (xw) (push xw stopped)))
                ((symbol-function '+my/excalidraw-add-library)
                 (lambda (source) (push (list source (current-buffer)) added))))
        (+my/excalidraw--libraries-callback site 'load-changed)
        (should (equal usual (list (list site 'load-changed))))
        (setf (+test-exd--xw-uri site)
              "https://excalidraw.emacs.invalid/#addLibrary=https%3A%2F%2Flibraries.excalidraw.com%2Flibraries%2Fa%2Fb.excalidrawlib&token=emacs")
        (+my/excalidraw--libraries-callback site 'load-changed)
        (+my/excalidraw--libraries-callback site 'load-changed)
        (should (= (length usual) 1))
        (should (memq site stopped))
        (should (= (+test-exd--fire #'+my/excalidraw--library-chosen) 1))
        (should (equal added (list (list "https://libraries.excalidraw.com/libraries/a/b.excalidrawlib" buffer)))))
      (should (eq (window-buffer window) buffer))
      (should (eq (selected-window) window))
      (should-not (buffer-live-p site-buffer)))))

;; ====== INSERTING ======

(ert-deftest exd/new-names ()
  (let ((dir (+test-exd--new-dir "names")))
    (should (equal (+my/excalidraw--new-name dir) (expand-file-name "drawing.excalidraw.svg" dir)))
    (with-temp-file (expand-file-name "drawing.excalidraw.svg" dir))
    (should (equal (+my/excalidraw--new-name dir) (expand-file-name "drawing-2.excalidraw.svg" dir)))
    (with-temp-file (expand-file-name "drawing-2.excalidraw.svg" dir))
    (should (equal (+my/excalidraw--new-name dir) (expand-file-name "drawing-3.excalidraw.svg" dir))))
  (dolist (case '(("fig" . "fig.excalidraw.svg") ("fig.excalidraw.svg" . "fig.excalidraw.svg")
                  ("fig.excalidraw" . "fig.excalidraw") ("Fig.EXCALIDRAW.SVG" . "Fig.EXCALIDRAW.SVG")
                  ("fig.svg" . "fig.svg.excalidraw.svg") ("a/b c" . "a/b c.excalidraw.svg")))
    (should (equal (+my/excalidraw--drawing-name (car case)) (cdr case)))))

(ert-deftest exd/links-to-a-drawing ()
  "Relative to the buffer's folder: Markdown's image, Org's link, else the
path."
  (let ((dir (+test-exd--new-dir "links")))
    (with-temp-buffer
      (setq default-directory dir)
      (markdown-mode)
      (should (equal (+my/excalidraw--link (expand-file-name "fig.excalidraw.svg" dir))
                     "![](fig.excalidraw.svg)"))
      (should (equal (+my/excalidraw--link (expand-file-name "img/my fig.excalidraw.svg" dir))
                     "![](img/my%20fig.excalidraw.svg)"))
      (should (equal (+my/excalidraw--link (expand-file-name "../up.excalidraw.svg" dir))
                     "![](../up.excalidraw.svg)"))
      (org-mode)
      (should (equal (+my/excalidraw--link (expand-file-name "img/fig.excalidraw" dir))
                     "[[file:img/fig.excalidraw]]"))
      (fundamental-mode)
      (should (equal (+my/excalidraw--link (expand-file-name "fig.excalidraw.svg" dir))
                     "fig.excalidraw.svg")))
    ;; From a file's buffer: its folder.
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "sub/doc.md" dir))
      (should (equal (+my/excalidraw--link (expand-file-name "fig.excalidraw.svg" dir))
                     "../fig.excalidraw.svg"))
      (setq buffer-file-name nil))))

(ert-deftest exd/drawing-at-point ()
  (let* ((dir (+test-exd--new-dir "at-point"))
         (fig (expand-file-name "img/my fig.excalidraw.svg" dir))
         (json (expand-file-name "b.excalidraw" dir)))
    (make-directory (file-name-directory fig) t)
    (with-temp-file fig)
    (with-temp-file json)
    (with-temp-buffer
      (setq default-directory dir)
      (insert "Text ![](img/my%20fig.excalidraw.svg) more [[file:b.excalidraw]] and ![](missing.excalidraw.svg)\n")
      (dolist (case `(("my%20" . ,fig) ("excalidraw.svg)" . ,fig) ("file:b" . ,json) ("b.excal" . ,json)
                      ("missing" . nil) ("Text" . nil) ("more" . nil)))
        (goto-char (point-min))
        (search-forward (car case))
        (backward-char 2)
        (should (equal (+my/excalidraw--at-point) (cdr case)))))))

(ert-deftest exd/insert-links-and-opens-a-new-drawing ()
  (+test-exd
    (let* ((dir (+test-exd--new-dir "insert"))
           (opened nil))
      (with-current-buffer (find-file-noselect (expand-file-name "notes.org" dir))
        (cl-letf (((symbol-function '+my/excalidraw-open)
                   (lambda (file &optional save-new) (push (list file save-new) opened))))
          (insert "See ")
          (+my/excalidraw-insert "img/fig")
          (should (equal (buffer-string) "See [[file:img/fig.excalidraw.svg]]"))
          (should (equal opened (list (list (expand-file-name "img/fig.excalidraw.svg" dir) t))))
          (should (file-directory-p (expand-file-name "img" dir)))
          ;; One there: linked and opened, not new.
          (with-temp-file (expand-file-name "old.excalidraw" dir))
          (insert "\n")
          (+my/excalidraw-insert (expand-file-name "old.excalidraw" dir))
          (should (equal (car opened) (list (expand-file-name "old.excalidraw" dir) nil)))
          (set-buffer-modified-p nil)))
      ;; Read-only: nothing.
      (with-temp-buffer
        (setq buffer-read-only t)
        (should-error (+my/excalidraw-insert "x") :type 'buffer-read-only))
      (should (commandp #'+my/excalidraw-insert)))))

(ert-deftest exd/open-beside-taking-focus ()
  (+test-exd
    (let* ((from (selected-window))
           (file (+test-exd--file "beside.excalidraw.svg"))
           (buffer (+my/excalidraw-open file t)))
      (should (eq (window-buffer (selected-window)) buffer))
      (should-not (eq (selected-window) from))
      (should (= (length (window-list)) 2))
      (should (eq (window-in-direction 'right from) (selected-window)))
      (should (buffer-local-value '+my/excalidraw--save-new buffer))
      ;; Again: the same window.
      (select-window from)
      (+my/excalidraw-open file)
      (should (= (length (window-list)) 2)))))

(ert-deftest exd/option-enter-actions ()
  (let* ((dir (+test-exd--new-dir "actions"))
         (fig (expand-file-name "fig.excalidraw.svg" dir)))
    (with-temp-file fig)
    (should (eq (car (last +my/context-action-providers)) '+my/context-actions-excalidraw))
    (with-temp-buffer
      (setq default-directory dir)
      (insert "![](fig.excalidraw.svg) words")
      (markdown-mode)
      (progn
        (goto-char 6)
        (should (equal (mapcar #'butlast (+my/context-actions-excalidraw))
                       '(("Drawing" "Edit the drawing") ("Drawing" "Insert a new drawing"))))
        (let ((opened nil))
          (cl-letf (((symbol-function '+my/excalidraw-open) (lambda (file &rest _) (push file opened))))
            (funcall (nth 2 (car (+my/context-actions-excalidraw)))))
          (should (equal opened (list fig))))
        (goto-char (point-max))
        (should (equal (mapcar #'butlast (+my/context-actions-excalidraw))
                       '(("Drawing" "Insert a new drawing"))))
        (setq buffer-read-only t)
        (should-not (+my/context-actions-excalidraw))
        (goto-char 6)
        (should (equal (mapcar #'butlast (+my/context-actions-excalidraw))
                       '(("Drawing" "Edit the drawing")))))
      ;; Elsewhere, not on a link: none.
      (fundamental-mode)
      (goto-char (point-max))
      (should-not (+my/context-actions-excalidraw))
      (goto-char 6)
      (should (equal (mapcar #'butlast (+my/context-actions-excalidraw))
                     '(("Drawing" "Edit the drawing")))))))

(ert-deftest exd/commands ()
  (dolist (command '(+my/excalidraw-insert +my/excalidraw-install +my/excalidraw-toggle-dark
                     +my/excalidraw-copy +my/excalidraw-cut +my/excalidraw-paste +my/excalidraw-key))
    (should (commandp command))))
