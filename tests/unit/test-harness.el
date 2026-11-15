;;; tests/unit/test-harness.el -*- lexical-binding: t; -*-
;; The unit test harness itself (tests/helper.el): a failed test's report,
;; its backtrace unprintable (a file it reads not read), still says its
;; condition, and the run goes on to the tests after it.

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
