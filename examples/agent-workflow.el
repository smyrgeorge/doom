;;; $DOOMDIR/examples/agent-workflow.el -*- lexical-binding: t; -*-
;; Example: a run's pane (the agent-workflow package's, config/agent-workflow.el,
;; docs/agent-workflow.md).
;; M-x +my/example-agent-workflow makes a small compiler project (a git
;; repository in the temp folder, demo-1's branch in its worktree: two
;; commits, a file not committed yet) and opens the pane of a run of the
;; feature workflow on demo-1, in the frame's two windows (beside its top,
;; its live boxes, Notes and its Log), as it runs: build done
;; (its notes in Notes), test's unit tests failed then fixed by its ci agent,
;; its e2e script running now (its output in its box, a real script's), docs
;; writing (its agent's last actions in its box), review and merge to come.
;; Its tiles, its branch, its flow, its checklist, its rounds, its Log are
;; the pane's own, drawn from the run's journal; the run itself isn't
;; started (no agent, no Beads: nothing runs but the e2e script), its boxes
;; moved on each second by the example. Try: TAB on a divider folds its
;; section, RET on a commit or a file opens it, Show output. The folder is
;; deleted once the pane is closed (q).

;; ====== VARIABLES ======

(defvar agent-shell--state)

(defconst +my/example-agent-workflow--session-state
  '((:config-options ((:id . "model") (:category . "model") (:current-value . "default")
                      (:options ((:value . "default") (:name . "Default (recommended)") (:description . "Opus 5.5"))))
                     ((:id . "effort") (:category . "thought_level") (:current-value . "high")
                      (:options ((:value . "default")) ((:value . "high"))))))
  "The docs agent's session's state, as agent-shell keeps it: its model (its
default, Opus 5.5) and its effort, high.")

(defconst +my/example-agent-workflow--issue "demo-1"
  "The example run's issue.")

(defconst +my/example-agent-workflow--workflow
  '(:name "feature" :budget (:cost 15 :time 10800)
    :jobs (("build" :name "build" :steps ((:kind agent :agent "build" :name "implement")))
           ("test" :name "test" :needs ("build")
            :steps ((:kind run :run "make lint" :name "lint")
                    (:kind run :run "make test" :name "unit" :retries 3 :on-fail "ci")
                    (:kind run :run "make e2e" :name "e2e")))
           ("docs" :name "docs" :needs ("build") :steps ((:kind agent :agent "docs" :name "write")))
           ("review" :name "review" :needs ("test" "docs") :steps ((:kind agent :agent "review" :name "review")))
           ("merge" :name "merge" :needs ("review") :steps ((:kind uses :uses "merge")))))
  "The run's workflow, as read: build, then test and docs, review, merge.")

(defconst +my/example-agent-workflow--journal
  ;; Seconds ago, event, its data.
  '((1080 "run-started" :workflow "feature" :by "you")
    (1080 "job-started" :job "build" :round 1)
    (1080 "step-started" :job "build" :step 0 :kind "agent" :name "implement")
    (600 "step-ended" :job "build" :step 0 :outcome "done"
         :notes "Escapes in strings: \\n, \\t, \\\", \\\\ and \\u{…}, each with its test.\n\n- src/lexer.el: lex-string reads them\n- tests/test-lexer.el: 14 tests added")
    (600 "job-done" :job "build" :outcome "done")
    (598 "job-started" :job "test" :round 1)
    (598 "job-started" :job "docs" :round 1)
    (598 "step-started" :job "test" :step 0 :kind "run" :name "lint" :try 1)
    (594 "script-ended" :job "test" :step 0 :exit 0 :name "lint")
    (594 "step-started" :job "test" :step 1 :kind "run" :name "unit" :try 1)
    (494 "script-ended" :job "test" :step 1 :exit 1 :name "unit")
    (494 "fixing" :job "test" :step 1 :agent "demo-1 · test" :name "unit")
    (316 "step-ended" :job "test" :step 1 :outcome "done" :name "unit"
         :notes "Fixed: test-lexer expected the old error message for an unknown escape.")
    (316 "retry-from" :job "test" :step 1 :from 1 :from-name "unit" :name "unit")
    (316 "step-started" :job "test" :step 1 :kind "run" :name "unit" :try 2)
    (206 "script-ended" :job "test" :step 1 :exit 0 :name "unit")
    (206 "step-started" :job "test" :step 2 :kind "run" :name "e2e" :try 1))
  "The run so far, as its journal says it (the e2e script started last).")

