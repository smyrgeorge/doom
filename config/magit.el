;;; $DOOMDIR/config/magit.el -*- lexical-binding: t; -*-
;; Magit add-ons. Loaded from config.el.

;; MAGIT
;; Render diffs with git-delta (brew install git-delta).
(use-package! magit-delta
  :hook (magit-mode . magit-delta-mode))

;; List TODO/FIXME/... comments of the repo in the magit status buffer (uses rg).
(use-package! magit-todos
  :after magit
  :config (magit-todos-mode +1))
