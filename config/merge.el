;;; $DOOMDIR/config/merge.el -*- lexical-binding: t; -*-
;; Resolving merge conflicts in three panes. Loaded from config.el; loads its
;; parts (config/merge/) below.

;; ====== VARIABLES ======

;; RESOLVING CONFLICTS
;; e on a conflicted file in Magit (its status: Unmerged) opens it in three
;; panes, under a bar: Yours (your side: the branch you're on in a merge or a
;; cherry-pick, what you're rebasing onto in a rebase), the Result (the file
;; as it'll be saved, starting from the version both sides came from), Theirs
;; (the branch merged, the commit being rebased or cherry-picked, the stash).
;; Each change of a side is highlighted (changed lines blue, added green,
;; removed grey, conflicts red: both sides changed them), with buttons in its
;; pane's margin, by the Result:
;;   >> / <<   put the change in the Result. In a conflict whose other side is
;;             in already, add it after that one (keep both).
;;   x         ignore the change (the Result keeps what it has there).
;; A change is done when each side that changed is in or ignored; it then
;; turns grey. The words that changed are highlighted too (smerge's).
;; A conflict whose sides changed different words gets a ✨ wand in the
;; Result's margin: it merges them, word by word (see THE WAND, merge/changes.el).
;; The bar, across the top:
;;   Accept Left / Accept Right   Yours / Theirs for every change not done yet
;;   ✨ Apply non-conflicting      every change only one side made (or both
;;                                the same), not done yet
;;   N changes left, M conflicts
;;   Done    save the file, and stage it (git add) if no change is left; with
;;           some left, ask first, and save them as conflict markers, unstaged
;;   Abort   close, the file left as it was
;; The panes line up: each change takes as many rows in each, the shorter
;; padded with grey filler lines (not text: not saved, not copied, the cursor
;; skips them); and they scroll together (the wheel, the trackpad, the keys,
;; smooth scrolling's glides; sideways too).
;; The Result can be edited as any file; u undoes the buttons too (and C-r
;; redoes them). Keys in the panes: ]c / [c next / previous change; SPC m l /
;; SPC m r the change at point from Yours / Theirs, SPC m x ignore it, SPC m w
;; the wand, SPC m L
;; / SPC m R accept left / right, SPC m a apply non-conflicting; C-c C-c (or
;; Cmd+S) done, C-c C-k abort.
;; The three versions are Git's, from its index (stages :1: the base, :2:
;; yours, :3: theirs): merges, rebases, cherry-picks, reverts and stashes
;; alike. Ediff finds the changes (its diff3 parser, comparing the three: it
;; says which side changed each region, or both), without its windows. Binary files, files added on
;; both sides or deleted on one, submodules and links open in Magit's usual
;; Ediff instead (each version isn't a text with a common base).
;; M-x +my/merge-all resolves each conflicted file of the repository, one
;; after the other; from the shell, cmd/diff.sh does (in this terminal, see
;; docs/cmd.md).
(defvar +my/merge-refine-max-lines 200
  "Changes longer than this (lines) on a side aren't refined word by word.")

(defvar +my/merge-refine-max-changes 100
  "Files with more changes than this aren't refined word by word.")

(defface +my/merge-changed '((t :inherit diff-changed :extend t))
  "A side's change of lines (blue, see `+my/merge-faces-h').")

(defface +my/merge-added '((t :inherit diff-added :extend t))
  "A side's added lines (green).")

(defface +my/merge-removed '((t :inherit shadow :extend t))
  "Where a side removed lines (grey).")

(defface +my/merge-conflict '((t :inherit diff-removed :extend t))
  "A conflict: both sides changed the lines, differently (red).")

(defface +my/merge-done '((t :inherit shadow))
  "A side's change once done (in the Result, or ignored).")

(defface +my/merge-filler '((t :inherit fringe :extend t))
  "The filler lines that line the panes up (see `+my/merge-faces-h').")

(defface +my/merge-refined '((t :inherit smerge-refined-changed))
  "The words a change changed.")

(defface +my/merge-button '((t :inherit (bold link) :underline nil))
  "The buttons in the margins and the bar.")

(defface +my/merge-mark '((t :inherit link :underline nil))
  "A ▶ in the Result's fringe where a change with nothing there goes (a side's
added lines): the accent's colour, not the change's tint (a blur there).")

(defface +my/merge-mark-conflict '((t :inherit error))
  "The same, for a conflict.")

(defvar +my/merge-finished-functions nil
  "Functions called with a merge's session once it's closed (done, aborted,
a pane closed).")

(defvar +my/merge-mode-map (make-sparse-keymap)
  "Keys in the three panes (see `+my/merge-mode').")

;; ====== KEY BINDINGS ======

(map! :map +my/merge-mode-map
      "C-c C-c" #'+my/merge-done
      "C-c C-k" #'+my/merge-abort
      "s-s"     #'+my/merge-done      ; the Result visits no file: Done saves it
      [left-margin mouse-1]  #'+my/merge-click
      [right-margin mouse-1] #'+my/merge-click
      [left-margin down-mouse-1]  #'ignore
      [right-margin down-mouse-1] #'ignore
      :nm "]c" #'+my/merge-next
      :nm "[c" #'+my/merge-previous)

(map! :map +my/merge-mode-map
      :localleader
      :desc "Change at point from Yours"  "l" #'+my/merge-take-left
      :desc "Change at point from Theirs" "r" #'+my/merge-take-right
      :desc "Ignore change at point"      "x" #'+my/merge-ignore
      :desc "Merge the words (wand)"      "w" #'+my/merge-wand
      :desc "Accept Left"                 "L" #'+my/merge-accept-left
      :desc "Accept Right"                "R" #'+my/merge-accept-right
      :desc "Apply non-conflicting"       "a" #'+my/merge-apply-non-conflicting
      :desc "Done"                        "d" #'+my/merge-done
      :desc "Abort"                       "q" #'+my/merge-abort)

;; e in Magit, on a conflicted file.
(after! magit-ediff
  (setq magit-ediff-dwim-resolve-function #'+my/merge))

;; ====== CODE ======

(cl-defstruct (+my/merge (:constructor +my/merge--make) (:copier nil))
  "A file being resolved."
  path toplevel coding labels frame
  yours base theirs result bar          ; buffers
  chunks                                ; vector of `+my/merge-chunk'
  winconf finished)

(cl-defstruct (+my/merge-chunk (:constructor +my/merge-chunk--make) (:copier nil))
  "A change (a region where a side differs from the base)."
  index
  kind                                  ; conflict, yours, theirs, same
  yours theirs result                   ; overlays in those buffers
  base                                  ; the base's text there
  yours-state theirs-state              ; nil, applied, ignored, merged
  wand                                  ; the sides' words merged, if they can be
  order                                 ; the sides applied, first first
  buttons)                              ; overlays of its margin buttons

(defvar-local +my/merge--session nil
  "The merge the buffer is part of (all its panes and the bar).")

(defvar +my/merge--aligning nil
  "Non-nil while fillers are made (not changes to line up after, see LINING
UP in config/merge/align.el).")

(define-minor-mode +my/merge-mode
  "A pane of a merge (see config/merge.el).

\\{+my/merge-mode-map}"
  :keymap +my/merge-mode-map
  (if +my/merge-mode
      (setq-local hl-line-range-function #'+my/merge--hl-line-range)
    (kill-local-variable 'hl-line-range-function)))

(defun +my/merge--hl-line-range ()
  "The current line's highlight (hl-line's range) in a pane: none on a
change's coloured lines. Doom's current line (`global-hl-line-sticky-flag'
window) shows in every window, above the changes' colours (its overlay's
priority is the selection's, which they stay under): the first change, where
each pane's point starts, looked like no change."
  (let ((start (line-beginning-position))
        (end (line-beginning-position 2)))
    (if (seq-some (lambda (ov) (and (memq (overlay-get ov 'face)
                                          '(+my/merge-changed +my/merge-added
                                            +my/merge-removed +my/merge-conflict))
                                    (< (overlay-start ov) (overlay-end ov))))
                  (overlays-in start end))
        (cons start start)
      (cons start end))))

;; THE PARTS, in order: each can use what the ones before it define.
(load! "merge/git")
(load! "merge/changes")
(load! "merge/panes")
(load! "merge/align")
(load! "merge/bar")
(load! "merge/session")
(load! "merge/commands")

;; THEME
;; The changes tinted with the theme's colours: the colour
;; blended into the theme's background, where colours are true (the GUI, a
;; terminal with 24-bit colour). With 256 colours a blend comes out as the
;; palette's nearest (teal, salmon): the palette's darkest tint of the colour
;; instead (a light theme's: lightest). With fewer, the faces they inherit.
;; The theme's colours, not a frame's: the GUI's server makes terminal frames
;; too, and a daemon's first frame has none.
(defconst +my/merge--tints
  '((+my/merge-changed  blue  0.25 "#00005f" "#d7d7ff")
    (+my/merge-added    green 0.25 "#005f00" "#d7ffd7")
    (+my/merge-removed  base5 0.35 "#3a3a3a" "#d0d0d0")
    (+my/merge-conflict red   0.25 "#5f0000" "#ffd7d7")
    (+my/merge-filler   base5 0.12 "#1c1c1c" "#e4e4e4"))
  "(FACE THEME-COLOUR AMOUNT DARK-256 LIGHT-256): see above.")

(defun +my/merge-faces-h ()
  "The changes tinted with the theme's colours (see above)."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (doom-color 'bg)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (let ((dark (color-dark-p (color-name-to-rgb bg))))
          (pcase-dolist (`(,face ,colour ,amount ,dark-256 ,light-256) +my/merge--tints)
            (when-let* ((tint (doom-color colour))
                        ((stringp tint))
                        ((string-prefix-p "#" tint)))
              (face-spec-set
               ;; Not inheriting diff-mode's faces then: their foregrounds
               ;; would hide the code's colours.
               face `((((min-colors 257)) :inherit nil :background ,(doom-blend tint bg amount))
                      (((min-colors 256)) :inherit nil :background ,(if dark dark-256 light-256))
                      (t))))))))))

(+my/merge-faces-h)
(add-hook 'doom-load-theme-hook #'+my/merge-faces-h)
