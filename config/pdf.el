;;; $DOOMDIR/config/pdf.el -*- lexical-binding: t; -*-
;; PDFs in WebKit, drawn by PDF.js. Loaded from config.el; its code is in
;; config/pdf/.

;; ====== VARIABLES ======

;; PDFS IN WEBKIT
;; PDFs open inside the file's tab as a web page in WebKit, like the Markdown
;; preview, drawn by PDF.js (Mozilla's PDF renderer, Firefox's), instead of
;; pdf-tools (Doom's pdf module is off in init.el): pages sharp at any zoom,
;; smooth trackpad scrolling, text selectable with the mouse. Not WebKit's own PDF viewer: on macOS Emacs takes
;; every key, so none reached it, and its buttons and selection didn't work in
;; Emacs. A page drawn by PDF.js is plain HTML (config/pdf/pdf.js) that
;; Emacs drives with JavaScript, so Evil keys work:
;;   j / k, h / l   scroll (+my/pdf-scroll-step), C-d / C-u half a
;;                  screen, C-f / C-b a screen, gg / G top / bottom (5G: page 5)
;;   J / K          next / previous page
;;   / and ?        search forward / backward (smart case), n / N next /
;;                  previous match, Esc ends it
;;   y or Cmd+C     copy the selected text (kill ring and clipboard)
;;   Cmd+= / Cmd+-  zoom (also + / -, Cmd+scroll), Cmd+0 100%, W fit the
;;                  width (as it opens), P the page
;;   C-o / C-i      back / forward: where jumps (links, the outline,
;;                  thumbnails, gg / G, a new search) left from; also Cmd+[ /
;;                  Cmd+], and the toolbar's ← →
;;   o (SPC m o)    go to a heading of the outline, picked in the minibuffer
;;   O (SPC m O)    the sidebar: the outline (headings, their pages, the
;;                  current one marked; ▸ / ▾ open / close) or the pages'
;;                  thumbnails; click one to go there
;;   SPC m d        dark pages: inverted to dark greys, hues kept (as
;;                  pdf-tools' midnight mode); again, light pages
;;   SPC m t        the toolbar: sidebar, back / forward, page, zoom, fit, dark
;;                  pages, Preview, print
;;   Option+Enter   the actions menu (config/editor/actions.el): for the selected
;;                  text, copy, search the PDF or the web, explain it with
;;                  Claude or add it to Claude's prompt (with the file and
;;                  page); Preview, print
;;   SPC m p        open it in macOS's Preview (to sign, annotate...)
;;   Cmd+P          print it, in Preview's print dialog
;;   q              close
;; A PDF opens where it was when last closed (page, place, zoom), kept in
;; `+my/pdf-places-file' across Emacs sessions, and with the toolbar,
;; sidebar and dark pages as the last one; the variables below are for the
;; first one. The mode line shows its page (P3/12).
;; Split (SPC w v, SPC w SPC, the tab's menu...), each pane shows the PDF on
;; its own: scrolled, zoomed and searched apart, its page in its mode line (a
;; WebKit view per window, see VIEWS in config/webkit/views.el). Keys act on the
;; selected pane; the settings (dark pages, the toolbar, the sidebar), Esc and
;; reverts on all of the PDF's.
;; The page can't call Emacs: it says its settings, page and place, the mouse
;; pointer it wants and the toolbar's requests (Preview, print) in its title,
;; which Emacs reads every 0.1 s, without JavaScript, while a PDF is on screen.
;; The page shows the search's matches, and the page number while it changes
;; when the toolbar (which shows it) is off.
;; Links out of the PDF open in the browser. A PDF changed on disk (e.g.
;; rebuilt by LaTeX) is shown anew, where it was: `revert-buffer', so also
;; Doom's auto-revert.
;; PDF.js (pdfjs-dist 3.11: newer versions only ship ES modules, which a
;; file:// page may not load) is downloaded once, from jsdelivr, each file
;; checked against its SHA-256 below (M-x +my/pdf-js-install does it again).
;; Without it (e.g. offline), WebKit's own viewer: trackpad only. In a
;; terminal, or an Emacs without xwidgets: doc-view, Emacs's own viewer.
;; JavaScript runs without waiting for answers, except the selection (y,
;; Cmd+C, Option+Enter) and the outline (o) (see JAVASCRIPT in
;; config/webkit/js.el, which has what WebKit pages share: a view per window, no
;; white flash, links out, the title read, the pointer, clicks).
(defvar +my/pdf-toolbar t
  "Show the toolbar in the first PDF opened (see above).")

(defvar +my/pdf-dark-pages nil
  "Dark pages in the first PDF opened (see above).")

(defvar +my/pdf-outline-sidebar nil
  "Show the sidebar (outline, pages) in the first PDF opened (see above).")

(defvar +my/pdf-places-file (expand-file-name "pdf-places" doom-state-dir)
  "Where each PDF's place (page, position, zoom) is kept between sessions.")

(defvar +my/pdf-places-max 300
  "How many PDFs' places to keep (the most recently closed).")

(defvar +my/pdf-scroll-step 60
  "Pixels j / k / h / l scroll a PDF.")

(defvar +my/pdf-zoom-step 1.25
  "How much Cmd+= / Cmd+- zoom a PDF (a factor).")

(defvar +my/pdf-js-version "3.11.174"
  "The PDF.js (npm's pdfjs-dist) version that draws PDFs (see above).")

(defvar +my/pdf-js-files
  '(("build/pdf.min.js"
     . "5b5799e6f8c680663207ac5b42ee14eed2a406fa7af48f50c154f0c0b1566946")
    ("build/pdf.worker.min.js"
     . "feabdf309770ed24bba31a5467836cdc8cf639c705af27d52b585b041bb8527b")
    ("web/pdf_viewer.js"
     . "fc8e473cc708259b229380c56a2e283c9a84792d34f028a06f2f7ac7efe2188f")
    ("web/pdf_viewer.css"
     . "3aed41dbfb4957d82ff7fa6ffa5b92936a18322b152fb51dee2292c9b7ca8363"))
  "PDF.js's files used, by their path in the npm package, with their SHA-256.")

