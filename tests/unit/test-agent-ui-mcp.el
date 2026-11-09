;;; tests/unit/test-agent-ui-mcp.el -*- lexical-binding: t; -*-
;; cmd/agent-ui-mcp.el and its place in config/agent-ui.el: Agent UI as MCP
;; tools. The protocol (initialize, tools/list, tools/call, errors), each tool
;; as the command line it runs; then the server itself, a batch Emacs as the
;; agent starts it, its calls answered by a server started in this test Emacs
;; (never the user's); its registration for agent-shell's sessions.

(require 'server)
(+test-load "config/agent-ui")
(require 'agent-shell)
(load (expand-file-name "cmd/agent-ui-mcp.el" +test-root) nil t)

;; ====== HELPERS ======

(defvar +test-aum-sent nil "The messages the server sent, the latest first.")
(defvar +test-aum-runs nil "The command lines it ran (their arguments), the latest first.")

(defmacro +test-aum (reply &rest body)
  "BODY with what the server sends recorded, cmd/agent-ui not run but
recorded, its reply REPLY (a plist)."
  (declare (indent 1))
  `(let ((+test-aum-sent nil) (+test-aum-runs nil))
     (cl-letf (((symbol-function 'agent-ui-mcp--send)
                (lambda (m) (push (json-parse-string (agent-ui-mcp--json m) :object-type 'plist
                                                     :null-object nil :false-object :false)
                                  +test-aum-sent)))
               ((symbol-function 'agent-ui-mcp--run)
                (lambda (args) (push args +test-aum-runs) ,reply)))
       ,@body)))

(defun +test-aum-handle (json)
  (agent-ui-mcp-handle (json-parse-string json :object-type 'plist :null-object :null :false-object :false))
  (car +test-aum-sent))

;; ====== THE PROTOCOL ======

(ert-deftest agent-ui-mcp/initialize ()
  (+test-aum '(:ok t)
    (let ((answer (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\"}}")))
      (should (equal (plist-get answer :id) 1))
      (let ((result (plist-get answer :result)))
        ;; The client's version, its tools, its name, what it's for.
        (should (equal (plist-get result :protocolVersion) "2025-03-26"))
        (should (plist-get (plist-get result :capabilities) :tools))
        (should (equal (plist-get (plist-get result :serverInfo) :name) "agent-ui"))
        (should (string-match-p "canvas beside your session" (plist-get result :instructions)))))
    ;; A notification: no answer.
    (setq +test-aum-sent nil)
    (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")
    (should-not +test-aum-sent)
    (should (equal (plist-get (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}") :result) nil))
    (should (equal (plist-get (plist-get (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"nope\"}") :error) :code)
                   -32601))))

(ert-deftest agent-ui-mcp/the-tools ()
  (+test-aum '(:ok t :types [(:name "progress" :doc "A progress bar: VALUE of MAX.\nMore." :props [(:name "value" :kind "number")])])
    (let ((tools (append (plist-get (plist-get (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}") :result) :tools) nil)))
      (should (equal (mapcar (lambda (tool) (plist-get tool :name)) tools)
                     '("show" "update" "append" "remove" "clear" "list" "types" "render" "snapshot" "batch" "define")))
      ;; Each its schema; show's description has the types, from Emacs.
      (dolist (tool tools)
        (should (equal (plist-get (plist-get tool :inputSchema) :type) "object")))
      (should (string-match-p "^- progress: A progress bar: VALUE of MAX\\. Properties: value (number)\\.$"
                              (plist-get (car tools) :description)))
      (should (equal (plist-get (plist-get (car tools) :inputSchema) :required) ["element"]))
      ;; Another canvas of the session: an argument of each tool that has one.
      (dolist (tool tools)
        (should (eq (and (plist-get (plist-get (plist-get tool :inputSchema) :properties) :canvas) t)
                    (not (member (plist-get tool :name) '("types" "define")))))))))

(ert-deftest agent-ui-mcp/each-tool-a-command-line ()
  (+test-aum '(:ok t :id "b")
    (cl-flet ((call (name arguments)
                (+test-aum-handle (format "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":%S,\"arguments\":%s}}"
                                          name arguments))
                (car +test-aum-runs)))
      (should (equal (call "show" "{\"element\":{\"id\":\"b\",\"type\":\"progress\",\"rows\":[[\"a\",null]],\"x\":false}}")
                     '("show" "{\"id\":\"b\",\"type\":\"progress\",\"rows\":[[\"a\",null]],\"x\":false}")))
      (should (equal (call "update" "{\"id\":\"b\",\"patch\":{\"value\":3,\"label\":null}}")
                     '("update" "b" "{\"value\":3,\"label\":null}")))
      (should (equal (call "append" "{\"id\":\"t\",\"patch\":{\"rows\":[[\"x\"]]}}")
                     '("append" "t" "{\"rows\":[[\"x\"]]}")))
      (should (equal (call "remove" "{\"id\":\"b\"}") '("remove" "b")))
      (should (equal (call "snapshot" "{\"id\":\"b\"}") '("snapshot" "b")))
      (should (equal (call "clear" "{}") '("clear")))
      (should (equal (call "list" "{}") '("list")))
      (should (equal (call "types" "{}") '("types")))
      (should (equal (call "types" "{\"type\":\"table\"}") '("types" "table")))
      (should (equal (call "render" "{\"element\":{\"type\":\"text\",\"text\":\"ü\"}}")
                     '("render" "{\"type\":\"text\",\"text\":\"ü\"}")))
      (should (equal (call "remove" "{\"id\":\"b\",\"canvas\":\"tests\"}") '("remove" "b" "--canvas" "tests")))
      (should (equal (call "types" "{\"canvas\":\"tests\"}") '("types")))
      (should (equal (call "batch" "{\"operations\":[{\"op\":\"remove\",\"id\":\"b\"}]}")
                     '("batch" "[{\"op\":\"remove\",\"id\":\"b\"}]")))
      ;; A type's code: in a file, gone after.
      (let ((run (call "define" "{\"code\":\"(agent-ui-define x)\"}")))
        (should (equal (car run) "define"))
        (should-not (file-exists-p (cadr run))))
      ;; Its reply, as the result's text; not an error.
      (let ((result (plist-get (car +test-aum-sent) :result)))
        (should (equal (plist-get (aref (plist-get result :content) 0) :text) "{\"ok\":true,\"id\":\"b\"}"))
        (should (eq (plist-get result :isError) :false)))))
  ;; Not done: an error, its reply saying why.
  (+test-aum '(:ok :false :error "no element \"z\"")
    (let ((result (plist-get (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"remove\",\"arguments\":{\"id\":\"z\"}}}")
                             :result)))
      (should (eq (plist-get result :isError) t))
      (should (string-match-p "no element" (plist-get (aref (plist-get result :content) 0) :text))))
    (should (string-match-p "unknown tool frob"
                            (plist-get (aref (plist-get (plist-get (+test-aum-handle "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"frob\",\"arguments\":{}}}") :result) :content) 0) :text)))))

;; ====== THE SERVER ITSELF ======

(defun +test-aum-serve (lines)
  "The server, as the agent starts it, given LINES on stdin: its answers,
parsed."
  (let* ((output (generate-new-buffer " *mcp*"))
         (process (make-process :name "agent-ui-mcp" :buffer output
                                :command (list (expand-file-name invocation-name invocation-directory)
                                               "--batch" "-Q" "-l"
                                               (expand-file-name "cmd/agent-ui-mcp.el" +test-root)
                                               "-f" "agent-ui-mcp-main")
                                :connection-type 'pipe :noquery t :sentinel #'ignore
                                :coding 'utf-8
                                :stderr (get-buffer-create " *mcp-stderr*"))))
    (process-send-string process (concat (string-join lines "\n") "\n"))
    (process-send-eof process)
    (with-timeout (30 (delete-process process) (ert-fail "The MCP server didn't end"))
      (while (process-live-p process)
        (accept-process-output nil 0.02)))
    (prog1 (mapcar (lambda (line) (json-parse-string line :object-type 'plist :null-object nil :false-object :false))
                   (split-string (with-current-buffer output (buffer-string)) "\n" t))
      (kill-buffer output))))

(ert-deftest agent-ui-mcp/the-server ()
  (let* ((agent-ui-default-canvas (make-temp-name "mcp-"))
         (agent-ui-display-function #'ignore)
         (server-socket-dir (make-temp-file "/tmp/aui-mcp-" t))
         (server-name "test")
         (process-environment
          (append (list (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                        (concat "AGENT_UI_SESSION=" agent-ui-default-canvas))
                  process-environment)))
    (unwind-protect
        (progn
          (server-start nil t)
          (let ((answers (+test-aum-serve
                          (list "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}"
                                "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"
                                "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"show\",\"arguments\":{\"element\":{\"id\":\"t\",\"type\":\"text\",\"text\":\"ünïcødé ✓ 日本\"}}}}"
                                "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"render\",\"arguments\":{\"element\":{\"type\":\"table\",\"columns\":[\"A\"],\"rows\":[[\"x\"]]}}}}"
                                "not json"))))
            (should (equal (mapcar (lambda (a) (plist-get a :id)) answers) '(1 2 3 4 nil)))
            ;; tools/list: the types, asked of this Emacs.
            (should (string-match-p "^- table: "
                                    (plist-get (aref (plist-get (plist-get (nth 1 answers) :result) :tools) 0) :description)))
            ;; show: on the session's canvas, its text whole.
            (should (eq (plist-get (plist-get (nth 2 answers) :result) :isError) :false))
            (should (equal (plist-get (agent-ui-get "t") :text) "ünïcødé ✓ 日本"))
            ;; render: its drawing back, box characters and all.
            (should (equal (plist-get (json-parse-string
                                       (plist-get (aref (plist-get (plist-get (nth 3 answers) :result) :content) 0) :text)
                                       :object-type 'plist)
                                      :text)
                           " A\n──\n x"))
            (should (equal (plist-get (plist-get (nth 4 answers) :error) :code) -32700))))
      (server-force-delete)
      (delete-directory server-socket-dir t)
      (when (get-buffer (agent-ui-canvas-buffer-name agent-ui-default-canvas))
        (kill-buffer (agent-ui-canvas-buffer-name agent-ui-default-canvas))))))

;; ====== FOR EACH SESSION ======

(ert-deftest agent-ui-mcp/for-each-session ()
  (should +my/agent-ui-mcp)
  (should agent-ui-agent-mcp)
  (let ((server (seq-find (lambda (s) (equal (alist-get 'name s) "agent-ui")) agent-shell-mcp-servers)))
    (should server)
    ;; This Emacs, in batch, the server's file.
    (should (equal (alist-get 'command server) (expand-file-name invocation-name invocation-directory)))
    (should (equal (alist-get 'args server)
                   (list "--batch" "-Q" "-l" (expand-file-name "cmd/agent-ui-mcp.el" +test-root)
                         "-f" "agent-ui-mcp-main")))
    ;; Its environment, read in the session's buffer when it starts.
    (let ((session (generate-new-buffer "Claude Agent @ test")))
      (unwind-protect
          (with-current-buffer session
            (setq default-directory "/tmp/proj/")
            (let ((env (agent-shell--eval-dynamic-values (alist-get 'env server))))
              (should (equal env '(((name . "AGENT_UI_SESSION") (value . "Claude Agent @ test"))
                                   ((name . "AGENT_UI_DIR") (value . "/tmp/proj/")))))))
        (kill-buffer session))))
  ;; Registered again: replaced, not added.
  (let ((agent-shell-mcp-servers (list '((name . "other")))))
    (+my/agent-ui-mcp-register)
    (+my/agent-ui-mcp-register)
    (should (equal (mapcar (lambda (s) (alist-get 'name s)) agent-shell-mcp-servers) '("other" "agent-ui"))))
  ;; Its system prompt says so.
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
    (should (string-match-p "MCP tools too" (agent-ui-agent-context)))))
