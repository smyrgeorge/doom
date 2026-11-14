;;; $DOOMDIR/config/html.el -*- lexical-binding: t; -*-
;; HTML files: a notice offering to open them in the browser; a page in
;; Emacs, in WebKit. Loaded from config.el.

;; ====== VARIABLES ======

;; BROWSER NOTICE
;; An HTML file (.html, .htm, .xhtml) opens with a notice at the top
;; (config/banner.el): "Open in browser" opens it in the default browser
;; (`browse-url-of-file': the file as saved; changes not saved yet, it says
;; so). The notice stays until its ✕. Its modes: Doom's web-mode, Emacs's
;; HTML modes, and the long lines' mode (an HTML report with its data on one
;; line, config/editor/long-lines.el), its notice under that one's.
(defvar +my/html-browser-notice t
  "Offer to open an HTML file in the browser, in a notice (see above).")

(defvar +my/html-modes '(web-mode html-mode html-ts-mode so-long-mode)
  "The modes HTML files open in (see above): their hooks show the notice.")

;; A PAGE IN EMACS
;; `+my/html-open-in-emacs' shows an HTML file or a URL as a page in WebKit
;; (config/webkit.el), in a buffer of its own, "Page: NAME", opened in a tiled
;; pane (one of tiling's applications); links out of it go to the browser. Where
;; WebKit can't (a terminal, an Emacs without xwidgets): the browser. Agent
;; UI's page cards open so (config/agent-ui.el). Its keys: j / k, C-d / C-u,
;; gg / G scroll, h / l sideways; y / Cmd+C copy; + / - zoom, 0 back to its
;; size, W fits the pane's width (a page wider than it), the zoom the page's in
;; all its panes (a split too); g r reloads it, as opening it again does; q
;; closes it.
(defvar-local +my/html-page-url nil
  "In a page's buffer (see A PAGE IN EMACS above): the URL it shows.")

(defvar +my/html-page-mode-map (make-sparse-keymap)
  "Keys of a page in Emacs (see `+my/html-page-mode').")

;; ====== KEY BINDINGS ======

(map! :map +my/html-page-mode-map
      "s-c"         #'+my/webkit-copy
      "s-="         #'+my/html-page-zoom-in
      "s-+"         #'+my/html-page-zoom-in
      "s--"         #'+my/html-page-zoom-out
      "s-0"         #'+my/html-page-actual-size
      :nm "j"       #'+my/webkit-scroll-down
      :nm "k"       #'+my/webkit-scroll-up
      :nm "h"       #'+my/webkit-scroll-left
      :nm "l"       #'+my/webkit-scroll-right
      :nm "<down>"  #'+my/webkit-scroll-down
      :nm "<up>"    #'+my/webkit-scroll-up
      :nm "<left>"  #'+my/webkit-scroll-left
      :nm "<right>" #'+my/webkit-scroll-right
      :nm "C-d"     #'+my/webkit-half-screen-down
      :nm "C-u"     #'+my/webkit-half-screen-up
      :nm "C-f"     #'+my/webkit-screen-down
      :nm "C-b"     #'+my/webkit-screen-up
      :nm "<next>"  #'+my/webkit-screen-down
      :nm "<prior>" #'+my/webkit-screen-up
      :nm "gg"      #'+my/webkit-top
      :nm "G"       #'+my/webkit-bottom
      :nm "<home>"  #'+my/webkit-top
      :nm "<end>"   #'+my/webkit-bottom
      :nm "y"       #'+my/webkit-copy
      :nm "+"       #'+my/html-page-zoom-in
      :nm "="       #'+my/html-page-zoom-in
      :nm "-"       #'+my/html-page-zoom-out
      :nm "0"       #'+my/html-page-actual-size
      :nm "W"       #'+my/html-page-fit-width
      :nm "gr"      #'revert-buffer
      :gnm "q"      #'+my/html-page-quit)

;; On Linux, Ctrl for Cmd (config/emacs.el, KEYS): zoom, copy.
(map! :unless (+my/macos-p)
      :map +my/html-page-mode-map
      :nm "C-="     #'+my/html-page-zoom-in
      :nm "C-+"     #'+my/html-page-zoom-in
      :nm "C--"     #'+my/html-page-zoom-out
      :nm "C-0"     #'+my/html-page-actual-size
      :nm "C-S-c"   #'+my/webkit-copy)

;; Clicks are WebKit's: Emacs only selects the window (config/webkit.el).
(+my/webkit-bind-clicks +my/html-page-mode-map)

;; ====== CODE ======

(defun +my/html-file-p ()
  "Non-nil if the buffer visits an HTML file."
  (and buffer-file-name
       (let ((case-fold-search t))
         (string-match-p "\\.x?html?\\'" buffer-file-name))))

(defun +my/html-open-in-browser ()
  "Open the buffer's HTML file in the default browser."
  (interactive)
  (unless (+my/html-file-p)
    (user-error "Not an HTML file"))
  (browse-url-of-file buffer-file-name))

(defun +my/html-browser-notice-h ()
  "Offer to open the buffer's HTML file in the browser (see above)."
  (when (and +my/html-browser-notice
             (+my/html-file-p)
             (fboundp '+my/banner-show))
    (+my/banner-show 'html-browser "Open this file in your browser."
                     :actions '(("Open in browser" . +my/html-open-in-browser)))))

(dolist (mode +my/html-modes)
  (add-hook (intern (format "%s-hook" mode)) #'+my/html-browser-notice-h))

;; A PAGE IN EMACS (see above)
(define-derived-mode +my/html-page-mode +my/webkit-mode "Page"
  "An HTML file or a web page, in WebKit (see A PAGE IN EMACS in
config/html.el).

\\{+my/html-page-mode-map}"
  (setq-local +my/webkit-url-function (lambda (_window) +my/html-page-url)
              revert-buffer-function #'+my/html--revert)
  (add-hook '+my/webkit-load-functions #'+my/html--loaded nil t))

;; Reloaded (g r, or the page opened again: its file changed, say): each of
;; its views, as WebKit reloads a page, its zoom kept (see below).
(defun +my/html--revert (&rest _)
  "g r: each of the page's views reloaded (see above)."
  (dolist (xwidget (+my/webkit-xwidgets))
    (xwidget-webkit-goto-history xwidget 0)))

;; Zoom: the page's, the same in each of its views (a new one, once loaded,
;; too). Down to half its size, WebKit's page zoom (CSS's on the page's root:
;; laid out anew for the zoomed width, the same on macOS and Linux); below,
;; where WebKit's text stops shrinking (9 px), the views are magnified by
;; what's left (`xwidget-webkit-zoom': macOS's magnifier, Linux's page zoom).
(defconst +my/html--zoom-floor 0.5
  "The smallest zoom laid out anew (see above).")

(defvar-local +my/html--zoom 1
  "A page's zoom (see above): 1, its own size.")

(defun +my/html--magnify (xwidget magnification)
  "XWIDGET's view magnified by MAGNIFICATION (WebKit's own zoom, which adds
to what it was)."
  (let ((was (or (xwidget-get xwidget '+my/html-magnified) 1.0)))
    (unless (= magnification was)
      (xwidget-webkit-zoom xwidget (float (- magnification was)))
      (xwidget-put xwidget '+my/html-magnified magnification))))

(defun +my/html--zoom-view (xwidget)
  "XWIDGET's view at the page's zoom (see above)."
  (let ((laid-out (max +my/html--zoom +my/html--zoom-floor)))
    (+my/webkit-execute (format "document.documentElement.style.zoom = '%s'"
                                (if (= laid-out 1) "" (format "%g" laid-out)))
                        xwidget)
    (+my/html--magnify xwidget (/ (float +my/html--zoom) laid-out))))

(defun +my/html--zoom (zoom)
  "The page at ZOOM, a tenth to ten times its size, in each of its views."
  (setq +my/html--zoom (max 0.1 (min 10 zoom)))
  (mapc #'+my/html--zoom-view (+my/webkit-xwidgets)))

(defun +my/html--loaded (xwidget)
  "XWIDGET's page has loaded: the page's zoom (see above)."
  (unless (= +my/html--zoom 1)
    (+my/html--zoom-view xwidget)))

(defun +my/html-page-zoom-in ()
  "+: the page bigger."
  (interactive)
  (+my/html--zoom (* +my/html--zoom 1.25)))

(defun +my/html-page-zoom-out ()
  "-: the page smaller."
  (interactive)
  (+my/html--zoom (* +my/html--zoom 0.8)))

(defun +my/html-page-actual-size ()
  "0: the page at its own size."
  (interactive)
  (+my/html--zoom 1))

;; Fitting the pane's width: the zoom making the page as wide as the selected
;; pane, at most its size, worked out in its view, unmagnified: laid out
;; smaller (measured again: its text may stop shrinking) down to the floor,
;; then what's left to magnify.
(defconst +my/html--fit-script
  "(function (floor) {
  var root = document.documentElement, zoom = 1;
  root.style.zoom = '';
  for (var i = 0; i < 10 && root.scrollWidth > root.clientWidth && zoom > floor; i++) {
    zoom = Math.max(floor, zoom * root.clientWidth / root.scrollWidth);
    root.style.zoom = zoom;
  }
  return zoom * Math.min(1, root.clientWidth / root.scrollWidth);
})(%s)"
  "JavaScript zooming a page to its pane's width (see above), for `format'
with the floor: its zoom.")

(defun +my/html--fitted (zoom)
  "The selected pane's page fits it at ZOOM: the page's zoom (all its views)."
  (when (numberp zoom)
    (+my/html--zoom zoom)))

(defun +my/html-page-fit-width ()
  "W: the page as wide as the pane, if it's wider (see above)."
  (interactive)
  (when-let* ((xwidget (+my/webkit-xwidget)))
    (+my/html--magnify xwidget 1.0)
    (+my/webkit-ask (format +my/html--fit-script +my/html--zoom-floor) #'+my/html--fitted xwidget)))

(defun +my/html-page-quit ()
  "q: the page closed, its panes quit as `quit-window' does: a pane made for
it closes, unless other tabs are under it."
  (interactive)
  (let ((kill-buffer-quit-windows t))
    (kill-buffer (current-buffer))))

(defun +my/html--url-p (page)
  (string-match-p "\\`[a-z]+://" page))

;; Read as a file's name, a URL typed after the folder offered ("~/dir/" then
;; "https://...") is the URL: its `//' doesn't start a name from the root
;; (Emacs's `substitute-in-file-name'), which also left the minibuffer with
;; the host's name alone (the folder before it shadowed, then deleted).
(defconst +my/html--url-regexp "[[:alpha:]][[:alnum:]+.-]*://"
  "A URL's start, in a name read (see above).")

(defun +my/html--url-name-handler (operation &rest args)
  "While a page is read (see above): a name holding a URL substituted as the
URL; the rest as usual."
  (let ((inhibit-file-name-handlers
         (cons #'+my/html--url-name-handler
               (and (eq inhibit-file-name-operation operation) inhibit-file-name-handlers)))
        (inhibit-file-name-operation operation))
    (if (eq operation 'substitute-in-file-name)
        (let ((name (car args)))
          (substring name (string-match +my/html--url-regexp name)))
      (apply operation args))))

(defun +my/html--read-page ()
  "An HTML file or a URL, read (see above)."
  (let ((handler (cons +my/html--url-regexp #'+my/html--url-name-handler)))
    ;; Not let-bound: what's added meanwhile (TRAMP, loaded) stays.
    (push handler file-name-handler-alist)
    (unwind-protect
        (let ((page (read-file-name "Page (a file or a URL): ")))
          (if (string-match +my/html--url-regexp page)
              (substring page (match-beginning 0))
            (expand-file-name page)))
      (setq file-name-handler-alist (delq handler file-name-handler-alist)))))

(defun +my/html-open-in-emacs (page)
  "Show PAGE, an HTML file or a URL, in WebKit in a pane (see A PAGE IN
EMACS above); where WebKit can't, in the browser. Returns its buffer, if
it's Emacs's."
  (interactive (list (+my/html--read-page)))
  (let ((url-p (+my/html--url-p page)))
    (if (not (and (display-graphic-p) (featurep 'xwidget-internal) (fboundp '+my/webkit-file-url)))
        (progn (if url-p (browse-url page) (browse-url-of-file page))
               nil)
      (let* ((url (if url-p page (+my/webkit-file-url page)))
             (name (format "Page: %s" (if url-p page (file-name-nondirectory page))))
             (old (get-buffer name)))
        ;; Another page so named: replaced.
        (when (and old (not (equal (buffer-local-value '+my/html-page-url old) url)))
          (kill-buffer old))
        (let ((buffer (get-buffer-create name)))
          (with-current-buffer buffer
            (if (derived-mode-p '+my/html-page-mode)
                ;; Open already: as it is now.
                (+my/html--revert)
              (+my/html-page-mode))
            ;; After the mode (which clears the buffer's variables), before
            ;; a window shows it (which starts its view).
            (setq +my/html-page-url url))
          (pop-to-buffer buffer)
          buffer)))))
