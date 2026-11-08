;;; $DOOMDIR/config/treemacs.el -*- lexical-binding: t; -*-
;; Treemacs project sidebar. Loaded from config.el; its code is in
;; config/treemacs/.

;; ====== VARIABLES ======

;; TREEMACS (project view)
(setq +treemacs-git-mode 'deferred)     ; async git status, incl. folders (python3)
(setq treemacs-hide-dot-git-directory nil) ; show .git (treemacs hides it)

;; Treemacs hides its window from winum; number it (leftmost => SPC w 1).
(after! (treemacs winum)
  (setq winum-ignored-buffers-regexp
        (remove (regexp-quote treemacs-buffer-name-prefix)
                winum-ignored-buffers-regexp)))

;; No mode line in the sidebar: it only said "Treemacs" and the workspace
;; ("Perspective pas-workspace").
(setq treemacs-user-mode-line-format 'none)

(after! treemacs
  (setq treemacs-is-never-other-window nil) ; reachable with SPC w w (Doom: t)
  (treemacs-follow-mode +1)             ; highlight the current file (Doom: off)
  (treemacs-project-follow-mode +1))    ; show the current buffer's project

;; Edits to files from outside Emacs (Claude Code, a terminal...) don't touch
;; .git, and macOS's file notifications don't report changes to a file's
;; contents: treemacs only caught up when Emacs lost and regained focus. So
;; while Emacs has focus and treemacs is shown, check each of its projects'
;; `git status' every few seconds, in the background, and refresh when it
;; changed. (--no-optional-locks: it never writes to .git, so no loop, and no
;; clash with a commit running at the same time.)
(defvar +my/treemacs-git-poll-interval 3
  "Seconds between checks of the shown projects' git status (nil: none).")

;; EXPAND / COLLAPSE ALL
;; `treemacs-expand-all' (zR in treemacs) opens every folder of the project(s)
;; in the sidebar; `treemacs-collapse-all' (zM) closes them all again but keeps
;; each project open at its top level (treemacs's
;; own `treemacs-collapse-all-projects' folds the projects down to their names).
(defvar +my/treemacs-expand-all-warn 300
  "Ask before `treemacs-expand-all' opens more than this many folders.")

;; ====== KEY BINDINGS ======

;; Arrows in trees: ← collapses (or goes to the parent), → expands
;; a closed node, or goes to the first child of an open one; on a file in the
;; project view it opens it, on an error in the error list (SPC c X) it jumps
;; there. ↑/↓ as k/j. (treemacs-evil binds h/l and j/k but leaves the arrows as
;; evil's line motions, which in lsp-treemacs' lists could stop on the hidden
;; first line; → was RET, which there didn't expand anything.)
(map! :after treemacs-evil
      :map evil-treemacs-state-map
      [left]  #'+my/treemacs-left
      [right] #'+my/treemacs-right
      [up]    #'treemacs-previous-line
      [down]  #'treemacs-next-line)

(map! :after treemacs-evil
      :map evil-treemacs-state-map
      "zR" #'treemacs-expand-all
      "zM" #'treemacs-collapse-all)

;; CLICKS
;; A click only goes to the clicked line: the sidebar gets the focus and the
;; node is selected (for Cmd+C, a key). A double click opens a file, or expands
;; / collapses a folder. (treemacs's own, on the press and the double click; the
;; click's release does nothing, where globally it moves point again, before
;; the icon.)
(after! treemacs
  (define-key treemacs-mode-map [down-mouse-1] #'treemacs-leftclick-action)
  (define-key treemacs-mode-map [mouse-1] #'ignore)
  (define-key treemacs-mode-map [double-mouse-1] #'treemacs-doubleclick-action))

;; COPY
;; Cmd+C (Linux: Ctrl+Shift+C) copies the selected file's (or folder's)
;; absolute path to the clipboard, as `ya' does (globally Cmd+C is
;; `evil-yank', which here would wait for a motion).
(after! treemacs
  (define-key treemacs-mode-map (kbd "s-c") #'treemacs-copy-absolute-path-at-point)
  (unless (+my/macos-p)
    (define-key treemacs-mode-map (kbd "C-S-c") #'treemacs-copy-absolute-path-at-point)))

;; ====== CODE ======

;; In config/treemacs/, in this order: each part can use what the ones before
;; it define.
(load! "treemacs/arrows")
(load! "treemacs/selection")
(load! "treemacs/follow")
(load! "treemacs/git")
(load! "treemacs/expand")
(load! "treemacs/menu")
