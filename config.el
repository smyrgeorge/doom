;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; ====== VARIABLES ======

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
(setq user-full-name "Yorgos S."
      user-mail-address "smyrgeorge@gmail.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; JetBrains Mono (brew install --cask font-jetbrains-mono): has ligatures.
(setq doom-font (font-spec :family "JetBrains Mono" :size 13))

;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/dev/org/")

;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; CUSTOM CONFIG ;;
(setq default-directory "~")

;; Maximum line length: where the right margin's line is drawn and where gq /
;; M-q wrap text (config/editor.el). A project's .editorconfig overrides it with
;; max_line_length. `setq-default', not `setq': each buffer has its own.
(setq-default fill-column 120)

;; Tiling strategy: where SPC w SPC opens a new pane, like a tiling window
;; manager (config/tiling.el). `tall': a main pane on the left, the others
;; stacked on the right (Amethyst's Tall).
(setq +my/tiling-strategy 'tall)

;; ====== CODE ======

;; EMACS (garbage collection)
(load! "config/emacs")

;; WINDOW (maximized frame; new windows get focus)
(load! "config/window")

;; TILING (SPC w SPC: a new pane where the tiling strategy puts it)
(load! "config/tiling")

;; CHILD FRAMES (laid over a window: the notices, the error stripe, WebKit's cover)
(load! "config/childframe")

;; BANNERS (notices at the top of a window, with actions)
(load! "config/banner")

;; ERROR STRIPE (marks for git changes and errors at the right edge)
(load! "config/stripe")

;; TERMINAL
(load! "config/terminal")

;; TREEMACS (project view)
(load! "config/treemacs")

;; CHEATSHEET (tips panel under treemacs: Vim, Doom and this config's keys)
;; Disabled for now; uncomment to try it again.
;;(load! "config/cheatsheet")

;; MAGIT (git-delta diffs, TODOs in the status buffer)
(load! "config/magit")

;; SPC g d: the current file's diff in a pane on the right.
(load! "config/git")

;; MERGE (conflicts resolved in three panes: e on a conflicted file in Magit)
(load! "config/merge")

;; EXAMPLES (M-x +my/example: a feature shown on files of its own, e.g. a merge in conflict)
(load! "config/examples")

;; EDITOR (SPC c ~: cycle case style)
(load! "config/editor")

;; LSP (Kotlin: JetBrains' kotlin-lsp; lsp-ui's usages/definitions peek: calmer, with
;; functions and line numbers)
(load! "config/lsp")

;; AGENT-SHELL (Claude Code via ACP; SPC o c / SPC o C)
(load! "config/agent-shell")

;; WEBKIT (web pages inside Emacs: what the PDF viewer, the Markdown preview and
;; drawings share)
(load! "config/webkit")

;; MARKDOWN
(load! "config/markdown")

;; PDF (PDFs in WebKit, drawn by PDF.js, inside the file's tab)
(load! "config/pdf")

;; DRAWINGS (*.excalidraw.svg, *.excalidraw: Excalidraw in WebKit, in the file's tab)
(load! "config/excalidraw")

;; PROJECTILE (projects under ~/dev, no file cache)
(load! "config/projectile")

;; SEARCH EVERYWHERE (classes, files, symbols, actions in one list)
(load! "config/search")

;; PROFILING (SPC h T starts the profiler; again, it writes a profile for an
;; agent, who reads .claude/skills/emacs-profiling first)
(load! "config/profiling")

;; COMPILE (byte-compile this config's functions when Emacs is idle; load last)
(load! "config/compile")
