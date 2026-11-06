;;; tests/unit/test-webkit.el -*- lexical-binding: t; -*-
;; config/webkit.el: web pages inside Emacs, in WebKit (xwidgets): a view per
;; window, spare views, views of closed windows tidied, the cover against the
;; white flash, links out, JavaScript, the title read, the pointer, clicks,
;; commands, the base mode.
;; Batch Emacs has no GUI: WebKit is faked (`+test-webkit--with-fakes'), the
;; windows, overlays, buffers and timers are real. Redisplay doesn't run here:
;; the window hooks it would run are called by the tests (`+test-webkit--show').

(require 'xwidget)                      ; before faking its functions
(+test-load "config/webkit")

;; ====== FAKE WEBKIT ======

(cl-defstruct (+test-webkit--xw (:constructor +test-webkit--xw-new) (:copier nil))
  "A fake WebKit view."
  buffer name width height props uri title killed)

(defvar +test-webkit--made nil "The fake views made, oldest first.")
(defvar +test-webkit--scripts nil "(XWIDGET SCRIPT CALLBACK) run, oldest first.")
(defvar +test-webkit--log nil "(FUNCTION ARGS...) of the other WebKit calls, oldest first.")
(defvar +test-webkit--stop-error nil "Non-nil: stopping a load signals an error.")

(defun +test-webkit--log (&rest call)
  (setq +test-webkit--log (append +test-webkit--log (list call))))

(defun +test-webkit--calls (function)
  "The arguments of each logged call to FUNCTION, oldest first."
  (mapcar #'cdr (seq-filter (lambda (call) (eq (car call) function)) +test-webkit--log)))

(defmacro +test-webkit--with-fakes (&rest body)
  "BODY with WebKit's functions faked (none of the real ones can run)."
  (declare (indent 0))
  `(let ((+test-webkit--made nil)
         (+test-webkit--scripts nil)
         (+test-webkit--log nil)
         (+test-webkit--stop-error nil))
     (cl-letf (((symbol-function 'make-xwidget)
                (lambda (type title width height &optional _arguments buffer _related)
                  (let ((xw (+test-webkit--xw-new :buffer buffer :name title
                                                  :width width :height height)))
                    (setq +test-webkit--made (append +test-webkit--made (list xw)))
                    (+test-webkit--log 'make-xwidget type title width height buffer)
                    xw)))
               ((symbol-function 'xwidget-put)
                (lambda (xw property value)
                  (setf (+test-webkit--xw-props xw)
                        (plist-put (+test-webkit--xw-props xw) property value))
                  value))
               ((symbol-function 'xwidget-get)
                (lambda (xw property) (plist-get (+test-webkit--xw-props xw) property)))
               ;; As in Emacs 31 on macOS: t still once killed.
               ((symbol-function 'xwidget-live-p) #'+test-webkit--xw-p)
               ((symbol-function 'kill-xwidget)
                (lambda (xw) (setf (+test-webkit--xw-killed xw) t) (+test-webkit--log 'kill-xwidget xw)))
               ((symbol-function 'xwidget-buffer) #'+test-webkit--xw-buffer)
               ((symbol-function 'set-xwidget-buffer)
                (lambda (xw buffer)
                  (setf (+test-webkit--xw-buffer xw) buffer)
                  (+test-webkit--log 'set-buffer xw buffer)))
               ((symbol-function 'set-xwidget-query-on-exit-flag)
                (lambda (xw flag) (+test-webkit--log 'query-on-exit xw flag)))
               ((symbol-function 'xwidget-webkit-goto-uri)
                (lambda (xw uri) (setf (+test-webkit--xw-uri xw) uri) (+test-webkit--log 'goto-uri xw uri)))
               ((symbol-function 'xwidget-webkit-uri) #'+test-webkit--xw-uri)
               ((symbol-function 'xwidget-webkit-title) #'+test-webkit--xw-title)
               ((symbol-function 'xwidget-webkit-execute-script)
                (lambda (xw script &optional callback)
                  (setq +test-webkit--scripts
                        (append +test-webkit--scripts (list (list xw script callback))))))
               ((symbol-function 'xwidget-webkit-adjust-size-to-window)
                (lambda (xw &optional window) (+test-webkit--log 'adjust xw window)))
               ((symbol-function 'xwidget-window-inside-pixel-width)
                (lambda (window) (* 7 (window-body-width window))))
               ((symbol-function 'xwidget-window-inside-pixel-height)
                (lambda (window) (* 15 (window-body-height window))))
               ((symbol-function 'xwidget-webkit-stop-loading)
                (lambda (xw)
                  (+test-webkit--log 'stop-loading xw)
                  (when +test-webkit--stop-error (error "WebKit: not loading"))))
               ((symbol-function 'xwidget-webkit-goto-history)
                (lambda (xw rel) (+test-webkit--log 'goto-history xw rel)))
               ((symbol-function 'xwidget-webkit-callback)
                (lambda (xw type) (+test-webkit--log 'xwidget-webkit-callback xw type))))
       ,@body)))

;; Cover frames (config/banner.el's, faked): symbols with their settings.
(defvar +test-webkit--frames nil "The cover frames made, latest first.")

(defun +test-webkit--fake-frame-p (frame)
  (and (symbolp frame) frame (get frame '+test-webkit-frame)))

(defmacro +test-webkit--graphic (&rest body)
  "BODY as in the GUI: views get covers, frames faked."
  (declare (indent 0))
  `(let ((+test-webkit--frames nil)
         (set-parameter (symbol-function 'set-frame-parameter))
         (set-size (symbol-function 'set-frame-size))
         (set-position (symbol-function 'set-frame-position))
         (make-visible (symbol-function 'make-frame-visible)))
     (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
               ((symbol-function '+my/banner--make-frame)
                (lambda (parent)
                  (let ((frame (make-symbol "cover")))
                    (put frame '+test-webkit-frame t)
                    (put frame 'parent parent)
                    (push frame +test-webkit--frames)
                    ;; As the real one: selecting the frame again makes
                    ;; another buffer current.
                    (set-buffer (get-buffer-create " *test-banner*"))
                    frame)))
               ((symbol-function '+my/banner--delete-frame)
                (lambda (frame) (put frame 'deleted (1+ (or (get frame 'deleted) 0)))))
               ((symbol-function 'set-frame-parameter)
                (lambda (frame parameter value)
                  (if (+test-webkit--fake-frame-p frame)
                      (put frame parameter value)
                    (funcall set-parameter frame parameter value))))
               ((symbol-function 'set-frame-size)
                (lambda (frame width height &optional pixelwise)
                  (if (+test-webkit--fake-frame-p frame)
                      (put frame 'size (list width height pixelwise))
                    (funcall set-size frame width height pixelwise))))
               ((symbol-function 'set-frame-position)
                (lambda (frame x y)
                  (if (+test-webkit--fake-frame-p frame)
                      (put frame 'position (cons x y))
                    (funcall set-position frame x y))))
               ((symbol-function 'make-frame-visible)
                (lambda (&optional frame)
                  (if (+test-webkit--fake-frame-p frame)
                      (put frame 'visible t)
                    (funcall make-visible frame)))))
       (unwind-protect (progn ,@body)
         ;; Their covers off while the frames are fake.
         (mapc #'+my/webkit--uncover +test-webkit--made)))))

;; ====== TIMERS ======

(defun +test-webkit--timers (function)
  "The pending timers (idle ones too) that will call FUNCTION."
  (seq-filter (lambda (timer) (eq (timer--function timer) function))
              (append timer-list timer-idle-list)))

(defun +test-webkit--fire (function)
  "Run the pending timers calling FUNCTION now, as if their time had come
(once: repeating ones are cancelled); return how many there were."
  (let ((timers (+test-webkit--timers function)))
    (mapc #'cancel-timer timers)
    (dolist (timer timers)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +test-webkit--due (timer)
  "Seconds until TIMER runs."
  (float-time (time-subtract (timer--time timer) nil)))

(defun +test-webkit--cancel-timers ()
  "Cancel the timers config/webkit.el left."
  (dolist (timer (append timer-list timer-idle-list))
    (let ((function (timer--function timer)))
      (when (and (symbolp function)
                 (string-prefix-p "+my/webkit" (symbol-name function)))
        (cancel-timer timer)))))

;; ====== A PAGE ======

(defvar +test-webkit--page-url "file:///tmp/test-page.html"
  "The URL the test page's views load.")

(defvar +test-webkit--urls nil
  "The windows the test page's URL was asked for, latest first.")

(defun +test-webkit--url-function (window)
  (push window +test-webkit--urls)
  (+test-webkit--log 'url window)
  +test-webkit--page-url)

(define-derived-mode +test-webkit--page-mode +my/webkit-mode "Test page"
  "A WebKit page for the tests, as a mode derived from `+my/webkit-mode' is."
  (setq-local +my/webkit-url-function #'+test-webkit--url-function))

(defmacro +test-webkit (&rest body)
  "BODY with WebKit faked, from one window on *scratch* (and again after), no
timer of config/webkit.el left."
  (declare (indent 0))
  `(+test-webkit--with-fakes
     (let ((+my/webkit--watch-timer nil)
           (+my/webkit--tidy-timer nil)
           (+test-webkit--urls nil))
       (unwind-protect (+test-with-reset
                         ;; What the first reset closed isn't the test's.
                         (setq +test-webkit--made nil +test-webkit--log nil)
                         ,@body)
         (+test-webkit--cancel-timers)))))

(defun +test-webkit--page (&optional name content)
  "A buffer NAME (default \"page\") with CONTENT, in the test page's mode."
  (let ((buffer (+test-buffer (or name "page") content)))
    (with-current-buffer buffer
      (set-buffer-modified-p nil)               ; as a file just read
      (+test-webkit--page-mode))
    buffer))

(defun +test-webkit--show (buffer &optional window)
  "Show BUFFER in WINDOW (default: the selected one) as redisplay would: its
hook, then the view started after it. Return WINDOW."
  (let ((window (or window (selected-window))))
    (set-window-buffer window buffer)
    (+my/webkit--shown-h window)
    (+test-webkit--fire #'+my/webkit--start)
    window))

(defun +test-webkit--views (buffer)
  (buffer-local-value '+my/webkit--views buffer))

(defun +test-webkit--xw (buffer window)
  "BUFFER's view for WINDOW."
  (with-current-buffer buffer (+my/webkit-xwidget window)))

(defun +test-webkit--event (xw status)
  "WebKit's load-changed event for XW, STATUS (\"load-finished\"...)."
  (list 'xwidget-event 'load-changed xw status))

;; ====== SETTINGS ======

(ert-deftest webkit/settings ()
  (should (= (default-value '+my/webkit-scroll-step) 60))
  (should (eq (default-value '+my/webkit-link-function) #'browse-url))
  (should (equal (default-value '+my/webkit-selection-script) "String(window.getSelection())"))
  (should-not (default-value '+my/webkit-url-function))
  (should-not (default-value '+my/webkit-background))
  (should-not (default-value '+my/webkit-load-functions))
  (should-not (default-value '+my/webkit-watch-function))
  ;; Set by a mode for its buffers alone.
  (dolist (var '(+my/webkit-url-function +my/webkit-background +my/webkit-load-functions
                 +my/webkit-watch-function +my/webkit-link-function +my/webkit-selection-script))
    (should (local-variable-if-set-p var))))

(ert-deftest webkit/p-needs-the-gui-and-xwidgets ()
  (should-not (+my/webkit-p))                       ; batch: no GUI
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t)))
    (should (+my/webkit-p))
    (cl-letf* ((featurep (symbol-function 'featurep))
               ((symbol-function 'featurep)
                (lambda (feature &rest args)
                  (and (not (eq feature 'xwidget-internal)) (apply featurep feature args)))))
      (should-not (+my/webkit-p)))))

;; ====== URLS ======

(ert-deftest webkit/file-url-encodes-what-a-url-cannot-hold ()
  (should (equal (+my/webkit-file-url "/tmp/plain.html") "file:///tmp/plain.html"))
  (should (equal (+my/webkit-file-url "/tmp/a b/c.pdf") "file:///tmp/a%20b/c.pdf"))
  (should (equal (+my/webkit-file-url "/tmp/C#/notes.md") "file:///tmp/C%23/notes.md"))
  (should (equal (+my/webkit-file-url "/tmp/why?.pdf") "file:///tmp/why%3F.pdf"))
  (should (equal (+my/webkit-file-url "/tmp/\"q\".pdf") "file:///tmp/%22q%22.pdf"))
  (should (equal (+my/webkit-file-url "/tmp/ü文.pdf") "file:///tmp/%C3%BC%E6%96%87.pdf"))
  ;; A `%' is the file's, not an escape already there.
  (should (equal (+my/webkit-file-url "/tmp/100%.pdf") "file:///tmp/100%25.pdf"))
  (should (equal (+my/webkit-file-url "/tmp/a%20b.pdf") "file:///tmp/a%2520b.pdf")))

(ert-deftest webkit/file-url-of-a-relative-name ()
  (let ((default-directory "/tmp/some dir/"))
    (should (equal (+my/webkit-file-url "page.html") "file:///tmp/some%20dir/page.html")))
  (should (equal (+my/webkit-file-url "~/x.html")
                 (concat "file://" (url-hexify-string (expand-file-name "~/x.html")
                                                      url-path-allowed-chars)))))

(ert-deftest webkit/url-file-decodes-and-drops-the-fragment ()
  (should (equal (+my/webkit-url-file "file:///tmp/a%20b/c.pdf") "/tmp/a b/c.pdf"))
  (should (equal (+my/webkit-url-file "file:///tmp/notes.md#install") "/tmp/notes.md"))
  (should (equal (+my/webkit-url-file "file:///tmp/%C3%BC%E6%96%87.md") "/tmp/ü文.md"))
  (should (equal (+my/webkit-url-file "file:///tmp/C%23/x.md#a%20b") "/tmp/C#/x.md"))
  (should (equal (+my/webkit-url-file "file:///tmp/plain.md") "/tmp/plain.md")))

(ert-deftest webkit/file-url-round-trips-odd-names ()
  (dolist (name '("plain.pdf" "with space.pdf" "C#/notes.md" "why?.pdf" "ü文 résumé.pdf"
                  "100%.pdf" "a%20b.pdf" "it's (1) [x] {y} & z;=+,@$!.md" "tab\there.md"))
    (let ((file (concat "/tmp/" name)))
      (should (equal (+my/webkit-url-file (+my/webkit-file-url file)) file)))))

;; ====== VIEWS ======

(ert-deftest webkit/new-view-loads-the-modes-url ()
  (+test-webkit
    (let* ((page (+test-webkit--page "my page"))
           (window (+test-webkit--show page))
           (xw (car +test-webkit--made)))
      (should (= (length +test-webkit--made) 1))
      (should (equal +test-webkit--urls (list window)))
      ;; Made for the buffer, as big as the window.
      (should (equal (+test-webkit--xw-name xw) "my page"))
      (should (eq (+test-webkit--xw-buffer xw) page))
      (should (equal (car (+test-webkit--calls 'make-xwidget))
                     (list 'webkit "my page"
                           (xwidget-window-inside-pixel-width window)
                           (xwidget-window-inside-pixel-height window)
                           page)))
      ;; The URL asked first: making the page may take a while.
      (should (equal (mapcar #'car (seq-take +test-webkit--log 2)) '(url make-xwidget)))
      ;; Closing the tab doesn't ask about it; WebKit's events are ours; home
      ;; is the page (anywhere else is a link out).
      (should (member (list xw nil) (+test-webkit--calls 'query-on-exit)))
      (should (eq (xwidget-get xw 'callback) #'+my/webkit--callback))
      (should (equal (xwidget-get xw 'home) +test-webkit--page-url))
      (should (equal (+test-webkit--calls 'goto-uri) (list (list xw +test-webkit--page-url))))
      (should (eq (+test-webkit--xw page window) xw)))))

(ert-deftest webkit/view-shown-by-an-overlay-in-its-window-alone ()
  (+test-webkit
    (let* ((page (+test-webkit--page "page" "some\ntext\n"))
           (window (+test-webkit--show page)))
      (with-current-buffer page
        (let ((view (car +my/webkit--views)))
          (should (= (length +my/webkit--views) 1))
          (should (= (overlay-start view) (point-min)))
          (should (= (overlay-end view) (point-max)))
          (should (eq (overlay-get view 'window) window))
          (should (equal (overlay-get view 'display)
                         (list 'xwidget :xwidget (car +test-webkit--made)))))))))

(ert-deftest webkit/a-view-per-window ()
  "Split, both panes show the page: a view each."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x1 (+test-webkit--xw page w1))
           (x2 (+test-webkit--xw page w2)))
      (should (= (length +test-webkit--made) 2))
      (should (and x1 x2 (not (eq x1 x2))))
      (should (equal (mapcar (lambda (view) (overlay-get view 'window)) (+test-webkit--views page))
                     (list w1 w2)))
      (should (equal +test-webkit--urls (list w2 w1)))
      ;; Each its window's size.
      (should (= (+test-webkit--xw-width x2) (xwidget-window-inside-pixel-width w2))))))

(ert-deftest webkit/views-are-the-buffers-own ()
  (+test-webkit
    (let* ((a (+test-webkit--page "A"))
           (b (+test-webkit--page "B"))
           (w1 (+test-webkit--show a))
           (w2 (+test-webkit--show b (split-window w1 nil 'right))))
      (should (= (length +test-webkit--made) 2))
      (should (equal (with-current-buffer a (+my/webkit-xwidgets)) (list (+test-webkit--xw a w1))))
      (should (equal (with-current-buffer b (+my/webkit-xwidgets)) (list (+test-webkit--xw b w2))))
      (should-not (+test-webkit--xw a w2))
      (should-not (+test-webkit--xw b w1)))))

(ert-deftest webkit/no-url-no-view ()
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (with-current-buffer page (setq-local +my/webkit-url-function nil))
      (+test-webkit--show page)
      (with-current-buffer page (setq-local +my/webkit-url-function (lambda (_window) nil)))
      (+test-webkit--show page)
      (should-not +test-webkit--made)
      (should-not (+test-webkit--views page))
      (should-not +my/webkit--watch-timer))))     ; nothing to watch

(ert-deftest webkit/start-only-in-a-window-still-showing-the-page ()
  (+test-webkit
    (let ((page (+test-webkit--page))
          (window (selected-window)))
      (+my/webkit--start page window)             ; the window shows *scratch*
      (set-window-buffer window page)
      (let ((gone (split-window window nil 'right)))
        (delete-window gone)
        (+my/webkit--start page gone))            ; a closed window
      (let ((dead (+test-buffer "dead")))
        (kill-buffer dead)
        (+my/webkit--start dead window))          ; a killed buffer
      (let ((plain (+test-buffer "plain")))
        (set-window-buffer window plain)
        (+my/webkit--start plain window))         ; not a page
      (should-not +test-webkit--made)
      ;; Shown: a view; started again: still the one.
      (set-window-buffer window page)
      (+my/webkit--start page window)
      (+my/webkit--start page window)
      (should (= (length +test-webkit--made) 1)))))

(ert-deftest webkit/views-go-edge-to-edge ()
  (+test-webkit
    (let ((fringes nil)
          (page (+test-webkit--page)))
      (cl-letf* ((set-fringes (symbol-function 'set-window-fringes))
                 ((symbol-function 'set-window-fringes)
                  (lambda (window &rest args)
                    (push (cons window args) fringes)
                    (apply set-fringes window args))))
        (let ((window (+test-webkit--show page)))
          (should (member (list window 0 0) fringes))))
      (with-current-buffer page
        (should (= left-fringe-width 0))
        (should (= right-fringe-width 0))))))

(ert-deftest webkit/shown-starts-a-view-after-redisplay ()
  (+test-webkit
    (let ((page (+test-webkit--page))
          (window (selected-window)))
      (set-window-buffer window page)
      (+my/webkit--shown-h window)
      (should-not +test-webkit--made)             ; not during redisplay
      (let ((timers (+test-webkit--timers #'+my/webkit--start)))
        (should (= (length timers) 1))
        (should (equal (timer--args (car timers)) (list page window)))
        (should (<= (+test-webkit--due (car timers)) 0.01)))
      (+test-webkit--fire #'+my/webkit--start)
      (should (= (length +test-webkit--made) 1))
      ;; Shown again (resized, a tab back): fitted, no new view.
      (setq +test-webkit--log nil)
      (+my/webkit--shown-h window)
      (should-not (+test-webkit--timers #'+my/webkit--start))
      (should (equal (+test-webkit--calls 'adjust) (list (list (car +test-webkit--made) window)))))))

(ert-deftest webkit/no-view-in-a-child-frame ()
  "A cover is a child frame showing the current buffer: no view there (one
would get a cover, and so on)."
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (set-window-buffer nil page)
      (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) (selected-frame))))
        (+my/webkit--shown-h (selected-window)))
      (should-not (+test-webkit--timers #'+my/webkit--start))
      (should-not +test-webkit--log))))

(ert-deftest webkit/fit-makes-the-view-as-big-as-its-window ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right))))
      (setq +test-webkit--log nil)
      (+my/webkit--fit-h w2)
      (should (equal (+test-webkit--calls 'adjust) (list (list (+test-webkit--xw page w2) w2))))
      ;; A window of the page without a view yet, a window of another buffer.
      (setq +test-webkit--log nil)
      (+my/webkit--fit-h (split-window w1 nil 'below))
      (set-window-buffer w1 (+test-buffer "plain"))
      (+my/webkit--fit-h w1)
      (should-not (+test-webkit--calls 'adjust)))))

(ert-deftest webkit/a-closed-view-is-one-whose-overlay-is-gone ()
  "`xwidget-live-p' stays t for a killed xwidget (Emacs 31 on macOS; faked so
here): a view is open while its overlay is in the buffer."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (window (+test-webkit--show page))
           (xw (car +test-webkit--made)))
      (with-current-buffer page
        (let ((view (+my/webkit--view window)))
          (should (eq (+my/webkit--view-xwidget view) xw))
          (+my/webkit--close view)
          (should (+test-webkit--xw-killed xw))
          (should (xwidget-live-p xw))            ; the quirk
          (should-not (overlay-buffer view))
          (should-not (+my/webkit--view-xwidget view))
          (should-not (+my/webkit--view window))
          (should-not (+my/webkit-xwidget window))
          (should-not (+my/webkit-xwidget))
          (should-not (+my/webkit-xwidgets))
          ;; Closed twice: killed once.
          (+my/webkit--close view)
          (should (= (length (+test-webkit--calls 'kill-xwidget)) 1))))
      ;; Its window shows the page again: a new view.
      (+test-webkit--show page window)
      (should (= (length +test-webkit--made) 2)))))

(ert-deftest webkit/xwidget-of-the-selected-window-else-the-latest-looked-at ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (w3 (split-window w1 nil 'below))
           (x1 (+test-webkit--xw page w1))
           (x2 (+test-webkit--xw page w2)))
      (set-window-buffer w3 (+test-buffer "plain"))
      (with-current-buffer page
        (select-window w2)
        (should (eq (+my/webkit-xwidget) x2))
        (select-window w1)
        (should (eq (+my/webkit-xwidget) x1))
        (should (eq (+my/webkit-xwidget w2) x2))
        ;; The selected window shows another buffer (the page's code run from a
        ;; timer, say): the view latest looked at.
        (select-window w3)
        (set-buffer page)
        (should (eq (+my/webkit-xwidget) x1))
        (+my/webkit--looked-at w2)
        (should (eq (+my/webkit-xwidget) x2))
        (should (eq (car +my/webkit--views) (+my/webkit--view w2)))
        ;; A window without a view changes nothing.
        (let ((views (copy-sequence +my/webkit--views)))
          (+my/webkit--looked-at w3)
          (+my/webkit--looked-at w2)
          (should (equal +my/webkit--views views)))
        (should (equal (+my/webkit-xwidgets) (list x2 x1)))))))

(ert-deftest webkit/no-view-yet ()
  (+test-webkit
    (with-current-buffer (+test-webkit--page)
      (should-not (+my/webkit-xwidget))
      (should-not (+my/webkit-xwidget (selected-window)))
      (should-not (+my/webkit-xwidgets)))))

;; SPARE VIEWS

(ert-deftest webkit/closed-windows-view-goes-to-the-next-window ()
  "Panes laid out anew, a workspace switched back to: a closed window's view
goes to the next window showing the page, none made."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x2 (+test-webkit--xw page w2)))
      (delete-window w2)
      (setq +test-webkit--log nil)
      (let ((w3 (+test-webkit--show page (split-window w1 nil 'below))))
        (should (= (length +test-webkit--made) 2))
        (should (eq (+test-webkit--xw page w3) x2))
        (should-not (+test-webkit--calls 'url))         ; nothing loaded
        ;; Fitted to its new window.
        (should (equal (+test-webkit--calls 'adjust) (list (list x2 w3))))
        (should (= (length (+test-webkit--views page)) 2))))))

(ert-deftest webkit/a-window-on-another-buffer-lends-its-view ()
  "A window showing another buffer keeps its view only while no other window
needs one."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x2 (+test-webkit--xw page w2)))
      (set-window-buffer w2 (+test-buffer "other"))
      (let ((w3 (+test-webkit--show page (split-window w1 nil 'below))))
        (should (= (length +test-webkit--made) 2))
        (should (eq (+test-webkit--xw page w3) x2))
        ;; w2 back on the page: its view's gone, a new one.
        (+test-webkit--show page w2)
        (should (= (length +test-webkit--made) 3))
        (should-not (memq (+test-webkit--xw page w2)
                          (list x2 (+test-webkit--xw page w1))))))))

(ert-deftest webkit/tab-away-and-back-keeps-the-view ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (window (+test-webkit--show page))
           (xw (+test-webkit--xw page window)))
      (set-window-buffer window (+test-buffer "other"))
      (should (eq (+test-webkit--xw page window) xw))   ; kept meanwhile
      (+test-webkit--show page window)
      (should (= (length +test-webkit--made) 1))
      (should (eq (+test-webkit--xw page window) xw))
      (should-not (+test-webkit--xw-killed xw)))))

(ert-deftest webkit/a-closed-windows-view-comes-before-a-lent-one ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (w3 (+test-webkit--show page (split-window w1 nil 'below)))
           (x2 (+test-webkit--xw page w2))
           (x3 (+test-webkit--xw page w3)))
      (set-window-buffer w2 (+test-buffer "other"))     ; could lend its view
      (delete-window w3)                                ; closed
      (let ((w4 (+test-webkit--show page (split-window w1 nil 'below))))
        (should (eq (+test-webkit--xw page w4) x3))
        (should (eq (+test-webkit--xw page w2) x2))
        (should (= (length +test-webkit--made) 3))))))

;; TIDY

(ert-deftest webkit/tidy-closes-the-views-of-closed-windows ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x1 (+test-webkit--xw page w1))
           (x2 (+test-webkit--xw page w2))
           (v2 (with-current-buffer page (+my/webkit--view w2))))
      (delete-window w2)
      (+my/webkit--tidy)
      (should (+test-webkit--xw-killed x2))
      (should-not (overlay-buffer v2))
      (should-not (+test-webkit--xw-killed x1))
      (should (equal (with-current-buffer page (+my/webkit-xwidgets)) (list x1)))
      (should (= (length (+test-webkit--views page)) 1)))))

(ert-deftest webkit/tidy-keeps-the-last-view-looked-at ()
  "All of a page's windows closed: the view latest looked at stays, for its
next window; the others close."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (main (selected-window))
           (w2 (+test-webkit--show page (split-window main nil 'right)))
           (w3 (+test-webkit--show page (split-window w2 nil 'below)))
           (x2 (+test-webkit--xw page w2))
           (x3 (+test-webkit--xw page w3)))
      (with-current-buffer page (+my/webkit--looked-at w3))
      (delete-window w2)
      (delete-window w3)
      (+my/webkit--tidy)
      (should (+test-webkit--xw-killed x2))
      (should-not (+test-webkit--xw-killed x3))
      (should (equal (with-current-buffer page (+my/webkit-xwidgets)) (list x3)))
      ;; Tidied again: still there.
      (+my/webkit--tidy)
      (should-not (+test-webkit--xw-killed x3))
      ;; The page shown again: that view, none made.
      (let ((w4 (+test-webkit--show page (split-window main nil 'right))))
        (should (eq (+test-webkit--xw page w4) x3))
        (should (= (length +test-webkit--made) 2))))))

(ert-deftest webkit/tidy-leaves-views-of-windows-on-other-buffers ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right))))
      (set-window-buffer w2 (+test-buffer "other"))
      (+my/webkit--tidy)
      (should-not (+test-webkit--calls 'kill-xwidget))
      (should (= (length (with-current-buffer page (+my/webkit-xwidgets))) 2)))))

(ert-deftest webkit/tidy-forgets-views-closed-already ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (v2 (with-current-buffer page (+my/webkit--view w2))))
      (delete-overlay v2)
      (+my/webkit--tidy)
      (should-not (+test-webkit--calls 'kill-xwidget))
      (should (equal (+test-webkit--views page) (list (with-current-buffer page (+my/webkit--view w1))))))))

(ert-deftest webkit/tidy-each-pages-buffer ()
  (+test-webkit
    (let* ((a (+test-webkit--page "A"))
           (b (+test-webkit--page "B"))
           (w1 (+test-webkit--show a))
           (wa (+test-webkit--show a (split-window w1 nil 'right)))
           (wb1 (+test-webkit--show b (split-window w1 nil 'below)))
           (wb2 (+test-webkit--show b (split-window wa nil 'below)))
           (xa (+test-webkit--xw a wa))
           (xb1 (+test-webkit--xw b wb1))
           (xb2 (+test-webkit--xw b wb2)))
      (with-current-buffer b (+my/webkit--looked-at wb2))
      (delete-window wa)
      (delete-window wb1)
      (delete-window wb2)
      (+my/webkit--tidy)
      (should (+test-webkit--xw-killed xa))      ; A has w1's
      (should (+test-webkit--xw-killed xb1))
      (should-not (+test-webkit--xw-killed xb2)) ; B's last
      (should (= (length (+test-webkit--views a)) 1))
      (should (= (length (+test-webkit--views b)) 1)))))

(ert-deftest webkit/tidy-a-second-after-windows-change ()
  (+test-webkit
    (should (memq #'+my/webkit--tidy-h (default-value 'window-buffer-change-functions)))
    ;; No page open (nothing watched): nothing to tidy.
    (+my/webkit--tidy-h (selected-frame))
    (should-not (+test-webkit--timers #'+my/webkit--tidy))
    (+test-webkit--show (+test-webkit--page))
    (+my/webkit--tidy-h (selected-frame))
    (+my/webkit--tidy-h (selected-frame))
    (let ((timers (+test-webkit--timers #'+my/webkit--tidy)))
      (should (= (length timers) 1))
      (should (eq +my/webkit--tidy-timer (car timers)))
      ;; Not at once: an answer may be on its way.
      (should (< 0.5 (+test-webkit--due (car timers)) 1.1)))
    (+test-webkit--fire #'+my/webkit--tidy)
    (should-not +my/webkit--tidy-timer)
    (+my/webkit--tidy-h (selected-frame))
    (should (= (length (+test-webkit--timers #'+my/webkit--tidy)) 1))))

;; WATCHING

(ert-deftest webkit/watching-starts-with-the-first-view ()
  (+test-webkit
    (should-not +my/webkit--watch-timer)
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (timer +my/webkit--watch-timer))
      (should (timerp timer))
      (should (memq timer timer-list))
      (should (eq (timer--function timer) #'+my/webkit--watch))
      (should (equal (timer--repeat-delay timer) 0.1))
      (+test-webkit--show page (split-window w1 nil 'right))
      (+test-webkit--show (+test-webkit--page "other page") (split-window w1 nil 'below))
      (should (eq +my/webkit--watch-timer timer))
      (should (= (length (+test-webkit--timers #'+my/webkit--watch)) 1)))))

(ert-deftest webkit/watch-stops-once-no-page-is-open ()
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (+test-webkit--show page)
      (let ((timer +my/webkit--watch-timer))
        (+my/webkit--watch)
        (should (eq +my/webkit--watch-timer timer))
        (kill-buffer page)
        (+my/webkit--watch)
        (should-not +my/webkit--watch-timer)
        (should-not (memq timer timer-list))))))

(ert-deftest webkit/watch-calls-the-modes-function-per-window ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (seen nil))
      (split-window w1 nil 'below)              ; the page, no view yet: skipped
      (with-current-buffer page
        (setq-local +my/webkit-watch-function
                    (lambda (window xwidget) (push (list window xwidget (current-buffer)) seen))))
      (with-current-buffer "*scratch*"
        (+my/webkit--watch))
      (should (= (length seen) 2))
      (should (member (list w1 (+test-webkit--xw page w1) page) seen))
      (should (member (list w2 (+test-webkit--xw page w2) page) seen)))))

(ert-deftest webkit/watch-without-a-function ()
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (+test-webkit--show page)
      (+my/webkit--watch)
      (should +my/webkit--watch-timer))))

(ert-deftest webkit/watch-the-selected-windows-view-is-looked-at ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right))))
      (should (eq (car (+test-webkit--views page)) (with-current-buffer page (+my/webkit--view w1))))
      (select-window w2)
      (+my/webkit--watch)
      (should (eq (car (+test-webkit--views page)) (with-current-buffer page (+my/webkit--view w2)))))))

(ert-deftest webkit/watch-knows-the-window-under-the-mouse ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (under 'unset))
      (with-current-buffer page
        (setq-local +my/webkit-watch-function (lambda (_window _xw) (setq under +my/webkit--under))))
      (+my/webkit--watch)                       ; batch: no mouse
      (should (null under))
      (cl-letf (((symbol-function 'mouse-pixel-position)
                 (lambda () (cons (selected-frame) (cons 50 3))))
                ((symbol-function 'window-at-x-y)
                 (lambda (x y &optional frame _no-other)
                   (should (equal (list x y frame) (list 50 3 (selected-frame))))
                   w2)))
        (+my/webkit--watch))
      (should (eq under w2))
      (should-not +my/webkit--under))))         ; only while watching

;; POINTER

(ert-deftest webkit/pointer-over-the-view-under-the-mouse ()
  (+test-webkit
    (let* ((page (+test-webkit--page "page" "line 1\nline 2\n"))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right))))
      (with-current-buffer page
        (let ((+my/webkit--under w2))
          (+my/webkit-pointer w1 'hand)           ; not under the mouse
          (should-not (get-text-property (point-min) 'pointer))
          (+my/webkit-pointer w2 'hand)
          (should (eq (get-text-property (point-min) 'pointer) 'hand))
          (should (eq (get-text-property (1- (point-max)) 'pointer) 'hand))
          (should-not (buffer-modified-p))
          (+my/webkit-pointer w2 'text)
          (should (eq (get-text-property (point-min) 'pointer) 'text))
          ;; The same shape again: the text left alone.
          (with-silent-modifications
            (remove-text-properties (point-min) (point-max) '(pointer nil)))
          (+my/webkit-pointer w2 'text)
          (should-not (get-text-property (point-min) 'pointer))
          (+my/webkit-pointer w2 'arrow)
          (should (eq (get-text-property (point-min) 'pointer) 'arrow)))
        (let ((+my/webkit--under nil))
          (+my/webkit-pointer w2 'hand)
          (should (eq (get-text-property (point-min) 'pointer) 'arrow)))))))

;; HOME

(ert-deftest webkit/point-and-window-start-stay-where-the-views-are ()
  (+test-webkit
    (let* ((page (+test-webkit--page "page" "line 1\nline 2\nline 3\n"))
           (window (+test-webkit--show page)))
      (with-current-buffer page
        (should (memq #'+my/webkit--home-h post-command-hook))
        (goto-char 10)
        (set-window-start window 8)
        (+my/webkit--home-h)
        (should (= (point) (point-min)))
        (should (= (window-start window) (point-min)))
        ;; Not the window of another buffer.
        (let ((other (+test-buffer "other" "a\nb\nc\n")))
          (set-window-buffer window other)
          (set-window-start window 3)
          (goto-char 5)
          (+my/webkit--home-h)
          (should (= (point) (point-min)))
          (should (= (window-start window) 3)))))))

;; ====== THE MODE ======

(ert-deftest webkit/mode-shows-only-the-views ()
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (with-current-buffer page
        (should (derived-mode-p 'special-mode))
        (should buffer-read-only)
        (should (equal (buffer-string) " "))     ; some text for the views
        (should (= (point) (point-min)))          ; where the views are
        (should (equal (get-text-property (point-min) 'display) ""))
        (should-not (buffer-modified-p))
        (should-not cursor-type)
        (should (equal evil-normal-state-cursor '(nil)))
        (should (equal evil-motion-state-cursor '(nil)))
        (should (= left-fringe-width 0))
        (should (= right-fringe-width 0))
        (should (eq evil-state 'normal))))
    (should (eq (evil-initial-state '+my/webkit-mode) 'normal))))

(ert-deftest webkit/mode-keeps-the-buffers-text-hidden ()
  (+test-webkit
    (let ((page (+test-webkit--page "page" "%PDF-1.4\nbytes\n")))
      (with-current-buffer page
        (should (equal (buffer-substring-no-properties (point-min) (point-max)) "%PDF-1.4\nbytes\n"))
        (should-not (text-property-not-all (point-min) (point-max) 'display ""))
        (should-not (buffer-modified-p))))))

(ert-deftest webkit/mode-hooks-are-the-buffers ()
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (with-current-buffer page
        (dolist (hook '((window-buffer-change-functions . +my/webkit--shown-h)
                        (window-size-change-functions . +my/webkit--fit-h)
                        (post-command-hook . +my/webkit--home-h)
                        (change-major-mode-hook . +my/webkit--stop)
                        (kill-buffer-hook . +my/webkit--stop)))
          (should (local-variable-p (car hook)))
          (should (memq (cdr hook) (symbol-value (car hook))))
          (should-not (memq (cdr hook) (default-value (car hook)))))))))

(ert-deftest webkit/mode-turned-on-in-a-shown-buffer-starts-its-view ()
  "No window will change buffer: started after the command, once the derived
mode has said what its page is."
  (+test-webkit
    (let ((buffer (+test-buffer "page")))
      (set-window-buffer nil buffer)
      (with-current-buffer buffer (+test-webkit--page-mode))
      (should-not +test-webkit--made)
      (should (= (+test-webkit--fire #'+my/webkit--start) 1))
      (should (= (length +test-webkit--made) 1))
      (should (eq (+test-webkit--xw buffer (selected-window)) (car +test-webkit--made))))))

(ert-deftest webkit/another-mode-closes-the-views ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right))))
      (with-current-buffer page
        (let ((+my/webkit--under w2))
          (+my/webkit-pointer w2 'hand))
        (fundamental-mode)
        (should-not +my/webkit--views)
        (should-not (overlays-in (point-min) (point-max)))
        (should-not (text-property-not-all (point-min) (point-max) 'display nil))
        (should-not (text-property-not-all (point-min) (point-max) 'pointer nil)))
      (should (= (length +test-webkit--made) 2))
      (should (seq-every-p #'+test-webkit--xw-killed +test-webkit--made)))))

(ert-deftest webkit/killing-the-buffer-closes-its-views ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page)))
      (+test-webkit--show page (split-window w1 nil 'right))
      (kill-buffer page)
      (should (= (length (+test-webkit--calls 'kill-xwidget)) 2)))))

(ert-deftest webkit/a-modes-own-hooks-see-the-views-before-they-close ()
  "The views close last: a mode keeping its place, say, still reads them."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (seen 'unset))
      (+test-webkit--show page)
      (with-current-buffer page
        (add-hook 'kill-buffer-hook (lambda () (setq seen (+my/webkit-xwidgets))) nil t))
      (kill-buffer page)
      (should (equal seen +test-webkit--made)))
    (let* ((page (+test-webkit--page))
           (seen 'unset))
      (+test-webkit--show page)
      (with-current-buffer page
        (add-hook 'change-major-mode-hook (lambda () (setq seen (+my/webkit-xwidgets))) nil t)
        (fundamental-mode))
      (should (= (length seen) 1)))))

;; ====== NO WHITE FLASH ======

(ert-deftest webkit/background ()
  (with-temp-buffer
    (should (equal (+my/webkit--background) (face-background 'default nil t)))
    (setq-local +my/webkit-background "#0d1117")
    (should (equal (+my/webkit--background) "#0d1117"))
    (setq-local +my/webkit-background (lambda () "#ffffff"))
    (should (equal (+my/webkit--background) "#ffffff"))))

(ert-deftest webkit/no-cover-in-a-terminal ()
  (+test-webkit
    (let ((made nil))
      (cl-letf (((symbol-function '+my/banner--make-frame) (lambda (_) (setq made t))))
        (+test-webkit--show (+test-webkit--page)))
      (should-not made)
      (should-not (xwidget-get (car +test-webkit--made) 'cover)))))

(ert-deftest webkit/new-view-covered-while-it-loads ()
  (+test-webkit
    (+test-webkit--graphic
      (let* ((page (+test-webkit--page))
             (window (split-window (selected-window) nil 'right)))
        (with-current-buffer page (setq-local +my/webkit-background "#123456"))
        (+test-webkit--show page window)
        (let* ((xw (+test-webkit--xw page window))
               (cover (xwidget-get xw 'cover))
               (frame (car cover))
               (edges (window-inside-pixel-edges window)))
          (should (equal +test-webkit--frames (list frame)))
          (should (eq (get frame 'parent) (window-frame window)))
          (should (equal (get frame 'background-color) "#123456"))
          ;; Over the window's text area.
          (should (equal (get frame 'size) (list (- (nth 2 edges) (nth 0 edges))
                                                 (- (nth 3 edges) (nth 1 edges))
                                                 t)))
          (should (equal (get frame 'position) (cons (nth 0 edges) (nth 1 edges))))
          (should (get frame 'visible))
          ;; Off after 2 s at most.
          (should (timerp (cdr cover)))
          (should (eq (timer--function (cdr cover)) #'+my/webkit--uncover))
          (should (equal (timer--args (cdr cover)) (list xw)))
          (should (< 1.5 (+test-webkit--due (cdr cover)) 2.1)))))))

(ert-deftest webkit/cover-in-the-pages-colour-from-a-function ()
  (+test-webkit
    (+test-webkit--graphic
      (let ((page (+test-webkit--page)))
        (with-current-buffer page (setq-local +my/webkit-background (lambda () "#abcdef")))
        (+test-webkit--show page)
        (should (equal (get (car +test-webkit--frames) 'background-color) "#abcdef"))))))

(ert-deftest webkit/cover-keeps-the-current-buffer ()
  (+test-webkit
    (+test-webkit--graphic
      (let ((page (+test-webkit--page))
            (xw (+test-webkit--xw-new)))
        (with-current-buffer page
          (+my/webkit--cover (selected-window) xw)
          (should (eq (current-buffer) page)))
        (should (xwidget-get xw 'cover))))))

(ert-deftest webkit/no-cover-without-config-banner ()
  (+test-webkit
    (+test-webkit--graphic
      (cl-letf (((symbol-function '+my/banner--make-frame) nil))
        (+test-webkit--show (+test-webkit--page)))
      (should (= (length +test-webkit--made) 1))
      (should-not (xwidget-get (car +test-webkit--made) 'cover)))))

(ert-deftest webkit/cover-goes-once-the-page-has-loaded ()
  (+test-webkit
    (+test-webkit--graphic
      (let* ((page (+test-webkit--page))
             (window (+test-webkit--show page))
             (xw (+test-webkit--xw page window))
             (cover (xwidget-get xw 'cover)))
        (let ((last-input-event (+test-webkit--event xw "load-finished")))
          (+my/webkit--callback xw 'load-changed))
        (should (eq (get (car cover) 'deleted) nil))    ; a moment to paint it
        (let ((soon (seq-find (lambda (timer) (not (eq timer (cdr cover))))
                              (+test-webkit--timers #'+my/webkit--uncover))))
          (should soon)
          (should (< (+test-webkit--due soon) 0.2))
          (cancel-timer soon)
          (apply #'+my/webkit--uncover (timer--args soon)))
        (should (= (get (car cover) 'deleted) 1))
        (should-not (xwidget-get xw 'cover))
        (should-not (memq (cdr cover) timer-list))      ; the 2 s one too
        ;; Again (the 2 s one, had it run): nothing.
        (+my/webkit--uncover xw)
        (should (= (get (car cover) 'deleted) 1))))))

(ert-deftest webkit/closing-a-covered-view-takes-its-cover-off ()
  (+test-webkit
    (+test-webkit--graphic
      (let* ((page (+test-webkit--page))
             (window (+test-webkit--show page))
             (cover (xwidget-get (+test-webkit--xw page window) 'cover)))
        (kill-buffer page)
        (should (= (get (car cover) 'deleted) 1))
        (should-not (memq (cdr cover) timer-list))))))

;; ====== LINKS OUT ======

(ert-deftest webkit/elsewhere-p ()
  (+test-webkit
    (let* ((home (+test-file "links/page.html" "<p>home</p>"))
           (other (+test-file "links/other.html" "<p>other</p>"))
           (xw (+test-webkit--xw-new)))
      (xwidget-put xw 'home (+my/webkit-file-url home))
      (dolist (url '("https://example.com/" "http://example.com" "ftp://example.com/f"
                     "mailto:me@example.com"))
        (should (+my/webkit--elsewhere-p xw url)))
      (should (+my/webkit--elsewhere-p xw (+my/webkit-file-url other)))
      (should-not (+my/webkit--elsewhere-p xw (+my/webkit-file-url home)))
      (should-not (+my/webkit--elsewhere-p xw (concat (+my/webkit-file-url home) "#install")))
      ;; The same file, said otherwise: unencoded, through a link.
      (should-not (+my/webkit--elsewhere-p xw (concat "file://" home)))
      (let ((link (+test-tmp-file "links/link.html")))
        (make-symbolic-link home link t)
        (should-not (+my/webkit--elsewhere-p xw (+my/webkit-file-url link))))
      ;; Not a link out.
      (should-not (+my/webkit--elsewhere-p xw nil))
      (should-not (+my/webkit--elsewhere-p xw "about:blank"))
      (xwidget-put xw 'home nil)
      (should-not (+my/webkit--elsewhere-p xw "https://example.com/")))))

(ert-deftest webkit/elsewhere-p-with-odd-file-names ()
  (+test-webkit
    (let* ((home (+test-file "links/odd dir #1/ü page.html" "<p>home</p>"))
           (other (+test-file "links/odd dir #1/ü other.html" "<p>other</p>"))
           (xw (+test-webkit--xw-new)))
      (xwidget-put xw 'home (+my/webkit-file-url home))
      (should-not (+my/webkit--elsewhere-p xw (+my/webkit-file-url home)))
      (should-not (+my/webkit--elsewhere-p xw (concat (+my/webkit-file-url home) "#x")))
      (should (+my/webkit--elsewhere-p xw (+my/webkit-file-url other))))))

(ert-deftest webkit/link-out-goes-to-the-browser-once ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (progn (+test-webkit--show page) (car +test-webkit--made)))
           (+test-browsed nil))
      (with-current-buffer page
        (+my/webkit--link-out xw "https://example.com/" "load-started")
        (should (equal +test-browsed '("https://example.com/")))
        (should (equal (+test-webkit--calls 'stop-loading) (list (list xw))))
        ;; WebKit's next step for the same link: not again; back to the page.
        (+my/webkit--link-out xw "https://example.com/" "load-committed")
        (should (equal +test-browsed '("https://example.com/")))
        (should (equal (+test-webkit--calls 'goto-history) (list (list xw -1))))
        ;; Another link: followed.
        (+my/webkit--link-out xw "https://example.org/" "load-started")
        (should (equal +test-browsed '("https://example.org/" "https://example.com/")))
        ;; The first again, 5 s on: followed again.
        (setq +my/webkit--followed (cons "https://example.com/" (time-subtract nil 6)))
        (+my/webkit--link-out xw "https://example.com/" "load-finished")
        (should (equal +test-browsed '("https://example.com/" "https://example.org/"
                                       "https://example.com/")))
        ;; load-finished: neither stopped nor back.
        (should (= (length (+test-webkit--calls 'stop-loading)) 2))
        (should (= (length (+test-webkit--calls 'goto-history)) 1))))))

(ert-deftest webkit/link-out-to-the-modes-function ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (progn (+test-webkit--show page) (car +test-webkit--made)))
           (got nil)
           (+test-browsed nil))
      (with-current-buffer page
        (setq-local +my/webkit-link-function (lambda (url) (push url got)))
        (setq +test-webkit--stop-error t)       ; not loading any more: no matter
        (+my/webkit--link-out xw "mailto:me@example.com" "load-started"))
      (should (equal got '("mailto:me@example.com")))
      (should-not +test-browsed))))

(ert-deftest webkit/callback-page-loaded ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (progn (+test-webkit--show page) (car +test-webkit--made)))
           (loaded nil))
      (with-current-buffer page
        (add-hook '+my/webkit-load-functions
                  (lambda (x) (push (list x (current-buffer)) loaded)) nil t))
      (with-current-buffer "*scratch*"
        (let ((last-input-event (+test-webkit--event xw "load-started")))
          (+my/webkit--callback xw 'load-changed))
        (should-not loaded)
        (should-not (+test-webkit--timers #'+my/webkit--uncover))
        (let ((last-input-event (+test-webkit--event xw "load-finished")))
          (+my/webkit--callback xw 'load-changed)))
      ;; Run in the view's buffer, with the view.
      (should (equal loaded (list (list xw page))))
      (let ((timers (+test-webkit--timers #'+my/webkit--uncover)))
        (should (= (length timers) 1))
        (should (equal (timer--args (car timers)) (list xw)))
        (should (< (+test-webkit--due (car timers)) 0.2)))
      ;; Not Emacs's own handling for loads (it renames the buffer).
      (should-not (+test-webkit--calls 'xwidget-webkit-callback))
      (should (equal (buffer-name page) "page")))))

(ert-deftest webkit/callback-link-out ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (progn (+test-webkit--show page) (car +test-webkit--made)))
           (loaded nil)
           (+test-browsed nil))
      (with-current-buffer page
        (add-hook '+my/webkit-load-functions (lambda (x) (push x loaded)) nil t))
      (setf (+test-webkit--xw-uri xw) "https://example.com/")
      (let ((last-input-event (+test-webkit--event xw "load-started")))
        (+my/webkit--callback xw 'load-changed))
      (should (equal +test-browsed '("https://example.com/")))
      (should (equal (+test-webkit--calls 'stop-loading) (list (list xw))))
      (let ((last-input-event (+test-webkit--event xw "load-finished")))
        (+my/webkit--callback xw 'load-changed))
      (should-not loaded)
      (should (equal +test-browsed '("https://example.com/"))))))

(ert-deftest webkit/callback-other-events-as-usual ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (progn (+test-webkit--show page) (car +test-webkit--made))))
      (+my/webkit--callback xw 'decide-policy)
      (should (equal (+test-webkit--calls 'xwidget-webkit-callback)
                     (list (list xw 'decide-policy)))))))

(ert-deftest webkit/callback-of-a-killed-buffer ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (progn (+test-webkit--show page) (car +test-webkit--made))))
      (kill-buffer page)
      (let ((last-input-event (+test-webkit--event xw "load-finished")))
        (+my/webkit--callback xw 'load-changed))
      (should-not (+test-webkit--timers #'+my/webkit--uncover)))))

;; ====== JAVASCRIPT ======

(ert-deftest webkit/execute-in-the-selected-windows-view ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x1 (+test-webkit--xw page w1))
           (x2 (+test-webkit--xw page w2)))
      (with-current-buffer page
        (select-window w2)
        ;; Nothing comes back: `void 0' last.
        (+my/webkit-execute "go()")
        (should (equal +test-webkit--scripts (list (list x2 "go()\n;void 0" nil))))
        (setq +test-webkit--scripts nil)
        (+my/webkit-execute "all()" t)
        (should (seq-set-equal-p (mapcar #'car +test-webkit--scripts) (list x1 x2)))
        (should (seq-every-p (lambda (run) (equal (cdr run) '("all()\n;void 0" nil)))
                             +test-webkit--scripts))
        (setq +test-webkit--scripts nil)
        (+my/webkit-execute "one()" x1)
        (should (equal +test-webkit--scripts (list (list x1 "one()\n;void 0" nil))))
        ;; The selected window shows another buffer: the view latest looked at.
        (setq +test-webkit--scripts nil)
        (let ((w3 (split-window w1 nil 'below)))
          (set-window-buffer w3 (+test-buffer "plain"))
          (select-window w3))
        (set-buffer page)
        (+my/webkit--looked-at w2)
        (+my/webkit-execute "latest()")
        (should (equal (mapcar #'car +test-webkit--scripts) (list x2)))))))

(ert-deftest webkit/execute-without-a-view ()
  (+test-webkit
    (with-current-buffer (+test-webkit--page)
      (+my/webkit-execute "go()")
      (+my/webkit-execute "go()" t)
      (should-not +test-webkit--scripts))))

(ert-deftest webkit/ask-awaits-an-answer ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (window (+test-webkit--show page))
           (xw (+test-webkit--xw page window)))
      (with-current-buffer page
        (should (eq (+my/webkit-ask "1 + 1" #'ignore) t))
        (should (equal +test-webkit--scripts (list (list xw "1 + 1" #'ignore)))))
      (with-current-buffer (+test-webkit--page "no view")
        (should-not (+my/webkit-ask "1 + 1" #'ignore))
        (should (= (length +test-webkit--scripts) 1))))))

(ert-deftest webkit/ask-a-given-view ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x1 (+test-webkit--xw page w1))
           (x2 (+test-webkit--xw page w2)))
      (with-current-buffer page
        (select-window w1)
        (should (+my/webkit-ask "a()" #'ignore x2))
        (should (+my/webkit-ask "b()" #'ignore x2))
        (should (equal +test-webkit--scripts (list (list x2 "a()" #'ignore) (list x2 "b()" #'ignore))))
        ;; Answers awaited, counted per view.
        (should (= (xwidget-get x2 'asked) 2))
        (should (+my/webkit--asked-p x2))
        (should-not (+my/webkit--asked-p x1))))))

(defvar +test-webkit--answers nil "(VALUE BUFFER ANSWERING) of each answer, latest first.")

(defun +test-webkit--answer-function (value)
  (push (list value (current-buffer) +my/webkit-answering) +test-webkit--answers))

(defun +test-webkit--answer (xw value &optional function)
  "WebKit answers VALUE from XW's page (as its event comes in)."
  (let ((last-input-event (list 'xwidget-event 'javascript-callback xw
                                (or function #'+test-webkit--answer-function) value)))
    (+my/webkit--callback xw 'javascript-callback)))

(ert-deftest webkit/answer-runs-in-the-views-buffer ()
  "An answer: its function with the value, in the view's buffer, knowing the
view that answered; one fewer awaited (never below none)."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (+test-webkit--xw page (+test-webkit--show page)))
           (+test-webkit--answers nil))
      (with-current-buffer page
        (+my/webkit-ask "a()" '+test-webkit--answer-function)
        (+my/webkit-ask "b()" '+test-webkit--answer-function))
      (with-temp-buffer
        (+test-webkit--answer xw "first")
        (should (equal +test-webkit--answers (list (list "first" page xw))))
        (should (= (xwidget-get xw 'asked) 1))
        (+test-webkit--answer xw "second")
        (+test-webkit--answer xw "unasked")         ; a script run by `+test-js', say
        (should (= (xwidget-get xw 'asked) 0))
        (should (= (length +test-webkit--answers) 3)))
      ;; Not `xwidget-webkit-callback''s (it calls the function as is).
      (should-not (+test-webkit--calls 'xwidget-webkit-callback))
      (should-not +my/webkit-answering))))

(ert-deftest webkit/answer-to-a-killed-buffer ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (+test-webkit--xw page (+test-webkit--show page)))
           (+test-webkit--answers nil))
      (kill-buffer page)
      (+test-webkit--answer xw "late")
      (should-not +test-webkit--answers))))

(ert-deftest webkit/view-closed-while-an-answer-is-on-its-way ()
  "The page's buffer killed while an answer is awaited: the view isn't killed
(it crashed Emacs) until the answer has come, in a buffer of its own meanwhile
(killing its buffer would kill it), and the answer goes nowhere."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (+test-webkit--xw page (+test-webkit--show page)))
           (+test-webkit--answers nil))
      (with-current-buffer page
        (+my/webkit-ask "slow()" '+test-webkit--answer-function))
      (kill-buffer page)
      (should-not (+test-webkit--xw-killed xw))
      (should (equal (+test-webkit--calls 'set-buffer)
                     (list (list xw (get-buffer " *webkit-closing*")))))
      (should (buffer-live-p (xwidget-buffer xw)))
      ;; At most 5 s.
      (let ((timer (car (+test-webkit--timers #'+my/webkit--kill-now))))
        (should timer)
        (should (< 4 (+test-webkit--due timer) 5.1)))
      (+test-webkit--answer xw "done")
      (should-not +test-webkit--answers)
      (should-not (+test-webkit--xw-killed xw))
      ;; Killed after this event, once.
      (should (= (+test-webkit--fire #'+my/webkit--kill-now) 2))
      (should (+test-webkit--xw-killed xw))
      (should (= (length (+test-webkit--calls 'kill-xwidget)) 1)))))

(ert-deftest webkit/view-closed-answer-never-comes ()
  "WebKit doesn't answer a script that failed: the view is killed 5 s later."
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (xw (+test-webkit--xw page (+test-webkit--show page))))
      (with-current-buffer page
        (+my/webkit-ask "throw 1" #'ignore))
      (with-current-buffer page
        (fundamental-mode))                 ; another mode: closed too
      (should-not (+test-webkit--xw-killed xw))
      (should (= (+test-webkit--fire #'+my/webkit--kill-now) 1))
      (should (+test-webkit--xw-killed xw)))))

(ert-deftest webkit/closed-window-view-waits-for-its-answer-too ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right)))
           (x2 (+test-webkit--xw page w2)))
      (with-current-buffer page
        (+my/webkit-ask "slow()" #'ignore x2))
      (delete-window w2)
      (+my/webkit--tidy)
      (should-not (+test-webkit--xw-killed x2))
      (should-not (memq x2 (with-current-buffer page (+my/webkit-xwidgets))))
      (+test-webkit--answer x2 "done")
      (+test-webkit--fire #'+my/webkit--kill-now)
      (should (+test-webkit--xw-killed x2)))))

(ert-deftest webkit/killed-views-kept-referenced-a-while ()
  "A killed view stays referenced for 10 s (an answer to one the garbage
collector took would crash Emacs), then not."
  (+test-webkit
    (let* ((+my/webkit--killed nil)
           (page (+test-webkit--page))
           (xw (+test-webkit--xw page (+test-webkit--show page)))
           (old (+test-webkit--xw-new)))
      (push (cons old (- (float-time) 11)) +my/webkit--killed)
      (kill-buffer page)
      (should (+test-webkit--xw-killed xw))
      (should (assq xw +my/webkit--killed))
      (should-not (assq old +my/webkit--killed))
      ;; Once.
      (+my/webkit--kill-now xw)
      (should (= (length (+test-webkit--calls 'kill-xwidget)) 1))
      (should (= (length +my/webkit--killed) 1)))))

(ert-deftest webkit/wait ()
  (let ((n 0))
    (should (eq (+my/webkit-wait (lambda () (and (> (cl-incf n) 3) 'done)) 5) 'done))
    (should (= n 4)))
  (let ((start (float-time)))
    (should-not (+my/webkit-wait #'ignore 0.2))
    (should (< 0.15 (- (float-time) start) 1))))

;; ====== THE BUFFER'S TEXT ======

(ert-deftest webkit/set-text-under-the-views ()
  (+test-webkit
    (let* ((page (+test-webkit--page "page" "old text"))
           (w1 (+test-webkit--show page))
           (w2 (+test-webkit--show page (split-window w1 nil 'right))))
      (with-current-buffer page
        (setq +my/webkit--pointer 'hand)
        (with-silent-modifications
          (let ((inhibit-read-only t))
            (put-text-property (point-min) (point-max) 'pointer 'hand)))
        (should-not (buffer-modified-p))
        (+my/webkit-set-text "a longer, new text\nover two lines")
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       "a longer, new text\nover two lines"))
        ;; Hidden, the pointer kept, all of it under each view.
        (should-not (text-property-not-all (point-min) (point-max) 'display ""))
        (should-not (text-property-not-all (point-min) (point-max) 'pointer 'hand))
        (dolist (view +my/webkit--views)
          (should (= (overlay-start view) (point-min)))
          (should (= (overlay-end view) (point-max))))
        (should (= (point) (point-min)))
        (dolist (window (list w1 w2))
          (should (= (window-start window) (point-min)))
          (should (= (window-point window) (point-min))))
        (should (buffer-modified-p))
        (should buffer-read-only)
        ;; Shorter: still all of it.
        (+my/webkit-set-text "x")
        (dolist (view +my/webkit--views)
          (should (= (overlay-end view) 2)))
        (should (equal (get-text-property 1 'display) ""))))))

(ert-deftest webkit/set-text-without-a-pointer-yet ()
  (+test-webkit
    (with-current-buffer (+test-webkit--page "page" "old")
      (+my/webkit-set-text "new")
      (should-not (get-text-property 1 'pointer))
      (should (equal (get-text-property 1 'display) "")))))

;; ====== DOWNLOADS ======

(defmacro +test-webkit--with-cdn (files &rest body)
  "BODY with `url-copy-file' copying from a fake CDN of FILES ((URL . BYTES)...);
the URLs asked for in `downloads', oldest first."
  (declare (indent 1))
  `(let ((downloads nil))
     (cl-letf (((symbol-function 'url-copy-file)
                (lambda (url newname &optional ok-if-already-exists &rest _)
                  (setq downloads (append downloads (list url)))
                  (let ((bytes (cdr (assoc url ,files))))
                    (unless bytes (signal 'file-error (list "Not found" url)))
                    (when (and (file-exists-p newname) (not ok-if-already-exists))
                      (signal 'file-already-exists (list newname)))
                    (let ((coding-system-for-write 'no-conversion))
                      (with-temp-file newname
                        (set-buffer-multibyte nil)
                        (insert bytes)))
                    t))))
       ,@body)))

(defun +test-webkit--sha256 (bytes)
  (secure-hash 'sha256 bytes))

(ert-deftest webkit/install-checks-each-file-into-its-folder ()
  (let* ((dir (file-name-as-directory (+test-tmp-file "install/lib-1.0")))
         (binary (apply #'unibyte-string (number-sequence 0 255)))
         (files `(("lib.js" "https://cdn.example/lib.js" ,(+test-webkit--sha256 "var lib;"))
                  ("assets/font.woff2" "https://cdn.example/assets/font.woff2"
                   ,(+test-webkit--sha256 binary)))))
    (should-not (+my/webkit-installed-p files dir))
    (+test-clear-messages)
    (+test-webkit--with-cdn `(("https://cdn.example/lib.js" . "var lib;")
                              ("https://cdn.example/assets/font.woff2" . ,binary))
      (+my/webkit-install "Lib" "1.0" files dir)
      (should (equal downloads '("https://cdn.example/lib.js" "https://cdn.example/assets/font.woff2"))))
    (should (+my/webkit-installed-p files dir))
    (should (equal (with-temp-buffer
                     (set-buffer-multibyte nil)
                     (insert-file-contents-literally (expand-file-name "assets/font.woff2" dir))
                     (buffer-string))
                   binary))
    (should-not (directory-files-recursively dir "\\.part\\'"))
    (should (= (+test-messages "^Downloading Lib: lib\\.js\\.\\.\\.$") 1))
    (should (= (+test-messages "^Downloading Lib: assets/font\\.woff2\\.\\.\\.$") 1))
    (should (= (+test-messages (concat "^Lib 1\\.0 installed in " (regexp-quote dir) "$")) 1))
    ;; Again: replaced.
    (+test-webkit--with-cdn `(("https://cdn.example/lib.js" . "var lib;")
                              ("https://cdn.example/assets/font.woff2" . ,binary))
      (+my/webkit-install "Lib" "1.0" files dir)
      (should (= (length downloads) 2)))))

(ert-deftest webkit/install-refuses-a-wrong-file ()
  (let* ((dir (file-name-as-directory (+test-tmp-file "install/wrong")))
         (files `(("a.js" "https://cdn.example/a.js" ,(+test-webkit--sha256 "var a;"))
                  ("b/c.js" "https://cdn.example/c.js" ,(+test-webkit--sha256 "var c;")))))
    (+test-webkit--with-cdn '(("https://cdn.example/a.js" . "var a;")
                              ("https://cdn.example/c.js" . "var evil;"))
      (let ((err (should-error (+my/webkit-install "Lib" "1" files dir))))
        (should (string-match-p
                 "\\`Lib: https://cdn\\.example/c\\.js isn.t the file expected (SHA-256 differs), not installed\\'"
                 (error-message-string err)))))
    (should-not (file-exists-p (expand-file-name "b/c.js" dir)))
    (should-not (file-exists-p (expand-file-name "b/c.js.part" dir)))
    (should-not (+my/webkit-installed-p files dir))
    ;; Offline: the download's error.
    (+test-webkit--with-cdn nil
      (should-error (+my/webkit-install "Lib" "1" files dir) :type 'file-error))))

(ert-deftest webkit/title-json ()
  (let ((xw (+test-webkit--xw-new)))
    (+test-webkit--with-fakes
      (should-not (+my/webkit-title-json xw "pdfx "))          ; no title yet
      (setf (+test-webkit--xw-title xw) "Some page")
      (should-not (+my/webkit-title-json xw "pdfx "))
      (setf (+test-webkit--xw-title xw)
            "pdfx {\"page\":3,\"dark\":false,\"place\":null,\"action\":{\"name\":\"print\",\"n\":2},\"t\":\"ü\"}")
      (should (equal (+my/webkit-title-json xw "pdfx ")
                     '(:page 3 :dark nil :place nil :action (:name "print" :n 2) :t "ü")))
      (should-not (+my/webkit-title-json xw "other "))
      (setf (+test-webkit--xw-title xw) "pdfx {broken")
      (should-not (+my/webkit-title-json xw "pdfx "))
      (setf (+test-webkit--xw-title xw) "xpdfx {\"page\":1}")
      (should-not (+my/webkit-title-json xw "pdfx "))
      (should-not (+my/webkit-title-json nil "pdfx "))
      (cl-letf (((symbol-function 'xwidget-webkit-title) (lambda (_) (error "Gone"))))
        (should-not (+my/webkit-title-json xw "pdfx "))))))

;; ====== CLICKS ======

(ert-deftest webkit/click-selects-the-window ()
  (+test-webkit
    (let* ((w1 (selected-window))
           (w2 (split-window w1 nil 'right))
           (gone (split-window w2 nil 'below)))
      (delete-window gone)
      (should (commandp #'+my/webkit-mouse-select))
      (+my/webkit-mouse-select (list 'down-mouse-1 (list w2 1 '(0 . 0) 0)))
      (should (eq (selected-window) w2))
      (+my/webkit-mouse-select (list 'down-mouse-1 (list gone 1 '(0 . 0) 0)))
      (should (eq (selected-window) w2)))))

(ert-deftest webkit/clicks-are-webkits ()
  (let ((map (make-sparse-keymap))
        (ignored '([mouse-1] [drag-mouse-1] [double-down-mouse-1] [double-mouse-1]
                   [triple-down-mouse-1] [triple-mouse-1])))
    (+my/webkit-bind-clicks map)
    (should (eq (lookup-key map [down-mouse-1]) #'+my/webkit-mouse-select))
    (dolist (key ignored)
      (should (eq (lookup-key map key) #'ignore)))
    ;; Evil's states too: no visual selection of Emacs's own.
    (dolist (state '(normal motion visual))
      (let ((aux (evil-get-auxiliary-keymap map state)))
        (should (eq (lookup-key aux [down-mouse-1]) #'+my/webkit-mouse-select))
        (dolist (key ignored)
          (should (eq (lookup-key aux key) #'ignore)))))))

;; ====== COMMANDS ======

(defun +test-webkit--script-of (function &rest args)
  "The script FUNCTION run (with ARGS), in the current buffer's view."
  (setq +test-webkit--scripts nil)
  (apply function args)
  (should (= (length +test-webkit--scripts) 1))
  (nth 1 (car +test-webkit--scripts)))

(ert-deftest webkit/scroll-commands ()
  (+test-webkit
    (let ((page (+test-webkit--page)))
      (+test-webkit--show page)
      (with-current-buffer page
        (should (equal (+test-webkit--script-of #'+my/webkit-scroll-down) "window.scrollBy(0, 60)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-scroll-down 3) "window.scrollBy(0, 180)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-scroll-up) "window.scrollBy(0, -60)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-scroll-up 2) "window.scrollBy(0, -120)\n;void 0"))
        (let ((+my/webkit-scroll-step 10))
          (should (equal (+test-webkit--script-of #'+my/webkit-scroll-down 2) "window.scrollBy(0, 20)\n;void 0")))
        (let ((current-prefix-arg 4))
          (should (equal (+test-webkit--script-of #'call-interactively #'+my/webkit-scroll-down)
                         "window.scrollBy(0, 240)\n;void 0")))
        (should (equal (+test-webkit--script-of #'+my/webkit-half-screen-down) "window.scrollBy(0, innerHeight / 2)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-half-screen-up) "window.scrollBy(0, -innerHeight / 2)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-screen-down) "window.scrollBy(0, innerHeight * 0.9)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-screen-up) "window.scrollBy(0, -innerHeight * 0.9)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-top) "window.scrollTo(0, 0)\n;void 0"))
        (should (equal (+test-webkit--script-of #'+my/webkit-bottom)
                       "window.scrollTo(0, document.documentElement.scrollHeight)\n;void 0")))
      (dolist (command '(+my/webkit-scroll-down +my/webkit-scroll-up +my/webkit-half-screen-down
                         +my/webkit-half-screen-up +my/webkit-screen-down +my/webkit-screen-up
                         +my/webkit-top +my/webkit-bottom +my/webkit-copy))
        (should (commandp command))))))

(ert-deftest webkit/copy-asks-the-page-for-its-selection ()
  (+test-webkit
    (let* ((page (+test-webkit--page))
           (window (+test-webkit--show page))
           (xw (+test-webkit--xw page window)))
      (with-current-buffer page
        (+my/webkit-copy)
        ;; Its answer to a symbol (a closure could be gone by then).
        (should (equal +test-webkit--scripts
                       (list (list xw "String(window.getSelection())" '+my/webkit-copied))))
        (setq-local +my/webkit-selection-script "mySelection()")
        (+my/webkit-copy)
        (should (equal (nth 1 (car (last +test-webkit--scripts))) "mySelection()"))))))

(ert-deftest webkit/copied-text-goes-to-the-kill-ring-and-clipboard ()
  (let* ((kill-ring nil)
         (kill-ring-yank-pointer nil)
         (cut nil)
         (interprogram-cut-function (lambda (text) (push text cut)))
         (interprogram-paste-function nil))
    (+test-clear-messages)
    (+my/webkit-copied "Hello ü")
    (should (equal kill-ring '("Hello ü")))
    (should (equal cut '("Hello ü")))
    (should (= (+test-messages "^Copied 7 characters$") 1))
    (dolist (nothing '("" "  \n\t" nil 42))
      (+my/webkit-copied nothing))
    (should (equal kill-ring '("Hello ü")))
    (should (= (+test-messages "^No text selected \\[4 times\\]$") 1))))
