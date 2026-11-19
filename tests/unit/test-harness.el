;;; tests/unit/test-harness.el -*- lexical-binding: t; -*-
;; The unit test harness itself (tests/helper.el): a failed test's report,
;; its backtrace unprintable (a file it reads not read), still says its
;; condition, and the run goes on to the tests after it; no test sees the
;; shell's Beads settings; tests/run.sh keeps a failed file's log in
;; TEST_LOGS; a page's question unanswered in a wait is asked again.

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

(ert-deftest harness/a-page-s-question-unanswered-in-a-wait-asked-again ()
  "`+test-js' in a wait's predicate, WebKit not answering in its time (a
loaded machine, its page hidden: doom-5kt): the wait asks again, under its
own clock, not ended by an error; outside a wait, an error."
  (let ((asked 0))
    (cl-letf (((symbol-function '+test--pump) (lambda (seconds) (accept-process-output nil seconds)))
              ((symbol-function 'xwidget-webkit-execute-script)
               (lambda (_xwidget _script callback)
                 (when (= (cl-incf asked) 3)
                   (run-at-time 0 nil callback "true")))))
      (should (equal (+test-wait-for (lambda () (+test-js 'page "String(true)" 0.2)) 5) "true"))
      (should (= asked 3))
      (should (equal (should-error (+test-js 'page "String(1)" 0.2) :type '+test-js-no-answer)
                     '(+test-js-no-answer "String(1)"))))))

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

;; ====== TESTS/RUN.SH ======

(defun +test-harness--run-sh (files env &rest names)
  "A copy of tests/run.sh run on FILES, unit tests ((NAME . CONTENT) each),
ENV added to its environment (\"VAR=value\" each), NAMES the files to run
(none: all): (STATUS OUTPUT). Its runs' folders in a temp folder of their
own (TMPDIR); its helper.el loads this one."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-") t)))
         (tests (expand-file-name "tests/" dir)))
    (make-directory (expand-file-name "unit/" tests) t)
    (make-directory (expand-file-name "scripts/" dir) t)
    (copy-file (expand-file-name "run.sh" +test-dir) (expand-file-name "run.sh" tests))
    (copy-file (expand-file-name "scripts/ui.sh" +test-root) (expand-file-name "scripts/ui.sh" dir))
    (with-temp-file (expand-file-name "helper.el" tests)
      (prin1 `(load ,(expand-file-name "helper.el" +test-dir) nil t) (current-buffer)))
    (pcase-dolist (`(,name . ,content) files)
      (with-temp-file (expand-file-name (concat "unit/" name) tests)
        (insert ";;; -*- lexical-binding: t; -*-\n" content)))
    (let ((process-environment
           (append env
                   (list (concat "EMACS=" (expand-file-name invocation-name invocation-directory))
                         (concat "TMPDIR=" dir) "JOBS=2")
                   process-environment)))
      (with-temp-buffer
        (list (apply #'call-process "bash" nil t nil (expand-file-name "run.sh" tests) "unit" names)
              (buffer-string))))))

(defun +test-harness--log-folder (output name)
  "The run folder of the file NAME (test-NAME.el) whose full log OUTPUT
shows."
  (and (string-match (concat "full log: \\(.*/unit-test-" name "\\)/log\\.txt") output)
       (file-name-as-directory (match-string 1 output))))

(ert-deftest harness/run-sh-keeps-a-failed-file-s-log ()
  "tests/run.sh with TEST_LOGS: a failed file's log copied there too, as
KIND-NAME.txt, a passing one's not; nothing failed, no folder. CI keeps it
with the run (doom-4q6)."
  (let ((logs (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-logs-") t)))
        (files '(("test-passes.el" . "(ert-deftest run/passes () (should t))\n")
                 ("test-fails.el" . "(ert-deftest run/fails () (message \"What it saw\") (should (= 1 2)))\n"))))
    (delete-directory logs)
    (cl-flet ((run (&rest names)
                (car (apply #'+test-harness--run-sh files (list (concat "TEST_LOGS=" logs) "RAM_DISK=0") names))))
      (should (= (run "passes") 0))
      (should-not (file-exists-p logs))
      (should (= (run) 1))
      (should (equal (directory-files logs nil "\\`[^.]") '("unit-test-fails.txt")))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "unit-test-fails.txt" logs))
        (should (string-search "What it saw" (buffer-string)))
        (should (string-search "Test run/fails condition:" (buffer-string)))))))

(ert-deftest harness/run-sh-runs-a-split-file-in-parts ()
  "A file with \";; run.sh: split 2\": its tests in two Emacsen, each test
once; the parts' results one line, their tests added up; a failure in one
part reported, its log in TEST_LOGS. The selector of a part: every PARTS-th
test by name."
  (let* ((logs (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-logs-") t)))
         (ran (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-ran-") t)))
         ;; Each test a file of its own there (two Emacsen writing one: a lock
         ;; conflict).
         (test (lambda (name ok)
                 (format "(ert-deftest run/%s () (write-region \"\" nil %S) (should %s))\n"
                         name (expand-file-name name ran) ok))))
    (pcase-let ((`(,status ,output)
                 (+test-harness--run-sh
                  `(("test-parts.el" . ,(concat ";; run.sh: split 2 (two at once).\n"
                                                (funcall test "a" "t") (funcall test "b" "t")
                                                (funcall test "c-fails" "(= 1 2)"))))
                  (list (concat "TEST_LOGS=" logs) "RAM_DISK=0"))))
      (should (= status 1))
      (should (string-match-p "test-parts +FAIL 3 tests, 1 failed · [0-9.]+ s, in 2 parts" output))
      (should (string-search "Test run/c-fails condition:" output))
      (should (string-match-p "full log: .*/unit-test-parts\\.1/log\\.txt" output))
      (should-not (string-search "unit-test-parts.2/log.txt" output))
      ;; Each test once, the first part's a and c-fails, the second's b.
      (should (equal (directory-files ran nil "\\`[^.]") '("a" "b" "c-fails")))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "unit-test-parts.txt" logs))
        (should (string-search "Test run/c-fails condition:" (buffer-string))))))
  ;; This Emacs's tests (this file's): the first part every other one by
  ;; name, from the first; a part beyond them, none.
  (let* ((names (sort (mapcar #'ert-test-name (ert-select-tests t t)) #'string<))
         (one (cdr (+test-part-selector 1 2)))
         (two (cdr (+test-part-selector 2 2))))
    (should (> (length names) 2))
    (should (equal (cdr (+test-part-selector 1 1)) names))
    (should (equal one (cl-loop for name in names for i from 0 when (cl-evenp i) collect name)))
    (should (equal (sort (append one two) #'string<) names))
    (should (equal (+test-part-selector (1+ (length names)) (1+ (length names))) '(member)))))

(ert-deftest harness/run-sh-on-a-ram-disk ()
  "On macOS, the files' folders (TEST_TMP) on a RAM disk of the run's own,
hidden from the Finder; a failed file's folder copied beside its log; the
disk gone once the run ends. RAM_DISK=0: on the disk, beside the log."
  (skip-unless (and (eq system-type 'darwin) (executable-find "hdiutil")))
  (let ((files '(("test-disk.el" . "(ert-deftest run/disk ()
  (write-region (getenv \"TEST_TMP\") nil (expand-file-name \"where\" (getenv \"TEST_TMP\")))
  (message \"MOUNTS<<%s>>\" (with-temp-buffer (call-process \"mount\" nil t) (buffer-string)))
  (should nil))\n"))))
    (pcase-let* ((`(,status ,output) (+test-harness--run-sh files '("RAM_DISK=64")))
                 (folder (+test-harness--log-folder output "disk"))
                 (run (file-name-directory (directory-file-name folder)))
                 (ram (concat run "ram")))
      (should (= status 1))
      (should (equal (with-temp-buffer (insert-file-contents (concat folder "where")) (buffer-string))
                     (concat ram "/unit-test-disk")))
      (with-temp-buffer
        (insert-file-contents (concat folder "log.txt"))
        (should (string-match-p (concat " on " (regexp-quote ram) " (hfs, .*nobrowse") (buffer-string))))
      (should-not (string-search ram (with-temp-buffer (call-process "mount" nil t) (buffer-string)))))
    (pcase-let* ((`(,status ,output) (+test-harness--run-sh files '("RAM_DISK=0")))
                 (folder (+test-harness--log-folder output "disk")))
      (should (= status 1))
      (should (equal (with-temp-buffer (insert-file-contents (concat folder "where")) (buffer-string))
                     (directory-file-name folder))))))
