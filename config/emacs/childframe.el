;;; $DOOMDIR/config/emacs/childframe.el -*- lexical-binding: t; -*-
;; Child frames laid over a window: the notices (config/banner.el), the error
;; stripe (config/stripe.el), WebKit's cover while a page loads
;; (config/webkit.el). Loaded from config/emacs.el, before them.

;; ====== CODE ======

;; A FRAME
;; Inside its parent, without borders, never focused, hidden until laid out;
;; its window shows a read-only buffer of its own, nothing but its text (no
;; mode line, header line, tab line, margins, fringes or cursor).
;; Its focus redirected to its parent (`redirect-frame-focus', as posframe
;; does): no-accept-focus keeps the window system's focus away, but Emacs
;; still made a switch-frame event as the mouse moved into it while mouse
;; tracking was on (dap-mode's tooltips), or as it was clicked. Run as a
;; command, that ended a selection made with the mouse, and selected the child
;; frame: a visual selection vanished as the mouse crossed the stripe or a
;; notice. Its events now go to its parent; a click on it is still the child's
;; window's (its position, its buffer's keys).
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

(defconst +my/childframe--laid-out
  '(parent-frame minibuffer visibility width height left top)
  "A child frame's parameters its feature sets as it lays it out (see ITS OWN
PARAMETERS): not given back.")

(defvar +my/childframe--buffers nil
  "(FRAME . BUFFER) for each frame `+my/childframe-make' made (see ITS BUFFER).")

(defvar +my/childframe--own nil
  "(FRAME . PARAMETERS) for each frame `+my/childframe-make' made: those it was
made with but `+my/childframe--laid-out' (see ITS OWN PARAMETERS).")

(defvar +my/childframe--listed nil
  "(FRAME . LIST) for each frame a feature's list (a symbol) has held, as
`+my/childframe-sync' saw it (see LEFT BEHIND).")

(defun +my/childframe-make (parent name &optional parameters)
  "A child frame of PARENT (see A FRAME), its buffer \" *NAME*\". PARAMETERS,
an alist, are added to its parameters or replace them. Other code isn't told
about it (`after-make-frame-functions'), and the selected frame stays so."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (frame-resize-pixelwise t)
         (buffer (generate-new-buffer (format " *%s*" name)))
         (selected (selected-frame))
         (all (append parameters
                      (cl-remove-if (lambda (parameter) (assq (car parameter) parameters))
                                    `((parent-frame . ,parent)
                                      (minibuffer . ,(minibuffer-window parent))
                                      ,@+my/childframe--parameters))))
         (frame (make-frame all)))
    ;; Its own, kept (see ITS OWN PARAMETERS): not where it is, nor its size
    ;; (laid out by its feature).
    (push (cons frame (cl-remove-if (lambda (parameter) (memq (car parameter) +my/childframe--laid-out))
                                    all))
          +my/childframe--own)
    (unless (eq (selected-frame) selected)
      (select-frame selected 'norecord))
    (redirect-frame-focus frame parent)
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
    (push (cons frame buffer) +my/childframe--buffers)
    frame))

