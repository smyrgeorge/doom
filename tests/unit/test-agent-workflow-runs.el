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
                       "waiting" "state" "step-ended" "state" "job-done" "branch-deleted" "state" "run-done")))
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
      ;; Its worktree removed; its branch deleted (branch: delete, the
      ;; default): nothing in it the main branch hasn't.
      (should-not (file-exists-p (agent-workflow-worktree-directory project issue)))
      (should-not (string-match-p (concat "feat/" (regexp-quote issue) "-lexer-escapes")
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
                       "run: which issues? agent-workflow run ISSUE..., or a workflow with no ticket: agent-workflow run --workflow NAME"))))))

(ert-deftest agent-workflow-runs/done-with-one-argument ()
  "agent-workflow done with one argument: a word is the outcome (done
changes: changes, refused if it isn't one of its job's), text with spaces
the notes."
  (+test-awr "done-one"
    (let* ((issue (+test-awr--issue project "Done with one"))
           (run (agent-workflow-start-run project issue)))
      (+test-awr--finish run "build" nil "built")
      (let ((review (+test-awr--agent run "review")))
        (should (+test-awr--wait (lambda () (eq (+test-awr--job run "review") 'waiting))))
        (cl-letf (((symbol-function 'agent-workflow--request-caller) (lambda (_pid) review)))
          (should (string-match-p "Outcome nope: not one of done, approved, changes"
                                  (cadr (should-error (agent-workflow--request-done '(:outcome "" :notes "" :one "nope") 1)
                                                      :type 'user-error))))
          (let ((reply (agent-workflow--request-done '(:outcome "" :notes "" :one "changes") 1)))
            (should (equal (plist-get reply :outcome) "changes"))
            (should (equal (plist-get (agent-workflow--job run "review") :outcome) "changes"))))
        ;; Sent back to build: build done again, then review's notes as one argument.
        (+test-awr--finish run "build" nil "again")
        (let ((again (+test-awr--agent run "review")))
          (should (+test-awr--wait (lambda () (eq (+test-awr--job run "review") 'waiting))))
          (cl-letf (((symbol-function 'agent-workflow--request-caller) (lambda (_pid) again)))
            (should (equal (plist-get (agent-workflow--request-done '(:outcome "" :notes "" :one "looks good to me") 1)
                                      :outcome)
                           "done"))
            (should (equal (plist-get (agent-workflow--job run "review") :notes) "looks good to me"))))))))

(ert-deftest agent-workflow-runs/an-agent-freed-by-a-cancel ()
  "The pool full, a run waiting for an agent: another run cancelled, its
agent freed: the waiting run gets it, nothing else happening."
  (+test-awr "freed"
    (let* ((agent-workflow-pool 1)
           (a (agent-workflow-start-run project (+test-awr--issue project "A")))
           (b (progn (+test-awr--agent a "build")
                     (agent-workflow-start-run project (+test-awr--issue project "B")))))
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why b) "build: waiting for an agent: 1 of 1 work"))))
      (agent-workflow-cancel a)
      (should (+test-awr--agent b "build"))
      (agent-workflow-cancel b))))

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

(ert-deftest agent-workflow-runs/back-after-emacs-stopped-not-interrupted ()
  "Emacs stops while a run is queued (nothing of it running): read back, it
goes on by itself, to its end; one interrupted waits for you, nothing new
of it started."
  (+test-awr "restore-queued"
    (write-region "description: x
for: [chore]
jobs:
  a:
    run: echo a
  b:
    run: echo b
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (unwind-protect
        (let ((run (progn (agent-workflow-pause)
                          (agent-workflow-start-run project (+test-awr--issue project "Queued" "--type" "chore")))))
          (should (+test-awr--wait (lambda () (string-suffix-p "runs are paused" (or (agent-workflow-run-why run) "")))))
          ;; Emacs stops; started again, not paused.
          (setq agent-workflow--runs nil agent-workflow--paused nil)
          (let ((back (car (agent-workflow-restore project))))
            (should back)
            (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state back) 'done)) 10))))
      (setq agent-workflow--paused nil))
    ;; Interrupted: a's script was running; b, which could start, doesn't.
    (write-region "description: x
for: [chore]
jobs:
  a:
    run: sleep 30
  b:
    needs: c
    run: echo b
  c:
    run: sleep 30
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (let ((run (agent-workflow-start-run project (+test-awr--issue project "Interrupted" "--type" "chore"))))
      (should (+test-awr--wait (lambda () (and (eq (+test-awr--job run "a") 'running) (eq (+test-awr--job run "c") 'running)))))
      (agent-workflow--stop-all run)
      (setq agent-workflow--runs nil)
      ;; c ended meanwhile (as Emacs stopped), a still running: a interrupted.
      (let* ((dir (agent-workflow-run-dir run))
             (back (progn (let ((saved (agent-workflow--read-run dir)))
                            (agent-workflow--job-set saved "c" :status 'done)
                            (agent-workflow--save-state saved))
                          (car (agent-workflow-restore project)))))
        (should (equal (agent-workflow--interrupted back) '("a")))
        (+test-awr--wait (lambda () nil) 1)
        (should (eq (agent-workflow-run-state back) 'waiting))
        (should (eq (+test-awr--job back "b") 'pending))
        (agent-workflow-cancel back)))))

(ert-deftest agent-workflow-runs/interrupted-waiting-for-an-agent ()
  "A job whose agent step waits for a free agent (the pool full),
interrupted (its budget used up, paused now): it waits for you, not for an
agent; one freed starts nothing for it. Cancelled: the same."
  (+test-awr "pool-interrupted"
    (write-region "description: x
for: [chore]
jobs:
  a:
    steps:
      - run: echo a
      - agent: build
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (let* ((agent-workflow-pool 0)
           (run (agent-workflow-start-run project (+test-awr--issue project "Pool" "--type" "chore"))))
      (should (+test-awr--wait (lambda () (plist-get (agent-workflow--job run "a") :pool))))
      (agent-workflow--interrupt run "a")
      (should (eq (+test-awr--job run "a") 'waiting))
      (should-not (plist-get (agent-workflow--job run "a") :pool))
      ;; An agent free now: nothing started for it.
      (setq agent-workflow-pool 3)
      (agent-workflow-tick)
      (should-not (agent-workflow-agents project))
      (should (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'interrupted))
      ;; Waiting for one again (as it was), then cancelled: none for it.
      (agent-workflow--job-set run "a" :pool 1)
      (agent-workflow-cancel run)
      (should-not (plist-get (agent-workflow--job run "a") :pool))
      (agent-workflow-tick)
      (should-not (agent-workflow-agents project)))))

(ert-deftest agent-workflow-runs/its-concurrency-for-every-agent ()
  "A workflow's concurrency counts every agent of its runs, an on-fail one
too: one past it waits for an agent, saying why, and starts once one of its
workflow stops."
  (+test-awr "concurrency-fix"
    (write-region "description: x
for: [chore]
concurrency: 1
jobs:
  a:
    run: test -f ok.txt || { echo missing; exit 1; }
    retries: 1
    on-fail: build
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (let* ((agent-workflow-pool 5)
           (one-issue (+test-awr--issue project "One" "--type" "chore"))
           (one (agent-workflow-start-run project one-issue))
           (fixer (+test-awr--agent one "a"))
           (two (agent-workflow-start-run project (+test-awr--issue project "Two" "--type" "chore"))))
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why two) "a: waiting: chores at its limit, 1 of 1 agents"))))
      (should (= (length (seq-filter (lambda (agent) (buffer-live-p (agent-workflow-agent-buffer agent)))
                                     (agent-workflow-agents project)))
                 1))
      ;; One's fixed, done: two's agent starts.
      (write-region "x" nil (expand-file-name "ok.txt" (agent-workflow-worktree-directory project one-issue)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job one "a") 'waiting))))
      (agent-workflow-done fixer nil "wrote it")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state one) 'done))))
      (should (+test-awr--agent two "a"))
      (agent-workflow-cancel two))))

(ert-deftest agent-workflow-runs/back-from-m-x ()
  "M-x agent-workflow-back: the run picked (the only one), the job, the
note asked; sent back."
  (+test-awr "back-command"
    (let* ((issue (+test-awr--issue project "Back from M-x"))
           (run (agent-workflow-start-run project issue)))
      (+test-awr--finish run "build" nil "built")
      (+test-awr--agent run "review")
      (should (eq (agent-workflow--pick-run project) run))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "build"))
                ((symbol-function 'read-string) (lambda (&rest _) "again, please")))
        (call-interactively #'agent-workflow-back-command))
      (should (+test-awr--wait (lambda () (eql (plist-get (agent-workflow--job run "build") :round) 2))))
      (should (+test-awr--wait (lambda () (seq-some (lambda (prompt) (string-search "with this note: again, please" prompt))
                                                    (+test-awr--prompts "back-command")))))
      (agent-workflow-cancel run))))

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
      (should-not (agent-workflow-run-of project issue))
      ;; Its job running: cancelled (not left running), journaled, in status,
      ;; read back so after a restart; those that hadn't started, pending.
      (should (eq (+test-awr--job run "build") 'cancelled))
      (should (eq (+test-awr--job run "review") 'pending))
      (should (equal (plist-get (car (last (seq-filter (lambda (event) (equal (plist-get event :ev) "cancelled"))
                                                       (agent-workflow--journal-events (agent-workflow-run-dir run)))))
                                :jobs)
                     '("build")))
      (should (equal (mapcar (lambda (job) (list (plist-get job :name) (plist-get job :status)))
                             (plist-get (aref (plist-get (agent-workflow--request-status project (list :issue issue)) :runs) 0)
                                        :jobs))
                     '(("build" "cancelled") ("docs" "pending") ("review" "pending"))))
      (let ((back (agent-workflow--read-run (agent-workflow-run-dir run))))
        (should (eq (agent-workflow-run-state back) 'cancelled))
        (should (eq (plist-get (cdr (assoc "build" (agent-workflow-run-jobs back))) :status) 'cancelled))))))

;; ====== BUDGET ======

(defun +test-awr--spend (agent cost tokens)
  "AGENT's session as Claude Code says what it spent: COST dollars so far
\(its running total), a turn of TOKENS tokens over (its usage, a turn's)."
  (with-current-buffer (agent-workflow-agent-buffer agent)
    (let ((usage (copy-alist (map-elt agent-shell--state :usage))))
      (setf (alist-get :cost-amount usage) cost)
      (map-put! agent-shell--state :usage usage))
    (agent-shell--save-usage :state agent-shell--state :acp-usage `((totalTokens . ,tokens)))))

(ert-deftest agent-workflow-runs/budget ()
  "What a run spent: its agents' (a session's cost its running total, its
tokens every turn's, added up), kept as they stop, and its time not
waiting for you. Near its budget: said once. At it: its running steps
stopped, asked; go on with more: continued; kept with the run."
  (+test-awr "budget"
    (write-region (concat "budget:\n  cost: 10\n" +test-awr--feature) nil
                  (expand-file-name ".agent-workflow/workflows/feature.yml" project))
    (let* ((issue (+test-awr--issue project "Budget"))
           (run (agent-workflow-start-run project issue))
           (build (+test-awr--agent run "build")))
      (should (equal (agent-workflow-run-budget run) '(:cost 10 :tokens nil :time nil)))
      (+test-awr--spend build 3.0 1000)
      (should (equal (butlast (agent-workflow-run-spent-now run) 2) '(:cost 3.0 :tokens 1000)))
      (+test-awr--finish run "build" nil "built")
      ;; build's agent gone: what it spent kept.
      (should (equal (butlast (agent-workflow-run-spent-now run) 2) '(:cost 3.0 :tokens 1000)))
      (let ((review (+test-awr--agent run "review")))
        (should (+test-awr--wait (lambda () (agent-workflow-agent-session review))))
        (+test-awr--spend review 5.5 2000)
        (should (equal (butlast (agent-workflow-run-spent-now run) 2) '(:cost 8.5 :tokens 3000)))
        (agent-workflow-check-budget run)
        (should (agent-workflow-run-warned run))
        (should (member "budget-near" (+test-awr--journal run)))
        ;; Another turn: its tokens added to the first's (Claude Code says
        ;; a turn's), its cost the session's total so far.
        (+test-awr--spend review 7.5 3000)
        (should (equal (butlast (agent-workflow-run-spent-now run) 2) '(:cost 10.5 :tokens 6000)))
        ;; A turn without its total: nothing more.
        (with-current-buffer (agent-workflow-agent-buffer review)
          (agent-shell--save-usage :state agent-shell--state :acp-usage '((inputTokens . 4))))
        (should (equal (butlast (agent-workflow-run-spent-now run) 2) '(:cost 10.5 :tokens 6000)))
        (agent-workflow-check-budget run)
        (should (equal (agent-workflow-run-why run)
                       "review: its run's budget is used up ($10.50 of $10): go on with more, or stop?"))
        (should-not (buffer-live-p (agent-workflow-agent-buffer review))))
      ;; More: on again, its session resumed.
      (agent-workflow-confirm run "go" :more '(:cost 5))
      (should (equal (agent-workflow-run-budget run) '(:cost 15 :tokens nil :time nil)))
      (should (equal (agent-workflow-agent-resumed (+test-awr--agent run "review")) "mock-session"))
      ;; Its time: counted while it ran, not while it waited for you.
      (should (> (plist-get (agent-workflow-run-spent-now run) :time) 0))
      ;; Kept with it.
      (let ((saved (with-temp-buffer
                     (insert-file-contents (expand-file-name "state.json" (agent-workflow-run-dir run)))
                     (json-parse-buffer :object-type 'plist))))
        (should (equal (plist-get (plist-get saved :more) :cost) 5))
        (should (>= (plist-get (plist-get saved :spent) :cost) 10.5))
        ;; Every turn's tokens, review's kept as it stopped at its budget.
        (should (equal (plist-get (plist-get saved :spent) :tokens) 6000))))))

;; ====== CHANGED BY HAND ======

(ert-deftest agent-workflow-runs/changed-by-hand ()
  "Its issue edited: the next steps read it; its type changed: its workflow
kept, said; blocked anew: nothing new starts; closed: its steps stopped,
asked, go on: in progress again; a job's commits gone from the branch:
stopped, asked."
  (+test-awr "byhand"
    (let* ((issue (+test-awr--issue project "By hand"))
           (blocker (+test-awr--issue project "Blocker"))
           (run (agent-workflow-start-run project issue))
           (worktree (agent-workflow-worktree-directory project issue)))
      (+test-awr--agent run "build")
      ;; Its text, its type.
      (+test-awr--bd project "update" issue "--description" "Now with escapes." "--type" "bug")
      (agent-workflow-watch-run run)
      (should (equal (plist-get (agent-workflow-run-info run) :description) "Now with escapes."))
      (should (equal (plist-get (agent-workflow-run-workflow run) :name) "feature"))
      (should (member "issue-changed" (+test-awr--journal run)))
      ;; Closed by hand: build stopped, asked; go on: in progress, continued.
      (+test-awr--bd project "close" issue)
      (agent-workflow-watch-run run)
      (should (equal (agent-workflow-run-why run)
                     "build: its issue was closed by hand: go on (it's in progress again), or cancel the run?"))
      (should-not (plist-get (agent-workflow--job run "build") :agent))
      (agent-workflow-confirm run "go")
      (should (equal (alist-get 'status (+test-awr--shown project issue)) "in_progress"))
      (should (+test-awr--agent run "build"))
      ;; Its commit, then build done; a new blocker: nothing new starts (docs
      ;; first: its if holds now that the issue is a bug).
      (+test-awr--commit worktree "lexer.el" "Lexer")
      (+test-awr--bd project "dep" "add" issue blocker)
      (agent-workflow-watch-run run)
      (+test-awr--finish run "build" nil "built")
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why run)
                                                 (format "docs: waiting: its issue is blocked by %s" blocker)))))
      ;; Its branch reset by hand: build's commit gone.
      (let ((default-directory worktree)) (call-process "git" nil nil nil "reset" "-q" "--hard" "HEAD~1"))
      (+test-awr--bd project "close" blocker)
      (agent-workflow-watch-run run)
      (should (string-match-p "the commits of build aren't on the branch any more"
                              (or (agent-workflow-run-why run) ""))))))

;; ====== TRUST ======

(ert-deftest agent-workflow-runs/trust ()
  "A project's workflow runs once you trust it: refused unasked; asked, run
it (this once), trust it (remembered), or no; a starter's runs without."
  (+test-awr "trust"
    (agent-workflow-forget-trust project)
    (let ((one (+test-awr--issue project "One"))
          (two (+test-awr--issue project "Two"))
          (three (+test-awr--issue project "Three")))
      (should (equal (cadr (should-error (agent-workflow-start-run project one) :type 'user-error))
                     "trust's workflows run as you, and you don't trust it yet: M-x agent-workflow-trust in it"))
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) '(?n "no"))))
        (should-error (agent-workflow-start-run project one :ask t) :type 'user-error))
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) '(?y "run it"))))
        (should (agent-workflow-start-run project one :ask t)))
      (should-not (agent-workflow-trusted-p project))
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) '(?t "trust the project"))))
        (should (agent-workflow-start-run project two :ask t)))
      (should (agent-workflow-trusted-p project))
      (should (agent-workflow-start-run project three))
      ;; A starter: trusted.
      (agent-workflow-forget-trust project)
      (let ((starters (+test-tmp-file "awr/trust-starters/")))
        (make-directory (expand-file-name "workflows" starters) t)
        (copy-file (expand-file-name ".agent-workflow/workflows/feature.yml" project)
                   (expand-file-name "workflows/chores.yml" starters) t)
        (with-temp-buffer
          (insert-file-contents (expand-file-name "workflows/chores.yml" starters))
          (goto-char (point-min))
          (while (search-forward "for: [feature]" nil t) (replace-match "for: [chore]"))
          (write-region nil nil (expand-file-name "workflows/chores.yml" starters)))
        (let ((agent-workflow-starters-directory starters)
              (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
          (should (agent-workflow-start-run project (+test-awr--issue project "A chore" "--type" "chore"))))))))
