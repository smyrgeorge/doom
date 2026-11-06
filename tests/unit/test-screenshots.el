;;; tests/unit/test-screenshots.el -*- lexical-binding: t; -*-
;; scripts/screenshots.sh and scripts/screenshots.el: the examples to capture,
;; each opened, captured (screencapture, the frame's rectangle) and closed, its
;; files gone; the script's checks and what it passes its Emacs. The capture
;; itself is never run (it needs macOS's Screen Recording permission): a
;; stand-in records it. Git with a temp HOME, as in test-examples.el.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/merge" "config/examples")
(load (expand-file-name "scripts/screenshots.el" +test-root) nil t)

(defconst +test-screenshots--script (expand-file-name "scripts/screenshots.sh" +test-root))

(defvar +test-screenshots--said nil "Progress lines, latest first.")

(defmacro +test-screenshots (&rest body)
  "BODY from one window, git with a temp HOME, progress lines recorded in
`+test-screenshots--said'; merges left open closed after."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "shots-home-") t)))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0")
                     process-environment))
            (+test-screenshots--said nil))
       (with-temp-file (expand-file-name ".gitconfig" home))
       (cl-letf (((symbol-function '+my/screenshots--say)
                  (lambda (format-string &rest args)
                    (push (apply #'format format-string args) +test-screenshots--said)))
                 ((symbol-function '+test-sleep) #'ignore))
         (unwind-protect (progn ,@body)
           (+my/screenshots--close))))))

(defun +test-screenshots--merges ()
  "The merges open."
  (seq-filter #'identity (mapcar (lambda (buffer) (buffer-local-value '+my/merge--session buffer))
                                 (buffer-list))))

;; ====== WHICH ======

(ert-deftest screenshots/every-example-or-those-named ()
  (let ((process-environment (cons "SCREENSHOT_EXAMPLES=" process-environment)))
    (should (equal (+my/screenshots--names) (+my/examples)))
    (should (member "merge" (+my/screenshots--names))))
  (let ((process-environment (cons "SCREENSHOT_EXAMPLES=merge  other" process-environment)))
    (should (equal (+my/screenshots--names) '("merge" "other")))))

;; ====== THE CAPTURE ======

(ert-deftest screenshots/capture-the-frames-rectangle ()
  "screencapture, silent, a PNG of the frame's outer edges (its title bar
too); a file left from before replaced."
  (let* ((file (+test-tmp-file "shots/a.png"))
         (calls nil))
    (with-temp-file file (insert "old"))
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(40 70 1884 1176)))
              ((symbol-function 'call-process)
               (lambda (program &rest args)
                 (push (cons program (nthcdr 3 args)) calls)
                 (should-not (file-exists-p file))   ; the old one gone first
                 (with-temp-file file (insert "png"))
                 0)))
      (should (eq (+my/screenshots--capture (selected-frame) file) t)))
    (should (equal calls `(("screencapture" "-x" "-t" "png" "-R" "40,70,1844,1106" ,file))))
    ;; SCREENCAPTURE: another program.
    (let ((process-environment (cons "SCREENCAPTURE=/bin/fake" process-environment)))
      (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(0 0 10 10)))
                ((symbol-function 'call-process)
                 (lambda (program &rest _) (push program calls) 0)))
        (+my/screenshots--capture (selected-frame) file)))
    (should (equal (car calls) "/bin/fake"))))

(ert-deftest screenshots/capture-failed ()
  "screencapture failed, or made no file (no Screen Recording permission):
not captured, why (what it said, its exit status)."
  (let ((file (+test-tmp-file "shots/b.png")))
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(0 0 10 10)))
              ((symbol-function 'call-process)
               (lambda (_program _infile destination &rest _)
                 (should (eq destination t))
                 (insert "could not create image from rect\n")
                 1)))
      (should (equal (+my/screenshots--capture (selected-frame) file)
                     "could not create image from rect, exit 1")))
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(0 0 10 10)))
              ((symbol-function 'call-process) (lambda (&rest _) 0)))
      (should (equal (+my/screenshots--capture (selected-frame) file) "exit 0, no file made")))))

;; ====== AN EXAMPLE ======

