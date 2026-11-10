;;; $DOOMDIR/config/banner.el -*- lexical-binding: t; -*-
;; Notices at the top of a window, with actions. Loaded from config.el; its
;; code is in config/banner/.

;; ====== VARIABLES ======

;; BANNERS
;; A buffer can show notices at the top of its windows, under the tabs: a row
;; each, with an icon and colour for its type (info, warning, error), the
;; message, actions to click, and ✕ to close it. They stay put while scrolling,
;; and the header line (the file's path, or the sticky scopes) stays under them.
;; From code: (+my/banner-show ID TEXT :type 'warning :actions '(("Do" . fn)));
;; M-x +my/banner-close closes the first one.
;; (A header line is a single row of text. So it grows a row per notice, with
;; its own text in the bottom one, and a small frame without borders lays the
;; notices over the rows above. In a terminal the header line shows the first
;; notice instead, saying how many more there are.)
;;
;; Notices so far:
;; - long lines (warning, config/editor/long-lines.el): files with very long
;;   lines open in `so-long-mode', plain and unwrapped; "Wrap lines" wraps them
;;   again, "Open normally" goes back to the file's own mode (both can make
;;   scrolling slow again);
;; - large files (warning, config/editor/large-files.el): opened without the
;;   language server, spelling, syntax checking...; "Open normally" turns
;;   them on;
;; - the Markdown preview (info, config/markdown/notice.el): a Markdown file
;;   offers it ("Open preview");
;; - the browser (info, config/html.el): an HTML file offers it ("Open in
;;   browser").
(defvar +my/banner-types
  '((info    "nf-cod-info"    blue)
    (warning "nf-cod-warning" yellow)
    (error   "nf-cod-error"   red))
  "The kinds of notices: (TYPE ICON COLOUR), ICON a codicon (nerd-icons),
COLOUR a theme colour (`doom-color'): the icon's, and the row's tint.")

(defface +my/banner-info '((t :inherit header-line)) "An info notice's row.")

(defface +my/banner-warning '((t :inherit header-line)) "A warning notice's row.")

(defface +my/banner-error '((t :inherit header-line)) "An error notice's row.")

(defface +my/banner-action '((t :inherit link :underline nil :weight bold))
  "The actions in a notice.")

;; ====== KEY BINDINGS ======

(defvar +my/banner--row-map
  (let ((map (make-sparse-keymap)))
    ;; Clicks and the wheel on a notice do nothing (they'd select its frame or
    ;; scroll it).
    (dolist (event '(down-mouse-1 mouse-1 double-mouse-1 triple-mouse-1 drag-mouse-1
                     down-mouse-2 mouse-2 down-mouse-3 mouse-3
                     wheel-up wheel-down wheel-left wheel-right
                     double-wheel-up double-wheel-down triple-wheel-up triple-wheel-down))
      (define-key map (vector event) #'ignore))
    map)
  "Keys on a notice's row.")

;; ====== CODE ======

;; In config/banner/, in this order: each part can use what the ones before it
;; define.
(load! "banner/show")
(load! "banner/row")
(load! "banner/header")
(load! "banner/frames")
(load! "banner/theme")
