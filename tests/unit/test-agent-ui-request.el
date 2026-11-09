;;; tests/unit/test-agent-ui-request.el -*- lexical-binding: t; -*-
;; config/agent-ui/request.el and cmd/agent-ui: the agent's way in. Each
;; operation through `agent-ui-request' (a request folder, its reply), then the
;; script itself, run as the agent runs it, its emacsclient answered by a
;; server started in this test Emacs (never the user's).

(require 'server)
(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defconst +test-aur-script (expand-file-name "cmd/agent-ui" +test-root))

(defmacro +test-aur (&rest body)
  "BODY with a canvas of its own (the default: killed after), the real
element types, no window shown, no agent-shell sessions."
  (declare (indent 0))
  `(let* ((agent-ui-default-canvas (make-temp-name "test-"))
          (agent-ui-display-function #'ignore)
          (canvas (agent-ui-canvas)))
     (cl-letf (((symbol-function 'agent-ui--sessions) #'ignore))
       (unwind-protect (progn ,@body)
         (kill-buffer canvas)))))

(defun +test-aur-request (op &optional id payload session cwd)
  "OP's reply (parsed) as cmd/agent-ui gets it: a request folder with ID,
SESSION, CWD and PAYLOAD (a string), answered by `agent-ui-request'."
  (let ((dir (make-temp-file (+test-tmp-file "aur-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert (format "%s\n%s\n%s\n%s\n" op (or id "") (or session "") (or cwd ""))))
    (when payload
      (with-temp-file (expand-file-name "payload" dir) (insert payload)))
    (should (eq (agent-ui-request dir) t))
    (agent-ui-parse-json (with-temp-buffer
                           (insert-file-contents (expand-file-name "reply" dir))
                           (buffer-string)))))

(defun +test-aur-text ()
  (with-current-buffer (agent-ui-canvas)
    (agent-ui--flush)
    (buffer-substring-no-properties (point-min) (point-max))))

;; ====== OPERATIONS ======

(ert-deftest agent-ui-request/show-update-append-remove ()
  (+test-aur
    (should (equal (+test-aur-request "show" nil "{\"id\":\"b\",\"type\":\"progress\",\"max\":4}")
                   '(:ok t :id "b")))
    (should (string-match-p "\\`░+  0/4  0%\n\n\\'" (+test-aur-text)))
    (should (equal (+test-aur-request "update" "b" "{\"value\":2,\"label\":\"half\"}")
                   '(:ok t :id "b")))
    (should (string-match-p "2/4  50%  half" (+test-aur-text)))
    ;; null: back to its default.
    (+test-aur-request "update" "b" "{\"label\":null}")
    (should-not (string-match-p "half" (+test-aur-text)))
    (+test-aur-request "show" nil "{\"id\":\"t\",\"type\":\"table\",\"columns\":[\"A\"]}")
    (should (equal (+test-aur-request "append" "t" "{\"rows\":[[\"x\"],[\"y\"]]}")
                   '(:ok t :id "t")))
    (should (string-match-p " x\n y" (+test-aur-text)))
    (should (equal (+test-aur-request "list")
                   '(:ok t :elements ((:id "b" :type "progress") (:id "t" :type "table")))))
    (should (equal (+test-aur-request "remove" "b") '(:ok t :id "b")))
    (should (equal (+test-aur-request "clear") '(:ok t)))
    (should (equal (+test-aur-request "list") '(:ok t :elements nil)))))

(ert-deftest agent-ui-request/show-with-an-id-given ()
  (+test-aur
    ;; Made, or the one given beside the JSON.
    (should (equal (plist-get (+test-aur-request "show" nil "{\"type\":\"progress\"}") :id)
                   "progress-1"))
    (should (equal (plist-get (+test-aur-request "show" "mine" "{\"type\":\"progress\"}") :id)
                   "mine"))))

(ert-deftest agent-ui-request/types ()
  (+test-aur
    (let ((reply (+test-aur-request "types")))
      (should (eq (plist-get reply :ok) t))
      (should (equal (mapcar (lambda (e) (plist-get e :name)) (plist-get reply :types))
                     '("chart" "html" "image" "markdown" "progress" "steps" "table" "text"))))
    (let ((reply (+test-aur-request "types" "table")))
      (should (equal (mapcar (lambda (e) (plist-get e :name)) (plist-get reply :types)) '("table"))))
    (should (string-match-p "unknown type \"tabel\""
                            (plist-get (+test-aur-request "types" "tabel") :error)))))

(ert-deftest agent-ui-request/batch ()
  (+test-aur
    (let ((reply (+test-aur-request
                  "batch" nil
                  "[{\"op\":\"show\",\"id\":\"p\",\"type\":\"progress\",\"max\":2},
                    {\"op\":\"update\",\"id\":\"p\",\"value\":1},
                    {\"op\":\"update\",\"id\":\"nope\",\"value\":1},
                    {\"op\":\"list\"},
                    {\"op\":\"remove\",\"id\":\"p\"}]")))
      ;; Each done, or why not; not ok if one wasn't.
      (should (eq (plist-get reply :ok) :false))
      (let ((results (plist-get reply :results)))
        (should (equal (nth 0 results) '(:ok t :id "p")))
        (should (equal (nth 1 results) '(:ok t :id "p")))
        (should (string-match-p "no element \"nope\"" (plist-get (nth 2 results) :error)))
        (should (string-match-p "list isn't done in a batch" (plist-get (nth 3 results) :error)))
        (should (equal (nth 4 results) '(:ok t :id "p")))))
    (should (string-match-p "a JSON array"
                            (plist-get (+test-aur-request "batch" nil "{\"op\":\"show\"}") :error)))
    (should (eq (plist-get (+test-aur-request "batch" nil "[]") :ok) t))))

(ert-deftest agent-ui-request/errors-replied ()
  (+test-aur
    (cl-flet ((err (&rest args) (let ((reply (apply #'+test-aur-request args)))
                                  (should (eq (plist-get reply :ok) :false))
                                  (plist-get reply :error))))
      (should (string-match-p "\\`bad JSON" (err "show" nil "{\"type\":")))
      (should (equal (err "show" nil "") "show: no JSON given"))
      (should (equal (err "show" nil "[1]") "show: give a JSON object, not (1)"))
      (should (equal (err "update" nil "{\"value\":1}") "update: which element? give its id"))
      (should (string-match-p "unknown property \"total\""
                              (err "show" nil "{\"type\":\"progress\",\"total\":1}")))
      (should (string-match-p "unknown operation \"frob\"" (err "frob")))
      ;; No request at all.
      (let ((dir (make-temp-file (+test-tmp-file "aur-") t)))
        (agent-ui-request dir)
        (should (string-match-p "request"
                                (with-temp-buffer
                                  (insert-file-contents (expand-file-name "reply" dir))
                                  (buffer-string))))))))

(ert-deftest agent-ui-request/the-canvas-by-session ()
  (+test-aur
    (let ((name (make-temp-name "session-")))
      (unwind-protect
          (progn
            (+test-aur-request "show" nil "{\"id\":\"a\",\"type\":\"progress\"}" name)
            (should (get-buffer (agent-ui-canvas-buffer-name name)))
            (should-not (agent-ui-elements)))
        (kill-buffer (agent-ui-canvas-buffer-name name))))))

(ert-deftest agent-ui-request/unicode-both-ways ()
  (+test-aur
    (+test-aur-request "show" nil "{\"id\":\"u\",\"type\":\"progress\",\"label\":\"ünïcødé ✓ 日本\"}")
    (should (string-match-p "ünïcødé ✓ 日本" (+test-aur-text)))
    (should (string-match-p "\"ünïcødé\""
                            (plist-get (+test-aur-request "show" nil "{\"type\":\"ünïcødé\"}") :error)))))

;; render, define: the agent sees what it draws; makes a type.
(ert-deftest agent-ui-request/render ()
  (+test-aur
    (should (equal (+test-aur-request "render" nil "{\"type\":\"text\",\"text\":\"hello\",\"title\":\"T\"}")
                   '(:ok t :text "T\nhello")))
    ;; Nothing shown.
    (should-not (agent-ui-elements))
    ;; Wrong: an error, not a drawing of one.
    (should (string-match-p "unknown property"
                            (plist-get (+test-aur-request "render" nil "{\"type\":\"text\",\"txt\":1}") :error)))))

(ert-deftest agent-ui-request/define ()
  (+test-aur
    (let ((agent-ui-staging-directory (file-name-as-directory (make-temp-file (+test-tmp-file "staged-") t)))
          (agent-ui--types (copy-hash-table agent-ui--types)))
      (let ((reply (+test-aur-request
                    "define" nil
                    "(agent-ui-define dots \"Dots.\" :props ((n integer \"How many\" :default 3))
  :example (:n 5) :text (lambda (props _ctx) (make-string (plist-get props :n) ?.)))")))
        (should (eq (plist-get reply :ok) t))
        (should (equal (plist-get reply :type) "dots"))
        (should (equal (plist-get reply :preview) "....."))
        (should (equal (plist-get reply :warnings) nil)))
      ;; Usable at once.
      (should (equal (+test-aur-request "show" nil "{\"id\":\"d\",\"type\":\"dots\",\"n\":2}")
                     '(:ok t :id "d")))
      (should (string-match-p "one type (one agent-ui-define), not 0"
                              (plist-get (+test-aur-request "define" nil "(setq x 1)") :error)))
      (should (string-match-p "define: no JSON given\\|give a type's code"
                              (plist-get (+test-aur-request "define" nil "  ") :error))))))

;; ====== THE SCRIPT ======

(defmacro +test-aur-with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/aui-" t))
          (server-name "test")
          (process-environment
           (append (list (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                         "AGENT_UI_SESSION")
                   process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-aur-run (args &optional stdin)
  "Run cmd/agent-ui with ARGS (STDIN given, else closed): (STATUS . OUTPUT).
Asynchronously: this Emacs, its server, answers it meanwhile."
  (let* ((output (generate-new-buffer " *agent-ui-run*"))
         (process (make-process :name "agent-ui" :buffer output
                                :command (cons +test-aur-script args)
                                :connection-type 'pipe :noquery t :sentinel #'ignore
                                :stderr (get-buffer-create " *agent-ui-stderr*"))))
    (when stdin (process-send-string process stdin))
    (process-send-eof process)
    (with-timeout (20 (delete-process process) (ert-fail "cmd/agent-ui didn't end"))
      (while (process-live-p process)
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(ert-deftest agent-ui-request/the-script ()
  (+test-aur
    (+test-aur-with-server
      ;; JSON as an argument, or on stdin.
      (should (equal (+test-aur-run '("show" "{\"id\":\"p\",\"type\":\"progress\",\"max\":4}"))
                     '(0 . "{\"ok\":true,\"id\":\"p\"}")))
      (should (equal (+test-aur-run '("update" "p") "{\"value\": 3, \"label\": \"a \\\"quote\\\" and \\\\\"}")
                     '(0 . "{\"ok\":true,\"id\":\"p\"}")))
      (should (string-match-p "3/4  75%  a \"quote\" and \\\\" (+test-aur-text)))
      ;; Not done: 1, the reply says why.
      (let ((run (+test-aur-run '("update" "q" "{}"))))
        (should (= (car run) 1))
        (should (string-match-p "\\`{\"ok\":false,\"error\":\"no element \\\\\"q\\\\\"" (cdr run))))
      (should (equal (car (+test-aur-run '("list"))) 0))
      (should (string-match-p "\"name\":\"table\"" (cdr (+test-aur-run '("types" "table")))))
      ;; A type's code from a file.
      (let ((agent-ui-staging-directory (file-name-as-directory (make-temp-file (+test-tmp-file "staged-") t)))
            (agent-ui--types (copy-hash-table agent-ui--types))
            (file (make-temp-file (+test-tmp-file "type-") nil ".el"
                                  "(agent-ui-define bang \"!\" :example () :text (lambda (_p _c) \"!\"))")))
        (let ((run (+test-aur-run (list "define" file))))
          (should (= (car run) 1))
          (should (string-match-p "has no :example" (cdr run))))
        (with-temp-file file
          (insert "(agent-ui-define bang \"!\" :example (:title \"b\") :text (lambda (_p _c) \"!\"))"))
        (let ((run (+test-aur-run (list "define" file))))
          (should (= (car run) 0))
          (should (string-match-p "\"preview\":\"b\\\\n!\"" (cdr run))))
        (should (= (car (+test-aur-run '("define" "/no/such/file.el"))) 2)))
      ;; This directory's: the request says where it came from.
      (should (= (car (+test-aur-run '("remove" "p"))) 0))
      (should-not (agent-ui-elements)))))

(ert-deftest agent-ui-request/the-script-used-wrong ()
  (+test-aur
    (+test-aur-with-server
      (dolist (case '((("frob") . "unknown operation \\\\\"frob\\\\\"")
                      (("update") . "which element")
                      (("update" "a" "{}" "x") . "too many")
                      (("remove") . "agent-ui remove ID")
                      (("list" "x") . "takes no arguments")
                      (("show" "a" "b") . "too many")))
        (let ((run (+test-aur-run (car case))))
          (should (= (car run) 2))
          (should (string-match-p "\\`{\"ok\":false,\"error\":" (cdr run)))
          (should (string-match-p (cdr case) (cdr run)))))
      ;; Nothing on stdin, no argument: nothing sent.
      (let ((run (+test-aur-run '("show"))))
        (should (= (car run) 1))
        (should (string-match-p "show: no JSON given" (cdr run))))
      ;; Help: its header.
      (let ((run (+test-aur-run '("--help"))))
        (should (= (car run) 0))
        (should (string-match-p "agent-ui show \\[JSON\\]" (cdr run))))
      (should (= (car (+test-aur-run nil)) 2)))))

(ert-deftest agent-ui-request/the-script-without-emacs ()
  (let ((process-environment (cons "EMACS_SOCKET_NAME=/tmp/no-such-agent-ui-server"
                                   process-environment)))
    (let ((run (+test-aur-run '("list"))))
      (should (= (car run) 3))
      (should (string-match-p "no Emacs server answered" (cdr run))))))
