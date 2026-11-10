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
  (should (equal (agent-ui-types) '(chart choice code diff files graph heatmap html image issues log markdown panel progress stats steps table text timeline)))
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
            (should (equal (list name width line (string-width line))
                           (list name width line (min (string-width line) (max width 30)))))))))))

;; ====== TEXT ======

(ert-deftest agent-ui-elements/text ()
  (should (equal (+test-aue-draw '(:type "text" :text "One line.\nAnother.")) "One line.\nAnother."))
  ;; Wrapped to the width, at spaces.
  (should (equal (+test-aue-draw (list :type "text" :text (string-join (make-list 8 "word") " "))
                                 :width 20)
                 "word word word word\nword word word word"))
  (should (eq (+test-aue-face-at '(:type "text" :text "Done." :face "success") "Done") 'agent-ui-success))
  (should (eq (+test-aue-face-at '(:type "text" :text "Hm." :face "muted") "Hm") 'agent-ui-muted))
  (should-not (+test-aue-face-at '(:type "text" :text "Plain.") "Plain"))
  (should (equal (+test-aue-error '(:type "text")) "text: text is required"))
  (should (string-match-p "face must be one of"
                          (+test-aue-error '(:type "text" :text "x" :face "loud")))))

;; ====== MARKDOWN ======

(ert-deftest agent-ui-elements/markdown ()
  (let ((element '(:type "markdown" :markdown "# Plan\n\nSome **bold** and `code`.\n\n- one\n- two\n")))
    (should (equal (+test-aue-draw element) "Plan\n\nSome bold and code.\n\n• one\n• two"))
    ;; As agent-shell draws it: its faces.
    (should (eq (+test-aue-face-at element "bold") 'agent-shell-markdown-bold))
    ;; Wrapped to the width, its faces kept.
    (should (equal (+test-aue-draw element :width 10) "Plan\n\nSome bold\nand code.\n\n• one\n• two"))
    (should (eq (+test-aue-face-at element "code" :width 10) 'agent-shell-markdown-inline-code)))
  ;; A table: at the canvas's width, not the selected window's.
  (let ((text (+test-aue-draw (list :type "markdown"
                                    :markdown (concat "| A | B |\n|---|---|\n| "
                                                      (string-join (make-list 30 "word") " ")
                                                      " | x |\n"))
                              :width 40)))
    (should (string-match-p "│" text))
    (dolist (line (split-string text "\n"))
      (should (<= (string-width line) 40)))))

(ert-deftest agent-ui-elements/markdown-without-agent-shell ()
  ;; As written, wrapped.
  (cl-letf (((symbol-function 'agent-ui-markdown--render) #'ignore))
    (should (equal (+test-aue-draw '(:type "markdown" :markdown "Some **bold** words") :width 12)
                   "Some\n**bold**\nwords"))))

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
    ;; Drawn as given (not kept on a canvas: no times noted).
    (should (equal (+test-aue-draw element :tick 2)
                   (concat "✓ Run the tests  412 passed\n"
                           "⠹ Build\n"
                           "○ Publish\n"
                           "✗ Tag            exists\n"
                           "– Notify")))
    ;; None timed: no times' column.
    (should (equal (+test-aue-draw '(:type "steps" :steps ((:name "a" :status "done" :detail "x") "bb")))
                   "✓ a   x\n○ bb"))
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
                 "steps: step 1 has \"state\": a step has name, status, detail, seconds, steps"))
  (should (string-match-p "step 1 is 3" (+test-aue-error '(:type "steps" :steps (3))))))

(ert-deftest agent-ui-elements/steps-their-times ()
  (let* ((now 100.0)
         (agent-ui-clock (lambda () now))
         (element (agent-ui--checked '(:type "steps" :steps ((:name "a" :status "running") "b")))))
    ;; Running: when it began, noted; its time counts.
    (should (equal (plist-get (car (plist-get element :steps)) :started) 100.0))
    (setq now 112.0)
    (should (string-match-p "a  12s" (+test-aue-draw element)))
    ;; Done: how long it ran, kept; the next one starts.
    (setq now 141.0)
    (setq element (agent-ui--checked (agent-ui-append-to element '(:steps ((:name "a" :status "done")
                                                                            (:name "b" :status "running"))))))
    (should (equal (plist-get (car (plist-get element :steps)) :seconds) 41.0))
    (setq now 150.0)
    (should (equal (+test-aue-draw element) "✓ a  41s\n⠋ b   9s"))
    ;; Kept again (a panel's re-check): nothing changes.
    (should (equal (agent-ui--checked element) element))
    ;; A panel's: noted too.
    (should (equal (plist-get (car (plist-get (car (plist-get (agent-ui--checked '(:type "panel" :children ((:type "steps" :steps ((:name "c" :status "running"))))))
                                                              :children))
                                              :steps))
                              :started)
                   150.0))
    ;; Given: as given; a step not run has none.
    (should (equal (+test-aue-draw '(:type "steps" :steps ((:name "x" :status "done" :seconds 125) "y")))
                   "✓ x  2m 05s\n○ y"))
    ;; Run again (failed, then running): timed anew, not with its first run's
    ;; time (it stayed frozen at 41s).
    (setq element (agent-ui--checked (agent-ui-append-to element '(:steps ((:name "a" :status "failed"))))))
    (setq now 300.0)
    (setq element (agent-ui--checked (agent-ui-append-to element '(:steps ((:name "a" :status "running"))))))
    (setq now 312.0)
    (should (string-match-p "a +12s" (+test-aue-draw element)))
    (setq now 330.0)
    (setq element (agent-ui--checked (agent-ui-append-to element '(:steps ((:name "a" :status "done"))))))
    (should (equal (plist-get (car (plist-get element :steps)) :seconds) 30.0))))

(ert-deftest agent-ui-elements/steps-on-one-line-each ()
  "A step's name or detail with line breaks (a failing test's): on its line
(it ran onto lines of its own, at column 0)."
  (let ((text (+test-aue-draw '(:type "steps" :steps ((:name "Run the tests" :status "failed" :seconds 3
                                                      :detail "AssertionError: x\n  at foo.js:3")
                                                     (:name "Build\nthe app" :status "done" :seconds 2)
                                                     (:name "Ship")))
                              :width 70)))
    (should (= (length (split-string text "\n")) 3))
    (should (string-match-p "AssertionError: x⏎  at foo.js:3" text))
    (should (string-match-p "✓ Build⏎the app" text))))

(ert-deftest agent-ui-elements/steps-fit-narrow-widths ()
  "From 10 columns, steps with times, details and sub-steps within the width
(the names' column was 10 at least, past it under ~20)."
  (let ((element (agent-ui--checked
                  '(:type "steps" :steps ((:name "Build the project" :status "done" :seconds 100)
                                          (:name "Run the tests" :status "failed" :seconds 3 :detail "2 failed")
                                          (:name "Deploy" :steps ((:name "upload" :steps ((:name "chunks" :steps ((:name "chunk 1")))))))))))
        (agent-ui-clock (lambda () 0.0)))
    (dolist (width (number-sequence 10 24))
      (dolist (line (split-string (+test-aue-draw element :width width) "\n"))
        (should (<= (string-width line) width))))
    ;; Wide: the times shown.
    (should (string-match-p "1m 40s" (+test-aue-draw element :width 60)))))

(ert-deftest agent-ui-elements/steps-with-steps-of-their-own ()
  (let ((agent-ui-clock (lambda () 0.0)))
    ;; Drawn under theirs, indented; the names' column fits them.
    (should (equal (+test-aue-draw '(:type "steps"
                                     :steps ((:name "Build" :status "done" :seconds 12
                                              :steps ((:name "compile" :status "done" :seconds 8)
                                                      (:name "link" :status "done" :seconds 4 :detail "ok")))
                                             "Publish")))
                   "✓ Build      12s\n  ✓ compile   8s\n  ✓ link      4s  ok\n○ Publish"))
    ;; Appended by their parent's name, at any depth; merged by name.
    (let* ((element '(:type "steps" :steps ((:name "Build" :steps ((:name "compile"))) "Publish")))
           (element (agent-ui-append-to element '(:steps ((:name "link" :parent "Build" :status "running")
                                                         (:name "ld" :parent "link")
                                                         (:name "Publish" :steps ("upload"))))))
           (steps (plist-get element :steps)))
      (should (equal (mapcar #'agent-ui-steps--name (plist-get (car steps) :steps)) '("compile" "link")))
      (should (equal (plist-get (cadr (plist-get (car steps) :steps)) :steps) '((:name "ld"))))
      (should (equal (plist-get (cadr steps) :steps) '("upload")))
      ;; A nested step merged by name: its own steps too.
      (let ((merged (agent-ui-append-to element '(:steps ((:name "Build" :steps ((:name "compile" :status "done"))))))))
        (should (equal (plist-get (car (plist-get (car (plist-get merged :steps)) :steps)) :status) "done"))
        (should (= (length (plist-get (car (plist-get merged :steps)) :steps)) 2)))
      ;; Running deep down: it animates.
      (should (agent-ui-animated-p (agent-ui--checked element)))
      ;; A parent not there: said so.
      (should (string-match-p "no step \"nope\" to put \"x\" under"
                              (agent-ui-error-message
                               (should-error (agent-ui-append-to element '(:steps ((:name "x" :parent "nope"))))
                                             :type 'agent-ui-error)))))
    ;; Wrong ones: where they are.
    (should (equal (+test-aue-error '(:type "steps" :steps ((:name "a" :steps ((:name "b" :status "x"))))))
                   "steps: step 1.1 has status \"x\"; one of: pending, running, done, failed, skipped"))
    (should (string-match-p "step 1 has seconds -1" (+test-aue-error '(:type "steps" :steps ((:name "a" :seconds -1))))))
    (should (string-match-p "steps 5 deep: 4 at most"
                            (+test-aue-error '(:type "steps" :steps ((:name "1" :steps ((:name "2" :steps ((:name "3" :steps ((:name "4" :steps ("5")))))))))))))))

;; ====== TABLE ======

(ert-deftest agent-ui-elements/table-row-buttons-don-t-squeeze-it ()
  "Row buttons beside the cells while the cells keep their widths; else on a
line of their own under each row (they cut the cells to 3 columns, the rows
past the width); clickable either way."
  (let ((element '(:type "table" :columns ("Test" "Result" "Time") :rows (("lexer" "passed" "0.4s") ("parser" "failed" "1.2s"))
                   :row-actions ((:label "Fix it" :prompt "Fix {Test}") (:label "Explain" :prompt "Explain {row}")))))
    ;; Wide: beside.
    (should (string-match-p "lexer +│ passed │ 0.4s +⏵ Fix it  ⏵ Explain" (+test-aue-draw element :width 60)))
    ;; Narrow: under, the cells whole, every line within the width.
    (let ((text (+test-aue-draw element :width 34)))
      (should (string-match-p "lexer +│ passed │ 0.4s\n +⏵ Fix it  ⏵ Explain" text))
      (dolist (line (split-string text "\n"))
        (should (<= (string-width line) 34))))
    (let ((text (agent-ui-render element (agent-ui-context :width 34))))
      (should (get-text-property (string-search "⏵ Fix it" text) 'agent-ui-action text)))))

(ert-deftest agent-ui-elements/table-columns-that-fit ()
  "More columns than fit, each cut to its narrowest: those on the left that
fit, the others said under it (it stayed wider than its width)."
  (let ((six '(:type "table" :columns ("Name" "Status" "Time" "Owner" "Branch" "Commit")
               :rows (("a" "ok" "1s" "me" "main" "abc123") ("b" "ok" "2s" "you" "dev" "def456")))))
    (dolist (width '(15 20 30))
      (let ((text (+test-aue-draw six :width width)))
        (dolist (line (split-string text "\n"))
          (should (<= (string-width line) width)))
        (should (string-match-p "… [0-9]+ more col" text))))
    ;; Wide enough: all of them, no note.
    (should-not (string-match-p "more columns" (+test-aue-draw six :width 60)))
    (should (string-match-p "… 1 more column: Commit" (+test-aue-draw six :width 30)))))

(ert-deftest agent-ui-elements/table-sorted-by-durations ()
  "Durations sorted by their length, units and all (the leading numbers
alone put 850ms between 41s and 2m 05s)."
  (let ((text (+test-aue-draw '(:type "table" :columns ("Test" "Time") :sort "Time" :descending t
                                :rows (("a" "2m 05s") ("b" "41s") ("c" "850ms") ("d" "1.2s") ("e" "1h"))))))
    (should (string-match-p "e .*1h\n.*a .*2m 05s\n.*b .*41s\n.*d .*1.2s\n.*c .*850ms" text)))
  (should (= (agent-ui-table--duration "2m 05s") 125))
  (should (= (agent-ui-table--duration "850ms") 0.85))
  (should-not (agent-ui-table--duration "5 apples"))
  (should-not (agent-ui-table--duration "12"))
  ;; Plain numbers: as numbers still.
  (should (string-match-p " 2\n.* 10" (+test-aue-draw '(:type "table" :columns ("N") :sort "N" :rows (("10") ("2")))))))

(ert-deftest agent-ui-elements/table-sort-arrow-kept ()
  "A sorted column's name cut to fit: its arrow kept (it was cut first)."
  (let ((text (+test-aue-draw '(:type "table" :columns ("Name" "Status" "Duration" "Owner" "Branch" "Commit")
                                :sort "Duration" :descending t
                                :rows (("lexer" "passed" "0.4s" "me" "main" "abc123def") ("parser" "failed" "1.2s" "you" "dev" "def456abc")))
                              :width 40)))
    (should (string-match-p "…? ↓" (car (split-string text "\n"))))))

(ert-deftest agent-ui-elements/table-align-misspelt-refused ()
  "A misspelt align is refused (it was taken as automatic, silently); left,
right, center and null are taken."
  (dolist (wrong '("rigth" "centre" "Right" "middle"))
    (should (string-match-p "align is left, right, center or null"
                            (+test-aue-error `(:type "table" :columns ("A") :rows (("x")) :align (,wrong))))))
  (should (equal (plist-get (agent-ui-check "table" '(:type "table" :columns ("A" "B" "C") :rows (("x" "y" "z"))
                                                       :align ("right" nil "center")))
                            :align)
                 '(right nil center))))

(ert-deftest agent-ui-elements/table-cells-on-one-line ()
  "A cell's line breaks and tabs: on its line (they broke the table's lines,
and a panel's border around it)."
  (let ((text (+test-aue-draw '(:type "table" :columns ("Test" "Error")
                                :rows (("lexer" "AssertionError: x\n  at foo.js:3") ("parser" "got\tvalue")))
                              :width 40)))
    (should (= (length (split-string text "\n")) 4))
    (should (string-match-p "AssertionError: x⏎  at foo" text))
    (should (string-match-p "got value" text))
    (should-not (string-match-p "\t" text))))

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
  (should (string-match-p "align is left, right, center or null"
                          (+test-aue-error '(:type "table" :columns ("A") :align ("middle")))))
  (should (equal (+test-aue-error '(:type "table"))
                 "table: columns is required")))

;; ====== CHART ======

(ert-deftest agent-ui-elements/chart-equal-huge-values ()
  "Equal huge values (1e17): a flat line, one bin (the range's widening was
lost in float precision: a span of 0, \"Arithmetic overflow error\")."
  (dolist (kind '("line" "sparkline" "histogram" "bar"))
    (let ((element (list :type "chart" :kind kind :values '(1e17 1e17))))
      (should-not (string-search "⚠" (+test-aue-draw element :width 30)))
      (unless (equal kind "sparkline")
        (should (+test-aue-svg element 30)))))
  (should (> (agent-ui-chart--above 1e17) 1e17))
  (should (= (agent-ui-chart--above 5) 6)))

(ert-deftest agent-ui-elements/chart-a-time-for-each-value ()
  "Times and values counted the same, else refused, saying so (fewer times
broke the drawing, more squeezed the line); an append of values without
their times too."
  (should (string-match-p "3 values but 2 times"
                          (+test-aue-error '(:type "chart" :values (1 2 3) :times (0 600)))))
  (should (string-match-p "3 values but 6 times"
                          (+test-aue-error '(:type "chart" :values (1 2 3) :times (0 600 1200 1800 2400 3000)))))
  (let ((element '(:type "chart" :times ("2026-11-10T09:00:00" "2026-11-10T12:00:00") :values (120 340))))
    (should (string-match-p "3 values but 2 times"
                            (agent-ui-error-message
                             (should-error (agent-ui--checked (agent-ui-append-to element '(:values (410))))
                                           :type 'agent-ui-error))))
    ;; Together: fine.
    (should (agent-ui--checked (agent-ui-append-to element '(:values (410) :times ("2026-11-10T13:00:00")))))))

(ert-deftest agent-ui-elements/chart-times-in-any-order ()
  "Times newest first (git log's order) or unsorted: the same line as in
order (the text's plot drew nothing for them)."
  (let ((sorted '(:type "chart" :height 3 :values (10 20 30)
                  :times ("2026-11-10T10:00:00" "2026-11-10T11:00:00" "2026-11-10T12:00:00")))
        (newest-first '(:type "chart" :height 3 :values (30 20 10)
                        :times ("2026-11-10T12:00:00" "2026-11-10T11:00:00" "2026-11-10T10:00:00")))
        (unsorted '(:type "chart" :height 3 :values (20 10 30)
                    :times ("2026-11-10T11:00:00" "2026-11-10T10:00:00" "2026-11-10T12:00:00"))))
    (should (string-match-p "[⠀-⣿]" (+test-aue-draw newest-first :width 40)))
    (should (equal (+test-aue-draw newest-first :width 40) (+test-aue-draw sorted :width 40)))
    (should (equal (+test-aue-draw unsorted :width 40) (+test-aue-draw sorted :width 40)))
    (should (equal (+test-aue-svg newest-first 40) (+test-aue-svg sorted 40)))))

(ert-deftest agent-ui-elements/chart-first-and-last-labels-fit ()
  "A line chart's first and last labels each cut to half the plot (in the
GUI they were drawn over each other; in text the last ran past the width)."
  (let ((element '(:type "chart" :height 3 :labels ("2026-11-01 build" "x" "2026-11-10 nightly build") :values (1 3 2))))
    (dolist (width '(20 30 40))
      (dolist (line (split-string (+test-aue-draw element :width width) "\n"))
        (should (<= (string-width line) width))))
    (let ((svg (+test-aue-svg element 30)))
      (should-not (string-match-p ">2026-11-10 nightly build<" svg))
      (should-not (string-match-p ">2026-11-01 build<" svg)))
    ;; Wide: whole.
    (let ((svg (+test-aue-svg element 100)))
      (should (string-match-p ">2026-11-10 nightly build<" svg)))))

(ert-deftest agent-ui-elements/chart-legend-wraps ()
  "A legend wider than the chart: on more lines (rows in the GUI), its items
whole (one line ran past the width, and the SVG's right edge)."
  (let ((bars '(:type "chart" :kind "bar" :labels ("v1" "v2")
                :series ((:name "compile" :values (25 20)) (:name "test" :values (9 6))
                         (:name "lint" :values (2 3)) (:name "package" :values (4 4)))))
        (lines '(:type "chart" :height 3 :series ((:name "p50 latency" :values (1 2 3)) (:name "p95 latency" :values (2 3 4))
                                                 (:name "p99 latency" :values (3 4 5))))))
    (dolist (element (list bars lines))
      (let ((text (+test-aue-draw element :width 30)))
        (dolist (line (split-string text "\n"))
          (should (<= (string-width line) 30)))
        (should (string-match-p "● package\\|● p99 latency" text)))
      ;; In the GUI: every legend name drawn inside the image.
      (let* ((svg (+test-aue-svg element 30))
             (width (progn (string-match "<svg width=\"\\([0-9]+\\)\"" svg) (string-to-number (match-string 1 svg))))
             (start 0))
        (while (string-match "x=\"\\([0-9.]+\\)\">\\(compile\\|test\\|lint\\|package\\|p[0-9]+ latency\\)<" svg start)
          (should (< (+ (string-to-number (match-string 1 svg)) (* 8 (length (match-string 2 svg)))) (+ width 8)))
          (setq start (match-end 0)))))))

(ert-deftest agent-ui-elements/chart-labels-and-figures-fit ()
  "Long units and values: a sparkline's figures left out from the end, bar
values and line axis labels cut to a third of the width, every line within
it (they ran past it); in the GUI the plot stays inside the image."
  (let ((spark '(:type "chart" :kind "sparkline" :unit "ms" :values (1234.56 1500.25 1000.12 1300.5)))
        (bars '(:type "chart" :kind "bar" :unit "requests per second" :labels ("api" "web") :values (1200 800)))
        (line '(:type "chart" :height 3 :unit "requests per second" :values (1000.55 2000.25 1500))))
    (dolist (element (list spark bars line))
      (dolist (width '(20 30 40))
        (dolist (text-line (split-string (+test-aue-draw element :width width) "\n"))
          (should (<= (string-width text-line) width)))))
    ;; Wide: the sparkline's figures all there.
    (should (string-match-p "last 1300.5 ms  min 1000.12  max 1500.25" (+test-aue-draw spark :width 80)))
    ;; The line's plot inside its image at 20 columns (its left was 232 in 160).
    (let ((svg (+test-aue-svg line 20)))
      (string-match "points=\"\\([0-9.]+\\)" svg)
      (should (< (string-to-number (match-string 1 svg)) 160)))))

(ert-deftest agent-ui-elements/chart-svg-within-min-and-max ()
  "Values past a line chart's min or max: at the plot's edge in the GUI (the
line left the image at the top and crossed the labels' row)."
  (let* ((svg (+test-aue-svg '(:type "chart" :height 4 :min 0 :max 10 :labels ("a" "b" "c" "d") :values (5 20 -10 5)) 40))
         (points (progn (string-match "points=\"\\([^\"]+\\)\"" svg) (match-string 1 svg)))
         (ys (mapcar (lambda (p) (string-to-number (cadr (split-string (string-trim p) " "))))
                     (split-string points ","))))
    (should (cl-every (lambda (y) (and (>= y 0) (<= y (* 4 16)))) ys))))

(ert-deftest agent-ui-elements/chart-bars-start-at-min ()
  "A bar chart's min: its bars start at it (95 and 100 from 90: half and
whole; it was ignored, both near the full width); stacked bars from 0."
  (let* ((text (+test-aue-draw '(:type "chart" :kind "bar" :min 90 :labels ("a" "b") :values (95 100)) :width 40))
         (bars (mapcar (lambda (line) (cl-count-if (lambda (c) (memq c '(?█ ?▉ ?▊ ?▋ ?▌ ?▍ ?▎ ?▏))) line))
                       (split-string text "\n"))))
    (should (< (abs (- (* 2 (car bars)) (cadr bars))) 2)))
  (let ((stacked (+test-aue-draw '(:type "chart" :kind "bar" :stacked t :min 90 :labels ("a")
                                   :series ((:name "x" :values (50)) (:name "y" :values (50))))
                                 :width 40)))
    (should (string-match-p "100" stacked))))

(ert-deftest agent-ui-elements/chart-stacked-bars-not-too-long ()
  "A stacked bar no longer than its total says: 99.5 not longer than 100 (it
came out a cell too long, its line past the width)."
  (let* ((text (+test-aue-draw '(:type "chart" :kind "bar" :stacked t :labels ("a" "b")
                                 :series ((:name "x" :values (99 100)) (:name "y" :values (0.5 0))))
                               :width 42))
         (lines (split-string text "\n"))
         (cells (lambda (line) (cl-count-if (lambda (c) (memq c '(?█ ?▉ ?▊ ?▋ ?▌ ?▍ ?▎ ?▏))) line))))
    (dolist (line lines) (should (<= (string-width line) 42)))
    (should (<= (funcall cells (car lines)) (funcall cells (cadr lines))))))

(ert-deftest agent-ui-elements/chart-bars-of-nothing ()
  "Bars whose highest value is 0 (all 0 or below, or max 0): drawn, empty, text
and GUI (it divided by 0: \"Arithmetic overflow error\")."
  (dolist (element '((:type "chart" :kind "bar" :labels ("a" "b" "c") :values (-2 -1 0))
                     (:type "chart" :kind "bar" :labels ("a") :values (0))))
    (let ((text (+test-aue-draw element :width 40)))
      (should-not (string-search "⚠" text))
      (should-not (string-search "█" text)))
    (should (+test-aue-svg element 40)))
  ;; Max 0 and a min below: bars from the min (doom-nwj.52), no break.
  (should-not (string-search "⚠" (+test-aue-draw '(:type "chart" :kind "bar" :min -10 :max 0 :values (-5 -3)) :width 40))))

(ert-deftest agent-ui-elements/chart-bars ()
  (let ((element '(:type "chart" :kind "bar" :unit "ms" :labels ("mon" "tue" "wed" "thu")
                   :values (120 95 180 60))))
    (should (equal (+test-aue-draw element :width 50)
                   (concat "mon  ████████████████████████▋              120 ms\n"
                           "tue  ███████████████████▌                    95 ms\n"
                           "wed  █████████████████████████████████████  180 ms\n"
                           "thu  ████████████▎                           60 ms")))
    (should (eq (+test-aue-face-at element "█") 'agent-ui-accent)))
  ;; No labels: numbered.
  (should (string-prefix-p "1  " (+test-aue-draw '(:type "chart" :kind "bar" :values (1 2))))))

(ert-deftest agent-ui-elements/chart-sparkline ()
  (should (equal (+test-aue-draw '(:type "chart" :kind "sparkline" :unit "ms" :values (3 5 9 4 12 20 15 8 3 1 7)))
                 "▁▂▄▂▅█▆▃▁▁▃  last 7 ms  min 1  max 20"))
  ;; The latest that fit.
  (let ((text (+test-aue-draw (list :type "chart" :kind "sparkline" :values (number-sequence 1 100))
                              :width 40)))
    (should (= (string-width text) 40))
    (should (string-suffix-p "last 100  min 1  max 100" text))))

(ert-deftest agent-ui-elements/chart-lines ()
  (let* ((element '(:type "chart" :height 4 :labels ("a" "b" "c")
                    :series ((:name "up" :values (1 2 3)) (:name "down" :values (3 2 1)))))
         (lines (split-string (+test-aue-draw element :width 30) "\n")))
    ;; The height, then the labels, then the legend.
    (should (= (length lines) 6))
    (should (string-prefix-p "3 ┤" (nth 0 lines)))
    (should (string-prefix-p "  │" (nth 1 lines)))
    (should (string-prefix-p "1 ┤" (nth 3 lines)))
    (should (string-match-p "\\`   a +c\\'" (nth 4 lines)))
    (should (equal (nth 5 lines) "   ● up  ● down"))
    (dolist (line lines) (should (<= (string-width line) 30)))
    ;; Braille, each series its colour: up starts low, down high.
    (should (string-match-p "[⠀-⣿]" (nth 0 lines)))
    (should (eq (+test-aue-face-at element "● up") 'agent-ui-accent))
    (should (eq (+test-aue-face-at element "● down") 'agent-ui-warning)))
  ;; The plot: a rising line's first dot at the bottom left, its last at the
  ;; top right.
  (let ((plot (agent-ui-chart--plot '((:values (0 10))) '(0 . 10) 2 1)))
    ;; 4 dots wide, 4 high: (0,3) in the first cell, (3,0) in the second.
    (should (/= 0 (logand (aref (car plot) 0) #x40)))
    (should (/= 0 (logand (aref (car plot) 1) #x08))))
  (should (equal (+test-aue-draw '(:type "chart")) "no values yet")))

(ert-deftest agent-ui-elements/chart-as-svg ()
  (let* ((text (agent-ui-render '(:type "chart" :labels ("a" "c") :values (1 5 3) :title "T")
                                (agent-ui-context :width 50 :graphic t :char-width 8 :line-height 16)))
         (image (get-text-property 2 'display text))
         (svg (plist-get (cdr image) :data)))
    (should (string-prefix-p "T\n" (substring-no-properties text)))
    (should (eq (car image) 'image))
    (should (eq (plist-get (cdr image) :type) 'svg))
    ;; As wide as the text's 50 columns.
    (should (string-match-p "<svg width=\"400\"" svg))
    (should (string-match-p "<polyline" svg))
    (should (string-match-p ">5</text>" svg))
    (should (string-match-p ">a</text>" svg)))
  (let ((svg (plist-get (cdr (get-text-property
                              0 'display
                              (agent-ui-render '(:type "chart" :kind "bar" :labels ("x" "y") :values (1 2))
                                               (agent-ui-context :graphic t))))
                        :data)))
    (should (= (cl-count ?\n (replace-regexp-in-string "<rect" "\n" svg)) 2)))
  ;; A sparkline, or nothing to draw: text.
  (should-not (get-text-property 0 'display (agent-ui-render '(:type "chart" :kind "sparkline" :values (1 2))
                                                             (agent-ui-context :graphic t))))
  (should (equal (substring-no-properties (agent-ui-render '(:type "chart") (agent-ui-context :graphic t)))
                 "no values yet")))

(ert-deftest agent-ui-elements/chart-live ()
  ;; Values appended, the latest WINDOW kept.
  (let* ((element '(:type "chart" :window 3 :values (1 2)))
         (more (agent-ui-append-to element '(:values (3 4 5)))))
    (should (equal (plist-get more :values) '(1 2 3 4 5)))
    (should (equal (plist-get (car (plist-get (agent-ui-check "chart" more) :series)) :values) '(3 4 5))))
  ;; Series by name; a new one added.
  (let ((more (agent-ui-append-to '(:type "chart" :series ((:name "a" :values (1))))
                                  '(:series ((:name "a" :values (2)) (:name "b" :values (9)))))))
    (should (equal (plist-get more :series) '((:name "a" :values (1 2)) (:name "b" :values (9))))))
  (should (string-match-p "only values, series, labels and times"
                          (agent-ui-error-message
                           (should-error (agent-ui-append-to '(:type "chart") '(:unit "x"))
                                         :type 'agent-ui-error)))))

(ert-deftest agent-ui-elements/chart-wrong ()
  (should (equal (+test-aue-error '(:type "chart" :values (1 "x")))
                 "chart: values must be numbers; value 2 is \"x\""))
  (should (string-match-p "values (one series) or series, not both"
                          (+test-aue-error '(:type "chart" :values (1) :series ((:values (1)))))))
  (should (string-match-p "a histogram chart has one series"
                          (+test-aue-error '(:type "chart" :kind "histogram" :series ((:values (1)) (:values (2)))))))
  (should (string-match-p "series 1 has \"color\""
                          (+test-aue-error '(:type "chart" :series ((:values (1) :color "red"))))))
  (should (string-match-p "height must be from 2 to 40"
                          (+test-aue-error '(:type "chart" :height 1))))
  (should (string-match-p "min must be below max"
                          (+test-aue-error '(:type "chart" :min 5 :max 5)))))

;; ====== FILES, BUTTONS ======

(ert-deftest agent-ui-elements/a-file-relative-to-the-agent ()
  (let ((agent-ui-file-directory "/work/proj/"))
    (should (equal (plist-get (agent-ui-check "image" '(:file "shots/a.png")) :file) "/work/proj/shots/a.png"))
    (should (equal (plist-get (agent-ui-check "image" '(:file "/abs/a.png")) :file) "/abs/a.png")))
  (should (string-match-p "file must be a file's name"
                          (+test-aue-error '(:type "image" :file 3)))))

(ert-deftest agent-ui-elements/a-button ()
  (let* ((pressed nil)
         (text (agent-ui-button "open" (lambda () (setq pressed t)) "RET: open it")))
    (should (eq (get-text-property 0 'keymap text) agent-ui-button-map))
    (should (equal (get-text-property 0 'help-echo text) "RET: open it"))
    (with-temp-buffer
      (insert "x " text)
      (goto-char 4)
      (should (eq (key-binding (kbd "RET")) #'agent-ui-button-press))
      (agent-ui-button-press)
      (should pressed)
      (goto-char 1)
      (should-error (agent-ui-button-press) :type 'user-error))))

;; ====== IMAGE ======

(defconst +test-aue-image (expand-file-name "images/splash.svg" data-directory)
  "An image every Emacs has.")

(ert-deftest agent-ui-elements/image ()
  ;; In a terminal: a line naming it, a button opening it.
  (let* ((opened nil)
         (agent-ui-open-file-function (lambda (f) (setq opened f)))
         (element (list :type "image" :file +test-aue-image :alt "Emacs's splash"))
         (text (agent-ui-render element (agent-ui-context :width 200))))
    (should (equal (substring-no-properties text)
                   (format "▣ %s  Emacs's splash" (abbreviate-file-name +test-aue-image))))
    (funcall (get-text-property 3 'agent-ui-action text))
    (should (equal opened +test-aue-image)))
  ;; Not there: said.
  (should (string-suffix-p "(not found)" (+test-aue-draw '(:type "image" :file "/no/such.png"))))
  ;; In the GUI: the image, at most WIDTH percent of the pane, the alt under it.
  (let* ((text (agent-ui-render (list :type "image" :file +test-aue-image :width 50 :alt "splash")
                                (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))
         (image (get-text-property 0 'display text)))
    (should (eq (car image) 'image))
    (should (equal (plist-get (cdr image) :file) +test-aue-image))
    (should (= (plist-get (cdr image) :max-width) 240))
    (should (= (plist-get (cdr image) :max-height) (* 20 16)))
    (should (equal (substring-no-properties text 1) "\nsplash"))
    (should (functionp (get-text-property 0 'agent-ui-action text))))
  (should (string-match-p "width is a percentage" (+test-aue-error '(:type "image" :file "a.png" :width 0)))))

;; ====== HTML ======

(defun +test-aue-html (html)
  (let ((file (make-temp-file (+test-tmp-file "page-") nil ".html")))
    (with-temp-file file (insert html))
    file))

(ert-deftest agent-ui-elements/html ()
  (let* ((file (+test-aue-html "<html><head><title>Coverage &amp; report</title>
<style>p { color: red }</style></head><body><h1>Coverage: 87%</h1>
<p>Lines covered: <b>4,120</b> of&nbsp;4,735.</p><script>alert('x')</script>
<!-- a comment --><ul><li>parser.c 92%</li><li>lexer.c 78%</li></ul></body></html>"))
         (opened nil)
         (agent-ui-open-page-function (lambda (p) (setq opened p)))
         (element (list :type "html" :file file :lines 3))
         (text (agent-ui-render element (agent-ui-context :width 300))))
    (should (equal (substring-no-properties text)
                   (concat "◫ Coverage & report\n" (abbreviate-file-name file) "\n"
                           "Coverage: 87%\nLines covered: 4,120 of 4,735.\nparser.c 92%")))
    ;; Its title opens it.
    (funcall (get-text-property 2 'agent-ui-action text))
    (should (equal opened file)))
  ;; A URL: its address.
  (should (equal (+test-aue-draw '(:type "html" :url "https://example.com/report"))
                 "◫ https://example.com/report\nhttps://example.com/report"))
  (should (string-suffix-p "(not found)" (+test-aue-draw '(:type "html" :file "/no/page.html"))))
  (should (string-match-p "give a file or a url" (+test-aue-error '(:type "html"))))
  (should (string-match-p "give a file or a url" (+test-aue-error '(:type "html" :file "a" :url "b")))))

(ert-deftest agent-ui-elements/progress-seamless-in-the-gui ()
  ;; Its blocks as spaces on their colour (glyphs leave seams); the counts
  ;; and label as they are.
  (let* ((text (agent-ui-render '(:type "progress" :value 1 :max 2 :label "half")
                                (agent-ui-context :width 60 :graphic t)))
         (plain (substring-no-properties text)))
    (should-not (string-match-p "[█░]" plain))
    (should (string-match-p "\\`  +1/2  50%  half\\'" plain))
    (should (plist-get (get-text-property 0 'face text) :background))
    ;; The gap before the counts: no colour.
    (should-not (get-text-property (1- (string-search "1/2" plain)) 'face text))
    (let ((empty (get-text-property (- (string-search "1/2" plain) 3) 'face text)))
      (should (stringp (plist-get empty :background)))
      (should-not (equal (plist-get empty :background) (plist-get (get-text-property 0 'face text) :background))))))

;; ====== DIFF ======

(defconst +test-aue-diff
  "diff --git a/src/parser.c b/src/parser.c
index 1111111..2222222 100644
--- a/src/parser.c
+++ b/src/parser.c
@@ -40,4 +40,5 @@ parse_expr
   int depth = 0;
-  return NULL;
+  if (!p) return NULL;
+  return parse_term(p);
 }
\\ No newline at end of file
diff --git a/README.md b/README.md
new file mode 100644
--- /dev/null
+++ b/README.md
@@ -0,0 +1,2 @@
+# Parser
+A parser.
")

(ert-deftest agent-ui-elements/diff ()
  (let* ((opened nil)
         (agent-ui-open-file-function (lambda (f) (push f opened) (set-buffer (get-buffer-create " *opened*"))))
         (element (list :type "diff" :diff +test-aue-diff :dir "/work/"))
         (text (agent-ui-render element (agent-ui-context :width 60))))
    (should (equal (substring-no-properties text)
                   (concat "▾ src/parser.c  +2 −1\n"
                           "  @@ -40,4 +40,5 @@ parse_expr\n"
                           "     40     int depth = 0;\n"
                           "        −   return NULL;\n"
                           "     41 +   if (!p) return NULL;\n"
                           "     42 +   return parse_term(p);\n"
                           "     43   }\n"
                           "        \\  No newline at end of file\n"
                           "▾ README.md  +2 −0\n"
                           "  @@ -0,0 +1,2 @@\n"
                           "      1 + # Parser\n"
                           "      2 + A parser.")))
    (should (eq (+test-aue-face-at element "+2 −1") 'agent-ui-success))
    (should (eq (get-text-property (string-search "−   return" text) 'face text) 'agent-ui-error))
    ;; RET on an added line: its file, at its line.
    (funcall (get-text-property (string-search "if (!p)" text) 'agent-ui-action text))
    (should (equal (car opened) "/work/src/parser.c"))
    (should (= (with-current-buffer " *opened*" (line-number-at-pos)) 1))
    (kill-buffer " *opened*")
    ;; In the GUI: added and removed lines on a tint as wide as the pane.
    (let ((gui (agent-ui-render element (agent-ui-context :width 60 :graphic t))))
      (should (seq-some (lambda (f) (and (consp f) (keywordp (car f)) (plist-get f :background)))
                        (ensure-list (get-text-property (string-search "−   return" gui) 'face gui))))
      (should (= (string-width (nth 3 (split-string (substring-no-properties gui) "\n"))) 60))))
  (should (equal (+test-aue-draw '(:type "diff" :diff "")) "no changes"))
  ;; Too many lines: what's left out said.
  (let ((agent-ui-max-rows 3))
    (should (string-suffix-p "… 5 lines more" (+test-aue-draw (list :type "diff" :diff +test-aue-diff))))))

(ert-deftest agent-ui-elements/diff-dir-the-agents ()
  ;; Its dir: the agent's directory, when shown (relative names resolve there).
  (let ((agent-ui-file-directory "/proj/")
        (agent-ui-default-canvas (make-temp-name "diff-"))
        (agent-ui-display-function #'ignore))
    (unwind-protect
        (progn
          (agent-ui-show '(:id "d" :type "diff" :diff ""))
          (should (equal (plist-get (agent-ui-get "d") :dir) "/proj/"))
          (agent-ui-show '(:id "e" :type "diff" :dir "sub"))
          (should (equal (plist-get (agent-ui-get "e") :dir) "/proj/sub")))
      (kill-buffer (agent-ui-canvas)))))

;; ====== CHOICE ======

(defmacro +test-aue-canvas (&rest body)
  "BODY with a canvas of its own (`canvas'), no window shown; killed after."
  (declare (indent 0))
  `(let* ((agent-ui-default-canvas (make-temp-name "choice-"))
          (agent-ui-display-function #'ignore)
          (canvas (progn (agent-ui-show '(:id "first" :type "text" :text "x")) (agent-ui-canvas))))
     (unwind-protect (progn ,@body) (kill-buffer canvas))))

(defun +test-aue-press (text)
  "Press the button on TEXT in the current canvas."
  (agent-ui--flush)
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0))
  (agent-ui-button-press))

(ert-deftest agent-ui-elements/choice-one ()
  (+test-aue-canvas
    (let* ((sent nil)
           (agent-ui-action-function (lambda (prompt submit) (push (list prompt submit) sent))))
      (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?"
                       :options ((:label "Change the test" :detail "keeps the new message") "Revert")))
      (with-current-buffer canvas
        (agent-ui--flush)
        (should (string-match-p (concat "Which fix\\?\n ( ) Change the test  keeps the new message\n"
                                        " ( ) Revert\n ⏵ Answer")
                                (buffer-substring-no-properties (point-min) (point-max))))
        ;; Nothing chosen: nothing to answer.
        (should-error (+test-aue-press "⏵ Answer") :type 'user-error)
        (+test-aue-press "Change the test")
        (should (equal (plist-get (agent-ui-get "fix") :selected) '("Change the test")))
        ;; One only: choosing another replaces it; choosing it again, none.
        (+test-aue-press "Revert")
        (should (equal (plist-get (agent-ui-get "fix") :selected) '("Revert")))
        (agent-ui--flush)
        (should (string-match-p "(•) Revert" (buffer-string)))
        (+test-aue-press "⏵ Answer")
        (should (equal sent '(("Answer to choice fix (Which fix?): Revert" nil))))
        ;; Answered: said, no more buttons.
        (agent-ui--flush)
        (should (string-match-p "Which fix\\?\n✓ Answered: Revert" (buffer-string)))
        (should-not (string-search "⏵ Answer" (buffer-string)))))))

(ert-deftest agent-ui-elements/choice-several-and-a-note ()
  (+test-aue-canvas
    (let* ((sent nil)
           (agent-ui-action-function (lambda (prompt submit) (push (list prompt submit) sent))))
      (agent-ui-show '(:id "pick" :type "choice" :question "Which tests?" :multiple t :note t :submit t
                       :options ("lexer" "parser" "checker") :selected ("lexer")))
      (with-current-buffer canvas
        (+test-aue-press "parser")
        (+test-aue-press "lexer")
        (+test-aue-press "checker")
        (should (equal (plist-get (agent-ui-get "pick") :selected) '("parser" "checker")))
        (agent-ui--flush)
        (should (string-match-p "\\[ \\] lexer\n \\[x\\] parser\n \\[x\\] checker" (buffer-string)))
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "only the slow ones")))
          (+test-aue-press "Add a note"))
        (+test-aue-press "⏵ Send the answer")
        (should (equal sent '(("Answer to choice pick (Which tests?): parser, checker. Note: only the slow ones" t))))
        (should (equal (plist-get (agent-ui-get "pick") :answered) "parser, checker · note: only the slow ones"))))))

(ert-deftest agent-ui-elements/choice-wrong ()
  ;; None, or an empty list (JSON's []: the same): required.
  (should (string-match-p "options is required" (+test-aue-error '(:type "choice" :question "Q?" :options ()))))
  (should (string-match-p "option 2 must be" (+test-aue-error '(:type "choice" :question "Q?" :options ("a" 3)))))
  (should (string-match-p "same label" (+test-aue-error '(:type "choice" :question "Q?" :options ("a" "a")))))
  (should (string-match-p "selected \"c\" isn't an option"
                          (+test-aue-error '(:type "choice" :question "Q?" :options ("a" "b") :selected ("c")))))
  (should (string-match-p "one option only"
                          (+test-aue-error '(:type "choice" :question "Q?" :options ("a" "b") :selected ("a" "b")))))
  ;; Its buttons, outside a canvas (a render): said.
  (let ((text (agent-ui-render '(:type "choice" :question "Q?" :options ("a")) (agent-ui-context))))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (search-forward " a")
      (goto-char (match-beginning 0))
      (should-error (agent-ui-button-press) :type 'user-error))))

;; ====== FILES ======

(ert-deftest agent-ui-elements/files-flat-and-tree ()
  (let ((files '((:path "src/parser.c" :status "changed" :added 12 :removed 3)
                 (:path "src/lexer.h" :status "added" :added 40)
                 (:path "tests/parser_test.c" :status "failing" :errors 1 :line 88)
                 "README.md")))
    (should (equal (+test-aue-draw (list :type "files" :files files))
                   (concat "M src/parser.c         +12 −3\n"
                           "A src/lexer.h          +40\n"
                           "✗ tests/parser_test.c  1 error\n"
                           "  README.md")))
    (should (equal (+test-aue-draw (list :type "files" :files files :tree t))
                   (concat "▾ src/\n"
                           "    M parser.c  +12 −3\n"
                           "    A lexer.h   +40\n"
                           "▾ tests/\n"
                           "    ✗ parser_test.c  1 error\n"
                           "  README.md")))
    (should (eq (+test-aue-face-at (list :type "files" :files files) "✗") 'agent-ui-error))
    (should (equal (+test-aue-draw '(:type "files")) "no files"))))

(ert-deftest agent-ui-elements/files-open-and-fold ()
  (+test-aue-canvas
    (let* ((opened nil)
           (agent-ui-open-file-function (lambda (f) (push f opened) (set-buffer (get-buffer-create " *opened*")))))
      (with-current-buffer (get-buffer-create " *opened*") (erase-buffer) (insert (make-string 100 ?\n)))
      (agent-ui-show '(:id "f" :type "files" :tree t :dir "/work/"
                       :files ((:path "src/a.c" :status "changed") (:path "tests/t.c" :status "failing" :line 42))))
      (with-current-buffer canvas
        ;; A file: opened at its line.
        (+test-aue-press "t.c")
        (should (equal (car opened) "/work/tests/t.c"))
        (should (= (with-current-buffer " *opened*" (line-number-at-pos)) 42))
        ;; A folder: folded, its files counted; again, unfolded.
        (+test-aue-press "src/")
        (agent-ui--flush)
        (should (equal (plist-get (agent-ui-get "f") :folded) '("src/")))
        (should (string-match-p "▸ src/  1 files\n▾ tests/" (buffer-string)))
        (+test-aue-press "src/")
        (should-not (plist-get (agent-ui-get "f") :folded))))
    (kill-buffer " *opened*")))

(ert-deftest agent-ui-elements/files-wrong ()
  (should (string-match-p "file 2 has no path" (+test-aue-error '(:type "files" :files ("a" (:status "added"))))))
  (should (string-match-p "status \"edited\"" (+test-aue-error '(:type "files" :files ((:path "a" :status "edited"))))))
  (should (string-match-p "added must be a count" (+test-aue-error '(:type "files" :files ((:path "a" :added -1))))))
  (should (string-match-p "has \"size\"" (+test-aue-error '(:type "files" :files ((:path "a" :size 3)))))))

;; ====== STATS ======

(ert-deftest agent-ui-elements/stats ()
  (let ((element '(:type "stats" :figures ((:label "Coverage" :value 87.1 :unit "%" :change 2.3)
                                          (:label "Tests" :value 412 :change "all pass")
                                          (:label "Build" :value 29 :unit "s" :change -12 :good "down")
                                          (:label "Errors" :value 3 :change 1 :good "down")))))
    (should (equal (+test-aue-draw element :width 60)
                   (concat "Coverage       Tests          Build          Errors\n"
                           "87.1% ▲2.3     412 all pass   29 s ▼12       3 ▲1")))
    ;; A rise good (up), a fall good (down), a rise bad (down).
    (should (eq (+test-aue-face-at element "▲2.3") 'agent-ui-success))
    (should (eq (+test-aue-face-at element "▼12") 'agent-ui-success))
    (should (eq (+test-aue-face-at element "▲1") 'agent-ui-error))
    ;; Narrow: wrapped.
    (should (string-match-p "\\`Coverage +Tests\n87.1% ▲2.3 +412 all pass\n\nBuild +Errors\n29 s ▼12 +3 ▲1\\'"
                            (+test-aue-draw element :width 30)))
    ;; In the GUI: tiles, an SVG.
    (let ((svg (plist-get (cdr (get-text-property 0 'display (agent-ui-render element (agent-ui-context :width 80 :graphic t)))) :data)))
      (should (= 4 (cl-count ?\n (replace-regexp-in-string "<rect" "\n" svg))))
      (should (string-match-p ">87.1%</text>" svg))))
  (should (equal (+test-aue-draw '(:type "stats")) "no figures")))

(ert-deftest agent-ui-elements/stats-tiles-fit ()
  "In the GUI, a tile's value and change side by side when they fit; in a
narrow pane, the change on a line of its own under the value (its row a line
taller), both cut to the tile: nothing overlaps, nothing spills out."
  (let* ((element '(:type "stats" :figures ((:label "p50" :value 11.8 :unit "s" :change "max 36.6 s")
                                          (:label "p95" :value 20.1 :unit "s" :change "max 40.2 s")
                                          (:label "Runs" :value 412 :change 3)
                                          (:label "Failed" :value 2 :change -1 :good "down")
                                          (:label "Longest" :value "123456789012345" :change "x"))))
         (svg-of (lambda (width)
                   (plist-get (cdr (get-text-property 0 'display
                                                      (agent-ui-render element (agent-ui-context :width width :graphic t
                                                                                                :char-width 8 :line-height 16))))
                              :data))))
    ;; Narrow: 16-column tiles, 3 a row; "11.8 s" and "max 36.6 s" don't fit
    ;; side by side: the change under, at the tile's left, rows 4 lines tall.
    (let ((svg (funcall svg-of 60)))
      (should (string-match-p "<svg[^>]* height=\"136\"" svg))
      (should (string-match-p "<text[^>]* y=\"54.4\" x=\"8\">max 36.6 s</text>" svg))
      (should-not (string-match-p "text-anchor=\"end\"[^>]*>max 36.6 s<" svg))
      ;; A value wider than its tile: cut.
      (should (string-match-p ">12345678&#8230;</text>" svg)))
    ;; Wide: side by side, the change at the tile's right; 3 lines, but
    ;; for a value as wide as its tile (its change under).
    (let ((svg (funcall svg-of 160)))
      (should (string-match-p "<svg[^>]* height=\"64\"" svg))
      (should (string-match-p "text-anchor=\"end\"[^>]*>max 36.6 s</text>" svg)))
    (setq element (list :type "stats" :figures (butlast (plist-get element :figures))))
    (should (string-match-p "<svg[^>]* height=\"48\"" (funcall svg-of 160)))))

(ert-deftest agent-ui-elements/stats-tiles-in-one-row-when-they-fit ()
  "Tiles that fit side by side are drawn in one row (the gaps between them
weren't counted: 3 figures wrapped 2 and 1 from 50 to 79 columns)."
  (let ((rows-of (lambda (figures width)
                   (let ((svg (plist-get (cdr (get-text-property
                                               0 'display (agent-ui-render (list :type "stats" :figures figures)
                                                                           (agent-ui-context :width width :graphic t
                                                                                             :char-width 8 :line-height 16))))
                                         :data))
                         (ys nil) (start 0))
                     (while (string-match "<rect [^>]*y=\"\\([0-9.]+\\)\"" svg start)
                       (cl-pushnew (match-string 1 svg) ys :test #'equal)
                       (setq start (match-end 0)))
                     (length ys))))
        (three '((:label "Coverage" :value 87.1 :unit "%" :change 2.3) (:label "Tests" :value 412 :change "all pass")
                 (:label "Build" :value 29 :unit "s" :change -12 :good "down")))
        (four '((:label "a" :value 1) (:label "b" :value 2) (:label "c" :value 3) (:label "d" :value 4))))
    (dolist (width '(55 60 70 78))
      (should (= (funcall rows-of three width) 1)))
    (should (= (funcall rows-of four 80) 1))
    ;; Too narrow: they wrap still.
    (should (= (funcall rows-of three 40) 2))))

(ert-deftest agent-ui-elements/stats-narrow-pane-and-unit ()
  "Under 16 columns a tile is no wider than the pane (it was 128 px in 96);
a unit that isn't text is refused (it broke the drawing)."
  (let ((svg (plist-get (cdr (get-text-property
                              0 'display (agent-ui-render '(:type "stats" :figures ((:label "Heap" :value 512 :unit "MB")))
                                                          (agent-ui-context :width 12 :graphic t :char-width 8 :line-height 16))))
                        :data)))
    (should (string-match-p "<svg width=\"96\"" svg))
    (should (string-match-p "<rect width=\"96\"" svg)))
  (should (string-match-p "figure 1 has unit 1024: a unit is text"
                          (+test-aue-error '(:type "stats" :figures ((:label "Heap" :value 512 :unit 1024)))))))

(ert-deftest agent-ui-elements/stats-wrong ()
  (should (string-match-p "figure 1 has no label" (+test-aue-error '(:type "stats" :figures ((:value 1))))))
  (should (string-match-p "figure 1 has no value" (+test-aue-error '(:type "stats" :figures ((:label "a"))))))
  (should (string-match-p "good is up, down or none" (+test-aue-error '(:type "stats" :figures ((:label "a" :value 1 :good "yes"))))))
  (should (string-match-p "has \"trend\"" (+test-aue-error '(:type "stats" :figures ((:label "a" :value 1 :trend 2)))))))

;; ====== LOG ======

(ert-deftest agent-ui-elements/log ()
  (let ((element '(:type "log" :lines "start\nWARN: slow query\nERROR db: refused\ndebug: retry\nPanic! at the disco\nok")))
    (should (equal (+test-aue-draw element)
                   (concat "2 errors · 1 warning · 6 lines\n"
                           "start\nWARN: slow query\nERROR db: refused\ndebug: retry\nPanic! at the disco\nok")))
    (should (eq (+test-aue-face-at element "ERROR db") 'agent-ui-error))
    (should (eq (+test-aue-face-at element "WARN:") 'agent-ui-warning))
    (should (eq (+test-aue-face-at element "debug:") 'agent-ui-muted))
    (should-not (+test-aue-face-at element "start")))
  ;; Words, not parts of words: "errorless" isn't an error.
  (should (equal (+test-aue-draw '(:type "log" :lines "errorless run")) "1 line\nerrorless run"))
  ;; Given levels; the last SHOW shown, KEEP counted.
  (should (equal (+test-aue-draw '(:type "log" :show 2 :keep 3
                                   :lines ((:level "error" :text "a") "b" "c" (:level "warning" :text "d"))))
                 "1 warning · 3 lines\nc\nd"))
  (should (equal (+test-aue-draw '(:type "log")) "no lines yet")))

(ert-deftest agent-ui-elements/log-appended ()
  (should (equal (plist-get (agent-ui-append-to '(:type "log" :lines "a\nb") '(:lines "c\n")) :lines) '("a" "b" "c")))
  (should (equal (plist-get (agent-ui-append-to '(:type "log" :lines ("a")) '(:lines ("b" "c"))) :lines) '("a" "b" "c")))
  (should (string-match-p "only lines" (agent-ui-error-message (should-error (agent-ui-append-to '(:type "log") '(:show 3)) :type 'agent-ui-error)))))

(ert-deftest agent-ui-elements/log-wrong ()
  (should (string-match-p "line 1 must be" (+test-aue-error '(:type "log" :lines ((:level "loud" :text "x"))))))
  (should (string-match-p "keep is 1 to 5000" (+test-aue-error '(:type "log" :keep 0))))
  (should (string-match-p "lines is text or a list" (+test-aue-error '(:type "log" :lines 3)))))

;; ====== TIMELINE ======

(ert-deftest agent-ui-elements/timeline ()
  (let ((element '(:type "timeline" :tasks ((:name "build" :start 0 :duration 10)
                                           (:name "test" :start 10 :end 20 :status "failed")
                                           (:name "deploy" :start 20 :duration 10 :status "queued")))))
    (should (equal (+test-aue-draw element :width 50)
                   (concat "build   ██████████                      10s\n"
                           "test              ██████████            10s\n"
                           "deploy                      ░░░░░░░░░░  10s\n"
                           "        0s            15s          30s")))
    (should (eq (+test-aue-face-at element "░") 'agent-ui-muted))
    (let ((text (agent-ui-render element (agent-ui-context :width 50))))
      (should (eq (get-text-property (string-search "10s" text (string-search "test" text)) 'face text)
                  'agent-ui-error)))
    (should-not (agent-ui-animated-p element)))
  ;; Running, in seconds: until the latest end; not animated.
  (should (string-match-p "  running"
                          (+test-aue-draw '(:type "timeline" :tasks ((:name "a" :start 0 :duration 4) (:name "b" :start 2))))))
  ;; Timestamps: running ones until now, animated (they grow).
  (let* ((start (format-time-string "%FT%TZ" (time-subtract nil 30) t))
         (element (list :type "timeline" :tasks (list (list :name "job" :start start)))))
    (should (agent-ui-animated-p element))
    ;; Whole seconds in the timestamp: 30 or 31 ago.
    (should (string-match-p "3[01]s\\'" (+test-aue-draw element))))
  ;; In the GUI: SVG bars.
  (let ((svg (plist-get (cdr (get-text-property 0 'display (agent-ui-render '(:type "timeline" :tasks ((:name "a" :start 0 :duration 1)))
                                                                            (agent-ui-context :graphic t))))
                        :data)))
    (should (string-match-p "<rect" svg)))
  (should (equal (+test-aue-draw '(:type "timeline")) "no tasks")))

(ert-deftest agent-ui-elements/timeline-wrong ()
  (should (string-match-p "task 1 has no name" (+test-aue-error '(:type "timeline" :tasks ((:start 0))))))
  (should (string-match-p "start must be seconds or a timestamp" (+test-aue-error '(:type "timeline" :tasks ((:name "a" :start "soon"))))))
  (should (string-match-p "ends before it starts" (+test-aue-error '(:type "timeline" :tasks ((:name "a" :start 5 :end 1))))))
  (should (string-match-p "status is running, done" (+test-aue-error '(:type "timeline" :tasks ((:name "a" :start 0 :status "slow"))))))
  (should (string-match-p "has \"stop\"" (+test-aue-error '(:type "timeline" :tasks ((:name "a" :start 0 :stop 3)))))))

;; ====== GRAPH ======

(ert-deftest agent-ui-elements/graph-layout ()
  (cl-flet ((layout (nodes edges)
              (agent-ui-graph-layout (mapcar (lambda (id) (list :id id)) nodes)
                                     (mapcar (lambda (e) (list :from (car e) :to (cadr e))) edges))))
    ;; By the longest path: codegen after checker, not beside it.
    (should (equal (layout '("lexer" "parser" "checker" "codegen")
                           '(("lexer" "parser") ("parser" "checker") ("parser" "codegen") ("checker" "codegen")))
                   '(("lexer") ("parser") ("checker") ("codegen"))))
    ;; A cycle: its edge back left out, no loop.
    (should (equal (layout '("a" "b" "c") '(("a" "b") ("b" "c") ("c" "a"))) '(("a") ("b") ("c"))))
    ;; Unconnected nodes: the first layer.
    (should (equal (layout '("x" "y") nil) '(("x" "y"))))
    ;; Ordered by their parents' places (fewer crossings).
    (should (equal (layout '("a" "b" "c" "d") '(("a" "d") ("b" "c")))
                   '(("a" "b") ("d" "c"))))))

(ert-deftest agent-ui-elements/graph ()
  (let ((element '(:type "graph" :nodes ("lexer" "parser" (:id "checker" :status "error"))
                   :edges (("lexer" "parser") (:from "parser" :to "checker" :label "types") ("parser" "codegen")))))
    ;; codegen: a node only an edge names.
    (should (equal (+test-aue-draw element)
                   (concat "lexer   ─▶ parser\n"
                           "parser  ─▶ checker (types), codegen\n"
                           "checker\n"
                           "codegen")))
    (should (eq (+test-aue-face-at element "checker") 'agent-ui-error))
    ;; In the GUI: a box each, an arrow each, shrunk to the pane.
    (let ((svg (plist-get (cdr (get-text-property 0 'display (agent-ui-render element (agent-ui-context :width 20 :graphic t))))
                          :data)))
      (should (= 4 (cl-count ?\n (replace-regexp-in-string "<rect" "\n" svg))))
      (should (= 3 (cl-count ?\n (replace-regexp-in-string "marker-end" "\n" svg))))
      (should (string-match-p "<svg width=\"160\"" svg))
      (should (string-match-p "viewBox=\"0 0 [0-9]+ [0-9]+\"" svg))))
  (should (equal (+test-aue-draw '(:type "graph")) "no nodes")))

(ert-deftest agent-ui-elements/graph-wrong ()
  (should (string-match-p "edge 1 must be" (+test-aue-error '(:type "graph" :edges (("a"))))))
  (should (string-match-p "node 1 must be" (+test-aue-error '(:type "graph" :nodes (3)))))
  (should (string-match-p "status is ok, error" (+test-aue-error '(:type "graph" :nodes ((:id "a" :status "red"))))))
  (should (string-match-p "direction must be" (+test-aue-error '(:type "graph" :direction "up")))))

;; ====== CODE ======

(ert-deftest agent-ui-elements/code ()
  (let ((element '(:type "code" :language "emacs-lisp" :from 10
                   :code "(defun f (x)\n  (error \"no\"))"
                   :marks ((:line 11 :kind "error" :note "always fails")))))
    (should (equal (+test-aue-draw element)
                   "10 │ (defun f (x)\n11 ✗   (error \"no\"))  ← always fails"))
    ;; Highlighted by its mode; its mark, its note.
    (should (eq (+test-aue-face-at element "defun") 'font-lock-keyword-face))
    (should (eq (+test-aue-face-at element "✗") 'agent-ui-error))
    (should (eq (+test-aue-face-at element "← always") 'agent-ui-error))))

(ert-deftest agent-ui-elements/code-from-its-file ()
  (let* ((file (make-temp-file (+test-tmp-file "code-") nil ".py"
                               (mapconcat (lambda (n) (format "x%d = %d" n n)) (number-sequence 1 30) "\n")))
         (opened nil)
         (agent-ui-open-file-function (lambda (f) (push f opened) (find-file f)))
         (element (list :type "code" :file file :from 5 :to 7))
         (text (agent-ui-render element (agent-ui-context :width 60))))
    ;; Its lines FROM to TO, its file named above; python-mode's colours (by its name).
    (should (equal (substring-no-properties text)
                   (concat (abbreviate-file-name file) "\n5 │ x5 = 5\n6 │ x6 = 6\n7 │ x7 = 7")))
    (should (get-text-property (string-search "x6" text) 'face text))
    ;; RET on a line: its file, there.
    (funcall (get-text-property (string-search "x6" text) 'agent-ui-action text))
    (should (equal (car opened) file))
    (should (= (line-number-at-pos) 6))
    (kill-buffer (current-buffer))
    (should (string-suffix-p "not found" (+test-aue-draw '(:type "code" :file "/no/such.py"))))))

(ert-deftest agent-ui-elements/code-wrong ()
  (should (string-match-p "give code, or a file" (+test-aue-error '(:type "code"))))
  (should (string-match-p "from is a line" (+test-aue-error '(:type "code" :code "x" :from 0))))
  (should (string-match-p "to is before from" (+test-aue-error '(:type "code" :file "a" :from 5 :to 2))))
  (should (string-match-p "mark 1's kind" (+test-aue-error '(:type "code" :code "x" :marks ((:line 1 :kind "bad"))))))
  (should (string-match-p "mark 1 must be" (+test-aue-error '(:type "code" :code "x" :marks ((:kind "error")))))))

;; ====== ISSUES ======

(defconst +test-aue-issues
  '(:ready ("p-1" "p-4")
    :issues ((:id "p-1" :title "Ready one" :status "open" :priority 2)
             (:id "p-4" :title "Urgent ready" :status "open" :priority 0 :labels ("ui"))
             (:id "p-2" :title "Working on it" :status "in_progress" :priority 1)
             (:id "p-3" :title "Waits on p-2" :status "open" :priority 2)
             (:id "p-5" :title "Old" :status "closed" :closed_at "2026-01-01T00:00:00Z")
             (:id "p-6" :title "New" :status "closed" :closed_at "2026-02-01T00:00:00Z")
             (:id "p-e" :title "An epic" :status "open" :issue_type "epic")))
  "A project's issues as fetched: p-3 blocked (open, not ready).")

(ert-deftest agent-ui-elements/issues-a-board ()
  (let ((agent-ui-issues--cache (make-hash-table :test #'equal)))
    (puthash "/proj/" +test-aue-issues agent-ui-issues--cache)
    (let ((element '(:type "issues" :dir "/proj/")))
      ;; Side by side: by priority; done, the latest first; no epics.
      (should (equal (+test-aue-draw element :width 80)
                     (concat "Ready (2)           In progress (1)     Blocked (1)         Done (2)\n"
                             "p-4 Urgent ready    p-2 Working on it   p-3 Waits on p-2    p-6 New\n"
                             "p-1 Ready one                                               p-5 Old")))
      (should (eq (+test-aue-face-at element "p-4") 'agent-ui-warning))
      ;; Narrow: one under another.
      (should (string-prefix-p "Ready (2)\np-4 Urgent ready\np-1 Ready one\n\nIn progress (1)"
                               (+test-aue-draw element :width 40))))
    ;; An epic's, a label's.
    (puthash "/proj/" (list :ready nil :issues '((:id "e.1" :title "child" :status "in_progress")
                                                 (:id "x" :title "other" :status "in_progress")))
             agent-ui-issues--cache)
    (should (string-match-p "In progress (1)" (+test-aue-draw '(:type "issues" :dir "/proj/" :parent "e") :width 80)))
    (puthash "/proj/" +test-aue-issues agent-ui-issues--cache)
    (should (string-match-p "Ready (1)" (+test-aue-draw '(:type "issues" :dir "/proj/" :label "ui") :width 80)))
    ;; Not fetched yet; bd failing.
    ;; All led alike: the lead left out.
    (puthash "/proj/" '(:ready ("a") :issues ((:id "a" :title "Agent UI element: diff" :status "open")
                                              (:id "b" :title "Agent UI: a bug" :status "in_progress")))
             agent-ui-issues--cache)
    (should (string-match-p "a diff +b a bug" (+test-aue-draw '(:type "issues" :dir "/proj/") :width 80)))
    (should (equal (+test-aue-draw '(:type "issues" :dir "/other/")) "fetching the issues…"))
    (puthash "/bad/" '(:error "no Beads issues here (bd failed)") agent-ui-issues--cache)
    (should (equal (+test-aue-draw '(:type "issues" :dir "/bad/")) "no Beads issues here (bd failed)"))))

(ert-deftest agent-ui-elements/issues-open-one ()
  (let ((agent-ui-issues--cache (make-hash-table :test #'equal))
        (opened nil))
    (puthash "/proj/" +test-aue-issues agent-ui-issues--cache)
    (let* ((agent-ui-open-issue-function (lambda (id dir) (push (list id dir) opened)))
           (text (agent-ui-render '(:type "issues" :dir "/proj/") (agent-ui-context :width 80))))
      (funcall (get-text-property (string-search "Working on" text) 'agent-ui-action text))
      (should (equal opened '(("p-2" "/proj/")))))))

(ert-deftest agent-ui-elements/issues-fetched-by-bd ()
  (unless (executable-find "bd") (ert-skip "No bd"))
  (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "issues-home-") t)))
         (root (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "issues-") t))))
         (process-environment (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                                            "GIT_CONFIG_NOSYSTEM=1" "BD_ACTOR=Tester")
                                      process-environment))
         (default-directory root)
         (agent-ui-issues--cache (make-hash-table :test #'equal)))
    (with-temp-file (expand-file-name ".gitconfig" home)
      (insert "[user]\n\tname = T\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
    (call-process "git" nil nil nil "init" "-q")
    (should (zerop (call-process "bd" nil nil nil "init" "--quiet" "--prefix" "t")))
    (call-process "bd" nil nil nil "create" "--silent" "--title=First" "--priority=1")
    (+test-aue-canvas
      (let ((agent-ui-file-directory root))
        (agent-ui-show '(:id "board" :type "issues"))
        ;; Shown: fetched in the background, then drawn.
        (with-timeout (20 (ert-fail "Not fetched"))
          (while (not (gethash root agent-ui-issues--cache)) (accept-process-output nil 0.05)))
        (with-current-buffer canvas
          (agent-ui--flush)
          (should (string-match-p "Ready (1)" (buffer-string)))
          (should (string-match-p "t-[a-z0-9]+ First" (buffer-string))))))))

;; ====== HEATMAP ======

(defun +test-aue-svg (element width)
  "ELEMENT drawn for the GUI at WIDTH columns (8 px, lines 16 px): its SVG."
  (let ((text (agent-ui-render element (agent-ui-context :width width :graphic t :char-width 8 :line-height 16))))
    (plist-get (cdr (get-text-property (text-property-not-all 0 (length text) 'display nil text) 'display text))
               :data)))

(ert-deftest agent-ui-elements/heatmap-gui-numbers-fit-their-cells ()
  "In the GUI a cell's number is shown only if it fits the cell (\"130.25\"
overlapped the next cell's, \"1234\" spilled out of the last)."
  (let ((svg (+test-aue-svg (list :type "heatmap" :rows '("build" "test")
                                  :columns (mapcar (lambda (i) (format "c%d" i)) (number-sequence 1 12))
                                  :values (list (list 12.5 130.25 14 1 2 3 4 5 6 7 22 1234)
                                                (number-sequence 1 12)))
                            50)))
    ;; Cells of 28 px: two digits fit, five and four don't.
    (should (string-match-p ">12</text>" svg))
    (should-not (string-match-p ">130.25</text>" svg))
    (should-not (string-match-p ">1234</text>" svg))))

(ert-deftest agent-ui-elements/heatmap-legend-whole ()
  "A legend wider than the width: on more lines, each swatch with its word
(\"█\" was left at a line's end, \"skipped\" alone on the next), and all of
its lines in the GUI too (only the last was kept)."
  (let* ((element '(:type "heatmap" :rows ("lexer" "parser" "checker") :columns ("linux" "macos" "windows")
                    :values (("passed" "passed" "passed") ("passed" "flaky" "passed") ("failed" "passed" "skipped"))))
         (text (+test-aue-draw element :width 30))
         (legend (nthcdr 4 (split-string text "\n"))))
    (should (equal legend '("█ passed  █ flaky  █ failed" "█ skipped")))
    (let ((gui (substring-no-properties
                (agent-ui-render element (agent-ui-context :width 30 :graphic t :char-width 8 :line-height 16)))))
      (should (string-match-p "█ passed  █ flaky  █ failed\n█ skipped\\'" gui)))))

(ert-deftest agent-ui-elements/heatmap-latest-columns-that-fit ()
  "More columns than fit (a month of days): the latest that fit, the earlier
ones said left out, text and GUI (it ran 97 columns wide at 60, the SVG 784
px in 480)."
  (let* ((days (mapcar (lambda (i) (format "d%d" i)) (number-sequence 1 30)))
         (element (list :type "heatmap" :rows '("lexer" "parser") :columns days
                        :values (list (make-list 30 "passed") (append (make-list 29 "passed") '("failed")))))
         (text (+test-aue-draw element :width 60)))
    (dolist (line (split-string text "\n"))
      (should (<= (string-width line) 60)))
    (should (string-match-p "… 13 earlier columns left out" text))
    ;; The latest kept: the last day's failure among them (the legend says
    ;; the states shown).
    (should (string-match-p "█ failed" text))
    (let ((svg (+test-aue-svg element 60)))
      (string-match "<svg width=\"\\([0-9]+\\)\"" svg)
      (should (<= (string-to-number (match-string 1 svg)) 480)))
    (should (string-match-p "earlier columns left out\n.*█ failed"
                            (substring-no-properties
                             (agent-ui-render element (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))))
    ;; Few columns: all of them, no note.
    (should-not (string-match-p "left out" (+test-aue-draw '(:type "heatmap" :rows ("a") :columns ("x" "y") :values (("passed" "failed"))))))))

(ert-deftest agent-ui-elements/heatmap-gui-row-labels-cut ()
  "In the GUI a long row label is cut to its column (it ran through the cells)."
  (let ((svg (+test-aue-svg '(:type "heatmap" :rows ("test_parser_handles_unicode_identifiers" "lexer")
                              :columns ("linux" "macos" "windows")
                              :values (("passed" "failed" "passed") ("passed" "passed" "flaky")))
                            40)))
    (should-not (string-match-p "test_parser_handles_unicode_identifiers" svg))
    (should (string-match-p ">test_parser[^<]*&#8230;</text>" svg))))

(ert-deftest agent-ui-elements/heatmap-numbers ()
  (let ((element '(:type "heatmap" :rows ("a" "b") :columns ("mon" "tue") :values ((1 5) (nil 9)))))
    (should (equal (+test-aue-draw element)
                   "   mon tue\na  ███ ███\nb  ··· ███\n1 █████ 9"))
    ;; Coloured on the scale: the lowest faint, the highest strong.
    (let* ((text (agent-ui-render element (agent-ui-context :width 60)))
           (colour (lambda (n) (plist-get (get-text-property (+ (string-search "\na  " text) 4 (* n 4)) 'face text) :foreground))))
      (should (stringp (funcall colour 0)))
      (should-not (equal (funcall colour 0) (funcall colour 1))))
    ;; green-red: low good, high bad.
    (let ((text (agent-ui-render (plist-put (copy-sequence element) :scale "green-red") (agent-ui-context))))
      (should (stringp (plist-get (get-text-property (+ (string-search "\na  " text) 4) 'face text) :foreground))))))

(ert-deftest agent-ui-elements/heatmap-states ()
  (let ((text (+test-aue-draw '(:type "heatmap" :rows ("lexer") :columns ("linux" "macos") :values (("passed" "failed"))))))
    (should (equal text "       linux macos\nlexer  █████ █████\n█ passed  █ failed")))
  ;; In the GUI: SVG cells, a number's value in it; the legend as text.
  (let* ((text (agent-ui-render '(:type "heatmap" :rows ("a") :columns ("x" "y") :values ((3 7)))
                                (agent-ui-context :width 40 :graphic t)))
         (svg (plist-get (cdr (get-text-property 0 'display text)) :data)))
    (should (= 2 (cl-count ?\n (replace-regexp-in-string "<rect" "\n" svg))))
    (should (string-match-p ">7</text>" svg))
    (should (string-suffix-p "3 █████ 7" (substring-no-properties text)))))

(ert-deftest agent-ui-elements/heatmap-wrong ()
  (should (string-match-p "values has 1 rows, for 2" (+test-aue-error '(:type "heatmap" :rows ("a" "b") :columns ("x") :values ((1))))))
  (should (string-match-p "row 1 has 2 cells, for 1" (+test-aue-error '(:type "heatmap" :rows ("a") :columns ("x") :values ((1 2))))))
  (should (string-match-p "a cell is a number, a word or null" (+test-aue-error '(:type "heatmap" :rows ("a") :columns ("x") :values (((1)))))))
  (should (string-match-p "rows must be labels" (+test-aue-error '(:type "heatmap" :rows (1) :columns ("x") :values ((1)))))))

;; ====== PANEL ======

(ert-deftest agent-ui-elements/panel-row-and-column ()
  (let ((row '(:type "panel" :layout "row" :min-width 8
               :children ((:type "text" :title "A" :text "one") (:type "text" :title "B" :text "two\nlines")))))
    (should (equal (+test-aue-draw row :width 30)
                   (concat "╭────────────────────────────╮\n"
                           "│ A           │ B            │\n"
                           "│ one         │ two          │\n"
                           "│             │ lines        │\n"
                           "╰────────────────────────────╯")))
    ;; Weights: shares of the width.
    (should (string-prefix-p "╭────────────────────────────╮\n│ A       │ B"
                             (+test-aue-draw (plist-put (plist-put (copy-sequence row) :weights '(1 2)) :min-width 4) :width 30)))
    ;; Too narrow for its children: stacked.
    (should (equal (+test-aue-draw (plist-put (copy-sequence row) :min-width 20) :width 30)
                   (concat "╭────────────────────────────╮\n"
                           "│ A                          │\n│ one                        │\n"
                           "│                            │\n"
                           "│ B                          │\n│ two                        │\n│ lines                      │\n"
                           "╰────────────────────────────╯"))))
  ;; A column without a border.
  (should (equal (+test-aue-draw '(:type "panel" :border :false
                                   :children ((:type "text" :text "x") (:type "text" :text "y"))))
                 "x\n\ny")))

(ert-deftest agent-ui-elements/panel-nested-and-live ()
  ;; A panel in a panel; an animated child makes it animated.
  (let ((element '(:type "panel" :layout "row"
                   :children ((:type "panel" :border :false :children ((:type "text" :text "in")))
                              (:type "progress" :title "Wait")))))
    (should (string-match-p "│ in +│ Wait" (+test-aue-draw element :width 60)))
    (should (agent-ui-animated-p element)))
  ;; A child's buttons get its id (they change it).
  (let (seen)
    (cl-letf (((symbol-function 'agent-ui-choice--change) (lambda (ctx _patch) (setq seen (plist-get ctx :id)))))
      (let ((text (agent-ui-render '(:type "panel" :children ((:id "q" :type "choice" :question "?" :options ("a"))))
                                   (agent-ui-context :width 40 :id "outer"))))
        (funcall (get-text-property (string-search "( ) a" text) 'agent-ui-action text))
        (should (equal seen "q"))))))

(ert-deftest agent-ui-elements/panel-wrong ()
  (should (string-match-p "child 2 (text): text: text is required"
                          (+test-aue-error '(:type "panel" :children ((:type "text" :text "x") (:type "text"))))))
  (should (string-match-p "child 1 must be an element" (+test-aue-error '(:type "panel" :children ("x")))))
  (should (string-match-p "two children are \"a\""
                          (+test-aue-error '(:type "panel" :children ((:id "a" :type "text" :text "x")
                                                                      (:type "panel" :children ((:id "a" :type "text" :text "y"))))))))
  (should (string-match-p "weights are a positive number for each child"
                          (+test-aue-error '(:type "panel" :weights (1) :children ((:type "text" :text "x") (:type "text" :text "y"))))))
  (should (string-match-p "nest 2 deep at most"
                          (let ((agent-ui-panel-depth 2))
                            (+test-aue-error '(:type "panel" :children ((:type "panel" :children ((:type "panel" :children ()))))))))))

(ert-deftest agent-ui-elements/panel-empty ()
  "No children (shown empty, appended to later): its placeholder, row or
column, bordered or not (it broke working out widths for none)."
  (dolist (element '((:type "panel" :layout "row") (:type "panel" :children ())
                     (:type "panel" :layout "row" :border :false)))
    (let ((text (+test-aue-draw element :width 30)))
      (should-not (string-search "⚠" text))
      (should (string-search "no elements" text)))))

(ert-deftest agent-ui-elements/panel-never-under-a-column ()
  "However narrow: no child laid out at 0 columns or less (they hung, or
broke), the border left out where it can't fit, every line within the width."
  (let ((calls 0)
        (truncate (symbol-function 'truncate-string-to-width))
        (row '(:type "panel" :layout "row" :min-width 0
               :children ((:type "text" :text "Build ok") (:type "text" :text "Tests ok")
                          (:type "text" :text "Lint ok"))))
        (nested '(:type "panel" :children ((:type "panel" :children ((:type "panel" :children ((:type "text" :text "hi")))))))))
    (cl-letf (((symbol-function 'truncate-string-to-width)
               (lambda (&rest args)
                 (when (> (cl-incf calls) 100000) (error "a loop"))
                 (apply truncate args))))
      (dolist (width (number-sequence 1 20))
        (dolist (element (list row nested))
          (let ((text (+test-aue-draw element :width width)))
            (should-not (string-search "⚠" text))
            (dolist (line (split-string text "\n"))
              (should (<= (string-width line) (max width 1))))))))
    ;; Wide enough: its border, as before.
    (should (string-prefix-p "╭" (+test-aue-draw row :width 30)))))

(ert-deftest agent-ui-elements/panel-row-with-a-chart-in-the-gui ()
  (let* ((element '(:type "panel" :layout "row" :min-width 8
                    :children ((:type "chart" :title "p95" :values (1 3 2)) (:type "text" :title "Note" :text "fine"))))
         (gui (agent-ui-render element (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))
         (lines (split-string gui "\n")))
    ;; Its border's top and bottom as text; the row between, one SVG.
    (should (= (length lines) 3))
    (let* ((image (get-text-property 0 'display (nth 1 lines)))
           (svg (plist-get (cdr image) :data)))
      (should (eq (car image) 'image))
      (should (string-match-p "\\`<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"480\"" svg))
      ;; Each child nested: the chart's own SVG (a polyline), the text's.
      (should (string-match-p "<svg x=\"8\" y=\"0\"" svg))
      (should (string-match-p "<polyline" svg))
      (should (string-match-p ">fine</text>" svg))))
  ;; Without an image: text, its children's buttons kept.
  (let ((gui (agent-ui-render '(:type "panel" :layout "row" :min-width 8
                                :children ((:type "text" :text "a") (:type "choice" :question "?" :options ("x"))))
                              (agent-ui-context :width 60 :graphic t))))
    (should-not (text-property-not-all 0 (length gui) 'display nil gui))
    (should (text-property-any 0 (length gui) 'keymap agent-ui-button-map gui)))
  ;; In a terminal: text, as before.
  (should-not (string-match-p "<svg" (+test-aue-draw '(:type "panel" :layout "row" :min-width 8
                                                       :children ((:type "chart" :values (1 2)) (:type "text" :text "x")))))))

(ert-deftest agent-ui-elements/panel-borderless-keeps-its-images ()
  "Without a border, in the GUI: a row drawn as one SVG, and an image line in
a column, kept (trimming the lines' spaces deleted them: an image is a
space showing it); plain lines still trimmed."
  (let* ((ctx (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16))
         (row (agent-ui-render '(:type "panel" :layout "row" :border :false
                                 :children ((:type "chart" :title "Latency" :values (1 3 2 5 4))
                                            (:type "text" :text "hello")))
                               ctx))
         (column (agent-ui-render '(:type "panel" :border :false
                                    :children ((:type "chart" :values (1 3 2)) (:type "text" :text "hi")))
                                  ctx)))
    (should (agent-ui-panel--image-p row))
    (should (agent-ui-panel--image-p column))
    (should (string-match-p "^hi$" (substring-no-properties column))))
  (should (equal (agent-ui-panel--trim-right "ab   ") "ab"))
  (let ((image (concat "x " (propertize " " 'display '(space :width (3))))))
    (should (equal (agent-ui-panel--trim-right image) image))))

(ert-deftest agent-ui-elements/panel-gui-row-children-fit-their-columns ()
  "A GUI row drawn as one SVG: each child's text fitted to its column (a long
title ran across the line between them into the next child)."
  (let* ((text (agent-ui-render '(:type "panel" :layout "row"
                                  :children ((:type "table" :title "Slowest tests in the parser module this week"
                                                    :columns ("Test" "Result") :rows (("lexer" "passed") ("parser" "failed")))
                                             (:type "chart" :title "Latency" :values (1 3 2 5 4))))
                                (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))
         ;; The row's image: under the border's top line.
         (svg (plist-get (cdr (get-text-property (text-property-not-all 0 (length text) 'display nil text)
                                                 'display text))
                         :data))
         (nested (progn (string-match "<svg x=\"[0-9]+\" y=\"0\" [^>]*width=\"\\([0-9]+\\)\"" svg)
                        (string-to-number (match-string 1 svg)))))
    ;; The table's column: 26 of 60 (border and separator out), and the
    ;; snapshot's padding (a column each side).
    (should (<= nested (* 8 (+ 26 2))))
    ;; The title cut (a word a <text>): its end gone.
    (should (string-match-p "…\\|&#8230;" svg))
    (should-not (string-match-p ">week<" svg))))

(ert-deftest agent-ui-elements/panel-an-image-line-in-its-border ()
  ;; An image's line padded to the panel's width: a filler to its last
  ;; column's end, spaces, the border's right side.
  (let* ((image (lambda (w) (propertize "img" 'display (list 'image :type 'svg :scale 1
                                                             :data (format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"16\"/>" w)))))
         (ctx (agent-ui-context :width 20 :graphic t :char-width 8 :line-height 16))
         (lines (agent-ui-panel--lines (concat (funcall image 45) "\nab") 10 ctx))
         (line (car lines)))
    ;; 45 px: 6 columns, 3 px of filler, 4 spaces.
    (should (equal (substring-no-properties line) "img     "))
    (should (equal (get-text-property 3 'display line) '(space :width (3))))
    (should (= (agent-ui-panel--pixels line 8) 80))
    (should (equal (cadr lines) "ab        "))
    ;; Wider than its room: as it is.
    (should (equal (substring-no-properties (car (agent-ui-panel--lines (funcall image 200) 10 ctx))) "img")))
  ;; A chart in a column panel, in the GUI: both sides of the border.
  (let* ((gui (agent-ui-render '(:type "panel" :children ((:type "chart" :values (1 3 2))))
                               (agent-ui-context :width 30 :graphic t :char-width 8 :line-height 16)))
         (chart-line (seq-find #'agent-ui-panel--image-p (split-string gui "\n"))))
    (should (string-prefix-p "│ " (substring-no-properties chart-line)))
    (should (string-suffix-p " │" (substring-no-properties chart-line)))
    (should (= (agent-ui-panel--pixels chart-line 8) (* 30 8)))))

(ert-deftest agent-ui-elements/table-without-column-names ()
  ;; No column named: no header nor rule, the rows alone.
  (should (equal (+test-aue-draw '(:type "table" :columns ("" "") :rows (("build" "29s") ("tests" "1.4s"))))
                 " build │ 29s\n tests │ 1.4s"))
  (should (equal (+test-aue-draw '(:type "table" :columns ("") :rows ()))
                 " no rows yet"))
  ;; One named: the header, as before.
  (should (string-match-p "\\` +│ Time\n─+┼─+\n" (+test-aue-draw '(:type "table" :columns ("" "Time") :rows (("a" "1")))))))

(ert-deftest agent-ui-elements/progress-its-rate-and-time-left ()
  (let* ((now 100.0)
         (agent-ui-clock (lambda () now)))
    (with-temp-buffer
      (agent-ui-canvas-mode)
      (cl-flet ((at (time value &optional props)
                  (setq now time)
                  (substring-no-properties
                   (agent-ui-render (append (list :type "progress" :value value :max 100 :unit "MB") props)
                                    (agent-ui-context :width 100 :id "dl")))))
        ;; Not steady yet: two values, then three over under 2 seconds.
        (should-not (string-match-p "/s" (at 100.0 10)))
        (should-not (string-match-p "/s" (at 101.0 14)))
        ;; Steady: 3 values over 2 seconds, 4 MB a second; 82 MB left: 20s.
        (should (string-match-p "18/100 MB  18%  4 MB/s  20s left" (at 102.0 18)))
        ;; Drawn again, nothing new: the time left counts down.
        (should (string-match-p "4 MB/s  18s left" (at 104.5 18)))
        ;; Slower: 13 MB over 5 seconds, under 10 to a decimal.
        (should (string-match-p "2.6 MB/s" (at 105.0 23)))
        ;; Done, or failed: neither.
        (should-not (string-match-p "/s" (at 106.0 30 '(:status "done"))))
        ;; A lower value: starts again.
        (should-not (string-match-p "/s" (at 107.0 1)))
        ;; Without a max: the rate, no time left; slow ones a minute.
        (setq now 200.0)
        (cl-flet ((open (time value)
                    (setq now time)
                    (substring-no-properties
                     (agent-ui-render (list :type "progress" :value value) (agent-ui-context :width 80 :id "n")))))
          ;; 2 more in 30 seconds (the window's): 4 a minute.
          (open 200.0 1) (open 215.0 2)
          (let ((text (open 230.0 3)))
            (should (string-match-p "  3  4/min" text))
            (should-not (string-match-p "left" text)))))))
  ;; Not on a canvas (render, a snapshot): neither.
  (should-not (string-match-p "/s" (+test-aue-draw '(:type "progress" :value 5 :max 10)))))

(ert-deftest agent-ui-elements/table-sorted ()
  (let ((element '(:type "table" :columns ("Test" "Time")
                   :rows (("parser" "1.1s") ("lexer" "10.2s") ("codegen" nil) ("Checker" "0.7s")))))
    ;; By a column's name: as numbers where they're numbers, empty last; the
    ;; column marked.
    (should (equal (+test-aue-draw (append element '(:sort "Time")))
                   (concat " Test    │ Time ↑\n"
                           "─────────┼───────\n"
                           " Checker │ 0.7s\n"
                           " parser  │ 1.1s\n"
                           " lexer   │ 10.2s\n"
                           " codegen │")))
    ;; By index, the other way; text without case.
    (should (string-match-p "\\` Test ↓ +│ Time\n.*\n parser .*\n lexer .*\n codegen .*\n Checker "
                            (+test-aue-draw (append element '(:sort 0 :descending t)))))
    ;; Not a column: said so.
    (should (string-match-p "table: sort must be a column" (+test-aue-error (append element '(:sort "Size")))))))

(ert-deftest agent-ui-elements/table-sorted-in-the-canvas ()
  (let* ((agent-ui-default-canvas (make-temp-name "table-"))
         (agent-ui-display-function #'ignore)
         (canvas (agent-ui-canvas)))
    (unwind-protect
        (with-current-buffer canvas
          (agent-ui-show '(:id "t" :type "table" :columns ("Name" "Size") :rows (("b" 2) ("a" 10) ("c" 1))))
          (agent-ui--flush)
          (cl-flet ((rows () (agent-ui--flush)
                      (mapcar (lambda (l) (car (split-string l)))
                              (cddr (split-string (string-trim (buffer-string)) "\n")))))
            ;; s on the Size column: by it; again: the other way.
            (goto-char (point-min))
            (search-forward "10")
            (backward-char)
            (agent-ui-table-sort)
            (should (equal (plist-get (agent-ui-get "t") :sort) "Size"))
            (should (equal (rows) '("c" "b" "a")))
            (search-forward "Size")
            (agent-ui-table-sort)
            (should (eq (plist-get (agent-ui-get "t") :descending) t))
            (should (equal (rows) '("a" "b" "c")))
            ;; Another column: ascending again.
            (goto-char (point-min))
            (search-forward "Name")
            (agent-ui-table-sort)
            (should (equal (rows) '("a" "b" "c")))
            (should-not (plist-get (agent-ui-get "t") :descending))
            ;; Elsewhere: nothing to sort.
            (goto-char (point-max))
            (should-error (agent-ui-table-sort) :type 'user-error)))
      (kill-buffer canvas))))

(ert-deftest agent-ui-elements/table-row-actions ()
  (let* ((element '(:type "table" :columns ("Test" "Result")
                    :rows (("lexer" "passed") ("checker" "failed"))
                    :row-actions ((:label "Fix" :prompt "Fix {Test}: it {Result}. ({row}, {Other})")
                                  (:label "Run" :prompt "Run {Test}" :submit t))))
         (text (agent-ui-render element (agent-ui-context :width 60)))
         (sent nil)
         (agent-ui-action-function (lambda (prompt submit) (push (list prompt submit) sent))))
    ;; Buttons at each row's end.
    (should (string-match-p "^ checker │ failed  ⏵ Fix  ⏵ Run$" (substring-no-properties text)))
    ;; Pressed: their prompts with the row's cells.
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (search-forward "checker")
      (search-forward "⏵ Fix")
      (backward-char)
      (agent-ui-button-press)
      (search-forward "⏵ Run")
      (backward-char)
      (agent-ui-button-press))
    (should (equal (reverse sent)
                   '(("Fix checker: it failed. (Test: checker, Result: failed, {Other})" nil)
                     ("Run checker" t))))
    ;; Wrong ones: said so.
    (should (string-match-p "table: row-actions: action 1 must be"
                            (+test-aue-error '(:type "table" :columns ("A") :row-actions ("x")))))))

(ert-deftest agent-ui-elements/chart-bars-grouped-and-stacked ()
  (let ((grouped '(:type "chart" :kind "bar" :labels ("a" "b")
                   :series ((:name "x" :values (2 4)) (:name "y" :values (1 3))))))
    ;; Grouped: a bar per series under each label, each its colour; a legend.
    (should (equal (+test-aue-draw grouped :width 20)
                   (concat "a  ███████         2\n"
                           "   ███▌            1\n"
                           "b  ██████████████  4\n"
                           "   ██████████▌     3\n"
                           "   ● x  ● y")))
    (should (eq (+test-aue-face-at grouped "███▌" :width 20) (agent-ui-chart--face 1)))
    ;; Stacked: a bar per label, its series end to end, their total.
    (let ((text (agent-ui-render (append '(:stacked t) grouped) (agent-ui-context :width 20))))
      (should (equal (substring-no-properties text)
                     "a  ██████          3\nb  ██████████████  7\n   ● x  ● y"))
      ;; b: 4 of 7 in x's colour (8 cells), 3 in y's (6).
      (let ((b (cadr (split-string text "\n"))))
        (should (eq (get-text-property 10 'face b) (agent-ui-chart--face 0)))
        (should (eq (get-text-property 11 'face b) (agent-ui-chart--face 1)))
        (should (eq (get-text-property 3 'face b) (agent-ui-chart--face 0)))))
    ;; As SVG: a rectangle per segment, a legend.
    (let ((svg (plist-get (cdr (get-text-property 0 'display (agent-ui-render (append '(:stacked t) grouped)
                                                                              (agent-ui-context :width 40 :graphic t :char-width 8 :line-height 16))))
                          :data)))
      (with-temp-buffer
        (insert svg)
        (should (= (count-matches "<rect" (point-min) (point-max)) 4))
        (should (= (count-matches "<circle" (point-min) (point-max)) 2))))))

(ert-deftest agent-ui-elements/chart-histogram ()
  (let ((element '(:type "chart" :kind "histogram" :unit "ms" :bins 4 :values (0 1 2 3 4 5 6 7 8 9 10 40))))
    ;; Counted in 4 bins of 10, 0 to 40, each its range.
    (should (equal (plist-get (car (plist-get (agent-ui-chart--histogram (agent-ui-check "chart" element)) :series))
                              :values)
                   '(10 1 0 1)))
    (should (string-match-p "\\`0–10 ms  +█+ +10\n10–20 ms  .* 1\n20–30 ms  +0\n30–40 ms  .* 1\\'"
                            (+test-aue-draw element)))
    ;; Its min and max: its bins' span (the counts' axis from 0).
    (should (string-match-p "\\`0–25 ms .*\n25–50 ms "
                            (+test-aue-draw '(:type "chart" :kind "histogram" :unit "ms" :bins 2 :min 0 :max 50
                                              :values (5 30)))))
    (should (string-match-p "bins must be from 1 to 50"
                            (+test-aue-error '(:type "chart" :kind "histogram" :bins 0 :values (1)))))))

(ert-deftest agent-ui-elements/chart-a-time-axis ()
  (let ((zone (getenv "TZ")))
    (unwind-protect
        (progn
          (set-time-zone-rule "UTC")
          ;; Times as dates and times, or seconds; wrong ones said so.
          (should (= (agent-ui-chart--time "1970-01-02") 86400.0))
          (should (= (agent-ui-chart--time "1970-01-01T00:01:00Z") 60.0))
          (should (= (agent-ui-chart--time 5) 5.0))
          (should (string-match-p "time 2 is \"soon\""
                                  (+test-aue-error '(:type "chart" :values (1 2) :times (0 "soon")))))
          ;; Ticks at round times: hours over a day's hours, midnights over days.
          (should (equal (mapcar #'cdr (agent-ui-chart--ticks (* 9.5 3600) (* 17 3600) 5))
                         '("10:00" "12:00" "14:00" "16:00")))
          (should (equal (car (agent-ui-chart--ticks 0 (* 6 86400) 7)) '(0.0 . "Jan 01")))
          ;; Drawn: the values placed by their times; the axis, ┬ at each tick.
          (let* ((element '(:type "chart" :height 2 :values (1 2 3) :times (0 600 3600)))
                 (lines (split-string (+test-aue-draw element :width 30) "\n")))
            (should (string-match-p "\\` +└┬─+┬─+┬─*\\'" (nth 2 lines)))
            (should (string-match-p "00:00 +00:30 +01:00" (nth 3 lines))))
          ;; As SVG: the axis's ticks, labelled.
          (let ((svg (plist-get (cdr (get-text-property 0 'display (agent-ui-render '(:type "chart" :values (1 2 3) :times (0 600 3600))
                                                                                    (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16))))
                                :data)))
            (should (string-match-p ">00:20</text>" svg)))
          ;; Appended, with values: kept as many as they are.
          (should (equal (plist-get (agent-ui-append-to '(:type "chart" :values (1) :times (0)) '(:values (2) :times (60))) :times)
                         '(0 60))))
      (set-time-zone-rule zone))))

(ert-deftest agent-ui-elements/image-from-a-url ()
  (let* ((agent-ui-image-cache-directory (file-name-as-directory (make-temp-file (+test-tmp-file "images-") t)))
         (agent-ui-image--fetches (make-hash-table :test #'equal))
         (fetches nil) (done nil)
         (agent-ui-image-fetch-function (lambda (url file callback) (push url fetches) (setq done (list file callback))))
         (element '(:type "image" :url "https://example.com/chart?x=1" :alt "Sales")))
    (unwind-protect
        (progn
          ;; Not there yet: downloading, said; started once.
          (should (string-match-p "▣ https://example.com/chart\\?x=1  Sales  (downloading…)" (+test-aue-draw element)))
          (+test-aue-draw element)
          (should (equal fetches '("https://example.com/chart?x=1")))
          ;; Done: kept by its hash, its extension its type's; shown as a file.
          ;; (A PNG's signature: its type known by it.)
          (with-temp-file (car done) (set-buffer-multibyte nil) (insert "\211PNG\r\n\032\n"))
          (funcall (cadr done) nil)
          (should (equal (agent-ui-image--cached "https://example.com/chart?x=1")
                         (concat agent-ui-image-cache-directory (sha1 "https://example.com/chart?x=1") ".png")))
          (should (equal (+test-aue-draw element) "▣ https://example.com/chart?x=1  Sales"))
          ;; Not downloaded again.
          (+test-aue-draw element)
          (should (= (length fetches) 1))
          ;; Failed: said in its place; not an image, too.
          (let ((bad '(:type "image" :url "https://example.com/404.png")))
            (+test-aue-draw bad)
            (funcall (cadr done) "The requested URL returned error: 404")
            (should (string-match-p "(couldn't download it: The requested URL returned error: 404)" (+test-aue-draw bad :width 120)))
            (should (eq (+test-aue-face-at bad "(couldn't") 'agent-ui-error))
            ;; Shown again, within 30 seconds: not tried again; later: tried.
            (agent-ui--prepared bad)
            (+test-aue-draw bad)
            (should (= (length fetches) 2))
            (puthash "https://example.com/404.png" (list :error "x" :time 0) agent-ui-image--fetches)
            (agent-ui--prepared bad)
            (+test-aue-draw bad)
            (should (= (length fetches) 3)))
          (let ((page '(:type "image" :url "https://example.com/page")))
            (+test-aue-draw page)
            (with-temp-file (car done) (insert "<html>nope</html>"))
            (funcall (cadr done) nil)
            (should (string-match-p "(couldn't download it: not an image)" (+test-aue-draw page :width 120)))
            (should-not (file-exists-p (car done)))))
      (delete-directory agent-ui-image-cache-directory t)))
  ;; File or url, one; an http(s) url.
  (should (string-match-p "give file or url, one of them" (+test-aue-error '(:type "image"))))
  (should (string-match-p "give file or url" (+test-aue-error '(:type "image" :file "a.png" :url "https://x/a.png"))))
  (should (string-match-p "url is an http(s) address, not \"file:///a.png\""
                          (+test-aue-error '(:type "image" :url "file:///a.png")))))

