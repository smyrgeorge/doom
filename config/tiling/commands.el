;;; $DOOMDIR/config/tiling/commands.el -*- lexical-binding: t; -*-
;; SPC w SPC, SPC w a, SPC w RET, resizing (SPC w ] / [) and the strategy
;; chosen (SPC w e, SPC w TAB). Loaded from config/tiling.el.

(defvar +my/focus-new-windows)          ; config/window.el

;; COMMANDS (see config/tiling.el)
(defun +my/tiling-split ()
  "SPC w SPC: a new pane where the tiling strategy puts it (config/tiling.el)."
  (interactive)
  (let* ((strategy (+my/tiling--strategy))
         (panes (+my/tiling--ready-panes))
         (from (selected-window)))
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
  "SPC w a: lay the panes out as the tiling strategy does (config/tiling.el)."
  (interactive)
  (let* ((strategy (+my/tiling--strategy))
         (panes (+my/tiling--ready-panes)))
    (unless (memq (selected-window) panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (when (cdr panes)
      (funcall (plist-get strategy :arrange) panes))))

(defun +my/tiling-swap-main ()
  "SPC w RET: the selected pane's buffer to the main pane (the strategy's,
first in `+my/tiling--ordered-panes'), the main's to where it was; the focus
to the main pane. From the main pane: the next pane's buffer to it
\(config/tiling.el). Tabs, point and history move with each; the panes'
sizes stay. A strategy of its own (fullscreen's :swap-main): it says what it
did."
  (interactive)
  (let* ((swap (plist-get (+my/tiling--strategy) :swap-main))
         (panes (+my/tiling--ready-panes))
         (from (selected-window)))
    (unless (memq from panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (if swap
        (message "%s" (funcall swap))
      (unless (cdr panes)
        (user-error "Only one pane"))
      (let* ((main (car panes))
             (other (if (eq from main) (cadr panes) from))
             (main-state (+my/tiling--state main))
             (other-state (+my/tiling--state other)))
        (+my/tiling--restore main other-state)
        (+my/tiling--restore other main-state)
        (select-window main)
        main))))

(defvar +my/tiling-resize-map
  (let ((map (make-sparse-keymap)))
    (define-key map "]" #'+my/tiling-main-bigger)
    (define-key map "[" #'+my/tiling-main-smaller)
    (define-key map "}" #'+my/tiling-pane-bigger)
    (define-key map "{" #'+my/tiling-pane-smaller)
    map)
  "After a resize (SPC w ] / [, the main area; } / {, the current pane): any
of them again (see config/tiling.el).")

;; RESIZING: each strategy says what it is (see `+my/tiling-strategies'): the
;; main area bigger in tall is its width, in another its height; the current
;; pane's size within the others. These only check the panes, ask it, and
;; say what it did.
(defun +my/tiling--resize (key what direction keys)
  "Resize by the strategy's KEY (:resize-main or :resize-pane), WHAT it
resizes (said if it has nothing so), in DIRECTION (1 bigger, -1 smaller);
then KEYS repeat it, and what the strategy did is said."
  (let* ((resize (plist-get (+my/tiling--strategy) key))
         (panes (and resize (+my/tiling--ready-panes)))
         (pane (selected-window)))
    (unless resize
      (user-error "The tiling strategy `%s' has no %s to resize" +my/tiling-strategy what))
    (unless (memq pane panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (unless (cdr panes)
      (user-error "Only one pane"))
    (let ((said (if (eq key :resize-pane)
                    (funcall resize panes pane direction)
                  (funcall resize panes direction))))
      (set-transient-map +my/tiling-resize-map t)
      (message "%s (%s again)" said keys))))

(defun +my/tiling-resize-main (direction)
  "The main area bigger (DIRECTION 1) or smaller (-1), as the strategy has
it (tall: the main pane's width)."
  (+my/tiling--resize :resize-main "main area" direction "] / ["))

(defun +my/tiling-resize-pane (direction)
  "The current pane bigger (DIRECTION 1) or smaller (-1) within the others,
as the strategy has it."
  (+my/tiling--resize :resize-pane "pane" direction "} / {"))

(defun +my/tiling-main-bigger ()
  "SPC w ]: the main area bigger, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-main 1))

(defun +my/tiling-main-smaller ()
  "SPC w [: the main area smaller, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-main -1))

(defun +my/tiling-pane-bigger ()
  "The current pane bigger, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-pane 1))

(defun +my/tiling-pane-smaller ()
  "The current pane smaller, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-pane -1))

;; THE STRATEGY CHOSEN (SPC w e) OR ROTATED (SPC w TAB / S-TAB)
;; For the session (config.el's is the one at startup). The selected frame's
;; panes, the current workspace's, are laid out its way at once, as SPC w a
;; does: from fullscreen its hidden panes shown again (as many as it has room
;; for), to fullscreen the others hidden, the current one in front. From a
;; side panel, as from the pane used last, the focus staying there. Another
;; workspace's hidden panes come back at its next SPC w a or SPC w SPC.

(defun +my/tiling--lay-out ()
  "The selected frame's panes laid out as the strategy does (SPC w a), from a
pane or from a side panel (as from the pane used last, the focus kept
there). What to say besides, or nil: hidden panes left for want of room, no
room for the panes (nothing changed)."
  (let* ((from (selected-window))
         ;; config/tiling/apps.el's.
         (pane (if (memq from (+my/tiling--panes)) from (+my/tiling--last-pane))))
    (when (and pane (not (eq pane from)))
      (select-window pane 'norecord))
    (unwind-protect
        (condition-case err
            (let ((strategy (+my/tiling--strategy))
                  (panes (+my/tiling--ready-panes)))
              (when (cdr panes)
                (funcall (plist-get strategy :arrange) panes))
              (unless (plist-get strategy :hides)
                (when-let* ((hidden (remq :shown (+my/tiling--slots))))
                  (format "No room to show %d hidden pane%s"
                          (length hidden) (if (cdr hidden) "s" "")))))
          (user-error (error-message-string err)))
      (when (and (not (eq pane from)) (window-live-p from))
        (select-window from 'norecord)))))

(defun +my/tiling--set-strategy (name &optional keys)
  "NAME, one of `+my/tiling-strategies', the strategy (for the session), the
panes laid out its way (see above). What to say: its name, its place among
them (KEYS repeating it, if given), what laying out had to say."
  (unless (assq name +my/tiling-strategies)
    (user-error "No tiling strategy `%s' (see `+my/tiling-strategies')" name))
  (setq +my/tiling-strategy name)
  (let ((note (+my/tiling--lay-out)))
    (concat (format "Tiling: %s (%d/%d%s)" name
                    (1+ (seq-position (mapcar #'car +my/tiling-strategies) name))
                    (length +my/tiling-strategies)
                    (if keys (format "; %s again" keys) ""))
            (and note (concat ". " note)))))

(defun +my/tiling-choose-strategy (name)
  "SPC w e: the tiling strategy NAME, asked for among `+my/tiling-strategies'
\(the current one the default), for the session; the panes laid out its way
at once, said (config/tiling.el)."
  (interactive
   (let ((names (mapcar (lambda (strategy) (symbol-name (car strategy))) +my/tiling-strategies)))
     (list (intern (completing-read
                    (format-prompt "Tiling strategy" (symbol-name +my/tiling-strategy))
                    (lambda (string predicate action)
                      (if (eq action 'metadata)
                          '(metadata (display-sort-function . identity))
                        (complete-with-action action names string predicate)))
                    nil t nil nil (symbol-name +my/tiling-strategy))))))
  (message "%s" (+my/tiling--set-strategy name)))

(defun +my/tiling--rotate-strategy (direction)
  "The strategy after the current one in `+my/tiling-strategies' (DIRECTION
1) or before it (-1), wrapping; the panes laid out its way; TAB / S-TAB
then the next / previous one again (`+my/tiling-strategy-map'), said."
  (let* ((names (mapcar #'car +my/tiling-strategies))
         (index (seq-position names +my/tiling-strategy))
         (name (nth (mod (if index (+ index direction) (if (> direction 0) 0 -1)) (length names))
                    names))
         (said (+my/tiling--set-strategy name "TAB / S-TAB")))
    (set-transient-map +my/tiling-strategy-map t)
    (message "%s" said)))

(defun +my/tiling-next-strategy ()
  "SPC w TAB: the next tiling strategy, the panes laid out its way, said; TAB
again the one after, S-TAB the one before (config/tiling.el)."
  (interactive)
  (+my/tiling--rotate-strategy 1))

(defun +my/tiling-previous-strategy ()
  "SPC w S-TAB: the previous tiling strategy, the panes laid out its way,
said; S-TAB again the one before, TAB the one after (config/tiling.el)."
  (interactive)
  (+my/tiling--rotate-strategy -1))
