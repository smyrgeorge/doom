;;; $DOOMDIR/config/agent-ui/elements/timeline.el -*- lexical-binding: t; -*-
;; Agent UI's timeline: tasks as bars on a time axis. Loaded from
;; config/agent-ui/elements.el.
;;
;; A task: {"name", "start", "end" or "duration", "status"}: START and END
;; seconds (from any origin), or timestamps (2026-11-09T12:01:00Z, as date
;; parses them); a task without END nor DURATION runs, until now (with
;; timestamps: growing, redrawn). STATUS running, done, failed, queued
;; colours it. Text: blocks per slice of time, a scale under them; GUI: SVG.
;; For CI jobs, parallel test shards, a trace's spans.
;;
;;   build   ████████                      8s
;;   test-1          ██████████████        14s
;;   test-2          ████████████▒▒▒       running
;;           0s                 12s        24s

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-timeline--statuses
  '((done agent-ui-success) (running agent-ui-accent) (failed agent-ui-error) (queued agent-ui-muted))
  "Each status: its face, as the other elements colour it (a checklist's
step, a graph's node): running blue, done green (running was yellow, the
colour of what needs you; done blue).")

(defun agent-ui-timeline--zero (end)
  "The scale's start, in the unit of its END label: 0ms or 0s."
  (if (string-suffix-p "ms" end) "0ms" "0s"))

