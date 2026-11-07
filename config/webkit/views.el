;;; $DOOMDIR/config/webkit/views.el -*- lexical-binding: t; -*-
;; A view per window, with no white flash. Loaded from config/webkit.el.

;; VIEWS
;; A WebKit view is drawn in one window only: on macOS, Emacs says "You can't
;; share an xwidget (webkit2) among windows" and leaves the others empty. So
;; each window showing the buffer has a view of its own (a page of its own),
;; shown in that window alone by an overlay over the buffer whose `window'
;; property is that window (as doc-view and pdf-tools show a page per window):
;; split, both panes show the page, scrolled apart. A view starts once its
;; window shows the buffer (WebKit only draws on screen), loading the URL
;; `+my/webkit-url-function' gives. A window gets the view of a closed window
;; first (panes tiling lays out anew, a workspace switched back to), else of a
;; window showing another buffer, else a new one: a window that shows another
;; buffer keeps its view for when it shows the page again (a tab away and
;; back) only while no other window needs it. A second after windows come or
;; go, views of closed windows are closed, but for the buffer's last one (for
;; its next window).

(defvar-local +my/webkit--views nil
  "The buffer's views, overlays, the one latest looked at first (see VIEWS).")

(defun +my/webkit-p ()
  "Non-nil if WebKit pages can show here: the GUI, an Emacs with xwidgets."
  (and (display-graphic-p) (featurep 'xwidget-internal)))

(defun +my/webkit--view-xwidget (view)
  "VIEW's xwidget, while it's open: closed, its overlay is out of the buffer
(`xwidget-live-p' stays t for a killed xwidget, in Emacs 31 on macOS)."
  (and (overlay-buffer view) (overlay-get view '+my/webkit)))

(defun +my/webkit--view (window)
  "The buffer's view (an overlay) for WINDOW, if it has one open."
  (seq-find (lambda (view)
              (and (eq (overlay-get view 'window) window)
                   (+my/webkit--view-xwidget view)))
            +my/webkit--views))

(defun +my/webkit-xwidget (&optional window)
  "The buffer's WebKit view for WINDOW; without WINDOW, the selected window's,
else the one latest looked at. Nil before there's one."
  (when-let* ((view (if window
                        (+my/webkit--view window)
                      (or (+my/webkit--view (selected-window))
                          (seq-find #'+my/webkit--view-xwidget +my/webkit--views)))))
    (+my/webkit--view-xwidget view)))

(defun +my/webkit-xwidgets ()
  "The buffer's WebKit views, all of them."
  (delq nil (mapcar #'+my/webkit--view-xwidget +my/webkit--views)))

(defun +my/webkit--looked-at (window)
  "WINDOW's view first: the one latest looked at (see above)."
  (when-let* ((view (+my/webkit--view window)))
    (unless (eq view (car +my/webkit--views))
      (setq +my/webkit--views (cons view (delq view +my/webkit--views))))))

(defvar +my/webkit--killed nil
  "Views killed lately, kept from the garbage collector a while (see
JAVASCRIPT): (XWIDGET . TIME)...")

(defun +my/webkit--kill-now (xwidget)
  "Kill XWIDGET's view (once), kept referenced for 10 s after (see
JAVASCRIPT)."
  (unless (xwidget-get xwidget '+my/webkit-killed)
    (xwidget-put xwidget '+my/webkit-killed t)
    (let ((now (float-time)))
      (setq +my/webkit--killed
            (cons (cons xwidget now)
                  (seq-filter (lambda (killed) (< (- now (cdr killed)) 10))
                              +my/webkit--killed))))
    (when (xwidget-live-p xwidget)
      (kill-xwidget xwidget))))

(defun +my/webkit--kill (xwidget)
  "Kill XWIDGET's view; while an answer from its page is on its way, once it
has come, 5 s at most (see JAVASCRIPT in js.el), the view in a buffer of its own
meanwhile (killing a buffer kills its views)."
  (cond ((not (and (+my/webkit--asked-p xwidget) (fboundp 'set-xwidget-buffer)))
         (+my/webkit--kill-now xwidget))
        ((not (xwidget-get xwidget '+my/webkit-closing))
         (xwidget-put xwidget '+my/webkit-closing t)
         (set-xwidget-buffer xwidget (get-buffer-create " *webkit-closing*"))
         (run-at-time 5 nil #'+my/webkit--kill-now xwidget))))

(defun +my/webkit--close (view)
  "Close VIEW: its xwidget, its overlay (see above)."
  (when-let* ((xwidget (+my/webkit--view-xwidget view)))
    (+my/webkit--uncover xwidget)
    (+my/webkit--kill xwidget))
  (delete-overlay view))

(defvar +my/webkit--tidy-timer nil)

(defun +my/webkit--tidy ()
  "Close the views of closed windows, but for each buffer's last (see above)."
  (setq +my/webkit--tidy-timer nil)
  (dolist (buffer (buffer-list))
    (when (buffer-local-value '+my/webkit--views buffer)
      (with-current-buffer buffer
        (let* ((open (seq-filter #'+my/webkit--view-xwidget +my/webkit--views))
               (closed (seq-remove (lambda (view) (window-live-p (overlay-get view 'window)))
                                   open))
               ;; All closed: the latest looked at stays, for the next window.
               (kept (and (= (length closed) (length open)) (car open))))
          (dolist (view +my/webkit--views)
            (when (or (not (memq view open))
                      (and (memq view closed) (not (eq view kept))))
              (+my/webkit--close view)))
          (setq +my/webkit--views (seq-filter #'overlay-buffer +my/webkit--views)))))))

(defun +my/webkit--tidy-h (_frame)
  "Windows came or went: close the views of closed windows in a second (see
above), not at once: an answer may still be on its way (see JAVASCRIPT in
js.el)."
  (when (and +my/webkit--watch-timer (not +my/webkit--tidy-timer))
    (setq +my/webkit--tidy-timer (run-at-time 1 nil #'+my/webkit--tidy))))

(add-hook 'window-buffer-change-functions #'+my/webkit--tidy-h)

(defun +my/webkit--new-view (window)
  "Open a WebKit view for WINDOW, covered while it loads (see above)."
  ;; The URL first: making the page may take a while (a download, say), and
  ;; the cover only lasts 2 s.
  (when-let* ((url (and +my/webkit-url-function
                        (funcall +my/webkit-url-function window))))
    (let ((xwidget (make-xwidget 'webkit (buffer-name)
                                 (xwidget-window-inside-pixel-width window)
                                 (xwidget-window-inside-pixel-height window)
                                 nil (current-buffer)))
          (view (make-overlay (point-min) (point-max))))
      ;; Closing the tab doesn't ask "Buffer has xwidgets; kill it?".
      (set-xwidget-query-on-exit-flag xwidget nil)
      (xwidget-put xwidget 'callback #'+my/webkit--callback)
      ;; Anywhere else is a link out of the page (see LINKS OUT in links.el).
      (xwidget-put xwidget 'home url)
      (overlay-put view '+my/webkit xwidget)
      (overlay-put view 'window window)
      (overlay-put view 'display (list 'xwidget :xwidget xwidget))
      ;; Last: the one latest looked at stays first until this one is.
      (setq +my/webkit--views (append +my/webkit--views (list view)))
      (+my/webkit--cover window xwidget)
      (xwidget-webkit-goto-uri xwidget url))))

(defun +my/webkit--start (buffer window)
  "Give WINDOW a view of BUFFER's page if it still shows it: a spare one, else
a new one (see above)."
  (when (and (buffer-live-p buffer) (window-live-p window)
             (eq (window-buffer window) buffer))
    (with-current-buffer buffer
      (when (and (derived-mode-p '+my/webkit-mode)
                 (not (+my/webkit--view window)))
        ;; Edge to edge: no fringes (also buffer-local, for other windows).
        (set-window-fringes window 0 0)
        (let* ((open (seq-filter #'+my/webkit--view-xwidget +my/webkit--views))
               (spare (or (seq-find (lambda (view)
                                      (not (window-live-p (overlay-get view 'window))))
                                    open)
                          (seq-find (lambda (view)
                                      (not (eq (window-buffer (overlay-get view 'window))
                                               buffer)))
                                    open))))
          (if (not spare)
              (+my/webkit--new-view window)
            (overlay-put spare 'window window)
            (xwidget-webkit-adjust-size-to-window (+my/webkit--view-xwidget spare) window)))
        (when (and +my/webkit--views (not (timerp +my/webkit--watch-timer)))
          (setq +my/webkit--watch-timer (run-with-timer 0.1 0.1 #'+my/webkit--watch)))))))

(defun +my/webkit--fit-h (window)
  "Make WINDOW's WebKit view as big as it (a view keeps the size it was made
with)."
  (with-current-buffer (window-buffer window)
    (when-let* ((xwidget (+my/webkit-xwidget window)))
      (xwidget-webkit-adjust-size-to-window xwidget window))))

(defun +my/webkit--shown-h (window)
  "WINDOW shows the page: its view, fitted to it; or one for it after this
redisplay (the cover is a frame, not made during redisplay; see above). Not
in a child frame: a cover (see NO WHITE FLASH) is one, showing the current
buffer as it's made, and a view in it would get a cover, and so on (a test
Emacs crashed closing the views that made)."
  (unless (frame-parent (window-frame window))
    (with-current-buffer (window-buffer window)
      (if (+my/webkit--view window)
          (+my/webkit--fit-h window)
        (run-at-time 0 nil #'+my/webkit--start (current-buffer) window)))))

(defun +my/webkit--home-h ()
  "Keep point and the window's start at the buffer's start, where the views
are: moved, the window scrolled them away."
  (unless (= (point) (point-min))
    (goto-char (point-min)))
  (unless (or (not (eq (window-buffer) (current-buffer)))
              (= (window-start) (point-min)))
    (set-window-start nil (point-min))))

(defun +my/webkit--stop ()
  "Close the buffer's views (another mode, the buffer killed)."
  (mapc #'+my/webkit--close +my/webkit--views)
  (setq +my/webkit--views nil)
  (with-silent-modifications
    (remove-text-properties (point-min) (point-max) '(display nil pointer nil))))

;; NO WHITE FLASH
;; WebKit's view is white until its page has loaded. A view only starts once
;; its window shows the page (nothing shown until then, in the theme's colour),
;; under a borderless frame (config/childframe.el) in the page's background
;; colour (`+my/webkit-background'): it goes once WebKit says the page has
;; loaded, or after 2 s (e.g. offline).
(defun +my/webkit--uncover (xwidget)
  "Take the cover off XWIDGET's view."
  (when-let* ((cover (xwidget-get xwidget 'cover)))
    (xwidget-put xwidget 'cover nil)
    (when (timerp (cdr cover)) (cancel-timer (cdr cover)))
    (+my/childframe-delete (car cover))))

(defun +my/webkit--background ()
  "The page's background colour (see `+my/webkit-background')."
  (let ((background +my/webkit-background))
    (cond ((stringp background) background)
          ((functionp background) (funcall background))
          (t (face-background 'default nil t)))))

(defun +my/webkit--cover (window xwidget)
  "Cover WINDOW's text area in the page's background colour while XWIDGET
loads there (see above). The current buffer kept: making the frame selects
the selected one again, which makes its window's buffer current."
  (when (and (fboundp '+my/childframe-make)
             (display-graphic-p (window-frame window)))
    (let ((frame (save-current-buffer
                   (+my/childframe-make (window-frame window) "+my/webkit-cover")))
          (edges (window-inside-pixel-edges window))
          (frame-resize-pixelwise t))
      (set-frame-parameter frame 'background-color (+my/webkit--background))
      (set-frame-size frame (- (nth 2 edges) (nth 0 edges))
                      (- (nth 3 edges) (nth 1 edges)) t)
      (set-frame-position frame (nth 0 edges) (nth 1 edges))
      (make-frame-visible frame)
      (xwidget-put xwidget 'cover
                   (cons frame (run-at-time 2 nil #'+my/webkit--uncover xwidget))))))
