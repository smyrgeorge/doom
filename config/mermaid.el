;;; $DOOMDIR/config/mermaid.el -*- lexical-binding: t; -*-
;; Mermaid diagrams: mermaid-mode for Mermaid files, every diagram in the
;; theme's colours. Loaded from config.el; its code is in config/mermaid/.

;; ====== VARIABLES ======

;; MERMAID FILES
;; .mmd and .mermaid files open in mermaid-mode (MELPA): flowcharts' and
;; sequence diagrams' keywords coloured (the other diagrams draw, uncoloured),
;; TAB indents (`mermaid-indentation-level'), %% comments. SPC m c draws the
;; file as an SVG next to it (mmdc, scripts/tools.sh) and opens it; SPC m b /
;; SPC m r the buffer / the region (the SVG in Doom's cache), SPC m f a file
;; you pick. SPC m o opens the buffer (or the region) in Mermaid's Live Editor,
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
;; mmdc (-c): mermaid-mode's commands draw in it too, their SVG made to show
;; in Emacs (mermaid/mode.el).
(defvar +my/mermaid-config-file (expand-file-name "mermaid/config.json" doom-cache-dir)
  "Mermaid's config in the theme's colours, for mmdc (written as needed).")

(after! mermaid-mode
  (setq mermaid-output-format ".svg"
        mermaid-tmp-dir (expand-file-name "mermaid/tmp/" doom-cache-dir)
        mermaid-flags (format "-c %s -b transparent" +my/mermaid-config-file)))

;; ====== KEY BINDINGS ======

(map! :after mermaid-mode
      :map mermaid-mode-map
      :localleader
      :desc "Draw the file (SVG)"      "c" #'mermaid-compile
      :desc "Draw the buffer"          "b" #'mermaid-compile-buffer
      :desc "Draw the region"          "r" #'mermaid-compile-region
      :desc "Draw a file…"             "f" #'mermaid-compile-file
      :desc "Open in the Live Editor"  "o" #'mermaid-open-browser
      :desc "Mermaid's docs"           "d" #'mermaid-open-doc)

;; ====== CODE ======

;; In config/mermaid/, in this order: each part can use what the ones before
;; it define.
(load! "mermaid/theme")
(load! "mermaid/mode")
