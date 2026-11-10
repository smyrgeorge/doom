;;; tests/unit/test-agent-ui-core.el -*- lexical-binding: t; -*-
;; config/agent-ui/core.el: Agent UI's element types. Defining one, checking
;; an element against it, updating and appending, drawing it (in a terminal and
;; in the GUI) with its errors contained, JSON both ways, the catalog. Types of
;; the tests' own, forgotten after each test.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-aui (&rest body)
  "BODY with only the types it defines (the registry put back after)."
  (declare (indent 0))
  `(let ((agent-ui--types (make-hash-table :test #'eq)))
     ,@body))

(defun +test-aui--meter ()
  "A type for the tests: meter, VALUE of MAX, as text and for the GUI."
  (agent-ui-define meter
    "A meter: VALUE of MAX."
    :props ((value number "Done so far" :default 0)
            (max number "The total" :required t)
            (label string "What's being done")
            (status (choice running done failed) "Its state" :default running)
            (marks list "Notes, added as they come")
            (loud boolean "Shouted" :default t))
    :example (:value 3 :max 12)
    :animated (lambda (props) (eq (plist-get props :status) 'running))
    :text (lambda (props _ctx)
            (format "%s/%s %s%s" (plist-get props :value) (plist-get props :max)
                    (plist-get props :status)
                    (if (plist-get props :loud) "!" "")))
    :gui (lambda (props _ctx) (format "GUI %s" (plist-get props :value)))))

(defun +test-aui--message (fn &rest args)
  "The message of the `agent-ui-error' FN signals called with ARGS."
  (let ((err (should-error (apply fn args) :type 'agent-ui-error)))
    (agent-ui-error-message err)))

;; ====== DEFINING ======

(ert-deftest agent-ui-core/loaded ()
  (should (fboundp 'agent-ui-define))
  (should (featurep 'cl-lib))
  (should (natnump agent-ui-max-chars))
  (should (natnump agent-ui-max-rows)))

(ert-deftest agent-ui-core/a-type-defined ()
  (+test-aui
    (should (eq (+test-aui--meter) 'meter))
    (should (equal (agent-ui-types) '(meter)))
    (let ((type (agent-ui-type 'meter)))
      (should (equal (agent-ui-type-doc type) "A meter: VALUE of MAX."))
      (should (equal (mapcar #'agent-ui-prop-key (agent-ui-type-props type))
                     '(:value :max :label :status :marks :loud)))
      ;; Its file, for a type the agent made and the user keeps.
      (should (equal (agent-ui-type-file type) (or load-file-name buffer-file-name)))
      ;; By name as a string too (JSON's).
      (should (eq (agent-ui-type "meter") type)))
    ;; Again: replaced, not added.
    (agent-ui-define meter "Another." :text (lambda (_p _c) ""))
    (should (equal (agent-ui-types) '(meter)))
    (should (equal (agent-ui-type-doc (agent-ui-type 'meter)) "Another."))
    (agent-ui-undefine 'meter)
    (should-not (agent-ui-types))))

(ert-deftest agent-ui-core/a-bad-type-refused ()
  (+test-aui
    ;; Each says what's wrong; none is registered.
    (should (string-match-p "no :text"
                            (+test-aui--message #'agent-ui--register 'x "Doc.")))
    (should (string-match-p "a-z"
                            (+test-aui--message #'agent-ui--register 'Bad_Name "Doc." :text #'ignore)))
    (should (string-match-p "no documentation"
                            (+test-aui--message #'agent-ui--register 'x nil :text #'ignore)))
    (should (string-match-p "no property may be named title"
                            (+test-aui--message #'agent-ui--register 'x "Doc." :text #'ignore
                                                :props '((title string "Clashes")))))
    (should (string-match-p "kind colour"
                            (+test-aui--message #'agent-ui--register 'x "Doc." :text #'ignore
                                                :props '((c colour "Bad kind")))))
    (should (string-match-p "only :default and :required"
                            (+test-aui--message #'agent-ui--register 'x "Doc." :text #'ignore
                                                :props '((v number "V" :min 0)))))
    (should (string-match-p "named twice"
                            (+test-aui--message #'agent-ui--register 'x "Doc." :text #'ignore
                                                :props '((v number "V") (v string "W")))))
    ;; A default of the wrong kind; an example that doesn't check.
    (should (string-match-p "v must be a number"
                            (+test-aui--message #'agent-ui--register 'x "Doc." :text #'ignore
                                                :props '((v number "V" :default "no")))))
    (should (string-match-p "unknown property \"w\""
                            (+test-aui--message #'agent-ui--register 'x "Doc." :text #'ignore
                                                :props '((v number "V")) :example '(:w 1))))
    (should-not (agent-ui-types))
    ;; The macro: an unknown key, when it's expanded.
    (should-error (macroexpand '(agent-ui-define x "Doc." :txt ignore)))))

(ert-deftest agent-ui-core/an-unknown-type ()
  (+test-aui
    (+test-aui--meter)
    (should (equal (+test-aui--message #'agent-ui-type "metre")
                   "unknown type \"metre\"; types: meter"))
    (should (equal (+test-aui--message #'agent-ui-type nil)
                   "no type given; types: meter"))))

;; ====== CHECKING ======

(ert-deftest agent-ui-core/an-element-checked ()
  (+test-aui
    (+test-aui--meter)
    ;; Defaults filled; :id, :type, :title left out; a choice's string a symbol.
    (should (equal (agent-ui-check 'meter '(:id "m" :type "meter" :title "T" :max 12 :status "done"))
                   '(:value 0 :max 12 :label nil :status done :marks nil :loud t)))
    ;; JSON's false: a boolean's nil, not its default.
    (should (null (plist-get (agent-ui-check 'meter '(:max 1 :loud :false)) :loud)))
    ;; false in a list: kept, for the type to show.
    (should (equal (plist-get (agent-ui-check 'meter '(:max 1 :marks ("a" :false))) :marks)
                   '("a" :false)))))

(ert-deftest agent-ui-core/a-wrong-element-explained ()
  (+test-aui
    (+test-aui--meter)
    (should (equal (+test-aui--message #'agent-ui-check 'meter '(:max 12 :total 3))
                   "meter: unknown property \"total\"; its properties: value, max, label, status, marks, loud"))
    (should (equal (+test-aui--message #'agent-ui-check 'meter '(:max "twelve"))
                   "meter: max must be a number, not \"twelve\""))
    (should (equal (+test-aui--message #'agent-ui-check 'meter '(:max 1 :status "paused"))
                   "meter: status must be one of: running, done, failed, not \"paused\""))
    (should (equal (+test-aui--message #'agent-ui-check 'meter '(:max 1 :loud "yes"))
                   "meter: loud must be a boolean, not \"yes\""))
    (should (equal (+test-aui--message #'agent-ui-check 'meter '(:max 1 :marks 3))
                   "meter: marks must be a list, not 3"))
    (should (equal (+test-aui--message #'agent-ui-check 'meter '(:value 1))
                   "meter: max is required"))
    (should (string-match-p "an object of properties"
                            (+test-aui--message #'agent-ui-check 'meter '(1 2 3))))))

;; A type's own check: after each property's.
(ert-deftest agent-ui-core/a-types-own-check ()
  (+test-aui
    (agent-ui-define pair "Two numbers, A below B."
      :props ((a number "A" :default 0) (b number "B" :default 1))
      :check (lambda (props)
               (unless (< (plist-get props :a) (plist-get props :b))
                 (agent-ui--fail "pair: a must be below b"))
               (plist-put props :sum (+ (plist-get props :a) (plist-get props :b))))
      :text (lambda (props _c) (format "%s" (plist-get props :sum))))
    (should (equal (agent-ui-check 'pair '(:a 2 :b 5)) '(:a 2 :b 5 :sum 7)))
    (should (equal (+test-aui--message #'agent-ui-check 'pair '(:a 5 :b 2))
                   "pair: a must be below b"))
    ;; What it returns is what's drawn.
    (should (equal (agent-ui-render '(:type "pair" :a 1 :b 2) (agent-ui-context)) "3"))))

;; ====== CHANGING ======

(ert-deftest agent-ui-core/an-element-updated ()
  (+test-aui
    (+test-aui--meter)
    (let ((element '(:id "m" :type "meter" :max 12 :value 3 :label "a")))
      ;; Replaced, added; nil (JSON's null) back to its default; :id kept.
      (should (equal (agent-ui-merge element '(:id "m" :value 7 :status "done" :label nil))
                     '(:id "m" :type "meter" :max 12 :value 7 :status "done")))
      ;; The element given isn't changed.
      (should (equal element '(:id "m" :type "meter" :max 12 :value 3 :label "a")))
      ;; Its type, as a string or a symbol: the same, so allowed; another, not.
      (should (agent-ui-merge element '(:type meter)))
      (should (string-match-p "can't change the type"
                              (+test-aui--message #'agent-ui-merge element '(:type "table")))))))

(ert-deftest agent-ui-core/lists-appended-to ()
  (+test-aui
    (+test-aui--meter)
    (let ((element '(:type "meter" :max 1 :marks ("a"))))
      (should (equal (plist-get (agent-ui-append-to element '(:id "m" :marks ("b" "c"))) :marks)
                     '("a" "b" "c")))
      ;; None yet: after its default (none).
      (should (equal (plist-get (agent-ui-append-to '(:type "meter" :max 1) '(:marks ("b"))) :marks)
                     '("b")))
      (should (equal (+test-aui--message #'agent-ui-append-to element '(:value 3))
                     "meter: only lists can be appended to (marks)")))
    ;; A type's own way of appending.
    (agent-ui-define keyed "Rows by key."
      :props ((rows list "Rows"))
      :append (lambda (element patch)
                (plist-put (copy-sequence element) :rows (list (plist-get patch :rows))))
      :text (lambda (_p _c) ""))
    (should (equal (agent-ui-append-to '(:type "keyed" :rows (1)) '(:rows (2)))
                   '(:type "keyed" :rows ((2)))))))

;; ====== DRAWING ======

(ert-deftest agent-ui-core/an-element-drawn ()
  (+test-aui
    (+test-aui--meter)
    (let ((element '(:id "m" :type "meter" :title "Build" :value 3 :max 12)))
      ;; In a terminal: its text, under its title in the title's face.
      (let ((text (agent-ui-render element (agent-ui-context))))
        (should (equal (substring-no-properties text) "Build\n3/12 running!"))
        (should (eq (get-text-property 0 'face text) 'agent-ui-title)))
      ;; In the GUI: its :gui.
      (should (equal (substring-no-properties
                      (agent-ui-render element (agent-ui-context :graphic t)))
                     "Build\nGUI 3"))
      ;; No title: no line for it.
      (should (equal (substring-no-properties
                      (agent-ui-render '(:type "meter" :max 1 :loud :false) (agent-ui-context)))
                     "0/1 running")))
    ;; A type without :gui draws its text in the GUI.
    (agent-ui-define plain "Text." :text (lambda (_p _c) "plain\n\n"))
    (should (equal (agent-ui-render '(:type "plain") (agent-ui-context :graphic t))
                   "plain"))))

;; doom-nwj.105
(ert-deftest agent-ui-core/a-title-fits ()
  "An element's title is one line, cut to the width (never cut: 56 columns
at 20), for every type."
  (+test-aui
    (agent-ui-define plain "Text." :text (lambda (_p _c) "body"))
    (let ((title "A rather long title for what this element is all about"))
      (dolist (width '(10 20 40))
        (let ((first (car (split-string (substring-no-properties
                                         (agent-ui-render (list :type "plain" :title title) (agent-ui-context :width width)))
                                        "\n"))))
          (should (<= (string-width first) width))
          (should (string-suffix-p "…" first))))
      (should (equal (substring-no-properties (agent-ui-render (list :type "plain" :title title) (agent-ui-context :width 20)))
                     "A rather long title…\nbody"))
      ;; Its face kept; room for it: whole.
      (let ((text (agent-ui-render (list :type "plain" :title title) (agent-ui-context :width 80))))
        (should (equal (substring-no-properties text) (concat title "\nbody")))
        (should (eq (get-text-property 0 'face text) 'agent-ui-title)))
      ;; Its newlines: spaces (it was two lines).
      (should (equal (substring-no-properties (agent-ui-render '(:type "plain" :title "Two\nlines") (agent-ui-context :width 40)))
                     "Two lines\nbody")))))

(ert-deftest agent-ui-core/the-context-given ()
  (+test-aui
    (let (seen)
      (agent-ui-define spy "Spy." :text (lambda (_p ctx) (setq seen ctx) ""))
      (agent-ui-render '(:type "spy") (agent-ui-context :width 42 :tick 7))
      (should (equal seen '(:width 42 :graphic nil :tick 7 :char-width 8 :line-height 16))))))

(ert-deftest agent-ui-core/errors-drawn-in-place ()
  (+test-aui
    (+test-aui--meter)
    (agent-ui-define broken "Fails." :text (lambda (_p _c) (error "Boom")))
    (agent-ui-define wrong "Not text." :text (lambda (_p _c) 42))
    (cl-flet ((draw (element)
                (let ((text (agent-ui-render element (agent-ui-context))))
                  (should (eq (get-text-property (1- (length text)) 'face text) 'agent-ui-error))
                  (substring-no-properties text))))
      ;; Nothing signals: each error is the element's drawing.
      (should (equal (draw '(:type "nope")) "⚠ unknown type \"nope\"; types: broken, meter, wrong"))
      (should (equal (draw '(:type "meter" :max "x"))
                     "⚠ meter: max must be a number, not \"x\""))
      (should (equal (draw '(:type "broken" :title "B")) "B\n⚠ Boom"))
      (should (equal (draw '(:type "wrong")) "⚠ wrong: its drawing returned 42, not text")))))

(ert-deftest agent-ui-core/a-long-drawing-cut ()
  (+test-aui
    (agent-ui-define long "Long." :text (lambda (_p _c) (make-string 50 ?x)))
    (let* ((agent-ui-max-chars 10)
           (text (agent-ui-render '(:type "long") (agent-ui-context))))
      (should (equal (substring-no-properties text) "xxxxxxxxxx\n… 40 characters more"))
      (should (eq (get-text-property (1- (length text)) 'face text) 'agent-ui-muted)))))

(ert-deftest agent-ui-core/animated ()
  (+test-aui
    (+test-aui--meter)
    (agent-ui-define always "Spins." :animated t :text (lambda (_p _c) ""))
    (should (agent-ui-animated-p '(:type "meter" :max 1)))
    (should-not (agent-ui-animated-p '(:type "meter" :max 1 :status "done")))
    (should (agent-ui-animated-p '(:type "always")))
    ;; Unknown or wrong: not animated (it's drawn as an error).
    (should-not (agent-ui-animated-p '(:type "nope")))
    (should-not (agent-ui-animated-p '(:type "meter")))))

;; ====== HELPERS FOR TYPES ======

(ert-deftest agent-ui-core/helpers ()
  (should (equal (agent-ui-wrap "aaa bbb ccc" 7) "aaa bbb\nccc"))
  (should (equal (agent-ui-wrap "short\nlines kept" 20) "short\nlines kept"))
  ;; A word too long: within it.
  (should (equal (agent-ui-wrap "abcdefghij" 4) "abcd\nefgh\nij"))
  ;; Wide characters: by their width.
  (should (equal (agent-ui-wrap "日本語 日本語" 6) "日本語\n日本語"))
  (should (equal (get-text-property 0 'face (agent-ui-wrap (propertize "aa bb" 'face 'bold) 2)) 'bold))
  ;; Narrower than a character, or no width: a character a line, never stuck
  ;; (it looped forever; a loop now fails instead of hanging the tests).
  (let ((calls 0)
        (truncate (symbol-function 'truncate-string-to-width)))
    (cl-letf (((symbol-function 'truncate-string-to-width)
               (lambda (&rest args)
                 (when (> (cl-incf calls) 1000) (error "agent-ui-wrap loops"))
                 (apply truncate args))))
      (should (equal (agent-ui-wrap "中文" 1) "中\n文"))
      (should (equal (agent-ui-wrap "ab" 0) "a\nb"))
      (should (equal (agent-ui-wrap "a 😀b" -3) "a\n😀\nb"))
      (should (equal (agent-ui-wrap "中 x" 1) "中\nx"))))
  (should (equal (agent-ui-pad "ab" 4) "ab  "))
  (should (equal (agent-ui-pad "ab" 4 'right) "  ab"))
  (should (equal (agent-ui-pad "ab" 5 'center) " ab  "))
  (should (equal (agent-ui-pad "abcdef" 4) "abc…"))
  (should (equal (agent-ui-format-number 3.0) "3"))
  (should (equal (agent-ui-format-number 2.5) "2.5"))
  ;; Under 1: 3 significant digits (2 decimals read 0.004 as 0).
  (should (equal (agent-ui-format-number 0.004) "0.004"))
  (should (equal (agent-ui-format-number 0.0112) "0.0112"))
  (should (equal (agent-ui-format-number 0.00005) "0.00005"))
  (should (equal (agent-ui-format-number -0.0123) "-0.0123"))
  (should (equal (agent-ui-format-number 0.5) "0.5"))
  (should (equal (agent-ui-format-number 1234.5678) "1234.57"))
  (should (equal (agent-ui-format-number 12) "12"))
  (should (equal (mapcar #'agent-ui-cell '(nil t :false 1.5 "x")) '("" "true" "false" "1.5" "x")))
  ;; The spinner: a gap going round a square, its frames block elements (a
  ;; coding font's, not braille from a fallback font); another set, chosen.
  (should (equal (mapcar (lambda (tick) (agent-ui-spinner (agent-ui-context :tick tick))) '(0 1 2 3 4 11))
                 '("▟" "▙" "▛" "▜" "▟" "▜")))
  (should (equal (agent-ui-spinner (agent-ui-context)) "▟"))
  (let ((agent-ui-spinner-frames '("◌" "○" "◎")))
    (should (equal (agent-ui-spinner (agent-ui-context :tick 5)) "◎"))))

;; ====== JSON ======

(ert-deftest agent-ui-core/json-read ()
  (should (equal (agent-ui-parse-json
                  "{\"id\":\"t\",\"rows\":[[\"a\",1],[]],\"ok\":true,\"no\":false,\"reset\":null,\"o\":{\"k\":2}}")
                 '(:id "t" :rows (("a" 1) nil) :ok t :no :false :reset nil :o (:k 2))))
  ;; A null is there, as nil: an update's way of resetting.
  (should (plist-member (agent-ui-parse-json "{\"label\":null}") :label))
  (should (string-match-p "\\`bad JSON"
                          (+test-aui--message #'agent-ui-parse-json "{\"id\":"))))

(ert-deftest agent-ui-core/json-written ()
  (should (equal (json-serialize
                  (agent-ui-to-json '(:id "t" :status done :rows (("a" 1) ("b" 2)) :none nil
                                      :yes t :no :false :o (:k :v))))
                 "{\"id\":\"t\",\"status\":\"done\",\"rows\":[[\"a\",1],[\"b\",2]],\"none\":null,\"yes\":true,\"no\":false,\"o\":{\"k\":\"v\"}}"))
  ;; Both ways: the same.
  (let ((element '(:type "table" :rows (("a" 1)) :title "T")))
    (should (equal (agent-ui-parse-json (json-serialize (agent-ui-to-json element)))
                   element))))

;; ====== THE CATALOG ======

(ert-deftest agent-ui-core/the-catalog ()
  (+test-aui
    (+test-aui--meter)
    (agent-ui-define plain "Text." :text (lambda (_p _c) ""))
    (let ((catalog (agent-ui-catalog)))
      (should (equal (mapcar (lambda (e) (plist-get e :name)) catalog) '("meter" "plain")))
      (let ((meter (car catalog)))
        (should (equal (plist-get meter :doc) "A meter: VALUE of MAX."))
        (should (equal (aref (plist-get meter :props) 0)
                       '(:name "value" :kind "number" :doc "Done so far" :default 0)))
        (should (equal (aref (plist-get meter :props) 1)
                       '(:name "max" :kind "number" :doc "The total" :required t)))
        (should (equal (plist-get (aref (plist-get meter :props) 3) :kind)
                       "one of: running, done, failed"))
        (should (equal (plist-get meter :example) '(:type "meter" :value 3 :max 12))))
      ;; Without an example: none.
      (should-not (plist-member (cadr catalog) :example))
      ;; As JSON, for `agent-ui types'.
      (should (string-prefix-p "[{\"name\":\"meter\""
                               (json-serialize (vconcat catalog)))))))

;; ====== ACTIONS ======

(ert-deftest agent-ui-core/actions-drawn-as-buttons ()
  (+test-aui
    (agent-ui-define plain "Text." :text (lambda (_p _c) "body"))
    (let* ((pressed nil)
           (agent-ui-action-function (lambda (prompt submit) (push (list prompt submit (current-buffer)) pressed)))
           (text (agent-ui-render '(:type "plain" :title "T"
                                    :actions ((:label "Retry" :prompt "Run the failing tests again")
                                              (:label "Log" :prompt "Show me the log" :submit t)))
                                  (agent-ui-context))))
      (should (equal (substring-no-properties text) "T\nbody\n⏵ Retry   ⏵ Log"))
      (should (eq (get-text-property (string-search "⏵ Retry" text) 'face text) 'agent-ui-action))
      (should (string-match-p "put into the prompt \"Run the failing"
                              (get-text-property (string-search "⏵ Retry" text) 'help-echo text)))
      ;; Pressed: its prompt, sent or not, in the button's buffer.
      (with-temp-buffer
        (insert text)
        (goto-char (1+ (string-search "⏵ Log" text)))
        (agent-ui-button-press)
        (goto-char (1+ (string-search "⏵ Retry" text)))
        (agent-ui-button-press)
        (should (equal (mapcar #'butlast pressed)
                       '(("Run the failing tests again" nil) ("Show me the log" t))))
        (should (eq (nth 2 (car pressed)) (current-buffer)))))
    ;; None: no line for them.
    (should (equal (agent-ui-render '(:type "plain") (agent-ui-context)) "body"))))

(ert-deftest agent-ui-core/wrong-actions-explained ()
  (cl-flet ((wrong (actions) (agent-ui-error-message
                              (should-error (agent-ui-check-actions actions) :type 'agent-ui-error))))
    (should (string-match-p "give an array" (wrong '(:label "x"))))
    (should (string-match-p "action 1 must be" (wrong '("x"))))
    (should (string-match-p "action 1's prompt must be text" (wrong '((:label "x")))))
    (should (string-match-p "action 1's label must be text" (wrong '((:label " " :prompt "p")))))
    (should (string-match-p "action 2 has \"run\"" (wrong '((:label "a" :prompt "p") (:label "b" :prompt "q" :run t)))))
    (should (string-match-p "submit is true or false" (wrong '((:label "a" :prompt "p" :submit "yes")))))
    (should (string-match-p "at most 6" (wrong (make-list 7 '(:label "a" :prompt "p"))))))
  (should (agent-ui-check-actions '((:label "a" :prompt "p" :submit :false)))))


;; ====== BADGES ======

(defun +test-auc-svg (text)
  "The SVG shown over TEXT (its display's data), or nil."
  (plist-get (cdr (get-text-property 0 'display text)) :data))

(ert-deftest agent-ui-core/pills ()
  "A pill: its text outlined [LABEL COUNT] or filled \" LABEL COUNT \" (as
wide), in its face; in the GUI a rounded tag over the same text, filled in
its colour or outlined on a tint."
  (let ((text (agent-ui-context :width 60))
        (gui (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))
    (should (equal (substring-no-properties (agent-ui-pill "bug" text :count 3)) "[bug 3]"))
    (should (equal (substring-no-properties (agent-ui-pill "bug" text :count 3 :filled t)) " bug 3 "))
    (should (eq (get-text-property 1 'face (agent-ui-pill "PASSED" text :face 'agent-ui-success)) 'agent-ui-success))
    (should (equal (get-text-property 1 'face (agent-ui-pill "P1" text :face 'agent-ui-error :filled t))
                   '(:inherit agent-ui-error :inverse-video t)))
    (should-not (+test-auc-svg (agent-ui-pill "bug" text)))
    ;; The GUI's: as wide as its text, its words in it.
    (let* ((pill (agent-ui-pill "bug" gui :count 3))
           (svg (+test-auc-svg pill)))
      (should (equal (substring-no-properties pill) "[bug 3]"))
      (should (string-match-p "<svg width=\"56\" height=\"16\"" svg))
      (should (string-match-p "<rect [^>]*rx=" svg))
      (should (string-match-p ">bug 3</text>" svg)))
    ;; Filled: its colour behind, the words in the background's.
    (let ((svg (+test-auc-svg (agent-ui-pill "P1" gui :filled t :face 'agent-ui-error))))
      (should (string-match-p (format "fill=\"%s\"" (regexp-quote (agent-ui-color 'agent-ui-error))) svg))
      (should (string-match-p (format "<text fill=\"%s\"" (regexp-quote (agent-ui-background))) svg)))))

(ert-deftest agent-ui-core/pies ()
  "A pie: two columns, a quarter's glyph; in the GUI a circle and its slice
\(none at 0, a full disc at 1)."
  (let ((text (agent-ui-context :width 60))
        (gui (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))
    (should (equal (mapcar (lambda (f) (substring-no-properties (agent-ui-pie f text))) '(0 0.25 0.5 0.75 1 1.5))
                   '("○ " "◔ " "◑ " "◕ " "● " "● ")))
    (should (eq (get-text-property 0 'face (agent-ui-pie 0.5 text 'agent-ui-success)) 'agent-ui-success))
    (should (string-match-p "<path [^>]*d=\"M 8.00 8.00 L 8.00 1.50 A 6.50 6.50 0 0 1 14.50 8.00 Z\""
                            (+test-auc-svg (agent-ui-pie 0.25 gui))))
    (should-not (string-match-p "<path" (+test-auc-svg (agent-ui-pie 0 gui))))
    ;; Full: the disc filled over its ring.
    (should (= 2 (with-temp-buffer (insert (+test-auc-svg (agent-ui-pie 1 gui))) (how-many "<circle" (point-min) (point-max)))))))

(ert-deftest agent-ui-core/images-without-a-background-of-their-own ()
  "Agent UI's images have no background of their own, whatever gives one
\(solaire-mode's advice on `create-image'): their transparent parts show
what's behind them, a selection too (it had gaps there)."
  (let ((advice (lambda (image) (plist-put (cdr image) :background "#21242b") image))
        (gui (agent-ui-context :width 60 :graphic t :char-width 8 :line-height 16)))
    (advice-add 'create-image :filter-return advice '((name . test-solaire)))
    (unwind-protect
        (progn
          (should (plist-get (cdr (svg-image (svg-create 4 4))) :background))
          (dolist (text (list (agent-ui-pill "bug" gui)
                              (agent-ui-pie 0.5 gui)
                              (agent-ui-render '(:type "chart" :values (1 3 2)) gui)
                              (agent-ui-render '(:type "gauge" :value 40) gui)))
            (let ((image (get-text-property 0 'display text)))
              (should (eq (car image) 'image))
              (should-not (plist-member (cdr image) :background)))))
      (advice-remove 'create-image 'test-solaire))))

(ert-deftest agent-ui-core/the-context-knows-the-font ()
  "The text's font size and ascent, both, if given (a canvas's window says
them); else neither."
  (let ((ctx (agent-ui-context :graphic t :font-size 19 :font-ascent 19)))
    (should (= (plist-get ctx :font-size) 19))
    (should (= (plist-get ctx :font-ascent) 19)))
  (should-not (plist-member (agent-ui-context :graphic t :font-size 19) :font-size))
  (should-not (plist-member (agent-ui-context) :font-ascent)))
