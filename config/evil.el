;;; $DOOMDIR/config/evil.el -*- lexical-binding: t; -*-
;; Evil (vim emulation) tweaks. Loaded from config.el.

;; EVIL
;; Saving a buffer returns to normal state.
(add-hook! 'after-save-hook #'evil-normal-state)

;; Q CLOSES TRANSIENT MENUS
;; Transient menus (agent-shell's help and drawing menus, magit's...) closed
;; with Esc (Doom binds it) or C-g, but q only said "Unbound suffix: q". q
;; closes them too now, like Vim's q and Doom's popups. A menu that uses q for
;; something of its own keeps it: in magit's dispatch it buries the buffer, in
;; blame and git-timemachine it quits those (`transient-bind-q-to-quit' would
;; move such keys to Q, and Q's to M-q; not done).
(after! transient
  (keymap-set transient-base-map "q" #'transient-quit-one)
  (keymap-set transient-sticky-map "q" #'transient-quit-seq))
