;;; tests/unit/test-agent-workflow-files.el -*- lexical-binding: t; -*-
;; config/agent-workflow/: workflows (YAML) and profiles (Markdown) read and
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

(defun +test-awf--workflow (text &optional profiles name)
  "TEXT read as the workflow NAME (default feature.yml), its agent: and
on-fail: checked against PROFILES (default: build, review, docs):
\(WORKFLOW . PROBLEMS)."
  (agent-workflow-workflow-read (+test-awf--file (+test-awf--dir "read") (or name "feature.yml") text)
                                (or profiles '("build" "review" "docs"))))

(defun +test-awf--profile (text &optional name)
  "TEXT read as the profile NAME (default build.md): (PROFILE . PROBLEMS)."
  (agent-workflow-profile-read (+test-awf--file (+test-awf--dir "read") (or name "build.md") text)))

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
  "BODY with DIR the starters' folder (its workflows/ and profiles/), the
caches empty."
  (declare (indent 1))
  `(let ((agent-workflow-starters-directory ,dir)
         (agent-workflow--profiles-cache (make-hash-table :test #'equal))
         (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
     ,@body))

(defconst +test-awf--profile-text "---
description: builds an issue with its tests
---
Build it.
"
  "A profile with nothing but what it needs.")

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
              (error 4 "agent nobody: no such profile (build, review, docs)"))
             ("description: x\njobs:\n  a:\n    uses: deploy\n"
              (error 4 "uses deploy: not a built-in (merge)"))
             ("description: x\njobs:\n  a:\n    elisp: (oops\n"
              (error 4 "elisp (oops: Lisp (in YAML, a form with \": \" in it goes under elisp: |)"))
             ("description: x\njobs:\n  a:\n    shell: python\n    agent: build\n"
              (error 4 "shell: only for a run: step"))
             ("description: x\njobs:\n  a:\n    steps:\n      - run: x\n        on-fail: nobody\n"
              (error 6 "on-fail nobody: no such profile (build, review, docs)"))
             ("description: x\njobs:\n  a:\n    run: x\n    outcomes:\n      changes: rerun b\n"
              (error 6 "changes: rerun b: no such job (a)"))
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

(ert-deftest agent-workflow-files/profiles-not-checked-without-them ()
  "Read alone, with no profiles given, agent: and on-fail: name any."
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

;; ====== A PROFILE FILE ======

(ert-deftest agent-workflow-files/a-profile ()
  "Every key read: lists inline or as YAML items, a kebab-case mode as
Claude Code's id, the icon and its glyph, color as colour; the body its
instructions, with variables."
  (pcase-let ((`(,profile . ,problems)
               (+test-awf--profile "---
name: build
description: \"builds an issue with its tests\"
tools:
  - Read
  - 'Bash(git -C {main} commit:*)'
deny: [WebFetch]
model: opus
mode: accept-edits
icon: md-hammer ⚙
verb: building
color: blue
---

Build it on {branch}.
")))
    (should-not problems)
    (should (equal (plist-get profile :description) "builds an issue with its tests"))
    (should (equal (plist-get profile :tools) '("Read" "Bash(git -C {main} commit:*)")))
    (should (equal (plist-get profile :deny) '("WebFetch")))
    (should (equal (plist-get profile :model) "opus"))
    (should (equal (plist-get profile :mode) "acceptEdits"))
    (should (equal (plist-get profile :icon) "md-hammer"))
    (should (equal (plist-get profile :glyph) "⚙"))
    (should (equal (plist-get profile :verb) "building"))
    (should (equal (plist-get profile :colour) "blue"))
    (should (equal (plist-get profile :instructions) "Build it on {branch}."))))

(ert-deftest agent-workflow-files/a-profile-s-problems ()
  "Errors leave a profile out; warnings keep it."
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
    (pcase-let ((`(,profile . ,problems) (+test-awf--profile (car case))))
      (ert-info ((car case) :prefix "profile: ")
        (should-not profile)
        (should (member (cadr case) (+test-awf--said problems))))))
  (pcase-let ((`(,profile . ,problems)
               (+test-awf--profile "---\ndescription: x\ntools: Edit\ndeny: Edit\nlabels: build\nmodel: gpt\n---\n")))
    (should profile)
    (should (equal (+test-awf--said problems)
                   '((warning 4 "Edit both allowed (tools) and denied (deny): denied")
                     (warning 5 "unknown key labels: ignored")
                     (warning 6 "model gpt: not inherit, one of opus, sonnet, haiku, nor a model's id (claude-...)")
                     (warning 7 "no instructions after its front matter")))))
  (should (cdr (agent-workflow-profile-read
                (+test-awf--file (+test-awf--dir "bad-name") "Build.md" +test-awf--profile-text)))))

;; ====== A PROJECT'S ======

(ert-deftest agent-workflow-files/where-they-come-from ()
  "The starters, the project's, yours: a later one replacing one of the same
name, each saying where it's from; found from an agent's worktree too, read
from the main checkout; a workflow's agent: checked against them all."
  (let* ((starters (+test-awf--dir "starters"))
         (project (+test-awf--project "where")))
    (+test-awf--file starters "profiles/build.md" +test-awf--profile-text)
    (+test-awf--file starters "profiles/review.md" "---\ndescription: reviews\n---\nReview it.\n")
    (+test-awf--file starters "workflows/feature.yml" "description: starter\njobs:\n  a:\n    agent: build\n")
    (+test-awf--file starters "workflows/quick.yml" "description: quick\njobs:\n  a:\n    agent: review\n")
    (+test-awf--file project ".agent-workflow/profiles/review.md" "---\ndescription: the project's\n---\nx\n")
    (+test-awf--file project ".agent-workflow/workflows/feature.yaml"
                     "description: the project's\njobs:\n  a:\n    agent: docs\n")
    (+test-awf--file project ".agent-shell/agent-workflow/profiles/docs.md" "---\ndescription: mine\n---\nx\n")
    (+test-awf--file project ".agent-shell/agent-workflow/workflows/quick.yml"
                     "description: mine\njobs:\n  a:\n    agent: nobody\n")
    (+test-awf--file project ".agent-shell/agent-workflow/workflows/notes.txt" "not a workflow")
    (+test-awf--with-starters starters
      (let ((profiles (agent-workflow-profiles project))
            (workflows (agent-workflow-workflows project)))
        (should (equal (mapcar #'car profiles) '("build" "review" "docs")))
        (should (equal (mapcar (lambda (p) (plist-get (cdr p) :origin)) profiles) '(starter project local)))
        (should (eq (plist-get (alist-get "review" profiles nil nil #'equal) :replaces) 'starter))
        (should (equal (plist-get (alist-get "review" profiles nil nil #'equal) :description) "the project's"))
        ;; quick: yours, its agent nobody: left out, the starter's kept.
        (should (equal (mapcar #'car workflows) '("feature" "quick")))
        (should (equal (plist-get (alist-get "feature" workflows nil nil #'equal) :description) "the project's"))
        (should (eq (plist-get (alist-get "feature" workflows nil nil #'equal) :origin) 'project))
        (should (eq (plist-get (alist-get "quick" workflows nil nil #'equal) :origin) 'starter))
        (should (equal (+test-awf--said (agent-workflow-workflow-problems project))
                       '((error 4 "agent nobody: no such profile (build, review, docs)"))))
        ;; From an agent's worktree: the main checkout's.
        (let ((worktree (expand-file-name "wt" (+test-awf--dir "where-wt"))))
          (+test-awf--git project "worktree" "add" "-q" worktree)
          (+test-awf--file worktree ".agent-workflow/workflows/evil.yml" "description: x\njobs:\n  a:\n    run: x\n")
          (should (equal (agent-workflow-project worktree) project))
          (should (equal (mapcar #'car (agent-workflow-workflows (agent-workflow-project worktree)))
                         '("feature" "quick"))))))))

(ert-deftest agent-workflow-files/read-again-when-changed ()
  "A project's workflows are read again when a file changes, its profiles
too, else kept."
  (let ((starters (+test-awf--dir "again-starters"))
        (project (+test-awf--project "again")))
    (+test-awf--file starters "profiles/build.md" +test-awf--profile-text)
    (+test-awf--with-starters starters
      (let ((file (+test-awf--file project ".agent-workflow/workflows/w.yml"
                                   "description: one\njobs:\n  a:\n    agent: build\n")))
        (should (equal (plist-get (cdar (agent-workflow-workflows project)) :description) "one"))
        (+test-awf--file project ".agent-workflow/workflows/w.yml" "description: two\njobs:\n  a:\n    agent: build\n")
        (set-file-times file (time-add (current-time) 5))
        (should (equal (plist-get (cdar (agent-workflow-workflows project)) :description) "two"))
        ;; Its profile gone: left out, the project having none.
        (delete-file (expand-file-name "profiles/build.md" starters))
        (should-not (agent-workflow-workflows project))
        (should (equal (+test-awf--said (agent-workflow-workflow-problems project))
                       '((error 4 "agent build: no such profile (none)"))))))))

;; ====== CHECKING THEM ======

(ert-deftest agent-workflow-files/check ()
  "M-x agent-workflow-check: every problem a line FILE:LINE: level: what,
visiting it; none: said. One file alone, anywhere."
  (let ((starters (+test-awf--dir "check-starters"))
        (project (+test-awf--project "check")))
    (+test-awf--file starters "profiles/build.md" +test-awf--profile-text)
    (+test-awf--with-starters starters
      (let ((default-directory project))
        (+test-clear-messages)
        (should-not (agent-workflow-check))
        (should (= (+test-messages "\\`0 workflows, 1 profiles, no problems$") 1))
        (+test-awf--file project ".agent-workflow/workflows/w.yml" "description: x\nnope: 1\njobs:\n  a:\n    agent: who\n")
        (let ((problems (agent-workflow-check)))
          (should (= (length problems) 2))
          (with-current-buffer "*agent-workflow check*"
            (should (string-match-p "1 error, 1 warning" (buffer-string)))
            (should (string-match-p "^\\.agent-workflow/workflows/w\\.yml:2: warning: unknown key nope: ignored$"
                                    (buffer-string)))
            (should (string-match-p "^\\.agent-workflow/workflows/w\\.yml:5: error: agent who: no such profile (build)$"
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
    (+test-awf--file starters "profiles/build.md" +test-awf--profile-text)
    (+test-awf--file starters "workflows/quick.yml" "description: x\njobs:\n  a:\n    agent: build\n")
    (+test-awf--with-starters starters
      (let ((default-directory project))
        (let ((reply (+test-awf--request "check" "{}")))
          (should (eq (plist-get reply :ok) t))
          (should (equal (plist-get reply :project) (directory-file-name project)))
          (should (equal (plist-get reply :workflows) '("quick")))
          (should (equal (plist-get reply :profiles) '("build")))
          (should (equal (plist-get reply :problems) nil)))
        (let* ((file (+test-awf--file project ".agent-workflow/workflows/w.yml" "description: x\njobs:\n  a:\n    agent: who\n"))
               (reply (+test-awf--request "check" "{}")))
          (should (eq (plist-get reply :ok) :false))
          (should (equal (plist-get reply :error) "1 error"))
          (should (equal (plist-get reply :problems)
                         (list (list :level "error" :file file :line 4 :message "agent who: no such profile (build)"))))
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
    (+test-awf--file starters "profiles/build.md" +test-awf--profile-text)
    (+test-awf--with-starters starters
      (let ((default-directory project))
        (should (equal (car (+test-awf--run)) 2))
        (should (equal (+test-awf--run "check" "a" "b")
                       '(2 . "{\"ok\":false,\"error\":\"check: unknown argument \\\"b\\\"; agent-workflow check [FILE]\"}")))
        (should (equal (+test-awf--run "start")
                       '(2 . "{\"ok\":false,\"error\":\"unknown operation \\\"start\\\"; operations: run, done, back, confirm, approve, reject, continue, cancel, pause, unpause, dry-run, check, logs, status\"}")))
        (+test-awf--with-server
          (let ((run (+test-awf--run "check")))
            (should (= (car run) 0))
            (should (equal (plist-get (json-parse-string (cdr run) :object-type 'plist :array-type 'list) :profiles)
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
         (profiles (list (cons "build" (list :name "build"))
                         (cons "reader" (list :name "reader" :deny '("Edit" "Write"))))))
    (should workflow)
    (agent-workflow-dry-run workflow :info (list :id "demo-1" :type (or type "feature"))
                            :outcomes outcomes :exits exits :profiles profiles :pool 3)))

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

(ert-deftest agent-workflow-files/a-dry-run-stopping ()
  "Where it stops: the loop guard, retries used up; a job its if skips."
  (should (equal (plist-get (+test-awf--dry-run '(("review" "changes")) nil) :stopped)
                 "review: it sent build back 1 times: it asks you"))
  (should (equal (plist-get (+test-awf--dry-run nil '(("build.2" 1))) :stopped)
                 "build: its step 2 returns 1, its retries used up: it asks you"))
  (should (member "docs: skipped (its if)" (+test-awf--dry-lines (+test-awf--dry-run nil nil "task")))))