(defconst +my/example-agent-workflow--actions
  '(("read" "Read src/lexer.el") ("search" "Search \"escape\" in docs/")
    ("read" "Read docs/strings.md") ("edit" "Edit docs/strings.md")
    ("execute" "make docs") ("read" "Read docs/_build/strings.html")
    ("edit" "Edit docs/strings.md") ("execute" "make docs"))
  "The docs agent's actions, one every few seconds: (KIND TEXT).")

(defconst +my/example-agent-workflow--e2e
  "i=0
for t in lexer/strings lexer/escapes lexer/unicode parser/strings parser/errors repl/paste; do
  for n in 1 2 3 4 5 6 7 8; do
    i=$((i+1))
    case $i in
      9) echo \"warning: $t/$n took 1.2s (slow)\" ;;
      *) echo \"ok $i $t/case-$n ($((i * 7 % 40 + 3)) ms)\" ;;
    esac
    sleep 0.5
  done
done
echo \"48 passed\""
  "The e2e script: its output, a line every half second.")

(defvar +my/example-agent-workflow--timer nil "What moves its boxes on.")

;; The agent-workflow package's (its parts loaded by the example).
(defvar agent-workflow--pane-activity)
(defvar agent-workflow--pane-boxes)

;; ====== CODE ======

(defun +my/example-agent-workflow--git (&rest args)
  "git ARGS in this folder; an error saying why if it failed."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil
                          "-c" "user.name=Example" "-c" "user.email=example@example.com"
                          "-c" "commit.gpgsign=false" args))
      (error "git %s: %s" (string-join args " ") (string-trim (buffer-string))))
    (string-trim (buffer-string))))

