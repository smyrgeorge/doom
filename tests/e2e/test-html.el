;;; tests/e2e/test-html.el -*- lexical-binding: t; -*-
;; config/html.el in a GUI Emacs: an HTML file as a page in WebKit, in a
;; buffer of its own (A PAGE IN EMACS), its view loading the file; closed, its
;; view gone. Agent UI's html cards open so. An Emacs without xwidgets: the
;; browser. Its keys' commands: scrolled, copied, zoomed, fitted to a narrow
;; pane, the zoom kept in a split, closed. A URL (a server of the test's
;; own): shown, redirected in Emacs, a link to another page in the browser;
;; typed at M-x. A changed file: opened again or reverted, its new page.

(+test-load "config/emacs" "config/webkit" "config/html")

(defconst +test-html-page
  "<!doctype html><html><head><title>Report</title></head><body><p>87%</p></body></html>")

(defun +test-html--serve (routes)
  "A web server on this machine answering ROUTES, ((PATH . ANSWER)...): a
page, or (redirect . PATH); others are 404. Its port."
  (let ((server
         (make-network-process
          :name "test-http" :server t :host "127.0.0.1" :service t :family 'ipv4
          :coding 'binary :noquery t
          :filter
          (lambda (process text)
            (let ((request (concat (or (process-get process 'request) "") text)))
              (process-put process 'request request)
              (when (and (string-search "\r\n\r\n" request)
                         (string-match "\\`GET \\([^ ?#]+\\)" request))
                (let* ((answer (cdr (assoc (match-string 1 request) routes)))
                       (body (encode-coding-string (if (stringp answer) answer "") 'utf-8)))
                  (process-send-string
                   process
                   (concat (cond ((stringp answer) "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n")
                                 ((eq (car-safe answer) 'redirect)
                                  (format "HTTP/1.1 302 Found\r\nLocation: %s\r\n" (cdr answer)))
                                 (t "HTTP/1.1 404 Not Found\r\n"))
                           (format "Content-Length: %d\r\nConnection: close\r\n\r\n" (length body))
                           body))
                  (process-send-eof process))))))))
    (process-contact server :service)))

(defun +test-html--uri (buffer)
  "The URL BUFFER's view shows, in its window."
  (with-current-buffer buffer
    (when-let* ((window (get-buffer-window buffer))
                (xwidget (+my/webkit-xwidget window)))
      (xwidget-webkit-uri xwidget))))

(ert-deftest e2e-html/a-url-in-emacs ()
  "A URL shown in its view, its redirect followed there; a link to another
page goes to the browser, the view staying; M-x takes a URL."
  (+test-needs-webkit)
  (+test-with-reset
    (let* ((port (+test-html--serve
                  '(("/old.html" redirect . "/page.html")
                    ("/page.html" . "<!doctype html><title>Served</title><a id=\"other\" href=\"/other.html\">Other</a> <a id=\"part\" href=\"#part\">Part</a>")
                    ("/other.html" . "<!doctype html><title>Other</title>"))))
           (base (format "http://127.0.0.1:%d" port))
           (+test-browsed nil)
           (buffer (+my/html-open-in-emacs (concat base "/old.html"))))
      (should (+test-wait-for (lambda () (equal (+test-html--uri buffer) (concat base "/page.html"))) 10))
      (let ((xwidget (with-current-buffer buffer (+my/webkit-xwidget (get-buffer-window buffer)))))
        (should (+test-wait-for (lambda () (equal (xwidget-webkit-title xwidget) "Served")) 5))
        (should-not +test-browsed)
        ;; Its own part: in Emacs.
        (+test-html--js xwidget "document.getElementById('part').click()")
        (+test-sleep 0.5)
        (should-not +test-browsed)
        ;; Another page: the browser's; the view stays.
        (+test-html--js xwidget "document.getElementById('other').click()")
        (should (+test-wait-for (lambda () (equal +test-browsed (list (concat base "/other.html")))) 5))
        (+test-sleep 0.5)
        (should (equal (xwidget-webkit-title xwidget) "Served"))
        (should (string-prefix-p (concat base "/page.html") (xwidget-webkit-uri xwidget)))))
    ;; M-x: a URL typed after the folder offered.
    (let* ((port (+test-html--serve '(("/typed.html" . "<!doctype html><title>Typed</title>"))))
           (url (format "http://127.0.0.1:%d/typed.html" port))
           (+test-browsed nil))
      (execute-kbd-macro (vconcat (kbd "M-x") "+my/html-open-in-emacs" (kbd "RET") url (kbd "RET")))
      (let ((buffer (get-buffer (concat "Page: " url))))
        (should buffer)
        (should (+test-wait-for (lambda () (equal (+test-html--uri buffer) url)) 10))
        (should-not +test-browsed)))))

(ert-deftest e2e-html/a-page-in-the-browser-without-webkit ()
  (skip-when (featurep 'xwidget-internal))
  (+test-with-reset
    (let ((file (+test-file "pages/report.html" +test-html-page))
          (+test-browsed nil))
      (should-not (+my/html-open-in-emacs file))
      (should (string-prefix-p "file://" (car +test-browsed)))
      (should (string-suffix-p "/pages/report.html" (car +test-browsed)))
      (should-not (get-buffer "Page: report.html")))))

(ert-deftest e2e-html/a-page-in-emacs ()
  (+test-needs-webkit)
  (+test-with-reset
    (let* ((file (+test-file "pages/report.html" +test-html-page))
           (buffer (+my/html-open-in-emacs file)))
      (should (buffer-live-p buffer))
      (should (equal (buffer-name buffer) "Page: report.html"))
      (should (eq (buffer-local-value 'major-mode buffer) '+my/html-page-mode))
      (let ((window (get-buffer-window buffer)))
        (should window)
        ;; Its view, on the file.
        (should (+test-wait-for
                 (lambda ()
                   (with-current-buffer buffer
                     (let ((xwidget (+my/webkit-xwidget window)))
                       (and xwidget
                            (equal (xwidget-webkit-uri xwidget) (+my/webkit-file-url file))))))
                 10)))
      (kill-buffer buffer)
      (should-not (buffer-live-p buffer)))))

(ert-deftest e2e-html/a-changed-page-reloaded ()
  "The file changed: opened again, its new page; changed again, g r
(revert-buffer) shows it."
  (+test-needs-webkit)
  (+test-with-reset
    (let* ((version (lambda (title) (format "<!doctype html><title>%s</title><p>%s</p>" title title)))
           (file (+test-file "pages/changing.html" (funcall version "version one")))
           (buffer (+my/html-open-in-emacs file))
           (title (lambda ()
                    (with-current-buffer buffer
                      (when-let* ((xwidget (+my/webkit-xwidget (get-buffer-window buffer))))
                        (xwidget-webkit-title xwidget))))))
      (should (+test-wait-for (lambda () (equal (funcall title) "version one")) 10))
      (+test-file "pages/changing.html" (funcall version "version two"))
      (should (eq (+my/html-open-in-emacs file) buffer))
      (should (+test-wait-for (lambda () (equal (funcall title) "version two")) 10))
      (+test-file "pages/changing.html" (funcall version "version three"))
      (with-current-buffer buffer (revert-buffer))
      (should (+test-wait-for (lambda () (equal (funcall title) "version three")) 10)))))

;; ====== ITS KEYS ======

(defconst +test-html-wide
  (concat "<!doctype html><html><head><title>Wide</title></head><body>"
          "<div id=\"wide\" style=\"width:746px;height:40px;background:gray\"></div>"
          "<p id=\"text\">Some text to copy.</p><div style=\"height:3000px\"></div></body></html>")
  "A page wider than a narrow pane (a chart, say), taller than any.")

(defun +test-html--js (xwidget expression)
  "EXPRESSION's value in XWIDGET's page, as a string."
  (+test-js xwidget (format "String(%s)" expression)))

(defun +test-html--number (xwidget expression)
  (string-to-number (+test-html--js xwidget expression)))

(defconst +test-html--measures-js
  "JSON.stringify((() => { const w = document.getElementById('wide'), r = document.documentElement;
  return {box: w.getBoundingClientRect().width, offset: w.offsetWidth, zoom: r.style.zoom,
          computed: getComputedStyle(r).zoom, inner: innerWidth, client: r.clientWidth, scroll: r.scrollWidth,
          scale: visualViewport.scale, ua: navigator.userAgent}; })())"
  "The wide page's measures, as JSON: said when a zoom isn't seen.")

(defun +test-html--loaded (buffer window)
  "BUFFER's view in WINDOW, once its page has loaded (its cover off)."
  (+test-wait-for
   (lambda ()
     (with-current-buffer buffer
       (let ((xwidget (+my/webkit-xwidget window)))
         (and xwidget
              (equal (xwidget-webkit-title xwidget) "Wide")
              (not (xwidget-get xwidget 'cover))
              xwidget))))
   10))

(ert-deftest e2e-html/a-page-s-keys ()
  "In a 40-column pane: j scrolls the view, y copies its selection, -
shrinks the page, W fits it to the pane, the zoom kept in a split; q closes
it."
  (+test-needs-webkit)
  (+test-with-reset
    (let* ((file (+test-file "pages/wide.html" +test-html-wide))
           (buffer (+my/html-open-in-emacs file))
           (window (get-buffer-window buffer))
           (page "document.documentElement.scrollWidth"))
      (delete-other-windows window)
      (set-window-buffer (split-window window 40 'right) "*scratch*")
      (select-window window)
      (let ((xwidget (+test-html--loaded buffer window)))
        (should xwidget)
        (should (= (+test-html--number xwidget "innerWidth") (window-body-width window t)))
        ;; j: down.
        (+my/webkit-scroll-down)
        (should (+test-wait-for (lambda () (> (+test-html--number xwidget "scrollY") 0)) 5))
        ;; y: the selection copied (not to the system's clipboard).
        (+test-html--js xwidget "getSelection().selectAllChildren(document.getElementById('text'))")
        (let ((kill-ring nil)
              (interprogram-cut-function nil)
              (interprogram-paste-function nil))
          (+my/webkit-copy)
          (should (+test-wait-for (lambda () (equal (car kill-ring) "Some text to copy.")) 5)))
        ;; -: smaller, the page's width as laid out (its scroll width: an
        ;; element's box counts the root's zoom in some WebKits, not in others).
        (let ((width (+test-html--number xwidget page)))
          (+my/html-page-zoom-out)
          (unless (+test-wait-for (lambda () (< (+test-html--number xwidget page) (* 0.9 width))) 5)
            (ert-fail (list "- didn't make the page smaller" width (+test-js xwidget +test-html--measures-js)))))
        ;; W: as wide as the pane (wider at its own size).
        (+my/html-page-actual-size)
        (should (+test-wait-for (lambda () (> (+test-html--number xwidget "document.documentElement.scrollWidth")
                                              (+test-html--number xwidget "innerWidth")))
                                5))
        (+my/html-page-fit-width)
        (should (+test-wait-for (lambda () (<= (+test-html--number xwidget "document.documentElement.scrollWidth")
                                               (+test-html--number xwidget "innerWidth")))
                                5))
        ;; Split: the new pane's view at the page's zoom.
        (let ((zoom (+test-html--js xwidget "document.documentElement.style.zoom"))
              (scale (+test-html--js xwidget "visualViewport.scale"))
              (below (split-window window nil 'below)))
          (should (< 0.1 (string-to-number zoom) 1))
          (let ((other (+test-html--loaded buffer below)))
            (should other)
            (should-not (eq other xwidget))
            (should (+test-wait-for
                     (lambda () (and (equal (+test-html--js other "document.documentElement.style.zoom") zoom)
                                     (equal (+test-html--js other "visualViewport.scale") scale)))
                     5))))
        ;; q: closed.
        (call-interactively #'+my/html-page-quit)
        (should-not (buffer-live-p buffer))))))
