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

;; ====== THE LOOK ======

(ert-deftest screenshots/doom-s-frame ()
  "As Doom has it, not as `emacs -Q': no tool bar, no scroll bars, no cursor
in the windows not selected; the theme."
  (let ((tool-bar (bound-and-true-p tool-bar-mode))
        (scroll-bar (bound-and-true-p scroll-bar-mode))
        (cursor (default-value 'cursor-in-non-selected-windows)))
    (unwind-protect
        (cl-letf (((symbol-function 'doom-modeline-mode) #'ignore)
                  ((symbol-function 'global-tab-line-mode) #'ignore))
          (+my/screenshots--setup)
          (should-not (bound-and-true-p tool-bar-mode))
          (should-not scroll-bar-mode)
          (should-not (default-value 'cursor-in-non-selected-windows))
          (should (memq 'doom-one custom-enabled-themes))
          ;; Doom's editors: line numbers, the current line, its git gutter.
          (should (memq #'display-line-numbers-mode prog-mode-hook))
          (should (eq (default-value 'display-line-numbers-width) 3))
          (should global-hl-line-mode)
          (should (bound-and-true-p global-diff-hl-mode))
          (should (eq diff-hl-fringe-bmp-function '+vc-gutter-type-at-pos-fn))
          ;; Its setup as diff-hl loads, all of it (not stopped by Doom's
          ;; popup rules, which aren't here).
          (should (equal diff-hl-global-modes '(not image-mode pdf-view-mode)))
          (with-temp-buffer
            (emacs-lisp-mode)
            (should display-line-numbers-mode)))
      (when (fboundp 'tool-bar-mode) (tool-bar-mode (if tool-bar 1 -1)))
      (when (fboundp 'scroll-bar-mode) (scroll-bar-mode (if scroll-bar 1 -1)))
      (setq-default cursor-in-non-selected-windows cursor)
      (mapc #'disable-theme custom-enabled-themes))))

;; ====== THE CAPTURE ======

(ert-deftest screenshots/capture-the-frames-window ()
  "screencapture, silent, a PNG of the frame's window (its title bar too, no
shadow, its corners black: not what's behind it), into a temp file
first; a file left from before replaced once made."
  (let* ((file (+test-tmp-file "shots/a.png"))
         (new (+test-tmp-file "shots/a.new.png"))
         (calls nil))
    (with-temp-file file (insert "old"))
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(40 70 1884 1176)))
              ((symbol-function '+my/screenshots--window-number) (lambda (_) 4242))
              ((symbol-function '+my/screenshots--same-p) #'ignore)
              ((symbol-function 'call-process)
               (lambda (program &rest args)
                 (push (cons program (nthcdr 3 args)) calls)
                 (should (file-exists-p file))   ; the old one kept meanwhile
                 (with-temp-file (car (last args)) (insert "png"))
                 0)))
      (should (eq (+my/screenshots--capture (selected-frame) file) t)))
    (should (equal calls `(("screencapture" "-x" "-t" "png" "-o" "-l" "4242" ,new))))
    (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string)) "png"))
    (should-not (file-exists-p new))
    ;; macOS didn't say which window: the screen's rectangle under the frame.
    (setq calls nil)
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(40 70 1884 1176)))
              ((symbol-function '+my/screenshots--window-number) #'ignore)
              ((symbol-function '+my/screenshots--same-p) #'ignore)
              ((symbol-function 'call-process)
               (lambda (program &rest args)
                 (push (cons program (nthcdr 3 args)) calls)
                 (with-temp-file (car (last args)) (insert "png"))
                 0)))
      (should (eq (+my/screenshots--capture (selected-frame) file) t)))
    (should (equal calls `(("screencapture" "-x" "-t" "png" "-R" "40,70,1844,1106" ,new))))
    ;; SCREENCAPTURE: another program.
    (let ((process-environment (cons "SCREENCAPTURE=/bin/fake" process-environment)))
      (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(0 0 10 10)))
                ((symbol-function '+my/screenshots--window-number) #'ignore)
                ((symbol-function 'call-process)
                 (lambda (program &rest _) (push program calls) 0)))
        (+my/screenshots--capture (selected-frame) file)))
    (should (equal (car calls) "/bin/fake"))))

(ert-deftest screenshots/the-same-screenshot-kept ()
  "A capture the same as the last screenshot but for the window's edge: the
last one left as it is (its file not rewritten); different: replaced."
  (let ((file (+test-tmp-file "shots/same.png"))
        (new (+test-tmp-file "shots/same.new.png"))
        same)
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(0 0 10 10)))
              ((symbol-function '+my/screenshots--window-number) (lambda (_) 1))
              ((symbol-function '+my/screenshots--same-p)
               (lambda (old captured)
                 (should (equal old file))
                 (should (equal captured new))
                 same))
              ((symbol-function 'call-process)
               (lambda (&rest args)
                 (with-temp-file (car (last args)) (insert "capture"))
                 0)))
      (with-temp-file file (insert "last"))
      (setq same t)
      (should (eq (+my/screenshots--capture (selected-frame) file) t))
      (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string)) "last"))
      (should-not (file-exists-p new))
      (setq same nil)
      (should (eq (+my/screenshots--capture (selected-frame) file) t))
      (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string)) "capture"))
      (should-not (file-exists-p new)))))

(ert-deftest screenshots/same-but-for-the-window-s-edge ()
  "ImageMagick: the same image, or one differing in its outer
`+my/screenshots-edge' pixels only; not one differing inside."
  (skip-unless (executable-find "magick"))
  (let ((base (+test-tmp-file "shots/base.png"))
        (edge (+test-tmp-file "shots/edge.png"))
        (inside (+test-tmp-file "shots/inside.png")))
    (should (zerop (call-process "magick" nil nil nil "-size" "40x30" "xc:gray20" base)))
    (should (zerop (call-process "magick" nil nil nil base "-fill" "white"
                                 "-draw" "point 39,5" "-draw" "point 0,29" edge)))
    (should (zerop (call-process "magick" nil nil nil base "-fill" "white"
                                 "-draw" "point 20,15" inside)))
    (should (+my/screenshots--same-p base base))
    (should (+my/screenshots--same-p base edge))
    (should-not (+my/screenshots--same-p base inside))
    (let ((exec-path nil))
      (should-not (+my/screenshots--same-p base base)))))

(ert-deftest screenshots/the-frame-s-macos-window ()
  "The frame's macOS window number: of this Emacs's windows macOS lists (its
pid asked for), the one where the frame is; the only one if none is quite
there; nil if macOS doesn't say."
  (let (asked (listed "25407 661 183 597 560\n25410 0 0 300 200\n"))
    (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(661 183 1258 743)))
              ((symbol-function 'call-process)
               (lambda (program _infile _destination _display &rest args)
                 (setq asked (cons program args))
                 (insert listed)
                 0)))
      (should (eql (+my/screenshots--window-number (selected-frame)) 25407))
      (should (equal (car asked) "osascript"))
      (should (equal (car (last asked)) (number-to-string (emacs-pid))))
      (setq listed "25410 0 0 300 200\n")
      (should (eql (+my/screenshots--window-number (selected-frame)) 25410))
      (setq listed "1 0 0 1 1\n2 5 5 1 1\n")
      (should-not (+my/screenshots--window-number (selected-frame)))
      (setq listed "")
      (should-not (+my/screenshots--window-number (selected-frame))))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
      (should-not (+my/screenshots--window-number (selected-frame))))))

(ert-deftest screenshots/capture-failed ()
  "screencapture failed, or made no file (no Screen Recording permission):
not captured, why (what it said, its exit status), the last screenshot kept."
  (cl-letf (((symbol-function '+my/screenshots--window-number) (lambda (_) 7)))
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
	(should (equal (+my/screenshots--capture (selected-frame) file) "exit 0, no file made")))
      ;; The last screenshot kept: not lost to a failed capture.
      (with-temp-file file (insert "old"))
      (cl-letf (((symbol-function 'frame-edges) (lambda (&rest _) '(0 0 10 10)))
		((symbol-function 'call-process) (lambda (&rest _) 1)))
	(+my/screenshots--capture (selected-frame) file))
      (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string)) "old")))))

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

(ert-deftest screenshots/an-example-waited-for ()
  "An example with `+my/example-NAME-ready': captured once it says it's
drawn; never: not captured, said why, closed."
  (+test-screenshots
    (let ((ready nil)
          (captured nil))
      (cl-letf (((symbol-function '+my/example-merge-ready) (lambda () ready))
                ((symbol-function '+test-wait-for)
                 (lambda (predicate &optional _timeout) (setq ready t) (funcall predicate)))
                ((symbol-function '+my/screenshots--capture)
                 (lambda (&rest _) (setq captured ready) t)))
        (should (+my/screenshots--one "merge" (+test-tmp-file "shots-e/"))))
      (should captured)
      (cl-letf (((symbol-function '+my/example-merge-ready) #'ignore)
                ((symbol-function '+test-wait-for) (lambda (predicate &optional _) (funcall predicate)))
                ((symbol-function '+my/screenshots--capture) (lambda (&rest _) (error "Captured"))))
        (should-not (+my/screenshots--one "merge" (+test-tmp-file "shots-f/"))))
      (should (string-match-p "\\`merge: Not drawn after 40 s (\\+my/example-merge-ready)"
                              (car +test-screenshots--said)))
      (should-not (+test-screenshots--merges)))))

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
