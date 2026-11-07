;;; $DOOMDIR/config/pdf.el -*- lexical-binding: t; -*-
;; PDFs in WebKit (xwidgets), drawn by PDF.js. Loaded from config.el.

;; ====== VARIABLES ======

;; PDFS IN WEBKIT
;; PDFs open inside the file's tab as a web page in WebKit, like the Markdown
;; preview, drawn by PDF.js (Mozilla's PDF renderer, Firefox's), instead of
;; pdf-tools (Doom's pdf module is off in init.el): pages sharp at any zoom,
;; smooth trackpad scrolling, text selectable with the mouse. Not WebKit's own PDF viewer: on macOS Emacs takes
;; every key, so none reached it, and its buttons and selection didn't work in
;; Emacs. A page drawn by PDF.js is plain HTML (config/pdf.js) that
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
;;                  pdf-tools' midnight mode)
;;   SPC m t        the toolbar: sidebar, back / forward, page, zoom, fit, dark
;;                  pages, Preview, print
;;   Option+Enter   the actions menu (config/actions.el): for the selected
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
;; WebKit view per window, see VIEWS in config/webkit.el). Keys act on the
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
;; config/webkit.el, which has what WebKit pages share: a view per window, no
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

;; ====== CODE ======

(defvar-local +my/pdf--dir nil
  "The page's folder: index.html and the PDF's data, as base64.")

(defvar-local +my/pdf--data 0
  "N of the PDF's latest data-N.js.")

(defvar-local +my/pdf--native nil
  "Non-nil if WebKit's own viewer shows the PDF (no PDF.js).")

(defvar-local +my/pdf--home nil
  "The page's URL (see `+my/pdf--url').")

(defvar-local +my/pdf--searching nil
  "Non-nil while a search shows its matches (Esc ends it).")

(defvar +my/pdf--search-history nil)

