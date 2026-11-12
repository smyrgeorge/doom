;;; $DOOMDIR/config/mermaid.el -*- lexical-binding: t; -*-
;; Mermaid diagrams: mermaid-mode for Mermaid files, every diagram in the
;; theme's colours. Loaded from config.el; its code is in config/mermaid/.

;; ====== VARIABLES ======

;; MERMAID FILES
;; .mmd and .mermaid files open in mermaid-mode (MELPA): flowcharts' and
;; sequence diagrams' keywords coloured (the other diagrams draw, uncoloured),
;; TAB indents (`mermaid-indentation-level'), %% comments. SPC m c draws the
;; file as an SVG next to it and opens it, once drawn (by the renderer, below:
;; Emacs doesn't wait); SPC m b / SPC m r the buffer / the region (the SVG in
;; Doom's cache), SPC m f a file you pick. SPC m o opens the buffer (or the region) in Mermaid's Live Editor,
;; in the browser; SPC m d Mermaid's docs. Org's #+begin_src mermaid :file
;; x.svg blocks draw with C-c C-c. ```mermaid blocks are coloured by
;; mermaid-mode in Markdown files and Claude Code's replies (as any language
;; whose mode is there).
(add-to-list 'auto-mode-alist '("\\.mermaid\\'" . mermaid-mode))

;; THE THEME'S COLOURS
;; Every diagram is drawn in the current theme's colours, taken from its
;; faces: Mermaid's base theme, its colours set from them (mermaid/theme.el):
;; nodes a tint of `font-lock-keyword-face' bordered by it, their text and the
;; lines `default''s, notes `warning''s, errors and critical tasks `error''s,
;; groups' borders, lifelines and done tasks `shadow''s, a series (a pie's
;; slices, a git graph's branches, a mindmap's levels) the syntax colours; the
;; default font. A theme switch rewrites it, then runs
;; `+my/mermaid-theme-hook' (for what shows diagrams). Written as JSON for
;; mmdc (-c): Org's mermaid blocks draw in it too.
(defvar +my/mermaid-config-file (expand-file-name "mermaid/config.json" doom-cache-dir)
  "Mermaid's config in the theme's colours, for mmdc (written as needed).")

;; THE RENDERER
;; A diagram is drawn by mmdc (mermaid-cli: node and a headless Chrome, a
;; second or so each; scripts/tools.sh installs it) in the background: Emacs
;; never waits. Each is drawn once per theme, kept in Doom's cache (by its
;; source's and the theme's hash) while it's used: one unused for
;; `+my/mermaid-cache-days' is deleted. Several asking for the same diagram
;; share its run; at most `+my/mermaid-jobs' run at once, one is stopped after
;; `+my/mermaid-timeout' seconds. A diagram with an error gets Mermaid's
;; message; without mmdc, what to install. As root (a container), Chrome runs
;; without its sandbox (it won't otherwise). On Linux on ARM, where Chrome's
;; headless shell has no build, the system's chromium (scripts/tools.sh
;; installs it there). mermaid-mode's docker way (`mermaid-mmdc-location'
;; "docker") isn't used: mmdc on the PATH.
(defvar +my/mermaid-mmdc "mmdc"
  "mermaid-cli's command, which draws the diagrams.")

(defvar +my/mermaid-chrome nil
  "The Chrome mmdc runs (its path); nil: puppeteer's own, or on Linux on ARM
the system's chromium.")

(defvar +my/mermaid-jobs 2
  "How many diagrams are drawn at once (each runs a Chrome).")

(defvar +my/mermaid-timeout 60
  "Seconds a diagram's drawing may take before it's stopped.")

(defvar +my/mermaid-cache-directory (expand-file-name "mermaid/svg/" doom-cache-dir)
  "Where the drawn diagrams are kept.")

(defvar +my/mermaid-cache-days 30
  "Days a drawn diagram is kept unused.")

(after! mermaid-mode
  (setq mermaid-mmdc-location +my/mermaid-mmdc
        mermaid-output-format ".svg"
        mermaid-tmp-dir (expand-file-name "mermaid/tmp/" doom-cache-dir)
        mermaid-flags (format "-c %s -b transparent" +my/mermaid-config-file)))

;; THE PREVIEW
;; SPC m p shows the diagram beside its file, in a pane of its own, redrawn
;; as you type (once you pause), in the theme's colours (a theme switch
;; re-themes it); SPC m p again closes it, as q in it does. In the GUI with
;; WebKit (xwidgets): a page drawing it with mermaid.js, at once; +, - and 0
;; zoom it (0: as wide as it is, at most the pane), j / k, C-d / C-u, gg / G
;; scroll. Without WebKit: mmdc's SVG (the renderer), a second or so after
;; you pause. An error shows Mermaid's message under the last drawing. In a
;; terminal, SPC m p opens Mermaid's Live Editor in the browser instead.
;; mermaid.js (the version mmdc draws with) is downloaded once, from
;; jsdelivr, its SHA-256 checked below (M-x +my/mermaid-js-install does it
;; again); without it (offline), the preview is mmdc's SVG.
;; PREVIEW NOTICE
;; A Mermaid file opens with a notice at the top (config/banner.el) offering
;; the preview: its button opens it, or shows it again if its pane was closed.
;; It stays until its ✕. Only where the preview works (the GUI), for files.
(defvar +my/mermaid-preview-notice t
  "Offer the preview in a notice when a Mermaid file opens.")