(defun +my/childframe-delete (frame)
  "Delete FRAME (made by `+my/childframe-make'), and its buffer."
  (when (frame-live-p frame)
    (let ((buffer (window-buffer (frame-root-window frame))))
      (delete-frame frame t)
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

;; ITS OWN PARAMETERS
;; `modify-all-frames-parameters' sets a parameter on every frame, child frames
;; too: `fringe-mode' (8 and 16 px fringes on a 7 px strip made it 31 px wide,
;; over the file's text, and a notice wider than its parent; the running Emacs
;; ran out of memory as it did that), `scroll-bar-mode'... A child frame made
;; here gets back at once the value it was made with of each parameter it set
;; (`+my/childframe--own': A FRAME's, and its feature's: its font, colours...).
(defun +my/childframe--keep-own-a (alist)
  "After `modify-all-frames-parameters' set ALIST: the child frames made here
get back their own values of the parameters it set (see ITS OWN PARAMETERS)."
  (pcase-dolist (`(,frame . ,own) +my/childframe--own)
    (when (frame-live-p frame)
      (when-let* ((back (delq nil (mapcar (lambda (parameter) (assq (car parameter) own)) alist))))
        (modify-frame-parameters frame back)))))

(advice-add 'modify-all-frames-parameters :after #'+my/childframe--keep-own-a)

;; ITS BUFFER
;; Goes with its frame, however the frame goes: deleted by
;; `+my/childframe-delete', with its parent (Emacs deletes a frame's child
;; frames with it: a frame closed), or by other code. Else each frame closed
;; left a buffer per notice and stripe it had, shown nowhere.
(defun +my/childframe--deleted-h (frame)
  "Kill the buffer of FRAME, deleted, if `+my/childframe-make' made it; forget
its own parameters."
  (setq +my/childframe--own (assq-delete-all frame +my/childframe--own)
        +my/childframe--listed (assq-delete-all frame +my/childframe--listed))
  (when-let* ((entry (assq frame +my/childframe--buffers)))
    (setq +my/childframe--buffers (delq entry +my/childframe--buffers))
    (when (buffer-live-p (cdr entry))
      (kill-buffer (cdr entry)))))

(add-hook 'after-delete-frame-functions #'+my/childframe--deleted-h)

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
windows that no longer want one are hidden, those of closed windows deleted,
dead ones forgotten (their buffers killed).
An error in SHOW is a message, after LABEL: the other windows still get theirs."
  (let ((wanted (+my/childframe-windows wants))
        (gone nil))
    ;; Deleting a frame runs other code's hooks (`delete-frame-functions',
    ;; `kill-buffer-hook'...): the list is taken as it is after them, the
    ;; entries gone out of it, not set back to what it was before.
    (dolist (entry (symbol-value frames))
      (pcase-let ((`(,window ,frame) entry))
        (cond ((not (frame-live-p frame))
               (+my/childframe--deleted-h frame)
               (push entry gone))
              ((memq window wanted))
              ((window-live-p window) (make-frame-invisible frame t))
              (t (+my/childframe-delete frame) (push entry gone)))))
    (set frames (cl-remove-if (lambda (entry) (memq entry gone)) (symbol-value frames)))
    (+my/childframe--delete-left-behind frames)
    (dolist (window wanted)
      (condition-case err
          (funcall show window)
        (error (message "%s: %s" label (error-message-string err)))))
    (dolist (entry (symbol-value frames))
      (unless (assq (nth 1 entry) +my/childframe--listed)
        (push (cons (nth 1 entry) frames) +my/childframe--listed)))))

;; LEFT BEHIND
;; A frame out of its feature's list is out of its sync's reach: still on
;; the screen, it stayed there, over whatever window came there (the error
;; stripe over agent-shell, Agent UI, Beads... with the file's window long
;; closed). Each sync deletes the frames its list held and no longer does.
(defun +my/childframe--delete-left-behind (frames)
  "Delete the frames FRAMES (a symbol) held and no longer holds (see LEFT
BEHIND)."
  (pcase-dolist (`(,frame . ,list) (copy-sequence +my/childframe--listed))
    (when (and (eq list frames)
               (not (cl-find frame (symbol-value frames) :key #'cadr)))
      (setq +my/childframe--listed (assq-delete-all frame +my/childframe--listed))
      (+my/childframe-delete frame))))

(defun +my/childframe-soon (timer function)
  "Call FUNCTION right after this redisplay (frames can't be made during it),
once however many times asked meanwhile. TIMER, a symbol, holds the timer
until then."
  (unless (timerp (symbol-value timer))
    (set timer (run-at-time 0 nil (lambda ()
                                    (set timer nil)
                                    (funcall function))))))
