;;; $DOOMDIR/config/excalidraw.el -*- lexical-binding: t; -*-
;; Drawings in WebKit (xwidgets), drawn with Excalidraw. Loaded from config.el.

;; ====== VARIABLES ======

;; DRAWINGS
;; Files named *.excalidraw.svg or *.excalidraw open in the file's tab as a
;; drawing, in Excalidraw (excalidraw.com's editor: shapes, arrows, lines,
;; text, freehand, images, hand-drawn looking or not), a web page in WebKit
;; like PDFs (config/webkit.el has what WebKit pages share):
;; - *.excalidraw.svg: an SVG image with the drawing in it. Markdown and Org
;;   show it as any image (the preview, GitHub...), and it opens here again to
;;   edit, as at excalidraw.com.
;; - *.excalidraw: Excalidraw's own JSON (excalidraw.com's files).
;; A new file is a blank drawing. Draw with the mouse or trackpad (the
;; trackpad's scrolling pans, pinching zooms); Emacs takes the keys and gives
;; them to the page, so Excalidraw's work as at excalidraw.com (its ? lists
;; them): tools (v r d o a l p t e h k, 1-0), Delete, Esc, Enter, the arrows,
;; Shift+1 (fit), Cmd+Z / Cmd+Shift+Z (undo / redo), Cmd+A, Cmd+D, Cmd+G,
;; Cmd+= / Cmd+- / Cmd+0 (zoom)... Text is typed straight into the page (a
;; double-click, or t then a click). Emacs keeps SPC (the leader), : (Evil's
;; command line) and its keys that Excalidraw has none for (Cmd+S, Cmd+W,
;; M-x, C-x, C-g, Option+Enter...). Also:
;;   Cmd+C / Cmd+X  copy / cut the selection: Emacs's kill ring and the
;;                  clipboard, in Excalidraw's format (it pastes them back,
;;                  here or at excalidraw.com)
;;   Cmd+V          paste: shapes copied so, or text (a text element)
;;   SPC m d        dark canvas (the file stays light), for all drawings
;;   SPC m l        Excalidraw's libraries (libraries.excalidraw.com), see LIBRARIES
;;   SPC m r        read the file again
;; The buffer has the file's text, under the views (see THE BUFFER'S TEXT in
;; config/webkit.el): a moment after each change, the page exports the drawing
;; and Emacs puts it there, marked modified, so it's saved as any file (Cmd+S,
;; :w, Emacs asking on closing). Saving waits for the last change (5 s at
;; most). Undo is Excalidraw's.
;; Split, each pane shows the drawing (a WebKit view per window); a change in
;; one shows in the others. Changed on disk (git, say): shown anew.
;; From Markdown or Org, Option+Enter (config/actions.el) has "Insert a new
;; drawing" (M-x +my/excalidraw-insert): it links a new one as an image at
;; point and opens it beside, saved blank at once; on a link to one, "Edit the
;; drawing" opens it beside.
;; LIBRARIES: Excalidraw's library (its panel: shapes kept to reuse, drawn or
;; added from libraries.excalidraw.com) is the drawings' one, kept in
;; `+my/excalidraw-library-file' across sessions; a change in one drawing shows
;; in the others. Its "Browse libraries" (or SPC m l) opens the libraries' site
;; in Emacs (WebKit): its "Add to Excalidraw" adds the library and comes back to
;; the drawing. M-x +my/excalidraw-add-library adds one from its URL or file,
;; or from a link with addLibrary= in it (where the site sends a library).
;; Excalidraw (0.17.6: its plain-script build, on React 18) is downloaded
;; once, from jsdelivr, each file checked against its SHA-256 below (M-x
;; +my/excalidraw-install does it again). Without it (e.g. offline the first
;; time), in a terminal, or in an Emacs without xwidgets, a drawing opens in
;; its file's own mode: the SVG as an image (as XML in a terminal), the JSON
;; as JSON.
(defvar +my/excalidraw-theme 'auto
  "The drawings' canvas: `auto' (dark in a dark Emacs theme), `light' or
`dark' (SPC m d sets it). Saved drawings are light.")

(defvar +my/excalidraw-export-delay 300
  "Milliseconds after a change the page exports the drawing (see above).")

(defvar +my/excalidraw-version "0.17.6"
  "The Excalidraw (npm's @excalidraw/excalidraw) version that draws.")

(defvar +my/excalidraw-files
  '(("react.production.min.js" "react@18.2.0/umd/react.production.min.js"
     "4b4969fa4ef3594324da2c6d78ce8766fbbc2fd121fff395aedf997db0a99a06")
    ("react-dom.production.min.js" "react-dom@18.2.0/umd/react-dom.production.min.js"
     "21758ed084cd0e37e735722ee4f3957ea960628a29dfa6c3ce1a1d47a2d6e4f7")
    ("excalidraw.production.min.js"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw.production.min.js"
     "27b133f845543f091aa518924b5b2fdd7eb52a9e490de100b9bc3bfd2ae2f314")
    ("excalidraw-assets/vendor-677e88ca78c86bddf13d.js"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/vendor-677e88ca78c86bddf13d.js"
     "8e496e2d4d71d85c73c114ed5473d34c27c83a2344b6f036327b955e5ab0f260")
    ("excalidraw-assets/Virgil.woff2"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Virgil.woff2"
     "9976295bfe709bdea64839a4d4e9a1d436dd6eb67538399a5a0e8b8fadbcf1cf")
    ("excalidraw-assets/Cascadia.woff2"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Cascadia.woff2"
     "6d27c0474bb6c7922911f90ae811918f6be943005f1c4a6ec0e5b70a2bfddf16")
    ("excalidraw-assets/Assistant-Regular.woff2"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Assistant-Regular.woff2"
     "76945f09225aae65bdbd204cb4ac40d4caa4ff67150e5074bab1a04d1b778fc3")
    ("excalidraw-assets/Assistant-Medium.woff2"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Assistant-Medium.woff2"
     "81a9f280ce6a790f20ca8cd521183caa430f1f7fdc0752c36ef1cc6dc828ac57")
    ("excalidraw-assets/Assistant-SemiBold.woff2"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Assistant-SemiBold.woff2"
     "bba47a7d1b185a4a2e0d265ec82aeac5dbc2dc9cb0f482a2ff57cbdfe4e5045d")
    ("excalidraw-assets/Assistant-Bold.woff2"
     "@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Assistant-Bold.woff2"
     "e0cdd332ce039770e93ec44336b6db65f931940f42b0342aad35a06e7f991d29"))
  "Excalidraw's files (and React's): (FILE NPM-PATH SHA256), FILE in
`+my/excalidraw-dir', downloaded from jsdelivr's NPM-PATH.")

