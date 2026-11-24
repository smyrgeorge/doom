;;; $DOOMDIR/examples/agent-workspace/stand-in.el -*- lexical-binding: t; -*-
;; A stand-in coding agent, for the agent workspace's example
;; (examples/agent-workspace.el) and its tests: it speaks ACP (JSON-RPC, a
;; message a line, on stdin and stdout), as claude-agent-acp does, so
;; agent-shell runs a real session with it, offline, at no cost. Run by a
;; batch Emacs (agent-shell's mock agent kind runs it):
;;
;;   emacs --batch -Q -l examples/agent-workspace/stand-in.el -f mock-acp-main
;;
;; What a prompt says decides what it does:
;;   "permission"  asks to run a tool (a permission request), runs it once
;;                 answered, ends its turn
;;   "Look into"   (at its start) the same: asks to run npm install
;;   "Work on ID: close..."  (an issue whose title starts with close, as a
;;                 loop gives one) closes ID with bd (as its BEADS_ACTOR, in
;;                 its BEADS_DIR), says so, ends its turn
;;   "Work on ID: fail..."  fails the prompt (an error)
;;   "Work on"     (at its start, else) says it's on it, then works until it's
;;                 cancelled (session/cancel); with a src/lexer.el where it
;;                 runs (the example's), reads it and starts editing it first
;;   "hold"        says so, then works until it's cancelled
;;   "background"  (at its start) says it runs a command in the background,
;;                 ends its turn; 2.5 seconds later, woken by it as Claude
;;                 Code is (a task notification), works with no prompt: a
;;                 tool call for a second, its answer, its model's result (a
;;                 usage update naming its origin), as claude-agent-acp sends
;;   "slow"        says so, works a second and a half, ends its turn
;;   "read FILE"   reads FILE (a tool call of kind read, at its line 3), ends
;;   "edit FILE"   edits FILE (a tool call of kind edit; agent-shell writes it,
;;                 fs/write_text_file), ends its turn
;;   "child"       starts a child process (sleep 300, in a process group of its
;;                 own) and holds, saying its pid
;;   "orphan"      starts a command it doesn't wait for (sleep 300, in a process
;;                 group of its own), which outlives it, and holds, saying its pid
;;   "fail"        fails the prompt (an error)
;;   "exit"        exits, as an agent that crashed
;;   else          answers "ok: PROMPT" and ends its turn
;; A prompt steered into its turn (_session/steering) is injected, or declined
;; when it says "decline".
;;
;; With MOCK_ACP_LOG set, every message it gets is appended to that file (a
;; JSON object a line: its agent, cwd, method, params), its environment when
;; it starts, and the branch its folder is on as each prompt comes, for the
;; tests to read.

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(defvar mock-acp--holding nil "The id of the prompt being held (until cancelled).")
(defvar mock-acp--asking nil "Our permission request's id and the prompt's: (OURS . PROMPT).")
(defvar mock-acp--next-id 1000 "The next id of a request of ours.")
(defvar mock-acp--writing nil "Our file write request's id and the prompt's: (OURS . PROMPT).")

(defun mock-acp--send (object)
  "Write OBJECT as a JSON line."
  (princ (concat (json-serialize object) "\n")))

