;;; $DOOMDIR/config/pdf-xwidget.el -*- lexical-binding: t; -*-
;; PDFs in WebKit (xwidgets), drawn by PDF.js. Loaded from config.el.

;; ====== VARIABLES ======

;; PDFS IN WEBKIT
;; PDFs open inside the file's tab as a web page in WebKit, like the Markdown
;; preview, drawn by PDF.js (Mozilla's PDF renderer, Firefox's), instead of
;; pdf-tools (Doom's pdf module is off in init.el; its setup is kept in
;; config/pdf.el): pages sharp at any zoom, smooth trackpad scrolling, text
;; selectable with the mouse. Not WebKit's own PDF viewer: on macOS Emacs takes
;; every key, so none reached it, and its buttons and selection didn't work in
;; Emacs. A page drawn by PDF.js is plain HTML (config/pdf-xwidget.js) that
;; Emacs drives with JavaScript, so Evil keys work:
;;   j / k, h / l   scroll (+my/pdf-xwidget-scroll-step), C-d / C-u half a
;;                  screen, C-f / C-b a screen, gg / G top / bottom (5G: page 5)
;;   J / K          next / previous page
;;   / and ?        search forward / backward (smart case), n / N next /
;;                  previous match, Esc ends it
;;   y or Cmd+C     copy the selected text (kill ring and clipboard)
;;   Cmd+= / Cmd+-  zoom (also + / -, Cmd+scroll), Cmd+0 100%, W fit the
;;                  width (as it opens), P the page
;;   q              close
;; The page shows the page number while it changes, and the search's matches.
;; Links out of the PDF open in the browser. A PDF changed on disk (e.g.
;; rebuilt by LaTeX) is shown anew, where it was: `revert-buffer', so also
;; Doom's auto-revert.
;; PDF.js (pdfjs-dist 3.11: newer versions only ship ES modules, which a
;; file:// page may not load) is downloaded once, from jsdelivr, each file
;; checked against its SHA-256 below (M-x +my/pdf-js-install does it again).
;; Without it (e.g. offline), WebKit's own viewer: trackpad only. In a
;; terminal, or an Emacs without xwidgets: doc-view, Emacs's own viewer.
;; JavaScript runs without waiting for answers, except the selection (y,
;; Cmd+C): closing a WebKit view while an answer was pending crashed Emacs
;; (see config/markdown.el).
(defvar +my/pdf-xwidget-scroll-step 60
  "Pixels j / k / h / l scroll a PDF.")

(defvar +my/pdf-xwidget-zoom-step 1.25
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

(defvar +my/pdf-xwidget-mode-map (make-sparse-keymap)
  "Keys of PDFs in WebKit (see `+my/pdf-xwidget-mode').")

;; ====== KEY BINDINGS ======

