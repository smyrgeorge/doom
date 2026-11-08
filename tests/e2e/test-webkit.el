;;; tests/e2e/test-webkit.el -*- lexical-binding: t; -*-
;; config/webkit.el in a GUI Emacs, with real WebKit views: a page per window,
;; splits, spare and kept views, links out, JavaScript, the title read, copy,
;; scrolling, closing.

(+test-load "config/childframe" "config/window" "config/webkit")

;; ====== A TEST PAGE ======

(defconst +test-webkit--html
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>loading</title>
<style>body{margin:0;background:#123456;color:#eee;font:16px sans-serif}</style></head>
<body><p id=\"text\">Some text to select</p>
<p><a id=\"web\" href=\"https://example.com/x\">web</a>
<a id=\"file\" href=\"other.html\">file</a>
<a id=\"anchor\" href=\"#bottom\">anchor</a></p>
<div style=\"height:3000px\"></div><p id=\"bottom\">bottom</p>
<script>
function say(){ document.title = 'tp ' + JSON.stringify({y: Math.round(scrollY), w: innerWidth}); }
addEventListener('scroll', say); addEventListener('resize', say); say();
</script></body></html>")

(defvar +test-webkit--page
  (progn (+test-file "page/other.html" "<p>other</p>")
         (+test-file "page/index.html" +test-webkit--html)))

(defvar +test-webkit--watched nil
  "(WINDOW . STATE) the watch function was called with, the latest first.")

(defvar +test-webkit--loaded nil
  "The xwidgets whose page loaded, the latest first.")

(defun +test-webkit--url (_window)
  (+my/webkit-file-url +test-webkit--page))

(defun +test-webkit--watch (window xwidget)
  (push (cons window (+my/webkit-title-json xwidget "tp ")) +test-webkit--watched))

(defun +test-webkit--on-load (xwidget)
  (push xwidget +test-webkit--loaded))

(define-derived-mode +test-webkit-mode +my/webkit-mode "TestPage"
  "A test page in WebKit (config/webkit.el)."
  (setq-local +my/webkit-url-function #'+test-webkit--url
              +my/webkit-watch-function #'+test-webkit--watch
              +my/webkit-background "#123456")
  (add-hook '+my/webkit-load-functions #'+test-webkit--on-load nil t))

;; ====== HELPERS ======

(defun +test-webkit--open ()
  "The test page, in the selected window, loaded."
  (let ((buffer (get-buffer-create "*test page*")))
    (switch-to-buffer buffer)
    (unless (derived-mode-p '+test-webkit-mode)
      (+test-webkit-mode))
    (should (+test-webkit--loaded-in (selected-window)))
    buffer))

(defun +test-webkit--state (xwidget)
  (+my/webkit-title-json xwidget "tp "))

(defun +test-webkit--loaded-in (window &optional timeout)
  "WINDOW's view, once drawn there with its page loaded (its title said)."
  (+test-wait-for
   (lambda ()
     (with-current-buffer (window-buffer window)
       (let ((xwidget (+my/webkit-xwidget window)))
         (and xwidget
              (xwidget-view-lookup xwidget window)
              (+test-webkit--state xwidget)
              xwidget))))
   (or timeout 10)))

(defun +test-webkit--views (&optional buffer)
  (length (buffer-local-value '+my/webkit--views (or buffer (get-buffer "*test page*")))))

(defun +test-webkit--settle ()
  "Wait for the closed windows' views to go (a second after windows change)."
  (+test-sleep 1.4))

(defmacro +test-webkit (&rest body)
  "BODY from one window, the test page's buffer killed after (its views
closed)."
  (declare (indent 0))
  `(progn
     (+test-needs-webkit)
     (+test-with-reset
     (setq +test-webkit--watched nil
           +test-webkit--loaded nil
           +test-browsed nil)
     (+test-clear-messages)
     ,@body
     ;; Nothing left pending in WebKit when the views close.
     (+test-sleep 0.2))))

(defun +test-webkit--shares ()
  (+test-messages "share an xwidget"))

;; ====== VIEWS ======

(ert-deftest e2e-webkit/a-view-loads-in-the-window ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (should (equal (xwidget-size-request xwidget)
                     (list (xwidget-window-inside-pixel-width (selected-window))
                           (xwidget-window-inside-pixel-height (selected-window)))))
      (should (= (+test-webkit--views) 1))
      ;; The cover is gone once loaded.
      (should (+test-wait-for (lambda () (= (+test-visible-frames) 1)) 3))
      (should (memq xwidget +test-webkit--loaded)))))

(ert-deftest e2e-webkit/the-cover-has-the-page-colour ()
  (+test-webkit
    (let ((colours nil))
      (advice-add '+my/webkit--cover :after
                  (lambda (_window xwidget)
                    (when-let* ((cover (xwidget-get xwidget 'cover)))
                      (push (frame-parameter (car cover) 'background-color) colours)))
                  '((name . +test-cover)))
      (unwind-protect (+test-webkit--open)
        (advice-remove '+my/webkit--cover '+test-cover))
      (should (equal colours '("#123456"))))))

(ert-deftest e2e-webkit/split-gives-each-window-its-own-view ()
  (+test-webkit
    (+test-webkit--open)
    (let* ((left (selected-window))
           (right (split-window-right))
           (a (+test-webkit--loaded-in left))
           (b (+test-webkit--loaded-in right)))
      (should a)
      (should b)
      (should-not (eq a b))
      (should (= (+test-webkit--views) 2))
      (should (= (+test-webkit--shares) 0))
      ;; Each as big as its window.
      (dolist (pair (list (cons left a) (cons right b)))
        (should (equal (xwidget-size-request (cdr pair))
                       (list (xwidget-window-inside-pixel-width (car pair))
                             (xwidget-window-inside-pixel-height (car pair)))))))))

(ert-deftest e2e-webkit/views-scroll-apart ()
  (+test-webkit
    (+test-webkit--open)
    (let* ((left (selected-window))
           (right (split-window-right))
           (a (+test-webkit--loaded-in left))
           (b (+test-webkit--loaded-in right)))
      (with-current-buffer "*test page*"
        (+my/webkit-execute "window.scrollTo(0, 500)" a))
      (should (+test-wait-for (lambda () (eql (plist-get (+test-webkit--state a) :y) 500)) 3))
      (should (eql (plist-get (+test-webkit--state b) :y) 0))
      ;; The selected window's view by default, all of them with t.
      (select-window right)
      (with-current-buffer "*test page*"
        (+my/webkit-execute "window.scrollTo(0, 200)"))
      (should (+test-wait-for (lambda () (eql (plist-get (+test-webkit--state b) :y) 200)) 3))
      (should (eql (plist-get (+test-webkit--state a) :y) 500))
      (with-current-buffer "*test page*"
        (+my/webkit-execute "window.scrollTo(0, 100)" t))
      (should (+test-wait-for (lambda () (and (eql (plist-get (+test-webkit--state a) :y) 100)
                                              (eql (plist-get (+test-webkit--state b) :y) 100)))
                              3)))))

(ert-deftest e2e-webkit/a-closed-window-s-view-goes-a-second-later ()
  (+test-webkit
    (+test-webkit--open)
    (let* ((left (selected-window))
           (right (split-window-right)))
      (should (+test-webkit--loaded-in right))
      (delete-window right)
      (+test-webkit--settle)
      (should (= (+test-webkit--views) 1))
      ;; The one left is as wide as the window again.
      (let ((xwidget (+my/webkit-xwidget left)))
        (should (+test-wait-for
                 (lambda () (equal (xwidget-size-request xwidget)
                                   (list (xwidget-window-inside-pixel-width left)
                                         (xwidget-window-inside-pixel-height left))))
                 3))))))

(ert-deftest e2e-webkit/a-tab-away-and-back-keeps-the-view ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (with-current-buffer "*test page*"
        (+my/webkit-execute "window.scrollTo(0, 700)"))
      (should (+test-wait-for (lambda () (eql (plist-get (+test-webkit--state xwidget) :y) 700)) 3))
      (switch-to-buffer "*scratch*")
      (+test-sleep 0.3)
      (switch-to-buffer "*test page*")
      (should (eq (+test-webkit--loaded-in (selected-window)) xwidget))
      (should (eql (plist-get (+test-webkit--state xwidget) :y) 700))
      (+test-webkit--settle)
      (should (= (+test-webkit--views) 1)))))

(ert-deftest e2e-webkit/a-window-takes-a-spare-view ()
  "A window showing another buffer gives its view to a window that needs one."
  (+test-webkit
    (+test-webkit--open)
    (let* ((left (selected-window))
           (right (split-window-right))
           (a (+test-webkit--loaded-in left)))
      (should (+test-webkit--loaded-in right))
      (with-selected-window left (switch-to-buffer "*scratch*"))
      (let ((below (with-selected-window right (split-window-below))))
        (should (eq (+test-webkit--loaded-in below) a))
        (should (= (+test-webkit--views) 2))
        (should (= (+test-webkit--shares) 0))))))

(ert-deftest e2e-webkit/the-last-view-stays-for-the-next-window ()
  (+test-webkit
    (+test-webkit--open)
    (let* ((right (split-window-right))
           (_ (+test-webkit--loaded-in right))
           (latest nil))
      (select-window right)
      (+test-sleep 0.3)                   ; the watch sees it looked at
      (setq latest (+my/webkit-xwidget right))
      (delete-other-windows)
      (switch-to-buffer "*scratch*")
      (+test-webkit--settle)
      (should (= (+test-webkit--views) 1))
      (with-current-buffer "*test page*"
        (should (eq (+my/webkit-xwidget) latest)))
      (switch-to-buffer "*test page*")
      (should (eq (+test-webkit--loaded-in (selected-window)) latest))
      (should (= (+test-webkit--shares) 0)))))

(ert-deftest e2e-webkit/no-view-in-a-child-frame ()
  "A child frame showing the page (a cover is one) gets no view of it."
  (+test-webkit
    (+test-webkit--open)
    (let ((child (with-current-buffer "*test page*"
                   (+my/childframe-make (selected-frame) "test"))))
      (unwind-protect
          (progn
            (set-window-dedicated-p (frame-root-window child) nil)
            (set-window-buffer (frame-root-window child) "*test page*")
            (make-frame-visible child)
            (+test-sleep 0.6)
            (should (= (+test-webkit--views) 1))
            (should-not (+my/webkit--view (frame-root-window child))))
        (delete-frame child t)))))

(ert-deftest e2e-webkit/killing-the-buffer-closes-its-views ()
  (+test-webkit
    (+test-webkit--open)
    (let ((right (split-window-right)))
      (should (+test-webkit--loaded-in right))
      (let ((xwidgets (with-current-buffer "*test page*" (+my/webkit-xwidgets))))
        (should (= (length xwidgets) 2))
        (kill-buffer "*test page*")
        (dolist (xwidget xwidgets)
          (should-not (memq xwidget (bound-and-true-p xwidget-list))))
        (should (= (+test-visible-frames) 1))))))

(ert-deftest e2e-webkit/another-mode-closes-the-views ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (with-current-buffer "*test page*"
        (fundamental-mode)
        (should-not +my/webkit--views)
        (should-not (get-text-property (point-min) 'display)))
      (should-not (memq xwidget (bound-and-true-p xwidget-list))))))

;; ====== LINKS OUT ======

(defun +test-webkit--click (xwidget id)
  (with-current-buffer "*test page*"
    (+my/webkit-execute (format "document.getElementById('%s').click()" id) xwidget)))

(ert-deftest e2e-webkit/a-web-link-goes-to-the-browser ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (+test-webkit--click xwidget "web")
      (should (+test-wait-for (lambda () +test-browsed) 5))
      (should (equal +test-browsed '("https://example.com/x")))
      ;; The view stays on (or comes back to) the page.
      (should (+test-wait-for
               (lambda () (string-suffix-p "index.html" (or (xwidget-webkit-uri xwidget) "")))
               5))
      (should (+test-webkit--loaded-in (selected-window))))))

(ert-deftest e2e-webkit/a-link-to-another-file-goes-out-too ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (+test-webkit--click xwidget "file")
      (should (+test-wait-for (lambda () +test-browsed) 5))
      (should (string-suffix-p "/page/other.html" (car +test-browsed)))
      (should (equal (+my/webkit-url-file (car +test-browsed))
                     (expand-file-name "page/other.html" +test-tmp)))
      (should (+test-wait-for
               (lambda () (string-suffix-p "index.html" (or (xwidget-webkit-uri xwidget) "")))
               5)))))

(ert-deftest e2e-webkit/an-anchor-in-the-page-stays ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (+test-webkit--click xwidget "anchor")
      (should (+test-wait-for (lambda () (> (or (plist-get (+test-webkit--state xwidget) :y) 0) 0)) 3))
      (+test-sleep 0.3)
      (should-not +test-browsed))))

(ert-deftest e2e-webkit/the-same-link-twice-opens-once ()
  "WebKit may report a link's load twice: the browser gets it once."
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window))))
      (+test-webkit--click xwidget "web")
      (should (+test-wait-for (lambda () +test-browsed) 5))
      (should (+test-webkit--loaded-in (selected-window)))
      (+test-webkit--click xwidget "web")
      (+test-sleep 1)
      (should (equal +test-browsed '("https://example.com/x"))))))

;; ====== WATCHING, JAVASCRIPT ======

(ert-deftest e2e-webkit/the-watch-sees-each-window-s-page ()
  (+test-webkit
    (+test-webkit--open)
    (let* ((left (selected-window))
           (right (split-window-right)))
      (should (+test-webkit--loaded-in right))
      (setq +test-webkit--watched nil)
      (+test-sleep 0.5)
      (let ((windows (delete-dups (mapcar #'car +test-webkit--watched))))
        (should (memq left windows))
        (should (memq right windows)))
      ;; Each with its own page's state (its width).
      (let ((left-state (cdr (assq left +test-webkit--watched)))
            (right-state (cdr (assq right +test-webkit--watched))))
        (should (natnump (plist-get left-state :w)))
        (should (natnump (plist-get right-state :w)))))))

(ert-deftest e2e-webkit/the-latest-looked-at-comes-first ()
  (+test-webkit
    (+test-webkit--open)
    (let* ((left (selected-window))
           (right (split-window-right)))
      (should (+test-webkit--loaded-in right))
      (select-window right)
      (+test-sleep 0.3)
      (with-current-buffer "*test page*"
        (should (eq (overlay-get (car +my/webkit--views) 'window) right)))
      (select-window left)
      (+test-sleep 0.3)
      (with-current-buffer "*test page*"
        (should (eq (overlay-get (car +my/webkit--views) 'window) left))))))

(ert-deftest e2e-webkit/copy-takes-the-page-s-selection ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window)))
          (kill-ring nil))
      (should (equal (+test-js xwidget "var r = document.createRange();
r.selectNodeContents(document.getElementById('text'));
var s = getSelection(); s.removeAllRanges(); s.addRange(r); String(s)")
                     "Some text to select"))
      (with-current-buffer "*test page*"
        (should (+my/webkit-copy)))
      (should (+test-wait-for (lambda () kill-ring) 3))
      (should (equal (car kill-ring) "Some text to select")))))

(ert-deftest e2e-webkit/copy-without-a-selection-says-so ()
  (+test-webkit
    (+test-webkit--open)
    (let ((kill-ring nil))
      (with-current-buffer "*test page*"
        (+my/webkit-copy))
      (should (+test-wait-for (lambda () (> (+test-messages "No text selected") 0)) 3))
      (should-not kill-ring))))

(ert-deftest e2e-webkit/scroll-commands ()
  (+test-webkit
    (+test-webkit--open)
    (let ((xwidget (+my/webkit-xwidget (selected-window)))
          (y (lambda (xw) (plist-get (+test-webkit--state xw) :y))))
      (with-current-buffer "*test page*"
        (+my/webkit-scroll-down 2))
      (should (+test-wait-for (lambda () (eql (funcall y xwidget) (* 2 +my/webkit-scroll-step))) 3))
      (with-current-buffer "*test page*"
        (+my/webkit-scroll-up))
      (should (+test-wait-for (lambda () (eql (funcall y xwidget) +my/webkit-scroll-step)) 3))
      (with-current-buffer "*test page*"
        (+my/webkit-bottom))
      (should (+test-wait-for (lambda () (> (funcall y xwidget) 2000)) 3))
      (with-current-buffer "*test page*"
        (+my/webkit-top))
      (should (+test-wait-for (lambda () (eql (funcall y xwidget) 0)) 3))
      (with-current-buffer "*test page*"
        (+my/webkit-half-screen-down))
      (should (+test-wait-for (lambda () (> (funcall y xwidget) 100)) 3)))))

(ert-deftest e2e-webkit/point-stays-at-the-start ()
  (+test-webkit
    (+test-webkit--open)
    (with-current-buffer "*test page*"
      (should (= (point) (point-min)))
      (should (= (window-start) (point-min)))
      (should buffer-read-only))))
