;;; tests/e2e/test-html.el -*- lexical-binding: t; -*-
;; config/html.el in a GUI Emacs: an HTML file as a page in WebKit, in a
;; buffer of its own (A PAGE IN EMACS), its view loading the file; closed, its
;; view gone. Agent UI's html cards open so. An Emacs without xwidgets: the
;; browser.

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
