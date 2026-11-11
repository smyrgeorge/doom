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
    ;; Its link too, for the agent's reply.
    (should (equal (+test-aur-request "show" nil "{\"id\":\"b\",\"type\":\"progress\",\"max\":4}")
                   (list :ok t :id "b" :link (agent-ui-link agent-ui-default-canvas "b"))))
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
                     '("chart" "choice" "code" "compare" "confirm" "countdown" "diff" "files" "form" "gauge" "graph" "heatmap" "html" "image" "issues" "log" "markdown" "math" "panel" "progress" "rank" "slider" "stats" "steps" "table" "tags" "text" "timeline" "todo"))))
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
        (should (equal (nth 0 results) (list :ok t :id "p" :link (agent-ui-link agent-ui-default-canvas "p"))))
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

(defun +test-aur-request-in (canvas op &optional id payload)
  "OP's reply, its request naming the other canvas CANVAS (its 6th line)."
  (let ((dir (make-temp-file (+test-tmp-file "aur-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert (format "%s\n%s\n\n\n\n%s\n" op (or id "") canvas)))
    (when payload
      (with-temp-file (expand-file-name "payload" dir) (insert payload)))
    (agent-ui-request dir)
    (agent-ui-parse-json (with-temp-buffer
                           (insert-file-contents (expand-file-name "reply" dir))
                           (buffer-string)))))

(ert-deftest agent-ui-request/another-canvas ()
  (+test-aur
    (let ((tests (concat agent-ui-default-canvas " / tests"))
          (logs (concat agent-ui-default-canvas " / my logs")))
      (unwind-protect
          (progn
            ;; --canvas: the session's other canvas, its own buffer; linked so.
            (should (equal (+test-aur-request-in "tests" "show" nil "{\"id\":\"a\",\"type\":\"text\",\"text\":\"x\"}")
                           (list :ok t :id "a" :link (agent-ui-link tests "a"))))
            (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas tests)) '("a")))
            (should-not (agent-ui-elements))
            ;; Its ids its own: the same id in the session's canvas.
            (+test-aur-request "show" nil "{\"id\":\"a\",\"type\":\"text\",\"text\":\"main\"}")
            (should (equal (plist-get (agent-ui-get "a" :canvas tests) :text) "x"))
            ;; "canvas" in the JSON: the same, not kept in the element.
            (+test-aur-request "show" nil "{\"id\":\"l\",\"type\":\"text\",\"text\":\"y\",\"canvas\":\"my logs\"}")
            (should (equal (agent-ui-get "l" :canvas logs) '(:id "l" :type "text" :text "y")))
            (+test-aur-request "update" "l" "{\"text\":\"z\",\"canvas\":\"my logs\"}")
            (should (equal (plist-get (agent-ui-get "l" :canvas logs) :text) "z"))
            ;; list and clear: a canvas's.
            (should (= (length (plist-get (+test-aur-request-in "tests" "list") :elements)) 1))
            (+test-aur-request-in "tests" "clear")
            (should-not (agent-ui-elements :canvas tests))
            (should (agent-ui-elements))
            ;; A batch's operations, each its canvas.
            (should (eq (plist-get (+test-aur-request "batch" nil "[{\"op\":\"show\",\"id\":\"b\",\"type\":\"text\",\"text\":\"1\",\"canvas\":\"tests\"},{\"op\":\"remove\",\"id\":\"l\",\"canvas\":\"my logs\"},{\"op\":\"remove\",\"id\":\"a\"}]")
                                   :ok)
                        t))
            (should (agent-ui-get "b" :canvas tests))
            (should-not (agent-ui-elements :canvas logs))
            (should-not (agent-ui-elements))
            ;; A name that won't do: said so.
            (should (string-match-p "canvas: a name of letters"
                                    (plist-get (+test-aur-request-in "a/b" "list") :error)))
            (should (string-match-p "canvas: give a name"
                                    (plist-get (+test-aur-request "show" nil "{\"type\":\"text\",\"canvas\":3}") :error))))
        (dolist (name (list tests logs))
          (when (get-buffer (agent-ui-canvas-buffer-name name))
            (kill-buffer (agent-ui-canvas-buffer-name name))))))))

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
      (should (equal (plist-get (+test-aur-request "show" nil "{\"id\":\"d\",\"type\":\"dots\",\"n\":2}") :id)
                     "d"))
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
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *agent-ui-stderr*"))))
    (when stdin (process-send-string process stdin))
    (process-send-eof process)
    (with-timeout (20 (delete-process process) (ert-fail "cmd/agent-ui didn't end"))
      ;; Its output all read: not merely ended (`+test-process-sentinel').
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(ert-deftest agent-ui-request/the-script ()
  (+test-aur
    (+test-aur-with-server
      ;; JSON as an argument, or on stdin.
      (should (equal (+test-aur-run '("show" "{\"id\":\"p\",\"type\":\"progress\",\"max\":4}"))
                     (cons 0 (format "{\"ok\":true,\"id\":\"p\",\"link\":\"%s\"}"
                                     (agent-ui-link agent-ui-default-canvas "p")))))
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
      ;; render --ansi: in colour.
      (let ((run (+test-aur-run '("render" "--ansi" "{\"type\":\"text\",\"text\":\"ok\",\"face\":\"success\"}"))))
        (should (= (car run) 0))
        (should (string-match-p "\\\\u001b\\[" (cdr run))))
      ;; --canvas NAME, wherever it is: the session's other canvas.
      (let ((tests (concat agent-ui-default-canvas " / tests")))
        (unwind-protect
            (progn
              (should (= (car (+test-aur-run '("show" "--canvas" "tests" "{\"id\":\"c\",\"type\":\"text\",\"text\":\"t\"}"))) 0))
              (should (agent-ui-get "c" :canvas tests))
              (should (= (car (+test-aur-run '("--canvas=tests" "remove" "c"))) 0))
              (should-not (agent-ui-elements :canvas tests))
              (should (= (car (+test-aur-run '("list" "--canvas"))) 2)))
          (when (get-buffer (agent-ui-canvas-buffer-name tests))
            (kill-buffer (agent-ui-canvas-buffer-name tests)))))
      ;; This directory's: the request says where it came from.
      (should (= (car (+test-aur-run '("remove" "p"))) 0))
      (should-not (agent-ui-elements)))))

(ert-deftest agent-ui-request/the-script-files-a-bug ()
  "agent-ui bug: JSON as an argument or on stdin; filed: 0; not filed: 1,
its reply with the report (config/agent-ui/bug.el, the filing stood in for)."
  (+test-aur
    (+test-aur-with-server
      (let* ((answer '(:id "lib-1" :new t :dir "/lib/"))
             (agent-ui-bug-filed-functions nil)
             (agent-ui-bug-function (lambda (&rest _) (if (stringp answer) (error "%s" answer) answer))))
        (should (equal (+test-aur-run '("bug" "{\"title\":\"x\",\"description\":\"y\"}"))
                       '(0 . "{\"ok\":true,\"issue\":\"lib-1\",\"new\":true}")))
        (setq answer "bd isn't installed")
        (let ((run (+test-aur-run '("bug") "{\"title\":\"x\",\"description\":\"y\"}")))
          (should (= (car run) 1))
          (should (string-match-p "\"error\":\"Agent UI's bug wasn't filed: bd isn't installed" (cdr run)))
          (should (string-match-p "\"report\":\"# Agent UI: x\\\\n\\\\ny\\\\n" (cdr run))))
        (should (= (car (+test-aur-run '("bug" "a" "b"))) 2))))))

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
