;;; $DOOMDIR/config/scroll.el -*- lexical-binding: t; -*-
;; Scrolling. Loaded from config.el.

;; SMOOTH SCROLL (ultra-scroll, from Doom's :ui smooth-scroll)
;; While scrolling past the window, ultra-scroll switches off the modes in
;; `ultra-scroll-hide-functions' and back on 0.25s after scrolling stops. Doom
;; adds hl-todo-mode and jit-lock-mode there, which makes TODO/FIXME highlights
;; vanish and come back, and spell-fu underlines (drawn through jit-lock)
;; blink. Keep them on; smooth scrolling itself is unchanged.
(after! ultra-scroll
  (remove-hook 'ultra-scroll-hide-functions #'hl-todo-mode)
  (remove-hook 'ultra-scroll-hide-functions #'jit-lock-mode))
