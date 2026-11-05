;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

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

;; CUSTOM KEY BINDINGS
;; GUI only: in a terminal, M-[ / M-] are ESC [ / ESC ], the prefixes of
;; escape sequences (mouse, focus, OSC), so binding them flips buffers.
(defun +my/gui-only (cmd)
  `(menu-item "" ,cmd :filter ,(lambda (c) (when (display-graphic-p) c))))
(map! "M-[" (+my/gui-only #'previous-buffer)
      "M-]" (+my/gui-only #'next-buffer))
(map! "s-[" #'better-jumper-jump-backward)
(map! "s-]" #'better-jumper-jump-forward)

;; WINDOW (maximized frame; new windows get focus)
(load! "config/window")

;; TERMINAL
(load! "config/terminal")

;; EVIL
(add-hook! 'after-save-hook #'evil-normal-state)

;; TREEMACS (IntelliJ-like project view)
(load! "config/treemacs")

;; MAGIT
;; Render diffs with git-delta (brew install git-delta).
(use-package! magit-delta
  :hook (magit-mode . magit-delta-mode))

;; SPC g d: the current file's diff in a pane on the right.
(load! "config/git")

;; List TODO/FIXME/... comments of the repo in the magit status buffer (uses rg).
(use-package! magit-todos
  :after magit
  :config (magit-todos-mode +1))

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)
(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; SPELL
;; spell-fu ignores the personal dictionary until its file exists, so adding a
;; word (zg / Option+Enter) fails with "Cannot add ... to any active dictionary".
;; Create Doom's default one (under ~/.config/emacs/.local/etc/ispell/) if missing.
(after! ispell
  (when (and ispell-personal-dictionary
             (not (file-exists-p ispell-personal-dictionary)))
    (make-directory (file-name-directory ispell-personal-dictionary) t)
    (with-temp-file ispell-personal-dictionary
      (insert "personal_ws-1.1 en 0\n"))))

;; CONTEXT ACTIONS (Option+Enter, like JetBrains' Alt+Enter)
(load! "config/actions")

;; KOTLIN
;; Use JetBrains' kotlin-lsp (brew install --cask kotlin-lsp) instead of
;; lsp-mode's default kotlin-language-server.
(after! lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("kotlin-lsp" "--stdio"))
    :major-modes '(kotlin-mode kotlin-ts-mode)
    :priority 1                         ; win over kotlin-ls (-1)
    :server-id 'kotlin-lsp)))

;; AGENT-SHELL (Claude Code via ACP)
;; Uses the Claude CLI login (run `claude` once in a terminal to log in).
(use-package! agent-shell
  :commands (agent-shell agent-shell-anthropic-start-claude-code)
  :config
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t)
        ;; New shells (e.g. from the Option+Enter Claude actions) start Claude
        ;; Code without asking which agent to use.
        agent-shell-preferred-agent-config 'claude-code))

(map! :leader
      :desc "Claude Code (agent-shell)" "o c" #'agent-shell-anthropic-start-claude-code
      :desc "Agent shell"               "o C" #'agent-shell)

;; MARKDOWN
(load! "config/markdown")

;; PROJECTILE
;; Discover projects using 'projectile-discover-projects-in-search-path'
(setq projectile-project-search-path '("~/dev"))
;; List project files fresh on every SPC SPC (fd / git ls-files are fast) instead
;; of Doom's persistent cache, which misses files created outside Emacs (CLI,
;; Claude Code, git checkout) until `SPC p i'.
(setq projectile-enable-caching nil)

;; TABS
(load! "config/tabs")

;; UNIQUIFY
;; Meaningful names for buffers with the same name.
(after! uniquify
  (setq uniquify-buffer-name-style 'post-forward-angle-brackets
        uniquify-separator "/"
        uniquify-after-kill-buffer-p t
        uniquify-ignore-buffers-re "^\\*"))
