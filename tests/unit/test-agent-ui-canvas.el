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
        (should (eq (lookup-key normal "q") #'quit-window))
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
