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

(defvar +test-harness--stdin-open nil
  "Non-nil: `+test-harness--run-sh''s run.sh reads from a pipe left open
\(20 s), as from a terminal, not from /dev/null.")

(defvar +test-harness--durations nil
  "The tests/.durations of `+test-harness--run-sh''s copy of run.sh: its
text before the run (nil: none), set to its text after (nil: none).")

(defun +test-harness--run-sh-copy (files)
  "A copy of tests/run.sh in a temp folder of its own (its tests/), FILES its
unit tests ((NAME . CONTENT) each), its helper.el loading this one,
`+test-harness--durations' its tests/.durations: the folder."
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
    (when +test-harness--durations
      (write-region +test-harness--durations nil (expand-file-name ".durations" tests)))
    dir))

(defun +test-harness--run-sh-env (dir env)
  "The environment of the copy of run.sh in DIR: ENV (\"VAR=value\" each),
this Emacs its EMACS, its runs' folders in DIR (TMPDIR), 2 at once."
  (append env
          (list (concat "EMACS=" (expand-file-name invocation-name invocation-directory))
                (concat "TMPDIR=" dir) "JOBS=2")
          process-environment))

(defun +test-harness--run-sh (files env &rest names)
  "A copy of tests/run.sh run on FILES, unit tests ((NAME . CONTENT) each),
ENV added to its environment (\"VAR=value\" each), NAMES the files to run
(none: all): (STATUS OUTPUT). Its runs' folders in a temp folder of their
own (TMPDIR); its helper.el loads this one. Its tests/.durations
`+test-harness--durations', before and after."
  (let* ((dir (+test-harness--run-sh-copy files))
         (run-sh (expand-file-name "tests/run.sh" dir))
         (durations (expand-file-name "tests/.durations" dir)))
    (prog1 (let ((process-environment (+test-harness--run-sh-env dir env)))
             (with-temp-buffer
               (list (if +test-harness--stdin-open
                         (apply #'call-process "bash" nil t nil "-c"
                                "bash \"$0\" unit \"$@\" < <(exec sleep 20 2>/dev/null)" run-sh names)
                       (apply #'call-process "bash" nil t nil run-sh "unit" names))
                     (buffer-string))))
      (setq +test-harness--durations
            (and (file-exists-p durations)
                 (with-temp-buffer (insert-file-contents durations) (buffer-string)))))))

(defun +test-harness--mounted-p (dir)
  "Non-nil if a file system is mounted at DIR."
  (string-search (concat " on " (directory-file-name (file-truename dir)) " (")
                 (with-temp-buffer (call-process "mount" nil t) (buffer-string))))

(defun +test-harness--ram-disk (dir)
  "A RAM disk of 16 MB mounted at DIR/ram, as run.sh mounts its own."
  (let ((dev (car (split-string (with-temp-buffer
                                  (call-process "hdiutil" nil t nil "attach" "-nomount" "ram://32768")
                                  (buffer-string))))))
    (make-directory (expand-file-name "ram" dir) t)
    (should (eql 0 (call-process "newfs_hfs" nil nil nil "-v" "doom-tests" dev)))
    (should (eql 0 (call-process "diskutil" nil nil nil "mount" "nobrowse" "-mountPoint"
                                 (expand-file-name "ram" dir) dev)))
    (should (+test-harness--mounted-p (expand-file-name "ram" dir)))))

(defun +test-harness--detach (dir)
  "DIR/ram detached, if it's mounted."
  (when (+test-harness--mounted-p (expand-file-name "ram" dir))
    (call-process "hdiutil" nil nil nil "detach" (expand-file-name "ram" dir) "-force" "-quiet")))

(defun +test-harness--log-folder (output name)
  "The run folder of the file NAME (test-NAME.el) whose full log OUTPUT
shows."
  (and (string-match (concat "full log: \\(.*/unit-test-" name "\\)/log\\.txt") output)
       (file-name-as-directory (match-string 1 output))))

(defun +test-harness--shown-in-order (output names)
  "Non-nil if OUTPUT shows the results of the files NAMES (test-a...) in
that order."
  (let ((at (mapcar (lambda (name) (string-match (concat "unit +" name " ") output)) names)))
    (and (not (memq nil at)) (equal at (sort (copy-sequence at) #'<)))))

(ert-deftest harness/run-sh-longest-first-each-result-as-it-ends ()
  "tests/run.sh starts the longest files first, as long as each took in its
last run (tests/.durations), a file marked slow first when no run timed it;
each result shows as its file ends, not in file order (the first one was
shown after 200 s: test-actions.el started after every slow one). Each
file's time written back for the next run, the other files' and kinds'
kept. One at a time (JOBS=1): the order they end in, they start in."
  (let ((files '(("test-a.el" . "(ert-deftest run/a () (should t))\n")
                 ("test-b.el" . "(ert-deftest run/b () (should t))\n")
                 ("test-c.el" . ";; run.sh: slow (marked).\n(ert-deftest run/c () (should t))\n"))))
    (let ((+test-harness--durations nil))
      (pcase-let ((`(,status ,output) (+test-harness--run-sh files '("RAM_DISK=0" "JOBS=1"))))
        (should (= status 0))
        (should (+test-harness--shown-in-order output '("test-c" "test-a" "test-b")))
        (dolist (name '("a" "b" "c"))
          (should (string-match-p (format "^unit test-%s 1 [0-9]+$" name) +test-harness--durations)))))
    (let ((+test-harness--durations
           "unit test-a 1 3\nunit test-b 1 40\nunit test-c 1 1\nunit test-gone 1 7\ne2e test-a 1 99\n"))
      (pcase-let ((`(,status ,output) (+test-harness--run-sh files '("RAM_DISK=0" "JOBS=1"))))
        (should (= status 0))
        (should (+test-harness--shown-in-order output '("test-b" "test-a" "test-c")))
        (should (string-match-p "^unit test-gone 1 7$" +test-harness--durations))
        (should (string-match-p "^e2e test-a 1 99$" +test-harness--durations))
        (should-not (string-match-p "^unit test-b 1 40$" +test-harness--durations))
        (should (= (length (split-string +test-harness--durations "\n" t)) 5))))
    ;; Only some run: the others' times kept.
    (let ((+test-harness--durations "unit test-a 1 3\nunit test-b 1 40\n"))
      (+test-harness--run-sh files '("RAM_DISK=0" "JOBS=1") "a")
      (should (string-match-p "^unit test-b 1 40$" +test-harness--durations))
      (should (string-match-p "^unit test-a 1 [0-9]+$" +test-harness--durations)))))

(ert-deftest harness/run-sh-tests-read-nothing ()
  "A test asking (y-or-n-p) gets no answer: its Emacs's stdin /dev/null,
whatever run.sh's is (a terminal, a pipe left open), the question an error
at once. Bash 3.2 gave it run.sh's stdin once a loop had read from <<<:
the question waited on the terminal, the file never ended."
  (let ((+test-harness--stdin-open t)
        (start (float-time)))
    (pcase-let ((`(,status ,output)
                 (+test-harness--run-sh '(("test-asks.el" . "(ert-deftest run/asks () (should-error (y-or-n-p \"Go? \")))\n"))
                                        '("RAM_DISK=0"))))
      (should (= status 0))
      (should (string-match-p "unit +test-asks +1 tests" output))
      (should (< (- (float-time) start) 15)))))

(ert-deftest harness/run-sh-a-lane-for-the-shortest ()
  "With 4 slots or more, one takes the shortest file first, the others the
longest (results show from the start); a file running alone first, by
itself, then both lanes (it isn't starved by the short ones). Each file
notes when run.sh started it (its Emacs process's start), then takes 2 s.
Noting when its test ran instead counted its Emacs's loading too: under
CI's load, one of the first wave was over 1.5 s late (Linux)."
  (let* ((when (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-when-") t)))
         (file (lambda (name &optional mark)
                 (cons (format "test-%s.el" name)
                       (format "%s(ert-deftest run/%s () (write-region (format \"%%f\" (float-time (alist-get 'start (process-attributes (emacs-pid))))) nil %S) (sleep-for 2))\n"
                               (if mark (concat mark "\n") "") name (expand-file-name name when)))))
         (files (list (funcall file "a") (funcall file "b") (funcall file "c") (funcall file "d")
                      (funcall file "e") (funcall file "f") (funcall file "g" ";; run.sh: alone (by the clock)")))
         (+test-harness--durations
          "unit test-a 1 50\nunit test-b 1 40\nunit test-c 1 30\nunit test-d 1 20\nunit test-e 1 1\nunit test-f 1 2\nunit test-g 1 3\n"))
    (pcase-let ((`(,status ,_) (+test-harness--run-sh files '("RAM_DISK=0" "JOBS=4"))))
      (should (= status 0))
      (let* ((started (mapcar (lambda (name)
                                (cons name (with-temp-buffer
                                             (insert-file-contents (expand-file-name name when))
                                             (string-to-number (buffer-string)))))
                              '("a" "b" "c" "d" "e" "f" "g")))
             (g (alist-get "g" started nil nil #'equal))
             (others (cl-remove "g" started :key #'car :test #'equal))
             (first (apply #'min (mapcar #'cdr others))))
        ;; g alone, before them.
        (should (>= first (+ g 1.5)))
        ;; The first wave (within 1.5 s of the first): the 3 longest, and the shortest.
        (should (equal (sort (mapcar #'car (seq-filter (lambda (s) (< (cdr s) (+ first 1.5))) others)) #'string<)
                       '("a" "b" "c" "e")))))))

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

(ert-deftest harness/run-sh-ram-disk-detached-however-it-ends ()
  "Killed with kill -9 (no trap runs), its RAM disk detached all the same
and its test still running stopped: a watcher of its own sees it gone. A
run so killed left its disk mounted, its memory taken (doom-694)."
  (skip-unless (and (eq system-type 'darwin) (executable-find "hdiutil")))
  (let* ((dir (+test-harness--run-sh-copy
               '(("test-long.el" . "(ert-deftest run/long ()
  (write-region \"\" nil (expand-file-name \"started\" (getenv \"TEST_TMP\")))
  (sleep-for 60))\n"))))
         (process (let ((process-environment (+test-harness--run-sh-env dir '("RAM_DISK=16"))))
                    (make-process :name "run-sh" :noquery t :buffer nil :connection-type 'pipe
                                  :command (list "bash" (expand-file-name "tests/run.sh" dir) "unit"))))
         (started nil))
    (unwind-protect
        (progn
          (setq started (+test-wait-for
                         (lambda () (car (file-expand-wildcards
                                          (expand-file-name "doom-tests.*/ram/unit-test-long/started" dir))))
                         30))
          (should started)
          (let* ((run (file-name-as-directory (expand-file-name "../../.." started)))
                 (emacs (string-to-number (with-temp-buffer
                                            (insert-file-contents (expand-file-name "unit-test-long/pid" run))
                                            (buffer-string)))))
            (should (+test-harness--mounted-p (expand-file-name "ram" run)))
            (should (process-attributes emacs))
            (signal-process process 'SIGKILL)
            (should (+test-wait-for (lambda () (not (+test-harness--mounted-p (expand-file-name "ram" run)))) 15))
            (should (+test-wait-for (lambda () (not (process-attributes emacs))) 5))))
      (when (process-live-p process) (delete-process process))
      (dolist (run (file-expand-wildcards (expand-file-name "doom-tests.*" dir)))
        (+test-harness--detach run)))))

(ert-deftest harness/run-sh-detaches-disks-left ()
  "As a run starts, the RAM disks other runs left are detached: one whose
run.pid isn't a run.sh running, and one without (made before it) untouched
for 6 hours. Kept: a run's going on (its run.pid a run.sh running), and one
without a run.pid changed lately (an older run.sh's, running)."
  (skip-unless (and (eq system-type 'darwin) (executable-find "hdiutil")))
  (let* ((root (file-name-as-directory (make-temp-file (+test-tmp-file "run-sh-left-") t)))
         (runs (mapcar (lambda (name)
                         (let ((run (file-name-as-directory (expand-file-name (concat "doom-tests." name) root))))
                           (make-directory run t)
                           (cons name run)))
                       '("dead" "old" "running" "recent")))
         (running (start-process "run.sh stand-in" nil "bash" "-c" "sleep 60; :" "run.sh")))
    (unwind-protect
        (progn
          (pcase-dolist (`(,_ . ,run) runs) (+test-harness--ram-disk run))
          (write-region "999999\n" nil (expand-file-name "run.pid" (alist-get "dead" runs nil nil #'equal)))
          (write-region (format "%d\n" (process-id running)) nil
                        (expand-file-name "run.pid" (alist-get "running" runs nil nil #'equal)))
          (set-file-times (alist-get "old" runs nil nil #'equal) (time-subtract nil (* 7 3600)))
          (pcase-let ((`(,status ,_) (+test-harness--run-sh '(("test-a.el" . "(ert-deftest run/a () (should t))\n"))
                                                            '("RAM_DISK=0"))))
            (should (= status 0)))
          (should-not (+test-harness--mounted-p (expand-file-name "ram" (alist-get "dead" runs nil nil #'equal))))
          (should-not (+test-harness--mounted-p (expand-file-name "ram" (alist-get "old" runs nil nil #'equal))))
          (should (+test-harness--mounted-p (expand-file-name "ram" (alist-get "running" runs nil nil #'equal))))
          (should (+test-harness--mounted-p (expand-file-name "ram" (alist-get "recent" runs nil nil #'equal)))))
      (delete-process running)
      (pcase-dolist (`(,_ . ,run) runs) (+test-harness--detach run)))))

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