(ert-deftest screenshots/an-example-opened-captured-closed ()
  "The merge example: captured with its panes open, then closed: no merge
left, its repository deleted, one window again; the file said."
  (+test-screenshots
    (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "shots-") t)))
           (seen nil))
      (cl-letf (((symbol-function '+my/screenshots--capture)
                 (lambda (frame file)
                   (let ((session (car (+test-screenshots--merges))))
                     (setq seen (list frame file session (+my/merge-toplevel session)
                                      (length (window-list frame 'nomini))))
                     (with-temp-file file (insert "png"))
                     t))))
        (should (+my/screenshots--one "merge" dir)))
      (pcase-let ((`(,frame ,file ,session ,repo ,windows) seen))
        (should (eq frame (selected-frame)))
        (should (equal file (expand-file-name "merge.png" dir)))
        (should (+my/merge-p session))
        (should (>= windows 4))                     ; the bar, the three panes
        (should (+my/merge-finished session))
        (should-not (file-exists-p repo)))
      (should-not (+test-screenshots--merges))
      (should (= (length (window-list nil 'nomini)) 1))
      (should (equal +test-screenshots--said (list (expand-file-name "merge.png" dir)))))))

(ert-deftest screenshots/not-captured-still-closed ()
  (+test-screenshots
    (let ((repo nil))
      (cl-letf (((symbol-function '+my/screenshots--capture)
                 (lambda (&rest _)
                   (setq repo (+my/merge-toplevel (car (+test-screenshots--merges))))
                   "could not create image from rect, exit 1")))
        (should-not (+my/screenshots--one "merge" (+test-tmp-file "shots-c/"))))
      (should-not (+test-screenshots--merges))
      (should-not (file-exists-p repo))
      (should (string-prefix-p "merge: not captured (screencapture: could not create image from rect, exit 1). The terminal running this needs the Screen Recording permission"
                               (car +test-screenshots--said))))))

(ert-deftest screenshots/an-example-that-fails ()
  (+test-screenshots
    (cl-letf (((symbol-function '+my/example-merge) (lambda () (interactive) (error "Broken"))))
      (should-not (+my/screenshots--one "merge" (+test-tmp-file "shots-d/"))))
    (should (equal +test-screenshots--said '("merge: Broken")))))

;; ====== THE SCRIPT ======

(defun +test-screenshots--sh (env &rest args)
  "Run screenshots.sh with ARGS, ENV (\"VAR=value\"...) added: (STATUS .
OUTPUT)."
  (with-temp-buffer
    (let* ((process-environment (append env process-environment))
           (status (apply #'call-process "bash" nil t nil +test-screenshots--script args)))
      (cons status (buffer-string)))))

(defun +test-screenshots--fake-emacs (status)
  "A stand-in for the GUI Emacs: notes its arguments and the environment it
got, says a line of progress, exits with STATUS. Its notes' file."
  (let ((script (+test-tmp-file (format "fake-emacs-%d" status)))
        (notes (+test-tmp-file (format "fake-emacs-%d.notes" status))))
    (with-temp-file script
      (insert "#!/bin/bash\n"
              (format "{ echo \"$@\"; echo \"$SCREENSHOT_EXAMPLES|$SCREENSHOT_DIR|$TEST_TMP\"; } > %s\n" notes)
              "echo 'screenshots: /somewhere/merge.png' >&2\n"
              "echo 'noise' >&2\n"
              (format "exit %d\n" status)))
    (set-file-modes script #o755)
    (cons script notes)))

(ert-deftest screenshots/script-wrong-uses ()
  (let ((run (+test-screenshots--sh nil "nope")))
    (should (= (car run) 2))
    (should (string-match-p "no example nope (examples/nope.el)" (cdr run))))
  (let ((run (+test-screenshots--sh nil "--help")))
    (should (= (car run) 0))
    (should (string-match-p "scripts/screenshots.sh merge" (cdr run)))))

(ert-deftest screenshots/script-runs-its-emacs ()
  "Its Emacs: -Q, its own init folder and temp folder (gone after), the test
setup and screenshots.el, the examples named; its progress lines shown, not
the rest; its exit status passed on."
  (pcase-let* ((`(,emacs . ,notes) (+test-screenshots--fake-emacs 0))
               (run (+test-screenshots--sh (list (concat "EMACS_GUI=" emacs) "SCREENSHOT_DIR=/out")
                                           "merge")))
    (should (= (car run) 0))
    (should (equal (cdr run) "/somewhere/merge.png\n"))
    (let* ((lines (split-string (with-temp-buffer (insert-file-contents notes) (buffer-string)) "\n" t))
           (args (split-string (nth 0 lines) " "))
           (env (split-string (nth 1 lines) "|")))
      (should (equal (nth 0 args) "-Q"))
      (should (string-prefix-p "--init-directory=" (nth 1 args)))
      (should (equal (seq-drop args 2)
                     (list "-l" (expand-file-name "tests/helper.el" +test-root)
                           "-l" (expand-file-name "scripts/screenshots.el" +test-root)
                           "-f" "+my/screenshots-run")))
      (should (equal (nth 0 env) "merge"))
      (should (equal (nth 1 env) "/out"))
      ;; Its temp folder, removed after.
      (should-not (file-exists-p (nth 2 env)))))
  (pcase-let* ((`(,emacs . ,_) (+test-screenshots--fake-emacs 1))
               (run (+test-screenshots--sh (list (concat "EMACS_GUI=" emacs)))))
    (should (= (car run) 1))
    (should (string-match-p "failed (exit 1)" (cdr run)))
    (should (string-match-p "noise" (cdr run)))))
