;;; $DOOMDIR/config/tiling.el -*- lexical-binding: t; -*-
;; Tiling, like a tiling window manager (Amethyst). Loaded from config.el.

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

(defvar +my/focus-new-windows)          ; config/window.el

(defun +my/tiling--strategy ()
  "The strategy chosen (see above)."
  (or (alist-get +my/tiling-strategy +my/tiling-strategies)
      (user-error "No tiling strategy `%s' (see `+my/tiling-strategies')"
                  +my/tiling-strategy)))

(defun +my/tiling--children (window)
  "WINDOW's child windows, in order."
  (let ((child (window-child window))
        children)
    (while child
      (push child children)
      (setq child (window-next-sibling child)))
    (nreverse children)))

(defun +my/tiling--panes ()
  "The selected frame's panes: its windows besides side panels, in order."
  (let (panes)
    (named-let walk ((window (window-main-window)))
      (if (window-live-p window)
          (push window panes)
        (mapc #'walk (+my/tiling--children window))))
    (nreverse panes)))

(defun +my/tiling--state (window)
  "What WINDOW shows, to show it again in another window."
  (list :buffer (window-buffer window)
        :point (window-point window)
        :start (window-start window)
        :hscroll (window-hscroll window)
        :prev (window-prev-buffers window)
        :next (window-next-buffers window)
        :tabs (window-parameter window 'tab-line-buffers)
        :dedicated (window-dedicated-p window)))

(defun +my/tiling--restore (window state)
  "Show STATE (`+my/tiling--state') in WINDOW, its tabs included."
  (set-window-dedicated-p window nil)
  (set-window-buffer window (plist-get state :buffer))
  (set-window-start window (plist-get state :start) t)
  (set-window-point window (plist-get state :point))
  (set-window-hscroll window (plist-get state :hscroll))
  (set-window-prev-buffers window (plist-get state :prev))
  (set-window-next-buffers window (plist-get state :next))
  (set-window-parameter window 'tab-line-buffers (plist-get state :tabs))
  (set-window-dedicated-p window (plist-get state :dedicated)))

;; TALL
(defun +my/tiling--tall-p (root)
  "Non-nil if the panes under ROOT are laid out tall: one pane, or a pane on
the left of one column of panes."
  (or (window-live-p root)
      (let* ((main (window-left-child root)) ; side by side
             (stack (and main (window-next-sibling main))))
        (and (window-live-p main)
             stack
             (null (window-next-sibling stack))
             (or (window-live-p stack)
                 (and (window-top-child stack) ; one above the other
                      (seq-every-p #'window-live-p (+my/tiling--children stack))))))))

(defun +my/tiling--main-width (window)
  "The columns the main pane gets of WINDOW's (see `+my/tiling-tall-ratio')."
  (round (* +my/tiling-tall-ratio (window-total-width window))))

(defun +my/tiling-tall-arrange (panes)
  "Lay PANES out tall: the first one on the left, the others stacked on the
right at equal heights; each shows what it showed, the selected one stays so."
  (let* ((states (mapcar #'+my/tiling--state (cdr panes)))
         (index (seq-position panes (selected-window)))
         (main (car panes))
         (new (list main)))
    (dolist (pane (cdr panes))
      (delete-window pane))
    (when states
      (let ((pane (split-window main (+my/tiling--main-width main) 'right)))
        (push pane new)
        (dotimes (_ (1- (length states)))
          (setq pane (split-window pane nil 'below))
          (push pane new))
        (when (window-parent pane)
          (balance-windows (window-parent pane)))))
    (setq new (nreverse new))
    (cl-mapc #'+my/tiling--restore (cdr new) states)
    (select-window (nth (or index 0) new))))

(defun +my/tiling-tall-split (panes)
  "Open a pane, tall (see above): on the right of the only one, else at the
bottom of the stack; PANES arranged tall first if need be. Return it."
  (unless (+my/tiling--tall-p (window-main-window))
    (+my/tiling-tall-arrange panes))
  (let ((root (window-main-window)))
    (if (window-live-p root)
        (split-window root (+my/tiling--main-width root) 'right)
      (let* ((stack (window-next-sibling (window-left-child root)))
             (bottom (if (window-live-p stack)
                         stack
                       (car (last (+my/tiling--children stack)))))
             (new (split-window bottom nil 'below)))
        (balance-windows (window-parent new))
        new))))

;; COMMANDS (see above)
(defun +my/tiling-split ()
  "SPC w SPC: a new pane where the tiling strategy puts it (see above)."
  (interactive)
  (let ((from (selected-window))
        (panes (+my/tiling--panes))
        (strategy (+my/tiling--strategy)))
    (unless (memq from panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (let ((buffer (window-buffer from))
          (point (window-point from))
          (start (window-start from))
          (new (funcall (plist-get strategy :split) panes)))
      ;; The current buffer, its only tab (it showed another first).
      (set-window-buffer new buffer)
      (set-window-start new start t)
      (set-window-point new point)
      (set-window-prev-buffers new nil)
      (set-window-next-buffers new nil)
      (set-window-parameter new 'tab-line-buffers nil)
      ;; New panes take focus (config/window.el).
      (when (or (not (boundp '+my/focus-new-windows)) +my/focus-new-windows)
        (select-window new))
      new)))

(defun +my/tiling-arrange ()
  "SPC w a: lay the panes out as the tiling strategy does (see above)."
  (interactive)
  (let ((panes (+my/tiling--panes))
        (strategy (+my/tiling--strategy)))
    (unless (memq (selected-window) panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (when (cdr panes)
      (funcall (plist-get strategy :arrange) panes))))
