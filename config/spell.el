;;; $DOOMDIR/config/spell.el -*- lexical-binding: t; -*-
;; Spell checking (spell-fu + aspell). Loaded from config.el.

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