(defun +my/example-agent-workflow--project (dir)
  "The example's project in DIR, and demo-1's worktree: its base commit."
  (let ((default-directory dir)
        (process-environment (append '("GIT_CONFIG_NOSYSTEM=1" "GIT_CONFIG_GLOBAL=/dev/null") process-environment)))
    (+my/example-write dir "README.md" "# A small compiler\n\nThe example's project.\n")
    (+my/example-write dir "src/lexer.el" ";;; lexer.el --- the lexer -*- lexical-binding: t; -*-\n")
    (+my/example-write dir "src/parser.el" ";;; parser.el --- the parser -*- lexical-binding: t; -*-\n")
    (+my/example-write dir "docs/strings.md" "# Strings\n")
    (+my/example-write dir ".gitignore" ".agent-shell/\n")
    (+my/example-agent-workflow--git "init" "-q" "-b" "main")
    (+my/example-agent-workflow--git "add" ".")
    (+my/example-agent-workflow--git "commit" "-q" "-m" "A small compiler")
    (let ((base (+my/example-agent-workflow--git "rev-parse" "HEAD"))
          (worktree (agent-workflow-worktree-directory dir +my/example-agent-workflow--issue)))
      (+my/example-agent-workflow--git "worktree" "add" "-q" "-b" "feat/demo-1-lexer-escapes"
                                       (directory-file-name worktree) "main")
      (let ((default-directory worktree))
        (+my/example-write worktree "src/lexer.el"
                           ";;; lexer.el --- the lexer -*- lexical-binding: t; -*-\n\n(defun lex-string ())\n")
        (+my/example-agent-workflow--git "commit" "-q" "-am" "Lexer: string escapes")
        (+my/example-write worktree "tests/test-lexer.el" ";;; test-lexer.el -*- lexical-binding: t; -*-\n")
        (+my/example-agent-workflow--git "add" "tests/test-lexer.el")
        (+my/example-agent-workflow--git "commit" "-q" "-m" "Lexer: escapes tested")
        ;; Docs' agent at work: a file not committed yet.
        (+my/example-write worktree "docs/strings.md" "# Strings\n\nEscapes: \\n, \\t.\n"))
      base)))

(defun +my/example-agent-workflow--write-journal (dir now)
  "The run's journal in DIR, its events' times before NOW (seconds)."
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file (expand-file-name "journal.jsonl" dir)
      (pcase-dolist (`(,ago ,event . ,data) +my/example-agent-workflow--journal)
        (insert (json-serialize (append (list :t (format-time-string "%FT%T%z" (- now ago)) :ev event) data))
                "\n")))))

(defun +my/example-agent-workflow--run (dir project base now session process)
  "The example's run: its folder DIR, of PROJECT, its branch from BASE, as
its journal leaves it at NOW; docs's agent in SESSION, test's e2e script
PROCESS."
  (let ((docs (agent-workflow-agent--make :project project :issue +my/example-agent-workflow--issue
                                          :job "docs" :definition "docs" :buffer session)))
    ;; Its turn's actions so far, the latest first.
    (puthash docs (list :turn (- now 64) :count 3
                        :actions (list '("t3" "read" "Read docs/strings.md")
                                       '("t2" "search" "Search \"escape\" in docs/")
                                       '("t1" "read" "Read src/lexer.el")))
             agent-workflow--pane-activity)
    (agent-workflow-run--make
     :project project :issue +my/example-agent-workflow--issue :n 1 :dir dir :state 'running
     :workflow +my/example-agent-workflow--workflow
     :info '(:title "Lexer: strings with escapes" :type "feature")
     ;; Its cost alone (no tokens): its tiles on a row in half the frame.
     :spent '(:cost 1.24 :tokens 0) :active 1080
     :base (list :branch "main" :commit base)
     :jobs (list (cons "build" (list :status 'done :round 1 :outcome "done"))
                 (cons "test" (list :status 'running :step 2 :round 1 :process process :tries '((0 . 1) (1 . 2) (2 . 1))))
                 (cons "docs" (list :status 'running :step 0 :round 1 :agent docs))
                 (cons "review" (list :status 'pending))
                 (cons "merge" (list :status 'pending))))))

(defun +my/example-agent-workflow--tick (run pane)
  "RUN's boxes in PANE moved on: docs's agent's next action now and then,
the e2e script's output as it comes, their times; stopped with PANE."
  (if (not (buffer-live-p pane))
      (+my/example-agent-workflow--stop)
    (let* ((docs (plist-get (agent-workflow--job run "docs") :agent))
           (activity (gethash docs agent-workflow--pane-activity))
           (count (or (plist-get activity :count) 0)))
      ;; An action every 4 seconds, its turn's next.
      (when (and (zerop (% (truncate (float-time)) 4))
                 (< count (length +my/example-agent-workflow--actions)))
        (pcase-let ((`(,kind ,text) (nth count +my/example-agent-workflow--actions)))
          (agent-workflow--pane-agent-event
           docs (list (cons :event 'tool-call-update)
                      (cons :data (list (cons :tool-call-id (format "t%d" (1+ count)))
                                        (cons :tool-call (list (cons :kind kind) (cons :title text))))))))))
    (with-demoted-errors "agent workflow example: %S"
      (agent-workflow--pane-show-boxes run pane))))

(defun +my/example-agent-workflow--stop ()
  "The example's boxes stopped."
  (when (timerp +my/example-agent-workflow--timer)
    (cancel-timer +my/example-agent-workflow--timer))
  (setq +my/example-agent-workflow--timer nil))

