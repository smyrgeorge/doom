;;; tests/e2e/test-merge.el -*- lexical-binding: t; -*-
;; config/merge.el in a GUI Emacs: Magit's e on a conflicted file opens the
;; three panes under the bar; the margins' buttons clicked where they show;
;; Done writes and stages the file, Magit's status shows it.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/window" "config/tabs" "config/smooth" "config/merge")
(require 'magit)
(require 'magit-ediff)
(require 'ultra-scroll)
(global-tab-line-mode 1)

;; ====== HELPERS ======

(defun +test-merge--git (&rest args)
  (with-temp-buffer
    (let ((status (apply #'call-process "git" nil t nil args)))
      (unless (zerop status)
        (error "git %s: %s" (string-join args " ") (buffer-string)))
      (buffer-string))))

(defun +test-merge--write (file content)
  (with-temp-file (expand-file-name file) (insert content)))

(defun +test-merge--lines (&rest lines)
  (mapconcat (lambda (line) (concat line "\n")) lines ""))

(defun +test-merge--long (changes)
  "200 lines, \"line N\", but CHANGES: ((N . LINES)...), LINES instead of
line N."
  (mapconcat (lambda (n)
               (let ((change (assq n changes)))
                 (if change (apply #'+test-merge--lines (cdr change)) (format "line %d\n" n))))
             (number-sequence 1 200) ""))

(defmacro +test-merge-conflict (&rest body)
  "BODY in a repo where a.txt is in conflict (merging feature into main)."
  (declare (indent 0))
  `(+test-merge-conflict-of (+test-merge--lines "one" "two" "three" "four" "five" "six" "seven")
                            (+test-merge--lines "one" "TWO" "three" "four" "five" "six yours" "seven")
                            (+test-merge--lines "one" "two" "three" "FOUR" "five" "six theirs" "seven")
     ,@body))

(defmacro +test-merge-conflict-of (base yours theirs &rest body)
  "BODY in a repo where a.txt (BASE) is in conflict: YOURS on main, THEIRS
on feature, feature merged into main."
  (declare (indent 3))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "merge-home-") t)))
            (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "merge-repo-") t))))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0" "GIT_EDITOR=true")
                     process-environment))
            (default-directory repo))
       (with-temp-file (expand-file-name ".gitconfig" home)
         (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                 "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
       (+test-merge--git "init" "-q")
       (+test-merge--write "a.txt" ,base)
       (+test-merge--git "add" ".")
       (+test-merge--git "commit" "-qm" "base")
       (+test-merge--git "checkout" "-qb" "feature")
       (+test-merge--write "a.txt" ,theirs)
       (+test-merge--git "commit" "-qam" "theirs")
       (+test-merge--git "checkout" "-q" "main")
       (+test-merge--write "a.txt" ,yours)
       (+test-merge--git "commit" "-qam" "yours")
       (with-temp-buffer (call-process "git" nil t nil "merge" "-q" "feature"))
       (unwind-protect (progn ,@body)
         (dolist (buffer (buffer-list))
           (when (buffer-local-value '+my/merge--session buffer)
             (ignore-errors (+my/merge--finish (buffer-local-value '+my/merge--session buffer)))))))))

(defun +test-merge--e ()
  "Magit's status, point on a.txt (Unmerged), e: the merge's session."
  (magit-status-setup-buffer default-directory)
  (+test-sleep 0.3)
  (goto-char (point-min))
  (should (re-search-forward "^unmodified\\|a\\.txt" nil t))
  (goto-char (point-min))
  (re-search-forward "Unmerged")
  (re-search-forward "a\\.txt")
  (should (equal (magit-current-file) "a.txt"))
  (call-interactively #'magit-ediff-dwim)
  (+test-sleep 0.3)
  (buffer-local-value '+my/merge--session (current-buffer)))

;; ====== TESTS ======

(ert-deftest e2e-merge/e-in-magit-opens-the-panes ()
  (+test-merge-conflict
    (let ((session (+test-merge--e)))
      (should (+my/merge-p session))
      (let ((yours (get-buffer-window (+my/merge-yours session)))
            (result (get-buffer-window (+my/merge-result session)))
            (theirs (get-buffer-window (+my/merge-theirs session)))
            (bar (get-buffer-window (+my/merge-bar session))))
        (should (and yours result theirs bar))
        (should (eq (selected-window) result))
        (should (= (window-height bar) 1))
        ;; About a third each.
        (should (< (abs (- (window-total-width yours) (window-total-width theirs))) 3))
        ;; No tab line in them; their titles above them.
        (dolist (window (list yours result theirs bar))
          (should-not (with-current-buffer (window-buffer window) (bound-and-true-p tab-line-mode))))
        (should (string-match-p "Yours: main" (with-current-buffer (window-buffer yours)
                                                 (format-mode-line header-line-format nil yours))))
        ;; The margins with the buttons, shown.
        (should (equal (window-margins yours) '(nil . 5)))
        (should (equal (window-margins theirs) '(5)))))))

(ert-deftest e2e-merge/a-margin-button-clicked-where-it-shows ()
  (+test-merge-conflict
    (let* ((session (+test-merge--e))
           (window (get-buffer-window (+my/merge-yours session)))
           (chunk (aref (+my/merge-chunks session) 0)))
      (redisplay t)
      ;; The button by TWO (line 2): the right margin's first column there,
      ;; past the text and the right fringe (margins are outside fringes).
      (let* ((line-y (+ (nth 1 (pos-visible-in-window-p (overlay-end (+my/merge-chunk-yours chunk))
                                                         window t))
                        (- (/ (with-current-buffer (+my/merge-yours session) (default-line-height)) 2))))
             (edges (window-body-pixel-edges window))
             (x (+ (- (nth 2 edges) (nth 0 edges)) (nth 1 (window-fringes window)) 2))
             (posn (posn-at-x-y x line-y window)))
        (should (eq (posn-area posn) 'right-margin))
        (should (= (cdr (posn-col-row posn)) 1))
        (should (posn-string posn))
        (+my/merge-click (list 'mouse-1 posn))
        (should (eq (+my/merge-chunk-yours-state chunk) 'applied))
        (should (string-prefix-p "one\nTWO\n" (with-current-buffer (+my/merge-result session) (buffer-string))))))))

(ert-deftest e2e-merge/done-stages-and-magit-shows-it ()
  (+test-merge-conflict
    (let ((session (+test-merge--e)))
      (with-current-buffer (+my/merge-result session)
        (+my/merge-apply-non-conflicting)
        (let ((chunk (seq-find (lambda (c) (eq (+my/merge-chunk-kind c) 'conflict)) (+my/merge-chunks session))))
          (+my/merge--decide chunk 'theirs 'applied)
          (+my/merge--decide chunk 'yours 'applied))
        (+my/merge-done))
      (should (equal (with-temp-buffer (insert-file-contents "a.txt") (buffer-string))
                     (+test-merge--lines "one" "TWO" "three" "FOUR" "five" "six theirs" "six yours" "seven")))
      (should (string-empty-p (+test-merge--git "ls-files" "-u")))
      ;; Back in Magit's status, without the file in Unmerged.
      (should (derived-mode-p 'magit-status-mode))
      (should-not (save-excursion (goto-char (point-min)) (re-search-forward "^Unmerged" nil t))))))

;; ====== LINED UP, SCROLLING TOGETHER ======

(defmacro +test-merge-long (&rest body)
  "BODY with a 200-line a.txt in conflict, its merge open (`session', and
the panes' windows `yours', `result', `theirs'): Yours added lines at 20,
Theirs removed 3 at 60, both changed 100 (one line, four), Theirs 150."
  (declare (indent 0))
  `(+test-merge-conflict-of
       (+test-merge--long nil)
       (+test-merge--long '((20 "line 20" "y1" "y2" "y3" "y4" "y5") (100 "yours 100")))
       (+test-merge--long '((60) (61) (62) (100 "t1" "t2" "t3" "t4") (150 "THEIRS 150")))
     (let* ((session (+test-merge--e))
            (yours (get-buffer-window (+my/merge-yours session)))
            (result (get-buffer-window (+my/merge-result session)))
            (theirs (get-buffer-window (+my/merge-theirs session))))
       (ignore yours result theirs)
       ,@body)))

(defun +test-merge--first-line (window)
  (with-current-buffer (window-buffer window)
    (line-number-at-pos (window-start window))))

(defun +test-merge--together-p (session)
  "Non-nil if SESSION's panes show the same rows: their first line, the
pixels of it scrolled off, sideways."
  (let ((views (mapcar (lambda (buffer)
                         (let ((window (get-buffer-window buffer)))
                           (list (+test-merge--first-line window) (window-vscroll window t)
                                 (window-hscroll window))))
                       (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))))
    (or (and (equal (car views) (nth 1 views)) (equal (nth 1 views) (nth 2 views)))
        (progn (message "APART %S" views) nil))))

(defun +test-merge--row-heights (window)
  "The pixel heights of WINDOW's rows on screen."
  (let (heights)
    (dotimes (row (window-body-height window))
      (when-let* ((height (window-line-height row window)))
        (push (car height) heights)))
    heights))

(ert-deftest e2e-merge/rows-line-up-on-screen ()
  "Each change's first row: the same row of the three panes, and every row
as tall in each (the margins' icons don't make theirs taller): at the same
height on screen."
  (+test-merge-long
    (seq-doseq (chunk (+my/merge-chunks session))
      (with-current-buffer (+my/merge-result session)
        (+my/merge--goto chunk))
      (redisplay t)
      (+test-sleep 0.05)
      (let ((rows (mapcar (lambda (side)
                            (let* ((ov (+my/merge--overlay chunk side))
                                   (window (get-buffer-window (overlay-buffer ov))))
                              (cdr (posn-col-row (posn-at-point (overlay-start ov) window)))))
                          '(yours result theirs))))
        (should (car rows))
        (should (apply #'= rows)))
      (dolist (window (list yours result theirs))
        (should (seq-every-p (lambda (height) (= height (frame-char-height)))
                             (+test-merge--row-heights window)))))))

(ert-deftest e2e-merge/scrolling-together ()
  (+test-merge-long
    ;; Pixel by pixel (ultra-scroll, as the trackpad), from a side pane.
    (dotimes (_ 25)
      (ultra-scroll--scroll -37 theirs)
      (redisplay t))
    (+test-sleep 0.05)
    (should (> (+test-merge--first-line theirs) 10))
    (should (+test-merge--together-p session))
    ;; A glide (config/smooth.el's, as a mouse wheel's notch): together at
    ;; each frame.
    (let ((frames 0))
      (+my/smooth--glide yours -600)
      (while (and +my/smooth--timer (< frames 200))
        (+test--pump 0.01)
        (cl-incf frames)
        (should (+test-merge--together-p session)))
      (should-not +my/smooth--timer))
    (should (> (+test-merge--first-line result) 40))
    ;; Keys in the Result.
    (with-selected-window result
      (forward-line 120)
      (recenter 0))
    (redisplay t)
    (+test-sleep 0.05)
    (should (+test-merge--together-p session))
    ;; Sideways.
    (set-window-hscroll yours 4)
    (redisplay t)
    (+test-sleep 0.05)
    (should (= (window-hscroll theirs) 4))))

(ert-deftest e2e-merge/the-wheel-over-a-pane ()
  (+test-merge-long
    (let ((start (+test-merge--first-line result)))
      (dotimes (_ 5)
        (execute-kbd-macro (vector (list 'wheel-down (posn-at-x-y 40 40 theirs))))
        (+test--pump 0.05))
      (+test-sleep 0.6)
      (should (> (+test-merge--first-line theirs) start))
      (should (+test-merge--together-p session))
      ;; The Result stays the selected pane.
      (should (eq (selected-window) result)))))