(defvar +my/excalidraw-dir
  (expand-file-name (concat "excalidraw-" +my/excalidraw-version "/") doom-data-dir)
  "Where Excalidraw is downloaded to.")

(defvar +my/excalidraw-library-file
  (expand-file-name "excalidraw-library.excalidrawlib" doom-data-dir)
  "The drawings' library (see LIBRARIES above), an .excalidrawlib.")

(defvar +my/excalidraw-mode-map (make-sparse-keymap)
  "Keys of drawings (see `+my/excalidraw-mode').")

;; ====== KEY BINDINGS ======

;; KEYS
;; The keys Excalidraw has (see above), given to the page (see
;; `+my/excalidraw-key'): what they type, but SPC (Doom's leader) and : (Evil's
;; command line); Esc, Enter, Tab, Delete, the arrows; and its Cmd and Option
;; keys (macOS's, as Excalidraw has them there).
(defconst +my/excalidraw--page-keys
  (append
   (mapcar #'vector (remq ?: (number-sequence 33 126)))
   (mapcar #'kbd
           '("<escape>" "RET" "<return>" "TAB" "<tab>" "<backtab>" "DEL" "<backspace>"
             "<delete>" "<deletechar>" "<left>" "<right>" "<up>" "<down>"
             "S-<left>" "S-<right>" "S-<up>" "S-<down>"
             ;; Undo, redo, select all, duplicate, group, ungroup.
             "s-z" "s-Z" "s-y" "s-a" "s-d" "s-g" "s-G"
             ;; Zoom, the grid, a link, lock, font size.
             "s-=" "s-+" "s--" "s-0" "s-'" "s-k" "s-L" "s-<" "s->"
             ;; Backward, forward, to the back, to the front; align.
             "s-[" "s-]" "s-M-[" "s-M-]"
             "s-S-<up>" "s-S-<down>" "s-S-<left>" "s-S-<right>"
             ;; Copy and paste styles; a line's points; zen and view modes.
             "s-M-c" "s-M-v" "s-RET" "s-<return>" "M-z" "M-r")))
  "Keys given to a drawing's page (see above).")

(dolist (key +my/excalidraw--page-keys)
  (define-key +my/excalidraw-mode-map key #'+my/excalidraw-key))

(map! :map +my/excalidraw-mode-map
      "s-c" #'+my/excalidraw-copy
      "s-x" #'+my/excalidraw-cut
      "s-v" #'+my/excalidraw-paste)

;; Clicks are WebKit's: Emacs only selects the window (config/webkit.el).
(+my/webkit-bind-clicks +my/excalidraw-mode-map)

;; In normal state, before Evil's keys and its packages' (evil-snipe's f, t,
;; s...): only Doom's leader (SPC) comes first.
(after! evil
  (evil-make-intercept-map +my/excalidraw-mode-map 'normal))

(map! :map +my/excalidraw-mode-map
      :localleader
      :desc "Dark canvas"         "d" #'+my/excalidraw-toggle-dark
      :desc "Libraries"           "l" #'+my/excalidraw-browse-libraries
      :desc "Read the file again" "r" #'revert-buffer)

;; ====== CODE ======

(defvar-local +my/excalidraw--dir nil
  "The page's folder (index.html).")

(defvar-local +my/excalidraw--error nil
  "The page's error, shown in a notice (see WATCHING).")

(defvar-local +my/excalidraw--save-new nil
  "Non-nil: save the drawing once its page has made it (a new one, see
INSERTING).")

(defconst +my/excalidraw--page-template
  "<!doctype html>
<html><head><meta charset=\"utf-8\">
<style>html,body,#app{margin:0;height:100%%;overflow:hidden;background:%b}</style>
<script>window.EXCALIDRAW_ASSET_PATH = %a;</script>
<script src=\"%preact.production.min.js\"></script>
<script src=\"%preact-dom.production.min.js\"></script>
<script src=\"%pexcalidraw.production.min.js\"></script>
<script>window.EXD_OPTIONS = %o;</script>
<script src=\"%j\"></script>
</head><body><div id=\"app\"></div>
<script>
if (window.exd) exd.open(%d, %l);
else document.title = 'exd ' + JSON.stringify({error: 'Excalidraw did not load'});
</script>
</body></html>
"
  "A drawing's page (see config/excalidraw.js), for `format-spec': %b the
background, %a Excalidraw's folder (JSON), %p its URL, %o the settings (JSON),
%j the script, %d the drawing (the file's text as base64, JSON), %l the
library (its file's text so, see LIBRARIES).")

(defun +my/excalidraw-mode-maybe ()
  "Drawings' major mode: Excalidraw in WebKit where it works, else the file's
own (see above)."
  (if (and (+my/webkit-p) (+my/excalidraw-ensure))
      (+my/excalidraw-mode)
    (+my/excalidraw--fallback-mode)))

(defun +my/excalidraw--json-p ()
  "Non-nil if the buffer's drawing is Excalidraw's JSON (.excalidraw), not an
SVG."
  (and buffer-file-name
       (let ((case-fold-search t))
         (string-match-p "\\.excalidraw\\'" buffer-file-name))))

(defun +my/excalidraw--fallback-mode ()
  "The drawing's file in its own mode: the SVG as an image (as XML where
images don't show: a terminal), the JSON as JSON."
  (cond ((+my/excalidraw--json-p)
         (if (fboundp 'json-mode) (json-mode) (js-json-mode)))
        ((display-images-p) (image-mode))
        (t (nxml-mode))))

(add-to-list 'auto-mode-alist '("\\.excalidraw\\(?:\\.svg\\)?\\'" . +my/excalidraw-mode-maybe))

;; EXCALIDRAW
(defun +my/excalidraw--files ()
  "Excalidraw's files, as `+my/webkit-install' takes them."
  (mapcar (lambda (file)
            (list (nth 0 file) (concat "https://cdn.jsdelivr.net/npm/" (nth 1 file)) (nth 2 file)))
          +my/excalidraw-files))

(defun +my/excalidraw-installed-p ()
  "Non-nil if Excalidraw is in `+my/excalidraw-dir'."
  (+my/webkit-installed-p (+my/excalidraw--files) +my/excalidraw-dir))

(defun +my/excalidraw-install ()
  "Download Excalidraw into `+my/excalidraw-dir', checking each file's SHA-256."
  (interactive)
  (+my/webkit-install "Excalidraw" +my/excalidraw-version (+my/excalidraw--files)
                      +my/excalidraw-dir))

(defun +my/excalidraw-ensure ()
  "Non-nil if Excalidraw is there, downloaded now if need be (see above)."
  (or (+my/excalidraw-installed-p)
      (condition-case err
          (progn (+my/excalidraw-install) t)
        (error (message "Drawings open as their files (no Excalidraw): %s"
                        (error-message-string err))
               nil))))

;; THE PAGE (see config/excalidraw.js)
(defun +my/excalidraw--dark-p ()
  "Non-nil if drawings show on a dark canvas (see `+my/excalidraw-theme')."
  (pcase +my/excalidraw-theme
    ('dark t)
    ('light nil)
    (_ (eq (frame-parameter nil 'background-mode) 'dark))))

(defun +my/excalidraw--background ()
  "The canvas's colour, for the cover while a view loads (config/webkit.el)."
  (if (+my/excalidraw--dark-p) "#121212" "#ffffff"))

(defun +my/excalidraw--json (object)
  "OBJECT as JSON, a string of characters (`json-serialize' gives UTF-8
bytes, which a script made with them would carry as raw bytes)."
  (decode-coding-string (json-serialize object) 'utf-8 t))

(defun +my/excalidraw--base64 (text)
  "TEXT, UTF-8, as base64 on one line."
  (base64-encode-string (encode-coding-string text 'utf-8 t) t))

(defun +my/excalidraw--options ()
  "The settings a page starts with (JSON): the drawing's kind, the canvas,
how long after a change it's exported, and the CDN folder its SVG's fonts are
named in (Excalidraw adds /dist/excalidraw-assets/)."
  (+my/excalidraw--json (list :kind (if (+my/excalidraw--json-p) "json" "svg")
                        :dark (if (+my/excalidraw--dark-p) t :false)
                        :exportDelay +my/excalidraw-export-delay
                        :fonts (concat "https://cdn.jsdelivr.net/npm/@excalidraw/excalidraw@"
                                       +my/excalidraw-version)
                        :libraryReturn +my/excalidraw--library-return)))

(defun +my/excalidraw--page ()
  "The drawing's page, with the drawing as the buffer has it."
  (let ((assets (+my/webkit-file-url (file-name-as-directory +my/excalidraw-dir))))
    (format-spec
     +my/excalidraw--page-template
     `((?b . ,(+my/excalidraw--background))
       (?a . ,(+my/excalidraw--json assets))
       (?p . ,assets)
       (?o . ,(+my/excalidraw--options))
       (?j . ,(+my/webkit-file-url (expand-file-name "config/excalidraw.js" doom-user-dir)))
       (?d . ,(+my/excalidraw--json (+my/excalidraw--base64
                               (buffer-substring-no-properties (point-min) (point-max)))))
       (?l . ,(+my/excalidraw--json (+my/excalidraw--base64 (+my/excalidraw--library-text))))))))

(defun +my/excalidraw--write-page ()
  "Write the page's index.html (its folder made the first time); return it.
Written anew as the drawing changes: a view loading it shows it as it is."
  (unless (and +my/excalidraw--dir (file-directory-p +my/excalidraw--dir))
    (setq +my/excalidraw--dir (make-temp-file "excalidraw-" t)))
  (let ((file (expand-file-name "index.html" +my/excalidraw--dir))
        (page (+my/excalidraw--page))
        (coding-system-for-write 'utf-8-unix))
    (with-temp-file file
      (insert page))
    file))

(defun +my/excalidraw--url (_window)
  "The page a new view of the drawing loads (see VIEWS in config/webkit.el)."
  (+my/webkit-file-url (+my/excalidraw--write-page)))

(defun +my/excalidraw--loaded (xwidget)
  "XWIDGET's page has (re)loaded: its drawing starts at version 0 (see
SAVING)."
  (xwidget-put xwidget 'seen 0)
  (xwidget-put xwidget 'fetched 0)
  (xwidget-put xwidget 'library 0))

(defun +my/excalidraw--stop ()
  "Delete the page's folder (another mode, the buffer killed); its views
close after (config/webkit.el)."
  (when (and +my/excalidraw--dir (file-directory-p +my/excalidraw--dir))
    (delete-directory +my/excalidraw--dir t))
  (setq +my/excalidraw--dir nil)
  (+my/excalidraw--show-error nil))

;; Quitting Emacs kills no buffers: the pages' folders would stay.
(add-hook 'kill-emacs-hook
          (defun +my/excalidraw--cleanup-h ()
            (dolist (buffer (buffer-list))
              (when-let* ((dir (buffer-local-value '+my/excalidraw--dir buffer)))
                (ignore-errors (delete-directory dir t))))))

;; SAVING
;; The page says in its title the drawing's version (one more at each change;
;; a new file's blank drawing is the first) and the version of its latest
;; export (the file's text as it would be saved). Emacs, every 0.1 s while
;; it's on screen (see WATCHING in config/webkit.el): a new version marks the
;; buffer modified; a new export is asked for (an answer awaited, see
;; JAVASCRIPT there) and becomes the buffer's text, then the other views'
;; drawing. Saving first asks each page for its version, exported now, and
;; waits for those to be in the buffer.
(defun +my/excalidraw--state (&optional xwidget)
  "XWIDGET's page's state (default: this buffer's view), a plist (:ready
:version :exported :cursor :dark :error), or nil before it has said it."
  (+my/webkit-title-json (or xwidget (+my/webkit-xwidget)) "exd "))

(defun +my/excalidraw--number (state key)
  (let ((n (plist-get state key)))
    (if (natnump n) n 0)))

(defun +my/excalidraw--sync (xwidget)
  "Take in what XWIDGET's page says (see above); return its state."
  (when-let* ((state (+my/excalidraw--state xwidget)))
    (let ((version (+my/excalidraw--number state :version))
          (exported (+my/excalidraw--number state :exported)))
      (when (> version (or (xwidget-get xwidget 'seen) 0))
        (xwidget-put xwidget 'seen version)
        (unless (buffer-modified-p)
          (set-buffer-modified-p t)))
      (when (and (> exported (or (xwidget-get xwidget 'fetched) 0))
                 (not (+my/webkit--asked-p xwidget)))
        (+my/webkit-ask "window.exd ? exd.answer() : '0\\n'" #'+my/excalidraw--received
                        xwidget))
      ;; Its library (see LIBRARIES).
      (when (and (> (+my/excalidraw--number state :library) (or (xwidget-get xwidget 'library) 0))
                 (not (+my/webkit--asked-p xwidget)))
        (+my/webkit-ask "window.exd ? exd.library() : '0\\n'" #'+my/excalidraw--library-received
                        xwidget)))
    state))

(defun +my/excalidraw--versioned (answer)
  "A page's ANSWER, \"VERSION\\nTEXT\", as (VERSION . TEXT); nil if it isn't one."
  (when-let* (((stringp answer))
              (newline (string-search "\n" answer))
              ((string-match-p "\\`[0-9]+\\'" (substring answer 0 newline))))
    (cons (string-to-number (substring answer 0 newline))
          (substring answer (1+ newline)))))

(defun +my/excalidraw--received (answer)
  "A page's latest export (see above): \"VERSION\\nTEXT\", TEXT the file's."
  (pcase-let* ((xwidget +my/webkit-answering)
               (`(,version . ,text) (+my/excalidraw--versioned answer)))
    (when (and xwidget version
               (eq (xwidget-buffer xwidget) (current-buffer))
               (derived-mode-p '+my/excalidraw-mode)
               (> version (or (xwidget-get xwidget 'fetched) 0)))
      (xwidget-put xwidget 'fetched version)
      (unless (or (string-empty-p text)
                  (string= text (buffer-substring-no-properties (point-min) (point-max))))
        (+my/webkit-set-text text)
        (when +my/excalidraw--dir
          (+my/excalidraw--write-page))
        (+my/excalidraw--show text xwidget)
        (when +my/excalidraw--save-new
          (setq +my/excalidraw--save-new nil)
          (run-at-time 0 nil #'+my/excalidraw--save (current-buffer)))))))

(defun +my/excalidraw--show (text &optional except)
  "Show the drawing whose file's text is TEXT in the buffer's views, but
EXCEPT's."
  (let ((script (format "window.exd && exd.replace(\"%s\")" (+my/excalidraw--base64 text))))
    (dolist (xwidget (+my/webkit-xwidgets))
      (unless (eq xwidget except)
        (+my/webkit-execute script xwidget)))))

(defun +my/excalidraw--flushed (version)
  "A page's answer to saving: the VERSION its drawing is at (see above)."
  (when +my/webkit-answering
    (xwidget-put +my/webkit-answering 'flushed
                 (if (stringp version) (string-to-number version) 0))))

(defun +my/excalidraw--in-buffer-p (xwidget)
  "Non-nil if XWIDGET's drawing, as it was when saving began, is in the
buffer (see above)."
  (+my/excalidraw--sync xwidget)
  (when-let* ((flushed (xwidget-get xwidget 'flushed)))
    (<= flushed (or (xwidget-get xwidget 'fetched) 0))))

(defun +my/excalidraw--before-save ()
  "Saving: the drawings' last changes in the buffer first (see above)."
  (when-let* ((xwidgets (+my/webkit-xwidgets)))
    (dolist (xwidget xwidgets)
      (xwidget-put xwidget 'flushed nil)
      (+my/webkit-ask "window.exd ? exd.flush() : '0'" #'+my/excalidraw--flushed xwidget))
    (unless (+my/webkit-wait (lambda () (seq-every-p #'+my/excalidraw--in-buffer-p xwidgets))
                             5)
      (message "The drawing's last change didn't come from its page: saved without it"))))

(defun +my/excalidraw--save (buffer)
  "Save BUFFER's drawing, if changed."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (buffer-modified-p)
        (let ((save-silently t))
          (save-buffer))))))

(defun +my/excalidraw--revert (_ignore-auto noconfirm)
  "Show the drawing anew from its file (asked first if it was changed here,
unless NOCONFIRM)."
  (when (and (buffer-modified-p) (not noconfirm)
             (not (yes-or-no-p (format "Discard the drawing's changes, read %s again? "
                                       (file-name-nondirectory buffer-file-name)))))
    (user-error "Not read again"))
  (let* ((file buffer-file-name)
         (text (with-temp-buffer
                 (insert-file-contents file)
                 (buffer-string))))
    ;; The file's time first: changing the text of a buffer whose file
    ;; changed asks whether to.
    (set-visited-file-modtime)
    (+my/webkit-set-text (if (string-empty-p text) " " text))
    (set-buffer-modified-p nil)
    (when +my/excalidraw--dir
      (+my/excalidraw--write-page))
    (+my/excalidraw--show text)))

;; WATCHING
;; Every 0.1 s, for each window showing a drawing, from its view's title (see
;; WATCHING in config/webkit.el): its changes (see SAVING), the mouse pointer
;; the page wants (the hand over buttons and what can be moved, the I-beam
;; over text, else the arrow), its error in a notice.
(defun +my/excalidraw--watch (window xwidget)
  "WINDOW shows XWIDGET's view of the drawing (see above)."
  (when-let* ((state (+my/excalidraw--sync xwidget)))
    (+my/webkit-pointer window (pcase (plist-get state :cursor)
                                 ("hand" 'hand) ("text" 'text) (_ 'arrow)))
    (+my/excalidraw--show-error (plist-get state :error))))

(defun +my/excalidraw--show-error (error)
  "Show ERROR (a string, the page's) in a notice above the drawing; nil: none."
  (unless (equal error +my/excalidraw--error)
    (setq +my/excalidraw--error error)
    (cond ((not (fboundp '+my/banner-show))
           (when error (message "%s" error)))
          (error
           (+my/banner-show 'excalidraw
                            (if (string-prefix-p "Export" error)
                                (format "The drawing can't be saved: %s" error)
                              (format "%s: shown blank, saving replaces the file with what you draw"
                                      error))
                            :type 'error))
          (t (+my/banner-close 'excalidraw)))))

;; KEYS (see above)
;; A key typed in Emacs, as the KeyboardEvent a browser gives a page on a US
;; keyboard: the character typed (`key') and the physical key (`code', which
;; Excalidraw reads for some: Shift+1 is "!" on Digit1), and the modifiers
;; (Cmd is `metaKey', Option `altKey').
(defconst +my/excalidraw--shifted
  '((?! . ?1) (?@ . ?2) (?# . ?3) (?$ . ?4) (?% . ?5) (?^ . ?6) (?& . ?7) (?* . ?8)
    (?\( . ?9) (?\) . ?0) (?_ . ?-) (?+ . ?=) (?{ . ?\[) (?} . ?\]) (?| . ?\\)
    (?: . ?\;) (?\" . ?') (?< . ?,) (?> . ?.) (?? . ?/) (?~ . ?`))
  "A character typed with Shift, and the one its key types without.")

(defconst +my/excalidraw--codes
  '((?- . "Minus") (?= . "Equal") (?\[ . "BracketLeft") (?\] . "BracketRight")
    (?\\ . "Backslash") (?\; . "Semicolon") (?' . "Quote") (?, . "Comma")
    (?. . "Period") (?/ . "Slash") (?` . "Backquote"))
  "The code of the key typing a character, but letters and digits.")

(defconst +my/excalidraw--named
  '((return . "Enter") (tab . "Tab") (backtab . "Tab") (escape . "Escape")
    (backspace . "Backspace") (delete . "Delete") (deletechar . "Delete")
    (left . "ArrowLeft") (right . "ArrowRight") (up . "ArrowUp") (down . "ArrowDown"))
  "Function keys, and their name (`key' and `code' both).")

(defun +my/excalidraw--key-init (event)
  "Key EVENT as a KeyboardEvent's properties (JSON), or nil if it's none."
  (let* ((char (and (integerp event) (logand event #x3fffff))) ; no modifier bits
         ;; RET, TAB, ESC, DEL as characters: C-m, C-i... to Emacs.
         (named (pcase char (13 'return) (9 'tab) (27 'escape) (127 'backspace)))
         (modifiers (event-modifiers (if named (logior (- event char) ?a) event)))
         (basic (or named (event-basic-type event)))
         (shift (or (memq 'shift modifiers) (eq basic 'backtab)))
         (key nil)
         (code ""))
    (cond ((symbolp basic)
           (when-let* ((name (alist-get basic +my/excalidraw--named)))
             (setq key name code name)))
          ((not (characterp basic)))
          ((<= ?a basic ?z)
           (setq key (string (if shift (upcase basic) basic))
                 code (format "Key%c" (upcase basic))))
          ((<= ?0 basic ?9)
           (setq key (string basic) code (format "Digit%c" basic)))
          ((assq basic +my/excalidraw--shifted)
           (let ((unshifted (cdr (assq basic +my/excalidraw--shifted))))
             (setq key (string basic)
                   shift t
                   code (if (<= ?0 unshifted ?9)
                            (format "Digit%c" unshifted)
                          (cdr (assq unshifted +my/excalidraw--codes))))))
          (t (setq key (string basic)
                   code (or (cdr (assq basic +my/excalidraw--codes)) ""))))
    (when key
      (+my/excalidraw--json
       (list :key key :code code
             :shiftKey (if shift t :false)
             :metaKey (if (memq 'super modifiers) t :false)
             :altKey (if (memq 'meta modifiers) t :false)
             :ctrlKey (if (memq 'control modifiers) t :false))))))

(defun +my/excalidraw-key ()
  "A key of Excalidraw's: to the drawing in the selected window (see above)."
  (interactive)
  (when-let* ((init (+my/excalidraw--key-init last-command-event)))
    (+my/webkit-execute (format "window.exd && exd.key(%s)" init))))

;; COPY AND PASTE
;; Through Emacs's kill ring (and so the clipboard): WebKit's own clipboard
;; events don't come from Emacs's keys.
(defun +my/excalidraw-copy ()
  "Cmd+C: copy the selection (see above)."
  (interactive)
  (+my/webkit-ask "window.exd ? exd.copy() : ''" #'+my/excalidraw--copied))

(defun +my/excalidraw-cut ()
  "Cmd+X: cut the selection (see above)."
  (interactive)
  (+my/webkit-ask "window.exd ? exd.cut() : ''" #'+my/excalidraw--copied))

(defun +my/excalidraw--copied (text)
  "The selection a page copied, TEXT, in the kill ring."
  (if (and (stringp text) (not (string-empty-p text)))
      (progn (kill-new text)
             (message "Copied the selection"))
    (message "Nothing selected")))

(defun +my/excalidraw-paste ()
  "Cmd+V: paste the kill ring's latest (the clipboard's): shapes copied from
a drawing, or text."
  (interactive)
  (let ((text (ignore-errors (current-kill 0))))
    (if (not (and (stringp text) (not (string-empty-p text))))
        (message "Nothing to paste")
      (+my/webkit-execute (format "window.exd && exd.paste(%s)"
                                  (+my/excalidraw--json (substring-no-properties text)))))))

(defun +my/excalidraw-toggle-dark ()
  "SPC m d: drawings on a dark canvas, or a light one (see above)."
  (interactive)
  (let ((dark (not (+my/excalidraw--dark-p))))
    (setq +my/excalidraw-theme (if dark 'dark 'light))
    (dolist (buffer (buffer-list))
      (when (provided-mode-derived-p (buffer-local-value 'major-mode buffer) '+my/excalidraw-mode)
        (with-current-buffer buffer
          (+my/webkit-execute (format "window.exd && exd.set({dark: %s})" (if dark "true" "false"))
                              t))))
    (message "Dark canvas %s" (if dark "on" "off"))))

;; LIBRARIES (see above)
;; The library is the pages': each starts with its file's, and says in its
;; title when it changed (its version, see SAVING); Emacs asks for it, keeps it
;; in the file and gives it to the other drawings' pages. libraries.excalidraw.com
;; ("Browse libraries") sends the library chosen to the drawing's address, a
;; file:// one Emacs never sees (in the browser, where a link out of the page
;; goes): the site opens in Emacs instead, and its way to that address (one of
;; no site) is stopped, the library taken from it. But its "Add to Excalidraw"
;; links open a new window, which a click (not a script's) didn't do in Emacs's
;; WebKit, and on its way to no site WebKit still says the site's address; so
;; the site is told to put the link clicked in its title instead, which Emacs
;; reads every 0.2 s while it's open (as WebKit pages' titles, see WATCHING in
;; config/webkit.el). A notice above it says what to do, and goes back to the
;; drawing.
(defconst +my/excalidraw--libraries "https://libraries.excalidraw.com"
  "Excalidraw's libraries' site.")

(defconst +my/excalidraw--library-return "https://excalidraw.emacs.invalid/"
  "Where libraries.excalidraw.com sends a library to add (see above): no
site has the name.")

(defun +my/excalidraw--library-text ()
  "The library's file's text, \"\" without one."
  (if (file-readable-p +my/excalidraw-library-file)
      (with-temp-buffer
        (insert-file-contents +my/excalidraw-library-file)
        (buffer-string))
    ""))

(defun +my/excalidraw--drawings ()
  "The buffers showing drawings."
  (seq-filter (lambda (buffer)
                (provided-mode-derived-p (buffer-local-value 'major-mode buffer)
                                         '+my/excalidraw-mode))
              (buffer-list)))

(defun +my/excalidraw--library-received (answer)
  "A page's library (see above): \"VERSION\\nTEXT\", TEXT an .excalidrawlib's."
  (pcase-let* ((xwidget +my/webkit-answering)
               (`(,version . ,text) (+my/excalidraw--versioned answer)))
    (when (and xwidget version
               (> version (or (xwidget-get xwidget 'library) 0)))
      (xwidget-put xwidget 'library version)
      (unless (or (string-empty-p text) (equal text (+my/excalidraw--library-text)))
        (make-directory (file-name-directory +my/excalidraw-library-file) t)
        (let ((coding-system-for-write 'utf-8-unix))
          (with-temp-file +my/excalidraw-library-file
            (insert text)))
        ;; The other pages, the other drawings'.
        (let ((script (format "window.exd && exd.setLibrary(\"%s\")" (+my/excalidraw--base64 text))))
          (dolist (buffer (+my/excalidraw--drawings))
            (with-current-buffer buffer
              (dolist (other (+my/webkit-xwidgets))
                (unless (eq other xwidget)
                  (+my/webkit-execute script other))))))))))

(defun +my/excalidraw--library-in (link)
  "The library LINK says to add (libraries.excalidraw.com's addLibrary=), or nil."
  (require 'url-util)
  (when (and (stringp link)
             (string-match "[#?&]addLibrary=\\([^&#]+\\)" link))
    (url-unhex-string (match-string 1 link))))

(defun +my/excalidraw--fetch (source)
  "The text of SOURCE: a URL (http(s), file://) or a file."
  (cond ((string-match-p "\\`https?://" source)
         (require 'url)
         (message "Downloading %s..." source)
         (let ((buffer (or (url-retrieve-synchronously source t nil 30)
                           (user-error "Couldn't download %s" source))))
           (unwind-protect
               (with-current-buffer buffer
                 (goto-char (point-min))
                 (unless (looking-at "HTTP/[0-9.]+ 200")
                   (user-error "Couldn't download %s: %s" source
                               (buffer-substring (point) (line-end-position))))
                 (re-search-forward "\r?\n\r?\n" nil 'move)
                 (decode-coding-string (buffer-substring-no-properties (point) (point-max)) 'utf-8))
             (kill-buffer buffer))))
        (t
         (let ((file (if (string-prefix-p "file:" source) (+my/webkit-url-file source)
                       (expand-file-name source))))
           (unless (file-readable-p file)
             (user-error "No such library: %s" source))
           (with-temp-buffer
             (insert-file-contents file)
             (buffer-string))))))

(defun +my/excalidraw--library-p (text)
  "Non-nil if TEXT is an .excalidrawlib's (version 2's libraryItems, 1's
library)."
  (let ((json (ignore-errors (json-parse-string text :object-type 'alist))))
    (and (consp json)
         (or (assq 'libraryItems json) (assq 'library json)))))

(defun +my/excalidraw--a-view ()
  "A drawing's view to add a library in: the selected window's, else one on
screen, else any."
  (or (and (derived-mode-p '+my/excalidraw-mode) (+my/webkit-xwidget))
      (seq-some (lambda (window)
                  (with-current-buffer (window-buffer window)
                    (and (derived-mode-p '+my/excalidraw-mode) (+my/webkit-xwidget window))))
                (window-list-1 nil 'nomini 'visible))
      (seq-some (lambda (buffer) (with-current-buffer buffer (+my/webkit-xwidget)))
                (+my/excalidraw--drawings))))

(defun +my/excalidraw--library-guess ()
  "A library the kill ring's latest names, for `+my/excalidraw-add-library'."
  (let ((latest (ignore-errors (current-kill 0 t))))
    (and (stringp latest)
         (string-match-p "addLibrary=\\|\\.excalidrawlib\\'" latest)
         (string-trim latest))))

(defun +my/excalidraw-add-library (source)
  "Add the library SOURCE to the drawings' (see above): an .excalidrawlib's
URL or file, or a link with addLibrary= in it. Merged in an open drawing's
page, its library panel opened."
  (interactive
   (list (read-string "Library (URL, file, or a link with addLibrary=): "
                      (+my/excalidraw--library-guess))))
  (let* ((xwidget (or (+my/excalidraw--a-view)
                      (user-error "Open a drawing first: the library is added in its page")))
         (source (string-trim source))
         (text (+my/excalidraw--fetch (or (+my/excalidraw--library-in source) source))))
    (unless (+my/excalidraw--library-p text)
      (user-error "Not an Excalidraw library: %s" source))
    (with-current-buffer (xwidget-buffer xwidget)
      (+my/webkit-execute (format "window.exd && exd.addLibrary(\"%s\")" (+my/excalidraw--base64 text))
                          xwidget))
    (message "Library added: in the drawing's library panel")))

(defconst +my/excalidraw--libraries-script
  "window.exdLibraries || (window.exdLibraries = document.addEventListener('click', (event) => {
  const link = event.target.closest && event.target.closest('a[href*=\"addLibrary=\"]');
  if (link) { event.preventDefault(); event.stopPropagation(); document.title = 'exd-library ' + link.href; }
}, true) || true);"
  "Run in the libraries' site: its \"Add to Excalidraw\" link clicked said in its
title (see above).")

(defun +my/excalidraw--libraries-url ()
  "libraries.excalidraw.com's address, as Excalidraw's Browse libraries has it."
  (require 'url-util)
  (format "%s/?target=_excalidraw&referrer=%s&useHash=true&token=emacs&theme=%s&version=2"
          +my/excalidraw--libraries (url-hexify-string +my/excalidraw--library-return)
          (if (+my/excalidraw--dark-p) "dark" "light")))

(defun +my/excalidraw--link-out (url)
  "A link out of a drawing's page: libraries.excalidraw.com in Emacs (see
above), the rest in the browser."
  (if (string-prefix-p +my/excalidraw--libraries url)
      (run-at-time 0 nil #'+my/excalidraw-browse-libraries url (current-buffer))
    (browse-url url)))

(defun +my/excalidraw-browse-libraries (&optional url drawing)
  "SPC m l: Excalidraw's libraries, libraries.excalidraw.com (URL), in
Emacs, in DRAWING's window (default: the current buffer's): its \"Add to
Excalidraw\" adds one to the drawings' library (see above)."
  (interactive)
  (let ((drawing (or drawing (current-buffer))))
    (unless (and (buffer-live-p drawing)
                 (provided-mode-derived-p (buffer-local-value 'major-mode drawing) '+my/excalidraw-mode))
      (user-error "Not in a drawing"))
    (require 'xwidget)
    (let ((window (or (get-buffer-window drawing) (selected-window))))
      (select-window window)
      (xwidget-webkit-new-session (or url (+my/excalidraw--libraries-url)))
      (let ((xwidget (xwidget-webkit-current-session)))
        (set-xwidget-query-on-exit-flag xwidget nil)
        (xwidget-put xwidget 'callback #'+my/excalidraw--libraries-callback)
        (xwidget-put xwidget '+my/excalidraw-drawing drawing)
        (xwidget-put xwidget '+my/excalidraw-window window)
        (xwidget-put xwidget '+my/excalidraw-watch
                     (run-with-timer 0.2 0.2 #'+my/excalidraw--libraries-watch xwidget))
        (when (fboundp '+my/banner-show)
          (+my/banner-show 'excalidraw-libraries
                           "Pick a library: its \"Add to Excalidraw\" adds it to your drawings' library"
                           :actions '(("Back to the drawing" . +my/excalidraw-libraries-back))))
        xwidget))))

(defun +my/excalidraw--libraries-watch (xwidget)
  "Every 0.2 s while XWIDGET's libraries' site is open: the library its title
says was chosen (see above); done once it's closed."
  (let ((title (and (buffer-live-p (xwidget-buffer xwidget))
                    (not (xwidget-get xwidget '+my/excalidraw-added))
                    (ignore-errors (xwidget-webkit-title xwidget)))))
    (cond ((not (stringp title))
           (when (timerp (xwidget-get xwidget '+my/excalidraw-watch))
             (cancel-timer (xwidget-get xwidget '+my/excalidraw-watch))))
          ((string-prefix-p "exd-library " title)
           (+my/excalidraw--library-picked xwidget (+my/excalidraw--library-in title))))))

(defun +my/excalidraw--library-picked (xwidget library)
  "LIBRARY was chosen in XWIDGET's libraries' site: added after this event
(once), back in the drawing."
  (when (and library (not (xwidget-get xwidget '+my/excalidraw-added)))
    (xwidget-put xwidget '+my/excalidraw-added t)
    (when (timerp (xwidget-get xwidget '+my/excalidraw-watch))
      (cancel-timer (xwidget-get xwidget '+my/excalidraw-watch)))
    (run-at-time 0 nil #'+my/excalidraw--library-chosen xwidget library)))

(defun +my/excalidraw-libraries-back ()
  "Close the libraries' site (the current buffer's), back to its drawing."
  (interactive)
  (when-let* ((xwidget (xwidget-webkit-current-session)))
    (+my/excalidraw--leave-libraries xwidget)))

(defun +my/excalidraw--leave-libraries (xwidget)
  "Close XWIDGET's libraries' site, its drawing shown again in its window;
return the drawing's buffer, if it's still there."
  (when (timerp (xwidget-get xwidget '+my/excalidraw-watch))
    (cancel-timer (xwidget-get xwidget '+my/excalidraw-watch)))
  (let ((drawing (xwidget-get xwidget '+my/excalidraw-drawing))
        (window (xwidget-get xwidget '+my/excalidraw-window))
        (site (xwidget-buffer xwidget)))
    (when (and (buffer-live-p drawing) (window-live-p window))
      (set-window-buffer window drawing)
      (select-window window))
    (when (buffer-live-p site)
      (let ((kill-buffer-query-functions nil))
        (kill-buffer site)))
    (and (buffer-live-p drawing) drawing)))

(defun +my/excalidraw--libraries-callback (xwidget event-type)
  "WebKit's events in the libraries' site: on its way to a library to add,
stopped, the library added (once); others as usual."
  (let ((library (and (eq event-type 'load-changed)
                      (+my/excalidraw--library-in (xwidget-webkit-uri xwidget)))))
    (when (and (not library) (eq event-type 'load-changed)
               (equal (nth 3 last-input-event) "load-finished"))
      (xwidget-webkit-execute-script xwidget +my/excalidraw--libraries-script))
    (if (not library)
        (xwidget-webkit-callback xwidget event-type)
      (ignore-errors (xwidget-webkit-stop-loading xwidget))
      (+my/excalidraw--library-picked xwidget library))))

(defun +my/excalidraw--library-chosen (xwidget library)
  "LIBRARY was chosen in XWIDGET's libraries' site: back to the drawing, the
site closed, the library added."
  (if-let* ((drawing (+my/excalidraw--leave-libraries xwidget)))
      (with-current-buffer drawing
        (+my/excalidraw-add-library library))
    (+my/excalidraw-add-library library)))

;; INSERTING (see above)
(defun +my/excalidraw--dir-here ()
  "The folder of the current buffer's file."
  (if buffer-file-name (file-name-directory buffer-file-name) default-directory))

(defun +my/excalidraw--new-name (dir)
  "A drawing's file in DIR no file has: drawing.excalidraw.svg, drawing-2..."
  (let ((n 1)
        file)
    (while (and (< n 1000)
                (file-exists-p (setq file (expand-file-name
                                           (if (= n 1) "drawing.excalidraw.svg"
                                             (format "drawing-%d.excalidraw.svg" n))
                                           dir))))
      (setq n (1+ n)))
    file))

(defun +my/excalidraw--drawing-name (file)
  "FILE, a drawing's: with .excalidraw.svg after it unless it has a drawing's
extension."
  (if (let ((case-fold-search t))
        (string-match-p "\\.excalidraw\\(?:\\.svg\\)?\\'" file))
      file
    (concat file ".excalidraw.svg")))

(defun +my/excalidraw--link (file)
  "A link from the current buffer to drawing FILE, as an image: Markdown's,
Org's; elsewhere its path. Relative to the buffer's file."
  (let ((path (file-relative-name file (+my/excalidraw--dir-here))))
    (cond ((derived-mode-p 'markdown-mode)
           (format "![](%s)" (replace-regexp-in-string " " "%20" path t t)))
          ((derived-mode-p 'org-mode)
           (format "[[file:%s]]" path))
          (t path))))

(defun +my/excalidraw--at-point ()
  "The drawing a link at point names, if its file exists."
  (require 'thingatpt)
  (require 'url-util)
  (save-excursion
    (let ((case-fold-search t))
      (when (thing-at-point-looking-at "[^][ \t\n()<>\"'|]+\\.excalidraw\\(?:\\.svg\\)?" 500)
        (let* ((path (url-unhex-string (match-string-no-properties 0)))
               (file (expand-file-name (string-remove-prefix "file:" path)
                                       (+my/excalidraw--dir-here))))
          (and (file-exists-p file) file))))))

(defun +my/excalidraw-open (file &optional save-new)
  "Open drawing FILE beside the selected window (it takes focus); SAVE-NEW:
saved once its page has made it (a new one)."
  (let ((buffer (find-file-noselect file)))
    (when save-new
      (with-current-buffer buffer
        (setq +my/excalidraw--save-new t)))
    (pop-to-buffer buffer
                   `((display-buffer-reuse-window display-buffer-in-direction)
                     (direction . right)
                     (window-width . ,(/ (window-total-width) 2))))
    buffer))

(defun +my/excalidraw-insert (file)
  "Link a new drawing FILE at point, as an image, and open it beside (see
above); an existing FILE is linked and opened."
  (interactive
   (list (read-file-name "New drawing: " (+my/excalidraw--dir-here) nil nil
                         (file-name-nondirectory
                          (+my/excalidraw--new-name (+my/excalidraw--dir-here))))))
  (barf-if-buffer-read-only)
  (let* ((file (expand-file-name (+my/excalidraw--drawing-name file)))
         (new (not (file-exists-p file))))
    (when new
      (make-directory (file-name-directory file) t))
    (insert (+my/excalidraw--link file))
    (+my/excalidraw-open file new)))

;; OPTION+ENTER (config/actions.el)
(defun +my/context-actions-excalidraw ()
  "Drawings: edit the one a link at point names; in Markdown and Org, insert
a new one."
  (let ((file (+my/excalidraw--at-point)))
    (append
     (when file
       (list (list "Drawing" "Edit the drawing" (lambda () (+my/excalidraw-open file)))))
     (when (and (derived-mode-p 'markdown-mode 'org-mode) (not buffer-read-only))
       (list (list "Drawing" "Insert a new drawing"
                   (lambda () (call-interactively #'+my/excalidraw-insert))))))))

(when (boundp '+my/context-action-providers)
  (add-to-list '+my/context-action-providers #'+my/context-actions-excalidraw t))

;; THE MODE
(define-derived-mode +my/excalidraw-mode +my/webkit-mode "Drawing"
  "A drawing in Excalidraw, in WebKit (see config/excalidraw.el), a view per
window (config/webkit.el). The buffer has the file's text, under the views:
the page's export of the drawing after each change, saved as any file.

\\{+my/excalidraw-mode-map}"
  (setq-local font-lock-defaults '(nil t)
              revert-buffer-function #'+my/excalidraw--revert
              +my/webkit-url-function #'+my/excalidraw--url
              +my/webkit-watch-function #'+my/excalidraw--watch
              +my/webkit-background #'+my/excalidraw--background
              ;; libraries.excalidraw.com in Emacs (see LIBRARIES).
              +my/webkit-link-function #'+my/excalidraw--link-out
              ;; Saved as the page made it (and the buffer is read-only).
              require-final-newline nil)
  (setq buffer-file-coding-system
        (coding-system-change-text-conversion buffer-file-coding-system 'utf-8))
  ;; Undo is Excalidraw's: the buffer's text is replaced at each change.
  (buffer-disable-undo)
  (add-hook '+my/webkit-load-functions #'+my/excalidraw--loaded nil t)
  ;; First: other hooks see the drawing as saved.
  (add-hook 'before-save-hook #'+my/excalidraw--before-save -90 t)
  (add-hook 'change-major-mode-hook #'+my/excalidraw--stop nil t)
  (add-hook 'kill-buffer-hook #'+my/excalidraw--stop nil t))

(after! evil
  (evil-set-initial-state '+my/excalidraw-mode 'normal))
