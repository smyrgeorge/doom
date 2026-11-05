;;; $DOOMDIR/config/emacs.el -*- lexical-binding: t; -*-
;; Emacs itself: garbage collection. Loaded from config.el.

;; ====== VARIABLES ======

;; GARBAGE COLLECTION
;; gcmh (Doom) lets garbage pile up to 128 MB while you work, collects once
;; you've been idle a moment, then drops the limit to 800 KB until the next
;; command. But work keeps happening "idle" (a language server's replies,
;; highlighting, redraws after opening a file), and at 800 KB it collected
;; every few redraws, ~70 ms each (the heap is big): opening a file stuttered
;; for a second after it showed. 32 MB while idle: rarely a collection then.
(setq gcmh-low-cons-threshold (* 32 1024 1024))
