;;; tests/unit/test-html.el -*- lexical-binding: t; -*-
;; config/html.el: an HTML file's notice offering the browser. Which files and
;; modes get it (web-mode, Emacs's HTML modes, the long lines' mode), which
;; don't, turned off, and its button opening the file in the browser
;; (recorded: tests/helper.el's `browse-url'). A page in Emacs: its buffer,
;; its keys, its zoom (the scripts its views get, recorded).

(require 'xwidget)
(+test-load "config/webkit" "config/html")

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


;; ====== A PAGE'S KEYS ======

(ert-deftest html/page-keys ()
  "Scrolling, copying, zoom, q; clicks WebKit's (no visual state). Cmd and
Linux's Ctrl keys: test-keys.el."
  (pcase-dolist (`(,key . ,command)
                 '(("j" . +my/webkit-scroll-down) ("k" . +my/webkit-scroll-up)
                   ("h" . +my/webkit-scroll-left) ("l" . +my/webkit-scroll-right)
                   ("C-d" . +my/webkit-half-screen-down) ("C-u" . +my/webkit-half-screen-up)
                   ("C-f" . +my/webkit-screen-down) ("C-b" . +my/webkit-screen-up)
                   ("gg" . +my/webkit-top) ("G" . +my/webkit-bottom)
                   ("y" . +my/webkit-copy)
                   ("+" . +my/html-page-zoom-in) ("=" . +my/html-page-zoom-in)
                   ("-" . +my/html-page-zoom-out) ("0" . +my/html-page-actual-size)
                   ("W" . +my/html-page-fit-width) ("q" . +my/html-page-quit)))
    (should (eq (lookup-key (evil-get-auxiliary-keymap +my/html-page-mode-map 'normal) (kbd key))
                command)))
  (should (eq (lookup-key +my/html-page-mode-map (kbd "s-c")) #'+my/webkit-copy))
  (should (eq (lookup-key +my/html-page-mode-map (kbd "s--")) #'+my/html-page-zoom-out))
  (should (eq (lookup-key +my/html-page-mode-map [down-mouse-1]) #'+my/webkit-mouse-select))
  (should (eq (lookup-key (evil-get-auxiliary-keymap +my/html-page-mode-map 'normal) [down-mouse-1])
              #'+my/webkit-mouse-select))
  (dolist (command '(+my/html-page-zoom-in +my/html-page-zoom-out +my/html-page-actual-size
                     +my/html-page-fit-width +my/html-page-quit))
    (should (commandp command))))

(defvar +test-html--scripts nil
  "(SCRIPT VIEW) run in a page's views, the latest first; (ask SCRIPT
FUNCTION VIEW) asked; (zoom VIEW CHANGE) WebKit's own zoom changed.")

(defvar +test-html--views nil "The page's fake views (symbols).")

(defmacro +test-html--page (&rest body)
  "BODY in a page's buffer with two fake views, what they're asked to do
recorded."
  (declare (indent 0))
  `(+test-with-reset
     (let ((+test-html--scripts nil)
           (+test-html--views (list (make-symbol "view") (make-symbol "other"))))
       (cl-letf (((symbol-function '+my/webkit-xwidgets) (lambda () +test-html--views))
                 ((symbol-function '+my/webkit-xwidget) (lambda (&optional _) (car +test-html--views)))
                 ((symbol-function 'xwidget-put) (lambda (view property value) (put view property value)))
                 ((symbol-function 'xwidget-get) (lambda (view property) (get view property)))
                 ((symbol-function 'xwidget-webkit-zoom)
                  (lambda (view change) (push (list 'zoom view change) +test-html--scripts)))
                 ((symbol-function '+my/webkit-execute)
                  (lambda (script &optional where) (push (list script where) +test-html--scripts)))
                 ((symbol-function '+my/webkit-ask)
                  (lambda (script function &optional xwidget)
                    (push (list 'ask script function xwidget) +test-html--scripts))))
         (with-current-buffer (get-buffer-create "Page: zoom.html")
           (+my/html-page-mode)
           ,@body)))))

(defun +test-html--set (view)
  "The zoom VIEW's page was last given (\"\": its own size), or nil."
  (when-let* ((script (seq-find (lambda (s) (and (stringp (car s)) (eq (cadr s) view)))
                                +test-html--scripts)))
    (and (string-match "\\`document.documentElement.style.zoom = '\\([^']*\\)'\\'" (car script))
         (match-string 1 (car script)))))

(defun +test-html--magnified (view)
  "How much VIEW was magnified in all (WebKit's zoom, from 1)."
  (+ 1.0 (apply #'+ (mapcar (lambda (s) (nth 2 s))
                            (seq-filter (lambda (s) (and (eq (car s) 'zoom) (eq (nth 1 s) view)))
                                        +test-html--scripts)))))

(defun +test-html--near (a b) (< (abs (- a b)) 1e-9))

(ert-deftest html/page-zoom ()
  "+, -, 0: the page's zoom, laid out anew in each of its views."
  (+test-html--page
    (+my/html-page-zoom-in)
    (dolist (view +test-html--views)
      (should (equal (+test-html--set view) "1.25")))
    (+my/html-page-zoom-in)
    (should (equal (+test-html--set (car +test-html--views)) "1.5625"))
    (+my/html-page-zoom-out)
    (should (equal (+test-html--set (car +test-html--views)) "1.25"))
    (+my/html-page-actual-size)
    (should (equal (+test-html--set (car +test-html--views)) ""))
    (+my/html-page-zoom-out)
    (should (equal (+test-html--set (car +test-html--views)) "0.8"))
    ;; Laid out anew only: not magnified.
    (should-not (assq 'zoom +test-html--scripts))))

(ert-deftest html/page-zoomed-out-past-half-magnified ()
  "Below half its size: laid out at half, the views magnified by what's
left; back up, unmagnified. A tenth of its size at least, ten times at most."
  (+test-html--page
    (dotimes (_ 4) (+my/html-page-zoom-out))   ; 0.8^4 = 0.4096
    (dolist (view +test-html--views)
      (should (equal (+test-html--set view) "0.5"))
      (should (+test-html--near (+test-html--magnified view) 0.8192)))
    (dotimes (_ 30) (+my/html-page-zoom-out))
    (should (equal (+test-html--set (car +test-html--views)) "0.5"))
    (should (+test-html--near (+test-html--magnified (car +test-html--views)) 0.2))
    (+my/html-page-actual-size)
    (dolist (view +test-html--views)
      (should (equal (+test-html--set view) ""))
      (should (+test-html--near (+test-html--magnified view) 1.0)))
    (dotimes (_ 30) (+my/html-page-zoom-in))
    (should (equal (+test-html--set (car +test-html--views)) "10"))))

(ert-deftest html/page-zoom-in-a-new-view ()
  "A view loaded later (a split): the page's zoom; at its size, nothing."
  (+test-html--page
    (should (memq #'+my/html--loaded +my/webkit-load-functions))
    (let ((new (make-symbol "new")))
      (run-hook-with-args '+my/webkit-load-functions new)
      (should-not +test-html--scripts)
      (+my/html--zoom 0.25)
      (run-hook-with-args '+my/webkit-load-functions new)
      (should (equal (+test-html--set new) "0.5"))
      (should (+test-html--near (+test-html--magnified new) 0.5))
      ;; Loaded again (reloaded): laid out so again, magnified already.
      (run-hook-with-args '+my/webkit-load-functions new)
      (should (+test-html--near (+test-html--magnified new) 0.5)))))

(ert-deftest html/page-fit-width ()
  "W: the zoom worked out in the selected pane's view, unmagnified (an
answer to a symbol), then the page's, in each view."
  (+test-html--page
    (let ((view (car +test-html--views)))
      (+my/html--zoom 0.25)
      (+my/html-page-fit-width)
      ;; Unmagnified first.
      (should (+test-html--near (+test-html--magnified view) 1.0))
      (pcase-let ((`(ask ,script ,function ,asked) (car +test-html--scripts)))
        (should (string-search "root.clientWidth / root.scrollWidth" script))
        (should (string-search "})(0.5)" script))
        (should (eq asked view))
        (should (eq function '+my/html--fitted))
        (funcall function 0.35))
      (dolist (view +test-html--views)
        (should (equal (+test-html--set view) "0.5"))
        (should (+test-html--near (+test-html--magnified view) 0.7)))
      (setq +test-html--scripts nil)
      (+my/html--fitted nil)
      (should-not +test-html--scripts))))

(ert-deftest html/page-quit ()
  "q: the page closed with the pane made for it."
  (+test-html--page
    (let ((page (current-buffer)))
      (pop-to-buffer page '(display-buffer-pop-up-window))
      (should (= (length (window-list)) 2))
      (+my/html-page-quit)
      (should-not (buffer-live-p page))
      (should (= (length (window-list)) 1)))))
