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
  (should (equal (agent-ui-types) '(chart choice diff files html image markdown progress steps table text)))
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

;; ====== CHART ======

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
  (should (string-match-p "only values, series and labels"
                          (agent-ui-error-message
                           (should-error (agent-ui-append-to '(:type "chart") '(:unit "x"))
                                         :type 'agent-ui-error)))))

(ert-deftest agent-ui-elements/chart-wrong ()
  (should (equal (+test-aue-error '(:type "chart" :values (1 "x")))
                 "chart: values must be numbers; value 2 is \"x\""))
  (should (string-match-p "values (one series) or series, not both"
                          (+test-aue-error '(:type "chart" :values (1) :series ((:values (1)))))))
  (should (string-match-p "a bar chart has one series"
                          (+test-aue-error '(:type "chart" :kind "bar" :series ((:values (1)) (:values (2)))))))
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

