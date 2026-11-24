;;; tests/unit/test-agent-ui-pane.el -*- lexical-binding: t; -*-
;; config/agent-ui/pane.el: a session's Agent UI in its session's pane, the
;; bottom half, its views in a grid, the session's mode line under the
;; conversation; synced as windows change (a batch Emacs doesn't run window
;; change functions: the tests sync where Emacs would). No agent runs: the
;; session is a buffer. With tiling: test-agent-ui-tiling.el.

(+test-load "config/emacs" "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-aup (&rest body)
  "BODY from one window on a session's buffer (`session', its canvas's name
`name'); its canvases killed after, its Agent UI shown again."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((agent-ui-focus-questions nil)
            (agent-ui-close-finished nil)
            (session (+test-buffer "Claude Agent @ pane" "The conversation.\n"))
            (sessions (list session)))
       (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () sessions))
                 ((symbol-function 'message) #'ignore))
         (switch-to-buffer session)
         (let ((name (agent-ui--session-name session)))
           (unwind-protect (progn ,@body)
             (dolist (canvas (agent-ui-canvases)) (kill-buffer canvas))
             (when (buffer-live-p session)
               (kill-buffer session))))))))

(defun +test-aup-show (canvas &optional id)
  "An element ID (default \"x\") shown on CANVAS (a name)."
  (agent-ui-show `(:id ,(or id "x") :type "text" :text "something") :canvas canvas))

(defun +test-aup-cells ()
  "The views' windows of the selected frame, in order: their buffers' names."
  (mapcar (lambda (window) (buffer-name (window-buffer window)))
          (agent-ui--pane-cells (selected-frame))))

