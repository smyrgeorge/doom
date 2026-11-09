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
(require 'svg)

(defconst agent-ui-timeline--statuses
  '((done agent-ui-accent) (running agent-ui-warning) (failed agent-ui-error) (queued agent-ui-muted))
  "Each status: its face.")

(defun agent-ui-timeline--time (value)
  "VALUE, seconds or a timestamp, as seconds (a float); nil if neither."
  (cond ((numberp value) (float value))
        ((stringp value)
         (ignore-errors (float-time (date-to-time value))))))

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
                            (when (and end (< end start))
                              (agent-ui--fail "timeline: task %d ends before it starts" i))
                            (when (and (plist-get task :status) (not (assq status agent-ui-timeline--statuses)))
                              (agent-ui--fail "timeline: task %d's status is running, done, failed or queued" i))
                            (list :name (plist-get task :name) :start start
                                  :end (or end (and duration (+ start duration)))
                                  :stamped (stringp (plist-get task :start))
                                  :status (or status (if (or end duration) 'done 'running))))))))
    (plist-put props :tasks tasks)))

(defun agent-ui-timeline--span (props)
  "The tasks' (FROM . TO), running ones ending now (or at the latest end)."
  (let* ((tasks (plist-get props :tasks))
         (from (apply #'min (mapcar (lambda (task) (plist-get task :start)) tasks)))
         (ends (delq nil (mapcar (lambda (task) (plist-get task :end)) tasks)))
         (now (if (seq-some (lambda (task) (plist-get task :stamped)) tasks) (float-time)
                (apply #'max from ends)))
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
             (name-width (min (apply #'max (mapcar (lambda (task) (string-width (plist-get task :name))) tasks))
                              (/ width 4)))
             (bar-width (max 10 (- width name-width 14)))
             (cell (lambda (time) (round (* bar-width (/ (- time from) length))))))
        (concat
         (mapconcat
          (lambda (task)
            (let* ((end (agent-ui-timeline--end task span))
                   (a (min (1- bar-width) (funcall cell (plist-get task :start))))
                   (b (max (1+ a) (funcall cell end)))
                   (status (plist-get task :status))
                   (face (cadr (assq status agent-ui-timeline--statuses))))
              (concat (agent-ui-pad (plist-get task :name) name-width) "  "
                      (make-string a ?\s)
                      (propertize (make-string (- b a) (if (eq status 'queued) ?░ ?█)) 'face face)
                      (make-string (max 0 (- bar-width b)) ?\s) "  "
                      (propertize (if (eq status 'running) "running"
                                    (agent-ui-format-duration (- end (plist-get task :start))))
                                  'face (if (eq status 'failed) 'agent-ui-error 'agent-ui-muted)))))
          (seq-take tasks agent-ui-max-rows) "\n")
         "\n"
         ;; The scale: its start, middle and end.
         (propertize
          (let ((mid (agent-ui-format-duration (/ length 2)))
                (end (agent-ui-format-duration length)))
            (concat (make-string (+ name-width 2) ?\s)
                    (agent-ui-pad "0s" (- (/ bar-width 2) (/ (string-width mid) 2)))
                    (agent-ui-pad mid (- bar-width (- (/ bar-width 2) (/ (string-width mid) 2)) (string-width end)))
                    end))
          'face 'agent-ui-muted))))))

(defun agent-ui-timeline--gui (props ctx)
  (let ((tasks (plist-get props :tasks)))
    (if (null tasks)
        (agent-ui-timeline--text props ctx)
      (let* ((cw (plist-get ctx :char-width)) (lh (plist-get ctx :line-height))
             (span (agent-ui-timeline--span props))
             (from (car span)) (length (- (cdr span) from))
             (name-width (* cw (+ 2 (min (apply #'max (mapcar (lambda (task) (string-width (plist-get task :name))) tasks))
                                          (/ (plist-get ctx :width) 4)))))
             (width (* cw (plist-get ctx :width)))
             (bar-left name-width) (bar-width (- width name-width (* 10 cw)))
             (row (round (* 1.4 lh)))
             (shown (seq-take tasks agent-ui-max-rows))
             (svg (svg-create width (+ (* row (length shown)) lh)))
             (fg (agent-ui-chart--color 'default)) (muted (agent-ui-chart--color 'agent-ui-muted))
             (x-of (lambda (time) (+ bar-left (* bar-width (/ (- time from) length))))))
        (cl-loop for task in shown
                 for i from 0
                 do (let* ((y (* i row)) (end (agent-ui-timeline--end task span))
                           (status (plist-get task :status))
                           (x0 (funcall x-of (plist-get task :start))) (x1 (max (+ x0 2) (funcall x-of end))))
                      (agent-ui-chart--svg-text svg ctx (plist-get task :name) 0 (+ y (* 0.7 row)) :fill fg)
                      (svg-rectangle svg x0 (+ y (* 0.2 row)) (- x1 x0) (* 0.6 row) :rx 2
                                     :fill (agent-ui-chart--color (cadr (assq status agent-ui-timeline--statuses)))
                                     :fill-opacity (if (eq status 'queued) 0.5 1))
                      (agent-ui-chart--svg-text svg ctx (if (eq status 'running) "running"
                                                          (agent-ui-format-duration (- end (plist-get task :start))))
                                                (+ x1 (/ cw 2)) (+ y (* 0.7 row)) :fill muted)))
        (let ((y (+ (* row (length shown)) (* 0.8 lh))))
          (agent-ui-chart--svg-text svg ctx "0s" bar-left y :fill muted)
          (agent-ui-chart--svg-text svg ctx (agent-ui-format-duration length) (+ bar-left bar-width) y
                                    :fill muted :text-anchor "end"))
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
