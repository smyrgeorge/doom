;;; $DOOMDIR/config/banner/frames.el -*- lexical-binding: t; -*-
;; The frames laying notices over the header line. Loaded from config/banner.el.

;;; The notices' frames
;; A child frame (config/childframe.el) over the header line of each window
;; with notices.

(defvar +my/banner--frames nil
  "(WINDOW FRAME KEY) for each window that shows (or showed) notices: FRAME
lays them over its header line, KEY is what it shows.")

(defvar +my/banner--theme 0 "Bumped when the theme changes: redraw the notices.")

(defun +my/banner--make-frame (parent)
  "A frame without borders, not taking focus, inside PARENT, for notices."
  (+my/childframe-make parent "+my/banner"
                       `((title . "notices")
                         (font . ,(face-attribute 'default :font parent)))))

(defun +my/banner--show-in (window)
  "Lay the notices of WINDOW's buffer over its header line."
  (let* ((buffer (window-buffer window))
         (notices (buffer-local-value '+my/banner--list buffer))
         (entry (assq window +my/banner--frames)))
    ;; In case the header line was set anew (e.g. by a mode) since.
    (with-current-buffer buffer (+my/banner--install))
    (unless (and entry (frame-live-p (nth 1 entry)))
      (when entry (+my/childframe-delete (nth 1 entry)))
      (setq entry (list window (+my/banner--make-frame (window-frame window)) nil))
      (setq +my/banner--frames
            (cons entry (cl-remove window +my/banner--frames :key #'car))))
    (let* ((frame (nth 1 entry))
           (columns (/ (- (window-pixel-width window)
                          (window-right-divider-width window)
                          (window-scroll-bar-width window))
                       (frame-char-width (window-frame window))))
           (key (list buffer notices +my/banner--theme columns))
           ;; From the frame's native edges, like the frame's own position.
           (edges (window-pixel-edges window))
           (left (nth 0 edges))
           (top (+ (nth 1 edges) (window-tab-line-height window)))
           (width (- (window-pixel-width window)
                     (window-right-divider-width window)
                     (window-scroll-bar-width window)))
           (height (* (length notices) (+my/banner--row-height window)))
           (geometry (list left top width height))
           (frame-resize-pixelwise t))
      (unless (equal key (nth 2 entry))
        (with-current-buffer (window-buffer (frame-root-window frame))
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (mapconcat (lambda (notice) (+my/banner--row notice buffer nil nil columns))
                               notices "\n"))
            (goto-char (point-min))))
        (set-frame-parameter frame 'background-color
                             (face-background (+my/banner--face (nth 3 (car notices))) nil t))
        (setf (nth 2 entry) key))
      (unless (equal geometry (frame-parameter frame '+my/banner-geometry))
        (set-frame-size frame width height t)
        (set-frame-position frame left top)
        (set-frame-parameter frame '+my/banner-geometry geometry))
      (+my/childframe-show frame))))

(defun +my/banner--sync ()
  "Show each window's notices over its header line, and hide those of windows
that no longer have any."
  (+my/childframe-sync '+my/banner--frames
                       (lambda (window) (buffer-local-value '+my/banner--list (window-buffer window)))
                       #'+my/banner--show-in "Notices"))

(defvar +my/banner--sync-timer nil)

(defun +my/banner--sync-soon (&rest _)
  "Sync right after this redisplay (frames can't be made during it)."
  (+my/childframe-soon '+my/banner--sync-timer #'+my/banner--sync))

(defun +my/banner--window-change-h (frame)
  ;; Windows split, closed, resized, or showing another buffer.
  (unless (frame-parent frame)
    (+my/banner--sync-soon)))

(add-hook 'window-state-change-functions #'+my/banner--window-change-h)

;; A new major mode drops the buffer's notices.
(add-hook 'change-major-mode-hook #'+my/banner--sync-soon)
