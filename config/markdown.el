;;; $DOOMDIR/config/markdown.el -*- lexical-binding: t; -*-
;; Markdown live preview inside Emacs. Loaded from config.el; its code is in
;; config/markdown/.

;; ====== VARIABLES ======

;; MARKDOWN
;; Live preview inside Emacs (GUI, xwidget WebKit): re-renders as you type and
;; scrolls to the cursor line. pandoc's `sourcepos' tags each element with its
;; source line (data-pos="L:C-L:C"), which the scroll script uses.
;; Its pane is a WebKit page (config/webkit.el): split, each pane shows the
;; preview, following the cursor; it opens without a white flash; links to
;; files open them in Emacs, in the file's pane, other links in the browser, links to a
;; heading (#install) scroll there. In it, j / k, C-d / C-u, C-f / C-b, gg / G
;; scroll, y or Cmd+C (Linux: Ctrl+Shift+C) copies the selected text, q
;; closes it (as SPC m p).
;; Terminal, or an Emacs without xwidgets (most Linux distributions'): falls
;; back to markdown-mode's eww preview (updates on save).
;; PREVIEW NOTICE
;; A Markdown file opens with a notice at the top (config/banner.el) offering
;; the live preview: its button opens it, or shows it again if its pane was
;; closed, and does nothing more while it's on screen. The notice stays until
;; its ✕, and doesn't come back for that buffer. Only where the live preview
;; works (GUI, xwidgets, pandoc), and for files.
;; SPC m p closes the preview when it's on screen, else shows it (as the
;; notice's button).
(defvar +my/markdown-preview-notice t
  "Offer the live preview in a notice when a Markdown file opens.")

;; MERMAID DIAGRAMS
;; ```mermaid blocks show as diagrams in the live preview, drawn by mermaid.js
;; (config/mermaid.el: downloaded once), in the theme's colours on the page's
;; background, redrawn as you edit them (only a block that changed), re-themed
;; with the page; an error shows Mermaid's message under the block's last
;; drawing. In the Markdown buffer a block stays text, coloured by
;; mermaid-mode.

;; REFLOWED ON SCREEN
;; A file filled at 120 columns in a narrower pane wrapped raggedly (a short
;; row after each source line). In markdown-ts-mode, a paragraph's lines (a
;; list item's, a quote's) are shown as one line, wrapped at the pane's edge,
;; the following rows under the item's text; the file isn't changed. Hard
;; line breaks, code blocks, tables, headings are left as they are. In
;; config.el, (setq +my/markdown-reflow nil) turns it off.
(defvar +my/markdown-reflow t
  "Show a Markdown paragraph's lines as one, wrapped at the pane's edge.")

;; Hide marksman's false "Ambiguous link" warnings (see markdown/marksman.el).
(after! lsp-mode
  (setq lsp-diagnostic-filter #'+md--drop-false-link-warnings))

;; ====== KEY BINDINGS ======

;; Both maps: with +tree-sitter, .md files open in markdown-ts-mode.
(map! :after markdown-mode
      :map markdown-mode-map
      :localleader
      :desc "Live preview (in Emacs)" "p" #'+my/markdown-preview-toggle
      :desc "Preview in browser"      "P" #'markdown-preview)

(map! :after markdown-ts-mode
      :map markdown-ts-mode-map
      :localleader
      :desc "Live preview (in Emacs)" "p" #'+my/markdown-preview-toggle
      :desc "Preview in browser"      "P" #'markdown-preview)

;; The preview's pane (see above): keys of a WebKit page (config/webkit.el).
(defvar +md-preview-page-mode-map (make-sparse-keymap)
  "Keys of a Markdown preview's pane (see `+md-preview-page-mode').")

(map! :map +md-preview-page-mode-map
      "s-c"         #'+my/webkit-copy
      :nm "j"       #'+my/webkit-scroll-down
      :nm "k"       #'+my/webkit-scroll-up
      :nm "<down>"  #'+my/webkit-scroll-down
      :nm "<up>"    #'+my/webkit-scroll-up
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
      :gnm "q"      #'kill-current-buffer)

;; On Linux Ctrl+Shift+C copies (config/emacs.el, KEYS).
(map! :unless (+my/macos-p)
      :map +md-preview-page-mode-map
      :nm "C-S-c" #'+my/webkit-copy)

;; Clicks are WebKit's: Emacs only selects the window (config/webkit.el).
(+my/webkit-bind-clicks +md-preview-page-mode-map)

;; The pane starts in normal state, where its keys are.
(after! evil
  (evil-set-initial-state '+md-preview-page-mode 'normal))

;; ====== CODE ======

;; In config/markdown/, in this order: each part can use what the ones before
;; it define.
(load! "markdown/page")
(load! "markdown/mermaid")
(load! "markdown/preview")
(load! "markdown/notice")
(load! "markdown/marksman")
(load! "markdown/reflow")