(defun mock-acp--log (object)
  "Append OBJECT to MOCK_ACP_LOG, if set. No lock file: the crew's stand-ins
log to the same file at once, and a lock conflict can't be resolved in
batch (the stand-in would exit)."
  (when-let* ((file (getenv "MOCK_ACP_LOG")))
    (let ((create-lockfiles nil))
      (write-region (concat (json-serialize
                           `(:agent ,(or (getenv "AGENT_WORKSPACE_AGENT") :null)
                             :cwd ,(expand-file-name default-directory)
                             ,@object))
                          "\n")
                  nil file t 'silent))))

(defun mock-acp--result (id result)
  (mock-acp--send `(:jsonrpc "2.0" :id ,id :result ,result)))

(defun mock-acp--update (session update)
  (mock-acp--send `(:jsonrpc "2.0" :method "session/update"
                    :params (:sessionId ,session :update ,update))))

(defun mock-acp--say (session text)
  (mock-acp--update session `(:sessionUpdate "agent_message_chunk"
                              :content (:type "text" :text ,text))))

(defun mock-acp--prompt-text (params)
  "The text of a prompt's PARAMS."
  (mapconcat (lambda (block) (or (gethash "text" block) "")) (gethash "prompt" params) ""))

(defun mock-acp--prompt (id params)
  "Prompt ID with PARAMS: do what it says (see above)."
  (let ((session (gethash "sessionId" params))
        (text (mock-acp--prompt-text params)))
    (when (getenv "MOCK_ACP_LOG")
      (mock-acp--log `(:branch ,(or (car (process-lines-ignore-status "git" "branch" "--show-current")) :null))))
    (cond
     ((string-match "\\`read \\(.+\\)" text)
      (let ((file (expand-file-name (string-trim (match-string 1 text)))))
        (mock-acp--update session `(:sessionUpdate "tool_call" :toolCallId "r1" :title ,(concat "Read " file)
                                    :kind "read" :status "completed"
                                    :locations [(:path ,file :line 3)]))
        (mock-acp--say session (format "read %s" file))
        (mock-acp--result id '(:stopReason "end_turn"))))
     ((string-match "\\`edit \\(.+\\)" text)
      (let ((file (expand-file-name (string-trim (match-string 1 text))))
            (ours (cl-incf mock-acp--next-id)))
        (mock-acp--update session `(:sessionUpdate "tool_call" :toolCallId "e1" :title ,(concat "Edit " file)
                                    :kind "edit" :status "in_progress"
                                    :locations [(:path ,file :line 1)]))
        (setq mock-acp--writing (cons ours id))
        (mock-acp--send `(:jsonrpc "2.0" :id ,ours :method "fs/write_text_file"
                          :params (:sessionId ,session :path ,file :content "edited by the stand-in\n")))))
     ((string-match "\\`Work on \\([^ :]+\\): close" text)
      (let* ((issue (match-string 1 text))
             (status (call-process "bd" nil nil nil "close" issue)))
        (mock-acp--log `(:closed ,issue :status ,status))
        (mock-acp--say session (if (eql status 0) (format "closed %s" issue) (format "couldn't close %s" issue)))
        (mock-acp--result id '(:stopReason "end_turn"))))
     ((string-match-p "\\`Work on [^ :]+: fail" text)
      (mock-acp--send `(:jsonrpc "2.0" :id ,id :error (:code -32603 :message "mock failure"))))
     ((string-match-p "\\`Work on" text)
      ;; In the example's project: reads the lexer, starts editing it.
      (when (file-exists-p "src/lexer.el")
        (let ((file (expand-file-name "src/lexer.el")))
          (mock-acp--update session `(:sessionUpdate "tool_call" :toolCallId "w1" :title ,(concat "Read " file)
                                      :kind "read" :status "completed" :locations [(:path ,file :line 1)]))
          (mock-acp--update session `(:sessionUpdate "tool_call" :toolCallId "w2" :title ,(concat "Edit " file)
                                      :kind "edit" :status "in_progress" :locations [(:path ,file :line 12)]))))
      (mock-acp--say session "On it: reading the code first, then the tests.")
      (setq mock-acp--holding id))
     ((or (string-match-p "permission" text) (string-match-p "\\`Look into" text))
      (mock-acp--update session '(:sessionUpdate "tool_call" :toolCallId "t1"
                                  :title "npm install" :kind "execute" :status "pending"))
      (let ((ours (cl-incf mock-acp--next-id)))
        (setq mock-acp--asking (cons ours id))
        (mock-acp--send
         `(:jsonrpc "2.0" :id ,ours :method "session/request_permission"
           :params (:sessionId ,session
                    :toolCall (:toolCallId "t1" :title "npm install" :kind "execute" :status "pending")
                    :options [(:optionId "allow" :name "Allow" :kind "allow_once")
                              (:optionId "reject" :name "Reject" :kind "reject_once")])))))
     ((string-match-p "\\`background" text)
      (mock-acp--say session "running the suite in the background")
      (mock-acp--result id '(:stopReason "end_turn"))
      ;; Woken by its task, out of any turn. What it wrote sent first (a
      ;; batch Emacs's stdout to a pipe is written out when it reads).
      (send-string-to-terminal "")
      (sleep-for 2.5)
      (mock-acp--update session '(:sessionUpdate "tool_call" :toolCallId "b1" :title "git log -1"
                                  :kind "execute" :status "in_progress"))
      (send-string-to-terminal "")
      (sleep-for 1)
      (mock-acp--update session '(:sessionUpdate "tool_call_update" :toolCallId "b1" :status "completed"))
      (mock-acp--say session "the suite passed")
      (mock-acp--update session '(:sessionUpdate "usage_update" :used 1000 :size 200000
                                  :cost (:amount 0.01 :currency "USD")
                                  :_meta (:_claude/origin (:kind "task-notification")))))
     ((string-match-p "slow" text)
      (mock-acp--say session "slowly")
      (sleep-for 1.5)
      (mock-acp--result id '(:stopReason "end_turn")))
     ((string-match-p "hold" text)
      (mock-acp--say session "holding")
      (setq mock-acp--holding id))
     ((string-match-p "orphan" text)
      ;; Not a process of its own (Emacs exiting kills those): call-process
      ;; with 0, its child all the same, outliving it, out of its group.
      (let ((file (make-temp-file "mock-acp-orphan-"))
            (end (+ (float-time) 5))
            pid)
        (call-process "perl" nil 0 nil "-e"
                      "setpgrp(0,0); open(my $f, '>', $ARGV[0]); print $f $$; close $f; exec q(sleep), 300"
                      file)
        (while (and (not pid) (< (float-time) end))
          (sleep-for 0.02)
          (setq pid (with-temp-buffer
                      (insert-file-contents file)
                      (and (> (buffer-size) 0) (string-to-number (buffer-string))))))
        (delete-file file)
        (mock-acp--log `(:orphan ,(or pid :null)))
        (mock-acp--say session (format "orphan %s" pid)))
      (setq mock-acp--holding id))
     ((string-match-p "child" text)
      ;; A child of its own, in a process group of its own (as a command
      ;; run in a session of its own): the agent's group signalled, it stays.
      (let ((pid (process-id (make-process :name "child" :connection-type 'pipe :noquery t
                                           :command '("perl" "-e" "setpgrp(0,0); exec q(sleep), 300")))))
        (mock-acp--log `(:child ,pid))
        (mock-acp--say session (format "child %s" pid)))
      (setq mock-acp--holding id))
     ((string-match-p "fail" text)
      (mock-acp--send `(:jsonrpc "2.0" :id ,id :error (:code -32603 :message "mock failure"))))
     ((string-match-p "exit" text)
      (kill-emacs 3))
     (t
      (mock-acp--say session (format "ok: %s" text))
      (mock-acp--result id '(:stopReason "end_turn"))))))

(defun mock-acp--config-options (effort)
  "Claude Code's config options as claude-agent-acp lists them (its effort
only), EFFORT its effort now."
  (vector (list :id "effort" :name "Effort" :category "thought_level" :type "select" :currentValue effort
                :options (vconcat (mapcar (lambda (level) (list :value level :name (capitalize level)))
                                          '("default" "low" "medium" "high" "xhigh" "max"))))))

(defun mock-acp--handle (message)
  "Handle MESSAGE, a JSON-RPC object (a hash table)."
  (let ((id (gethash "id" message))
        (method (gethash "method" message))
        (params (gethash "params" message)))
    ;; A response to its own request (a permission's): what was answered.
    (mock-acp--log `(:method ,(or method :null) :params ,(or params :null)
                     ,@(when-let* ((result (and (null method) (gethash "result" message)))) (list :result result))))
    (pcase method
      ("initialize"
       ;; A system prompt from Emacs taken, as claude-agent-acp does, unless
       ;; MOCK_ACP_NO_SYSTEM_PROMPT says not (an agent that takes none).
       (mock-acp--result id `(:protocolVersion 1
                              :agentCapabilities (:loadSession :false
                                                  :promptCapabilities (:image :false :embeddedContext :false)
                                                  ,@(unless (getenv "MOCK_ACP_NO_SYSTEM_PROMPT")
                                                      '(:sessionCapabilities (:systemPrompt (:mode "append")))))
                              :authMethods [])))
      ("session/new"
       ;; Claude Code's modes and models, as claude-agent-acp lists them.
       (mock-acp--result id `(:sessionId "mock-session"
                              :modes (:currentModeId "default"
                                      :availableModes [(:id "default" :name "Default")
                                                       (:id "acceptEdits" :name "Accept Edits")
                                                       (:id "plan" :name "Plan Mode")
                                                       (:id "auto" :name "Auto")
                                                       (:id "dontAsk" :name "Don't Ask")
                                                       (:id "bypassPermissions" :name "Bypass Permissions")])
                              :models (:currentModelId "default"
                                       :availableModels [(:modelId "default" :name "Default")
                                                         (:modelId "opus" :name "Opus")
                                                         (:modelId "sonnet" :name "Sonnet")
                                                         (:modelId "haiku" :name "Haiku")])
                              ;; Its effort, as claude-agent-acp offers it.
                              :configOptions ,(mock-acp--config-options "default"))))
      ("session/set_mode" (mock-acp--result id '()))
      ("session/set_model" (mock-acp--result id '()))
      ("session/set_config_option"
       (mock-acp--result id (list :configOptions (mock-acp--config-options (gethash "value" params)))))
      ("session/prompt" (mock-acp--prompt id params))
      ("_session/steering"
       ;; A prompt steered into the running turn (agent-shell sends one only
       ;; to an agent saying it can: a test says so for it): declined when it
       ;; says "decline", else injected.
       (mock-acp--result id (list :outcome (if (string-match-p "decline" (mock-acp--prompt-text params))
                                               "failed"
                                             "injected"))))
      ("session/cancel"
       (when mock-acp--asking
         (setq mock-acp--holding (cdr mock-acp--asking)
               mock-acp--asking nil))
       (when mock-acp--holding
         (mock-acp--result mock-acp--holding '(:stopReason "cancelled"))
         (setq mock-acp--holding nil)))
      ('nil
       ;; A response to our file write: the edit done, the turn ends.
       (when (and mock-acp--writing (equal id (car mock-acp--writing)))
         (let ((prompt (cdr mock-acp--writing)))
           (setq mock-acp--writing nil)
           (mock-acp--update "mock-session" '(:sessionUpdate "tool_call_update" :toolCallId "e1"
                                              :status "completed"))
           (mock-acp--result prompt '(:stopReason "end_turn"))))
       ;; A response to our permission request: the tool runs, the turn ends.
       (when (and mock-acp--asking (equal id (car mock-acp--asking)))
         (let ((prompt (cdr mock-acp--asking)))
           (setq mock-acp--asking nil)
           (mock-acp--update "mock-session" '(:sessionUpdate "tool_call_update" :toolCallId "t1"
                                              :status "completed"))
           (mock-acp--say "mock-session" "ran it")
           (mock-acp--result prompt '(:stopReason "end_turn")))))
      (_
       (when id
         (mock-acp--send `(:jsonrpc "2.0" :id ,id
                           :error (:code -32601 :message ,(format "no method %s" method)))))))))

(defun mock-acp-main ()
  "Serve ACP on stdin and stdout until stdin closes."
  (mock-acp--log `(:start (:BEADS_ACTOR ,(or (getenv "BEADS_ACTOR") :null)
                           :BEADS_DIR ,(or (getenv "BEADS_DIR") :null)
                           :pid ,(emacs-pid))))
  (while t
    (let ((line (condition-case nil
                    (read-from-minibuffer "")
                  (error (kill-emacs 0)))))
      (unless (string-empty-p (string-trim line))
        (mock-acp--handle (json-parse-string line :null-object nil :false-object nil))))))
