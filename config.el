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

;; NEOTREE (IntelliJ-like project view)
(after! neotree
  (setq neo-theme 'nerd-icons))         ; file/folder icons (Doom default: 'nerd)

;; Highlight the whole selected line instead of showing a cursor.
(add-hook! 'neotree-mode-hook
  (defun +my/neotree-line-cursor-h ()
    (setq-local evil-normal-state-cursor (list nil)
                evil-motion-state-cursor (list nil)
                evil-emacs-state-cursor  (list nil)
                cursor-type nil)
    (hl-line-mode +1)))

(defun +my/neotree-reveal (file)
  "Show FILE in neotree without leaving the current window.
Re-roots neotree to FILE's project if FILE is outside the current root."
  (require 'neotree)
  (save-selected-window
    (unless (neo-global--file-in-root-p file)
      (neotree-dir (or (doom-project-root (file-name-directory file))
                       (file-name-directory file))))
    (neo-global--with-window
      (neo-buffer--select-file-node file t))))

;; 1. SPC p p: pick a file first, then open the project tree on that file.
;;    Cancelling the file picker (C-g) leaves neotree closed.
(setq +workspaces-switch-project-function
      (lambda (dir)
        (doom-project-find-file dir)
        (let ((file buffer-file-name))
          (save-selected-window (neotree-dir dir))
          (when file (+my/neotree-reveal file)))))

;; 2. Follow the current buffer: highlight its file in neotree (if open).
(defun +my/neotree-follow-h (&rest _)
  (when-let* (((featurep 'neotree))
              ((neo-global--window-exists-p))
              (file (buffer-file-name (window-buffer (selected-window))))
              ((not (equal file (neo-global--with-buffer
                                  (neo-buffer--get-filename-current-line))))))
    (condition-case err
        (+my/neotree-reveal file)
      (error (message "neotree follow: %s" (error-message-string err))))))
(add-hook 'window-buffer-change-functions #'+my/neotree-follow-h)
(add-hook 'window-selection-change-functions #'+my/neotree-follow-h)

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

;; PROJECTILE
;; Discover projects using 'projectile-discover-projects-in-search-path'
(setq projectile-project-search-path '("~/dev"))

;; UNIQUIFY
;; Meaningful names for buffers with the same name.
(after! uniquify
  (setq uniquify-buffer-name-style 'post-forward-angle-brackets
        uniquify-separator "/"
        uniquify-after-kill-buffer-p t
        uniquify-ignore-buffers-re "^\\*"))
