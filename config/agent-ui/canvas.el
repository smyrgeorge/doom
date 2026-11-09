;;; $DOOMDIR/config/agent-ui/canvas.el -*- lexical-binding: t; -*-
;; Agent UI's canvas: a buffer per agent session holding the elements it shows,
;; in the order shown, each redrawn in place when it changes. Loaded from
;; config/agent-ui.el, after core.el. No Doom here (see docs/agent-ui.md).
;;
;; Each element is the text between two markers, a blank line after it. A new
;; element is drawn at once; an update marks it dirty, and a timer redraws the
;; dirty ones `agent-ui-redraw-delay' later, so a stream of updates costs a
;; few redraws. Animated elements (a spinner) are redrawn by a timer of the
;; canvas while there are any. Elements are checked when given: a wrong one is
;; an error to the caller, not a drawing.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-ui-redraw-delay 0.1
  "Seconds between an element's update and its redraw: updates within it are
drawn together."
  :type 'number :group 'agent-ui)

(defcustom agent-ui-animation-interval 0.15
  "Seconds between frames of animated elements (a spinner)."
  :type 'number :group 'agent-ui)

(defcustom agent-ui-default-width 80
  "The width elements are drawn at while their canvas isn't in a window."
  :type 'natnum :group 'agent-ui)

(defcustom agent-ui-max-elements 100
  "The most elements a canvas holds; showing one more is an error."
  :type 'natnum :group 'agent-ui)

(defcustom agent-ui-default-canvas "default"
  "The canvas used when none is named."
  :type 'string :group 'agent-ui)

(defcustom agent-ui-display-function #'agent-ui-display-canvas
  "Called with a canvas's buffer when a new element is shown in it while it's
in no window: shows it, without selecting it."
  :type 'function :group 'agent-ui)

(defvar agent-ui-canvas-hook nil
  "Run in a canvas's buffer once it's made.")

(cl-defstruct (agent-ui--entry (:constructor agent-ui--make-entry))
  "An element of a canvas: its id, itself (a plist), where it's drawn."
  id element start end)

(defvar-local agent-ui--canvas-name nil "This canvas's name.")
(defvar-local agent-ui--entries nil "This canvas's elements, by id.")
(defvar-local agent-ui--order nil "This canvas's elements' ids, in order.")
(defvar-local agent-ui--dirty nil "Ids of the elements to redraw.")
(defvar-local agent-ui--redraw-timer nil)
(defvar-local agent-ui--animation-timer nil)
(defvar-local agent-ui--tick 0 "Counts animation frames.")
(defvar-local agent-ui--width nil "The width its elements were drawn at.")
(defvar-local agent-ui--counter 0 "For ids made for elements shown without one.")

;; ====== THE BUFFER ======

(defvar-keymap agent-ui-canvas-mode-map
  :doc "Keys of an Agent UI canvas."
  "g" #'agent-ui-canvas-redraw)

(define-derived-mode agent-ui-canvas-mode special-mode "Agent UI"
  "What a coding agent shows: its elements, updated as they change.

\\{agent-ui-canvas-mode-map}"
  (setq-local truncate-lines t
              buffer-undo-list t
              cursor-in-non-selected-windows nil)
  (setq agent-ui--entries (make-hash-table :test #'equal))
  (add-hook 'window-size-change-functions #'agent-ui--size-changed nil t)
  (add-hook 'kill-buffer-hook #'agent-ui--stop-timers nil t))

(defun agent-ui-canvas-buffer-name (name)
  (format "Agent UI: %s" name))

(defun agent-ui-canvas (&optional name)
  "The canvas named NAME (default `agent-ui-default-canvas'), its buffer: made
