;;; $DOOMDIR/config/tiling.el -*- lexical-binding: t; -*-
;; Tiling, like a tiling window manager (Amethyst). Loaded from config.el; its
;; code is in config/tiling/.

;; ====== VARIABLES ======

;; TILING
;; SPC w SPC opens a new pane where the tiling strategy puts it, like a tiling
;; window manager does (Amethyst's layouts). The strategy is chosen in config.el
;; (`+my/tiling-strategy'). The usual splits (SPC w v, SPC w s...) don't
;; change: tiling only happens on these keys.
;;   SPC w SPC   a new pane where the strategy puts it, showing the current
;;               buffer (its only tab, as SPC w v), which takes focus
;;   SPC w a     arrange the panes as the strategy lays them out (e.g. after
;;               splits of your own)
;;   SPC w RET   the current pane's buffer to the main pane (the first one),
;;               the main's to where it was, the focus with it (Amethyst's
;;               swap with main); from the main pane, the next one's to it
;;   SPC w ] / [ the main area bigger / smaller, as the strategy has it (tall:
;;               the main pane's width, by `+my/tiling-resize-step' of it),
;;               from any pane; ] and [ again repeat it. Kept: SPC w a and new
;;               panes lay it out so (Amethyst's expand / shrink main)
;;   SPC w } / { the current pane bigger / smaller, as the strategy has it
;;               (tall: a pane of the stack taller / shorter, by
;;               `+my/tiling-resize-step' of the stack's height, the others of
;;               the stack at equal heights); } and { again repeat it, as do ]
;;               and [. Kept: SPC w a, new panes and a closed pane keep its
;;               height (one pane at a time: resizing another evens it out)
;; Panes are the frame's windows besides its side panels (treemacs, popups...),
;; in order: left to right, top to bottom.
;; A pane closed, however (SPC w d, q, its last tab...): the others laid out
;; again as the strategy has them (tall: the stack's panes at equal heights,
;; but one resized with SPC w } / {; Emacs gave the closed one's rows to its
;; neighbour).
;; TILING FIRST (config/tiling/apps.el)
;; - Applications (`+my/tiling-known-apps': Claude Code, the terminal, the
;;   Markdown preview, magit, drawings, issues, Agent UI's canvas, a page in
;;   WebKit; those chosen in config.el, `+my/tiling-apps') open in a new pane where the strategy
;;   puts it, whatever their own setting or Doom's popup rules say; one shown
;;   already, or a tab of a pane (a file over it): that pane. But from a
;;   command opening one in the window you're in (`+my/tiling-here-commands':
;;   Doom's SPC o T, a new terminal there): where it asks, as without tiling.
;;   Magit's status (SPC g g), and any magit buffer opened
;;   from outside magit (SPC g d's diff, a log from a file), open so; inside
;;   magit, a log or a diff from the status stays in its pane as magit has it,
;;   a commit or a stash (Doom: beside) opens in a new pane, its process log
;;   below as Doom has it.
;; - Applications then behave as any buffer: a file opened in their pane is a
;;   tab there, they keep theirs (shown again when its tab closes).
;; - Files open as a tab in the current pane, always: an application's too (a
;;   link in Claude Code, RET in magit or SPC g d's diff, SPC SPC there), one
;;   asked for in another window too, Doom's terminal's pane too. From a popup
;;   or a side panel (the sidebar, *Help*), in the pane used last (a new pane
;;   without one). Git's own (a commit message, the rebase todo: in .git/,
;;   edited for git) stay where git opens them.
;; - A pane closes with its last tab: its tab closed (config/editor/tabs.el)
;;   or its buffer killed (SPC b k, a terminal's shell ending), but the
;;   frame's last pane.
;; Without this file (config.el not loading it), each opens as it did: Claude
;; Code in the current window, the terminal as Doom's popup, the preview and
;; the diff on the right, a drawing for Claude on its shell's left.
;; Strategies:
;; - tall (Amethyst's Tall): the first pane is the main one, on the left
;;   (`+my/tiling-tall-ratio' of the width), the others stacked on the right at
;;   equal heights. The second pane opens on the right, the next ones at the
;;   bottom of the stack, from whichever pane. Panes laid out otherwise are
;;   arranged tall first.
;; More can be added to `+my/tiling-strategies'.
(defvar +my/tiling-strategy 'tall
  "How SPC w SPC places new panes: a strategy of `+my/tiling-strategies'.")

(defvar +my/tiling-tall-ratio 0.5
  "The main pane's share of the width in the tall strategy.")

(defvar +my/tiling-tall-ratio-limits '(0.2 . 0.8)
  "The smallest and biggest share of the width SPC w [ / ] give the main pane.")

(defvar +my/tiling-resize-step 0.05
  "The share SPC w ] / [ add to or take from the main area, and SPC w } / {
from the current pane (tall: of the width; of the stack's height).")

;; APPLICATIONS, by name (see TILING FIRST above). Which are is chosen in
;; config.el: (setq +my/tiling-apps 'all), every one of them (the default), or
;; a list of names, '(claude magit); M-x customize-variable +my/tiling-apps
;; ticks them. One left out opens as it would without tiling (the terminal as
;; Doom's popup...) and isn't one otherwise either (no tab kept under a file,
;; not added to the workspace). A name unknown: a warning at startup.
(defvar +my/tiling-known-apps
  '((claude agent-shell-mode)                       ; Claude Code (SPC o c, SPC o C)
    (terminal ghostel-mode)                         ; the terminal (SPC o t)
    (preview +md-preview-page-mode)                 ; the Markdown preview (SPC m p)
    (drawings +my/excalidraw-mode)                  ; drawings (Option+Enter, C-c C-d)
    (magit (magit-mode . +my/tiling-magit-new-pane-p)) ; magit (SPC g g, SPC g d...)
    (issues beads-list-mode                         ; issues (SPC o i, config/beads.el)
            (beads-detail-mode . +my/tiling-beads-issue-new-pane-p) ; an issue (RET there)
            (beads-detail-vui-mode . +my/tiling-beads-issue-new-pane-p))
    (agent-ui agent-ui-canvas-mode                  ; Agent UI's canvas (config/agent-ui.el)
              agent-ui-form-mode)                   ; a form of it, filled in (Fill in)
    (html +my/html-page-mode))                      ; a page in WebKit (config/html.el)
  "Every application tiling knows (see TILING FIRST above): (NAME MODE...),
each MODE a major mode (and the modes derived from it), whose buffers open in
a new pane; or (MODE . PREDICATE), MODE's buffers an application's, opening
in a new pane when PREDICATE, called in the buffer being shown, says so
\(else as they ask).")

(defcustom +my/tiling-apps 'all
  "The applications (see APPLICATIONS above): all, every one of
`+my/tiling-known-apps', or a list of their names. Chosen in config.el."
  :type `(choice (const :tag "All of them" all)
                 (set :tag "These" ,@(mapcar (lambda (app) (list 'const (car app))) +my/tiling-known-apps)))
  :group 'windows)

(defvar +my/tiling-here-commands '(+ghostel/here)
  "Commands opening an application in the window you're in (see TILING
FIRST above): what they show goes where they ask, not in a new pane.")

(defvar +my/tiling-strategies
  '((tall :split +my/tiling-tall-split :arrange +my/tiling-tall-arrange
          :resize-main +my/tiling-tall-resize-main :resize-pane +my/tiling-tall-resize-pane
          :closed +my/tiling-tall-closed))
  "Tiling strategies: (NAME :split FUNCTION :arrange FUNCTION [:resize-main
FUNCTION] [:resize-pane FUNCTION] [:closed FUNCTION]). Each takes the panes
in order (see above): :split opens a new pane and returns it, :arrange lays
the panes out, :closed lays out the panes left once one closed. Resizing, as
the strategy has it, also given a DIRECTION (1 bigger, -1 smaller), keeping
the size for SPC w a and new panes, and returning what to say (\"Main pane:
55% of the width\"): :resize-main the main area (tall: its width; a strategy
whose main pane is on top: its height); :resize-pane, also given the current
pane, that pane within the others. Without one: nothing to resize, said.")

;; ====== KEY BINDINGS ======

;; In Evil's window map: SPC w ... and C-w ...
(after! evil
  (map! :map evil-window-map
        :desc "New pane (tiling)"      "SPC" #'+my/tiling-split
        :desc "Arrange panes (tiling)" "a"   #'+my/tiling-arrange
        :desc "Swap with main (tiling)" "RET" #'+my/tiling-swap-main
        :desc "Main pane bigger (tiling)" "]" #'+my/tiling-main-bigger
        :desc "Main pane smaller (tiling)" "[" #'+my/tiling-main-smaller
        :desc "Pane bigger (tiling)"       "}" #'+my/tiling-pane-bigger
        :desc "Pane smaller (tiling)"      "{" #'+my/tiling-pane-smaller))

;; ====== CODE ======

;; In config/tiling/, in this order: each part can use what the ones before it
;; define.
(load! "tiling/panes")
(load! "tiling/tall")
(load! "tiling/commands")
(load! "tiling/apps")
