;;; tests/unit/test-agent-workflow-runs.el -*- lexical-binding: t; -*-
;; config/agent-workflow/runs.el, with beads.el and request.el: runs on
;; issues of a throwaway Beads project (skipped without bd), their jobs in
;; order, an agent step ended by its agent's done (stand-in sessions,
;; examples/agent-workspace/stand-in.el), a turn without it waiting for you;
;; an if skipping a job; refused, queued while blocked, the queue's order;
;; the journal, state.json, and what's written on the issue.
;; run.sh: split 2 (stand-in sessions, bd)

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-workflow")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workflow-kinds '(mock :config agent-shell-mock-agent-make-agent-config :claude-code t))
(load (expand-file-name "../helper-agent-workflow" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== A RUN ======

(ert-deftest agent-workflow-runs/a-run ()
  "Its jobs in order: build's agent, its first message filled in; its turn
ending without done, the run waits; done, the next job (an if not holding:
skipped), told what build said; every job done, the run is. Its journal,
its state.json, its workflow as it started; on the issue: in progress, its
job's label, its metadata, its notes."
  (+test-awr "run"
    (let* ((issue (+test-awr--issue project "Lexer escapes"))
           (run (agent-workflow-start-run project issue)))
      (should (equal (agent-workflow-run-name run) (concat issue " · feature")))
      (should (eq (agent-workflow-run-state run) 'queued))
      (should (file-exists-p (expand-file-name "workflow.yml" (agent-workflow-run-dir run))))
      (should (string-suffix-p (format ".agent-shell/agent-workflow/runs/%s/1/" issue) (agent-workflow-run-dir run)))
      ;; build: its agent, in progress.
      (let ((build (+test-awr--agent run "build")))
        (should build)
        (should (eq (agent-workflow-run-state run) 'running))
        (should (equal (agent-workflow-agent-name build) (concat issue " · build")))
        (let ((shown (+test-awr--shown project issue)))
          (should (equal (alist-get 'status shown) "in_progress"))
          (should (member "job:build" (alist-get 'labels shown))))
        ;; The stand-in answers and ends its turn, without done: it waits.
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'waiting))))
        (should (equal (agent-workflow-run-why run) "build: its agent ended its turn without saying it's done"))
        ;; Done now: build's over, its agent stopped; docs skipped; review starts.
        (should (equal (cdr (agent-workflow-done build nil "Built it, with its tests."))
                       (list "build" "done")))
        (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'done))))
        (should-not (buffer-live-p (agent-workflow-agent-buffer build)))
        (should (+test-awr--wait (lambda () (eq (+test-awr--job run "docs") 'skipped)))))
      (let ((review (+test-awr--agent run "review")))
        ;; Its first message, what build said filled in.
        (should (+test-awr--wait
                 (lambda () (seq-some (lambda (prompt) (string-match-p (concat "\\`Review " (regexp-quote issue)
                                                                               "\\. The builder said: Built it, with its tests\\.")
                                                                       prompt))
                                      (+test-awr--prompts "run")))))
        (should (equal (cadr (should-error (agent-workflow-done review "maybe" "") :type 'user-error))
                       "Outcome maybe: not one of done, approved, changes"))
        (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'waiting)))
        (agent-workflow-done review "approved" "Fine.")
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)))))
      (should (equal (+test-awr--journal run)
                     '("run-started" "job-started" "state" "step-starting" "step-started" "waiting" "state"
                       "step-ended" "state" "job-done" "job-skipped" "job-started" "step-starting" "step-started"
                       "waiting" "state" "step-ended" "state" "job-done" "state" "run-done")))
      (let ((state (with-temp-buffer
                     (insert-file-contents (expand-file-name "state.json" (agent-workflow-run-dir run)))
                     (json-parse-buffer :object-type 'plist :array-type 'list))))
        (should (equal (plist-get state :state) "done"))
        (should (equal (mapcar (lambda (job) (plist-get job :status)) (plist-get state :jobs))
                       '("done" "skipped" "done"))))
      (let ((shown (+test-awr--shown project issue)))
        (should-not (seq-some (lambda (label) (string-prefix-p "job:" label)) (alist-get 'labels shown)))
        (should (equal (alist-get 'workflow_state (alist-get 'metadata shown)) "done"))
        (should (equal (alist-get 'workflow_jobs (alist-get 'metadata shown)) "build:done,docs:skipped,review:done"))
        (should (string-match-p "build (done): Built it, with its tests\\." (alist-get 'notes shown)))
        (should (string-match-p "review (approved): Fine\\." (alist-get 'notes shown))))
      ;; Its worktree removed, its branch kept.
      (should-not (file-exists-p (agent-workflow-worktree-directory project issue)))
      (should (string-match-p (concat "feat/" (regexp-quote issue) "-lexer-escapes")
                              (with-output-to-string (call-process "git" nil standard-output nil "branch")))))))

(ert-deftest agent-workflow-runs/refused ()
  "A closed issue, an epic, one with a run already, one no workflow fits or
several do; a workflow named that isn't one."
  (+test-awr "refused"
    (let ((closed (+test-awr--issue project "Closed"))
          (epic (+test-awr--issue project "An epic" "--type" "epic"))
          (chore (+test-awr--issue project "A chore" "--type" "chore"))
          (one (+test-awr--issue project "One")))
      (+test-awr--bd project "close" closed)
      (cl-flet ((why (issue &rest args)
                  (cadr (should-error (apply #'agent-workflow-start-run project issue args) :type 'user-error))))
        (should (equal (why closed) (concat closed " is closed")))
        (should (equal (why epic) (concat epic " is an epic: its issues are run, not it")))
        (should (equal (why chore) (format "No workflow for a chore like %s (feature): --workflow NAME" chore)))
        (should (equal (why one :workflow "nope") "No workflow nope (feature)"))
        (agent-workflow-start-run project one)
        (should (equal (why one) (format "%s has a run already (%s · feature)" one one)))
        (write-region "description: x\nfor: [feature]\njobs:\n  a:\n    agent: build\n" nil
                      (expand-file-name ".agent-workflow/workflows/quick.yml" project))
        (let ((two (+test-awr--issue project "Two")))
          (should (equal (why two) (format "Several workflows fit %s, a feature: feature, quick (--workflow NAME)" two)))
          ;; Its label decides.
          (+test-awr--bd project "update" two "--add-label" "workflow:quick")
          (should (equal (plist-get (agent-workflow-run-workflow (agent-workflow-start-run project two)) :name)
                         "quick")))))))

(ert-deftest agent-workflow-runs/blocked-then-the-queue ()
  "A blocked issue's run is queued, saying by what, until its blockers
close; with one agent in the pool, a free agent goes to the highest
priority first, then the one started first."
  (+test-awr "queue"
    (let* ((agent-workflow-pool 1)
           (first (+test-awr--issue project "First" "--type" "feature" "--priority" "2"))
           (blocked (+test-awr--issue project "Blocked" "--type" "feature" "--priority" "1"
                                      "--deps" (concat "blocked-by:" first)))
           (a (agent-workflow-start-run project first))
           (b (agent-workflow-start-run project blocked)))
      (let ((build (+test-awr--agent a "build")))
        (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why b) (concat "blocked by " first)))))
        (let ((c (agent-workflow-start-run project (+test-awr--issue project "Urgent" "--type" "feature"
                                                                     "--priority" "0"))))
          (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why c) "build: waiting for an agent: 1 of 1 work"))))
          ;; first's build done: its review and c's build want the agent; c (P0) gets it.
          (+test-awr--wait (lambda () (eq (agent-workflow-run-state a) 'waiting)))
          (agent-workflow-done build nil "built")
          (should (+test-awr--agent c "build"))
          (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why a) "review: waiting for an agent: 1 of 1 work"))))
          (should (eq (+test-awr--job a "review") 'pending))
          ;; Its blocker closed: blocked no more, waiting for the agent.
          (+test-awr--bd project "close" first)
          (agent-workflow-tick)
          (should (equal (agent-workflow-run-why b) "build: waiting for an agent: 1 of 1 work")))))))

(ert-deftest agent-workflow-runs/from-the-shell ()
  "run: an epic's open issues started, the rest refused; done: only from an
agent's session."
  (+test-awr "shell"
    (let* ((epic (+test-awr--issue project "An epic" "--type" "epic"))
           (one (+test-awr--issue project "One" "--type" "feature" "--parent" epic))
           (two (+test-awr--issue project "Two" "--type" "chore" "--parent" epic))
           (dir (make-temp-file (+test-tmp-file "awr-request-") t)))
      (cl-flet ((request (op payload &optional pid)
                  (with-temp-file (expand-file-name "request" dir)
                    (insert op "\n" project "\n" (if pid (number-to-string pid) "") "\n"))
                  (with-temp-file (expand-file-name "payload" dir) (insert payload))
                  (agent-workflow-request dir)
                  (with-temp-buffer
                    (insert-file-contents (expand-file-name "reply" dir))
                    (json-parse-buffer :object-type 'plist :array-type 'list))))
        (let ((reply (request "run" (json-serialize (list :issues (vector epic))))))
          (should (eq (plist-get reply :ok) t))
          (should (equal (mapcar (lambda (s) (plist-get s :issue)) (plist-get reply :started)) (list one)))
          (should (equal (plist-get (car (plist-get reply :refused)) :issue) two)))
        (should (equal (plist-get (request "done" "{\"notes\":\"x\"}" (emacs-pid)) :error)
                       "done: only an agent of a run ends its step, from its own session"))
        (should (equal (plist-get (request "run" "{\"issues\":[]}") :error)
                       "run: which issues? agent-workflow run ISSUE..."))))))

;; ====== PARALLEL JOBS ======

(ert-deftest agent-workflow-runs/parallel-jobs ()
  "Jobs whose needs are done start at once: those that only read (their
profile denies Edit and Write) each on a snapshot of the branch, detached at
the commit it's at, removed after; one that edits in the issue's worktree,
the next that edits waiting for it, saying why. Each says the commit it
saw."
  (+test-awr "parallel"
    (write-region "---\ndescription: reads\ndeny: Edit, Write\n---\nRead it.\n" nil
                  (expand-file-name ".agent-workflow/profiles/reader.md" project))
    (write-region "description: x
for: [feature]
jobs:
  build:
    agent: build
  review:
    needs: build
    agent: reader
  security:
    needs: build
    agent: reader
  docs:
    needs: build
    agent: build
  tests:
    needs: build
    agent: build
" nil (expand-file-name ".agent-workflow/workflows/feature.yml" project))
    (let* ((agent-workflow-pool 5)
           (issue (+test-awr--issue project "Parallel"))
           (run (agent-workflow-start-run project issue))
           (worktree (agent-workflow-worktree-directory project issue)))
      (should (equal (agent-workflow-agent-worktree (+test-awr--agent run "build")) worktree))
      (+test-awr--finish run "build")
      ;; review, security and docs at once; tests waits for docs.
      (let ((review (+test-awr--agent run "review"))
            (security (+test-awr--agent run "security"))
            (docs (+test-awr--agent run "docs"))
            (head (let ((default-directory worktree)) (string-trim (shell-command-to-string "git rev-parse HEAD")))))
        (should (equal (agent-workflow-agent-worktree review) (agent-workflow-snapshot-directory project issue "review")))
        (should (equal (agent-workflow-agent-worktree security) (agent-workflow-snapshot-directory project issue "security")))
        (should (equal (agent-workflow-agent-commit review) head))
        (should (equal (agent-workflow-agent-worktree docs) worktree))
        (should-not (agent-workflow-agent-commit docs))
        ;; A snapshot: detached at the branch's commit.
        (let ((default-directory (agent-workflow-agent-worktree review)))
          (should (equal (string-trim (shell-command-to-string "git rev-parse HEAD")) head))
          (should (equal (string-trim (shell-command-to-string "git branch --show-current")) "")))
        (should (eq (+test-awr--job run "tests") 'pending))
        (should (equal (plist-get (agent-workflow--job run "tests") :why) "tests: waiting for docs, which edits the branch"))
        ;; What a reading agent's told.
        (should (string-match-p "change nothing and commit nothing"
                                (let ((agent-workflow--starting review)) (agent-workflow-agent-context))))
        (+test-awr--finish run "review")
        (should-not (file-exists-p (agent-workflow-snapshot-directory project issue "review")))
        (+test-awr--finish run "docs")
        (should (equal (agent-workflow-agent-worktree (+test-awr--agent run "tests")) worktree))
        (+test-awr--finish run "security")
        (+test-awr--finish run "tests")
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        ;; The commit each saw, in its journal.
        (should (seq-some (lambda (line) (and (string-match-p "\"ev\":\"job-started\"" line)
                                              (string-match-p "\"job\":\"review\"" line)
                                              (string-match-p (concat "\"commit\":\"" head "\"") line)))
                          (with-temp-buffer
                            (insert-file-contents (expand-file-name "journal.jsonl" (agent-workflow-run-dir run)))
                            (split-string (buffer-string) "\n" t))))))))

;; ====== GOING BACK ======

(ert-deftest agent-workflow-runs/going-back ()
  "Back to a job that ran, with a note: the branch kept; it and the jobs
that need it run again, a round more, the others keep their results; its
agent's session resumed, told the note and what the branch has; journaled,
said on the issue. Discarding: the branch back to where the job's round
started, what's lost said. Refused: a job that hasn't run, a step it
hasn't, from an agent's session."
  (+test-awr "back"
    (write-region "---\ndescription: reads\ndeny: Edit, Write\n---\nRead it.\n" nil
                  (expand-file-name ".agent-workflow/profiles/reader.md" project))
    (write-region "description: x
for: [feature]
jobs:
  build:
    agent: build
  lint:
    agent: reader
  review:
    needs: build
    agent: reader
" nil (expand-file-name ".agent-workflow/workflows/feature.yml" project))
    (let* ((agent-workflow-pool 4)
           (issue (+test-awr--issue project "Going back"))
           (run (agent-workflow-start-run project issue))
           (worktree (agent-workflow-worktree-directory project issue)))
      (should (equal (cadr (should-error (agent-workflow-back run "review") :type 'user-error))
                     (format "review hasn't run in %s · feature" issue)))
      (+test-awr--agent run "build")
      (+test-awr--commit worktree "lexer.el" "Lexer: escapes read")
      (+test-awr--finish run "build" nil "built")
      (+test-awr--finish run "lint")
      (+test-awr--agent run "review")
      (should (equal (cadr (should-error (agent-workflow-back run "build" :step 3) :type 'user-error))
                     "build has no step 3 (1 step)"))
      ;; Back to build: build and review replaced, lint kept.
      (should (equal (agent-workflow-back run "build" :note "handle the empty list too") '("build" "review")))
      (should (eq (+test-awr--job run "lint") 'done))
      (should (file-exists-p (expand-file-name "lexer.el" worktree)))
      (let ((build (+test-awr--agent run "build")))
        (should (equal (agent-workflow-agent-resumed build) "mock-session"))
        (should (eql (plist-get (agent-workflow--job run "build") :round) 2))
        (should (eql (plist-get (agent-workflow--job run "review") :round) 2))
        (should (eq (+test-awr--job run "review") 'pending))
        (should (+test-awr--wait
                 (lambda () (seq-some (lambda (prompt)
                                        (and (string-match-p "\\`The user sent the work back to you, build (round 2), with this note: handle the empty list too\\." prompt)
                                             (string-match-p "Lexer: escapes read" prompt)))
                                      (+test-awr--prompts "back"))))))
      (should (member "went-back" (+test-awr--journal run)))
      (should (string-match-p "Sent back to build by you: handle the empty list too"
                              (alist-get 'notes (+test-awr--shown project issue))))
      ;; Round 2's work, then back again, discarding it.
      (+test-awr--commit worktree "empty.el" "Lexer: the empty list")
      (should (equal (car (agent-workflow-back-lost run "build")) (list (car (process-lines "git" "-C" worktree "log" "--oneline" "-1")))))
      (agent-workflow-back run "build" :note "start this round over" :discard t)
      (should-not (file-exists-p (expand-file-name "empty.el" worktree)))
      (should (file-exists-p (expand-file-name "lexer.el" worktree)))
      (should (eql (plist-get (agent-workflow--job run "build") :round) 3))
      ;; Not from an agent's session.
      (let ((dir (make-temp-file (+test-tmp-file "awr-back-") t))
            (someone (+test-awr--agent run "build")))
        (with-temp-file (expand-file-name "request" dir) (insert "back\n" project "\n1\n"))
        (with-temp-file (expand-file-name "payload" dir)
          (insert (json-serialize (list :issue issue :job "build"))))
        (cl-letf (((symbol-function 'agent-workflow--request-caller) (lambda (_pid) someone)))
          (agent-workflow-request dir))
        (should (equal (plist-get (with-temp-buffer
                                    (insert-file-contents (expand-file-name "reply" dir))
                                    (json-parse-buffer :object-type 'plist))
                                  :error)
                       "back: yours to do, not an agent's"))))))

;; ====== LOOPS ======

(ert-deftest agent-workflow-runs/loops-and-their-guard ()
  "review's changes: rerun build, its notes the note: build and review
again, counted; past max-rounds, the run asks you; stop: it waits; go on:
the count starts again, each side told your note; a round that changed
nothing asks at once; accept: the run goes on as if continue."
  (+test-awr "loops"
    (write-region "---\ndescription: reads\ndeny: Edit, Write\n---\nRead it.\n" nil
                  (expand-file-name ".agent-workflow/profiles/reader.md" project))
    (write-region "description: x
for: [feature]
jobs:
  build:
    agent: build
  review:
    needs: build
    agent: reader
    max-rounds: 2
    outcomes:
      changes: rerun build
" nil (expand-file-name ".agent-workflow/workflows/feature.yml" project))
    (let* ((issue (+test-awr--issue project "Loops"))
           (run (agent-workflow-start-run project issue))
           (worktree (agent-workflow-worktree-directory project issue)))
      (cl-flet ((round (n &optional nothing)
                  ;; build's round N (a commit unless NOTHING), then review asks changes.
                  (+test-awr--wait (lambda () (eql (plist-get (agent-workflow--job run "build") :round) n)))
                  (+test-awr--agent run "build")
                  (unless nothing (+test-awr--commit worktree (format "r%d.el" n) (format "Round %d" n)))
                  (+test-awr--finish run "build" nil (format "round %d" n))
                  (let ((review (+test-awr--agent run "review")))
                    (should (+test-awr--wait (lambda () (eq (+test-awr--job run "review") 'waiting))))
                    (agent-workflow-done review "changes" (format "fix %d" n)))))
        (round 1)
        (should (+test-awr--wait (lambda () (eql (plist-get (agent-workflow--job run "build") :round) 2))))
        (should (+test-awr--wait
                 (lambda () (seq-some (lambda (prompt) (string-match-p "\\`review sent the work back to you, build (round 2), with this note: fix 1\\." prompt))
                                      (+test-awr--prompts "loops")))))
        (round 2)
        (round 3)
        ;; Sent back a third time, past max-rounds 2: asked.
        (should (+test-awr--wait (lambda () (agent-workflow-asking run))))
        (should (equal (agent-workflow-run-why run) "review: it sent build back 2 times: go on, accept it as it is, or stop?"))
        (should (equal (plist-get (cdr (agent-workflow-asking run)) :notes) '("fix 1" "fix 2" "fix 3")))
        (should (eq (+test-awr--job run "build") 'done))
        ;; Stop: it waits.
        (agent-workflow-confirm run "stop")
        (should (equal (agent-workflow-run-why run) "review: stopped by you"))
        ;; Go on, a note for each.
        (agent-workflow-confirm run "go" :notes '(("review" . "only bugs now") ("build" . "use a table")))
        (should (+test-awr--wait (lambda () (eql (plist-get (agent-workflow--job run "build") :round) 4))))
        (should (+test-awr--wait
                 (lambda () (seq-some (lambda (prompt) (string-match-p "fix 3\n\nThe user adds: use a table" prompt))
                                      (+test-awr--prompts "loops")))))
        ;; Round 4 changes nothing: asked at once.
        (round 4 t)
        (should (+test-awr--wait (lambda () (agent-workflow-asking run))))
        (should (equal (agent-workflow-run-why run)
                       "review: build's round 4 changed nothing on the branch: go on, accept it as it is, or stop?"))
        (should (seq-some (lambda (prompt) (string-match-p "\\`The user's note for you: only bugs now" prompt))
                          (+test-awr--prompts "loops")))
        ;; Accept: the run goes on, done.
        (agent-workflow-confirm run "accept")
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should (equal (seq-filter (lambda (ev) (member ev '("rerun" "asked" "answered"))) (+test-awr--journal run))
                       '("rerun" "rerun" "asked" "answered" "answered" "asked" "answered")))))))

;; ====== LIMITS ======

(ert-deftest agent-workflow-runs/limits ()
  "A workflow's concurrency: its agents at once; a job's: its runs at
once across issues, a script's too; waiting, saying why; another
workflow's runs beside them."
  (+test-awr "limits"
    (write-region "description: x
for: [feature]
concurrency: 1
jobs:
  build:
    agent: build
" nil (expand-file-name ".agent-workflow/workflows/feature.yml" project))
    (write-region "description: x
for: [chore]
jobs:
  check:
    run: sleep 2
    concurrency: 1
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (let* ((agent-workflow-pool 5)
           (a (agent-workflow-start-run project (+test-awr--issue project "A")))
           (b (agent-workflow-start-run project (+test-awr--issue project "B")))
           (c (agent-workflow-start-run project (+test-awr--issue project "C" "--type" "chore")))
           (d (agent-workflow-start-run project (+test-awr--issue project "D" "--type" "chore"))))
      (+test-awr--agent a "build")
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why b) "build: waiting: feature at its limit, 1 of 1 agents"))))
      ;; Another workflow beside it: its check runs, one at a time.
      (should (+test-awr--wait (lambda () (eq (+test-awr--job c "check") 'running))))
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why d) "check: waiting: check at its limit, 1 of 1"))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state c) 'done))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state d) 'done)) 10))
      ;; a's agent done: b's build starts.
      (+test-awr--finish a "build")
      (should (+test-awr--agent b "build")))))

;; ====== APPROVAL ======

(ert-deftest agent-workflow-runs/approval ()
  "A step marked approve waits, once done, for your OK, what to look at
said; rejected with a note: back to its agent, asked again once it's done;
approved: on. A script's result rejected: the run stops for you."
  (+test-awr "approval"
    (write-region "description: x
for: [feature]
jobs:
  build:
    agent: build
    approve: true
  check:
    needs: build
    steps:
      - run: echo checked
        approve: true
      - run: echo after
" nil (expand-file-name ".agent-workflow/workflows/feature.yml" project))
    (let* ((issue (+test-awr--issue project "Approval"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "build")))
      (+test-awr--commit (agent-workflow-worktree-directory project issue) "lexer.el" "Lexer")
      (+test-awr--finish-step run "build" "first try")
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why run)
                                                 "build: its result waits for your OK: approve it, or reject it with a note"))))
      (let ((look (agent-workflow-to-look-at run "build")))
        (should (equal (plist-get look :notes) "first try"))
        (should (string-match-p "lexer.el" (plist-get look :diff))))
      (should-error (agent-workflow-confirm run "go") :type 'user-error)
      ;; Rejected: its agent told, then asked again.
      (agent-workflow-reject run "name it lexer-escapes.el")
      (should (+test-awr--wait
               (lambda () (seq-some (lambda (prompt) (string-match-p "\\`The user rejected your result: name it lexer-escapes\\.el" prompt))
                                    (+test-awr--prompts "approval")))))
      (should (eq (plist-get (agent-workflow--job run "build") :agent) agent))
      (+test-awr--finish-step run "build" "renamed")
      (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
      (agent-workflow-approve run)
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'done))))
      ;; A script's: rejected, the run stops; skipped, on.
      (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
      (agent-workflow-reject run "not like this")
      (should (equal (agent-workflow-run-why run) "check: its result rejected by you (not like this): run it again, skip it, or stop?"))
      (agent-workflow-confirm run "skip")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (equal (seq-filter (lambda (ev) (member ev '("asked" "answered"))) (+test-awr--journal run))
                     '("asked" "answered" "asked" "answered" "asked" "answered" "answered"))))))

;; ====== RESUMING ======

(ert-deftest agent-workflow-runs/back-after-emacs-stopped ()
  "Emacs stops mid-run: read back, its running job interrupted, waiting;
continued, its agent's session resumed and told; its done job never run
again; its project noted; continued with the workflow as it is now."
  (+test-awr "restore"
    (let* ((issue (+test-awr--issue project "Restore"))
           (run (agent-workflow-start-run project issue)))
      (+test-awr--finish run "build" nil "built")
      (let ((review (+test-awr--agent run "review")))
        (should (+test-awr--wait (lambda () (agent-workflow-agent-session review))))
        (should (member project (agent-workflow--known-projects)))
        ;; Emacs stops.
        (agent-workflow--quit-h)
        (setq agent-workflow--runs nil)
        (let ((back (agent-workflow-restore project)))
          (should (= (length back) 1))
          (setq run (car back)))
        (should (eq (+test-awr--job run "build") 'done))
        (should (equal (agent-workflow-run-why run) "review: interrupted (Emacs stopped): continue it, skip its step, or stop?"))
        (should (equal (plist-get (agent-workflow-run-info run) :title) "Restore"))
        ;; The workflow changed meanwhile: continued with it as it is now.
        (write-region (concat +test-awr--feature "  extra:\n    needs: review\n    agent: build\n") nil
                      (expand-file-name ".agent-workflow/workflows/feature.yml" project))
        (agent-workflow-continue run :current t)
        (should (eq (+test-awr--job run "extra") 'pending))
        (let ((again (+test-awr--agent run "review")))
          (should (equal (agent-workflow-agent-resumed again) "mock-session"))
          (should (+test-awr--wait
                   (lambda () (seq-some (lambda (prompt) (string-match-p "\\`Your job, review, was interrupted (Emacs stopped) and goes on now" prompt))
                                        (+test-awr--prompts "restore"))))))
        (should (= (seq-count (lambda (ev) (equal ev "job-started")) (+test-awr--journal run)) 2))))))

(ert-deftest agent-workflow-runs/pause-and-cancel ()
  "Paused: nothing new starts, saying so; with now, a running script stopped,
interrupted, continued after: run again. Cancelled: its agents stopped, the
run over, its issue open again."
  (+test-awr "pause"
    (write-region "description: x
for: [chore]
jobs:
  check:
    run: sleep 1; echo slept
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (unwind-protect
        (progn
          (agent-workflow-pause)
          (let ((run (agent-workflow-start-run project (+test-awr--issue project "Paused" "--type" "chore"))))
            (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why run) "check: waiting: runs are paused"))))
            (agent-workflow-unpause)
            (should (+test-awr--wait (lambda () (eq (+test-awr--job run "check") 'running))))
            (agent-workflow-pause t)
            (should (equal (agent-workflow-run-why run) "check: interrupted (paused): continue it, skip its step, or stop?"))
            (agent-workflow-unpause)
            (agent-workflow-continue run)
            (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)) 10))
            (should (+test-aws--any-log run "slept"))))
      (setq agent-workflow--paused nil))
    (let* ((issue (+test-awr--issue project "Cancelled"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "build")))
      (agent-workflow-cancel run)
      (should (eq (agent-workflow-run-state run) 'cancelled))
      (should-not (buffer-live-p (agent-workflow-agent-buffer agent)))
      (should (equal (alist-get 'status (+test-awr--shown project issue)) "open"))
      (should-not (agent-workflow-run-of project issue)))))
