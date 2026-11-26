;;; tests/unit/test-agent-workflow-pane.el -*- lexical-binding: t; -*-
;; config/agent-workflow/log.el, pane.el, list.el, and the shell's run,
;; logs and status: a run's log (its journal's events as lines, log.txt made
;; again from it); its pane (an Agent UI canvas in sections: the run, what
;; needs you, its agents' own canvases, the log), opened when it's started
;; from Emacs, made when you look when it's from the shell; its questions
;; answered there; closed once it's done; every run listed; the shell
;; following a run's log to its end. Runs on issues of a throwaway Beads
;; project (skipped without bd), with stand-in agents.
;; run.sh: split 2 (stand-in sessions, bd)

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)
(require 'server)

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-ui" "config/agent-shell" "config/agent-workflow")
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workflow-kinds '(mock :config agent-shell-mock-agent-make-agent-config :claude-code t))
(load (expand-file-name "../helper-agent-workflow" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== HELPERS ======

(defconst +test-awp--gate "description: build, its result approved by you
for: [task]
jobs:
  build:
    agent: build
    approve: true
")

(defmacro +test-awp (name &rest body)
  "BODY as `+test-awr''s, panes recorded in `shown' as they open (no
window), questions not taking the focus; the workflow gate there too."
  (declare (indent 1))
  `(+test-awr ,name
     (let* ((shown nil)
            (agent-workflow--canvas-fallback (lambda (buffer) (push buffer shown)))
            (agent-ui-focus-questions nil)
            (agent-ui-close-answered t))
       (write-region +test-awp--gate nil (expand-file-name ".agent-workflow/workflows/gate.yml" project))
       (unwind-protect (progn ,@body)
         (dolist (buffer (agent-ui-canvases)) (kill-buffer buffer))))))

(defun +test-awp--box-lines (box)
  "BOX's lines' texts (a line text, or {level, text, mark}), each its mark
first."
  (mapcar (lambda (line)
            (if (stringp line) line (concat (if (plist-get line :mark) (concat (plist-get line :mark) " ") "")
                                            (plist-get line :text))))
          (plist-get box :lines)))

(defun +test-awp--sections (pane &optional all)
  "PANE's sections' names; but Needs you, unless ALL (a stand-in's turn
ending without its done makes it wait for you, a moment)."
  (let ((names (mapcar (lambda (s) (plist-get s :name)) (agent-ui-sections pane))))
    (if all names (remove "needs-you" names))))

(defun +test-awp--settle ()
  "Timers due now run (an answer's given after its command), 0.3 s at
least: `+test-timers-run'."
  (+test-timers-run 0.3))

(defun +test-awp--answer (pane label &optional note)
  "PANE's question answered: its button LABEL pressed, NOTE the note it asks
\(a label ending in …)."
  (with-current-buffer pane
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (or note ""))))
      (let ((agent-ui-pressed "needs-you/ask"))
        (funcall agent-ui-action-function label t)))))

(defun +test-awp--line (line)
  "LINE of a run's Log as words: MARK JOB TEXT (RIGHT), its job · if it has
none; a pause, ┊ and how long."
  (if (plist-get line :gap)
      (concat "┊ " (plist-get line :gap))
    (let ((text (plist-get line :text)))
      (concat (plist-get line :mark) " " (or (plist-get line :source) "·") " "
              (if (stringp text) text (mapconcat (lambda (piece) (if (stringp piece) piece (plist-get piece :text))) text ""))
              (if (plist-get line :right) (format " (%s)" (plist-get line :right)) "")))))

