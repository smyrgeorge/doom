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
;;   "slow"        says so, works a second and a half, ends its turn
;;   "read FILE"   reads FILE (a tool call of kind read, at its line 3), ends
;;   "edit FILE"   edits FILE (a tool call of kind edit; agent-shell writes it,
;;                 fs/write_text_file), ends its turn
;;   "child"       starts a child process (sleep 300, in a process group of its
;;                 own) and holds, saying its pid
;;   "fail"        fails the prompt (an error)
;;   "exit"        exits, as an agent that crashed
;;   else          answers "ok: PROMPT" and ends its turn
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
     ((string-match-p "slow" text)
      (mock-acp--say session "slowly")
      (sleep-for 1.5)
      (mock-acp--result id '(:stopReason "end_turn")))
     ((string-match-p "hold" text)
      (mock-acp--say session "holding")
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

(defun mock-acp--handle (message)
  "Handle MESSAGE, a JSON-RPC object (a hash table)."
  (let ((id (gethash "id" message))
        (method (gethash "method" message))
        (params (gethash "params" message)))
    (mock-acp--log `(:method ,(or method :null) :params ,(or params :null)))
    (pcase method
      ("initialize"
       (mock-acp--result id '(:protocolVersion 1
                              :agentCapabilities (:loadSession :false
                                                  :promptCapabilities (:image :false :embeddedContext :false))
                              :authMethods [])))
      ("session/new"
       ;; Claude Code's modes and models, as claude-agent-acp lists them.
       (mock-acp--result id '(:sessionId "mock-session"
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
                                                         (:modelId "haiku" :name "Haiku")]))))
      ("session/set_mode" (mock-acp--result id '()))
      ("session/set_model" (mock-acp--result id '()))
      ("session/prompt" (mock-acp--prompt id params))
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
