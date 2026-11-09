;;; $DOOMDIR/config/childframe.el -*- lexical-binding: t; -*-
;; Child frames laid over a window: the notices (config/banner.el), the error
;; stripe (config/stripe.el), WebKit's cover while a page loads
;; (config/webkit.el). Loaded from config.el, before them.

;; ====== CODE ======

;; A FRAME
;; Inside its parent, without borders, never focused, hidden until laid out;
;; its window shows a read-only buffer of its own, nothing but its text (no
;; mode line, header line, tab line, margins, fringes or cursor).
(defconst +my/childframe--parameters
  '((fullscreen . nil)
    (no-accept-focus . t)
    (no-focus-on-map . t)
    (min-width . 0)
    (min-height . 0)
    (width . 1)
    (height . 1)
    (border-width . 0)
    (internal-border-width . 0)
    (child-frame-border-width . 0)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil)
    (left-fringe . 0)
    (right-fringe . 0)
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (tab-bar-lines . 0)
    (line-spacing . 0)
    (unsplittable . t)
    (no-other-frame . t)
    (undecorated . t)
    (visibility . nil)
    (cursor-type . nil)
    (no-special-glyphs . t)
    (desktop-dont-save . t))
  "A child frame's parameters (see A FRAME), besides its parent and minibuffer.")

(defun +my/childframe-make (parent name &optional parameters)
  "A child frame of PARENT (see A FRAME), its buffer \" *NAME*\". PARAMETERS,
an alist, are added to its parameters or replace them. Other code isn't told
about it (`after-make-frame-functions'), and the selected frame stays so."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (frame-resize-pixelwise t)
         (buffer (generate-new-buffer (format " *%s*" name)))
         (selected (selected-frame))
         (frame (make-frame
                 (append parameters
                         (cl-remove-if (lambda (parameter) (assq (car parameter) parameters))
                                       `((parent-frame . ,parent)
                                         (minibuffer . ,(minibuffer-window parent))
                                         ,@+my/childframe--parameters))))))
    (unless (eq (selected-frame) selected)
      (select-frame selected 'norecord))
    (with-current-buffer buffer
      (setq-local mode-line-format nil
                  header-line-format nil
                  tab-line-format nil
                  cursor-type nil
                  cursor-in-non-selected-windows nil
                  truncate-lines t
                  display-line-numbers nil
                  show-trailing-whitespace nil
                  left-margin-width nil
                  right-margin-width nil
                  buffer-read-only t))
    (let ((window (frame-root-window frame)))
      (dolist (parameter '(mode-line-format header-line-format tab-line-format))
        (set-window-parameter window parameter 'none))
      (set-window-buffer window buffer)
      (set-window-dedicated-p window t))
    frame))

(defun +my/childframe-delete (frame)
  "Delete FRAME (made by `+my/childframe-make'), and its buffer."
  (when (frame-live-p frame)
    (let ((buffer (window-buffer (frame-root-window frame))))
      (delete-frame frame t)
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

;; ON THE SCREEN
;; Only a frame `frame-visible-p' calls t is on the screen. On X, one hidden
;; right after it was shown (its window showing another buffer at once) is
;; called `icon': its late events took the hiding for iconifying. It's off the
;; screen all the same, and showing it again must not skip it.
(defun +my/childframe-shown-p (frame)
  "Non-nil if FRAME is on the screen (see ON THE SCREEN)."
  (eq (frame-visible-p frame) t))

(defun +my/childframe-show (frame)
  "Put FRAME on the screen, unless it is (see ON THE SCREEN)."
  (unless (+my/childframe-shown-p frame)
    (make-frame-visible frame)))

;; A FRAME PER WINDOW
;; A feature keeps a list of (WINDOW FRAME ...), for the windows that want a
;; frame over them (or wanted one). When windows change, it syncs the list
;; with them, right after the redisplay (frames can't be made during it).
(defun +my/childframe-windows (wants)
  "The windows of the visible graphical frames (not child frames) for which
WANTS, called with the window, returns non-nil."
  (let (wanted)
    (dolist (frame (frame-list))
      (when (and (not (frame-parent frame))
                 (display-graphic-p frame)
                 (frame-visible-p frame))
        (dolist (window (window-list frame 'nomini))
          (when (funcall wants window)
            (push window wanted)))))
    wanted))

(defun +my/childframe-sync (frames wants show label)
  "Sync FRAMES, a symbol whose value is a list of (WINDOW FRAME ...), with the
windows: those for which WANTS returns non-nil get SHOW called with them (it
lays out the window's frame, making it if the window has none); the frames of
windows that no longer want one are hidden, those of closed windows deleted.
An error in SHOW is a message, after LABEL: the other windows still get theirs."
  (let ((wanted (+my/childframe-windows wants)))
    (set frames
         (cl-remove-if (lambda (entry)
                         (pcase-let ((`(,window ,frame) entry))
                           (cond ((not (frame-live-p frame)) t)
                                 ((memq window wanted) nil)
                                 ((window-live-p window)
                                  (make-frame-invisible frame t)
                                  nil)
                                 (t (+my/childframe-delete frame) t))))
                       (symbol-value frames)))
    (dolist (window wanted)
      (condition-case err
          (funcall show window)
        (error (message "%s: %s" label (error-message-string err)))))))

(defun +my/childframe-soon (timer function)
  "Call FUNCTION right after this redisplay (frames can't be made during it),
once however many times asked meanwhile. TIMER, a symbol, holds the timer
until then."
  (unless (timerp (symbol-value timer))
    (set timer (run-at-time 0 nil (lambda ()
                                    (set timer nil)
                                    (funcall function))))))