(defconst +my/pdf--page-template
  "<!doctype html>
<html><head><meta charset=\"utf-8\">
<link rel=\"stylesheet\" href=\"%ppdf_viewer.css\">
<style>
:root{%v}
html,body{margin:0;height:100%%;overflow:hidden;background:%b;color-scheme:%c}
#viewerContainer{position:absolute;inset:0;overflow:auto}
.pdfViewer.removePageBorders .page{margin:10px auto;box-shadow:0 1px 6px rgba(0,0,0,.45)}
.badge{position:fixed;right:14px;z-index:10;padding:3px 9px;border-radius:6px;
  font:12px -apple-system,sans-serif;white-space:pre;background:rgba(0,0,0,.72);
  color:#eee;pointer-events:none;opacity:0;transition:opacity .2s}
.badge.on{opacity:1}
#find{top:10px}
#page{bottom:12px}
</style></head><body>
<div id=\"viewerContainer\"><div id=\"viewer\" class=\"pdfViewer\"></div></div>
<div id=\"find\" class=\"badge\"></div><div id=\"page\" class=\"badge\"></div>
<script src=\"%ppdf.min.js\"></script>
<script src=\"%ppdf.worker.min.js\"></script>
<script src=\"%ppdf_viewer.js\"></script>
<script>window.PDFX_OPTIONS = %o;</script>
<script src=\"%j\"></script>
<script>
if (window.pdfx) pdfx.open(%d);
else { var b = document.getElementById('find'); b.textContent = 'PDF.js did not load'; b.className = 'badge on'; }
</script>
</body></html>
"
  "A PDF's page (see config/pdf.js), for `format-spec': %b the
background, %c the colour scheme, %v the theme's colours (CSS variables), %o
the settings (JSON), %p PDF.js's folder, %j the script, %d the data file's
name (JSON).")

(defun +my/pdf-p ()
  "Non-nil if this buffer's PDF can show in WebKit: a local file, in the GUI,
in an Emacs with xwidgets."
  (and buffer-file-name (not (file-remote-p buffer-file-name))
       (+my/webkit-p)))

(defun +my/pdf-mode-maybe ()
  "PDFs' major mode: WebKit where it works, doc-view otherwise (see above)."
  (if (+my/pdf-p)
      (+my/pdf-mode)
    (doc-view-mode-maybe)))

;; Ahead of Doom's pdf-tools (until `doom sync' and a restart take it out) and
;; Emacs's doc-view: magic-mode-alist (the file starts with %PDF) wins over the
;; file name.
(add-to-list 'auto-mode-alist '("\\.[pP][dD][fF]\\'" . +my/pdf-mode-maybe))
(add-to-list 'magic-mode-alist '("%PDF" . +my/pdf-mode-maybe))

;; No "File is large, really open?" for PDFs, as with Doom's pdf module: only
;; WebKit reads them.
(defadvice! +my/pdf-no-large-file-prompt-a (fn size op-type filename &optional offer-raw)
  :around #'abort-if-file-too-large
  (unless (string-match-p "\\.[pP][dD][fF]\\'" filename)
    (funcall fn size op-type filename offer-raw)))

;; PDF.JS
(defun +my/pdf--js-files ()
  "PDF.js's files, as `+my/webkit-install' takes them."
  (mapcar (lambda (file)
            (list (file-name-nondirectory (car file))
                  (format "https://cdn.jsdelivr.net/npm/pdfjs-dist@%s/%s"
                          +my/pdf-js-version (car file))
                  (cdr file)))
          +my/pdf-js-files))

(defun +my/pdf-js-installed-p ()
  "Non-nil if PDF.js is in `+my/pdf-js-dir'."
  (+my/webkit-installed-p (+my/pdf--js-files) +my/pdf-js-dir))

(defun +my/pdf-js-install ()
  "Download PDF.js into `+my/pdf-js-dir', checking each file's SHA-256."
  (interactive)
  (+my/webkit-install "PDF.js" +my/pdf-js-version (+my/pdf--js-files) +my/pdf-js-dir))

(defun +my/pdf-js-ensure ()
  "Non-nil if PDF.js is there, downloaded now if need be (see above)."
  (or (+my/pdf-js-installed-p)
      (condition-case err
          (progn (+my/pdf-js-install) t)
        (error (message "PDFs in WebKit's own viewer: %s" (error-message-string err))
               nil))))

;; THE PAGE (see config/pdf.js)
(defun +my/pdf--write-data ()
  "Write the PDF, as base64, to the page's next data-N.js; return its name."
  (let* ((name (format "data-%d.js" (setq +my/pdf--data (1+ +my/pdf--data))))
         (old (expand-file-name (format "data-%d.js" (1- +my/pdf--data))
                                +my/pdf--dir))
         (pdf buffer-file-name)
         (coding-system-for-write 'no-conversion))
    (with-temp-file (expand-file-name name +my/pdf--dir)
      (set-buffer-multibyte nil)
      (insert-file-contents-literally pdf)
      (base64-encode-region (point-min) (point-max) t)
      (goto-char (point-min))
      (insert "window.PDFX_DATA=\"")
      (goto-char (point-max))
      (insert "\";\n"))
    ;; The page has read the one before.
    (when (file-exists-p old)
      (delete-file old))
    name))

(defun +my/pdf--color (face attribute fallback)
  "FACE's ATTRIBUTE colour as #rrggbb (CSS doesn't know Emacs's colour
names), FALLBACK without one."
  (require 'color)
  (let ((color (face-attribute face attribute nil t)))
    (or (and (stringp color) (color-defined-p color)
             (apply #'color-rgb-to-hex (append (color-name-to-rgb color) '(2))))
        fallback)))

(defun +my/pdf--css-variables ()
  "The theme's colours, for the toolbar and the sidebar (CSS variables)."
  (format "--bg:%s;--bar:%s;--fg:%s;--dim:%s;--hover:%s;--accent:%s;--border:%s"
          (+my/pdf--color 'default :background "#282c34")
          (+my/pdf--color 'mode-line :background "#1d2026")
          (+my/pdf--color 'default :foreground "#bbc2cf")
          (+my/pdf--color 'shadow :foreground "#5b6268")
          (+my/pdf--color 'region :background "#3f444a")
          (+my/pdf--color 'link :foreground "#51afef")
          (+my/pdf--color 'vertical-border :foreground "#191b20")))

;; SETTINGS: the toolbar, the outline sidebar, dark pages (see above). The
;; page says them, and its page, in its title: "pdfx {json}".
(defun +my/pdf--state (&optional xwidget)
  "XWIDGET's page's settings and page (default: this buffer's view, see
`+my/webkit-xwidget'), a plist (:dark :toolbar :sidebar :view :outline
:page :pages :place :cursor :action), or nil before it has said them."
  (+my/webkit-title-json (or xwidget (+my/webkit-xwidget)) "pdfx "))

(defun +my/pdf--options ()
  "The settings a page starts with (JSON): this PDF's (a page written anew,
another window's view, see VIEWS), else the last PDF's looked at, else the
variables above; and its place, this PDF's or the one kept from last time (see
PLACES)."
  (require 'json)
  (let* ((own (+my/pdf--state))
         (last (or own
                   (seq-some (lambda (buffer)
                               (and (not (eq buffer (current-buffer)))
                                    (eq (buffer-local-value 'major-mode buffer)
                                        '+my/pdf-mode)
                                    (with-current-buffer buffer
                                      (+my/pdf--state))))
                             (buffer-list))))
         (get (lambda (key default) (if last (plist-get last key) default)))
         (bool (lambda (value) (if value "true" "false")))
         (place (or (plist-get own :place) (+my/pdf--kept-place))))
    (format "{\"dark\":%s,\"toolbar\":%s,\"sidebar\":%s,\"view\":%s,\"place\":%s,\"zoomStep\":%s}"
            (funcall bool (funcall get :dark +my/pdf-dark-pages))
            (funcall bool (funcall get :toolbar +my/pdf-toolbar))
            (funcall bool (funcall get :sidebar +my/pdf-outline-sidebar))
            (json-encode (or (funcall get :view nil) "outline"))
            (if place (json-encode place) "null")
            +my/pdf-zoom-step)))

;; PLACES
;; Each PDF's place (page, position on it, zoom) when it's closed or Emacs
;; quits, in `+my/pdf-places-file', for the next time it opens.
(defvar +my/pdf--places 'unread
  "The places kept: ((FILE . PLACE)...), the latest first.")

(defun +my/pdf--read-places ()
  "The places kept (see above), read from their file the first time."
  (when (eq +my/pdf--places 'unread)
    (setq +my/pdf--places
          (and (file-readable-p +my/pdf-places-file)
               (ignore-errors
                 (with-temp-buffer
                   (insert-file-contents +my/pdf-places-file)
                   (read (current-buffer)))))))
  +my/pdf--places)

(defun +my/pdf--kept-place ()
  "This PDF's place, from when it was last closed."
  (when buffer-file-name
    (cdr (assoc (abbreviate-file-name buffer-file-name) (+my/pdf--read-places)))))

(defun +my/pdf--keep-place (place)
  "Keep PLACE as this PDF's (see above)."
  (when (and place buffer-file-name)
    (let ((file (abbreviate-file-name buffer-file-name)))
      (setq +my/pdf--places
            (seq-take (cons (cons file place)
                            (seq-remove (lambda (entry) (equal (car entry) file))
                                        (+my/pdf--read-places)))
                      +my/pdf-places-max))
      (ignore-errors
        (make-directory (file-name-directory +my/pdf-places-file) t)
        (let ((print-length nil)
              (print-level nil))
          (with-temp-file +my/pdf-places-file
            (prin1 +my/pdf--places (current-buffer))))))))

(defun +my/pdf--forget-place (file)
  "Forget FILE's place (an example's PDF, deleted once closed)."
  (let ((file (abbreviate-file-name file)))
    (when (assoc file (+my/pdf--read-places))
      (setq +my/pdf--places (seq-remove (lambda (entry) (equal (car entry) file)) +my/pdf--places))
      (ignore-errors
        (let ((print-length nil)
              (print-level nil))
          (with-temp-file +my/pdf-places-file
            (prin1 +my/pdf--places (current-buffer))))))))

(defun +my/pdf--remember ()
  "Keep this page's settings for the next PDF, and its place (see above)."
  (when-let* ((state (+my/pdf--state)))
    (setq +my/pdf-dark-pages (plist-get state :dark)
          +my/pdf-toolbar (plist-get state :toolbar)
          +my/pdf-outline-sidebar (plist-get state :sidebar))
    (+my/pdf--keep-place (plist-get state :place))))

;; WATCHING THE PAGES ON SCREEN
;; Every 0.1 s, for each window showing a PDF, from its view's title (no
;; JavaScript, see WATCHING in config/webkit.el): its page in the window's
;; mode line, the toolbar's requests, and the mouse pointer the page wants
;; (hand: buttons, headings, thumbnails, links; text: the PDF's text; arrow).
(defun +my/pdf--show-page (window state)
  "The page of STATE in WINDOW's mode line (doom-modeline's PDF line, through
`+my/pdf--page')."
  (let* ((page (plist-get state :page))
         (pages (plist-get state :pages))
         (shown (cons (current-buffer)
                      (and (natnump pages) (> pages 0) (natnump page)
                           (format "  P%d/%d " page pages)))))
    (unless (equal shown (window-parameter window '+my/pdf-page))
      (set-window-parameter window '+my/pdf-page shown)
      (force-mode-line-update))))

(defun +my/pdf--page ()
  "The page of the PDF the mode line being drawn is for: its window's (each
window's view has its own). The window is the selected one meanwhile."
  (let ((shown (window-parameter nil '+my/pdf-page)))
    (and (eq (car shown) (current-buffer)) (cdr shown))))

;; doom-modeline's PDF line shows `doom-modeline--pdf-pages' as is, which in a
;; PDF is (:eval (+my/pdf--page)): a form the mode line only runs from
;; a variable marked risky.
(put 'doom-modeline--pdf-pages 'risky-local-variable t)

(defun +my/pdf--answer (xwidget state)
  "Run the toolbar's request in STATE, XWIDGET's, once (see above)."
  (let* ((action (plist-get state :action))
         (n (or (plist-get action :n) 0)))
    (unless (eql n (xwidget-get xwidget 'answered))
      (xwidget-put xwidget 'answered n)
      (when (> n 0)
        (pcase (plist-get action :name)
          ("preview" (+my/pdf-open-in-preview))
          ("print" (+my/pdf-print)))))))

(defun +my/pdf--watch (window xwidget)
  "WINDOW shows XWIDGET's view of the PDF: its page, the toolbar's requests,
the pointer (see above)."
  (when-let* ((state (+my/pdf--state xwidget)))
    (+my/pdf--show-page window state)
    (+my/pdf--answer xwidget state)
    (+my/webkit-pointer window (pcase (plist-get state :cursor)
                                 ("hand" 'hand) ("text" 'text) (_ 'arrow)))))

(defun +my/pdf--write-page (data)
  "Write the page's index.html, reading the PDF from DATA (a data-N.js)."
  (require 'json)
  (let ((page (format-spec
               +my/pdf--page-template
               `((?b . ,(+my/pdf--color 'default :background "#282c34"))
                 (?c . ,(if (eq (frame-parameter nil 'background-mode) 'light) "light" "dark"))
                 (?v . ,(+my/pdf--css-variables))
                 (?o . ,(+my/pdf--options))
                 (?p . ,(+my/webkit-file-url (file-name-as-directory +my/pdf-js-dir)))
                 (?j . ,(+my/webkit-file-url
                         (expand-file-name "config/pdf.js" doom-user-dir)))
                 (?d . ,(json-encode data))))))
    (with-temp-file (expand-file-name "index.html" +my/pdf--dir)
      (insert page))))

(defun +my/pdf--page-url ()
  "Make this buffer's page, in a folder of its own; return its URL. Without
PDF.js, the PDF's own (WebKit's viewer)."
  (if (not (+my/pdf-js-ensure))
      (progn (setq +my/pdf--native t)
             (+my/webkit-file-url buffer-file-name))
    (setq +my/pdf--native nil
          +my/pdf--dir (make-temp-file "pdf-" t)
          +my/pdf--data 0)
    (+my/pdf--write-page (+my/pdf--write-data))
    (+my/webkit-file-url (expand-file-name "index.html" +my/pdf--dir))))

(defun +my/pdf--url (_window)
  "The page a new view of the PDF loads (see VIEWS in config/webkit.el): made
the first time; written anew after, to start as the view latest looked at is
(settings, place)."
  (cond ((not +my/pdf--home)
         (setq +my/pdf--home (+my/pdf--page-url)))
        ((not +my/pdf--native)
         (+my/pdf--write-page (format "data-%d.js" +my/pdf--data))))
  +my/pdf--home)

(defun +my/pdf--js (script &optional all)
  "Run pdfx.SCRIPT in the selected window's page (ALL: in each of the PDF's
views), not waiting for an answer (see above)."
  (cond ((not (+my/webkit-xwidget)))
        (+my/pdf--native
         (message "No PDF.js here: M-x +my/pdf-js-install, then open the PDF again"))
        (t (+my/webkit-execute (concat "window.pdfx && pdfx." script) all))))

(defun +my/pdf--stop ()
  "Keep the PDF's place, delete its page's folder (another mode, the buffer
killed); its views close after (config/webkit.el)."
  (+my/pdf--remember)
  (when (and +my/pdf--dir (file-directory-p +my/pdf--dir))
    (delete-directory +my/pdf--dir t))
  (setq +my/pdf--dir nil))

;; Quitting Emacs kills no buffers: the open PDFs' places would be lost, and
;; the pages' folders (a copy of each PDF) would stay.
(add-hook 'kill-emacs-hook
          (defun +my/pdf--cleanup-h ()
            (dolist (buffer (buffer-list))
              (when (eq (buffer-local-value 'major-mode buffer) '+my/pdf-mode)
                (with-current-buffer buffer
                  (ignore-errors (+my/pdf--remember))))
              (when-let* ((dir (buffer-local-value '+my/pdf--dir buffer)))
                (ignore-errors (delete-directory dir t))))))

(defun +my/pdf--revert (&rest _)
  "Show the PDF anew from its file, where it was (see above)."
  (set-visited-file-modtime)
  (when-let* ((xwidgets (+my/webkit-xwidgets)))
    (if (or +my/pdf--native (not +my/pdf--dir))
        (dolist (xwidget xwidgets)
          (xwidget-webkit-goto-uri xwidget +my/pdf--home))
      (let ((data (+my/pdf--write-data)))
        ;; Also for the page loaded anew (back from a link, a new view).
        (+my/pdf--write-page data)
        (setq +my/pdf--searching nil)
        (+my/pdf--js (format "reload(%s)" (json-encode data)) t)))))

;; COMMANDS (see above)
(defun +my/pdf--scroll (dx dy)
  (+my/pdf--js (format "scroll(%d, %d)" dx dy)))

(defun +my/pdf-scroll-down (&optional count)
  "j: scroll the PDF down."
  (interactive "p")
  (+my/pdf--scroll 0 (* (or count 1) +my/pdf-scroll-step)))

(defun +my/pdf-scroll-up (&optional count)
  "k: scroll the PDF up."
  (interactive "p")
  (+my/pdf--scroll 0 (- (* (or count 1) +my/pdf-scroll-step))))

(defun +my/pdf-scroll-right (&optional count)
  "l: scroll the PDF right (zoomed in)."
  (interactive "p")
  (+my/pdf--scroll (* (or count 1) +my/pdf-scroll-step) 0))

(defun +my/pdf-scroll-left (&optional count)
  "h: scroll the PDF left (zoomed in)."
  (interactive "p")
  (+my/pdf--scroll (- (* (or count 1) +my/pdf-scroll-step)) 0))

(defun +my/pdf-half-screen-down ()
  "C-d: scroll the PDF down half a screen."
  (interactive)
  (+my/pdf--js "screen(0.5)"))

(defun +my/pdf-half-screen-up ()
  "C-u: scroll the PDF up half a screen."
  (interactive)
  (+my/pdf--js "screen(-0.5)"))

(defun +my/pdf-screen-down ()
  "C-f: scroll the PDF down a screen (a bit less, to keep your place)."
  (interactive)
  (+my/pdf--js "screen(0.9)"))

(defun +my/pdf-screen-up ()
  "C-b: scroll the PDF up a screen (a bit less, to keep your place)."
  (interactive)
  (+my/pdf--js "screen(-0.9)"))

(defun +my/pdf-top (&optional page)
  "gg: the PDF's start; with a count, that page."
  (interactive "P")
  (+my/pdf--js (if page
                           (format "goto(%d)" (prefix-numeric-value page))
                         "top()")))

(defun +my/pdf-bottom (&optional page)
  "G: the PDF's end; with a count, that page."
  (interactive "P")
  (+my/pdf--js (if page
                           (format "goto(%d)" (prefix-numeric-value page))
                         "bottom()")))

(defun +my/pdf-next-page (&optional count)
  "J: the next page."
  (interactive "p")
  (+my/pdf--js (format "page(%d)" (or count 1))))

(defun +my/pdf-previous-page (&optional count)
  "K: the previous page."
  (interactive "p")
  (+my/pdf--js (format "page(%d)" (- (or count 1)))))

(defun +my/pdf-back ()
  "C-o / Cmd+[: back to where the last jump left from (see above)."
  (interactive)
  (+my/pdf--js "back()"))

(defun +my/pdf-forward ()
  "C-i / Cmd+]: forward again, after going back (see above)."
  (interactive)
  (+my/pdf--js "forward()"))

(defun +my/pdf--find (query &optional backward)
  "Search the PDF for QUERY (its spaces and line breaks as single spaces);
BACKWARD towards its start. An empty QUERY ends the search."
  (require 'json)
  (let ((query (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " query))))
    (setq +my/pdf--searching (not (string-empty-p query)))
    (+my/pdf--js (format "find(%s, %s)" (json-encode query)
                                 (if backward "true" "false")))))

(defun +my/pdf-search (&optional backward)
  "/: search the PDF (case-sensitive with a capital), from where it shows;
BACKWARD (?) towards its start. Esc ends the search."
  (interactive)
  (+my/pdf--find (read-string (if backward "Search backward: " "Search: ")
                                      nil '+my/pdf--search-history)
                         backward))

(defun +my/pdf-search-backward ()
  "?: search the PDF towards its start (see `+my/pdf-search')."
  (interactive)
  (+my/pdf-search t))

(defun +my/pdf-search-next ()
  "n: the search's next match."
  (interactive)
  (+my/pdf--js "again(false)"))

(defun +my/pdf-search-previous ()
  "N: the search's previous match."
  (interactive)
  (+my/pdf--js "again(true)"))

(defun +my/pdf--escape-h ()
  "Esc in a PDF ends its search (highlights and count)."
  (when (and (derived-mode-p '+my/pdf-mode) +my/pdf--searching)
    (setq +my/pdf--searching nil)
    (+my/pdf--js "endFind()" t)
    t))

(add-hook 'doom-escape-hook #'+my/pdf--escape-h)

(defun +my/pdf--toggle (setting name was)
  "Turn the page's SETTING (\"dark\", \"toolbar\", \"sidebar\") on or off,
as the selected window's is, in all of the PDF's views (see VIEWS), and say so,
NAME being what it is; return whether it's on, WAS (as it was for the next PDF)
if it can't."
  (if (or (not (+my/webkit-xwidget)) +my/pdf--native)
      (progn (message "No PDF.js here: M-x +my/pdf-js-install, then open the PDF again")
             was)
    (let ((on (not (plist-get (+my/pdf--state) (intern (concat ":" setting))))))
      (+my/pdf--js (format "set({%s: %s})" setting (if on "true" "false")) t)
      (message "%s %s" name (if on "on" "off"))
      on)))

(defun +my/pdf-toggle-dark ()
  "SPC m d: dark pages on or off (see above)."
  (interactive)
  (setq +my/pdf-dark-pages (+my/pdf--toggle "dark" "Dark pages"
                                                             +my/pdf-dark-pages)))

(defun +my/pdf-toggle-toolbar ()
  "SPC m t: the toolbar on or off (see above)."
  (interactive)
  (setq +my/pdf-toolbar (+my/pdf--toggle "toolbar" "Toolbar"
                                                         +my/pdf-toolbar)))

(defun +my/pdf-toggle-sidebar ()
  "O: the sidebar (outline, pages) on or off (see above)."
  (interactive)
  (setq +my/pdf-outline-sidebar (+my/pdf--toggle "sidebar" "Sidebar"
                                                                 +my/pdf-outline-sidebar)))

;; PREVIEW AND PRINT
(defun +my/pdf-open-in-preview ()
  "SPC m p: the PDF in macOS's Preview (to sign, annotate...)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (call-process "open" nil 0 nil "-a" "Preview" (expand-file-name buffer-file-name)))

(defun +my/pdf-print ()
  "Cmd+P: print the PDF, in Preview's print dialog (macOS asks once to let
Emacs control Preview)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (make-process
   :name "pdf-print"
   :noquery t
   :command (list "osascript"
                  "-e" "on run argv"
                  "-e" "tell application \"Preview\""
                  "-e" "activate"
                  "-e" "print ((POSIX file (item 1 of argv)) as alias) with print dialog"
                  "-e" "end tell"
                  "-e" "end run"
                  (expand-file-name buffer-file-name))
   :sentinel (lambda (process _event)
               (when (and (eq (process-status process) 'exit)
                          (/= (process-exit-status process) 0))
                 (message "Couldn't print through Preview: SPC m p opens it there, then Cmd+P")))))

;; OPTION+ENTER (config/actions.el)
;; The menu's PDF actions, for the text selected in the page, which Emacs asks
;; the page for (an answer awaited, its function a symbol, as for copying)
;; before showing the menu.
(defvar-local +my/pdf--selection nil
  "The page's selected text while the actions menu is up.")

(defvar +my/pdf--actions-for nil
  "The PDF whose selection was asked for: WebKit's answer doesn't say.")

(defun +my/pdf-actions ()
  "Option+Enter: the actions menu, with the PDF's for its selected text."
  (interactive)
  (setq +my/pdf--actions-for (current-buffer))
  (unless (and (not +my/pdf--native)
               (+my/webkit-ask "window.pdfx ? pdfx.selection() : ''"
                               #'+my/pdf--selection-received))
    (+my/pdf--actions-menu (current-buffer) nil)))

(defun +my/pdf--selection-received (text)
  "WebKit's answer to `+my/pdf-actions': the menu after this event,
not inside it."
  (run-at-time 0 nil #'+my/pdf--actions-menu +my/pdf--actions-for text))

(defun +my/pdf--actions-menu (buffer text)
  "The actions menu for BUFFER's PDF, TEXT selected in it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq +my/pdf--selection (and (stringp text) (not (string-blank-p text)) text))
      (unwind-protect (+my/context-actions)
        (setq +my/pdf--selection nil)))))

(defun +my/pdf--claude-context (text)
  "For `+my/claude-ask': TEXT quoted, after the PDF's file and page."
  (let ((file buffer-file-name)
        (page (plist-get (+my/pdf--state) :page)))
    (lambda (cwd)
      (let ((relative (and cwd file (file-relative-name file cwd))))
        (format "From %s%s:\n\n%s"
                (if (and relative (not (string-prefix-p ".." relative)))
                    relative
                  (abbreviate-file-name (or file (buffer-name))))
                (if (natnump page) (format ", page %d" page) "")
                (replace-regexp-in-string "^" "> " (string-trim text)))))))

(defun +my/context-actions-pdf ()
  "In a PDF: for its selected text, copy, search the PDF or the web, Claude;
always Preview and print."
  (when (derived-mode-p '+my/pdf-mode)
    (let ((text +my/pdf--selection)
          (buffer (current-buffer)))
      (append
       (when text
         (list (list "PDF" "Copy" (lambda () (+my/webkit-copied text)))
               (list "PDF" "Search the PDF for it"
                     (lambda () (with-current-buffer buffer (+my/pdf--find text))))
               (list "PDF" "Search the web for it"
                     (lambda ()
                       (require 'url-util)
                       (browse-url (concat "https://www.google.com/search?q="
                                           (url-hexify-string (string-trim text))))))
               (list "Claude" "Explain selection with Claude"
                     (lambda ()
                       (with-current-buffer buffer
                         (+my/claude-ask "Explain this passage. Don't change any files."
                                         (+my/pdf--claude-context text)))))
               (list "Claude" "Add selection to Claude prompt"
                     (lambda ()
                       (with-current-buffer buffer
                         (require 'agent-shell)
                         (agent-shell-insert
                          :text (funcall (+my/pdf--claude-context text) (agent-shell-cwd))
                          :shell-buffer (agent-shell-shell-buffer)))))))
       (list (list "PDF" "Open in Preview"
                   (lambda () (with-current-buffer buffer (+my/pdf-open-in-preview))))
             (list "PDF" "Print..."
                   (lambda () (with-current-buffer buffer (+my/pdf-print)))))))))

;; First in the menu (config/actions.el is loaded before this file).
(when (boundp '+my/context-action-providers)
  (add-to-list '+my/context-action-providers #'+my/context-actions-pdf))

;; The mode line: doom-modeline's PDF line, with the page (see WATCHING).
(after! doom-modeline
  (add-to-list 'doom-modeline-mode-alist '(+my/pdf-mode . pdf)))

;; THE OUTLINE IN THE MINIBUFFER (o)
;; The page's headings, as `parent › heading' with their page, in their order.
(defvar +my/pdf--outline-for nil
  "The PDF whose outline was asked for: WebKit's answer doesn't say.")

(defun +my/pdf-outline ()
  "o: go to a heading of the PDF's outline, picked in the minibuffer."
  (interactive)
  (setq +my/pdf--outline-for (current-buffer))
  ;; An answer awaited (see JAVASCRIPT in config/webkit.el).
  (unless (and (not +my/pdf--native)
               (+my/webkit-ask "window.pdfx ? pdfx.outlineList() : '[]'"
                               #'+my/pdf--outline-received))
    (message "No outline here (no PDF.js)")))

(defun +my/pdf--outline-received (json)
  "WebKit's answer to `+my/pdf-outline': the minibuffer after this
event, not inside it."
  (run-at-time 0 nil #'+my/pdf--outline-pick +my/pdf--outline-for json))

(defun +my/pdf--outline-pick (buffer json)
  "Pick one of the headings in JSON, BUFFER's page's, and go there."
  (let ((headings (and (stringp json)
                       (ignore-errors
                         (json-parse-string json :array-type 'list :object-type 'plist
                                            :null-object nil))))
        (separator (if (boundp '+my/sticky-separator) +my/sticky-separator " › "))
        (seen (make-hash-table :test #'equal))
        candidates)
    (if (not headings)
        (message "This PDF has no outline")
      (let ((index 0))
        (dolist (heading headings)
          (let* ((titles (plist-get heading :t))
                 (parents (butlast titles))
                 (name (concat (if parents
                                   (propertize (concat (string-join parents separator) separator)
                                               'face 'shadow)
                                 "")
                               (car (last titles))))
                 (count (puthash name (1+ (gethash name seen 0)) seen)))
            ;; Same names (two "Introduction"s) told apart.
            (when (> count 1)
              (setq name (concat name (propertize (format " (%d)" count) 'face 'shadow))))
            (push (list name index (plist-get heading :p)) candidates)
            (setq index (1+ index)))))
      (setq candidates (nreverse candidates))
      (let* ((annotate (lambda (name)
                         (when-let* ((page (nth 2 (assoc name candidates))))
                           (propertize (format "  p. %d" page) 'face 'completions-annotations))))
             (choice (completing-read
                      "Outline: "
                      (lambda (string predicate action)
                        (if (eq action 'metadata)
                            `(metadata (display-sort-function . identity)
                                       (cycle-sort-function . identity)
                                       (annotation-function . ,annotate))
                          (complete-with-action action candidates string predicate)))
                      nil t))
             (index (nth 1 (assoc choice candidates))))
        (when (and index (buffer-live-p buffer))
          (with-current-buffer buffer
            (+my/pdf--js (format "outlineGo(%d)" index))))))))

(defun +my/pdf-zoom-in ()
  "Cmd+=: zoom the PDF in."
  (interactive)
  (+my/pdf--js (format "zoom(%s)" +my/pdf-zoom-step)))

(defun +my/pdf-zoom-out ()
  "Cmd+-: zoom the PDF out."
  (interactive)
  (+my/pdf--js (format "zoom(%s)" (/ 1.0 +my/pdf-zoom-step))))

(defun +my/pdf-actual-size ()
  "Cmd+0: the PDF at 100%."
  (interactive)
  (+my/pdf--js "fit('page-actual')"))

(defun +my/pdf-fit-width ()
  "W: the PDF as wide as the window (as it opens)."
  (interactive)
  (+my/pdf--js "fit('page-width')"))

(defun +my/pdf-fit-page ()
  "P: a whole page in the window."
  (interactive)
  (+my/pdf--js "fit('page-fit')"))

(define-derived-mode +my/pdf-mode +my/webkit-mode "PDF"
  "A PDF in WebKit, drawn by PDF.js (see config/pdf.el), a view per
window (config/webkit.el). The file's bytes stay in the buffer, unchanged:
WebKit is shown over them.

\\{+my/pdf-mode-map}"
  (setq-local font-lock-defaults '(nil t)  ; nothing to colour in a PDF's bytes
              revert-buffer-function #'+my/pdf--revert
              +my/webkit-url-function #'+my/pdf--url
              +my/webkit-watch-function #'+my/pdf--watch
              +my/webkit-selection-script
              "window.pdfx ? pdfx.selection() : String(window.getSelection())"
              ;; Each window's page (see WATCHING).
              doom-modeline--pdf-pages '(:eval (+my/pdf--page)))
  (add-hook 'change-major-mode-hook #'+my/pdf--stop nil t)
  (add-hook 'kill-buffer-hook #'+my/pdf--stop nil t))

;; Evil keys (see above) in normal state.
(after! evil
  (evil-set-initial-state '+my/pdf-mode 'normal))
