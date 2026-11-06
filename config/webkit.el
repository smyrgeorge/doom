;;; $DOOMDIR/config/webkit.el -*- lexical-binding: t; -*-
;; Web pages inside Emacs, in WebKit (xwidgets): what the PDF viewer
;; (config/pdf.el) and the Markdown preview (config/markdown.el)
;; share. Loaded from config.el, before them.

;; ====== VARIABLES ======

;; WEBKIT PAGES
;; A buffer in `+my/webkit-mode', or a mode derived from it, shows a web page
;; in WebKit (Emacs's xwidgets; emacs-plus has them), with what a page inside
;; Emacs needs, so that a mode only says what its page is:
;; - a view per window showing the buffer: split, both panes show the page
;;   (see VIEWS);
;; - no white flash while a view loads (see NO WHITE FLASH);
;; - links out of the page open in the browser (see LINKS OUT);
;; - JavaScript run in the selected window's view or in all of them, answers
;;   awaited without crashing Emacs (see JAVASCRIPT);
;; - what the page says in its title, read every 0.1 s, as a page can't call
;;   Emacs (see WATCHING), e.g. the mouse pointer it wants (see POINTER);
;; - clicks are WebKit's (selecting text, links): Emacs only selects the
;;   window (see CLICKS);
;; - scrolling and copying for pages with no keys of their own (see COMMANDS).
;; A mode derived from it sets, in its body, the variables below (buffer-local).
(defvar-local +my/webkit-url-function nil
  "Function of the window a new view is for (see VIEWS), returning the URL the
view loads: it may write the page first, e.g. as things are now. Nil: no view.")

(defvar-local +my/webkit-background nil
  "The page's background colour, for the cover while a view loads (see NO
WHITE FLASH): a colour, a function returning one, or nil for the theme's.")

(defvar-local +my/webkit-load-functions nil
  "Functions of a view's xwidget, called once its page has loaded.")

(defvar-local +my/webkit-watch-function nil
  "Function of a window showing the buffer and its view's xwidget, called
every 0.1 s while the window is on screen (see WATCHING).")

(defvar-local +my/webkit-link-function #'browse-url
  "Function of a URL a link out of the page goes to (see LINKS OUT).")

(defvar-local +my/webkit-selection-script "String(window.getSelection())"
  "JavaScript whose value is the page's selected text (see `+my/webkit-copy').")

(defvar +my/webkit-scroll-step 60
  "Pixels j / k scroll a page (see COMMANDS).")

;; ====== CODE ======

(defvar-local +my/webkit--views nil
  "The buffer's views, overlays, the one latest looked at first (see VIEWS).")

(defvar +my/webkit--watch-timer nil
  "Every 0.1 s while a page is open (see WATCHING).")

