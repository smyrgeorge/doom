;;; cmd/agent-ui-mcp.el --- Agent UI as an MCP server -*- lexical-binding: t; -*-
;; Agent UI's operations as MCP tools, for an agent to discover with their
;; schemas (docs/agent-ui.md). A batch Emacs runs it, started by the agent for
;; its session (agent-shell's `agent-shell-mcp-servers', config/agent-ui.el):
;;
;;   emacs --batch -Q -l cmd/agent-ui-mcp.el -f agent-ui-mcp-main
;;
;; It speaks MCP over stdio (JSON-RPC, a message a line) and does each tool
;; call through cmd/agent-ui, beside it: the same operations, replies and
;; errors as the command line, reaching the user's Emacs with emacsclient.
;; AGENT_UI_SESSION says whose canvas; AGENT_UI_DIR the agent's directory
;; (its files', its sources'), else where it was started. Tools' descriptions
;; carry the element types, asked of the user's Emacs (agent-ui types).

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-mcp-command
  (expand-file-name "agent-ui" (file-name-directory (or load-file-name buffer-file-name)))
  "cmd/agent-ui: what each tool call runs.")

(defconst agent-ui-mcp-version "2025-06-18"
  "The MCP version it speaks (or the client's, if it asks for another).")

;; ====== THE TOOLS ======

(defconst agent-ui-mcp--canvas-schema
  '(:type "string" :description "Optional: another canvas of your session, by name (\"tests\"), in a pane of its own; without it, your session's canvas")
  "The canvas argument's schema.")

(defun agent-ui-mcp--with-canvas (tool)
  "TOOL (a tools/list entry) taking a canvas argument too."
  (let* ((schema (copy-sequence (plist-get tool :inputSchema)))
         (properties (copy-sequence (plist-get schema :properties))))
    (plist-put tool :inputSchema
               (plist-put schema :properties (plist-put properties :canvas agent-ui-mcp--canvas-schema)))))

(defconst agent-ui-mcp--element-schema
  '(:type "object"
    :description "An element: \"type\" (one of the types below), \"id\" (yours, to change it later), an optional \"title\", the type's properties, optionally a \"source\" (a command, file or poll it follows) and \"actions\" (buttons putting a prompt into your session's prompt: [{\"label\", \"prompt\", \"submit\"}])."
    :properties (:type (:type "string") :id (:type "string") :title (:type "string")
                 :source (:type "object"))
    :required ["type"]
    :additionalProperties t)
  "An element's schema: open, each type's properties in the description.")

(defun agent-ui-mcp--types-text ()
  "The element types, a line each (name: properties), from the user's Emacs;
nil if it can't be reached."
  (let ((reply (agent-ui-mcp--run (list "types"))))
    (when (eq (plist-get reply :ok) t)
      (mapconcat (lambda (type)
                   (format "- %s: %s. Properties: %s."
                           (plist-get type :name)
                           (car (split-string (replace-regexp-in-string "\n" " " (plist-get type :doc))
                                              "\\. "))
                           (mapconcat (lambda (p) (format "%s (%s)" (plist-get p :name) (plist-get p :kind)))
                                      (plist-get type :props) ", ")))
                 (plist-get reply :types) "\n"))))