(defun agent-ui-timeline--time (value)
  "VALUE, seconds or a timestamp, as seconds (a float); nil if neither. An
ISO 8601 timestamp keeps its fraction of a second (21:17:49.461Z), which
`date-to-time' drops (a task of 690 ms drawn as 1 s); another, as date
parses it."
  (cond ((numberp value) (float value))
        ((stringp value)
         (or (ignore-errors (float-time (encode-time (iso8601-parse value t))))
             (ignore-errors (float-time (date-to-time value)))))))

(defun agent-ui-timeline--check (props)
  (let ((tasks (cl-loop for task in (plist-get props :tasks)
                        for i from 1
                        collect
                        (progn
                          (unless (agent-ui--plist-p task)
                            (agent-ui--fail "timeline: task %d must be {\"name\": ..., \"start\": ...}" i))
                          (cl-loop for (k _) on task by #'cddr
                                   unless (memq k '(:name :start :end :duration :status))
                                   do (agent-ui--fail "timeline: task %d has %s: a task has name, start, end, duration, status"
                                                      i (agent-ui--show-value (substring (symbol-name k) 1))))
                          (unless (stringp (plist-get task :name))
                            (agent-ui--fail "timeline: task %d has no name" i))
                          (let ((start (agent-ui-timeline--time (plist-get task :start)))
                                (end (and (plist-get task :end) (agent-ui-timeline--time (plist-get task :end))))
                                (duration (plist-get task :duration))
                                (status (let ((s (plist-get task :status))) (if (stringp s) (intern-soft s) s))))
                            (unless start
                              (agent-ui--fail "timeline: task %d's start must be seconds or a timestamp" i))
                            (when (and (plist-get task :end) (not end))
                              (agent-ui--fail "timeline: task %d's end must be seconds or a timestamp" i))
                            (when (and duration (not (and (numberp duration) (>= duration 0))))
                              (agent-ui--fail "timeline: task %d's duration must be seconds" i))
                            (when (and (plist-get task :end)
                                       (not (eq (stringp (plist-get task :start)) (stringp (plist-get task :end)))))
                              (agent-ui--fail "timeline: task %d's start and end must both be seconds or both timestamps" i))
                            (when (and end (< end start))
                              (agent-ui--fail "timeline: task %d ends before it starts" i))
                            (when (and (plist-get task :status) (not (assq status agent-ui-timeline--statuses)))
                              (agent-ui--fail "timeline: task %d's status is running, done, failed or queued" i))
                            (list :name (plist-get task :name) :start start
                                  :end (or end (and duration (+ start duration)))
                                  :stamped (stringp (plist-get task :start))
                                  :status (or status (if (or end duration) 'done 'running))))))))
    ;; Seconds and timestamps together made nonsense (an axis of 249209h).
    (when (and (seq-some (lambda (task) (plist-get task :stamped)) tasks)
               (seq-some (lambda (task) (not (plist-get task :stamped))) tasks))
      (agent-ui--fail "timeline: tasks must all use seconds or all timestamps"))
    (plist-put props :tasks tasks)))

(defun agent-ui-timeline--span (props)
  "The tasks' (FROM . TO), running ones ending now (or at the latest end)."
  (let* ((tasks (plist-get props :tasks))
         (starts (mapcar (lambda (task) (plist-get task :start)) tasks))
         (from (apply #'min starts))
         (ends (delq nil (mapcar (lambda (task) (plist-get task :end)) tasks)))
         ;; Now only while a task given timestamps runs (no end): finished,
         ;; the axis stretched to now (yesterday's run over 22 hours).
         (now (if (seq-some (lambda (task) (and (plist-get task :stamped) (null (plist-get task :end)))) tasks)
                  (funcall agent-ui-clock)
                ;; The latest start too: a running task starting after the
                ;; last end lay past the axis (outside the SVG).
                (apply #'max from (append starts ends))))
         (to (apply #'max now ends)))
    (cons from (if (<= to from) (+ from 1) to))))

(defun agent-ui-timeline--end (task span)
  (or (plist-get task :end) (cdr span)))

(defun agent-ui-timeline--text (props ctx)
  (let* ((tasks (plist-get props :tasks))
         (width (plist-get ctx :width)))
    (if (null tasks)
        (propertize "no tasks" 'face 'agent-ui-muted)
      (let* ((span (agent-ui-timeline--span props))
             (from (car span)) (length (- (cdr span) from))
             (shown (seq-take tasks agent-ui-max-rows))
             (times (mapcar (lambda (task)
                              (if (eq (plist-get task :status) 'running) "running"
                                (agent-ui-format-time-taken (- (agent-ui-timeline--end task span) (plist-get task :start)))))
                            shown))
             (time-width (apply #'max (mapcar #'string-width times)))
             ;; The names' column shrinks first, then the bars, to a column
             ;; each (the bars were 10 at least: lines past narrow widths).
             ;; A third of the width at most (it was a quarter); a name longer
             ;; wrapped in it (it was cut with …, its rest nowhere).
             (name-width (max 1 (min (apply #'max (mapcar (lambda (task) (string-width (plist-get task :name))) tasks))
                                     (/ width 3)
                                     (- width 3 4 time-width))))
             ;; 10 columns kept for the times while the bars keep 10 (a time
             ;; changing, the bars don't move), else only what they take.
             (bar-width (if (>= (- width name-width 14) 10)
                            (- width name-width 14)
                          (max 1 (- width name-width 4 time-width))))
             (cell (lambda (time) (round (* bar-width (/ (- time from) length))))))
        (concat
         (mapconcat
          (lambda (task)
            (let* ((end (agent-ui-timeline--end task span))
                   (a (min (1- bar-width) (funcall cell (plist-get task :start))))
                   (b (max (1+ a) (funcall cell end)))
                   (status (plist-get task :status))
                   (face (cadr (assq status agent-ui-timeline--statuses)))
                   (names (if (<= (string-width (plist-get task :name)) name-width)
                              (list (plist-get task :name))
                            (agent-ui-wrap-lines (plist-get task :name) name-width))))
              (concat (agent-ui-pad (car names) name-width) "  "
                      (make-string a ?\s)
                      (propertize (make-string (- b a) (if (eq status 'queued) ?░ ?█)) 'face face)
                      (make-string (max 0 (- bar-width b)) ?\s) "  "
                      (propertize (nth (cl-position task shown) times)
                                  'face (if (eq status 'failed) 'agent-ui-error 'agent-ui-muted))
                      (mapconcat (lambda (n) (concat "\n" n)) (cdr names) ""))))
          shown "\n")
         "\n"
         ;; The scale: its start, middle and end, within the bars' width; the
         ;; middle only with a space each side, the end only if it fits after
         ;; the start (they ran together: \"0s  13s26s\").
         (propertize
          (let* ((mid (agent-ui-format-time-taken (/ length 2)))
                 (end (agent-ui-format-time-taken length))
                 (zero (agent-ui-timeline--zero end))
                 (mid-at (- (/ bar-width 2) (/ (string-width mid) 2)))
                 (end-at (- bar-width (string-width end)))
                 ;; Its start and a space before the next label (0ms one
                 ;; wider than 0s).
                 (room (1+ (string-width zero)))
                 (scale (cond
                         ((and (>= mid-at room) (>= end-at (+ mid-at (string-width mid) 1)))
                          (concat (agent-ui-pad zero mid-at) (agent-ui-pad mid (- end-at mid-at)) end))
                         ((>= end-at room) (concat (agent-ui-pad zero end-at) end))
                         (t (agent-ui-truncate zero bar-width)))))
            (concat (make-string (+ name-width 2) ?\s) scale))
          'face 'agent-ui-muted))))))

(defun agent-ui-timeline--gui (props ctx)
  (let ((tasks (plist-get props :tasks)))
    (if (null tasks)
        (agent-ui-timeline--text props ctx)
      (let* ((cw (plist-get ctx :char-width)) (lh (plist-get ctx :line-height))
             (span (agent-ui-timeline--span props))
             (from (car span)) (length (- (cdr span) from))
             (columns (plist-get ctx :width))
             ;; As in text: the names' column shrinks first, the bars keep a
             ;; column (they went to 0 and below: drawn over the names).
             (name-width (* cw (+ 2 (max 1 (min (apply #'max (mapcar (lambda (task) (string-width (plist-get task :name))) tasks))
                                                 (/ columns 3)
                                                 (- columns 3 10))))))
             (width (* cw columns))
             (bar-left name-width)
             (bar-width (if (>= (- width name-width (* 10 cw)) (* 10 cw))
                            (- width name-width (* 10 cw))
                          (max cw (- width name-width (* 9 cw)))))
             (row (round (* 1.4 lh)))
             (shown (seq-take tasks agent-ui-max-rows))
             ;; Each name wrapped in its column (cut, it was read only in
             ;; part), its row a line taller for each more.
             (names (mapcar (lambda (task)
                              (let ((room (max 1 (- (/ name-width cw) 2))))
                                (if (<= (string-width (plist-get task :name)) room)
                                    (list (plist-get task :name))
                                  (agent-ui-wrap-lines (plist-get task :name) room))))
                            shown))
             (ys (let ((y 0)) (mapcar (lambda (n) (prog1 y (setq y (+ y row (* lh (1- (length n))))))) names)))
             (bottom (if shown (+ (car (last ys)) row (* lh (1- (length (car (last names)))))) 0))
             (svg (svg-create width (+ bottom lh)))
             (fg (agent-ui-chart--color 'default)) (muted (agent-ui-chart--color 'agent-ui-muted))
             (x-of (lambda (time) (+ bar-left (* bar-width (/ (- time from) length))))))
        (cl-loop for task in shown
                 for y in ys
                 for name in names
                 do (let* ((end (agent-ui-timeline--end task span))
                           (status (plist-get task :status))
                           (x0 (funcall x-of (plist-get task :start))) (x1 (max (+ x0 2) (funcall x-of end))))
                      ;; In its column, wrapped (whole on one line, it ran
                      ;; under the bars; cut, it was read only in part).
                      (cl-loop for part in name
                               for i from 0
                               do (agent-ui-chart--svg-text svg ctx part 0 (+ y (* 0.7 row) (* i lh)) :fill fg))
                      (svg-rectangle svg x0 (+ y (* 0.2 row)) (- x1 x0) (* 0.6 row) :rx 2
                                     :fill (agent-ui-chart--color (cadr (assq status agent-ui-timeline--statuses)))
                                     :fill-opacity (if (eq status 'queued) 0.5 1))
                      ;; Its time, where it fits in the image.
                      (let ((time (if (eq status 'running) "running"
                                    (agent-ui-format-time-taken (- end (plist-get task :start))))))
                        (when (<= (+ x1 (/ cw 2) (* 0.5 lh (string-width time))) width)
                          (agent-ui-chart--svg-text svg ctx time (+ x1 (/ cw 2)) (+ y (* 0.7 row)) :fill muted)))))
        (let* ((y (+ bottom (* 0.8 lh)))
               (end (agent-ui-format-time-taken length))
               (zero (agent-ui-timeline--zero end)))
          (agent-ui-chart--svg-text svg ctx zero bar-left y :fill muted)
          ;; Its end, where it clears its start (they overlapped, narrow).
          (when (>= bar-width (* 0.5 lh (+ 1 (string-width zero) (string-width end))))
            (agent-ui-chart--svg-text svg ctx end (+ bar-left bar-width) y
                                      :fill muted :text-anchor "end")))
        (agent-ui-chart--image svg)))))

(agent-ui-define timeline
  "Tasks as bars on a time axis: {\"name\", \"start\", \"end\" or
\"duration\", \"status\"}, START and END seconds or timestamps; a task
without END nor DURATION runs until now (with timestamps, growing).
STATUS running, done, failed or queued colours it. For CI jobs, parallel
test shards, a trace's spans; update or append tasks as they go."
  :props ((tasks list "The tasks: {\"name\", \"start\", \"end\", \"duration\", \"status\"}"))
  :example (:title "CI"
            :tasks ((:name "build" :start 0 :duration 8)
                    (:name "test-1" :start 8 :duration 14)
                    (:name "test-2" :start 8 :duration 11 :status "failed")
                    (:name "deploy" :start 22 :duration 4 :status "queued")))
  :animated (lambda (props)
              (seq-some (lambda (task) (and (eq (plist-get task :status) 'running) (plist-get task :stamped)))
                        (plist-get props :tasks)))
  :check #'agent-ui-timeline--check
  :text #'agent-ui-timeline--text
  :gui #'agent-ui-timeline--gui)