(defun +my/webkit-p ()
  "Non-nil if WebKit pages can show here: the GUI, an Emacs with xwidgets."
  (and (display-graphic-p) (featurep 'xwidget-internal)))

(defun +my/webkit-file-url (file)
  "FILE's file:// URL. Spaces and such encoded: Emacs's macOS WebKit doesn't
check that a URL is valid. A `%' too: in a file's name it's not an escape
(\"a%20b.pdf\" isn't \"a b.pdf\")."
  (require 'url-util)
  (let ((allowed (copy-sequence url-path-allowed-chars)))
    (aset allowed ?% nil)
    (concat "file://" (url-hexify-string (expand-file-name file) allowed))))

(defun +my/webkit-url-file (url)
  "The file a file:// URL names (without its #fragment)."
  (require 'url-parse)
  (decode-coding-string (url-unhex-string (url-filename (url-generic-parse-url url)))
                        'utf-8))

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

(defun +my/webkit--close (view)
  "Close VIEW: its xwidget, its overlay (see above)."
  (when-let* ((xwidget (+my/webkit--view-xwidget view)))
    (+my/webkit--uncover xwidget)
    (when (xwidget-live-p xwidget)
      (kill-xwidget xwidget)))
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
above), not at once: an answer may still be on its way (see JAVASCRIPT)."
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
      ;; Anywhere else is a link out of the page (see LINKS OUT).
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
;; under a borderless frame in the page's background colour
;; (`+my/webkit-background'), like the notices' (config/banner.el): it goes
;; once WebKit says the page has loaded, or after 2 s (e.g. offline).
(defun +my/webkit--uncover (xwidget)
  "Take the cover off XWIDGET's view."
  (when-let* ((cover (xwidget-get xwidget 'cover)))
    (xwidget-put xwidget 'cover nil)
    (when (timerp (cdr cover)) (cancel-timer (cdr cover)))
    (+my/banner--delete-frame (car cover))))

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
  (when (and (fboundp '+my/banner--make-frame)
             (display-graphic-p (window-frame window)))
    (let ((frame (save-current-buffer
                   (+my/banner--make-frame (window-frame window))))
          (edges (window-inside-pixel-edges window))
          (frame-resize-pixelwise t))
      (set-frame-parameter frame 'background-color (+my/webkit--background))
      (set-frame-size frame (- (nth 2 edges) (nth 0 edges))
                      (- (nth 3 edges) (nth 1 edges)) t)
      (set-frame-position frame (nth 0 edges) (nth 1 edges))
      (make-frame-visible frame)
      (xwidget-put xwidget 'cover
                   (cons frame (run-at-time 2 nil #'+my/webkit--uncover xwidget))))))

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
  "WebKit's events: the page has loaded (see NO WHITE FLASH,
`+my/webkit-load-functions'), links out of it (see above); others as usual
(not `xwidget-webkit-callback' for loads: it renames the buffer after the
page)."
  (let ((buffer (xwidget-buffer xwidget)))
    (cond ((not (eq event-type 'load-changed))
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

;; JAVASCRIPT
;; Run without waiting for an answer, but where one is needed (the selection,
;; say): closing a view while an answer was pending crashed Emacs, so views of
;; closed windows go a second later (see VIEWS), and the function awaiting it
;; is a symbol: nothing on the macOS side keeps it from the garbage collector
;; until WebKit answers, and a closure could be gone by then.
(defun +my/webkit-execute (script &optional where)
  "Run SCRIPT in the selected window's view; WHERE t: in each of the buffer's
views, an xwidget: in that one. Nothing comes back (`void 0' last: a Promise,
say, made WebKit log an error about its type)."
  (dolist (xwidget (cond ((eq where t) (+my/webkit-xwidgets))
                         (where (list where))
                         (t (ensure-list (+my/webkit-xwidget)))))
    (xwidget-webkit-execute-script xwidget (concat script "\n;void 0"))))

(defun +my/webkit-ask (script callback)
  "Run SCRIPT in the selected window's view, then CALLBACK, a symbol (see
above), with its value. Nil if there's no view."
  (when-let* ((xwidget (+my/webkit-xwidget)))
    (xwidget-webkit-execute-script xwidget script callback)
    t))

;; WATCHING
;; A page can't call Emacs: it may say things in its title instead (JSON after
;; a prefix, see `+my/webkit-title-json'), which Emacs reads without
;; JavaScript. Every 0.1 s, for each window on screen showing a page, its
;; mode's `+my/webkit-watch-function' (the PDF's page in its mode line...).
(defvar +my/webkit--under nil
  "The window under the mouse, while watching.")

(defun +my/webkit-title-json (xwidget prefix)
  "What XWIDGET's page says in its title after PREFIX, JSON, as a plist; nil
until it has said it."
  (when-let* ((title (and xwidget (ignore-errors (xwidget-webkit-title xwidget))))
              ((string-prefix-p prefix title)))
    (ignore-errors
      (json-parse-string (substring title (length prefix)) :object-type 'plist
                         :false-object nil :null-object nil))))

(defun +my/webkit--watch ()
  "Watch the windows showing pages (see above); stop once no page is open."
  (if (not (seq-some (lambda (buffer) (buffer-local-value '+my/webkit--views buffer))
                     (buffer-list)))
      (progn (cancel-timer +my/webkit--watch-timer)
             (setq +my/webkit--watch-timer nil))
    (let* ((mouse (mouse-pixel-position))
           (+my/webkit--under (and (frame-live-p (car mouse)) (numberp (cadr mouse))
                                   (window-at-x-y (cadr mouse) (cddr mouse) (car mouse)))))
      (dolist (window (window-list-1 nil 'nomini 'visible))
        (let ((buffer (window-buffer window)))
          (when (buffer-local-value '+my/webkit--views buffer)
            (with-current-buffer buffer
              (when (eq window (selected-window))
                (+my/webkit--looked-at window))
              (when-let* ((watch +my/webkit-watch-function)
                          (xwidget (+my/webkit-xwidget window)))
                (funcall watch window xwidget)))))))))

;; POINTER
;; Emacs draws its own mouse pointer over a view, the text I-beam everywhere,
;; so a page's CSS cursors never show (WebKit's hand over a link). A page that
;; says which one it wants (in its title, see WATCHING) gets it from its
;; watch function with `+my/webkit-pointer': into the `pointer' text property
;; under the views, which Emacs's pointer follows after the redisplay that
;; brings.
(defvar-local +my/webkit--pointer nil
  "The pointer shape the buffer's text has (see above).")

(defun +my/webkit-pointer (window shape)
  "The mouse pointer SHAPE (`hand', `text', `arrow') over WINDOW's view, if
the mouse is over it (see above)."
  (when (and (eq window +my/webkit--under)
             (not (eq shape +my/webkit--pointer)))
    (setq +my/webkit--pointer shape)
    (with-silent-modifications
      (put-text-property (point-min) (point-max) 'pointer shape))))

;; CLICKS
(defun +my/webkit-mouse-select (event)
  "A click on a page: select its window (the click itself is WebKit's)."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (select-window window))))

(defun +my/webkit-bind-clicks (map)
  "In MAP, clicks are WebKit's (selecting text, links): Emacs only selects the
window, instead of starting a selection of its own (Evil's visual state, where
the page's keys don't apply)."
  (let ((keys '(([down-mouse-1] . +my/webkit-mouse-select)
                ([mouse-1] . ignore)
                ([drag-mouse-1] . ignore)
                ([double-down-mouse-1] . ignore)
                ([double-mouse-1] . ignore)
                ([triple-down-mouse-1] . ignore)
                ([triple-mouse-1] . ignore))))
    (pcase-dolist (`(,key . ,command) keys)
      (define-key map key command))
    (with-eval-after-load 'evil
      (pcase-dolist (`(,key . ,command) keys)
        (evil-define-key* '(normal motion visual) map key command)))))

;; COMMANDS
;; For pages with no keys of their own (a mode binds them): j / k, C-d / C-u,
;; C-f / C-b, gg / G scroll the selected window's view; y / Cmd+C copy its
;; selected text (`+my/webkit-selection-script').
(defun +my/webkit-scroll-down (&optional count)
  "j: scroll the page down."
  (interactive "p")
  (+my/webkit-execute (format "window.scrollBy(0, %d)" (* (or count 1) +my/webkit-scroll-step))))

(defun +my/webkit-scroll-up (&optional count)
  "k: scroll the page up."
  (interactive "p")
  (+my/webkit-execute (format "window.scrollBy(0, %d)" (- (* (or count 1) +my/webkit-scroll-step)))))

(defun +my/webkit-half-screen-down ()
  "C-d: half a screen down."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, innerHeight / 2)"))

(defun +my/webkit-half-screen-up ()
  "C-u: half a screen up."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, -innerHeight / 2)"))

(defun +my/webkit-screen-down ()
  "C-f: a screen down."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, innerHeight * 0.9)"))

(defun +my/webkit-screen-up ()
  "C-b: a screen up."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, -innerHeight * 0.9)"))

(defun +my/webkit-top ()
  "gg: the page's top."
  (interactive)
  (+my/webkit-execute "window.scrollTo(0, 0)"))

(defun +my/webkit-bottom ()
  "G: the page's bottom."
  (interactive)
  (+my/webkit-execute "window.scrollTo(0, document.documentElement.scrollHeight)"))

(defun +my/webkit-copied (text)
  "Put TEXT, a page's selection, in the kill ring (and the clipboard)."
  (if (and (stringp text) (not (string-blank-p text)))
      (progn (kill-new text)
             (message "Copied %d characters" (length text)))
    (message "No text selected")))

(defun +my/webkit-copy ()
  "y / Cmd+C: copy the text selected in the page (an answer awaited, see
JAVASCRIPT)."
  (interactive)
  (+my/webkit-ask +my/webkit-selection-script #'+my/webkit-copied))

;; THE MODE
(define-derived-mode +my/webkit-mode special-mode "WebKit"
  "A web page in WebKit, a view per window showing the buffer (see
config/webkit.el). Modes derive from it, saying in their body what their page
is (`+my/webkit-url-function'...)."
  (require 'xwidget)
  (setq-local buffer-read-only t
              cursor-type nil
              ;; (list nil): see Doom's pdf module, emacs-evil/evil#2016.
              evil-normal-state-cursor (list nil)
              evil-motion-state-cursor (list nil)
              left-fringe-width 0
              right-fringe-width 0)
  (with-silent-modifications
    ;; Some text for the views to be shown over (point stays at its start,
    ;; see `+my/webkit--home-h').
    (when (= (point-min) (point-max))
      (let ((inhibit-read-only t))
        (insert " ")
        (goto-char (point-min))))
    ;; Nothing shown but the views (see VIEWS, NO WHITE FLASH).
    (put-text-property (point-min) (point-max) 'display ""))
  (add-hook 'window-buffer-change-functions #'+my/webkit--shown-h nil t)
  (add-hook 'window-size-change-functions #'+my/webkit--fit-h nil t)
  (add-hook 'post-command-hook #'+my/webkit--home-h nil t)
  ;; Last: a mode's own (keeping its place, say) still see the views.
  (add-hook 'change-major-mode-hook #'+my/webkit--stop 90 t)
  (add-hook 'kill-buffer-hook #'+my/webkit--stop 90 t)
  ;; Already on screen (the mode turned on in a shown buffer): no window will
  ;; change buffer to start a view. Started after this command, once the
  ;; derived mode's body has said what the page is.
  (dolist (window (get-buffer-window-list nil 'nomini 'visible))
    (+my/webkit--shown-h window)))

(after! evil
  (evil-set-initial-state '+my/webkit-mode 'normal))
