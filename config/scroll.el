;;; $DOOMDIR/config/scroll.el -*- lexical-binding: t; -*-
;; Scrolling leaves the caret where it is. Loaded from config.el.

;; ====== VARIABLES ======

;; THE CARET STAYS WHILE SCROLLING
;; Like IntelliJ: scrolling with the mouse wheel or trackpad doesn't move the
;; caret, which stays on its line even off-screen. Emacs can't show a window
;; without its point, so point is still pushed along as the text scrolls; the
;; caret's position is kept aside, and the cursor hidden (its line highlight
;; stays on the caret's line), until:
;; - you scroll back to it: the cursor reappears there;
;; - you press a key: the key acts on the caret (typing, j/k, p, u...) and the
;;   window scrolls back to it, unless the key leaves the caret alone (saving,
;;   M-x, switching windows...): then the view stays where you scrolled;
;; - you click in the text: the caret goes there.
;; Only in file buffers, and not while selecting (the selection would follow).
;; Keyboard scrolling (C-e/C-y, C-d/C-u...) still moves the cursor, as in Vim.
(defvar +my/scroll-caret-commands '(mwheel-scroll pixel-scroll-precision)
  "Scroll commands that leave the caret where it is.")

;; ====== CODE ======

(defvar +my/scroll--window nil
  "The window the current scroll command scrolls.")

(defvar +my/scroll--selected nil
  "The selected window when the current command started.")

(defvar +my/scroll--pending nil
  "(WINDOW BUFFER CARET START AWAY TICK) when the current command was given the
caret of WINDOW back: what's needed to scroll away again if it leaves it alone.")

(defvar +my/scroll--hl-window nil
  "The window whose line highlight is being drawn.")

(defun +my/scroll--caret (window)
  "The marker where WINDOW's caret is while scrolled away from it, or nil."
  (window-parameter window '+my/scroll-caret))

(defun +my/scroll--away (window caret)
  "Keep WINDOW's caret at CARET (a marker) and hide the cursor."
  (set-window-parameter window '+my/scroll-caret caret)
  (set-window-cursor-type window nil))

(defun +my/scroll--back (window)
  "Forget where WINDOW's caret was kept and show the cursor."
  (set-window-parameter window '+my/scroll-caret nil)
  (set-window-cursor-type window t))

(defun +my/scroll--drop (window)
  (when-let* ((caret (+my/scroll--caret window)))
    (set-marker caret nil))
  (+my/scroll--back window))

(defun +my/scroll--eligible-p (window)
  "Non-nil if scrolling WINDOW should leave its caret alone."
  (with-current-buffer (window-buffer window)
    (and buffer-file-name
         (not (region-active-p))
         (not (eq (bound-and-true-p evil-state) 'visual)))))

(defun +my/scroll--target ()
  "The window the current scroll command scrolls (the one under the mouse)."
  (let ((window (and (consp last-input-event)
                     (ignore-errors
                       (mouse-wheel--get-scroll-window last-input-event)))))
    (if (window-live-p window) window (selected-window))))

(defun +my/scroll--pre-command-h ()
  (setq +my/scroll--pending nil
        +my/scroll--window nil
        +my/scroll--selected (selected-window))
  (if (memq this-command +my/scroll-caret-commands)
      ;; Scrolling: remember the caret, unless it's already kept aside.
      (let ((window (+my/scroll--target)))
        (setq +my/scroll--window window)
        (when (and (not (+my/scroll--caret window))
                   (+my/scroll--eligible-p window))
          (set-window-parameter window '+my/scroll-caret
                                (copy-marker (window-point window)))))
    ;; Anything else: give the command the caret.
    (let ((window (selected-window)))
      (when-let* ((caret (+my/scroll--caret window)))
        (+my/scroll--back window)
        (if (not (eq (marker-buffer caret) (window-buffer window)))
            (set-marker caret nil)
          (setq +my/scroll--pending
                (list window (window-buffer window) caret (window-start window)
                      (window-point window)
                      (buffer-chars-modified-tick (window-buffer window))))
          (set-window-point window caret))))))

(defun +my/scroll--post-command-h ()
  (cond
   ;; Scrolled: show the cursor again once the caret is back in view.
   (+my/scroll--window
    (let ((window +my/scroll--window))
      (when-let* (((window-live-p window))
                  (caret (+my/scroll--caret window)))
        (cond ((not (eq (marker-buffer caret) (window-buffer window)))
               (+my/scroll--drop window))
              ((pos-visible-in-window-p caret window)
               (set-window-point window caret)
               (+my/scroll--drop window))
              (t (set-window-cursor-type window nil))))))
   ;; The command had the caret: if it left it (and the text) alone, scroll
   ;; away again; otherwise the window follows the caret as usual.
   (+my/scroll--pending
    (pcase-let ((`(,window ,buffer ,caret ,start ,away ,tick) +my/scroll--pending))
      (if (and (window-live-p window)
               (eq (window-buffer window) buffer)
               (= (window-point window) caret)
               (= (buffer-chars-modified-tick buffer) tick)
               (+my/scroll--eligible-p window))
          (progn
            (set-window-start window start)
            (set-window-point window away)
            (+my/scroll--away window caret))
        (set-marker caret nil)))))
  ;; A click in the text of another window whose caret was away: the caret
  ;; goes where you clicked.
  (let ((window (selected-window)))
    (when (and (not (eq window +my/scroll--selected))
               (+my/scroll--caret window)
               (mouse-event-p last-input-event)
               (eq (posn-window (event-start last-input-event)) window)
               (null (posn-area (event-start last-input-event))))
      (+my/scroll--drop window)))
  (setq +my/scroll--pending nil
        +my/scroll--window nil))

(defun +my/scroll--hl-line-range ()
  "Highlight the caret's line, also while the window is scrolled away from it."
  (let* ((window (or +my/scroll--hl-window (selected-window)))
         (caret (and (window-live-p window) (+my/scroll--caret window))))
    (save-excursion
      (when (and caret (eq (marker-buffer caret) (current-buffer)))
        (goto-char caret))
      (cons (line-beginning-position) (line-beginning-position 2)))))

;; Emacs 31's global hl-line draws each window's highlight before redisplay.
(defadvice! +my/scroll--hl-line-window-a (fn window)
  :around #'global-hl-line-window-redisplay
  (let ((+my/scroll--hl-window window))
    (funcall fn window)))

(define-minor-mode +my/scroll-keep-caret-mode
  "Scrolling with the mouse leaves the caret where it is, like IntelliJ."
  :global t
  (if +my/scroll-keep-caret-mode
      (progn
        (add-hook 'pre-command-hook #'+my/scroll--pre-command-h)
        (add-hook 'post-command-hook #'+my/scroll--post-command-h)
        (setq-default hl-line-range-function #'+my/scroll--hl-line-range))
    (remove-hook 'pre-command-hook #'+my/scroll--pre-command-h)
    (remove-hook 'post-command-hook #'+my/scroll--post-command-h)
    (when (eq (default-value 'hl-line-range-function) #'+my/scroll--hl-line-range)
      (setq-default hl-line-range-function nil))
    (dolist (frame (frame-list))
      (dolist (window (window-list frame 'nomini))
        (+my/scroll--drop window)))))

(+my/scroll-keep-caret-mode 1)
