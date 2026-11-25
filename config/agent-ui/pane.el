;;; $DOOMDIR/config/agent-ui/pane.el -*- lexical-binding: t; -*-
;; Agent UI in its session's pane: the pane split, the conversation on top,
;; Agent UI at the bottom, its views (the session's canvas and its others:
;; ask, tests...) laid out to use the room: columns, each a stack of views
;; (see THE LAYOUT). Loaded from config/agent-ui.el, after agent.el. No Doom
;; here (see docs/agent-ui.md).
;;
;; - Its height: what its views need (its tallest column: its views' text,
;;   their bars and the bar under them), no empty lines under them; at least
;;   `agent-ui-pane-min-lines', at most half the pane
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
  "The fewest columns a view of Agent UI gets (see THE LAYOUT)."
  :type 'natnum :group 'agent-ui)

(defcustom agent-ui-grid-wide-width 80
  "The fewest columns a view showing a wide type gets
\(`agent-ui-grid-wide-types', see THE LAYOUT)."
  :type 'natnum :group 'agent-ui)

(defcustom agent-ui-grid-wide-types '("diff" "code" "graph" "mermaid" "heatmap" "timeline" "compare")
  "The element types that want room across: a view showing one gets
`agent-ui-grid-wide-width'."
  :type '(repeat string) :group 'agent-ui)

(defcustom agent-ui-pane-keys "q close"
  "The keys said on the bar under Agent UI's views, at its right (nil: none)."
  :type '(choice (const nil) string) :group 'agent-ui)

(defvar agent-ui-pane-search-limit 200000
  "The most steps the search for the best layout takes (see THE LAYOUT): the
best found by then taken.")

(defvar agent-ui-pane-views-functions nil
  "Functions of a session (its buffer): more views of it, after its canvases
\(the agent workspace's: an agent's panels), canvases too.")

(defvar agent-ui-pane-change-functions nil
  "Functions called with a frame and a function of no argument, Agent UI's
own change of the frame's windows (its views laid out, fitted, taken out),
which they call, returning its value: the agent workspace's takes the sizes
it leaves as laid out (not a border dragged).")

(defvar-local agent-ui-pane-full nil
  "In a session: non-nil, its Agent UI takes its pane's whole room, the
conversation keeping `agent-ui-pane-min-lines', whatever its views need
\(the agent workspace's V: full size).")

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

(defvar-local agent-ui--pane-plan nil
  "In a session: its Agent UI's columns as last planned, each a list of its
views (canvases), top to bottom (see THE LAYOUT).")

(defvar-local agent-ui--pane-settled nil
  "In a session: non-nil once its Agent UI was planned again after its views
were drawn at their widths (see THE LAYOUT).")

(defvar agent-ui--pane-settling nil
  "Non-nil while Agent UI is laid out again once settled (see THE LAYOUT).")

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

(defun agent-ui--pane-sessions (&optional frame)
  "The sessions with canvases (live buffers), and FRAME's windows' buffers
with views from `agent-ui-pane-views-functions'."
  (let (sessions)
    (dolist (canvas (agent-ui-canvases))
      (let ((session (buffer-local-value 'agent-ui--session-buffer canvas)))
        (when (and (buffer-live-p session) (not (memq session sessions)))
          (push session sessions))))
    (when (and frame agent-ui-pane-views-functions)
      (dolist (window (window-list frame 'nomini))
        (let ((buffer (window-buffer window)))
          (unless (or (memq buffer sessions) (agent-ui-pane-window-p window))
            (when (agent-ui--pane-more-views buffer)
              (push buffer sessions))))))
    sessions))

(defun agent-ui--pane-more-views (session)
  "SESSION's views from `agent-ui-pane-views-functions': live canvases."
  (seq-filter (lambda (view) (and (buffer-live-p view)
                                  (eq (buffer-local-value 'major-mode view) 'agent-ui-canvas-mode)))
              (mapcan (lambda (fn) (copy-sequence (funcall fn session))) agent-ui-pane-views-functions)))

(defun agent-ui--pane-views (session)
  "SESSION's views: its canvases showing something and not dismissed (see
above), its own first, its others by name, then its views from
`agent-ui-pane-views-functions' (not dismissed); none while its Agent UI is
hidden."
  (unless (buffer-local-value 'agent-ui--pane-hidden session)
    (let ((shown (lambda (canvas)
                   (with-current-buffer canvas
                     (not (or agent-ui--pane-dismissed (agent-ui--empty-p)))))))
      (append
       (sort (seq-filter shown (agent-ui-session-canvases session))
             (lambda (a b)
               (let ((first (buffer-local-value 'agent-ui--canvas-part a))
                     (second (buffer-local-value 'agent-ui--canvas-part b)))
                 (cond ((null first) (and second t))
                       ((null second) nil)
                       (t (string< first second))))))
       (seq-filter (lambda (view) (not (buffer-local-value 'agent-ui--pane-dismissed view)))
                   (agent-ui--pane-more-views session))))))

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
  "The session of the view WINDOW shows (nil: none): the one its window
parameter names (a panel of an agent is no session's canvas), else its
canvas's."
  (let* ((named (window-parameter window 'agent-ui-pane))
         (session (if (stringp named)
                      (get-buffer named)
                    (buffer-local-value 'agent-ui--session-buffer (window-buffer window)))))
    (and (buffer-live-p session) session)))

(defun agent-ui--pane-cells (frame &optional session)
  "FRAME's views' windows (SESSION's only), in order."
  (seq-filter (lambda (window)
                (and (agent-ui-pane-window-p window)
                     (or (null session) (eq (agent-ui--pane-cell-session window) session))))
              (agent-ui--pane-windows frame)))

;; ====== THE LAYOUT ======
;; A masonry: columns side by side, each a stack of views. For each count of
;; columns, the views are dealt into them: the session's own first, in the
;; first column; then the others, the tallest first, each into the column
;; with the fewest lines so far (the leftmost of those); each column's views
;; in their order. Dealt so, and also with the views showing a wide type
;; going only into the columns allowed to be wide, every set of columns tried
;; (two wide views in two columns took 80 + 80 and left no room for four
;; columns, both in one did). Each count's best deal then improved: a view
;; moved to another column (its own gone if left empty), or two swapped,
;; while that lowers the score. That's a good layout, not always the best
;; (10 lines off, now and then): the best is then searched for, every way to
;; group the views into columns, the tallest placed first, a grouping given
;; up as soon as its tallest column so far, its width or a column's views
;; rule it out against the best found (the good layout the first), at most
;; `agent-ui-pane-search-limit' steps (the best found by then). Of those layouts, each view at least its width
;; (`agent-ui-grid-min-width'; showing a wide type, `agent-ui-grid-wide-width')
;; and no column holding more views than it has room for (3 lines each), the
;; one with the least height and room left empty together (its tallest
;; column's lines, and the lines left empty under the others, on average: a
;; line more beats half of two columns empty); then the least room left
;; empty; then the fewest columns (wider views). The
;; room left across is shared out between the columns. Planned when the views
;; change (opened, closed), not when their content does: their heights only
;; fitted then (see ITS HEIGHT), nothing moving around while the agent works.
;; Once, though, after they're laid out: a new view is measured as drawn at
;; the default width, its size changes once drawn at its column's; measured
;; again then, a layout better by more than half a line made (a ninth view
;; left it 5 lines off the best). At most 10 views.

(defun agent-ui--pane-view-width (view)
  "The fewest columns VIEW needs (see above)."
  (if (with-current-buffer view
        (seq-some (lambda (key)
                    (member (plist-get (agent-ui--entry-element (gethash key agent-ui--entries)) :type)
                            agent-ui-grid-wide-types))
                  agent-ui--order))
      agent-ui-grid-wide-width
    agent-ui-grid-min-width))

(defun agent-ui--pane-view-lines (view window)
  "The lines VIEW needs as WINDOW shows text (its frame's font): its text,
charts and images as high as they're drawn (an image is one line of text,
many on the screen), its dirty elements drawn first; and its bar."
  (with-current-buffer view
    (agent-ui--flush))
  (1+ (/ (float (cdr (buffer-text-pixel-size view window)))
         (frame-char-height (window-frame window)))))

(defun agent-ui--pane-deal (lines count &optional allowed)
  "The views (indices into LINES, their lines) dealt into COUNT columns (see
above): lists of indices, each column's in their order. ALLOWED, a function
of a view's index and a column's: non-nil if the view may go there (default:
any); nil if a view has no column it may go in."
  (let ((sums (make-vector count 0))
        (columns (make-vector count nil))
        (allowed (or allowed #'always)))
    (when (funcall allowed 0 0)
      (aset columns 0 (list 0))
      (aset sums 0 (car lines))
      (catch 'none
        ;; `sort' is stable: views as tall in their order.
        (dolist (index (sort (number-sequence 1 (1- (length lines)))
                             (lambda (a b) (> (nth a lines) (nth b lines)))))
          (let ((target nil))
            (dotimes (column count)
              (when (and (funcall allowed index column)
                         (or (null target) (< (aref sums column) (aref sums target))))
                (setq target column)))
            (unless target
              (throw 'none nil))
            (aset columns target (cons index (aref columns target)))
            (aset sums target (+ (aref sums target) (nth index lines)))))
        ;; A column left empty (the wide views kept out of it): none, as
        ;; with fewer columns.
        (delq nil (mapcar (lambda (column) (sort column #'<)) (append columns nil)))))))

(defun agent-ui--pane-subsets (count)
  "Every set of the numbers 0 to COUNT - 1 but the empty one: lists."
  (cl-loop for mask from 1 below (ash 1 count)
           collect (cl-loop for bit below count
                            unless (zerop (logand mask (ash 1 bit))) collect bit)))

(defun agent-ui--pane-deals (lines widths count)
  "The ways views needing LINES and WIDTHS are dealt into COUNT columns (see
above): any column allowed for any view; and, with views showing a wide
type, those allowed only in each set of columns."
  (let ((wide (cl-loop for width in widths for index from 0
                       when (> width agent-ui-grid-min-width) collect index)))
    (delq nil
          (cons (agent-ui--pane-deal lines count)
                (when wide
                  (mapcar (lambda (wide-columns)
                            (agent-ui--pane-deal
                             lines count
                             (lambda (index column)
                               (or (not (memq index wide)) (memq column wide-columns)))))
                          (agent-ui--pane-subsets count)))))))

(defun agent-ui--pane-score (columns lines widths width most)
  "COLUMNS' score (see above), views needing LINES and WIDTHS in WIDTH
columns and MOST lines: (KEY NEEDS HEIGHT), KEY lower is better, NEEDS each
column's width, HEIGHT the tallest column's lines; nil if they don't fit."
  (let* ((pick (lambda (list column) (mapcar (lambda (index) (nth index list)) column)))
         (needs (mapcar (lambda (column) (apply #'max (funcall pick widths column))) columns))
         (heights (mapcar (lambda (column) (apply #'+ (funcall pick lines column))) columns))
         (height (apply #'max heights))
         (count (length columns)))
    (when (and (<= (apply #'+ needs) width)
               (<= (* 3 (apply #'max (mapcar #'length columns))) most))
      ;; The least height and room left empty together (see above), then
      ;; the least room left empty, then the fewest columns.
      (let ((empty (- (* height count) (apply #'+ heights))))
        (list (list (+ height (/ (float empty) count)) empty count) needs height)))))

(defun agent-ui--pane-moved (columns view from to)
  "COLUMNS with VIEW moved from column FROM to column TO, FROM gone if left
empty; each column's views in their order. New lists: COLUMNS' are shared
by the other candidates (`sort' changes the list it's given)."
  (delq nil (cl-loop for column in columns
                     for index from 0
                     collect (cond ((= index from) (remq view column))
                                   ((= index to) (sort (cons view (copy-sequence column)) #'<))
                                   (t (copy-sequence column))))))

(defun agent-ui--pane-swapped (columns view from other to)
  "COLUMNS with VIEW (of column FROM) and OTHER (of column TO) swapped; new
lists (see `agent-ui--pane-moved')."
  (cl-loop for column in columns
           for index from 0
           collect (cond ((= index from) (sort (cons other (copy-sequence (remq view column))) #'<))
                         ((= index to) (sort (cons view (copy-sequence (remq other column))) #'<))
                         (t (copy-sequence column)))))

(defun agent-ui--pane-neighbours (columns)
  "COLUMNS with a view moved to another column, or two of different columns
swapped (see above); the session's own (0) staying in the first."
  (let ((count (length columns))
        result)
    (dotimes (from count)
      (dolist (view (nth from columns))
        (unless (= view 0)
          (dotimes (to count)
            (unless (= to from)
              (push (agent-ui--pane-moved columns view from to) result)))
          (cl-loop for to from (1+ from) below count
                   do (dolist (other (nth to columns))
                        (unless (= other 0)
                          (push (agent-ui--pane-swapped columns view from other to) result)))))))
    (nreverse result)))

(defun agent-ui--pane-improve (columns lines widths width most)
  "COLUMNS improved (see above): their neighbours tried while one lowers the
score, the first such taken; (COLUMNS . SCORE)."
  (let ((score (agent-ui--pane-score columns lines widths width most))
        (better t)
        (passes 0))
    (while (and better score (< passes 50))
      (setq better nil
            passes (1+ passes))
      (catch 'taken
        (dolist (neighbour (agent-ui--pane-neighbours columns))
          (let ((its (agent-ui--pane-score neighbour lines widths width most)))
            (when (and its (agent-ui--pane-key< (car its) (car score)))
              (setq columns neighbour
                    score its
                    better t)
              (throw 'taken nil))))))
    (cons columns score)))

(defun agent-ui--pane-search (lines widths width most bound)
  "The best columns for views needing LINES and WIDTHS in WIDTH columns and
MOST lines (see above), better than BOUND, a score's key (nil: none);
every grouping searched, the tallest views placed first, groupings given up
once they can't beat the best found. (COLUMNS . SCORE), or nil if none
beats BOUND."
  (let* ((count (length lines))
         (heights (vconcat lines))
         (needs (vconcat widths))
         (most-columns (min count (max 1 (/ width (max 1 agent-ui-grid-min-width)))))
         (room (max 1 (/ most 3)))
         (order (cons 0 (sort (number-sequence 1 (1- count))
                              (lambda (a b) (> (aref heights a) (aref heights b))))))
         (columns (make-vector most-columns nil))
         (sums (make-vector most-columns 0))
         (widest (make-vector most-columns 0))
         (sizes (make-vector most-columns 0))
         (total (apply #'+ lines))
         (best-key bound)
         (best nil)
         (steps 0))
    (catch 'enough
      (named-let place ((rest order) (used 0) (tallest 0) (across 0))
        (cl-incf steps)
        (when (> steps agent-ui-pane-search-limit)
          (throw 'enough nil))
        (if (null rest)
            (let* ((empty (- (* tallest used) total))
                   (key (list (+ tallest (/ (float empty) used)) empty used)))
              (when (or (null best-key) (agent-ui--pane-key< key best-key))
                (setq best-key key
                      best (cl-loop for column below used
                                    collect (sort (copy-sequence (aref columns column)) #'<)))))
          (let ((view (car rest)))
            ;; Into each column used so far, or one more (one: the new ones
            ;; are all alike).
            (dotimes (column (min (1+ used) most-columns))
              (let* ((new (= column used))
                     (sum (+ (aref sums column) (aref heights view)))
                     (wide (max (aref widest column) (aref needs view)))
                     (across* (+ (- across (aref widest column)) wide))
                     (tallest* (max tallest sum)))
                (when (and (<= across* width)
                           (< (aref sizes column) room)
                           ;; The tallest column only grows: can't beat the best.
                           (or (null best-key) (< tallest* (car best-key)))
                           (or (not new) (> view 0) (= column 0)))
                  (let ((saved (list (aref columns column) (aref sums column)
                                     (aref widest column) (aref sizes column))))
                    (aset columns column (cons view (aref columns column)))
                    (aset sums column sum)
                    (aset widest column wide)
                    (aset sizes column (1+ (aref sizes column)))
                    (place (cdr rest) (if new (1+ used) used) tallest* across*)
                    (aset columns column (nth 0 saved))
                    (aset sums column (nth 1 saved))
                    (aset widest column (nth 2 saved))
                    (aset sizes column (nth 3 saved))))))))))
    (when best
      (cons best (agent-ui--pane-score best lines widths width most)))))

(defun agent-ui--pane-plan (lines widths width most)
  "The layout (see above) of views needing LINES (lines each, their bars)
and WIDTHS (columns each) in WIDTH columns and MOST lines: (COLUMNS WIDTHS
HEIGHT), each column a list of its views' indices, top to bottom, each
column's width (WIDTH shared out), the tallest column's lines; nil if none
fits."
  (let (best)
    (cl-loop
     for count from 1 to (min (length lines) (max 1 (/ width (max 1 agent-ui-grid-min-width))))
     do (let (dealt)
          ;; This count's best deal...
          (dolist (columns (agent-ui--pane-deals lines widths count))
            (let ((score (agent-ui--pane-score columns lines widths width most)))
              (when (and score (or (null dealt) (agent-ui--pane-key< (car score) (car (cdr dealt)))))
                (setq dealt (cons columns score)))))
          ;; ... improved.
          (when dealt
            (let ((improved (agent-ui--pane-improve (car dealt) lines widths width most)))
              (when (or (null best) (agent-ui--pane-key< (car (cdr improved)) (car (cdr best))))
                (setq best improved))))))
    ;; The best, if the good one isn't.
    (when-let* ((found (agent-ui--pane-search lines widths width most (car (cdr best)))))
      (setq best found))
    (when best
      (pcase-let* ((`(,columns (,_ ,needs ,height)) (list (car best) (cdr best)))
                   (count (length columns))
                   (left (- width (apply #'+ needs))))
        (list columns
              (cl-loop for need in needs
                       for index from 0
                       collect (+ need (/ left count) (if (< index (% left count)) 1 0)))
              height)))))

(defun agent-ui--pane-key< (a b)
  "Non-nil if A comes before B, lists of numbers compared in order."
  (catch 'done
    (cl-loop for x in a
             for y in b
             do (cond ((< x y) (throw 'done t))
                      ((> x y) (throw 'done nil))))
    nil))

(defun agent-ui--pane-build (area plan)
  "AREA, a window, split as PLAN says (`agent-ui--pane-plan'): its columns
at their widths, each its views stacked; the windows, column by column, top
to bottom."
  (pcase-let* ((`(,columns-planned ,widths ,_) plan)
               (sizes (mapcar #'length columns-planned))
               (window-min-height 2)
               (window-min-width 4)
               (columns (list area))
               (cells nil))
    (dolist (width (butlast widths))
      (let ((last (car (last columns))))
        (setq columns (append columns (list (split-window last width 'right))))))
    (cl-loop for column in columns
             for size in sizes
             do (let ((here (list column)))
                  (dotimes (placed (1- size))
                    ;; Its first split: a stack of its own (one column: not
                    ;; beside the conversation in its pane's group). Each
                    ;; view its share: the last window keeps one, the next
                    ;; ones below it (halving it each time left the fifth
                    ;; of five too small).
                    (let* ((window-combination-limit (null (cdr here)))
                           (last (car (last here)))
                           (share (max window-min-height (/ (window-total-height last) (- size placed)))))
                      (setq here (append here (list (split-window last share 'below))))))
                  (setq cells (append cells here))))
    cells))

;; ====== ITS WINDOWS ======

(defun agent-ui-pane-view-name (view)
  "VIEW's name: its part's (\"tests\"), a panel's, else Canvas (the
session's own canvas: Agent UI is the bar's under the views)."
  (or (buffer-local-value 'agent-ui--canvas-part view)
      (and (boundp 'agent-ui-panels--state)
           (when-let* ((panel (buffer-local-value 'agent-ui-panels--state view)))
             (agent-ui-panels--name panel)))
      "Canvas"))

(defun agent-ui--pane-bar (view)
  "VIEW's bar, a header line: its name (see `agent-ui-pane-view-name')."
  (list (propertize (concat " " (string-replace "%" "%%" (agent-ui-pane-view-name view)))
                    'face 'agent-ui-pane-bar-name)))

;; THE BAR UNDER ITS VIEWS
;; Agent UI's own, as the session's mode line is the conversation's: what it
;; is (its views, how many) and its keys (`agent-ui-pane-keys'). No window
;; spans the layout: each column's last view's mode line (all at its bottom)
;; drawn as one line, the leftmost's saying what it is, the rightmost's ending
;; with the keys (one column: both), the others' the bar only; in its own
;; face, the same whichever window is selected.
(defun agent-ui--pane-footer (count left right)
  "The mode line of a view at the layout's bottom, COUNT views in all (see
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
(its name), no tab line; the mode lines of those at the bottom Agent UI's
bar (see above), the others none; closing one dismisses its view (see
above)."
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

(defun agent-ui--pane-show-in (cell view session)
  "VIEW, a canvas, in CELL, a window of the layout of SESSION's views (its
parameter names it: kept with a workspace's windows)."
  (set-window-dedicated-p cell nil)
  (set-window-buffer cell view)
  (set-window-prev-buffers cell nil)
  (set-window-next-buffers cell nil)
  (set-window-parameter cell 'agent-ui-pane (buffer-name session)))

(defun agent-ui--pane-attach (window views)
  "VIEWS (canvases) in WINDOW's pane, a session's: WINDOW split, its bottom
part (as high as they need, see above) a grid of them, a group of their own. Their
windows; nil without room (WINDOW as it was)."
  (let* ((height (window-total-height window))
         (width (window-total-width window))
         (most (agent-ui--pane-most height (window-buffer window)))
         (views (seq-take views 10))
         plan)
    ;; More views than room: the last ones not shown.
    (while (and views
                (not (setq plan (agent-ui--pane-plan (mapcar (lambda (view) (agent-ui--pane-view-lines view window))
                                                             views)
                                                     (mapcar #'agent-ui--pane-view-width views)
                                                     width most))))
      (setq views (butlast views)))
    (let ((lines (and plan (if (buffer-local-value 'agent-ui-pane-full (window-buffer window))
                               most
                             (min most (max agent-ui-pane-min-lines (1+ (ceiling (nth 2 plan)))))))))
      (when (and plan (>= (- height lines) agent-ui-pane-min-lines))
        (when-let* ((area (condition-case nil
                              (let ((window-combination-limit t))
                                (split-window window (- lines) 'below))
                            (error nil))))
          (let* ((cells (condition-case nil
                            (agent-ui--pane-build area plan)
                          (error nil)))
                 (session (window-buffer window))
                 (columns (mapcar (lambda (column) (mapcar (lambda (index) (nth index views)) column))
                                  (car plan))))
            (if (not cells)
                ;; Half built (no room after all): what it made deleted, the
                ;; session's window as it was (they stayed, showing the
                ;; session, more at each try: 18 windows of it).
                (let ((ignore-window-parameters t))
                  (when-let* ((made (window-next-sibling window)))
                    (delete-window made))
                  nil)
              (cl-mapc (lambda (cell view) (agent-ui--pane-show-in cell view session))
                       cells (apply #'append columns))
              (agent-ui--pane-decorate window cells)
              (set-window-parameter window 'delete-window #'agent-ui--pane-delete-session-window)
              (with-current-buffer session
                (setq agent-ui--pane-plan columns
                      agent-ui--pane-height nil
                      agent-ui--pane-settled agent-ui--pane-settling))
              ;; As high as each needs now; again once drawn at their widths.
              (agent-ui--pane-fit window session)
              (agent-ui--pane-tops cells)
              (agent-ui--pane-fit-soon session)
              cells)))))))

;; ====== ITS HEIGHT (see above) ======

(defun agent-ui--pane-share (&optional session)
  "The most of its pane SESSION's Agent UI takes: all of it with
`agent-ui-pane-full', else `agent-ui-pane-max-share'."
  (if (and session (buffer-local-value 'agent-ui-pane-full session)) 1.0 agent-ui-pane-max-share))

(defun agent-ui--pane-most (pane &optional session)
  "The most lines Agent UI takes in a session's pane PANE lines high (of
SESSION: `agent-ui--pane-share'), the conversation keeping its fewest."
  (max agent-ui-pane-min-lines
       (min (round (* (agent-ui--pane-share session) pane)) (- pane agent-ui-pane-min-lines))))

;; Once shown, measured in pixels, as Emacs shows them: each view's text
;; (charts and images as high as they're drawn), its bars, its divider. Each
;; view as high as that in its column, the column's last one the rest; Agent
;; UI as high as its tallest column, within its least and most (held at its
;; most: a column's views each their share).

(defun agent-ui--pane-columns (cells)
  "CELLS, the views' windows of the layout, by column, left to right, each
top to bottom: lists."
  (let (columns)
    (dolist (cell cells)
      (let* ((left (car (window-pixel-edges cell)))
             (column (assq left columns)))
        (if column
            (setcdr column (append (cdr column) (list cell)))
          (push (list left cell) columns))))
    (mapcar (lambda (column)
              (sort (cdr column) (lambda (a b) (< (nth 1 (window-pixel-edges a)) (nth 1 (window-pixel-edges b))))))
            (sort columns (lambda (a b) (< (car a) (car b)))))))

(defun agent-ui--pane-cell-need (cell)
  "The pixels CELL, a view's window, needs: its view's text as shown (its
dirty elements drawn first), and the bars and divider around it."
  (with-current-buffer (window-buffer cell)
    (agent-ui--flush)
    (+ (cdr (window-text-pixel-size cell (point-min) (point-max)))
       (- (window-pixel-height cell) (window-body-height cell t)))))

(defun agent-ui--pane-fit (window session)
  "SESSION's Agent UI, in WINDOW's pane, as high as what it shows needs
\(see above), each view as high as its own in its column, if that changed
since it was last given its height."
  (when-let* ((area (window-next-sibling window))
              (cells (agent-ui--pane-cells (window-frame window) session))
              ((agent-ui--pane-in-place-p window cells)))
    (let* ((columns (agent-ui--pane-columns cells))
           (needs (mapcar (lambda (column) (mapcar #'agent-ui--pane-cell-need column)) columns))
           (pane (+ (window-pixel-height window) (window-pixel-height area)))
           (line (frame-char-height (window-frame window)))
           (least (* agent-ui-pane-min-lines line))
           (most (max least (min (round (* (agent-ui--pane-share session) pane)) (- pane least))))
           (height (if (buffer-local-value 'agent-ui-pane-full session)
                       most
                     (min most (max least (apply #'max (mapcar (lambda (n) (apply #'+ n)) needs))))))
           (wanted (cons height needs)))
      (unless (equal wanted (buffer-local-value 'agent-ui--pane-height session))
        (with-current-buffer session
          (setq agent-ui--pane-height wanted))
        (let ((window-resize-pixelwise t)
              ;; A view of a line and its bar is 2 lines: Emacs's least (4)
              ;; left empty lines under it.
              (window-min-height 1)
              (delta (- height (window-pixel-height area))))
          (unless (zerop delta)
            (ignore-errors (window-resize area delta nil nil t)))
          ;; In each column, each view its height, the last one the rest;
          ;; more than there's room for, each its share.
          (cl-loop for column in columns
                   for column-needs in needs
                   do (let* ((sum (apply #'+ column-needs))
                             (scale (if (> sum height) (/ (float height) sum) 1.0)))
                        (cl-loop for cell in (butlast column)
                                 for need in column-needs
                                 do (ignore-errors
                                      (adjust-window-trailing-edge
                                       cell (- (floor (* scale need)) (window-pixel-height cell)) nil t))))))))))

(defvar agent-ui--pane-fit-timer nil)

(defvar agent-ui--pane-to-fit nil
  "The sessions whose Agent UI is fitted to what it shows, soon.")

(defun agent-ui--pane-settle (window session)
  "SESSION's Agent UI, in WINDOW's pane, planned again once its views are
drawn at their widths (see THE LAYOUT): laid out again if that's better by
more than half a line; once."
  (unless (buffer-local-value 'agent-ui--pane-settled session)
    (with-current-buffer session
      (setq agent-ui--pane-settled t))
    (let* ((views (agent-ui--pane-views session))
           (shown (buffer-local-value 'agent-ui--pane-plan session))
           (index (lambda (view) (seq-position views view)))
           (now (mapcar (lambda (column) (mapcar index column)) shown)))
      (unless (seq-some (lambda (column) (memq nil column)) now)
        (let* ((lines (mapcar (lambda (view) (agent-ui--pane-view-lines view window)) views))
               (widths (mapcar #'agent-ui--pane-view-width views))
               (area (window-next-sibling window))
               (width (window-total-width window))
               (most (agent-ui--pane-most (+ (window-total-height window)
                                             (if area (window-total-height area) 0))
                                          session))
               (current (agent-ui--pane-score now lines widths width most))
               (plan (agent-ui--pane-plan lines widths width most))
               (better (and plan (agent-ui--pane-score (car plan) lines widths width most))))
          (when (and current better (< (car (car better)) (- (car (car current)) 0.5)))
            (let ((agent-ui--pane-settling t))
              (agent-ui--pane-detach (window-frame window) session)
              (agent-ui--pane-attach window views))))))))

(defun agent-ui--pane-fit-now ()
  "The sessions waiting, their Agent UI fitted (`agent-ui--pane-fit'),
planned again once settled (`agent-ui--pane-settle')."
  (setq agent-ui--pane-fit-timer nil)
  (let ((sessions agent-ui--pane-to-fit))
    (setq agent-ui--pane-to-fit nil)
    (dolist (session sessions)
      (when-let* (((buffer-live-p session))
                  (window (agent-ui--pane-session-window session)))
        (with-demoted-errors "Agent UI, its height: %S"
          (agent-ui--pane-changing
           (window-frame window)
           (lambda ()
             (agent-ui--pane-settle window session)
             (when (window-live-p window)
               (agent-ui--pane-fit window session)))))))))

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
does, in the columns last planned for its session (a view closed: the
others left where they were, laid out again)."
  (when-let* ((area (window-next-sibling window)))
    (and (window-combined-p window)
         (null (window-next-sibling area))
         (seq-every-p (lambda (cell) (agent-ui--pane-under-p cell area)) cells)
         (= (length cells)
            (seq-count (lambda (other) (agent-ui--pane-under-p other area))
                       (agent-ui--pane-windows (window-frame window))))
         (equal (mapcar (lambda (column) (mapcar #'window-buffer column)) (agent-ui--pane-columns cells))
                (buffer-local-value 'agent-ui--pane-plan (window-buffer window))))))

(defun agent-ui--pane-sync-window (window session)
  "SESSION's Agent UI in WINDOW's pane as it should be: its views in a grid
below it (made again if they aren't), or none. Non-nil if they're shown."
  (let ((views (agent-ui--pane-views session))
        (cells (agent-ui--pane-cells (window-frame window) session)))
    (if (and cells
             (seq-set-equal-p (mapcar #'window-buffer cells) views)
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
          (agent-ui--pane-changing frame (lambda () (agent-ui--pane-sync-frame frame)))
          (when (and view (not (agent-ui-pane-window-p (selected-window))))
            (when-let* ((window (get-buffer-window view frame)))
              (when (agent-ui-pane-window-p window)
                (select-window window 'norecord)))))))))

(defun agent-ui--pane-sync-frame (frame)
  "FRAME's sessions' panes as they should be (see `agent-ui--pane-sync')."
  (let* ((agent-ui--pane-syncing t)
         (shown (agent-ui--pane-session-windows frame (agent-ui--pane-sessions frame))))
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

;; ====== ITS OWN CHANGES, AND ANOTHER'S LAYOUT ======
;; Agent UI's own changes of a frame's windows go through
;; `agent-ui-pane-change-functions' (the agent workspace's stage takes them as
;; its own); another's layout (the stage's) takes its windows out first
;; (`agent-ui-pane-detach') and puts them in its pane after
;; (`agent-ui-pane-attach-window').

(defun agent-ui--pane-changing (frame change)
  "CHANGE, a function of no argument, Agent UI's own change of FRAME's
windows, through `agent-ui-pane-change-functions' (the first outermost); its
value."
  (funcall (seq-reduce (lambda (inner around)
                         (if (functionp around) (lambda () (funcall around frame inner)) inner))
                       (reverse agent-ui-pane-change-functions)
                       change)))

(defun agent-ui-pane-detach (frame)
  "Agent UI's views' windows out of FRAME (another's layout coming)."
  (let ((agent-ui--pane-syncing t))
    (agent-ui--pane-detach frame)))

(defun agent-ui-pane-attach-window (window session)
  "SESSION's Agent UI laid out in WINDOW's pane now (another's layout
showing SESSION in WINDOW); its views' windows."
  (let ((agent-ui--pane-syncing t))
    (save-current-buffer
      (agent-ui--pane-sync-window window session)))
  (agent-ui--pane-cells (window-frame window) session))

(defun agent-ui-pane-cells (frame session)
  "SESSION's views' windows in FRAME, in order."
  (agent-ui--pane-cells frame session))

(defun agent-ui-pane-window-session (window)
  "The session whose view WINDOW shows, if it's one of Agent UI's views."
  (and (window-live-p window) (agent-ui-pane-window-p window) (agent-ui--pane-cell-session window)))

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
