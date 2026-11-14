;;; tests/unit/test-agent-ui-source.el -*- lexical-binding: t; -*-
;; config/agent-ui/source.el: elements following a command Emacs runs, a file
;; as it grows, a polled command; rules turning lines into updates; stopped
;; with their element or canvas. Real processes (sh), files in the test's
;; temp folder.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-ausrc (&rest body)
  "BODY with a canvas of its own (killed after), no window shown."
  (declare (indent 0))
  `(let* ((agent-ui-default-canvas (make-temp-name "source-"))
          (agent-ui-display-function #'ignore)
          (agent-ui-source-file-interval 0.05)
          (agent-ui-source-log-directory (file-name-as-directory (+test-tmp-file "source-logs/")))
          (canvas (agent-ui-canvas)))
     (unwind-protect (progn ,@body)
       (when (buffer-live-p canvas) (kill-buffer canvas)))))

(defun +test-ausrc-wait (predicate &optional timeout)
  (with-timeout ((or timeout 5) (ert-fail "Waited too long"))
    (while (not (funcall predicate))
      (accept-process-output nil 0.02))))

(defun +test-ausrc-ended (id)
  (+test-ausrc-wait (lambda () (eq (plist-get (agent-ui-source-status id) :running) :false))))

(defun +test-ausrc-text ()
  (with-current-buffer (agent-ui-canvas)
    (agent-ui--flush)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-ausrc-error (source)
  (agent-ui-error-message (should-error (agent-ui-source-check source) :type 'agent-ui-error)))

;; ====== REGULAR EXPRESSIONS ======

(ert-deftest agent-ui-source/pcre-as-emacs-regexps ()
  (dolist (case '(("(\\d+)/(\\d+)" "\\([0-9]+\\)/\\([0-9]+\\)")
                  ("a|b" "a\\|b")
                  ("(?:x)" "\\(?:x\\)")
                  ("x{2,3}" "x\\{2,3\\}")
                  ("\\s+\\S\\w\\W" "[[:space:]]+[^[:space:]][[:alnum:]_][^[:alnum:]_]")
                  ("[\\d.]+" "[0-9.]+")
                  ("[^]x]" "[^]x]")
                  ("\\[\\(\\.\\)" "\\[(\\.)")
                  ("^a$" "^a$")))
    (should (equal (agent-ui-source-regexp (car case)) (cadr case))))
  ;; As grep -E would match.
  (let ((re (agent-ui-source-regexp "^\\[(\\d+)/(\\d+)\\] (CC|LD) (\\S+)$")))
    (should (string-match re "[3/12] CC lexer.c"))
    (should (equal (match-string 4 "[3/12] CC lexer.c") "lexer.c"))
    (should-not (string-match re "[3/12] AS lexer.s"))))

;; ====== CHECKING ======

(ert-deftest agent-ui-source/a-wrong-source-explained ()
  (should (string-match-p "give one of command, file, poll" (+test-ausrc-error '(:match "x" :set (:a 1)))))
  (should (string-match-p "give one of" (+test-ausrc-error '(:command "a" :file "b" :tail 1))))
  (should (string-match-p "unknown key \"cmd\"" (+test-ausrc-error '(:cmd "make"))))
  (should (string-match-p "give rules (or tail, into)" (+test-ausrc-error '(:file "x.log"))))
  (should (string-match-p "rule 1 has no match" (+test-ausrc-error '(:command "a" :rules ((:set (:a 1)))))))
  (should (string-match-p "rule 1 changes nothing" (+test-ausrc-error '(:command "a" :match "x"))))
  (should (string-match-p "isn't a regular expression" (+test-ausrc-error '(:command "a" :match "(" :set (:a 1)))))
  (should (string-match-p "tail is how many lines" (+test-ausrc-error '(:command "a" :tail 0))))
  (should (string-match-p "every is a poll's" (+test-ausrc-error '(:command "a" :every 5))))
  (should (string-match-p "every is seconds, 1 or more" (+test-ausrc-error '(:poll "a" :every 0.1 :tail 1))))
  (should (string-match-p "done and failed are a command's" (+test-ausrc-error '(:file "a" :tail 1 :done (:a 1)))))
  (should (string-match-p "not both" (+test-ausrc-error '(:command "a" :match "x" :set (:a 1) :rules ((:match "y" :set (:b 1)))))))
  ;; In an element: refused with it.
  (+test-ausrc
    (should (string-match-p "unknown key"
                            (agent-ui-error-message
                             (should-error (agent-ui-show '(:id "a" :type "text" :text "" :source (:cmd "x")))
                                           :type 'agent-ui-error))))
    (should-not (agent-ui-elements))
    ;; An update can't change it.
    (agent-ui-show '(:id "a" :type "text" :text "" :source (:command "true" :tail 1)))
    (should (string-match-p "can't change a source"
                            (agent-ui-error-message
                             (should-error (agent-ui-update "a" '(:source (:command "false" :tail 1)))
                                           :type 'agent-ui-error))))))

;; ====== A COMMAND ======

(ert-deftest agent-ui-source/a-command-drives-a-bar ()
  (+test-ausrc
    (agent-ui-show '(:id "b" :type "progress" :max 1
                     :source (:command "for i in 1 2 3; do echo \"[$i/3] CC f$i.c\"; done; echo linking"
                              :match "^\\[(\\d+)/(\\d+)\\] CC (\\S+)$"
                              :set (:value "$1" :max "$2" :label "compiling $3"))))
    (+test-ausrc-ended "b")
    ;; Its last line's values; done by itself (exit 0).
    (should (equal (agent-ui-get "b") (agent-ui-get "b")))
    (let ((element (agent-ui-get "b")))
      (should (equal (plist-get element :value) 3))
      (should (equal (plist-get element :max) 3))
      (should (equal (plist-get element :label) "compiling f3.c"))
      (should (equal (plist-get element :status) "done")))
    (let ((status (agent-ui-source-status "b")))
      (should (equal (plist-get status :kind) "command"))
      (should (equal (plist-get status :exit) 0))
      (should (equal (plist-get status :lines) 4))
      ;; Its output, all of it, for the agent to read.
      (should (equal (with-temp-buffer (insert-file-contents (plist-get status :log)) (buffer-string))
                     "[1/3] CC f1.c\n[2/3] CC f2.c\n[3/3] CC f3.c\nlinking\n")))))

(ert-deftest agent-ui-source/a-command-failing ()
  (+test-ausrc
    (agent-ui-show '(:id "b" :type "progress" :max 4 :source (:command "echo 1; exit 3" :match "^(\\d)$" :set (:value "$1"))))
    (+test-ausrc-ended "b")
    (should (equal (plist-get (agent-ui-get "b") :status) "failed"))
    (should (equal (plist-get (agent-ui-get "b") :label) "exited with 3"))
    ;; Its own done and failed, with $code.
    (agent-ui-show '(:id "t" :type "table" :columns ("Test" "Result") :key 0
                     :source (:command "printf 'a ... ok\\nb ... FAILED\\nb ... ok\\n'; exit 1"
                              :rules ((:match "^(\\w+) \\.\\.\\. (ok|FAILED)$" :append (:rows (("$1" "$2")))))
                              :failed (:title "Tests: exit $code"))))
    (+test-ausrc-ended "t")
    (should (equal (plist-get (agent-ui-get "t") :rows) '(("a" "ok") ("b" "ok"))))
    (should (equal (plist-get (agent-ui-get "t") :title) "Tests: exit 1"))))

(ert-deftest agent-ui-source/running-until-its-end-is-handled ()
  "A command dead, its sentinel not run yet (Emacs runs it a moment after):
still running, its exit and patch not there; once run, done."
  (+test-ausrc
    (let (held)
      (cl-letf* ((exited (symbol-function 'agent-ui-source--exited))
                 ((symbol-function 'agent-ui-source--exited)
                  (lambda (&rest args) (push (lambda () (apply exited args)) held))))
        (agent-ui-show '(:id "b" :type "progress" :max 4 :source (:command "exit 3")))
        (+test-ausrc-wait (lambda () held))
        (let ((status (agent-ui-source-status "b")))
          (should (eq (plist-get status :running) t))
          (should-not (plist-get status :exit)))
        (should-not (plist-get (agent-ui-get "b") :status))
        (funcall (car held))
        (let ((status (agent-ui-source-status "b")))
          (should (eq (plist-get status :running) :false))
          (should (equal (plist-get status :exit) 3)))
        (should (equal (plist-get (agent-ui-get "b") :status) "failed"))))))

(ert-deftest agent-ui-source/a-tail ()
  (+test-ausrc
    (agent-ui-show '(:id "log" :type "text" :text "" :source (:command "seq 1 50" :tail 3)))
    (+test-ausrc-ended "log")
    (should (equal (plist-get (agent-ui-get "log") :text) "48\n49\n50"))))

(ert-deftest agent-ui-source/carriage-returns-are-lines ()
  ;; A progress meter rewriting its line.
  (+test-ausrc
    (agent-ui-show '(:id "d" :type "progress" :max 100
                     :source (:command "printf ' 10%%\\r 55%%\\r 90%%\\r'" :match "(\\d+)%" :set (:value "$1"))))
    (+test-ausrc-ended "d")
    (should (equal (plist-get (agent-ui-get "d") :value) 90))))

(ert-deftest agent-ui-source/in-its-directory ()
  (+test-ausrc
    (let ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "src-dir-") t))))
      (agent-ui-show (list :id "p" :type "text" :text "" :source (list :command "pwd" :tail 1 :dir dir)))
      (+test-ausrc-ended "p")
      (should (equal (file-truename (file-name-as-directory (plist-get (agent-ui-get "p") :text)))
                     (file-truename dir))))))

(ert-deftest agent-ui-source/a-bad-change-said-not-raised ()
  (+test-ausrc
    ;; "x" isn't a number: the bar's update is refused, its source says why.
    (agent-ui-show '(:id "b" :type "progress" :max 4 :source (:command "echo v=x" :match "v=(\\w)" :set (:value "$1"))))
    (+test-ausrc-ended "b")
    (should (string-match-p "value must be a number" (plist-get (agent-ui-source-status "b") :error)))))

;; ====== STOPPING ======

(ert-deftest agent-ui-source/stopped-with-its-element ()
  (+test-ausrc
    (agent-ui-show '(:id "s" :type "text" :text "" :source (:command "sleep 30" :tail 1)))
    (let ((process (agent-ui-source--state-process (agent-ui-source--state canvas "s"))))
      (should (process-live-p process))
      (agent-ui-remove "s")
      (should-not (process-live-p process))
      (should-not (agent-ui-source-status "s")))
    ;; Shown again without a source: the old one stopped.
    (agent-ui-show '(:id "s" :type "text" :text "" :source (:command "sleep 30" :tail 1)))
    (let ((process (agent-ui-source--state-process (agent-ui-source--state canvas "s"))))
      (agent-ui-show '(:id "s" :type "text" :text "plain"))
      (should-not (process-live-p process)))
    ;; Its canvas closed: all of them.
    (agent-ui-show '(:id "k" :type "text" :text "" :source (:command "sleep 30" :tail 1)))
    (let ((process (agent-ui-source--state-process (agent-ui-source--state canvas "k"))))
      (kill-buffer canvas)
      (should-not (process-live-p process)))))

;; ====== A FILE, A POLL ======

(ert-deftest agent-ui-source/a-file-followed ()
  (+test-ausrc
    (let ((file (+test-tmp-file (format "follow-%d.log" (random 100000)))))
      (with-temp-file file (insert "old 1\n"))
      ;; From its end: what's there already doesn't count.
      (agent-ui-show (list :id "f" :type "chart" :kind "sparkline"
                           :source (list :file file :from "end" :match "^v (\\d+)$" :append '(:values ("$1")))))
      (accept-process-output nil 0.1)
      (write-region "v 3\nv 5\nv" nil file t 'silent)
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "f") :values) '(3 5))))
      ;; The rest of a line once it's written.
      (write-region " 8\n" nil file t 'silent)
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "f") :values) '(3 5 8))))
      ;; Written again from its start.
      (write-region "v 1\n" nil file nil 'silent)
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "f") :values) '(3 5 8 1))))
      (should (eq (plist-get (agent-ui-source-status "f") :running) t)))))

(ert-deftest agent-ui-source/a-file-not-there-yet ()
  (+test-ausrc
    (let ((file (+test-tmp-file (format "later-%d.log" (random 100000)))))
      (agent-ui-show (list :id "f" :type "text" :text "" :source (list :file file :tail 2)))
      (accept-process-output nil 0.1)
      (write-region "a\nb\nc\n" nil file nil 'silent)
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "f") :text) "b\nc"))))))

(ert-deftest agent-ui-source/a-poll ()
  (+test-ausrc
    (let ((file (+test-tmp-file (format "count-%d" (random 100000)))))
      (with-temp-file file (insert "1"))
      (agent-ui-show (list :id "p" :type "chart" :kind "sparkline"
                           :source (list :poll (format "cat %s" (shell-quote-argument file)) :every 1
                                         :match "^(\\d+)$" :append '(:values ("$1")))))
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "p") :values) '(1))))
      (with-temp-file file (insert "7"))
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "p") :values) '(1 7))) 4))))

(ert-deftest agent-ui-source/one-that-cant-run-said ()
  "A command or a poll in a directory that isn't there: the element shown,
its source stopped, its error said (the show was an error out of it, the
element in all the same; a poll said running forever, its timer failing at
each run). A wrong source among a panel's children: the show refused, nothing
added."
  (+test-ausrc
    (let* ((gone (expand-file-name "not-there/" (+test-tmp-file "")))
           (timer-errors 0))
      (cl-letf* ((message-fn (symbol-function 'message))
                 ((symbol-function 'message)
                  (lambda (format-string &rest args)
                    (when (and format-string (string-match-p "Error running timer" format-string))
                      (cl-incf timer-errors))
                    (apply message-fn format-string args))))
        (dolist (source (list (list :command "pwd" :tail 1 :dir gone)
                              (list :poll "pwd" :every 1 :tail 1 :dir gone)))
          (should (equal (agent-ui-show (list :id "p" :type "text" :text "" :source source)) "p"))
          (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements)) '("p")))
          (let ((status (agent-ui-source-status "p")))
            (should (eq (plist-get status :running) :false))
            (should (string-match-p "no directory .*not-there" (plist-get status :error))))
          (agent-ui-remove "p"))
        ;; Its dir gone after it started: stopped at its next run, said.
        (let ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "polled-") t))))
          (agent-ui-show (list :id "q" :type "text" :text "" :source (list :poll "pwd" :every 1 :tail 1 :dir dir)))
          (+test-ausrc-wait (lambda () (plist-get (agent-ui-get "q") :text)))
          (delete-directory dir t)
          (+test-ausrc-wait (lambda () (eq (plist-get (agent-ui-source-status "q") :running) :false)) 3)
          (should (string-match-p "no directory" (plist-get (agent-ui-source-status "q") :error))))
        (should (= timer-errors 0)))
      ;; Through a request: ok, the reply says why.
      (let ((reply (agent-ui-do "show" nil (list :id "r" :type "text" :text ""
                                                 :source (list :command "pwd" :dir gone))
                                canvas)))
        (should (eq (plist-get reply :ok) t))
        (should (string-match-p "no directory" (plist-get (plist-get reply :source) :error))))
      ;; A panel's child's source wrong: refused, nothing added.
      (should (string-match-p "panel: child c: source: give one of command, file, poll"
                              (agent-ui-error-message
                               (should-error (agent-ui-show '(:id "panel" :type "panel"
                                                              :children ((:id "c" :type "text" :text "" :source (:tail 3)))))
                                             :type 'agent-ui-error))))
      (should-not (member "panel" (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements)))))))

(ert-deftest agent-ui-source/its-log-deleted-when-it-stops ()
  "A command's log: kept while its element is shown (for the agent to read),
deleted when it's removed, shown again, its canvas killed (they stayed in
the temporary folder)."
  (+test-ausrc
    (cl-flet ((log-of (id) (plist-get (agent-ui-source-status id) :log)))
      (agent-ui-show '(:id "a" :type "text" :text "" :source (:command "echo a" :tail 1)))
      (+test-ausrc-ended "a")
      (let ((log (log-of "a")))
        (should (file-exists-p log))
        (agent-ui-remove "a")
        (should-not (file-exists-p log)))
      (agent-ui-show '(:id "b" :type "text" :text "" :source (:command "echo b" :tail 1)))
      (let ((log (log-of "b")))
        (agent-ui-show '(:id "b" :type "text" :text "" :source (:command "echo again" :tail 1)))
        (should-not (file-exists-p log))
        (should (file-exists-p (log-of "b"))))
      ;; A panel's child's too, with its canvas.
      (agent-ui-show '(:id "p" :type "panel" :children ((:id "c" :type "text" :text "" :source (:command "echo c" :tail 1)))))
      (let ((logs (list (log-of "b") (log-of "c"))))
        (should (cl-every #'file-exists-p logs))
        (kill-buffer canvas)
        (should-not (cl-some #'file-exists-p logs))))))

(ert-deftest agent-ui-source/late-output-of-a-stopped-source-ignored ()
  "A command's output and end read after its source stopped (deleting
another process reads what an exited one left: its log was written again,
on Linux, once its canvas was killed): its log not made again, the
element's next source neither fed nor told it ended."
  (+test-ausrc
    (agent-ui-show '(:id "b" :type "text" :text "" :source (:command "echo first" :tail 1)))
    (let* ((first (with-current-buffer canvas (gethash "b" agent-ui-source--states)))
           (process (agent-ui-source--state-process first))
           (log (agent-ui-source--state-log first)))
      (+test-ausrc-ended "b")
      ;; Shown again: its first source stopped, its log deleted.
      (agent-ui-show '(:id "b" :type "text" :text "" :source (:command "sleep 30" :tail 1)))
      (should-not (file-exists-p log))
      ;; The first command's output and end, read late.
      (funcall (process-filter process) process "late\n")
      (funcall (process-sentinel process) process "finished\n")
      (should-not (file-exists-p log))
      (should-not (string-match-p "late" (+test-ausrc-text)))
      (should (eq (plist-get (agent-ui-source-status "b") :running) t))
      (should-not (plist-get (agent-ui-source-status "b") :exit)))))

;; ====== THROUGH THE COMMAND LINE ======

(ert-deftest agent-ui-source/in-a-request ()
  (+test-ausrc
    (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "req-dir-") t)))
           ;; As `agent-ui-request' has them.
           (agent-ui--request-cwd dir)
           (agent-ui-file-directory dir)
           (reply (agent-ui-do "show" nil
                               '(:id "p" :type "text" :text "" :source (:command "pwd" :tail 1))
                               canvas)))
      ;; Its log named; run in the agent's directory.
      (should (string-match-p "\\.log\\'" (plist-get reply :log)))
      (+test-ausrc-ended "p")
      (should (equal (file-truename (file-name-as-directory (plist-get (agent-ui-get "p") :text)))
                     (file-truename dir)))
      (let ((listed (aref (plist-get (agent-ui-do "list" nil nil canvas) :elements) 0)))
        (should (equal (plist-get (plist-get listed :source) :exit) 0))))))

