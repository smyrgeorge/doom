;;; tests/unit/test-agent-workspace-handover.el -*- lexical-binding: t; -*-
;; config/agent-workspace/handover.el: issues as the crew's channel. What
;; each agent is told (the project's roles; its role's hands-to: in order, or
;; any, and returns-to:, the roles the crew has), the room's words for a hand-over
;; (as the issue changed: its label moved, open again), and two agents
;; claiming one issue at once (bd's claim, atomic: one gets it).

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require (quote agent-shell))
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
(remove-hook (quote +my/agent-shell-claude-context-functions) (function +my/agent-shell-beads-context))

;; ====== HELPERS ======

(defun +test-awo--dir (name)
  "A new, empty folder NAME in the temp folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awo/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun +test-awo--agent (project name role &optional state)
  (agent-workspace--make-agent :name name :role role :project project :state (or state 'desk)
                               :worktree (expand-file-name (concat ".agent-shell/worktrees/" name "/") project)
                               :branch (concat "agent/" name)))

(defmacro +test-awo--crew (project agents &rest body)
  "BODY with PROJECT's crew AGENTS (and no other crew)."
  (declare (indent 2))
  `(let ((agent-workspace--crews (make-hash-table :test #'equal)))
     (puthash ,project ,agents agent-workspace--crews)
     ,@body))

;; ====== TESTS ======

(ert-deftest agent-workspace-handover/what-each-is-told ()
  "A role handing on is told how (its label changed to the next role's, open,
unassigned, notes); one handing to nobody, nothing; its starter's own words
agree."
  (let* ((project (+test-awo--dir "told"))
         (investigator (+test-awo--agent project "sam" "investigator"))
         (reviewer (+test-awo--agent project "rex" "reviewer"))
         (scribe (+test-awo--agent project "liz" "scribe"))
         (agent-workspace--crews (make-hash-table :test #'equal)))
    (puthash project (list investigator reviewer scribe (+test-awo--agent project "ken" "builder"))
             agent-workspace--crews)
    (let ((told (agent-workspace--handover-context investigator)))
      (should (string-search "hand it to the builders" told))
      (should (string-search "bd update ID --remove-label investigation --remove-label incident --add-label build --status open --assignee \"\""
                             told))
      (should (string-search "the first free builder takes it" told)))
    (should (string-search "--remove-label review --add-label build" (agent-workspace--handover-context reviewer)))
    (should-not (agent-workspace--handover-context scribe))
    (let ((text (let ((agent-workspace--starting reviewer)) (agent-workspace-agent-context))))
      (should (string-search "assigned to the one who made it (--assignee NAME)" text))
      (should (string-search "Work moves between roles" text)))
    (should (equal (agent-workspace-label-role project "build") "builder"))
    (should (equal (agent-workspace-label-role project "incident") "investigator"))
    (should-not (agent-workspace-label-role project "nobody's"))))

(defun +test-awo--roles (project)
  "PROJECT's own roles: a tester, a router handing to any, a chain handing
to the testers else the reviewers, returning to the builders."
  (let ((dir (expand-file-name ".agent-workspace/roles/" project)))
    (make-directory dir t)
    (write-region "---\ndescription: tests it\nlabels: test\n---\nTest.\n" nil (expand-file-name "tester.md" dir))
    (write-region "---\ndescription: routes issues\nlabels: triage\nhands-to: any\n---\nRoute.\n" nil
                  (expand-file-name "router.md" dir))
    (write-region "---\ndescription: makes it\nlabels: chain\nhands-to: tester, reviewer\nreturns-to: builder\n---\nMake.\n"
                  nil (expand-file-name "chain.md" dir))))

(ert-deftest agent-workspace-handover/hands-on-in-order ()
  "hands-to in order: the first role the crew has an agent of (asleep too,
not gone home) is the one it's told to hand to; none: it tells the user;
returns-to: the work going back, to the one who made it."
  (let* ((project (+test-awo--dir "order"))
         (ann (+test-awo--agent project "ann" "chain"))
         (tim (+test-awo--agent project "tim" "tester" 'asleep))
         (rex (+test-awo--agent project "rex" "reviewer"))
         (bob (+test-awo--agent project "bob" "builder"))
         (agent-workspace-agents-talk t))
    (+test-awo--roles project)
    (+test-awo--crew project (list ann rex bob)
      (should (equal (agent-workspace-hands-to project "chain") '("reviewer")))
      (should (equal (agent-workspace-hands-to project "chain" :returns-to) '("builder")))
      (let ((told (agent-workspace--handover-context ann)))
        (should (string-search "hand it to the reviewers" told))
        (should (string-search "bd update ID --remove-label chain --add-label review --status open --assignee \"\"" told))
        (should-not (string-search "tester" told))
        (should (string-search "give it back to the builders, assigned to the one who made it" told))
        (should (string-search "bd update ID --remove-label chain --add-label build --status open --assignee NAME" told))))
    ;; A tester in the crew, asleep: it comes first.
    (+test-awo--crew project (list ann tim rex bob)
      (should (equal (agent-workspace-hands-to project "chain") '("tester")))
      (should (string-search "hand it to the testers" (agent-workspace--handover-context ann))))
    ;; Gone home: not.
    (setf (agent-workspace-agent-state tim) 'home)
    (+test-awo--crew project (list ann tim rex bob)
      (should (equal (agent-workspace-hands-to project "chain") '("reviewer"))))
    ;; None of them in the crew: it tells the user; nothing goes back.
    (+test-awo--crew project (list ann)
      (should-not (agent-workspace-hands-to project "chain"))
      (let ((told (agent-workspace--handover-context ann)))
        (should (string-search "goes to the testers or the reviewers, but the crew has none of them now" told))
        (should (string-search "tell the user what you did" told))
        (should-not (string-search "--add-label" told))))))

(ert-deftest agent-workspace-handover/hands-to-any ()
  "hands-to any: every role with labels the crew has an agent of, but its
own, each with its bd command; a role without labels, or none in the
crew, not offered."
  (let* ((project (+test-awo--dir "any"))
         (rio (+test-awo--agent project "rio" "router"))
         (agent-workspace-agents-talk t))
    (+test-awo--roles project)
    (+test-awo--crew project (list rio (+test-awo--agent project "ann" "chain") (+test-awo--agent project "tim" "tester")
                                   (+test-awo--agent project "bob" "builder") (+test-awo--agent project "liz" "scribe"))
      (should (equal (agent-workspace-hands-to project "router") '("builder" "chain" "tester")))
      (let ((told (agent-workspace--handover-context rio)))
        (should (string-search "hand it to the role it's for" told))
        (should (string-search "\n- the builders (builds what you give it): bd update ID --remove-label triage --add-label build --status open --assignee \"\""
                               told))
        (should (string-search "\n- the chains (makes it): bd update ID --remove-label triage --add-label chain" told))
        (should (string-search "\n- the testers (tests it): bd update ID --remove-label triage --add-label test" told))
        (should-not (string-search "reviewer" told))
        (should-not (string-search "scribe" told))
        (should-not (string-search "add-label triage" told))))))

(ert-deftest agent-workspace-handover/every-agent-told-the-roles ()
  "Every agent is told the project's roles, a line each (name, what it
does, its labels): the starters, the project's own and your local ones;
before how it hands on, and the scribe's own words name no labels."
  (let* ((project (+test-awo--dir "roles"))
         (liz (+test-awo--agent project "liz" "scribe"))
         (local (expand-file-name ".agent-shell/agent-workspace/roles/" project)))
    (+test-awo--roles project)
    (make-directory local t)
    (write-region "---\ndescription: my own\nlabels: mine, also\n---\nMine.\n" nil (expand-file-name "mine.md" local))
    (let ((told (agent-workspace--roles-context liz)))
      (should (string-prefix-p "The project's roles, and the labels of the issues each is for" told))
      (dolist (line '("\n- builder, builds what you give it: build"
                      "\n- investigator, investigates what you give it: investigation, incident"
                      "\n- scribe, writes issues with you: no labels"
                      "\n- tester, tests it: test"
                      "\n- chain, makes it: chain"
                      "\n- mine, my own: mine, also"))
        (should (string-search line told))))
    (+test-awo--crew project (list liz (+test-awo--agent project "rex" "reviewer") (+test-awo--agent project "bob" "builder"))
      (let ((text (let ((agent-workspace--starting (+test-awo--agent project "rex" "reviewer")))
                    (agent-workspace-agent-context))))
        (should (< (string-search "The project's roles" text) (string-search "Work moves between roles" text))))
      (let ((text (let ((agent-workspace--starting liz)) (agent-workspace-agent-context))))
        (should (string-search "\n- mine, my own: mine, also" text))
        (should (string-search "Label it for the role that takes it" text))
        (should-not (string-search "investigation, incident, build or review" text))))))

(ert-deftest agent-workspace-handover/said-in-the-room ()
  "A hand-over as the issue says it (two fetches compared): its label moved
from its agent's role's to another role's, open again: to that role,
unassigned; back to an agent, assigned; while agents may not talk, only
labelled. A label just added (the builders' too): labelled, never handed
on. A claim: claimed."
  (let* ((project (+test-awo--dir "said"))
         (agent-workspace--crews (make-hash-table :test #'equal))
         (issue (lambda (id status assignee labels)
                  (list :id id :title id :status status :assignee assignee :labels labels)))
         (sam-had (funcall issue "p-1" 'in_progress "sam" '("investigation")))
         (sam-handed (funcall issue "p-1" 'open nil '("build")))
         (rex-had (funcall issue "p-2" 'in_progress "rex" '("review")))
         (rex-handed (funcall issue "p-2" 'open "ken" '("build")))
         (filed (funcall issue "p-3" 'open nil nil))
         (labelled (funcall issue "p-3" 'open nil '("build"))))
    (puthash project (list (+test-awo--agent project "sam" "investigator") (+test-awo--agent project "rex" "reviewer")
                           (+test-awo--agent project "ken" "builder") (+test-awo--agent project "ada" "scribe"))
             agent-workspace--crews)
    (let ((agent-workspace-agents-talk t))
      (should (equal (agent-workspace--issues-said project (list sam-had) (list sam-handed) "sam")
                     '(("sam" . "handed p-1 to the builders"))))
      (should (equal (agent-workspace--issues-said project (list rex-had) (list rex-handed) "rex")
                     '(("rex" . "handed p-2 back to ken"))))
      (should (equal (agent-workspace--issues-said project (list filed) (list labelled) "ada")
                     '(("ada" . "labelled p-3 build"))))
      (should (equal (agent-workspace--issues-said project (list labelled)
                                                   (list (funcall issue "p-3" 'in_progress "ken" '("build")))
                                                   "ken")
                     '(("ken" . "claimed p-3")))))
    (let ((agent-workspace-agents-talk nil))
      (should (equal (agent-workspace--issues-said project (list sam-had) (list sam-handed) "sam")
                     '(("sam" . "labelled p-1 build")))))))

(ert-deftest agent-workspace-handover/two-claims-at-once ()
  "Two agents claiming the same ready issue at once (each as itself, bd's
claim): one gets it, the other is refused; the issue is the one's."
  (skip-unless (executable-find "bd"))
  (let* ((project (+test-awo--dir "claims"))
         (default-directory project)
         (process-environment (append '("BEADS_NO_DAEMON=1") process-environment)))
    (+test-bd-init "--quiet" "--skip-agents" "--prefix" "clm")
    (let* ((id (with-temp-buffer
                 (should (eql 0 (call-process "bd" nil t nil "create" "--title" "Build it" "--type" "task"
                                              "--labels" "build" "--json")))
                 (goto-char (point-min))
                 (search-forward "{")
                 (backward-char)
                 (plist-get (json-parse-buffer :object-type 'plist) :id)))
           (claim (lambda (name)
                    (let ((process-environment (cons (concat "BEADS_ACTOR=" name) process-environment)))
                      (make-process :name (concat "claim-" name) :buffer (generate-new-buffer (concat " claim-" name))
                                    :command (list "bd" "update" id "--claim" "--json")
                                    :connection-type 'pipe :noquery t))))
           (processes (list (funcall claim "ada") (funcall claim "ken"))))
      (should (+test-wait-for (lambda () (seq-every-p (lambda (p) (not (process-live-p p))) processes)) 30))
      (let ((statuses (mapcar #'process-exit-status processes))
            (assignee (with-temp-buffer
                        (call-process "bd" nil t nil "show" id "--json")
                        (goto-char (point-min))
                        (let ((issue (json-parse-buffer :object-type 'plist :array-type 'list)))
                          (plist-get (if (listp issue) (car issue) issue) :assignee)))))
        (should (= (seq-count #'zerop statuses) 1))
        (should (member assignee '("ada" "ken")))
        (should (equal assignee (if (zerop (car statuses)) "ada" "ken"))))
      (dolist (p processes) (kill-buffer (process-buffer p))))))

(ert-deftest agent-workspace-handover/every-label-of-its-role-goes ()
  "An investigator (labels investigation, incident) handing an incident on,
as it's told: none of its role's labels left on it, so its loop's claim
\(bd ready --claim --label-any investigation,incident) doesn't take it
back; a builder's does (doom-pbk.57)."
  (skip-unless (executable-find "bd"))
  (let* ((project (+test-awo--dir "labels"))
         (default-directory project)
         (investigator (+test-awo--agent project "ivy" "investigator"))
         (told (+test-awo--crew project (list investigator (+test-awo--agent project "ken" "builder"))
                 (agent-workspace--handover-context investigator))))
    (+test-bd-init "--quiet" "--skip-agents" "--prefix" "lbl")
    (should (string-match "bd update ID \\(.*?\\) --append-notes" told))
    (let* ((flags (split-string-and-unquote (match-string 1 told)))
           (id (with-temp-buffer
                 (should (eql 0 (call-process "bd" nil t nil "create" "--title" "Prod is down" "--type" "bug"
                                              "--labels" "investigation,incident" "--json")))
                 (goto-char (point-min))
                 (search-forward "{")
                 (backward-char)
                 (plist-get (json-parse-buffer :object-type 'plist) :id)))
           (claim (lambda (actor labels)
                    (with-temp-buffer
                      (let ((process-environment (cons (concat "BEADS_ACTOR=" actor) process-environment)))
                        (should (eql 0 (call-process "bd" nil t nil "ready" "--claim" "--label-any" labels "--json"))))
                      (goto-char (point-min))
                      (let ((answer (and (search-forward "[" nil t)
                                         (progn (backward-char) (json-parse-buffer :object-type 'plist :array-type 'list)))))
                        (plist-get (car answer) :id))))))
      (should (equal (funcall claim "ivy" "investigation,incident") id))
      ;; As it does it: as itself.
      (let ((process-environment (cons "BEADS_ACTOR=ivy" process-environment)))
        (with-temp-buffer
          (unless (eql 0 (apply #'call-process "bd" nil t nil "update" id flags))
            (ert-fail (list flags (buffer-string))))))
      (should-not (funcall claim "ivy" "investigation,incident"))
      (should (equal (funcall claim "bob" "build") id)))))

(defun +test-awo--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (+test-awo--dir name)))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    dir))

(ert-deftest agent-workspace-handover/a-ready-issue-offered ()
  "An issue ready for the builders, ken free: offered in the room once,
[Give it to ken] giving it him (his worktree on its branch); no builder
free, offered once one is."
  (+test-with-reset
    (let* ((project (+test-awo--project "offer"))
           (default-directory project)
           (agent-workspace--crews (make-hash-table :test #'equal))
           (agent-workspace--apps (make-hash-table :test #'equal))
           (agent-workspace--offered (make-hash-table :test #'equal))
           (sent nil))
      (set-frame-size (selected-frame) 220 40)
      (cl-letf (((symbol-function 'agent-workspace--start)
                 (lambda (agent)
                   (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                     (with-current-buffer buffer (setq agent-workspace--agent agent))
                     (setf (agent-workspace-agent-buffer agent) buffer)
                     (agent-workspace--set-state agent 'desk)
                     buffer)))
                ((symbol-function 'agent-workspace--stop)
                 (lambda (agent state &rest _)
                   (when (buffer-live-p (agent-workspace-agent-buffer agent))
                     (kill-buffer (agent-workspace-agent-buffer agent)))
                   (setf (agent-workspace-agent-buffer agent) nil)
                   (agent-workspace--set-state agent state)
                   nil))
                ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil)))
                ((symbol-function 'agent-workspace-send)
                 (lambda (agent text &rest _) (push (list (agent-workspace-agent-name agent) text) sent) 'sent)))
        (unwind-protect
            (let ((ken (agent-workspace-create :role "builder" :name "ken"))
                  (fetched (lambda (ready)
                             (let ((data (list :ready ready)))
                               (with-current-buffer (agent-workspace--issues-buffer project)
                                 (setq agent-workspace--issues-data data))
                               (run-hook-with-args 'agent-workspace-issues-fetched-functions project data))))
                  (feed (lambda () (with-current-buffer (agent-workspace--room-buffer project) (buffer-string)))))
              (agent-workspace-create :role "investigator" :name "sam")
              (agent-workspace-open t)
              (funcall fetched (list (list :id "demo-3" :title "Fix it" :role "builder" :status 'ready :type "bug")))
              (should (string-search "demo-3 is ready for the builders: ken is free" (funcall feed)))
              (should (string-search "[Give it to ken]" (funcall feed)))
              (funcall fetched (list (list :id "demo-3" :title "Fix it" :role "builder" :status 'ready :type "bug")))
              (should (= 1 (with-temp-buffer (insert (funcall feed)) (count-matches "demo-3 is ready" (point-min) (point-max)))))
              (agent-workspace-offer-take project "demo-3" "ken")
              (should (equal (car sent) (list "ken" (agent-workspace-issue-prompt "demo-3" "Fix it"))))
              (should (equal (agent-workspace-agent-issue ken) "demo-3"))
              (should (equal (agent-workspace-agent-branch ken) "fix/demo-3-fix"))
              (should-not (string-search "[Give it to ken]" (funcall feed)))
              (funcall fetched nil)
              (should-not (string-search "[Give it to ken]" (funcall feed)))
              ;; No builder free: offered once he is.
              (agent-workspace--set-state ken 'working)
              (agent-workspace-give ken nil)
              (funcall fetched (list (list :id "demo-4" :title "More" :role "builder" :status 'ready)))
              (should-not (string-search "demo-4 is ready" (funcall feed)))
              (agent-workspace--set-state ken 'done)
              (should (string-search "demo-4 is ready for the builders: ken is free" (funcall feed)))
              ;; Looping, he takes them himself: none offered.
              (setf (agent-workspace-agent-loop ken) t)
              (agent-workspace-give ken nil)
              (funcall fetched (list (list :id "demo-5" :title "Loop it" :role "builder" :status 'ready)))
              (should-not (string-search "demo-5 is ready" (funcall feed)))
              (setf (agent-workspace-agent-loop ken) nil))
          (when (agent-workspace--app project) (agent-workspace--close-app project))
          (agent-workspace-close-all))))))

(ert-deftest agent-workspace-handover/one-handed-back-offered-to-its-agent ()
  "A ready issue handed back to ken (open, assigned to him) is offered to
him once he's free, not to another builder; taken, its button goes
\(doom-pbk.58)."
  (let* ((project (+test-awo--project "back"))
         (default-directory project)
         (sent nil))
    (set-frame-size (selected-frame) 220 40)
    (cl-letf (((symbol-function 'agent-workspace--start)
               (lambda (agent)
                 (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                   (with-current-buffer buffer (setq agent-workspace--agent agent))
                   (setf (agent-workspace-agent-buffer agent) buffer)
                   (agent-workspace--set-state agent 'desk)
                   buffer)))
              ((symbol-function 'agent-workspace--stop)
               (lambda (agent state &rest _)
                 (when (buffer-live-p (agent-workspace-agent-buffer agent))
                   (kill-buffer (agent-workspace-agent-buffer agent)))
                 (setf (agent-workspace-agent-buffer agent) nil)
                 (agent-workspace--set-state agent state)
                 nil))
              ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
              ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil)))
              ((symbol-function 'agent-workspace-send)
               (lambda (agent text &rest _) (push (list (agent-workspace-agent-name agent) text) sent) 'sent)))
      (unwind-protect
          (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
                 (ken (agent-workspace-create :role "builder" :name "ken"))
                 (feed (lambda () (with-current-buffer (agent-workspace--room-buffer project) (buffer-string))))
                 (fetched (lambda ()
                            (let ((data (list :ready (list (list :id "demo-7" :title "Changes asked" :role "builder"
                                                                 :status 'ready :type "task" :assignee "ken")))))
                              (with-current-buffer (agent-workspace--issues-buffer project)
                                (setq agent-workspace--issues-data data))
                              (run-hook-with-args 'agent-workspace-issues-fetched-functions project data)))))
            (ignore ada)
            (agent-workspace-open t)
            ;; ken working: not offered, not to ada either.
            (agent-workspace--set-state ken 'working)
            (funcall fetched)
            (should-not (string-search "demo-7" (funcall feed)))
            ;; Free: offered to him.
            (agent-workspace--set-state ken 'done)
            (should (string-search "demo-7 is back for ken, free now" (funcall feed)))
            (should (string-search "[Give it to ken]" (funcall feed)))
            (agent-workspace-offer-take project "demo-7" "ken")
            (should (equal (car sent) (list "ken" (agent-workspace-issue-prompt "demo-7" "Changes asked"))))
            (should-not (string-search "[Give it to ken]" (funcall feed))))
        (when (agent-workspace--app project) (agent-workspace--close-app project))
        (agent-workspace-close-all)))))

(ert-deftest agent-workspace-handover/offered-again-to-the-next-role ()
  "demo-1 offered to ken, a builder; handed to the reviewers: offered to
rita, free; ken's old button gone, not coming back (doom-pbk.62)."
  (let* ((project (+test-awo--project "next-role"))
         (default-directory project))
    (set-frame-size (selected-frame) 220 40)
    (cl-letf (((symbol-function 'agent-workspace--start)
               (lambda (agent)
                 (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                   (with-current-buffer buffer (setq agent-workspace--agent agent))
                   (setf (agent-workspace-agent-buffer agent) buffer)
                   (agent-workspace--set-state agent 'desk)
                   buffer)))
              ((symbol-function 'agent-workspace--stop)
               (lambda (agent state &rest _)
                 (when (buffer-live-p (agent-workspace-agent-buffer agent))
                   (kill-buffer (agent-workspace-agent-buffer agent)))
                 (setf (agent-workspace-agent-buffer agent) nil)
                 (agent-workspace--set-state agent state)
                 nil))
              ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
              ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil))))
      (unwind-protect
          (let* ((ken (agent-workspace-create :role "builder" :name "ken"))
                 (rita (agent-workspace-create :role "reviewer" :name "rita"))
                 (feed (lambda () (with-current-buffer (agent-workspace--room-buffer project) (buffer-string))))
                 (fetched (lambda (role)
                            (let ((data (list :ready (list (list :id "demo-1" :title "Lexer" :role role
                                                                 :status 'ready :type "task")))))
                              (with-current-buffer (agent-workspace--issues-buffer project)
                                (setq agent-workspace--issues-data data))
                              (run-hook-with-args 'agent-workspace-issues-fetched-functions project data)))))
            (ignore ken rita)
            (agent-workspace-open t)
            (funcall fetched "builder")
            (should (string-search "demo-1 is ready for the builders: ken is free" (funcall feed)))
            (should (string-search "[Give it to ken]" (funcall feed)))
            ;; Handed to the reviewers.
            (funcall fetched "reviewer")
            (should (string-search "demo-1 is ready for the reviewers: rita is free" (funcall feed)))
            (should (string-search "[Give it to rita]" (funcall feed)))
            (should-not (string-search "[Give it to ken]" (funcall feed))))
        (when (agent-workspace--app project) (agent-workspace--close-app project))
        (agent-workspace-close-all)))))

(ert-deftest agent-workspace-handover/nothing-handed-on-while-agents-may-not-talk ()
  "Agents may not talk (`agent-workspace-agents-talk' nil): a role handing
on is told to hand nothing on, only to tell the user, not how to hand on;
one handing to nobody, nothing."
  (let* ((project (+test-awo--dir "never"))
         (investigator (+test-awo--agent project "sam" "investigator"))
         (scribe (+test-awo--agent project "liz" "scribe"))
         (agent-workspace-agents-talk nil))
    (let ((told (agent-workspace--handover-context investigator)))
      (should (string-search "hand nothing on" told))
      (should (string-search "tell the user what you did" told))
      (should-not (string-search "--add-label" told)))
    (should-not (agent-workspace--handover-context scribe))
    (let ((text (let ((agent-workspace--starting investigator)) (agent-workspace-agent-context))))
      (should (string-search "hand nothing on" text))
      (should-not (string-search "Work moves between roles" text)))))
