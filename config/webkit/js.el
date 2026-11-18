;;; $DOOMDIR/config/webkit/js.el -*- lexical-binding: t; -*-
;; JavaScript in pages; what they say in their titles. Loaded from
;; config/webkit.el.

;; JAVASCRIPT
;; Run without waiting for an answer, but where one is needed (the selection, a
;; drawing's file text, say): closing a view while an answer was pending
;; crashed Emacs. So views of closed windows go a second later (see VIEWS in
;; views.el); a view closed while an answer is on its way is killed once it has
;; come, 5 s at most (WebKit never answers a script that failed, or whose value
;; is null), its function not called; a killed view stays referenced for 10 s
;; (an answer to a view the garbage collector took would be Emacs's end); and
;; the function awaiting an answer is a symbol: nothing on the macOS side keeps
;; it from the garbage collector until WebKit answers, and a closure could be
;; gone by then. It runs with `+my/webkit-answering' the view that answered, in
;; the view's buffer.
(defvar +my/webkit-answering nil
  "The view (an xwidget) whose answer a `+my/webkit-ask' function runs for.")

(defun +my/webkit--asked-p (xwidget)
  "Non-nil if an answer from XWIDGET's page is on its way (see above)."
  (> (or (xwidget-get xwidget 'asked) 0) 0))

(defun +my/webkit--answered (xwidget function value)
  "XWIDGET's page answered VALUE: FUNCTION with it, but if its view was
closed meanwhile (see above); killed already (5 s passed), nothing."
  (when (xwidget-live-p xwidget)
    (+my/webkit--answered-live xwidget function value)))

(defun +my/webkit--answered-live (xwidget function value)
  "`+my/webkit--answered', XWIDGET not killed."
  (xwidget-put xwidget 'asked (max 0 (1- (or (xwidget-get xwidget 'asked) 1))))
  (cond ((xwidget-get xwidget '+my/webkit-closing)
         (unless (+my/webkit--asked-p xwidget)
           (run-at-time 0 nil #'+my/webkit--kill-now xwidget)))
        ((buffer-live-p (xwidget-buffer xwidget))
         (with-current-buffer (xwidget-buffer xwidget)
           (let ((+my/webkit-answering xwidget))
             (funcall function value))))))

(defun +my/webkit-wait (predicate seconds)
  "Wait until PREDICATE returns non-nil, SECONDS at most, WebKit's answers and
titles coming in meanwhile (keys typed meanwhile are kept for after); return
its value."
  (let ((end (+ (float-time) seconds))
        (typed nil)
        value)
    (while (and (not (setq value (funcall predicate)))
                (< (float-time) end))
      (if noninteractive
          (sleep-for 0.02)
        ;; WebKit's events come with the input; not a keyboard macro's keys.
        (when-let* ((event (let ((executing-kbd-macro nil))
                             (read-event nil nil 0.02))))
          (push event typed))))
    (setq unread-command-events (append unread-command-events (nreverse typed)))
    value))

(defun +my/webkit-execute (script &optional where)
  "Run SCRIPT in the selected window's view; WHERE t: in each of the buffer's
views, an xwidget: in that one. Nothing comes back (`void 0' last: a Promise,
say, made WebKit log an error about its type)."
  (dolist (xwidget (cond ((eq where t) (+my/webkit-xwidgets))
                         (where (list where))
                         (t (ensure-list (+my/webkit-xwidget)))))
    (xwidget-webkit-execute-script xwidget (concat script "\n;void 0"))))

(defun +my/webkit-ask (script callback &optional xwidget)
  "Run SCRIPT in XWIDGET's view (default: the selected window's), then
CALLBACK, a symbol (see above), with its value: SCRIPT always has one (not
null, no error). Nil if there's no view."
  (when-let* ((xwidget (or xwidget (+my/webkit-xwidget))))
    (xwidget-put xwidget 'asked (1+ (or (xwidget-get xwidget 'asked) 0)))
    (xwidget-webkit-execute-script xwidget script callback)
    t))

;; WATCHING
;; A page can't call Emacs: it may say things in its title instead (JSON after
;; a prefix, see `+my/webkit-title-json'), which Emacs reads without
;; JavaScript. Every 0.1 s, for each window on screen showing a page, its
;; mode's `+my/webkit-watch-function' (the PDF's page in its mode line...).

(defvar +my/webkit--watch-timer nil
  "Every 0.1 s while a page is open (see WATCHING).")

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

;; THE READING PLACE
;; WebKit keeps a page's scroll in pixels: its pane narrowed or widened (tiling
;; resizes panes all the time), the text laid out anew, another part of it was
;; at the top. So each page, once loaded, keeps what's at its top as it's
;; scrolled (the deepest block there: not one that's fixed or sticky, an image
;; or an SVG whole; and how far into it the top is, or how far above it), and
;; puts it back at the top as its view is resized. At the very top it stays at
;; the top. It starts with the place the page is at: scrolled before (a key
;; pressed at once, the scroll a reload puts back), there was no scroll after
;; it to say it. Kept at each scroll, not at the next animation frame: WebKit
;; holds those back for a view it doesn't show whole (a second and more), and
;; a resize meanwhile put back the place before. A page scrolled in an element
;; of its own (PDF.js) or not at all (a drawing) isn't concerned. A page whose
;; place is something else (the Markdown preview's: the cursor's line) puts it
;; back itself: window.emacsKeepPlace, a function, is called instead.
(defconst +my/webkit--place-js
  "(function () {
  if (window.emacsPlace) return;
  var anchor = null;
  function block(element) {
    var style = getComputedStyle(element);
    return style.position !== 'fixed' && style.position !== 'sticky' && !/^inline/.test(style.display);
  }
  function first(parent) {
    for (var child = parent.firstElementChild; child; child = child.nextElementSibling) {
      var box = child.getBoundingClientRect();
      if (box.height > 0 && box.bottom > 0 && block(child)) return child;
    }
    return null;
  }
  function top() {
    var found = null, next = document.body && first(document.body);
    while (next) {
      found = next;
      if (next.getBoundingClientRect().top >= 0 || /^(svg|img|canvas|video|iframe)$/i.test(next.tagName)) break;
      next = first(next);
    }
    return found;
  }
  function record() {
    var element = window.scrollY > 0 ? top() : null;
    if (!element) { anchor = null; return; }
    var box = element.getBoundingClientRect();
    anchor = {element: element, top: box.top, part: box.top < 0 ? -box.top / box.height : 0};
  }
  function restore() {
    if (typeof window.emacsKeepPlace === 'function') return window.emacsKeepPlace();
    if (!anchor || !anchor.element.isConnected) return;
    var box = anchor.element.getBoundingClientRect();
    window.scrollBy(0, box.top - (anchor.top < 0 ? -anchor.part * box.height : anchor.top));
  }
  addEventListener('scroll', record, {passive: true});
  addEventListener('resize', restore);
  window.emacsPlace = {anchor: function () { return anchor && anchor.element; }};
  record();
})();"
  "JavaScript keeping a page's reading place (see above).")

(defun +my/webkit--keep-place (xwidget)
  "XWIDGET's page, just loaded, keeps its reading place (see above)."
  (+my/webkit-execute +my/webkit--place-js xwidget))
