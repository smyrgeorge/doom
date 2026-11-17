;;; tests/unit/test-harness.el -*- lexical-binding: t; -*-
;; The unit test harness itself (tests/helper.el): a failed test's report,
;; its backtrace unprintable (a file it reads not read), still says its
;; condition, and the run goes on to the tests after it; no test sees the
;; shell's Beads settings; tests/run.sh keeps a failed file's log in
;; TEST_LOGS.

(defun +test-harness--unreadable (&rest _)
  "What reading a file signals when it can't be (as once in a full run)."
  (signal 'file-error (list "Opening input file" "Operation not permitted" "/emacs/etc/DOC")))

(ert-deftest harness/an-unprintable-backtrace-printed-plainly ()
  "Each frame's function and arguments, saying why; no file read."
  (cl-letf (((symbol-function 'find-lisp-object-file-name) #'+test-harness--unreadable))
    (let* ((frames (list (backtrace-make-frame :evald t :fun '= :args '("Interrupt" 0))
                         (backtrace-make-frame :evald t :fun 'apply :args '(= ("Interrupt" 0)))
                         (backtrace-make-frame :evald t :fun 'command-line :args nil)))
           (text (backtrace-to-string frames)))
      (should (equal text (concat "  (printed plainly: Opening input file: Operation not permitted, /emacs/etc/DOC)\n"
                                  "  =(\"Interrupt\" 0)\n"
                                  "  apply(= (\"Interrupt\" 0))\n"
                                  "  command-line()\n")))
      ;; The current one too.
      (should (string-search "harness/an-unprintable-backtrace-printed-plainly" (backtrace-to-string)))))
  ;; Printable: as ever.
  (let ((frames (list (backtrace-make-frame :evald t :fun 'car :args '((1 2))))))
    (should (equal (backtrace-to-string frames) "  car((1 2))\n"))))

(ert-deftest harness/a-failure-reported-the-run-goes-on ()
  "A batch run (as tests/run.sh runs a file) whose failing test's backtrace
can't be printed: the failure's condition said, the test after it run, the
run not aborted (exit status 1, not 2)."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "harness-") t)))
         (file (expand-file-name "test-run.el" dir)))
    (with-temp-file file
      (insert ";;; -*- lexical-binding: t; -*-\n"
              (prin1-to-string
               '(advice-add 'find-lisp-object-file-name :override
                            (lambda (&rest _)
                              (signal 'file-error '("Opening input file" "Operation not permitted" "DOC")))))
              "\n(ert-deftest run/a-first () (should t))\n"
              "(ert-deftest run/b-fails () (should (= (length \"three\") 0)))\n"
              "(ert-deftest run/c-after () (should t))\n"))
    (with-temp-buffer
      (let* ((process-environment (cons (concat "TEST_TMP=" dir) process-environment))
             (status (call-process (expand-file-name invocation-name invocation-directory) nil t nil
                                   "--batch" "-Q" (concat "--init-directory=" dir "home")
                                   "-l" (expand-file-name "helper.el" +test-dir)
                                   "-l" file "-f" "ert-run-tests-batch-and-exit"))
             (output (buffer-string)))
        (should (equal (list status (string-search "Aborted" output)) (list 1 nil)))
        (should (string-search "(printed plainly: Opening input file: Operation not permitted, DOC)"
                               output))
        (should (string-search "  ert-run-tests-batch-and-exit()" output))
        (should (string-search "Test run/b-fails condition:" output))
        (should (string-search "(= (length \"three\") 0)" output))
        (should (string-match-p "passed +3/3 +run/c-after" output))
        (should (string-search "Ran 3 tests, 2 results as expected, 1 unexpected" output))))))

(ert-deftest harness/no-test-sees-the-shells-beads-settings ()
  "A batch run (as tests/run.sh runs a file) from a crew's agent's shell,
BEADS_DIR, BEADS_ACTOR, AGENT_WORKSPACE_AGENT... set: neither its tests nor
what they run see them (bd would use the project's issues); the other
variables are kept. Nor does this Emacs. bd's usage metrics are off for
them (DO_NOT_TRACK)."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "harness-") t)))
         (file (expand-file-name "test-run.el" dir))
         (crew '("BEADS_DIR" "BEADS_DB" "BEADS_ACTOR" "BD_ACTOR" "AGENT_WORKSPACE_AGENT")))
    (should-not (seq-some #'getenv crew))
    (should (equal (getenv "DO_NOT_TRACK") "1"))
    (with-temp-file file
      (insert ";;; -*- lexical-binding: t; -*-\n"
              (prin1-to-string
               `(ert-deftest run/env ()
                  (should-not (seq-some #'getenv ',crew))
                  (message "ENV<<%s>>ENV" (with-temp-buffer (call-process "env" nil t nil) (buffer-string)))))))
    (with-temp-buffer
      (let* ((process-environment
              (append (list (concat "TEST_TMP=" dir) (concat "BEADS_DIR=" dir ".beads")
                            (concat "BEADS_DB=" dir ".beads/beads.db")
                            "BEADS_ACTOR=tester" "BD_ACTOR=tester" "AGENT_WORKSPACE_AGENT=tester")
                      process-environment))
             (status (call-process (expand-file-name invocation-name invocation-directory) nil t nil
                                   "--batch" "-Q" (concat "--init-directory=" dir "home")
                                   "-l" (expand-file-name "helper.el" +test-dir)
                                   "-l" file "-f" "ert-run-tests-batch-and-exit"))
             (output (buffer-string))
             (env (and (string-match "ENV<<\\(\\(?:.\\|\n\\)*?\\)>>ENV" output) (match-string 1 output))))
        (should (equal status 0))
        (should (string-match-p "passed +1/1 +run/env" output))
        (should (string-match-p (concat "^TEST_TMP=" (regexp-quote dir) "$") env))
        (should (string-match-p "^DO_NOT_TRACK=1$" env))
        (dolist (name crew)
          (should-not (string-match-p (concat "^" name "=") env)))))))

(ert-deftest harness/run-sh-keeps-a-failed-file-s-log ()
  "tests/run.sh with TEST_LOGS: a failed file's log copied there too, as
KIND-NAME.txt, a passing one's not; nothing failed, no folder. CI keeps it
with the run (doom-4q6)."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-") t)))
         (tests (expand-file-name "tests/" dir))
         (logs (expand-file-name "logs/" dir)))
    (make-directory (expand-file-name "unit/" tests) t)
    (make-directory (expand-file-name "scripts/" dir) t)
    (copy-file (expand-file-name "run.sh" +test-dir) (expand-file-name "run.sh" tests))
    (copy-file (expand-file-name "scripts/ui.sh" +test-root) (expand-file-name "scripts/ui.sh" dir))
    (with-temp-file (expand-file-name "helper.el" tests) (insert "(require 'ert)\n"))
    (with-temp-file (expand-file-name "unit/test-passes.el" tests)
      (insert ";;; -*- lexical-binding: t; -*-\n(ert-deftest run/passes () (should t))\n"))
    (with-temp-file (expand-file-name "unit/test-fails.el" tests)
      (insert ";;; -*- lexical-binding: t; -*-\n"
              "(ert-deftest run/fails () (message \"What it saw\") (should (= 1 2)))\n"))
    (cl-flet ((run (&rest names)
                (let ((process-environment
                       (append (list (concat "EMACS=" (expand-file-name invocation-name invocation-directory))
                                     (concat "TMPDIR=" dir) (concat "TEST_LOGS=" logs) "JOBS=2")
                               process-environment)))
                  (with-temp-buffer
                    (apply #'call-process "bash" nil t nil (expand-file-name "run.sh" tests) "unit" names)))))
      (should (= (run "passes") 0))
      (should-not (file-exists-p logs))
      (should (= (run) 1))
      (should (equal (directory-files logs nil "\\`[^.]") '("unit-test-fails.txt")))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "unit-test-fails.txt" logs))
        (should (string-search "What it saw" (buffer-string)))
        (should (string-search "Test run/fails condition:" (buffer-string)))))))
