;;; tests/unit/test-agent-ui-canvas.el -*- lexical-binding: t; -*-
;; config/agent-ui/canvas.el: Agent UI's canvas. Elements shown, replaced,
;; updated (redrawn together, later), appended to, removed; the canvas shown
;; when an element is added, at its window's width; animations' timer; errors.
;; Types of the tests' own; each test's canvas killed after it.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defvar +test-auc-draws 0 "How many times a `meter' was drawn.")
(defvar +test-auc-displayed nil "The canvases `agent-ui-display-function' was given.")

(defmacro +test-auc (&rest body)
  "BODY with a canvas of its own, `canvas' (killed after), and only the
tests' types: meter (VALUE/MAX), spinner (animated), broken (fails)."
  (declare (indent 0))
  `(let ((agent-ui--types (make-hash-table :test #'eq))
         (agent-ui-default-canvas (make-temp-name "test-"))
         (agent-ui-display-function (lambda (b) (push b +test-auc-displayed)))
         (+test-auc-draws 0)
         (+test-auc-displayed nil))
     (agent-ui-define meter "VALUE of MAX."
       :props ((value number "Done" :default 0)
               (max number "Total" :default 10)
               (marks list "Marks")
               (wide boolean "Its width shown"))
       :text (lambda (props ctx)
               (cl-incf +test-auc-draws)
               (format "%s/%s%s%s" (plist-get props :value) (plist-get props :max)
                       (if (plist-get props :marks)
                           (concat " " (string-join (plist-get props :marks) ","))
                         "")
                       (if (plist-get props :wide) (format " w%s" (plist-get ctx :width)) ""))))
     (agent-ui-define spinner "Spins." :animated t
       :text (lambda (_props ctx) (format "spin %d" (plist-get ctx :tick))))
     (agent-ui-define broken "Fails." :text (lambda (_p _c) (error "Boom")))
     (let ((canvas (agent-ui-canvas)))
       (unwind-protect (progn ,@body)
         (kill-buffer canvas)))))

(defun +test-auc-text (&optional canvas)
  (with-current-buffer (or canvas (agent-ui-canvas))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-auc-flush ()
  (with-current-buffer (agent-ui-canvas) (agent-ui--flush)))

(defun +test-auc-message (fn &rest args)
  (agent-ui-error-message (should-error (apply fn args) :type 'agent-ui-error)))

;; ====== THE CANVAS ======

(ert-deftest agent-ui-canvas/settings ()
  (should (= (default-value 'agent-ui-redraw-delay) 0.1))
  (should (= (default-value 'agent-ui-max-elements) 100))
  (should (equal (default-value 'agent-ui-default-canvas) "default"))
  ;; Its own default; the config's is the session's workspace's
  ;; (config/agent-ui/workspaces.el, test-agent-ui-workspaces.el).
  (should (eq (eval (car (get 'agent-ui-display-function 'standard-value)) t) #'agent-ui-display-canvas)))

(ert-deftest agent-ui-canvas/a-canvas-made ()
  (+test-auc
    (should (equal (buffer-name canvas) (format "Agent UI: %s" agent-ui-default-canvas)))
    (with-current-buffer canvas
      (should (eq major-mode 'agent-ui-canvas-mode))
      (should buffer-read-only)
      (should truncate-lines)
      ;; Without Evil, and with it (normal state).
      (should (eq (lookup-key agent-ui-canvas-mode-map "g") #'agent-ui-canvas-redraw))
      (let ((normal (evil-get-auxiliary-keymap agent-ui-canvas-mode-map 'normal)))
        ;; q kills it (config/agent-ui.el), in Vim's keys and Emacs's.
        (should (eq (lookup-key normal "q") #'kill-current-buffer))
        (should (eq (lookup-key agent-ui-canvas-mode-map "q") #'kill-current-buffer))
        (should (eq (lookup-key normal "gr") #'agent-ui-canvas-redraw))))
    ;; The same one again; others by name.
    (should (eq (agent-ui-canvas) canvas))
    (let ((other (agent-ui-canvas "other-test")))
      (unwind-protect
          (progn (should-not (eq other canvas))
                 (should (memq other (agent-ui-canvases)))
                 (should (memq canvas (agent-ui-canvases))))
        (kill-buffer other)))
    ;; Not a canvas: an error.
    (with-temp-buffer
      (should (string-match-p "isn't a live canvas"
                              (+test-auc-message #'agent-ui-show '(:type "meter")
                                                 :canvas (current-buffer)))))))

;; Only showing an element makes a canvas: looking at one doesn't.
(ert-deftest agent-ui-canvas/made-by-showing-only ()
  (+test-auc
    (let ((name (make-temp-name "unmade-")))
      (should-not (agent-ui-elements :canvas name))
      (should-not (agent-ui-clear :canvas name))
      (dolist (call (list (lambda () (agent-ui-get "a" :canvas name))
                          (lambda () (agent-ui-update "a" '(:value 1) :canvas name))
                          (lambda () (agent-ui-append "a" '(:marks ("x")) :canvas name))
                          (lambda () (agent-ui-remove "a" :canvas name))))
        (should (equal (agent-ui-error-message (should-error (funcall call) :type 'agent-ui-error))
                       (format "canvas %s has no elements yet" name))))
      (should-not (get-buffer (agent-ui-canvas-buffer-name name)))
      (agent-ui-show '(:id "a" :type "meter") :canvas name)
      (let ((made (get-buffer (agent-ui-canvas-buffer-name name))))
        (should made)
        (kill-buffer made)))))

;; ====== SHOWING ======

(ert-deftest agent-ui-canvas/elements-shown-in-order ()
  (+test-auc
    (should (equal (agent-ui-show '(:id "a" :type "meter" :value 1)) "a"))
    (should (equal (agent-ui-show '(:id "b" :type meter :value 2 :title "B")) "b"))
    ;; Drawn at once, a blank line after each.
    (should (equal (+test-auc-text) "1/10\n\nB\n2/10\n\n"))
    (should (equal (agent-ui-elements) '((:id "a" :type "meter") (:id "b" :type "meter"))))
    ;; Each element's text knows its id.
    (with-current-buffer canvas
      (should (equal (get-text-property 1 'agent-ui-id) "a"))
      (should (equal (get-text-property 7 'agent-ui-id) "b")))
    ;; Its type a string, as JSON's.
    (should (equal (agent-ui-get "b") '(:id "b" :type "meter" :value 2 :title "B")))))

(ert-deftest agent-ui-canvas/shown-again-replaced-in-place ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter" :value 1))
    (agent-ui-show '(:id "b" :type "meter" :value 2))
    ;; All of it replaced (no :max: its default), in its place, drawn soon.
    (agent-ui-show '(:id "a" :type "spinner"))
    (+test-auc-flush)
    (should (equal (+test-auc-text) "spin 0\n\n2/10\n\n"))
    (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements)) '("a" "b")))))

(ert-deftest agent-ui-canvas/an-id-made ()
  (+test-auc
    (should (equal (agent-ui-show '(:type "meter")) "meter-1"))
    (should (equal (agent-ui-show '(:type "meter")) "meter-2"))
    ;; One the agent chose is skipped.
    (agent-ui-show '(:id "meter-3" :type "meter"))
    (should (equal (agent-ui-show '(:type "meter")) "meter-4"))
    (should (string-match-p "an id is letters"
                            (+test-auc-message #'agent-ui-show '(:id "a b" :type "meter"))))
    (should (string-match-p "an id is letters"
                            (+test-auc-message #'agent-ui-show '(:id 3 :type "meter"))))))

(ert-deftest agent-ui-canvas/a-wrong-element-refused ()
  (+test-auc
    (should (string-match-p "unknown property \"total\""
                            (+test-auc-message #'agent-ui-show '(:id "a" :type "meter" :total 3))))
    (should (string-match-p "unknown type"
                            (+test-auc-message #'agent-ui-show '(:id "a" :type "metre"))))
    (should (string-match-p "a title is text"
                            (+test-auc-message #'agent-ui-show '(:id "a" :type "meter" :title 3))))
    ;; Nothing added, nothing shown.
    (should-not (agent-ui-elements))
    (should (equal (+test-auc-text) ""))
    (should-not +test-auc-displayed)))

(ert-deftest agent-ui-canvas/a-failing-drawing-in-its-place ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "broken"))
    (agent-ui-show '(:id "b" :type "meter"))
    (should (equal (+test-auc-text) "⚠ Boom\n\n0/10\n\n"))))

(ert-deftest agent-ui-canvas/at-most-so-many ()
  (+test-auc
    (let ((agent-ui-max-elements 2))
      (agent-ui-show '(:type "meter"))
      (agent-ui-show '(:id "b" :type "meter"))
      (should (string-match-p "the most it holds"
                              (+test-auc-message #'agent-ui-show '(:type "meter"))))
      ;; One shown again is no more.
      (should (agent-ui-show '(:id "b" :type "meter"))))))

;; ====== SHOWN IN A WINDOW ======

(ert-deftest agent-ui-canvas/shown-when-an-element-is-added ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter"))
    (should (equal +test-auc-displayed (list canvas)))
    ;; Updates, an element shown again: not shown again.
    (agent-ui-update "a" '(:value 3))
    (agent-ui-show '(:id "a" :type "meter"))
    (should (= (length +test-auc-displayed) 1))
    ;; Hidden, then a new element: shown again.
    (agent-ui-show '(:id "b" :type "meter"))
    (should (= (length +test-auc-displayed) 2))
    ;; In a window already: not.
    (save-window-excursion
      (switch-to-buffer canvas)
      (agent-ui-show '(:id "c" :type "meter"))
      (should (= (length +test-auc-displayed) 2)))))

(ert-deftest agent-ui-canvas/shown-without-the-focus ()
  (+test-auc
    (let ((agent-ui-display-function #'agent-ui-display-canvas))
      (save-window-excursion
        (delete-other-windows)
        (let ((before (selected-window)))
          (agent-ui-show '(:id "a" :type "meter"))
          (should (eq (selected-window) before))
          (should (get-buffer-window canvas)))))))

(ert-deftest agent-ui-canvas/drawn-at-its-windows-width ()
  (+test-auc
    ;; In no window: `agent-ui-default-width'.
    (let ((agent-ui-default-width 33))
      (agent-ui-show '(:id "a" :type "meter" :wide t)))
    (should (equal (+test-auc-text) "0/10 w33\n\n"))
    (save-window-excursion
      (delete-other-windows)
      (switch-to-buffer canvas)
      (agent-ui-canvas-redraw)
      ;; A column short of the window's.
      (should (equal (+test-auc-text)
                     (format "0/10 w%d\n\n" (1- (window-max-chars-per-line))))))))

;; ====== UPDATES ======

(ert-deftest agent-ui-canvas/updated-later-together ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter" :value 1))
    (setq +test-auc-draws 0)
    (should (equal (agent-ui-update "a" '(:value 2)) "a"))
    (agent-ui-update "a" '(:value 3 :max 5))
    ;; Not yet.
    (should (equal (+test-auc-text) "1/10\n\n"))
    (should (= +test-auc-draws 0))
    ;; Once, with both.
    (+test-auc-flush)
    (should (equal (+test-auc-text) "3/5\n\n"))
    (should (= +test-auc-draws 1))
    ;; nil: back to its default.
    (agent-ui-update "a" '(:max nil))
    (+test-auc-flush)
    (should (equal (+test-auc-text) "3/10\n\n"))))

(ert-deftest agent-ui-canvas/glyphs-in-their-cells ()
  "In the GUI, an element's text goes into the canvas evened out
\(`agent-ui-even-glyphs'): the space after a glyph wider than its column
narrower, a panel's border after it in line; in a terminal, as it is."
  (+test-auc
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
              ((symbol-function 'frame-char-width) (lambda (&optional _) 11))
              ((symbol-function 'agent-ui--glyph)
               (lambda (char _face _buffer) (if (eq char ?✎) '(17) '(11)))))
      (agent-ui-show '(:id "a" :type "meter" :marks ("✎ a")))
      (should (equal (+test-auc-text) "0/10 ✎ a\n\n"))
      (with-current-buffer canvas
        (should (equal (get-text-property 7 'display) '(space :width (5))))))
    (agent-ui-show '(:id "a" :type "meter" :marks ("✎ b")))
    (+test-auc-flush)
    (with-current-buffer canvas
      (should-not (get-text-property 7 'display)))))

(ert-deftest agent-ui-canvas/redrawn-when-the-font-changes ()
  "A frame's font changed (its size): every canvas drawn again, for its new
cells (its window's size in pixels the same, no size change said it); a
size change with the same width in columns but other cells too."
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter"))
    (+test-auc-flush)
    (let ((draws +test-auc-draws))
      (run-hooks 'after-setting-font-hook)
      (with-current-buffer canvas (should agent-ui--dirty))
      (+test-auc-flush)
      (should (= +test-auc-draws (1+ draws))))
    (save-window-excursion
      (delete-other-windows)
      (switch-to-buffer canvas)
      (agent-ui-canvas-redraw)
      (+test-auc-flush)
      (let ((draws +test-auc-draws))
        ;; Same width, same cells: as it is.
        (agent-ui--size-changed (selected-window))
        (+test-auc-flush)
        (should (= +test-auc-draws draws))
        ;; Same width, other cells: drawn again.
        (with-current-buffer canvas (setq agent-ui--cell '(11 25)))
        (agent-ui--size-changed (selected-window))
        (+test-auc-flush)
        (should (= +test-auc-draws (1+ draws)))
        (with-current-buffer canvas
          (should (equal agent-ui--cell (list (frame-char-width) (frame-char-height)))))))))

(ert-deftest agent-ui-canvas/redrawn-by-its-timer ()
  (+test-auc
    (let ((agent-ui-redraw-delay 0.01))
      (agent-ui-show '(:id "a" :type "meter"))
      (agent-ui-update "a" '(:value 4))
      (with-timeout (2 (ert-fail "Not redrawn"))
        (while (not (equal (+test-auc-text) "4/10\n\n"))
          (accept-process-output nil 0.01)))
      (should-not (buffer-local-value 'agent-ui--redraw-timer canvas)))))

(ert-deftest agent-ui-canvas/many-updates-quick ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter"))
    (setq +test-auc-draws 0)
    (let ((start (float-time)))
      (dotimes (i 1000)
        (agent-ui-update "a" (list :value i)))
      ;; A thousand updates: well under a second, nothing drawn yet.
      (should (< (- (float-time) start) 1.0)))
    (should (= +test-auc-draws 0))
    (+test-auc-flush)
    (should (= +test-auc-draws 1))
    (should (equal (+test-auc-text) "999/10\n\n"))))

(ert-deftest agent-ui-canvas/a-wrong-update-refused ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter" :value 1))
    (agent-ui-show '(:id "b" :type "meter"))
    (should (equal (+test-auc-message #'agent-ui-update "c" '(:value 2))
                   (format "no element \"c\" in canvas %s; its elements: a, b"
                           agent-ui-default-canvas)))
    (should (string-match-p "must be a number"
                            (+test-auc-message #'agent-ui-update "a" '(:value "x"))))
    (should (string-match-p "can't change the type"
                            (+test-auc-message #'agent-ui-update "a" '(:type "spinner"))))
    ;; Unchanged.
    (should (equal (agent-ui-get "a") '(:id "a" :type "meter" :value 1)))))

(ert-deftest agent-ui-canvas/appended-to ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter" :marks ("x")))
    (should (equal (agent-ui-append "a" '(:marks ("y" "z"))) "a"))
    (+test-auc-flush)
    (should (equal (+test-auc-text) "0/10 x,y,z\n\n"))
    (should (string-match-p "only lists"
                            (+test-auc-message #'agent-ui-append "a" '(:value 3))))))

(ert-deftest agent-ui-canvas/point-kept ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter"))
    (agent-ui-show '(:id "b" :type "meter" :value 2))
    (with-current-buffer canvas
      ;; On b's text; a grows before it.
      (goto-char (point-min))
      (search-forward "2/")
      (agent-ui-update "a" '(:value 123456 :marks ("long" "marks")))
      (agent-ui--flush)
      (should (looking-at "10\n"))
      (should (looking-back "2/" 2)))))

(ert-deftest agent-ui-canvas/the-mark-kept-in-a-redrawn-element ()
  "The mark inside an element drawn again: kept at its line and column (its
text replaced, it fell to the element's start: a region there, text being
selected, stretched to it), as active as it was (doom-8gh)."
  (+test-auc
    (agent-ui-define lines "Its text." :props ((text string "The text")) :text (lambda (p _c) (plist-get p :text)))
    (agent-ui-show '(:id "intro" :type "lines" :text "hello"))
    (agent-ui-show '(:id "t" :type "lines" :text "one\ntwo\nthree"))
    (with-current-buffer canvas
      (agent-ui--flush)
      (let ((transient-mark-mode t))
        (goto-char (point-min))
        (search-forward "two")
        (backward-char 1)
        (push-mark (point) t t)
        (search-forward "thr")
        (agent-ui-update "t" '(:text "ONE\nTWO\nTHREE"))
        (agent-ui--flush)
        (should (equal (buffer-substring-no-properties (region-beginning) (region-end)) "O\nTHR"))
        (should (region-active-p))
        ;; Not active: still where it was.
        (deactivate-mark)
        (agent-ui-update "t" '(:text "one\ntwo\nthree"))
        (agent-ui--flush)
        (should-not (region-active-p))
        (should (equal (buffer-substring-no-properties (mark) (point)) "o\nthr"))))))

(ert-deftest agent-ui-canvas/a-click-on-a-button-leaves-no-region ()
  "A click on a button: its press, the drag's, left an active mark at the
click, which the action's redraw moved to the element's start (everything
above it highlighted); the button's press drops it, the redraw keeps the
mark where it was (doom-8gh)."
  (+test-auc
    (let ((pressed 0))
      (agent-ui-define clicky "A button redrawing it."
        :props ((n integer "Pressed"))
        :text (lambda (p _c)
                (concat (format "line one\nline two %s\n" (plist-get p :n))
                        (agent-ui-button "[press]" (lambda ()
                                                     (cl-incf pressed)
                                                     (agent-ui-update "c" `(:n ,pressed)))))))
      (agent-ui-show '(:id "intro" :type "meter"))
      (agent-ui-show '(:id "c" :type "clicky" :n 0))
      (save-window-excursion
        (delete-other-windows)
        (set-window-buffer (selected-window) canvas)
        (with-current-buffer canvas
          (agent-ui--flush)
          (let* ((transient-mark-mode t)
                 (pos (progn (goto-char (point-min)) (search-forward "[press]") (1+ (match-beginning 0))))
                 (posn (list (selected-window) pos '(0 . 0) 0 nil pos '(0 . 0) nil '(0 . 0) '(1 . 1)))
                 (column (progn (goto-char pos) (current-column))))
            ;; The press, as mouse-drag-track leaves it: point at the click,
            ;; the mark pushed there, active (transient-mark-mode's (only . t)).
            (goto-char pos)
            (push-mark pos t t)
            (setq transient-mark-mode (cons 'only t))
            ;; The release: pressed, the element drawn again.
            (let ((last-nonmenu-event (list 'mouse-1 posn)))
              (call-interactively (key-binding (vector last-nonmenu-event) t)))
            (agent-ui--flush)
            (should (= pressed 1))
            (should (string-search "line two 1" (buffer-string)))
            ;; No region; the mark on the button, not at the element's start.
            (should-not (region-active-p))
            (should (equal (buffer-substring-no-properties (line-beginning-position) (line-end-position)) "[press]"))
            (should (= (save-excursion (goto-char (mark t)) (current-column)) column))
            (should (= (line-number-at-pos (mark t)) (line-number-at-pos (point))))
            ;; Through Evil's press (a slow click: mouse-1 still), as clicked.
            (goto-char (point-min))
            (let ((posn (lambda (time) (list (selected-window) pos '(0 . 0) time nil pos '(0 . 0) nil '(0 . 0) '(1 . 1)))))
              (setq unread-command-events (list (list 'mouse-1 (funcall posn 900))))
              (evil-mouse-drag-region (list 'down-mouse-1 (funcall posn 0)))
              (let ((last-nonmenu-event (pop unread-command-events)))
                (should (eq (car last-nonmenu-event) 'mouse-1))
                (call-interactively (key-binding (vector last-nonmenu-event) t))))
            (agent-ui--flush)
            (should (= pressed 2))
            (should-not (region-active-p))
            (should (= (line-number-at-pos (mark t)) (line-number-at-pos (point))))))))))

(ert-deftest agent-ui-canvas/point-kept-in-a-redrawn-element ()
  "Point, a window's point and its start inside an element drawn again:
kept at their line and column in it (its text replaced, they went to its
start); past its new end, at its end."
  (+test-auc
    (agent-ui-define lines "Its text." :props ((text string "The text")) :text (lambda (p _c) (plist-get p :text)))
    (agent-ui-show '(:id "intro" :type "lines" :text "hello"))
    (agent-ui-show '(:id "t" :type "lines" :text "one\ntwo\nthree\nfour"))
    (with-current-buffer canvas
      (agent-ui--flush)
      (goto-char (point-min))
      (search-forward "three")
      (backward-char 2)
      (agent-ui-update "t" '(:text "ONE\nTWO\nTHREE\nFOUR"))
      (agent-ui--flush)
      (should (looking-at "EE"))
      ;; Shorter: on its last line.
      (agent-ui-update "t" '(:text "just one"))
      (agent-ui--flush)
      (should (equal (buffer-substring-no-properties (line-beginning-position) (line-end-position)) "just one"))
      ;; Before it: where it was.
      (goto-char (+ (point-min) 2))
      (agent-ui-update "t" '(:text "again\nand again"))
      (agent-ui--flush)
      (should (= (point) (+ (point-min) 2))))
    ;; A window showing it, not selected: its point and start kept.
    (save-window-excursion
      (delete-other-windows)
      (let ((window (split-window)))
        (set-window-buffer window canvas)
        (agent-ui-update "t" '(:text "a\nb\nc\nd\ne"))
        (with-current-buffer canvas (agent-ui--flush))
        (let ((d (with-current-buffer canvas
                   (goto-char (point-min)) (search-forward "d") (match-beginning 0))))
          (set-window-point window d)
          (set-window-start window d)
          (with-current-buffer canvas (goto-char (point-min)))
          (agent-ui-update "t" '(:text "A\nB\nC\nD\nE"))
          (with-current-buffer canvas (agent-ui--flush))
          (with-current-buffer canvas
            (should (equal (char-after (window-point window)) ?D))
            (should (equal (char-after (window-start window)) ?D))))))))

;; ====== REMOVING ======

(ert-deftest agent-ui-canvas/removed ()
  (+test-auc
    (dolist (id '("a" "b" "c"))
      (agent-ui-show (list :id id :type "meter" :title id)))
    (should (equal (agent-ui-remove "b") "b"))
    (should (equal (+test-auc-text) "a\n0/10\n\nc\n0/10\n\n"))
    ;; A pending redraw of it: forgotten.
    (agent-ui-update "c" '(:value 5))
    (agent-ui-remove "c")
    (+test-auc-flush)
    (should (equal (+test-auc-text) "a\n0/10\n\n"))
    (should (string-match-p "no element \"c\"" (+test-auc-message #'agent-ui-remove "c")))
    ;; Shown again: at the end.
    (agent-ui-show '(:id "b" :type "meter"))
    (should (equal (+test-auc-text) "a\n0/10\n\n0/10\n\n"))
    (agent-ui-clear)
    (should (equal (+test-auc-text) ""))
    (should-not (agent-ui-elements))))

(ert-deftest agent-ui-canvas/empty-its-pane-closes ()
  "Cleared, or its last element removed: its pane closes (it stayed open,
empty); shown again, it opens. A pane made for it (a new window: tiling's,
with nothing before; display-buffer's, marked so) closes; a window that
showed another buffer goes back to it; a frame's last window stays."
  (+test-auc
    (save-window-excursion
      (delete-other-windows)
      (let* ((window nil)
             (agent-ui-display-function
              (lambda (b)
                (setq window (split-window (frame-root-window) nil 'right))
                (set-window-buffer window b)
                ;; As tiling makes it: nothing shown there before.
                (set-window-prev-buffers window nil))))
        (agent-ui-show '(:id "a" :type "meter"))
        (agent-ui-show '(:id "b" :type "meter"))
        (should (eq (window-buffer window) canvas))
        (agent-ui-remove "a")
        (should (eq (window-buffer window) canvas))
        (agent-ui-remove "b")
        (should-not (window-live-p window))
        (should (one-window-p))
        ;; Shown again: a pane; cleared: gone.
        (agent-ui-show '(:id "c" :type "meter"))
        (should (window-live-p window))
        (agent-ui-clear)
        (should-not (window-live-p window))
        (should (buffer-live-p canvas)))
      ;; Made by display-buffer for it (marked so): closes, though the split
      ;; window showed another buffer first.
      (let* ((window nil)
             (agent-ui-display-function
              (lambda (b)
                (setq window (split-window (frame-root-window) nil 'right))
                (set-window-buffer window b)
                (set-window-parameter window 'quit-restore (list 'window 'window (selected-window) b)))))
        (agent-ui-show '(:id "d" :type "meter"))
        (agent-ui-clear)
        (should-not (window-live-p window)))
      ;; A window that showed another buffer: back to it.
      (let ((other (get-buffer-create "*test-before*")))
        (unwind-protect
            (let* ((window (split-window (frame-root-window) nil 'right))
                   (agent-ui-display-function (lambda (b) (set-window-buffer window b))))
              (set-window-buffer window other)
              (agent-ui-show '(:id "e" :type "meter"))
              (should (eq (window-buffer window) canvas))
              (agent-ui-clear)
              (should (window-live-p window))
              (should (eq (window-buffer window) other)))
          (kill-buffer other)))
      ;; The frame's last window: stays.
      (delete-other-windows)
      (let ((agent-ui-display-function (lambda (b) (set-window-buffer (selected-window) b)
                                         (set-window-prev-buffers (selected-window) nil))))
        (agent-ui-show '(:id "f" :type "meter"))
        (agent-ui-clear)
        (should (window-live-p (selected-window)))))))

;; ====== ANIMATION ======

(ert-deftest agent-ui-canvas/animated-while-there-are ()
  (+test-auc
    (agent-ui-show '(:id "a" :type "meter"))
    (should-not (buffer-local-value 'agent-ui--animation-timer canvas))
    (agent-ui-show '(:id "s" :type "spinner"))
    (should (timerp (buffer-local-value 'agent-ui--animation-timer canvas)))
    ;; A frame: drawn only while the canvas is in a window.
    (agent-ui--frame canvas)
    (should (equal (+test-auc-text) "0/10\n\nspin 0\n\n"))
    (save-window-excursion
      (switch-to-buffer canvas)
      (agent-ui--frame canvas)
      (agent-ui--frame canvas))
    (should (equal (+test-auc-text) "0/10\n\nspin 2\n\n"))
    ;; None left: its timer stopped.
    (agent-ui-remove "s")
    (should-not (buffer-local-value 'agent-ui--animation-timer canvas))))

(ert-deftest agent-ui-canvas/timers-stopped-when-killed ()
  (+test-auc
    (agent-ui-show '(:id "s" :type "spinner"))
    (agent-ui-update "s" '(:title "x"))
    (let ((timers (with-current-buffer canvas
                    (list agent-ui--redraw-timer agent-ui--animation-timer))))
      (should (cl-every #'timerp timers))
      (kill-buffer canvas)
      (dolist (timer timers)
        (should-not (memq timer timer-list))))
    ;; The macro kills it again: a live one.
    (setq canvas (agent-ui-canvas))))

;; ====== A PANEL'S CHILDREN ======

(defconst +test-auc-panel-type (gethash 'panel agent-ui--types)
  "The real panel type (the tests' registry, bound in each test, lacks it).")

(defun +test-auc-with-panels ()
  "The real panel type, in the tests' registry."
  (puthash 'panel +test-auc-panel-type agent-ui--types))

(defconst +test-auc-panel
  '(:id "dash" :type "panel" :layout "row" :min-width 5
    :children ((:id "a" :type "meter" :value 1)
               (:type "panel" :border :false :children ((:id "b" :type "meter" :value 2)))))
  "A panel: a, and b in a panel in it.")

(ert-deftest agent-ui-canvas/a-panels-children-by-id ()
  (+test-auc
    (+test-auc-with-panels)
    (agent-ui-show +test-auc-panel)
    ;; Listed after their panel.
    (should (equal (agent-ui-elements)
                   '((:id "dash" :type "panel") (:id "a" :type "meter" :panel "dash") (:id "b" :type "meter" :panel "dash"))))
    (should (equal (agent-ui-get "b") '(:id "b" :type "meter" :value 2)))
    ;; Updated by its own id: its panel redrawn.
    (agent-ui-update "b" '(:value 7))
    (+test-auc-flush)
    (should (string-match-p "1/10 +│ 7/10" (+test-auc-text)))
    (should (equal (plist-get (agent-ui-get "b") :value) 7))
    ;; Appended to.
    (agent-ui-append "a" '(:marks ("x")))
    (+test-auc-flush)
    (should (string-match-p "1/10 x" (+test-auc-text)))
    ;; Shown again by its id: replaced in its place.
    (agent-ui-show '(:id "a" :type "spinner"))
    (+test-auc-flush)
    (should (string-match-p "spin [0-9]+ +│ 7/10" (+test-auc-text)))
    ;; Removed: out of its panel.
    (agent-ui-remove "a")
    (+test-auc-flush)
    (should-not (agent-ui--find-child (agent-ui-get "dash") "a"))
    (should (string-match-p "7/10" (+test-auc-text)))
    (should (string-match-p "no element \"a\"" (+test-auc-message #'agent-ui-get "a")))))

(ert-deftest agent-ui-canvas/a-childs-id-taken ()
  (+test-auc
    (+test-auc-with-panels)
    (agent-ui-show +test-auc-panel)
    (should (string-match-p "the id \"b\" is taken"
                            (+test-auc-message #'agent-ui-show '(:id "other" :type "panel" :children ((:id "b" :type "meter"))))))
    ;; A wrong change to a child: refused, the panel as it was.
    (should (string-match-p "must be a number" (+test-auc-message #'agent-ui-update "b" '(:value "x"))))
    (should (equal (plist-get (agent-ui-get "b") :value) 2))))

(ert-deftest agent-ui-canvas/a-childs-text-knows-it ()
  (+test-auc
    (+test-auc-with-panels)
    (agent-ui-show +test-auc-panel)
    (with-current-buffer canvas
      (agent-ui--flush)
      (goto-char (point-min))
      (search-forward "2/10")
      (should (equal (get-text-property (match-beginning 0) 'agent-ui-child) "b"))
      (should (equal (get-text-property (match-beginning 0) 'agent-ui-id) "dash"))
      ;; Its link, its start.
      (should (equal (get-text-property (agent-ui--element-start canvas "b") 'agent-ui-child) "b")))))
