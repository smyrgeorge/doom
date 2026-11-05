;;; $DOOMDIR/config/spell.el -*- lexical-binding: t; -*-
;; Spell checking (spell-fu + aspell). Loaded from config.el.

;; ====== VARIABLES ======

;; CAMELCASE
;; Check identifiers like AgreementController as Agreement + Controller (as
;; IntelliJ does) instead of flagging them whole. Only applies to words that
;; would otherwise be marked as misspelled.
(setq spell-fu-word-delimit-camel-case t)

;; TECH WORDS
;; dict/tech.txt holds ~40k programming words English lacks (rect, rgba, async,
;; kotlin, stdout, postgres...), built by scripts/dict.sh from cspell's
;; dictionaries. Load it in every spell-checked buffer, next to English and the
;; personal dictionary. It's read-only, so zg / "Add to dictionary" still go to
;; the personal dictionary without asking which one.
(defvar +my/spell-tech-words-file (expand-file-name "dict/tech.txt" doom-user-dir))

(defvar +my/spell-tech-dictionary nil)

;; ====== CODE ======

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

(add-hook! 'spell-fu-mode-hook
  (defun +my/spell-add-tech-words-h ()
    (when (file-exists-p +my/spell-tech-words-file)
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
