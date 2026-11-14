;;; $DOOMDIR/config/git.el -*- lexical-binding: t; -*-
;; Git: Magit's additions (the commit graph like tig, git-delta diffs, TODOs in
;; the status buffer) and SPC g d (the current file's diff in a pane).
;; Loaded from config.el; its code is in config/git/.

;; ====== VARIABLES ======

;; COMMIT GRAPH
;; Commits are shown as a tree, like tig: in the log (l l) and in the status
;; buffer's commit sections (SPC g g: open, 20 commits), each branch's lane in
;; its own colour, drawn with box-drawing lines instead of ASCII (`*' `|' `/'
;; `\'). The log has the date and author in the margin; the status buffer
;; doesn't: a margin takes its width from the whole window, and its diffs and
;; headers were cut where it starts (L L there shows it, for that buffer).
(defvar +my/magit-graph-glyphs
  '((?* . "●") (?| . "│") (?/ . "╱") (?\\ . "╲") (?- . "─"))
  "How the characters of git's graph are drawn.")

;; THE MARGIN IN A NARROW PANE
;; The margin (the log's date and author: 36 columns) is hidden where it would
;; leave fewer columns of text than this, and shown again once the pane is
;; wide enough (config/git/magit.el). L L still hides or shows it.
(defvar +my/magit-margin-min-text 40
  "The fewest columns of text a magit buffer's margin may leave its window.")

(after! magit-log
  (put 'magit-log-mode 'magit-log-default-arguments
       '("--graph" "--color" "-n256" "--decorate"))
  (setq magit-log-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width t 18)))

(after! magit-status
  ;; The status buffer's commit sections (recent, unpushed, unpulled): open
  ;; (magit folds "Recent commits"), with more of them.
  (put 'magit-status-mode 'magit-log-default-arguments
       '("--graph" "--color" "-n256" "--decorate"))
  ;; No margin (see above); its look, when L L shows it, the log's.
  (setq magit-status-margin '(nil "%Y-%m-%d %H:%M " magit-log-margin-width t 18)
        magit-log-section-commit-count 20)
  (add-to-list 'magit-section-initial-visibility-alist '(recent . show))
  (add-to-list 'magit-section-initial-visibility-alist '(unpushed . show)))

;; A diff's --stat summary (SPC g d's) as wide as its window, not git's 80
;; columns cut at a narrow pane's edge; fitted again on each refresh (a save,
;; g).
(after! magit-diff
  (setq magit-diff-extra-stat-arguments #'magit-diff-use-window-width-as-stat-width))

;; ====== KEY BINDINGS ======

;; SPC g d: the current file's diff in a pane (config/git/diff-pane.el).
(map! :leader :desc "Diff file (side pane)" "g d" #'+my/git-diff-pane)

;; Esc closes the pane too (like q).
(map! :after magit-diff
      :map magit-diff-mode-map
      :n [escape] #'+my/git-diff-pane-escape)

;; ====== CODE ======

(load! "git/magit")                     ; delta, TODOs, the graph drawn
(load! "git/diff-pane")                 ; SPC g d
