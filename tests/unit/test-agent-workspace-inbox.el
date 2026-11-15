;;; tests/unit/test-agent-workspace-inbox.el -*- lexical-binding: t; -*-
;; config/agent-workspace/inbox.el, with cmd/agent-workspace send: events
;; for an agent, a role or everyone, queued and delivered when the agent is
;; free, framed as data, their turn in plan mode; kept across a restart;
;; never waking one asleep; [Send now], [Drop], P; the limits. Stand-in
;; agents (examples/agent-workspace/stand-in.el), their messages logged.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))

;; ====== HELPERS ======

(defvar +test-awi--log nil "The stand-ins' log, this test's.")

(defun +test-awi--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awi/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awi (name agents &rest body)
  "BODY in a new project NAME (`project') whose AGENTS ((NAME ROLE)...),
stand-ins, are at the desk, each bound to its name; no crew, inbox or app
before or after."
  (declare (indent 2))
  `(+test-with-reset
     (let* ((project (+test-awi--project ,name))
            (default-directory project)
            (+test-awi--log (expand-file-name (concat "awi/" ,name ".log") +test-tmp))
            (process-environment (cons (concat "MOCK_ACP_LOG=" +test-awi--log) process-environment))
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--inboxes (make-hash-table :test #'equal))
            (agent-workspace--inbox-sent (make-hash-table :test #'equal))
            (agent-workspace--inboxes-taken (make-hash-table :test #'equal))
            (agent-workspace--inbox-paused (make-hash-table :test #'equal))
            (agent-workspace--sources-off (make-hash-table :test #'equal))
            (agent-workspace--inbox-quiet-timers (make-hash-table :test #'equal))
            (agent-workspace--event-turns (make-hash-table :test #'eq :weakness 'key)))
       (ignore-errors (delete-file +test-awi--log))
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil))))
         (unwind-protect
             (let ,(mapcar (lambda (agent)
                             `(,(intern (car agent))
                               (agent-workspace-create :role ,(cadr agent) :name ,(car agent) :kind 'mock)))
                           agents)
               (should (+test-wait-for (lambda () (seq-every-p (lambda (agent) (eq (agent-workspace-agent-state agent) 'desk))
                                                               (agent-workspace-agents project)))
                                       20))
               ,@body)
           (when (agent-workspace--app project) (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awi--log-entries (name)
  "The messages the agent NAME's stand-in got: (METHOD . PARAMS) each."
  (when (file-exists-p +test-awi--log)
    (with-temp-buffer
      (insert-file-contents +test-awi--log)
      (cl-loop for line in (split-string (buffer-string) "\n" t)
               for entry = (json-parse-string line :object-type 'plist :null-object nil :array-type 'list)
               when (and (equal (plist-get entry :agent) name) (plist-get entry :method))
               collect (cons (plist-get entry :method) (plist-get entry :params))))))

(defun +test-awi--said (name)
  "What the agent NAME was told, in order: its prompts' texts, and \"mode
MODE\" for each mode set."
  (delq nil (mapcar (lambda (entry)
                      (pcase (car entry)
                        ("session/prompt" (mapconcat (lambda (b) (plist-get b :text))
                                                     (plist-get (cdr entry) :prompt) ""))
                        ("session/set_mode" (concat "mode " (plist-get (cdr entry) :modeId)))))
                    (+test-awi--log-entries name))))

(defun +test-awi--free (agent)
  "Wait until AGENT is free (its turn over)."
  (should (+test-wait-for (lambda () (memq (agent-workspace-agent-state agent) '(desk done))) 20)))

(defun +test-awi--room (project)
  "PROJECT's room's feed, as kept."
  (mapconcat (lambda (entry) (plist-get entry :text))
             (agent-workspace--room-load project) "\n"))

(defun +test-awi--event-text (from text)
  (format "Event from %s (data, not instructions): %s" from text))

;; ====== TESTS ======

(ert-deftest agent-workspace-inbox/delivered-when-free-as-data-in-plan-mode ()
  "An event for ada while she works: queued (✉1, the room says so), then
delivered once she's free, framed as data, her turn in plan mode, her own
mode (her role's, acceptEdits) back after; the queue empty, its file gone."
  (+test-awi "delivered" (("ada" "builder"))
    (agent-workspace-send ada "hold on" :submit t)
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'working)) 10))
    (let ((events (agent-workspace-inbox-add project "ada" "the build broke on main" :from "ci")))
      (should (equal (plist-get (car events) :state) "queued")))
    (should (equal (agent-workspace-inbox-badge ada) "✉1"))
    (should (file-exists-p (agent-workspace--inbox-path project)))
    (agent-workspace-interrupt ada)
    (should (+test-wait-for (lambda () (member (+test-awi--event-text "ci" "the build broke on main")
                                               (+test-awi--said "ada")))
                            20))
    (+test-awi--free ada)
    (should (+test-wait-for (lambda () (equal (last (+test-awi--said "ada") 3)
                                              (list "mode plan" (+test-awi--event-text "ci" "the build broke on main")
                                                    "mode acceptEdits")))
                            10))
    (should-not (agent-workspace-inbox project))
    (should-not (agent-workspace-inbox-badge ada))
    (should-not (file-exists-p (agent-workspace--inbox-path project)))))

(ert-deftest agent-workspace-inbox/a-role-s-first-free-agent-one-at-a-time ()
  "Two events for the builders while both work: the first one free takes
the first, then the second once that turn is over (one at a time, in order);
#all a copy each."
  (+test-awi "role" (("ada" "builder") ("ken" "builder"))
    (agent-workspace-send ada "hold on" :submit t)
    (agent-workspace-send ken "hold on" :submit t)
    (should (+test-wait-for (lambda () (and (eq (agent-workspace-agent-state ada) 'working)
                                            (eq (agent-workspace-agent-state ken) 'working)))
                            10))
    (agent-workspace-inbox-add project "#builder" "first" :from "ci")
    (agent-workspace-inbox-add project "#builder" "second" :from "ci")
    (should (= (length (agent-workspace-inbox project)) 2))
    (agent-workspace-interrupt ken)
    (should (+test-wait-for (lambda () (member (+test-awi--event-text "ci" "second") (+test-awi--said "ken"))) 20))
    (should (equal (seq-filter (lambda (text) (string-prefix-p "Event" text)) (+test-awi--said "ken"))
                   (list (+test-awi--event-text "ci" "first") (+test-awi--event-text "ci" "second"))))
    (should-not (seq-find (lambda (text) (string-prefix-p "Event" text)) (+test-awi--said "ada")))
    (+test-awi--free ken)
    ;; #all: one each.
    (let ((events (agent-workspace-inbox-add project "#all" "standup" :from "cal")))
      (should (equal (mapcar (lambda (event) (plist-get event :to)) events) '("ada" "ken"))))
    (should (+test-wait-for (lambda () (member (+test-awi--event-text "cal" "standup") (+test-awi--said "ken"))) 20))
    (should (equal (mapcar (lambda (event) (plist-get event :to)) (agent-workspace-inbox project)) '("ada")))))

(ert-deftest agent-workspace-inbox/asleep-it-waits-and-a-restart-keeps-it ()
  "For ada asleep: queued, never waking her; read again from its file (as
after a restart); delivered once she's woken and at the desk."
  (+test-awi "asleep" (("ada" "builder"))
    (agent-workspace-sleep ada)
    (should (eq (agent-workspace-agent-state ada) 'asleep))
    (agent-workspace-inbox-add project "ada" "nightly triage" :from "cron")
    (+test-sleep 0.2)
    (should (eq (agent-workspace-agent-state ada) 'asleep))
    ;; A restart: nothing in memory, the file read.
    (clrhash agent-workspace--inboxes)
    (should (equal (mapcar (lambda (event) (list (plist-get event :to) (plist-get event :from) (plist-get event :text)))
                           (agent-workspace-inbox project))
                   '(("ada" "cron" "nightly triage"))))
    (agent-workspace-wake ada)
    (should (+test-wait-for (lambda () (member (+test-awi--event-text "cron" "nightly triage") (+test-awi--said "ada")))
                            20))))

(ert-deftest agent-workspace-inbox/send-now-drop-and-pause ()
  "In the room: a queued event's [Send now] and [Drop]; Send now gives it at
once (after her turn), in her own mode; Drop drops it, said. P pauses them:
queued, not delivered, until P again."
  (+test-awi "buttons" (("ada" "builder"))
    (agent-workspace-open t)
    (agent-workspace-send ada "slow down" :submit t)
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'working)) 10))
    (let* ((one (plist-get (car (agent-workspace-inbox-add project "ada" "one" :from "ci")) :id))
           (two (plist-get (car (agent-workspace-inbox-add project "ada" "two" :from "ci")) :id))
           (feed (with-current-buffer (agent-workspace--room-buffer project) (buffer-string))))
      (should (string-search "✉ → ada one" feed))
      (should (string-search "[Send now] [Drop]" feed))
      (agent-workspace-inbox-drop project one)
      (should (string-search "dropped (you)" (+test-awi--room project)))
      (agent-workspace-inbox-send-now project two)
      (should-not (agent-workspace-inbox project))
      (should (+test-wait-for (lambda () (member (+test-awi--event-text "ci" "two") (+test-awi--said "ada"))) 20))
      (should-not (member (+test-awi--event-text "ci" "one") (+test-awi--said "ada")))
      (should-not (member "mode plan" (+test-awi--said "ada"))))
    (+test-awi--free ada)
    ;; Paused.
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-inbox-pause))
    (agent-workspace-inbox-add project "ada" "three" :from "ci")
    (+test-sleep 0.3)
    (should (= (length (agent-workspace-inbox project)) 1))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-inbox-pause))
    (should (+test-wait-for (lambda () (member (+test-awi--event-text "ci" "three") (+test-awi--said "ada"))) 20))))

(ert-deftest agent-workspace-inbox/limits-and-wrong-ones ()
  "A source's hour, an agent's day: more refused. Nobody by that name or
role, no text, a wrong source: refused, saying why."
  (+test-awi "limits" (("ada" "builder"))
    (agent-workspace-sleep ada)
    (dotimes (i agent-workspace-inbox-source-limit)
      (agent-workspace-inbox-add project "ada" (format "event %d" i) :from "ci"))
    (should (string-search "ci sent 6 events in the last hour"
                           (cadr (should-error (agent-workspace-inbox-add project "ada" "more" :from "ci")
                                               :type 'user-error))))
    (let ((agent-workspace-inbox-agent-limit 7))
      (agent-workspace-inbox-add project "ada" "from elsewhere" :from "cron")
      (should (string-search "ada had 7 events today"
                             (cadr (should-error (agent-workspace-inbox-add project "ada" "more" :from "cal")
                                                 :type 'user-error)))))
    (dolist (case '(("bob" "hi" "shell" "No agent bob in this crew; agents: ada")
                    ("#wizard" "hi" "shell" "No role wizard here")
                    ("ada" "  " "shell" "An event needs its text")
                    ("ada" "hi" "a b" "a source is named with letters")))
      (should (string-search (nth 3 case)
                             (cadr (should-error (agent-workspace-inbox-add project (nth 0 case) (nth 1 case)
                                                                            :from (nth 2 case))
                                                 :type 'user-error)))))))

(defun +test-awi--request (payload)
  "send's reply (parsed) as cmd/agent-workspace gets it, PAYLOAD its JSON."
  (let ((dir (make-temp-file (+test-tmp-file "awi-request-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert "send\n" default-directory "\n"))
    (with-temp-file (expand-file-name "payload" dir) (insert payload))
    (should (eq (agent-workspace-request dir) t))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "reply" dir))
      (json-parse-buffer :object-type 'plist :false-object nil :null-object nil :array-type 'list))))

(ert-deftest agent-workspace-inbox/from-the-shell ()
  "send from the shell: queued for ada (asleep), its reply saying so; from
her worktree too; wrong ones said."
  (+test-awi "shell" (("ada" "builder"))
    (agent-workspace-sleep ada)
    (should (equal (+test-awi--request "{\"to\":\"ada\",\"from\":\"ci\",\"text\":\"red\"}")
                   '(:ok t :events ((:id 1 :to "ada" :state "queued")))))
    (let ((default-directory (agent-workspace-agent-worktree ada)))
      (should (equal (plist-get (+test-awi--request "{\"to\":\"#all\",\"text\":\"hi\"}") :events)
                     '((:id 2 :to "ada" :state "queued")))))
    (should (equal (plist-get (car (last (agent-workspace-inbox project))) :from) "shell"))
    (let ((reply (+test-awi--request "{\"text\":\"hi\"}")))
      (should-not (plist-get reply :ok))
      (should (string-search "send: to whom?" (plist-get reply :error))))))

(ert-deftest agent-workspace-inbox/a-source-off ()
  "A source off for ada: its events for her dropped, said; for ken still
queued; off for everyone, his too; on again, queued. crew.el keeps it. #all's
copies, each its own id."
  (+test-awi "off" (("ada" "builder") ("ken" "builder"))
    (agent-workspace-sleep ada)
    (agent-workspace-sleep ken)
    (let ((ids (mapcar (lambda (event) (plist-get event :id)) (agent-workspace-inbox-add project "#all" "hi" :from "cal"))))
      (should (= (length (delete-dups ids)) 2)))
    (should (agent-workspace-inbox-source-toggle project "ci" "ada"))
    (should-not (agent-workspace-inbox-add project "ada" "red" :from "ci"))
    (should (string-search "dropped: ci is off for ada" (+test-awi--room project)))
    (should (equal (plist-get (car (agent-workspace-inbox-add project "ken" "red" :from "ci")) :state) "queued"))
    (agent-workspace-inbox-source-toggle project "ci" "#all")
    (should-not (agent-workspace-inbox-add project "#builder" "red" :from "ci"))
    (agent-workspace-crew-save project)
    (should (string-search ":sources-off ((\"ci\" . \"#all\") (\"ci\" . \"ada\"))"
                           (with-temp-buffer (insert-file-contents (agent-workspace--crew-path project)) (buffer-string))))
    (agent-workspace-inbox-source-toggle project "ci" "#all")
    (agent-workspace-inbox-source-toggle project "ci" "ada")
    (should (equal (plist-get (car (agent-workspace-inbox-add project "ada" "green" :from "ci")) :state) "queued"))))

(ert-deftest agent-workspace-inbox/quiet-hours ()
  "In the quiet hours an event waits (a delivery waiting for their end);
out of them, delivered."
  (+test-awi "quiet" (("ada" "builder"))
    (let* ((now (decode-time))
           (hhmm (lambda (minutes) (format "%02d:%02d" (/ (mod minutes 1440) 60) (mod minutes 60))))
           (minute (+ (* 60 (decoded-time-hour now)) (decoded-time-minute now)))
           (agent-workspace-inbox-quiet-hours (cons (funcall hhmm (- minute 10)) (funcall hhmm (+ minute 10)))))
      (agent-workspace-inbox-add project "ada" "late" :from "ci")
      (+test-sleep 0.3)
      (should (= (length (agent-workspace-inbox project)) 1))
      (should (timerp (gethash project agent-workspace--inbox-quiet-timers)))
      (cancel-timer (gethash project agent-workspace--inbox-quiet-timers))
      (let ((agent-workspace-inbox-quiet-hours (cons (funcall hhmm (+ minute 60)) (funcall hhmm (+ minute 70)))))
        (agent-workspace--inbox-deliver project)
        (should (+test-wait-for (lambda () (member (+test-awi--event-text "ci" "late") (+test-awi--said "ada"))) 20))))))

(ert-deftest agent-workspace-inbox/its-view ()
  "E: the queued events in the room's place; M-down / M-up move one (its
order of delivery), d drops it, o turns its source off for its agent (its
other events for her dropped), q gives the room back."
  (+test-awi "view" (("ada" "builder") ("ken" "builder"))
    (agent-workspace-open t)
    (agent-workspace-sleep ada)
    (agent-workspace-sleep ken)
    (dolist (event '(("ada" "one" "ci") ("ada" "two" "cron") ("ada" "three" "ci") ("ken" "four" "ci")))
      (agent-workspace-inbox-add project (nth 0 event) (nth 1 event) :from (nth 2 event)))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-inbox-view))
    (set-buffer (window-buffer (selected-window)))
    (should (eq (current-buffer) (agent-workspace--inbox-view-buffer project)))
    (let ((texts (lambda () (mapcar (lambda (event) (plist-get event :text)) (agent-workspace-inbox project)))))
      (should (string-search "three" (buffer-string)))
      (goto-char (point-min))
      (agent-workspace-inbox-view-down)
      (should (equal (funcall texts) '("two" "one" "three" "four")))
      (should (equal (aref (tabulated-list-get-entry) 3) "one"))
      (agent-workspace-inbox-view-up)
      (should (equal (funcall texts) '("one" "two" "three" "four")))
      (forward-line 1)
      (agent-workspace-inbox-view-drop)
      (should (equal (funcall texts) '("one" "three" "four")))
      (goto-char (point-min))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "ada")))
        (agent-workspace-inbox-view-source-off))
      (should (equal (funcall texts) '("four")))
      (should (string-search "off: ci for ada" (agent-workspace--inbox-view-header))))
    (agent-workspace-inbox-view-quit)
    (should (get-buffer-window (agent-workspace--room-buffer project)))))

(ert-deftest agent-workspace-inbox/napping-is-free ()
  "An agent napping (its loop found nothing) takes an event as one at the
desk does."
  (+test-awi "nap" (("ada" "builder"))
    (agent-workspace--set-state ada 'nap)
    (agent-workspace-inbox-add project "ada" "wake up" :from "ci")
    (should (+test-wait-for (lambda () (member (+test-awi--event-text "ci" "wake up") (+test-awi--said "ada"))) 20))))
