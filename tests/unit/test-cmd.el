;;; tests/unit/test-cmd.el -*- lexical-binding: t; -*-
;; cmd/diff: Git conflicts resolved in the merge's panes from the shell.
;; The script really runs, in a pseudo-terminal (`script'), its Emacs a test
;; one (tests/fixtures/diff-emacs.el: each merge then done by itself), new
;; (--new) or a test server (--socket): never the user's Emacs. Real git in
;; temp repos, a temp HOME and global gitconfig.

(defconst +test-cmd--script (expand-file-name "cmd/diff" +test-root))

(defconst +test-cmd--emacs (expand-file-name invocation-name invocation-directory)
  "This Emacs's binary (the GUI app's: -nw in a terminal).")

(defun +test-cmd--emacs-args (home)
  "Arguments for the script's Emacs: a test one (see above); no spaces in
them (the script splits EMACS_ARGS on spaces)."
  (format "-Q --init-directory=%s -l %s"
          (expand-file-name "init" home)
          (expand-file-name "fixtures/diff-emacs.el" +test-dir)))

(defmacro +test-cmd-with-repo (&rest body)
  "BODY in a new repo (`default-directory') where a.txt and b.txt are in
conflict (feature merged into main), `home' a temp HOME (and the script's
Emacs's), `log' where its merges are noted."
  (declare (indent 0))
  `(let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "cmd-home-") t)))
          (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "cmd-repo-") t))))
          (log (expand-file-name "merges.log" home))
          (process-environment
           (append (list (concat "HOME=" home)
                         (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                         "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0" "GIT_EDITOR=true"
                         "TERM=xterm-256color"
                         "COLORTERM"      ; not set (a test sets it)
                         ;; Doom's own folder: HOME is another.
                         (concat "DOOM_EMACS_DIR=" +test-doom-emacs-dir)
                         (concat "TEST_TMP=" (expand-file-name "emacs-tmp" home))
                         (concat "DIFF_TEST_LOG=" log)
                         (concat "EMACS=" +test-cmd--emacs)
                         (concat "EMACS_ARGS=" (+test-cmd--emacs-args home)))
                   process-environment))
          (default-directory repo))
     (with-temp-file (expand-file-name ".gitconfig" home)
       (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
               "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
     (+test-cmd--git "init" "-q")
     (dolist (file '("a.txt" "b.txt"))
       (with-temp-file file (insert "one\ntwo\nthree\n")))
     (+test-cmd--git "add" ".")
     (+test-cmd--git "commit" "-qm" "base")
     (+test-cmd--git "checkout" "-qb" "feature")
     (dolist (file '("a.txt" "b.txt"))
       (with-temp-file file (insert "one\ntheirs\nthree\n")))
     (+test-cmd--git "commit" "-qam" "theirs")
     (+test-cmd--git "checkout" "-q" "main")
     (dolist (file '("a.txt" "b.txt"))
       (with-temp-file file (insert "one\nyours\nthree\n")))
     (+test-cmd--git "commit" "-qam" "yours")
     (with-temp-buffer (call-process "git" nil t nil "merge" "-q" "feature"))
     ,@body))

(defun +test-cmd--git (&rest args)
  (with-temp-buffer
    (unless (zerop (apply #'call-process "git" nil t nil args))
      (error "git %s: %s" (string-join args " ") (buffer-string)))
    (buffer-string)))

(defun +test-cmd--run (&rest args)
  "Run cmd/diff with ARGS in a pseudo-terminal: (STATUS . OUTPUT); killed
after 90 s (STATUS then `timeout')."
  (with-temp-buffer
    (let* ((buffer (current-buffer))
           ;; The terminal a size, as a real one has (with nothing attached,
           ;; script's has none: a server's frame there was too small).
           (command (append (list "bash" "-c"
                                  "stty cols 120 rows 40 2>/dev/null; exec bash \"$0\" \"$@\""
                                  +test-cmd--script)
                            args))
           ;; script(1) runs it in a pseudo-terminal: BSD's (macOS) takes the
           ;; command as arguments, util-linux's (Linux) as one string (-c),
           ;; its exit status passed on with -e.
           (process (make-process :name "diff" :buffer buffer :connection-type 'pipe
                                  :sentinel #'+test-process-sentinel
                                  :command (if (eq system-type 'darwin)
                                               (append (list "script" "-q" "/dev/null") command)
                                             (list "script" "-q" "-e" "-c"
                                                   (mapconcat #'shell-quote-argument command " ")
                                                   "/dev/null"))))
           (end (+ (float-time) 90)))
      ;; No input: a wrong use may have exited already (at once, 2), and a
      ;; finished process can't be sent its end (CI's macOS runner).
      (when (process-live-p process)
        (condition-case nil
            (process-send-eof process)
          (error (when (process-live-p process)
                   (error "Couldn't end cmd/diff's input")))))
      ;; Its output all read: not merely ended (`+test-process-sentinel'):
      ;; --help's was read empty once, on CI's macOS.
      (while (and (not (+test-process-ended-p process)) (< (float-time) end))
        (accept-process-output process 0.1))
      (if (not (+test-process-ended-p process))
          (progn (kill-process process) (cons 'timeout (buffer-string)))
        (cons (process-exit-status process) (buffer-string))))))

(defun +test-cmd--log (log &optional colours)
  "The merges LOG noted: \"PATH tty|gui\" each, and its frame's number of
colours if COLOURS."
  (and (file-exists-p log)
       (mapcar (lambda (line) (if colours line (replace-regexp-in-string " [0-9]+\\'" "" line)))
               (split-string (with-temp-buffer (insert-file-contents log) (buffer-string)) "\n" t))))

(defun +test-cmd--unmerged ()
  (split-string (+test-cmd--git "diff" "--name-only" "--diff-filter=U") "\n" t))

;; ====== USE ======

(ert-deftest cmd/help-and-wrong-uses ()
  (let ((help (+test-cmd--run "--help")))
    (should (= (car help) 0))
    (should (string-match-p "cmd/diff FILE\\.\\.\\." (cdr help)))
    (should (string-match-p "-g, --gui" (cdr help))))
  (let ((wrong (+test-cmd--run "--bogus")))
    (should (= (car wrong) 2))
    (should (string-match-p "unknown option --bogus" (cdr wrong))))
  (let* ((default-directory (file-name-as-directory (make-temp-file (+test-tmp-file "not-a-repo-") t)))
         (outside (+test-cmd--run "--new")))
    (should (= (car outside) 2))
    (should (string-match-p "not in a Git repository" (cdr outside))))
  (should (= (car (+test-cmd--run "--socket")) 2)))

(ert-deftest cmd/list-and-nothing-to-do ()
  (+test-cmd-with-repo
    (let ((listed (+test-cmd--run "--list")))
      (should (= (car listed) 0))
      ;; (script echoes the end of its input: ^D and backspaces.)
      (should (equal (delq nil (mapcar (lambda (line)
                                         (and (string-match "\\([[:alnum:]_./-]+\\.txt\\)" line)
                                              (match-string 1 line)))
                                       (split-string (cdr listed) "[\r\n]+" t)))
                     '("a.txt" "b.txt"))))
    (should (= (car (+test-cmd--run "--new" "missing.txt")) 2))
    (+test-cmd--git "checkout" "--theirs" "--" "a.txt" "b.txt")
    (+test-cmd--git "add" "a.txt" "b.txt")
    (let ((none (+test-cmd--run "--new")))
      (should (= (car none) 0))
      (should (string-match-p "No conflicts here" (cdr none))))))

;; ====== A NEW EMACS ======

(ert-deftest cmd/each-conflict-one-after-the-other ()
  (+test-cmd-with-repo
    (let* ((process-environment (cons "DIFF_TEST_ACTION=right" process-environment))
           (run (+test-cmd--run "--new")))
      (should (= (car run) 0))
      (should (string-match-p "Resolved: 2 files" (cdr run)))
      ;; In a terminal, one after the other.
      (should (equal (+test-cmd--log log) '("a.txt tty" "b.txt tty")))
      (should-not (+test-cmd--unmerged))
      (should (equal (with-temp-buffer (insert-file-contents "a.txt") (buffer-string)) "one\ntheirs\nthree\n")))))

(ert-deftest cmd/the-files-given ()
  (+test-cmd-with-repo
    (make-directory "sub")
    (let* ((process-environment (cons "DIFF_TEST_ACTION=right" process-environment))
           (default-directory (expand-file-name "sub/"))
           (run (+test-cmd--run "--new" "../b.txt")))
      (should (= (car run) 0))
      (should (equal (+test-cmd--log log) '("b.txt tty"))))
    (should (equal (+test-cmd--unmerged) '("a.txt")))))

(ert-deftest cmd/aborted-still-in-conflict ()
  (+test-cmd-with-repo
    (let* ((process-environment (cons "DIFF_TEST_ACTION=abort" process-environment))
           (run (+test-cmd--run "--new")))
      (should (= (car run) 1))
      (should (string-match-p "Still in conflict: a.txt b.txt" (cdr run)))
      ;; Aborted, the next one all the same.
      (should (equal (+test-cmd--log log) '("a.txt tty" "b.txt tty")))
      (should (equal (+test-cmd--unmerged) '("a.txt" "b.txt"))))))

(ert-deftest cmd/the-example ()
  (+test-cmd-with-repo
    (let* ((process-environment (cons "DIFF_TEST_ACTION=right" process-environment))
           (run (+test-cmd--run "--new" "example")))
      (should (= (car run) 0))
      (should (equal (+test-cmd--log log) '("orders.py tty")))
      ;; Its repository gone.
      (should-not (directory-files (expand-file-name "emacs-tmp/tmp/" home) nil "merge-example-")))))

;; ====== A SERVER ======

(ert-deftest cmd/a-running-emacs ()
  "An Emacs server running (here a test one, --socket): a new frame of it, in
this terminal; the server still running after."
  (+test-cmd-with-repo
    ;; A name, not a path: a socket's path has at most ~104 characters, the
    ;; test's folders more. In Emacs's socket folder (the user's server's has
    ;; another name).
    (let* ((socket (format "doom-test-diff-%d-%d" (emacs-pid) (random 100000)))
           (process-environment (cons "DIFF_TEST_ACTION=right" process-environment)))
      (apply #'call-process +test-cmd--emacs nil nil nil
             (concat "--daemon=" socket)
             (split-string (+test-cmd--emacs-args home)))
      (unwind-protect
          (progn
            (should (zerop (call-process "emacsclient" nil nil nil "-s" socket "-e" "t")))
            (let ((run (+test-cmd--run "--socket" socket)))
              (should (= (car run) 0))
              (should (string-match-p "Resolved: 2 files" (cdr run))))
            ;; A terminal without 24-bit colour: its 256.
            (should (equal (+test-cmd--log log t) '("a.txt tty 256" "b.txt tty 256")))
            (should-not (file-exists-p (expand-file-name ".terminfo" home)))
            (should-not (+test-cmd--unmerged))
            ;; Still running, its frame gone.
            (should (zerop (call-process "emacsclient" nil nil nil "-s" socket "-e" "t"))))
        (call-process "emacsclient" nil nil nil "-s" socket "-e" "(kill-emacs)")))))

(ert-deftest cmd/a-running-emacs-in-24-bit-colour ()
  "The terminal has 24-bit colour (COLORTERM), the server not (started
elsewhere): its frame has them all the same, through a terminfo entry put in
~/.terminfo the first time."
  (+test-cmd-with-repo
    (let* ((socket (format "doom-test-diff-%d-%d" (emacs-pid) (random 100000)))
           (process-environment (cons "DIFF_TEST_ACTION=right" process-environment)))
      ;; The server: no COLORTERM.
      (apply #'call-process +test-cmd--emacs nil nil nil
             (concat "--daemon=" socket)
             (split-string (+test-cmd--emacs-args home)))
      (unwind-protect
          (let ((process-environment (cons "COLORTERM=truecolor" process-environment)))
            (let ((run (+test-cmd--run "--socket" socket "a.txt")))
              (should (= (car run) 0))
              (should (string-match-p "installed xterm-24bit in ~/.terminfo" (cdr run))))
            (should (equal (+test-cmd--log log t) '("a.txt tty 16777216")))
            (should (directory-files-recursively (expand-file-name ".terminfo" home) "\\`xterm-24bit\\'"))
            ;; Once: then there.
            (let ((run (+test-cmd--run "--socket" socket "b.txt")))
              (should (= (car run) 0))
              (should-not (string-match-p "installed" (cdr run))))
            (should (equal (+test-cmd--log log t) '("a.txt tty 16777216" "b.txt tty 16777216"))))
        (call-process "emacsclient" nil nil nil "-s" socket "-e" "(kill-emacs)")))))
