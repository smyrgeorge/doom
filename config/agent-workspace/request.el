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
;;
;; The crew seen, then run, as you do in the app:
;;
;;   status {} -> {"ok": true, "project", "agents": [{"name", "role",
;;        "state", "words" (as its bar says them), "time" (its turn's),
;;        "loop", "issue", "issue_title", "branch", "worktree", "changed"
;;        (its files), "asking" ({"kind", "title", "words"}: its raised
;;        hand), "events" (waiting for it)}...], "conflicts": [{"file",
;;        "agents"}...] (the minimap's ⚠), "offers": [{"issue", "title",
;;        "to", "role"}...] (the room's, still standing), "talk"}
;;   give {"issue": "doom-a1b", "to": "grace"} -> {"ok": true, "name", ...,
;;        "issue", "prompt": "sent" | "queued"}: as t does
;;        (`agent-workspace-give-issue')
;;   wake {"name": "linus"}, sleep {"name": "linus"} -> {"ok": true, "name",
;;        ...}: as Z does
;;   loop {"name": "linus", "on": true} -> {"ok": true, "name", ..., "loop"}:
;;        as L does (`agent-workspace-loop-set')
;;
;; give, wake, sleep and loop come with "agent" too: from an agent's shell
;; (AGENT_WORKSPACE_AGENT), its name, and they're refused unless its role
;; leads (leads: true, roles.el); from yours or a script's, none, and they
;; all work. Each said in the room, by who did it: "linus woke ken", "shell
;; gave doom-a1b to grace". new and crew alike.
;;
;; WHO ASKS
;; Not what its shell says (AGENT_WORKSPACE_AGENT can be unset or changed)
;; but where a request comes from: the script sends its process's id, and
;; the agent whose session's process is one of its ancestors sent it (a
;; command its session ran), whatever its shell says. None: yours, or a
;; script's (your terminal in an agent's worktree too), its shell's word
;; taken. An agent's send is its message, never an event --from a source
;; (no way round the crew's switch, a thread stopped, its limit).

(require 'cl-lib)
(require 'subr-x)
(require 'json)

(declare-function agent-workspace-inbox-add "agent-workspace/inbox")
(declare-function agent-workspace-inbox-count "agent-workspace/inbox")
(declare-function agent-workspace-message-send "agent-workspace/messages")
(declare-function agent-workspace-talk-mode "agent-workspace/messages")
(declare-function agent-workspace--ordered "agent-workspace/app")
(declare-function agent-workspace-state-words "agent-workspace/look")
(declare-function agent-workspace-time "agent-workspace/look")
(declare-function agent-workspace-activity "agent-workspace/activity")
(declare-function agent-workspace-conflicts "agent-workspace/activity")
(declare-function agent-workspace--issues-data "agent-workspace/handover")
(declare-function agent-workspace--still-ready "agent-workspace/handover")
(declare-function agent-workspace--bd-now "agent-workspace/issues")
(declare-function agent-workspace--bd-why "agent-workspace/issues")
(declare-function agent-workspace-give-issue "agent-workspace/issues")
(declare-function agent-workspace-loop-set "agent-workspace/loops")
(declare-function agent-workspace-room-post "agent-workspace/room")
(declare-function agent-workspace--room-redraw-soon "agent-workspace/room")
(defvar agent-workspace--offered)
(declare-function agent-workspace--ready-given "agent-workspace/handover")
(declare-function agent-workspace--session-process "agent-workspace/session")

;; ====== WHO ASKS ======

(defvar agent-workspace--request-from nil
  "While a request is answered: the agent whose session sent it
\(`agent-workspace--request-caller'), or nil (your shell, a script).")

(defun agent-workspace--pid-ancestors (pid)
  "PID and its ancestors' ids, itself first (at most 64)."
  (let ((pids nil))
    (while (and (natnump pid) (> pid 1) (not (memq pid pids)) (< (length pids) 64))
      (push pid pids)
      (setq pid (alist-get 'ppid (ignore-errors (process-attributes pid)))))
    (nreverse pids)))

(defun agent-workspace--agent-pid (agent)
  "The id of AGENT's session's process (its ACP client's), or nil."
  (when-let* ((process (agent-workspace--session-process (agent-workspace-agent-buffer agent)))
              ((process-live-p process)))
    (process-id process)))

(defun agent-workspace--request-caller (pid)
  "The agent whose session ran the command that sent a request (see WHO
ASKS): of every crew's, the one whose session's process is an ancestor of
PID (the script's); nil if none."
  (when-let* ((ancestors (and pid (agent-workspace--pid-ancestors pid))))
    (seq-find (lambda (agent) (memq (agent-workspace--agent-pid agent) ancestors))
              (apply #'append (mapcar #'agent-workspace-agents (agent-workspace-crews))))))

(defun agent-workspace--request-new (directory payload)
  "Make an agent in DIRECTORY's project, as PAYLOAD (a plist) says: the
reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workspace-project)
                      (user-error "No crew here: %s" (agent-workspace-no-crew-reason))))
         (role (plist-get payload :role))
         (name (plist-get payload :name))
         (prompt (plist-get payload :prompt)))
    (agent-workspace--request-actor project payload)
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
        :worktree (agent-workspace--request-or-null
                   (and (agent-workspace-agent-worktree agent)
                        (directory-file-name (agent-workspace-agent-worktree agent))))
        ;; None checked out (a rebase, a commit): null, not {}.
        :branch (agent-workspace--request-or-null (agent-workspace-agent-branch agent))
        :state (symbol-name (agent-workspace-agent-state agent))))

(defun agent-workspace--request-crew (directory payload)
  "Make what DIRECTORY's project's crew lacks of the crew file PAYLOAD (a
plist) names: the reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workspace-project)
                      (user-error "No crew here: %s" (agent-workspace-no-crew-reason))))
         (name (plist-get payload :name)))
    (agent-workspace--request-actor project payload)
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
         ;; Its session's agent, whatever its shell says; else as it says.
         (sender (or agent-workspace--request-from
                     (and (stringp (plist-get payload :agent))
                          (agent-workspace-agent (plist-get payload :agent) project)))))
    (unless (and (stringp to) (not (string-empty-p to)))
      (user-error "send: to whom? --to NAME, --to #ROLE or --to #all"))
    (when (and agent-workspace--request-from (stringp from) (not (string-empty-p from)))
      (user-error "%s" (format "send: --from is for scripts outside the agents' sessions; from %s's, a send is its message"
                               (agent-workspace-agent-name agent-workspace--request-from))))
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

;; ====== THE CREW SEEN ======

(defun agent-workspace--request-project (directory)
  "DIRECTORY's project, its crew's: a user error if it has none."
  (let ((default-directory (file-name-as-directory directory)))
    (or (agent-workspace-project)
        (user-error "No crew here: %s" (agent-workspace-no-crew-reason)))))

(defun agent-workspace--request-or-null (value)
  "VALUE as JSON has it: nil, null."
  (or value :null))

(defun agent-workspace--request-agent-status (agent)
  "AGENT as status says it: a plist."
  (let ((ask (agent-workspace-agent-ask agent))
        (activity (and (fboundp 'agent-workspace-activity) (agent-workspace-activity agent))))
    (list :name (agent-workspace-agent-name agent)
          :role (agent-workspace-agent-role agent)
          :state (symbol-name (agent-workspace-agent-state agent))
          :words (substring-no-properties (agent-workspace-state-words agent))
          :time (agent-workspace--request-or-null (agent-workspace-time agent))
          :loop (if (agent-workspace-agent-loop agent) t :false)
          :issue (agent-workspace--request-or-null (agent-workspace-agent-issue agent))
          :issue_title (agent-workspace--request-or-null (agent-workspace-agent-issue-title agent))
          :branch (agent-workspace--request-or-null (agent-workspace-agent-branch agent))
          :worktree (agent-workspace--request-or-null
                     (and (agent-workspace-agent-worktree agent)
                          (directory-file-name (agent-workspace-agent-worktree agent))))
          :changed (vconcat (plist-get activity :changed))
          :asking (if (and ask (eq (agent-workspace-agent-state agent) 'hand))
                      (list :kind (symbol-name (plist-get ask :kind))
                            :title (agent-workspace--request-or-null (plist-get ask :title))
                            :words (agent-workspace--ask-text ask))
                    :null)
          :events (if (fboundp 'agent-workspace-inbox-count) (agent-workspace-inbox-count agent) 0))))

(defun agent-workspace--request-offers (project)
  "PROJECT's room's offers still standing (their buttons shown: the issue
still ready for the role it was offered for, its agent in the crew), the
oldest first: plists."
  (let (offers)
    ;; The latest first: pushed, the oldest first.
    (pcase-dolist (`((,id ,role ,_) . ,name)
                   (and (boundp 'agent-workspace--offered)
                        (gethash (agent-workspace--root project) agent-workspace--offered)))
      (when-let* ((issue (agent-workspace--still-ready project id name))
                  ((equal (plist-get issue :role) role))
                  ((agent-workspace-agent name project)))
        (push (list :issue id :title (agent-workspace--request-or-null (plist-get issue :title))
                    :to name :role (agent-workspace--request-or-null role))
              offers)))
    offers))

(defun agent-workspace--request-status (directory)
  "DIRECTORY's project's crew as it is: the reply, a plist."
  (let ((project (agent-workspace--request-project directory)))
    (list :ok t
          :project (directory-file-name project)
          :agents (vconcat (mapcar #'agent-workspace--request-agent-status
                                   (if (fboundp 'agent-workspace--ordered)
                                       (agent-workspace--ordered project)
                                     (agent-workspace-agents project))))
          :conflicts (vconcat (mapcar (lambda (conflict)
                                        (list :file (car conflict)
                                              :agents (vconcat (mapcar #'agent-workspace-agent-name (cdr conflict)))))
                                      (agent-workspace-conflicts project)))
          :offers (vconcat (agent-workspace--request-offers project))
          :talk (symbol-name (agent-workspace-talk-mode project)))))

;; ====== THE CREW RUN ======

(defun agent-workspace--request-actor (project payload)
  "Who runs PROJECT's crew: the agent whose session sent the request
\(`agent-workspace--request-from'), else the one PAYLOAD's :agent names
\(its shell's word), its name, a user error unless its role leads; else
\"shell\"."
  (let ((name (if agent-workspace--request-from
                  (agent-workspace-agent-name agent-workspace--request-from)
                (plist-get payload :agent))))
    (if (not (and (stringp name) (not (string-empty-p name))))
        "shell"
      (let ((agent (agent-workspace-agent name project)))
        (cond
         ;; "%s": its apostrophes kept straight, for scripts.
         ((not agent) (user-error "%s" (format "only a lead runs the crew: %s isn't in it" name)))
         ((not (plist-get (agent-workspace-role agent) :leads))
          (user-error "%s" (format "only a lead runs the crew: %s's role, %s, doesn't lead"
                                   name (agent-workspace-agent-role agent))))
         (t name))))))

(defun agent-workspace--request-target (project payload key what)
  "The agent of PROJECT's crew PAYLOAD's KEY names: a user error if none
\(WHAT: the operation, its usage)."
  (let ((name (plist-get payload key)))
    (unless (and (stringp name) (not (string-empty-p name)))
      (user-error "%s" what))
    (or (agent-workspace-agent name project)
        (user-error "No agent %s in this crew%s" name
                    (if-let* ((names (mapcar #'agent-workspace-agent-name (agent-workspace-agents project))))
                        (concat "; agents: " (string-join names ", "))
                      "")))))

(defun agent-workspace--request-said (project actor kind target text)
  "What ACTOR did to the agent TARGET, TEXT, said in PROJECT's room: an
entry of KIND."
  (when (fboundp 'agent-workspace-room-post)
    (agent-workspace-room-post project :kind kind :agent actor :to (agent-workspace-agent-name target)
                               :text text)))

(defun agent-workspace--request-issue (project actor id)
  "Issue ID of PROJECT as bd shows it (as ACTOR): a plist, :id, :title,
:type, :status. A user error if bd doesn't know it, it's closed, an epic,
or there's no bd or Beads there."
  (let ((result (agent-workspace--bd-now project actor (list "show" id "--json"))))
    (pcase result
      ('nil (user-error "%s" (format "%s doesn't track its issues with Beads: no issue to give"
                                     (file-name-nondirectory (directory-file-name project)))))
      (`(timeout . ,_) (user-error "%s not given: bd didn't answer" id))
      (`(0 . ,output)
       (let* ((data (ignore-errors
                      (with-temp-buffer
                        (insert output)
                        (goto-char (point-min))
                        ;; Its JSON, after anything bd said on stderr.
                        (when (re-search-forward "^[[{]" nil t)
                          (json-parse-string (buffer-substring (match-beginning 0) (point-max))
                                             :object-type 'plist :array-type 'list
                                             :null-object nil :false-object nil)))))
              (issue (if (and (consp data) (not (keywordp (car data)))) (car data) data)))
         (unless (and (consp issue) (equal (plist-get issue :id) id))
           (user-error "No issue %s here" id))
         (when (equal (plist-get issue :status) "closed")
           (user-error "%s is closed" id))
         (when (equal (plist-get issue :issue_type) "epic")
           (user-error "%s is an epic: give one of its issues" id))
         (list :id id :title (plist-get issue :title) :type (plist-get issue :issue_type)
               :status (plist-get issue :status))))
      (`(,_ . ,output)
       (if (string-match-p "not found" output)
           (user-error "No issue %s here" id)
         (user-error "%s: %s" id (agent-workspace--bd-why output)))))))

(defun agent-workspace--request-give (directory payload)
  "Give an issue to an agent of DIRECTORY's project, as PAYLOAD (a plist)
says, as t does: the reply, a plist."
  (let* ((project (agent-workspace--request-project directory))
         (actor (agent-workspace--request-actor project payload))
         (id (plist-get payload :issue))
         (agent (agent-workspace--request-target project payload :to "give: to whom? give ISSUE --to NAME"))
         (name (agent-workspace-agent-name agent)))
    (unless (and (stringp id) (not (string-empty-p id)))
      (user-error "give: which issue? give ISSUE --to NAME"))
    (unless (agent-workspace-live-p agent)
      (user-error "%s not given to %s: %s is %s" id name name (agent-workspace-state-text agent)))
    (let* ((issue (agent-workspace--request-issue project actor id))
           (how (agent-workspace-give-issue agent id (plist-get issue :title) (plist-get issue :type))))
      (agent-workspace--ready-given project id name)
      (agent-workspace--request-said project actor 'issue agent (format "gave %s to %s" id name))
      (append (list :ok t) (agent-workspace--request-agent agent)
              (list :issue id :prompt (if (eq how 'queued) "queued" "sent"))))))

(defun agent-workspace--request-wake (directory payload)
  "Wake an agent of DIRECTORY's project (asleep or gone home), as PAYLOAD
\(a plist) says, as Z does: the reply, a plist."
  (let* ((project (agent-workspace--request-project directory))
         (actor (agent-workspace--request-actor project payload))
         (agent (agent-workspace--request-target project payload :name "wake: whom? wake NAME")))
    (agent-workspace-wake agent)
    (agent-workspace--request-said project actor 'note agent (format "woke %s" (agent-workspace-agent-name agent)))
    (cons :ok (cons t (agent-workspace--request-agent agent)))))

(defun agent-workspace--request-sleep (directory payload)
  "Put an agent of DIRECTORY's project to sleep, as PAYLOAD (a plist) says,
as Z does: the reply, a plist. Not one that doesn't run, nor the lead
asking (its own session would end with its command)."
  (let* ((project (agent-workspace--request-project directory))
         (actor (agent-workspace--request-actor project payload))
         (agent (agent-workspace--request-target project payload :name "sleep: whom? sleep NAME"))
         (name (agent-workspace-agent-name agent)))
    (unless (agent-workspace-live-p agent)
      (user-error "%s is %s" name (agent-workspace-state-text agent)))
    (when (equal actor name)
      (user-error "%s" (format "%s can't put itself to sleep: its session would end with this command" name)))
    (agent-workspace-sleep agent)
    (agent-workspace--request-said project actor 'note agent (format "put %s to sleep" name))
    (cons :ok (cons t (agent-workspace--request-agent agent)))))

(defun agent-workspace--request-loop (directory payload)
  "Turn the loop of an agent of DIRECTORY's project on or off, as PAYLOAD
\(a plist, :on) says, as L does: the reply, a plist. Said in the room only
if it changed."
  (let* ((project (agent-workspace--request-project directory))
         (actor (agent-workspace--request-actor project payload))
         (agent (agent-workspace--request-target project payload :name "loop: whose? loop NAME on|off"))
         (name (agent-workspace-agent-name agent))
         (on (plist-get payload :on)))
    (unless (plist-member payload :on)
      (user-error "loop: on or off? loop NAME on|off"))
    (unless (eq (and on t) (and (agent-workspace-agent-loop agent) t))
      (agent-workspace-loop-set agent on)
      (agent-workspace--request-said project actor 'note agent
                                     (format "turned %s's loop %s" name (if on "on" "off"))))
    (append (list :ok t) (agent-workspace--request-agent agent)
            (list :loop (if (agent-workspace-agent-loop agent) t :false)))))

(defun agent-workspace-request (dir)
  "Answer cmd/agent-workspace's request in DIR (see the top of this file):
its reply written to DIR/reply. Return t."
  (let* ((lines (split-string (with-temp-buffer
                                (insert-file-contents (expand-file-name "request" dir))
                                (buffer-string))
                              "\n"))
         (op (nth 0 lines))
         (directory (nth 1 lines))
         (pid (and (nth 2 lines) (string-match-p "\\`[0-9]+\\'" (nth 2 lines)) (string-to-number (nth 2 lines))))
         (agent-workspace--request-from (ignore-errors (agent-workspace--request-caller pid)))
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
                  ("status" (agent-workspace--request-status directory))
                  ("give" (agent-workspace--request-give directory payload))
                  ("wake" (agent-workspace--request-wake directory payload))
                  ("sleep" (agent-workspace--request-sleep directory payload))
                  ("loop" (agent-workspace--request-loop directory payload))
                  (_ (list :ok :false
                           :error (format "unknown operation %S; operations: %s" op
                                          "new, crew, send, status, give, wake, sleep, loop")))))
            (json-parse-error (list :ok :false :error (format "not JSON: %s" (error-message-string err))))
            (error (list :ok :false :error (error-message-string err))))))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file (expand-file-name "reply" dir)
        (insert (json-serialize reply) "\n")))
    t))
