;;; tests/unit/test-pdf.el -*- lexical-binding: t; -*-
;; config/pdf.el: PDFs in WebKit, drawn by PDF.js (on config/webkit.el):
;; the mode and its doc-view fallback, no large-file prompt, PDF.js's install
;; (SHA-256 checked), the page (data-N.js, index.html, its settings), places
;; kept across sessions, the state read from the title (mode line, toolbar
;; requests, pointer), commands, search, toggles, Preview and print, Option+Enter,
;; the outline, reverts, quitting Emacs, keys.
;; Batch Emacs has no GUI: WebKit is faked (`+test-pdf--with-fakes'); PDFs
;; show in it (`+my/webkit-p' t) unless a test says otherwise. Nothing is
;; downloaded (`url-copy-file' fails, or copies from a fake CDN), nothing opens
;; outside Emacs (Preview, osascript recorded), temp folders and the places
;; file are the test's own.

(require 'xwidget)                      ; before faking its functions
(require 'json)
(+test-load "config/actions" "config/webkit" "config/pdf")

(defvar +my/sticky-separator)           ; config/sticky.el's, when loaded

;; ====== FAKE WEBKIT ======

(cl-defstruct (+test-pdf--xw (:constructor +test-pdf--xw-new) (:copier nil))
  "A fake WebKit view."
  buffer props uri title killed)

(defvar +test-pdf--made nil "The fake views made, oldest first.")
(defvar +test-pdf--scripts nil "(XWIDGET SCRIPT CALLBACK) run, oldest first.")
(defvar +test-pdf--log nil "(FUNCTION ARGS...) of the other WebKit calls, oldest first.")
(defvar +test-pdf--opened nil "The arguments `call-process' got for \"open\", latest first.")
(defvar +test-pdf--processes nil "The arguments `make-process' got for printing, latest first.")

(defun +test-pdf--log (&rest call)
  (setq +test-pdf--log (append +test-pdf--log (list call))))

(defun +test-pdf--calls (function)
  (mapcar #'cdr (seq-filter (lambda (call) (eq (car call) function)) +test-pdf--log)))

(defmacro +test-pdf--with-fakes (&rest body)
  "BODY with WebKit's functions faked, downloads failing, Preview and
osascript recorded (not run)."
  (declare (indent 0))
  `(let ((+test-pdf--made nil)
         (+test-pdf--scripts nil)
         (+test-pdf--log nil)
         (+test-pdf--opened nil)
         (+test-pdf--processes nil)
         (call-process-fn (symbol-function 'call-process))
         (make-process-fn (symbol-function 'make-process)))
     (cl-letf (((symbol-function 'make-xwidget)
                (lambda (_type _title _width _height &optional _arguments buffer _related)
                  (let ((xw (+test-pdf--xw-new :buffer buffer)))
                    (setq +test-pdf--made (append +test-pdf--made (list xw)))
                    xw)))
               ((symbol-function 'xwidget-put)
                (lambda (xw property value)
                  (setf (+test-pdf--xw-props xw) (plist-put (+test-pdf--xw-props xw) property value))
                  value))
               ((symbol-function 'xwidget-get)
                (lambda (xw property) (plist-get (+test-pdf--xw-props xw) property)))
               ((symbol-function 'xwidget-live-p) #'+test-pdf--xw-p)
               ((symbol-function 'kill-xwidget)
                (lambda (xw) (setf (+test-pdf--xw-killed xw) t) (+test-pdf--log 'kill-xwidget xw)))
               ((symbol-function 'xwidget-buffer) #'+test-pdf--xw-buffer)
               ((symbol-function 'set-xwidget-buffer)
                (lambda (xw buffer) (setf (+test-pdf--xw-buffer xw) buffer)))
               ((symbol-function 'set-xwidget-query-on-exit-flag) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-uri)
                (lambda (xw uri) (setf (+test-pdf--xw-uri xw) uri) (+test-pdf--log 'goto-uri xw uri)))
               ((symbol-function 'xwidget-webkit-uri) #'+test-pdf--xw-uri)
               ((symbol-function 'xwidget-webkit-title) #'+test-pdf--xw-title)
               ((symbol-function 'xwidget-webkit-execute-script)
                (lambda (xw script &optional callback)
                  (setq +test-pdf--scripts (append +test-pdf--scripts (list (list xw script callback))))))
               ((symbol-function 'xwidget-webkit-adjust-size-to-window)
                (lambda (xw &optional window) (+test-pdf--log 'adjust xw window)))
               ((symbol-function 'xwidget-window-inside-pixel-width) (lambda (_window) 700))
               ((symbol-function 'xwidget-window-inside-pixel-height) (lambda (_window) 500))
               ((symbol-function 'xwidget-webkit-stop-loading) #'ignore)
               ((symbol-function 'xwidget-webkit-goto-history) #'ignore)
               ((symbol-function 'xwidget-webkit-callback) #'ignore)
               ;; No download, no Preview, no osascript.
               ((symbol-function 'url-copy-file)
                (lambda (url &rest _) (signal 'file-error (list "A test can't download" url))))
               ((symbol-function 'call-process)
                (lambda (program &rest args)
                  (if (equal program "open")
                      (progn (push args +test-pdf--opened) 0)
                    (apply call-process-fn program args))))
               ((symbol-function 'make-process)
                (lambda (&rest args)
                  (if (equal (plist-get args :name) "pdf-print")
                      (progn (push args +test-pdf--processes) 'fake-process)
                    (apply make-process-fn args)))))
       ,@body)))

;; ====== TIMERS ======

(defun +test-pdf--timers (function)
  (seq-filter (lambda (timer) (eq (timer--function timer) function))
              (append timer-list timer-idle-list)))

(defun +test-pdf--fire (function)
  "Run the pending timers calling FUNCTION now, once; return how many."
  (let ((timers (+test-pdf--timers function)))
    (mapc #'cancel-timer timers)
    (dolist (timer timers)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +test-pdf--cancel-timers ()
  (dolist (timer (append timer-list timer-idle-list))
    (let ((function (timer--function timer)))
      (when (and (symbolp function)
                 (string-match-p "\\`\\+my/\\(webkit\\|pdf\\)" (symbol-name function)))
        (cancel-timer timer)))))

;; ====== FILES ======

(defun +test-pdf--new-dir (name)
  "A new folder in the test run's temp folder, its name starting with NAME."
  (file-name-as-directory (make-temp-file (expand-file-name name (+test-tmp-file "dirs/")) t)))

(defun +test-pdf--write-bytes (file bytes)
  "Write the unibyte string BYTES to FILE (its folder made); return FILE."
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert bytes)))
  file)

(defun +test-pdf--bytes (file)
  "FILE's bytes, a unibyte string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defun +test-pdf--text (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun +test-pdf--sha256 (bytes)
  (secure-hash 'sha256 (encode-coding-string bytes 'no-conversion)))

(defun +test-pdf--fake-pdfjs ()
  "A folder with PDF.js's files (fakes): PDF.js is installed."
  (let ((dir (+test-pdf--new-dir "pdfjs")))
    (dolist (file +my/pdf-js-files)
      (+test-pdf--write-bytes (expand-file-name (file-name-nondirectory (car file)) dir)
                              "/* fake */"))
    dir))