(defvar +my/pdf-js-dir
  (expand-file-name (concat "pdfjs-" +my/pdf-js-version "/") doom-data-dir)
  "Where PDF.js is downloaded to.")

(defvar +my/pdf-mode-map (make-sparse-keymap)
  "Keys of PDFs in WebKit (see `+my/pdf-mode').")

;; Ahead of Doom's pdf-tools (until `doom sync' and a restart take it out) and
;; Emacs's doc-view: magic-mode-alist (the file starts with %PDF) wins over the
;; file name.
(add-to-list 'auto-mode-alist '("\\.[pP][dD][fF]\\'" . +my/pdf-mode-maybe))
(add-to-list 'magic-mode-alist '("%PDF" . +my/pdf-mode-maybe))

;; The mode line: doom-modeline's PDF line, with the page (see WATCHING, pdf/watch.el).
(after! doom-modeline
  (add-to-list 'doom-modeline-mode-alist '(+my/pdf-mode . pdf)))

;; ====== KEY BINDINGS ======

(map! :map +my/pdf-mode-map
      "s-="      #'+my/pdf-zoom-in
      "s-+"      #'+my/pdf-zoom-in
      "s--"      #'+my/pdf-zoom-out
      "s-0"      #'+my/pdf-actual-size
      "s-c"      #'+my/webkit-copy
      "s-["      #'+my/pdf-back
      "s-]"      #'+my/pdf-forward
      "s-p"      #'+my/pdf-print
      :nm "C-o"     #'+my/pdf-back
      :nm "C-i"     #'+my/pdf-forward
      :nm "<tab>"   #'+my/pdf-forward
      :nm "M-RET"   #'+my/pdf-actions
      :nm "j"       #'+my/pdf-scroll-down
      :nm "k"       #'+my/pdf-scroll-up
      :nm "h"       #'+my/pdf-scroll-left
      :nm "l"       #'+my/pdf-scroll-right
      :nm "<down>"  #'+my/pdf-scroll-down
      :nm "<up>"    #'+my/pdf-scroll-up
      :nm "<left>"  #'+my/pdf-scroll-left
      :nm "<right>" #'+my/pdf-scroll-right
      :nm "C-d"     #'+my/pdf-half-screen-down
      :nm "C-u"     #'+my/pdf-half-screen-up
      :nm "C-f"     #'+my/pdf-screen-down
      :nm "C-b"     #'+my/pdf-screen-up
      :nm "<next>"  #'+my/pdf-screen-down
      :nm "<prior>" #'+my/pdf-screen-up
      :nm "gg"      #'+my/pdf-top
      :nm "G"       #'+my/pdf-bottom
      :nm "<home>"  #'+my/pdf-top
      :nm "<end>"   #'+my/pdf-bottom
      :nm "J"       #'+my/pdf-next-page
      :nm "K"       #'+my/pdf-previous-page
      :nm "/"       #'+my/pdf-search
      :nm "?"       #'+my/pdf-search-backward
      :nm "n"       #'+my/pdf-search-next
      :nm "N"       #'+my/pdf-search-previous
      :nm "y"       #'+my/webkit-copy
      :nm "+"       #'+my/pdf-zoom-in
      :nm "="       #'+my/pdf-zoom-in
      :nm "-"       #'+my/pdf-zoom-out
      :nm "W"       #'+my/pdf-fit-width
      :nm "P"       #'+my/pdf-fit-page
      :nm "o"       #'+my/pdf-outline
      :nm "O"       #'+my/pdf-toggle-sidebar
      :gnm "q"      #'kill-current-buffer)  ; as Doom's pdf-tools did

;; Clicks are WebKit's: Emacs only selects the window (config/webkit.el).
(+my/webkit-bind-clicks +my/pdf-mode-map)

(map! :map +my/pdf-mode-map
      :localleader
      :desc "Outline: go to a heading" "o" #'+my/pdf-outline
      :desc "Sidebar (outline, pages)" "O" #'+my/pdf-toggle-sidebar
      :desc "Dark pages"               "d" #'+my/pdf-toggle-dark
      :desc "Toolbar"                  "t" #'+my/pdf-toggle-toolbar
      :desc "Open in Preview"          "p" #'+my/pdf-open-in-preview
      :desc "Print"                    "P" #'+my/pdf-print)

;; Evil keys (see above) in normal state.
(after! evil
  (evil-set-initial-state '+my/pdf-mode 'normal))

;; ====== CODE ======

;; In config/pdf/, in this order: each part can use what the ones before it
;; define.
(load! "pdf/page")
(load! "pdf/places")
(load! "pdf/watch")
(load! "pdf/commands")
(load! "pdf/actions")
(load! "pdf/outline")
(load! "pdf/mode")
