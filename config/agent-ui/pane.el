;;; $DOOMDIR/config/agent-ui/pane.el -*- lexical-binding: t; -*-
;; Agent UI in its session's pane: the pane split, the conversation on top,
;; Agent UI at the bottom, its views (the session's canvas and its others:
;; ask, tests...) in a grid. Loaded from config/agent-ui.el, after agent.el.
;; No Doom here (see docs/agent-ui.md).
;;
;; - Its height: what its views need (its rows, each as high as its tallest
;;   view, their bars and the bar under them), no empty lines under them; at
;;   least `agent-ui-pane-min-lines', at most half the pane
;;   (`agent-ui-pane-max-share'). Fitted when an element changes and at each
;;   window change (views closed or opened), but only when what it needs
;;   changes: a bar moving every second leaves it as it is, at a height you
;;   gave it too. A view whose content fits its window is shown from its top.
;; - A view is a window of its own (scrolled, selected on its own), without a
;;   tab line or a mode line: a bar with its name. Under them, Agent UI's
;;   bar: what it is, its keys. The session's mode line stays under the
;;   conversation, its window's own.
;; - The conversation and its views are a window group of their own: closing
;;   the conversation's window closes them; a window manager laying panes out
;;   takes them out first and puts them back after (tiling:
;;   `agent-ui-pane-around-layout', config/tiling.el).
;; - The views' windows are made again whenever they don't match (synced at
;;   each window change): a view shown or gone, the session in another
;;   window, or in none (Agent UI waits, shown with the session), a workspace
;;   switched to.
;; - A view whose window is closed while it shows something stays hidden
;;   until an element is shown in it (a new one, or one again; an update
;;   doesn't: a bar ticking would bring it back each second); q kills it. Agent UI hidden for a
;;   session (`agent-ui-pane-toggle') stays so until shown again, or until a
;;   question is to be answered.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-ui-pane-max-share 0.5
  "The most of its session's pane Agent UI takes when what it shows needs
more room (see above)."
  :type 'number :group 'agent-ui)

(defcustom agent-ui-pane-min-lines 6
  "The fewest lines the conversation and Agent UI each keep in a session's
pane: in a pane too short for both, a view opens in a pane of its own."
  :type 'natnum :group 'agent-ui)

(defcustom agent-ui-grid-min-width 40
  "The narrowest column of Agent UI's grid: fewer columns in a narrower pane."
  :type 'natnum :group 'agent-ui)

(defcustom agent-ui-pane-keys "q close"
  "The keys said on the bar under Agent UI's views, at its right (nil: none)."
  :type '(choice (const nil) string) :group 'agent-ui)

