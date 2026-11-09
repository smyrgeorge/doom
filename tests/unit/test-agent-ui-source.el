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

;; ====== THROUGH THE COMMAND LINE ======

(ert-deftest agent-ui-source/in-a-request ()
  (+test-ausrc
    (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "req-dir-") t)))
           (agent-ui--request-cwd dir)
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

;; ====== THE SKILL ======

(ert-deftest agent-ui-source/the-skills-sources-right ()
  "Each element with a source the skill shows (a heredoc): right, its source
checked (not run), its rules matching a line as they should."
  (let* ((skill (with-temp-buffer
                  (insert-file-contents (expand-file-name "skills/agent-ui/SKILL.md" +test-root))
                  (buffer-string)))
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

