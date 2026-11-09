;;; tests/unit/test-agent-ui-elements.el -*- lexical-binding: t; -*-
;; config/agent-ui/elements/: Agent UI's element types, each drawn as text at
;; a width, checked (what's wrong said), appended to; their examples right.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defun +test-aue-draw (element &rest ctx)
  "ELEMENT drawn, its text only, in CTX (`agent-ui-context''s keys; width 60)."
  (substring-no-properties
   (agent-ui-render element (apply #'agent-ui-context (append ctx '(:width 60))))))

(defun +test-aue-face-at (element string &rest ctx)
  "The face of STRING's first character in ELEMENT's drawing."
  (let* ((text (agent-ui-render element (apply #'agent-ui-context (append ctx '(:width 60)))))
         (at (string-search string (substring-no-properties text))))
    (should at)
    (get-text-property at 'face text)))

(defun +test-aue-error (element)
  (agent-ui-error-message
   (should-error (agent-ui-check (plist-get element :type) element) :type 'agent-ui-error)))

;; ====== ALL OF THEM ======

(ert-deftest agent-ui-elements/the-types ()
  (should (equal (agent-ui-types) '(progress steps table)))
  ;; Each with an example (checked when defined), drawn without an error.
  (dolist (name (agent-ui-types))
    (let* ((type (agent-ui-type name))
           (example (append (list :type (symbol-name name)) (agent-ui-type-example type))))
      (should (agent-ui-type-example type))
      (should (equal (agent-ui-type-file type)
                     (expand-file-name (format "config/agent-ui/elements/%s.el" name) +test-root)))
      (dolist (width '(20 60 200))
        (let ((text (agent-ui-render example (agent-ui-context :width width))))
          (should-not (string-match-p "⚠" text))
          ;; No line wider than the width.
          (dolist (line (split-string text "\n"))
            (should (<= (string-width line) (max width 30)))))))))

;; ====== PROGRESS ======

(ert-deftest agent-ui-elements/progress ()
  (should (equal (+test-aue-draw '(:type "progress" :value 7 :max 12 :label "linking"))
                 "████████████████▎░░░░░░░░░░░  7/12  58%  linking"))
  ;; No label: the bar takes the room.
  (should (equal (+test-aue-draw '(:type "progress" :value 1 :max 4))
                 (concat (make-string 10 ?█) (make-string 30 ?░) "  1/4  25%")))
  ;; Over its max: full.
  (should (string-prefix-p (make-string 40 ?█) (+test-aue-draw '(:type "progress" :value 9 :max 4))))
  (should (string-suffix-p "  9/4  100%" (+test-aue-draw '(:type "progress" :value 9 :max 4))))
  ;; Floats, a unit.
  (should (string-match-p "  1.5/3 MB  50%\\'"
                          (+test-aue-draw '(:type "progress" :value 1.5 :max 3 :unit "MB"))))
  ;; A long label cut to the width.
  (let ((text (+test-aue-draw (list :type "progress" :value 1 :max 2 :label (make-string 100 ?x)))))
    (should (= (string-width text) 60))
    (should (string-suffix-p "x…" text))))

(ert-deftest agent-ui-elements/progress-states ()
  (let ((done '(:type "progress" :value 12 :max 12 :status "done" :label "built"))
        (failed '(:type "progress" :value 3 :max 12 :status "failed" :label "cc: error")))
    (should (string-suffix-p "12/12  100%  ✓ built" (+test-aue-draw done)))
    (should (eq (+test-aue-face-at done "█") 'agent-ui-success))
    (should (string-suffix-p "3/12  25%  ✗ cc: error" (+test-aue-draw failed)))
    (should (eq (+test-aue-face-at failed "█") 'agent-ui-error))
    (should (eq (+test-aue-face-at failed "░") 'agent-ui-muted))
    (should (eq (+test-aue-face-at '(:type "progress" :value 1 :max 2) "█") 'agent-ui-accent))
    ;; Only one without a max, running, is animated.
    (should-not (agent-ui-animated-p done))
    (should-not (agent-ui-animated-p '(:type "progress" :max 2)))
    (should (agent-ui-animated-p '(:type "progress")))
    (should-not (agent-ui-animated-p '(:type "progress" :status "done")))))

(ert-deftest agent-ui-elements/progress-without-an-end ()
  (cl-flet ((at (tick) (string-search "█" (+test-aue-draw '(:type "progress" :label "waiting")
                                                           :tick tick))))
    ;; The block moves with the ticks, then back.
    (should (= (at 0) 0))
    (should (= (at 3) 3))
    (should (> (at 20) (at 3)))
    (should (= (at (* 2 (- 33 4))) 0)))
  (should (string-match-p "  37 files  waiting\\'"
                          (+test-aue-draw '(:type "progress" :value 37 :unit "files" :label "waiting"))))
  ;; Done: full, no counts.
  (should (equal (+test-aue-draw '(:type "progress" :status "done"))
                 (concat (make-string 40 ?█) "  ✓"))))

(ert-deftest agent-ui-elements/progress-wrong ()
  (should (equal (+test-aue-error '(:type "progress" :max 0))
                 "progress: max must be above 0, not 0"))
  (should (equal (+test-aue-error '(:type "progress" :status "paused"))
                 "progress: status must be one of: running, done, failed, not \"paused\"")))

;; ====== STEPS ======

(ert-deftest agent-ui-elements/steps ()
  (let ((element '(:type "steps"
                   :steps ((:name "Run the tests" :status "done" :detail "412 passed")
                           (:name "Build" :status "running")
                           "Publish"
                           (:name "Tag" :status "failed" :detail "exists")
                           (:name "Notify" :status "skipped")))))
    (should (equal (+test-aue-draw element :tick 2)
                   (concat "✓ Run the tests  412 passed\n"
                           "⠹ Build\n"
                           "○ Publish\n"
                           "✗ Tag            exists\n"
                           "– Notify")))
    ;; The spinner turns.
    (should (string-match-p "⠼ Build" (+test-aue-draw element :tick 4)))
    (should (agent-ui-animated-p element))
    (should (eq (+test-aue-face-at element "✓") 'agent-ui-success))
    (should (eq (+test-aue-face-at element "exists") 'agent-ui-error))
    (should (eq (+test-aue-face-at element "Publish") 'agent-ui-muted)))
  (should-not (agent-ui-animated-p '(:type "steps" :steps ("a" (:name "b" :status "done")))))
  (should (equal (+test-aue-draw '(:type "steps")) "no steps yet")))

(ert-deftest agent-ui-elements/steps-appended-by-name ()
  (let ((element '(:type "steps" :steps ("a" (:name "b" :status "running" :detail "x")))))
    (should (equal (plist-get (agent-ui-append-to element
                                                  '(:steps ((:name "b" :status "done") "c" "a")))
                              :steps)
                   ;; b changed in its place, its detail kept; c added; a as it was.
                   '("a" (:name "b" :status "done" :detail "x") "c")))
    (should (string-match-p "only steps"
                            (agent-ui-error-message
                             (should-error (agent-ui-append-to element '(:title "x"))
                                           :type 'agent-ui-error))))))

(ert-deftest agent-ui-elements/steps-wrong ()
  (should (equal (+test-aue-error '(:type "steps" :steps ("a" (:name "b" :status "paused"))))
                 "steps: step 2 has status \"paused\"; one of: pending, running, done, failed, skipped"))
  (should (equal (+test-aue-error '(:type "steps" :steps ((:status "done"))))
                 "steps: step 1 has no name"))
  (should (equal (+test-aue-error '(:type "steps" :steps ((:name "a" :state "done"))))
                 "steps: step 1 has \"state\": a step has name, status, detail"))
  (should (string-match-p "step 1 is 3" (+test-aue-error '(:type "steps" :steps (3))))))

;; ====== TABLE ======

(ert-deftest agent-ui-elements/table ()
  (let ((element '(:type "table" :columns ("Test" "Result" "Time" "N")
                   :rows (("lexer" "passed" "0.4s" 12) ("parser" "running" nil 3.5) ("x")))))
    (should (equal (+test-aue-draw element)
                   (concat " Test   │ Result  │ Time │   N\n"
                           "────────┼─────────┼──────┼────\n"
                           " lexer  │ passed  │ 0.4s │  12\n"
                           " parser │ running │      │ 3.5\n"
                           " x      │         │      │")))
    (should (eq (+test-aue-face-at element "Test") 'bold))
    (should (eq (+test-aue-face-at element "passed") 'agent-ui-success))
    (should (eq (+test-aue-face-at element "running") 'agent-ui-accent)))
  ;; Alignment given; true, false, null.
  (should (equal (+test-aue-draw '(:type "table" :columns ("A" "B") :align ("right" "center")
                                   :rows (("x" t) ("yy" :false))))
                 (concat "  A │   B\n"
                         "────┼──────\n"
                         "  x │ true\n"
                         " yy │ false")))
  (should (equal (+test-aue-draw '(:type "table" :columns ("A" "B")))
                 " A │ B\n───┼──\n no rows yet")))

(ert-deftest agent-ui-elements/table-fits-the-width ()
  (let ((text (+test-aue-draw '(:type "table" :columns ("Name" "Description")
                                :rows (("a long name, longer than that" "a description much too long for the width it's given"))))))
    (dolist (line (split-string text "\n"))
      (should (<= (string-width line) 60)))
    (should (string-match-p "…" text)))
  ;; Too many rows: what's left out said.
  (let ((agent-ui-max-rows 2))
    (should (string-suffix-p "… 1 rows more"
                             (+test-aue-draw '(:type "table" :columns ("A") :rows (("1") ("2") ("3"))))))))

(ert-deftest agent-ui-elements/table-appended-by-key ()
  (dolist (key '(0 "Test"))
    (let ((element (list :type "table" :columns '("Test" "Result") :key key
                         :rows '(("lexer" "running") ("parser" "running")))))
      (should (equal (plist-get (agent-ui-append-to element '(:rows (("parser" "failed") ("ast" "running"))))
                                :rows)
                     '(("lexer" "running") ("parser" "failed") ("ast" "running"))))))
  ;; No key: added.
  (should (equal (plist-get (agent-ui-append-to '(:type "table" :columns ("A") :rows (("x")))
                                                '(:rows (("x"))))
                            :rows)
                 '(("x") ("x"))))
  ;; Numbers as keys: as their text.
  (should (equal (plist-get (agent-ui-append-to '(:type "table" :columns ("N" "V") :key 0 :rows ((1 "a")))
                                                '(:rows ((1 "b"))))
                            :rows)
                 '((1 "b")))))

(ert-deftest agent-ui-elements/table-wrong ()
  (should (equal (+test-aue-error '(:type "table" :columns ("A") :rows (("x" "y"))))
                 "table: row 1 has 2 cells, for 1 columns"))
  (should (equal (+test-aue-error '(:type "table" :columns ("A") :rows ("x")))
                 "table: row 1 must be an array of cells, not \"x\""))
  (should (string-match-p "a cell is text"
                          (+test-aue-error '(:type "table" :columns ("A") :rows (((:k 1)))))))
  (should (string-match-p "columns must be names"
                          (+test-aue-error '(:type "table" :columns (1 2)))))
  (should (string-match-p "key must be a column"
                          (+test-aue-error '(:type "table" :columns ("A") :key "B"))))
  (should (string-match-p "key must be a column"
                          (+test-aue-error '(:type "table" :columns ("A") :key 1))))
  (should (string-match-p "align is left, right or center"
                          (+test-aue-error '(:type "table" :columns ("A") :align ("middle")))))
  (should (equal (+test-aue-error '(:type "table"))
                 "table: columns is required")))
