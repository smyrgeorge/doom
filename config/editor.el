;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; General editing helpers. Loaded from config.el.

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; ====== CODE ======

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)

;; RAINBOW BRACKETS
;; Color (), [] and {} by nesting depth in code, like IntelliJ's Rainbow
;; Brackets plugin, so matching pairs are easy to spot.
(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))
