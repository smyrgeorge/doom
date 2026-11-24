;;; tests/unit/test-agent-workflow-steps.el -*- lexical-binding: t; -*-
;; config/agent-workflow/steps.el: run steps (their exit codes: next, fixed by
;; the job's agent or an on-fail one, broke; timeouts; retries used up, asked;
;; their environment; your checkout's copy of a script), elisp steps, and the
;; built-in merge (into your checkout, waiting for your changes, moving a
;; branch not checked out, a conflict). Runs on a throwaway Beads project
;; (skipped without bd), with stand-in agents (examples/agent-workspace/
;; stand-in.el).
;; run.sh: split 2 (stand-in sessions, bd)

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-workflow")
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workflow-kinds '(mock :config agent-shell-mock-agent-make-agent-config :claude-code t))
(load (expand-file-name "../helper-agent-workflow" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== HELPERS ======

(defun +test-aws--workflow (project text)
  "PROJECT's workflow feature: TEXT."
  (write-region text nil (expand-file-name ".agent-workflow/workflows/feature.yml" project)))

(defun +test-aws--log (run pattern)
  "Non-nil if a log of RUN has PATTERN."
  (seq-some (lambda (file) (with-temp-buffer (insert-file-contents file) (re-search-forward pattern nil t)))
            (directory-files (expand-file-name "logs" (agent-workflow-run-dir run)) t "\\.log\\'")))

(defun +test-aws--end (run)
  "RUN's branch's end, its last commit (:head, a commit) checked and left out."
  (let ((end (agent-workflow-run-branch-end run)))
    (should (string-match-p "\\`[0-9a-f]\\{40\\}\\'" (plist-get end :head)))
    (cl-loop for (key value) on end by #'cddr unless (eq key :head) append (list key value))))

(defun +test-aws--asks (run why)
  "Wait for RUN to ask WHY."
  (should (+test-awr--wait (lambda () (and (agent-workflow-asking run) (equal (agent-workflow-run-why run) why))))))

;; ====== RUN STEPS ======

(ert-deftest agent-workflow-steps/exit-1-fixed-by-the-job-s-agent ()
  "Exit 1: the output to the job's agent, which fixes it and says done; the
step runs again, passes; its output logged and journaled."
  (+test-awr "fixed"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  build:
    steps:
      - agent: build
      - run: test -f fixed.txt || { echo \"not fixed yet\"; exit 1; }
        retries: 2
")
    (let* ((issue (+test-awr--issue project "Fixed"))
           (run (agent-workflow-start-run project issue))
           (worktree (agent-workflow-worktree-directory project issue))
           (agent (+test-awr--agent run "build")))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'waiting))))
      (agent-workflow-done agent nil "built")
      ;; The script fails: its output sent to the same agent.
      (should (+test-awr--wait
               (lambda () (seq-some (lambda (prompt) (and (string-prefix-p (format "its step 2 (%s) returned 1 (try 1 of 3)"
                                                                                   (agent-workflow--short "test -f fixed.txt || { echo \"not fixed yet\"; exit 1; }"))
                                                                           prompt)
                                                          (string-match-p "not fixed yet" prompt)))
                                    (+test-awr--prompts "fixed")))))
      (should (+test-aws--log run "not fixed yet"))
      (should (eq (plist-get (agent-workflow--job run "build") :agent) agent))
      ;; Fixed, said done: run again, it passes.
      (write-region "x" nil (expand-file-name "fixed.txt" worktree))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'waiting))))
      (agent-workflow-done agent nil "fixed")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (equal (seq-filter (lambda (ev) (member ev '("script-ended" "fixing"))) (+test-awr--journal run))
                     '("script-ended" "fixing" "script-ended"))))))

(ert-deftest agent-workflow-steps/retry-from-an-earlier-step ()
  "A step with retry-from: its exit 1, fixed by the job's agent (told so),
runs its job again from that step: both run again, the second passes; its
tries counted on it; journaled, logged, the steps' names with them."
  (let ((pushes (make-temp-file "pushes")))
    (+test-awr "retryfrom"
      (+test-aws--workflow project (format "description: x
for: [feature]
jobs:
  green:
    steps:
      - agent: build
      - run: echo pushed >> %s
        name: push
      - run: test -f fixed.txt || { echo \"red\"; exit 1; }
        name: watch
        retries: 2
        retry-from: push
" pushes))
      (let* ((issue (+test-awr--issue project "Retry from"))
             (run (agent-workflow-start-run project issue))
             (worktree (agent-workflow-worktree-directory project issue))
             (agent (+test-awr--agent run "green")))
        (should (+test-awr--wait (lambda () (eq (+test-awr--job run "green") 'waiting))))
        (agent-workflow-done agent nil "built")
        (should (+test-awr--wait
                 (lambda () (seq-some (lambda (prompt)
                                        (and (string-prefix-p "its step 3, watch (" prompt)
                                             (string-match-p "returned 1 (try 1 of 3)" prompt)
                                             (string-match-p "its job runs again from its step 2 (push), then this one" prompt)))
                                      (+test-awr--prompts "retryfrom")))))
        (should (equal (with-temp-buffer (insert-file-contents pushes) (buffer-string)) "pushed\n"))
        (write-region "x" nil (expand-file-name "fixed.txt" worktree))
        (agent-workflow-done agent nil "fixed")
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        ;; The push ran again, then the watch passed.
        (should (equal (with-temp-buffer (insert-file-contents pushes) (buffer-string)) "pushed\npushed\n"))
        (let ((tries (plist-get (agent-workflow--job run "green") :tries)))
          (should (equal (alist-get 1 tries) 2))
          (should (equal (alist-get 2 tries) 2)))
        (should (equal (seq-filter (lambda (ev) (member ev '("script-ended" "fixing" "retry-from"))) (+test-awr--journal run))
                       '("script-ended" "script-ended" "fixing" "retry-from" "script-ended" "script-ended")))
        (with-temp-buffer
          (insert-file-contents (expand-file-name "log.txt" (agent-workflow-run-dir run)))
          (should (search-forward "step 3 (watch) fixed: run again from step 2 (push)" nil t))
          (goto-char (point-min))
          (should (search-forward "step 2 (push) started (run)" nil t)))))
    (delete-file pushes)))

(ert-deftest agent-workflow-steps/exit-3-fails-the-run ()
  "Exit 3: the run failed at once (no agent sent, nothing asked), its job
failed, the jobs after it never started, its issue open again; said as a
run needing you is; logged; read back failed, not restored; not sent back.
An elisp: step's agent-workflow-abort: the same."
  (+test-awr "fails"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    steps:
      - run: echo checking
      - run: echo \"gh isn't installed\" >&2; exit 3
        name: gh
  after:
    needs: check
    run: echo after > after.txt
")
    (let* ((issue (+test-awr--issue project "Fails"))
           (said nil)
           (agent-workflow-needs-you-functions (list (lambda (_run why) (push why said))))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'failed))))
      (should (equal (agent-workflow-run-why run) "check: its step 2, gh (echo \"gh isn't installed\" >&2; exit 3): gh isn't installed"))
      (should (eq (+test-awr--job run "check") 'failed))
      (should (eq (+test-awr--job run "after") 'pending))
      (should-not (agent-workflow-asking run))
      (should-not (agent-workflow-agents project))
      (should (member (concat "failed: " (agent-workflow-run-why run)) said))
      (should (equal (alist-get 'status (+test-awr--shown project issue)) "open"))
      (should (member "failed" (+test-awr--journal run)))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "log.txt" (agent-workflow-run-dir run)))
        (should (search-forward "run failed: check: its step 2, gh" nil t)))
      (should-error (agent-workflow--back run "check") :type 'user-error)
      ;; Read back (Emacs started again): failed, its job too; not restored.
      (let ((back (agent-workflow--read-run (agent-workflow-run-dir run))))
        (should (eq (agent-workflow-run-state back) 'failed))
        (should (eq (plist-get (cdr (assoc "check" (agent-workflow-run-jobs back))) :status) 'failed)))
      (should (memq 'failed agent-workflow--ended))))
  (+test-awr "aborts"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    elisp: (signal 'agent-workflow-abort '(\"no gh here\"))
")
    (let ((run (agent-workflow-start-run project (+test-awr--issue project "Aborts"))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'failed))))
      (should (string-match-p "no gh here" (agent-workflow-run-why run)))))
  ;; Another job startable beside it: the run failed stays failed, the
  ;; other not started after (it never came back to life, running).
  (+test-awr "aborts-beside"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  a:
    elisp: (signal 'agent-workflow-abort '(\"no gh here\"))
  b:
    run: echo b
")
    (let ((run (agent-workflow-start-run project (+test-awr--issue project "Aborts beside"))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'failed))))
      (+test-awr--wait (lambda () nil) 1)
      (should (eq (agent-workflow-run-state run) 'failed))
      (should (eq (+test-awr--job run "a") 'failed))
      (should (eq (+test-awr--job run "b") 'pending))
      (should-not (member "job-started" (cdr (member "failed" (+test-awr--journal run)))))
      ;; Set running again: refused, it's over.
      (agent-workflow--set-state run 'running)
      (should (eq (agent-workflow-run-state run) 'failed)))))

(ert-deftest agent-workflow-steps/broke-timeout-skip ()
  "Another exit code: it broke, asked (no agent sent); skip goes on. A
timeout: broke too; stop waits, skip after."
  (+test-awr "broke"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    steps:
      - run: exit 4
      - run: sleep 5
        timeout: 1s
      - run: echo fine
")
    (let ((run (agent-workflow-start-run project (+test-awr--issue project "Broke"))))
      (+test-aws--asks run "check: its step 1 (exit 4) broke (it returned 4): run it again, skip it, or stop?")
      (should-not (agent-workflow-agents project))
      (should-error (agent-workflow--confirm run "accept") :type 'user-error)
      (agent-workflow--confirm run "skip")
      (+test-aws--asks run "check: its step 2 (sleep 5) ran out of time: run it again, skip it, or stop?")
      (agent-workflow--confirm run "stop")
      (should (equal (agent-workflow-run-why run) "check: stopped by you"))
      (agent-workflow--confirm run "skip")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (+test-aws--log run "fine")))))

(ert-deftest agent-workflow-steps/retries-used-up-then-an-on-fail-agent ()
  "A script-only job, no retries: its first failure asked; go, with a note:
an agent with its on-fail agent started, told the output and your note;
fixed, run again."
  (+test-awr "onfail"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    run: test -f ok.txt || { echo missing ok.txt; exit 1; }
    on-fail: build
")
    (let* ((issue (+test-awr--issue project "On fail"))
           (run (agent-workflow-start-run project issue)))
      (+test-aws--asks run (format "check: its step 1 (%s) returned 1, its retries used up: go on, skip it, or stop?"
                                   (agent-workflow--short "test -f ok.txt || { echo missing ok.txt; exit 1; }")))
      (should-not (agent-workflow-agents project))
      (agent-workflow--confirm run "go" :notes '(("check" . "write ok.txt")))
      (let ((agent (+test-awr--agent run "check")))
        (should (equal (agent-workflow-agent-definition agent) "build"))
        (should (+test-awr--wait
                 (lambda () (seq-some (lambda (prompt) (and (string-match-p "missing ok.txt" prompt)
                                                            (string-match-p "The user adds: write ok.txt" prompt)))
                                      (+test-awr--prompts "onfail")))))
        (write-region "x" nil (expand-file-name "ok.txt" (agent-workflow-worktree-directory project issue)))
        (should (+test-awr--wait (lambda () (eq (+test-awr--job run "check") 'waiting))))
        (agent-workflow-done agent nil "wrote it"))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)))))))

(ert-deftest agent-workflow-steps/sent-back-while-its-on-fail-script-runs ()
  "Sent back while its on-fail script runs: the script stopped, the job
not left waiting on it (its agent heard again), nor an OK to a protected
merge kept for its next round (doom-38o.72)."
  (+test-awr "onfail-back"
    ;; Its first round fails, its next passes: a file outside its
    ;; worktree (a job's own, made again for its next round).
    (+test-aws--workflow project (format "description: x
for: [feature]
jobs:
  check:
    run: test -f %s || { touch %s; exit 1; }
    retries: 1
    on-fail:
      run: sleep 30
" (+test-tmp-file "onfail-back-ok") (+test-tmp-file "onfail-back-ok")))
    (let* ((issue (+test-awr--issue project "On fail back"))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (plist-get (agent-workflow--job run "check") :fix-script))))
      (agent-workflow--job-set run "check" :protected-ok t)
      (agent-workflow--back run "check")
      (should-not (plist-get (agent-workflow--job run "check") :fix-script))
      (should-not (plist-get (agent-workflow--job run "check") :protected-ok))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should-not (plist-get (agent-workflow--job run "check") :fix-script)))))

(ert-deftest agent-workflow-steps/a-script-printing-what-isnt-utf-8 ()
  "A script printing what isn't UTF-8: its step ends all the same, its
journal and state written, the bytes as U+FFFD (doom-38o.71)."
  (+test-awr "raw-bytes"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    run: printf 'bad \\377\\376 bytes\\n'
  later:
    needs: check
    run: printf 'cut \\342\\234'; exit 1
")
    (let* ((issue (+test-awr--issue project "Raw bytes"))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "check") 'done))))
      (should (+test-awr--wait (lambda () (plist-get (agent-workflow--job run "later") :ask))))
      (let ((journal (with-temp-buffer
                       (insert-file-contents (expand-file-name "journal.jsonl" (agent-workflow-run-dir run)))
                       (buffer-string)))
            (state (with-temp-buffer
                     (insert-file-contents (expand-file-name "state.json" (agent-workflow-run-dir run)))
                     (json-parse-buffer :object-type 'plist :null-object nil))))
        (should (string-search "bad \uFFFD\uFFFD bytes" journal))
        (should (string-search "cut \uFFFD"
                               (plist-get (plist-get (aref (plist-get state :jobs) 1) :ask) :output)))))))

(ert-deftest agent-workflow-steps/a-discard-refused-changes-nothing ()
  "Sent back discarding its work, its worktree gone (a done run's): refused
before anything changes, the run as it was; sent back after, without
discarding, it runs again (doom-38o.81)."
  (+test-awr "discard-refused"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    run: echo ok
")
    (let* ((issue (+test-awr--issue project "Discard refused"))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (when (file-directory-p (agent-workflow--work-directory run))
        (agent-workflow-worktree-remove project issue t))
      (should-error (agent-workflow--back run "check" :discard t) :type 'user-error)
      (should (eq (agent-workflow-run-state run) 'done))
      (should (eq (+test-awr--job run "check") 'done))
      (should-not (plist-get (agent-workflow--job run "check") :back))
      (should (equal (agent-workflow--back run "check") '("check")))
      ;; Running again, its time counted again, said (doom-38o.76).
      (should (agent-workflow-run-active-since run))
      (should (member "state" (seq-drop-while (lambda (e) (not (equal e "went-back"))) (+test-awr--journal run))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)))))))

(ert-deftest agent-workflow-steps/its-variables-filled ()
  "{output} the failing step's output, {try} its tries, {diff.stat} the
branch's changes against the main branch: filled for the agent fixing it
\(doom-38o.80)."
  (+test-awr "variables"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    run: test -f ok.txt || { echo missing ok.txt; exit 1; }
    retries: 1
    on-fail: build
")
    (let* ((issue (+test-awr--issue project "Variables"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "check"))
           (values (agent-workflow--agent-values agent)))
      (should (string-match-p "missing ok.txt" (cdr (assoc "output" values))))
      (should (equal (cdr (assoc "try" values)) "1"))
      (should (equal (cdr (assoc "diff.stat" values)) ""))
      (+test-awr--commit (agent-workflow-worktree-directory project issue) "lexer.el" "Lexer")
      (should (string-match-p "lexer.el | 1 +" (agent-workflow--diff-stat run))))))

(ert-deftest agent-workflow-steps/done-refused-during-a-script ()
  "Its agent saying done while its job's step is a script (a command it
left running, ending): refused, the script's step going on to its end
\(doom-38o.78)."
  (+test-awr "done-during-script"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  build:
    steps:
      - agent: build
      - run: sleep 2
")
    (let* ((issue (+test-awr--issue project "Done during a script"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "build")))
      (+test-awr--finish-step run "build")
      (should (+test-awr--wait (lambda () (eql (plist-get (agent-workflow--job run "build") :step) 1))))
      (should (string-match-p "isn't yours now"
                              (cadr (should-error (agent-workflow-done agent nil "again") :type 'user-error))))
      (should (eql (plist-get (agent-workflow--job run "build") :step) 1))
      (should (eq (+test-awr--job run "build") 'running))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)))))))

(ert-deftest agent-workflow-steps/a-skipped-job-read-again-when-sent-back ()
  "A job its if: skipped, then the job it needs sent back: pending again, its
if: read anew, its round kept; the dry run the same (doom-38o.84)."
  (let ((marker (+test-tmp-file (format "skipped-marker-%d" (random 100000)))))
    (+test-awr "skipped-back"
      (+test-aws--workflow project (format "description: x
for: [feature]
jobs:
  build:
    run: echo build
  docs:
    needs: build
    if: (file-exists-p %S)
    run: echo docs
" marker))
      (let* ((issue (+test-awr--issue project "Skipped back"))
             (run (agent-workflow-start-run project issue)))
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should (eq (+test-awr--job run "docs") 'skipped))
        (write-region "" nil marker)
        (should (equal (agent-workflow--back run "build") '("build" "docs")))
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should (eq (+test-awr--job run "docs") 'done))
        (should (eql (plist-get (agent-workflow--job run "docs") :round) 1))))))

(ert-deftest agent-workflow-steps/an-on-fail-script ()
  "on-fail: {run: ...}: a failed step's script first, FAILED_STEP and
FAILED_OUTPUT in its environment, its output a log of its own. Exit 0 it
fixed it: the step runs again, no agent. 1 it couldn't: to its on-fail
agent, told the step's output and the script's; with no agent, the run
asks you. Other, it broke: the run asks you."
  ;; It fixes it: no agent; the step run again, passing.
  (+test-awr "onfail-run"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    name: check
    run: test -f ok.txt || { echo missing ok.txt; exit 1; }
    retries: 2
    on-fail:
      run: 'echo \"fixing $FAILED_STEP: $FAILED_OUTPUT\"; touch ok.txt'
")
    (let* ((issue (+test-awr--issue project "On fail run"))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should-not (agent-workflow-agents project))
      (should (member "fix-script" (+test-awr--journal run)))
      (should (member "fix-script-ended" (+test-awr--journal run)))
      (should (+test-aws--log run "fixing check: missing ok.txt"))
      (should (seq-some (lambda (file) (string-suffix-p ".on-fail.log" file))
                        (directory-files (expand-file-name "logs" (agent-workflow-run-dir run)))))
      (should (eql (alist-get 0 (plist-get (agent-workflow--job run "check") :tries)) 2))))
  ;; It can't: its agent, told both.
  (+test-awr "onfail-both"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    run: test -f ok.txt || { echo missing ok.txt; exit 1; }
    retries: 1
    on-fail:
      run: echo cannot fix it; exit 1
      agent: build
")
    (let* ((issue (+test-awr--issue project "On fail both"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "check")))
      (should (equal (agent-workflow-agent-definition agent) "build"))
      (should (+test-awr--wait
               (lambda () (seq-some (lambda (prompt) (and (string-match-p "missing ok.txt" prompt)
                                                          (string-match-p "on-fail script ran first and couldn't fix it" prompt)
                                                          (string-match-p "cannot fix it" prompt)))
                                    (+test-awr--prompts "onfail-both")))))
      (write-region "x" nil (expand-file-name "ok.txt" (agent-workflow-worktree-directory project issue)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "check") 'waiting))))
      (agent-workflow-done agent nil "wrote it")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))))
  ;; It can't, no agent: it asks you; it broke: it asks you.
  (+test-awr "onfail-alone"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    run: echo nope; exit 1
    retries: 1
    on-fail:
      run: exit 1
  other:
    run: echo nope; exit 1
    retries: 1
    on-fail:
      run: exit 7
")
    (let* ((issue (+test-awr--issue project "On fail alone"))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "check") 'waiting))))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "other") 'waiting))))
      (should (string-match-p "its on-fail script couldn't fix it"
                              (plist-get (agent-workflow--job run "check") :why)))
      (should (string-match-p "its on-fail script broke (it returned 7)"
                              (plist-get (agent-workflow--job run "other") :why)))
      (should-not (agent-workflow-agents project))
      (agent-workflow--cancel run))))

(ert-deftest agent-workflow-steps/a-cancelled-run-s-worktree-removed ()
  "A run cancelled keeps its worktree; removed (M-x
agent-workflow-remove-worktree, asked first, saying what goes): its changes
not committed lost, its branch deleted with no commit of its own, else
kept; journaled. Not over, or nothing left: refused."
  (+test-awr "remove-worktree"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  build:
    run: sleep 30
")
    (let* ((one (+test-awr--issue project "No commit"))
           (run (agent-workflow-start-run project one))
           (asked nil))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'running))))
      (should-error (agent-workflow--remove-worktree run) :type 'user-error)
      (agent-workflow--cancel run)
      (should (agent-workflow--worktree-left-p run))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (question) (setq asked question) t)))
        (should (agent-workflow-remove-worktree run)))
      (should (string-match-p "deleted (no commit of its own)" asked))
      (should-not (file-exists-p (agent-workflow-worktree-directory project one)))
      (should (plist-get (agent-workflow-run-branch-end run) :deleted))
      (should (member "worktree-removed" (+test-awr--journal run)))
      (should-not (agent-workflow--worktree-left-p run)))
    ;; A commit of its own and a file not committed: the file lost, said;
    ;; its branch kept.
    (let* ((two (+test-awr--issue project "A commit"))
           (run (agent-workflow-start-run project two))
           (worktree (agent-workflow-worktree-directory project two))
           (asked nil))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'running))))
      (let ((default-directory worktree))
        (write-region "a" nil "a.txt")
        (call-process "git" nil nil nil "add" "a.txt")
        (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-qm" "a")
        (write-region "b" nil "b.txt"))
      (agent-workflow--cancel run)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (question) (setq asked question) t)))
        (agent-workflow-remove-worktree run))
      (should (string-match-p "Its 1 file not committed is lost" asked))
      (should (string-match-p "is kept (1 commit of its own)" asked))
      (should-not (file-exists-p worktree))
      (should (plist-get (agent-workflow-run-branch-end run) :why))
      (should (agent-workflow-issue-branch-made project two)))))

(ert-deftest agent-workflow-steps/a-cancelled-run-s-worktree-removed-by-itself ()
  "A run cancelled: its worktree removed by itself after
`agent-workflow-worktree-removal-delay' seconds, its pane counting down
(Keep worktree); its branch deleted (no commit of its own); its git line's
buttons gone with it. Keep worktree: it stays. Changes not committed: never
by itself."
  (+test-awr "auto-remove"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  build:
    run: sleep 30
")
    (let* ((agent-workflow-worktree-removal-delay 1)
           (one (+test-awr--issue project "Removed"))
           (run (agent-workflow-start-run project one)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'running))))
      (agent-workflow--cancel run)
      (should (agent-workflow-worktree-removal-time run))
      (let ((removal (nth 3 (agent-workflow--pane-git run (agent-workflow-run-where run t)))))
        (should (equal (plist-get removal :type) "countdown"))
        (should (equal (mapcar (lambda (a) (plist-get a :label)) (plist-get removal :actions)) '("Keep worktree"))))
      (should (+test-awr--wait (lambda () (not (agent-workflow--worktree-left-p run)))))
      (should (plist-get (agent-workflow-run-branch-end run) :deleted))
      (should (+test-aws--log-line run "its worktree removed, by itself, 1s after it ended\\'"))
      (let ((elements (agent-workflow--pane-git run (agent-workflow-run-where run t))))
        (should-not (plist-get (car elements) :actions))
        (should-not (nth 3 elements))))
    ;; Kept: it stays.
    (let* ((agent-workflow-worktree-removal-delay 1)
           (two (+test-awr--issue project "Kept"))
           (run (agent-workflow-start-run project two)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'running))))
      (agent-workflow--cancel run)
      (agent-workflow-keep-worktree run)
      (should-not (agent-workflow-worktree-removal-time run))
      (sleep-for 1.5)
      (should (agent-workflow--worktree-left-p run))
      (should (member "worktree-kept" (+test-awr--journal run))))
    ;; A change not committed: never by itself.
    (let* ((agent-workflow-worktree-removal-delay 1)
           (three (+test-awr--issue project "Changed"))
           (run (agent-workflow-start-run project three)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'running))))
      (write-region "x" nil (expand-file-name "new.txt" (agent-workflow-worktree-directory project three)))
      (agent-workflow--cancel run)
      (should-not (agent-workflow-worktree-removal-time run))
      (should (agent-workflow--worktree-left-p run)))
    ;; A new run on its issue before its time: its removal called off, the
    ;; worktree the new run's (doom-38o.70).
    (let* ((agent-workflow-worktree-removal-delay 1)
           (four (+test-awr--issue project "Again"))
           (run (agent-workflow-start-run project four)))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'running))))
      (agent-workflow--cancel run)
      (should (agent-workflow-worktree-removal-time run))
      (let ((again (agent-workflow-start-run project four)))
        (should-not (agent-workflow-worktree-removal-time run))
        (should (+test-awr--wait (lambda () (eq (+test-awr--job again "build") 'running))))
        (sleep-for 1.5)
        (should (file-exists-p (expand-file-name ".git" (agent-workflow-worktree-directory project four))))
        (should (eq (+test-awr--job again "build") 'running))
        (should-not (agent-workflow-run-branch-end again))
        ;; Nor the old run's to remove, even once the new one's over.
        (should-not (agent-workflow--worktree-left-p run))
        (agent-workflow--cancel again)
        (should-not (agent-workflow--worktree-left-p run))))))

(ert-deftest agent-workflow-steps/sent-back-to-a-step-once ()
  "A job sent back to its step 2: that round starts there; a later round of
it (its job before rerun, it with it) from its first step again."
  (+test-awr "back-step"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  build:
    run: echo build
  check:
    needs: build
    steps:
      - name: lint
        run: echo lint
      - name: test
        run: test -f ok.txt || exit 1
")
    (let* ((issue (+test-awr--issue project "Back to a step"))
           (run (agent-workflow-start-run project issue)))
      (cl-flet ((waits () (should (+test-awr--wait (lambda () (eq (+test-awr--job run "check") 'waiting)))))
                (starts ()
                  ;; Each round of check: the step it started from.
                  (let ((events (agent-workflow--journal-events (agent-workflow-run-dir run)))
                        (from nil) (started nil))
                    (dolist (event events)
                      (when (equal (plist-get event :job) "check")
                        (pcase (plist-get event :ev)
                          ("job-started" (setq started t))
                          ("step-starting" (when started (push (plist-get event :step) from) (setq started nil))))))
                    (nreverse from))))
        (waits)
        (agent-workflow--back run "check" :step 1)
        (should (+test-awr--wait (lambda () (equal (starts) '(0 1)))))
        (waits)
        (agent-workflow--back run "build" :step 0)
        (should (+test-awr--wait (lambda () (equal (starts) '(0 1 0)))))
        (waits)
        (should-not (plist-get (plist-get (agent-workflow--job run "check") :back) :step))))))

(ert-deftest agent-workflow-steps/rerun-of-a-job-skipped ()
  "An outcome rerunning a job its if: skipped: nothing to send back to; the
job waits for you, saying so (not left running); skipped, on as if done.
A rerun of a job it needs, directly or not, passes the check."
  (should (equal (sort (agent-workflow--before '(("review" "security") ("security" "build") ("build")) "review") #'string<)
                 '("build" "security")))
  (+test-awr "rerun-skipped"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  security:
    if: (member \"security\" (issue-labels))
    run: echo security
  review:
    needs: security
    agent: review
    outcomes:
      insecure: rerun security
")
    (let* ((issue (+test-awr--issue project "Rerun skipped"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "review")))
      (should (eq (+test-awr--job run "security") 'skipped))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run "review") 'waiting))))
      (agent-workflow-done agent "insecure" "not safe")
      (+test-aws--asks run "review: its outcome insecure reruns security, which hasn't run (skipped): run its step again, skip it (on as if done), or stop?")
      (agent-workflow--confirm run "skip")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)))))))

(ert-deftest agent-workflow-steps/a-script-that-can-t-start ()
  "A run: step whose interpreter isn't there: its step broke, the run
asking (not its job left running)."
  (+test-awr "cant-start"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    shell: no-such-interpreter-here
    run: print('x')
")
    (let ((run (agent-workflow-start-run project (+test-awr--issue project "Can't start"))))
      (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'broke))))
      (should (string-match-p "\\`check: its step 1 can't start: .*no-such-interpreter-here" (agent-workflow-run-why run)))
      (should (eq (+test-awr--job run "check") 'waiting))
      (should-not (plist-get (agent-workflow--job run "check") :process))
      (agent-workflow--cancel run))))

(ert-deftest agent-workflow-steps/a-fix-interrupted ()
  "A failed step's agent fixing it, interrupted (budget, pause now):
continued, the step runs afresh, once, then the next; skipped, the next at
once (not the step again)."
  (dolist (answer '(continue skip))
    (+test-awr (format "fix-interrupted-%s" answer)
      (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    steps:
      - name: test
        run: test -f ok.txt || { echo missing; exit 1; }
        retries: 1
        on-fail: build
      - name: next
        run: echo next
")
      (let* ((issue (+test-awr--issue project "Fix interrupted"))
             (run (agent-workflow-start-run project issue)))
        (+test-awr--agent run "check")
        (agent-workflow--interrupt run "check")
        (should-not (plist-get (agent-workflow--job run "check") :retry))
        (write-region "x" nil (expand-file-name "ok.txt" (agent-workflow-worktree-directory project issue)))
        (pcase answer
          ('continue (agent-workflow--continue run))
          ('skip (agent-workflow--confirm run "skip")))
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        ;; After the interrupt: test run once (continued) or not (skipped).
        (let ((after (cdr (member "interrupted" (mapcar (lambda (event)
                                                          (if (equal (plist-get event :ev) "step-started")
                                                              (format "started %s" (plist-get event :step))
                                                            (plist-get event :ev)))
                                                        (agent-workflow--journal-events (agent-workflow-run-dir run)))))))
          (should (equal (seq-filter (lambda (ev) (string-prefix-p "started" ev)) after)
                         (if (eq answer 'continue) '("started 0" "started 1") '("started 1")))))))))

(ert-deftest agent-workflow-steps/environment-shell-and-your-copy ()
  "A script's environment; shell: its interpreter; a script of
.agent-workflow/ run from your checkout, not the branch."
  (+test-awr "env"
    (make-directory (expand-file-name ".agent-workflow/scripts" project) t)
    (write-region "echo from your checkout\n" nil (expand-file-name ".agent-workflow/scripts/check.sh" project))
    (set-file-modes (expand-file-name ".agent-workflow/scripts/check.sh" project) #o755)
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  check:
    steps:
      - shell: python3
        run: |
          import os
          print(\"env\", os.environ[\"ISSUE\"], os.environ[\"JOB\"], os.environ[\"BRANCH\"], os.environ[\"MAIN_BRANCH\"], os.environ[\"TRY\"])
      - run: .agent-workflow/scripts/check.sh
")
    (let* ((issue (+test-awr--issue project "Env"))
           (run (agent-workflow-start-run project issue)))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (+test-aws--log run (format "^env %s check feat/%s-env %s 1$" (regexp-quote issue) (regexp-quote issue)
                                          (agent-workflow-main-branch project))))
      (should (+test-aws--log run "^from your checkout$")))))

;; ====== LISP ======

(ert-deftest agent-workflow-steps/elisp ()
  "Lisp in your Emacs, the run's helpers bound: returning goes on;
agent-workflow-fail is exit 1 (asked, no retries); another error broke."
  (+test-awr "elisp"
    (+test-aws--workflow project "description: x
for: [feature]
jobs:
  lisp:
    steps:
      - elisp: (setq +test-aws--seen (list (issue-id) (issue-type) default-directory))
      - elisp: (signal 'agent-workflow-fail '(\"not good\"))
      - elisp: (car 1)
")
    (defvar +test-aws--seen nil)
    (let* ((issue (+test-awr--issue project "Lisp"))
           (run (agent-workflow-start-run project issue)))
      (+test-aws--asks run "lisp: its step 2 (elisp) returned 1, its retries used up: go on, skip it, or stop?")
      (should (equal (butlast +test-aws--seen) (list issue 'feature)))
      (should (string-prefix-p (agent-workflow-snapshot-directory project issue "lisp") (nth 2 +test-aws--seen)))
      (agent-workflow--confirm run "skip")
      (+test-aws--asks run "lisp: its step 3 (elisp) broke (it returned 2): run it again, skip it, or stop?")
      (agent-workflow--confirm run "skip")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)))))))

;; ====== MERGE ======

(defconst +test-aws--merge "description: x
for: [feature]
jobs:
  build:
    agent: build
  merge:
    needs: build
    uses: merge
    with:
      suite: test -f lexer.el
    on-fail: build
")

(defun +test-aws--build (run project issue file text)
  "RUN's build: its agent commits FILE with TEXT, says done."
  (let ((agent (+test-awr--agent run "build"))
        (worktree (agent-workflow-worktree-directory project issue)))
    (let ((default-directory worktree))
      (write-region text nil file)
      (call-process "git" nil nil nil "add" file)
      (call-process "git" nil nil nil "-c" "user.name=A" "-c" "user.email=a@a" "commit" "-q" "-m" (concat "Add " file)))
    (should (+test-awr--wait (lambda () (eq (+test-awr--job run "build") 'waiting))))
    (agent-workflow-done agent nil "built")))

(ert-deftest agent-workflow-steps/merge-into-your-checkout ()
  "Tried with its suite, then merged into your checkout's main branch;
waiting first for your change to a file it changes; the issue closed."
  (+test-awr "merge"
    (+test-aws--workflow project +test-aws--merge)
    (let* ((issue (+test-awr--issue project "Merged"))
           (run (agent-workflow-start-run project issue))
           (main (agent-workflow-main-branch project)))
      ;; A change of yours to the file it adds.
      (write-region "mine\n" nil (expand-file-name "lexer.el" project))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (+test-aws--asks run "merge: its merge waits: your checkout has changes in lexer.el: commit or stash them, then go")
      (delete-file (expand-file-name "lexer.el" project))
      (agent-workflow--confirm run "go")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (let ((default-directory project))
        (should (equal (string-trim (shell-command-to-string "git branch --show-current")) main))
        (should (file-exists-p (expand-file-name "lexer.el" project)))
        (should (string-match-p (concat "Merge feat/" (regexp-quote issue)) (shell-command-to-string "git log -1 --format=%s"))))
      (should (equal (alist-get 'status (+test-awr--shown project issue)) "closed"))
      (should-not (file-exists-p (agent-workflow-snapshot-directory project issue "merge-try"))))))

(ert-deftest agent-workflow-steps/your-commit-while-its-suite-ran ()
  "Main checked out in your checkout, your commit there while the merge's
suite ran: never merged blind there: tried again on it (here a conflict:
its agent asked to rebase); your checkout never left mid-merge."
  (+test-awr "checkout-moved"
    (+test-aws--workflow project (replace-regexp-in-string "suite: test -f lexer.el" "suite: sleep 2; test -f lexer.el"
                                                           +test-aws--merge))
    (let* ((issue (+test-awr--issue project "Yours meanwhile"))
           (run (agent-workflow-start-run project issue))
           (default-directory project))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (should (+test-awr--wait (lambda () (process-live-p (plist-get (agent-workflow--job run "merge") :process)))))
      (+test-awr--commit project "lexer.el" "your lexer")
      (should (+test-awr--wait (lambda () (seq-some (lambda (prompt) (string-match-p "Rebase it onto" prompt))
                                                    (+test-awr--prompts "checkout-moved")))
                               30))
      (should (member "main-moved" (+test-awr--journal run)))
      (should-not (file-exists-p (expand-file-name (agent-workflow--git "rev-parse" "--git-path" "MERGE_HEAD"))))
      ;; Nothing of a merge left there (the project's own workflow files
      ;; aside, never committed here).
      (should-not (seq-remove (lambda (line) (string-prefix-p "?? " line)) (agent-workflow--git-lines "status" "--porcelain")))
      (should (equal (agent-workflow--git "log" "-1" "--format=%s") "your lexer"))
      (agent-workflow--cancel run))))

(ert-deftest agent-workflow-steps/merge-a-branch-not-checked-out ()
  "The main branch checked out nowhere: moved to the merge, no tree
touched."
  (+test-awr "moved"
    (+test-aws--workflow project +test-aws--merge)
    (let* ((issue (+test-awr--issue project "Moved"))
           (main (agent-workflow-main-branch project))
           (run (agent-workflow-start-run project issue)))
      (let ((default-directory project)) (call-process "git" nil nil nil "checkout" "-q" "-b" "elsewhere"))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (let ((default-directory project))
        (should-not (file-exists-p (expand-file-name "lexer.el" project)))
        (should (equal (shell-command-to-string (format "git show %s:lexer.el" main)) "theirs\n"))))))

(defun +test-aws--log-line (run pattern)
  "Non-nil if a line of RUN's log has PATTERN."
  (seq-some (lambda (line) (string-match-p pattern line)) (agent-workflow-log-lines run)))

(ert-deftest agent-workflow-steps/main-moved-while-its-suite-ran ()
  "Main checked out nowhere, moved while the merge's suite ran (another run
merged): not overwritten, the merge tried again on it; both on main."
  (+test-awr "main-moved"
    (+test-aws--workflow project (replace-regexp-in-string "suite: test -f lexer.el" "suite: sleep 2; test -f lexer.el"
                                                           +test-aws--merge))
    (let* ((issue (+test-awr--issue project "Moved"))
           (main (agent-workflow-main-branch project))
           (run (agent-workflow-start-run project issue))
           (default-directory project))
      (call-process "git" nil nil nil "checkout" "-q" "-b" "elsewhere")
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      ;; Its suite running: main moves.
      (should (+test-awr--wait (lambda () (process-live-p (plist-get (agent-workflow--job run "merge") :process)))))
      (let ((other (agent-workflow--git "commit-tree" "-p" main "-m" "Another run's merge"
                                        (agent-workflow--git "rev-parse" (concat main "^{tree}")))))
        (agent-workflow--git "update-ref" (concat "refs/heads/" main) other)
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done)) 30))
        (should (eql 0 (call-process "git" nil nil nil "merge-base" "--is-ancestor" other main)))
        (should (equal (agent-workflow--git "show" (concat main ":lexer.el")) "theirs"))
        (should (+test-aws--log-line run "moved while its merge was tried: tried again on it"))))))

(ert-deftest agent-workflow-steps/its-branch-deleted-once-merged ()
  "A run done, merged (your checkout on another branch): its branch
deleted, its log saying so; its pane's where and status's too."
  (+test-awr "branch-deleted"
    (+test-aws--workflow project +test-aws--merge)
    (let* ((issue (+test-awr--issue project "Deleted"))
           (main (agent-workflow-main-branch project))
           (run (agent-workflow-start-run project issue))
           (branch (agent-workflow-issue-branch issue "feature" "Deleted")))
      (let ((default-directory project)) (call-process "git" nil nil nil "checkout" "-q" "-b" "elsewhere"))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should-not (agent-workflow-issue-branch-made project issue))
      (should (equal (+test-aws--end run) (list :branch branch :deleted t :into main)))
      (should (+test-aws--log-line run (format "its branch %s deleted, merged into %s\\'" (regexp-quote branch) main)))
      (let ((where (agent-workflow-run-where run t)))
        (should (equal (plist-get where :branch) branch))
        (should (plist-get where :deleted))
        (should (equal (agent-workflow--pane-git-line where) (format "⎇ %s   deleted, merged into %s" branch main)))
        ;; Its files and commits still: read up to its last commit, kept.
        (should (equal (mapcar (lambda (file) (plist-get file :path)) (plist-get where :files)) '("lexer.el")))
        (should (plist-get where :commits)))
      ;; A run before its last commit was kept: found from its merge (Merge
      ;; BRANCH ...: its second parent); a branch with no such merge, none.
      (let ((default-directory project)
            (head (plist-get (agent-workflow-run-branch-end run) :head)))
        (should (equal (agent-workflow--deleted-head (list :branch branch :into main)) head))
        (should-not (agent-workflow--deleted-head (list :branch "feat/never-merged" :into main)))))))

(ert-deftest agent-workflow-steps/a-run-without-a-ticket ()
  "A workflow with ticket: false, run on no ticket (M-x agent-workflow-run),
in a project with no Beads: named by its workflow and number, {issue} that
name; its worktree on run/NAME-N from your HEAD; merged, its branch
deleted; bd never called. Refused: a second run of it at once, a workflow
on tickets, it on a ticket; the next run on a branch of its own."
  (+test-awr "noticket"
    (delete-directory (expand-file-name ".beads" project) t)
    (write-region "description: x
ticket: false
jobs:
  build:
    agent: build
    prompt: Build {issue}, on {branch}.
  merge:
    needs: build
    uses: merge
" nil (expand-file-name ".agent-workflow/workflows/solo.yml" project))
    (let* ((bd nil)
           (main (agent-workflow-main-branch project))
           (agent-workflow-from-shell t))
      (cl-letf (((symbol-function 'agent-workflow--bd)
                 (lambda (_project args &optional _actor) (push args bd) (cons 0 "[]"))))
        (pcase-let* ((`(,started . ,refused) (agent-workflow-run "solo" project))
                     (run (car started)))
          (should-not refused)
          (should (equal (agent-workflow-run-name run) "solo · run 1"))
          (should-not (agent-workflow-run-ticket-p run))
          ;; One at a time; not on a ticket; a workflow on tickets not here.
          (should (equal (cdr (car (cdr (agent-workflow-run "solo" project))))
                         "solo has a run already (solo · run 1)"))
          (should (string-prefix-p "feature runs on a ticket"
                                   (cdr (car (cdr (agent-workflow-run "feature" project))))))
          (should (string-prefix-p "solo runs without a ticket"
                                   (cdr (car (cdr (agent-workflow-run-ticket '("demo-x1") "solo" project))))))
          (let ((agent (+test-awr--agent run "build")))
            (should (+test-awr--wait
                     (lambda () (member "Build solo · run 1, on run/solo-1." (+test-awr--prompts "noticket")))))
            (should (equal (agent-workflow-agent-branch agent) "run/solo-1"))
            (+test-awr--commit (agent-workflow-worktree-directory project "solo") "solo.txt" "solo")
            (+test-awr--finish run "build"))
          (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
          (should (file-exists-p (expand-file-name "solo.txt" project)))
          (should (equal (+test-aws--end run) (list :branch "run/solo-1" :deleted t :into main)))
          (should (member "merged" (+test-awr--journal run)))
          (should-not (plist-get (agent-workflow--pane-header run) :title))
          ;; The next run, from the shell (no issue, --workflow): a branch of
          ;; its own.
          (let* ((reply (agent-workflow--request-run project (list :issues [] :workflow "solo")))
                 (next (car (last (agent-workflow-runs-of project)))))
            (should (eq (plist-get reply :ok) t))
            (should (equal (plist-get (aref (plist-get reply :started) 0) :issue) "solo"))
            (should (equal (agent-workflow-run-name next) "solo · run 2"))
            (should (equal (agent-workflow-agent-branch (+test-awr--agent next "build")) "run/solo-2"))
            (agent-workflow--cancel next)))
        (should-not bd)))))

(ert-deftest agent-workflow-steps/a-run-in-your-checkout ()
  "runs-in: checkout: its job that edits waits while your checkout has
changes not committed, then starts; its agent works in your checkout, its
commit on your branch; no worktree, no branch of its own. Refused: a
second run there, going back with discard. On a ticket: the issue closed
once it's done."
  (+test-awr "checkout"
    (dolist (name '("here" "there"))
      (write-region "description: x\nticket: false\nruns-in: checkout\njobs:\n  build:\n    agent: build\n    prompt: Build {issue}.\n"
                    nil (expand-file-name (format ".agent-workflow/workflows/%s.yml" name) project)))
    (write-region "description: x\nfor: [task]\nruns-in: checkout\njobs:\n  build:\n    agent: build\n    prompt: Build {issue}.\n"
                  nil (expand-file-name ".agent-workflow/workflows/fix.yml" project))
    ;; Its files committed: your checkout clean but for what the test adds.
    (let ((default-directory project))
      (call-process "git" nil nil nil "add" "-A")
      (call-process "git" nil nil nil "commit" "-q" "-m" "workflows"))
    (let* ((agent-workflow-from-shell t)
           (branch (agent-workflow--checkout-branch project))
           (wip (expand-file-name "wip.txt" project)))
      (write-region "mine\n" nil wip)
      (let ((run (car (car (agent-workflow-run "here" project)))))
        (should (equal (agent-workflow-run-name run) "here · run 1"))
        (should (+test-awr--wait
                 (lambda () (equal (plist-get (agent-workflow--job run "build") :why)
                                   "build: waiting: your checkout has changes not committed (commit or stash them)"))))
        (should (eq (+test-awr--job run "build") 'pending))
        (should (string-prefix-p "here · run 1 works in your checkout already"
                                 (cdr (car (cdr (agent-workflow-run "there" project))))))
        ;; Your changes gone: it starts, its agent in your checkout.
        (delete-file wip)
        (agent-workflow-tick)
        (let ((agent (+test-awr--agent run "build")))
          (should (equal (agent-workflow-agent-worktree agent) project))
          (should (equal (agent-workflow-agent-branch agent) branch))
          (should-error (agent-workflow--back run "build" :discard t) :type 'user-error)
          (+test-awr--commit project "here.txt" "here")
          (+test-awr--finish run "build"))
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should-not (file-exists-p (agent-workflow-worktree-directory project "here")))
        (should-not (let ((default-directory project)) (agent-workflow--git-lines "branch" "--list" "run/*")))
        (should (equal (agent-workflow--checkout-branch project) branch))
        (let ((where (agent-workflow-run-where run t)))
          (should (plist-get where :checkout))
          (should (equal (plist-get where :own) 1))
          (should (string-prefix-p (format "⎇ %s   your checkout, from " branch) (agent-workflow--pane-git-line where)))
          (should (string-suffix-p " · 1 commit of its" (agent-workflow--pane-git-line where)))
          (should (equal (mapcar (lambda (file) (plist-get file :path)) (plist-get where :files)) '("here.txt")))
          (should (equal (mapcar #'cadr (plist-get where :commits)) '("here")))))
      ;; On a ticket: closed once done.
      (let* ((issue (+test-awr--issue project "In place" "--type" "task"))
             (run (agent-workflow-start-run project issue :workflow "fix")))
        (+test-awr--commit project "fix.txt" "fix")
        (+test-awr--finish run "build")
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should (equal (alist-get 'status (+test-awr--shown project issue)) "closed"))
        (should-not (agent-workflow-issue-branch-made project issue))))))

(ert-deftest agent-workflow-steps/its-own-commits-in-your-checkout ()
  "A run in your checkout: its commits are those made while its agents
worked (from a step's start, or a fix's, to its done, or the run's end);
yours before, between and after aren't its, nor are their files; a change
not committed, counted, not listed. Kept in its state.json."
  (let* ((project (file-name-as-directory (make-temp-file "awf-own" t)))
         (default-directory project)
         (run (agent-workflow-run--make :project project :issue "github" :n 1 :dir (file-name-as-directory (make-temp-file "awf-run" t))
                                        :state 'running :spent '(:cost 0 :tokens 0)
                                        :workflow '(:name "github" :checkout t
                                                    :jobs (("green" :name "green" :steps ((:kind run :run "watch.sh" :on-fail "ci")))))
                                        :jobs (list (cons "green" (list :status 'running :step 0))))))
    (unwind-protect
        (cl-flet ((commit (file)
                    (write-region file nil (expand-file-name file project))
                    (call-process "git" nil nil nil "add" file)
                    (call-process "git" nil nil nil "commit" "-q" "-m" file))
                  (event (name &rest data) (agent-workflow--checkout-track run name data)))
          (call-process "git" nil nil nil "init" "-q")
          (call-process "git" nil nil nil "config" "user.email" "t@t")
          (call-process "git" nil nil nil "config" "user.name" "t")
          (commit "base.txt")
          (setf (agent-workflow-run-base run) (list :branch "main" :commit (car (agent-workflow--git-lines "rev-parse" "HEAD"))))
          (commit "mine-before.txt")
          ;; The script fails: its agent fixes it, commits; done.
          (event "step-started" :job "green" :step 0 :kind "run")
          (should-not (plist-get (agent-workflow--job run "green") :head))
          (event "fixing" :job "green" :step 0 :agent "ci-1")
          (commit "fix-1.txt")
          (event "step-ended" :job "green" :step 0 :outcome "done")
          (commit "mine-between.txt")
          ;; Again: a fix, the run over before it says done.
          (event "fixing" :job "green" :step 0 :agent "ci-1")
          (commit "fix-2.txt")
          (event "run-done")
          (commit "mine-after.txt")
          (write-region "loose" nil (expand-file-name "loose.txt" project))
          (let ((where (agent-workflow--where-checkout run)))
            (should (equal (plist-get where :own) 2))
            (should-not (plist-get where :empty))
            (should (equal (mapcar (lambda (file) (plist-get file :path)) (plist-get where :files)) '("fix-1.txt" "fix-2.txt")))
            (should (equal (plist-get (car (plist-get where :files)) :status) 'added))
            (should (equal (mapcar #'cadr (plist-get where :commits)) '("fix-2.txt" "fix-1.txt")))
            (should (equal (plist-get where :uncommitted) 1))
            (should (string-suffix-p " · 2 commits of its · 1 not committed" (agent-workflow--pane-git-line where))))
          ;; Saved with its job, and read back.
          (agent-workflow--save-state run)
          (let* ((json (json-parse-string (with-temp-buffer
                                            (insert-file-contents (expand-file-name "state.json" (agent-workflow-run-dir run)))
                                            (buffer-string))
                                          :object-type 'plist :array-type 'list :null-object nil :false-object nil))
                 (job (agent-workflow--job-from-json (car (plist-get json :jobs)))))
            (should (equal (plist-get job :own) (plist-get (agent-workflow--job run "green") :own)))
            (should (= (length (plist-get job :own)) 2))))
      (delete-directory project t)
      (delete-directory (agent-workflow-run-dir run) t))))

(ert-deftest agent-workflow-steps/its-branch-kept ()
  "A run done, its branch not merged (no merge in its workflow): kept,
saying why. branch: keep: kept, merged or not."
  (+test-awr "branch-kept"
    (+test-aws--workflow project "description: x\nfor: [feature]\njobs:\n  build:\n    agent: build\n")
    (let* ((issue (+test-awr--issue project "Not merged"))
           (main (agent-workflow-main-branch project))
           (run (agent-workflow-start-run project issue))
           (branch (agent-workflow-issue-branch issue "feature" "Not merged")))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (equal (agent-workflow-issue-branch-made project issue) branch))
      (should (equal (+test-aws--end run) (list :branch branch :why (format "not merged into %s" main))))
      (should (+test-aws--log-line run (format "its branch %s kept: not merged into %s" (regexp-quote branch) main)))))
  (+test-awr "branch-keep"
    (+test-aws--workflow project (concat "branch: keep\n" +test-aws--merge))
    (let* ((issue (+test-awr--issue project "Kept"))
           (run (agent-workflow-start-run project issue))
           (branch (agent-workflow-issue-branch issue "feature" "Kept")))
      (let ((default-directory project)) (call-process "git" nil nil nil "checkout" "-q" "-b" "elsewhere"))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (equal (agent-workflow-issue-branch-made project issue) branch))
      (should (equal (+test-aws--end run)
                     (list :branch branch :why "its workflow keeps it (branch: keep)"))))))

(ert-deftest agent-workflow-steps/merge-a-conflict ()
  "A conflict no rebase gets past: the on-fail agent told to rebase,
resolving; once it says done, the run goes back to its first job that
edits."
  (+test-awr "conflict"
    (+test-aws--workflow project +test-aws--merge)
    (let* ((issue (+test-awr--issue project "Conflict"))
           (run (agent-workflow-start-run project issue)))
      (+test-awr--agent run "build")
      ;; The main branch gets its own lexer.el meanwhile.
      (let ((default-directory project))
        (write-region "main's\n" nil "lexer.el")
        (call-process "git" nil nil nil "add" "lexer.el")
        (call-process "git" nil nil nil "-c" "user.name=Y" "-c" "user.email=y@y" "commit" "-q" "-m" "main's lexer"))
      (+test-aws--build run project issue "lexer.el" "theirs\n")
      (should (+test-awr--wait
               (lambda () (seq-some (lambda (prompt) (string-match-p "Rebase it onto" prompt))
                                    (+test-awr--prompts "conflict")))))
      (let ((fixer (plist-get (agent-workflow--job run "merge") :agent))
            (worktree (agent-workflow-worktree-directory project issue)))
        (should fixer)
        (should (+test-awr--wait (lambda () (eq (+test-awr--job run "merge") 'waiting))))
        ;; Its agent rebases, mid-way, then resolved: the watch takes it for
        ;; no commits gone (build's end commit not an ancestor any more).
        (let ((default-directory worktree))
          (should-not (eql 0 (call-process "git" nil nil nil "-c" "user.name=A" "-c" "user.email=a@a"
                                           "rebase" (agent-workflow-main-branch project))))
          (agent-workflow-watch-run run)
          (write-region "both\n" nil "lexer.el")
          (call-process "git" nil nil nil "add" "lexer.el")
          (should (eql 0 (call-process "git" nil nil nil "-c" "user.name=A" "-c" "user.email=a@a" "-c" "core.editor=true"
                                       "rebase" "--continue")))
          (agent-workflow-watch-run run))
        (should-not (member "branch-moved" (+test-awr--journal run)))
        (agent-workflow-done fixer nil "rebased")
        ;; Its end commits moved with the rebase: still none gone.
        (should-not (agent-workflow--commits-gone run))
        (agent-workflow-watch-run run)
        (should-not (member "branch-moved" (+test-awr--journal run))))
      ;; Back to build, round 2, told why.
      (should (+test-awr--wait (lambda () (eql (plist-get (agent-workflow--job run "build") :round) 2))))
      (should (+test-awr--wait
               (lambda () (seq-some (lambda (prompt) (string-match-p "\\`merge sent the work back to you, build (round 2), with this note: The branch was rebased onto the main branch" prompt))
                                    (+test-awr--prompts "conflict"))))))))

(ert-deftest agent-workflow-steps/merge-changing-what-runs-the-workflows ()
  "A branch that changes .agent-workflow/ waits for your go before it's
merged, whatever approve says; agents are denied editing it."
  (+test-awr "protected"
    (+test-aws--workflow project +test-aws--merge)
    (let* ((issue (+test-awr--issue project "Protected"))
           (run (agent-workflow-start-run project issue))
           (agent (+test-awr--agent run "build")))
      (should (member "Edit(.agent-workflow/**)"
                      (let ((meta (alist-get :session-meta (agent-workflow--config agent))))
                        (append (alist-get 'disallowedTools (alist-get 'options (alist-get 'claudeCode meta))) nil))))
      (let ((worktree (agent-workflow-worktree-directory project issue)))
        (make-directory (expand-file-name ".agent-workflow/scripts" worktree) t)
        (+test-aws--build run project issue ".agent-workflow/scripts/check.sh" "exit 0\n")
        (let ((default-directory worktree))
          (write-region "x" nil "lexer.el")
          (call-process "git" nil nil nil "add" "lexer.el")
          (call-process "git" nil nil nil "-c" "user.name=A" "-c" "user.email=a@a" "commit" "-q" "-m" "lexer")))
      (+test-aws--asks run "merge: its branch changes what runs the workflows (.agent-workflow/scripts/check.sh): merge it anyway (go), or stop?")
      (agent-workflow--confirm run "go")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should (file-exists-p (expand-file-name ".agent-workflow/scripts/check.sh" project))))))

;; ====== THE STARTERS ======

(defmacro +test-aws--with-starters (&rest body)
  "BODY with the starters as they ship, the project's own workflows and
agents gone."
  (declare (indent 0))
  `(progn
     (delete-directory (expand-file-name ".agent-workflow" project) t)
     (let ((agent-workflow-starters-directory (expand-file-name "config/agent-workflow/" +test-root))
           (agent-workflow--definitions-cache (make-hash-table :test #'equal))
           (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
       ,@body)))

(defun +test-aws--through (run jobs)
  "RUN's JOBS, in order, each one's agent saying done (review: approved)."
  (dolist (job jobs)
    (let ((agent (+test-awr--agent run job)))
      (should agent)
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run job) 'waiting))))
      (agent-workflow-done agent (and (equal job "review") "approved") (format "%s done" job))
      (should (+test-awr--wait (lambda () (eq (+test-awr--job run job) 'done)))))))

(ert-deftest agent-workflow-steps/the-starters ()
  "The starters check with no problem; feature and bugfix run through, to
the merge, the issue closed."
  (+test-awr "starters"
    (+test-aws--with-starters
      (should-not (agent-workflow-check-problems project))
      (should (equal (mapcar #'car (agent-workflow-workflows project)) '("bugfix" "feature" "quick")))
      (should (equal (mapcar #'car (agent-workflow-agent-definitions project))
                     '("build" "docs" "investigate" "review" "security" "test")))
      (let* ((feature (+test-awr--issue project "A feature"))
             (run (agent-workflow-start-run project feature)))
        (should (equal (plist-get (agent-workflow-run-workflow run) :name) "feature"))
        (+test-aws--through run '("build" "docs" "review"))
        (should (eq (+test-awr--job run "security") 'skipped))
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should (equal (alist-get 'status (+test-awr--shown project feature)) "closed")))
      (let* ((bug (+test-awr--issue project "A bug" "--type" "bug"))
             (run (agent-workflow-start-run project bug)))
        (should (equal (plist-get (agent-workflow-run-workflow run) :name) "bugfix"))
        (+test-aws--through run '("reproduce" "fix" "review"))
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should (equal (alist-get 'status (+test-awr--shown project bug)) "closed"))))))