(ert-deftest agent-ui-source/a-panels-children-in-the-agents-directory ()
  "Through a request from the agent's directory: a panel's child's source
runs there, a relative dir under it, an absolute one as it is (they ran in
the canvas's directory, whatever buffer's it was when it was made: /usr/,
/usr/sub/)."
  (+test-ausrc
    (let* ((cwd (file-name-as-directory (make-temp-file (+test-tmp-file "agent-cwd-") t)))
           (other (file-name-as-directory (make-temp-file (+test-tmp-file "elsewhere-") t)))
           (folder (make-temp-file (+test-tmp-file "req-") t)))
      (make-directory (expand-file-name "sub" cwd))
      (with-current-buffer canvas (setq default-directory other))
      (with-temp-file (expand-file-name "request" folder)
        (insert (format "show\n\n\n%s\n" cwd)))
      (with-temp-file (expand-file-name "payload" folder)
        (insert (json-serialize
                 (agent-ui-to-json
                  `(:id "p" :type "panel"
                   :children ((:id "here" :type "text" :text "" :source (:command "pwd" :tail 1))
                              (:id "sub" :type "text" :text "" :source (:command "pwd" :tail 1 :dir "sub"))
                              (:id "abs" :type "text" :text "" :source (:command "pwd" :tail 1 :dir ,other))))))))
      (let ((agent-ui-canvas-function (lambda (_session _cwd) canvas)))
        (agent-ui-request folder))
      (dolist (id '("here" "sub" "abs")) (+test-ausrc-ended id))
      (cl-flet ((ran-in (id) (file-truename (file-name-as-directory (plist-get (agent-ui-get id) :text)))))
        (should (equal (ran-in "here") (file-truename cwd)))
        (should (equal (ran-in "sub") (file-truename (expand-file-name "sub/" cwd))))
        (should (equal (ran-in "abs") (file-truename other)))))))

;; ====== THE SKILL ======

(ert-deftest agent-ui-source/the-skills-sources-right ()
  "Each element with a source the skill shows (a heredoc): right, its source
checked (not run), its rules matching a line as they should."
  (let* ((skill (+test-agent-ui-skill))
         (pos 0)
         (elements nil))
    (while (string-match "^agent-ui show <<'EOF'\n\\(\\(?:.\\|\n\\)*?\\)\nEOF$" skill pos)
      (push (agent-ui-parse-json (match-string 1 skill)) elements)
      (setq pos (match-end 0)))
    (setq elements (nreverse elements))
    (should (= (length elements) 6))
    (dolist (element elements)
      (should (agent-ui-check (plist-get element :type) element))
      (should (agent-ui-source-check (plist-get element :source))))
    ;; The rules read what they're for.
    (cl-flet ((applied (element line)
                (agent-ui-source--apply (agent-ui-source-check (plist-get element :source)) (list line))))
      (should (equal (applied (nth 2 elements) "[3/120] Building CXX object a.o")
                     '((:value 3 :max 120 :label "Building CXX object a.o"))))
      (should (equal (applied (nth 3 elements) "test parser::empty ... FAILED")
                     '(nil :rows (("parser::empty" "FAILED")))))
      (should (equal (applied (nth 5 elements) " 51234")
                     '(nil :values (51234)))))))

(ert-deftest agent-ui-source/all-of-it-into-a-property ()
  (+test-ausrc
    ;; A diff following a command: its whole output, its diff.
    (agent-ui-show '(:id "d" :type "diff" :source (:command "printf -- '--- a/x\\n+++ b/x\\n@@ -1 +1 @@\\n-a\\n+b\\n'" :into "diff")))
    (+test-ausrc-ended "d")
    (should (equal (plist-get (agent-ui-get "d") :diff) "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b"))
    (should (string-match-p "into names a property" (+test-ausrc-error '(:command "a" :into "Bad Name"))))))

(ert-deftest agent-ui-source/a-log-following-a-file ()
  (+test-ausrc
    (let ((file (+test-tmp-file (format "app-%d.log" (random 100000)))))
      (with-temp-file file (insert "old\n"))
      (agent-ui-show (list :id "l" :type "log" :source (list :file file :from "end" :into "lines")))
      (accept-process-output nil 0.1)
      (write-region "12:00 INFO up\n12:01 ERROR down\n" nil file t 'silent)
      (+test-ausrc-wait (lambda () (equal (plist-get (agent-ui-get "l") :lines) "12:00 INFO up\n12:01 ERROR down")))
      (should (string-prefix-p "1 error · 2 lines" (+test-ausrc-text))))))


(ert-deftest agent-ui-source/a-childs-source ()
  (+test-ausrc
    ;; A child's source: started with its panel, updating the child.
    (agent-ui-show '(:id "p" :type "panel"
                     :children ((:id "c" :type "progress" :max 1
                                 :source (:command "echo 3/4" :match "(\\d)/(\\d)" :set (:value "$1" :max "$2"))))))
    (+test-ausrc-ended "c")
    (should (equal (plist-get (agent-ui-get "c") :value) 3))
    (should (string-match-p "3/4  75%" (+test-ausrc-text)))
    ;; Its panel removed: its source stopped.
    (agent-ui-show '(:id "q" :type "panel" :children ((:id "s" :type "text" :text "" :source (:command "sleep 30" :tail 1)))))
    (let ((process (agent-ui-source--state-process (agent-ui-source--state canvas "s"))))
      (should (process-live-p process))
      (agent-ui-remove "q")
      (should-not (process-live-p process)))
    ;; Updating a panel keeps its children's sources running; one gone, stopped.
    (agent-ui-show '(:id "r" :type "panel" :children ((:id "t" :type "text" :text "" :source (:command "sleep 30" :tail 1)))))
    (let ((process (agent-ui-source--state-process (agent-ui-source--state canvas "t"))))
      (agent-ui-update "r" '(:title "renamed"))
      (should (process-live-p process))
      (agent-ui-update "r" '(:children ((:id "u" :type "text" :text "x"))))
      (should-not (process-live-p process)))))