(defvar agent-ui-pane-skip-functions nil
  "Functions of a window showing a session: non-nil, Agent UI isn't shown in
its pane (the agent workspace's stage shows its crew's).")

(defface agent-ui-pane-bar '((t :inherit header-line))
  "A view's bar in its session's pane.")

(defface agent-ui-pane-bar-name '((t :inherit (bold agent-ui-pane-bar)))
  "A view's name on its bar.")

(defface agent-ui-pane-bar-keys '((t :inherit (shadow agent-ui-pane-bar)))
  "The keys on the first view's bar.")

(defvar-local agent-ui--pane-hidden nil
  "In a session: non-nil while its Agent UI is hidden (`agent-ui-pane-toggle').")

(defvar-local agent-ui--pane-dismissed nil
  "In a view: non-nil once its window was closed while it showed something:
not shown again until something new is (see above).")

(defvar-local agent-ui--pane-height nil
  "In a session: the height its Agent UI was last given, in pixels, and its
rows' (see above).")

(defvar agent-ui--pane-detaching nil
  "Non-nil while Agent UI takes its views' windows out itself (no view
closed by you).")

(defvar agent-ui--pane-syncing nil
  "Non-nil while the panes are synced.")

;; A view's window known again when a workspace's windows are made anew
;; (persp-mode keeps them writable).
(add-to-list 'window-persistent-parameters '(agent-ui-pane . writable))

;; ====== THE SESSIONS AND THEIR VIEWS ======

(defun agent-ui-pane-window-p (window)
  "Non-nil if WINDOW shows one of Agent UI's views in its session's pane
\(to a window manager, tiling's in config/tiling.el: not a pane)."
  (and (window-parameter window 'agent-ui-pane) t))

(defun agent-ui--pane-sessions ()
  "The sessions with canvases (live buffers)."
  (let (sessions)
    (dolist (canvas (agent-ui-canvases))
      (let ((session (buffer-local-value 'agent-ui--session-buffer canvas)))
        (when (and (buffer-live-p session) (not (memq session sessions)))
          (push session sessions))))
    sessions))

(defun agent-ui--pane-views (session)
  "SESSION's views: its canvases showing something and not dismissed (see
above), its own first, its others by name; none while its Agent UI is
hidden."
  (unless (buffer-local-value 'agent-ui--pane-hidden session)
    (sort (seq-filter (lambda (canvas)
                        (with-current-buffer canvas
                          (not (or agent-ui--pane-dismissed (agent-ui--empty-p)))))
                      (agent-ui-session-canvases session))
          (lambda (a b)
            (let ((first (buffer-local-value 'agent-ui--canvas-part a))
                  (second (buffer-local-value 'agent-ui--canvas-part b)))
              (cond ((null first) (and second t))
                    ((null second) nil)
                    (t (string< first second))))))))

(defun agent-ui--pane-session-p (window)
  "Non-nil if WINDOW may hold Agent UI for the session it shows: a window
of a frame's own (not a child frame's, nor a side panel), not a view, not
one `agent-ui-pane-skip-functions' leave out."
  (and (window-live-p window)
       (not (agent-ui-pane-window-p window))
       (not (window-parameter window 'window-side))
       (not (frame-parent (window-frame window)))
       (not (run-hook-with-args-until-success 'agent-ui-pane-skip-functions window))))

(defun agent-ui--pane-windows (frame)
  "FRAME's windows, in order: top to bottom, left to right."
  (window-list frame 'nomini (frame-first-window frame)))

(defun agent-ui--pane-session-windows (frame sessions)
  "FRAME's windows holding Agent UI for one of SESSIONS: ((WINDOW .
SESSION)...), each session's first window only."
  (let (found)
    (dolist (window (agent-ui--pane-windows frame))
      (let ((buffer (window-buffer window)))
        (when (and (memq buffer sessions)
                   (not (rassq buffer found))
                   (agent-ui--pane-session-p window))
          (push (cons window buffer) found))))
    (nreverse found)))

(defun agent-ui--pane-session-window (session)
  "The window holding SESSION's Agent UI: the selected frame's first, else
another visible frame's; nil if it's in none."
  (seq-find #'agent-ui--pane-session-p
            (append (get-buffer-window-list session 'nomini nil)
                    (get-buffer-window-list session 'nomini 'visible))))

(defun agent-ui--pane-cell-session (window)
  "The session of the view WINDOW shows (nil: none)."
  (let ((session (buffer-local-value 'agent-ui--session-buffer (window-buffer window))))
    (and (buffer-live-p session) session)))

(defun agent-ui--pane-cells (frame &optional session)
  "FRAME's views' windows (SESSION's only), in order."
  (seq-filter (lambda (window)
                (and (agent-ui-pane-window-p window)
                     (or (null session) (eq (agent-ui--pane-cell-session window) session))))
              (agent-ui--pane-windows frame)))

;; ====== THE GRID ======
;; Columns as many as fit, `agent-ui-grid-min-width' each, but no more than
;; the square root of the views' count (two side by side, three as two and
;; one, four as two by two); rows filled in turn, the last one's views
;; sharing its width. Rows at equal heights, a row's views at equal widths.

(defun agent-ui--pane-grid-shape (count width)
  "(COLUMNS . ROWS) of the grid of COUNT views in WIDTH columns (see above)."
  (let ((columns (max 1 (min count (ceiling (sqrt count)) (/ width agent-ui-grid-min-width)))))
    (cons columns (ceiling count columns))))

(defun agent-ui--pane-grid (area count)
  "AREA, a window, split into a grid of COUNT windows (see above), a window
combination of its own; the windows, row by row, left to right."
  (pcase-let* ((`(,columns . ,rows) (agent-ui--pane-grid-shape count (window-total-width area)))
               (window-min-height 2)
               (window-min-width 4)
               (row-windows (list area))
               (cells nil)
               (grid nil))
    (dotimes (_ (1- rows))
      (let ((window-combination-limit (null (cdr row-windows))))
        (setq row-windows (append row-windows
                                  (list (split-window (car (last row-windows)) nil 'below))))))
    (when (cdr row-windows)
      (setq grid (window-parent area)))
    (let ((left count))
      (dolist (row row-windows)
        (let ((here (list row)))
          (dotimes (_ (1- (min columns left)))
            (setq here (append here (list (split-window (car (last here)) nil 'right)))))
          (unless grid
            (setq grid (and (cdr here) (window-parent row))))
          (setq left (- left (length here))
                cells (append cells here)))))
    (when grid
      (balance-windows grid))
    cells))

;; ====== ITS WINDOWS ======

(defun agent-ui--pane-bar (view)
  "VIEW's bar, a header line: its name (the session's own canvas: Agent UI)."
  (list (propertize (concat " " (string-replace "%" "%%" (or (buffer-local-value 'agent-ui--canvas-part view)
                                                              "Agent UI")))
                    'face 'agent-ui-pane-bar-name)))

;; THE BAR UNDER ITS VIEWS
;; Agent UI's own, as the session's mode line is the conversation's: what it
;; is (its views, how many) and its keys (`agent-ui-pane-keys'). No window
;; spans the grid: the bottom row's views' mode lines are drawn as one line,
;; the leftmost's saying what it is, the rightmost's ending with the keys (one
;; view across: both), the others' the bar only; in its own face, the same
;; whichever window is selected.
(defun agent-ui--pane-footer (count left right)
  "The mode line of a view in the grid's bottom row, COUNT views in all (see
above): LEFT, the leftmost (what Agent UI is); RIGHT, the rightmost (the
keys)."
  (let ((keys (and right agent-ui-pane-keys (string-replace "%" "%%" agent-ui-pane-keys))))
    (list (if left
              (propertize (if (> count 1) (format " Agent UI · %d views" count) " Agent UI")
                          'face 'agent-ui-pane-bar-name)
            "")
          (propertize " " 'display `(space :align-to (- right ,(if keys (1+ (string-width keys)) 0)))
                      'face 'agent-ui-pane-bar)
          (if keys (propertize keys 'face 'agent-ui-pane-bar-keys) ""))))

(defun agent-ui--pane-set (window parameter value)
  "WINDOW's PARAMETER set to VALUE, unless it is already."
  (unless (equal (window-parameter window parameter) value)
    (set-window-parameter window parameter value)))

(defun agent-ui--pane-decorate (window cells)
  "CELLS, the views' windows in WINDOW's pane (a session's): each its bar
(its name), no tab line; the bottom row's mode lines Agent UI's bar (see
above), the others none; closing one dismisses its view (see above)."
  (let* ((bottom (nth 3 (window-edges (window-next-sibling window))))
         (row (sort (seq-filter (lambda (cell) (= (nth 3 (window-edges cell)) bottom)) cells)
                    (lambda (a b) (< (car (window-edges a)) (car (window-edges b)))))))
    (dolist (cell cells)
      (agent-ui--pane-set cell 'tab-line-format 'none)
      (agent-ui--pane-set cell 'header-line-format (agent-ui--pane-bar (window-buffer cell)))
      (agent-ui--pane-set cell 'mode-line-format
                          (if (memq cell row)
                              (agent-ui--pane-footer (length cells) (eq cell (car row)) (eq cell (car (last row))))
                            'none))
      (set-window-parameter cell 'delete-window #'agent-ui--pane-delete-cell)
      (set-window-dedicated-p cell t))))

(defun agent-ui--pane-tops (cells)
  "Each of CELLS whose view fits it shown from its top: none of it hidden
above, room left under it (shrunk, then grown again, a window kept its
start)."
  (dolist (cell cells)
    (when (window-live-p cell)
      (with-current-buffer (window-buffer cell)
        (when (and (> (window-start cell) (point-min))
                   (<= (count-lines (point-min) (point-max)) (window-body-height cell)))
          (set-window-start cell (point-min) t))))))

(defun agent-ui--pane-show-in (cell view)
  "VIEW, a canvas, in CELL, a window of the grid."
  (set-window-dedicated-p cell nil)
  (set-window-buffer cell view)
  (set-window-prev-buffers cell nil)
  (set-window-next-buffers cell nil)
  (set-window-parameter cell 'agent-ui-pane t))

(defun agent-ui--pane-attach (window views)
  "VIEWS (canvases) in WINDOW's pane, a session's: WINDOW split, its bottom
part (as high as they need, see above) a grid of them, a group of their own. Their
windows; nil without room (WINDOW as it was)."
  (let* ((height (window-total-height window))
         (width (window-total-width window))
         (views (agent-ui--pane-fitting views (agent-ui--pane-most height) width))
         (lines (and views (agent-ui--pane-lines height views width))))
    (when (and views (>= (- height lines) agent-ui-pane-min-lines))
      (when-let* ((area (condition-case nil
                            (let ((window-combination-limit t))
                              (split-window window (- lines) 'below))
                          (error nil))))
        (let ((cells (agent-ui--pane-grid area (length views))))
          (cl-mapc #'agent-ui--pane-show-in cells views)
          (agent-ui--pane-decorate window cells)
          (agent-ui--pane-tops cells)
          (set-window-parameter window 'delete-window #'agent-ui--pane-delete-session-window)
          ;; Drawn at their width now: measured again then, as shown.
          (with-current-buffer (window-buffer window)
            (setq agent-ui--pane-height nil))
          (agent-ui--pane-fit-soon (window-buffer window))
          cells)))))

;; ====== ITS HEIGHT (see above) ======

(defun agent-ui--pane-most (pane)
  "The most lines Agent UI takes in a session's pane PANE lines high, the
conversation keeping its fewest."
  (max agent-ui-pane-min-lines
       (min (round (* agent-ui-pane-max-share pane)) (- pane agent-ui-pane-min-lines))))

(defun agent-ui--pane-needs (views width)
  "The lines VIEWS need in a grid WIDTH columns wide: its rows, each as high
as its tallest view, its bar too, and the bar under them (their dirty
elements drawn first)."
  (let ((tallest 0))
    (dolist (view views)
      (with-current-buffer view
        (agent-ui--flush)
        (setq tallest (max tallest (1+ (count-lines (point-min) (point-max)))))))
    (1+ (* (cdr (agent-ui--pane-grid-shape (length views) width)) tallest))))

(defun agent-ui--pane-lines (pane views width)
  "The lines Agent UI takes in a session's pane PANE lines high, showing
VIEWS in a grid WIDTH wide (see above)."
  (min (agent-ui--pane-most pane)
       (max agent-ui-pane-min-lines (agent-ui--pane-needs views width))))

;; Once shown, measured in pixels, as Emacs shows them: each view's text
;; (charts and images as high as they're drawn), its bars, its divider. Each
;; row as high as its tallest view; Agent UI the rows' sum, within its least
;; and most (held at its most: the rows at equal heights).

(defun agent-ui--pane-rows (cells)
  "CELLS, the views' windows of a grid, by row, top to bottom: lists."
  (let (rows)
    (dolist (cell cells)
      (let* ((top (nth 1 (window-pixel-edges cell)))
             (row (assq top rows)))
        (if row
            (setcdr row (append (cdr row) (list cell)))
          (push (list top cell) rows))))
    (mapcar #'cdr (sort rows (lambda (a b) (< (car a) (car b)))))))

(defun agent-ui--pane-cell-need (cell)
  "The pixels CELL, a view's window, needs: its view's text as shown (its
dirty elements drawn first), and the bars and divider around it."
  (with-current-buffer (window-buffer cell)
    (agent-ui--flush)
    (+ (cdr (window-text-pixel-size cell (point-min) (point-max)))
       (- (window-pixel-height cell) (window-body-height cell t)))))

(defun agent-ui--pane-fit (window session)
  "SESSION's Agent UI, in WINDOW's pane, as high as what it shows needs
\(see above), each row as high as its tallest view, if that changed since
it was last given its height."
  (when-let* ((area (window-next-sibling window))
              (cells (agent-ui--pane-cells (window-frame window) session))
              ((agent-ui--pane-in-place-p window cells)))
    (let* ((rows (agent-ui--pane-rows cells))
           (needs (mapcar (lambda (row) (apply #'max (mapcar #'agent-ui--pane-cell-need row))) rows))
           (pane (+ (window-pixel-height window) (window-pixel-height area)))
           (line (frame-char-height (window-frame window)))
           (least (* agent-ui-pane-min-lines line))
           (most (max least (min (round (* agent-ui-pane-max-share pane)) (- pane least))))
           (total (apply #'+ needs))
           (height (min most (max least total)))
           (wanted (cons height needs)))
      (unless (equal wanted (buffer-local-value 'agent-ui--pane-height session))
        (with-current-buffer session
          (setq agent-ui--pane-height wanted))
        (let ((window-resize-pixelwise t)
              ;; A row of a line and its bar is 2 lines: Emacs's least (4)
              ;; left empty lines under it.
              (window-min-height 1)
              (delta (- height (window-pixel-height area))))
          (unless (zerop delta)
            (ignore-errors (window-resize area delta nil nil t)))
          (if (and (cdr rows) (= height total))
              ;; Each row its own height, the last one the rest.
              (cl-loop for row in (butlast rows)
                       for need in needs
                       do (let ((row-window (if (cdr row) (window-parent (car row)) (car row))))
                            (ignore-errors
                              (adjust-window-trailing-edge
                               row-window (- need (window-pixel-height row-window)) nil t))))
            (when (cdr rows)
              (balance-windows area))))))))

(defvar agent-ui--pane-fit-timer nil)

(defvar agent-ui--pane-to-fit nil
  "The sessions whose Agent UI is fitted to what it shows, soon.")

(defun agent-ui--pane-fit-now ()
  "The sessions waiting, their Agent UI fitted (`agent-ui--pane-fit')."
  (setq agent-ui--pane-fit-timer nil)
  (let ((sessions agent-ui--pane-to-fit))
    (setq agent-ui--pane-to-fit nil)
    (dolist (session sessions)
      (when-let* (((buffer-live-p session))
                  (window (agent-ui--pane-session-window session)))
        (with-demoted-errors "Agent UI, its height: %S"
          (agent-ui--pane-fit window session))))))

(defun agent-ui--pane-fit-soon (session)
  "SESSION's Agent UI fitted to what it shows once its views are drawn
\(`agent-ui-redraw-delay' after a change)."
  (cl-pushnew session agent-ui--pane-to-fit)
  (unless (timerp agent-ui--pane-fit-timer)
    (setq agent-ui--pane-fit-timer
          (run-with-timer (+ agent-ui-redraw-delay 0.05) nil #'agent-ui--pane-fit-now))))

(defun agent-ui--pane-changed-h ()
  "A canvas changed (`agent-ui-changed-hook'): its session's Agent UI fitted
to it again, soon."
  (when (buffer-live-p agent-ui--session-buffer)
    (agent-ui--pane-fit-soon agent-ui--session-buffer)))

(add-hook 'agent-ui-changed-hook #'agent-ui--pane-changed-h)

(defun agent-ui--pane-fitting (views lines width)
  "The first of VIEWS that fit in a grid LINES high and WIDTH wide, each row
at least 3 lines (its bar and two of its view's): the others not shown."
  (while (and (cdr views)
              (> (cdr (agent-ui--pane-grid-shape (length views) width)) (/ lines 3)))
    (setq views (butlast views)))
  views)

(defun agent-ui--pane-unattach (cell)
  "CELL, a view's window that can't go (the frame's last): a window like
any, showing its view."
  (set-window-dedicated-p cell nil)
  (dolist (parameter '(agent-ui-pane mode-line-format tab-line-format header-line-format delete-window))
    (set-window-parameter cell parameter nil)))

(defun agent-ui--pane-detach (frame &optional session)
  "Agent UI's views' windows out of FRAME (SESSION's only): deleted, their
room given back to their sessions."
  (let ((agent-ui--pane-detaching t))
    (dolist (cell (agent-ui--pane-cells frame session))
      (when (window-live-p cell)
        (condition-case nil
            (let ((ignore-window-parameters t))
              (delete-window cell))
          (error (agent-ui--pane-unattach cell)))))))

(defun agent-ui--pane-delete-cell (cell)
  "`delete-window' on a view's window (its parameter): deleted; its view, if
it still shows something, dismissed (see above), but when Agent UI takes its
windows out itself."
  (let ((view (window-buffer cell)))
    (unless (or agent-ui--pane-detaching (not (buffer-live-p view)))
      (with-current-buffer view
        (unless (agent-ui--empty-p)
          (setq agent-ui--pane-dismissed t)))))
  (let ((ignore-window-parameters t))
    (delete-window cell)))

(defun agent-ui--pane-delete-session-window (window)
  "`delete-window' on a session's window holding Agent UI (its parameter):
its views' windows deleted with it."
  (when-let* ((session (and (window-live-p window) (window-buffer window))))
    (agent-ui--pane-detach (window-frame window) session))
  (let ((ignore-window-parameters t))
    (delete-window window)))

;; ====== SYNCED ======

(defun agent-ui--pane-under-p (window ancestor)
  "Non-nil if WINDOW is ANCESTOR or inside it."
  (while (and window (not (eq window ancestor)))
    (setq window (window-parent window)))
  (eq window ancestor))

(defun agent-ui--pane-in-place-p (window cells)
  "Non-nil if CELLS fill the part of WINDOW's pane below it, and nothing else
does, in as many rows as a grid of them has (views closed: the others left
in the rows they were in, laid out again)."
  (when-let* ((area (window-next-sibling window)))
    (and (window-combined-p window)
         (null (window-next-sibling area))
         (seq-every-p (lambda (cell) (agent-ui--pane-under-p cell area)) cells)
         (= (length cells)
            (seq-count (lambda (other) (agent-ui--pane-under-p other area))
                       (agent-ui--pane-windows (window-frame window))))
         (= (length (delete-dups (mapcar #'window-top-line cells)))
            (cdr (agent-ui--pane-grid-shape (length cells) (window-total-width area)))))))

(defun agent-ui--pane-sync-window (window session)
  "SESSION's Agent UI in WINDOW's pane as it should be: its views in a grid
below it (made again if they aren't), or none. Non-nil if they're shown."
  (let ((views (agent-ui--pane-views session))
        (cells (agent-ui--pane-cells (window-frame window) session)))
    (if (and cells
             (equal (mapcar #'window-buffer cells) views)
             (agent-ui--pane-in-place-p window cells))
        (progn
          (agent-ui--pane-decorate window cells)
          (set-window-parameter window 'delete-window #'agent-ui--pane-delete-session-window)
          ;; As high as what it shows needs now (views closed: less).
          (agent-ui--pane-fit window session)
          (agent-ui--pane-tops cells)
          t)
      (when cells
        (agent-ui--pane-detach (window-frame window) session))
      (if views
          (and (agent-ui--pane-attach window views) t)
        (when (eq (window-parameter window 'delete-window) #'agent-ui--pane-delete-session-window)
          (set-window-parameter window 'delete-window nil))
        nil))))

(defun agent-ui--pane-sync (&optional frame)
  "FRAME's (the selected one's) sessions' panes as they should be (see
above): views of a session shown nowhere here, or hidden, taken out; each
session shown, its views in its pane."
  (let ((frame (or frame (selected-frame))))
    (when (and (not agent-ui--pane-syncing)
               (frame-live-p frame)
               (not (frame-parent frame)))
      ;; The current buffer and the view selected kept: a view's window made
      ;; again, deleted while selected, selected another (its buffer
      ;; current: a canvas's new element was drawn there).
      (save-current-buffer
        (let ((view (and (agent-ui-pane-window-p (selected-window)) (window-buffer (selected-window)))))
          (agent-ui--pane-sync-frame frame)
          (when (and view (not (agent-ui-pane-window-p (selected-window))))
            (when-let* ((window (get-buffer-window view frame)))
              (when (agent-ui-pane-window-p window)
                (select-window window 'norecord)))))))))

(defun agent-ui--pane-sync-frame (frame)
  "FRAME's sessions' panes as they should be (see `agent-ui--pane-sync')."
  (let* ((agent-ui--pane-syncing t)
         (shown (agent-ui--pane-session-windows frame (agent-ui--pane-sessions))))
    (dolist (cell (agent-ui--pane-cells frame))
      (when (window-live-p cell)
        (let ((session (agent-ui--pane-cell-session cell)))
          (cond
           ;; Not a canvas (a workspace's windows made again at startup, its
           ;; buffers gone): a window like any.
           ((not (eq (buffer-local-value 'major-mode (window-buffer cell)) 'agent-ui-canvas-mode))
            (agent-ui--pane-unattach cell))
           ((not (and session (rassq session shown)))
            (let ((agent-ui--pane-detaching t))
              (condition-case nil
                  (let ((ignore-window-parameters t))
                    (delete-window cell))
                (error (agent-ui--pane-unattach cell)))))))))
    (pcase-dolist (`(,window . ,session) shown)
      (when (window-live-p window)
        (agent-ui--pane-sync-window window session)))))

(defun agent-ui--pane-sync-h (frame)
  "A window change in FRAME (`window-state-change-functions'): its panes
synced; not while the minibuffer is open (its previews show other buffers
in panes for a moment, Agent UI would come and go with each): once it's
closed, a window change too."
  (unless (active-minibuffer-window)
    (with-demoted-errors "Agent UI, its views in their pane: %S"
      (agent-ui--pane-sync frame))))

(add-hook 'window-state-change-functions #'agent-ui--pane-sync-h)

;; ====== SHOWN ======

(defun agent-ui-pane-display (canvas)
  "Agent UI's display function (`agent-ui-display-function'): a session's
CANVAS in its session's pane, the grid laid out again (it waits while the
session is in no window, or while its Agent UI is hidden); in a pane of its
own if there's no room. Any other canvas: as `agent-ui-display-canvas'."
  (let ((session (buffer-local-value 'agent-ui--session-buffer canvas)))
    (if (not (buffer-live-p session))
        (agent-ui-display-canvas canvas)
      (with-current-buffer canvas
        (setq agent-ui--pane-dismissed nil))
      (when-let* ((window (agent-ui--pane-session-window session)))
        (agent-ui--pane-sync (window-frame window))
        (unless (or (buffer-local-value 'agent-ui--pane-hidden session)
                    (get-buffer-window canvas 'visible))
          (agent-ui-display-canvas canvas))))))

(defun agent-ui-pane-reveal (canvas)
  "CANVAS, in no window, shown for a question to be answered
\(`agent-ui-reveal-function'): a session's in its session's pane, its Agent
UI shown again if hidden, the session shown first if it's in no window; any
other canvas as Agent UI shows it."
  (let ((session (buffer-local-value 'agent-ui--session-buffer canvas)))
    (if (not (buffer-live-p session))
        (agent-ui--display canvas)
      (with-current-buffer session
        (setq agent-ui--pane-hidden nil))
      (with-current-buffer canvas
        (setq agent-ui--pane-dismissed nil))
      (unless (agent-ui--pane-session-window session)
        (display-buffer session))
      (if-let* ((window (agent-ui--pane-session-window session)))
          (progn
            (agent-ui--pane-sync (window-frame window))
            (unless (get-buffer-window canvas 'visible)
              (agent-ui-display-canvas canvas)))
        (agent-ui-display-canvas canvas)))))

(defun agent-ui--pane-shown-h (_key _element)
  "An element shown in a view (`agent-ui-shown-functions': new, or shown
again): the view back if its window was closed (see above)."
  (when agent-ui--pane-dismissed
    (setq agent-ui--pane-dismissed nil)
    (when-let* ((session agent-ui--session-buffer)
                ((buffer-live-p session))
                (window (agent-ui--pane-session-window session)))
      (agent-ui--pane-sync (window-frame window)))))

(add-hook 'agent-ui-shown-functions #'agent-ui--pane-shown-h)

;; ====== A WINDOW MANAGER LAYING PANES OUT ======

(defun agent-ui-pane-around-layout (layout)
  "A window manager's around function (tiling's, config/tiling.el): LAYOUT
done with Agent UI's views' windows out of the way, put back after; its
value. From a view, as from its session's window, the view selected again
after if the session still is."
  (let* ((frame (selected-frame))
         (from (selected-window))
         (view (and (agent-ui-pane-window-p from) (window-buffer from)))
         (session (and view (agent-ui--pane-cell-session from))))
    (when session
      (when-let* ((window (agent-ui--pane-session-window session)))
        (select-window window 'norecord)))
    (agent-ui--pane-detach frame)
    (unwind-protect
        (let ((agent-ui--pane-syncing t))
          (funcall layout))
      (when (frame-live-p frame)
        (agent-ui--pane-sync frame)
        (when (and view session (eq (window-buffer (selected-window)) session))
          (when-let* ((window (get-buffer-window view frame)))
            (when (agent-ui-pane-window-p window)
              (select-window window))))))))

;; ====== COMMANDS ======

(defun agent-ui--pane-current-session ()
  "The session of the current buffer: an agent's session itself, a
canvas's (a view's) session; nil if none."
  (cond ((buffer-live-p agent-ui--session-buffer) agent-ui--session-buffer)
        ((memq (current-buffer) (agent-ui--sessions)) (current-buffer))
        ((agent-ui-session-canvases (current-buffer)) (current-buffer))))

(defun agent-ui-pane-toggle ()
  "Hide Agent UI in this session's pane, or show it again: from the session,
or one of its views. Hidden, it stays so until shown again, or until a
question is to be answered."
  (interactive)
  (let ((session (agent-ui--pane-current-session)))
    (unless session
      (user-error "Not in an agent's session"))
    (let ((hide (not (buffer-local-value 'agent-ui--pane-hidden session))))
      (with-current-buffer session
        (setq agent-ui--pane-hidden hide))
      (unless hide
        (dolist (canvas (agent-ui-session-canvases session))
          (with-current-buffer canvas
            (setq agent-ui--pane-dismissed nil))))
      (when (and hide (agent-ui-pane-window-p (selected-window)))
        (when-let* ((window (agent-ui--pane-session-window session)))
          (select-window window)))
      (agent-ui--pane-sync)
      (message "%s" (cond (hide (substitute-command-keys
                                 "Agent UI hidden (\\[agent-ui-pane-toggle] shows it again)"))
                          ((agent-ui--pane-views session) "Agent UI shown")
                          (t "Agent UI shown (nothing on it yet)"))))))

(defun agent-ui-quit ()
  "Close this canvas for good, its elements with it (its buffer killed): in
its session's pane, its view gone, the others laid out again, the cursor in
the session; else its pane closed (`kill-current-buffer'). A session's saved
elements come back when it's resumed."
  (interactive)
  (if (agent-ui-pane-window-p (selected-window))
      (let ((session (agent-ui--pane-cell-session (selected-window))))
        (kill-buffer (current-buffer))
        (when-let* ((window (and session (agent-ui--pane-session-window session))))
          (select-window window)))
    (kill-current-buffer)))

;; ====== AGENT UI'S WAY OF SHOWING A SESSION'S CANVASES ======

(setq agent-ui-display-function #'agent-ui-pane-display
      agent-ui-reveal-function #'agent-ui-pane-reveal)
