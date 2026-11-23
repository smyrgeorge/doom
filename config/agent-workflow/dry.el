;;; $DOOMDIR/config/agent-workflow/dry.el -*- lexical-binding: t; -*-
;; A dry run: a workflow tried before it spends tokens. Loaded from
;; config/agent-workflow.el, after watch.el. No Doom here.
;;
;; Nothing runs and nothing changes (no worktree, branch, issue or
;; session): the workflow is walked as the engine would, its agents' outcomes
;; and its scripts' exit codes as you choose them (none chosen: done, 0), its
;; approvals given. It says, wave by wave, what would run, what at once, what
;; would wait and why (the branch held by a job that edits, the pool, a
;; concurrency), what would be skipped (if:), sent back (an outcome's rerun,
;; counted against max-rounds), fixed and run again (a script's 1, up to its
;; retries), and where the run would stop and ask you.
;;
;; M-x agent-workflow-dry-run asks for the workflow, the issue its if: reads
;; (none: one of the first type it's for), and each job's outcomes and each
;; script's exit codes, one a round (changes,approved: changes, then
;; approved). cmd/agent-workflow dry-run says it as JSON.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow-pool)
(defvar agent-workflow-max-rounds)

(cl-defun agent-workflow-dry-run (workflow &key info outcomes exits (pool agent-workflow-pool) profiles)
  "WORKFLOW (a plist, as read) walked, nothing run: a plist (:waves :end
:stopped :branch), :waves a list of waves, each a list of lines (what
happened), :end the jobs' statuses, :stopped why it would stop, or nil,
:branch what happens to its issue's branch once it ends (words; nil if it
stops). INFO: the
issue its if: reads (a plist, as `agent-workflow-issue' gives it).
OUTCOMES: ((JOB . (OUTCOME...)) ...), an agent job's outcome each round
\(none: done). EXITS: ((\"JOB.N\" . (CODE...))...), step N's (from 1)
exit code each try (none: 0). POOL: the agents at once. PROFILES: the
project's (to tell the jobs that edit; default: the current project's)."
  (let* ((jobs (plist-get workflow :jobs))
         (profiles (or profiles (agent-workflow-profiles (agent-workflow-project))))
         (state (mapcar (lambda (job) (list (car job) :status 'pending :round 1)) jobs))
         (counts nil) (total 0)
         (max (or (plist-get workflow :max-rounds) agent-workflow-max-rounds))
         (waves nil) (stopped nil) (wave 0))
    (cl-labels
        ((get (job key) (plist-get (cdr (assoc job state)) key))
         (put (job key value) (setf (cdr (assoc job state)) (plist-put (cdr (assoc job state)) key value)))
         (spec (job) (cdr (assoc job jobs)))
         (edits (job)
           (seq-some (lambda (step)
                       (seq-some (lambda (name)
                                   (and name (agent-workflow-profile-edits-p (cdr (assoc name profiles)))))
                                 (list (plist-get step :agent) (plist-get step :on-fail))))
                     (plist-get (spec job) :steps)))
         (agent-p (job) (seq-some (lambda (step) (eq (plist-get step :kind) 'agent)) (plist-get (spec job) :steps)))
         (holds (job)
           (let ((form (plist-get (spec job) :if)))
             (or (null form)
                 (cl-letf (((symbol-function 'issue-id) (lambda () (plist-get info :id)))
                           ((symbol-function 'issue-type) (lambda () (intern (or (plist-get info :type) "task"))))
                           ((symbol-function 'issue-labels) (lambda () (plist-get info :labels)))
                           ((symbol-function 'issue-priority) (lambda () (or (plist-get info :priority) 2)))
                           ((symbol-function 'issue-title) (lambda () (plist-get info :title)))
                           ((symbol-function 'job-outcome) (lambda (name) (get (format "%s" name) :outcome)))
                           ((symbol-function 'job-status) (lambda (name) (get (format "%s" name) :status))))
                   (condition-case err (eval (car (read-from-string form)) t)
                     (error (setq stopped (format "%s: its if failed: %s" job (error-message-string err))) nil))))))
         (outcome (job)
           (let* ((round (get job :round))
                  (chosen (cdr (assoc job outcomes))))
             (or (nth (1- round) chosen) (car (last chosen)) "done")))
         (exit (job index try)
           (let ((chosen (cdr (assoc (format "%s.%d" job (1+ index)) exits))))
             (or (nth (1- try) chosen) (car (last chosen)) 0)))
         (dependents (job)
           (let ((needs (mapcar (lambda (j) (cons (car j) (plist-get (cdr j) :needs))) jobs)))
             (seq-filter (lambda (other) (member job (agent-workflow--before needs other))) (mapcar #'car jobs))))
         (run-step (job step index lines)
           ;; Step INDEX of JOB: said in LINES; why it stops, or nil.
           (pcase (plist-get step :kind)
             ('agent
              (push (format "%s: its agent (%s) works%s" job (plist-get step :agent)
                            (if (> (get job :round) 1) (format ", round %d" (get job :round)) ""))
                    (car lines))
              nil)
             (kind
              (let ((try 1) (retries (or (plist-get step :retries) 0)) (why nil) (done nil))
                (while (not (or done why))
                  (let ((code (exit job index try)))
                    (cond
                     ((eql code 0)
                      (push (format "%s: its %s step %d passes%s" job kind (1+ index)
                                    (if (> try 1) (format " (try %d)" try) ""))
                            (car lines))
                      (setq done t))
                     ((not (eql code 1))
                      (setq why (format "%s: its step %d breaks (%s): it asks you" job (1+ index) code)))
                     ((> try retries)
                      (setq why (format "%s: its step %d returns 1, its retries used up: it asks you" job (1+ index))))
                     ((not (or (agent-p job) (plist-get step :on-fail)))
                      (setq why (format "%s: its step %d returns 1, and no agent fixes it: it asks you" job (1+ index))))
                     (t
                      (push (format "%s: its step %d returns 1: %s fixes it, run again" job (1+ index)
                                    (if (agent-p job) "its agent" (format "an agent (%s)" (plist-get step :on-fail))))
                            (car lines))
                      (cl-incf try)))))
                why))))
         (run-job (job lines)
           ;; JOB's steps, each to its end: said in LINES; why it stops, or nil.
           (let ((why nil))
             (cl-loop for step in (plist-get (spec job) :steps) for index from 0
                      until why do
                      (setq why (run-step job step index lines))
                      (when (and (not why) (plist-get step :approve))
                        (push (format "%s: its step %d waits for your OK (given)" job (1+ index)) (car lines))))
             (when (and (not why) (plist-get (spec job) :approve))
               (push (format "%s: waits for your OK (given)" job) (car lines)))
             why)))
      (while (and (not stopped) (< wave 100)
                  (seq-some (lambda (job) (eq (get (car job) :status) 'pending)) state))
        (cl-incf wave)
        (let* ((lines (list nil))
               (startable (seq-filter (lambda (job)
                                        (and (eq (get job :status) 'pending)
                                             (seq-every-p (lambda (need) (memq (get need :status) '(done skipped)))
                                                          (plist-get (spec job) :needs))))
                                      (mapcar #'car jobs)))
               (started nil) (agents 0) (editing nil))
          (unless startable
            (setq stopped "nothing more can start: a job's needs aren't done"))
          (dolist (job (and (not stopped) startable))
            (cond
             ((not (holds job))
              (put job :status 'skipped)
              (push (format "%s: skipped (its if)" job) (car lines)))
             ((and (edits job) editing)
              (push (format "%s: waits for %s, which edits the branch" job editing) (car lines)))
             ((and (agent-p job) (>= agents pool))
              (push (format "%s: waits for an agent (%d of %d)" job agents pool) (car lines)))
             ((and (agent-p job) (plist-get workflow :concurrency) (>= agents (plist-get workflow :concurrency)))
              (push (format "%s: waits: %s at its limit, %d agents" job (plist-get workflow :name) agents) (car lines)))
             (t
              (when (edits job) (setq editing job))
              (when (agent-p job) (cl-incf agents))
              (put job :status 'running)
              (push job started))))
          (setq started (nreverse started))
          (when (cdr started)
            (push (format "at once: %s" (string-join started ", ")) (car lines)))
          (dolist (job started)
            (unless stopped
              (let ((stop (run-job job lines)))
                (if stop
                    (setq stopped stop)
                  (let* ((said (outcome job))
                         (then (cdr (assoc said (plist-get (spec job) :outcomes)))))
                    (pcase then
                      (`(rerun ,other)
                       (let* ((edge (format "%s>%s" job other))
                              (count (1+ (or (cdr (assoc edge counts)) 0))))
                         (setf (alist-get edge counts nil nil #'equal) count)
                         (cl-incf total)
                         (if (or (> count (or (plist-get (spec job) :max-rounds) max)) (> total (* 3 max)))
                             (setq stopped (format "%s: it sent %s back %d times: it asks you" job other (1- count)))
                           (push (format "%s: %s: %s and every job after it again" job said other) (car lines))
                           (dolist (replaced (cons other (dependents other)))
                             (unless (eq (get replaced :status) 'pending)
                               (put replaced :round (1+ (get replaced :round))))
                             (put replaced :status 'pending)))))
                      (_
                       (put job :status 'done)
                       (put job :outcome said)
                       (push (format "%s: done (%s)" job said) (car lines))))))))
            (when (and (agent-workflow--uses-merge-p (spec job)) (eq (get job :status) 'done))
              (push (format "%s: merged, the issue closed" job) (car lines))))
          (push (nreverse (car lines)) waves)))
      (list :waves (nreverse waves)
            :end (mapcar (lambda (job) (cons (car job) (plist-get (cdr job) :status))) state)
            :stopped stopped
            ;; Its branch, the run done (runs.el's `agent-workflow--branch-end').
            :branch (unless stopped
                      (cond ((eq (plist-get workflow :branch) 'keep) "kept (branch: keep)")
                            ((seq-some (lambda (job) (and (agent-workflow--uses-merge-p (spec (car job)))
                                                          (eq (plist-get (cdr job) :status) 'done)))
                                       state)
                             "deleted, merged into the main branch")
                            (t "kept: not merged into the main branch (no merge ran)")))))))

(defun agent-workflow--uses-merge-p (spec)
  "Non-nil if a job SPEC merges."
  (seq-some (lambda (step) (equal (plist-get step :uses) "merge")) (plist-get spec :steps)))

(defun agent-workflow--dry-text (result)
  "RESULT of a dry run, in words: a line each, its waves numbered."
  (concat
   (mapconcat #'identity
              (cl-loop for wave in (plist-get result :waves) for n from 1
                       collect (concat (format "%d.\n" n) (mapconcat (lambda (line) (concat "   " line)) wave "\n")))
              "\n")
   "\n\n"
   (if-let* ((why (plist-get result :stopped)))
       (concat "It stops: " why)
     (concat "It ends: every job done or skipped. Its branch: " (plist-get result :branch) "."))
   "\n"))

(defun agent-workflow--parse-chosen (text)
  "TEXT, \"JOB=a,b JOB2=c\", as ((JOB . (a b))...); numbers as numbers."
  (mapcar (lambda (pair)
            (let ((parts (split-string pair "=")))
              (cons (car parts)
                    (mapcar (lambda (v) (if (string-match-p "\\`[0-9]+\\'" v) (string-to-number v) v))
                            (split-string (or (cadr parts) "") "," t)))))
          (split-string (or text "") "[ \t]+" t)))

(defun agent-workflow-dry-run-command (workflow issue outcomes exits)
  "Dry run of WORKFLOW (M-x agent-workflow-dry-run) on ISSUE (its id, or
nil: one of the first type it's for), OUTCOMES and EXITS as typed
\(\"review=changes,approved\", \"build.2=1,0\"): what would happen, in a
buffer."
  (interactive
   (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
          (names (mapcar #'car (agent-workflow-workflows project))))
     (list (completing-read "Dry run of the workflow: " names nil t)
           (let ((id (read-string "On the issue (empty: none): "))) (and (not (string-empty-p id)) id))
           (read-string "Agents' outcomes, a round each (review=changes,approved): ")
           (read-string "Scripts' exit codes, a try each (build.2=1,0): "))))
  (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (spec (or (alist-get workflow (agent-workflow-workflows project) nil nil #'equal)
                   (user-error "No workflow %s" workflow)))
         (info (if issue
                   (agent-workflow-issue project issue)
                 (list :id "(none)" :title "(a dry run)" :type (or (car (plist-get spec :for)) "task"))))
         (result (agent-workflow-dry-run spec :info info :outcomes (agent-workflow--parse-chosen outcomes)
                                         :exits (agent-workflow--parse-chosen exits)
                                         :profiles (agent-workflow-profiles project)))
         (buffer (get-buffer-create "*agent-workflow dry run*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "A dry run of %s on %s: nothing runs, nothing changes.\n\n" workflow (plist-get info :id))
                (agent-workflow--dry-text result)))
      (special-mode)
      (goto-char (point-min)))
    (when (called-interactively-p 'any) (pop-to-buffer buffer))
    result))