(map! :map +my/pdf-xwidget-mode-map
      "s-="      #'+my/pdf-xwidget-zoom-in
      "s-+"      #'+my/pdf-xwidget-zoom-in
      "s--"      #'+my/pdf-xwidget-zoom-out
      "s-0"      #'+my/pdf-xwidget-actual-size
      "s-c"      #'+my/pdf-xwidget-copy
      :nm "j"       #'+my/pdf-xwidget-scroll-down
      :nm "k"       #'+my/pdf-xwidget-scroll-up
      :nm "h"       #'+my/pdf-xwidget-scroll-left
      :nm "l"       #'+my/pdf-xwidget-scroll-right
      :nm "<down>"  #'+my/pdf-xwidget-scroll-down
      :nm "<up>"    #'+my/pdf-xwidget-scroll-up
      :nm "<left>"  #'+my/pdf-xwidget-scroll-left
      :nm "<right>" #'+my/pdf-xwidget-scroll-right
      :nm "C-d"     #'+my/pdf-xwidget-half-screen-down
      :nm "C-u"     #'+my/pdf-xwidget-half-screen-up
      :nm "C-f"     #'+my/pdf-xwidget-screen-down
      :nm "C-b"     #'+my/pdf-xwidget-screen-up
      :nm "<next>"  #'+my/pdf-xwidget-screen-down
      :nm "<prior>" #'+my/pdf-xwidget-screen-up
      :nm "gg"      #'+my/pdf-xwidget-top
      :nm "G"       #'+my/pdf-xwidget-bottom
      :nm "<home>"  #'+my/pdf-xwidget-top
      :nm "<end>"   #'+my/pdf-xwidget-bottom
      :nm "J"       #'+my/pdf-xwidget-next-page
      :nm "K"       #'+my/pdf-xwidget-previous-page
      :nm "/"       #'+my/pdf-xwidget-search
      :nm "?"       #'+my/pdf-xwidget-search-backward
      :nm "n"       #'+my/pdf-xwidget-search-next
      :nm "N"       #'+my/pdf-xwidget-search-previous
      :nm "y"       #'+my/pdf-xwidget-copy
      :nm "+"       #'+my/pdf-xwidget-zoom-in
      :nm "="       #'+my/pdf-xwidget-zoom-in
      :nm "-"       #'+my/pdf-xwidget-zoom-out
      :nm "W"       #'+my/pdf-xwidget-fit-width
      :nm "P"       #'+my/pdf-xwidget-fit-page
      :gnm "q"      #'kill-current-buffer    ; as Doom's pdf-tools did
      ;; Clicks are WebKit's (selecting text, links): Emacs only selects the
      ;; window, instead of starting a selection of its own (Evil's visual
      ;; state, where the keys above don't apply).
      :gnmv [down-mouse-1]        #'+my/pdf-xwidget-mouse-select
      :gnmv [mouse-1]             #'ignore
      :gnmv [drag-mouse-1]        #'ignore
      :gnmv [double-down-mouse-1] #'ignore
      :gnmv [double-mouse-1]      #'ignore
      :gnmv [triple-down-mouse-1] #'ignore
      :gnmv [triple-mouse-1]      #'ignore)

;; ====== CODE ======

(defvar-local +my/pdf-xwidget--starting nil
  "Non-nil once WebKit is on its way (see `+my/pdf-xwidget--shown-h').")

(defvar-local +my/pdf-xwidget--cover nil
  "(FRAME . TIMER): the frame over the PDF while WebKit loads it.")

(defvar-local +my/pdf-xwidget--dir nil
  "The page's folder: index.html and the PDF's data, as base64.")

(defvar-local +my/pdf-xwidget--data 0
  "N of the PDF's latest data-N.js.")

(defvar-local +my/pdf-xwidget--native nil
  "Non-nil if WebKit's own viewer shows the PDF (no PDF.js).")

(defvar-local +my/pdf-xwidget--home nil
  "The URL WebKit was given: anywhere else is a link out of the PDF.")

(defvar-local +my/pdf-xwidget--followed nil
  "(URL . TIME): the link out of the PDF last opened in the browser.")

(defvar-local +my/pdf-xwidget--searching nil
  "Non-nil while a search shows its matches (Esc ends it).")

(defvar +my/pdf-xwidget--search-history nil)

(defconst +my/pdf-xwidget--page-template
  "<!doctype html>
<html><head><meta charset=\"utf-8\">
<link rel=\"stylesheet\" href=\"%ppdf_viewer.css\">
<style>
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
<script src=\"%j\"></script>
<script>
if (window.pdfx) pdfx.open(%d);
else { var b = document.getElementById('find'); b.textContent = 'PDF.js did not load'; b.className = 'badge on'; }
</script>
</body></html>
"
  "A PDF's page (see config/pdf-xwidget.js), for `format-spec': %b the
background, %c the colour scheme, %p PDF.js's folder, %j the script, %d the
data file's name (JSON).")

(defun +my/pdf-xwidget-p ()
  "Non-nil if this buffer's PDF can show in WebKit: a local file, in the GUI,
in an Emacs with xwidgets."
  (and buffer-file-name (not (file-remote-p buffer-file-name))
       (display-graphic-p) (featurep 'xwidget-internal)))

(defun +my/pdf-xwidget-mode-maybe ()
  "PDFs' major mode: WebKit where it works, doc-view otherwise (see above)."
  (if (+my/pdf-xwidget-p)
      (+my/pdf-xwidget-mode)
    (doc-view-mode-maybe)))

;; Ahead of Doom's pdf-tools (until `doom sync' and a restart take it out) and
;; Emacs's doc-view: magic-mode-alist (the file starts with %PDF) wins over the
;; file name.
(add-to-list 'auto-mode-alist '("\\.[pP][dD][fF]\\'" . +my/pdf-xwidget-mode-maybe))
(add-to-list 'magic-mode-alist '("%PDF" . +my/pdf-xwidget-mode-maybe))

;; No "File is large, really open?" for PDFs, as with Doom's pdf module: only
;; WebKit reads them.
(defadvice! +my/pdf-xwidget-no-large-file-prompt-a (fn size op-type filename &optional offer-raw)
  :around #'abort-if-file-too-large
  (unless (string-match-p "\\.[pP][dD][fF]\\'" filename)
    (funcall fn size op-type filename offer-raw)))

;; PDF.JS
(defun +my/pdf-js-installed-p ()
  "Non-nil if PDF.js is in `+my/pdf-js-dir'."
  (seq-every-p (lambda (file)
                 (file-exists-p (expand-file-name (file-name-nondirectory (car file))
                                                  +my/pdf-js-dir)))
               +my/pdf-js-files))

(defun +my/pdf-js-install ()
  "Download PDF.js into `+my/pdf-js-dir', checking each file's SHA-256."
  (interactive)
  (require 'url)
  (make-directory +my/pdf-js-dir t)
  (pcase-dolist (`(,path . ,sha256) +my/pdf-js-files)
    (let* ((url (format "https://cdn.jsdelivr.net/npm/pdfjs-dist@%s/%s"
                        +my/pdf-js-version path))
           (file (expand-file-name (file-name-nondirectory path) +my/pdf-js-dir))
           (part (concat file ".part")))
      (message "Downloading PDF.js: %s..." path)
      (url-copy-file url part t)
      (unless (equal (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally part)
                       (secure-hash 'sha256 (current-buffer)))
                     sha256)
        (delete-file part)
        (error "PDF.js: %s isn't the file expected (SHA-256 differs), not installed" url))
      (rename-file part file t)))
  (message "PDF.js %s installed in %s" +my/pdf-js-version +my/pdf-js-dir))

(defun +my/pdf-js-ensure ()
  "Non-nil if PDF.js is there, downloaded now if need be (see above)."
  (or (+my/pdf-js-installed-p)
      (condition-case err
          (progn (+my/pdf-js-install) t)
        (error (message "PDFs in WebKit's own viewer: %s" (error-message-string err))
               nil))))

;; THE PAGE (see config/pdf-xwidget.js)
(defun +my/pdf-xwidget--file-url (file)
  "FILE's file:// URL. Spaces and such encoded: Emacs's macOS WebKit doesn't
check that a URL is valid."
  (require 'url-util)
  (concat "file://" (url-hexify-string (expand-file-name file) url-path-allowed-chars)))

(defun +my/pdf-xwidget--write-data ()
  "Write the PDF, as base64, to the page's next data-N.js; return its name."
  (let* ((name (format "data-%d.js" (setq +my/pdf-xwidget--data (1+ +my/pdf-xwidget--data))))
         (old (expand-file-name (format "data-%d.js" (1- +my/pdf-xwidget--data))
                                +my/pdf-xwidget--dir))
         (pdf buffer-file-name)
         (coding-system-for-write 'no-conversion))
    (with-temp-file (expand-file-name name +my/pdf-xwidget--dir)
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

(defun +my/pdf-xwidget--write-page (data)
  "Write the page's index.html, reading the PDF from DATA (a data-N.js)."
  (require 'json)
  (let ((page (format-spec
               +my/pdf-xwidget--page-template
               `((?b . ,(face-background 'default nil t))
                 (?c . ,(if (eq (frame-parameter nil 'background-mode) 'light) "light" "dark"))
                 (?p . ,(+my/pdf-xwidget--file-url (file-name-as-directory +my/pdf-js-dir)))
                 (?j . ,(+my/pdf-xwidget--file-url
                         (expand-file-name "config/pdf-xwidget.js" doom-user-dir)))
                 (?d . ,(json-encode data))))))
    (with-temp-file (expand-file-name "index.html" +my/pdf-xwidget--dir)
      (insert page))))

(defun +my/pdf-xwidget--page-url ()
  "Make this buffer's page, in a folder of its own; return its URL. Without
PDF.js, the PDF's own (WebKit's viewer)."
  (if (not (+my/pdf-js-ensure))
      (progn (setq +my/pdf-xwidget--native t)
             (+my/pdf-xwidget--file-url buffer-file-name))
    (setq +my/pdf-xwidget--native nil
          +my/pdf-xwidget--dir (make-temp-file "pdf-xwidget-" t)
          +my/pdf-xwidget--data 0)
    (+my/pdf-xwidget--write-page (+my/pdf-xwidget--write-data))
    (+my/pdf-xwidget--file-url (expand-file-name "index.html" +my/pdf-xwidget--dir))))

(defun +my/pdf-xwidget--xwidget ()
  "This buffer's WebKit view, once it has one."
  (xwidget-at (point-min)))

(defun +my/pdf-xwidget--js (script)
  "Run SCRIPT in the page, not waiting for an answer (see above)."
  (let ((xwidget (+my/pdf-xwidget--xwidget)))
    (cond ((not xwidget))
          (+my/pdf-xwidget--native
           (message "No PDF.js here: M-x +my/pdf-js-install, then open the PDF again"))
          ;; `void': nothing comes back (a Promise, say, made WebKit log an
          ;; error about its type).
          (t (xwidget-webkit-execute-script
              xwidget (concat "window.pdfx && void pdfx." script))))))

;; NO WHITE FLASH
;; WebKit's view is white until its page has loaded. WebKit only starts once
;; the buffer is on screen (nothing shown until then, in the theme's colour),
;; under a borderless frame in the theme's background colour, like the
;; Markdown preview's: it goes once WebKit says the page has loaded, or after
;; 2 s. The page is in the theme's colour too, around the pages.
(defun +my/pdf-xwidget--uncover (buffer)
  "Take the cover off BUFFER's PDF."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((cover +my/pdf-xwidget--cover))
        (setq +my/pdf-xwidget--cover nil)
        (when (timerp (cdr cover)) (cancel-timer (cdr cover)))
        (+my/banner--delete-frame (car cover))))))

(defun +my/pdf-xwidget--cover-window (window)
  "Cover WINDOW's text area in the theme's background colour (see above)."
  (+my/pdf-xwidget--uncover (current-buffer))
  (when (fboundp '+my/banner--make-frame)
    (let ((frame (+my/banner--make-frame (window-frame window)))
          (edges (window-inside-pixel-edges window))
          (frame-resize-pixelwise t))
      (set-frame-parameter frame 'background-color (face-background 'default nil t))
      (set-frame-size frame (- (nth 2 edges) (nth 0 edges))
                      (- (nth 3 edges) (nth 1 edges)) t)
      (set-frame-position frame (nth 0 edges) (nth 1 edges))
      (make-frame-visible frame)
      (setq +my/pdf-xwidget--cover
            (cons frame (run-at-time 2 nil #'+my/pdf-xwidget--uncover
                                     (current-buffer)))))))

;; LINKS OUT OF THE PDF
;; PDF.js makes them plain links: WebKit would leave the PDF for the page.
;; Its first step (load-started) is stopped and the link opened in the
;; browser; had it gone further, WebKit goes back to the PDF.
(defun +my/pdf-xwidget--url-file (url)
  "The file a file:// URL names."
  (require 'url-parse)
  (decode-coding-string (url-unhex-string (url-filename (url-generic-parse-url url)))
                        'utf-8))

(defun +my/pdf-xwidget--elsewhere-p (url)
  "Non-nil if WebKit at URL has left the PDF's page (by the file, not the URL
text: WebKit may encode it otherwise)."
  (and (stringp url) +my/pdf-xwidget--home
       (or (string-match-p "\\`\\(?:https?\\|ftp\\|mailto\\):" url)
           (and (string-prefix-p "file:" url)
                (not (equal (file-truename (+my/pdf-xwidget--url-file url))
                            (file-truename (+my/pdf-xwidget--url-file
                                            +my/pdf-xwidget--home))))))))

(defun +my/pdf-xwidget--link-out (xwidget url status)
  "WebKit is following a link out of the PDF, to URL (see above)."
  (unless (and (equal (car +my/pdf-xwidget--followed) url)
               (< (float-time (time-since (cdr +my/pdf-xwidget--followed))) 5))
    (setq +my/pdf-xwidget--followed (cons url (current-time)))
    (browse-url url))
  (if (equal status "load-started")
      (ignore-errors (xwidget-webkit-stop-loading xwidget))
    (when (equal status "load-committed")
      (xwidget-webkit-goto-history xwidget -1))))

(defun +my/pdf-xwidget--callback (xwidget event-type)
  "WebKit's events: the page has loaded (see NO WHITE FLASH), links out of
the PDF (see above); others as usual (not `xwidget-webkit-callback' for loads:
it renames the buffer after the page)."
  (let ((buffer (xwidget-buffer xwidget)))
    (cond ((not (eq event-type 'load-changed))
           (xwidget-webkit-callback xwidget event-type))
          ((buffer-live-p buffer)
           (with-current-buffer buffer
             (let ((status (nth 3 last-input-event))
                   (url (xwidget-webkit-uri xwidget)))
               (cond ((+my/pdf-xwidget--elsewhere-p url)
                      (+my/pdf-xwidget--link-out xwidget url status))
                     ((equal status "load-finished")
                      ;; A moment for WebKit to paint it.
                      (run-at-time 0.05 nil #'+my/pdf-xwidget--uncover buffer)))))))))

(defun +my/pdf-xwidget--start (buffer window)
  "Show BUFFER's PDF in WebKit, in WINDOW, covered while it loads."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((window (if (and (window-live-p window) (eq (window-buffer window) buffer))
                        window
                      (get-buffer-window buffer 'visible))))
        (cond ((not (derived-mode-p '+my/pdf-xwidget-mode)))
              ((+my/pdf-xwidget--xwidget))
              ((not window)               ; gone meanwhile: when next shown
               (setq +my/pdf-xwidget--starting nil))
              (t
               ;; First, as it may download PDF.js (the cover only lasts 2 s).
               (setq +my/pdf-xwidget--home (+my/pdf-xwidget--page-url))
               ;; Edge to edge: no fringes (also buffer-local, for other windows).
               (set-window-fringes window 0 0)
               (+my/pdf-xwidget--cover-window window)
               (let ((xwidget (make-xwidget 'webkit (buffer-name)
                                            (xwidget-window-inside-pixel-width window)
                                            (xwidget-window-inside-pixel-height window)
                                            nil buffer)))
                 ;; Closing the tab doesn't ask "Buffer has xwidgets; kill it?".
                 (set-xwidget-query-on-exit-flag xwidget nil)
                 (xwidget-put xwidget 'callback #'+my/pdf-xwidget--callback)
                 (with-silent-modifications
                   (put-text-property (point-min) (point-max)
                                      'display (list 'xwidget :xwidget xwidget)))
                 (xwidget-webkit-goto-uri xwidget +my/pdf-xwidget--home))))))))

(defun +my/pdf-xwidget--shown-h (window)
  "Start WebKit once the PDF is on screen, in WINDOW (see NO WHITE FLASH).
After this redisplay: the cover is a frame, not made during redisplay."
  (with-current-buffer (window-buffer window)
    (unless +my/pdf-xwidget--starting
      (setq +my/pdf-xwidget--starting t)
      (run-at-time 0 nil #'+my/pdf-xwidget--start (current-buffer) window))))

(defun +my/pdf-xwidget--fit-h (window)
  "Make WebKit's view as big as WINDOW (it keeps the size it was made with)."
  (with-current-buffer (window-buffer window)
    (when-let* ((xwidget (+my/pdf-xwidget--xwidget)))
      (xwidget-webkit-adjust-size-to-window xwidget window))))

(defun +my/pdf-xwidget--home-h ()
  "Keep point and the window's start at the buffer's start, where WebKit is:
moved, the window scrolled it away."
  (unless (= (point) (point-min))
    (goto-char (point-min)))
  (unless (or (not (eq (window-buffer) (current-buffer)))
              (= (window-start) (point-min)))
    (set-window-start nil (point-min))))

(defun +my/pdf-xwidget--stop ()
  "Close this buffer's WebKit view and its page (another mode, the buffer
killed)."
  (+my/pdf-xwidget--uncover (current-buffer))
  (when-let* ((xwidget (+my/pdf-xwidget--xwidget)))
    (kill-xwidget xwidget))
  (with-silent-modifications
    (remove-text-properties (point-min) (point-max) '(display nil)))
  (when (and +my/pdf-xwidget--dir (file-directory-p +my/pdf-xwidget--dir))
    (delete-directory +my/pdf-xwidget--dir t))
  (setq +my/pdf-xwidget--dir nil))

;; Quitting Emacs kills no buffers: the pages' folders (a copy of each PDF)
;; would stay.
(add-hook 'kill-emacs-hook
          (defun +my/pdf-xwidget--cleanup-h ()
            (dolist (buffer (buffer-list))
              (when-let* ((dir (buffer-local-value '+my/pdf-xwidget--dir buffer)))
                (ignore-errors (delete-directory dir t))))))

(defun +my/pdf-xwidget--revert (&rest _)
  "Show the PDF anew from its file, where it was (see above)."
  (set-visited-file-modtime)
  (when-let* ((xwidget (+my/pdf-xwidget--xwidget)))
    (if (or +my/pdf-xwidget--native (not +my/pdf-xwidget--dir))
        (xwidget-webkit-goto-uri xwidget +my/pdf-xwidget--home)
      (let ((data (+my/pdf-xwidget--write-data)))
        ;; Also for the page loaded anew (back from a link).
        (+my/pdf-xwidget--write-page data)
        (setq +my/pdf-xwidget--searching nil)
        (+my/pdf-xwidget--js (format "reload(%s)" (json-encode data)))))))

;; COMMANDS (see above)
(defun +my/pdf-xwidget-mouse-select (event)
  "A click on the PDF: select its window (the click itself is WebKit's)."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (select-window window))))

(defun +my/pdf-xwidget--scroll (dx dy)
  (+my/pdf-xwidget--js (format "scroll(%d, %d)" dx dy)))

(defun +my/pdf-xwidget-scroll-down (&optional count)
  "j: scroll the PDF down."
  (interactive "p")
  (+my/pdf-xwidget--scroll 0 (* (or count 1) +my/pdf-xwidget-scroll-step)))

(defun +my/pdf-xwidget-scroll-up (&optional count)
  "k: scroll the PDF up."
  (interactive "p")
  (+my/pdf-xwidget--scroll 0 (- (* (or count 1) +my/pdf-xwidget-scroll-step))))

(defun +my/pdf-xwidget-scroll-right (&optional count)
  "l: scroll the PDF right (zoomed in)."
  (interactive "p")
  (+my/pdf-xwidget--scroll (* (or count 1) +my/pdf-xwidget-scroll-step) 0))

(defun +my/pdf-xwidget-scroll-left (&optional count)
  "h: scroll the PDF left (zoomed in)."
  (interactive "p")
  (+my/pdf-xwidget--scroll (- (* (or count 1) +my/pdf-xwidget-scroll-step)) 0))

(defun +my/pdf-xwidget-half-screen-down ()
  "C-d: scroll the PDF down half a screen."
  (interactive)
  (+my/pdf-xwidget--js "screen(0.5)"))

(defun +my/pdf-xwidget-half-screen-up ()
  "C-u: scroll the PDF up half a screen."
  (interactive)
  (+my/pdf-xwidget--js "screen(-0.5)"))

(defun +my/pdf-xwidget-screen-down ()
  "C-f: scroll the PDF down a screen (a bit less, to keep your place)."
  (interactive)
  (+my/pdf-xwidget--js "screen(0.9)"))

(defun +my/pdf-xwidget-screen-up ()
  "C-b: scroll the PDF up a screen (a bit less, to keep your place)."
  (interactive)
  (+my/pdf-xwidget--js "screen(-0.9)"))

(defun +my/pdf-xwidget-top (&optional page)
  "gg: the PDF's start; with a count, that page."
  (interactive "P")
  (+my/pdf-xwidget--js (if page
                           (format "goto(%d)" (prefix-numeric-value page))
                         "top()")))

(defun +my/pdf-xwidget-bottom (&optional page)
  "G: the PDF's end; with a count, that page."
  (interactive "P")
  (+my/pdf-xwidget--js (if page
                           (format "goto(%d)" (prefix-numeric-value page))
                         "bottom()")))

(defun +my/pdf-xwidget-next-page (&optional count)
  "J: the next page."
  (interactive "p")
  (+my/pdf-xwidget--js (format "page(%d)" (or count 1))))

(defun +my/pdf-xwidget-previous-page (&optional count)
  "K: the previous page."
  (interactive "p")
  (+my/pdf-xwidget--js (format "page(%d)" (- (or count 1)))))

(defun +my/pdf-xwidget-search (&optional backward)
  "/: search the PDF (case-sensitive with a capital), from where it shows;
BACKWARD (?) towards its start. Esc ends the search."
  (interactive)
  (require 'json)
  (let ((query (read-string (if backward "Search backward: " "Search: ")
                            nil '+my/pdf-xwidget--search-history)))
    (setq +my/pdf-xwidget--searching (not (string-empty-p query)))
    (+my/pdf-xwidget--js (format "find(%s, %s)" (json-encode query)
                                 (if backward "true" "false")))))

(defun +my/pdf-xwidget-search-backward ()
  "?: search the PDF towards its start (see `+my/pdf-xwidget-search')."
  (interactive)
  (+my/pdf-xwidget-search t))

(defun +my/pdf-xwidget-search-next ()
  "n: the search's next match."
  (interactive)
  (+my/pdf-xwidget--js "again(false)"))

(defun +my/pdf-xwidget-search-previous ()
  "N: the search's previous match."
  (interactive)
  (+my/pdf-xwidget--js "again(true)"))

(defun +my/pdf-xwidget--escape-h ()
  "Esc in a PDF ends its search (highlights and count)."
  (when (and (derived-mode-p '+my/pdf-xwidget-mode) +my/pdf-xwidget--searching)
    (setq +my/pdf-xwidget--searching nil)
    (+my/pdf-xwidget--js "endFind()")
    t))

(add-hook 'doom-escape-hook #'+my/pdf-xwidget--escape-h)

(defun +my/pdf-xwidget--copied (text)
  "Put TEXT, the PDF's selection, in the kill ring (and the clipboard)."
  (if (and (stringp text) (not (string-blank-p text)))
      (progn (kill-new text)
             (message "Copied %d characters" (length text)))
    (message "No text selected")))

(defun +my/pdf-xwidget-copy ()
  "y / Cmd+C: copy the text selected in the PDF."
  (interactive)
  (when-let* ((xwidget (+my/pdf-xwidget--xwidget)))
    ;; The one call waiting for an answer (see above). Its function is a
    ;; symbol: nothing on the macOS side keeps it from the garbage collector
    ;; until WebKit answers, and a closure could be gone by then.
    (xwidget-webkit-execute-script
     xwidget "window.pdfx ? pdfx.selection() : String(window.getSelection())"
     #'+my/pdf-xwidget--copied)))

(defun +my/pdf-xwidget-zoom-in ()
  "Cmd+=: zoom the PDF in."
  (interactive)
  (+my/pdf-xwidget--js (format "zoom(%s)" +my/pdf-xwidget-zoom-step)))

(defun +my/pdf-xwidget-zoom-out ()
  "Cmd+-: zoom the PDF out."
  (interactive)
  (+my/pdf-xwidget--js (format "zoom(%s)" (/ 1.0 +my/pdf-xwidget-zoom-step))))

(defun +my/pdf-xwidget-actual-size ()
  "Cmd+0: the PDF at 100%."
  (interactive)
  (+my/pdf-xwidget--js "fit('page-actual')"))

(defun +my/pdf-xwidget-fit-width ()
  "W: the PDF as wide as the window (as it opens)."
  (interactive)
  (+my/pdf-xwidget--js "fit('page-width')"))

(defun +my/pdf-xwidget-fit-page ()
  "P: a whole page in the window."
  (interactive)
  (+my/pdf-xwidget--js "fit('page-fit')"))

(define-derived-mode +my/pdf-xwidget-mode special-mode "PDF"
  "A PDF in WebKit, drawn by PDF.js (see config/pdf-xwidget.el).
The file's bytes stay in the buffer, unchanged: WebKit is shown over them.

\\{+my/pdf-xwidget-mode-map}"
  (require 'xwidget)
  (setq-local buffer-read-only t
              cursor-type nil
              ;; (list nil): see Doom's pdf module, emacs-evil/evil#2016.
              evil-normal-state-cursor (list nil)
              evil-motion-state-cursor (list nil)
              font-lock-defaults '(nil t)  ; nothing to colour in a PDF's bytes
              left-fringe-width 0
              right-fringe-width 0
              revert-buffer-function #'+my/pdf-xwidget--revert)
  ;; Nothing shown until WebKit starts (see NO WHITE FLASH).
  (with-silent-modifications
    (put-text-property (point-min) (point-max) 'display ""))
  (add-hook 'window-buffer-change-functions #'+my/pdf-xwidget--shown-h nil t)
  (add-hook 'window-size-change-functions #'+my/pdf-xwidget--fit-h nil t)
  (add-hook 'post-command-hook #'+my/pdf-xwidget--home-h nil t)
  (add-hook 'change-major-mode-hook #'+my/pdf-xwidget--stop nil t)
  (add-hook 'kill-buffer-hook #'+my/pdf-xwidget--stop nil t)
  ;; Already on screen (the mode turned on in a shown buffer): no window will
  ;; change buffer to start it.
  (when-let* ((window (get-buffer-window nil 'visible)))
    (+my/pdf-xwidget--shown-h window)))

;; Evil keys (see above) in normal state.
(after! evil
  (evil-set-initial-state '+my/pdf-xwidget-mode 'normal))
