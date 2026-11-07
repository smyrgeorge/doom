;;; $DOOMDIR/config/tiling/apps.el -*- lexical-binding: t; -*-
;; Tiling first: applications in new panes, files as tabs in the panes of
;; files, a pane closed with its last tab (see TILING FIRST in
;; config/tiling.el). Loaded from config/tiling.el.

;; WHAT A BUFFER IS
(defun +my/tiling-file-diff-p ()
  "Non-nil in a magit diff of some files (SPC g d's), not a whole one."
  (bound-and-true-p magit-buffer-diff-files))

(defun +my/tiling-app-p (buffer)
  "Non-nil if BUFFER is an application's (see `+my/tiling-apps')."
  (with-current-buffer buffer
    (seq-some (lambda (app)
                (if (consp app)
                    (and (derived-mode-p (car app)) (funcall (cdr app)))
                  (derived-mode-p app)))
              +my/tiling-apps)))

(defun +my/tiling--file-p (buffer)
  "Non-nil if BUFFER is a file's (or a folder's, dired)."
  (or (buffer-file-name buffer)
      (provided-mode-derived-p (buffer-local-value 'major-mode buffer) 'dired-mode)))

;; PANES
(defun +my/tiling--file-pane-p (window)
  "Non-nil if WINDOW is a pane files open in: not an application's, not
dedicated."
  (and (memq window (+my/tiling--panes))
       (not (window-dedicated-p window))
       (not (+my/tiling-app-p (window-buffer window)))))

(defun +my/tiling--file-pane ()
  "The pane files open in from elsewhere: the last selected of those files open
in, one showing a file first; nil without one."
  (let* ((panes (seq-filter #'+my/tiling--file-pane-p (+my/tiling--panes)))
         (files (seq-filter (lambda (window) (+my/tiling--file-p (window-buffer window))) panes)))
    (car (sort (or files panes)
               (lambda (a b) (> (window-use-time a) (window-use-time b)))))))

(defun +my/tiling--alist (alist)
  "ALIST, a `display-buffer' one, without where and how big its window should
be (other rules', e.g. Doom's popups': the strategy decides)."
  (seq-remove (lambda (entry)
                (memq (car-safe entry) '(window-width window-height window-size preserve-size
                                         window-parameters dedicated side slot direction)))
              alist))

(defun +my/tiling--new-pane ()
  "A new pane where the strategy puts it, with no tabs yet; nil in a frame
without panes."
  (when-let* ((panes (+my/tiling--panes)))
    (let ((new (funcall (plist-get (+my/tiling--strategy) :split) panes)))
      (set-window-prev-buffers new nil)
      (set-window-next-buffers new nil)
      (set-window-parameter new 'tab-line-buffers nil)
      new)))

(defun +my/tiling-display-buffer (buffer alist)
  "A `display-buffer' action: BUFFER in a new pane where the tiling strategy
puts it (config/tiling.el), its only tab; quitting it closes the pane. Nil
(the next action then) in a frame without panes."
  (when-let* ((new (+my/tiling--new-pane)))
    (window--display-buffer buffer new 'window (+my/tiling--alist alist))))

;; APPLICATIONS AND FILES SHOWN (`display-buffer', see config/tiling.el)
(defun +my/tiling--display (buffer alist)
  "`display-buffer-overriding-action': an application in its pane, else a new
one; a file shown from elsewhere than a pane of files, in the last one (a new
pane without one). Nil for anything else (popups, *Completions*, transient
menus...), and while the minibuffer is open (previews put back what they
showed): as it asks."
  (cond
   ((active-minibuffer-window) nil)
   ((and (+my/tiling-app-p buffer) (not (alist-get 'allow-no-window alist)))
    (if-let* ((window (get-buffer-window buffer)))
        (window--display-buffer buffer window 'reuse (+my/tiling--alist alist))
      (+my/tiling-display-buffer buffer alist)))
   ((and (+my/tiling--file-p buffer)
         (not (+my/tiling--file-pane-p (selected-window))))
    (if-let* ((window (or (seq-find #'+my/tiling--file-pane-p (get-buffer-window-list buffer 'nomini))
                          (+my/tiling--file-pane))))
        (window--display-buffer buffer window 'reuse (+my/tiling--alist alist))
      (+my/tiling-display-buffer buffer alist)))))

(setq display-buffer-overriding-action '((+my/tiling--display)))

;; FILES SWITCHED TO (find-file, the sidebar...: `switch-to-buffer')
(defun +my/tiling-switch-to-buffer-a (fn buffer-or-name &optional norecord &rest args)
  "A file switched to in an application's pane: in the last pane of files
instead (a new pane without one), see config/tiling.el. Not while the
minibuffer is open, nor without recording it (NORECORD): previews (consult's)
show files where they were asked to, and put back what was there."
  (let ((buffer (get-buffer buffer-or-name)))
    (when (and buffer
               (not norecord)
               (not (active-minibuffer-window))
               (+my/tiling--file-p buffer)
               (memq (selected-window) (+my/tiling--panes))
               (+my/tiling-app-p (window-buffer)))
      (when-let* ((pane (or (+my/tiling--file-pane) (+my/tiling--new-pane))))
        (select-window pane)))
    (apply fn buffer-or-name norecord args)))

(advice-add 'switch-to-buffer :around #'+my/tiling-switch-to-buffer-a)

;; A PANE CLOSED WITH ITS LAST TAB (see config/tiling.el)
(defun +my/tiling--last-tab-p (window buffer)
  "Non-nil if BUFFER is WINDOW's only tab (config/editor/tabs.el), or without
tabs the only live buffer it showed."
  (with-selected-window window
    (if (and (fboundp '+my/tabs-window-buffers) (bound-and-true-p tab-line-mode))
        (equal (+my/tabs-window-buffers) (list buffer))
      (not (seq-some (lambda (entry) (and (buffer-live-p (car entry)) (not (eq (car entry) buffer))))
                     (window-prev-buffers window))))))

(defun +my/tiling-close-pane-h ()
  "The buffer killed: the panes it was the last tab of close, but a frame's
last pane."
  (let ((buffer (current-buffer)))
    (dolist (window (get-buffer-window-list buffer 'nomini t))
      (when (and (window-live-p window)
                 (not (window-parameter window 'window-side))
                 (eq (window-deletable-p window) t)
                 (+my/tiling--last-tab-p window buffer))
        (delete-window window)))))

(add-hook 'kill-buffer-hook #'+my/tiling-close-pane-h)