(defun +test-pdf--pdf (name &rest args)
  "A PDF NAME in the temp folder (see `+test-make-pdf' for ARGS), by its true
name (as Emacs visits it: `find-file-visit-truename', as in Doom)."
  (file-truename (apply #'+test-make-pdf (+test-tmp-file (concat "pdfs/" name)) args)))

;; ====== A PDF ======

(defmacro +test-pdf (&rest body)
  "BODY with WebKit faked and PDFs shown in it, PDF.js installed in a folder
of the test's, the places in a file of the test's, the settings at their
defaults, temp files in the test's folder; from one window on *scratch*, and
again after."
  (declare (indent 0))
  `(+test-pdf--with-fakes
     (let* ((temporary-file-directory (+test-pdf--new-dir "tmp"))
            (+my/webkit--watch-timer nil)
            (+my/webkit--tidy-timer nil)
            (+my/pdf-js-dir (+test-pdf--fake-pdfjs))
            (+my/pdf-places-file
             (expand-file-name "pdf-places" (+test-pdf--new-dir "state")))
            (+my/pdf--places 'unread)
            (+my/pdf-toolbar t)
            (+my/pdf-dark-pages nil)
            (+my/pdf-outline-sidebar nil)
            (+my/pdf--search-history nil)
            (+my/pdf--actions-for nil)
            (+my/pdf--outline-for nil)
            (+test-browsed nil)
            (kill-ring nil)
            (kill-ring-yank-pointer nil)
            (interprogram-cut-function nil)
            (interprogram-paste-function nil))
       (cl-letf (((symbol-function '+my/webkit-p) (lambda () t)))
         (unwind-protect
             (+test-with-reset
               (setq +test-pdf--made nil +test-pdf--log nil +test-pdf--scripts nil)
               ,@body)
           (+test-pdf--cancel-timers))))))

(defun +test-pdf--show (buffer &optional window)
  "Show BUFFER in WINDOW (default: the selected one), its view started as
redisplay would; return WINDOW."
  (let ((window (or window (selected-window))))
    (set-window-buffer window buffer)
    (+my/webkit--shown-h window)
    (+test-pdf--fire #'+my/webkit--start)
    window))

(defun +test-pdf--open (file &optional window)
  "Visit FILE and show it in WINDOW (see `+test-pdf--show'); its buffer."
  (let ((buffer (find-file-noselect file)))
    (+test-pdf--show buffer window)
    buffer))

(defun +test-pdf--xw (buffer &optional window)
  "BUFFER's view for WINDOW (default: the selected one)."
  (with-current-buffer buffer (+my/webkit-xwidget (or window (selected-window)))))

(defun +test-pdf--say (xw json)
  "XW's page says JSON in its title."
  (setf (+test-pdf--xw-title xw) (concat "pdfx " json)))

(defun +test-pdf--pdfx (script)
  "What `+my/pdf--js' runs for SCRIPT."
  (concat "window.pdfx && pdfx." script "\n;void 0"))

(defun +test-pdf--scripts-of (function &rest args)
  "The scripts FUNCTION run (with ARGS)."
  (setq +test-pdf--scripts nil)
  (apply function args)
  (mapcar #'cadr +test-pdf--scripts))

(defun +test-pdf--options ()
  "The settings a page of the current buffer would start with, parsed."
  (json-parse-string (+my/pdf--options) :object-type 'plist
                     :false-object nil :null-object nil))

(defun +test-pdf--page-html (buffer)
  (+test-pdf--text (expand-file-name "index.html" (buffer-local-value '+my/pdf--dir buffer))))

(defconst +test-pdf--no-pdf-js
  "No PDF.js here: M-x +my/pdf-js-install, then open the PDF again")

;; ====== SETTINGS ======

(ert-deftest pdf/settings ()
  (should (eq (default-value '+my/pdf-toolbar) t))
  (should-not (default-value '+my/pdf-dark-pages))
  (should-not (default-value '+my/pdf-outline-sidebar))
  (should (= +my/pdf-places-max 300))
  (should (= +my/pdf-scroll-step 60))
  (should (= +my/pdf-zoom-step 1.25))
  (should (equal +my/pdf-js-version "3.11.174"))
  ;; Doom's folders (the test's temp ones here), not the config's.
  (should (equal +my/pdf-places-file (expand-file-name "pdf-places" doom-state-dir)))
  (should (equal +my/pdf-js-dir (expand-file-name "pdfjs-3.11.174/" doom-data-dir))))

(ert-deftest pdf/pdf-js-files ()
  (should (equal (mapcar #'car +my/pdf-js-files)
                 '("build/pdf.min.js" "build/pdf.worker.min.js" "web/pdf_viewer.js" "web/pdf_viewer.css")))
  (dolist (file +my/pdf-js-files)
    (should (string-match-p "\\`[0-9a-f]\\{64\\}\\'" (cdr file)))
    ;; The page loads each one, from PDF.js's folder.
    (should (string-match-p (regexp-quote (concat "%p" (file-name-nondirectory (car file))))
                            +my/pdf--page-template)))
  (should (file-exists-p (expand-file-name "config/pdf.js" +test-root))))

(ert-deftest pdf/pdf-js-checksums-are-pdf-js-3-11-174s ()
  "The SHA-256s listed are those of Doom's copy of PDF.js (when there's one)."
  (let ((dir (+test-pdfjs-dir)))
    (unless dir (ert-skip "No PDF.js in Doom's folder"))
    (pcase-dolist (`(,path . ,sha256) +my/pdf-js-files)
      (should (equal (secure-hash 'sha256 (+test-pdf--bytes
                                             (expand-file-name (file-name-nondirectory path) dir)))
                     sha256)))))

;; ====== OPENING ======

(ert-deftest pdf/pdfs-open-in-the-mode-by-name ()
  (dolist (name '("a.pdf" "B.PDF" "c.Pdf" "/tmp/with space/ü #1.pdf"))
    (should (eq (assoc-default name auto-mode-alist #'string-match) '+my/pdf-mode-maybe)))
  (dolist (name '("a.pdf.txt" "pdf" "a.pdfx"))
    (should-not (eq (assoc-default name auto-mode-alist #'string-match) '+my/pdf-mode-maybe)))
  ;; Ahead of doc-view's (and pdf-tools'): the first that matches.
  (should (eq (cdr (seq-find (lambda (entry) (and (stringp (car entry)) (string-match-p (car entry) "x.pdf")))
                             auto-mode-alist))
              '+my/pdf-mode-maybe))
  (should (eq (cdr (assoc "%PDF" magic-mode-alist)) '+my/pdf-mode-maybe)))

(ert-deftest pdf/pdfs-open-in-webkit ()
  (+test-pdf
    (let ((buffer (find-file-noselect (+test-pdf--pdf "open.pdf"))))
      (with-current-buffer buffer
        (should (eq major-mode '+my/pdf-mode))
        (should (derived-mode-p '+my/webkit-mode))
        ;; The file's bytes stay, unchanged: WebKit is shown over them.
        (should (string-prefix-p "%PDF-1.4" (buffer-substring-no-properties (point-min) (point-max))))
        (should-not (buffer-modified-p))
        (should (eq evil-state 'normal))))))

(ert-deftest pdf/pdfs-open-in-webkit-by-their-content ()
  "magic-mode-alist: a PDF without .pdf in its name (%PDF at its start)."
  (+test-pdf
    (let ((buffer (find-file-noselect (+test-make-pdf (+test-tmp-file "pdfs/no-extension") :pages 1))))
      (should (eq (buffer-local-value 'major-mode buffer) '+my/pdf-mode)))))

(ert-deftest pdf/terminal-falls-back-to-doc-view ()
  (+test-pdf
    (let ((called nil))
      (cl-letf (((symbol-function '+my/webkit-p) #'ignore)
                ((symbol-function 'doc-view-mode-maybe)
                 (lambda () (push (current-buffer) called) (fundamental-mode))))
        (let ((buffer (find-file-noselect (+test-pdf--pdf "terminal.pdf"))))
          (should (equal called (list buffer)))
          (should-not (eq (buffer-local-value 'major-mode buffer) '+my/pdf-mode)))))))

(ert-deftest pdf/p-a-local-file-in-webkit ()
  (+test-pdf
    (with-temp-buffer
      (should-not (+my/pdf-p))                    ; no file
      (setq buffer-file-name "/tmp/x.pdf")
      (should (+my/pdf-p))
      (setq buffer-file-name "/ssh:host:/tmp/x.pdf")
      (should-not (+my/pdf-p))                    ; remote
      (setq buffer-file-name "/tmp/x.pdf")
      (cl-letf (((symbol-function '+my/webkit-p) #'ignore))
        (should-not (+my/pdf-p)))                 ; terminal
      (setq buffer-file-name nil))))

(ert-deftest pdf/no-large-file-prompt-for-pdfs ()
  "Only WebKit reads a PDF: no \"File is large, really open?\"."
  (let ((asked nil)
        (answer 'abort)
        (large-file-warning-threshold 1000))
    (cl-letf (((symbol-function 'files--ask-user-about-large-file)
               (lambda (size op-type filename offer-raw)
                 (push (list size op-type filename offer-raw) asked)
                 answer)))
      (dolist (name '("big.pdf" "BIG.PDF" "with space/big ü.Pdf"))
        (should-not (abort-if-file-too-large 5000 "open" (+test-file (concat "large/" name) "%PDF"))))
      (should-not asked)
      ;; Other files: asked, as usual.
      (let ((text (+test-file "large/big.txt" "text")))
        (should-error (abort-if-file-too-large 5000 "open" text) :type 'user-error)
        (should (equal asked (list (list 5000 "open" text nil))))
        (setq answer 'raw)
        (should (eq (abort-if-file-too-large 5000 "visit" text t) 'raw))
        (should (equal (car asked) (list 5000 "visit" text t)))
        (setq asked nil)
        (should-not (abort-if-file-too-large 10 "open" text))
        (should-not asked))))
  (should (advice-member-p #'+my/pdf-no-large-file-prompt-a #'abort-if-file-too-large)))

;; ====== PDF.JS ======

(defvar +test-pdf--downloads nil "The URLs downloaded from the fake CDN, in order.")

(defmacro +test-pdf--with-cdn (files &rest body)
  "BODY with `url-copy-file' copying from a fake CDN of FILES ((PATH . BYTES)...),
by their path in the npm package; others missing (an error)."
  (declare (indent 1))
  `(let ((cdn (+test-pdf--new-dir "cdn"))
         (+test-pdf--downloads nil))
     (pcase-dolist (`(,path . ,bytes) ,files)
       (+test-pdf--write-bytes (expand-file-name path cdn) bytes))
     (cl-letf (((symbol-function 'url-copy-file)
                (lambda (url newname &optional ok-if-already-exists &rest _)
                  (setq +test-pdf--downloads (append +test-pdf--downloads (list url)))
                  (let ((path (and (string-match "\\`https://cdn\\.jsdelivr\\.net/npm/pdfjs-dist@[^/]+/\\(.+\\)\\'" url)
                                   (match-string 1 url))))
                    (unless (and path (file-exists-p (expand-file-name path cdn)))
                      (signal 'file-error (list "Not found" url)))
                    (copy-file (expand-file-name path cdn) newname ok-if-already-exists)
                    t))))
       ,@body)))

(defconst +test-pdf--binary (apply #'unibyte-string (number-sequence 0 255))
  "Every byte.")

(ert-deftest pdf/pdf-js-install-checks-each-file ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (file-name-as-directory (expand-file-name "new/pdfjs" (+test-pdf--new-dir "install"))))
           (+my/pdf-js-files `(("build/a.min.js" . ,(+test-pdf--sha256 "var a;"))
                               ("web/b.css" . ,(+test-pdf--sha256 +test-pdf--binary)))))
      (should-not (+my/pdf-js-installed-p))
      (+test-clear-messages)
      (+test-pdf--with-cdn `(("build/a.min.js" . "var a;") ("web/b.css" . ,+test-pdf--binary))
        (+my/pdf-js-install)
        (should (equal +test-pdf--downloads
                       '("https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/a.min.js"
                         "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/web/b.css"))))
      ;; Flat, in the folder made for it, no .part left.
      (should (equal (directory-files +my/pdf-js-dir nil "\\`[^.]") '("a.min.js" "b.css")))
      (should (equal (+test-pdf--bytes (expand-file-name "a.min.js" +my/pdf-js-dir)) "var a;"))
      (should (equal (+test-pdf--bytes (expand-file-name "b.css" +my/pdf-js-dir)) +test-pdf--binary))
      (should (+my/pdf-js-installed-p))
      (should (= (+test-messages "^Downloading PDF.js: a.min.js\\.\\.\\.") 1))
      (should (= (+test-messages (concat "^PDF.js 3.11.174 installed in " (regexp-quote +my/pdf-js-dir))) 1))
      ;; Again (M-x +my/pdf-js-install): replaced.
      (+test-pdf--with-cdn `(("build/a.min.js" . "var a;") ("web/b.css" . ,+test-pdf--binary))
        (+my/pdf-js-install)
        (should (= (length +test-pdf--downloads) 2)))
      (should (equal (directory-files +my/pdf-js-dir nil "\\`[^.]") '("a.min.js" "b.css"))))))

(ert-deftest pdf/pdf-js-install-of-its-version ()
  (+test-pdf
    (let ((+my/pdf-js-version "9.9.9")
          (+my/pdf-js-dir (+test-pdf--new-dir "version"))
          (+my/pdf-js-files `(("build/a.js" . ,(+test-pdf--sha256 "a")))))
      (+test-pdf--with-cdn '(("build/a.js" . "a"))
        (+my/pdf-js-install)
        (should (equal +test-pdf--downloads '("https://cdn.jsdelivr.net/npm/pdfjs-dist@9.9.9/build/a.js")))))))

(ert-deftest pdf/pdf-js-install-refuses-a-wrong-file ()
  "A file whose SHA-256 differs: an error, and it isn't installed (nor its
.part left, nor an older copy replaced)."
  (+test-pdf
    (let ((+my/pdf-js-dir (+test-pdf--new-dir "wrong"))
          (+my/pdf-js-files `(("build/a.min.js" . ,(+test-pdf--sha256 "var a;"))
                              ("web/b.css" . ,(+test-pdf--sha256 "body{}")))))
      (+test-pdf--with-cdn '(("build/a.min.js" . "var a;") ("web/b.css" . "body{evil}"))
        (let ((err (should-error (+my/pdf-js-install))))
          (should (string-match-p
                   (concat "\\`PDF.js: " (regexp-quote "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/web/b.css")
                           " isn.t the file expected (SHA-256 differs), not installed\\'")
                   (error-message-string err)))))
      (should (file-exists-p (expand-file-name "a.min.js" +my/pdf-js-dir)))
      (should-not (file-exists-p (expand-file-name "b.css" +my/pdf-js-dir)))
      (should-not (file-exists-p (expand-file-name "b.css.part" +my/pdf-js-dir)))
      (should-not (+my/pdf-js-installed-p))
      ;; An older good copy stays.
      (+test-pdf--write-bytes (expand-file-name "b.css" +my/pdf-js-dir) "body{}")
      (+test-pdf--with-cdn '(("build/a.min.js" . "var a;") ("web/b.css" . "body{evil}"))
        (should-error (+my/pdf-js-install)))
      (should (equal (+test-pdf--bytes (expand-file-name "b.css" +my/pdf-js-dir)) "body{}")))))

(ert-deftest pdf/pdf-js-ensure ()
  (+test-pdf
    ;; There: nothing downloaded (the macro's `url-copy-file' fails).
    (should (+my/pdf-js-installed-p))
    (should (eq (+my/pdf-js-ensure) t))
    (let ((+my/pdf-js-dir (+test-pdf--new-dir "ensure"))
          (+my/pdf-js-files `(("build/a.js" . ,(+test-pdf--sha256 "a")))))
      ;; Offline: WebKit's own viewer, said once.
      (+test-clear-messages)
      (should-not (+my/pdf-js-ensure))
      (should (= (+test-messages "^PDFs in WebKit.s own viewer: ") 1))
      ;; Downloaded now.
      (+test-pdf--with-cdn '(("build/a.js" . "a"))
        (should (eq (+my/pdf-js-ensure) t))
        (should (+my/pdf-js-installed-p)))
      ;; A wrong file: said, not there.
      (delete-file (expand-file-name "a.js" +my/pdf-js-dir))
      (+test-clear-messages)
      (+test-pdf--with-cdn '(("build/a.js" . "b"))
        (should-not (+my/pdf-js-ensure)))
      (should (= (+test-messages "^PDFs in WebKit.s own viewer: PDF.js: .*SHA-256 differs") 1)))))

;; ====== THE PAGE ======

(ert-deftest pdf/data-is-the-pdf-in-base64 ()
  (+test-pdf
    (let ((file (+test-pdf--write-bytes (+test-tmp-file "pdfs/odd name ü #1.pdf")
                                        (concat "%PDF-1.4\n" +test-pdf--binary)))
          (dir (+test-pdf--new-dir "data")))
      (with-temp-buffer
        (setq buffer-file-name file)
        (setq-local +my/pdf--dir dir)
        (should (equal (+my/pdf--write-data) "data-1.js"))
        (let ((js (+test-pdf--bytes (expand-file-name "data-1.js" dir))))
          (should (string-match "\\`window\\.PDFX_DATA=\"\\([A-Za-z0-9+/=]*\\)\";\n\\'" js))
          (should (equal (base64-decode-string (match-string 1 js)) (+test-pdf--bytes file))))
        ;; The next one: the one before deleted (the page has read it).
        (should (equal (+my/pdf--write-data) "data-2.js"))
        (should (= +my/pdf--data 2))
        (should (equal (directory-files dir nil "\\`[^.]") '("data-2.js")))
        (setq buffer-file-name nil)))))

(ert-deftest pdf/colours-as-css ()
  "CSS doesn't know Emacs's colour names: #rrggbb, or the fallback."
  (with-temp-buffer
    (let ((face (make-symbol "test-face")))
      (make-empty-face face)
      (should (equal (+my/pdf--color face :background "#123456") "#123456"))
      (set-face-attribute face nil :background "red" :foreground "#00ff00")
      (should (equal (+my/pdf--color face :background "#123456") "#ff0000"))
      (should (equal (+my/pdf--color face :foreground "#123456") "#00ff00"))
      (set-face-attribute face nil :background "no-such-colour")
      (should (equal (+my/pdf--color face :background "#123456") "#123456")))))

(defmacro +test-pdf--with-theme (colours &rest body)
  "BODY with faces' colours as COLOURS ((FACE ATTRIBUTE . COLOUR)...)."
  (declare (indent 1))
  `(cl-letf* ((face-attribute-fn (symbol-function 'face-attribute))
              ((symbol-function 'face-attribute)
               (lambda (face attribute &optional frame inherit)
                 (let ((colour (assoc (list face attribute) (mapcar (lambda (c) (cons (list (car c) (cadr c)) (cddr c))) ,colours))))
                   (if colour (cdr colour) (funcall face-attribute-fn face attribute frame inherit))))))
     ,@body))

(defconst +test-pdf--theme
  '((default :background . "black") (mode-line :background . "red")
    (default :foreground . "white") (shadow :foreground . "#00ff00")
    (region :background . "#0000ff") (link :foreground . "#ffff00")
    (vertical-border :foreground . "#ff00ff"))
  "Colours the batch display knows exactly.")

(ert-deftest pdf/theme-colours-as-css-variables ()
  (+test-pdf--with-theme +test-pdf--theme
    (should (equal (+my/pdf--css-variables)
                   "--bg:#000000;--bar:#ff0000;--fg:#ffffff;--dim:#00ff00;--hover:#0000ff;--accent:#ffff00;--border:#ff00ff")))
  ;; Without colours (batch's unspecified ones): doom-one's.
  (+test-pdf--with-theme (mapcar (lambda (c) (cons (car c) (cons (cadr c) 'unspecified))) +test-pdf--theme)
    (should (equal (+my/pdf--css-variables)
                   "--bg:#282c34;--bar:#1d2026;--fg:#bbc2cf;--dim:#5b6268;--hover:#3f444a;--accent:#51afef;--border:#191b20"))))

(ert-deftest pdf/page-made-in-a-folder-of-its-own ()
  (+test-pdf
    (let* ((file (+test-pdf--pdf "page.pdf"))
           (buffer (+test-pdf--open file))
           (xw (+test-pdf--xw buffer)))
      (with-current-buffer buffer
        (should-not +my/pdf--native)
        (should (file-directory-p +my/pdf--dir))
        (should (string-prefix-p (expand-file-name "pdf-" temporary-file-directory)
                                 +my/pdf--dir))
        (should (= +my/pdf--data 1))
        (should (equal (directory-files +my/pdf--dir nil "\\`[^.]") '("data-1.js" "index.html")))
        (should (equal +my/pdf--home
                       (+my/webkit-file-url (expand-file-name "index.html" +my/pdf--dir))))
        (should (equal (+test-pdf--xw-uri xw) +my/pdf--home))
        (should (equal (xwidget-get xw 'home) +my/pdf--home))))))

(ert-deftest pdf/page-html ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--fake-pdfjs))
           (buffer (+test-pdf--open (+test-pdf--pdf "html.pdf")))
           (html (+test-pdf--page-html buffer))
           (pdfjs (+my/webkit-file-url (file-name-as-directory +my/pdf-js-dir))))
      (with-current-buffer buffer
        (dolist (part (list "<!doctype html>"
                            "html,body{margin:0;height:100%;overflow:hidden;" ; %% is %
                            (format "background:%s;" (+my/pdf--color 'default :background "#282c34"))
                            "color-scheme:dark}"                             ; batch: dark
                            (format ":root{%s}" (+my/pdf--css-variables))
                            (format "<link rel=\"stylesheet\" href=\"%spdf_viewer.css\">" pdfjs)
                            (format "<script src=\"%spdf.min.js\"></script>" pdfjs)
                            (format "<script src=\"%spdf.worker.min.js\"></script>" pdfjs)
                            (format "<script src=\"%spdf_viewer.js\"></script>" pdfjs)
                            (format "<script>window.PDFX_OPTIONS = %s;</script>" (+my/pdf--options))
                            (format "<script src=\"%s\"></script>"
                                    (+my/webkit-file-url (expand-file-name "config/pdf.js" doom-user-dir)))
                            "if (window.pdfx) pdfx.open(\"data-1.js\");"
                            "b.textContent = 'PDF.js did not load'"))
          (should (string-search part html)))))))

(ert-deftest pdf/page-html-in-a-light-theme ()
  (+test-pdf
    (cl-letf* ((frame-parameter-fn (symbol-function 'frame-parameter))
               ((symbol-function 'frame-parameter)
                (lambda (frame parameter)
                  (if (eq parameter 'background-mode) 'light (funcall frame-parameter-fn frame parameter)))))
      (let ((buffer (+test-pdf--open (+test-pdf--pdf "light.pdf"))))
        (should (string-search "color-scheme:light}" (+test-pdf--page-html buffer)))))))

(ert-deftest pdf/page-background-is-css ()
  "A theme whose background is an Emacs colour name CSS doesn't know (gray12):
the page's background as #rrggbb, as the toolbar's colours."
  (+test-pdf
    (+test-pdf--with-theme '((default :background . "gray12"))
      (let ((html (+test-pdf--page-html (+test-pdf--open (+test-pdf--pdf "gray.pdf")))))
        (should-not (string-search "gray12" html))
        (should (string-match-p "overflow:hidden;background:#[0-9a-f]\\{6\\};color-scheme" html))))))

(ert-deftest pdf/page-from-pdf-js-in-an-odd-folder ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (let ((dir (file-name-as-directory
                                       (expand-file-name "odd dir #1 ü/pdfjs" (+test-pdf--new-dir "odd")))))
                             (dolist (file +my/pdf-js-files)
                               (+test-pdf--write-bytes (expand-file-name (file-name-nondirectory (car file)) dir) ""))
                             dir))
           (html (+test-pdf--page-html (+test-pdf--open (+test-pdf--pdf "odd folder.pdf")))))
      (should (string-search "odd%20dir%20%231%20%C3%BC/pdfjs/pdf.min.js" html)))))

(ert-deftest pdf/without-pdf-js-webkits-own-viewer ()
  "Offline the first time: the PDF in WebKit's own viewer, and PDF.js's keys
say so."
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--new-dir "no-pdfjs"))
           (file (+test-pdf--pdf "native a%20b.pdf"))
           (buffer (+test-pdf--open file))
           (xw (+test-pdf--xw buffer)))
      (with-current-buffer buffer
        (should +my/pdf--native)
        (should-not +my/pdf--dir)
        (should (equal +my/pdf--home (+my/webkit-file-url file)))
        (should (equal (+my/webkit-url-file (+test-pdf--xw-uri xw)) file))
        (+test-clear-messages)
        (should-not (+test-pdf--scripts-of #'+my/pdf-scroll-down))
        (should-not (+test-pdf--scripts-of #'+my/pdf-toggle-dark))
        (should (= (+test-messages (concat "^" (regexp-quote +test-pdf--no-pdf-js) " \\[2 times\\]$")) 1))))))

(ert-deftest pdf/new-view-starts-where-the-pdf-is-looked-at ()
  "Split: the new pane's page starts with the settings and place of the view
latest looked at; the same page, its data not written again."
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "split.pdf")))
           (w1 (selected-window))
           (x1 (+test-pdf--xw buffer w1)))
      (+test-pdf--say x1 "{\"dark\":true,\"toolbar\":false,\"sidebar\":true,\"view\":\"thumbnails\",\"page\":5,\"pages\":9,\"place\":{\"page\":5,\"top\":0.25,\"zoom\":\"page-width\"}}")
      (let* ((w2 (+test-pdf--show buffer (split-window w1 nil 'right)))
             (x2 (+test-pdf--xw buffer w2)))
        (should-not (eq x1 x2))
        (with-current-buffer buffer
          (should (equal (+test-pdf--xw-uri x2) +my/pdf--home))
          (should (= +my/pdf--data 1))
          (should (equal (directory-files +my/pdf--dir nil "\\`[^.]") '("data-1.js" "index.html"))))
        (let ((html (+test-pdf--page-html buffer)))
          (should (string-search "pdfx.open(\"data-1.js\")" html))
          (should (string-search "window.PDFX_OPTIONS = {\"dark\":true,\"toolbar\":false,\"sidebar\":true,\"view\":\"thumbnails\",\"place\":{\"page\":5,\"top\":0.25,\"zoom\":\"page-width\"},\"zoomStep\":1.25};" html)))))))

(ert-deftest pdf/new-view-in-webkits-own-viewer ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--new-dir "no-pdfjs"))
           (buffer (+test-pdf--open (+test-pdf--pdf "native split.pdf")))
           (w2 (+test-pdf--show buffer (split-window nil nil 'right))))
      (should (equal (+test-pdf--xw-uri (+test-pdf--xw buffer w2))
                     (buffer-local-value '+my/pdf--home buffer))))))

;; SETTINGS A PAGE STARTS WITH

(ert-deftest pdf/state-from-the-title ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "state.pdf")))
           (w1 (selected-window))
           (w2 (+test-pdf--show buffer (split-window w1 nil 'right)))
           (x1 (+test-pdf--xw buffer w1))
           (x2 (+test-pdf--xw buffer w2)))
      (with-current-buffer buffer
        (should-not (+my/pdf--state))          ; nothing said yet
        (setf (+test-pdf--xw-title x1) "state.pdf")    ; WebKit's own title
        (should-not (+my/pdf--state))
        (+test-pdf--say x1 "{\"dark\":true,\"page\":2,\"pages\":9,\"cursor\":\"text\",\"action\":null}")
        (+test-pdf--say x2 "{\"dark\":false,\"page\":8}")
        (select-window w1)
        (should (equal (+my/pdf--state) '(:dark t :page 2 :pages 9 :cursor "text" :action nil)))
        (should (equal (+my/pdf--state x2) '(:dark nil :page 8)))
        (select-window w2)
        (set-buffer buffer)
        (should (equal (+my/pdf--state) '(:dark nil :page 8)))))))

(ert-deftest pdf/options-of-the-first-pdf-from-the-variables ()
  (+test-pdf
    (with-current-buffer (find-file-noselect (+test-pdf--pdf "first.pdf"))
      (should (equal (+test-pdf--options)
                     '(:dark nil :toolbar t :sidebar nil :view "outline" :place nil :zoomStep 1.25)))
      (let ((+my/pdf-dark-pages t)
            (+my/pdf-toolbar nil)
            (+my/pdf-outline-sidebar t)
            (+my/pdf-zoom-step 1.5))
        (should (equal (+test-pdf--options)
                       '(:dark t :toolbar nil :sidebar t :view "outline" :place nil :zoomStep 1.5)))))))

(ert-deftest pdf/options-from-the-pdfs-own-view ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "own.pdf"))))
      (+test-pdf--say (+test-pdf--xw buffer)
                      "{\"dark\":true,\"toolbar\":false,\"sidebar\":false,\"view\":\"thumbnails\",\"place\":{\"page\":2}}")
      (let ((+my/pdf-toolbar t))
        (with-current-buffer buffer
          (should (equal (+test-pdf--options)
                         '(:dark t :toolbar nil :sidebar nil :view "thumbnails" :place (:page 2) :zoomStep 1.25))))))))

(ert-deftest pdf/options-from-another-pdf-looked-at ()
  "A PDF opening starts as another one is (its settings, not its place)."
  (+test-pdf
    (let ((other (+test-pdf--open (+test-pdf--pdf "other.pdf"))))
      (+test-pdf--say (+test-pdf--xw other)
                      "{\"dark\":true,\"toolbar\":false,\"sidebar\":true,\"view\":\"thumbnails\",\"place\":{\"page\":7}}")
      (with-current-buffer (find-file-noselect (+test-pdf--pdf "new.pdf"))
        (should (equal (+test-pdf--options)
                       '(:dark t :toolbar nil :sidebar t :view "thumbnails" :place nil :zoomStep 1.25)))))))

(ert-deftest pdf/options-view-defaults-to-the-outline ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "view.pdf"))))
      (+test-pdf--say (+test-pdf--xw buffer) "{\"dark\":false}")
      (with-current-buffer buffer
        (should (equal (plist-get (+test-pdf--options) :view) "outline"))))))

;; ====== PLACES ======

(ert-deftest pdf/places-kept-across-sessions ()
  (+test-pdf
    (with-temp-buffer
      (setq buffer-file-name (+test-tmp-file "pdfs/kept ü #1.pdf"))
      (should-not (+my/pdf--kept-place))           ; no file yet
      (should-not (file-exists-p +my/pdf-places-file))
      (+my/pdf--keep-place '(:page 3 :top 0.5 :zoom "page-width"))
      (should (file-exists-p +my/pdf-places-file))
      (should (equal (+my/pdf--kept-place) '(:page 3 :top 0.5 :zoom "page-width")))
      ;; By the file's (abbreviated) name.
      (should (equal (caar (+my/pdf--read-places)) (abbreviate-file-name buffer-file-name)))
      ;; Emacs started again: read from the file.
      (setq +my/pdf--places 'unread)
      (should (equal (+my/pdf--kept-place) '(:page 3 :top 0.5 :zoom "page-width")))
      (setq buffer-file-name nil)
      (should-not (+my/pdf--kept-place)))))

(ert-deftest pdf/places-read-once ()
  (+test-pdf
    (+test-file "places-once" "((\"/a.pdf\" :page 1))")
    (let ((+my/pdf-places-file (+test-tmp-file "places-once")))
      (should (equal (+my/pdf--read-places) '(("/a.pdf" :page 1))))
      (+test-file "places-once" "((\"/b.pdf\" :page 2))")
      (should (equal (+my/pdf--read-places) '(("/a.pdf" :page 1)))))))

(ert-deftest pdf/places-for-the-latest-closed-only ()
  (+test-pdf
    (let ((+my/pdf-places-max 3))
      (with-temp-buffer
        (dolist (n '(1 2 3 4 5))
          (setq buffer-file-name (format "/tmp/pdf-%d.pdf" n))
          (+my/pdf--keep-place (list :page n)))
        (should (equal (mapcar #'car (+my/pdf--read-places))
                       '("/tmp/pdf-5.pdf" "/tmp/pdf-4.pdf" "/tmp/pdf-3.pdf")))
        ;; Closed again: first, once.
        (setq buffer-file-name "/tmp/pdf-3.pdf")
        (+my/pdf--keep-place '(:page 30))
        (should (equal (+my/pdf--read-places)
                       '(("/tmp/pdf-3.pdf" :page 30) ("/tmp/pdf-5.pdf" :page 5) ("/tmp/pdf-4.pdf" :page 4))))
        ;; No place, no file: nothing.
        (+my/pdf--keep-place nil)
        (setq buffer-file-name nil)
        (+my/pdf--keep-place '(:page 1))
        (should (= (length (+my/pdf--read-places)) 3))
        ;; The file says the same.
        (setq +my/pdf--places 'unread)
        (should (equal (mapcar #'car (+my/pdf--read-places))
                       '("/tmp/pdf-3.pdf" "/tmp/pdf-5.pdf" "/tmp/pdf-4.pdf")))))))

(ert-deftest pdf/places-file-written-whole ()
  "`print-length' and `print-level' don't cut the file short."
  (+test-pdf
    (with-temp-buffer
      (let ((print-length 2)
            (print-level 1))
        (dolist (n '(1 2 3 4))
          (setq buffer-file-name (format "/tmp/whole-%d.pdf" n))
          (+my/pdf--keep-place (list :page n :top 0.5 :zoom "auto"))))
      (setq buffer-file-name nil)
      (setq +my/pdf--places 'unread)
      (should (= (length (+my/pdf--read-places)) 4))
      (should (equal (cdar (+my/pdf--read-places)) '(:page 4 :top 0.5 :zoom "auto"))))))

(ert-deftest pdf/places-file-broken-or-not-writable ()
  (+test-pdf
    (with-temp-buffer
      (setq buffer-file-name "/tmp/broken.pdf")
      ;; Broken: none kept, and it's written anew.
      (+test-pdf--write-bytes +my/pdf-places-file "((\"/x.pdf\" :page")
      (should-not (+my/pdf--read-places))
      (+my/pdf--keep-place '(:page 2))
      (setq +my/pdf--places 'unread)
      (should (equal (+my/pdf--read-places) '(("/tmp/broken.pdf" :page 2))))
      ;; Not writable (its folder can't be made): no error, kept for the session.
      (let ((+my/pdf-places-file
             (expand-file-name "sub/pdf-places" (+test-file "places-not-a-folder" "a file"))))
        (+my/pdf--keep-place '(:page 9))
        (should (equal (+my/pdf--kept-place) '(:page 9))))
      (setq buffer-file-name nil))))

(ert-deftest pdf/places-file-made-with-its-folder ()
  (+test-pdf
    (let ((+my/pdf-places-file (expand-file-name "a/b/pdf-places" (+test-pdf--new-dir "deep"))))
      (with-temp-buffer
        (setq buffer-file-name "/tmp/deep.pdf")
        (+my/pdf--keep-place '(:page 1))
        (setq buffer-file-name nil))
      (should (file-exists-p +my/pdf-places-file)))))

(ert-deftest pdf/remember-the-settings-and-the-place ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "remember.pdf"))))
      (with-current-buffer buffer
        ;; Nothing said yet: nothing kept.
        (+my/pdf--remember)
        (should (eq +my/pdf-toolbar t))
        (should-not (+my/pdf--read-places))
        (+test-pdf--say (+test-pdf--xw buffer)
                        "{\"dark\":true,\"toolbar\":false,\"sidebar\":true,\"place\":{\"page\":4,\"top\":0.1}}")
        (+my/pdf--remember)
        (should (eq +my/pdf-dark-pages t))
        (should-not +my/pdf-toolbar)
        (should (eq +my/pdf-outline-sidebar t))
        (should (equal (+my/pdf--kept-place) '(:page 4 :top 0.1)))))))

(ert-deftest pdf/closing-a-pdf-keeps-its-place-for-next-time ()
  (+test-pdf
    (let* ((file (+test-pdf--pdf "closed.pdf"))
           (buffer (+test-pdf--open file))
           (dir (buffer-local-value '+my/pdf--dir buffer)))
      (+test-pdf--say (+test-pdf--xw buffer) "{\"dark\":false,\"place\":{\"page\":6,\"top\":0.75}}")
      (kill-buffer buffer)
      (should-not (file-exists-p dir))                     ; its page deleted
      (should (seq-every-p #'+test-pdf--xw-killed +test-pdf--made))
      (setq +my/pdf--places 'unread)                ; even after a restart
      (let ((again (+test-pdf--open file)))
        (with-current-buffer again
          (should (equal (plist-get (+test-pdf--options) :place) '(:page 6 :top 0.75)))
          (should (string-search "\"place\":{\"page\":6,\"top\":0.75}" (+test-pdf--page-html again))))))))

(ert-deftest pdf/another-mode-keeps-the-place-and-deletes-the-page ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "mode.pdf")))
           (dir (buffer-local-value '+my/pdf--dir buffer)))
      (+test-pdf--say (+test-pdf--xw buffer) "{\"place\":{\"page\":2}}")
      (with-current-buffer buffer
        (fundamental-mode)
        (should-not (file-exists-p dir))
        (should (equal (+my/pdf--kept-place) '(:page 2)))
        (should-not +my/webkit--views)))))

(ert-deftest pdf/quitting-emacs-keeps-places-and-deletes-pages ()
  (should (memq #'+my/pdf--cleanup-h kill-emacs-hook))
  (+test-pdf
    (let* ((a (+test-pdf--open (+test-pdf--pdf "quit-a.pdf")))
           (b (+test-pdf--open (+test-pdf--pdf "quit-b.pdf") (split-window nil nil 'right)))
           (dirs (list (buffer-local-value '+my/pdf--dir a)
                       (buffer-local-value '+my/pdf--dir b)))
           (keep (symbol-function '+my/pdf--keep-place)))
      (+test-pdf--say (+test-pdf--xw a (get-buffer-window a)) "{\"place\":{\"page\":1}}")
      (+test-pdf--say (+test-pdf--xw b (get-buffer-window b)) "{\"place\":{\"page\":2}}")
      ;; One failing doesn't stop the others.
      (cl-letf (((symbol-function '+my/pdf--keep-place)
                 (lambda (place)
                   (when (eq (current-buffer) a) (error "Disk full"))
                   (funcall keep place))))
        (+my/pdf--cleanup-h))
      (should-not (seq-some #'file-exists-p dirs))
      (with-current-buffer b
        (should (equal (+my/pdf--kept-place) '(:page 2)))))))

;; ====== WATCHING ======

(ert-deftest pdf/page-in-each-windows-mode-line ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "modeline.pdf")))
           (w1 (selected-window))
           (w2 (+test-pdf--show buffer (split-window w1 nil 'right))))
      (+test-pdf--say (+test-pdf--xw buffer w1) "{\"page\":3,\"pages\":12}")
      (+test-pdf--say (+test-pdf--xw buffer w2) "{\"page\":7,\"pages\":12}")
      (+my/webkit--watch)
      (with-selected-window w1
        (should (equal (+my/pdf--page) "  P3/12 ")))
      (with-selected-window w2
        (should (equal (+my/pdf--page) "  P7/12 ")))
      ;; Another buffer in the window: not its page.
      (with-selected-window w1
        (with-current-buffer "*scratch*"
          (should-not (+my/pdf--page))))
      ;; doom-modeline's PDF line shows it.
      (should (equal (buffer-local-value 'doom-modeline--pdf-pages buffer) '(:eval (+my/pdf--page))))
      (should (get 'doom-modeline--pdf-pages 'risky-local-variable)))))

(ert-deftest pdf/mode-line-redrawn-only-when-the-page-changes ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "redraw.pdf")))
          (window (selected-window))
          (redraws 0))
      (cl-letf (((symbol-function 'force-mode-line-update) (lambda (&rest _) (setq redraws (1+ redraws)))))
        (with-current-buffer buffer
          (+my/pdf--show-page window '(:page 3 :pages 12))
          (+my/pdf--show-page window '(:page 3 :pages 12))
          (should (= redraws 1))
          (should (equal (window-parameter window '+my/pdf-page) (cons buffer "  P3/12 ")))
          (+my/pdf--show-page window '(:page 4 :pages 12))
          (should (= redraws 2))
          ;; Not known yet: nothing shown.
          (dolist (state '((:pages 0 :page 1) (:page "x" :pages 3) (:page 1) nil))
            (+my/pdf--show-page window state)
            (should (equal (window-parameter window '+my/pdf-page) (cons buffer nil))))
          (should (= redraws 3)))))))

(ert-deftest pdf/toolbar-requests-answered-once ()
  (+test-pdf
    (let* ((file (+test-pdf--pdf "requests.pdf"))
           (buffer (+test-pdf--open file))
           (xw (+test-pdf--xw buffer)))
      (with-current-buffer buffer
        (+my/pdf--answer xw '(:action (:name "preview" :n 0)))
        (should-not +test-pdf--opened)
        (+my/pdf--answer xw '(:action (:name "preview" :n 1)))
        (+my/pdf--answer xw '(:action (:name "preview" :n 1)))
        (should (= (length +test-pdf--opened) 1))
        (+my/pdf--answer xw '(:action (:name "print" :n 2)))
        (+my/pdf--answer xw '(:action (:name "print" :n 2)))
        (should (= (length +test-pdf--processes) 1))
        (+my/pdf--answer xw '(:action (:name "unknown" :n 3)))
        (+my/pdf--answer xw '(:page 1))             ; no request
        (should (= (length +test-pdf--opened) 1))
        (should (= (length +test-pdf--processes) 1))
        (should (eql (xwidget-get xw 'answered) 0))))))

(ert-deftest pdf/toolbar-requests-through-the-title ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "title requests.pdf")))
           (xw (+test-pdf--xw buffer)))
      (+test-pdf--say xw "{\"page\":1,\"pages\":3,\"action\":{\"name\":\"preview\",\"n\":1}}")
      (with-current-buffer "*scratch*"
        (+my/webkit--watch)
        (+my/webkit--watch))
      (should (equal +test-pdf--opened
                     (list (list nil 0 nil "-a" "Preview" (buffer-file-name buffer))))))))

(ert-deftest pdf/pointer-the-page-wants ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "pointer.pdf")))
           (window (selected-window))
           (xw (+test-pdf--xw buffer))
           (shapes nil))
      (cl-letf (((symbol-function '+my/webkit-pointer)
                 (lambda (w shape) (should (eq w window)) (push shape shapes))))
        (with-current-buffer buffer
          (+my/pdf--watch window xw)                 ; nothing said yet
          (should-not shapes)
          (dolist (cursor '("hand" "text" "arrow" "grab"))
            (+test-pdf--say xw (format "{\"cursor\":%S}" cursor))
            (+my/pdf--watch window xw))
          (+test-pdf--say xw "{\"page\":1}")
          (+my/pdf--watch window xw))
        (should (equal (nreverse shapes) '(hand text arrow arrow arrow)))))))

(ert-deftest pdf/pointer-into-the-text ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "pointer-text.pdf")))
           (window (selected-window)))
      (+test-pdf--say (+test-pdf--xw buffer) "{\"cursor\":\"hand\"}")
      (cl-letf (((symbol-function 'mouse-pixel-position) (lambda () (cons (selected-frame) (cons 1 1))))
                ((symbol-function 'window-at-x-y) (lambda (&rest _) window)))
        (+my/webkit--watch))
      (with-current-buffer buffer
        (should (eq (get-text-property (point-min) 'pointer) 'hand))))))

;; ====== JAVASCRIPT ======

(ert-deftest pdf/js-runs-pdfx-in-the-selected-view ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "js.pdf")))
           (w1 (selected-window))
           (w2 (+test-pdf--show buffer (split-window w1 nil 'right)))
           (x1 (+test-pdf--xw buffer w1))
           (x2 (+test-pdf--xw buffer w2)))
      (select-window w2)
      (should (equal (+test-pdf--scripts-of #'+my/pdf--js "top()") (list (+test-pdf--pdfx "top()"))))
      (should (eq (caar +test-pdf--scripts) x2))
      (+test-pdf--scripts-of #'+my/pdf--js "endFind()" t)
      (should (seq-set-equal-p (mapcar #'car +test-pdf--scripts) (list x1 x2)))
      ;; No view: nothing, quietly.
      (with-current-buffer (find-file-noselect (+test-pdf--pdf "js-hidden.pdf"))
        (+test-clear-messages)
        (should-not (+test-pdf--scripts-of #'+my/pdf--js "top()"))
        (should (= (+test-messages "No PDF.js") 0))))))

;; ====== REVERT ======

(ert-deftest pdf/revert-shows-the-pdf-anew-where-it-was ()
  "Rebuilt by LaTeX, say: the new PDF reloaded in each view (keeping its
place), the page written for views to come."
  (+test-pdf
    (let* ((file (+test-pdf--pdf "revert.pdf" :pages 2))
           (buffer (+test-pdf--open file))
           (w1 (selected-window))
           (w2 (+test-pdf--show buffer (split-window w1 nil 'right))))
      (with-current-buffer buffer
        (should (eq revert-buffer-function #'+my/pdf--revert))
        (setq +my/pdf--searching t)
        (+test-make-pdf file :pages 5)
        (set-file-times file (time-add nil 10))
        (should-not (verify-visited-file-modtime))
        (setq +test-pdf--scripts nil +test-pdf--log nil)
        (revert-buffer t t)
        (should (verify-visited-file-modtime))
        (should-not (buffer-modified-p))
        (should-not +my/pdf--searching)
        (should (equal (directory-files +my/pdf--dir nil "\\`[^.]") '("data-2.js" "index.html")))
        (let ((js (+test-pdf--bytes (expand-file-name "data-2.js" +my/pdf--dir))))
          (string-match "PDFX_DATA=\"\\([^\"]*\\)\"" js)
          (should (equal (base64-decode-string (match-string 1 js)) (+test-pdf--bytes file))))
        (should (string-search "pdfx.open(\"data-2.js\")" (+test-pdf--page-html buffer)))
        (should (seq-set-equal-p (mapcar #'car +test-pdf--scripts)
                                 (list (+test-pdf--xw buffer w1) (+test-pdf--xw buffer w2))))
        (should (seq-every-p (lambda (run) (equal (cadr run) (+test-pdf--pdfx "reload(\"data-2.js\")")))
                             +test-pdf--scripts))
        (should-not (+test-pdf--calls 'goto-uri))))))

(ert-deftest pdf/revert-in-webkits-own-viewer-loads-it-again ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--new-dir "no-pdfjs"))
           (buffer (+test-pdf--open (+test-pdf--pdf "revert native.pdf")))
           (w2 (+test-pdf--show buffer (split-window nil nil 'right)))
           (home (buffer-local-value '+my/pdf--home buffer)))
      (setq +test-pdf--log nil)
      (with-current-buffer buffer (revert-buffer t t))
      (should (seq-set-equal-p (+test-pdf--calls 'goto-uri)
                               (list (list (+test-pdf--xw buffer (get-buffer-window buffer)) home)
                                     (list (+test-pdf--xw buffer w2) home))))
      (should-not +test-pdf--scripts))))

(ert-deftest pdf/revert-before-it-was-shown ()
  (+test-pdf
    (let ((file (+test-pdf--pdf "revert hidden.pdf")))
      (with-current-buffer (find-file-noselect file)
        (set-file-times file (time-add nil 10))
        (revert-buffer t t)
        (should (verify-visited-file-modtime))
        (should-not +my/pdf--dir)
        (should-not +test-pdf--scripts)))))

;; ====== COMMANDS ======

(ert-deftest pdf/scroll-page-zoom-commands ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "commands.pdf"))))
      (with-current-buffer buffer
        (pcase-dolist (`(,script ,command . ,args)
                       '(("scroll(0, 60)" +my/pdf-scroll-down)
                         ("scroll(0, 180)" +my/pdf-scroll-down 3)
                         ("scroll(0, -60)" +my/pdf-scroll-up)
                         ("scroll(0, -120)" +my/pdf-scroll-up 2)
                         ("scroll(60, 0)" +my/pdf-scroll-right)
                         ("scroll(-60, 0)" +my/pdf-scroll-left)
                         ("scroll(-240, 0)" +my/pdf-scroll-left 4)
                         ("screen(0.5)" +my/pdf-half-screen-down)
                         ("screen(-0.5)" +my/pdf-half-screen-up)
                         ("screen(0.9)" +my/pdf-screen-down)
                         ("screen(-0.9)" +my/pdf-screen-up)
                         ("top()" +my/pdf-top)
                         ("goto(5)" +my/pdf-top 5)
                         ("goto(4)" +my/pdf-top (4))
                         ("bottom()" +my/pdf-bottom)
                         ("goto(12)" +my/pdf-bottom 12)
                         ("page(1)" +my/pdf-next-page)
                         ("page(3)" +my/pdf-next-page 3)
                         ("page(-1)" +my/pdf-previous-page)
                         ("page(-2)" +my/pdf-previous-page 2)
                         ("back()" +my/pdf-back)
                         ("forward()" +my/pdf-forward)
                         ("zoom(1.25)" +my/pdf-zoom-in)
                         ("zoom(0.8)" +my/pdf-zoom-out)
                         ("fit('page-actual')" +my/pdf-actual-size)
                         ("fit('page-width')" +my/pdf-fit-width)
                         ("fit('page-fit')" +my/pdf-fit-page)
                         ("again(false)" +my/pdf-search-next)
                         ("again(true)" +my/pdf-search-previous)))
          (should (equal (apply #'+test-pdf--scripts-of command args) (list (+test-pdf--pdfx script))))
          (should (commandp command)))
        (let ((+my/pdf-scroll-step 10)
              (+my/pdf-zoom-step 2))
          (should (equal (+test-pdf--scripts-of #'+my/pdf-scroll-down 2) (list (+test-pdf--pdfx "scroll(0, 20)"))))
          (should (equal (+test-pdf--scripts-of #'+my/pdf-zoom-in) (list (+test-pdf--pdfx "zoom(2)"))))
          (should (equal (+test-pdf--scripts-of #'+my/pdf-zoom-out) (list (+test-pdf--pdfx "zoom(0.5)")))))
        ;; A count (5G, 3j) as Evil gives it.
        (let ((current-prefix-arg 5))
          (should (equal (+test-pdf--scripts-of #'call-interactively #'+my/pdf-bottom)
                         (list (+test-pdf--pdfx "goto(5)"))))
          (should (equal (+test-pdf--scripts-of #'call-interactively #'+my/pdf-scroll-down)
                         (list (+test-pdf--pdfx "scroll(0, 300)")))))))))

;; SEARCH

(ert-deftest pdf/search-normalises-the-query ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "search.pdf"))))
      (with-current-buffer buffer
        ;; Its spaces and line breaks as single spaces (text copied from the PDF).
        (should (equal (+test-pdf--scripts-of #'+my/pdf--find "  two\twords\n across \r\n lines ")
                       (list (+test-pdf--pdfx "find(\"two words across lines\", false)"))))
        (should +my/pdf--searching)
        (should (equal (+test-pdf--scripts-of #'+my/pdf--find "back" t)
                       (list (+test-pdf--pdfx "find(\"back\", true)"))))
        ;; Quoted as JavaScript.
        (let* ((query "say \"hi\" \\ ünï ' </script>")
               (script (car (+test-pdf--scripts-of #'+my/pdf--find query))))
          (should (string-match "pdfx\\.find(\\(.*\\), false)" script))
          (should (equal (json-parse-string (match-string 1 script)) query)))
        ;; Empty: the search ends.
        (dolist (query '("" "  \n "))
          (should (equal (+test-pdf--scripts-of #'+my/pdf--find query)
                         (list (+test-pdf--pdfx "find(\"\", false)"))))
          (should-not +my/pdf--searching))))))

(ert-deftest pdf/search-reads-the-query ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "search-read.pdf")))
          (asked nil))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt &optional initial history &rest _)
                   (push (list prompt initial history) asked)
                   "Theorem 2")))
        (with-current-buffer buffer
          (should (equal (+test-pdf--scripts-of #'call-interactively #'+my/pdf-search)
                         (list (+test-pdf--pdfx "find(\"Theorem 2\", false)"))))
          (should (equal (+test-pdf--scripts-of #'call-interactively #'+my/pdf-search-backward)
                         (list (+test-pdf--pdfx "find(\"Theorem 2\", true)"))))))
      (should (equal (nreverse asked)
                     '(("Search: " nil +my/pdf--search-history)
                       ("Search backward: " nil +my/pdf--search-history)))))))

(ert-deftest pdf/escape-ends-the-search-in-all-views ()
  (should (memq #'+my/pdf--escape-h doom-escape-hook))
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "escape.pdf")))
           (w2 (+test-pdf--show buffer (split-window nil nil 'right))))
      (with-current-buffer buffer
        (+my/pdf--find "word")
        (setq +test-pdf--scripts nil)
        (should (run-hook-with-args-until-success 'doom-escape-hook))
        (should-not +my/pdf--searching)
        (should (= (length +test-pdf--scripts) 2))
        (should (memq (+test-pdf--xw buffer w2) (mapcar #'car +test-pdf--scripts)))
        (should (seq-every-p (lambda (run) (equal (cadr run) (+test-pdf--pdfx "endFind()"))) +test-pdf--scripts))
        ;; Not searching: Esc is someone else's.
        (setq +test-pdf--scripts nil)
        (should-not (+my/pdf--escape-h))
        (should-not +test-pdf--scripts))
      (with-current-buffer "*scratch*"
        (should-not (+my/pdf--escape-h))))))

;; TOGGLES

(ert-deftest pdf/toggles-apply-to-all-views ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "toggles.pdf")))
           (w1 (selected-window))
           (w2 (+test-pdf--show buffer (split-window w1 nil 'right)))
           (x1 (+test-pdf--xw buffer w1))
           (x2 (+test-pdf--xw buffer w2)))
      (+test-pdf--say x1 "{\"dark\":false,\"toolbar\":true,\"sidebar\":false}")
      (+test-pdf--say x2 "{\"dark\":true,\"toolbar\":true,\"sidebar\":false}")
      (select-window w1)
      (+test-clear-messages)
      (pcase-dolist (`(,command ,variable ,script ,message ,value)
                     '((+my/pdf-toggle-dark +my/pdf-dark-pages "set({dark: true})" "Dark pages on" t)
                       (+my/pdf-toggle-toolbar +my/pdf-toolbar "set({toolbar: false})" "Toolbar off" nil)
                       (+my/pdf-toggle-sidebar +my/pdf-outline-sidebar "set({sidebar: true})" "Sidebar on" t)))
        (let ((scripts (+test-pdf--scripts-of #'call-interactively command)))
          (should (equal scripts (list (+test-pdf--pdfx script) (+test-pdf--pdfx script))))
          (should (seq-set-equal-p (mapcar #'car +test-pdf--scripts) (list x1 x2)))
          ;; For the next PDF too.
          (should (eq (symbol-value variable) value))
          (should (= (+test-messages (concat "^" message "$")) 1))))
      ;; As the selected window's view is.
      (select-window w2)
      (should (equal (+test-pdf--scripts-of #'+my/pdf-toggle-dark)
                     (list (+test-pdf--pdfx "set({dark: false})") (+test-pdf--pdfx "set({dark: false})"))))
      (should-not +my/pdf-dark-pages)
      ;; Not said yet: on.
      (+test-pdf--say x2 "")
      (should (equal (car (+test-pdf--scripts-of #'+my/pdf-toggle-sidebar)) (+test-pdf--pdfx "set({sidebar: true})"))))))

(ert-deftest pdf/toggles-without-pdf-js-change-nothing ()
  "No PDF.js (or no view): said, and the settings for the next PDF stay."
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--new-dir "no-pdfjs"))
           (buffer (+test-pdf--open (+test-pdf--pdf "toggle native.pdf")))
           (+my/pdf-dark-pages t)
           (+my/pdf-toolbar t)
           (+my/pdf-outline-sidebar t))
      (with-current-buffer buffer
        (+test-clear-messages)
        (should-not (+test-pdf--scripts-of #'+my/pdf-toggle-dark))
        (should-not (+test-pdf--scripts-of #'+my/pdf-toggle-toolbar))
        (should-not (+test-pdf--scripts-of #'+my/pdf-toggle-sidebar))
        (should (= (+test-messages (regexp-quote +test-pdf--no-pdf-js)) 1)))  ; [3 times]
      (should (eq +my/pdf-dark-pages t))
      (should (eq +my/pdf-toolbar t))
      (should (eq +my/pdf-outline-sidebar t))
      (with-current-buffer (find-file-noselect (+test-pdf--pdf "toggle hidden.pdf"))
        (+my/pdf-toggle-toolbar))
      (should (eq +my/pdf-toolbar t)))))

;; PREVIEW AND PRINT

(ert-deftest pdf/open-in-preview ()
  (+test-pdf
    (let* ((file (+test-pdf--pdf "preview it's ü #1.pdf"))
           (buffer (+test-pdf--open file)))
      (with-current-buffer buffer
        (call-interactively #'+my/pdf-open-in-preview))
      ;; Not waited for (BUFFER 0); the file as one argument.
      (should (equal +test-pdf--opened (list (list nil 0 nil "-a" "Preview" file))))
      (with-temp-buffer
        (should-error (+my/pdf-open-in-preview) :type 'user-error))
      (should (= (length +test-pdf--opened) 1)))))

(ert-deftest pdf/print-through-previews-dialog ()
  (+test-pdf
    (let* ((file (+test-pdf--pdf "print \"me\".pdf"))
           (buffer (+test-pdf--open file)))
      (with-current-buffer buffer
        (call-interactively #'+my/pdf-print))
      (let ((process (car +test-pdf--processes)))
        (should (= (length +test-pdf--processes) 1))
        (should (equal (plist-get process :name) "pdf-print"))
        (should (eq (plist-get process :noquery) t))
        (let ((command (plist-get process :command)))
          (should (equal (car command) "osascript"))
          ;; The file an argument, not in the script (no quoting to get wrong).
          (should (equal (car (last command)) file))
          (should-not (seq-some (lambda (arg) (string-search "print \"me\"" arg)) (butlast command)))
          (should (member "print ((POSIX file (item 1 of argv)) as alias) with print dialog" command))
          (should (member "tell application \"Preview\"" command)))
        ;; It failing is said.
        (let ((sentinel (plist-get process :sentinel))
              (status 'exit) (code 1))
          (cl-letf (((symbol-function 'process-status) (lambda (_) status))
                    ((symbol-function 'process-exit-status) (lambda (_) code)))
            (+test-clear-messages)
            (funcall sentinel 'fake-process "exited abnormally with code 1\n")
            (setq code 0)
            (funcall sentinel 'fake-process "finished\n")
            (setq status 'run code 1)
            (funcall sentinel 'fake-process "run\n")
            (should (= (+test-messages "^Couldn.t print through Preview: SPC m p opens it there, then Cmd\\+P$") 1)))))
      (with-temp-buffer
        (should-error (+my/pdf-print) :type 'user-error))
      (should (= (length +test-pdf--processes) 1)))))

;; ====== OPTION+ENTER ======

(ert-deftest pdf/actions-provider-first ()
  (should (eq (car +my/context-action-providers) #'+my/context-actions-pdf)))

(ert-deftest pdf/actions-ask-the-page-for-its-selection ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "actions.pdf")))
           (xw (+test-pdf--xw buffer))
           (menus nil))
      (cl-letf (((symbol-function '+my/context-actions)
                 (lambda () (push (list (current-buffer) +my/pdf--selection) menus))))
        (with-current-buffer buffer
          (+my/pdf-actions))
        ;; Asked, its answer awaited (to a symbol).
        (should (equal +test-pdf--scripts
                       (list (list xw "window.pdfx ? pdfx.selection() : ''" '+my/pdf--selection-received))))
        (should-not menus)
        (should (eq +my/pdf--actions-for buffer))
        ;; The answer (WebKit's doesn't say whose): the menu after this event.
        (with-current-buffer "*scratch*"
          (+my/pdf--selection-received " some text "))
        (should-not menus)
        (should (= (+test-pdf--fire #'+my/pdf--actions-menu) 1))
        (should (equal menus (list (list buffer " some text "))))
        (should-not (buffer-local-value '+my/pdf--selection buffer))
        ;; Nothing selected.
        (dolist (answer '("" "  \n" nil :null))
          (setq menus nil)
          (+my/pdf--selection-received answer)
          (+test-pdf--fire #'+my/pdf--actions-menu)
          (should (equal menus (list (list buffer nil)))))))))

(ert-deftest pdf/actions-without-pdf-js-at-once ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--new-dir "no-pdfjs"))
           (buffer (+test-pdf--open (+test-pdf--pdf "actions native.pdf")))
           (menus nil))
      (cl-letf (((symbol-function '+my/context-actions)
                 (lambda () (push (list (current-buffer) +my/pdf--selection) menus))))
        (with-current-buffer buffer
          (+my/pdf-actions))
        (should-not +test-pdf--scripts)
        (should (equal menus (list (list buffer nil))))
        ;; No view either.
        (setq menus nil)
        (let ((hidden (find-file-noselect (+test-pdf--pdf "actions hidden.pdf"))))
          (with-current-buffer hidden
            (+my/pdf-actions))
          (should (equal menus (list (list hidden nil)))))))))

(ert-deftest pdf/actions-menu-of-a-closed-pdf ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "actions closed.pdf")))
          (menus nil))
      (cl-letf (((symbol-function '+my/context-actions) (lambda () (push t menus))))
        (with-current-buffer buffer (+my/pdf-actions))
        (+my/pdf--selection-received "text")
        (kill-buffer buffer)
        (+test-pdf--fire #'+my/pdf--actions-menu))
      (should-not menus))))

(ert-deftest pdf/actions-menu-quit-forgets-the-selection ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "actions quit.pdf"))))
      (cl-letf (((symbol-function '+my/context-actions) (lambda () (signal 'quit nil))))
        (should (eq (condition-case nil (+my/pdf--actions-menu buffer "text") (quit 'quit))
                    'quit)))
      (should-not (buffer-local-value '+my/pdf--selection buffer)))))

(ert-deftest pdf/actions-in-the-menu ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "provider.pdf"))))
      (with-temp-buffer
        (should-not (+my/context-actions-pdf)))
      (with-current-buffer buffer
        (should (equal (mapcar #'butlast (+my/context-actions-pdf))
                       '(("PDF" "Open in Preview") ("PDF" "Print..."))))
        (setq-local +my/pdf--selection "some text")
        (should (equal (mapcar #'butlast (+my/context-actions-pdf))
                       '(("PDF" "Copy") ("PDF" "Search the PDF for it") ("PDF" "Search the web for it")
                         ("Claude" "Explain selection with Claude") ("Claude" "Add selection to Claude prompt")
                         ("PDF" "Open in Preview") ("PDF" "Print..."))))
        (should (seq-every-p (lambda (action) (functionp (nth 2 action))) (+my/context-actions-pdf)))
        (setq-local +my/pdf--selection nil)))))

(defun +test-pdf--choose (buffer text label)
  "Pick LABEL in BUFFER's Option+Enter menu, TEXT selected in its page."
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) label)))
    (+my/pdf--actions-menu buffer text)))

(ert-deftest pdf/actions-do-what-they-say ()
  (+test-pdf
    (let* ((root (file-truename (file-name-as-directory (+test-tmp-file "pdfs/project/"))))
           (file (+test-pdf--pdf "project/docs/paper.pdf"))
           (buffer (+test-pdf--open file))
           (text "two words & ü")
           (asked nil)
           (inserted nil)
           (require-fn (symbol-function 'require)))
      (+test-pdf--say (+test-pdf--xw buffer) "{\"page\":3,\"pages\":9}")
      (cl-letf (((symbol-function '+my/claude-ask)
                 (lambda (instruction context-fn)
                   (push (list instruction (funcall context-fn root) (current-buffer)) asked)))
                ((symbol-function 'require)
                 (lambda (feature &rest args)
                   (unless (eq feature 'agent-shell) (apply require-fn feature args))))
                ((symbol-function 'agent-shell-cwd) (lambda () root))
                ((symbol-function 'agent-shell-shell-buffer) (lambda () 'the-shell))
                ((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted))))
        (with-current-buffer "*scratch*"
          (+test-clear-messages)
          (+test-pdf--choose buffer text "Copy")
          (should (equal (car kill-ring) text))
          (should (= (+test-messages "^Copied 13 characters$") 1))
          (+test-pdf--choose buffer text "Search the PDF for it")
          (should (equal (cadr (car (last +test-pdf--scripts)))
                         (+test-pdf--pdfx "find(\"two words & ü\", false)")))
          (should (buffer-local-value '+my/pdf--searching buffer))
          (+test-pdf--choose buffer (concat "  " text "\n") "Search the web for it")
          (should (equal (car +test-browsed) "https://www.google.com/search?q=two%20words%20%26%20%C3%BC"))
          (+test-pdf--choose buffer text "Explain selection with Claude")
          (should (equal asked (list (list "Explain this passage. Don't change any files."
                                           "From docs/paper.pdf, page 3:\n\n> two words & ü"
                                           buffer))))
          (+test-pdf--choose buffer text "Add selection to Claude prompt")
          (should (equal inserted (list (list :text "From docs/paper.pdf, page 3:\n\n> two words & ü"
                                              :shell-buffer 'the-shell))))
          (+test-pdf--choose buffer text "Open in Preview")
          (should (equal +test-pdf--opened (list (list nil 0 nil "-a" "Preview" file))))
          (+test-pdf--choose buffer nil "Print...")
          (should (= (length +test-pdf--processes) 1)))))))

(ert-deftest pdf/claude-context ()
  (+test-pdf
    (let* ((root (file-truename (file-name-as-directory (+test-tmp-file "pdfs/claude/"))))
           (file (+test-pdf--pdf "claude/docs/notes ü.pdf"))
           (buffer (+test-pdf--open file))
           (xw (+test-pdf--xw buffer)))
      (+test-pdf--say xw "{\"page\":12}")
      (with-current-buffer buffer
        (let ((context (+my/pdf--claude-context "  first line\nsecond line \n\n")))
          ;; The page when asked, not later.
          (+test-pdf--say xw "{\"page\":1}")
          (should (equal (funcall context root) "From docs/notes ü.pdf, page 12:\n\n> first line\n> second line"))
          ;; Outside the project, no project: its whole name.
          (should (equal (funcall context (+test-pdf--new-dir "elsewhere"))
                         (format "From %s, page 12:\n\n> first line\n> second line" (abbreviate-file-name file))))
          (should (equal (funcall context nil)
                         (format "From %s, page 12:\n\n> first line\n> second line" (abbreviate-file-name file)))))
        ;; No page said.
        (+test-pdf--say xw "{}")
        (should (equal (funcall (+my/pdf--claude-context "x") root) "From docs/notes ü.pdf:\n\n> x"))
        (+test-pdf--say xw "{\"page\":null}")
        (should (equal (funcall (+my/pdf--claude-context "x\n\ny") root)
                       "From docs/notes ü.pdf:\n\n> x\n> \n> y")))
      (with-temp-buffer
        (rename-buffer "not a file" t)
        (should (equal (funcall (+my/pdf--claude-context "x") root)
                       (format "From %s:\n\n> x" (buffer-name))))))))

;; ====== THE OUTLINE (o) ======

(defconst +test-pdf--outline
  "[{\"t\":[\"Chapter 1\"],\"p\":1},{\"t\":[\"Chapter 1\",\"Section 1.1\"],\"p\":2},{\"t\":[\"Introduction\"],\"p\":3},{\"t\":[\"Introduction\"],\"p\":5},{\"t\":[\"A\",\"B\",\"C ü\"],\"p\":null}]")

(ert-deftest pdf/outline-asks-the-page ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "outline.pdf")))
           (xw (+test-pdf--xw buffer)))
      (with-current-buffer buffer (+my/pdf-outline))
      (should (equal +test-pdf--scripts
                     (list (list xw "window.pdfx ? pdfx.outlineList() : '[]'" '+my/pdf--outline-received))))
      (should (eq +my/pdf--outline-for buffer))
      ;; The answer: the minibuffer after this event, for that PDF.
      (with-current-buffer "*scratch*"
        (+my/pdf--outline-received "[]"))
      (let ((timers (+test-pdf--timers #'+my/pdf--outline-pick)))
        (should (= (length timers) 1))
        (should (equal (timer--args (car timers)) (list buffer "[]")))))))

(ert-deftest pdf/outline-without-pdf-js ()
  (+test-pdf
    (let* ((+my/pdf-js-dir (+test-pdf--new-dir "no-pdfjs"))
           (buffer (+test-pdf--open (+test-pdf--pdf "outline native.pdf"))))
      (+test-clear-messages)
      (with-current-buffer buffer (+my/pdf-outline))
      (with-current-buffer (find-file-noselect (+test-pdf--pdf "outline hidden.pdf"))
        (+my/pdf-outline))
      (should-not +test-pdf--scripts)
      (should (= (+test-messages "^No outline here (no PDF\\.js)") 1)))))

(ert-deftest pdf/outline-picked-in-the-minibuffer ()
  (+test-pdf
    (let* ((buffer (+test-pdf--open (+test-pdf--pdf "outline pick.pdf")))
           (got nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt collection &optional predicate require-match &rest _)
                   (setq got (list prompt collection predicate require-match))
                   "Introduction (2)")))
        (with-current-buffer "*scratch*"
          (should (equal (+test-pdf--scripts-of #'+my/pdf--outline-pick buffer +test-pdf--outline)
                         (list (+test-pdf--pdfx "outlineGo(3)"))))))
      (should (eq (caar +test-pdf--scripts) (+test-pdf--xw buffer)))
      (pcase-let ((`(,prompt ,collection ,_ ,require-match) got))
        (should (equal prompt "Outline: "))
        (should require-match)
        ;; In their order, parents before, same names told apart.
        (let ((names (all-completions "" collection)))
          (should (equal names '("Chapter 1" "Chapter 1 › Section 1.1" "Introduction" "Introduction (2)" "A › B › C ü")))
          (should (eq (get-text-property 0 'face (nth 1 names)) 'shadow))
          (should-not (get-text-property (length "Chapter 1 › ") 'face (nth 1 names)))
          (should (eq (get-text-property (length "Introduction") 'face (nth 3 names)) 'shadow))
          (should-not (get-text-property 0 'face (nth 0 names))))
        (let* ((metadata (cdr (funcall collection "" nil 'metadata)))
               (annotate (alist-get 'annotation-function metadata)))
          (should (eq (alist-get 'display-sort-function metadata) #'identity))
          (should (eq (alist-get 'cycle-sort-function metadata) #'identity))
          (should (equal (funcall annotate "Chapter 1 › Section 1.1") "  p. 2"))
          (should (eq (get-text-property 2 'face (funcall annotate "Introduction (2)")) 'completions-annotations))
          (should-not (funcall annotate "A › B › C ü"))          ; no page
          (should-not (funcall annotate "Nothing")))))))

(ert-deftest pdf/outline-separator-of-the-sticky-header ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "outline separator.pdf")))
          (+my/sticky-separator " / ")
          (names nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (setq names (all-completions "" collection))
                   "A / B / C ü")))
        (should (equal (+test-pdf--scripts-of #'+my/pdf--outline-pick buffer +test-pdf--outline)
                       (list (+test-pdf--pdfx "outlineGo(4)")))))
      (should (member "Chapter 1 / Section 1.1" names)))))

(ert-deftest pdf/outline-none ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "outline none.pdf")))
          (asked nil))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (setq asked t) "")))
        (+test-clear-messages)
        (dolist (json '("[]" "not json" nil))
          (should-not (+test-pdf--scripts-of #'+my/pdf--outline-pick buffer json))))
      (should-not asked)
      (should (>= (+test-messages "^This PDF has no outline") 1)))))

(ert-deftest pdf/outline-nothing-picked-or-pdf-closed ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "outline closed.pdf")))
          (choice ""))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) choice)))
        (should-not (+test-pdf--scripts-of #'+my/pdf--outline-pick buffer +test-pdf--outline))
        (setq choice "Chapter 1")
        (kill-buffer buffer)
        (should-not (+test-pdf--scripts-of #'+my/pdf--outline-pick buffer +test-pdf--outline))))))

;; ====== THE MODE ======

(ert-deftest pdf/mode ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "the mode.pdf"))))
      (with-current-buffer buffer
        (should (derived-mode-p '+my/webkit-mode))
        (should (equal font-lock-defaults '(nil t)))
        (should (eq revert-buffer-function #'+my/pdf--revert))
        (should (eq +my/webkit-url-function #'+my/pdf--url))
        (should (eq +my/webkit-watch-function #'+my/pdf--watch))
        (should (equal +my/webkit-selection-script
                       "window.pdfx ? pdfx.selection() : String(window.getSelection())"))
        (should (eq (current-local-map) +my/pdf-mode-map))
        (dolist (hook '(change-major-mode-hook kill-buffer-hook))
          (should (memq #'+my/pdf--stop (symbol-value hook)))
          (should-not (memq #'+my/pdf--stop (default-value hook))))
        (should (eq evil-state 'normal))))
    (should (eq (evil-initial-state '+my/pdf-mode) 'normal))))

(ert-deftest pdf/doom-modeline-pdf-line ()
  (require 'doom-modeline)
  (should (eq (alist-get '+my/pdf-mode doom-modeline-mode-alist) 'pdf)))

(ert-deftest pdf/copy-asks-for-the-pdfs-selection ()
  (+test-pdf
    (let ((buffer (+test-pdf--open (+test-pdf--pdf "copy.pdf"))))
      (with-current-buffer buffer
        (+my/webkit-copy))
      (should (equal (cdar +test-pdf--scripts)
                     (list "window.pdfx ? pdfx.selection() : String(window.getSelection())" '+my/webkit-copied))))))

;; ====== KEYS ======

(defun +test-pdf--key (state key)
  (lookup-key (evil-get-auxiliary-keymap +my/pdf-mode-map state) (kbd key)))

(ert-deftest pdf/keys ()
  (pcase-dolist (`(,key . ,command)
                 '(("C-o" . +my/pdf-back) ("C-i" . +my/pdf-forward)
                   ("<tab>" . +my/pdf-forward) ("M-RET" . +my/pdf-actions)
                   ("j" . +my/pdf-scroll-down) ("k" . +my/pdf-scroll-up)
                   ("h" . +my/pdf-scroll-left) ("l" . +my/pdf-scroll-right)
                   ("<down>" . +my/pdf-scroll-down) ("<up>" . +my/pdf-scroll-up)
                   ("<left>" . +my/pdf-scroll-left) ("<right>" . +my/pdf-scroll-right)
                   ("C-d" . +my/pdf-half-screen-down) ("C-u" . +my/pdf-half-screen-up)
                   ("C-f" . +my/pdf-screen-down) ("C-b" . +my/pdf-screen-up)
                   ("<next>" . +my/pdf-screen-down) ("<prior>" . +my/pdf-screen-up)
                   ("gg" . +my/pdf-top) ("G" . +my/pdf-bottom)
                   ("<home>" . +my/pdf-top) ("<end>" . +my/pdf-bottom)
                   ("J" . +my/pdf-next-page) ("K" . +my/pdf-previous-page)
                   ("/" . +my/pdf-search) ("?" . +my/pdf-search-backward)
                   ("n" . +my/pdf-search-next) ("N" . +my/pdf-search-previous)
                   ("y" . +my/webkit-copy) ("+" . +my/pdf-zoom-in) ("=" . +my/pdf-zoom-in)
                   ("-" . +my/pdf-zoom-out) ("W" . +my/pdf-fit-width)
                   ("P" . +my/pdf-fit-page) ("o" . +my/pdf-outline)
                   ("O" . +my/pdf-toggle-sidebar) ("q" . kill-current-buffer)))
    (dolist (state '(normal motion))
      (should (eq (+test-pdf--key state key) command))))
  ;; Cmd keys, in any state.
  (pcase-dolist (`(,key . ,command)
                 '(("s-=" . +my/pdf-zoom-in) ("s-+" . +my/pdf-zoom-in)
                   ("s--" . +my/pdf-zoom-out) ("s-0" . +my/pdf-actual-size)
                   ("s-c" . +my/webkit-copy) ("s-[" . +my/pdf-back)
                   ("s-]" . +my/pdf-forward) ("s-p" . +my/pdf-print)
                   ("q" . kill-current-buffer)))
    (should (eq (lookup-key +my/pdf-mode-map (kbd key)) command)))
  ;; SPC m.
  (pcase-dolist (`(,key . ,command)
                 '(("o" . +my/pdf-outline) ("O" . +my/pdf-toggle-sidebar)
                   ("d" . +my/pdf-toggle-dark) ("t" . +my/pdf-toggle-toolbar)
                   ("p" . +my/pdf-open-in-preview) ("P" . +my/pdf-print)))
    (should (eq (+test-pdf--key 'normal (concat "SPC m " key)) command)))
  ;; Clicks are WebKit's.
  (should (eq (lookup-key +my/pdf-mode-map [down-mouse-1]) #'+my/webkit-mouse-select))
  (should (eq (+test-pdf--key 'normal "<drag-mouse-1>") #'ignore)))
