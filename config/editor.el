;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; The editor. Loaded from config.el; its code is in config/editor/; getting
;; around is config/navigation.el.

;; ====== VARIABLES ======

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)

;; RAINBOW BRACKETS
;; Color (), [] and {} by nesting depth in code, so matching pairs are easy
;; to spot.
(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; ====== CODE ======

;; In config/editor/, in this order: each part can use what the ones before it
;; define.
(load! "editor/margin")
(load! "editor/wrapped")
(load! "editor/fontify")
