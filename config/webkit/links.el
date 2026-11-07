;;; $DOOMDIR/config/webkit/links.el -*- lexical-binding: t; -*-
;; Links out of a page, to the browser. Loaded from config/webkit.el.

;; LINKS OUT
;; A link elsewhere than the view's page would take WebKit away from it: its
;; first step (load-started) is stopped and the link given to
;; `+my/webkit-link-function' (the browser); had it gone further, WebKit goes
;; back to the page.
(defvar-local +my/webkit--followed nil
  "(URL . TIME): the link out of the page last followed.")

(defun +my/webkit--elsewhere-p (xwidget url)
  "Non-nil if XWIDGET at URL has left its page (by the file, not the URL text:
WebKit may encode it otherwise)."
  (let ((home (xwidget-get xwidget 'home)))
    (and (stringp url) home
         (or (string-match-p "\\`\\(?:https?\\|ftp\\|mailto\\):" url)
             (and (string-prefix-p "file:" url)
                  (not (equal (file-truename (+my/webkit-url-file url))
                              (file-truename (+my/webkit-url-file home)))))))))

(defun +my/webkit--link-out (xwidget url status)
  "WebKit is following a link out of the page, to URL (see above)."
  (unless (and (equal (car +my/webkit--followed) url)
               (< (float-time (time-since (cdr +my/webkit--followed))) 5))
    (setq +my/webkit--followed (cons url (current-time)))
    (funcall +my/webkit-link-function url))
  (if (equal status "load-started")
      (ignore-errors (xwidget-webkit-stop-loading xwidget))
    (when (equal status "load-committed")
      (xwidget-webkit-goto-history xwidget -1))))

(defun +my/webkit--callback (xwidget event-type)
  "WebKit's events: the page has loaded (see NO WHITE FLASH in views.el,
`+my/webkit-load-functions'), links out of it (see above); others as usual
(not `xwidget-webkit-callback' for loads: it renames the buffer after the
page)."
  (let ((buffer (xwidget-buffer xwidget)))
    (cond ((eq event-type 'javascript-callback)
           (+my/webkit--answered xwidget (nth 3 last-input-event) (nth 4 last-input-event)))
          ((not (eq event-type 'load-changed))
           (xwidget-webkit-callback xwidget event-type))
          ((buffer-live-p buffer)
           (with-current-buffer buffer
             (let ((status (nth 3 last-input-event))
                   (url (xwidget-webkit-uri xwidget)))
               (cond ((+my/webkit--elsewhere-p xwidget url)
                      (+my/webkit--link-out xwidget url status))
                     ((equal status "load-finished")
                      ;; A moment for WebKit to paint it.
                      (run-at-time 0.05 nil #'+my/webkit--uncover xwidget)
                      (run-hook-with-args '+my/webkit-load-functions xwidget)))))))))
