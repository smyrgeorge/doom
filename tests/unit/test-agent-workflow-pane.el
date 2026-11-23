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
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

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

(defun +test-awp--sections (pane &optional all)
  "PANE's sections' names; but Needs you, unless ALL (a stand-in's turn
ending without its done makes it wait for you, a moment)."
  (let ((names (mapcar (lambda (s) (plist-get s :name)) (agent-ui-sections pane))))
    (if all names (remove "needs-you" names))))

(defun +test-awp--settle ()
  "Timers due now run (an answer's given after its command)."
  (let ((end (+ (float-time) 0.3)))
    (while (< (float-time) end) (accept-process-output nil 0.02))))

(defun +test-awp--answer (pane choice &optional note)
  "PANE's question answered: CHOICE picked, NOTE given, its Answer pressed."
  (agent-ui-update "ask" (list :selected (list choice) :note-text note) :canvas pane :section "needs-you")
  (with-current-buffer pane
    (let ((agent-ui-pressed "needs-you/ask"))
      (funcall agent-ui-action-function "the answer" t))))

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
sections Run and Log; each agent a section, its session's canvas shown
there (what it shows goes there); its job over, folded, its mark done, the
agent's elements gone with it. Its log, log.txt and the pane's. Done: its
checklist's countdown closes it all."
  (+test-awp "pane"
    (let* ((issue (+test-awr--issue project "A pane"))
           (run (car (car (agent-workflow-run (list issue) nil project))))
           (pane (agent-workflow-run-pane run)))
      (should (buffer-live-p pane))
      (should (equal (buffer-name pane) (format "Agent UI: %s · feature" issue)))
      (should (equal shown (list pane)))
      (should (equal (+test-awp--sections pane) '("run" "log")))
      ;; Build's agent: its section, its canvas there.
      (let* ((agent (+test-awr--agent run "build"))
             (name (agent-ui--session-name (agent-workflow-agent-buffer agent))))
        (should (+test-awr--wait (lambda () (member "job.build" (+test-awp--sections pane)))))
        (should (equal (+test-awp--sections pane) '("run" "job.build" "log")))
        (should (equal (plist-get (seq-find (lambda (s) (equal (plist-get s :name) "job.build")) (agent-ui-sections pane))
                                  :hosts)
                       name))
        (agent-ui-show '(:id "plan" :type "steps" :steps ("Read" "Write")) :canvas name)
        (should-not (get-buffer (agent-ui-canvas-buffer-name name)))
        (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas pane :section "job.build"))
                       '("plan")))
        ;; RET on its divider: its session.
        (with-current-buffer pane
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "▾ build")
          (cl-letf (((symbol-function 'pop-to-buffer) (lambda (buffer &rest _) (push buffer shown))))
            (agent-ui-section-open))
          (should (eq (car shown) (agent-workflow-agent-buffer agent)))))
      ;; What it shows.
      (let ((header (agent-ui-get "run" :canvas pane))
            (jobs (agent-ui-get "jobs" :canvas pane :section "run")))
        (should (equal (plist-get header :title) (concat issue ": A pane")))
        (should (string-match-p "\\`feature · \\(running\\|waits for you\\) · " (plist-get header :text)))
        (should (equal (mapcar (lambda (s) (plist-get s :name)) (plist-get jobs :steps)) '("build" "docs" "review")))
        (should (member (plist-get (car (plist-get jobs :steps)) :status) '("running" "pending"))))
      (should (seq-some (lambda (line) (string-match-p (format "  %s  build  started\\'" (regexp-quote issue)) line))
                        (plist-get (agent-ui-get "log" :canvas pane :section "log") :lines)))
      ;; Build done: folded, done; its agent's elements gone with it.
      (+test-awr--finish run "build")
      (should (+test-awr--wait (lambda () (null (agent-ui-elements :canvas pane :section "job.build")))))
      (let ((build (seq-find (lambda (s) (equal (plist-get s :name) "job.build")) (agent-ui-sections pane))))
        (should (plist-get build :folded))
        (should (eq (plist-get build :state) 'done)))
      ;; Review's: after build's.
      (+test-awr--agent run "review")
      (should (+test-awr--wait (lambda () (member "job.review" (+test-awp--sections pane)))))
      (should (equal (+test-awp--sections pane) '("run" "job.build" "job.review" "log")))
      (+test-awr--finish run "review" "approved")
      (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
      ;; Its log: every event a line, the pane's the same.
      (let ((lines (agent-workflow-log-lines run)))
        (should (string-match-p "  ·  run done\\'" (car (last lines))))
        (should (seq-some (lambda (line) (string-match-p "  docs  skipped" line)) lines))
        (should (equal (last (plist-get (agent-ui-get "log" :canvas pane :section "log") :lines) 3)
                       (last lines 3)))
        ;; log.txt gone: made again from the journal, the same.
        (delete-file (agent-workflow--log-path run))
        (should (equal (mapcar (lambda (line) (substring line 10)) (agent-workflow-log-lines run))
                       (mapcar (lambda (line) (substring line 10)) lines))))
      ;; Done: its checklist finished, counting down; over, the pane goes.
      (with-current-buffer pane
        (should (equal agent-ui-closes-with "run/jobs"))
        (should (gethash "run/jobs" agent-ui--closing))
        (agent-ui--flush)
        (should (string-search "All done, closing in" (buffer-string))))
      (agent-ui--close-finished pane '("run/jobs"))
      (should-not (buffer-live-p pane))
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
           (run (car (car (let ((agent-workflow-from-shell t)) (agent-workflow-run (list issue) nil project))))))
      (should-not (agent-workflow-run-pane run))
      (let ((pane (agent-workflow-pane run)))
        (should (buffer-live-p pane))
        (should-not shown)
        (+test-awr--finish-step run "build" "built it")
        (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
        (should (equal (+test-awp--sections pane t) '("run" "needs-you" "job.build" "log")))
        (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas pane :section "needs-you"))
                       '("ask" "look")))
        (should (equal (plist-get (agent-ui-get "ask" :canvas pane :section "needs-you") :options) '("Approve" "Reject")))
        (should (string-match-p "Notes: built it" (plist-get (agent-ui-get "look" :canvas pane :section "needs-you") :text)))
        ;; Said once a wait: its turn's end without done before, then this.
        (should (string-match-p "its result waits for your OK" (cdar said)))
        (should (= (seq-count (lambda (s) (string-match-p "your OK" (cdr s))) said) 1))
        (agent-workflow--changed run)
        (should (= (seq-count (lambda (s) (string-match-p "your OK" (cdr s))) said) 1))
        ;; Waiting for you, it opens by itself only once you looked.
        (should-not shown)
        ;; Rejected without a note: refused, still asked.
        (should (string-match-p "Say why in a note"
                                (cadr (should-error (+test-awp--answer pane "Reject") :type 'user-error))))
        (+test-awp--answer pane "Reject" "shorter, please")
        (+test-awp--settle)
        ;; Its agent told (it runs, its turn ends without done: waiting).
        (should (+test-awr--wait (lambda () (seq-some (lambda (p) (string-search "shorter, please" p))
                                                      (+test-awr--prompts "needs")))))
        ;; Asked again: approved, done.
        (+test-awr--finish-step run "build" "shorter now")
        (should (+test-awr--wait (lambda () (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))))
        (should (equal (plist-get (agent-ui-get "ask" :canvas pane :section "needs-you") :options) '("Approve" "Reject")))
        (should (= (seq-count (lambda (s) (string-match-p "your OK" (cdr s))) said) 2))
        (+test-awp--answer pane "Approve")
        (+test-awp--settle)
        (should (+test-awr--wait (lambda () (eq (agent-workflow-run-state run) 'done))))
        (should-not (member "needs-you" (+test-awp--sections pane t)))
        (should (member "approve, by you, in its pane"
                        (mapcar (lambda (line) (car (last (split-string line "  ")))) (agent-workflow-log-lines run))))))))

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
           (run (car (car (agent-workflow-run (list issue) nil project))))
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
                              (cadr (should-error (agent-workflow-confirm run "go") :type 'user-error))))
      ;; Needs you: agent-shell's buttons, and Go to it.
      (should (+test-awr--wait (lambda () (+test-awp--ask pane))))
      (let ((ask (+test-awp--ask pane)))
        (should (equal (plist-get ask :question) why))
        (should (string-prefix-p "Allow" (car (plist-get ask :options))))
        (should (equal (car (last (plist-get ask :options))) agent-workflow--pane-go-to-it))
        ;; Allow, from the pane: its agent goes on; its turn over without
        ;; done, the usual wait.
        (+test-awp--answer pane (car (plist-get ask :options))))
      (+test-awp--settle)
      (should (+test-awr--wait (lambda () (equal (agent-workflow-run-why run)
                                                 "build: its agent ended its turn without saying it's done"))))
      (should-not (agent-workflow-agent-asking run))
      (should (+test-awr--wait (lambda () (equal (plist-get (+test-awp--ask pane) :options)
                                                 '("Run its step again" "Cancel the run")))))
      (should (member "answered its agent, by you"
                      (mapcar (lambda (line) (car (last (split-string line "  ")))) (agent-workflow-log-lines run))))
      (should (equal (seq-filter (lambda (event) (member event '("asked" "answered"))) (+test-awr--journal run))
                     '("asked" "answered")))
      ;; A question, its form in its session (its job running again).
      (agent-workflow--job-set run "build" :status 'running :why nil)
      (agent-workflow--agent-event agent '((:event . elicitation-request)
                                           (:data (:message . "Retina or 1x?\nThe screen is 1x."))))
      (should (equal (agent-workflow-run-why run) "build: its agent asks you: Retina or 1x?"))
      (should (+test-awr--wait (lambda () (equal (plist-get (+test-awp--ask pane) :options)
                                                 (list agent-workflow--pane-go-to-it)))))
      ;; Go to it: its session shown; asked here again, it still is.
      (+test-awp--answer pane agent-workflow--pane-go-to-it)
      (+test-awp--settle)
      (should (get-buffer-window (agent-workflow-agent-buffer agent)))
      (should (agent-workflow-agent-asking run))
      (should (+test-awp--ask pane))
      (should-not (plist-get (+test-awp--ask pane) :selected))
      ;; Answered there: running, Needs you gone.
      (agent-workflow--agent-event agent '((:event . elicitation-response)))
      (should (eq (agent-workflow-run-state run) 'running))
      (should (+test-awr--wait (lambda () (not (member "needs-you" (+test-awp--sections pane t)))))))))

;; ====== WHERE ITS WORK IS ======

(ert-deftest agent-workflow-pane/where-in-words ()
  "Where a run's work is, in its header's words: its branch, its commits,
what isn't committed, where it started, what it merges into (merged once
it is); under it, its worktree and its reading jobs' snapshots; started
from another branch than the main one, said."
  (should (equal (agent-workflow--pane-where-lines
                  '(:branch "feat/demo-1-x" :into "main" :own 2 :uncommitted 1 :worktree "/p/w/"
                    :base (:branch "main" :commit "abcdef1234")))
                 '("⎇ feat/demo-1-x: 2 commits, 1 file not committed" "from main at abcdef1 · merges into main")))
  (should (equal (agent-workflow--pane-where-lines '(:branch "feat/demo-1-x" :into "main" :own 1 :merged t
                                                     :base (:branch nil :commit "abcdef1234")))
                 '("⎇ feat/demo-1-x: 1 commit, its worktree removed" "from a detached HEAD at abcdef1 · merged into main")))
  (should (equal (agent-workflow--pane-where-lines '(:branch "feat/demo-1-x" :into "main" :own 0 :worktree "/p/w/"))
                 '("⎇ feat/demo-1-x: no commit yet" "merges into main")))
  (should (equal (agent-workflow--pane-where-lines '(:branch "feat/demo-1-x" :into "main" :own 0 :merged t))
                 '("⎇ feat/demo-1-x: its worktree removed" "merged into main")))
  (should-not (agent-workflow--pane-where-lines '(:into "main")))
  (let ((run (agent-workflow-run--make :project "/p/" :issue "demo-1")))
    (should (equal (agent-workflow--pane-where
                    run '(:worktree "/p/w/" :into "main" :with 0 :snapshots (("review" "/p/w@review/" "1234567890"))))
                   '((:id "where" :type "files" :dir "/p/"
                      :files ((:path "w/" :note "its worktree") (:path "w@review/" :note "review's snapshot, at 1234567")))
                     nil)))
    (should (equal (agent-workflow--pane-where run '(:into "main" :with 3 :base (:branch "side" :commit "abc")))
                   '(nil (:id "where-note" :type "text" :face "warning"
                          :text "Started from side, not main: its 3 commits not in main are merged too."))))
    (should (equal (agent-workflow--pane-where run '(:into "main" :with 3 :merged t :base (:branch "side" :commit "abc")))
                   '(nil nil)))))

(ert-deftest agent-workflow-pane/where-its-work-is ()
  "Started from a branch other than the main one: its header says its
branch, where it started and what it merges into, its worktree under it,
the start branch's commit merged too, said; a commit and a file changed by
its agent, said once looked at again; status has the same; kept in its
state.json. Done: its worktree removed, said."
  (+test-awp "where"
    (let* ((main (agent-workflow-main-branch project))
           (agent-workflow--where-age 0)
           (base (let ((default-directory project))
                   (call-process "git" nil nil nil "checkout" "-q" "-b" "side")
                   (+test-awr--commit project "side.txt" "a side commit")
                   (agent-workflow--git "rev-parse" "HEAD")))
           (issue (+test-awr--issue project "Where it is"))
           (run (car (car (agent-workflow-run (list issue) nil project))))
           (pane (agent-workflow-run-pane run))
           (dir (progn (+test-awr--agent run "build") (agent-workflow-worktree-directory project issue)))
           (branch (agent-workflow-issue-branch issue "feature" "Where it is"))
           (text (lambda () (plist-get (agent-ui-get "run" :canvas pane) :text))))
      (should (equal (agent-workflow-run-base run) (list :branch "side" :commit base)))
      (should (string-search (format "⎇ %s: no commit yet" branch) (funcall text)))
      (should (string-search (format "from side at %s · merges into %s" (substring base 0 7) main) (funcall text)))
      (should (equal (plist-get (agent-ui-get "where" :canvas pane) :files)
                     (list (list :path (file-relative-name dir project) :note "its worktree"))))
      (should (equal (plist-get (agent-ui-get "where-note" :canvas pane) :text)
                     (format "Started from side, not %s: its 1 commit not in %s is merged too." main main)))
      ;; Its agent commits, changes a file: said once looked at again.
      (+test-awr--commit dir "a.txt" "a commit of its own")
      (write-region "x" nil (expand-file-name "b.txt" dir))
      (agent-workflow--pane-where-tick)
      (should (string-search ": 1 commit, 1 file not committed" (funcall text)))
      (should (equal (plist-get (aref (plist-get (agent-workflow--request-status project nil) :runs) 0) :where)
                     (list :worktree dir :branch branch :deleted :false
                           :base (list :branch "side" :commit base) :into main
                           :own 1 :with 1 :uncommitted 1 :merged :false)))
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
      (should (string-search ": 1 commit, its worktree removed" (funcall text)))
      (should-not (ignore-errors (agent-ui-get "where" :canvas pane))))))

;; ====== EVERY RUN ======

(ert-deftest agent-workflow-pane/the-runs-listed ()
  "M-x agent-workflow-runs: every run of the project, those over read from
their folders; RET opens a run's pane, selected."
  (+test-awp "list"
    (let* ((one (+test-awr--issue project "One"))
           (run (car (car (let ((agent-workflow-from-shell t)) (agent-workflow-run (list one) nil project))))))
      (agent-workflow-cancel run)
      ;; Read from its folder, as after Emacs started again.
      (let ((agent-workflow--runs nil))
        (save-window-excursion
          (agent-workflow-runs project)
          (with-current-buffer (format "*agent-workflow runs: %s*" (file-name-nondirectory (directory-file-name project)))
            (should (derived-mode-p 'agent-workflow-runs-mode))
            (should (= (length tabulated-list-entries) 1))
            (should (equal (aref (cadr (car tabulated-list-entries)) 0) one))
            (should (equal (substring-no-properties (aref (cadr (car tabulated-list-entries)) 3)) "cancelled"))
            (goto-char (point-min))
            (let ((agent-ui-display-function (lambda (buffer) (set-window-buffer (selected-window) buffer))))
              (agent-workflow-runs-open))
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
          (agent-workflow-approve run))
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
            (agent-workflow-cancel (agent-workflow-run-of project two))
            (pcase-let ((`(,status . ,output) (+test-awp--ended process)))
              (should (= status 1))
              (should (string-suffix-p "run cancelled, by you" output)))))
        (should (equal (+test-awp--ended (+test-awp--script "logs"))
                       '(2 . "{\"ok\":false,\"error\":\"logs: which issue? agent-workflow logs ISSUE [-f] [--json]\"}")))))))
