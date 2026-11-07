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
