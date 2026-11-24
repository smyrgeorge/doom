;;; $DOOMDIR/config/agent-workspace/session.el -*- lexical-binding: t; -*-
;; An agent's session. Loaded from config/agent-workspace.el, after core.el
;; and worktree.el. No Doom here.
;;
;; agent-shell's, started in its worktree with a config of its own (its name
;; on its buffer, its role's model, mode, tools and instructions, its
;; environment), its events moving its state (core.el), and stopped without a
;; question, leaving no process behind.

(require 'cl-lib)
(require 'subr-x)
(require 'map)

(declare-function agent-shell--start "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell-interrupt "agent-shell")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell--prompt-queue-enqueue "agent-shell-prompt-queue")
(declare-function agent-shell--prompt-queue-confirm-kill-buffer "agent-shell-prompt-queue")
(declare-function shell-maker-busy "shell-maker")
(declare-function shell-maker--process "shell-maker")
(defvar agent-shell--state)
(defvar agent-shell-mcp-servers)
(defvar agent-shell-buffer-name-format)
(defvar shell-maker-prompt-before-killing-buffer)
(defvar +my/agent-shell-permission-rules)

;; ====== VARIABLES ======

(defcustom agent-workspace-kinds
  '((claude-code :config agent-shell-anthropic-make-claude-code-config :claude-code t)
    (codex :config agent-shell-openai-make-codex-config)
    (gemini-cli :config agent-shell-google-make-gemini-config)
    (opencode :config agent-shell-opencode-make-agent-config)
    (qwen-code :config agent-shell-qwen-make-agent-config)
    (copilot :config agent-shell-github-make-copilot-config)
    (goose :config agent-shell-goose-make-agent-config)
    (cursor :config agent-shell-cursor-make-agent-config))
  "The agents a crew can have: a kind (a symbol: agent-shell's identifier
for it) and how its session starts. :config, a function returning
agent-shell's config for it; :claude-code, non-nil if it's Claude Code (its
role's tools go to Claude Code's options). A role says which (kind:), else
`agent-workspace-kind'."
  :type '(alist :key-type symbol :value-type plist)
  :group 'agent-workspace)

(defcustom agent-workspace-exit-timeout 7
  "Seconds a stopped session's processes have to exit, before any left is
killed (acp.el gives the agent's process group 5, then kills the group: this
catches what left the group)."
  :type 'number
  :group 'agent-workspace)

(defvar agent-workspace-session-functions nil
  "Called with an agent and its session's buffer, once its session started.")

(defvar agent-workspace--starting nil
  "The agent whose session starts, while its config is made (see
`agent-workspace-agent-context').")

(defvar-local agent-workspace--watched nil
  "In an agent's session: its agent's process, once watched for its end.")

;; ====== STARTING ======

(defun agent-workspace--start (agent)
  "Start AGENT's session, fresh, in its worktree (made again if it went): its
buffer, not shown. If it can't start, AGENT is stuck, saying why; a session
agent-shell made before the failure (a hook failing after) stopped, its
processes with it."
  (require 'agent-shell)
  (when (buffer-live-p (agent-workspace-agent-buffer agent))
    (agent-workspace--stop agent 'waking))
  (setf (agent-workspace-agent-buffer agent) nil)
  (agent-workspace--set-state agent 'waking)
  (let ((made nil))
    (condition-case err
        (let* ((dir (agent-workspace-worktree-ensure agent))
               (config (let ((agent-workspace--starting agent))
                         (agent-workspace--config agent)))
               ;; Its buffer named as its config says: "ada · builder".
               (agent-shell-buffer-name-format (lambda (name _project) name))
               ;; Its kind's welcome (Claude Code's banner) as any
               ;; agent-shell buffer's: `agent-shell-show-welcome-message'.
               ;; What it's told worked out as it starts, it bound
               ;; (`agent-workspace-agent-context').
               (buffer (setq made (let ((agent-workspace--starting agent))
                                    (agent-shell--start :config config :no-focus t :new-session t
                                                        :session-strategy 'new :cwd dir)))))
          (with-current-buffer buffer
            (setq agent-workspace--agent agent)
            ;; Stopping it asks nothing: not agent-shell's "N prompts
            ;; queued. Kill anyway?", nor shell-maker's to save its transcript,
            ;; nor Emacs's about its process when quitting.
            (remove-hook 'kill-buffer-query-functions #'agent-shell--prompt-queue-confirm-kill-buffer t)
            (setq-local shell-maker-prompt-before-killing-buffer nil)
            (when-let* ((process (ignore-errors (shell-maker--process))))
              (set-process-query-on-exit-flag process nil))
            (add-hook 'window-buffer-change-functions #'agent-workspace--shown-h nil t)
            ;; An agent other than Claude Code (which takes them as its
            ;; options): its role's tools and deny answer its permission
            ;; requests (config/agent-shell/permissions.el).
            (unless (plist-get (alist-get (agent-workspace-agent-kind agent) agent-workspace-kinds) :claude-code)
              (let ((role (agent-workspace-role-filled agent)))
                (setq-local +my/agent-shell-permission-rules
                            (list :tools (plist-get role :tools) :deny (plist-get role :deny))))))
          (setf (agent-workspace-agent-buffer agent) buffer)
          (agent-shell-subscribe-to
           :shell-buffer buffer
           :on-event (lambda (event)
                       ;; An old session's events, once it's been replaced, aren't its.
                       (when (eq (agent-workspace-agent-buffer agent) buffer)
                         (agent-workspace--watch-process agent buffer)
                         (agent-workspace--event agent event))))
          (run-hook-with-args 'agent-workspace-session-functions agent buffer)
          (agent-workspace--changed agent 'session)
          buffer)
      (error
       ;; Its error first: the state's hooks say it (the room's stuck line).
       (setf (agent-workspace-agent-error agent) (concat "its session: " (error-message-string err)))
       ;; Made before it failed: stopped, out of reach otherwise.
       (when (buffer-live-p made)
         (setf (agent-workspace-agent-buffer agent) made)
         (ignore-errors (agent-workspace--stop agent 'stuck)))
       (setf (agent-workspace-agent-buffer agent) nil)
       (agent-workspace--set-state agent 'stuck)
       (agent-workspace--changed agent 'state)
       (message "%s's session didn't start: %s" (agent-workspace-agent-name agent) (error-message-string err))
       nil))))

(defun agent-workspace-mode-of (agent)
  "The permission mode AGENT's session starts in (Claude Code's id): its own
\(e, C-u c), else its role's, else `agent-workspace-mode' (auto); nil,
Claude Code's own default."
  (or (agent-workspace-agent-mode agent) (plist-get (agent-workspace-role agent) :mode)
      agent-workspace-mode))

;; ====== ITS ROLE, FILLED IN ======
;; A role's tools, deny and instructions may name what's the agent's own,
;; in braces: {main} its project's main checkout, {main-branch} the branch
;; that's on, {name} the agent's name, {project} the main checkout's folder
;; name. Each is filled in, shell-quoted, as its session starts. A rule then
;; names the exact command, with no * where git's own options go (-c,
;; --exec-path: they'd run anything without a prompt): the reviewer's
;; Bash(git -C {main} merge --no-ff *). Its instructions say that command, so
;; it runs one its rules allow. Any other {word} is left as it is.

(defconst agent-workspace-role-placeholders '("main" "main-branch" "name" "project")
  "What a role's tools, deny and instructions may name in braces: see ITS
ROLE, FILLED IN.")

(declare-function agent-workspace-main-branch "agent-workspace/worktree")

(defun agent-workspace--placeholder (agent word)
  "AGENT's value of the placeholder WORD (\"main\"...), not quoted; nil if
it has none."
  (let ((project (directory-file-name (agent-workspace-agent-project agent))))
    (pcase word
      ("main" project)
      ("main-branch" (agent-workspace-main-branch project))
      ("name" (agent-workspace-agent-name agent))
      ("project" (file-name-nondirectory project)))))

(defun agent-workspace-role-filled (agent)
  "AGENT's role (a copy), its tools, deny and instructions with their
placeholders filled in (see ITS ROLE, FILLED IN)."
  (let* ((role (copy-sequence (agent-workspace-role agent)))
         (values nil)
         (fill (lambda (text)
                 (replace-regexp-in-string
                  "{\\([a-z-]+\\)}"
                  ;; replace-match runs on the match data REP leaves: a
                  ;; value's lookup mustn't change it.
                  (lambda (match)
                    (let ((word (match-string 1 match)))
                      (save-match-data
                        (or (and (member word agent-workspace-role-placeholders)
                                 (with-memoization (alist-get word values nil nil #'equal)
                                   (when-let* ((value (agent-workspace--placeholder agent word)))
                                     (shell-quote-argument value))))
                            match))))
                  text t t))))
    (dolist (key '(:tools :deny))
      (when (plist-get role key)
        (setq role (plist-put role key (mapcar fill (plist-get role key))))))
    (when (plist-get role :instructions)
      (setq role (plist-put role :instructions (funcall fill (plist-get role :instructions)))))
    role))

(defun agent-workspace--config (agent)
  "agent-shell's config for AGENT's session (see the top of this file)."
  (let* ((kind (or (alist-get (agent-workspace-agent-kind agent) agent-workspace-kinds)
                   (error "No such kind of agent: %s" (agent-workspace-agent-kind agent))))
         (role (agent-workspace-role-filled agent))
         (model (or (agent-workspace-agent-model agent) (plist-get role :model)))
         (mode (agent-workspace-mode-of agent))
         ;; A copy: the maker's own values (a quoted session meta) stay.
         (config (copy-tree (funcall (plist-get kind :config))))
         (maker (alist-get :client-maker config))
         (environment (agent-workspace--environment agent)))
    (setf (alist-get :buffer-name config) (agent-workspace-buffer-name agent))
    (when model
      (setf (alist-get :default-model-id config) (lambda () model)))
    (when mode
      (setf (alist-get :default-session-mode-id config) (lambda () mode)))
    (when-let* ((servers (plist-get role :mcp-servers)))
      (setf (alist-get :mcp-servers config)
            (append (bound-and-true-p agent-shell-mcp-servers) servers)))
    (when (plist-get kind :claude-code)
      (setf (alist-get :session-meta config)
            (agent-workspace--claude-options (alist-get :session-meta config) role)))
    ;; Its environment added to whatever the kind's client has.
    (when maker
      (setf (alist-get :client-maker config)
            (lambda (buffer)
              (let ((client (funcall maker buffer)))
                (when client
                  (setf (alist-get :environment-variables client)
                        (append environment (alist-get :environment-variables client))))
                client))))
    config))

(defun agent-workspace--claude-options (meta role)
  "META, Claude Code's session meta, with ROLE's tools in Claude Code's
options (allowedTools, disallowedTools). Its model goes through agent-shell
\(:default-model-id), checked by the agent."
  (let* ((claude (alist-get 'claudeCode meta))
         (options (alist-get 'options claude)))
    (when-let* ((tools (plist-get role :tools)))
      (setf (alist-get 'allowedTools options) (vconcat tools)))
    (when-let* ((deny (plist-get role :deny)))
      (setf (alist-get 'disallowedTools options) (vconcat deny)))
    (when options
      (setf (alist-get 'options claude) options
            (alist-get 'claudeCode meta) claude))
    meta))

(defun agent-workspace--environment (agent)
  "AGENT's environment variables (\"NAME=VALUE\"): its name for Beads
\(BEADS_ACTOR: who it is in the issues' history, the assignee of an issue it
claims) and for us (AGENT_WORKSPACE_AGENT); the project's issues (BEADS_DIR:
it works in a worktree)."
  (let ((name (agent-workspace-agent-name agent))
        (beads (expand-file-name ".beads" (agent-workspace-agent-project agent))))
    (append (list (concat "BEADS_ACTOR=" name)
                  (concat "AGENT_WORKSPACE_AGENT=" name))
            (when (file-directory-p beads)
              (list (concat "BEADS_DIR=" beads))))))

(defvar agent-workspace-context-functions nil
  "Called with the agent whose session starts: a paragraph more it's told
\(its crew and messages: messages.el), or nil.")

(defun agent-workspace-agent-context ()
  "What the agent whose session starts is told, after what every session
is: who it is and how it works (one whose role leads, that it runs the
crew on the user's word; the others, that they don't hand work to each
other), then its role's instructions. nil for any other session."
  (when-let* ((agent agent-workspace--starting))
    (let* ((name (agent-workspace-agent-name agent))
           (project (agent-workspace-agent-project agent))
           (role (agent-workspace-role-filled agent))
           (instructions (plist-get role :instructions)))
      (concat
       (format "You are %s, the %s in a crew of coding agents the user runs at once on \
%s, from Emacs (its agent workspace). Each agent has a name, a role and a colour. %s

You work in your own git worktree, %s: make your changes and commits there, never \
in the project's main checkout (%s), which is the user's. Each piece of work gets a \
branch of its own there, made and named for you as it starts (an issue's after its \
type, id and title: fix/doom-a1b-lexer-escapes). Commit on the branch you're on, and \
never switch, make or rename branches yourself. The user reviews each branch and \
merges it (or the crew's reviewer does). Your bd commands run as %s (BEADS_ACTOR), on \
the project's issues: an issue the user gives you, claim it as yourself. Your \
notifications carry your name already."
               name (agent-workspace-agent-role agent)
               (file-name-nondirectory (directory-file-name project))
               (if (plist-get role :leads)
                   "You run the crew for the user, on their word: you see it from your \
shell (cmd/agent-workspace status) and act on it (give an issue to an agent, wake one or \
put it to sleep, turn its loop on or off, message one) only when they ask you to, in your \
session or from the crew's room, and you answer them. Never start work by yourself."
                 "You work for the user: your work comes from them (in your session, from \
the crew's room, an issue they give you), and you answer them. Don't hand work to other \
agents or wait for them.")
               (directory-file-name (agent-workspace-agent-worktree agent))
               (directory-file-name project)
               name)
       (mapconcat (lambda (more) (concat "\n\n" more))
                  (delq nil (mapcar (lambda (function) (funcall function agent))
                                    agent-workspace-context-functions))
                  "")
       (when (and instructions (not (string-empty-p (string-trim instructions))))
         (concat "\n\n" (string-trim instructions)))))))

;; ====== WHILE IT RUNS ======

(defun agent-workspace--session-process (buffer)
  "The agent's process of the session BUFFER (its ACP client's), or nil."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((client (and (boundp 'agent-shell--state)
                               (map-elt agent-shell--state :client))))
        (map-elt client :process)))))

(defun agent-workspace--watch-process (agent buffer)
  "AGENT's process watched, once there is one: its end (not stopped by us)
sends AGENT home."
  (unless (buffer-local-value 'agent-workspace--watched buffer)
    (when-let* ((process (agent-workspace--session-process buffer)))
      (with-current-buffer buffer
        (setq agent-workspace--watched process))
      (add-function :after (process-sentinel process)
                    (lambda (process _event)
                      (when (and (not (process-live-p process))
                                 (eq (agent-workspace-agent-buffer agent) buffer)
                                 (not (agent-workspace-agent-stopping agent)))
                        (agent-workspace--set-state agent 'home)))))))

(defun agent-workspace--shown-h (window)
  "An agent's session shown in WINDOW: you looked (done becomes at the
desk). Buffer-local in `window-buffer-change-functions'."
  (when-let* ((agent (agent-workspace-buffer-agent (window-buffer window))))
    (agent-workspace-seen agent)))

(declare-function agent-ui-ask-question "agent-ui/ask")
(declare-function agent-ui-get "agent-ui/canvas")

(defun agent-workspace--question-waiting (session canvas id)
  "SESSION's turn ended with question ID waiting on its Agent UI CANVAS: its
agent raises its hand, asking it. In `agent-ui-question-waiting-functions'."
  (when-let* ((agent (agent-workspace-buffer-agent session)))
    (when (eq (agent-workspace-agent-buffer agent) session)
      (agent-workspace--raise-hand
       agent (list :kind 'question :canvas canvas :id id
                   :title (or (and (buffer-live-p canvas) (fboundp 'agent-ui-ask-question)
                                   (ignore-errors (agent-ui-ask-question (agent-ui-get id :canvas canvas))))
                              "a question on its canvas"))))))

(defvar-local agent-workspace--sent nil
  "In an agent's session: the prompts the app sent it (`agent-workspace-send')
not submitted yet. The room says what you send in a session as yours
\(room.el), not these: it said them already (a message from its compose
line), or they aren't yours (an issue given, a loop's next one, an event).
Those of a queue removed go (`agent-workspace--queue-removed-a'), and those
of a prompt steered, never said submitted
\(`agent-workspace--steer-request-a').")

(cl-defun agent-workspace-send (agent text &key submit no-branch)
  "Put TEXT in AGENT's prompt; SUBMIT: send it. Working, it gets it after
its turn (agent-shell's queue); still waking up, once it's ready.
NO-BRANCH: it's no work of its own (it's told something): the turn it
starts makes no branch for it at rest (worktree.el). Sent, it's the app's
\(`agent-workspace--not-sent-by-app'), not yours. Return `sent', `queued' or
`inserted'."
  (let ((buffer (agent-workspace--live-or-error agent))
        (done nil))
    (when (and submit no-branch)
      (agent-workspace-branch-quiet agent text))
    ;; Marked before it's sent: agent-shell says it's submitted as it sends
    ;; it, now or once the turn it waits for ends.
    (when submit
      (with-current-buffer buffer (push text agent-workspace--sent)))
    (unwind-protect
        (prog1
            (cond
             ((and submit (memq (agent-workspace-agent-state agent) '(working hand))
                   (with-current-buffer buffer (shell-maker-busy)))
              (with-current-buffer buffer
                (agent-shell--prompt-queue-enqueue :prompt text))
              'queued)
             (t
              (agent-shell-insert :text text :submit submit :no-focus t :shell-buffer buffer)
              (if submit 'sent 'inserted)))
          (setq done t))
      ;; Not sent: not waited for.
      (when (and submit (not done) (buffer-live-p buffer))
        (with-current-buffer buffer
          (setq agent-workspace--sent (cl-remove text agent-workspace--sent :test #'eq :count 1)))))))

(defun agent-workspace--part-at (whole part)
  "Where PART is in WHOLE as one of its parts, joined by blank lines (or as
all of it): (START . END), or nil."
  (let ((start 0)
        (found nil))
    (while (and (not found) (setq start (string-search part whole start)))
      (let ((end (+ start (length part))))
        (if (and (or (= start 0) (string-suffix-p "\n\n" (substring whole 0 start)))
                 (or (= end (length whole)) (string-prefix-p "\n\n" (substring whole end))))
            (setq found (cons start end))
          (setq start (1+ start)))))
    found))

(defun agent-workspace--queued ()
  "The prompts waiting in this session's queue (agent-shell's) for its turn's
end: each the very string queued."
  (and (local-variable-p 'agent-shell--state)
       (map-elt agent-shell--state :pending-prompts)))

(defun agent-workspace--not-sent-by-app (buffer prompt)
  "What of PROMPT, just submitted in the session BUFFER, the app didn't send
it (`agent-workspace-send'): all of it, or what's left once the app's are
taken out, each of their marks taken once (agent-shell sends the prompts
queued during a turn as one, joined by blank lines: one the app queued, and
one you typed meanwhile); nil if it's all the app's. A mark whose prompt
still waits in the queue isn't of PROMPT, whatever its text."
  (let ((left (string-trim prompt)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        ;; The turn it waited for interrupted (or failed), agent-shell keeps
        ;; the queue for a turn after; a message you send meanwhile isn't it.
        (let ((waiting (agent-workspace--queued)))
          (dolist (mark (reverse agent-workspace--sent))
            (when-let* (((not (memq mark waiting)))
                        (text (string-trim mark))
                        ((not (string-empty-p text)))
                        (at (agent-workspace--part-at left text)))
              (let ((before (string-trim-right (substring left 0 (car at))))
                    (after (string-trim-left (substring left (cdr at)))))
                (setq left (concat before (and (not (string-empty-p before)) (not (string-empty-p after)) "\n\n")
                                   after)
                      agent-workspace--sent (cl-remove mark agent-workspace--sent :test #'eq :count 1 :from-end t))))))))
    (unless (string-empty-p left) left)))

;; THE QUEUE DROPPED
;; agent-shell keeps its queue when a turn is interrupted or fails: it asks
;; whether to go on with it (interrupted), or says how to resume or remove it;
;; kept, it goes after the next turn that ends well (or on M-x
;; agent-shell-prompt-queue-resume). Removed (M-x
;; agent-shell-prompt-queue-remove, all of it or one), it's never sent, and
;; nothing says so (no event, no hook): the marks of the app's prompts in it
;; go then, or a message of yours with the same text would be taken for one
;; (not shown in the room).
(defun agent-workspace--sent-drop (buffer prompt)
  "The app's mark of PROMPT (its very string) in the session BUFFER gone, if
it's there: PROMPT was never sent, or never said submitted."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq agent-workspace--sent (cl-remove prompt agent-workspace--sent :test #'eq :count 1)))))

(defun agent-workspace--queue-removed-a (fn &rest args)
  "agent-shell's queued prompts removed: the marks of the app's among them go
\(see `agent-workspace--sent'). Around `agent-shell-prompt-queue-remove'."
  (let ((before (delq nil (mapcar (lambda (buffer)
                                    (when (buffer-local-value 'agent-workspace--sent buffer)
                                      (cons buffer (with-current-buffer buffer
                                                     (copy-sequence (agent-workspace--queued))))))
                                  (buffer-list)))))
    (unwind-protect (apply fn args)
      (pcase-dolist (`(,buffer . ,queued) before)
        (when (buffer-live-p buffer)
          (dolist (prompt (seq-difference queued (with-current-buffer buffer (agent-workspace--queued)) #'eq))
            (agent-workspace--sent-drop buffer prompt)))))))

(with-eval-after-load 'agent-shell-prompt-queue
  (advice-add 'agent-shell-prompt-queue-remove :around #'agent-workspace--queue-removed-a))

;; A QUEUED PROMPT STEERED INSTEAD
;; agent-shell's override at an empty prompt while the agent works (C-u RET)
;; offers the last queued prompt as a steer instead
;; (`agent-shell-busy-submit-reroute-queue-to-steer'): out of the queue, it's
;; sent into the running turn. Injected, or left to be submitted, it's said
;; submitted (input-submitted takes its mark). Declined, the turn interrupted,
;; it's dropped; started as a turn of its own, it's never said submitted; and
;; nothing says either (no event, no hook). A mark left would take a message
;; of yours with the same text (not shown in the room): an app's prompt
;; steered so loses its mark once the agent has answered the steer (or the
;; request failed), if input-submitted didn't take it then.
(defvar agent-workspace--steering nil
  "While agent-shell steers its last queued prompt instead, an app's: (PROMPT
. SESSION), PROMPT the very string the app queued.")

(defun agent-workspace--reroute-a (fn &rest args)
  "agent-shell steering its last queued prompt instead: an app's, noted for
`agent-workspace--steer-request-a'. Around
`agent-shell-busy-submit-reroute-queue-to-steer' (run in the session)."
  (let ((agent-workspace--steering
         (when-let* ((last (car (last (agent-workspace--queued))))
                     ((memq last agent-workspace--sent)))
           (cons last (current-buffer)))))
    (apply fn args)))

(defun agent-workspace--steer-request-a (fn &rest args)
  "The steering request of an app's prompt (`agent-workspace--steering'):
once the agent answers it (or it fails), after agent-shell has acted on the
answer, the prompt's mark goes if nothing took it. Around
`agent-shell--send-request'."
  (if-let* ((steering agent-workspace--steering)
            ((equal (map-elt (plist-get args :request) :method) "_session/steering")))
      (let ((success (plist-get args :on-success))
            (failure (plist-get args :on-failure))
            (done (lambda () (agent-workspace--sent-drop (cdr steering) (car steering)))))
        (setq agent-workspace--steering nil)
        ;; The first of a key wins: these over the ones in ARGS.
        (apply fn :on-success (lambda (response)
                                (unwind-protect (when success (funcall success response))
                                  (funcall done)))
               :on-failure (lambda (error raw)
                             (unwind-protect (when failure (funcall failure error raw))
                               (funcall done)))
               args))
    (apply fn args)))

(with-eval-after-load 'agent-shell-prompt-queue
  (advice-add 'agent-shell-busy-submit-reroute-queue-to-steer :around #'agent-workspace--reroute-a))
(with-eval-after-load 'agent-shell
  (advice-add 'agent-shell--send-request :around #'agent-workspace--steer-request-a))

;; ====== STOPPING ======
;; A session's buffer killed: agent-shell shuts its agent down (acp.el: the
;; agent's process group sent SIGTERM, then SIGKILL 5 s later). What it
;; started outside its group (a command in a session of its own) is found
;; first, and killed if it's still there `agent-workspace-exit-timeout' later.

(defun agent-workspace--process-table ()
  "Every process: (PID PPID START STATE)."
  (delq nil (mapcar (lambda (pid)
                      (when-let* ((attributes (process-attributes pid)))
                        (list pid (alist-get 'ppid attributes) (alist-get 'start attributes)
                              (alist-get 'state attributes))))
                    (list-system-processes))))

(defun agent-workspace--process-tree (pid table)
  "PID and its descendants in TABLE (`agent-workspace--process-table'), each
\(PID . START)."
  (let ((tree (list pid))
        (more t))
    (while more
      (setq more nil)
      (dolist (entry table)
        (when (and (memq (nth 1 entry) tree) (not (memq (car entry) tree)))
          (push (car entry) tree)
          (setq more t))))
    (delq nil (mapcar (lambda (pid)
                        (when-let* ((entry (assq pid table)))
                          (cons pid (nth 2 entry))))
                      tree))))

(defun agent-workspace--same-start-p (a b)
  "Non-nil if A and B, start times `process-attributes' gave for one pid,
are the same process's: under a second apart. On Linux Emacs works a
process's start out at each call, as now minus its time since boot (each
rounded to 1/100 s): two reads of one process differ by 10 ms now and
then. A pid used again starts later than that."
  (and a b (< (abs (float-time (time-subtract a b))) 1.0)))

(defun agent-workspace--alive-p (process)
  "Non-nil if PROCESS, (PID . START), still runs (the same one: not a pid
used again, nor a zombie)."
  (when-let* ((attributes (process-attributes (car process))))
    (and (agent-workspace--same-start-p (alist-get 'start attributes) (cdr process))
         (not (member (alist-get 'state attributes) '("Z" "X"))))))

(defun agent-workspace--reap (processes)
  "Kill PROCESSES, each (PID . START), still running."
  (dolist (process processes)
    (when (agent-workspace--alive-p process)
      (ignore-errors (signal-process (car process) 'SIGKILL)))))

(defun agent-workspace--stop (agent state &optional table)
  "Stop AGENT's session, if it runs, without asking; AGENT then in STATE.
TABLE: the processes now (`agent-workspace--process-table'), when several
are stopped at once. Return its processes, (PID . START) each, killed
`agent-workspace-exit-timeout' later if still running."
  (let ((buffer (agent-workspace-agent-buffer agent))
        processes)
    (setf (agent-workspace-agent-stopping agent) t)
    (unwind-protect
        (when (buffer-live-p buffer)
          (when-let* ((process (agent-workspace--session-process buffer))
                      (pid (and (process-live-p process) (process-id process))))
            (setq processes (agent-workspace--process-tree
                             pid (or table (agent-workspace--process-table)))))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer))
          (when processes
            (run-at-time agent-workspace-exit-timeout nil #'agent-workspace--reap processes)))
      (setf (agent-workspace-agent-stopping agent) nil
            (agent-workspace-agent-buffer agent) nil))
    (agent-workspace--set-state agent state)
    processes))

(defun agent-workspace--quit-h ()
  "Emacs quits: every crew closed, their processes given a second to exit,
then killed. In `kill-emacs-hook'."
  (let ((processes (agent-workspace-close-all))
        (deadline (+ (float-time) 1.0)))
    (while (and (seq-some #'agent-workspace--alive-p processes)
                (< (float-time) deadline))
      (sleep-for 0.05))
    (agent-workspace--reap processes)))

(add-hook 'kill-emacs-hook #'agent-workspace--quit-h)

(defun agent-workspace--no-question-a (fn &rest args)
  "agent-shell asking, as Emacs quits, about queued prompts: not the crews'
\(their sessions end with Emacs, asking nothing)."
  (let (held)
    (dolist (buffer (buffer-list))
      (when-let* ((agent (agent-workspace-buffer-agent buffer))
                  ((boundp 'agent-shell--state))
                  (state (buffer-local-value 'agent-shell--state buffer))
                  (prompts (map-elt state :pending-prompts)))
        (push (cons state prompts) held)
        (map-put! state :pending-prompts nil)))
    (unwind-protect (apply fn args)
      (dolist (entry held)
        (map-put! (car entry) :pending-prompts (cdr entry))))))

(with-eval-after-load 'agent-shell-prompt-queue
  (advice-add 'agent-shell--prompt-queue-confirm-kill-emacs :around #'agent-workspace--no-question-a))
