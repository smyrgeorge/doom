;;; $DOOMDIR/config/webkit.el -*- lexical-binding: t; -*-
;; Web pages inside Emacs, in WebKit (xwidgets): what the PDF viewer
;; (config/pdf.el), the Markdown preview (config/markdown.el) and drawings
;; (config/excalidraw.el) share. Loaded from config.el, before them; its code
;; is in config/webkit/.

;; ====== VARIABLES ======

;; WEBKIT PAGES
;; A buffer in `+my/webkit-mode', or a mode derived from it, shows a web page
;; in WebKit (Emacs's xwidgets; emacs-plus has them), with what a page inside
;; Emacs needs, so that a mode only says what its page is:
;; - a view per window showing the buffer: split, both panes show the page
;;   (see VIEWS in webkit/views.el);
;; - no white flash while a view loads (see NO WHITE FLASH in
;;   webkit/views.el);
;; - links out of the page open in the browser (see LINKS OUT in
;;   webkit/links.el);
;; - JavaScript run in the selected window's view or in all of them, answers
;;   awaited without crashing Emacs (see JAVASCRIPT in webkit/js.el);
;; - what the page says in its title, read every 0.1 s, as a page can't call
;;   Emacs (see WATCHING in webkit/js.el), e.g. the mouse pointer it wants
;;   (see POINTER in webkit/input.el);
;; - clicks are WebKit's (selecting text, links): Emacs only selects the
;;   window (see CLICKS in webkit/input.el);
;; - scrolling and copying for pages with no keys of their own (see COMMANDS
;;   in webkit/input.el);
;; - a file's new text, from a page that edits it, under the views, to be
;;   saved as any (see THE BUFFER'S TEXT in webkit/files.el);
;; - the libraries a page needs, downloaded and checked (see DOWNLOADS in
;;   webkit/files.el).
;; A mode derived from it sets, in its body, the variables below (buffer-local).
(defvar-local +my/webkit-url-function nil
  "Function of the window a new view is for (see VIEWS in webkit/views.el),
returning the URL the view loads: it may write the page first, e.g. as things
are now. Nil: no view.")

(defvar-local +my/webkit-background nil
  "The page's background colour, for the cover while a view loads (see NO
WHITE FLASH in webkit/views.el): a colour, a function returning one, or nil
for the theme's.")

(defvar-local +my/webkit-load-functions nil
  "Functions of a view's xwidget, called once its page has loaded.")

(defvar-local +my/webkit-watch-function nil
  "Function of a window showing the buffer and its view's xwidget, called
every 0.1 s while the window is on screen (see WATCHING in webkit/js.el).")

(defvar-local +my/webkit-link-function #'browse-url
  "Function of a URL a link out of the page goes to (see LINKS OUT in
webkit/links.el).")

(defvar-local +my/webkit-selection-script "String(window.getSelection())"
  "JavaScript whose value is the page's selected text (see `+my/webkit-copy').")

(defvar +my/webkit-scroll-step 60
  "Pixels j / k scroll a page (see COMMANDS in webkit/input.el).")

;; ====== KEY BINDINGS ======

;; Pages start in normal state, where modes bind their keys.
(after! evil
  (evil-set-initial-state '+my/webkit-mode 'normal))

;; ====== CODE ======

;; In config/webkit/, in this order: each part can use what the ones before it
;; define.
(load! "webkit/files")
(load! "webkit/views")
(load! "webkit/links")
(load! "webkit/js")
(load! "webkit/input")
(load! "webkit/mode")
