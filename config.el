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

;; ====== KEY BINDINGS ======

;; CUSTOM KEY BINDINGS
;; GUI only: in a terminal, M-[ / M-] are ESC [ / ESC ], the prefixes of
;; escape sequences (mouse, focus, OSC), so binding them flips buffers.
(defun +my/gui-only (cmd)
  `(menu-item "" ,cmd :filter ,(lambda (c) (when (display-graphic-p) c))))

(map! "M-[" (+my/gui-only #'previous-buffer)
      "M-]" (+my/gui-only #'next-buffer))

(map! "s-[" #'better-jumper-jump-backward)

(map! "s-]" #'better-jumper-jump-forward)

;; ====== CODE ======

;; WINDOW (maximized frame; new windows get focus)
(load! "config/window")

;; SCROLL (mouse scrolling leaves the caret where it is, like IntelliJ)
;; Disabled for now: Emacs' default scrolling; uncomment to try it again.
;;(load! "config/scroll")

;; ERROR STRIPE (IntelliJ-like marks for git changes and errors at the right edge)
(load! "config/stripe")

;; STICKY HEADER (the functions/classes around the top visible line)
(load! "config/sticky")

;; TERMINAL
(load! "config/terminal")

;; EVIL (back to normal state on save)
(load! "config/evil")

;; TREEMACS (IntelliJ-like project view)
(load! "config/treemacs")

;; CHEATSHEET (tips panel under treemacs: Vim, Doom and this config's keys)
;; Disabled for now; uncomment to try it again.
;;(load! "config/cheatsheet")

;; MAGIT (git-delta diffs, TODOs in the status buffer)
(load! "config/magit")

;; SPC g d: the current file's diff in a pane on the right.
(load! "config/git")

;; EDITOR (SPC c ~: cycle case style)
(load! "config/editor")

;; SPELL (create the personal dictionary if missing)
(load! "config/spell")

;; CONTEXT ACTIONS (Option+Enter, like JetBrains' Alt+Enter)
(load! "config/actions")

;; LSP (Kotlin: JetBrains' kotlin-lsp)
(load! "config/lsp")

;; AGENT-SHELL (Claude Code via ACP; SPC o c / SPC o C)
(load! "config/agent-shell")

;; MARKDOWN
(load! "config/markdown")

;; PROJECTILE (projects under ~/dev, no file cache)
(load! "config/projectile")

;; SEARCH EVERYWHERE (IntelliJ's double Shift: classes, files, symbols, actions)
(load! "config/search")

;; TABS
(load! "config/tabs")
