;;; $DOOMDIR/config/tiling/hidden.el -*- lexical-binding: t; -*-
;; Panes hidden (the fullscreen strategy's), kept in order, shown again.
;; Loaded from config/tiling.el.

;; HIDDEN PANES
;; A strategy that hides panes (:hides: fullscreen) keeps the frame's panes in
;; order, one on the screen, the others hidden: what each showed (its state:
;; buffer, point, tabs...) kept, the current workspace's (each of Doom's
;; workspaces has windows of its own). Its SLOTS: the hidden panes' states,
;; and :shown where the pane on the screen is among them. Another strategy
;; shows them again (SPC w SPC, SPC w a...), in order, before laying the panes
;; out. The pane on the screen closed (SPC w d, its last tab, its buffer
;; killed, q on an application): the next one shown in its window (the frame's
;; last can't be deleted). A buffer killed while hidden: its pane shows the one
;; it showed before, or is gone.

(defun +my/tiling--hidden-key ()
  "Whose hidden panes: the current workspace's (persp-mode's), else the
frame's."
  (if (and (bound-and-true-p persp-mode) (fboundp 'get-current-persp))
      (get-current-persp)
    'frame))

(defun +my/tiling--slots (&optional frame)
  "FRAME's slots (see above), the current workspace's; nil: none hidden."
  (alist-get (+my/tiling--hidden-key) (frame-parameter frame '+my/tiling-hidden)))

(defun +my/tiling--set-slots (slots &optional frame)
  "FRAME's slots (the current workspace's) SLOTS; none hidden: forgotten."
  (let ((all (frame-parameter frame '+my/tiling-hidden)))
    (setf (alist-get (+my/tiling--hidden-key) all nil 'remove)
          (and (seq-some #'consp slots) slots))
    (set-frame-parameter frame '+my/tiling-hidden all)))

(defun +my/tiling--hidden-p (&optional frame)
  "Non-nil if FRAME has panes hidden (the current workspace's)."
  (and (+my/tiling--slots frame) t))

(defun +my/tiling--shown-alone-p (window)
  "Non-nil if WINDOW is its frame's only pane while others are hidden: where
closing it shows the next one (see above)."
  (let ((frame (window-frame window)))
    (and (+my/tiling--hidden-p frame)
         (equal (+my/tiling--panes frame) (list window)))))

(defun +my/tiling--live-state (state)
  "STATE (`+my/tiling--state') as it can be shown again: its killed buffers
out; its buffer killed, the one it showed before instead; nil if none is
left."
  (let* ((prev (seq-filter (lambda (entry) (buffer-live-p (car entry))) (plist-get state :prev)))
         (state (append (list :prev prev
                              :next (seq-filter #'buffer-live-p (plist-get state :next))
                              :tabs (seq-filter #'buffer-live-p (plist-get state :tabs)))
                        state)))
    (cond ((buffer-live-p (plist-get state :buffer)) state)
          (prev (append (list :buffer (car (car prev)) :start (nth 1 (car prev))
                              :point (nth 2 (car prev)) :prev (cdr prev))
                        state)))))

(defun +my/tiling--live-slots (slots)
  "SLOTS, each hidden state as it can be shown again; those gone, out."
  (delq nil (mapcar (lambda (slot) (if (eq slot :shown) slot (+my/tiling--live-state slot))) slots)))

(defun +my/tiling--hidden-holds-p (buffer)
  "Non-nil if a hidden pane, any frame's or workspace's, shows BUFFER or has
it as a tab."
  (seq-some (lambda (frame)
              (seq-some (lambda (entry)
                          (seq-some (lambda (slot)
                                      (and (consp slot)
                                           (or (eq (plist-get slot :buffer) buffer)
                                               (assq buffer (plist-get slot :prev))
                                               (memq buffer (plist-get slot :tabs)))))
                                    (cdr entry)))
                        (frame-parameter frame '+my/tiling-hidden)))
            (frame-list)))

;; Closing a file's last tab (config/editor/tabs.el) closes it unless a
;; window holds it: a hidden pane does too.
(add-hook '+my/tabs-held-functions #'+my/tiling--hidden-holds-p)

;; SHOWN AGAIN
(defun +my/tiling--new-window ()
  "A window for a pane shown again: the biggest pane split along its longer
side (in pixels); nil if there's no room."
  (let ((biggest (car (sort (+my/tiling--panes)
                            (lambda (a b) (> (* (window-pixel-width a) (window-pixel-height a))
                                             (* (window-pixel-width b) (window-pixel-height b))))))))
    (ignore-errors
      (split-window biggest nil (if (> (window-pixel-width biggest) (window-pixel-height biggest))
                                    'right
                                  'below)))))

(defun +my/tiling--show-hidden ()
  "The hidden panes shown again (see above), each in a window of its own;
return the panes in their order (those on the screen where :shown was), the
first one marked the main one. No room for them all: those left stay hidden,
said."
  (let ((slots (+my/tiling--live-slots (+my/tiling--slots)))
        (visible (+my/tiling--ordered-panes))
        panes left)
    (unless (memq :shown slots)
      (push :shown slots))
    (+my/tiling--set-slots nil)
    (dolist (slot slots)
      (if (eq slot :shown)
          (setq panes (append (reverse visible) panes))
        (let ((window (and (not left) (+my/tiling--new-window))))
          (if (not window)
              (push slot left)
            (+my/tiling--restore window slot)
            (push window panes)))))
    (setq panes (nreverse panes))
    (when left
      (+my/tiling--set-slots (cons :shown (nreverse left)))
      (message "No room to show %d hidden pane%s" (length left) (if (cdr left) "s" "")))
    (+my/tiling--mark-main (car panes))
    panes))

(defun +my/tiling--ready-panes ()
  "The panes to lay out, the main one first (`+my/tiling--ordered-panes'):
hidden ones shown again first, when the strategy doesn't hide panes, and
laid out its way (its :arrange), in their order."
  (let ((strategy (alist-get +my/tiling-strategy +my/tiling-strategies)))
    (when (and (+my/tiling--hidden-p) strategy (not (plist-get strategy :hides)))
      (let ((panes (+my/tiling--show-hidden)))
        (when (cdr panes)
          (funcall (plist-get strategy :arrange) panes))))
    (+my/tiling--ordered-panes)))

;; ONE PANE ON THE SCREEN, THE OTHERS IN TURN
(defun +my/tiling--show-slot (window slots target)
  "SLOTS with the TARGETth shown in WINDOW, the frame's only pane (what WINDOW
showed hidden where :shown was); kept. What to say (\"Pane 2/4\")."
  (let ((index (seq-position slots :shown))
        (state (nth target slots)))
    (unless (= index target)
      (setf (nth index slots) (+my/tiling--state window)
            (nth target slots) :shown)
      (+my/tiling--restore window state))
    (+my/tiling--set-slots slots)
    (format "Pane %d/%d" (1+ target) (length slots))))

(defun +my/tiling--show-next (direction)
  "The pane after the one shown (DIRECTION 1) or before it (-1) shown in its
window, wrapping. What to say."
  (let ((window (car (+my/tiling--panes)))
        (slots (+my/tiling--live-slots (+my/tiling--slots))))
    (+my/tiling--show-slot window slots (mod (+ (seq-position slots :shown) direction) (length slots)))))

(defun +my/tiling--show-holding (buffer)
  "The hidden pane showing BUFFER (else one with it as a tab) shown in the
frame's only pane; that window, or nil if none holds it."
  (let* ((slots (+my/tiling--live-slots (+my/tiling--slots)))
         (holds (lambda (test) (seq-position slots nil (lambda (slot _) (and (consp slot) (funcall test slot))))))
         (target (or (funcall holds (lambda (slot) (eq (plist-get slot :buffer) buffer)))
                     (funcall holds (lambda (slot) (or (assq buffer (plist-get slot :prev))
                                                       (memq buffer (plist-get slot :tabs))))))))
    (when target
      (let ((window (car (+my/tiling--panes))))
        (+my/tiling--show-slot window slots target)
        window))))

(defun +my/tiling--close-shown (window)
  "WINDOW, the frame's only pane, closed while others are hidden: the next one
shown in it (the one before, if it was the last). Non-nil if so."
  (let* ((slots (+my/tiling--live-slots (+my/tiling--slots)))
         (index (seq-position slots :shown))
         (rest (remq :shown slots)))
    (when rest
      (let ((target (min index (1- (length rest)))))
        (+my/tiling--restore window (nth target rest))
        (setf (nth target rest) :shown)
        (+my/tiling--set-slots rest)
        t))))

;; CLOSING THE PANE ON THE SCREEN (see above)
(defun +my/tiling-delete-shown-a (fn &optional window)
  "`delete-window' on the frame's only pane while others are hidden (SPC w
d): the next one shown in it instead (the frame's last window can't be
deleted)."
  (let ((window (window-normalize-window window)))
    (if (+my/tiling--shown-alone-p window)
        (with-selected-frame (window-frame window)
          (+my/tiling--close-shown window))
      (funcall fn window))))

(advice-add 'delete-window :around #'+my/tiling-delete-shown-a)

;; Doom's SPC w d (its workspaces' `+workspace/close-window-or-workspace', in
;; place of `delete-window') kills the workspace from its only window, or
;; deletes the frame: there, with panes hidden, it would have taken them all.
(defun +my/tiling-close-shown-not-workspace-a (&rest _)
  "Doom's SPC w d on the frame's only pane while others are hidden: that pane
closed, the next one shown, the workspace kept. Non-nil if so."
  (when (and (not (window-dedicated-p)) (+my/tiling--shown-alone-p (selected-window)))
    (delete-window)
    t))

(advice-add '+workspace/close-window-or-workspace :before-until
            #'+my/tiling-close-shown-not-workspace-a)

(defun +my/tiling-quit-shown-a (fn &optional window bury-or-kill)
  "`quit-restore-window' (q) on an application opened in the frame's only pane
while others are hidden: the pane closed, the next one shown (another
strategy deletes its window); the buffer killed if asked."
  (let* ((window (window-normalize-window window t))
         (buffer (window-buffer window))
         (quit (window-parameter window 'quit-restore)))
    (if (and (+my/tiling--shown-alone-p window)
             (eq (car quit) 'window)
             (eq (nth 3 quit) buffer))
        (progn
          (set-window-parameter window 'quit-restore nil)
          (delete-window window)
          (when (eq bury-or-kill 'kill)
            (kill-buffer buffer)))
      (funcall fn window bury-or-kill))))

(advice-add 'quit-restore-window :around #'+my/tiling-quit-shown-a)

(defun +my/tiling-close-last-tab-a (fn tab)
  "`+my/tabs-close' (config/editor/tabs.el) on the last tab of the frame's
only pane while others are hidden: the pane closed, the next one shown; its
file closed if nothing holds it any more."
  (let ((buffer (if (bufferp tab) tab (cdr (assq 'buffer tab))))
        (window (selected-window)))
    (if (and (+my/tiling--shown-alone-p window)
             (fboundp '+my/tabs-window-buffers)
             (equal (+my/tabs-window-buffers) (list buffer)))
        (progn
          (delete-window window)
          (when (and (buffer-live-p buffer) (buffer-file-name buffer)
                     (fboundp '+my/tabs-held-p) (not (+my/tabs-held-p buffer)))
            (kill-buffer buffer)))
      (funcall fn tab))))

(advice-add '+my/tabs-close :around #'+my/tiling-close-last-tab-a)
