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
;; Panes are the frame's windows besides its side panels (treemacs, popups...),
;; in order: left to right, top to bottom.
;; TILING FIRST (config/tiling/apps.el)
;; - Applications (`+my/tiling-apps': Claude Code, the terminal, the Markdown
;;   preview, magit, drawings) open in a new pane where the strategy puts it,
;;   whatever their own setting or Doom's popup rules say; one shown already:
;;   its pane. Magit's status (SPC g g), and any magit buffer opened from
;;   outside magit (SPC g d's diff, a log from a file), open so; inside magit,
;;   a log or a diff from the status stays in its pane as magit has it, a
;;   commit or a stash (Doom: beside) opens in a new pane, its process log
;;   below as Doom has it.
;; - Files open as a tab in the current pane. From an application's pane, a
;;   popup or a side panel (a link in Claude Code, RET in magit, the sidebar,
;;   SPC SPC there), in the last pane of files instead (a new pane without
;;   one): applications' panes get no file tabs. Git's own (a commit message,
;;   the rebase todo: in .git/, edited for git) stay where git opens them.
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

(defvar +my/tiling-apps
  '(agent-shell-mode                    ; Claude Code (SPC o c, SPC o C)
    ghostel-mode                        ; the terminal (SPC o t)
    +md-preview-page-mode               ; the Markdown preview (SPC m p)
    +my/excalidraw-mode                 ; drawings (Option+Enter, C-c C-d)
    (magit-mode . +my/tiling-magit-new-pane-p)) ; magit (SPC g g, SPC g d...)
  "Applications (see TILING FIRST above): major modes (and the modes derived
from them), whose buffers open in a new pane; or (MODE . PREDICATE), MODE's
buffers an application's, opening in a new pane when PREDICATE, called in the
buffer being shown, says so (else as they ask).")

(defvar +my/tiling-strategies
  '((tall :split +my/tiling-tall-split :arrange +my/tiling-tall-arrange))
  "Tiling strategies: (NAME :split FUNCTION :arrange FUNCTION). Both take
the panes in order (see above): :split opens a new pane and returns it,
:arrange lays the panes out.")

;; ====== KEY BINDINGS ======

;; In Evil's window map: SPC w ... and C-w ...
(after! evil
  (map! :map evil-window-map
        :desc "New pane (tiling)"      "SPC" #'+my/tiling-split
        :desc "Arrange panes (tiling)" "a"   #'+my/tiling-arrange))

;; ====== CODE ======

;; In config/tiling/, in this order: each part can use what the ones before it
;; define.
(load! "tiling/panes")
(load! "tiling/tall")
(load! "tiling/commands")
(load! "tiling/apps")
