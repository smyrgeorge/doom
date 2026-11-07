;;; $DOOMDIR/config/excalidraw.el -*- lexical-binding: t; -*-
;; Drawings in WebKit (xwidgets), drawn with Excalidraw. Loaded from config.el;
;; its code is in config/excalidraw/.

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

;; Drawings' files (.excalidraw.svg, .excalidraw) open in it.

(add-to-list 'auto-mode-alist '("\\.excalidraw\\(?:\\.svg\\)?\\'" . +my/excalidraw-mode-maybe))

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

(after! evil
  (evil-set-initial-state '+my/excalidraw-mode 'normal))

;; ====== CODE ======

;; In config/excalidraw/, in this order: each part can use what the ones before
;; it define.
(load! "excalidraw/page")
(load! "excalidraw/sync")
(load! "excalidraw/input")
(load! "excalidraw/libraries")
(load! "excalidraw/insert")
(load! "excalidraw/mode")
