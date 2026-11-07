;;; $DOOMDIR/config/merge.el -*- lexical-binding: t; -*-
;; Resolving merge conflicts in three panes. Loaded from config.el; its code is
;; in config/merge/.

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

;; In config/merge/, in this order: each part can use what the ones before it
;; define.
(load! "merge/core")
(load! "merge/git")
(load! "merge/changes")
(load! "merge/panes")
(load! "merge/align")
(load! "merge/bar")
(load! "merge/session")
(load! "merge/commands")
(load! "merge/theme")
