;;; $DOOMDIR/config/tiling/panes.el -*- lexical-binding: t; -*-
;; The panes, in order, and the strategy chosen.
;; Loaded from config/tiling.el.

(defun +my/tiling--strategy ()
  "The strategy chosen (see config/tiling.el)."
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

(defun +my/tiling--panes (&optional frame)
  "FRAME's (the selected frame's) panes: its windows besides side panels, in
order."
  (let (panes)
    (named-let walk ((window (window-main-window frame)))
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

;; A PANE CLOSED (see config/tiling.el)
(defun +my/tiling--closed-h (frame)
  "FRAME's panes fewer than when last seen (one closed, however): the others
laid out again by the strategy's :closed. Not a child frame's (notices, the
stripe), nor down to one pane."
  (unless (frame-parent frame)
    (let ((count (length (+my/tiling--panes frame)))
          (before (frame-parameter frame '+my/tiling-panes)))
      (set-frame-parameter frame '+my/tiling-panes count)
      (when (and before (< count before) (> count 1))
        (when-let* ((closed (plist-get (+my/tiling--strategy) :closed)))
          (with-selected-frame frame
            (funcall closed (+my/tiling--panes))))))))

(add-hook 'window-state-change-functions #'+my/tiling--closed-h)
