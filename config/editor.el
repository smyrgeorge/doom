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

;; SMOOTH SCROLL
;; Doom's smooth-scroll module (ultra-scroll) scrolls by the pixels each wheel
;; event reports, all at once: right for a trackpad's stream of small steps,
;; but a mouse wheel reports a few lines per notch (51 px here), so it still
;; moved in jumps. Bigger steps now glide, fast at first and slowing down
;; (ease-out); notches in quick succession add to what's left, without a
;; restart. A frame per refresh of the display (60 Hz), each covering a share
;; of what's left that depends on the time since the last one: a late frame
;; catches up instead of slowing the glide down.
(defvar +my/smooth-scroll-min-step 20
  "Wheel steps bigger than this many pixels glide; smaller ones (trackpads) don't.")

(defvar +my/smooth-scroll-frame (/ 1.0 60)
  "Seconds between the frames of a glide: the display's refresh (60 Hz).")

(defvar +my/smooth-scroll-time-constant 0.05
  "Seconds in which a glide covers ~63% of what's left; it ends after about
three times this.")

(after! ultra-scroll
  ;; Doom's module pauses hl-todo during scrolls (`ultra-scroll-hide-functions'),
  ;; so TODO/NOTE/FIXME lost their highlight while scrolling and got it back
  ;; when it stopped: they flickered. Keep them on.
  (remove-hook 'ultra-scroll-hide-functions #'hl-todo-mode)

  ;; Doom also has it freeze the mode line during scrolls, by pushing onto
  ;; `mode-line-format'. In a buffer whose mode line is a string (Doom's popups,
  ;; e.g. *Messages*) that made it an invalid list: evil, which updates the mode
  ;; line on every state change, then failed, so Esc couldn't close the popup;
  ;; and its cleanup timer failed when the window was gone. Leave it alone.
  (setq ultra-scroll-throttle-mode-line nil))

;; EVIL
;; Saving a buffer returns to normal state.
(add-hook! 'after-save-hook #'evil-normal-state)

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

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

;; ====== CODE ======

;; In config/editor/, in this order: each part can use what the ones before it
;; define.
(load! "editor/margin")
(load! "editor/wrapped")
(load! "editor/fontify")
(load! "editor/smooth")
