;;; $DOOMDIR/config/treemacs/width.el -*- lexical-binding: t; -*-
;; The sidebar's width. Loaded from config/treemacs.el.

;; WIDTH
;; Opened `treemacs-width' columns wide, at most `+my/treemacs-max-width' of
;; the frame (not under `window-min-width'), and made so again when the
;; frame's width changes. Its width preserved (`window-preserve-size'), not
;; locked as treemacs had it: panes opened, closed or balanced leave it as it
;; is, but dragging its edge, SPC w < / > and w resize it (locked, they said
;; "Selected window has fixed size", "No resizable window on the left of this
;; one"). Resized so, its width becomes `treemacs-width' (as w makes it), kept
;; once it's closed and opened again, and not cut to the frame's part in
;; frames as wide as the one it was set in (narrower ones still cut it).
;; Emacs forgets a preserved size once the window is resized: preserved again
;; then.

(defvar +my/treemacs--width-set-at nil
  "The frame's width when the sidebar was last resized by hand, nil if never
\(see above).")

(defun +my/treemacs--width-in (frame)
  "The sidebar's width in FRAME, in columns (see above)."
  (let ((columns (frame-width frame)))
    (if (and +my/treemacs--width-set-at (>= columns +my/treemacs--width-set-at))
        treemacs-width
      (min treemacs-width
           (max window-min-width (floor (* columns +my/treemacs-max-width)))))))

(defun +my/treemacs--sidebar-window (frame)
  "FRAME's window showing the sidebar, if there's one."
  (seq-find (lambda (window)
              (with-current-buffer (window-buffer window) (+my/treemacs--sidebar-p)))
            (window-list frame 'nomini)))

(defun +my/treemacs--keep-width (window)
  "WINDOW's width (the sidebar's) preserved, and noted as set, with its
frame's width (see `+my/treemacs-width-h')."
  (let ((frame (window-frame window)))
    (window-preserve-size window t t)
    (set-window-parameter window '+my/treemacs-width (window-total-width window))
    (set-frame-parameter frame '+my/treemacs-frame-width (frame-width frame))))

(defun +my/treemacs--set-window-width (window width)
  "WINDOW (the sidebar) WIDTH columns wide, or as near as the frame lets it."
  (window-preserve-size window t nil)
  (let ((delta (- width (window-total-width window))))
    (unless (zerop delta)
      (window-resize window (window-resizable window delta t) t)))
  (+my/treemacs--keep-width window))

(defadvice! +my/treemacs-open-width-a (fn &rest args)
  "The sidebar opened at its width in the frame (see above)."
  :around #'treemacs--popup-window
  (let ((treemacs-width (+my/treemacs--width-in (selected-frame))))
    (prog1 (apply fn args)
      ;; It selects the sidebar (its mode's not set yet).
      (when (string-prefix-p treemacs-buffer-name-prefix (buffer-name (window-buffer)))
        (+my/treemacs--keep-width (selected-window))))))

(defun +my/treemacs-width-h (frame)
  "After FRAME's windows changed size: the sidebar to its width there if the
frame's width changed, else its new width kept if it was resized (see above)."
  (when-let* ((window (+my/treemacs--sidebar-window frame)))
    (when (cond ((not (eql (frame-width frame) (frame-parameter frame '+my/treemacs-frame-width)))
                 (+my/treemacs--set-window-width window (+my/treemacs--width-in frame))
                 t)
                ((not (eql (window-total-width window) (window-parameter window '+my/treemacs-width)))
                 (setq treemacs-width (window-total-width window)
                       +my/treemacs--width-set-at (frame-width frame))
                 (+my/treemacs--keep-width window)
                 t))
      ;; The selected node in view at its new width (selection.el, SIDEWAYS).
      (with-current-buffer (window-buffer window)
        (+my/treemacs--show-name window)))))

(add-hook 'window-size-change-functions #'+my/treemacs-width-h)
