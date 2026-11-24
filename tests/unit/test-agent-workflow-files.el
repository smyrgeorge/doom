;;; tests/unit/test-agent-workflow-files.el -*- lexical-binding: t; -*-
;; config/agent-workflow/: workflows (YAML) and agents (Markdown) read and
;; checked, their problems naming the file and line; where they come from
;; (the starters, a project's own read from its main checkout, yours), a
;; later one replacing one of the same name; the variables a prompt names,
;; filled in; M-x agent-workflow-check, and cmd/agent-workflow check through
;; Emacs's server.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'server)
(require 'json)
(+test-load "config/agent-workflow")

(defconst +test-awf-script (expand-file-name "cmd/agent-workflow" +test-root))

;; ====== HELPERS ======

(defun +test-awf--dir (name)
  "A new, empty folder NAME in the temp folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awf/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun +test-awf--file (dir name text)
  "A file NAME in DIR holding TEXT: its name."
  (let ((file (expand-file-name name dir)))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file file (insert text)))
    file))

(defun +test-awf--workflow (text &optional definitions name)
  "TEXT read as the workflow NAME (default feature.yml), its agent: and
on-fail: checked against DEFINITIONS (default: build, review, docs):
\(WORKFLOW . PROBLEMS)."
  (agent-workflow-workflow-read (+test-awf--file (+test-awf--dir "read") (or name "feature.yml") text)
                                (or definitions '("build" "review" "docs"))))

(defun +test-awf--definition (text &optional name)
  "TEXT read as the agent NAME (default build.md): (DEFINITION . PROBLEMS)."
  (agent-workflow-definition-read (+test-awf--file (+test-awf--dir "read") (or name "build.md") text)))

(defun +test-awf--said (problems)
  "PROBLEMS as (LEVEL LINE \"what\") each."
  (mapcar (lambda (problem) (list (nth 0 problem) (nth 3 problem) (nth 4 problem))) problems))

(defun +test-awf--git (dir &rest args)
  "Run git with ARGS in DIR; fail the test if it fails."
  (let ((default-directory dir))
    (should (eql 0 (apply #'process-file "git" nil nil nil args)))))

(defun +test-awf--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (+test-awf--dir name)))
    (+test-awf--git dir "init" "-q" "-b" "main")
    (+test-awf--file dir "README" "x\n")
    (+test-awf--git dir "add" ".")
    (+test-awf--git dir "-c" "user.name=t" "-c" "user.email=t@t" "commit" "-q" "-m" "first")
    dir))

(defmacro +test-awf--with-starters (dir &rest body)
  "BODY with DIR the starters' folder (its workflows/ and agents/), the
caches empty."
  (declare (indent 1))
  `(let ((agent-workflow-starters-directory ,dir)
         (agent-workflow--definitions-cache (make-hash-table :test #'equal))
         (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
     ,@body))

(defconst +test-awf--definition-text "---
description: builds an issue with its tests
---
Build it.
"
  "An agent with nothing but what it needs.")

(defconst +test-awf--feature "name: feature
description: A feature built with its tests, reviewed, merged.
for: [feature, task]
concurrency: 3
budget:
  cost: 15
  tokens: 2000000
  time: 3h

jobs:
  build:
    steps:
      - agent: build
        prompt: |
          Build {issue}: {issue.title}.
          {issue.acceptance}
          Round {round}. {note}
      - run: .agent-workflow/scripts/check.sh
        timeout: 15m
        retries: 3

  coverage:
    needs: build
    steps:
      - run: make coverage
      - shell: python
        run: |
          import sys
          sys.exit(0)
        on-fail: build

  docs:
    needs: build
    if: (not (eq (issue-type) 'task))
    agent: docs

  review:
    needs: [build, docs]
    agent: review
    prompt: |
      The builder said: {jobs.build.notes}
    approve: true
    outcomes:
      approved: continue
      changes: rerun build
    max-rounds: 10

  merge:
    needs: [review, coverage]
    concurrency: 1
    steps:
      - uses: merge
        on-fail: build
      - elisp: |
          (message \"Merged: %s\" (issue-title))
"
  "The example workflow, everything in it.")

;; ====== A WORKFLOW FILE ======

(ert-deftest agent-workflow-files/a-workflow ()
  "Every key read: the workflow's, its jobs' (one step's keys on a job
itself too), its steps' kinds; durations in seconds; outcomes; nothing run."
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow +test-awf--feature)))
    (should-not problems)
    (should (equal (plist-get workflow :name) "feature"))
    (should (equal (plist-get workflow :description) "A feature built with its tests, reviewed, merged."))
    (should (equal (plist-get workflow :for) '("feature" "task")))
    (should (eql (plist-get workflow :concurrency) 3))
    (should (equal (plist-get workflow :budget) '(:cost 15 :tokens 2000000 :time 10800)))
    (let ((jobs (plist-get workflow :jobs)))
      (should (equal (mapcar #'car jobs) '("build" "coverage" "docs" "review" "merge")))
      (let ((build (alist-get "build" jobs nil nil #'equal)))
        (should (equal (mapcar (lambda (step) (plist-get step :kind)) (plist-get build :steps)) '(agent run)))
        (let ((agent (car (plist-get build :steps))) (run (cadr (plist-get build :steps))))
          (should (equal (plist-get agent :agent) "build"))
          (should (string-prefix-p "Build {issue}: {issue.title}." (plist-get agent :prompt)))
          (should (equal (plist-get run :run) ".agent-workflow/scripts/check.sh"))
          (should (eql (plist-get run :timeout) 900))
          (should (eql (plist-get run :retries) 3))))
      (let ((python (cadr (plist-get (alist-get "coverage" jobs nil nil #'equal) :steps))))
        (should (eq (plist-get python :kind) 'run))
        (should (equal (plist-get python :shell) "python"))
        (should (equal (plist-get python :on-fail) "build")))
      (let ((docs (alist-get "docs" jobs nil nil #'equal)))
        (should (equal (plist-get docs :needs) '("build")))
        (should (equal (plist-get docs :if) "(not (eq (issue-type) 'task))"))
        (should (equal (plist-get docs :steps) '((:kind agent :agent "docs")))))
      (let ((review (alist-get "review" jobs nil nil #'equal)))
        (should (equal (plist-get review :needs) '("build" "docs")))
        (should (eq (plist-get review :approve) t))
        (should (equal (plist-get review :outcomes) '(("approved" . continue) ("changes" rerun "build"))))
        (should (eql (plist-get review :max-rounds) 10)))
      (let ((merge (alist-get "merge" jobs nil nil #'equal)))
        (should (eql (plist-get merge :concurrency) 1))
        (should (equal (plist-get (car (plist-get merge :steps)) :uses) "merge"))
        (should (equal (plist-get (cadr (plist-get merge :steps)) :kind) 'elisp))
        (should (string-match-p "(message" (plist-get (cadr (plist-get merge :steps)) :elisp)))))))

(ert-deftest agent-workflow-files/if-and-elisp-are-never-run ()
  "Reading a workflow runs none of its Lisp."
  (let ((ran nil))
    (cl-letf (((symbol-function '+test-awf--boom) (lambda () (setq ran t))))
      (pcase-let ((`(,workflow . ,problems)
                   (+test-awf--workflow "description: x
jobs:
  one:
    if: (+test-awf--boom)
    elisp: (+test-awf--boom)
")))
        (should workflow)
        (should-not problems)
        (should-not ran)))))

(ert-deftest agent-workflow-files/on-fail-a-script-an-agent-or-both ()
  "on-fail: an agent (its agent fixes it), {run: a script} (it alone),
{run, agent} (the script first, then the agent), {agent} (as its name alone)."
  (cl-flet ((step (on-fail)
              (pcase-let ((`(,workflow . ,problems)
                           (+test-awf--workflow (concat "description: x\njobs:\n  a:\n    run: x\n    on-fail:" on-fail))))
                (should-not problems)
                (car (plist-get (cdr (assoc "a" (plist-get workflow :jobs))) :steps)))))
    (let ((it (step " build\n")))
      (should (equal (plist-get it :on-fail) "build"))
      (should-not (plist-get it :on-fail-run)))
    (let ((it (step "\n      run: tests/rerun.sh\n")))
      (should-not (plist-get it :on-fail))
      (should (equal (plist-get it :on-fail-run) "tests/rerun.sh")))
    (let ((it (step "\n      run: tests/rerun.sh\n      agent: build\n")))
      (should (equal (plist-get it :on-fail) "build"))
      (should (equal (plist-get it :on-fail-run) "tests/rerun.sh")))
    (should (equal (plist-get (step "\n      agent: review\n") :on-fail) "review"))))

(ert-deftest agent-workflow-files/errors-leave-it-out ()
  "Each error names its line, and leaves the workflow out."
  (dolist (case
           '(("description: x\njobs:\n  a:\n    run: x\n    agent: build\n"
              (error 3 "a step does one thing: agent or run, not agent and run"))
             ("description: x\njobs:\n  a:\n    timeout: 3m\n"
              (error 3 "a step with nothing to do: agent:, run:, elisp: or uses:"))
             ("description: x\njobs:\n  a:\n    needs: b\n    run: x\n"
              (error 4 "needs b: no such job (a)"))
             ("description: x\njobs:\n  a:\n    needs: b\n    run: x\n  b:\n    needs: a\n    run: y\n"
              (error 4 "needs go round: a → b → a"))
             ("description: x\njobs:\n  a:\n    needs: a\n    run: x\n"
              (error 4 "needs a: its own job"))
             ("description: x\njobs:\n  a:\n    if: (eq x\n    run: x\n"
              (error 4 "if (eq x: one Lisp form, as (eq (issue-type) 'bug)"))
             ("description: x\njobs:\n  a:\n    if: (a) (b)\n    run: x\n"
              (error 4 "if (a) (b): one Lisp form, as (eq (issue-type) 'bug)"))
             ("description: x\njobs:\n  a:\n    agent: nobody\n"
              (error 4 "agent nobody: no such agent (build, review, docs)"))
             ("description: x\njobs:\n  a:\n    uses: deploy\n"
              (error 4 "uses deploy: not a built-in (merge)"))
             ("description: x\njobs:\n  a:\n    elisp: (oops\n"
              (error 4 "elisp (oops: Lisp (in YAML, a form with \": \" in it goes under elisp: |)"))
             ("description: x\njobs:\n  a:\n    shell: python\n    agent: build\n"
              (error 4 "shell: only for a run: step"))
             ("description: x\njobs:\n  a:\n    steps:\n      - run: x\n        on-fail: nobody\n"
              (error 6 "on-fail nobody: no such agent (build, review, docs)"))
             ("description: x\njobs:\n  a:\n    run: x\n    on-fail:\n      agent: nobody\n"
              (error 6 "on-fail nobody: no such agent (build, review, docs)"))
             ("description: x\njobs:\n  a:\n    run: x\n    on-fail: {}\n"
              (error 5 "on-fail: run: (a script), agent: (an agent's name), or both"))
             ("description: x\njobs:\n  a:\n    run: x\n    on-fail:\n      run: 3\n"
              (error 6 "run 3: a script"))
             ("description: x\njobs:\n  a:\n    run: x\n    on-fail: [build]\n"
              (error 5 "on-fail (\"build\"): an agent's name, or {run: a script, agent: an agent's name}"))
             ("description: x\njobs:\n  a:\n    run: x\n    outcomes:\n      changes: rerun b\n"
              (error 6 "changes: rerun b: no such job (a)"))
             ("description: x\njobs:\n  a:\n    run: x\n    outcomes:\n      changes: rerun b\n  b:\n    run: y\n"
              (error 6 "changes: rerun b: not a job a needs (directly or not): it may not have run yet"))
             ("description: x\njobs:\n  a:\n    run: x\n    outcomes:\n      changes: again\n"
              (error 6 "changes again: continue, or rerun JOB"))
             ("description: x\njobs:\n  a:\n    agent: build\n    prompt: Do {issue.nope}\n"
              (error 5 "prompt: {issue.nope} isn't a variable ({issue}, {issue.title}, {issue.description}, {issue.acceptance}, {issue.notes}, {branch}, {main}, {main-branch}, {worktree}, {project}, {diff.stat}, {output}, {note}, {round}, {try}, {jobs.JOB.outcome}, {jobs.JOB.notes})"))
             ("description: x\njobs:\n  a:\n    agent: build\n    prompt: As {jobs.b.notes}\n"
              (error 5 "prompt: {jobs.b.notes}: no such job (a)"))
             ("description: x\njobs:\n  a:\n    run: x\n    timeout: soon\n"
              (error 5 "timeout soon: a duration (45s, 10m, 3h, 1h30m)"))
             ("description: x\njobs:\n  a:\n    run: x\n    retries: -1\n"
              (error 5 "retries -1: a whole number, 0 or more"))
             ("description: x\njobs:\n  a:\n    run: x\n    approve: maybe\n"
              (error 5 "approve maybe: true or false"))
             ("description: x\nconcurrency: 0\njobs:\n  a:\n    run: x\n"
              (error 2 "concurrency 0: a whole number above 0"))
             ("description: x\nbudget:\n  cost: free\njobs:\n  a:\n    run: x\n"
              (error 3 "cost free: a number above 0 (dollars)"))
             ("description: x\njobs:\n  a:\n    run: x\n    steps:\n      - run: y\n"
              (error 3 "job a: its steps (steps:) or one step's keys (run), not both"))
             ("description: x\njobs:\n  a:\n    concurrency: 2\n"
              (error 3 "job a: no steps (steps: ...), nor one step's keys (agent:, run:...)"))
             ("description: x\njobs:\n  Build:\n    run: x\n"
              (error 3 "job Build: a lowercase letter, then lowercase letters, digits or -"))
             ("description: x\n" (error 1 "no jobs: a workflow does its work in jobs (jobs: ...)"))
             ("name: other\ndescription: x\njobs:\n  a:\n    run: x\n"
              (error 1 "its name is other, its file's feature: they must agree"))
             ("- just\n- a list\n" (error 1 "not a workflow: its keys (name, for, jobs...) and their values"))))
    (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow (car case))))
      (ert-info ((car case) :prefix "workflow: ")
        (should-not workflow)
        (should (member (cadr case) (+test-awf--said problems)))))))

(ert-deftest agent-workflow-files/not-yaml ()
  "YAML that doesn't parse: an error at the line where yaml.el stopped."
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x\njobs:\n  a:\n    run: x\n  bad\n")))
    (should-not workflow)
    (should (eq (car (car problems)) 'error))
    (should (string-prefix-p "not YAML: " (nth 4 (car problems))))
    (should (>= (nth 3 (car problems)) 4))))

(ert-deftest agent-workflow-files/warnings-keep-it ()
  "A warning keeps the workflow: an unknown key, a type Beads doesn't have,
a job's notes before it ran, retries or on-fail on an agent step, no
description."
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "for: [feature, saga]
color: blue
jobs:
  a:
    agent: build
    prompt: After {jobs.b.notes}
    retries: 2
    on-fail: build
    colour: red
  b:
    run: x
")))
    (should workflow)
    (should (equal (+test-awf--said problems)
                   '((warning 1 "for saga: not one of Beads' types (bug, feature, task, epic, chore, decision, spike, story, milestone)")
                     (warning 1 "no description: say what it's for (description: ...)")
                     (warning 2 "unknown key color: ignored")
                     (warning 6 "prompt: {jobs.b.notes}: b isn't before a (its needs): empty when it starts")
                     (warning 7 "retries: an agent step isn't retried (its script's are)")
                     (warning 8 "on-fail: an agent step has no script to fail: ignored")
                     (warning 9 "unknown key colour: ignored"))))))

(ert-deftest agent-workflow-files/step-names-and-retry-from ()
  "A step's name and retry-from: retry-from read as an index of its job's
steps (a name, a number from 1, its own step); naming no step, a step after
it, not a name, a name twice in a job: errors; on an agent step: warned."
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  green:
    steps:
      - run: check.sh
        name: check
      - run: push.sh
        name: push
      - run: watch.sh
        name: watch
        retries: 5
        retry-from: push
  again:
    steps:
      - run: a.sh
      - run: b.sh
        retry-from: 1
  self:
    run: x
    retry-from: 1
")))
    (should-not problems)
    (let ((green (plist-get (cdr (assoc "green" (plist-get workflow :jobs))) :steps)))
      (should (equal (mapcar (lambda (step) (plist-get step :name)) green) '("check" "push" "watch")))
      (should (equal (mapcar (lambda (step) (plist-get step :retry-from)) green) '(nil nil 1))))
    (should (equal (plist-get (nth 1 (plist-get (cdr (assoc "again" (plist-get workflow :jobs))) :steps)) :retry-from) 0))
    (should (equal (plist-get (car (plist-get (cdr (assoc "self" (plist-get workflow :jobs))) :steps)) :retry-from) 0)))
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  a:
    steps:
      - run: one.sh
        name: one
        retry-from: two
      - run: two.sh
        name: two
        retry-from: three
      - run: x
        name: one
      - run: y
        name: Big
        retry-from: 9
      - agent: build
        retry-from: one
")))
    (should-not workflow)
    (should (equal (+test-awf--said problems)
                   '((error 7 "retry-from two: a step after it (its retry starts again at one before it, or itself)")
                     (error 10 "retry-from three: no such step of its job (one, two)")
                     (error 12 "name one: another step's of its job")
                     (error 14 "name Big: a lowercase letter, then lowercase letters, digits or -")
                     (error 15 "retry-from 9: no such step of its job (one, two)")
                     (warning 17 "retry-from: an agent step isn't retried (its script's are): ignored"))))))

(ert-deftest agent-workflow-files/a-step-s-model-and-effort ()
  "An agent step's model and effort, over its agent's: read; one not one
there is, warned; on a step not an agent's, or not text, an error; on an
agent step after its job's first, warned (its session goes on)."
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  build:
    agent: build
    model: sonnet
    effort: low
  docs:
    steps:
      - agent: docs
        model: claude-haiku-5-5
      - run: check.sh
      - agent: docs
        model: opus
        effort: max
  review:
    agent: review
    model: gpt
    effort: extreme
")))
    (should workflow)
    (let ((step (car (plist-get (cdr (assoc "build" (plist-get workflow :jobs))) :steps))))
      (should (equal (plist-get step :model) "sonnet"))
      (should (equal (plist-get step :effort) "low")))
    (should (equal (plist-get (car (plist-get (cdr (assoc "docs" (plist-get workflow :jobs))) :steps)) :model)
                   "claude-haiku-5-5"))
    (should (equal (+test-awf--said problems)
                   '((warning 13 "model: its job's agent goes on in the session its step 1 started, with its model: ignored")
                     (warning 14 "effort: its job's agent goes on in the session its step 1 started, with its effort: ignored")
                     (warning 17 "model gpt: not one of fable, opus, sonnet, haiku, nor a model's id (claude-...)")
                     (warning 18 "effort extreme: not one of low, medium, high, xhigh, max")))))
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  a:
    run: x
    model: opus
    effort: high
  b:
    agent: build
    model: [opus]
    effort: 3
")))
    (should-not workflow)
    (should (equal (+test-awf--said problems)
                   '((error 5 "model: only for an agent: step")
                     (error 6 "effort: only for an agent: step")
                     (error 9 "model (\"opus\"): a model (fable, opus, sonnet, haiku, a model's id)")
                     (error 10 "effort 3: one of low, medium, high, xhigh, max"))))))

(ert-deftest agent-workflow-files/a-kind ()
  "kind: names an agent's agent, in its file or on an agent step (over it):
one of `agent-workflow-kinds'; another, or on a step not an agent's, an
error; on an agent step after its job's first, warned (its session goes
on)."
  (pcase-let ((`(,definition . ,problems) (+test-awf--definition "---\ndescription: x\nkind: codex\n---\nDo.\n")))
    (should-not problems)
    (should (eq (plist-get definition :kind) 'codex)))
  (pcase-let ((`(,definition . ,problems) (+test-awf--definition "---\ndescription: x\nkind: chatgpt\n---\nDo.\n")))
    (should-not definition)
    (should (equal (+test-awf--said problems)
                   (list (list 'error 3 (concat "kind chatgpt: not one of " (agent-workflow--kinds-said)))))))
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  build:
    agent: build
    kind: gemini-cli
  docs:
    steps:
      - agent: docs
      - agent: docs
        kind: codex
")))
    (should workflow)
    (let ((build (car (plist-get (cdr (assoc "build" (plist-get workflow :jobs))) :steps))))
      (should (eq (plist-get build :kind) 'agent))
      (should (eq (plist-get build :agent-kind) 'gemini-cli)))
    (should (equal (+test-awf--said problems)
                   '((warning 10 "kind: its job's agent goes on in the session its step 1 started, with its kind: ignored")))))
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  a:
    run: x
    kind: codex
  b:
    agent: build
    kind: chatgpt
")))
    (should-not workflow)
    (should (equal (+test-awf--said problems)
                   (list '(error 5 "kind: only for an agent: step")
                         (list 'error 8 (concat "kind chatgpt: not one of " (agent-workflow--kinds-said))))))))

(ert-deftest agent-workflow-files/model-effort-and-mode-by-kind ()
  "An agent's model, effort and mode checked by its kind: Claude Code's
against its names, levels and modes; another agent's taken as they are, in
its file or on a step of it."
  (pcase-let ((`(,definition . ,problems)
               (+test-awf--definition "---\ndescription: x\nkind: codex\nmodel: gpt-5\neffort: extreme\nmode: full-auto\n---\nDo.\n")))
    (should-not problems)
    (should (equal (mapcar (lambda (key) (plist-get definition key)) '(:model :effort :mode))
                   '("gpt-5" "extreme" "full-auto"))))
  (pcase-let ((`(,_ . ,problems)
               (+test-awf--definition "---\ndescription: x\nmode: full-auto\n---\nDo.\n")))
    (should (equal (+test-awf--said problems)
                   '((error 3 "mode full-auto: not one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions")))))
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow "description: x
jobs:
  build:
    agent: build
    kind: codex
    model: gpt-5
    effort: extreme
")))
    (should workflow)
    (should-not problems)))

(ert-deftest agent-workflow-files/runs-in-checkout-claude-code-only ()
  "A workflow that runs in your checkout: its agents (their steps' kinds,
their files', its on-fail agents') Claude Code only: another, an error
naming the job and the kind, the workflow left out."
  (let* ((dir (+test-awf--dir "checkout-kinds"))
         (project (file-name-as-directory dir))
         (agent-workflow-starters-directory (+test-tmp-file "awf/no-starters/"))
         (agent-workflow--definitions-cache (make-hash-table :test #'equal))
         (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
    (+test-awf--file dir ".agent-workflow/agents/build.md" "---\ndescription: x\n---\nDo.\n")
    (+test-awf--file dir ".agent-workflow/agents/fixer.md" "---\ndescription: x\nkind: codex\n---\nFix.\n")
    (+test-awf--file dir ".agent-workflow/workflows/here.yml"
                     "description: x\nticket: false\nruns-in: checkout\njobs:\n  build:\n    agent: build\n")
    (+test-awf--file dir ".agent-workflow/workflows/other.yml"
                     "description: x\nticket: false\nruns-in: checkout\njobs:\n  build:\n    agent: build\n    kind: gemini-cli\n")
    (+test-awf--file dir ".agent-workflow/workflows/fixed.yml"
                     "description: x\nticket: false\nruns-in: checkout\njobs:\n  check:\n    run: x\n    on-fail: fixer\n")
    (pcase-let ((`(,workflows . ,problems) (agent-workflow--workflows-read project)))
      (should (equal (mapcar #'car workflows) '("here")))
      (should (equal (sort (mapcar (lambda (problem) (nth 1 problem)) problems) #'string<)
                     (sort (list (format "%s:3: runs-in checkout: build's agent runs on gemini-cli, not Claude Code: in your checkout, nothing keeps it from editing .agent-workflow/ (what runs it)"
                                         (abbreviate-file-name (expand-file-name ".agent-workflow/workflows/other.yml" dir)))
                                 (format "%s:3: runs-in checkout: check's agent runs on codex, not Claude Code: in your checkout, nothing keeps it from editing .agent-workflow/ (what runs it)"
                                         (abbreviate-file-name (expand-file-name ".agent-workflow/workflows/fixed.yml" dir))))
                           #'string<))))))

(ert-deftest agent-workflow-files/a-job-s-approve-beside-its-steps ()
  "A job's approve: true beside its steps: read, its last step's result
waiting for your OK; one step's keys on the job, approve among them: the
same."
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow "description: x
jobs:
  build:
    approve: true
    steps:
      - run: make
      - run: make test
")))
    (should-not problems)
    (let ((run (agent-workflow-run--make :workflow workflow :jobs (list (cons "build" (list :status 'running :step 1))))))
      (should (plist-get (cdr (assoc "build" (plist-get workflow :jobs))) :approve))
      (should (agent-workflow--needs-approval-p run "build"))
      (agent-workflow--job-set run "build" :step 0)
      (should-not (agent-workflow--needs-approval-p run "build"))))
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow "description: x\njobs:\n  build:\n    agent: build\n    approve: true\n")))
    (should-not problems)
    (should (= (length (plist-get (cdr (assoc "build" (plist-get workflow :jobs))) :steps)) 1))
    (should (agent-workflow--needs-approval-p
             (agent-workflow-run--make :workflow workflow :jobs (list (cons "build" (list :status 'running :step 0))))
             "build"))))

(ert-deftest agent-workflow-files/steps-as-a-mapping ()
  "steps: written as a mapping (the dash forgotten, or in braces): an error
of its file, at its line, not a signal; an empty job in a ticketless or
checkout workflow too. A file that signals as it's read: its own problem,
the project's other workflows still read."
  (dolist (text '("description: x\njobs:\n  a:\n    steps:\n      run: make\n"
                  "description: x\njobs:\n  a:\n    steps: {run: make}\n"))
    (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow text)))
      (should-not workflow)
      (should (equal (+test-awf--said problems) '((error 4 "steps: a list, each a step's keys (- run: ...)"))))))
  (dolist (head '("ticket: false" "runs-in: checkout"))
    (pcase-let ((`(,workflow . ,problems)
                 (+test-awf--workflow (format "description: x\n%s\njobs:\n  a:\n  b:\n    steps:\n      run: make\n" head))))
      (should-not workflow)
      (should (seq-every-p (lambda (problem) (eq (car problem) 'error)) problems))
      (should problems)))
  (let ((starters (+test-awf--dir "mapping-starters"))
        (project (+test-awf--project "mapping")))
    (+test-awf--file starters "agents/build.md" +test-awf--definition-text)
    (+test-awf--with-starters starters
      (+test-awf--file project ".agent-workflow/workflows/good.yml" "description: one\njobs:\n  a:\n    agent: build\n")
      (let ((bad (+test-awf--file project ".agent-workflow/workflows/bad.yml" "description: two\njobs:\n  a:\n    run: x\n")))
        (cl-letf* ((read (symbol-function 'agent-workflow--workflow-read))
                   ((symbol-function 'agent-workflow--workflow-read)
                    (lambda (file definitions as)
                      (if (equal file bad) (signal 'wrong-type-argument '(listp "make")) (funcall read file definitions as)))))
          (should (equal (mapcar #'car (agent-workflow-workflows project)) '("good")))
          (should (equal (+test-awf--said (agent-workflow-workflow-problems project))
                         '((error 1 "it can't be read: Wrong type argument: listp, \"make\"")))))))))

(ert-deftest agent-workflow-files/ticket-false ()
  "ticket: false read (:ticketless); true, or none: on tickets; another
value an error. Its prompts' {issue.title}... warned (empty without a
ticket), {issue} not."
  (should-not (plist-get (car (+test-awf--workflow "description: x\njobs:\n  a:\n    run: x\n")) :ticketless))
  (should-not (plist-get (car (+test-awf--workflow "description: x\nticket: true\njobs:\n  a:\n    run: x\n")) :ticketless))
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow "description: x
ticket: false
jobs:
  a:
    agent: build
    prompt: Build {issue}, {issue.title}.
  b:
    steps:
      - run: x
      - agent: build
        prompt: '{issue.description}'
" '("build"))))
    (should (plist-get workflow :ticketless))
    (should (equal (+test-awf--said problems)
                   '((warning 6 "prompt: {issue.title}: empty, its workflow has no ticket (ticket: false)")
                     (warning 11 "prompt: {issue.description}: empty, its workflow has no ticket (ticket: false)")))))
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow "description: x\nticket: maybe\njobs:\n  a:\n    run: x\n")))
    (should-not workflow)
    (should (equal (+test-awf--said problems) '((error 2 "ticket maybe: true or false"))))))

(ert-deftest agent-workflow-files/runs-in ()
  "runs-in: checkout read (:checkout); worktree, or none: its own; another
value an error. In your checkout: uses: merge an error, branch: a warning."
  (should-not (plist-get (car (+test-awf--workflow "description: x\njobs:\n  a:\n    run: x\n")) :checkout))
  (should-not (plist-get (car (+test-awf--workflow "description: x\nruns-in: worktree\njobs:\n  a:\n    run: x\n"))
                         :checkout))
  (should (plist-get (car (+test-awf--workflow "description: x\nruns-in: checkout\njobs:\n  a:\n    run: x\n")) :checkout))
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow "description: x
runs-in: checkout
branch: keep
jobs:
  a:
    run: x
  b:
    needs: a
    steps:
      - run: y
      - uses: merge
  c:
    needs: a
    uses: merge
")))
    (should-not workflow)
    (should (equal (+test-awf--said problems)
                   '((warning 3 "branch: ignored: it runs in your checkout (runs-in: checkout), on its branch")
                     (error 11 "uses merge: it runs in your checkout (runs-in: checkout): nothing to merge")
                     (error 14 "uses merge: it runs in your checkout (runs-in: checkout): nothing to merge")))))
  (pcase-let ((`(,workflow . ,problems) (+test-awf--workflow "description: x\nruns-in: here\njobs:\n  a:\n    run: x\n")))
    (should-not workflow)
    (should (equal (+test-awf--said problems)
                   '((error 2 "runs-in here: worktree (its own: the default) or checkout (yours)"))))))

(ert-deftest agent-workflow-files/a-check-an-agent-can-change ()
  "A run: of a file of the branch: warned (its agents can change it); one of
.agent-workflow/, a command, a script: not."
  (pcase-let ((`(,_ . ,problems)
               (+test-awf--workflow "description: x
jobs:
  a:
    steps:
      - run: tests/run.sh --all
      - run: .agent-workflow/scripts/check.sh
      - run: make test
      - run: |
          tests/run.sh
          echo done
")))
    (should (equal (+test-awf--said problems)
                   '((warning 5 "run tests/run.sh: a file of the branch's: its agents can change it (and make it pass); one of .agent-workflow/ runs your checkout's"))))))

(ert-deftest agent-workflow-files/a-job-before-another ()
  "A job's notes in a prompt are fine when it's before it, directly or not."
  (should-not (cdr (+test-awf--workflow "description: x
jobs:
  a:
    run: x
  b:
    needs: a
    run: y
  c:
    needs: b
    agent: review
    prompt: '{jobs.a.notes} {jobs.b.outcome}'
"))))

(ert-deftest agent-workflow-files/definitions-not-checked-without-them ()
  "Read alone, with no agents given, agent: and on-fail: name any."
  (should-not (cdr (agent-workflow-workflow-read
                    (+test-awf--file (+test-awf--dir "alone") "x.yml"
                                     "description: x\njobs:\n  a:\n    agent: anyone\n")))))

;; ====== A LINE OF A YAML FILE ======

(ert-deftest agent-workflow-files/a-line-found-again ()
  "A key's line, through mappings and lists' items; the deepest found when
not all of it is there."
  (let ((text "name: x
jobs:
  build:
    steps:
      - agent: build
        prompt: |
          Build it: now.
      # a comment
      - run: check.sh
        retries: 3
  review:
    needs: [build]
    outcomes:
      changes: rerun build
"))
    (dolist (case '((("name") 1) (("jobs") 2) (("jobs" "build") 3) (("jobs" "build" "steps" 0) 5)
                    (("jobs" "build" "steps" 0 "prompt") 6) (("jobs" "build" "steps" 1) 9)
                    (("jobs" "build" "steps" 1 "retries") 10) (("jobs" "review" "needs") 12)
                    (("jobs" "review" "outcomes" "changes") 14) (("jobs" "review" "nope") 11)
                    (("nope") 1)))
      (should (equal (list (car case) (agent-workflow--yaml-line text (car case))) case)))))

;; ====== VARIABLES ======

(ert-deftest agent-workflow-files/variables ()
  "The variables a text names ({ \"a\": 1 } isn't one), filled in; one
without a value left as it is; nil empty."
  (should (equal (agent-workflow-variables-in "Build {issue}: {issue.title} { \"a\": 1 } {jobs.b.notes}")
                 '(("issue" . 6) ("issue.title" . 15) ("jobs.b.notes" . 40))))
  (should (agent-workflow-variable-p "jobs.review.outcome"))
  (should-not (agent-workflow-variable-p "jobs.review.time"))
  (should (equal (agent-workflow-fill "Build {issue}: {issue.title}. {note}{round} {nope}"
                                      '(("issue" . "doom-1") ("issue.title" . "Its title") ("note")))
                 "Build doom-1: Its title. {round} {nope}")))

(ert-deftest agent-workflow-files/durations ()
  (should (equal (mapcar #'agent-workflow--duration '("45s" "10m" "3h" "1h30m" 90 "3x" "10" 0 "0m"))
                 '(45 600 10800 5400 90 nil nil nil nil))))

;; ====== A DEFINITION FILE ======

(ert-deftest agent-workflow-files/a-definition ()
  "Every key read: lists inline or as YAML items, a kebab-case mode as
Claude Code's id, the icon and its glyph, color as colour; the body its
instructions, with variables."
  (pcase-let ((`(,definition . ,problems)
               (+test-awf--definition "---
name: build
description: \"builds an issue with its tests\"
tools:
  - Read
  - 'Bash(git -C {main} commit:*)'
deny: [WebFetch]
model: opus
effort: high
mode: accept-edits
icon: md-hammer ⚙
verb: building
color: blue
---

Build it on {branch}.
")))
    (should-not problems)
    (should (equal (plist-get definition :description) "builds an issue with its tests"))
    (should (equal (plist-get definition :tools) '("Read" "Bash(git -C {main} commit:*)")))
    (should (equal (plist-get definition :deny) '("WebFetch")))
    (should (equal (plist-get definition :model) "opus"))
    (should (equal (plist-get definition :effort) "high"))
    (should (equal (plist-get definition :mode) "acceptEdits"))
    (should (equal (plist-get definition :icon) "md-hammer"))
    (should (equal (plist-get definition :glyph) "⚙"))
    (should (equal (plist-get definition :verb) "building"))
    (should (equal (plist-get definition :colour) "blue"))
    (should (equal (plist-get definition :instructions) "Build it on {branch}."))))

(ert-deftest agent-workflow-files/a-definition-s-problems ()
  "Errors leave an agent out; warnings keep it."
  (dolist (case '(("description: x\n" (error 1 "no front matter: it starts with a line ---, its keys, then a line ---"))
                  ("---\ndescription: x\n" (error 3 "its front matter isn't closed: a line --- after its keys"))
                  ("---\ntools: Read\n---\nx\n" (error 1 "no description: say what it's for (description: ...)"))
                  ("---\ndescription: x\nmode: yolo\n---\nx\n"
                   (error 3 "mode yolo: not one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions"))
                  ("---\ndescription: x\ntools: Read(\n---\nx\n" (error 3 "tools Read(: not a tool, Tool or Tool(pattern)"))
                  ("---\ndescription: x\ntools: Bash(cd {home}:*)\n---\nx\n"
                   (error 3 "tools Bash(cd {home}:*): {home} isn't a variable ({issue}, {issue.title}, {issue.description}, {issue.acceptance}, {issue.notes}, {branch}, {main}, {main-branch}, {worktree}, {project}, {diff.stat}, {output}, {note}, {round}, {try}, {jobs.JOB.outcome}, {jobs.JOB.notes})"))
                  ("---\ndescription: x\n---\nWork on {ticket}.\n"
                   (error 4 "{ticket} isn't a variable ({issue}, {issue.title}, {issue.description}, {issue.acceptance}, {issue.notes}, {branch}, {main}, {main-branch}, {worktree}, {project}, {diff.stat}, {output}, {note}, {round}, {try}, {jobs.JOB.outcome}, {jobs.JOB.notes})"))
                  ("---\nname: other\ndescription: x\n---\nx\n" (error 2 "its name is other, its file's build: they must agree"))
                  ("---\ndescription: x\ncolour: pink\n---\nx\n"
                   (error 3 "colour pink: not one of blue, magenta, green, yellow, cyan, red, white, black"))))
    (pcase-let ((`(,definition . ,problems) (+test-awf--definition (car case))))
      (ert-info ((car case) :prefix "agent: ")
        (should-not definition)
        (should (member (cadr case) (+test-awf--said problems))))))
  (pcase-let ((`(,definition . ,problems)
               (+test-awf--definition "---\ndescription: x\ntools: Edit\ndeny: Edit\nlabels: build\nmodel: gpt\n---\n")))
    (should definition)
    (should (equal (+test-awf--said problems)
                   '((warning 4 "Edit both allowed (tools) and denied (deny): denied")
                     (warning 5 "unknown key labels: ignored")
                     (warning 6 "model gpt: not inherit, one of fable, opus, sonnet, haiku, nor a model's id (claude-...)")
                     (warning 7 "no instructions after its front matter")))))
  ;; An effort: default is none; one not one there is, warned.
  (should-not (plist-get (car (+test-awf--definition "---\ndescription: x\neffort: default\n---\nx\n")) :effort))
  (pcase-let ((`(,definition . ,problems) (+test-awf--definition "---\ndescription: x\neffort: hard\n---\nx\n")))
    (should (equal (plist-get definition :effort) "hard"))
    (should (equal (+test-awf--said problems)
                   '((warning 3 "effort hard: not default, nor one of low, medium, high, xhigh, max")))))
  (should (cdr (agent-workflow-definition-read
                (+test-awf--file (+test-awf--dir "bad-name") "Build.md" +test-awf--definition-text)))))

;; ====== A PROJECT'S ======

(ert-deftest agent-workflow-files/where-they-come-from ()
  "The starters, the project's, yours: a later one replacing one of the same
name, each saying where it's from; found from an agent's worktree too, read
from the main checkout; a workflow's agent: checked against them all."
  (let* ((starters (+test-awf--dir "starters"))
         (project (+test-awf--project "where")))
    (+test-awf--file starters "agents/build.md" +test-awf--definition-text)
    (+test-awf--file starters "agents/review.md" "---\ndescription: reviews\n---\nReview it.\n")
    (+test-awf--file starters "workflows/feature.yml" "description: starter\njobs:\n  a:\n    agent: build\n")
    (+test-awf--file starters "workflows/quick.yml" "description: quick\njobs:\n  a:\n    agent: review\n")
    (+test-awf--file project ".agent-workflow/agents/review.md" "---\ndescription: the project's\n---\nx\n")
    (+test-awf--file project ".agent-workflow/workflows/feature.yaml"
                     "description: the project's\njobs:\n  a:\n    agent: docs\n")
    (+test-awf--file project ".agent-shell/agent-workflow/agents/docs.md" "---\ndescription: mine\n---\nx\n")
    (+test-awf--file project ".agent-shell/agent-workflow/workflows/quick.yml"
                     "description: mine\njobs:\n  a:\n    agent: nobody\n")
    (+test-awf--file project ".agent-shell/agent-workflow/workflows/notes.txt" "not a workflow")
    (+test-awf--with-starters starters
      (let ((definitions (agent-workflow-agent-definitions project))
            (workflows (agent-workflow-workflows project)))
        (should (equal (mapcar #'car definitions) '("build" "review" "docs")))
        (should (equal (mapcar (lambda (p) (plist-get (cdr p) :origin)) definitions) '(starter project local)))
        (should (eq (plist-get (alist-get "review" definitions nil nil #'equal) :replaces) 'starter))
        (should (equal (plist-get (alist-get "review" definitions nil nil #'equal) :description) "the project's"))
        ;; quick: yours, its agent nobody: left out, the starter's kept.
        (should (equal (mapcar #'car workflows) '("feature" "quick")))
        (should (equal (plist-get (alist-get "feature" workflows nil nil #'equal) :description) "the project's"))
        (should (eq (plist-get (alist-get "feature" workflows nil nil #'equal) :origin) 'project))
        (should (eq (plist-get (alist-get "quick" workflows nil nil #'equal) :origin) 'starter))
        (should (equal (+test-awf--said (agent-workflow-workflow-problems project))
                       '((error 4 "agent nobody: no such agent (build, review, docs)"))))
        ;; From an agent's worktree: the main checkout's.
        (let ((worktree (expand-file-name "wt" (+test-awf--dir "where-wt"))))
          (+test-awf--git project "worktree" "add" "-q" worktree)
          (+test-awf--file worktree ".agent-workflow/workflows/evil.yml" "description: x\njobs:\n  a:\n    run: x\n")
          (should (equal (agent-workflow-project worktree) project))
          (should (equal (mapcar #'car (agent-workflow-workflows (agent-workflow-project worktree)))
                         '("feature" "quick"))))))))

(ert-deftest agent-workflow-files/read-again-when-changed ()
  "A project's workflows are read again when a file changes, its agents
too, else kept."
  (let ((starters (+test-awf--dir "again-starters"))
        (project (+test-awf--project "again")))
    (+test-awf--file starters "agents/build.md" +test-awf--definition-text)
    (+test-awf--with-starters starters
      (let ((file (+test-awf--file project ".agent-workflow/workflows/w.yml"
                                   "description: one\njobs:\n  a:\n    agent: build\n")))
        (should (equal (plist-get (cdar (agent-workflow-workflows project)) :description) "one"))
        (+test-awf--file project ".agent-workflow/workflows/w.yml" "description: two\njobs:\n  a:\n    agent: build\n")
        (set-file-times file (time-add (current-time) 5))
        (should (equal (plist-get (cdar (agent-workflow-workflows project)) :description) "two"))
        ;; Its agent gone: left out, the project having none.
        (delete-file (expand-file-name "agents/build.md" starters))
        (should-not (agent-workflow-workflows project))
        (should (equal (+test-awf--said (agent-workflow-workflow-problems project))
                       '((error 4 "agent build: no such agent (none)"))))))))

;; ====== THIS CONFIG'S OWN ======

(ert-deftest agent-workflow-files/this-config-s-samples ()
  "The workflows of this config (.agent-workflow/: github, screenshots,
their agents ci and screenshots) checked, no problem; each walked to its
end, its branch deleted once merged."
  (let ((agent-workflow--definitions-cache (make-hash-table :test #'equal))
        (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
    (should-not (agent-workflow-check-problems +test-root))
    (let ((workflows (agent-workflow-workflows +test-root)))
      (should (equal (mapcar #'car (seq-filter (lambda (w) (eq (plist-get (cdr w) :origin) 'project)) workflows))
                     '("github" "screenshots")))
      (dolist (name '("github" "screenshots"))
        (ert-info (name :prefix "workflow: ")
          (let* ((workflow (cdr (assoc name workflows)))
                 (result (agent-workflow--dry-run workflow :info '(:id "demo-1" :type "task")
                                                 :definitions (agent-workflow-agent-definitions +test-root))))
            (should (equal (plist-get workflow :file)
                           (expand-file-name (format ".agent-workflow/workflows/%s.yml" name) +test-root)))
            (should-not (plist-get workflow :for))
            (should-not (plist-get result :stopped))
            (should (plist-get workflow :ticketless))
            (pcase name
              ;; In your checkout: no branch, nothing merged.
              ("github"
               (should (plist-get workflow :checkout))
               (should (equal (plist-get result :branch) "none: its commits are on your checkout's branch")))
              ;; No ticket: its merge merged, nothing to close.
              (_
               (should (member "merge: merged (no ticket to close)" (+test-awf--dry-lines result)))
               (should (equal (plist-get result :branch) "deleted, merged into the main branch"))))))))
    (should (assoc "screenshots" (agent-workflow-agent-definitions +test-root)))
    (should (assoc "ci" (agent-workflow-agent-definitions +test-root)))))

;; github's scripts (check, push, watch): a stand-in gh (its runs and logs from
;; GH_RUNS, GH_PENDING, GH_LOGGED_OUT), a bare origin, a clone of it on main
;; standing in for your checkout and the issue's worktree.

(defun +test-awf--gh (bin)
  "A stand-in gh in BIN: auth status fails with GH_LOGGED_OUT; run list
prints GH_RUNS (lines ID TAB STATUS TAB CONCLUSION TAB NAME, \\n between),
in_progress the first GH_PENDING times (counted in GH_COUNT); run view
prints a failed job's lines. Its arguments, a line each call, in GH_ARGS."
  (make-directory bin t)
  (let ((gh (expand-file-name "gh" bin)))
    (write-region "#!/bin/bash
[ -n \"$GH_ARGS\" ] && echo \"$*\" >> \"$GH_ARGS\"
case \"$1 $2\" in
  'auth status') [ -z \"$GH_LOGGED_OUT\" ] ;;
  'run list')
    n=$(cat \"$GH_COUNT\" 2>/dev/null || echo 0); echo $((n + 1)) > \"$GH_COUNT\"
    if [ \"$n\" -lt \"${GH_PENDING:-0}\" ]; then printf '1\\tin_progress\\t\\tTests\\n'
    else printf \"$GH_RUNS\"; fi ;;
  'run view') echo \"test-lexer.el: FAILED lexer/escapes\" ;;
  *) exit 3 ;;
esac
" nil gh)
    (set-file-modes gh #o755)
    gh))

(defun +test-awf--github (name script &rest env)
  "SCRIPT (github-check.sh...) run in a clone on main of a bare origin (a
commit there), named NAME, ENV more of its environment (GH_RUNS ...) and
how it's set up (:ahead a commit origin hasn't, :behind origin one it
hasn't, :off-main, :no-remote, :no-gh, :logged-out): (EXIT OUTPUT CLONE
ORIGIN), CLONE your checkout and its worktree."
  (let* ((dir (+test-awf--dir name))
         (origin (expand-file-name "origin.git" dir))
         (clone (file-name-as-directory (expand-file-name "clone" dir)))
         (bin (expand-file-name "bin" dir))
         (git (lambda (where &rest args)
                (let ((default-directory where))
                  (apply #'call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" args)))))
    (funcall git dir "init" "-q" "--bare" "-b" "main" origin)
    (funcall git dir "clone" "-q" origin clone)
    (funcall git clone "checkout" "-q" "-b" "main")
    (+test-awf--file clone "a.el" "one\n")
    (funcall git clone "add" "a.el")
    (funcall git clone "commit" "-q" "-m" "first")
    (funcall git clone "push" "-q" "origin" "main")
    (+test-awf--gh bin)
    (when (plist-get env :ahead)
      (+test-awf--file clone "b.el" "two\n")
      (funcall git clone "add" "b.el")
      (funcall git clone "commit" "-q" "-m" "second"))
    (when (plist-get env :behind)
      (let ((other (expand-file-name "other" dir)))
        (funcall git dir "clone" "-q" origin other)
        (+test-awf--file (file-name-as-directory other) "c.el" "theirs\n")
        (funcall git other "add" "c.el")
        (funcall git other "commit" "-q" "-m" "theirs")
        (funcall git other "push" "-q" "origin" "main")))
    (when (plist-get env :off-main)
      (funcall git clone "checkout" "-q" "-b" "other"))
    (when (plist-get env :no-remote)
      (funcall git clone "remote" "remove" "origin"))
    ;; Origin's URL a GitHub one, fetched from the bare origin all the same.
    (when-let* ((url (plist-get env :url)))
      (funcall git clone "remote" "set-url" "origin" url)
      (funcall git clone "config" (format "url.%s.insteadOf" origin) url))
    (with-temp-buffer
      (let* ((default-directory clone)
             (process-environment
              (append (list (concat "PATH=" (if (plist-get env :no-gh)
                                                   ;; Nothing: gh nowhere (the Linux runners have one in /usr/bin).
                                                   (let ((none (expand-file-name "none" dir))) (make-directory none t) none)
                                                 (concat bin ":" (getenv "PATH"))))
                            (concat "MAIN=" clone) "MAIN_BRANCH=main" "GITHUB_POLL=0"
                            (format "GITHUB_APPEAR=%s" (or (plist-get env :appear) 0))
                            (concat "GH_COUNT=" (expand-file-name "count" dir))
                            (concat "GH_ARGS=" (expand-file-name "args" dir))
                            (concat "GH_RUNS=" (or (plist-get env :runs) ""))
                            (format "GH_PENDING=%s" (or (plist-get env :pending) 0))
                            (concat "GH_LOGGED_OUT=" (if (plist-get env :logged-out) "1" "")))
                      process-environment))
             (exit (call-process "bash" nil t nil
                                 (expand-file-name (concat ".agent-workflow/scripts/" script) +test-root))))
        (list exit (string-trim (buffer-string)) clone origin)))))

(defun +test-awf--origin-main (origin)
  "ORIGIN's main, its commit."
  (let ((default-directory origin))
    (string-trim (shell-command-to-string "git rev-parse main"))))

(ert-deftest agent-workflow-files/github-check-sh ()
  "github-check.sh: no gh, gh logged out, your checkout not on main, no
remote: the run fails (3), its last line why; else 0."
  (pcase-dolist (`(,name ,setup ,why)
                 '(("chk-none" (:no-gh t) "gh (GitHub's command line) isn't installed: brew install gh, then gh auth login")
                   ("chk-out" (:logged-out t) "gh isn't logged in to GitHub: gh auth login")
                   ("chk-off" (:off-main t) "your checkout is on other, not main: check out main, then run it again")
                   ("chk-remote" (:no-remote t) "no remote origin to push to")))
    (ert-info (name :prefix "case: ")
      (pcase-let ((`(,exit ,out) (apply #'+test-awf--github name "github-check.sh" setup)))
        (should (eql exit 3))
        (should (equal (car (last (split-string out "\n"))) (concat "github-check.sh: " why))))))
  (pcase-let ((`(,exit ,out) (+test-awf--github "chk-ok" "github-check.sh")))
    (should (eql exit 0))
    (should (string-prefix-p "github-check.sh: gh logged in, your checkout on main, origin: " out))))

(ert-deftest agent-workflow-files/github-push-sh ()
  "github-push.sh: commits origin hasn't, pushed; none, said (0); origin
with commits yours hasn't, or your checkout off main: refused, the run
asks (2)."
  (pcase-let ((`(,exit ,out ,clone ,origin) (+test-awf--github "push-ahead" "github-push.sh" :ahead t)))
    (should (eql exit 0))
    (should (string-match-p "pushed 1 commit(s): origin/main now" out))
    (should (equal (+test-awf--origin-main origin)
                   (let ((default-directory clone)) (string-trim (shell-command-to-string "git rev-parse HEAD"))))))
  (pcase-let ((`(,exit ,out) (+test-awf--github "push-none" "github-push.sh")))
    (should (eql exit 0))
    (should (string-match-p "nothing to push: origin/main has" out)))
  (pcase-let ((`(,exit ,out) (+test-awf--github "push-refused" "github-push.sh" :ahead t :behind t)))
    (should (eql exit 2))
    (should (string-match-p "refused (origin/main has commits your main hasn't)" out)))
  ;; Your checkout moved off main meanwhile: not pushed.
  (pcase-let ((`(,exit ,out ,clone ,origin) (+test-awf--github "push-off" "github-push.sh" :ahead t :off-main t)))
    (should (eql exit 2))
    (should (string-match-p "your checkout is on other now, not main" out))
    (should-not (equal (+test-awf--origin-main origin)
                       (let ((default-directory clone)) (string-trim (shell-command-to-string "git rev-parse HEAD")))))))

(ert-deftest agent-workflow-files/github-watch-sh ()
  "github-watch.sh: origin's main's runs green: 0; one failed: 1, its
failed jobs' lines; still running: watched until done; none at all: 0,
said; cancelled: 2."
  (pcase-let ((`(,exit ,out) (+test-awf--github "watch-green" "github-watch.sh"
                                                :runs "7\tcompleted\tsuccess\tTests\n8\tcompleted\tskipped\tLint\n")))
    (should (eql exit 0))
    (should (string-match-p "green: Tests, Lint passed" out)))
  (pcase-let ((`(,exit ,out) (+test-awf--github "watch-fail" "github-watch.sh"
                                                :runs "8\tcompleted\tfailure\tTests\n9\tcompleted\tsuccess\tLint\n")))
    (should (eql exit 1))
    (should (string-match-p "GitHub Actions failed on main" out))
    (should (string-match-p "== Tests: failure (gh run view 8)" out))
    (should (string-match-p "FAILED lexer/escapes" out))
    (should-not (string-match-p "Lint:" out)))
  ;; Waiting: where they are said, once each time it changes.
  (pcase-let ((`(,exit ,out) (+test-awf--github "watch-wait" "github-watch.sh" :pending 2
                                                :runs "10\tcompleted\tsuccess\tTests\n9\tcompleted\tfailure\tLint\n"
                                                :appear 60)))
    (should (eql exit 1))
    (let ((lines (split-string out "\n")))
      (should (string-match-p "\\`[0-9a-f]\\{7\\}: 0 of 1 done · Tests …\\'" (nth 0 lines)))
      (should (string-match-p "\\`[0-9a-f]\\{7\\}: 2 of 2 done · Tests ✓ · Lint ✗\\'" (nth 1 lines)))
      (should (string-prefix-p "GitHub Actions failed on main" (nth 2 lines)))))
  (pcase-let ((`(,exit ,out) (+test-awf--github "watch-late" "github-watch.sh" :pending 1
                                                :runs "10\tcompleted\tsuccess\tTests\n")))
    (should (eql exit 0))
    (should (string-match-p "green" out)))
  (pcase-let ((`(,exit ,out) (+test-awf--github "watch-none" "github-watch.sh")))
    (should (eql exit 0))
    (should (string-match-p "no GitHub Actions run" out)))
  (pcase-let ((`(,exit ,out) (+test-awf--github "watch-cancel" "github-watch.sh"
                                                :runs "11\tcompleted\tcancelled\tTests\n")))
    (should (eql exit 2))
    (should (string-match-p "was cancelled" out)))
  ;; gh asked about origin's own repository (-R), not its default one.
  (pcase-let ((`(,exit ,_out) (+test-awf--github "watch-repo" "github-watch.sh" :url "git@github.com:me/doom.git"
                                                 :runs "8\tcompleted\tfailure\tTests\n")))
    (should (eql exit 1))
    (let ((calls (with-temp-buffer
                   (insert-file-contents (expand-file-name "awf/watch-repo/args" +test-tmp))
                   (split-string (buffer-string) "\n" t))))
      (should (string-prefix-p "run list -R github.com/me/doom --commit " (car calls)))
      (should (equal (cadr calls) "run view -R github.com/me/doom 8 --log-failed")))))

(ert-deftest agent-workflow-files/check ()
  "M-x agent-workflow-check: every problem a line FILE:LINE: level: what,
visiting it; none: said. One file alone, anywhere."
  (let ((starters (+test-awf--dir "check-starters"))
        (project (+test-awf--project "check")))
    (+test-awf--file starters "agents/build.md" +test-awf--definition-text)
    (+test-awf--with-starters starters
      (let ((default-directory project))
        (+test-clear-messages)
        (should-not (agent-workflow-check))
        (should (= (+test-messages "\\`0 workflows, 1 agents, no problems$") 1))
        (+test-awf--file project ".agent-workflow/workflows/w.yml" "description: x\nnope: 1\njobs:\n  a:\n    agent: who\n")
        (let ((problems (agent-workflow-check)))
          (should (= (length problems) 2))
          (with-current-buffer "*agent-workflow check*"
            (should (string-match-p "1 error, 1 warning" (buffer-string)))
            (should (string-match-p "^\\.agent-workflow/workflows/w\\.yml:2: warning: unknown key nope: ignored$"
                                    (buffer-string)))
            (should (string-match-p "^\\.agent-workflow/workflows/w\\.yml:5: error: agent who: no such agent (build)$"
                                    (buffer-string)))
            (should (derived-mode-p 'compilation-mode))))
        (let ((draft (+test-awf--file (+test-awf--dir "drafts") "draft.yml" "description: x\njobs:\n  a:\n    agent: build\n")))
          (should-not (agent-workflow-check project draft)))))))

(defun +test-awf--request (op &optional payload)
  "OP's reply (parsed) as cmd/agent-workflow gets it, PAYLOAD its JSON,
from `default-directory'."
  (let ((dir (make-temp-file (+test-tmp-file "awf-request-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert op "\n" default-directory "\n"))
    (when payload
      (with-temp-file (expand-file-name "payload" dir) (insert payload)))
    (should (eq (agent-workflow-request dir) t))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "reply" dir))
      (json-parse-buffer :object-type 'plist :array-type 'list))))

(ert-deftest agent-workflow-files/check-from-the-shell ()
  "The request: the project's names and problems; ok false with an error;
one file alone; a file not there, an unknown operation: refused."
  (let ((starters (+test-awf--dir "request-starters"))
        (project (+test-awf--project "request")))
    (+test-awf--file starters "agents/build.md" +test-awf--definition-text)
    (+test-awf--file starters "workflows/quick.yml" "description: x\njobs:\n  a:\n    agent: build\n")
    (+test-awf--with-starters starters
      (let ((default-directory project))
        (let ((reply (+test-awf--request "check" "{}")))
          (should (eq (plist-get reply :ok) t))
          (should (equal (plist-get reply :project) (directory-file-name project)))
          (should (equal (plist-get reply :workflows) '("quick")))
          (should (equal (plist-get reply :agents) '("build")))
          (should (equal (plist-get reply :problems) nil)))
        (let* ((file (+test-awf--file project ".agent-workflow/workflows/w.yml" "description: x\njobs:\n  a:\n    agent: who\n"))
               (reply (+test-awf--request "check" "{}")))
          (should (eq (plist-get reply :ok) :false))
          (should (equal (plist-get reply :error) "1 error"))
          (should (equal (plist-get reply :problems)
                         (list (list :level "error" :file file :line 4 :message "agent who: no such agent (build)"))))
          (let ((alone (+test-awf--request "check" (json-serialize (list :file file)))))
            (should (equal (plist-get alone :workflows) nil))
            (should (= (length (plist-get alone :problems)) 1))))
        (should (string-match-p "no file" (plist-get (+test-awf--request "check" "{\"file\":\"/no/such.yml\"}") :error)))
        (should (equal (plist-get (+test-awf--request "launch") :error) "unknown operation \"launch\"; operations: run, done, back, confirm, approve, reject, continue, cancel, pause, unpause, dry-run, check, logs, status"))))))

(defmacro +test-awf--with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/awf-" t))
          (server-name "test")
          (process-environment
           (cons (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                 process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-awf--run (&rest args)
  "Run cmd/agent-workflow with ARGS in `default-directory': (STATUS .
OUTPUT). Asynchronously: this Emacs, its server, answers it meanwhile."
  (let* ((output (generate-new-buffer " *agent-workflow-run*"))
         (process (make-process :name "agent-workflow" :buffer output
                                :command (cons +test-awf-script args)
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *agent-workflow-stderr*"))))
    (with-timeout (30 (delete-process process) (ert-fail "cmd/agent-workflow didn't end"))
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(ert-deftest agent-workflow-files/the-script ()
  "cmd/agent-workflow check through Emacs's server: 0 without errors, 1
with; a file of its folder alone; wrong uses: 2, without Emacs."
  (let ((starters (+test-awf--dir "script-starters"))
        (project (+test-awf--project "script")))
    (+test-awf--file starters "agents/build.md" +test-awf--definition-text)
    (+test-awf--with-starters starters
      (let ((default-directory project))
        (should (equal (car (+test-awf--run)) 2))
        (should (equal (+test-awf--run "check" "a" "b")
                       '(2 . "{\"ok\":false,\"error\":\"check: unknown argument \\\"b\\\"; agent-workflow check [FILE]\"}")))
        (should (equal (+test-awf--run "confirm" "demo-1" "nope")
                       '(2 . "{\"ok\":false,\"error\":\"confirm: \\\"nope\\\" isn't go, accept, skip, stop or cancel\"}")))
        (should (equal (+test-awf--run "start")
                       '(2 . "{\"ok\":false,\"error\":\"unknown operation \\\"start\\\"; operations: run, done, back, confirm, approve, reject, continue, cancel, pause, unpause, dry-run, check, logs, status\"}")))
        (+test-awf--with-server
          ;; confirm ISSUE cancel (a run whose issue was closed by hand): past
          ;; the script, answered by Emacs (no run here: its error, not a
          ;; wrong use).
          (let ((run (+test-awf--run "confirm" "demo-1" "cancel")))
            (should (= (car run) 1))
            (should-not (string-search "isn't go" (cdr run))))
          (let ((run (+test-awf--run "check")))
            (should (= (car run) 0))
            (should (equal (plist-get (json-parse-string (cdr run) :object-type 'plist :array-type 'list) :agents)
                           '("build"))))
          (+test-awf--file project "w.yml" "description: x\njobs:\n  a:\n    agent: who\n")
          (let ((run (+test-awf--run "check" "w.yml")))
            (should (= (car run) 1))
            (let ((reply (json-parse-string (cdr run) :object-type 'plist :array-type 'list)))
              (should (equal (plist-get reply :error) "1 error"))
              (should (equal (plist-get (car (plist-get reply :problems)) :file)
                             (expand-file-name "w.yml" project))))))))))

;; ====== A DRY RUN ======

(defconst +test-awf--dry "description: x
for: [feature]
jobs:
  build:
    steps:
      - agent: build
      - run: make test
        retries: 1
  docs:
    needs: build
    if: (not (eq (issue-type) 'task))
    agent: build
  lint:
    needs: build
    agent: build
  review:
    needs: build
    agent: reader
    max-rounds: 1
    outcomes:
      approved: continue
      changes: rerun build
  merge:
    needs: [docs, lint, review]
    uses: merge
")

(defun +test-awf--dry-run (outcomes exits &optional type)
  "The dry run of `+test-awf--dry' with OUTCOMES and EXITS, its issue a
TYPE (default feature): its result."
  (let* ((workflow (car (+test-awf--workflow +test-awf--dry '("build" "reader") "dry.yml")))
         (definitions (list (cons "build" (list :name "build"))
                         (cons "reader" (list :name "reader" :deny '("Edit" "Write"))))))
    (should workflow)
    (agent-workflow--dry-run workflow :info (list :id "demo-1" :type (or type "feature"))
                            :outcomes outcomes :exits exits :definitions definitions :pool 3)))

(defun +test-awf--dry-lines (result)
  "All RESULT's lines."
  (apply #'append (plist-get result :waves)))

(ert-deftest agent-workflow-files/a-dry-run ()
  "Waves: what runs at once, what waits for the branch, a script fixed and
run again, a review's changes sending build back, the merge; nothing run."
  (let* ((result (+test-awf--dry-run '(("review" "changes" "approved")) '(("build.2" 1 0))))
         (lines (+test-awf--dry-lines result)))
    (should-not (plist-get result :stopped))
    (should (equal (car (plist-get result :waves))
                   '("build: its agent (build) works" "build: its step 2 returns 1: its agent fixes it, run again"
                     "build: its run step 2 passes (try 2)" "build: done (done)")))
    (should (member "at once: docs, review" lines))
    (should (member "lint: waits for docs, which edits the branch" lines))
    (should (member "review: changes: build and every job after it again" lines))
    (should (member "build: its agent (build) works, round 2" lines))
    (should (member "merge: merged, the issue closed" lines))
    (should (equal (cdr (assoc "merge" (plist-get result :end))) 'done))))

(ert-deftest agent-workflow-files/a-dry-run-of-a-project-not-trusted ()
  "A dry run of a project's workflow, the project not trusted: its if: not
evaluated (its Lisp would run), taken as true, said; trusted, evaluated
\(doom-38o.69)."
  (let* ((marker (+test-tmp-file (format "dry-marker-%d" (random 100000))))
         (project (file-name-as-directory (make-temp-file (+test-tmp-file "dry-project-") t)))
         (agent-workflow-trust-file (+test-tmp-file (format "trusted-%d.el" (random 100000))))
         (workflow (append (list :origin 'project)
                           (car (+test-awf--workflow (format "description: x
jobs:
  a:
    if: (progn (write-region \"x\" nil %S) nil)
    run: echo a
" marker))))))
    (should (plist-get (alist-get "a" (plist-get workflow :jobs) nil nil #'equal) :if))
    (let ((result (agent-workflow--dry-run workflow :info '(:id "demo-1" :type "task") :project project)))
      (should-not (file-exists-p marker))
      (should (member "a: its if not evaluated (the project's workflows aren't trusted: its Lisp would run), taken as true"
                      (+test-awf--dry-lines result)))
      (should (equal (cdr (assoc "a" (plist-get result :end))) 'done)))
    (agent-workflow-trust project)
    (let ((result (agent-workflow--dry-run workflow :info '(:id "demo-1" :type "task") :project project)))
      (should (file-exists-p marker))
      (should (equal (cdr (assoc "a" (plist-get result :end))) 'skipped)))))

(ert-deftest agent-workflow-files/a-dry-run-says-its-agent-s-kind ()
  "A step's agent on another kind than `agent-workflow-kind' (its step's,
else its agent file's): said."
  (let* ((workflow (car (+test-awf--workflow "description: x
jobs:
  build:
    agent: build
  review:
    needs: build
    agent: build
    kind: gemini-cli
" '("build") "kinds.yml")))
         (lines (+test-awf--dry-lines
                 (agent-workflow--dry-run workflow :info (list :id "demo-1" :type "feature")
                                          :definitions (list (cons "build" (list :name "build" :kind 'codex)))
                                          :pool 3))))
    (should (member "build: its agent (build, on codex) works" lines))
    (should (member "review: its agent (build, on gemini-cli) works" lines))))

(ert-deftest agent-workflow-files/its-branch ()
  "branch: delete or keep, read (none: delete, nil); another value an
error. A dry run says what happens to the branch once the run ends:
deleted once merged, kept with no merge or branch: keep; nothing if it
stops."
  (should-not (plist-get (car (+test-awf--workflow +test-awf--dry '("build" "reader") "dry.yml")) :branch))
  (should (eq (plist-get (car (+test-awf--workflow (concat "branch: keep\n" +test-awf--dry) '("build" "reader") "dry.yml"))
                         :branch)
              'keep))
  (pcase-let ((`(,workflow . ,problems)
               (+test-awf--workflow (concat "branch: maybe\n" +test-awf--dry) '("build" "reader") "dry.yml")))
    (should-not workflow)
    (should (member '(error 1 "branch maybe: delete (once merged: the default) or keep") (+test-awf--said problems))))
  (should (equal (plist-get (+test-awf--dry-run nil nil) :branch) "deleted, merged into the main branch"))
  (let ((definitions (list (cons "build" (list :name "build")))))
    (should (equal (plist-get (agent-workflow--dry-run
                               (car (+test-awf--workflow (concat "branch: keep\n" +test-awf--dry) '("build" "reader") "dry.yml"))
                               :info '(:id "demo-1" :type "feature") :definitions definitions :pool 3)
                              :branch)
                   "kept (branch: keep)"))
    (should (equal (plist-get (agent-workflow--dry-run
                               (car (+test-awf--workflow "description: x\njobs:\n  build:\n    agent: build\n" '("build") "dry.yml"))
                               :info '(:id "demo-1" :type "feature") :definitions definitions :pool 3)
                              :branch)
                   "kept: not merged into the main branch (no merge ran)")))
  (should-not (plist-get (+test-awf--dry-run '(("review" "changes")) nil) :branch))
  (should (string-suffix-p "Its branch: deleted, merged into the main branch.\n"
                           (agent-workflow--dry-text (+test-awf--dry-run nil nil)))))

(ert-deftest agent-workflow-files/a-dry-run-retry-from-and-exit-3 ()
  "A dry run of a step with retry-from: its 1 fixed, its job again from
that step (it runs again too, its own tries), the steps named; a 3: the
run fails."
  (let* ((workflow (car (+test-awf--workflow "description: x
jobs:
  green:
    steps:
      - run: check.sh
        name: check
      - run: push.sh
        name: push
      - run: watch.sh
        name: watch
        retries: 5
        retry-from: push
        on-fail: build
" '("build") "dry.yml")))
         (definitions (list (cons "build" (list :name "build"))))
         (dry (lambda (exits) (agent-workflow--dry-run workflow :info '(:id "demo-1" :type "task")
                                                      :exits exits :definitions definitions :pool 3))))
    (should (equal (car (plist-get (funcall dry '(("green.3" 1 1 0))) :waves))
                   '("green: its run step 1 (check) passes"
                     "green: its run step 2 (push) passes"
                     "green: its step 3 (watch) returns 1: an agent (build) fixes it, run again from step 2 (push)"
                     "green: its run step 2 (push) passes (try 2)"
                     "green: its step 3 (watch) returns 1: an agent (build) fixes it, run again from step 2 (push)"
                     "green: its run step 2 (push) passes (try 3)"
                     "green: its run step 3 (watch) passes (try 3)"
                     "green: done (done)")))
    (should (equal (plist-get (funcall dry '(("green.3" 1 1 1 1 1 1))) :stopped)
                   "green: its step 3 (watch) returns 1, its retries used up: it asks you"))
    (should (equal (plist-get (funcall dry '(("green.1" 3))) :stopped)
                   "green: its step 1 (check) returns 3: the run fails"))))

(ert-deftest agent-workflow-files/a-dry-run-stopping ()
  "Where it stops: the loop guard, retries used up; a job its if skips."
  (should (equal (plist-get (+test-awf--dry-run '(("review" "changes")) nil) :stopped)
                 "review: it sent build back 1 times: it asks you"))
  (should (equal (plist-get (+test-awf--dry-run nil '(("build.2" 1))) :stopped)
                 "build: its step 2 returns 1, its retries used up: it asks you"))
  (should (member "docs: skipped (its if)" (+test-awf--dry-lines (+test-awf--dry-run nil nil "task")))))
