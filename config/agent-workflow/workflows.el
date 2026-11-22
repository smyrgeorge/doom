;;; $DOOMDIR/config/agent-workflow/workflows.el -*- lexical-binding: t; -*-
;; Workflows: the work, as GitHub Actions describes it, some steps an LLM.
;; Loaded from config/agent-workflow.el, after profiles.el. No Doom here.
;;
;; A workflow is a YAML file, NAME.yml (or .yaml), read with yaml.el:
;;
;;   name: feature                  its file's name, if given
;;   description: ...
;;   for: [feature, task]           the issue types it's offered for
;;   concurrency: 3                 agents on its runs at once
;;   budget: {cost: 15, tokens: 2000000, time: 3h}
;;   jobs:
;;     build:                       a job: a lowercase letter, then letters,
;;       steps:                     digits or -
;;         - agent: build           an LLM in agent-shell, with a profile
;;           prompt: Build {issue}.
;;         - run: tests/run.sh      any program (inline: run: |, shell:
;;           timeout: 10m           python...)
;;           retries: 3
;;     review:
;;       needs: build               after it (a list too)
;;       if: (eq (issue-type) 'bug) Lisp, evaluated as the job starts
;;       agent: review              one step's keys on the job itself
;;       approve: true
;;       outcomes: {changes: rerun build, approved: continue}
;;       max-rounds: 10
;;       concurrency: 1
;;   A step is agent: (with prompt:), run: (with shell:), elisp: (Lisp in
;;   your Emacs) or uses: (a built-in: merge), with timeout:, retries:,
;;   on-fail: (a profile), approve:.
;;
;; WORKFLOW, read: a plist (:name :file :description :for :concurrency
;; :budget (:cost :tokens :time) :jobs ((NAME . JOB)...)), JOB (:name :needs
;; :if :concurrency :approve :outcomes ((OUTCOME . continue|(rerun JOB))...)
;; :max-rounds :steps (STEP...)), STEP (:kind agent|run|elisp|uses :agent
;; :prompt :run :shell :elisp :uses :timeout :retries :on-fail :approve),
;; durations in seconds. Nothing in it is run here: if: and elisp: are only
;; read, to check them.
;;
;; A problem names the file and line (yaml.el gives none: found again in the
;; text, `agent-workflow--yaml-line'). Errors leave the workflow out: YAML
;; that doesn't parse, no jobs, a name (its file's) not a lowercase letter
;; then letters, digits or -, a name: not its file's, a needs, rerun or
;; {jobs.X...} naming no job, needs going round, a step with no kind or two,
;; an agent: or on-fail: naming no profile, a uses: no built-in, a shell:
;; without run:, an if: not one Lisp form, an elisp: not Lisp, a variable not
;; one there is, a number, duration or true/false that isn't one. Warnings:
;; an unknown key, a for: type Beads doesn't have, a {jobs.X...} of a job not
;; before it, retries: or on-fail: on an agent step, no description.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function yaml-parse-string "yaml")

;; ====== VARIABLES ======

(defconst agent-workflow-builtins '("merge")
  "The built-in steps (uses:).")

(defconst agent-workflow-issue-types
  '("bug" "feature" "task" "epic" "chore" "decision" "spike" "story" "milestone")
  "Beads' issue types, a workflow's for: names (one of the project's own
is only warned about).")

(defconst agent-workflow--workflow-keys
  '("name" "description" "for" "concurrency" "budget" "jobs")
  "A workflow's keys.")

(defconst agent-workflow--step-keys
  '("agent" "prompt" "run" "shell" "elisp" "uses" "timeout" "retries" "on-fail" "approve")
  "A step's keys.")

(defconst agent-workflow--job-keys
  '("needs" "if" "concurrency" "approve" "outcomes" "max-rounds" "steps")
  "A job's keys, and one step's (`agent-workflow--step-keys') on the job
itself.")

(defvar agent-workflow--workflows-cache (make-hash-table :test #'equal)
  "A project's workflows, as last read: project to (STAMP (WORKFLOWS .
PROBLEMS)), STAMP the files (its profiles' too) and their times.")

;; ====== A WORKFLOW FILE ======

(defun agent-workflow--yaml-parse (text)
  "TEXT parsed as YAML: mappings alists with string keys, sequences lists,
true t, false :false, null :null."
  (require 'yaml)
  (yaml-parse-string text :object-type 'alist :object-key-type 'string :sequence-type 'list
                     :null-object :null :false-object :false))

(defun agent-workflow--mapping-p (value)
  "Non-nil if VALUE is a YAML mapping, as read (an alist, maybe empty)."
  (and (listp value) (seq-every-p (lambda (pair) (and (consp pair) (stringp (car pair)))) value)))

(defun agent-workflow--names (value)
  "VALUE, a name or a list of them, as a list; nil if it isn't."
  (cond ((stringp value) (list value))
        ((and (listp value) (seq-every-p #'stringp value)) value)))

(defun agent-workflow--one-form-p (text)
  "Non-nil if TEXT is one Lisp form, nothing after it."
  (condition-case nil
      (let ((end (cdr (read-from-string text))))
        (string-blank-p (substring text end)))
    (error nil)))

(defun agent-workflow--lisp-p (text)
  "Non-nil if TEXT reads as Lisp forms, one or more."
  (condition-case nil
      (let ((start 0) (forms 0))
        (while (not (string-blank-p (substring text start)))
          (setq start (cdr (read-from-string text start)))
          (cl-incf forms))
        (> forms 0))
    (error nil)))

(defun agent-workflow--before (jobs name)
  "The jobs of JOBS (an alist of a name and its needs) NAME needs, directly
or not."
  (let ((seen nil) (todo (cdr (assoc name jobs))))
    (while todo
      (let ((job (pop todo)))
        (unless (member job seen)
          (push job seen)
          (setq todo (append (cdr (assoc job jobs)) todo)))))
    seen))

(defun agent-workflow--cycle (jobs)
  "A cycle in JOBS' needs (an alist of a name and its needs), as the list
of its jobs, or nil."
  (catch 'cycle
    (let ((done nil))
      (cl-labels ((visit (name path)
                    (cond ((member name path)
                                  ;; From where it first went round, in the order
                           ;; it went.
                           (throw 'cycle (member name (reverse path))))
                          ((member name done))
                          (t (dolist (next (cdr (assoc name jobs)))
                               (visit next (cons name path)))
                             (push name done)))))
        (dolist (job jobs) (visit (car job) nil))
        nil))))

(cl-defun agent-workflow-workflow-read (file &optional (profiles 'any))
  "Read the workflow FILE: (WORKFLOW . PROBLEMS). WORKFLOW is a plist (see
the top of this file), nil if FILE has errors; PROBLEMS, each
\(error|warning \"FILE:LINE: what\" FILE LINE \"what\"), in the order of
their lines. PROFILES: the names its agent: and on-fail: may name (any, the
default: not checked)."
  (let* ((name (replace-regexp-in-string "\\.ya?ml\\'" "" (file-name-nondirectory file)))
         (text (with-temp-buffer
                 (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
                 (buffer-string)))
         (case-fold-search nil)
         (problems nil)
         (workflow (list :name name :file file))
         (data nil))
    (cl-flet* ((problem (level path format &rest args)
                 (push (apply #'agent-workflow--problem level file
                              (if (integerp path) path (agent-workflow--yaml-line text path))
                              format args)
                       problems))
               (count (path value min what)
                 ;; VALUE a whole number from MIN, or a problem: nil.
                 (if (and (integerp value) (>= value min))
                     value
                   (problem 'error path "%s %s: %s" what (agent-workflow--shown value)
                            (if (= min 0) "a whole number, 0 or more" "a whole number above 0"))
                   nil))
               (duration (path value what)
                 (or (agent-workflow--duration value)
                     (progn (problem 'error path "%s %s: a duration (45s, 10m, 3h, 1h30m)"
                                     what (agent-workflow--shown value))
                            nil)))
               (bool (path value what)
                 (pcase value
                   ('t t)
                   (:false nil)
                   (_ (problem 'error path "%s %s: true or false" what (agent-workflow--shown value)) nil))))
      (unless (string-match-p agent-workflow--name-regexp name)
        (problem 'error 1 "its name %s (its file's): a lowercase letter, then lowercase letters, digits or -" name))
      (condition-case err
          (setq data (agent-workflow--yaml-parse text))
        (error
         (problem 'error
                  (if (string-match "end of input \\([0-9]+\\)/" (error-message-string err))
                      (agent-workflow--offset-line text (string-to-number (match-string 1 (error-message-string err))))
                    1)
                  "not YAML: %s" (error-message-string err))
         (setq data :unread)))
      (cond
       ((eq data :unread))
       ((not (and data (agent-workflow--mapping-p data)))
        (problem 'error 1 "not a workflow: its keys (name, for, jobs...) and their values"))
       (t
        (pcase-dolist (`(,key . ,value) data)
          (pcase key
            ("name"
             (unless (equal value name)
               (problem 'error '("name") "its name is %s, its file's %s: they must agree"
                        (agent-workflow--shown value) name)))
            ("description"
             (if (and (stringp value) (not (string-blank-p value)))
                 (setq workflow (plist-put workflow :description (string-trim value)))
               (problem 'warning '("description") "description: empty: say what it's for")))
            ("for"
             (if-let* ((types (agent-workflow--names value)))
                 (progn
                   (dolist (type types)
                     (unless (member type agent-workflow-issue-types)
                       (problem 'warning '("for") "for %s: not one of Beads' types (%s)" type
                                (string-join agent-workflow-issue-types ", "))))
                   (setq workflow (plist-put workflow :for types)))
               (problem 'error '("for") "for %s: an issue type, or a list of them" (agent-workflow--shown value))))
            ("concurrency"
             (setq workflow (plist-put workflow :concurrency (count '("concurrency") value 1 "concurrency"))))
            ("budget"
             (if (not (and value (agent-workflow--mapping-p value)))
                 (problem 'error '("budget") "budget: its cost, tokens or time")
               (let (budget)
                 (pcase-dolist (`(,k . ,v) value)
                   (pcase k
                     ("cost" (if (and (numberp v) (> v 0))
                                 (setq budget (plist-put budget :cost v))
                               (problem 'error '("budget" "cost") "cost %s: a number above 0 (dollars)"
                                        (agent-workflow--shown v))))
                     ("tokens" (setq budget (plist-put budget :tokens (count '("budget" "tokens") v 1 "tokens"))))
                     ("time" (setq budget (plist-put budget :time (duration '("budget" "time") v "time"))))
                     (_ (problem 'warning (list "budget" k) "unknown key %s: ignored (cost, tokens, time)" k))))
                 (setq workflow (plist-put workflow :budget budget)))))
            ("jobs")
            (_ (problem 'warning (list key) "unknown key %s: ignored" key))))
        (unless (plist-get workflow :description)
          (unless (assoc "description" data)
            (problem 'warning 1 "no description: say what it's for (description: ...)")))
        (let ((jobs (cdr (assoc "jobs" data))))
          (cond
           ((not (assoc "jobs" data))
            (problem 'error 1 "no jobs: a workflow does its work in jobs (jobs: ...)"))
           ((not (and jobs (agent-workflow--mapping-p jobs)))
            (problem 'error '("jobs") "jobs: each a name, then its steps"))
           (t
            (let ((needs (mapcar (lambda (job)
                                   (cons (car job)
                                         (and (agent-workflow--mapping-p (cdr job))
                                              (agent-workflow--names (cdr (assoc "needs" (cdr job)))))))
                                 jobs))
                  (read-jobs nil))
              (pcase-dolist (`(,job . ,spec) jobs)
                (push (cons job (agent-workflow--job-read job spec needs profiles #'problem
                                                          #'count #'duration #'bool))
                      read-jobs))
              (when-let* ((cycle (agent-workflow--cycle
                                  (seq-filter (lambda (job) (assoc (car job) jobs)) needs))))
                (problem 'error (list "jobs" (car cycle) "needs") "needs go round: %s"
                         (string-join (append cycle (list (car cycle))) " → ")))
              (setq workflow (plist-put workflow :jobs (nreverse read-jobs))))))))))
    (setq problems (agent-workflow--by-line (nreverse problems)))
    (cons (unless (agent-workflow--errors-p problems) workflow) problems)))

(defun agent-workflow--shown (value)
  "VALUE as a problem shows it."
  (pcase value
    ('t "true") (:false "false") (:null "null")
    ((pred stringp) value)
    (_ (format "%S" value))))

(defun agent-workflow--job-read (job spec needs profiles problem count duration bool)
  "The job JOB of a workflow, SPEC as read: a plist (see the top of this
file). NEEDS: every job's needs (an alist), PROFILES the profiles' names
\(any: not checked); PROBLEM, COUNT, DURATION and BOOL report as
`agent-workflow-workflow-read' does."
  (let ((read (list :name job))
        (jobs (mapcar #'car needs))
        (path (list "jobs" job)))
    (unless (string-match-p agent-workflow--name-regexp job)
      (funcall problem 'error path "job %s: a lowercase letter, then lowercase letters, digits or -" job))
    (if (not (and spec (agent-workflow--mapping-p spec)))
        (funcall problem 'error path "job %s: its steps (steps: ...), or one step's keys (agent:, run:...)" job)
      (pcase-dolist (`(,key . ,value) spec)
        (let ((at (append path (list key))))
          (pcase key
            ("needs"
             (if-let* ((names (agent-workflow--names value)))
                 (progn
                   (dolist (other names)
                     (cond ((equal other job) (funcall problem 'error at "needs %s: its own job" other))
                           ((not (member other jobs))
                            (funcall problem 'error at "needs %s: no such job (%s)" other (string-join jobs ", ")))))
                   (setq read (plist-put read :needs names)))
               (funcall problem 'error at "needs %s: a job, or a list of them" (agent-workflow--shown value))))
            ("if"
             (if (and (stringp value) (agent-workflow--one-form-p value))
                 (setq read (plist-put read :if (string-trim value)))
               (funcall problem 'error at "if %s: one Lisp form, as (eq (issue-type) 'bug)"
                        (agent-workflow--shown value))))
            ("concurrency" (setq read (plist-put read :concurrency (funcall count at value 1 "concurrency"))))
            ("max-rounds" (setq read (plist-put read :max-rounds (funcall count at value 1 "max-rounds"))))
            ("approve" (setq read (plist-put read :approve (funcall bool at value "approve"))))
            ("outcomes"
             (if (not (and value (agent-workflow--mapping-p value)))
                 (funcall problem 'error at "outcomes: each an outcome, then continue or rerun JOB")
               (let (outcomes)
                 (pcase-dolist (`(,outcome . ,then) value)
                   (let ((here (append at (list outcome))))
                     (cond
                      ((not (string-match-p agent-workflow--name-regexp outcome))
                       (funcall problem 'error here "outcome %s: a lowercase letter, then lowercase letters, digits or -"
                                outcome))
                      ((equal then "continue") (push (cons outcome 'continue) outcomes))
                      ((and (stringp then) (string-match "\\`rerun[ \t]+\\([^ \t]+\\)\\'" then))
                       (let ((other (match-string 1 then)))
                         (if (member other jobs)
                             (push (cons outcome (list 'rerun other)) outcomes)
                           (funcall problem 'error here "%s: rerun %s: no such job (%s)" outcome other
                                    (string-join jobs ", ")))))
                      (t (funcall problem 'error here "%s %s: continue, or rerun JOB" outcome
                                  (agent-workflow--shown then))))))
                 (setq read (plist-put read :outcomes (nreverse outcomes))))))
            ("steps")
            ((pred (lambda (k) (member k agent-workflow--step-keys))))
            (_ (funcall problem 'warning at "unknown key %s: ignored" key)))))
      (let* ((steps (cdr (assoc "steps" spec)))
             (own (seq-filter (lambda (pair) (member (car pair) agent-workflow--step-keys)) spec)))
        (cond
         ((and (assoc "steps" spec) own)
          (funcall problem 'error path "job %s: its steps (steps:) or one step's keys (%s), not both"
                   job (string-join (mapcar #'car own) ", ")))
         (own
          (setq read (plist-put read :steps (list (agent-workflow--step-read own path job needs profiles
                                                                            problem count duration bool)))))
         ((not (assoc "steps" spec))
          (funcall problem 'error path "job %s: no steps (steps: ...), nor one step's keys (agent:, run:...)" job))
         ((not (and (consp steps) (seq-every-p (lambda (step) (and step (agent-workflow--mapping-p step))) steps)))
          (funcall problem 'error (append path '("steps")) "steps: a list, each a step's keys (- run: ...)"))
         (t
          (setq read (plist-put read :steps
                                (cl-loop for step in steps for i from 0
                                         collect (agent-workflow--step-read
                                                  step (append path (list "steps" i)) job needs profiles
                                                  problem count duration bool))))))))
    read))

(defun agent-workflow--step-read (spec path job needs profiles problem count duration bool)
  "A step of the job JOB, SPEC as read, at PATH: a plist (see the top of
this file). As `agent-workflow--job-read' for the rest."
  (let* ((kinds (seq-filter (lambda (kind) (assoc kind spec)) '("agent" "run" "elisp" "uses")))
         (kind (car kinds))
         (step (list :kind (and kind (intern kind)))))
    (cond
     ((null kinds)
      (funcall problem 'error path "a step with nothing to do: agent:, run:, elisp: or uses:"))
     ((cdr kinds)
      (funcall problem 'error path "a step does one thing: %s, not %s"
               (string-join kinds " or ") (string-join kinds " and "))))
    (pcase-dolist (`(,key . ,value) spec)
      (let ((at (append path (list key))))
        (pcase key
          ("agent"
           (cond ((not (stringp value)) (funcall problem 'error at "agent %s: a profile" (agent-workflow--shown value)))
                 ((and (listp profiles) (not (member value profiles)))
                  (funcall problem 'error at "agent %s: no such profile (%s)" value
                           (agent-workflow--listed profiles)))
                 (t (setq step (plist-put step :agent value)))))
          ("prompt"
           (if (not (stringp value))
               (funcall problem 'error at "prompt: its text")
             (unless (equal kind "agent")
               (funcall problem 'error at "prompt: only for an agent: step"))
             (dolist (found (agent-workflow-variables-in value))
               (let* ((variable (car found))
                      (other (agent-workflow--variable-job variable)))
                 (cond
                  ((not (agent-workflow-variable-p variable))
                   (funcall problem 'error at "prompt: {%s} isn't a variable (%s)" variable
                            (agent-workflow--variables-said)))
                  ((and other (not (assoc other needs)))
                   (funcall problem 'error at "prompt: {%s}: no such job (%s)" variable
                            (string-join (mapcar #'car needs) ", ")))
                  ((and other (not (member other (agent-workflow--before needs job))))
                   (funcall problem 'warning at "prompt: {%s}: %s isn't before %s (its needs): empty when it starts"
                            variable other job)))))
             (setq step (plist-put step :prompt value))))
          ("run"
           (if (and (stringp value) (not (string-blank-p value)))
               (setq step (plist-put step :run value))
             (funcall problem 'error at "run: a program, or a script (run: |)")))
          ("shell"
           (cond ((not (assoc "run" spec)) (funcall problem 'error at "shell: only for a run: step"))
                 ((not (and (stringp value) (string-match-p "\\`[^ \t\n]+\\(?: [^\n]*\\)?\\'" value)))
                  (funcall problem 'error at "shell %s: an interpreter (bash, python...)" (agent-workflow--shown value)))
                 (t (setq step (plist-put step :shell value)))))
          ("elisp"
           (if (and (stringp value) (agent-workflow--lisp-p value))
               (setq step (plist-put step :elisp value))
             (funcall problem 'error at "elisp %s: Lisp (in YAML, a form with \": \" in it goes under elisp: |)"
                      (agent-workflow--shown value))))
          ("uses"
           (if (member value agent-workflow-builtins)
               (setq step (plist-put step :uses value))
             (funcall problem 'error at "uses %s: not a built-in (%s)" (agent-workflow--shown value)
                      (string-join agent-workflow-builtins ", "))))
          ("timeout" (setq step (plist-put step :timeout (funcall duration at value "timeout"))))
          ("retries"
           (when (equal kind "agent")
             (funcall problem 'warning at "retries: an agent step isn't retried (its script's are)"))
           (setq step (plist-put step :retries (funcall count at value 0 "retries"))))
          ("on-fail"
           (cond ((equal kind "agent")
                  (funcall problem 'warning at "on-fail: an agent step has no script to fail: ignored"))
                 ((not (stringp value)) (funcall problem 'error at "on-fail %s: a profile" (agent-workflow--shown value)))
                 ((and (listp profiles) (not (member value profiles)))
                  (funcall problem 'error at "on-fail %s: no such profile (%s)" value
                           (agent-workflow--listed profiles)))
                 (t (setq step (plist-put step :on-fail value)))))
          ("approve" (setq step (plist-put step :approve (funcall bool at value "approve"))))
          (_ (funcall problem 'warning at "unknown key %s: ignored" key)))))
    step))

;; ====== A PROJECT'S WORKFLOWS ======

(defun agent-workflow--workflows-read (project)
  "PROJECT's workflows and their problems, read again if a file changed
\(its profiles' too): (WORKFLOWS . PROBLEMS), WORKFLOWS an alist of a name
and its workflow, in order (the starters first), each one's :origin where
its file is (starter, project, local), its :replaces the origin of the one
of its name it replaced."
  (let* ((files (agent-workflow--files project "workflows" "\\`[^.].*\\.ya?ml\\'"))
         (profiles (agent-workflow-profiles project))
         (stamp (cons (agent-workflow--stamp files)
                      (car (gethash (or project "") agent-workflow--profiles-cache))))
         (key (or project ""))
         (cached (gethash key agent-workflow--workflows-cache)))
    (if (equal (car cached) stamp)
        (cadr cached)
      (let ((names (mapcar #'car profiles)) workflows problems)
        (dolist (file files)
          (pcase-let ((`(,workflow . ,found) (agent-workflow-workflow-read (cdr file) names)))
            (setq problems (append problems found))
            (when workflow
              (let* ((name (plist-get workflow :name))
                     (replaced (alist-get name workflows nil nil #'equal)))
                (setq workflow (plist-put workflow :origin (car file)))
                (when replaced
                  (setq workflow (plist-put workflow :replaces (plist-get replaced :origin))))
                (setf (alist-get name workflows nil nil #'equal) workflow)))))
        (let ((value (cons (nreverse workflows) problems)))
          (puthash key (list stamp value) agent-workflow--workflows-cache)
          value)))))

(defun agent-workflow-workflows (&optional project)
  "PROJECT's workflows (default: the current project's): an alist of a
name and its workflow, the starters, the project's and yours."
  (car (agent-workflow--workflows-read (or project (agent-workflow-project)))))

(defun agent-workflow-workflow-problems (&optional project)
  "What's wrong with PROJECT's workflow files."
  (cdr (agent-workflow--workflows-read (or project (agent-workflow-project)))))