(defun +test-aup-bar (window &optional parameter)
  "WINDOW's bar (its header line; PARAMETER: that one, its mode line), as
text; nil without one."
  (let ((format (window-parameter window (or parameter 'header-line-format))))
    (and (consp format)
         (mapconcat (lambda (part) (if (stringp part) part "")) format ""))))

(defun +test-aup-canvas (name &optional part)
  (get-buffer (agent-ui-canvas-buffer-name (if part (agent-ui-sub-canvas name part) name))))

;; ====== SETTINGS ======

(ert-deftest agent-ui-pane/settings ()
  (should-not (boundp 'agent-ui-pane-share))
  (should (= (default-value 'agent-ui-pane-max-share) 0.5))
  (should (= (default-value 'agent-ui-pane-min-lines) 6))
  (should (= (default-value 'agent-ui-grid-min-width) 40))
  ;; Agent UI shows a session's canvases so (config/agent-ui/pane.el).
  (should (eq agent-ui-display-function #'agent-ui-pane-display))
  (should (eq agent-ui-reveal-function #'agent-ui-pane-reveal))
  ;; The config says its keys on the first view's bar.
  (should (equal agent-ui-pane-keys "q close a view · SPC m u hide Agent UI"))
  (should (memq #'agent-ui--pane-sync-h (default-value 'window-state-change-functions)))
  (should (assq 'agent-ui-pane window-persistent-parameters)))

;; ====== ITS HEIGHT ======

(ert-deftest agent-ui-pane/its-height-bounds ()
  "6 lines at least, half the pane at most, the conversation keeping 6
lines; in between, what the views need."
  (should (= (agent-ui--pane-most 64) 32))
  (should (= (agent-ui--pane-most 14) 7))
  (should (= (agent-ui--pane-most 10) 6)))

(ert-deftest agent-ui-pane/grows-with-what-it-shows ()
  "Something taller shown: Agent UI grows to fit it (its bars too), up to
half the pane; gone again: as small as what's left. Only when what it needs
changes: a height you gave it stays while an element changes without
needing more."
  (+test-aup
    (let* ((window (selected-window))
           (pane (window-total-height window))
           (area (lambda () (window-total-height (window-next-sibling window)))))
      (+test-aup-show name)
      (should (= (funcall area) agent-ui-pane-min-lines))
      ;; 8 lines: 10 with its bar and the one under it.
      (agent-ui-show '(:id "lines" :type "text" :text "1\n2\n3\n4\n5\n6\n7") :canvas name)
      (agent-ui--pane-fit-now)
      (let ((wanted (min (agent-ui--pane-most pane)
                         (max agent-ui-pane-min-lines
                              (+ 2 (with-current-buffer (+test-aup-canvas name)
                                    (count-lines (point-min) (point-max))))))))
        (should (> wanted agent-ui-pane-min-lines))
        (should (= (funcall area) wanted)))
      ;; Much taller: half at most.
      (agent-ui-show `(:id "lines" :type "text" :text ,(mapconcat #'number-to-string (number-sequence 1 60) "\n"))
                     :canvas name)
      (agent-ui--pane-fit-now)
      (should (= (funcall area) (agent-ui--pane-most pane)))
      ;; Gone: as small as what's left.
      (agent-ui-remove "lines" :canvas name)
      (agent-ui--pane-fit-now)
      (should (= (funcall area) agent-ui-pane-min-lines))
      ;; Made taller by hand: kept while what it shows needs no more.
      (window-resize (window-next-sibling window) 2)
      (let ((yours (funcall area)))
        (agent-ui-show '(:id "x" :type "text" :text "something else") :canvas name)
        (agent-ui--pane-fit-now)
        (should (= (funcall area) yours))))))

;; ====== THE GRID ======

(ert-deftest agent-ui-pane/grid-shape ()
  "As many columns as fit (40 each), up to the square root of the count:
two side by side, three as two and one, four as two by two, five as three
and two; a narrow pane, one column."
  (should (equal (agent-ui--pane-grid-shape 1 115) '(1 . 1)))
  (should (equal (agent-ui--pane-grid-shape 2 115) '(2 . 1)))
  (should (equal (agent-ui--pane-grid-shape 3 115) '(2 . 2)))
  (should (equal (agent-ui--pane-grid-shape 4 115) '(2 . 2)))
  (should (equal (agent-ui--pane-grid-shape 5 120) '(3 . 2)))
  (should (equal (agent-ui--pane-grid-shape 5 115) '(2 . 3)))
  (should (equal (agent-ui--pane-grid-shape 4 70) '(1 . 4)))
  (should (equal (agent-ui--pane-grid-shape 2 30) '(1 . 2))))

(ert-deftest agent-ui-pane/as-many-as-fit ()
  "Each row at least 3 lines: the views that fit shown, the first ones."
  (should (equal (agent-ui--pane-fitting '(a b c d) 6 40) '(a b)))
  (should (equal (agent-ui--pane-fitting '(a b c d) 6 100) '(a b c d)))
  (should (equal (agent-ui--pane-fitting '(a) 2 40) '(a))))

;; ====== IN THE SESSION'S PANE ======

(ert-deftest agent-ui-pane/the-first-element-in-the-sessions-pane ()
  "The first element: the session's pane split, Agent UI at its bottom (a
quarter of it: little to show), a view of its own; the focus stays in the conversation; the conversation
keeps its mode line, the view has a bar instead (its name, the keys)."
  (+test-aup
    (let ((window (selected-window))
          (height (window-total-height)))
      (+test-aup-show name)
      (let ((cell (car (agent-ui--pane-cells (selected-frame))))
            (canvas (+test-aup-canvas name)))
        (should cell)
        (should (eq (window-buffer cell) canvas))
        (should (eq (selected-window) window))
        ;; A quarter, under the conversation, in its pane's group.
        (should (eq (window-next-sibling window) cell))
        (should (= (window-total-height cell) (max 6 (round (* 0.25 height)))))
        (should (= (+ (window-total-height window) (window-total-height cell)) height))
        (should (agent-ui-pane-window-p cell))
        (should-not (agent-ui-pane-window-p window))
        ;; Its name on its bar; under it, Agent UI's bar: what it is, its
        ;; keys. No tab line; the conversation's mode line its own.
        (should (eq (window-parameter cell 'tab-line-format) 'none))
        (should-not (window-parameter window 'mode-line-format))
        (should (equal (+test-aup-bar cell) " Agent UI"))
        (let ((under (+test-aup-bar cell 'mode-line-format)))
          (should (string-prefix-p " Agent UI" under))
          (should-not (string-search "views" under))
          (should (string-search "q close a view" under)))
        (should (window-dedicated-p cell))
        ;; Synced again: as it is.
        (agent-ui--pane-sync)
        (should (eq (car (agent-ui--pane-cells (selected-frame))) cell))))))

(ert-deftest agent-ui-pane/its-views-in-a-grid ()
  "The session's other canvases: views too, its own first, then by name; two
side by side, a third under them across the width; each its name on its bar.
Agent UI's bar under the bottom row: what it is on its leftmost view's mode
line, the keys on its rightmost's; the others' none."
  (+test-aup
    (+test-aup-show name)
    (+test-aup-show (agent-ui-sub-canvas name "tests"))
    (should (equal (+test-aup-cells)
                   (list (agent-ui-canvas-buffer-name name)
                         (agent-ui-canvas-buffer-name (agent-ui-sub-canvas name "tests")))))
    (pcase-let ((`(,a ,b) (agent-ui--pane-cells (selected-frame))))
      (should (= (window-top-line a) (window-top-line b)))
      (should (< (window-left-column a) (window-left-column b)))
      (should (string-prefix-p " Agent UI · 2 views" (+test-aup-bar a 'mode-line-format)))
      (should-not (string-search "q close" (+test-aup-bar a 'mode-line-format)))
      (should (string-search "q close a view" (+test-aup-bar b 'mode-line-format)))
      (should-not (string-search "Agent UI ·" (+test-aup-bar b 'mode-line-format))))
    (+test-aup-show (agent-ui-sub-canvas name "logs"))
    (should (equal (+test-aup-cells)
                   (mapcar #'agent-ui-canvas-buffer-name
                           (list name (agent-ui-sub-canvas name "logs") (agent-ui-sub-canvas name "tests")))))
    (pcase-let ((`(,a ,b ,c) (agent-ui--pane-cells (selected-frame))))
      (should (= (window-top-line a) (window-top-line b)))
      (should (> (window-top-line c) (window-top-line a)))
      (should (= (window-total-width c) (+ (window-total-width a) (window-total-width b))))
      (should (string-prefix-p " logs" (+test-aup-bar b)))
      (should (string-prefix-p " tests" (+test-aup-bar c)))
      ;; The top row: no mode lines; the bottom one across: both ends.
      (should (eq (window-parameter a 'mode-line-format) 'none))
      (should (eq (window-parameter b 'mode-line-format) 'none))
      (let ((under (+test-aup-bar c 'mode-line-format)))
        (should (string-prefix-p " Agent UI · 3 views" under))
        (should (string-search "q close a view" under))))
    ;; The conversation's window: only it, above them.
    (should (= (length (window-list nil 'nomini)) 4))))

(ert-deftest agent-ui-pane/q-closes-a-view ()
  "q in a view: its canvas killed, the others laid out again, the cursor in
the session."
  (+test-aup
    (+test-aup-show name)
    (+test-aup-show (agent-ui-sub-canvas name "tests"))
    (let ((tests (+test-aup-canvas name "tests")))
      (select-window (get-buffer-window tests))
      (agent-ui-quit)
      (agent-ui--pane-sync)
      (should-not (buffer-live-p tests))
      (should (eq (window-buffer (selected-window)) session))
      (should (equal (+test-aup-cells) (list (agent-ui-canvas-buffer-name name))))
      ;; Across the width again.
      (should (= (window-total-width (car (agent-ui--pane-cells (selected-frame))))
                 (window-total-width (selected-window)))))))

(ert-deftest agent-ui-pane/a-views-window-closed-hides-it ()
  "A view's window closed (SPC w d) while it shows something: hidden, the
others laid out again; something new shown in it: back."
  (+test-aup
    (+test-aup-show name)
    (+test-aup-show (agent-ui-sub-canvas name "tests"))
    (delete-window (get-buffer-window (+test-aup-canvas name "tests")))
    (agent-ui--pane-sync)
    (should (equal (+test-aup-cells) (list (agent-ui-canvas-buffer-name name))))
    (should (buffer-live-p (+test-aup-canvas name "tests")))
    (+test-aup-show (agent-ui-sub-canvas name "tests") "y")
    (should (equal (length (+test-aup-cells)) 2))))

(ert-deftest agent-ui-pane/emptied-its-view-gone ()
  "A view emptied (its last element removed): its window gone, the others
laid out again; its next element shows it again."
  (+test-aup
    (+test-aup-show name)
    (+test-aup-show (agent-ui-sub-canvas name "tests"))
    (agent-ui-remove "x" :canvas name)
    (agent-ui--pane-sync)
    (should (equal (+test-aup-cells)
                   (list (agent-ui-canvas-buffer-name (agent-ui-sub-canvas name "tests")))))
    (+test-aup-show name "y")
    (should (equal (length (+test-aup-cells)) 2))))

(ert-deftest agent-ui-pane/hidden-and-shown-again ()
  "SPC m u: Agent UI hidden for the session, the conversation its whole
pane; a new element leaves it hidden; SPC m u again, or a question, shows it."
  (+test-aup
    (+test-aup-show name)
    (let ((height (window-total-height (frame-root-window))))
      (agent-ui-pane-toggle)
      (should-not (+test-aup-cells))
      (should (= (window-total-height (selected-window)) (- height (window-total-height (minibuffer-window)) -1)))
      (+test-aup-show name "y")
      (should-not (+test-aup-cells))
      (agent-ui-pane-toggle)
      (should (equal (length (+test-aup-cells)) 1))
      ;; From a view: hidden, the cursor in the conversation.
      (select-window (car (agent-ui--pane-cells (selected-frame))))
      (agent-ui-pane-toggle)
      (should-not (+test-aup-cells))
      (should (eq (window-buffer (selected-window)) session))
      ;; A question shows it anyway.
      (agent-ui-show '(:id "fix" :type "choice" :question "Which?" :options ("A" "B")) :canvas name)
      (agent-ui-goto-question)
      (should (equal (length (+test-aup-cells)) 1))
      (should (eq (window-buffer (selected-window)) (+test-aup-canvas name))))))

(ert-deftest agent-ui-pane/a-session-in-no-window-waits ()
  "The session's pane showing another buffer: its views gone; an element
shown meanwhile opens nothing; the session shown again: they come back."
  (+test-aup
    (+test-aup-show name)
    (switch-to-buffer (+test-buffer "notes.txt"))
    (agent-ui--pane-sync)
    (should-not (+test-aup-cells))
    (should (= (length (window-list nil 'nomini)) 1))
    (+test-aup-show name "y")
    (should (= (length (window-list nil 'nomini)) 1))
    (switch-to-buffer session)
    (agent-ui--pane-sync)
    (should (equal (length (+test-aup-cells)) 1))))

(ert-deftest agent-ui-pane/the-conversation-closed-takes-its-views ()
  "The conversation's window deleted (SPC w d): its views' windows with it,
the room to the other window."
  (+test-aup
    (let ((other (split-window nil nil 'right)))
      (set-window-buffer other (+test-buffer "notes.txt"))
      (+test-aup-show name)
      (should (equal (length (+test-aup-cells)) 1))
      (delete-window (selected-window))
      (should-not (+test-aup-cells))
      (should (equal (window-list nil 'nomini) (list other))))))

(ert-deftest agent-ui-pane/a-pane-too-short-a-pane-of-its-own ()
  "A session's pane too short for both halves: the view in a window of its
own, as without a session's pane."
  (+test-aup
    (let ((agent-ui-pane-min-lines 20))
      (+test-aup-show name)
      (should-not (+test-aup-cells))
      (should (get-buffer-window (+test-aup-canvas name))))))

(ert-deftest agent-ui-pane/a-canvas-without-a-session ()
  "A canvas of no session (a shell's request): in a window of its own."
  (+test-aup
    (unwind-protect
        (progn
          (+test-aup-show "from-a-shell")
          (should-not (+test-aup-cells))
          (should (get-buffer-window (+test-aup-canvas "from-a-shell"))))
      (when-let* ((canvas (+test-aup-canvas "from-a-shell")))
        (kill-buffer canvas)))))

(ert-deftest agent-ui-pane/skipped-windows ()
  "A window `agent-ui-pane-skip-functions' leave out (a crew's frame): no
Agent UI in it."
  (+test-aup
    (let ((agent-ui-pane-skip-functions (list (lambda (_window) t))))
      (+test-aup-show name)
      (should-not (+test-aup-cells)))))

(ert-deftest agent-ui-pane/kept-with-the-session-only ()
  "The session's buffer killed: its views' windows gone with its canvases."
  (+test-aup
    (+test-aup-show name)
    (let ((other (split-window nil nil 'right)))
      (set-window-buffer other (+test-buffer "notes.txt"))
      (kill-buffer session)
      (agent-ui--pane-sync)
      (should-not (+test-aup-cells)))))

(ert-deftest agent-ui-pane/one-sessions-views-in-one-window ()
  "The session in two windows: its views under the first only."
  (+test-aup
    (let ((second (split-window nil nil 'right)))
      (set-window-buffer second session)
      (+test-aup-show name)
      (should (equal (length (+test-aup-cells)) 1))
      (let ((cell (car (agent-ui--pane-cells (selected-frame)))))
        (should (eq (window-next-sibling (frame-first-window)) cell))))))

(ert-deftest agent-ui-pane/a-view-window-of-no-canvas-left-alone ()
  "A window marked as a view but showing no canvas (a workspace's windows
made again at startup, its buffers gone): a window like any again, kept."
  (+test-aup
    (let ((other (split-window nil nil 'below)))
      (set-window-buffer other (+test-buffer "notes.txt"))
      (set-window-parameter other 'agent-ui-pane t)
      (set-window-dedicated-p other t)
      (agent-ui--pane-sync)
      (should (window-live-p other))
      (should-not (agent-ui-pane-window-p other))
      (should-not (window-dedicated-p other)))))

(ert-deftest agent-ui-pane/views-closed-less-room ()
  "Views closed (q, SPC w d): the others laid out again as a grid of their
count (two left in two rows: side by side), Agent UI as high as they need
now, as small as they need."
  (+test-aup
    (let* ((window (selected-window))
           (pane (window-total-height window))
           (area (lambda () (window-total-height (window-next-sibling window))))
           (text "line 1\nline 2\nline 3"))
      (dolist (canvas (list name (agent-ui-sub-canvas name "b") (agent-ui-sub-canvas name "c")
                            (agent-ui-sub-canvas name "d")))
        (agent-ui-show `(:id "x" :type "text" :text ,text) :canvas canvas))
      (agent-ui--pane-fit-now)
      (let ((four (funcall area)))
        (should (= (length (agent-ui--pane-cells (selected-frame))) 4))
        (should (> four agent-ui-pane-min-lines))
        ;; The top two closed: q on one, SPC w d on the other.
        (select-window (get-buffer-window (+test-aup-canvas name)))
        (agent-ui-quit)
        (agent-ui--pane-sync)
        (delete-window (get-buffer-window (+test-aup-canvas name "b")))
        (agent-ui--pane-sync)
        (let ((cells (agent-ui--pane-cells (selected-frame))))
          (should (= (length cells) 2))
          (should (= (window-top-line (car cells)) (window-top-line (cadr cells)))))
        (should (< (funcall area) four))
        (should (= (funcall area) agent-ui-pane-min-lines))))))

(ert-deftest agent-ui-pane/no-empty-lines-under-its-views ()
  "Views shorter than a quarter of the pane: Agent UI as high as they need
\(their lines, their bars, the bar under them), no empty lines under them,
the conversation keeping the rest."
  (+test-aup
    (let* ((agent-ui-pane-min-lines 3)
           (window (selected-window))
           (pane (window-total-height window)))
      (agent-ui-show '(:id "x" :type "text" :text "one\ntwo") :canvas name)
      ;; Measured again once drawn (a timer, after the redraw).
      (agent-ui--pane-fit-now)
      (let* ((cell (car (agent-ui--pane-cells (selected-frame))))
             (lines (with-current-buffer (window-buffer cell) (count-lines (point-min) (point-max)))))
        (should (< (window-total-height cell) (round (* 0.25 pane))))
        (should (= (window-total-height cell) (+ lines 2)))
        (should (= (window-body-height cell) lines))
        (should (= (window-total-height window) (- pane lines 2)))))))

(ert-deftest agent-ui-pane/a-view-that-fits-from-its-top ()
  "A view whose content fits its window, scrolled down (shrunk, then grown
again): shown from its top at the next sync, nothing hidden above it."
  (+test-aup
    (agent-ui-show '(:id "x" :type "text" :text "one\ntwo\nthree") :canvas name)
    (let ((cell (car (agent-ui--pane-cells (selected-frame)))))
      (with-current-buffer (window-buffer cell)
        (set-window-start cell (save-excursion (goto-char (point-min)) (forward-line 1) (point)) t))
      (should (> (window-start cell) 1))
      (agent-ui--pane-sync)
      (should (= (window-start cell) (with-current-buffer (window-buffer cell) (point-min)))))))

(ert-deftest agent-ui-pane/each-row-its-own-height ()
  "Rows of different heights: each as high as its tallest view, no empty
lines under the views of the short one."
  (+test-aup
    (let ((agent-ui-pane-min-lines 3))
      (+test-aup-show name)
      (+test-aup-show (agent-ui-sub-canvas name "b"))
      (agent-ui-show '(:id "x" :type "text" :text "1\n2\n3\n4") :canvas (agent-ui-sub-canvas name "c"))
      (agent-ui--pane-fit-now)
      (pcase-let ((`(,a ,_b ,c) (agent-ui--pane-cells (selected-frame))))
        (should (< (window-total-height a) (window-total-height c)))
        (dolist (cell (list a c))
          (should (= (window-body-height cell)
                     (with-current-buffer (window-buffer cell) (count-lines (point-min) (point-max))))))))))
