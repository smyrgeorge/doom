;;; tests/e2e/test-html.el -*- lexical-binding: t; -*-
;; config/html.el in a GUI Emacs: an HTML file as a page in WebKit, in a
;; buffer of its own (A PAGE IN EMACS), its view loading the file; closed, its
;; view gone. Agent UI's html cards open so. An Emacs without xwidgets: the
;; browser. Its keys' commands: scrolled, copied, zoomed, fitted to a narrow
;; pane, the zoom kept in a split, closed.

(+test-load "config/childframe" "config/window" "config/webkit" "config/html")

(defconst +test-html-page
  "<!doctype html><html><head><title>Report</title></head><body><p>87%</p></body></html>")

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
           (wide "document.getElementById('wide').getBoundingClientRect().width"))
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
        ;; -: smaller.
        (let ((width (+test-html--number xwidget wide)))
          (+my/html-page-zoom-out)
          (should (+test-wait-for (lambda () (< (+test-html--number xwidget wide) (* 0.9 width))) 5)))
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