if there's none."
  (let* ((name (or name agent-ui-default-canvas))
         (buffer (get-buffer-create (agent-ui-canvas-buffer-name name))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'agent-ui-canvas-mode)
        (agent-ui-canvas-mode)
        (setq agent-ui--canvas-name name)
        (run-hooks 'agent-ui-canvas-hook)))
    buffer))

(defun agent-ui-canvases ()
  "The canvases' buffers."
  (seq-filter (lambda (b) (eq (buffer-local-value 'major-mode b) 'agent-ui-canvas-mode))
              (buffer-list)))

(defun agent-ui--buffer (canvas)
  "CANVAS's buffer: CANVAS a buffer, a canvas's name, or nil (the default)."
  (if (bufferp canvas)
      (if (and (buffer-live-p canvas)
               (eq (buffer-local-value 'major-mode canvas) 'agent-ui-canvas-mode))
          canvas
        (agent-ui--fail "%S isn't a live canvas" canvas))
    (agent-ui-canvas canvas)))

(defmacro agent-ui--in (canvas &rest body)
  "BODY in CANVAS's buffer (see `agent-ui--buffer')."
  (declare (indent 1))
  `(with-current-buffer (agent-ui--buffer ,canvas) ,@body))

(defun agent-ui-display-canvas (buffer)
  "Show BUFFER, a canvas, in another window, without selecting it."
  (display-buffer buffer '(nil (inhibit-same-window . t))))

;; ====== DRAWING ======

(defun agent-ui--window ()
  "A window showing the current canvas, the selected frame's first."
  (or (get-buffer-window (current-buffer))
      (get-buffer-window (current-buffer) t)))

(defun agent-ui--context ()
  "The context the current canvas's elements are drawn in (`agent-ui-context')."
  (let* ((window (agent-ui--window))
         (frame (if window (window-frame window) (selected-frame))))
    (agent-ui-context
     :width (if window
                ;; One column short: a line as wide as the window wraps in a
                ;; terminal.
                (max 10 (1- (window-max-chars-per-line window)))
              agent-ui-default-width)
     :graphic (display-graphic-p frame)
     :tick agent-ui--tick
     :char-width (frame-char-width frame)
     :line-height (frame-char-height frame))))

(defun agent-ui--draw (entry ctx)
  "Draw ENTRY again, in its place."
  (let ((inhibit-read-only t)
        (start (agent-ui--entry-start entry))
        (end (agent-ui--entry-end entry)))
    (save-excursion
      (delete-region start end)
      (goto-char start)
      (insert (propertize (agent-ui-render (agent-ui--entry-element entry) ctx)
                          'agent-ui-id (agent-ui--entry-id entry)))
      ;; The end follows what's inserted at it; the start stays before it.
      (set-marker end (point)))))

(defun agent-ui--flush ()
  "Redraw the current canvas's dirty elements."
  (when (timerp agent-ui--redraw-timer)
    (cancel-timer agent-ui--redraw-timer))
  (setq agent-ui--redraw-timer nil)
  (when agent-ui--dirty
    (let ((ctx (agent-ui--context))
          (dirty agent-ui--dirty))
      (setq agent-ui--dirty nil
            agent-ui--width (plist-get ctx :width))
      (dolist (id agent-ui--order)
        (when (member id dirty)
          (agent-ui--draw (gethash id agent-ui--entries) ctx)))))
  (agent-ui--animate))

(defun agent-ui--dirty (ids)
  "Redraw IDS of the current canvas `agent-ui-redraw-delay' from now (with
any others by then)."
  (dolist (id ids)
    (cl-pushnew id agent-ui--dirty :test #'equal))
  (unless agent-ui--redraw-timer
    (let ((buffer (current-buffer)))
      (setq agent-ui--redraw-timer
            (run-with-timer agent-ui-redraw-delay nil
                            (lambda ()
                              (when (buffer-live-p buffer)
                                (with-current-buffer buffer
                                  (agent-ui--flush)))))))))

(defun agent-ui-canvas-redraw (&optional canvas)
  "Redraw every element of CANVAS (default: the current buffer's) now."
  (interactive)
  (agent-ui--in (or canvas (current-buffer))
    (setq agent-ui--dirty (copy-sequence agent-ui--order))
    (agent-ui--flush)))

(defun agent-ui--size-changed (window)
  "Its window's width changed: draw the elements at the new width."
  (with-current-buffer (window-buffer window)
    (when (and agent-ui--order
               (not (equal agent-ui--width (plist-get (agent-ui--context) :width))))
      (agent-ui--dirty agent-ui--order))))

;; ====== ANIMATION ======

(defun agent-ui--animated-ids ()
  (seq-filter (lambda (id)
                (agent-ui-animated-p (agent-ui--entry-element (gethash id agent-ui--entries))))
              agent-ui--order))

(defun agent-ui--animate ()
  "Start the current canvas's animation timer if an element is animated, stop
it if none is."
  (if (agent-ui--animated-ids)
      (unless agent-ui--animation-timer
        (let ((buffer (current-buffer)))
          (setq agent-ui--animation-timer
                (run-with-timer agent-ui-animation-interval agent-ui-animation-interval
                                #'agent-ui--frame buffer))))
    (when (timerp agent-ui--animation-timer)
      (cancel-timer agent-ui--animation-timer))
    (setq agent-ui--animation-timer nil)))

(defun agent-ui--frame (buffer)
  "The next frame of BUFFER's animated elements, if it's in a window."
  (if (not (buffer-live-p buffer))
      nil
    (with-current-buffer buffer
      (if-let* ((ids (agent-ui--animated-ids)))
          (when (agent-ui--window)
            (cl-incf agent-ui--tick)
            (let ((ctx (agent-ui--context)))
              (dolist (id ids)
                (agent-ui--draw (gethash id agent-ui--entries) ctx))))
        (agent-ui--animate)))))

(defun agent-ui--stop-timers ()
  (dolist (timer (list agent-ui--redraw-timer agent-ui--animation-timer))
    (when (timerp timer)
      (cancel-timer timer)))
  (setq agent-ui--redraw-timer nil
        agent-ui--animation-timer nil))

;; ====== ELEMENTS ======

(defun agent-ui--entry (id)
  "The current canvas's element ID; an error naming the others if none."
  (or (and (stringp id) (gethash id agent-ui--entries))
      (agent-ui--fail "no element %s in canvas %s; its elements: %s"
                      (agent-ui--show-value id) agent-ui--canvas-name
                      (if agent-ui--order (string-join agent-ui--order ", ") "none"))))

(defun agent-ui--check-id (id)
  (unless (and (stringp id) (string-match-p "\\`[A-Za-z0-9_.-]+\\'" id))
    (agent-ui--fail "an id is letters, digits, -, _ or ., not %s" (agent-ui--show-value id))))

(defun agent-ui--new-id (type)
  (let (id)
    (while (gethash (setq id (format "%s-%d" type (cl-incf agent-ui--counter)))
                    agent-ui--entries))
    id))

(defun agent-ui--checked (element)
  "ELEMENT, if it's right (its type known, its properties right); else an
error saying what's wrong. Its :type a string, as JSON gives it."
  (let ((type (agent-ui-type (plist-get element :type))))
    (agent-ui-check type element)
    (let ((title (plist-get element :title)))
      (when (and title (not (stringp title)))
        (agent-ui--fail "a title is text, not %s" (agent-ui--show-value title))))
    (plist-put (copy-sequence element) :type (symbol-name (agent-ui-type-name type)))))

(cl-defun agent-ui-show (element &key canvas)
  "Show ELEMENT (a plist: :type, :id, :title, its type's properties) in
CANVAS (a buffer or a name; default `agent-ui-default-canvas'). An element
with its id there already is replaced in its place; a new one goes at the
end, drawn at once, and the canvas is shown if it's in no window
\(`agent-ui-display-function'). Without an id, one is made. Returns the id.
Signals `agent-ui-error' if ELEMENT is wrong."
  (agent-ui--in canvas
    (let* ((element (agent-ui--checked element))
           (id (or (plist-get element :id)
                   (agent-ui--new-id (plist-get element :type))))
           (element (plist-put element :id id))
           (entry (progn (agent-ui--check-id id) (gethash id agent-ui--entries))))
      (if entry
          (progn
            (setf (agent-ui--entry-element entry) element)
            (agent-ui--dirty (list id)))
        (when (>= (length agent-ui--order) agent-ui-max-elements)
          (agent-ui--fail "canvas %s has %d elements, the most it holds: remove some"
                          agent-ui--canvas-name agent-ui-max-elements))
        (let ((inhibit-read-only t))
          (save-excursion
            (goto-char (point-max))
            (let ((start (point-marker)))
              (insert "\n\n")
              (setq entry (agent-ui--make-entry :id id :element element :start start
                                                :end (copy-marker start t)))))
          (puthash id entry agent-ui--entries)
          (setq agent-ui--order (append agent-ui--order (list id)))
          (unless (agent-ui--window)
            (funcall agent-ui-display-function (current-buffer)))
          (agent-ui--draw entry (agent-ui--context))
          (agent-ui--animate)))
      id)))

(cl-defun agent-ui-update (id patch &key canvas)
  "Change element ID of CANVAS by PATCH (see `agent-ui-merge'), redrawn
`agent-ui-redraw-delay' from now. Returns ID. Signals `agent-ui-error' if
there's no such element or the change makes it wrong (then it's unchanged)."
  (agent-ui--in canvas
    (let ((entry (agent-ui--entry id)))
      (setf (agent-ui--entry-element entry)
            (agent-ui--checked (agent-ui-merge (agent-ui--entry-element entry) patch)))
      (agent-ui--dirty (list id))
      id)))

(cl-defun agent-ui-append (id patch &key canvas)
  "Add PATCH's lists to element ID of CANVAS (see `agent-ui-append-to'), as
`agent-ui-update' changes it."
  (agent-ui--in canvas
    (let ((entry (agent-ui--entry id)))
      (setf (agent-ui--entry-element entry)
            (agent-ui--checked (agent-ui-append-to (agent-ui--entry-element entry) patch)))
      (agent-ui--dirty (list id))
      id)))

(cl-defun agent-ui-remove (id &key canvas)
  "Remove element ID from CANVAS. Returns ID."
  (agent-ui--in canvas
    (let ((entry (agent-ui--entry id))
          (inhibit-read-only t))
      ;; Its text and the blank line after it.
      (delete-region (agent-ui--entry-start entry)
                     (min (point-max) (+ (agent-ui--entry-end entry) 2)))
      (set-marker (agent-ui--entry-start entry) nil)
      (set-marker (agent-ui--entry-end entry) nil)
      (remhash id agent-ui--entries)
      (setq agent-ui--order (delete id agent-ui--order)
            agent-ui--dirty (delete id agent-ui--dirty))
      (agent-ui--animate)
      id)))

(cl-defun agent-ui-clear (&key canvas)
  "Remove every element from CANVAS."
  (agent-ui--in canvas
    (dolist (id (copy-sequence agent-ui--order))
      (agent-ui-remove id :canvas (current-buffer)))
    (let ((inhibit-read-only t))
      (erase-buffer))
    nil))

(cl-defun agent-ui-get (id &key canvas)
  "Element ID of CANVAS, a plist."
  (agent-ui--in canvas
    (copy-sequence (agent-ui--entry-element (agent-ui--entry id)))))

(cl-defun agent-ui-elements (&key canvas)
  "CANVAS's elements in order: plists (:id ID :type TYPE)."
  (agent-ui--in canvas
    (mapcar (lambda (id)
              (let ((element (agent-ui--entry-element (gethash id agent-ui--entries))))
                (list :id id :type (plist-get element :type))))
            agent-ui--order)))
