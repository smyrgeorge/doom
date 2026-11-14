;;; tests/unit/test-agent-ui-mermaid.el -*- lexical-binding: t; -*-
;; config/agent-ui/elements/mermaid.el: the mermaid type (its diagram an
;; image in the GUI once the stand-in mmdc drew it, sized to the canvas, in
;; a snapshot as it's shown; its source meanwhile, in a terminal, or with
;; Mermaid's message; an update draws anew; a theme switch draws again); the
;; markdown type's ```mermaid blocks drawn the same; its example right.

(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)
(+test-load "config/agent-shell" "config/window" "config/webkit" "config/mermaid" "config/agent-ui")
(require 'agent-shell)
(require 'mermaid-mode)
(load (expand-file-name "../helper-mermaid" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defmacro +test-aum (&rest body)
  "BODY in a GUI (faked: images made, not drawn), the stand-in mmdc, a
stand-in theme, no diagram failed yet; `redrawn' the diagrams whose elements
were to be redrawn."
  (declare (indent 0))
  `(+test-mermaid--with-mmdc
     (let ((agent-ui-mermaid--errors (make-hash-table :test #'equal))
           (redrawn nil))
       (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                 ((symbol-function 'image-type-available-p) (lambda (&rest _) t))
                 ((symbol-function 'agent-ui-mermaid--redraw)
                  (lambda (&optional diagram) (push diagram redrawn))))
         (+test-mermaid--theme +test-mermaid--dark
           ,@body)))))

(defun +test-aum--gui (&optional width)
  (agent-ui-context :width (or width 60) :graphic t :char-width 8 :line-height 16))

(defun +test-aum--draw (element &optional ctx)
  (agent-ui-render element (or ctx (+test-aum--gui))))

(defun +test-aum--image (text)
  "The image TEXT shows, or nil."
  (let ((pos (text-property-not-all 0 (length text) 'display nil text)))
    (and pos (get-text-property pos 'display text))))

(defconst +test-aum--flow '(:type "mermaid" :id "flow" :diagram "flowchart LR\n    build --> test"))

(ert-deftest agent-ui-mermaid/the-type ()
  (should (memq 'mermaid (agent-ui-types)))
  (should (agent-ui-check "mermaid" '(:type "mermaid" :diagram "flowchart LR; a --> b")))
  (should (string-search "diagram" (agent-ui-error-message
                                    (should-error (agent-ui-check "mermaid" '(:type "mermaid"))
                                                  :type 'agent-ui-error))))
  (should (memq #'agent-ui-mermaid-theme-h +my/mermaid-theme-hook)))

(ert-deftest agent-ui-mermaid/in-a-terminal-its-source-coloured ()
  (let ((text (agent-ui-render +test-aum--flow (agent-ui-context :width 60))))
    (should (equal (substring-no-properties text) "flowchart LR\n    build --> test"))
    (should (memq 'font-lock-keyword-face (ensure-list (get-text-property 0 'face text))))))

(ert-deftest agent-ui-mermaid/its-source-fits-the-width ()
  "Its source, shown in a terminal or until drawn, wrapped to the width,
each line's rest under its indent (a line ran 190 columns at every width)."
  (let* ((element '(:type "mermaid" :diagram "flowchart LR\n    parser[The parser module] --> checker[The type checker, slow on big files]"))
         (text (substring-no-properties (agent-ui-render element (agent-ui-context :width 24)))))
    (should (equal text (concat "flowchart LR\n"
                                "    parser[The parser\n"
                                "    module] -->\n"
                                "    checker[The type\n"
                                "    checker, slow on big\n"
                                "    files]")))
    (+test-aum
      (dolist (line (split-string (substring-no-properties (+test-aum--draw element (+test-aum--gui 24))) "\n"))
        (should (<= (string-width line) 24))))))

(ert-deftest agent-ui-mermaid/drawn-in-the-background ()
  (+test-aum
    (let ((text (+test-aum--draw +test-aum--flow)))
      ;; Its source meanwhile.
      (should (string-prefix-p "flowchart LR\n    build --> test\ndrawing…" (substring-no-properties text)))
      (should-not (+test-aum--image text)))
    ;; Drawn: its elements redrawn, now its image.
    (should (+test-mermaid--wait (lambda () redrawn)))
    (should (equal redrawn '("flowchart LR\n    build --> test")))
    (let* ((text (+test-aum--draw +test-aum--flow))
           (image (+test-aum--image text)))
      (should (eq (car image) 'image))
      (should (eq (image-property image :type) 'svg))
      ;; Its size in its data, pixels (the stand-in's has none: its source's).
      (should (string-search "build --> test" (image-property image :data))))
    (should (= (length (+test-mermaid--runs mmdc)) 1))))

(ert-deftest agent-ui-mermaid/sized-to-the-canvas ()
  (let ((svg "<svg xml:space=\"preserve\" id=\"my-svg\" width=\"100%\" style=\"max-width: 1200px; background-color: transparent;\" viewBox=\"0 0 1200 300\"><g/></svg>"))
    ;; Wider than the canvas (59 columns of 8 px): as wide as it.
    (let ((sized (agent-ui-mermaid--sized svg (+test-aum--gui 60))))
      (should (string-prefix-p "<svg width=\"472\" height=\"118\" xml:space=\"preserve\" id=\"my-svg\"" sized))
      (should-not (string-search "max-width" sized))
      (should (string-search "background-color: transparent;" sized))
      ;; The snapshot reads its size there.
      (should (equal (agent-ui-snapshot--svg-size sized) '(472 . 118))))
    ;; Narrower: as it is.
    (should (string-prefix-p "<svg width=\"1200\" height=\"300\""
                             (agent-ui-mermaid--sized svg (+test-aum--gui 200))))))

(ert-deftest agent-ui-mermaid/an-update-draws-anew ()
  (+test-aum
    (+test-aum--draw +test-aum--flow)
    (should (+test-mermaid--wait (lambda () redrawn)))
    (let ((text (+test-aum--draw '(:type "mermaid" :diagram "flowchart LR\n    build --> deploy"))))
      (should (string-search "drawing…" (substring-no-properties text))))
    (should (+test-mermaid--wait (lambda () (= (length redrawn) 2))))
    (should (string-search "build --> deploy"
                           (image-property (+test-aum--image (+test-aum--draw '(:type "mermaid" :diagram "flowchart LR\n    build --> deploy")))
                                           :data)))))

(ert-deftest agent-ui-mermaid/an-error-mermaid-s-message ()
  (+test-aum
    (let ((element '(:type "mermaid" :diagram "flowchart LR\n    a --> ERROR")))
      (+test-aum--draw element)
      (should (+test-mermaid--wait (lambda () redrawn)))
      (let ((text (+test-aum--draw element)))
        (should (string-prefix-p "flowchart LR\n    a --> ERROR\nParse error on line 2:" (substring-no-properties text)))
        (should (eq (get-text-property (string-search "Parse" text) 'face text) 'agent-ui-error)))
      ;; Not drawn again.
      (+test-aum--draw element)
      (accept-process-output nil 0.1)
      (should (= (length (+test-mermaid--runs mmdc)) 1)))))

(ert-deftest agent-ui-mermaid/a-markdown-element-s-blocks ()
  (+test-aum
    (let ((element '(:type "markdown" :id "notes" :markdown "The flow:\n\n```mermaid\nflowchart LR\n    build --> test\n```\n\nThat's it.")))
      (let ((text (substring-no-properties (+test-aum--draw element))))
        (should (string-search "The flow:" text))
        (should (string-search "flowchart LR\n    build --> test\ndrawing…" text))
        (should (string-search "That's it." text))
        (should-not (string-search "```" text)))
      (should (+test-mermaid--wait (lambda () redrawn)))
      (let ((text (+test-aum--draw element)))
        (should (eq (car (+test-aum--image text)) 'image))
        (should (string-search "That's it." (substring-no-properties text)))))))

(ert-deftest agent-ui-mermaid/redrawn-where-it-shows ()
  "The elements showing a diagram, in a canvas: a mermaid element's, a
markdown one's block, inside a panel too."
  (should (agent-ui-mermaid--shows-p '(:type "mermaid" :diagram " a\n") "a"))
  (should-not (agent-ui-mermaid--shows-p '(:type "mermaid" :diagram "b") "a"))
  (should (agent-ui-mermaid--shows-p '(:type "markdown" :markdown "x\n```mermaid\na\n```") "a"))
  (should-not (agent-ui-mermaid--shows-p '(:type "markdown" :markdown "no diagram")))
  (should (agent-ui-mermaid--shows-p '(:type "markdown" :markdown "x\n~~~ mermaid\na\n~~~")))
  (should-not (agent-ui-mermaid--shows-p '(:type "text" :text "a") "a")))

(ert-deftest agent-ui-mermaid/a-theme-switch-draws-again ()
  (+test-aum
    (run-hooks '+my/mermaid-theme-hook)
    (should (equal redrawn '(nil)))))

(ert-deftest agent-ui-mermaid/its-example ()
  (let ((example (agent-ui-type-example (agent-ui-type 'mermaid))))
    (should (string-search "-->" (plist-get example :diagram)))
    (should (agent-ui-check "mermaid" (append '(:type "mermaid") example)))))
