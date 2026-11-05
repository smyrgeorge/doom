;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; General editing helpers. Loaded from config.el.

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)
(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)
