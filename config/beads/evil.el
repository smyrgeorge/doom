;;; $DOOMDIR/config/beads/evil.el -*- lexical-binding: t; -*-
;; beads.el's keys over Vim's. Loaded from config/beads.el.

;; EVIL
;; beads.el's buffers are run with single letters (e edit, a assign, f filter,
;; s sort, P preview...), most of them Vim's in normal state: theirs win there
;; (Vim's where they bind nothing: j / k, gg, gt...). Refreshing is gr, as in
;; Doom's other lists: g stays Vim's prefix. beads.el does it for three of
;; them (the list, an issue, its dependencies), making their whole keymaps
;; Vim's, inherited keys too (SPC scrolling, Doom's leader); here each
;; buffer's own keys only, the same way in all. Its forms start in Emacs's
;; state (beads.el's): TAB next field, C-c C-c save, C-c C-k cancel.
(defconst +my/beads--maps
  '((beads-list . beads-list-mode-map)
    (beads-detail . beads-detail-mode-map)
    (beads-detail . beads-detail-vui-mode-map)
    (beads-hierarchy . beads-hierarchy-mode-map)
    (beads-stale . beads-stale-mode-map)
    (beads-orphans . beads-orphans-mode-map)
    (beads-lint . beads-lint-mode-map)
    (beads-duplicates . beads-duplicates-mode-map)
    (beads-types . beads-types-mode-map)
    (beads-transient . beads-create-preview-mode-map))
  "(FEATURE . KEYMAP): beads.el's buffers' keys, KEYMAP once FEATURE is loaded.")

(defun +my/beads-evil-keys (map)
  "MAP's own keys over Vim's in normal state; its g (refresh) on gr (see
above). Its own only: not those it inherits (tabulated-list's, special-mode's:
SPC scrolling there, where it's Doom's leader; h, digits...). Nor ESC, the
prefix of its Meta keys: Vim's Escape."
  ;; Not beads.el's whole keymap (see above).
  (define-key map [override-state] nil)
  (map-keymap-internal
   (lambda (event binding)
     (cond ((memq event '(?\e override-state)))
           ((eq event ?g)
            (when (commandp binding)
              ;; Off g altogether: bound there, Vim's gg and gt went too.
              (define-key map "g" nil)
              (evil-define-key* 'normal map "gr" binding)))
           (binding
            (evil-define-key* 'normal map (vector event) binding))))
   map))

(pcase-dolist (`(,feature . ,map) +my/beads--maps)
  (with-eval-after-load feature
    (when (and (boundp map) (keymapp (symbol-value map)))
      (+my/beads-evil-keys (symbol-value map)))))
