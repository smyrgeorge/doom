;;; $DOOMDIR/config/agent-ui/elements/steps.el -*- lexical-binding: t; -*-
;; Agent UI's checklist: steps whose state changes as work goes on. Loaded from
;; config/agent-ui/elements.el. Appending a step whose name is there changes
;; it in its place. A step may have steps of its own, drawn under it;
;; appended to by its "parent" name. Its time: how long it ran (from running
;; to done or failed, or given), counting while it runs.
;;
;;   ✓ Run the tests      41s  412 passed
;;   ▛ Build              12s
;;     ✓ compile           8s
;;     ▛ link              4s
;;   ○ Publish

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-steps--statuses '(pending running done failed skipped))

(defconst agent-ui-steps--keys '(:name :status :detail :seconds :started :steps)
  "What a step has (started: when it began running, noted).")

(defconst agent-ui-steps-max-depth 4
  "How deep steps nest.")

(defun agent-ui-steps--name (step)
  "STEP's name: STEP itself (a string), or its :name."
  (if (stringp step) step (and (agent-ui--plist-p step) (plist-get step :name))))

;; ====== CHECKING ======

(defun agent-ui-steps--normalize (step where depth)
  "STEP (\"name\", or (:name :status :detail :seconds :steps)) as a plist,
its status a symbol, its sub-steps too. An error naming WHERE (\"step 2\",
\"step 2.1\") if it's wrong; DEPTH, how deep it is (0: not a sub-step)."
  (cl-flet ((bad (what) (agent-ui--fail "steps: %s %s" where what)))
    (cond
     ((stringp step) (list :name step :status 'pending))
     ((agent-ui--plist-p step)
      (cl-loop for (k _) on step by #'cddr
               unless (memq k agent-ui-steps--keys)
               do (bad (format "has %s: a step has name, status, detail, seconds, steps"
                               (agent-ui--show-value (substring (symbol-name k) 1)))))
      (let* ((name (plist-get step :name))
             (status (or (plist-get step :status) "pending"))
             (sym (if (stringp status) (intern-soft status) status))
             (detail (plist-get step :detail))
             (seconds (plist-get step :seconds))
             (started (plist-get step :started))
             (steps (plist-get step :steps)))
        (unless (stringp name) (bad "has no name"))
        (unless (memq sym agent-ui-steps--statuses)
          (bad (format "has status %s; one of: pending, running, done, failed, skipped"
                       (agent-ui--show-value status))))
        (when (and detail (not (stringp detail)))
          (setq detail (agent-ui-cell detail)))
        (unless (or (null seconds) (and (numberp seconds) (>= seconds 0)))
          (bad (format "has seconds %s: a number, 0 or more" (agent-ui--show-value seconds))))
        (unless (or (null started) (numberp started))
          (bad (format "has started %s: a time, in seconds" (agent-ui--show-value started))))
        (unless (listp steps)
          (bad "has steps that aren't a list"))
        (when (and steps (> (+ depth 2) agent-ui-steps-max-depth))
          (bad (format "has steps %d deep: %d at most" (+ depth 2) agent-ui-steps-max-depth)))
        (append (list :name name :status sym)
                (when detail (list :detail detail))
                (when seconds (list :seconds seconds))
                (when started (list :started started))
                (when steps
                  (list :steps (cl-loop for s in steps
                                        for i from 1
                                        collect (agent-ui-steps--normalize
                                                 s (format "%s.%d" where i) (1+ depth))))))))
     (t (bad (format "is %s: a name, or {\"name\": ..., \"status\": ...}"
                     (agent-ui--show-value step)))))))

;; ====== ITS TIMES ======

(defun agent-ui-steps--timed (steps now)
  "STEPS (as given) with their times noted at NOW: when one began running;
how long it ran, once done or failed. A step noted already: as it is."
  (mapcar (lambda (step)
            (if (not (agent-ui--plist-p step))
                step
              (let ((status (format "%s" (or (plist-get step :status) "pending")))
                    (step (copy-sequence step)))
                (cond
                 ((and (equal status "running") (not (plist-get step :started)))
                  (setq step (plist-put step :started now)))
                 ((and (member status '("done" "failed")) (plist-get step :started)
                       (not (plist-get step :seconds)))
                  (setq step (plist-put step :seconds (- now (plist-get step :started))))))
                (if (listp (plist-get step :steps))
                    (plist-put step :steps (agent-ui-steps--timed (plist-get step :steps) now))
                  step))))
          steps))

;; ====== DRAWING ======

(defun agent-ui-steps--icon (status ctx)
  (pcase status
    ('done (propertize "✓" 'face 'agent-ui-success))
    ('failed (propertize "✗" 'face 'agent-ui-error))
    ('running (propertize (agent-ui-spinner ctx) 'face 'agent-ui-accent))
    ('skipped (propertize "–" 'face 'agent-ui-muted))
    (_ (propertize "○" 'face 'agent-ui-muted))))

(defun agent-ui-steps--flat (steps depth)
  "STEPS and their sub-steps, in order: ((DEPTH . STEP) ...)."
  (mapcan (lambda (step)
            (cons (cons depth step) (agent-ui-steps--flat (plist-get step :steps) (1+ depth))))
          steps))

(defun agent-ui-steps--time (step)
  "STEP's time as text: how long it ran, or has been running; \"\" if none."
  (let ((seconds (plist-get step :seconds))
        (started (plist-get step :started)))
    (cond
     ((memq (plist-get step :status) '(pending skipped)) "")
     (seconds (agent-ui-format-duration seconds))
     ((and started (eq (plist-get step :status) 'running))
      (agent-ui-format-duration (max 0 (- (funcall agent-ui-clock) started))))
     (t ""))))

(defun agent-ui-steps--one-line (text)
  "TEXT on one line: its line breaks as ⏎, its tabs as a space (a failing
test's detail ran onto lines of its own, at column 0)."
  (and text (replace-regexp-in-string "\t" " " (replace-regexp-in-string "\r?\n" "⏎" text))))

(defun agent-ui-steps--text (props ctx)
  (let* ((steps (plist-get props :steps))
         (all (agent-ui-steps--flat steps 0))
         (shown (mapcar (lambda (s)
                          (let ((step (copy-sequence (cdr s))))
                            (setq step (plist-put step :name (agent-ui-steps--one-line (plist-get step :name))))
                            (when (plist-get step :detail)
                              (setq step (plist-put step :detail (agent-ui-steps--one-line (plist-get step :detail)))))
                            (cons (car s) step)))
                        (seq-take all agent-ui-max-rows)))
         (width (plist-get ctx :width))
         (times (mapcar (lambda (s) (agent-ui-steps--time (cdr s))) shown))
         ;; The times' column, right-aligned; left out where it can't fit.
         (time-width (let ((w (apply #'max 0 (mapcar #'string-width times))))
                       (if (> (+ w 5) width) 0 w)))
         ;; The names' column, indents in it: no wider than the width leaves
         ;; (it was 10 at least: past the width under ~20 columns).
         (names (max 1 (min (apply #'max 0 (mapcar (lambda (s) (+ (* 2 (car s)) (string-width (plist-get (cdr s) :name))))
                                                   shown))
                            (max 10 (/ width 2))
                            (- width 4 time-width)))))
    (if (null steps)
        (propertize "no steps yet" 'face 'agent-ui-muted)
      (concat
       (mapconcat
        (lambda (pair)
          (let* ((depth (car (car pair)))
                 (step (cdr (car pair)))
                 (time (cdr pair))
                 (indent (make-string (* 2 depth) ?\s))
                 (status (plist-get step :status))
                 (detail (or (plist-get step :detail) ""))
                 (name (plist-get step :name))
                 (name (if (memq status '(pending skipped)) (propertize name 'face 'agent-ui-muted) name)))
            (if (and (string-empty-p detail) (= time-width 0))
                (concat indent (agent-ui-steps--icon status ctx) " "
                        (agent-ui-truncate name (max 1 (- width 2 (length indent)))))
              (string-trim-right
               (concat indent (agent-ui-steps--icon status ctx) " "
                       (agent-ui-pad name (max 1 (- names (length indent))))
                       (if (> time-width 0)
                           (concat "  " (propertize (agent-ui-pad time time-width 'right) 'face 'agent-ui-muted))
                         "")
                       (if (string-empty-p detail)
                           ""
                         (concat "  " (propertize (agent-ui-truncate
                                                   detail (max 0 (- width names time-width 6)))
                                                  'face (if (eq status 'failed) 'agent-ui-error 'agent-ui-muted)))))))))
        (cl-mapcar #'cons shown times) "\n")
       (when (> (length all) (length shown))
         (concat "\n" (propertize (format "… %d steps more" (- (length all) (length shown)))
                                  'face 'agent-ui-muted)))))))

;; ====== APPENDING ======

(defun agent-ui-steps--merge (steps new)
  "STEPS with NEW ones: one whose name is there changes it (its own steps
merged so too), the others after."
  (let ((steps (copy-sequence steps)))
    (dolist (step new)
      (let* ((name (agent-ui-steps--name step))
             (at (and name (cl-position name steps :key #'agent-ui-steps--name :test #'equal))))
        (if (not at)
            (setq steps (append steps (list step)))
          (let ((old (nth at steps)))
            (setf (nth at steps)
                  (cond
                   ((stringp step) old)
                   ((stringp old) step)
                   (t
                    ;; Running again (after done, failed...): timed anew,
                    ;; not with its last run's start and time.
                    (when (and (equal (format "%s" (plist-get step :status)) "running")
                               (not (equal (format "%s" (plist-get old :status)) "running"))
                               (not (plist-member step :started)))
                      (setq old (agent-ui--plist-delete (agent-ui--plist-delete old :started) :seconds)))
                    (cl-loop for (k v) on step by #'cddr
                               do (setq old (plist-put (copy-sequence old) k
                                                       (if (eq k :steps)
                                                           (agent-ui-steps--merge (plist-get old :steps) v)
                                                         v))))
                      old)))))))
    steps))

(defun agent-ui-steps--under (steps parent new)
  "STEPS with NEW merged into the sub-steps of the one named PARENT, at
any depth; nil if there's none."
  (let ((found nil))
    (cl-labels ((walk (steps)
                  (mapcar (lambda (step)
                            (cond
                             (found step)
                             ((equal (agent-ui-steps--name step) parent)
                              (setq found t)
                              (let ((step (if (stringp step) (list :name step) step)))
                                (plist-put (copy-sequence step) :steps
                                           (agent-ui-steps--merge (plist-get step :steps) new))))
                             ((and (agent-ui--plist-p step) (plist-get step :steps))
                              (plist-put (copy-sequence step) :steps (walk (plist-get step :steps))))
                             (t step)))
                          steps)))
      (let ((result (walk steps)))
        (and found result)))))

(defun agent-ui-steps--append (element patch)
  "ELEMENT with PATCH's steps: one whose name is there replaces it (its
status and detail changed, its steps merged), the others after; one with
a \"parent\" goes among that step's own."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :steps))
           do (agent-ui--fail "steps: only steps can be appended to"))
  (let ((steps (plist-get element :steps)))
    (dolist (step (plist-get patch :steps))
      (let ((parent (and (agent-ui--plist-p step) (plist-get step :parent))))
        (if (not parent)
            (setq steps (agent-ui-steps--merge steps (list step)))
          (setq steps (or (agent-ui-steps--under steps parent (list (agent-ui--plist-delete step :parent)))
                          (agent-ui--fail "steps: no step %s to put %s under"
                                          (agent-ui--show-value parent)
                                          (agent-ui--show-value (agent-ui-steps--name step))))))))
    (plist-put (copy-sequence element) :steps steps)))

(agent-ui-define steps
  "A checklist whose steps change state as work goes on. A step is a name
\(pending), or {\"name\", \"status\", \"detail\", \"seconds\", \"steps\"}:
status one of pending, running (a spinner), done, failed, skipped; detail a
note after it; seconds how long it took (else timed from running to done);
steps its own, drawn under it. Appending a step whose name is there changes
it in its place: append {\"steps\": [{\"name\": \"Build\", \"status\":
\"done\"}]}; with \"parent\": \"Build\", among that step's own."
  :props ((steps list "The steps, in order"))
  :example (:title "Release"
            :steps ((:name "Run the tests" :status "done" :detail "412 passed" :seconds 41)
                    (:name "Build the release" :status "running"
                     :steps ((:name "compile" :status "done" :seconds 8) (:name "link" :status "running")))
                    "Publish"))
  :animated (lambda (props)
              (seq-some (lambda (s) (eq (plist-get (cdr s) :status) 'running))
                        (agent-ui-steps--flat (plist-get props :steps) 0)))
  :check (lambda (props)
           (plist-put props :steps
                      (cl-loop for step in (plist-get props :steps)
                               for i from 1
                               collect (agent-ui-steps--normalize step (format "step %d" i) 0))))
  :append #'agent-ui-steps--append
  :prepare (lambda (element)
             (let ((steps (plist-get element :steps)))
               (if (listp steps)
                   (plist-put (copy-sequence element) :steps
                              (agent-ui-steps--timed steps (funcall agent-ui-clock)))
                 element)))
  :text #'agent-ui-steps--text)
