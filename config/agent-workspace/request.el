;;; $DOOMDIR/config/agent-workspace/request.el -*- lexical-binding: t; -*-
;; The shell's way in: cmd/agent-workspace. Loaded from
;; config/agent-workspace.el, after new.el. No Doom here.
;;
;; cmd/agent-workspace writes its request in a folder of its own (`request':
;; its operation, then the shell's folder; `payload': JSON) and has Emacs
;; answer it (emacsclient: `agent-workspace-request'), the reply JSON in
;; `reply'. For your scripts: an agent made from the shell.
;;
;;   new  {"role": "builder", "name": "ada", "prompt": "..."}  (name, prompt:
;;        optional) -> {"ok": true, "name", "role", "worktree", "branch",
;;        "state"}
;;   crew {"name": "full"} -> {"ok": true, "made": [{"name", "role",
;;        "worktree", "branch", "state"}...]}: what the crew lacks of the
;;        crew file full made (crews.el), none if it lacks nothing; those not
;;        made (their worktree), "failed": [{"role", "error"}...] too. An
;;        unknown crew: {"ok": false, "error"} naming the crews there are
;;   send {"to": "ada" | "#builder" | "#all", "from": "ci", "text": "..."}
;;        (from: optional, "shell") -> {"ok": true, "events": [{"id", "to",
;;        "state": "queued" | "delivered"}]} (inbox.el); with "agent": "ada"
;;        (from her shell, AGENT_WORKSPACE_AGENT, no from): her message
;;        (messages.el), its state "waiting" too, for your OK. Refused
;;        ({"ok": false, "error"}) while events from outside are off
;;        (`agent-workspace-outside-events'), or for an agent's message,
;;        while agents may not talk (`agent-workspace-agents-talk')

(require 'cl-lib)
(require 'subr-x)
(require 'json)

(declare-function agent-workspace-inbox-add "agent-workspace/inbox")
(declare-function agent-workspace-message-send "agent-workspace/messages")

(defun agent-workspace--request-new (directory payload)
  "Make an agent in DIRECTORY's project, as PAYLOAD (a plist) says: the
reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workspace-project)
                      (user-error "No crew here: %s" (agent-workspace-no-crew-reason))))
         (role (plist-get payload :role))
         (name (plist-get payload :name))
         (prompt (plist-get payload :prompt)))
    (unless (stringp role)
      (user-error "new: which role? --role ROLE"))
    (let ((agent (agent-workspace-create
                  :project project :role role
                  :name (if (and (stringp name) (not (string-empty-p name)))
                            name
                          (agent-workspace-pool-name project role))
                  :prompt (and (stringp prompt) (not (string-empty-p prompt)) prompt))))
      (cons :ok (cons t (agent-workspace--request-agent agent))))))

(defun agent-workspace--request-agent (agent)
  "AGENT as a reply says it: a plist."
  (list :name (agent-workspace-agent-name agent)
        :role (agent-workspace-agent-role agent)
        :worktree (directory-file-name (agent-workspace-agent-worktree agent))
        :branch (agent-workspace-agent-branch agent)
        :state (symbol-name (agent-workspace-agent-state agent))))

(defun agent-workspace--request-crew (directory payload)
  "Make what DIRECTORY's project's crew lacks of the crew file PAYLOAD (a
plist) names: the reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workspace-project)
                      (user-error "No crew here: %s" (agent-workspace-no-crew-reason))))
         (name (plist-get payload :name)))
    (unless (and (stringp name) (not (string-empty-p name)))
      (user-error "crew: which one? crew NAME"))
    (pcase-let ((`(,made ,failed ,_) (agent-workspace-crew-make project name)))
      (append (list :ok t :made (vconcat (mapcar #'agent-workspace--request-agent made)))
              (and failed
                   (list :failed (vconcat (mapcar (lambda (failure) (list :role (car failure) :error (cdr failure)))
                                                  failed))))))))

(defun agent-workspace--request-send (directory payload)
  "Queue an event in DIRECTORY's project, as PAYLOAD (a plist) says: the
reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workspace-project)
                      (user-error "No crew here: %s" (agent-workspace-no-crew-reason))))
         (to (plist-get payload :to))
         (from (plist-get payload :from))
         (sender (and (stringp (plist-get payload :agent))
                      (agent-workspace-agent (plist-get payload :agent) project))))
    (unless (and (stringp to) (not (string-empty-p to)))
      (user-error "send: to whom? --to NAME, --to #ROLE or --to #all"))
    (list :ok t
          :events (vconcat
                   (mapcar (lambda (event)
                             (list :id (plist-get event :id) :to (plist-get event :to)
                                   :state (plist-get event :state)))
                           (if sender
                               ;; From an agent's shell: its message.
                               (agent-workspace-message-send sender to (plist-get payload :text))
                             (agent-workspace-inbox-add project to (plist-get payload :text)
                                                        :from (if (and (stringp from) (not (string-empty-p from)))
                                                                  from
                                                                "shell"))))))))

(defun agent-workspace-request (dir)
  "Answer cmd/agent-workspace's request in DIR (see the top of this file):
its reply written to DIR/reply. Return t."
  (let* ((lines (split-string (with-temp-buffer
                                (insert-file-contents (expand-file-name "request" dir))
                                (buffer-string))
                              "\n"))
         (op (nth 0 lines))
         (directory (nth 1 lines))
         (payload-file (expand-file-name "payload" dir))
         (reply
          (condition-case err
              (let ((payload (when (file-exists-p payload-file)
                               (with-temp-buffer
                                 (let ((coding-system-for-read 'utf-8))
                                   (insert-file-contents payload-file))
                                 (json-parse-buffer :object-type 'plist :null-object nil
                                                    :false-object nil)))))
                (pcase op
                  ("new" (agent-workspace--request-new directory payload))
                  ("crew" (agent-workspace--request-crew directory payload))
                  ("send" (agent-workspace--request-send directory payload))
                  (_ (list :ok :false :error (format "unknown operation %S; operations: new, crew, send" op)))))
            (json-parse-error (list :ok :false :error (format "not JSON: %s" (error-message-string err))))
            (error (list :ok :false :error (error-message-string err))))))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file (expand-file-name "reply" dir)
        (insert (json-serialize reply) "\n")))
    t))
