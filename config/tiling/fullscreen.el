;;; $DOOMDIR/config/tiling/fullscreen.el -*- lexical-binding: t; -*-
;; The fullscreen strategy: the current pane alone, the others hidden.
;; Loaded from config/tiling.el.

;; FULLSCREEN
;; Every pane fills the frame, one in front: Emacs's windows can't overlap, so
;; the pane on the screen is the frame's only window and the others are
;; hidden, in order (config/tiling/hidden.el). A new pane opens alone, just
;; after the current one; SPC w w / SPC w W bring the next / previous one to
;; the front, in turn, saying which ("Pane 2/4"). An application already in a
;; hidden pane: that pane brought to the front. SPC w RET makes the pane on
;; the screen the first, the main one
;; another strategy lays out so. Nothing to resize. Closing it shows the next
;; one. Another strategy chosen: its SPC w a (SPC w SPC...) shows them all
;; again, laid out its way.

(defun +my/tiling-fullscreen-arrange (panes)
  "PANES (the main one first) laid out fullscreen: the selected one alone (else
the first), the others hidden in order, where the pane on the screen was
among those hidden already."
  (when (cdr panes)
    (let* ((shown (if (memq (selected-window) panes) (selected-window) (car panes)))
           (here (mapcar (lambda (pane) (if (eq pane shown) :shown (+my/tiling--state pane))) panes))
           (slots (or (+my/tiling--slots) (list :shown))))
      (dolist (pane panes)
        (unless (eq pane shown)
          (delete-window pane)))
      (+my/tiling--set-slots (mapcan (lambda (slot) (if (eq slot :shown) (copy-sequence here) (list slot)))
                                     slots))
      (select-window shown))))

(defun +my/tiling-fullscreen-split (panes)
  "A new pane, fullscreen: the pane on the screen hidden, just before the new
one, shown alone in its window (PANES laid out fullscreen first). Return that
window."
  (when (cdr panes)
    (+my/tiling-fullscreen-arrange panes))
  (let* ((window (car (+my/tiling--panes)))
         (slots (or (+my/tiling--slots) (list :shown)))
         (index (seq-position slots :shown)))
    (+my/tiling--set-slots (append (seq-take slots index)
                                   (list (+my/tiling--state window) :shown)
                                   (seq-drop slots (1+ index))))
    (message "Pane %d/%d" (+ 2 index) (1+ (length slots)))
    window))

(defun +my/tiling-fullscreen-swap-main ()
  "SPC w RET, fullscreen: the pane on the screen first, the main one (another
strategy lays it out so). What to say."
  (let ((panes (+my/tiling--ordered-panes)))
    (when (cdr panes)
      (+my/tiling-fullscreen-arrange panes)))
  (let ((slots (+my/tiling--slots)))
    (unless slots
      (user-error "Only one pane"))
    (+my/tiling--set-slots (cons :shown (remq :shown slots)))
    (format "Pane 1/%d, the main one" (length slots))))

(defun +my/tiling-fullscreen-show (buffer)
  "A hidden pane holding BUFFER (an application shown) brought to the front;
its window, or nil."
  (+my/tiling--show-holding buffer))

;; SPC w w / SPC w W
(defun +my/tiling--cycle (direction command)
  "Fullscreen with panes hidden: the next (DIRECTION 1) or previous (-1) one
in front, said. Else COMMAND (Evil's next / previous window), as it was."
  (if (and (plist-get (alist-get +my/tiling-strategy +my/tiling-strategies) :hides)
           (memq (selected-window) (+my/tiling--panes))
           (or (+my/tiling--hidden-p) (cdr (+my/tiling--panes))))
      (progn
        (when (cdr (+my/tiling--panes))
          (+my/tiling-fullscreen-arrange (+my/tiling--ordered-panes)))
        (if (+my/tiling--hidden-p)
            (message "%s" (+my/tiling--show-next direction))
          (message "Only one pane")))
    (call-interactively command)))

(defun +my/tiling-next-pane ()
  "SPC w w: the next pane in front (the fullscreen strategy, see above); else
Evil's next window."
  (interactive)
  (+my/tiling--cycle 1 #'evil-window-next))

(defun +my/tiling-previous-pane ()
  "SPC w W: the previous pane in front (the fullscreen strategy, see above);
else Evil's previous window."
  (interactive)
  (+my/tiling--cycle -1 #'evil-window-prev))