(defun +test-awp--log (pane)
  "PANE's Log's lines as words (`+test-awp--line')."
  (mapcar #'+test-awp--line (plist-get (agent-ui-get "log" :canvas pane :section "log") :lines)))

(defun +test-awp--figure (header label)
  "HEADER's (a run pane's \"run\" element) tile LABEL: (VALUE CHANGE FACE)."
  (let ((figure (seq-find (lambda (f) (equal (plist-get f :label) label)) (plist-get header :figures))))
    (and figure (list (plist-get figure :value) (plist-get figure :change) (plist-get figure :face)))))

(defun +test-awp--labels (element)
  "ELEMENT's buttons' labels."
  (mapcar (lambda (action) (plist-get action :label)) (plist-get element :actions)))

;; ====== ITS LOG ======

(ert-deftest agent-workflow-pane/log-lines ()
  "An event, a line: its time, its issue, its job, what happened; a wait
says how to answer from the shell; what says nothing left out. Its journal
read back, the same lines, a wait's hint from its question."
  (let ((time (encode-time '(7 42 10 23 11 2026 nil -1 nil))))
    (should (equal (agent-workflow--log-line "demo-1" "job-started" '(:job "build") time)
                   "10:42:07  demo-1  build  started"))
    (should (equal (agent-workflow--log-line "demo-1" "run-started" '(:workflow "feature" :by "you") time)
                   "10:42:07  demo-1  ·  started, with feature, by you"))
    (should (equal (agent-workflow--log-line "demo-1" "waiting" '(:job "build" :why "build: its result waits for your OK")
                                             time 'approve)
                   "10:42:07  demo-1  build  waits for you: build: its result waits for your OK → agent-workflow approve demo-1, or reject demo-1 NOTE"))
    (should (string-suffix-p "→ agent-workflow confirm demo-1 go|accept|stop [--note-to JOB NOTE]"
                             (agent-workflow--log-line "demo-1" "waiting" '(:job "review" :why "x") time nil)))
    (should (string-suffix-p "→ agent-workflow continue demo-1, back demo-1 JOB NOTE, or cancel demo-1"
                             (agent-workflow--log-line "demo-1" "waiting" '(:job "review" :why "x") time 'none)))
    (should (equal (agent-workflow--log-line "demo-1" "answered"
                                             (list :job "review" :choice "go" :by "you"
                                                   :notes (vector '(:job "build" :note "shorter")))
                                             time)
                   "10:42:07  demo-1  review  go, by you; for build: shorter"))
    (should (equal (agent-workflow--log-line "demo-1" "job-done" '(:job "review" :outcome "changes") time)
                   "10:42:07  demo-1  review  done: changes"))
    (should (equal (agent-workflow--log-line "demo-1" "merged" '(:job "merge" :branch "feat/x" :into "main" :already :false)
                                             time)
                   "10:42:07  demo-1  merge  feat/x merged into main"))
    (should (equal (agent-workflow--log-line "demo-1" "merged" '(:job "merge" :branch "feat/x" :into "main" :already t
                                                                  :empty t)
                                             time)
                   "10:42:07  demo-1  merge  nothing to merge: feat/x has no commit"))
    (should (equal (agent-workflow--log-line "demo-1" "branch-deleted" '(:branch "feat/x" :into "main" :empty t) time)
                   "10:42:07  demo-1  ·  its branch feat/x deleted: no commit"))
    (should-not (agent-workflow--log-line "demo-1" "step-starting" '(:job "build") time))
    (should-not (agent-workflow--log-line "demo-1" "state" '(:state "running") time))
    ;; Read back: a wait's hint from its question.
    (let ((lines (agent-workflow--log-replay
                  "demo-1"
                  '((:t "2026-11-23T09:42:07+0000" :ev "asked" :job "build" :kind "approve")
                    (:t "2026-11-23T09:42:07+0000" :ev "waiting" :job "build" :why "OK?")
                    (:t "2026-11-23T09:42:09+0000" :ev "answered" :job "build" :choice "approve" :by "you")
                    (:t "2026-11-23T09:43:00+0000" :ev "waiting" :job "build" :why "again")))))
      (should (= (length lines) 3))
      (should (string-suffix-p "→ agent-workflow approve demo-1, or reject demo-1 NOTE" (nth 0 lines)))
      (should (string-match-p "  demo-1  build  approve, by you\\'" (nth 1 lines)))
      (should (string-suffix-p "or cancel demo-1" (nth 2 lines)))
      (should (string-prefix-p (format-time-string "%H:%M:%S" (date-to-time "2026-11-23T09:42:07+0000"))
                               (car lines))))))

;; ====== A RUN IN ITS PANE ======

(ert-deftest agent-workflow-pane/a-run-in-its-pane ()
  "Started from Emacs: its pane opens, ISSUE · WORKFLOW, the run above its
sections Run and Log; each job running its live box in Run (its agent at
work, Show session showing its session); what its agent shows on its
canvas stays with its session (no pane, nor in the run's); its job over,
its box gone. Its log, log.txt and the pane's. Done: it stays, nothing
counting down, until closed (q)."
  (+test-awp "pane"
    (let* ((issue (+test-awr--issue project "A pane"))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (pane (agent-workflow-run-pane run)))
      (should (buffer-live-p pane))
      (should (equal (buffer-name pane) (format "Agent UI: %s · feature" issue)))
      (should (equal shown (list pane)))
      (should (equal (+test-awp--sections pane) '("run" "log")))
      ;; Build's agent: its live box at Run's bottom, under Rounds; no section.
      (let* ((agent (+test-awr--agent run "build"))
             (name (agent-ui--session-name (agent-workflow-agent-buffer agent))))
        (should (+test-awr--wait (lambda () (ignore-errors (agent-ui-get "now-build" :canvas pane :section "run")))))
        (should (equal (+test-awp--sections pane) '("run" "log")))
        (let ((box (agent-ui-get "now-build" :canvas pane :section "run")))
          (should (equal (plist-get box :type) "activity"))
          (should (equal (plist-get box :owner) "build"))
          (should (equal (+test-awp--labels box) '("Show session"))))
        (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-components :canvas pane :section "run"))
                       '("graph" "jobs" "rounds" "now-build")))
        ;; What it shows on its canvas: there, no pane of its own, not in the run's.
        (agent-ui-show '(:id "plan" :type "steps" :steps ("Read" "Write")) :canvas name)
        (should (get-buffer (agent-ui-canvas-buffer-name name)))
        (should-not (memq (get-buffer (agent-ui-canvas-buffer-name name)) shown))
        (should-not (ignore-errors (agent-ui-get "plan" :canvas pane :section "run")))
        ;; Show session: its session.
        (with-current-buffer pane
          (cl-letf (((symbol-function 'pop-to-buffer) (lambda (buffer &rest _) (push buffer shown))))
            (agent-workflow--pane-answer "session build" nil "run/now-build"))
          (should (eq (car shown) (agent-workflow-agent-buffer agent)))))
      ;; What it shows: its state as tiles; a graph of its jobs, its
      ;; checklist, its rounds; its log without its issue.
      (let ((header (agent-ui-get "run" :canvas pane))
            (jobs (agent-ui-get "jobs" :canvas pane :section "run"))
            (graph (agent-ui-get "graph" :canvas pane :section "run")))
        (should (equal (plist-get header :title) "A pane"))
        (should (equal (plist-get header :type) "stats"))
        (should (member (car (+test-awp--figure header "State")) '("● running" "◆ needs you")))
        (should (string-match-p "\\`[0-9]+s\\'" (car (+test-awp--figure header "Time"))))
        (should (equal (+test-awp--figure header "Cost") '("$0" nil nil)))
        (should (equal (car (+test-awp--figure header "Jobs")) "0 / 3"))
        (should-not (+test-awp--figure header "Tokens"))
        (should (equal (mapcar (lambda (s) (plist-get s :name)) (plist-get jobs :steps)) '("build" "docs" "review")))
        (should (member (plist-get (car (plist-get jobs :steps)) :status) '("running" "waiting" "pending")))
        (should (equal (mapcar (lambda (node) (plist-get node :id)) (plist-get graph :nodes)) '("build" "docs" "review")))
        (should (equal (plist-get graph :edges) '(("build" "docs") ("build" "review"))))
        (should (string-match-p "\\`build [●◆]\\'" (plist-get (car (plist-get graph :nodes)) :label)))
        (should (equal (mapcar (lambda (task) (plist-get task :name))
                               (plist-get (agent-ui-get "rounds" :canvas pane :section "run") :tasks))
                       '("build")))
        ;; Each under its caption, as the git's (branch, 3 commits).
        (should (equal (mapcar (lambda (id) (plist-get (agent-ui-get id :canvas pane :section "run") :caption))
                               '("graph" "jobs" "rounds"))
                       '("flow" "3 jobs" "rounds"))))
      (should (member "▸ build started" (+test-awp--log pane)))
      ;; Build done: its box gone. Its notes in Notes; no commit of its, said.
      (+test-awr--finish run "build" nil "Built it, with its tests.")
      (should (+test-awr--wait (lambda () (member "notes" (+test-awp--sections pane)))))
      (should (string-match-p "\\`[0-9:]+ · Built it, with its tests\\.\\'"
                              (plist-get (car (plist-get (agent-ui-get "notes" :canvas pane :section "notes") :steps))
                                         :detail)))
      (should (equal (plist-get (car (plist-get (agent-ui-get "notes" :canvas pane :section "notes") :steps)) :body)
                     "Built it, with its tests."))
      (should (string-search "no commit" (plist-get (car (plist-get (agent-ui-get "jobs" :canvas pane :section "run") :steps))
                                                    :detail)))
      (should (equal (plist-get (agent-ui-get "jobs" :canvas pane :section "run") :caption) "3 jobs · 1 done"))
      (with-current-buffer pane (agent-workflow--pane-show-boxes run pane))
      (should-not (ignore-errors (agent-ui-get "now-build" :canvas pane :section "run")))
      ;; Review's: its box.
      (+test-awr--agent run "review")
      (should (+test-awr--wait (lambda () (ignore-errors (agent-ui-get "now-review" :canvas pane :section "run")))))
      (should (equal (+test-awp--sections pane) '("run" "notes" "log")))
      (+test-awr--finish run "review" "approved")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      ;; Its log: every event a line; the pane's shorter: no issue, a job's
      ;; agent step's start and end left out, a job done how long it took
      ;; at its end.
      (let ((lines (agent-workflow-log-lines run))
            (pane-lines (+test-awp--log pane)))
        (should (string-match-p "  ·  run done\\'" (car (last lines))))
        (should (seq-some (lambda (line) (string-match-p "  docs  skipped" line)) lines))
        (should (seq-some (lambda (line) (string-match-p "step 1 started" line)) lines))
        (should (string-match-p "\\`★ · run done ([0-9]+s)\\'" (car (last pane-lines))))
        (should (seq-some (lambda (line) (string-match-p "\\`✓ review done · approved ([0-9]+s)\\'" line)) pane-lines))
        (should (member "– docs skipped · if: (eq (issue-type) 'bug)" pane-lines))
        (should-not (seq-some (lambda (line) (string-match-p "step 1" line)) pane-lines))
        ;; log.txt gone: made again from the journal, the same.
        (delete-file (agent-workflow--log-path run))
        (should (equal (mapcar (lambda (line) (substring line 10)) (agent-workflow-log-lines run))
                       (mapcar (lambda (line) (substring line 10)) lines))))
      ;; Done: it stays, its checklist finished, nothing counting down; you
      ;; close it (q).
      (with-current-buffer pane
        (agent-ui--flush)
        (should-not agent-ui-closes-with)
        (should-not (and agent-ui--closing (gethash "run/jobs" agent-ui--closing)))
        (should-not (string-search "closing in" (buffer-string)))
        (should (equal (+test-awp--figure (agent-ui-get "run" :canvas pane) "State") '("✓ done" nil "success"))))
      (kill-buffer pane)
      (should-not (agent-workflow-run-pane run)))))

;; ====== WHAT NEEDS YOU ======

(ert-deftest agent-workflow-pane/needs-you-answered-there ()
  "Started from the shell: no pane, made when you look (not shown). Its
result waiting for your OK: Needs you, the question and what to look at,
said once; rejected with a note (none: refused), back to its agent; asked
again, approved: the run done."
  (+test-awp "needs"
    (let* ((issue (+test-awr--issue project "A gate" "--type" "task"))
           (said nil)
           (agent-workflow-needs-you-functions (list (lambda (run why) (push (cons run why) said))))
           (run (car (car (let ((agent-workflow-from-shell t)) (agent-workflow-run-ticket (list issue) nil project))))))
      (should-not (agent-workflow-run-pane run))
      (let ((pane (agent-workflow-pane run)))
        (should (buffer-live-p pane))
        (should-not shown)
        (+test-awr--finish-step run "build" "built it")
        (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
        (should (equal (+test-awp--sections pane t) '("run" "needs-you" "notes" "log")))
        (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-components :canvas pane :section "needs-you"))
                       '("ask" "look")))
        (let ((ask (agent-ui-get "ask" :canvas pane :section "needs-you")))
          (should (equal (plist-get ask :type) "text"))
          (should (string-prefix-p "◆ build: its result waits for your OK" (plist-get ask :text)))
          (should (equal (+test-awp--labels ask) '("Approve" "Reject…"))))
        (should (string-match-p "Notes: built it" (plist-get (agent-ui-get "look" :canvas pane :section "needs-you") :text)))
        ;; Said once a wait: its turn's end without done before, then this.
        (should (string-match-p "its result waits for your OK" (cdar said)))
        (should (= (seq-count (lambda (s) (string-match-p "your OK" (cdr s))) said) 1))
        (agent-workflow--changed run)
        (should (= (seq-count (lambda (s) (string-match-p "your OK" (cdr s))) said) 1))
        ;; Waiting for you, it opens by itself only once you looked.
        (should-not shown)
        ;; Rejected without a note: refused, still asked.
        (should (string-match-p "No note"
                                (cadr (should-error (+test-awp--answer pane "Reject…") :type 'user-error))))
        (+test-awp--answer pane "Reject…" "shorter, please")
        (+test-awp--settle)
        ;; Its agent told (it runs, its turn ends without done: waiting).
        (should (+test-awr--wait (lambda () (seq-some (lambda (p) (string-search "shorter, please" p))
                                                      (+test-awr--prompts "needs")))))
        ;; Asked again: approved, done.
        (+test-awr--finish-step run "build" "shorter now")
        (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
        (should (equal (+test-awp--labels (agent-ui-get "ask" :canvas pane :section "needs-you")) '("Approve" "Reject…")))
        (should (= (seq-count (lambda (s) (string-match-p "your OK" (cdr s))) said) 2))
        (+test-awp--answer pane "Approve")
        (+test-awp--settle)
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should-not (member "needs-you" (+test-awp--sections pane t)))
        (should (member "approve, by you, in its pane"
                        (mapcar (lambda (line) (car (last (split-string line "  ")))) (agent-workflow-log-lines run))))))))

(ert-deftest agent-workflow-pane/cancelled-from-its-pane ()
  "Its header's Cancel, while the run isn't over: pressed, asked first (what
it stops, what it keeps); no: nothing; yes: the run cancelled, by you in its
pane, its header saying so, Cancel gone."
  (+test-awp "cancel"
    (let* ((issue (+test-awr--issue project "Cancel me"))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (pane (agent-workflow-run-pane run))
           (asked nil)
           (yes nil))
      (+test-awr--agent run "build")
      (should (equal (+test-awp--labels (agent-ui-get "run" :canvas pane)) '("Cancel")))
      (cl-flet ((press ()
                  (with-current-buffer pane
                    (agent-ui--flush)
                    (goto-char (point-min))
                    (search-forward "⏵ Cancel")
                    (should (equal (get-text-property (match-beginning 0) 'help-echo) "RET: cancel the run (asked first)"))
                    (goto-char (match-beginning 0))
                    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (prompt) (push prompt asked) yes)))
                      (agent-ui-button-press)))))
        (press)
        (should (string-match-p "\\`Cancel .*· feature\\? Its agents and scripts stop.*its branch and worktree are kept"
                                (car asked)))
        (should (eq (agent-workflow-run-state run) 'running))
        (setq yes t)
        (press)
        (should (eq (agent-workflow-run-state run) 'cancelled))
        (should (eq (+test-awr--job run "build") 'cancelled))
        (let ((header (agent-ui-get "run" :canvas pane)))
          (should (equal (car (+test-awp--figure header "State")) "✗ cancelled"))
          (should-not (plist-get header :actions)))
        (should (member "run cancelled, by you, in its pane"
                        (mapcar (lambda (line) (car (last (split-string line "  ")))) (agent-workflow-log-lines run))))
        (with-current-buffer pane
          (agent-ui--flush)
          (should-not (string-search "⏵ Cancel" (buffer-string))))))))

(ert-deftest agent-workflow-pane/redrawn-as-its-steps-go ()
  "Its checklist redrawn as its job goes on, nothing else happening: the
next step running once the one before ends; a failed step, its agent
fixing it (failed, who fixes it), at once. Its header's time drawn again
on its tick."
  (+test-awp "steps"
    (write-region "description: x
for: [chore]
jobs:
  check:
    steps:
      - name: one
        run: echo one
      - name: two
        run: sleep 1; test -f ok.txt || exit 1
        retries: 1
        on-fail: build
" nil (expand-file-name ".agent-workflow/workflows/chores.yml" project))
    (let* ((issue (+test-awr--issue project "Steps" "--type" "chore"))
           (run (agent-workflow-start-run project issue))
           (pane (agent-workflow-pane run))
           (agent-workflow-pane-where-every 3600))
      (cl-flet ((job () (car (plist-get (agent-ui-get "jobs" :canvas pane :section "run") :steps)))
                (step (name) (seq-find (lambda (step) (equal (plist-get step :name) name))
                                       (plist-get (car (plist-get (agent-ui-get "jobs" :canvas pane :section "run") :steps))
                                                  :steps))))
        (should (+test-awr--wait (lambda () (equal (plist-get (step "two") :status) "running"))))
        (should (equal (plist-get (step "one") :status) "done"))
        (should (+test-awr--wait (lambda () (equal (plist-get (step "two") :status) "failed"))))
        (should (equal (plist-get (job) :detail) "fixing"))
        (should (string-match-p "build fixing it · try 1 of 2" (plist-get (step "two") :detail)))
        ;; Its header: drawn again on its tick, nothing else changing.
        (with-current-buffer pane
          (agent-ui-show '(:id "run" :type "text" :text "stale") :canvas pane))
        (agent-workflow--pane-where-tick)
        (should (equal (car (+test-awp--figure (agent-ui-get "run" :canvas pane) "State")) "● running"))
        (agent-workflow--cancel run)))))

(ert-deftest agent-workflow-pane/a-cancelled-run-asks-nothing ()
  "A run waiting for your OK, cancelled: it asks nothing more; approve,
reject and confirm refuse it; M-x agent-workflow-approve and confirm don't
pick it; it stays cancelled, no agent started."
  (+test-awp "cancelled-asks"
    (let* ((issue (+test-awr--issue project "A gate" "--type" "task"))
           (run (car (car (let ((agent-workflow-from-shell t)) (agent-workflow-run-ticket (list issue) nil project))))))
      (+test-awr--finish-step run "build" "built it")
      (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
      (agent-workflow--cancel run)
      (should-not (agent-workflow-asking run))
      (should-not (plist-get (agent-workflow--job run "build") :ask))
      (should (string-match-p "is over (cancelled)"
                              (cadr (should-error (agent-workflow--approve run) :type 'user-error))))
      (should-error (agent-workflow--reject run "no") :type 'user-error)
      (should-error (agent-workflow--confirm run "go") :type 'user-error)
      (should (equal (cadr (should-error (agent-workflow--read-approval "Approve: ") :type 'user-error))
                     "No run waits for your OK"))
      (should-error (call-interactively #'agent-workflow-confirm) :type 'user-error)
      (should (eq (agent-workflow-run-state run) 'cancelled))
      (should-not (seq-some (lambda (agent) (buffer-live-p (agent-workflow-agent-buffer agent)))
                            (agent-workflow-agents project))))))

(ert-deftest agent-workflow-pane/git-left-alone-while-it-waits ()
  "Its tick, while its run waits for you: git asked once, then not again
until something's committed or staged in its worktree. Its files changed:
one ls-files --others."
  (+test-awp "git-quiet"
    (let* ((issue (+test-awr--issue project "A gate" "--type" "task"))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (agent-workflow--where-age 0)
           (calls nil))
      (+test-awr--finish-step run "build" "built it")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'waiting))))
      (cl-flet ((git-calls (thunk)
                  (setq calls nil)
                  (cl-letf* ((process-file-real (symbol-function 'process-file))
                             ((symbol-function 'process-file)
                              (lambda (program &rest args)
                                (when (equal program "git") (push (nthcdr 3 args) calls))
                                (apply process-file-real program args))))
                    (funcall thunk))
                  (length calls)))
        (git-calls #'agent-workflow--pane-where-tick)
        (should (= (git-calls #'agent-workflow--pane-where-tick) 0))
        (should (= (git-calls #'agent-workflow--pane-where-tick) 0))
        ;; A commit there: looked at again.
        (let ((worktree (agent-workflow-worktree-directory project issue)))
          (+test-awr--commit worktree "c.txt" "a commit")
          (should (> (git-calls #'agent-workflow--pane-where-tick) 0))
          (git-calls (lambda () (agent-workflow--where-files worktree "HEAD")))
          (should (= (seq-count (lambda (args) (equal (car args) "ls-files")) calls) 1))))
      (agent-workflow--cancel run))))

(ert-deftest agent-workflow-pane/git-left-alone-its-index-rewritten-by-reading ()
  "Its tick reading git rewrites the worktree's index, as git status and
diff do when its files are racily clean (changed in the second the index
was last written, on a git without nanosecond times: Debian's, each read
in that second): its next tick still asks git nothing. A commit while it
reads: git asked again at the next."
  (+test-awp "git-index-rewritten"
    (let* ((issue (+test-awr--issue project "A gate" "--type" "task"))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (agent-workflow--where-age 0)
           (worktree (agent-workflow-worktree-directory project issue))
           (index nil)
           (during nil)
           (calls 0))
      (+test-awr--finish-step run "build" "built it")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'waiting))))
      (setq index (expand-file-name "index" (let ((default-directory worktree))
                                              (car (process-lines "git" "rev-parse" "--absolute-git-dir")))))
      (cl-letf* ((process-file-real (symbol-function 'process-file))
                 ((symbol-function 'process-file)
                  (lambda (program &rest args)
                    (prog1 (apply process-file-real program args)
                      (when (equal program "git")
                        (cl-incf calls)
                        (when (and during (equal (nth 3 args) "status"))
                          (funcall during)))))))
        (cl-flet ((git-calls () (setq calls 0) (agent-workflow--pane-where-tick) calls)
                  (rewrite () (set-file-times index (time-add nil (random 1000)))))
          ;; Each read rewrites the index: read once, then left alone.
          (setq during #'rewrite)
          (rewrite)
          (should (> (git-calls) 0))
          (should (= (git-calls) 0))
          (should (= (git-calls) 0))
          ;; A commit as it reads: read again.
          (rewrite)
          (setq during (lambda ()
                         (setq during nil)
                         (+test-awr--commit worktree "c.txt" "a commit")))
          (should (> (git-calls) 0))
          (should-not during)
          (should (> (git-calls) 0))
          (should (= (git-calls) 0))))
      (agent-workflow--cancel run))))

(ert-deftest agent-workflow-pane/each-run-its-own-pane ()
  "Two runs of an issue with one workflow (the first failed, its pane kept):
each its own pane, the second's named with its number; the first's still
its own."
  (+test-awp "two-panes"
    (let* ((issue (+test-awr--issue project "Twice"))
           (one (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (one-pane (agent-workflow-run-pane one)))
      (agent-workflow--cancel one)
      (let* ((two (car (car (agent-workflow-run-ticket (list issue) nil project))))
             (two-pane (agent-workflow-run-pane two)))
        (should (= (agent-workflow-run-n two) 2))
        (should-not (eq one-pane two-pane))
        (should (equal (buffer-name two-pane) (format "Agent UI: %s · feature · run 2" issue)))
        (should (eq (buffer-local-value 'agent-workflow--pane-run one-pane) one))
        (should (eq (buffer-local-value 'agent-workflow--pane-run two-pane) two))
        (agent-workflow--cancel two)))))

(defun +test-awp--ask (pane)
  "The question in PANE's Needs you, if there's one."
  (ignore-errors (agent-ui-get "ask" :canvas pane :section "needs-you")))

(ert-deftest agent-workflow-pane/its-agent-asks ()
  "Its agent asking for a permission in its session: its run waits for you,
saying what (its why, status, its log, said once); Needs you shows
agent-shell's own buttons and Go to it; confirm refused, it's its agent's;
Allow pressed there: its agent goes on (its turn ending without done, the
usual wait). A question (agent-shell's form): Go to it shows its session,
the question asked here again; answered there: running, Needs you gone."
  (+test-awp "agent-asks"
    (let* ((issue (+test-awr--issue project "Ask for a permission"))
           (said nil)
           (agent-workflow-needs-you-functions (list (lambda (_run why) (push why said))))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (pane (agent-workflow-run-pane run))
           (agent (+test-awr--agent run "build"))
           (why "build: its agent asks for your permission: npm install"))
      ;; It asks: the run waits for you, saying what.
      (should (+test-awr--wait (lambda () (agent-workflow-agent-asking run))))
      (should (eq (agent-workflow-run-state run) 'waiting))
      (should (equal (agent-workflow-run-why run) why))
      (should (equal (agent-workflow-agent-asking run)
                     (list "build" :kind 'permission :what "npm install" :why why)))
      (should (equal said (list why)))
      (should (equal (plist-get (aref (plist-get (agent-workflow--request-status project nil) :runs) 0) :asking)
                     (list :job "build" :kind "agent" :question "npm install"
                           :session (agent-workflow-agent-name agent))))
      (should (string-suffix-p (concat "waits for you: " why " → answer it in its agent's session, or in the run's pane")
                               (car (last (agent-workflow-log-lines run)))))
      (should (string-match-p "asks you in its session"
                              (cadr (should-error (agent-workflow--confirm run "go") :type 'user-error))))
      ;; Needs you: agent-shell's buttons, and Go to it.
      (should (+test-awr--wait (lambda () (+test-awp--ask pane))))
      (let ((ask (+test-awp--ask pane)))
        (should (equal (plist-get ask :text) "◆ build asks for your permission: npm install"))
        (should (string-prefix-p "Allow" (car (+test-awp--labels ask))))
        (should (equal (car (last (+test-awp--labels ask))) agent-workflow--pane-go-to-it))
        ;; Allow, from the pane: its agent goes on; its turn over without
        ;; done, the usual wait.
        (+test-awp--answer pane (car (+test-awp--labels ask))))
      (+test-awp--settle)
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why run)
                                                 "build: its agent ended its turn without saying it's done"))))
      (should-not (agent-workflow-agent-asking run))
      (should (+test-awr--wait (lambda () (equal (+test-awp--labels (+test-awp--ask pane))
                                                 '("Run its step again" "Run it again, with a note…" "Cancel the run")))))
      (should (member "answered its agent, by you"
                      (mapcar (lambda (line) (car (last (split-string line "  ")))) (agent-workflow-log-lines run))))
      (should (equal (seq-filter (lambda (event) (member event '("asked" "answered"))) (+test-awr--journal run))
                     '("asked" "answered")))
      ;; A question, its form in its session (its job running again).
      (agent-workflow--job-set run "build" :status 'running :why nil)
      (agent-workflow--agent-event agent '((:event . elicitation-request)
                                           (:data (:message . "Retina or 1x?\nThe screen is 1x."))))
      (should (equal (agent-workflow-run-why run) "build: its agent asks you: Retina or 1x?"))
      (should (+test-awr--wait (lambda () (equal (+test-awp--labels (+test-awp--ask pane))
                                                 (list agent-workflow--pane-go-to-it)))))
      (should (equal (plist-get (+test-awp--ask pane) :text) "◆ build asks you: Retina or 1x?"))
      ;; Go to it: its session shown; asked here again, it still is.
      (+test-awp--answer pane agent-workflow--pane-go-to-it)
      (+test-awp--settle)
      (should (get-buffer-window (agent-workflow-agent-buffer agent)))
      (should (agent-workflow-agent-asking run))
      (should (+test-awp--ask pane))
      ;; Answered there: running, Needs you gone.
      (agent-workflow--agent-event agent '((:event . elicitation-response)))
      (should (eq (agent-workflow-run-state run) 'running))
      (should (+test-awr--wait (lambda () (not (member "needs-you" (+test-awp--sections pane t)))))))))

(defun +test-awp--form (agent id schema)
  "AGENT's session asks its form ID (agent-shell's elicitation/create, its
SCHEMA's properties and required ones: alists), as Claude Code's
AskUserQuestion does: drawn there, said."
  (with-current-buffer (agent-workflow-agent-buffer agent)
    (agent-shell-elicitation--on-create-request
     :state (agent-shell--state)
     :acp-request `((id . ,id) (method . "elicitation/create")
                    (params . ((mode . "form") (message . "Should the escape table cover Unicode escapes?")
                               (requestedSchema . ((type . "object") ,@schema))))))))

(defun +test-awp--form-answered (agent id)
  "AGENT's form ID: its status and values, as agent-shell has them."
  (with-current-buffer (agent-workflow-agent-buffer agent)
    (let ((form (agent-shell-elicitation--get (agent-shell--state) id)))
      (list (map-elt form :status) (map-elt form :values)))))

(ert-deftest agent-workflow-pane/its-agent-s-form-answered-there ()
  "Its agent's question, its form in its session (AskUserQuestion's), in
the pane as Agent UI's own: one with options a choice (its free answer the
note), several a form; answered there as its Submit does, the run goes
on; Go to it, beside."
  (+test-awp "agent-form"
    (let* ((issue (+test-awr--issue project "Ask a question"))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (pane (agent-workflow-run-pane run))
           (agent (+test-awr--agent run "build"))
           (custom agent-shell-elicitation--custom-answer-meta-key)
           (select `((type . "string") (title . "Unicode")
                     (oneOf . [((const . "both") (title . "Both forms") (description . "and their tests"))
                               ((const . "braced") (title . "Only braced"))]))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'waiting))))
      ;; One question with options: a choice, its note the free answer.
      (agent-workflow--job-set run "build" :status 'running :why nil)
      (+test-awp--form agent 41 `((properties . ((question_0 . ,select)
                                                 (question_0_custom . ((type . "string")
                                                                       (_meta . ((,custom . ((questionId . "question_0")))))))))
                                  (required . ["question_0"])))
      (should (equal (plist-get (cdr (agent-workflow-agent-asking run)) :request) 41))
      (should (+test-awr--wait (lambda () (equal (plist-get (+test-awp--ask pane) :type) "choice"))))
      (let ((ask (+test-awp--ask pane)))
        (should (equal (plist-get ask :question) "build asks: Should the escape table cover Unicode escapes?"))
        (should (equal (plist-get ask :title) "Unicode"))
        (should (equal (plist-get ask :options) '((:label "Both forms" :detail "and their tests") (:label "Only braced"))))
        (should (eq (plist-get ask :note) t))
        (should (equal (+test-awp--labels ask) (list agent-workflow--pane-go-to-it))))
      (should (string-match-p "Choose one" (cadr (should-error (+test-awp--answer pane "the answer") :type 'user-error))))
      (agent-ui-update "ask" '(:selected ("Only braced")) :canvas pane :section "needs-you")
      (+test-awp--answer pane "the answer")
      (+test-awp--settle)
      (should (equal (+test-awp--form-answered agent 41) '(answered (("question_0" . "braced")))))
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'running))))
      (should (+test-awr--wait (lambda () (not (member "needs-you" (+test-awp--sections pane t))))))
      ;; Its free answer, the note.
      (+test-awp--form agent 42 `((properties . ((question_0 . ,select)
                                                 (question_0_custom . ((type . "string")
                                                                       (_meta . ((,custom . ((questionId . "question_0")))))))))))
      (should (+test-awr--wait (lambda () (equal (plist-get (+test-awp--ask pane) :type) "choice"))))
      (agent-ui-update "ask" '(:note-text "only \\x, for now") :canvas pane :section "needs-you")
      (+test-awp--answer pane "the answer")
      (+test-awp--settle)
      (should (equal (+test-awp--form-answered agent 42) '(answered (("question_0_custom" . "only \\x, for now")))))
      ;; Two questions: a form, its select and its yes or no.
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'running))))
      (+test-awp--form agent 43 `((properties . ((question_0 . ,select)
                                                 (tests . ((type . "boolean") (title . "With tests?")))))
                                  (required . ["question_0" "tests"])))
      (should (+test-awr--wait (lambda () (equal (plist-get (+test-awp--ask pane) :type) "form"))))
      (should (equal (mapcar (lambda (field) (list (plist-get field :name) (plist-get field :type)))
                             (plist-get (+test-awp--ask pane) :fields))
                     '(("question_0" "select") ("tests" "boolean"))))
      (agent-ui-update "ask" '(:values (:question_0 "Both forms" :tests t)) :canvas pane :section "needs-you")
      (+test-awp--answer pane "the answer")
      (+test-awp--settle)
      (should (equal (car (+test-awp--form-answered agent 43)) 'answered))
      (should (equal (sort (copy-sequence (cadr (+test-awp--form-answered agent 43)))
                           (lambda (a b) (string< (car a) (car b))))
                     '(("question_0" . "both") ("tests" . t))))
      ;; Go to it, beside it: its session shown, the form still asked.
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'running))))
      (+test-awp--form agent 44 `((properties . ((question_0 . ,select)))))
      (should (+test-awr--wait (lambda () (+test-awp--ask pane))))
      (+test-awp--answer pane agent-workflow--pane-go-to-it)
      (+test-awp--settle)
      (should (get-buffer-window (agent-workflow-agent-buffer agent)))
      (should (eq (car (+test-awp--form-answered agent 44)) 'pending)))))

;; ====== WHERE ITS WORK IS ======

(ert-deftest agent-workflow-pane/notes ()
  "Its agents' notes, a feed of verdicts: a line each, its job (its round
past 1), its time, its outcome (not done), its verdict (its first line,
else its first sentence, 80 characters at most); whole in its agent's
section, several rounds' each under its own; none yet, none shown."
  (should (equal (agent-workflow--pane-verdict "No commit: none changed in look.\n- all 13 taken")
                 "No commit: none changed in look."))
  (should (equal (agent-workflow--pane-verdict "**Approved**: `a.el` reads well.") "Approved: a.el reads well."))
  (should (equal (agent-workflow--pane-verdict (concat "First sentence, short. " (make-string 90 ?x)))
                 "First sentence, short."))
  (should (= (length (agent-workflow--pane-verdict (make-string 120 ?x))) 80))
  (with-temp-buffer
    (should-not (agent-workflow--pane-notes-element))
    (let ((time (float-time (encode-time '(0 16 14 23 11 2026 nil -1 nil)))))
      (setq-local agent-workflow--pane-notes
                  (list (list :job "capture" :round 1 :outcome "done" :time time
                              :text "No commit: none changed in look.\n- all 13 taken")
                        (list :job "review" :round 1 :outcome "changes" :time (+ time 60) :text "Name it better.")
                        (list :job "review" :round 2 :outcome "approved" :time (+ time 240) :text "Reads well now.")
                        (list :job "review" :round 3 :outcome "approved" :time (+ time 300) :text "Approved: it reads well.")))
      (should (equal (mapcar (lambda (step) (list (plist-get step :name) (plist-get step :detail)))
                             (plist-get (agent-workflow--pane-notes-element) :steps))
                     '(("capture" "14:16 · No commit: none changed in look.")
                       ("review" "14:17 · changes · Name it better.")
                       ("review · round 2" "14:20 · approved · Reads well now.")
                       ("review · round 3" "14:21 · Approved: it reads well."))))
      ;; Each unfolding to its whole; those unfolded given.
      (should (equal (mapcar (lambda (step) (plist-get step :body)) (plist-get (agent-workflow--pane-notes-element) :steps))
                     '("No commit: none changed in look.\n- all 13 taken" "Name it better." "Reads well now."
                       "Approved: it reads well.")))
      (should (equal (plist-get (agent-workflow--pane-notes-element '("capture")) :open) '("capture"))))))

(ert-deftest agent-workflow-pane/notes-of-fixes ()
  "A failed step's agent's notes, from its journal: each fix said (fixing
its step · the try that failed), in its section's headings (its round too
once its job's notes are of several) and in the feed; its agent step's,
its step's name in its section only."
  (with-temp-buffer
    (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
    (let ((time (float-time (encode-time '(0 41 20 23 11 2026 nil -1 nil)))))
      (pcase-dolist (`(,event ,at ,data)
                     `(("job-started" 0 (:job "green" :round 1))
                       ("step-started" 0 (:job "green" :step 2 :kind "run" :try 1 :name "watch"))
                       ("fixing" 10 (:job "green" :step 2 :name "watch"))
                       ("step-ended" 360 (:job "green" :step 2 :outcome "done" :notes "Not fixed: it logs why."))
                       ("step-started" 370 (:job "green" :step 2 :kind "run" :try 2 :name "watch"))
                       ("fixing" 2000 (:job "green" :step 2 :name "watch"))
                       ("step-ended" 2500 (:job "green" :step 2 :outcome "done" :notes "Fixed: the frame."))
                       ("went-back" 2600 (:job "green" :step 2 :name "watch"))
                       ("job-started" 2600 (:job "green" :round 2))
                       ("step-started" 2600 (:job "green" :step 2 :kind "run" :try 1 :name "watch"))
                       ("fixing" 2700 (:job "green" :step 2 :name "watch"))
                       ("step-ended" 2800 (:job "green" :step 2 :outcome "done" :notes "Fixed: again."))
                       ("job-started" 0 (:job "docs" :round 1))
                       ("step-started" 0 (:job "docs" :step 0 :agent "github · docs" :name "write"))
                       ("step-ended" 60 (:job "docs" :step 0 :outcome "done" :notes "Wrote it."))))
        (agent-workflow--pane-time event data (+ time at)))
      (should (equal (mapcar (lambda (note) (plist-get note :what)) agent-workflow--pane-notes)
                     '("fixing watch · try 1" "fixing watch · try 2" "fixing watch · try 1" "write")))
      (should (equal (mapcar (lambda (step) (plist-get step :name)) (plist-get (agent-workflow--pane-notes-element) :steps))
                     '("green · fixing watch · try 1" "green · fixing watch · try 2"
                       "green · round 2 · fixing watch · try 1" "docs")))
      (should (equal (mapcar (lambda (step) (plist-get step :detail)) (plist-get (agent-workflow--pane-notes-element) :steps))
                     '("20:47 · Not fixed: it logs why." "21:22 · Fixed: the frame." "21:27 · Fixed: again."
                       "20:42 · Wrote it."))))))

(ert-deftest agent-workflow-pane/notes-of-agents-gone ()
  "A pane drawn from its run's journal, its agents gone (Emacs started
again, its pane closed and opened again): its agents' notes in Notes, each
unfolding to its whole (no section of its agent's made for them); one
unfolded stays so as it's drawn again."
  (let* ((dir (file-name-as-directory (make-temp-file "awp-notes-" t)))
         (run (agent-workflow-run--make
               :project dir :issue "demo-9" :n 1 :dir dir :info '(:title "Gone") :state 'done
               :workflow '(:name "quick" :jobs (("build" :steps ((:kind agent :agent "build")))
                                                ("review" :needs ("build") :steps ((:kind agent :agent "review")))))
               :jobs '(("build" :status done :round 1) ("review" :status done :round 1 :outcome "approved"))))
         (agent-ui-display-function #'ignore)
         (pane nil))
    (with-temp-file (expand-file-name "journal.jsonl" dir)
      (dolist (event '((:ev "job-started" :job "build" :round 1)
                       (:ev "step-ended" :job "build" :step 0 :outcome "done" :notes "Built it.\n- a.el:3")
                       (:ev "job-done" :job "build" :outcome "done")
                       (:ev "job-started" :job "review" :round 1)
                       (:ev "step-ended" :job "review" :step 0 :outcome "approved" :notes "Fine.")
                       (:ev "job-done" :job "review" :outcome "approved")
                       (:ev "run-done")))
        (insert (json-serialize (append (list :t "2026-11-23T13:00:00+0000") event)) "\n")))
    (unwind-protect
        (progn
          (setq pane (agent-workflow--pane-make run))
          (should (equal (+test-awp--sections pane t) '("run" "notes" "log")))
          (should (equal (mapcar (lambda (step) (plist-get step :name))
                                 (plist-get (agent-ui-get "notes" :canvas pane :section "notes") :steps))
                         '("build" "review")))
          (should (equal (plist-get (car (plist-get (agent-ui-get "notes" :canvas pane :section "notes") :steps)) :body)
                         "Built it.\n- a.el:3"))
          ;; Folded: its line, ▸; unfolded (RET on it), its whole under it,
          ;; kept so as the pane's drawn again.
          (with-current-buffer pane
            (agent-ui--flush)
            (should (string-match-p "▸ [0-9:]+ · Built it\\." (buffer-string)))
            (should-not (string-search "a.el:3" (buffer-string)))
            (goto-char (point-min))
            (search-forward "Built it.")
            (funcall (get-text-property (match-beginning 0) 'agent-ui-action))
            (agent-ui--flush)
            (should (string-match-p "▾ [0-9:]+ · Built it\\." (buffer-string)))
            (should (string-search "a.el:3" (buffer-string))))
          (agent-workflow--pane-draw run)
          (with-current-buffer pane
            (agent-ui--flush)
            (should (string-search "a.el:3" (buffer-string)))))
      (when (buffer-live-p pane) (kill-buffer pane))
      (delete-directory dir t))))

(ert-deftest agent-workflow-pane/rounds ()
  "Its rounds, a bar each: ended, done whatever its outcome (approved,
changes: in its name), not red; replaced or cancelled, grey; running,
growing (no end)."
  (with-temp-buffer
    (setq-local agent-workflow--pane-rounds
                (list (list :job "build" :round 1 :start 100.0 :end 160.0 :outcome "done")
                      (list :job "review" :round 1 :start 160.0 :end 200.0 :outcome "changes")
                      (list :job "docs" :round 1 :start 160.0 :end 170.0 :outcome "replaced")
                      (list :job "build" :round 2 :start 200.0 :end 230.0 :outcome "done")
                      (list :job "review" :round 2 :start 230.0 :end 260.0 :outcome "approved")
                      (list :job "merge" :round 1 :start 260.0 :end nil)))
    (should (equal (mapcar (lambda (task) (list (plist-get task :name) (plist-get task :status)))
                           (plist-get (agent-workflow--pane-rounds-element) :tasks))
                   '(("build" "done") ("review → changes" "done") ("docs → replaced" "queued")
                     ("build · round 2" "done") ("review · round 2 → approved" "done") ("merge" "running"))))
    (should-not (plist-get (car (last (plist-get (agent-workflow--pane-rounds-element) :tasks))) :end)))
  ;; The run failed: its round failed, red.
  (with-temp-buffer
    (setq-local agent-workflow--pane-rounds
                (list (list :job "green" :round 1 :start 100.0 :end 110.0 :outcome "failed")))
    (should (equal (plist-get (car (plist-get (agent-workflow--pane-rounds-element) :tasks)) :status) "failed"))))

(ert-deftest agent-workflow-pane/rounds-to-the-millisecond ()
  "Its rounds' bars stamped to the millisecond, as the job list times them:
a check of 690 ms was a bar of 1 s (its start and end cut to the second)."
  (with-temp-buffer
    (setq-local agent-workflow--pane-rounds
                (list (list :job "check" :round 1 :start 1795641469.46142 :end 1795641470.151197 :outcome "done")
                      (list :job "all-green" :round 1 :start 1795641470.204792 :end nil)))
    (let ((tasks (plist-get (agent-workflow--pane-rounds-element) :tasks)))
      (should (equal (plist-get (car tasks) :start) "2026-11-25T21:17:49.461Z"))
      (should (equal (plist-get (car tasks) :end) "2026-11-25T21:17:50.151Z"))
      (should (equal (plist-get (cadr tasks) :start) "2026-11-25T21:17:50.204Z")))))

(ert-deftest agent-workflow-pane/journal-to-the-millisecond ()
  "The journal's times to the millisecond, read back so: a pane opened later
times its steps as one open all along (690 ms, not 1 s or 0 s). A journal
written before: whole seconds; a time that doesn't read: now."
  (should (string-match-p "\\`[0-9-]+T[0-9:]+\\.[0-9]\\{3\\}\\+0000\\'" (agent-workflow--now)))
  (let ((now (agent-workflow--journal-time (list :t (agent-workflow--now)))))
    (should (< (abs (- now (float-time))) 1)))
  (should (< (abs (- (- (agent-workflow--journal-time '(:t "2026-11-25T21:17:50.151+0000"))
                        (agent-workflow--journal-time '(:t "2026-11-25T21:17:49.461+0000")))
                     0.69))
             0.001))
  (should (= (agent-workflow--journal-time '(:t "2026-11-23T09:42:07+0000"))
             (float-time (date-to-time "2026-11-23T09:42:07+0000"))))
  (should (< (abs (- (agent-workflow--journal-time '(:t "not a time")) (float-time))) 1))
  (should (< (abs (- (agent-workflow--journal-time '(:ev "no time")) (float-time))) 1)))

(ert-deftest agent-workflow-pane/rounds-sent-back ()
  "A job sending the work back (review: changes, rerun build): its round
closed as it does, with its outcome (review → changes), not running through
build's round 2 then replaced; the others it replaced, replaced; their
times not counting on."
  (with-temp-buffer
    (setq-local agent-workflow--pane-rounds nil)
    (setq-local agent-workflow--pane-notes nil)
    (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
    (pcase-dolist (`(,event ,time ,data)
                   '(("job-started" 100.0 (:job "build" :round 1))
                     ("job-done" 160.0 (:job "build"))
                     ("job-started" 160.0 (:job "review" :round 1))
                     ("job-started" 160.0 (:job "docs" :round 1))
                     ("step-ended" 200.0 (:job "review" :step 0 :outcome "changes"))
                     ("went-back" 201.0 (:job "build" :step 0 :by "review" :replaced ["build" "docs" "review"]))
                     ("job-started" 202.0 (:job "build" :round 2))))
      (agent-workflow--pane-time event data time))
    (should (equal (mapcar (lambda (task) (list (plist-get task :name) (plist-get task :status)))
                           (plist-get (agent-workflow--pane-rounds-element) :tasks))
                   '(("build" "done") ("review → changes" "done") ("docs → replaced" "queued")
                     ("build · round 2" "running"))))
    (should-not (gethash "review" agent-workflow--pane-times))
    (should-not (gethash "docs" agent-workflow--pane-times))
    (should (gethash "build" agent-workflow--pane-times))))

(ert-deftest agent-workflow-pane/waiting-for-an-agent ()
  "A running job whose next agent step waits for a free agent (the pool
full): not drawn running (no spinner, no time), saying why; its run's State
tile its state alone."
  (let* ((workflow '(:name "w" :jobs (("a" :name "a" :steps ((:kind agent :agent "build")
                                                             (:kind run :run "make")
                                                             (:kind agent :agent "review"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "demo-1" :state 'running :workflow workflow
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "a" (list :status 'running :step 2 :pool 2
                                                                    :why "a: waiting for an agent: 3 of 3 work"))))))
    (let ((item (with-temp-buffer
                  (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
                  (puthash "a" (list :started 100.0 :steps '((2 :started 150.0))) agent-workflow--pane-times)
                  (agent-workflow--pane-job run "a" (cdr (assoc "a" (agent-workflow-run-jobs run)))))))
      (should (equal (plist-get item :status) "pending"))
      (should-not (plist-get item :started))
      (should (string-match-p "waits: a: waiting for an agent: 3 of 3 work" (plist-get item :detail)))
      (should (equal (mapcar (lambda (step) (plist-get step :status)) (plist-get item :steps)) '("done" "done" "pending")))
      (should-not (plist-get (nth 2 (plist-get item :steps)) :started)))
    (should (equal (agent-workflow--pane-state run) '("● running" "accent")))))

(ert-deftest agent-workflow-pane/a-step-s-try ()
  "A running job's line: its step's first try says no try; its second, try
2 (its tries count the one running)."
  (let* ((workflow '(:name "github" :jobs (("green" :name "green" :steps ((:kind run :run "watch.sh" :name "watch"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "github" :n 1 :state 'running :workflow workflow
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "green" (list :status 'running :step 0 :tries '((0 . 1))))))))
    (cl-flet ((detail () (with-temp-buffer
                           (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
                           (plist-get (agent-workflow--pane-job run "green" (cdr (assoc "green" (agent-workflow-run-jobs run))))
                                      :detail))))
      (should-not (detail))
      (setf (cdr (assoc "green" (agent-workflow-run-jobs run))) (list :status 'running :step 0 :tries '((0 . 2))))
      (should (equal (detail) "try 2")))))

(ert-deftest agent-workflow-pane/a-step-being-fixed ()
  "A step that failed, its agent fixing it (its job's :retry): failed, its
detail who fixes it (the agent's agent, else its on-fail) and the try that
failed, of all it may have; its job's line says fixing. A job of one step:
all on its line. A merge's conflicts: resolving them."
  (let* ((workflow '(:name "github"
                     :jobs (("green" :name "green"
                             :steps ((:kind run :run "push.sh" :name "push")
                                     (:kind run :run "watch.sh" :name "watch" :retries 5 :on-fail "ci")))
                            ("lint" :name "lint" :steps ((:kind run :run "lint.sh" :retries 2 :on-fail "build"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "github" :n 1 :state 'running :workflow workflow
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "green" (list :status 'running :step 1 :retry 1
                                                                        :tries '((0 . 1) (1 . 1))))
                                                    (cons "lint" (list :status 'running :step 0 :retry 0
                                                                       :tries '((0 . 2))))))))
    (with-temp-buffer
      (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
      (cl-flet ((item (job) (agent-workflow--pane-job run job (cdr (assoc job (agent-workflow-run-jobs run))))))
        (let* ((green (item "green"))
               (watch (nth 1 (plist-get green :steps))))
          (should (equal (plist-get green :status) "running"))
          (should (equal (plist-get green :detail) "fixing"))
          (should (equal (plist-get (car (plist-get green :steps)) :status) "done"))
          (should (equal (plist-get watch :status) "failed"))
          (should (equal (plist-get watch :detail) "run: watch.sh · ci fixing it · try 1 of 6")))
        ;; The agent fixing it known: its agent.
        (setf (plist-get (cdr (assoc "green" (agent-workflow-run-jobs run))) :agent)
              (agent-workflow-agent--make :issue "github" :job "green" :definition "fixer")
              (plist-get (cdr (assoc "green" (agent-workflow-run-jobs run))) :tries) '((0 . 1) (1 . 3)))
        (should (equal (plist-get (nth 1 (plist-get (item "green") :steps)) :detail)
                       "run: watch.sh · fixer fixing it · try 3 of 6"))
        ;; One step: all on its job's line, no try said twice.
        (should (equal (plist-get (item "lint") :detail) "build fixing it · try 2 of 3"))
        ;; A merge's conflicts.
        (setf (plist-get (cdr (assoc "lint" (agent-workflow-run-jobs run))) :resolving) t)
        (should (equal (plist-get (item "lint") :detail) "build resolving its conflicts"))
        ;; Fixed, the step running again: running, no fixing.
        (setf (cdr (assoc "green" (agent-workflow-run-jobs run))) (list :status 'running :step 1 :tries '((1 . 4))))
        (let ((green (item "green")))
          (should (equal (plist-get green :detail) "try 4"))
          (should (equal (plist-get (nth 1 (plist-get green :steps)) :status) "running"))
          (should (equal (plist-get (nth 1 (plist-get green :steps)) :detail) "run: watch.sh")))))))

(ert-deftest agent-workflow-pane/live-boxes ()
  "A job running, its live box (Agent UI's activity, its job its owner): its
agent at work (fixing a failed step, its agent step), what on and its
turn's time in its header, its actions as they come (the latest last and
bright, the box's lines at most, a tool call's line where it came, its text
as it's known better, each marked by its kind), counted; Show session (Go
to it while it asks, ◆, its question its last line); else its script
running, named, its step of all, its try and its time in its header, its
command first, its output's last lines (colour codes gone, a line redrawn
in place its last state), its lines counted; Show output; neither (its
agent kept, stopped; nothing running), none. Show session and Show output
pressed: shown."
  (let* ((workflow '(:name "github"
                     :jobs (("green" :name "green"
                             :steps ((:kind run :run "push.sh" :name "push")
                                     (:kind run :run "watch.sh" :name "watch" :retries 5 :on-fail "ci"
                                      :on-fail-run "rerun.sh")))
                            ("docs" :name "docs" :steps ((:kind agent :agent "docs" :name "write"))))))
         (session (generate-new-buffer " *test agent session*"))
         (agent (agent-workflow-agent--make :issue "github" :job "green" :definition "ci" :buffer session))
         (run (agent-workflow-run--make :project "/p/" :issue "github" :n 1 :state 'running :workflow workflow
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "green" (list :status 'running :step 1 :retry 1 :agent agent
                                                                        :tries '((0 . 1) (1 . 1))))
                                                    (cons "docs" (list :status 'pending)))))
         (agent-workflow--pane-activity (make-hash-table :test #'eq :weakness 'key))
         (agent-workflow-pane-box-lines 3)
         (state (lambda (job) (cdr (assoc job (agent-workflow-run-jobs run)))))
         (box (lambda (job) (agent-workflow--pane-box job (funcall state job))))
         (event (lambda (name &optional id kind title)
                  (agent-workflow--pane-agent-event
                   agent (list (cons :event name)
                               (cons :data (and id (list (cons :tool-call-id id)
                                                         (cons :tool-call (list (cons :kind kind) (cons :title title)))))))))))
    (unwind-protect
        (with-temp-buffer
          (setq-local agent-workflow--pane-run run
                      agent-workflow--pane-times (make-hash-table :test #'equal))
          (let ((element (funcall box "green")))
            (should (equal (plist-get element :id) "now-green"))
            (should (equal (plist-get element :type) "activity"))
            (should (equal (plist-get element :owner) "green"))
            (should (equal (plist-get element :sources) '("green" "docs")))
            (should (equal (plist-get element :label) "agent ci"))
            (should (equal (plist-get element :detail) "fixing step 2 (watch) · try 1 of 6"))
            (should (equal (plist-get element :mark) "●"))
            ;; Nothing yet: said.
            (should-not (plist-get element :lines))
            (should-not (plist-get element :footer))
            (should (equal (plist-get element :empty) "Nothing done yet in this turn."))
            (should (agent-ui-check 'activity element)))
          (funcall event 'tool-call-update "t0" "read" "Read a.el")
          (let ((element (funcall box "green")))
            (should (equal (+test-awp--box-lines element) '("≡ Read a.el")))
            (should (equal (plist-get element :footer) "1 action in this turn"))
            (should (equal (+test-awp--labels element) '("Show session"))))
          ;; Its turn, its actions as they come.
          (funcall event 'input-submitted)
          (funcall event 'tool-call-update "t1" "execute" "gh run view 1")
          (funcall event 'tool-call-update "t2" "read" "Read `config/stripe/gui.el`")
          (funcall event 'tool-call-update "t1" "execute" "gh run view 1 --log-failed")
          (let ((element (funcall box "green")))
            (should (string-match-p "\\`its turn [0-9]+s\\'" (plist-get element :right)))
            (should (equal (+test-awp--box-lines element) '("❯ gh run view 1 --log-failed" "≡ Read config/stripe/gui.el"))))
          (funcall event 'tool-call-update "t3" "edit" "Edit tests.yml")
          (funcall event 'tool-call-update "t4" "other" "Thinking")
          (let ((element (funcall box "green")))
            (should (equal (+test-awp--box-lines element)
                           '("≡ Read config/stripe/gui.el" "± Edit tests.yml" "• Thinking")))
            ;; Counted: all its turn's, more than shown.
            (should (equal (plist-get element :footer) "4 actions in this turn"))
            ;; The latest bright, those before muted; their words no level
            ;; (no error found in them).
            (should (equal (mapcar (lambda (line) (list (plist-get line :mark-face) (plist-get line :level)))
                                   (plist-get element :lines))
                           '(("muted" "debug") ("muted" "debug") ("accent" nil)))))
          ;; It asks you: said, its button at the question.
          (setf (alist-get "green" (agent-workflow-run-jobs run) nil nil #'equal)
                (append (list :status 'waiting :agent-asks '(:kind permission :what "Bash")) (funcall state "green")))
          (let ((element (funcall box "green")))
            (should (equal (list (plist-get element :mark) (plist-get element :mark-face)) '("◆" "warning")))
            (should (equal (list (plist-get element :right) (plist-get element :right-face)) '("asks you" "warning")))
            (should (equal (car (last (+test-awp--box-lines element))) "? may it: Bash"))
            (should (equal (plist-get element :footer) "4 actions in this turn · waiting for your answer"))
            (should (equal (+test-awp--labels element) '("Go to it"))))
          ;; Fixed, its script running again, its agent kept: its script's box.
          (let* ((output (generate-new-buffer " *test script*"))
                 (process (make-process :name "test-script" :buffer output :command '("sleep" "30") :noquery t)))
            (unwind-protect
                (progn
                  (puthash "green" (list :steps (list (cons 1 (list :started (- (float-time) 75))))) agent-workflow--pane-times)
                  (setf (alist-get "green" (agent-workflow-run-jobs run) nil nil #'equal)
                        (list :status 'running :step 1 :agent agent :process process :tries '((1 . 2))))
                  ;; No output yet: its command alone.
                  (let ((element (funcall box "green")))
                    (should (equal (+test-awp--box-lines element) '("❯ watch.sh")))
                    (should-not (plist-get element :footer)))
                  (with-current-buffer output
                    (insert "\e[32mstep one\e[0m\n\nprogress 10%\rprogress 90%\nstep two\nstep three\n"))
                  (puthash "green" (list :steps (list (cons 1 (list :started (- (float-time) 75))))) agent-workflow--pane-times)
                  (setf (alist-get "green" (agent-workflow-run-jobs run) nil nil #'equal)
                        (list :status 'running :step 1 :agent agent :process process :tries '((1 . 2))))
                  (let ((element (funcall box "green")))
                    (should (equal (mapcar (lambda (key) (plist-get element key)) '(:owner :label :detail :right))
                                   '("green" "watch" "step 2 of 2 · try 2" "1m 15s")))
                    (should (equal (+test-awp--box-lines element) '("❯ watch.sh" "progress 90%" "step two" "step three")))
                    ;; Its lines counted, all (not blank), more than shown.
                    (should (equal (plist-get element :footer) '("the last 3 of 4 lines")))
                    (should (equal (+test-awp--labels element) '("Show output")))
                    (should (agent-ui-check 'activity element)))
                  ;; More, an error: counted, those read before not again.
                  (with-current-buffer output (insert "error: refused\nhalf a li"))
                  (should (equal (plist-get (funcall box "green") :footer)
                                 '("the last 3 of 5 lines" " · " (:text "1 error" :face "error"))))
                  (let (shown)
                    (cl-letf (((symbol-function 'pop-to-buffer) (lambda (buffer &rest _) (setq shown buffer))))
                      (agent-workflow--pane-answer "output green" nil "run/now-green"))
                    (should (eq shown output)))
                  ;; Its on-fail script fixing it (its agent kept): the script's
                  ;; box, said so, its time from the script's start.
                  (puthash "green" (list :fix-started (- (float-time) 20)
                                         :steps (list (cons 1 (list :started (- (float-time) 75)))))
                           agent-workflow--pane-times)
                  (setf (alist-get "green" (agent-workflow-run-jobs run) nil nil #'equal)
                        (list :status 'running :step 1 :retry 1 :fix-script t :agent agent :process process
                              :tries '((1 . 2))))
                  (let ((element (funcall box "green")))
                    (should (equal (mapcar (lambda (key) (plist-get element key)) '(:label :detail :right))
                                   '("on-fail script" "fixing watch · try 2 of 6" "20s")))
                    (should (equal (car (+test-awp--box-lines element)) "❯ rerun.sh"))))
              (delete-process process)
              (kill-buffer output)))
          ;; Nothing running: none.
          (setf (alist-get "green" (agent-workflow-run-jobs run) nil nil #'equal)
                (list :status 'running :step 1 :agent agent :tries '((1 . 2))))
          (should-not (funcall box "green"))
          ;; An agent step: its name; Show session pressed, its session.
          (setf (alist-get "docs" (agent-workflow-run-jobs run) nil nil #'equal)
                (list :status 'running :step 0 :agent agent))
          (should (equal (mapcar (lambda (key) (plist-get (funcall box "docs") key)) '(:owner :label :detail))
                         '("docs" "agent ci" "step 1 (write)")))
          (let (opened)
            (cl-letf (((symbol-function 'agent-workflow--pane-open-session) (lambda (_run job) (setq opened job))))
              (agent-workflow--pane-answer "session docs" nil "run/now-docs"))
            (should (equal opened "docs")))
          ;; Stopped, its session gone: none.
          (setf (agent-workflow-agent-stopping agent) t)
          (should-not (funcall box "docs"))
          (setf (agent-workflow-agent-stopping agent) nil)
          (kill-buffer session)
          (should-not (funcall box "docs")))
      (when (buffer-live-p session) (kill-buffer session)))))

(ert-deftest agent-workflow-pane/an-agent-s-model-and-effort ()
  "An agent's box says what its session runs, after its agent: its model
(its default by what it is) and its effort, as its session says them; until
it does, what it was asked for; neither known, nothing."
  (let* ((session (generate-new-buffer " *test agent session*"))
         (agent (agent-workflow-agent--make :issue "github" :job "docs" :definition "docs" :buffer session))
         (options (lambda (model effort)
                    ;; Its config options, as agent-shell keeps claude-agent-acp's.
                    (delq nil
                          (list (list (cons :id "model") (cons :category "model") (cons :current-value model)
                                      (cons :options (list (list (cons :value "default") (cons :name "Default (recommended)")
                                                                 (cons :description "Opus 5.5"))
                                                           (list (cons :value "sonnet") (cons :name "Sonnet 5.5")
                                                                 (cons :description "Most efficient")))))
                                (and effort
                                     (list (cons :id "effort") (cons :category "thought_level")
                                           (cons :current-value effort)
                                           (cons :options (mapcar (lambda (level) (list (cons :value level)))
                                                                  '("default" "low" "high")))))))))
         (state (lambda (state) (with-current-buffer session (setq-local agent-shell--state state))))
         (run (agent-workflow-run--make :project "/p/" :issue "github" :n 1 :state 'running
                                        :workflow '(:name "github" :jobs (("docs" :name "docs" :steps ((:kind agent :agent "docs" :name "write")))))
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "docs" (list :status 'running :step 0 :agent agent)))))
         (agent-workflow--pane-activity (make-hash-table :test #'eq :weakness 'key)))
    (unwind-protect
        (progn
          ;; Nothing known: nothing said.
          (should-not (agent-workflow--pane-agent-model agent))
          ;; Asked (its step's), its session not saying yet.
          (setf (agent-workflow-agent-model agent) "sonnet"
                (agent-workflow-agent-effort agent) "low")
          (should (equal (agent-workflow--pane-agent-model agent) "sonnet · low effort"))
          ;; Its session's: its default by what it is, its effort.
          (funcall state (list (cons :config-options (funcall options "default" "high"))))
          (should (equal (agent-workflow--pane-agent-model agent) "Opus 5.5 · high effort"))
          (funcall state (list (cons :config-options (funcall options "sonnet" "default"))))
          (should (equal (agent-workflow--pane-agent-model agent) "Sonnet 5.5 · default effort"))
          ;; Its model offering no effort: none said (what was asked, skipped).
          (funcall state (list (cons :config-options (funcall options "sonnet" nil))))
          (should (equal (agent-workflow--pane-agent-model agent) "Sonnet 5.5"))
          ;; No config options: its session's model, the effort asked.
          (funcall state (list (cons :session (list (cons :model-id "haiku")
                                                    (cons :models (list (list (cons :model-id "haiku") (cons :name "Haiku 5.5"))))))))
          (should (equal (agent-workflow--pane-agent-model agent) "Haiku 5.5 · low effort"))
          ;; In its box's header, after its agent, before what it's on.
          (funcall state (list (cons :config-options (funcall options "default" "high"))))
          (with-temp-buffer
            (setq-local agent-workflow--pane-run run
                        agent-workflow--pane-times (make-hash-table :test #'equal))
            (let ((element (agent-workflow--pane-box "docs" (cdr (assoc "docs" (agent-workflow-run-jobs run))))))
              (should (equal (mapcar (lambda (key) (plist-get element key)) '(:label :detail))
                             '("agent docs" "Opus 5.5 · high effort · step 1 (write)")))
              (should (agent-ui-check 'activity element)))))
      (kill-buffer session))))

(ert-deftest agent-workflow-pane/an-agent-s-cost-not-known ()
  "A run with an agent whose cost isn't known (another agent reporting
none): its Cost tile says so (+), its budget's words too."
  (let ((run (agent-workflow-run--make :project "/p/" :issue "demo-1" :n 1 :state 'running
                                       :workflow '(:name "feature" :jobs nil) :jobs nil
                                       :spent '(:cost 1.5 :tokens 10 :cost-unknown t))))
    (cl-letf (((symbol-function 'agent-workflow-run-budget) (lambda (_) '(:cost 10))))
      (should (equal (plist-get (seq-find (lambda (tile) (equal (plist-get tile :label) "Cost"))
                                          (agent-workflow--pane-figures run))
                                :value)
                     "$1.50+"))
      (should (string-prefix-p "$1.50 (an agent's not known) of $10"
                               (agent-workflow--budget-words (agent-workflow-run-spent-now run) '(:cost 10)))))))

(ert-deftest agent-workflow-pane/live-boxes-at-the-bottom ()
  "The live boxes at the Run section's bottom: under Rounds, even one
shown before Rounds came (all shown again under it)."
  (let* ((session (generate-new-buffer " *test agent session*"))
         (agent (agent-workflow-agent--make :issue "github" :job "docs" :definition "docs" :buffer session))
         (run (agent-workflow-run--make :project "/p/" :issue "github" :n 1 :state 'running
                                        :workflow '(:name "github" :jobs (("docs" :name "docs" :steps ((:kind agent :agent "docs")))))
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "docs" (list :status 'running :step 0 :agent agent)))))
         (agent-ui-display-function #'ignore)
         (agent-workflow--pane-activity (make-hash-table :test #'eq :weakness 'key))
         (agent-workflow--pane-boxes-timer nil)
         (pane (agent-ui-canvas (make-temp-name "boxes-"))))
    (unwind-protect
        (with-current-buffer pane
          (setq-local agent-workflow--pane-run run
                      agent-workflow--pane-times (make-hash-table :test #'equal))
          (agent-ui-section pane "run" :title "Run")
          (agent-ui-show '(:id "jobs" :type "text" :text "jobs") :canvas pane :section "run")
          (agent-workflow--pane-show-boxes run pane)
          (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-components :canvas pane :section "run"))
                         '("jobs" "now-docs")))
          ;; Rounds came after it: it under Rounds.
          (agent-ui-show '(:id "rounds" :type "text" :text "rounds") :canvas pane :section "run")
          (agent-workflow--pane-show-boxes run pane)
          (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-components :canvas pane :section "run"))
                         '("jobs" "rounds" "now-docs"))))
      (when (timerp agent-workflow--pane-boxes-timer) (cancel-timer agent-workflow--pane-boxes-timer))
      (kill-buffer pane)
      (kill-buffer session))))

(ert-deftest agent-workflow-pane/its-commits-before-its-files ()
  "Under its header: git, its commits, its files changed; a commit coming
after its files were shown (a run's first commit): still above them."
  (let* ((agent-ui-display-function #'ignore)
         (pane (agent-ui-canvas (make-temp-name "where-")))
         (where '(:branch "feature/x" :worktree "/w/" :into "main"
                  :files ((:path "a.el" :status changed :added 1 :removed 0 :uncommitted t))))
         (ids (lambda () (with-current-buffer pane
                           (seq-filter (lambda (key) (member key '("git" "commits" "changes" "where-note")))
                                       agent-ui--order)))))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-workflow-run-where) (lambda (&rest _) where)))
          (with-current-buffer pane
            (agent-workflow--pane-show-where nil pane)
            (should (equal (funcall ids) '("git" "changes")))
            ;; Its first commit: above its files.
            (setq where (append where '(:commits (("abc1234" "A commit")))))
            (agent-workflow--pane-show-where nil pane)
            (should (equal (funcall ids) '("git" "commits" "changes")))
            ;; Shown again as it is: nothing moves.
            (agent-workflow--pane-show-where nil pane)
            (should (equal (funcall ids) '("git" "commits" "changes")))))
      (kill-buffer pane))))

(ert-deftest agent-workflow-pane/its-log-in-columns ()
  "Its Log, an event a line in columns: its time, a mark (an error's or a
warning's making its line one), its job (none for the run's), a step's
named (else its script's file), its words in the same column as its job's
(indented, they read as out of line), an agent's left out; how
long a script, a fix, a job and the run took at its end; a pause of 5
minutes or more between two lines said; its span, its first line to its
last."
  (let* ((workflow '(:name "github"
                     :jobs (("green" :name "green"
                             :steps ((:kind run :run "scripts/check.sh --all")
                                     (:kind run :run "push.sh" :name "push")
                                     (:kind agent :agent "docs"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "demo-1" :state 'running :workflow workflow
                                        :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "green" (list :status 'running :step 0)))))
         (t0 1795000000.0)
         (events `((0 "run-started" :workflow "github" :by "you")
                   (0 "job-started" :job "green" :round 1)
                   (0 "step-started" :job "green" :step 0 :kind "run" :try 1)
                   (1 "script-ended" :job "green" :step 0 :exit 0)
                   (1 "step-started" :job "green" :step 1 :kind "run" :name "push" :try 1)
                   (600 "script-ended" :job "green" :step 1 :exit 1 :name "push")
                   (600 "fixing" :job "green" :step 1 :name "push")
                   (700 "step-ended" :job "green" :step 1 :outcome "done" :name "push")
                   (700 "step-started" :job "green" :step 2 :kind "agent")
                   (790 "step-ended" :job "green" :step 2 :outcome "done")
                   (800 "job-done" :job "green")
                   (900 "cancelled" :by "you"))))
    (with-temp-buffer
      (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
      (setq-local agent-workflow--pane-rounds nil)
      (setq-local agent-workflow--pane-notes nil)
      (setq-local agent-workflow--pane-doing nil)
      (setq-local agent-workflow--pane-log-span nil)
      (let ((lines (cl-loop for (at event . data) in events
                            do (agent-workflow--pane-time event data (+ t0 at))
                            append (agent-workflow--pane-log-lines run event data (+ t0 at)))))
        (should (equal (mapcar #'+test-awp--line lines)
                       '("▸ · started with github · by you"
                         "▸ green started"
                         "› green check.sh started"
                         "✓ green check.sh exited 0 (1s)"
                         "› green push started"
                         "┊ 10m"
                         "✗ green push exited 1 (9m 59s)"
                         "↻ green push failed · its agent fixes it"
                         "✓ green push fixed (1m 40s)"
                         "✓ green done (13m 20s)"
                         "⊘ · run cancelled, by you (15m)")))
        (let ((real (seq-remove (lambda (line) (plist-get line :gap)) lines)))
          (should (equal (mapcar (lambda (line) (plist-get line :level)) real)
                         '(nil nil nil nil nil "error" "warning" nil nil "error")))
          ;; Every one's words in one column: none indented.
          (should-not (seq-some (lambda (line) (plist-get line :indent)) real))
          (should (equal (plist-get (car real) :time) (format-time-string "%H:%M" t0)))
          ;; Drawn: its time once a minute, its job in its column.
          (should (string-match-p "\n +▸  green  started\n +›  green  check\\.sh started\n"
                                  (substring-no-properties
                                   (agent-ui-render (list :type "log" :sources '("green") :lines lines)
                                                    (agent-ui-context :width 70))))))
        (should (equal (agent-workflow--pane-log-span)
                       (format "%s – %s · 15m" (format-time-string "%H:%M" t0) (format-time-string "%H:%M" (+ t0 900)))))))))

(ert-deftest agent-workflow-pane/what-it-is-at ()
  "Running, its State tile says its state alone: not what it's at (each
running job's step: its checklist says it), nor near its budget (its Log):
a line more grew its tile."
  (let* ((workflow '(:name "github"
                     :jobs (("green" :name "green"
                             :steps ((:kind run :run "check.sh" :name "check")
                                     (:kind run :run "push.sh" :name "push")
                                     (:kind run :run "watch.sh" :name "watch")))
                            ("docs" :name "docs" :steps ((:kind agent :agent "docs"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "demo-1" :state 'running
                                        :workflow workflow :spent '(:cost 0 :tokens 0) :active 60
                                        :jobs (list (cons "green" (list :status 'running :step 2))
                                                    (cons "docs" (list :status 'pending))))))
    (should (equal (+test-awp--figure (agent-workflow--pane-header run) "State") '("● running" nil "accent")))
    (setf (alist-get "docs" (agent-workflow-run-jobs run) nil nil #'equal) (list :status 'running :step 0))
    (setf (agent-workflow-run-warned run) t)
    (should (equal (+test-awp--figure (agent-workflow--pane-header run) "State") '("● running" nil "accent")))
    (should (equal (+test-awp--figure (agent-workflow--pane-header run) "Jobs") '("0 / 2" "done" nil)))
    ;; Its header without its name (its tab's, its buffer's); a ticket's
    ;; run, its issue's title.
    (setf (agent-workflow-run-workflow run) (plist-put (copy-sequence workflow) :ticketless t))
    (should-not (plist-member (agent-workflow--pane-header run) :title))
    (setf (agent-workflow-run-workflow run) workflow
          (agent-workflow-run-info run) '(:title "Lexer escapes"))
    (should (equal (plist-get (agent-workflow--pane-header run) :title) "Lexer escapes"))))

(ert-deftest agent-workflow-pane/a-failed-run ()
  "A run that failed: its State tile says it, red (why: its Log); its job failed (✗, an
error in the graph), its steps done up to the one that failed, named, what
each does after its name."
  (let* ((workflow '(:name "github"
                     :jobs (("green" :name "green"
                             :steps ((:kind run :run "check.sh" :name "check")
                                     (:kind run :run "push.sh" :name "push")
                                     (:kind run :run "watch.sh"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "demo-1" :state 'failed
                                        :why "green: its step 2, push (push.sh): refused"
                                        :workflow workflow :spent '(:cost 0 :tokens 0) :active 60
                                        :jobs (list (cons "green" (list :status 'failed :step 1))))))
    (should (equal (+test-awp--figure (agent-workflow--pane-header run) "State")
                   '("✗ failed" nil "error")))
    (let ((node (car (plist-get (agent-workflow--pane-graph run) :nodes))))
      (should (equal (plist-get node :label) "green ✗"))
      (should (equal (plist-get node :status) "error")))
    (let ((item (with-temp-buffer
                  (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
                  (agent-workflow--pane-job run "green" (cdr (assoc "green" (agent-workflow-run-jobs run)))))))
      (should (equal (plist-get item :status) "failed"))
      (should (equal (mapcar (lambda (step) (list (plist-get step :name) (plist-get step :status) (plist-get step :detail)))
                             (plist-get item :steps))
                     '(("check" "done" "run: check.sh") ("push" "failed" "run: push.sh") ("run: watch.sh" "pending" nil)))))))

(ert-deftest agent-workflow-pane/a-cancelled-run ()
  "A cancelled run's job (its own status cancelled): no spinner, grey
\(skipped), its line saying cancelled; its steps done before the one it was
on, the rest grey; ⊘ in the graph, not coloured."
  (let* ((workflow '(:name "github"
                     :jobs (("green" :name "green"
                             :steps ((:kind run :run "push.sh" :name "push")
                                     (:kind run :run "watch.sh" :name "watch"))))))
         (run (agent-workflow-run--make :project "/p/" :issue "github" :n 1 :state 'cancelled
                                        :workflow workflow :spent '(:cost 0 :tokens 0)
                                        :jobs (list (cons "green" (list :status 'cancelled :step 1))))))
    (let ((node (car (plist-get (agent-workflow--pane-graph run) :nodes))))
      (should (equal (plist-get node :label) "green ⊘"))
      (should-not (plist-get node :status)))
    (let ((item (with-temp-buffer
                  (setq-local agent-workflow--pane-times (make-hash-table :test #'equal))
                  (agent-workflow--pane-job run "green" (cdr (assoc "green" (agent-workflow-run-jobs run)))))))
      (should (equal (plist-get item :status) "skipped"))
      (should (equal (plist-get item :detail) "cancelled"))
      (should (equal (mapcar (lambda (step) (plist-get step :status)) (plist-get item :steps)) '("done" "skipped"))))))

(ert-deftest agent-workflow-pane/where-in-words ()
  "Its state as tiles: its mark, its time, what it spent, its tokens (if it
spent some), each against its budget. Where its work is: ⎇ its branch, where it started →
what it merges into (merged, deleted once it is; its worktree removed,
said; its reading jobs' snapshots); its files changed (not committed,
said), its commits; started from another branch than the main one, said."
  (let ((run (agent-workflow-run--make :project "/p/" :issue "demo-1" :state 'waiting
                                       :workflow '(:name "feature" :budget (:cost 15 :time 10800))
                                       :spent '(:cost 1.24 :tokens 182000) :active 900)))
    (let ((header (agent-workflow--pane-header run)))
      (should (equal (mapcar (lambda (f) (plist-get f :label)) (plist-get header :figures))
                     '("State" "Time" "Cost" "Tokens" "Jobs")))
      (should (equal (+test-awp--figure header "State") '("◆ needs you" nil "warning")))
      (should (equal (+test-awp--figure header "Time") '("15m" "of 3h" nil)))
      (should (equal (+test-awp--figure header "Cost") '("$1.24" "of $15" nil)))
      (should (equal (+test-awp--figure header "Tokens") '("182k" nil nil))))
    (setf (agent-workflow-run-state run) 'running
          (agent-workflow-run-workflow run) '(:name "feature")
          (agent-workflow-run-spent run) '(:cost 0 :tokens 0))
    (let ((header (agent-workflow--pane-header run)))
      (should (equal (mapcar (lambda (f) (plist-get f :label)) (plist-get header :figures))
                     '("State" "Time" "Cost" "Jobs")))
      (should (equal (+test-awp--figure header "State") '("● running" nil "accent")))
      (should (equal (+test-awp--figure header "Time") '("15m" nil nil)))))
  (should (equal (agent-workflow--pane-git-line
                  '(:branch "feat/demo-1-x" :into "main" :worktree "/p/w/" :base (:branch "main" :commit "abcdef1234")))
                 "⎇ feat/demo-1-x   main@abcdef1 → main"))
  (should (equal (agent-workflow--pane-git-line '(:branch "feat/demo-1-x" :into "main" :merged t))
                 "⎇ feat/demo-1-x   merged into main · its worktree removed"))
  (should (equal (agent-workflow--pane-git-line '(:branch "feat/demo-1-x" :into "main" :deleted t :merged t))
                 "⎇ feat/demo-1-x   deleted, merged into main"))
  (should (equal (agent-workflow--pane-git-line '(:branch "feat/demo-1-x" :into "main" :worktree "/p/w/"
                                                  :snapshots (("review" "/p/w@review/" "1234567890"))))
                 "⎇ feat/demo-1-x   → main\nreview reads its snapshot at 1234567"))
  (should-not (agent-workflow--pane-git-line '(:into "main")))
  (let ((run (agent-workflow-run--make :project "/p/" :issue "demo-1")))
    (pcase-let ((`(,git ,commits ,changes ,_removal ,note)
                 (agent-workflow--pane-git
                  run '(:branch "feat/demo-1-x" :into "main" :worktree "/p/w/" :with 0
                        :files ((:path "a.el" :status changed :added 2 :removed 1 :uncommitted t)
                                (:path "b.el" :status added :added 3))
                        :commits (("abc1234" "A commit"))))))
      (should (equal (+test-awp--labels git) '("Worktree" "Magit")))
      (should (equal changes '(:id "changes" :type "files" :caption "2 files changed · 1 not committed"
                               :dir "/p/w/" :tree :false
                               :files ((:path "a.el" :status "changed" :added 2 :removed 1 :note "not committed")
                                       (:path "b.el" :status "added" :added 3)))))
      ;; Each its caption, as a log's counts.
      (should (equal (plist-get git :caption) "branch"))
      (should (equal (plist-get commits :caption) "1 commit"))
      (should (equal (plist-get (nth 1 (agent-workflow--pane-git
                                       run '(:branch "b" :into "main" :own 9 :commits (("a" "x") ("b" "y")))))
                                :caption)
                     "9 commits, the last 2"))
      (should (equal (plist-get commits :rows) '(("abc1234" "A commit"))))
      (should (eq (plist-get commits :nowrap) t))
      (should (equal (plist-get (plist-get commits :row-open) :prompt) "{0}"))
      (should-not note))
    (should (equal (nth 4 (agent-workflow--pane-git run '(:into "main" :with 3 :base (:branch "side" :commit "abc"))))
                   '(:id "where-note" :type "text" :face "warning"
                     :text "Started from side, not main: its 3 commits not in main are merged too.")))
    (should-not (nth 4 (agent-workflow--pane-git run '(:into "main" :with 3 :merged t :base (:branch "side" :commit "abc")))))))

(ert-deftest agent-workflow-pane/git-s-buttons-say-what-they-do ()
  "Its git line's Worktree and Magit, hovered: what they open (the pane's
own), not a prompt they'd put into a session's."
  (let* ((element (car (agent-workflow--pane-git nil '(:branch "feature/x" :worktree "/w/" :into "main"))))
         (text (agent-ui-render element (agent-ui-context))))
    (should (equal (get-text-property (string-search "⏵ Worktree" text) 'help-echo text) "RET: open its worktree"))
    (should (equal (get-text-property (string-search "⏵ Magit" text) 'help-echo text) "RET: magit on its worktree"))))

(ert-deftest agent-workflow-pane/a-checkout-run-has-no-worktree-button ()
  "A run in your checkout (runs-in: checkout): no worktree of its own, so
no Worktree button (it would open your project); Magit, on your checkout."
  (let ((element (car (agent-workflow--pane-git nil '(:checkout t :branch "main" :worktree "/p/" :into "main")))))
    (should (equal (+test-awp--labels element) '("Magit")))
    (should (equal (plist-get (car (plist-get element :actions)) :help) "magit on your checkout"))))

(ert-deftest agent-workflow-pane/where-its-work-is ()
  "Started from a branch other than the main one: its git line says its
branch, where it started and what it merges into, the start branch's
commit merged too, said; a commit and a file changed by its agent, its
files changed (not committed, said) and its commits, once looked at again;
status has the same; kept in its state.json. Done: its worktree removed
\(its branch kept: not merged), said."
  (+test-awp "where"
    (let* ((main (agent-workflow-main-branch project))
           (agent-workflow--where-age 0)
           (base (let ((default-directory project))
                   (call-process "git" nil nil nil "checkout" "-q" "-b" "side")
                   (+test-awr--commit project "side.txt" "a side commit")
                   (agent-workflow--git "rev-parse" "HEAD")))
           (issue (+test-awr--issue project "Where it is"))
           (run (car (car (agent-workflow-run-ticket (list issue) nil project))))
           (pane (agent-workflow-run-pane run))
           (dir (progn (+test-awr--agent run "build") (agent-workflow-worktree-directory project issue)))
           (branch (agent-workflow-issue-branch issue "feature" "Where it is"))
           (git (lambda () (plist-get (agent-ui-get "git" :canvas pane) :text))))
      (should (equal (agent-workflow-run-base run) (list :branch "side" :commit base)))
      (should (equal (funcall git) (format "⎇ %s   side@%s → %s" branch (substring base 0 7) main)))
      (should-not (ignore-errors (agent-ui-get "changes" :canvas pane)))
      (should (equal (plist-get (agent-ui-get "where-note" :canvas pane) :text)
                     (format "Started from side, not %s: its 1 commit not in %s is merged too." main main)))
      ;; Its agent commits, changes a file: said once looked at again.
      (+test-awr--commit dir "a.txt" "a commit of its own")
      (write-region "x" nil (expand-file-name "b.txt" dir))
      (agent-workflow--pane-where-tick)
      (should (equal (plist-get (agent-ui-get "changes" :canvas pane) :files)
                     '((:path "a.txt" :status "added" :added 1 :removed 0)
                       (:path "b.txt" :status "added" :note "not committed"))))
      (should (equal (cadr (car (plist-get (agent-ui-get "commits" :canvas pane) :rows))) "a commit of its own"))
      (should (equal (plist-get (aref (plist-get (agent-workflow--request-status project nil) :runs) 0) :where)
                     (list :worktree dir :branch branch :deleted :false
                           :base (list :branch "side" :commit base) :into main
                           :own 1 :with 1 :uncommitted 1 :merged :false :checkout :false)))
      (should (equal (plist-get (with-temp-buffer
                                  (insert-file-contents (expand-file-name "state.json" (agent-workflow-run-dir run)))
                                  (json-parse-buffer :object-type 'plist :array-type 'list))
                                :base)
                     (list :branch "side" :commit base)))
      ;; Done (nothing left uncommitted): its worktree removed, said.
      (delete-file (expand-file-name "b.txt" dir))
      (+test-awr--finish run "build")
      (+test-awr--finish run "review" "approved")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      (should-not (file-exists-p dir))
      (should (equal (funcall git) (format "⎇ %s   side@%s → %s · its worktree removed"
                                           branch (substring base 0 7) main)))
      (should-not (ignore-errors (agent-ui-get "changes" :canvas pane))))))

;; ====== EVERY RUN ======

(ert-deftest agent-workflow-pane/the-runs-listed ()
  "M-x agent-workflow-list: every run of the project, those over read from
their folders; RET opens a run's pane, selected."
  (+test-awp "list"
    (let* ((one (+test-awr--issue project "One"))
           (run (car (car (let ((agent-workflow-from-shell t)) (agent-workflow-run-ticket (list one) nil project))))))
      (agent-workflow--cancel run)
      ;; Read from its folder, as after Emacs started again.
      (let ((agent-workflow--runs nil))
        (save-window-excursion
          (agent-workflow-list project)
          (with-current-buffer (format "*agent-workflow runs: %s*" (file-name-nondirectory (directory-file-name project)))
            (should (derived-mode-p 'agent-workflow-list-mode))
            (should (= (length tabulated-list-entries) 1))
            (should (equal (aref (cadr (car tabulated-list-entries)) 0) one))
            (should (equal (substring-no-properties (aref (cadr (car tabulated-list-entries)) 3)) "cancelled"))
            (goto-char (point-min))
            (let ((agent-ui-display-function (lambda (buffer) (set-window-buffer (selected-window) buffer))))
              (agent-workflow-list-open))
            (should (equal (buffer-name (window-buffer (selected-window))) (format "Agent UI: %s · feature" one)))))))))

;; ====== FROM THE SHELL ======

(defmacro +test-awp--with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/awp-" t))
          (server-name "test")
          (process-environment
           (cons (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                 process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-awp--script (&rest args)
  "cmd/agent-workflow ARGS started in `default-directory': its process,
its output in its buffer."
  (make-process :name "agent-workflow" :buffer (generate-new-buffer " *agent-workflow*")
                :command (cons (expand-file-name "cmd/agent-workflow" +test-root) args)
                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                :stderr (get-buffer-create " *agent-workflow-stderr*")))

(defun +test-awp--ended (process &optional timeout)
  "PROCESS waited for (TIMEOUT seconds at most): (STATUS . OUTPUT)."
  (with-timeout ((or timeout 60) (delete-process process) (ert-fail "cmd/agent-workflow didn't end"))
    (while (not (+test-process-ended-p process))
      (accept-process-output nil 0.05)))
  (prog1 (cons (process-exit-status process)
               (with-current-buffer (process-buffer process) (string-trim (buffer-string))))
    (kill-buffer (process-buffer process))))

(ert-deftest agent-workflow-pane/followed-from-the-shell ()
  "run: its runs' logs printed as they go, until they end (0: done; what
needs you said with its command); --detach: the reply only; logs: a run's
log, or its journal; status: its state, its jobs."
  (+test-awp "shell"
    (+test-awp--with-server
      (let* ((issue (+test-awr--issue project "From the shell" "--type" "task"))
             (process (+test-awp--script "run" issue)))
        ;; Its result waits for your OK: said, how to answer too; approved.
        (let ((run (+test-awr--wait (lambda () (agent-workflow-run-of project issue)))))
          (should-not (agent-workflow-run-pane run))
          (+test-awr--finish-step run "build")
          (should (+test-awr--wait (lambda () (agent-workflow-asking run))))
          (agent-workflow--approve run))
        (pcase-let ((`(,status . ,output) (+test-awp--ended process)))
          (should (= status 0))
          (let ((lines (split-string output "\n")))
            (should (string-match-p (format "\\`[0-9:]\\{8\\}  %s  ·  started, with gate, by you\\'" (regexp-quote issue))
                                    (car lines)))
            (should (seq-some (lambda (line) (string-search (format "→ agent-workflow approve %s, or reject %s NOTE" issue issue)
                                                            line))
                              lines))
            (should (string-suffix-p "run done" (car (last lines))))))
        ;; logs, --json: the same run.
        (pcase-let ((`(,status . ,output) (+test-awp--ended (+test-awp--script "logs" issue))))
          (should (= status 0))
          (should (string-suffix-p "run done" output)))
        (pcase-let ((`(,status . ,output) (+test-awp--ended (+test-awp--script "logs" issue "--json"))))
          (should (= status 0))
          (should (equal (plist-get (json-parse-string (car (split-string output "\n")) :object-type 'plist) :ev)
                         "run-started")))
        (pcase-let ((`(,status . ,output) (+test-awp--ended (+test-awp--script "logs" issue "-f" "--json"))))
          (should (= status 0))
          (should (equal (plist-get (json-parse-string (car (split-string output "\n")) :object-type 'plist) :issue)
                         issue)))
        ;; status: its jobs.
        (pcase-let* ((`(,status . ,output) (+test-awp--ended (+test-awp--script "status" issue)))
                     (run (car (plist-get (json-parse-string output :object-type 'plist :array-type 'list) :runs))))
          (should (= status 0))
          (should (equal (plist-get run :state) "done"))
          (should (equal (mapcar (lambda (job) (plist-get job :status)) (plist-get run :jobs)) '("done"))))
        ;; --detach: the reply, at once; cancelled: 1, followed.
        (let ((two (+test-awr--issue project "Detached" "--type" "task")))
          (pcase-let ((`(,status . ,output) (+test-awp--ended (+test-awp--script "run" two "--detach"))))
            (should (= status 0))
            (should (string-match-p "log\\.txt" (plist-get (car (plist-get (json-parse-string output :object-type 'plist
                                                                                               :array-type 'list)
                                                                            :started))
                                                          :log))))
          (let ((process (+test-awp--script "logs" two "-f")))
            (agent-workflow--cancel (agent-workflow-run-of project two))
            (pcase-let ((`(,status . ,output) (+test-awp--ended process)))
              (should (= status 1))
              (should (string-suffix-p "run cancelled, by you" output)))))
        (should (equal (+test-awp--ended (+test-awp--script "logs"))
                       '(2 . "{\"ok\":false,\"error\":\"logs: which issue? agent-workflow logs ISSUE [-f] [--json]\"}")))))))
