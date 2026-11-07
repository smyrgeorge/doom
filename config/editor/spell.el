;;; $DOOMDIR/config/editor/spell.el -*- lexical-binding: t; -*-
;; Spell checking (spell-fu + aspell): the personal dictionary, the tech words.
;; Loaded from config/editor.el.

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

(defvar +my/spell-tech-dictionary nil)

(add-hook! 'spell-fu-mode-hook
  (defun +my/spell-add-tech-words-h ()
    ;; Turning on only: the hook runs when it's turned off too, and in a
    ;; buffer where it never was on the tech words were then its only
    ;; dictionary (spell-fu adds English only to an empty list).
    (when (and (bound-and-true-p spell-fu-mode)
               (file-exists-p +my/spell-tech-words-file))
      (unless +my/spell-tech-dictionary
        (setq +my/spell-tech-dictionary
              (spell-fu--dictionary-create
               :name "spell-fu-tech-words"
               :description (format "Programming words from %s" +my/spell-tech-words-file)
               :update #'spell-fu--personal-update ; reads a one-word-per-line file
               :add-word nil
               :remove-word nil
               :aspell-name nil
               :file +my/spell-tech-words-file)))
      (spell-fu-dictionary-add +my/spell-tech-dictionary))))
