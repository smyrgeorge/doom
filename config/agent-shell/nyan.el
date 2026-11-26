;;; $DOOMDIR/config/agent-shell/nyan.el -*- lexical-binding: t; -*-
;; Nyan Cat in a session's mode line. Loaded from config/agent-shell.el.

;; NYAN CAT
;; A session's mode line shows Nyan Cat (nyan-mode) for where you are in the
;; conversation: doom-modeline's position draws it in a buffer where
;; `nyan-mode' is non-nil. Set in the session's buffer alone (with its width,
;; `+my/agent-shell-nyan-bar-length'), the mode never turned on: other
;; buffers keep their mode line.
;; Animated: nyan draws its next frame while `nyan-animation-timer' is a timer.
;; Ours, not nyan's (whose every frame redraws the current buffer's mode line,
;; whatever it is): each frame redraws the mode lines of the sessions in a
;; window, and it runs from the first session opened to the last one killed.
(defvar nyan-mode)
(defvar nyan-bar-length)
(defvar nyan-animation-timer)
(defvar nyan-animation-frame-interval)
(defvar nyan-current-frame)
(declare-function nyan-stop-animation "ext:nyan-mode")

(defun +my/agent-shell-nyan-h ()
  "Nyan Cat in this session's mode line, animated (see above)."
  (when (require 'nyan-mode nil t)
    (setq-local nyan-mode t
                nyan-bar-length +my/agent-shell-nyan-bar-length)
    (add-hook 'kill-buffer-hook #'+my/agent-shell-nyan-stop-h nil t)
    (+my/agent-shell-nyan-start)))

(add-hook 'agent-shell-mode-hook #'+my/agent-shell-nyan-h)

(defun +my/agent-shell-nyan-frame ()
  "Nyan Cat's next frame, in the mode lines of the sessions in a window."
  ;; nyan's 6 frames (`nyan-animation-frames').
  (setq nyan-current-frame (% (1+ nyan-current-frame) 6))
  (walk-windows
   (lambda (window)
     (let ((buffer (window-buffer window)))
       (when (local-variable-p 'nyan-mode buffer)
         (with-current-buffer buffer
           (force-mode-line-update)))))
   'no-minibuf 'visible))

(defun +my/agent-shell-nyan-ours-p ()
  "Non-nil if Nyan Cat's animation is ours (see above), not nyan's."
  (and (timerp nyan-animation-timer)
       (eq (timer--function nyan-animation-timer) #'+my/agent-shell-nyan-frame)))

(defun +my/agent-shell-nyan-start ()
  "Nyan Cat's animation started, unless it runs already."
  (unless (timerp nyan-animation-timer)
    (setq nyan-animation-timer
          (run-at-time nyan-animation-frame-interval nyan-animation-frame-interval
                       #'+my/agent-shell-nyan-frame))))

(defun +my/agent-shell-nyan-stop-h ()
  "Nyan Cat's animation stopped with the last session's buffer, this one."
  (when (and (+my/agent-shell-nyan-ours-p)
             (not (seq-some (lambda (buffer)
                              (and (not (eq buffer (current-buffer)))
                                   (local-variable-p 'nyan-mode buffer)))
                            (buffer-list))))
    (nyan-stop-animation)))
