;;; tests/unit/test-agent-workspace-handover.el -*- lexical-binding: t; -*-
;; config/agent-workspace/handover.el: issues as the crew's channel. What
;; each agent is told (its role's hands-to:), the room's words for a hand-over
;; (an agent's bd command), and two agents claiming one issue at once (bd's
;; claim, atomic: one gets it).

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

(defun +test-awo--agent (project name role)
  (agent-workspace--make-agent :name name :role role :project project
                               :worktree (expand-file-name (concat ".agent-shell/worktrees/" name "/") project)
                               :branch (concat "agent/" name)))

;; ====== TESTS ======

(ert-deftest agent-workspace-handover/what-each-is-told ()
  "A role handing on is told how (its label changed to the next role's, open,
unassigned, notes); one handing to nobody, nothing; its starter's own words
agree."
  (let* ((project (+test-awo--dir "told"))
         (investigator (+test-awo--agent project "sam" "investigator"))
         (reviewer (+test-awo--agent project "rex" "reviewer"))
         (scribe (+test-awo--agent project "liz" "scribe")))
    (let ((told (agent-workspace--handover-context investigator)))
      (should (string-search "hand it to the builders" told))
      (should (string-search "bd update ID --remove-label investigation --add-label build --status open --assignee \"\""
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

(ert-deftest agent-workspace-handover/said-in-the-room ()
  "An agent's bd command handing an issue on: to a role (its label's), back
to an agent (assigned), or only labelled."
  (let ((project (+test-awo--dir "said")))
    (should (equal (agent-workspace--bd-said
                    "bd update doom-a1b --remove-label investigation --add-label build --status open --assignee \"\" --append-notes 'found it'"
                    project)
                   "handed doom-a1b to the builders"))
    (should (equal (agent-workspace--bd-said
                    "bd update doom-a1b --remove-label review --add-label=build --status open --assignee ken --append-notes \"x\""
                    project)
                   "handed doom-a1b back to ken"))
    (should (equal (agent-workspace--bd-said "bd update doom-a1b --add-label wontfix" project)
                   "labelled doom-a1b wontfix"))
    (should (equal (agent-workspace--bd-said "bd update doom-a1b --claim --json" project) "claimed doom-a1b"))))

(ert-deftest agent-workspace-handover/two-claims-at-once ()
  "Two agents claiming the same ready issue at once (each as itself, bd's
claim): one gets it, the other is refused; the issue is the one's."
  (skip-unless (executable-find "bd"))
  (let* ((project (+test-awo--dir "claims"))
         (default-directory project)
         (process-environment (append '("BEADS_NO_DAEMON=1") process-environment)))
    (call-process "git" nil nil nil "init" "-q" "-b" "main")
    (should (eql 0 (call-process "bd" nil nil nil "init" "--quiet" "--skip-agents" "--prefix" "clm")))
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
              (should (equal (agent-workspace-agent-branch ken) "fix/demo-3"))
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
