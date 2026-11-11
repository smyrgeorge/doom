;;; $DOOMDIR/config/agent-ui/finished.el -*- lexical-binding: t; -*-
;; A finished element closes itself. Loaded from config/agent-ui.el, after
;; canvas.el. No Doom here (see docs/agent-ui.md).
;;
;; An element of a type that finishes (its :finished: steps, todo, progress),
;; once all of it went well (`done'), closes itself `agent-ui-close-finished'
;; seconds later, or its own :close's (false: never); a line under it counts
;; them down, with a Keep button. Closed, it's removed: its canvas's pane
;; closes if it was the last (as an emptied canvas's does), the cursor back in
;; the session if it was there. Some of it failed: it stays. It changing
;; meanwhile starts its countdown again, or stops it (not finished well any
;; more); Keep stops it until it changes. The countdown runs while its canvas
;; is in a window: you see it go. A project's panel (config/agent-ui/panels.el)
;; never closes: it stays.

(require 'cl-lib)

;; ====== VARIABLES ======

(defcustom agent-ui-close-finished 10
  "Seconds a finished element (see above) stays before it closes itself;
nil: only those whose :close gives seconds close."
  :type '(choice (const :tag "Only when the element says" nil) number)
  :group 'agent-ui)

(defvar-local agent-ui--closing nil
  "In a canvas: its elements counting down, by id: (ELEMENT . SECONDS-LEFT),
ELEMENT as it was when it started (it changing starts it again).")

(defvar-local agent-ui--kept nil
  "In a canvas: its finished elements the user kept, by id: each as it was
then (it changing forgets it).")

(defvar-local agent-ui--closing-timer nil
  "In a canvas: the countdowns' timer, a tick a second.")

;; ====== COUNTING DOWN ======

(defun agent-ui--close-seconds (element)
  "The seconds ELEMENT stays once finished (its :close, else
`agent-ui-close-finished'), or nil: it doesn't close."
  (let ((close (plist-get element :close)))
    (cond ((eq close :false) nil)
          ((numberp close) close)
          ((eq close t) (or agent-ui-close-finished 10))
          (t agent-ui-close-finished))))

(defun agent-ui--finished-check ()
  "The current canvas changed (`agent-ui-changed-hook'): its finished
elements' countdowns started, started again or stopped (see above)."
  (unless (bound-and-true-p agent-ui-panels--state)
    (let ((closing (or agent-ui--closing (make-hash-table :test #'equal)))
          (kept (or agent-ui--kept (make-hash-table :test #'equal))))
      ;; Gone from it: forgotten.
      (dolist (table (list closing kept))
        (let (gone)
          (maphash (lambda (id _) (unless (member id agent-ui--order) (push id gone))) table)
          (dolist (id gone) (remhash id table))))
      (dolist (id agent-ui--order)
        (let* ((element (agent-ui--entry-element (gethash id agent-ui--entries)))
               (counting (gethash id closing))
               (seconds (agent-ui--close-seconds element)))
          ;; Changed since the user kept it: forgotten.
          (unless (eq (gethash id kept element) element)
            (remhash id kept))
          (if (and seconds
                   (not (gethash id kept))
                   (eq (agent-ui-finished element) 'done))
              (unless (eq (car counting) element)
                (puthash id (cons element (max 0 (ceiling seconds))) closing)
                (agent-ui--dirty (list id)))
            (when counting
              (remhash id closing)
              (agent-ui--dirty (list id))))))
      (setq agent-ui--closing closing
            agent-ui--kept kept)
      (agent-ui--closing-timer))))

(add-hook 'agent-ui-changed-hook #'agent-ui--finished-check)

(defun agent-ui--closing-timer ()
  "The current canvas's countdowns' timer: running while one counts down,
stopped once none does."
  (if (and agent-ui--closing (> (hash-table-count agent-ui--closing) 0))
      (unless (timerp agent-ui--closing-timer)
        (let ((buffer (current-buffer))
              (timer nil))
          (setq timer (run-with-timer 1 1 (lambda () (agent-ui--closing-tick buffer timer)))
                agent-ui--closing-timer timer)))
    (when (timerp agent-ui--closing-timer)
      (cancel-timer agent-ui--closing-timer))
    (setq agent-ui--closing-timer nil)))

(defun agent-ui--closing-tick (canvas timer)
  "A second gone: CANVAS's countdowns a second down, if it's in a window (else
they wait); those at 0 closed. TIMER, the timer: stopped once CANVAS is gone."
  (if (not (buffer-live-p canvas))
      (cancel-timer timer)
    (with-current-buffer canvas
      (when (agent-ui--window)
        (let (over)
          (maphash (lambda (id counting)
                     (setcdr counting (1- (cdr counting)))
                     (if (<= (cdr counting) 0)
                         (push id over)
                       (agent-ui--dirty (list id))))
                   agent-ui--closing)
          (when over
            (agent-ui--close-finished canvas over)))
        (agent-ui--closing-timer)))))

(defun agent-ui--close-finished (canvas ids)
  "IDS of CANVAS removed, their countdown over: the cursor back in its
session if it was in CANVAS's pane, closed now."
  (with-current-buffer canvas
    (let ((focused (eq (window-buffer (selected-window)) canvas))
          (session (bound-and-true-p agent-ui--session-buffer)))
      (dolist (id ids)
        (remhash id agent-ui--closing)
        (when (member id agent-ui--order)
          (agent-ui-remove id :canvas canvas)))
      (when-let* (((and focused (not (get-buffer-window canvas))))
                  (window (and (buffer-live-p session) (get-buffer-window session))))
        (select-window window)))))

;; ====== ITS LINE ======

(defun agent-ui--closing-footer (id)
  "Element ID's countdown, a line under it, while it counts down
\(`agent-ui-footer-functions')."
  (when-let* ((counting (and agent-ui--closing (gethash id agent-ui--closing))))
    (concat (propertize "✓ " 'face 'agent-ui-success)
            (propertize (format "All done, closing in %ds" (cdr counting)) 'face 'agent-ui-muted)
            "   "
            (agent-ui-button (propertize "⏵ Keep" 'face 'agent-ui-action)
                             (lambda () (agent-ui-keep-finished id))
                             "RET: keep it, not closed"))))

(add-hook 'agent-ui-footer-functions #'agent-ui--closing-footer)

(defun agent-ui-keep-finished (id &optional canvas)
  "Keep finished element ID of CANVAS (default: the current buffer's): not
closed, until it changes (see above)."
  (agent-ui--in (or canvas (current-buffer))
    (when-let* ((entry (gethash id agent-ui--entries)))
      (puthash id (agent-ui--entry-element entry)
               (or agent-ui--kept (setq agent-ui--kept (make-hash-table :test #'equal))))
      (when agent-ui--closing
        (remhash id agent-ui--closing))
      (agent-ui--dirty (list id))
      (agent-ui--closing-timer))))
