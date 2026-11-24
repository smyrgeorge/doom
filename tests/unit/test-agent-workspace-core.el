;;; tests/unit/test-agent-workspace-core.el -*- lexical-binding: t; -*-
;; config/agent-workspace.el and its core (config/agent-workspace/core.el):
;; agents' names and colours, the crews, the states and their words, how
;; agent-shell's events move them; what a session is configured with
;; (session.el's config, environment, what the agent is told). No agent starts
;; here: test-agent-workspace-session.el runs real sessions.

(require 'agent-shell)

(+test-load "config/agent-shell" "config/agent-workspace")

;; What Claude is told of a project's issues: not this config's.
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

;; ====== HELPERS ======

(defun +test-awc--agent (&rest args)
  "An agent record (not in a crew, no session): ARGS its slots."
  (apply #'agent-workspace--make-agent
         (append args (list :name (or (plist-get args :name) "ada")
                            :role (or (plist-get args :role) "builder")
                            :colour "blue" :project "/tmp/project/"
                            :worktree "/tmp/project/.agent-shell/worktrees/ada/"
                            :branch "agent/ada"))))

(defun +test-awc--emit (agent event &optional data)
  "AGENT gets agent-shell's EVENT with DATA (an alist)."
  (agent-workspace--event agent (append (list (cons :event event))
                                        (when data (list (cons :data data))))))

(defmacro +test-awc--with-crew (project agents &rest body)
  "BODY with PROJECT's crew AGENTS (records), the crews put back after."
  (declare (indent 2))
  `(let ((agent-workspace--crews (make-hash-table :test #'equal)))
     (puthash (agent-workspace--root ,project) ,agents agent-workspace--crews)
     ,@body))

;; ====== LOADING ======

(ert-deftest agent-workspace/loads-its-parts ()
  (dolist (fn '(agent-workspace-create agent-workspace-send agent-workspace-close
                agent-workspace-worktree-ensure agent-workspace--start))
    (should (fboundp fn))))

(ert-deftest agent-workspace/wired-in ()
  "What an agent is told comes after what every session is; a question on
its canvas raises its hand; quitting Emacs closes the crews."
  (should (eq (car (last +my/agent-shell-context-functions)) #'agent-workspace-agent-context))
  (should (memq #'agent-workspace--question-waiting agent-ui-question-waiting-functions))
  (should (memq #'agent-workspace--quit-h kill-emacs-hook)))

;; ====== NAMES AND COLOURS ======

(ert-deftest agent-workspace/names ()
  "A name: a lowercase letter, then lowercase letters, digits or -, at most
20 (test-agent-workspace-new.el has more)."
  (dolist (name '("ada" "builder-3" "a" "abcdefghijabcdefghij"))
    (should (agent-workspace-name-valid-p name)))
  (dolist (name '("" "3ada" "-ada" "Ada" "x_y" "ada lovelace" "ada/b" "abcdefghijabcdefghijk" "ádá" nil "a.b"))
    (should-not (agent-workspace-name-valid-p name))))

(ert-deftest agent-workspace/a-name-taken ()
  "A name taken in the crew is refused, but the agent's own; one not valid
too."
  (let ((ada (+test-awc--agent :name "ada")))
    (+test-awc--with-crew "/tmp/project/" (list ada)
      (should (string-match-p "There.s an agent named ada already"
                              (cadr (should-error (agent-workspace--check-name "ada" "/tmp/project/")
                                                  :type 'user-error))))
      (should-error (agent-workspace--check-name "no good" "/tmp/project/") :type 'user-error)
      (should-error (agent-workspace--check-name "Ada" "/tmp/project/") :type 'user-error)
      (should-not (agent-workspace--check-name "grace" "/tmp/project/"))
      (should-not (agent-workspace--check-name "ada" "/tmp/project/" ada)))))

(ert-deftest agent-workspace/a-free-colour ()
  "The first colour no agent has; all taken, the one fewest have."
  (let ((agent-workspace-colours '("blue" "green" "red")))
    (+test-awc--with-crew "/tmp/project/" nil
      (should (equal (agent-workspace-free-colour "/tmp/project/") "blue")))
    (+test-awc--with-crew "/tmp/project/" (list (+test-awc--agent :colour "blue"))
      (should (equal (agent-workspace-free-colour "/tmp/project/") "green")))
    (+test-awc--with-crew "/tmp/project/"
        (list (+test-awc--agent) (+test-awc--agent) (+test-awc--agent))
      (setf (agent-workspace-agent-colour (nth 1 (agent-workspace-agents "/tmp/project/"))) "green")
      (setf (agent-workspace-agent-colour (nth 2 (agent-workspace-agents "/tmp/project/"))) "red")
      ;; One each: the first.
      (should (equal (agent-workspace-free-colour "/tmp/project/") "blue"))
      (setf (agent-workspace-agent-colour (nth 2 (agent-workspace-agents "/tmp/project/"))) "blue")
      (should (equal (agent-workspace-free-colour "/tmp/project/") "red")))))

(ert-deftest agent-workspace/colours-are-the-theme-s ()
  "An agent's colour is a face of the theme's (never a hex)."
  (should (eq (agent-workspace-agent-face (+test-awc--agent)) 'ansi-color-blue))
  (dolist (colour agent-workspace-colours)
    (should (facep (intern (concat "ansi-color-" colour)))))
  (should (equal (car (last agent-workspace-colours 3)) "red")))

(ert-deftest agent-workspace/create-checks-what-it-gets ()
  "A role and a valid, free name, a known colour, a git repository: else
nothing is made."
  (let ((default-directory temporary-file-directory))
    (cl-letf (((symbol-function 'agent-workspace-project) (lambda (&rest _) nil)))
      (should-error (agent-workspace-create :role "builder" :name "ada") :type 'user-error)))
  (+test-awc--with-crew "/tmp/project/" nil
    (cl-letf (((symbol-function 'agent-workspace-worktree-ensure) (lambda (&rest _) (error "Made one")))
              ((symbol-function 'agent-workspace--start) (lambda (&rest _) (error "Started one"))))
      (should-error (agent-workspace-create :project "/tmp/project/" :name "ada") :type 'user-error)
      (should-error (agent-workspace-create :project "/tmp/project/" :role "builder") :type 'user-error)
      (should-error (agent-workspace-create :project "/tmp/project/" :role "builder" :name "a b")
                    :type 'user-error)
      (should-error (agent-workspace-create :project "/tmp/project/" :role "builder" :name "ada"
                                            :colour "#ff0000")
                    :type 'user-error)
      (should-not (agent-workspace-agents "/tmp/project/")))))

(ert-deftest agent-workspace/create-makes-it-in-order ()
  "Made: its worktree, then in the crew (said), then its session started,
then its first message."
  (let ((calls nil)
        (temporary-file-directory (file-truename temporary-file-directory)))
    (+test-awc--with-crew "/tmp/elsewhere/" nil
      (cl-letf (((symbol-function 'agent-workspace-worktree-ensure)
                 (lambda (agent) (push (list 'worktree (agent-workspace-agent-name agent)) calls)))
                ((symbol-function 'agent-workspace--start)
                 (lambda (agent) (push (list 'start (agent-workspace-agent-colour agent)) calls)))
                ((symbol-function 'agent-workspace-send)
                 (lambda (_agent text &rest args) (push (list 'send text args) calls))))
        (let* ((agent-workspace-change-functions
                (list (lambda (agent what) (push (list what (agent-workspace-agent-name agent)) calls))))
               (agent (agent-workspace-create :project temporary-file-directory
                                              :role "builder" :name "ada" :prompt "hi")))
          (should (equal (reverse calls)
                         '((worktree "ada") (created "ada") (start "blue") (send "hi" (:submit t)))))
          (should (equal (agent-workspace-agents temporary-file-directory) (list agent)))
          (should (eq (agent-workspace-agent "ada" temporary-file-directory) agent))
          (should (equal (agent-workspace-agent-project agent)
                         (file-name-as-directory temporary-file-directory))))))))

;; ====== THE STATES ======

(ert-deftest agent-workspace/state-words ()
  "Each state in words: working says its role's verb and issue; a raised
hand what it wants."
  (let ((agent (+test-awc--agent :role "tester"))
        (agent-workspace-role-function #'agent-workspace--bare-role))
    (dolist (case '((waking . "waking up") (desk . "at the desk") (working . "working")
                    (done . "done, have a look") (stuck . "stuck") (asleep . "asleep")
                    (home . "gone home") (hand . "asks you something")))
      (setf (agent-workspace-agent-state agent) (car case))
      (should (equal (agent-workspace-state-text agent) (cdr case))))
    (setf (agent-workspace-agent-issue agent) "doom-a1b")
    (setf (agent-workspace-agent-state agent) 'working)
    (should (equal (agent-workspace-state-text agent) "working doom-a1b"))
    (let ((agent-workspace-role-function (lambda (_project name) (list :name name :verb "building"))))
      (should (equal (agent-workspace-state-text agent) "building doom-a1b")))
    (setf (agent-workspace-agent-state agent) 'stuck)
    (should (equal (agent-workspace-state-text agent) "stuck on doom-a1b"))
    (setf (agent-workspace-agent-state agent) 'hand)
    (dolist (case '(((:kind permission :title "npm install" :tool-kind "execute") . "wants to run npm install")
                    ((:kind permission :title "src/a.el" :tool-kind "edit") . "wants to edit src/a.el")
                    ((:kind permission :title "a thing") . "wants to use a thing")
                    ((:kind permission) . "wants your permission")
                    ((:kind question :title "restore or rebuild?") . "asks: restore or rebuild?")))
      (setf (agent-workspace-agent-ask agent) (car case))
      (should (equal (agent-workspace-state-text agent) (cdr case))))))

(ert-deftest agent-workspace/events-move-its-state ()
  "agent-shell's events, in a session's life: its states, and the hooks
told each change once."
  (let* ((agent (+test-awc--agent :state 'waking))
         (changes nil)
         (agent-workspace-state-change-functions
          (list (lambda (a old new) (should (eq a agent)) (push (cons old new) changes)))))
    (+test-awc--emit agent 'init-client)
    (+test-awc--emit agent 'init-session)
    (should (eq (agent-workspace-agent-state agent) 'waking))
    (+test-awc--emit agent 'init-finished)
    (should (eq (agent-workspace-agent-state agent) 'desk))
    (+test-awc--emit agent 'input-submitted '((:prompt . "hi")))
    (should (eq (agent-workspace-agent-state agent) 'working))
    (let ((since (agent-workspace-agent-since agent)))
      (should since)
      ;; More of its turn: the same.
      (+test-awc--emit agent 'tool-call-update)
      (+test-awc--emit agent 'agent-message-chunk)
      (should (eq (agent-workspace-agent-state agent) 'working))
      (+test-awc--emit agent 'permission-request
                       `((:request-id . 7) (:tool-call . ((:title . "npm install") (:kind . "execute")))))
      (should (eq (agent-workspace-agent-state agent) 'hand))
      (let ((ask (agent-workspace-agent-ask agent)))
        ;; A key of its own (doom-pbk.44), then what it asks.
        (should (stringp (plist-get ask :key)))
        (should (equal (butlast ask 2)
                       '(:kind permission :title "npm install" :tool-kind "execute" :request-id 7))))
      (+test-awc--emit agent 'permission-response)
      (should (eq (agent-workspace-agent-state agent) 'working))
      (should-not (agent-workspace-agent-ask agent))
      ;; Its time counts from its turn's start.
      (should (equal (agent-workspace-agent-since agent) since))
      (+test-awc--emit agent 'elicitation-request '((:message . "restore or rebuild?")))
      (should (equal (agent-workspace-state-text agent) "asks: restore or rebuild?"))
      (should (equal (agent-workspace-agent-since agent) since))
      (+test-awc--emit agent 'tool-call-update)
      (should (eq (agent-workspace-agent-state agent) 'working)))
    (+test-awc--emit agent 'turn-complete '((:stop-reason . "end_turn")))
    (should (eq (agent-workspace-agent-state agent) 'done))
    (should-not (agent-workspace-agent-since agent))
    ;; Updates after its turn's end leave it done.
    (+test-awc--emit agent 'tool-call-update)
    (should (eq (agent-workspace-agent-state agent) 'done))
    (agent-workspace-seen agent)
    (should (eq (agent-workspace-agent-state agent) 'desk))
    ;; Interrupted: at the desk, not done.
    (+test-awc--emit agent 'input-submitted)
    (+test-awc--emit agent 'turn-complete '((:stop-reason . "cancelled")))
    (should (eq (agent-workspace-agent-state agent) 'desk))
    ;; An error: stuck, saying it; a message: working again, the error gone.
    (+test-awc--emit agent 'error '((:code . -32603) (:message . "it broke")))
    (should (eq (agent-workspace-agent-state agent) 'stuck))
    (should (equal (agent-workspace-agent-error agent) "it broke"))
    (+test-awc--emit agent 'input-submitted)
    (should-not (agent-workspace-agent-error agent))
    ;; Its session cleaned up, not by us: gone home.
    (+test-awc--emit agent 'clean-up)
    (should (eq (agent-workspace-agent-state agent) 'home))
    (should (equal (reverse changes)
                   '((waking . desk) (desk . working) (working . hand) (hand . working)
                     (working . hand) (hand . working) (working . done) (done . desk)
                     (desk . working) (working . desk) (desk . stuck) (stuck . working)
                     (working . home))))))

(defun +test-awc--tool (agent id status &optional meta)
  "AGENT's tool call ID updated, STATUS (ACP's: \"in_progress\"...), with
META (its _meta)."
  (+test-awc--emit agent 'tool-call-update
                   (append `((:tool-call-id . ,id) (:tool-call . ((:status . ,status))))
                           (when meta (list (cons :meta meta))))))

(defun +test-awc--long-after (agent)
  "AGENT's last turn ended long ago: its updates aren't late ones."
  (puthash agent (- (float-time) 60) agent-workspace--turn-ends))

(ert-deftest agent-workspace/a-turn-it-starts-by-itself ()
  "Woken by a background task (updates, no input-submitted, no
turn-complete): working from its first update, timed from then, a tool
running holding its turn however quiet; done once its session is quiet.
Its model's result (a usage update naming its origin) ends one at once."
  (let* ((agent (+test-awc--agent :state 'desk))
         (changes nil)
         (agent-workspace-quiet-turn 0.2)
         (agent-workspace-state-change-functions
          (list (lambda (_agent old new) (push (cons old new) changes)))))
    (unwind-protect
        (progn
          (+test-awc--emit agent 'agent-message-chunk '((:text-chunk . "The suite runs.")))
          (should (eq (agent-workspace-agent-state agent) 'working))
          (should (agent-workspace-agent-since agent))
          ;; A command running: its turn goes on, quiet as it is.
          (+test-awc--tool agent "t1" "in_progress")
          (should-not (+test-wait-for (lambda () (not (eq (agent-workspace-agent-state agent) 'working))) 0.6))
          (+test-awc--tool agent "t1" "completed")
          ;; Then quiet: done.
          (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state agent) 'done)) 5))
          (should-not (agent-workspace-agent-since agent))
          (should-not (gethash agent agent-workspace--self-turns))
          (should (equal (reverse changes) '((desk . working) (working . done))))
          ;; Its model's result: over at once, a tool still said running.
          (+test-awc--long-after agent)
          (let ((agent-workspace-quiet-turn 60))
            (+test-awc--tool agent "t2" "pending")
            (should (eq (agent-workspace-agent-state agent) 'working))
            ;; Its context's size only: not a result.
            (+test-awc--emit agent 'usage-update '((:usage . ((:context-used . 1000)))))
            (should (eq (agent-workspace-agent-state agent) 'working))
            (+test-awc--emit agent 'usage-update
                             '((:usage . ((:context-used . 1200)))
                               (:meta . ((_claude/origin . ((kind . "task-notification")))))))
            (should (eq (agent-workspace-agent-state agent) 'done))
            (should-not (gethash agent agent-workspace--self-turns))))
      (agent-workspace--self-turn-stop agent))))

(ert-deftest agent-workspace/a-hand-raised-in-a-turn-it-started ()
  "Its hand raised in a turn it started by itself, then answered: working
again, its time from its turn's start, then done once its turn is over, no
prompt of yours. Its hand raised as it rests, nothing before: a turn of its
own too."
  (let ((agent (+test-awc--agent :state 'nap))
        (agent-workspace-quiet-turn 0.2))
    (unwind-protect
        (progn
          (+test-awc--tool agent "q1" "pending")
          (should (eq (agent-workspace-agent-state agent) 'working))
          (let ((since (agent-workspace-agent-since agent)))
            (+test-awc--emit agent 'permission-request
                             '((:request-id . 3) (:tool-call . ((:title . "Which branch?")))))
            (should (eq (agent-workspace-agent-state agent) 'hand))
            ;; Raised, it stays raised, quiet or not.
            (should-not (+test-wait-for (lambda () (not (eq (agent-workspace-agent-state agent) 'hand))) 0.6))
            (+test-awc--emit agent 'permission-response)
            (should (eq (agent-workspace-agent-state agent) 'working))
            (should (equal (agent-workspace-agent-since agent) since)))
          (+test-awc--tool agent "q1" "completed")
          (+test-awc--emit agent 'agent-message-chunk '((:text-chunk . "Merging main.")))
          (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state agent) 'done)) 5))
          ;; Asked first thing.
          (+test-awc--long-after agent)
          (+test-awc--emit agent 'permission-request
                           '((:request-id . 4) (:tool-call . ((:title . "rm -rf build")))))
          (should (eq (agent-workspace-agent-state agent) 'hand))
          (should (agent-workspace-agent-since agent))
          (+test-awc--emit agent 'permission-response)
          (should (eq (agent-workspace-agent-state agent) 'working))
          (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state agent) 'done)) 5)))
      (agent-workspace--self-turn-stop agent))))

(ert-deftest agent-workspace/a-question-on-its-canvas-through-a-turn-it-started ()
  "Its hand raised for a question on its canvas (asked at its turn's end),
then woken by a background task: its updates don't lower it (its answer
is a prompt), the turn tracked all the same, over when quiet or at its
model's result, the hand still raised; not free meanwhile (its loop, the
inbox)."
  (+test-with-reset
    (let* ((buffer (get-buffer-create "ada · builder"))
           (agent (+test-awc--agent :state 'desk :loop t :buffer buffer))
           (agent-workspace-state-change-functions nil)
           (agent-workspace-quiet-turn 0.2)
           (ask '(:kind question :canvas nil :id "q1" :title "Merge it?")))
      (unwind-protect
          (progn
            (agent-workspace--raise-hand agent ask)
            (should (eq (agent-workspace-agent-state agent) 'hand))
            (+test-awc--long-after agent)
            (+test-awc--emit agent 'agent-message-chunk '((:text-chunk . "The suite passed.")))
            (should (eq (agent-workspace-agent-state agent) 'hand))
            (should (equal (plist-get (agent-workspace-agent-ask agent) :id) "q1"))
            (should (equal (plist-get (gethash agent agent-workspace--self-turns) :ask)
                           (agent-workspace-agent-ask agent)))
            (should-not (agent-workspace--loop-at-rest-p agent))
            (should-not (agent-workspace--inbox-free-p agent))
            ;; A tool running holds it; then quiet: over, the hand kept.
            (+test-awc--tool agent "t1" "in_progress")
            (should-not (+test-wait-for (lambda () (not (gethash agent agent-workspace--self-turns))) 0.6))
            (+test-awc--tool agent "t1" "completed")
            (should (+test-wait-for (lambda () (not (gethash agent agent-workspace--self-turns))) 5))
            (should (eq (agent-workspace-agent-state agent) 'hand))
            (should (equal (plist-get (agent-workspace-agent-ask agent) :id) "q1"))
            ;; Its model's result: over at once, the hand kept.
            (+test-awc--long-after agent)
            (let ((agent-workspace-quiet-turn 60))
              (+test-awc--tool agent "t2" "pending")
              (should (gethash agent agent-workspace--self-turns))
              (+test-awc--emit agent 'usage-update '((:meta . ((_claude/origin . ((kind . "task-notification")))))))
              (should-not (gethash agent agent-workspace--self-turns))
              (should (eq (agent-workspace-agent-state agent) 'hand)))
            ;; Its answer, a prompt: to work.
            (+test-awc--emit agent 'input-submitted '((:prompt . "Answer to choice q1 (Merge it?): Yes")))
            (should (eq (agent-workspace-agent-state agent) 'working)))
        (agent-workspace--self-turn-stop agent)
        (kill-buffer buffer)))))

(ert-deftest agent-workspace/its-canvas-question-asked-again-after-a-permission ()
  "Its hand raised for a question on its canvas, a turn it started by
itself asking a permission (that hand in its place), answered: working;
over, the question asked again if it still waits (a new hand), else done."
  (+test-with-reset
    (let* ((buffer (get-buffer-create "ada · builder"))
           (canvas (get-buffer-create "Agent UI: ada"))
           (agent (+test-awc--agent :state 'desk :buffer buffer))
           (agent-workspace-state-change-functions nil)
           (agent-workspace-quiet-turn 0.2)
           (waiting (list (cons canvas "q1"))))
      (cl-letf (((symbol-function 'agent-ui--waiting)
                 (lambda (session &rest _) (and (eq session buffer) waiting))))
        (unwind-protect
            (dolist (still '(t nil))
              (setq waiting (and still (list (cons canvas "q1"))))
              (agent-workspace--set-state agent 'desk)
              (agent-workspace--raise-hand agent (list :kind 'question :canvas canvas :id "q1" :title "Merge it?"))
              (let ((key (plist-get (agent-workspace-agent-ask agent) :key)))
                (+test-awc--long-after agent)
                (+test-awc--tool agent "t1" "in_progress")
                (+test-awc--emit agent 'permission-request
                                 '((:request-id . 3) (:tool-call . ((:title . "git push")))))
                (should (eq (plist-get (agent-workspace-agent-ask agent) :kind) 'permission))
                (+test-awc--emit agent 'permission-response)
                (should (eq (agent-workspace-agent-state agent) 'working))
                (+test-awc--tool agent "t1" "completed")
                (should (+test-wait-for (lambda () (not (gethash agent agent-workspace--self-turns))) 5))
                (if still
                    (progn
                      (should (eq (agent-workspace-agent-state agent) 'hand))
                      (should (equal (plist-get (agent-workspace-agent-ask agent) :id) "q1"))
                      (should (eq (plist-get (agent-workspace-agent-ask agent) :canvas) canvas))
                      (should-not (equal (plist-get (agent-workspace-agent-ask agent) :key) key))
                      (should (= (cl-count :key (agent-workspace-agent-ask agent)) 1)))
                  (should (eq (agent-workspace-agent-state agent) 'done)))))
          (agent-workspace--self-turn-stop agent)
          (kill-buffer buffer)
          (kill-buffer canvas))))))

(ert-deftest agent-workspace/updates-that-start-no-turn ()
  "No turn of its own from its turn's late updates (just after its
turn-complete), a subagent's, a background command's end, a stale answer.
Your prompt into a turn it started makes it the prompt's: over at its
turn-complete, not when quiet nor at a result."
  (let ((agent (+test-awc--agent :state 'desk))
        (agent-workspace-quiet-turn 0.2))
    (unwind-protect
        (progn
          (+test-awc--emit agent 'input-submitted '((:prompt . "hi")))
          (+test-awc--emit agent 'turn-complete '((:stop-reason . "end_turn")))
          (should (eq (agent-workspace-agent-state agent) 'done))
          (+test-awc--tool agent "t1" "completed")
          (+test-awc--emit agent 'agent-message-chunk '((:text-chunk . "…")))
          (should (eq (agent-workspace-agent-state agent) 'done))
          (+test-awc--long-after agent)
          (+test-awc--emit agent 'agent-message-chunk
                           '((:text-chunk . "found it") (:meta . ((claudeCode . ((parentToolUseId . "toolu_1")))))))
          (+test-awc--tool agent "b1" "completed"
                           '((terminal_exit . ((terminal_id . "b1") (exit_code) (signal)))))
          (+test-awc--emit agent 'permission-response)
          (should (eq (agent-workspace-agent-state agent) 'done))
          (should-not (gethash agent agent-workspace--self-turns))
          ;; A turn it starts, your prompt into it.
          (+test-awc--emit agent 'agent-message-chunk '((:text-chunk . "The suite passed.")))
          (should (eq (agent-workspace-agent-state agent) 'working))
          (let ((since (agent-workspace-agent-since agent)))
            (+test-awc--emit agent 'input-submitted '((:prompt . "then merge it")))
            (should-not (gethash agent agent-workspace--self-turns))
            (should (equal (agent-workspace-agent-since agent) since)))
          (should-not (+test-wait-for (lambda () (not (eq (agent-workspace-agent-state agent) 'working))) 0.6))
          (+test-awc--emit agent 'usage-update '((:meta . ((_claude/origin . ((kind . "task-notification")))))))
          (should (eq (agent-workspace-agent-state agent) 'working))
          (+test-awc--emit agent 'turn-complete '((:stop-reason . "end_turn")))
          (should (eq (agent-workspace-agent-state agent) 'done)))
      (agent-workspace--self-turn-stop agent))))

(ert-deftest agent-workspace/no-issue-nor-event-in-a-turn-it-started ()
  "In a turn it started by itself, an agent isn't free: its loop gives it no
issue, the inbox no event. Over, it's free again."
  (+test-with-reset
    (let* ((buffer (get-buffer-create "ada · builder"))
           (agent (+test-awc--agent :state 'nap :loop t :buffer buffer))
           (agent-workspace-state-change-functions nil)
           (agent-workspace-quiet-turn 60))
      (unwind-protect
          (progn
            (should (agent-workspace--loop-at-rest-p agent))
            (should (agent-workspace--inbox-free-p agent))
            (+test-awc--emit agent 'agent-message-chunk '((:text-chunk . "Still running.")))
            (should (eq (agent-workspace-agent-state agent) 'working))
            (should-not (agent-workspace--loop-at-rest-p agent))
            (should-not (agent-workspace--inbox-free-p agent))
            (+test-awc--emit agent 'usage-update '((:meta . ((_claude/origin . ((kind . "task-notification")))))))
            (should (eq (agent-workspace-agent-state agent) 'done))
            (should (agent-workspace--loop-at-rest-p agent))
            (should (agent-workspace--inbox-free-p agent)))
        (agent-workspace--self-turn-stop agent)
        (kill-buffer buffer)))))

(ert-deftest agent-workspace/stopped-on-purpose-isn-t-gone-home ()
  "Its session cleaned up while we stop it (sleep, restart): not gone home."
  (let ((agent (+test-awc--agent :state 'desk :stopping t)))
    (+test-awc--emit agent 'clean-up)
    (should (eq (agent-workspace-agent-state agent) 'desk))))

(ert-deftest agent-workspace/a-change-said ()
  "Each change said to `agent-workspace-change-functions': its state, its
colour, its issue."
  (let* ((agent (+test-awc--agent :state 'desk))
         (whats nil)
         (agent-workspace-change-functions (list (lambda (_agent what) (push what whats)))))
    (+test-awc--emit agent 'input-submitted)
    (agent-workspace-recolour agent "green")
    (should (equal (agent-workspace-agent-colour agent) "green"))
    (should-error (agent-workspace-recolour agent "#00ff00") :type 'user-error)
    (agent-workspace-give agent "doom-a1b" "Its title")
    (should (equal (agent-workspace-agent-issue-title agent) "Its title"))
    (should (equal (reverse whats) '(state colour issue)))))

(ert-deftest agent-workspace/done-or-looked-at ()
  "Its turn over while its session is shown: at the desk at once."
  (+test-with-reset
    (let* ((buffer (get-buffer-create "ada · builder"))
           (agent (+test-awc--agent :state 'working :buffer buffer)))
      (switch-to-buffer buffer)
      (+test-awc--emit agent 'turn-complete '((:stop-reason . "end_turn")))
      (should (eq (agent-workspace-agent-state agent) 'desk))
      ;; Shown again later (its pane opened): looked at.
      (setf (agent-workspace-agent-state agent) 'done)
      (with-current-buffer buffer (setq agent-workspace--agent agent))
      (agent-workspace--shown-h (selected-window))
      (should (eq (agent-workspace-agent-state agent) 'desk)))))

(ert-deftest agent-workspace/a-buffer-s-agent-stays ()
  "A buffer's agent stays when its major mode is run again."
  (with-temp-buffer
    (setq agent-workspace--agent 'ada)
    (fundamental-mode)
    (should (eq (agent-workspace-buffer-agent) 'ada))))

;; ====== ITS SESSION'S CONFIG ======

(ert-deftest agent-workspace/what-the-agent-is-told ()
  "Who it is and how it works (a branch made for each piece of its work, an
issue's renamed once by it, never one of its own), then its role's
instructions, after what every
session is told; nothing for a session not an agent's."
  (let ((agent (+test-awc--agent))
        (agent-workspace-role-function
         (lambda (_project name) (list :name name :instructions "  Build what you're given.\n"))))
    (should-not (agent-workspace-agent-context))
    (let* ((agent-workspace--starting agent)
           (text (agent-workspace-agent-context)))
      (dolist (part '("You are ada, the builder" "crew of coding agents" "on project"
                      "You work for the user" "Don't hand work to other agents"
                      "your own git worktree, /tmp/project/.agent-shell/worktrees/ada:"
                      "never in the project's main checkout (/tmp/project)"
                      "Each piece of work gets a branch of its own there, made and named for you as it starts"
                      "an issue's after its type, id and title: fix/doom-a1b-lexer-escapes"
                      "never switch, make or rename branches yourself"
                      "bd commands run as ada" "Your notifications carry your name already"))
        (should (string-search part text)))
      (should-not (string-search "agent/ada" text))
      (should-not (string-search "You run the crew" text))
      (should (string-suffix-p "\n\nBuild what you're given." text)))))

(ert-deftest agent-workspace/a-role-s-placeholders-filled-in ()
  "Its role's tools, deny and instructions with {main}, {main-branch},
{name} and {project} filled in, shell-quoted, as its session starts (in
Claude Code's options and what it's told); any other {word} left; the
role itself untouched; the main branch asked once."
  (let* ((role (list :name "reviewer"
                     :tools '("Read" "Bash(git -C {main} merge --no-ff *)"
                              "Bash(git -C /tmp/merge-{project}-{name} merge --no-ff *)" "Bash(ls {other}:*)")
                     :deny '("Bash(git -C * push)" "Bash(git -C {main} reset:*)")
                     :instructions "git -C {main} merge --no-ff BRANCH, into {main-branch} ({main-branch}); {NAME}."))
         (agent-workspace-role-function (lambda (_project _name) role))
         (asked 0))
    (cl-letf (((symbol-function 'agent-workspace-main-branch)
               (lambda (project)
                 (cl-incf asked)
                 (should (string-prefix-p "/tmp/" project))
                 ;; A lookup changing the match data: the value still
                 ;; where its placeholder was.
                 (string-match "o\\(o\\)" "xoo")
                 "main")))
      (let ((filled (agent-workspace-role-filled (+test-awc--agent :name "ken" :role "reviewer"))))
        (should (equal (plist-get filled :tools)
                       '("Read" "Bash(git -C /tmp/project merge --no-ff *)"
                         "Bash(git -C /tmp/merge-project-ken merge --no-ff *)" "Bash(ls {other}:*)")))
        (should (equal (plist-get filled :deny) '("Bash(git -C * push)" "Bash(git -C /tmp/project reset:*)")))
        (should (equal (plist-get filled :instructions)
                       "git -C /tmp/project merge --no-ff BRANCH, into main (main); {NAME}."))
        (should (= asked 1))
        (setq asked 0)
        ;; The role as it was.
        (should (equal (plist-get role :tools)
                       '("Read" "Bash(git -C {main} merge --no-ff *)"
                         "Bash(git -C /tmp/merge-{project}-{name} merge --no-ff *)" "Bash(ls {other}:*)"))))
      ;; Reaching Claude Code's options and what it's told.
      (let* ((agent (+test-awc--agent :name "ken" :role "reviewer" :project "/tmp/my project/"))
             (config (let ((agent-workspace--starting agent)) (agent-workspace--config agent)))
             (meta (alist-get :session-meta config))
             (options (alist-get 'options (alist-get 'claudeCode meta))))
        ;; A path with a space: quoted, as the command the agent runs has it.
        (should (equal (alist-get 'allowedTools options)
                       ["Read" "Bash(git -C /tmp/my\\ project merge --no-ff *)"
                        "Bash(git -C /tmp/merge-my\\ project-ken merge --no-ff *)" "Bash(ls {other}:*)"]))
        (should (equal (alist-get 'disallowedTools options)
                       ["Bash(git -C * push)" "Bash(git -C /tmp/my\\ project reset:*)"]))
        (should (string-suffix-p "git -C /tmp/my\\ project merge --no-ff BRANCH, into main (main); {NAME}."
                                 (let ((agent-workspace--starting agent)) (+my/agent-shell-context-text))))))))

(ert-deftest agent-workspace/what-a-lead-is-told ()
  "An agent whose role leads is told it runs the crew for the user, on their
word, from its shell, never starting work by itself; not that it doesn't
hand work to other agents."
  (let* ((agent (+test-awc--agent :name "max" :role "lead"))
         (agent-workspace-role-function
          (lambda (_project name) (list :name name :leads t :instructions "Run the crew.")))
         (text (let ((agent-workspace--starting agent)) (agent-workspace-agent-context))))
    (dolist (part '("You are max, the lead" "You run the crew for the user, on their word"
                    "cmd/agent-workspace status" "only when they ask you to"
                    "Never start work by yourself." "your own git worktree"))
      (should (string-search part text)))
    (should-not (string-search "Don't hand work to other agents" text))
    (should (string-suffix-p "\n\nRun the crew." text))))

(ert-deftest agent-workspace/a-session-s-config ()
  "Claude Code's config for an agent: its buffer's name, its role's model and
mode, tools and MCP servers, its environment added to its client's, what
it's told as it starts; the maker's own config untouched."
  (let* ((agent (+test-awc--agent))
         (agent-shell-mcp-servers '(((name . "agent-ui"))))
         (agent-workspace-role-function
          (lambda (_project name)
            (list :name name :model "opus" :mode "acceptEdits" :tools '("Read" "Bash(git:*)")
                  :deny '("WebFetch") :mcp-servers '(((name . "role-server")))
                  :instructions "Build it."))))
    (cl-letf (((symbol-function 'file-directory-p)
               (lambda (dir) (equal dir "/tmp/project/.beads"))))
      (let* ((config (let ((agent-workspace--starting agent)) (agent-workspace--config agent)))
             (meta (alist-get :session-meta config))
             (options (alist-get 'options (alist-get 'claudeCode meta))))
        (should (equal (alist-get :buffer-name config) "ada · builder"))
        (should (equal (funcall (alist-get :default-model-id config)) "opus"))
        (should (equal (funcall (alist-get :default-session-mode-id config)) "acceptEdits"))
        ;; Its own mode over its role's; neither: auto (agent-workspace-mode).
        (setf (agent-workspace-agent-mode agent) "plan")
        (should (equal (funcall (alist-get :default-session-mode-id (agent-workspace--config agent))) "plan"))
        (setf (agent-workspace-agent-mode agent) nil)
        (should (equal (default-value 'agent-workspace-mode) "auto"))
        (let ((agent-workspace-role-function (lambda (_project name) (list :name name))))
          (should (equal (funcall (alist-get :default-session-mode-id (agent-workspace--config agent))) "auto"))
          (should (equal (agent-workspace-mode-of agent) "auto")))
        (should (equal (alist-get :mcp-servers config) '(((name . "agent-ui")) ((name . "role-server")))))
        (should (equal (alist-get 'allowedTools options) ["Read" "Bash(git:*)"]))
        (should (equal (alist-get 'disallowedTools options) ["WebFetch"]))
        ;; agent-shell's own options kept.
        (should (alist-get 'thinking options))
        ;; What it's told, worked out as it starts (it bound).
        (let ((prompt (let ((agent-workspace--starting agent)) (+my/agent-shell-context-text))))
          (should (string-prefix-p +my/agent-shell-context prompt))
          (should (string-search "You are ada, the builder" prompt))
          (should (string-suffix-p "Build it." prompt)))
        (with-temp-buffer
          (let ((client (funcall (alist-get :client-maker config) (current-buffer))))
            (should (equal (seq-take (alist-get :environment-variables client) 3)
                           '("BEADS_ACTOR=ada" "AGENT_WORKSPACE_AGENT=ada"
                             "BEADS_DIR=/tmp/project/.beads")))
            ;; The kind's own (the login's) kept.
            (should (member "ANTHROPIC_API_KEY=" (alist-get :environment-variables client)))))))
    ;; The maker's config as it was; another agent's own.
    (let ((plain (agent-shell-anthropic-make-claude-code-config)))
      (should-not (alist-get 'allowedTools (alist-get 'options (alist-get 'claudeCode (alist-get :session-meta plain))))))
    (let* ((agent-workspace-role-function #'agent-workspace--bare-role)
           (config (agent-workspace--config (+test-awc--agent :name "grace" :model "sonnet"))))
      (should (equal (alist-get :buffer-name config) "grace · builder"))
      (should (equal (funcall (alist-get :default-model-id config)) "sonnet"))
      (should-not (alist-get :mcp-servers config)))))

(ert-deftest agent-workspace/an-unknown-kind ()
  (should-error (agent-workspace--config (+test-awc--agent :kind 'nope))))

;; ====== CLOSING ======

(ert-deftest agent-workspace/close-a-crew ()
  "Closing a crew: each agent stopped (gone home), said, the crew gone;
another project's crew stays."
  (let* ((ada (+test-awc--agent :state 'working))
         (grace (+test-awc--agent :name "grace" :state 'hand))
         (other (+test-awc--agent :name "linus" :project "/tmp/other/"))
         (stopped nil)
         (whats nil)
         (agent-workspace-change-functions (list (lambda (agent what) (push (cons (agent-workspace-agent-name agent) what) whats)))))
    (let ((agent-workspace--crews (make-hash-table :test #'equal)))
      (puthash "/tmp/project/" (list ada grace) agent-workspace--crews)
      (puthash "/tmp/other/" (list other) agent-workspace--crews)
      (cl-letf (((symbol-function 'agent-workspace--root) #'identity)
                ((symbol-function 'agent-workspace--stop)
                 (lambda (agent state &optional _table)
                   (push (agent-workspace-agent-name agent) stopped)
                   (setf (agent-workspace-agent-state agent) state)
                   (list (cons 1 (agent-workspace-agent-name agent))))))
        (should (equal (agent-workspace-close "/tmp/project/") '((1 . "ada") (1 . "grace"))))
        (should (equal (reverse stopped) '("ada" "grace")))
        (should (eq (agent-workspace-agent-state grace) 'home))
        (should (member '("grace" . closed) whats))
        (should (equal (agent-workspace-crews) '("/tmp/other/")))
        (should-not (agent-workspace-close "/tmp/project/"))
        (agent-workspace-close-all)
        (should-not (agent-workspace-crews))))))
