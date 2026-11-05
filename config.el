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

;; WINDOW
(add-hook 'window-setup-hook #'toggle-frame-maximized)

;; TERMINAL
;; Paint the terminal's own background (the strip below the echo area) with the
;; theme's background via OSC 11, and restore it (OSC 111) when Emacs exits.
(defun +my/tty-sync-bg-h (&rest _)
  (dolist (frame (frame-list))
    (when (eq (framep frame) t)         ; tty frame
      (when-let* ((bg (face-background 'default frame))
                  ((string-prefix-p "#" bg)))
        (send-string-to-terminal (format "\e]11;%s\a" bg)
                                 (frame-terminal frame))))))
(defun +my/tty-reset-bg-h (&rest _)
  (dolist (frame (frame-list))
    (when (eq (framep frame) t)
      (send-string-to-terminal "\e]111\a" (frame-terminal frame)))))
(add-hook 'doom-load-theme-hook #'+my/tty-sync-bg-h)
(add-hook 'tty-setup-hook #'+my/tty-sync-bg-h)
(add-hook 'after-make-frame-functions #'+my/tty-sync-bg-h)
(add-hook 'kill-emacs-hook #'+my/tty-reset-bg-h)
;; emacsclient -t: restore the terminal when its frame is closed.
(add-hook 'delete-frame-functions
          (defun +my/tty-reset-frame-bg-h (frame)
            (when (eq (framep frame) t)
              (send-string-to-terminal "\e]111\a" (frame-terminal frame)))))

;; EVIL
(add-hook! 'after-save-hook #'evil-normal-state)

;; TREEMACS (IntelliJ-like project view)
(setq +treemacs-git-mode 'deferred)     ; async git status, incl. folders (python3)
(after! treemacs
  (setq treemacs-is-never-other-window nil) ; reachable with SPC w w (Doom: t)
  (treemacs-follow-mode +1)             ; highlight the current file (Doom: off)
  (treemacs-project-follow-mode +1))    ; show the current buffer's project
;; Arrows mirror h/l (treemacs-evil binds h/l but leaves ←/→ as char motions).
(map! :after treemacs-evil
      :map evil-treemacs-state-map
      [left]  #'treemacs-COLLAPSE-action
      [right] #'treemacs-RET-action)
;; Update the saved file's git status in treemacs. macOS uses kqueue for file
;; notifications, which doesn't report in-place edits, so filewatch misses them.
(defun +my/treemacs-git-update-on-save-h ()
  (when-let* ((file buffer-file-name)
              ((featurep 'treemacs)))
    (dolist (win (window-list))
      (when (with-current-buffer (window-buffer win) (derived-mode-p 'treemacs-mode))
        (with-selected-window win
          (ignore-errors (treemacs-update-single-file-git-state file)))))))
(add-hook 'after-save-hook #'+my/treemacs-git-update-on-save-h)
;; Treemacs hides its window from winum; number it (leftmost => SPC w 1).
(after! (treemacs winum)
  (setq winum-ignored-buffers-regexp
        (remove (regexp-quote treemacs-buffer-name-prefix)
                winum-ignored-buffers-regexp)))

;; Open treemacs the first time a project file is shown in each workspace
;; (SPC p p, SPC SPC, SPC f r, dashboard, ...). If you close it afterwards
;; (SPC o p) it stays closed for that workspace.
(defun +my/treemacs-auto-open-h (&rest _)
  (when-let* ((buf (window-buffer (selected-window)))
              ((buffer-file-name buf))
              ((with-current-buffer buf (doom-project-root)))
              (persp (and (bound-and-true-p persp-mode) (get-current-persp)))
              ((not (persp-parameter '+my/treemacs-opened persp))))
    (set-persp-parameter '+my/treemacs-opened t persp)
    (require 'treemacs)
    (when (eq (treemacs-current-visibility) 'none)
      (with-current-buffer buf
        (save-selected-window
          (treemacs-add-and-display-current-project-exclusively))))))
(add-hook 'window-buffer-change-functions #'+my/treemacs-auto-open-h)

;; MAGIT
;; Render diffs with git-delta (brew install git-delta).
(use-package! magit-delta
  :hook (magit-mode . magit-delta-mode))

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
        (agent-shell-anthropic-make-authentication :login t)))

(map! :leader
      :desc "Claude Code (agent-shell)" "o c" #'agent-shell-anthropic-start-claude-code
      :desc "Agent shell"               "o C" #'agent-shell)

;; MARKDOWN
;; Live preview inside Emacs (re-renders on save). GUI: real WebKit via
;; xwidgets; terminal: eww.
(defun +my/markdown-live-preview-window (file)
  (if (and (display-graphic-p) (featurep 'xwidget-internal))
      (progn
        (require 'xwidget)
        (xwidget-webkit-browse-url (concat "file://" file))
        (xwidget-buffer (xwidget-webkit-current-session)))
    (markdown-live-preview-window-eww file)))
(after! markdown-mode
  (setq markdown-live-preview-window-function #'+my/markdown-live-preview-window))
;; Both maps: with +tree-sitter, .md files open in markdown-ts-mode.
(map! :after markdown-mode
      :map markdown-mode-map
      :localleader
      :desc "Live preview (in Emacs)" "p" #'markdown-live-preview-mode
      :desc "Preview in browser"      "P" #'markdown-preview)
(map! :after markdown-ts-mode
      :map markdown-ts-mode-map
      :localleader
      :desc "Live preview (in Emacs)" "p" #'markdown-live-preview-mode
      :desc "Preview in browser"      "P" #'markdown-preview)

;; PROJECTILE
;; Discover projects using 'projectile-discover-projects-in-search-path'
(setq projectile-project-search-path '("~/dev"))

;; TABS
;; Workspaces disable uniquify, so same-named files show as lib.rs, lib.rs<2>.
;; When two tabs (in the same tab group) share a file name, label them with the
;; shortest distinguishing path instead, e.g. crate-a/src/lib.rs.
(defun +my/tabs-unique-label (file others)
  "Return the shortest trailing part of FILE's path not shared by OTHERS."
  (let* ((split (lambda (f) (reverse (split-string (abbreviate-file-name f) "/" t))))
         (parts (funcall split file))
         (other-parts (mapcar split others))
         (n 1))
    (while (and (< n (length parts))
                (seq-some (lambda (o) (equal (seq-take o n) (seq-take parts n)))
                          other-parts))
      (setq n (1+ n)))
    (string-join (reverse (seq-take parts n)) "/")))

(defadvice! +my/tabs-label-with-path-a (fn tab)
  :around #'centaur-tabs-buffer-tab-label
  (let* ((buf (car tab))
         (file (buffer-file-name buf))
         (name (and file (file-name-nondirectory file)))
         (others
          (and file (not centaur-tabs--buffer-show-groups)
               (delq nil (mapcar (lambda (b)
                                   (let ((f (buffer-file-name b)))
                                     (and f (not (eq b buf))
                                          (equal (file-name-nondirectory f) name)
                                          f)))
                                 (centaur-tabs-tab-values (centaur-tabs-tab-tabset tab)))))))
    (if others
        (format " %s" (+my/tabs-unique-label file others))
      (funcall fn tab))))

;; UNIQUIFY
;; Meaningful names for buffers with the same name.
(after! uniquify
  (setq uniquify-buffer-name-style 'post-forward-angle-brackets
        uniquify-separator "/"
        uniquify-after-kill-buffer-p t
        uniquify-ignore-buffers-re "^\\*"))