(defvar +my/mermaid-js-version "12.3.0"
  "The mermaid.js version the preview draws with (see above).")

(defvar +my/mermaid-js-sha256 "336df803d87a38b70a01e736e666c8f7601d2ce42f5e47c8fafe5d721074b9a3"
  "The SHA-256 of mermaid.js's dist/mermaid.min.js, that version's.")

(defvar +my/mermaid-js-dir
  (expand-file-name (concat "mermaid-" +my/mermaid-js-version "/") doom-data-dir)
  "Where mermaid.js is downloaded to.")

;; ====== KEY BINDINGS ======

(map! :after mermaid-mode
      :map mermaid-mode-map
      :localleader
      :desc "Preview"                  "p" #'+my/mermaid-preview-toggle
      :desc "Draw the file (SVG)"      "c" #'mermaid-compile
      :desc "Draw the buffer"          "b" #'mermaid-compile-buffer
      :desc "Draw the region"          "r" #'mermaid-compile-region
      :desc "Draw a file…"             "f" #'mermaid-compile-file
      :desc "Open in the Live Editor"  "o" #'mermaid-open-browser
      :desc "Mermaid's docs"           "d" #'mermaid-open-doc)

;; The preview's pane: a WebKit page's keys (config/webkit.el), its zoom.
(defvar +my/mermaid-preview-page-mode-map (make-sparse-keymap)
  "Keys of a Mermaid preview's page (see `+my/mermaid-preview-page-mode').")

(map! :map +my/mermaid-preview-page-mode-map
      :nm "j"       #'+my/webkit-scroll-down
      :nm "k"       #'+my/webkit-scroll-up
      :nm "<down>"  #'+my/webkit-scroll-down
      :nm "<up>"    #'+my/webkit-scroll-up
      :nm "C-d"     #'+my/webkit-half-screen-down
      :nm "C-u"     #'+my/webkit-half-screen-up
      :nm "gg"      #'+my/webkit-top
      :nm "G"       #'+my/webkit-bottom
      :nm "+"       #'+my/mermaid-preview-zoom-in
      :nm "="       #'+my/mermaid-preview-zoom-in
      :nm "-"       #'+my/mermaid-preview-zoom-out
      :nm "0"       #'+my/mermaid-preview-zoom-reset
      :gnm "q"      #'kill-current-buffer)

;; Clicks are WebKit's: Emacs only selects the window (config/webkit.el).
(+my/webkit-bind-clicks +my/mermaid-preview-page-mode-map)

(defvar +my/mermaid-preview-image-mode-map (make-sparse-keymap)
  "Keys of a Mermaid preview's image (see `+my/mermaid-preview-image-mode').")

(map! :map +my/mermaid-preview-image-mode-map
      :gnm "q" #'kill-current-buffer)

(after! evil
  (evil-set-initial-state '+my/mermaid-preview-page-mode 'normal)
  (evil-set-initial-state '+my/mermaid-preview-image-mode 'normal))

;; ====== CODE ======

;; In config/mermaid/, in this order: each part can use what the ones before
;; it define.
(load! "mermaid/theme")
(load! "mermaid/render")
(load! "mermaid/mode")
(load! "mermaid/page")
(load! "mermaid/preview")
(load! "mermaid/notice")
