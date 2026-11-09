;;; tests/unit/test-html.el -*- lexical-binding: t; -*-
;; config/html.el: an HTML file's notice offering the browser. Which files and
;; modes get it (web-mode, Emacs's HTML modes, the long lines' mode), which
;; don't, turned off, and its button opening the file in the browser
;; (recorded: tests/helper.el's `browse-url').

(+test-load "config/html")

;; ====== HELPERS ======

(defvar +test-html--shown nil
  "The notices shown, (ID TEXT ACTIONS BUFFER), the latest first.")

(defmacro +test-html (&rest body)
  "BODY with notices recorded in `+test-html--shown', from one window."
  (declare (indent 0))
  `(+test-with-reset
     (let ((+test-html--shown nil)
           (+test-browsed nil)
           (+my/html-browser-notice t))
       (cl-letf (((symbol-function '+my/banner-show)
                  (lambda (id text &rest args)
                    (push (list id text (plist-get args :actions) (current-buffer))
                          +test-html--shown))))
         ,@body))))

(defun +test-html--file (name &optional content)
  "File NAME (CONTENT) in the temp folder, visited; its buffer."
  (find-file-noselect (+test-file (concat "html/" name) (or content "<p>Hi</p>\n"))))

(defun +test-html--offered-p (buffer)
  (seq-find (lambda (shown) (and (eq (car shown) 'html-browser) (eq (nth 3 shown) buffer)))
            +test-html--shown))

;; ====== SETTINGS ======

(ert-deftest html/settings ()
  (should (eq (default-value '+my/html-browser-notice) t))
  (should (equal +my/html-modes '(web-mode html-mode html-ts-mode so-long-mode)))
  (dolist (mode +my/html-modes)
    (should (memq #'+my/html-browser-notice-h
                  (default-value (intern (format "%s-hook" mode)))))))

;; ====== THE NOTICE ======

(ert-deftest html/an-html-file-offers-the-browser ()
  "An HTML file (Emacs's HTML mode here): the notice, its button."
  (+test-html
    (let ((buffer (+test-html--file "page.html")))
      (with-current-buffer buffer
        (should (derived-mode-p 'html-mode)))
      (let ((shown (+test-html--offered-p buffer)))
        (should shown)
        (should (equal (nth 1 shown) "Open this file in your browser."))
        (should (equal (nth 2 shown) '(("Open in browser" . +my/html-open-in-browser))))))))

(ert-deftest html/html-s-names ()
  ".html, .htm, .xhtml, in any case; not other files."
  (+test-html
    (dolist (name '("a.html" "b.htm" "c.xhtml" "D.HTML"))
      (with-current-buffer (+test-html--file name)
        (should (+my/html-file-p))))
    (dolist (name '("a.vue" "b.php" "c.txt" "d.html.erb" "e.htmlx"))
      (with-current-buffer (+test-html--file name)
        (should-not (+my/html-file-p))))
    (with-temp-buffer
      (html-mode)
      (should-not (+my/html-file-p)))))

(ert-deftest html/not-for-other-files ()
  "web-mode's other files (a template), an HTML buffer without a file: no
notice."
  (+test-html
    (with-temp-buffer
      (html-mode)
      (should-not (+test-html--offered-p (current-buffer))))
    (when (require 'web-mode nil t)
      (let ((buffer (+test-html--file "view.vue")))
        (with-current-buffer buffer (web-mode))
        (should-not (+test-html--offered-p buffer))))))

(ert-deftest html/in-web-mode ()
  "Doom's mode for HTML (:lang web): the notice."
  (skip-unless (require 'web-mode nil t))
  (+test-html
    (let ((buffer (+test-html--file "web.html")))
      (with-current-buffer buffer (web-mode))
      (should (+test-html--offered-p buffer)))))

(ert-deftest html/in-the-long-lines-mode ()
  "An HTML report with its data on one line (so-long-mode): the notice too."
  (+test-html
    (let ((buffer (+test-html--file "report.html")))
      (with-current-buffer buffer
        (setq +test-html--shown nil)
        (so-long-mode)
        (should (derived-mode-p 'so-long-mode)))
      (should (+test-html--offered-p buffer)))))

(ert-deftest html/turned-off ()
  (+test-html
    (let ((+my/html-browser-notice nil))
      (should-not (+test-html--offered-p (+test-html--file "off.html"))))))

;; ====== THE BROWSER ======

(ert-deftest html/open-in-browser ()
  "The button (in the file's buffer): the file in the browser, as a file URL."
  (+test-html
    (let ((buffer (+test-html--file "open.html")))
      (with-current-buffer buffer
        (funcall (cdr (assoc "Open in browser" (nth 2 (+test-html--offered-p buffer))))))
      (should (= (length +test-browsed) 1))
      (should (string-prefix-p "file://" (car +test-browsed)))
      (should (string-suffix-p "/html/open.html" (car +test-browsed))))
    (with-temp-buffer
      (should-error (+my/html-open-in-browser) :type 'user-error))
    (should (commandp #'+my/html-open-in-browser))))

;; ====== A PAGE IN EMACS ======

(ert-deftest html/a-page-in-emacs-without-webkit ()
  "In a terminal (as here, in batch): the browser, a file as a file URL."
  (+test-html
    (should (commandp #'+my/html-open-in-emacs))
    (should-not (+my/html-open-in-emacs "/tmp/report.html"))
    (should (string-prefix-p "file://" (car +test-browsed)))
    (should (string-suffix-p "/tmp/report.html" (car +test-browsed)))
    (should-not (+my/html-open-in-emacs "https://example.com/"))
    (should (equal (car +test-browsed) "https://example.com/"))))

(ert-deftest html/a-page-in-emacs-with-webkit ()
  "Where WebKit can: a page buffer of its own, its URL, in a pane; another
page so named replaces it."
  (+test-html
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
              ((symbol-function 'featurep) (let ((featurep (symbol-function 'featurep)))
                                             (lambda (f &rest r) (or (eq f 'xwidget-internal)
                                                                     (apply featurep f r)))))
              ((symbol-function '+my/webkit-file-url) (lambda (f) (concat "file://" f)))
              ((symbol-function '+my/html-page-mode) (lambda () (setq major-mode '+my/html-page-mode))))
      (let ((buffer (+my/html-open-in-emacs "/tmp/a/report.html")))
        (should (equal (buffer-name buffer) "Page: report.html"))
        (should (equal (buffer-local-value '+my/html-page-url buffer) "file:///tmp/a/report.html"))
        (should (eq (window-buffer (selected-window)) buffer))
        (should-not +test-browsed)
        (let ((other (+my/html-open-in-emacs "/tmp/b/report.html")))
          (should-not (buffer-live-p buffer))
          (should (equal (buffer-local-value '+my/html-page-url other) "file:///tmp/b/report.html"))
          (kill-buffer other))))))

(ert-deftest html/the-page-mode ()
  (should (eq (get '+my/html-page-mode 'derived-mode-parent) '+my/webkit-mode)))