(defun agent-ui-mcp--tools ()
  "The tools, as tools/list gives them."
  (let* ((types (agent-ui-mcp--types-text))
         (id '(:type "string" :description "The element's id"))
         (patch '(:type "object" :description "The properties to change (null: back to the default)"
                  :additionalProperties t)))
    (vconcat
     (mapcar
      (lambda (tool)
        (if (member (plist-get tool :name) '("types" "define"))
            tool
          (agent-ui-mcp--with-canvas tool)))
      (list
      (list :name "show"
            :description (concat "Show an element on the canvas beside your session (the user's Emacs); one with its id there already is replaced in place. For what changes over time or should stay in view: progress, a checklist, test results, a chart. Types:\n"
                                 (or types "(ask with the types tool)"))
            :inputSchema (list :type "object" :properties (list :element agent-ui-mcp--element-schema)
                               :required ["element"]))
      (list :name "update" :description "Change some of an element's properties, in place."
            :inputSchema (list :type "object" :properties (list :id id :patch patch) :required ["id" "patch"]))
      (list :name "append" :description "Add to an element's lists: a table's rows (by its key column: replaced), a checklist's steps (by name: changed), a chart's values."
            :inputSchema (list :type "object" :properties (list :id id :patch patch) :required ["id" "patch"]))
      (list :name "remove" :description "Remove an element."
            :inputSchema (list :type "object" :properties (list :id id) :required ["id"]))
      (list :name "clear" :description "Remove every element of the canvas."
            :inputSchema '(:type "object"))
      (list :name "list" :description "The canvas's elements: ids, types, their sources' state."
            :inputSchema '(:type "object"))
      (list :name "types" :description "The element types: their properties, an example each."
            :inputSchema '(:type "object" :properties (:type (:type "string" :description "One type only"))))
      (list :name "render" :description "An element drawn as text, as the canvas would, nothing shown: to see what it looks like."
            :inputSchema (list :type "object" :properties (list :element agent-ui-mcp--element-schema)
                               :required ["element"]))
      (list :name "snapshot" :description "An element as an image (SVG) in .agent-shell/images/: the reply's markdown, put in your reply, shows it in the conversation."
            :inputSchema (list :type "object" :properties (list :id id) :required ["id"]))
      (list :name "batch" :description "Several operations at once: [{\"op\": \"show\", ...element}, {\"op\": \"update\", \"id\": ..., ...patch}, {\"op\": \"append\", ...}, {\"op\": \"remove\", \"id\": ...}]."
            :inputSchema '(:type "object" :properties (:operations (:type "array" :items (:type "object")))
                           :required ["operations"]))
      (list :name "bug" :description "A bug in Agent UI itself (a wrong drawing, an error, a property missing), filed in its own issues, not this project's: ask the user first, then carry on with a workaround. Its title and description; what you expected and the workaround used; the element on the canvas showing it (its JSON and drawing go with it); a repro, an element with neutral data showing it (drawn as text). Replies with the issue; a similar open bug gets the report as a note (new: true files it anyway). Not filed (no issues set up): the reply's report, written, for the user to report by hand."
            :inputSchema '(:type "object"
                           :properties (:title (:type "string") :description (:type "string")
                                        :expected (:type "string") :workaround (:type "string")
                                        :element (:type "string" :description "The id of the element on the canvas showing it")
                                        :repro (:type "object" :description "An element showing it, with neutral data")
                                        :new (:type "boolean" :description "File it even if a similar bug is open"))
                           :required ["title" "description"]))
      (list :name "define" :description "A type of your own: Emacs Lisp code with one agent-ui-define and its definitions, each named agent-ui-NAME-... (see the agent-ui skill). Checked, compiled, loaded, its example drawn (the reply's preview); the user keeps or discards it."
            :inputSchema '(:type "object" :properties (:code (:type "string")) :required ["code"])))))))

;; ====== DOING A CALL ======

(defun agent-ui-mcp--json (value)
  "VALUE as JSON text (decoded: `json-serialize' gives UTF-8 bytes)."
  (decode-coding-string (json-serialize value :null-object :null :false-object :false) 'utf-8))

(defun agent-ui-mcp--run (args)
  "cmd/agent-ui with ARGS, in the agent's directory: its reply, parsed (or
an error reply if it said nothing readable)."
  (let ((default-directory (file-name-as-directory
                            (or (getenv "AGENT_UI_DIR") default-directory))))
    (with-temp-buffer
      (let* ((status (let ((coding-system-for-read 'utf-8))
                       (apply #'call-process agent-ui-mcp-command nil (list t nil) nil args)))
             (text (string-trim (buffer-string)))
             (text (if (multibyte-string-p text) text (decode-coding-string text 'utf-8))))
        (condition-case nil
            (json-parse-string text :object-type 'plist :null-object nil :false-object :false)
          (error (list :ok :false :error (format "cmd/agent-ui (exit %s): %s" status text))))))))

(defun agent-ui-mcp--call (name arguments)
  "Tool NAME with ARGUMENTS (a plist): (ERROR-P . TEXT)."
  (cl-flet ((arg (key) (plist-get arguments key))
            (json (value) (agent-ui-mcp--json value)))
    (let* ((canvas (let ((c (arg :canvas))) (and (stringp c) (not (string-empty-p c)) c)))
           (args (pcase name
                   ("show" (list "show" (json (arg :element))))
                   ("render" (list "render" (json (arg :element))))
                   ("update" (list "update" (or (arg :id) "") (json (or (arg :patch) (make-hash-table)))))
                   ("append" (list "append" (or (arg :id) "") (json (or (arg :patch) (make-hash-table)))))
                   ("remove" (list "remove" (or (arg :id) "")))
                   ("snapshot" (list "snapshot" (or (arg :id) "")))
                   ("clear" (list "clear"))
                   ("list" (list "list"))
                   ("types" (if (arg :type) (list "types" (arg :type)) (list "types")))
                   ("batch" (list "batch" (json (or (arg :operations) []))))
                   ;; The bug as given, but its canvas (an argument of its own).
                   ("bug" (list "bug" (json (cl-loop for (k v) on arguments by #'cddr
                                                     unless (eq k :canvas) append (list k v)))))))
           (reply
            (cond
             (args
              ;; Another canvas of the session, if it names one.
              (agent-ui-mcp--run (if (and canvas (not (equal name "types")))
                                     (append args (list "--canvas" canvas))
                                   args)))
             ((equal name "define")
              (let ((file (make-temp-file "agent-ui-type-" nil ".el")))
                (unwind-protect
                    (progn
                      (let ((coding-system-for-write 'utf-8))
                        (write-region (or (arg :code) "") nil file nil 'silent))
                      (agent-ui-mcp--run (list "define" file)))
                  (delete-file file))))
             (t (list :ok :false :error (format "unknown tool %s" name))))))
      (cons (not (eq (plist-get reply :ok) t)) (json reply)))))

;; ====== THE PROTOCOL ======

(defun agent-ui-mcp--send (message)
  (princ (agent-ui-mcp--json message))
  (terpri))

(defun agent-ui-mcp--answer (id result)
  (agent-ui-mcp--send (list :jsonrpc "2.0" :id id :result result)))

(defun agent-ui-mcp--fail (id code message)
  (agent-ui-mcp--send (list :jsonrpc "2.0" :id id :error (list :code code :message message))))

(defun agent-ui-mcp-handle (message)
  "Answer MESSAGE (a JSON-RPC request or notification, parsed)."
  (let ((id (plist-get message :id))
        (method (plist-get message :method))
        (params (plist-get message :params)))
    (pcase method
      ("initialize"
       (agent-ui-mcp--answer
        id (list :protocolVersion (or (plist-get params :protocolVersion) agent-ui-mcp-version)
                 :capabilities '(:tools (:listChanged :false))
                 :serverInfo '(:name "agent-ui" :version "1.0")
                 :instructions "Show things to the user in Emacs, on a canvas beside your session: progress bars, checklists, tables, charts, text, Markdown, images, pages, updated in place. Use it for what changes over time or deserves watching, not for what a reply says once. The agent-ui skill (skills/agent-ui/SKILL.md) has the details.")))
      ("ping" (agent-ui-mcp--answer id (make-hash-table)))
      ("tools/list" (agent-ui-mcp--answer id (list :tools (agent-ui-mcp--tools))))
      ("tools/call"
       (pcase-let ((`(,error-p . ,text) (agent-ui-mcp--call (plist-get params :name)
                                                            (plist-get params :arguments))))
         (agent-ui-mcp--answer id (list :content (vector (list :type "text" :text text))
                                        :isError (if error-p t :false)))))
      ;; Notifications (no id): nothing to say.
      ((guard (memq id '(nil :null))))
      (_ (agent-ui-mcp--fail id -32601 (format "Method not found: %s" method))))))

(defun agent-ui-mcp-main ()
  "Serve MCP on stdin and stdout until stdin ends."
  ;; UTF-8 both ways, whatever the locale.
  (set-language-environment "UTF-8")
  (prefer-coding-system 'utf-8)
  (setq locale-coding-system 'utf-8)
  (set-terminal-coding-system 'utf-8)
  (set-keyboard-coding-system 'utf-8)
  (let ((coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))
    (catch 'done
      (while t
        (let ((line (condition-case nil
                        (read-from-minibuffer "")
                      (error (throw 'done nil)))))
          (unless (string-blank-p line)
            ;; Arrays as vectors, null as :null: sent on as they came.
            (let ((message (condition-case nil
                               (json-parse-string line :object-type 'plist :null-object :null
                                                  :false-object :false)
                             (error nil))))
              (if (not message)
                  (agent-ui-mcp--fail :null -32700 "Parse error")
                (condition-case err
                    (agent-ui-mcp-handle message)
                  (error (when (plist-get message :id)
                           (agent-ui-mcp--fail (plist-get message :id) -32603
                                               (error-message-string err)))))))))))
    (kill-emacs 0)))