(defun +my/example-agent-workflow--pane ()
  "The example's run's pane, if it's open."
  (get-buffer (format "Agent UI: %s · feature" +my/example-agent-workflow--issue)))

(defun +my/example-agent-workflow-ready ()
  "Non-nil once the example's pane shows its boxes, the e2e script's output
under its command (the screenshots wait for it)."
  (when-let* ((pane (+my/example-agent-workflow--pane))
              (box (ignore-errors (agent-ui-get "now-test" :canvas pane :section "run"))))
    (>= (length (plist-get box :lines)) 6)))

(defun +my/example-agent-workflow ()
  "Example: a run's pane as it runs, in the frame's two windows: its top,
its live boxes and Log beside it (the folder deleted once it's closed). See
examples/agent-workflow.el."
  (interactive)
  ;; The package's parts, loaded when first used otherwise.
  (require 'agent-workflow-parts)
  (+my/example-agent-workflow--stop)
  (when-let* ((old (+my/example-agent-workflow--pane)))
    (kill-buffer old))
  (let* ((dir (+my/example-folder "agent-workflow"))
         (project (file-name-as-directory (expand-file-name "compiler" dir)))
         (run-dir (file-name-as-directory (expand-file-name ".agent-shell/agent-workflow/runs/demo-1/1" project)))
         (now (float-time))
         (_ (make-directory run-dir t))
         (base (+my/example-agent-workflow--project project))
         (session (get-buffer-create "*Example: docs's agent*"))
         ;; Run in its worktree, as a run's script is.
         (process (let ((default-directory (agent-workflow-worktree-directory
                                            project +my/example-agent-workflow--issue)))
                    (make-process :name "example-e2e" :buffer (generate-new-buffer " *example e2e*")
                                  :command (list "sh" "-c" +my/example-agent-workflow--e2e)
                                  :noquery t :connection-type 'pipe))))
    (with-current-buffer session
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "A stand-in for the docs agent's agent-shell session: in a run, the agent works here.\n"))
      ;; What it runs on, as a session says it (its box's header).
      (setq-local agent-shell--state +my/example-agent-workflow--session-state))
    (+my/example-agent-workflow--write-journal run-dir now)
    (let* ((run (+my/example-agent-workflow--run run-dir project base now session process))
           (pane (agent-workflow--pane-make run)))
      (+my/example-alone)
      (switch-to-buffer pane)
      (goto-char (point-min))
      ;; Beside it, the same pane from its live boxes down (they, Notes and
      ;; the Log under its fold), as wide: a canvas is drawn at its first
      ;; window's width (a narrower one cut its lines). Split first, drawn
      ;; at the width it has then (drawn again after, its text moved under
      ;; the window's start).
      (let ((right (split-window-right)))
        (set-window-buffer right pane)
        (with-current-buffer pane (agent-ui--flush))
        (when-let* ((entry (gethash "run/now-test" (buffer-local-value 'agent-ui--entries pane)))
                    (start (with-current-buffer pane
                             (save-excursion (goto-char (agent-ui--entry-start entry))
                                             ;; Its start is at the line before's end.
                                             (skip-chars-forward "\n")
                                             (line-beginning-position)))))
          (set-window-start right start)
          (set-window-point right start)))
      (with-current-buffer pane
        (add-hook 'kill-buffer-hook
                  (lambda ()
                    (+my/example-agent-workflow--stop)
                    (when (process-live-p process) (delete-process process))
                    (when (buffer-live-p (process-buffer process)) (kill-buffer (process-buffer process)))
                    (when (buffer-live-p session) (kill-buffer session)))
                  nil t))
      (setq +my/example-agent-workflow--timer
            (run-at-time 1 1 #'+my/example-agent-workflow--tick run pane))
      (+my/example-delete-when-closed dir (list pane))
      (message "Run example: TAB folds a section, RET opens a commit or a file, q closes it")
      pane)))

(provide 'example-agent-workflow)
