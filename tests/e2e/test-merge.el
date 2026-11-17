;;; tests/e2e/test-merge.el -*- lexical-binding: t; -*-
;; config/merge.el in a GUI Emacs: Magit's e on a conflicted file opens the
;; three panes under the bar; the margins' buttons clicked where they show;
;; Done writes and stages the file, Magit's status shows it.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/window" "config/editor" "config/merge")
(require 'magit)
(require 'magit-ediff)
(require 'ultra-scroll)
(global-tab-line-mode 1)

;; A mode that takes clicks in the margins, as dap-mode does in code buffers
;; (Doom's debugger: a breakpoint): made after the merge's, its keymap comes
;; first. It took Theirs' buttons and the wand's.
(defvar +test-merge--taken 0 "Clicks the margin thief took.")

(define-minor-mode +test-merge-margin-thief-mode
  "Takes the margins' clicks (as dap-mode's breakpoints do)."
  :keymap (let ((map (make-sparse-keymap))
                (take (lambda () (interactive) (cl-incf +test-merge--taken))))
            (dolist (area '(left-margin right-margin))
              (define-key map (vector area 'mouse-1) take)
              (define-key map (vector area 'down-mouse-1) take))
            map))

;; ====== HELPERS ======

(defun +test-merge--thieves (session)
  "The margin thief on in SESSION's panes."
  (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
    (with-current-buffer buffer (+test-merge-margin-thief-mode 1))))

(defun +test-merge--click (posn)
  "A click at POSN, run as Emacs would: by what the click is bound to there
(its area's keys, the clicked string's keymap first)."
  (let* ((area (posn-area posn))
         (down (key-binding (vector area 'down-mouse-1) nil nil posn))
         (command (key-binding (vector area 'mouse-1) nil nil posn)))
    (should (eq command #'+my/merge-click))
    (should (eq down #'ignore))
    (funcall command (list 'mouse-1 posn))
    (should (= +test-merge--taken 0))))

(defun +test-merge--margin-posn (window area action)
  "Where WINDOW's AREA (left-margin, right-margin) shows a button doing ACTION
\=(applied, ignored, merged), scanning its frame's pixels: its position."
  (let ((edges (window-pixel-edges window)))
    (catch 'found
      (dolist (y (number-sequence (nth 1 edges) (min (nth 3 edges) (+ (nth 1 edges) 300)) 3))
        (dolist (x (number-sequence (nth 0 edges) (1- (nth 2 edges)) 2))
          (let* ((posn (posn-at-x-y x y (window-frame window)))
                 (string (posn-string posn)))
            (when (and (eq (posn-window posn) window)
                       (eq (posn-area posn) area)
                       (car string) (cdr string)
                       (eq (nth 2 (get-text-property (cdr string) '+my/merge-action (car string)))
                           action))
              (throw 'found posn))))))))

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
            (default-directory repo)
            ;; Side by side whatever the frame's width (the stacked layout's
            ;; tests ask for it).
            (+my/merge-side-by-side-width 0))
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
  "Magit's status, point on a.txt (Unmerged), e: the merge's session. In
Magit's status buffer and window, whatever the frame's focus did meanwhile
(Xvfb, without a window manager)."
  (let ((status (magit-status-setup-buffer default-directory)))
    (+test-sleep 0.3)
    (when (get-buffer-window status)
      (select-window (get-buffer-window status)))
    (set-buffer status))
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
        ;; The margins with the buttons, shown: as wide as they draw (Yours'
        ;; a column more at least: the icons), the columns at least.
        (should (equal (window-margins yours) (cons nil (+my/merge--yours-margin-columns))))
        (should (equal (window-margins theirs) (list (+my/merge--theirs-margin-columns))))
        (should (>= (cdr (window-margins yours)) 6))
        (should (>= (car (window-margins theirs)) 5))))))

(defun +test-merge--bar-button-xy (session label)
  "Where LABEL's button shows in SESSION's bar, whole: (X Y) in its window,
or nil if any of it is off the screen."
  (let ((bar (get-buffer-window (+my/merge-bar session))))
    (with-current-buffer (+my/merge-bar session)
      (goto-char (point-min))
      (let (found)
        (while-let (((not found))
                    (button (next-button (point))))
          (when (equal (button-label button) label)
            (setq found button))
          (goto-char (button-end button)))
        (and found
             (pos-visible-in-window-p (button-start found) bar)
             (pos-visible-in-window-p (1- (button-end found)) bar)
             (let ((place (pos-visible-in-window-p (button-start found) bar t)))
               (and (consp place) (list (car place) (cadr place)))))))))

(ert-deftest e2e-merge/the-bar-in-a-narrow-frame ()
  "At 120, 60 and 40 columns, Done and Abort on the screen, whole, a click
there on them; the bar's row whole in its window (no pixel of it hidden)."
  (+test-merge-conflict
    (let ((columns-before (frame-width))
          (font-before (face-attribute 'default :font)))
      (unwind-protect
          (let* ((session (progn
                            ;; config.el's font, where the wand's row was cut.
                            (when (find-font (font-spec :family "JetBrains Mono"))
                              (set-face-attribute 'default nil :family "JetBrains Mono" :height 130))
                            (+test-merge--e)))
                 (bar (get-buffer-window (+my/merge-bar session))))
            (dolist (columns '(120 60 40))
              (set-frame-width nil columns)
              (should (+test-wait-for (lambda () (= (frame-width) columns)) 5))
              (+test-sleep 0.3)
              (let ((line (window-line-height 0 bar)))
                (should line)
                (should (equal (list columns (nth 3 line)) (list columns 0))))
              (dolist (label '("Done" "Abort"))
                (let ((xy (+test-merge--bar-button-xy session label)))
                  (should (equal (list columns label (and xy t)) (list columns label t)))
                  (let ((posn (posn-at-x-y (+ (car xy) 2) (+ (cadr xy) 2) bar)))
                    (should (eq (posn-window posn) bar))
                    (should (equal (with-current-buffer (+my/merge-bar session)
                                     (button-label (button-at (posn-point posn))))
                                   label)))))))
        (set-face-attribute 'default nil :font font-before)
        (set-frame-width nil columns-before)))))

(ert-deftest e2e-merge/a-narrow-frame-stacked ()
  "A rebase's conflict in a frame of 80, then 60 columns: Yours and Theirs
above the Result, as wide as the frame (at 80, the Result 40 columns of code
at least, each side 20); each side's role in the rebase on the screen in its
title; the panes scrolling together."
  (+test-merge-conflict
    (+test-merge--git "merge" "--abort")
    (+test-merge--git "checkout" "-q" "feature")
    (with-temp-buffer (call-process "git" nil t nil "rebase" "main"))
    (let ((columns-before (frame-width))
          (+my/merge-side-by-side-width 120))
      (unwind-protect
          (dolist (columns '(80 60))
            (set-frame-width nil columns)
            (should (+test-wait-for (lambda () (= (frame-width) columns)) 5))
            (let* ((session (+my/merge "a.txt"))
                   (windows (mapcar #'get-buffer-window
                                    (list (+my/merge-yours session) (+my/merge-result session)
                                          (+my/merge-theirs session))))
                   (code (lambda (window) (- (window-body-width window) (+ +my/merge--number-width 2)))))
              (+test-sleep 0.3)
              (pcase-let ((`(,yours ,result ,theirs) windows))
                (should (= (cadr (window-edges yours)) (cadr (window-edges theirs))))
                (should (> (cadr (window-edges result)) (cadr (window-edges yours))))
                (when (= columns 80)
                  (should (>= (funcall code result) 40))
                  (should (>= (funcall code yours) 20))
                  (should (>= (funcall code theirs) 20)))
                (pcase-dolist (`(,window ,role) `((,yours "(rebasing onto)") (,theirs "(being rebased)")))
                  (let* ((header (format-mode-line (buffer-local-value 'header-line-format (window-buffer window))
                                                   'header-line window (window-buffer window)))
                         (end (string-search role header)))
                    (should (equal (list columns role (and end t)) (list columns role t)))
                    (should (<= (string-pixel-width (substring header 0 (+ end (length role))))
                                (window-pixel-width window)))))
                ;; Scrolled: the others too.
                (with-selected-window result
                  (scroll-up 2))
                (+test-sleep 0.2)
                (let ((first (lambda (window)
                               (with-current-buffer (window-buffer window)
                                 (line-number-at-pos (window-start window))))))
                  (should (= (funcall first yours) (funcall first result) (funcall first theirs)))))
              (with-current-buffer (+my/merge-result session)
                (+my/merge-abort))))
        (set-frame-width nil columns-before)))))

(defun +test-merge--row-ys (session line)
  "Where row LINE (from 1, the panes scrolled to the top) shows in SESSION's
three panes: the pixel y of its top, each in its window."
  (mapcar (lambda (buffer)
            (nth 2 (window-line-height (1- line) (get-buffer-window buffer))))
          (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session))))

(ert-deftest e2e-merge/rows-with-emoji-line-up ()
  "Lines with emoji on one side only (a taller row in its pane): each row at
the same pixel y in the three panes, side by side and stacked, and again
once the Result is edited."
  (dolist (stacked '(nil t))
    (+test-merge-conflict-of
        (+test-merge--lines "one" "two" "three" "four" "five" "six" "seven" "eight" "nine" "ten")
        (+test-merge--lines "one" "two ✅ done" "three 🚀" "four" "five" "six yours" "seven" "eight" "nine" "ten")
        (+test-merge--lines "one" "two" "three" "four" "five" "six theirs" "seven" "eight" "nine" "ten")
      (let* ((+my/merge-side-by-side-width (if stacked 10000 0))
             (session (+my/merge "a.txt")))
        (+test-sleep 0.3)
        (dolist (line '(2 3 4 9))
          (let ((ys (+test-merge--row-ys session line)))
            (should (equal (list stacked line ys)
                           (list stacked line (list (car ys) (car ys) (car ys)))))))
        ;; An emoji typed into the Result's 8th line: lined up again.
        (with-current-buffer (+my/merge-result session)
          (goto-char (point-min))
          (forward-line 7)
          (end-of-line)
          (insert " 🎉")
          (run-hooks 'post-command-hook))
        (+test-sleep 0.3)
        (dolist (line '(8 9))
          (let ((ys (+test-merge--row-ys session line)))
            (should (equal (list stacked line ys)
                           (list stacked line (list (car ys) (car ys) (car ys)))))))
        (with-current-buffer (+my/merge-result session)
          (+my/merge-abort))))))

(ert-deftest e2e-merge/a-margin-button-clicked-where-it-shows ()
  (+test-merge-conflict
    (let* ((session (+test-merge--e))
           (window (get-buffer-window (+my/merge-yours session)))
           (chunk (aref (+my/merge-chunks session) 0)))
      (redisplay t)
      ;; The button by TWO (line 2), in the right margin.
      (let ((posn (+test-merge--margin-posn window 'right-margin 'applied)))
        (should posn)
        (should (= (cdr (posn-col-row posn)) 1))
        ;; The buttons in the margin, after its space: off the code, the x
        ;; whole (the margin's wide enough).
        (let ((string (posn-string posn)))
          (should (> (cdr string) 0))
          (should-not (get-text-property 0 '+my/merge-action (car string)))
          (let* ((x-index (cl-loop for i from (cdr string) below (length (car string))
                                   when (eq (nth 2 (get-text-property i '+my/merge-action (car string))) 'ignored)
                                   return i))
                 (margin-px (* (cdr (window-margins window)) (frame-char-width)))
                 (text-px (with-current-buffer (+my/merge-yours session)
                            (string-pixel-width (substring (car string) 0 (1+ x-index))))))
            (should x-index)
            (should (<= text-px margin-px))))
        (+test-merge--thieves session)
        (+test-merge--click posn)
        (should (eq (+my/merge-chunk-yours-state chunk) 'applied))
        (should (string-prefix-p "one\nTWO\n" (with-current-buffer (+my/merge-result session) (buffer-string))))))))

(ert-deftest e2e-merge/theirs-buttons-clicked-where-they-show ()
  "Theirs' buttons, in its left margin, clicked where they show, a mode
taking the margins' clicks on (dap-mode's breakpoints did, in code)."
  (+test-merge-conflict
    (let* ((session (+test-merge--e))
           (window (get-buffer-window (+my/merge-theirs session)))
           (chunk (aref (+my/merge-chunks session) 1)))   ; FOUR, Theirs'
      (+test-merge--thieves session)
      (redisplay t)
      (let ((posn (+test-merge--margin-posn window 'left-margin 'applied)))
        (should posn)
        (should (eq (nth 0 (get-text-property (cdr (posn-string posn)) '+my/merge-action
                                              (car (posn-string posn))))
                    chunk))
        (+test-merge--click posn))
      (should (eq (+my/merge-chunk-theirs-state chunk) 'applied))
      (should (string-match-p "three\nFOUR\nfive" (with-current-buffer (+my/merge-result session)
                                                      (buffer-string))))
      ;; Its x, on the next one (six theirs: a conflict).
      (redisplay t)
      (let ((posn (+test-merge--margin-posn window 'left-margin 'ignored)))
        (should posn)
        (+test-merge--click posn)
        (should (eq (+my/merge-chunk-theirs-state (nth 0 (get-text-property (cdr (posn-string posn))
                                                                             '+my/merge-action
                                                                             (car (posn-string posn)))))
                    'ignored))))))

(ert-deftest e2e-merge/line-numbers-on-screen ()
  "Each pane's lines numbered on screen: jit-lock put them on what's shown,
each drawn left of its line; the current line's in its own face."
  (+test-merge-conflict
    (let ((session (+test-merge--e)))
      (redisplay t)
      (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
        (let ((window (get-buffer-window buffer)))
          (with-current-buffer buffer
            (goto-char (point-min))
            (forward-line 4)                ; five
            (should (= (string-to-number (get-text-property (point) 'line-prefix)) 5))
            ;; Left of the line's text, on its row: the number's string.
            (let* ((xy (pos-visible-in-window-p (point) window t))
                   (posn (posn-at-x-y (- (car xy) (* 2 (frame-char-width))) (cadr xy) window)))
              (should (stringp (car (posn-string posn))))
              (should (= (string-to-number (car (posn-string posn))) 5)))
            ;; The current line's, in the window.
            (let ((ov (alist-get window +my/merge--current-numbers)))
              (should ov)
              (should (eq (get-text-property 1 'face (overlay-get ov 'line-prefix))
                          'line-number-current-line)))))))))

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
  "The pixel heights of WINDOW's rows on screen, but one the window's bottom
cuts (its height not a whole number of rows: its visible part)."
  (let (heights)
    (dotimes (row (window-body-height window))
      (when-let* ((height (window-line-height row window))
                  ((zerop (nth 3 height))))
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
    ;; A glide (config/editor/smooth.el's, as a mouse wheel's notch): together
    ;; at each frame.
    (let ((frames 0))
      (+my/smooth--glide yours -600)
      (while (and +my/smooth--timer (< frames 200))
        (+test--pump 0.01)
        ;; As drawn: a frame's timer may have run after the last redisplay.
        (redisplay t)
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

;; ====== THE WAND ======

(ert-deftest e2e-merge/the-wand-clicked-where-it-shows ()
  (+test-merge-conflict-of
      (+test-merge--lines "start" "call(first, second);" "end")
      (+test-merge--lines "start" "call(FIRST, second);" "end")
      (+test-merge--lines "start" "invoke(first, second);" "end")
    (let* ((session (+test-merge--e))
           (result (get-buffer-window (+my/merge-result session)))
           (chunk (aref (+my/merge-chunks session) 0)))
      (redisplay t)
      (should (equal (window-margins result) '(2)))
      ;; In the Result's left margin, where it shows: the conflict's row.
      (let ((posn (+test-merge--margin-posn result 'left-margin 'merged)))
        (should posn)
        (should (= (cdr (posn-col-row posn))
                   (with-current-buffer (+my/merge-result session)
                     (1- (line-number-at-pos (overlay-start (+my/merge-chunk-result chunk)))))))
        (+test-merge--thieves session)
        (+test-merge--click posn))
      (should (equal (with-current-buffer (+my/merge-result session) (+my/merge--result-text session))
                     (+test-merge--lines "start" "invoke(FIRST, second);" "end")))
      (should (+my/merge--resolved-p chunk)))))
