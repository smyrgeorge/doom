;;; $DOOMDIR/config/evil.el -*- lexical-binding: t; -*-
;; Evil (vim emulation) tweaks. Loaded from config.el.

;; EVIL
;; Saving a buffer returns to normal state.
(add-hook! 'after-save-hook #'evil-normal-state)
