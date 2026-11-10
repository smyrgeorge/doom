;;; tests/unit/test-sticky.el -*- lexical-binding: t; -*-
;; config/editor/sticky.el: the header line of code windows shows the classes /
;; functions (Markdown: headings) the top visible line is inside, once their
;; first lines scrolled out of view; otherwise the file's path in its project.

(+test-load "config/editor")

;; Doom's tree-sitter grammars (read only) and the modes using them.
(add-to-list 'treesit-extra-load-path
             (expand-file-name ".local/etc/tree-sitter/" +test-doom-emacs-dir))
(require 'kotlin-ts-mode nil t)
(require 'markdown-ts-mode nil t)
(require 'projectile nil t)

;; ====== HELPERS ======

(defconst +test-sticky--python
  "class Foo:
    x = 1

    def bar(self):
        y = 2
        return y


def top():
    def inner():
        return 1
    pass
"
  "Lines: 1 class, 4 method, 5 its body, 9 top-level function, 10 nested, 11 its body.")

(defconst +test-sticky--kotlin
  "class Api {
    companion object {
        fun make() = Api()
    }
    fun call(x: Int) {
        val y = x
    }
}
object Single {
    fun go() {
        println()
    }
}
")

(defconst +test-sticky--markdown
  "# Guide

Intro.

## Setup

Text.

### Install

Steps.

```python
def f():
    pass
```

## Usage

More.
"
  "Headings on lines 1, 5, 9 and 18; a code block on lines 13-16.")

(defmacro +test-sticky--needs (&rest languages)
  "Skip the test unless the grammars of LANGUAGES (and their modes) are there."
  `(skip-unless (and (treesit-available-p)
                     (seq-every-p #'treesit-language-available-p ',languages))))

(defmacro +test-sticky (name content mode &rest body)
  "BODY in a buffer visiting NAME (in the temp folder) with CONTENT, opened in
MODE, shown in the only window; files visited by their true name, as Doom does."
  (declare (indent 3))
  `(+test-with-reset
     (set-window-parameter nil '+my/sticky nil)
     (let ((auto-mode-alist (list (cons "" ,mode)))
           (magic-mode-alist nil)
           (interpreter-mode-alist nil)
           (major-mode-remap-alist nil)
           (find-file-visit-truename t))
       (find-file (+test-file ,name ,content)))
     ,@body))

(defun +test-sticky--goto-line (line)
  (goto-char (point-min))
  (forward-line (1- line))
  (point))

(defun +test-sticky--starts (line)
  "The scopes around LINE as the lines they start on."
  (mapcar #'line-number-at-pos
          (+my/sticky--scope-starts (save-excursion (+test-sticky--goto-line line)))))

(defun +test-sticky--scopes (line)
  "The header's scopes for the top line LINE (no properties)."
  (substring-no-properties
   (+my/sticky--compute (save-excursion (+test-sticky--goto-line line)))))

(defun +test-sticky--node (type)
  "The first tree-sitter node of TYPE in the buffer."
  (treesit-search-subtree (treesit-buffer-root-node)
                          (lambda (node) (equal (treesit-node-type node) type))))

;; ====== SETTINGS ======

(ert-deftest sticky/settings ()
  "Our list: only Kotlin, whose mode declares neither its defuns nor an
outline (Markdown's come from its outline)."
  (should (equal (default-value '+my/sticky-separator) " › "))
  (should (equal (mapcar #'car +my/sticky-defun-types) '(kotlin)))
  (let ((kotlin (alist-get 'kotlin +my/sticky-defun-types)))
    (dolist (type '("class_declaration" "object_declaration" "function_declaration"
                    "companion_object"))
      (should (string-match-p kotlin type)))
    (dolist (type '("property_declaration" "class_body" "my_class_declaration"
                    "companion_object_x"))
      (should-not (string-match-p kotlin type)))))

;; ====== LANGUAGE ======

(ert-deftest sticky/language-markdown-host-wins ()
  "In Markdown the headings count, not the language of the code block at point."
  (+test-sticky--needs markdown markdown-inline)
  (+test-sticky "sticky/guide.md" +test-sticky--markdown #'markdown-ts-mode
    (+test-sticky--goto-line 14)
    (should (eq (+my/sticky--language) 'markdown))
    (cl-letf (((symbol-function 'treesit-language-at) (lambda (&rest _) 'python)))
      (should (eq (+my/sticky--language) 'markdown)))))

(ert-deftest sticky/language-at-point-otherwise ()
  (+test-sticky--needs python json)
  (+test-sticky "sticky/a.py" +test-sticky--python #'python-ts-mode
    (should (eq (+my/sticky--language) 'python))
    (cl-letf (((symbol-function 'treesit-language-at) (lambda (&rest _) 'embedded)))
      (should (eq (+my/sticky--language) 'embedded))))
  ;; No primary parser: the language at point.
  (with-temp-buffer
    (insert "{\"a\": 1}")
    (treesit-parser-create 'json)
    (should (eq (+my/sticky--language) 'json))))

;; ====== TREE-SITTER ======

(ert-deftest sticky/treesit-p ()
  "Tree-sitter scopes where the buffer has a parser and its defuns are known:
from our list, the mode's regexp, or its `defun' thing."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not (+my/sticky--treesit-p)))
  (when (treesit-language-available-p 'python)
    (with-temp-buffer
      (python-ts-mode)
      (should (+my/sticky--treesit-p))))
  (when (treesit-language-available-p 'json)
    (with-temp-buffer
      (json-ts-mode)
      (should (stringp treesit-defun-type-regexp))
      (should (+my/sticky--treesit-p)))
    ;; A parser, but nothing says what its defuns are.
    (with-temp-buffer
      (treesit-parser-create 'json)
      (should-not (+my/sticky--treesit-p))))
  (when (and (fboundp 'kotlin-ts-mode) (treesit-language-available-p 'kotlin))
    (with-temp-buffer
      (kotlin-ts-mode)
      (should-not treesit-defun-type-regexp)
      (should-not (treesit-thing-defined-p 'defun 'kotlin))
      (should (+my/sticky--treesit-p)))))

;; ====== OUTLINE ======

(defconst +test-sticky--dockerfile
  "ARG GO=1.22
FROM golang:${GO} AS build
WORKDIR /src
RUN go build -o /app

FROM alpine:3.20
COPY --from=build /app /app
CMD [\"/app\"]
"
  "Stages starting on lines 2 and 6; line 1 before them.")

(ert-deftest sticky/outline-when-no-defuns ()
  "A mode declaring no defuns: its outline (`treesit-outline-predicate') tells
the scopes, in the buffer's own language; a mode declaring defuns: those."
  (+test-sticky--needs json)
  ;; A parser, no defuns declared, an outline: its headings are the scopes.
  (with-temp-buffer
    (insert "{\"a\": {\"b\": 1}}")
    (setq-local treesit-primary-parser (treesit-parser-create 'json))
    (should-not (+my/sticky--treesit-p))
    (setq-local treesit-outline-predicate "\\`pair\\'")
    (should (equal (+my/sticky--outline 'json) "\\`pair\\'"))
    (should-not (+my/sticky--outline 'python))      ; not the buffer's language
    (should (+my/sticky--treesit-p))
    (should (+my/sticky--defun-node-p (+test-sticky--node "pair")))
    (should-not (+my/sticky--defun-node-p (+test-sticky--node "number"))))
  ;; json-ts-mode declares its defuns: they win over an outline.
  (with-temp-buffer
    (insert "{\"a\": 1}")
    (json-ts-mode)
    (setq-local treesit-outline-predicate "\\`number\\'")
    (should-not (+my/sticky--outline 'json))
    (should-not (+my/sticky--defun-node-p (+test-sticky--node "number")))
    (should (+my/sticky--defun-node-p (+test-sticky--node "pair")))))

(ert-deftest sticky/outline-of-markdown ()
  "markdown-ts-mode declares no defuns, only an outline (its sections): the
scopes without an entry in our list."
  (+test-sticky--needs markdown markdown-inline)
  (with-temp-buffer
    (insert +test-sticky--markdown)
    (markdown-ts-mode)
    (should-not (alist-get 'markdown +my/sticky-defun-types))
    (should (+my/sticky--outline 'markdown))
    (should (+my/sticky--treesit-p))
    (cl-flet ((node (type)              ; in the block tree (not the inline one)
                (treesit-search-subtree (treesit-buffer-root-node 'markdown)
                                        (lambda (n) (equal (treesit-node-type n) type)))))
      (should (+my/sticky--defun-node-p (node "section")))
      (should-not (+my/sticky--defun-node-p (node "atx_heading")))
      (should-not (+my/sticky--defun-node-p (node "paragraph"))))))

(ert-deftest sticky/defun-node-p ()
  (+test-sticky--needs python)
  ;; The mode's `defun' thing.
  (with-temp-buffer
    (insert +test-sticky--python)
    (python-ts-mode)
    (should (+my/sticky--defun-node-p (+test-sticky--node "class_definition")))
    (should (+my/sticky--defun-node-p (+test-sticky--node "function_definition")))
    (should-not (+my/sticky--defun-node-p (+test-sticky--node "identifier")))
    (should-not (+my/sticky--defun-node-p (+test-sticky--node "block")))))

(ert-deftest sticky/defun-node-p-our-list ()
  (+test-sticky--needs kotlin)
  (skip-unless (fboundp 'kotlin-ts-mode))
  (with-temp-buffer
    (insert +test-sticky--kotlin)
    (kotlin-ts-mode)
    (dolist (type '("class_declaration" "companion_object" "function_declaration"
                    "object_declaration"))
      (should (+my/sticky--defun-node-p (+test-sticky--node type))))
    (should-not (+my/sticky--defun-node-p (+test-sticky--node "property_declaration")))
    (should-not (+my/sticky--defun-node-p (+test-sticky--node "class_body")))))

(ert-deftest sticky/defun-node-p-mode-regexp ()
  "Older tree-sitter modes: `treesit-defun-type-regexp', a regexp or (REGEXP . PRED)."
  (+test-sticky--needs json)
  (with-temp-buffer
    (insert "{\"a\": \"b\"}")
    (json-ts-mode)
    (let ((pair (+test-sticky--node "pair"))
          (string (+test-sticky--node "string")))
      (should (+my/sticky--defun-node-p pair))
      (should-not (+my/sticky--defun-node-p string))
      (let ((treesit-defun-type-regexp (cons "pair" #'ignore)))
        (should-not (+my/sticky--defun-node-p pair)))
      (let ((treesit-defun-type-regexp (cons "pair" #'identity)))
        (should (+my/sticky--defun-node-p pair))
        (should-not (+my/sticky--defun-node-p string))))))

;; ====== SCOPES ======

(ert-deftest sticky/scopes-tree-sitter ()
  "The scopes the line is inside, outermost first, those starting on the line
itself (or below) left out."
  (+test-sticky--needs python)
  (+test-sticky "sticky/a.py" +test-sticky--python #'python-ts-mode
    (should (equal (+test-sticky--starts 1) nil))      ; class line
    (should (equal (+test-sticky--starts 2) '(1)))     ; class body
    (should (equal (+test-sticky--starts 3) '(1)))     ; blank line in the class
    (should (equal (+test-sticky--starts 4) '(1)))     ; method line
    (should (equal (+test-sticky--starts 5) '(1 4)))   ; method body
    (should (equal (+test-sticky--starts 6) '(1 4)))
    (should (equal (+test-sticky--starts 7) nil))      ; between them
    (should (equal (+test-sticky--starts 9) nil))      ; top-level function
    (should (equal (+test-sticky--starts 10) '(9)))    ; nested function line
    (should (equal (+test-sticky--starts 11) '(9 10))) ; nested body
    (should (equal (+test-sticky--starts 12) '(9)))
    ;; From anywhere in the line's indentation.
    (should (equal (mapcar #'line-number-at-pos
                           (+my/sticky--scope-starts (+ 2 (+test-sticky--goto-line 5))))
                   '(1 4)))))

(ert-deftest sticky/scopes-without-tree-sitter ()
  "Other modes: the defun around the line, if it starts above it."
  (+test-sticky "sticky/a.el"
      ";; A comment\n(defun foo ()\n  (let ((x 1))\n    x))\n\n(defvar bar 1)\n(bar)\n"
      #'emacs-lisp-mode
    (should-not (+my/sticky--treesit-p))
    (should (equal (+test-sticky--starts 1) nil))
    (should (equal (+test-sticky--starts 2) nil))      ; the defun's own line
    (should (equal (+test-sticky--starts 3) '(2)))
    (should (equal (+test-sticky--starts 4) '(2)))
    (should (equal (+test-sticky--starts 5) nil))      ; after it
    (should (equal (+test-sticky--starts 7) nil))
    (should (equal (+test-sticky--scopes 3) "(defun foo ()"))))

(ert-deftest sticky/scopes-not-a-comment-or-blank-line ()
  "A mode's `beginning-of-defun' that stops on a comment or a blank line: no scope."
  (+test-sticky "sticky/a.txt" "  ;; note\n\nfoo\n  bar\n  baz\n" #'emacs-lisp-mode
    (dolist (line '(1 2 3))
      (setq-local beginning-of-defun-function
                  (lambda (&rest _) (+test-sticky--goto-line line) t))
      (setq-local end-of-defun-function (lambda (&rest _) (goto-char (point-max))))
      (should (equal (+test-sticky--starts 5) (if (= line 3) '(3) nil))))))

(ert-deftest sticky/scopes-none-found ()
  (+test-sticky "sticky/b.el" "(setq a 1)\nb\n" #'emacs-lisp-mode
    ;; `beginning-of-defun' fails, or finds nothing.
    (setq-local beginning-of-defun-function (lambda (&rest _) (error "No defun")))
    (should-not (+test-sticky--starts 2))
    (setq-local beginning-of-defun-function (lambda (&rest _) nil))
    (should-not (+test-sticky--starts 2))))

(ert-deftest sticky/line ()
  "A scope's line: fontified, without its indentation or trailing blanks."
  (+test-sticky--needs python)
  (+test-sticky "sticky/a.py" "class Foo:\n    def bär(self):   \n        pass\n" #'python-ts-mode
    (let ((line (+my/sticky--line (+test-sticky--goto-line 2))))
      (should (equal (substring-no-properties line) "def bär(self):"))
      (should (eq (get-text-property 0 'face line) 'font-lock-keyword-face)))
    ;; From any position on the line.
    (should (equal (substring-no-properties (+my/sticky--line (+ 3 (+test-sticky--goto-line 2))))
                   "def bär(self):"))))

;; ====== THE FILE'S PATH ======

(ert-deftest sticky/path-in-the-project ()
  "The file's path in its project, dimmed."
  (+test-sticky "sticky-path/src/app.py" "x = 1\n" #'python-mode
    (cl-letf (((symbol-function 'doom-project-root)
               (lambda (&rest _) (file-truename (+test-tmp-file "sticky-path/")))))
      (let ((path (+my/sticky--path)))
        (should (equal (substring-no-properties path) "src/app.py"))
        (should (eq (get-text-property 0 'face path) 'shadow))
        (should (equal (+my/sticky--compute (point-min)) path))))))

(ert-deftest sticky/path-in-a-real-project ()
  "A project as projectile finds it (a `.projectile' file at its root)."
  (skip-unless (featurep 'projectile))
  (+test-file "sticky-real/.projectile" "")
  (+test-sticky "sticky-real/lib/core/app.py" "x = 1\n" #'python-mode
    (should (equal (substring-no-properties (+my/sticky--path)) "lib/core/app.py"))))

(ert-deftest sticky/path-outside-a-project ()
  "Outside a project: the whole path, `~' for the home folder."
  (with-temp-buffer
    (setq buffer-file-name (expand-file-name "~/sticky-test/notes/app.py"))
    (cl-letf (((symbol-function 'doom-project-root) #'ignore))
      (should (equal (substring-no-properties (+my/sticky--path)) "~/sticky-test/notes/app.py")))
    (setq buffer-file-name nil)))

(ert-deftest sticky/path-cached ()
  "Remembered per file (finding the project root on each scroll was slow)."
  (with-temp-buffer
    (let ((calls 0))
      (cl-letf (((symbol-function 'doom-project-root)
                 (lambda (&rest _) (cl-incf calls) (expand-file-name "/proj/"))))
        (setq buffer-file-name "/proj/a.py")
        (should (equal (substring-no-properties (+my/sticky--path)) "a.py"))
        (should (equal (substring-no-properties (+my/sticky--path)) "a.py"))
        (should (= calls 1))
        ;; Renamed.
        (setq buffer-file-name "/proj/sub/b.py")
        (should (equal (substring-no-properties (+my/sticky--path)) "sub/b.py"))
        (should (= calls 2))
        (setq buffer-file-name nil)))))

;; ====== THE HEADER ======

(ert-deftest sticky/compute ()
  "Scopes joined by the separator (dimmed), else the path."
  (+test-sticky--needs python)
  (+test-sticky "sticky/a.py" +test-sticky--python #'python-ts-mode
    (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) default-directory)))
      (let ((text (+my/sticky--compute (+test-sticky--goto-line 5))))
        (should (equal (substring-no-properties text) "class Foo: › def bar(self):"))
        (should (eq (get-text-property (string-search "›" text) 'face text) 'shadow))
        (should (eq (get-text-property 0 'face text) 'font-lock-keyword-face)))
      (let ((+my/sticky-separator " / "))
        (should (equal (+test-sticky--scopes 11) "def top(): / def inner():")))
      (should (equal (+test-sticky--scopes 1) "a.py")))))

(ert-deftest sticky/indent-lines-up-with-the-code ()
  "Spaces as wide as the line numbers: the widest that can show, at least
`display-line-numbers-width' digits, plus 2; none without line numbers."
  (+test-sticky "sticky/long.py" (mapconcat (lambda (n) (format "x%d = %d\n" n n))
                                            (number-sequence 1 1100) "")
      #'python-mode
    (let ((window (selected-window))
          (rows (window-body-height)))
      (setq-local display-line-numbers nil)
      (should (equal (+my/sticky--indent window) ""))
      (setq-local display-line-numbers t)
      (setq-local display-line-numbers-width nil)
      (should (equal (+my/sticky--indent window)
                     (make-string (+ 2 (length (number-to-string rows))) ?\s)))
      (setq-local display-line-numbers-width 5)
      (should (= (length (+my/sticky--indent window)) 7))
      (setq-local display-line-numbers-width nil)
      ;; Scrolled where the numbers have 4 digits (the last row's counts).
      (set-window-start window (+test-sticky--goto-line (- 1000 (1- rows))))
      (should (= (length (+my/sticky--indent window)) 6))
      (set-window-start window (+test-sticky--goto-line (- 999 (1- rows))))
      (should (= (length (+my/sticky--indent window)) 5)))))

(ert-deftest sticky/indent-relative-numbers-ask-emacs ()
  (+test-sticky "sticky/rel.py" "x = 1\n" #'python-mode
    (let* ((window (selected-window))
           (other (split-window))
           asked)
      (cl-letf (((symbol-function 'line-number-display-width)
                 (lambda (&optional unit) (push (cons (selected-window) unit) asked) 3.6)))
        (dolist (style '(relative visual))
          (setq-local display-line-numbers style)
          (select-window other)
          (should (equal (+my/sticky--indent window) "   "))
          (should (equal (car asked) (cons window 'columns)))
          (should (eq (selected-window) other)))))))

(ert-deftest sticky/header-shows-the-scopes-once-scrolled ()
  "At the top: the path; scrolled into a method: its class and itself."
  (+test-sticky--needs python)
  (+test-sticky "sticky-hdr/app.py" +test-sticky--python #'python-ts-mode
    (cl-letf (((symbol-function 'doom-project-root)
               (lambda (&rest _) (file-truename (+test-tmp-file "sticky-hdr/")))))
      (setq-local display-line-numbers nil)
      (should +my/sticky-header-mode)
      (should (equal (substring-no-properties (+my/sticky-header)) "app.py"))
      (set-window-start nil (+test-sticky--goto-line 5))
      (should (equal (substring-no-properties (+my/sticky-header))
                     "class Foo: › def bar(self):"))
      ;; Lined up past the line numbers.
      (setq-local display-line-numbers t)
      (should (equal (substring-no-properties (+my/sticky-header))
                     (concat (+my/sticky--indent (selected-window))
                             "class Foo: › def bar(self):"))))))

(ert-deftest sticky/header-cached-per-scroll-position ()
  (+test-sticky "sticky/c.py" (mapconcat (lambda (n) (format "x%d = %d\n" n n))
                                         (number-sequence 1 100) "")
      #'python-mode
    (let ((computed 0))
      (cl-letf* ((compute (symbol-function '+my/sticky--compute))
                 ((symbol-function '+my/sticky--compute)
                  (lambda (start) (cl-incf computed) (format "at %d" (line-number-at-pos start)))))
        (let ((text (+my/sticky-header)))
          (should (eq (+my/sticky-header) text))
          (should (= computed 1))
          (should (equal (cdr (window-parameter nil '+my/sticky)) text))
          ;; Scrolled.
          (set-window-start nil (+test-sticky--goto-line 10))
          (should (string-suffix-p "at 10" (+my/sticky-header)))
          (should (= computed 2))
          ;; Edited.
          (goto-char (point-max))
          (insert "y = 1\n")
          (+my/sticky-header)
          (should (= computed 3))
          ;; Line numbers on or off.
          (setq-local display-line-numbers (not display-line-numbers))
          (+my/sticky-header)
          (should (= computed 4))
          ;; Resized.
          (split-window)
          (+my/sticky-header)
          (should (= computed 5))
          (+my/sticky-header)
          (should (= computed 5))
          (ignore compute))))))

(ert-deftest sticky/header-per-window ()
  "Each window showing the buffer has its own header (its own top line)."
  (+test-sticky "sticky/w.py" (mapconcat (lambda (n) (format "x%d = %d\n" n n))
                                         (number-sequence 1 100) "")
      #'python-mode
    (cl-letf (((symbol-function '+my/sticky--compute)
               (lambda (start) (format "at %d" (line-number-at-pos start)))))
      (setq-local display-line-numbers nil)
      (let* ((top (selected-window))
             (bottom (split-window)))
        (set-window-parameter bottom '+my/sticky nil)
        (set-window-start bottom (+test-sticky--goto-line 40))
        (should (equal (+my/sticky-header) "at 1"))
        (should (equal (with-selected-window bottom (+my/sticky-header)) "at 40"))
        (should (equal (with-selected-window top (+my/sticky-header)) "at 1"))))))

(ert-deftest sticky/header-never-signals ()
  "An error working out the scopes leaves the header empty (but lined up)."
  (+test-sticky "sticky/e.py" "x = 1\n" #'python-mode
    (cl-letf (((symbol-function '+my/sticky--compute) (lambda (_) (error "Boom"))))
      (setq-local display-line-numbers nil)
      (should (equal (+my/sticky-header) ""))
      (setq-local display-line-numbers t)
      (should (equal (+my/sticky-header) (+my/sticky--indent (selected-window)))))))

;; ====== THE MODE ======

(ert-deftest sticky/mode ()
  "On: the header row (past the fringe, then our text); off: the default back."
  (with-temp-buffer
    (+my/sticky-header-mode 1)
    (should (local-variable-p 'header-line-format))
    (should (equal header-line-format
                   '("" (:propertize " " display (space :align-to 0))
                     (:eval (+my/sticky-header)))))
    (cl-letf (((symbol-function '+my/sticky-header) (lambda () "HEADER")))
      (should (equal (eval (cadr (nth 2 header-line-format)) t) "HEADER")))
    (+my/sticky-header-mode -1)
    (should-not (local-variable-p 'header-line-format))
    (call-interactively #'+my/sticky-header-mode)
    (should +my/sticky-header-mode)
    (call-interactively #'+my/sticky-header-mode)
    (should-not +my/sticky-header-mode)))

(ert-deftest sticky/supported-p ()
  "Where scopes can be told: tree-sitter defuns, a mode's `beginning-of-defun',
or Lisp."
  (dolist (case '((python-mode . t) (emacs-lisp-mode . t) (lisp-data-mode . t)
                  (js-mode . t) (makefile-mode . nil) (text-mode . nil)
                  (fundamental-mode . nil)))
    (with-temp-buffer
      (funcall (car case))
      (should (eq (and (+my/sticky--supported-p) t) (cdr case)))))
  (when (treesit-language-available-p 'python)
    (with-temp-buffer
      (python-ts-mode)
      (should (+my/sticky--supported-p)))))

(ert-deftest sticky/on-in-code-files ()
  "On in code files whose scopes can be told; not in other buffers."
  (+test-sticky "sticky-on/a.py" "x = 1\n" #'python-mode
    (should +my/sticky-header-mode)
    (should (local-variable-p 'header-line-format)))
  (+test-sticky "sticky-on/a.el" "(setq x 1)\n" #'emacs-lisp-mode
    (should +my/sticky-header-mode))
  ;; No notion of scopes: no header row at all.
  (+test-sticky "sticky-on/Makefile" "all:\n\techo\n" #'makefile-mode
    (should-not +my/sticky-header-mode)
    (should-not (local-variable-p 'header-line-format)))
  ;; Not a code mode.
  (+test-sticky "sticky-on/a.txt" "text\n" #'text-mode
    (should-not +my/sticky-header-mode))
  ;; Not a file.
  (+test-with-reset
    (with-current-buffer (+test-buffer "sticky-no-file" "x = 1\n" #'python-mode)
      (should-not +my/sticky-header-mode))))

(ert-deftest sticky/not-in-html ()
  "web-mode has no notion of scopes: no header row."
  (skip-unless (require 'web-mode nil t))
  (+test-sticky "sticky-on/page.html" "<html><body><p>x</p></body></html>\n" #'web-mode
    (should (derived-mode-p 'prog-mode))
    (should-not +my/sticky-header-mode)
    (should-not (local-variable-p 'header-line-format))))

(ert-deftest sticky/not-in-so-long-mode ()
  "Files with very long lines (so-long-mode replaces their mode): no header row."
  (require 'so-long)
  (+test-sticky "sticky-on/long.py" (concat "x = '" (make-string 300 ?a) "'\n") #'python-mode
    (should +my/sticky-header-mode)
    (so-long-mode)
    (should-not +my/sticky-header-mode)
    (should-not (local-variable-p 'header-line-format))))

(ert-deftest sticky/hooks ()
  (should (memq #'+my/sticky-header-maybe-h (default-value 'prog-mode-hook)))
  (should (memq #'+my/sticky-header-maybe-h (default-value 'markdown-ts-mode-hook))))

;; ====== END TO END ======

(ert-deftest sticky/kotlin-classes-and-functions ()
  "Kotlin (its node types from our list): e.g. \"class Api { › fun call(x: Int) {\"."
  (+test-sticky--needs kotlin)
  (skip-unless (fboundp 'kotlin-ts-mode))
  (+test-sticky "sticky/Api.kt" +test-sticky--kotlin #'kotlin-ts-mode
    (setq-local display-line-numbers nil)
    (should +my/sticky-header-mode)
    (dolist (case '((3 . "class Api { › companion object {")
                    (6 . "class Api { › fun call(x: Int) {")
                    (5 . "class Api {")
                    (11 . "object Single { › fun go() {")))
      (set-window-start nil (+test-sticky--goto-line (car case)))
      (should (equal (substring-no-properties (+my/sticky-header)) (cdr case))))))

(ert-deftest sticky/markdown-headings ()
  "Markdown: the headings, e.g. \"# Guide › ## Setup › ### Install\"; in a code
block too."
  (+test-sticky--needs markdown markdown-inline)
  (+test-sticky "sticky/guide.md" +test-sticky--markdown #'markdown-ts-mode
    (setq-local display-line-numbers nil)
    (should +my/sticky-header-mode)
    (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) default-directory)))
      (dolist (case '((1 . "guide.md")
                      (3 . "# Guide")
                      (5 . "# Guide")
                      (7 . "# Guide › ## Setup")
                      (11 . "# Guide › ## Setup › ### Install")
                      (15 . "# Guide › ## Setup › ### Install")
                      (19 . "# Guide › ## Usage")))
        (set-window-start nil (+test-sticky--goto-line (car case)))
        (should (equal (substring-no-properties (+my/sticky-header)) (cdr case)))))))

(ert-deftest sticky/dockerfile-stages ()
  "A Dockerfile (its outline Emacs's, from its Imenu): the stage a line is in,
its FROM line; a flat outline, its lines after it, not in it. Before the
first stage, and on a FROM line: the path."
  (+test-sticky--needs dockerfile)
  (skip-unless (require 'dockerfile-ts-mode nil t))
  (+test-sticky "sticky/Dockerfile" +test-sticky--dockerfile #'dockerfile-ts-mode
    (setq-local display-line-numbers nil)
    (should +my/sticky-header-mode)
    (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) default-directory)))
      (dolist (case '((1 . "Dockerfile")
                      (2 . "Dockerfile")
                      (3 . "FROM golang:${GO} AS build")
                      (4 . "FROM golang:${GO} AS build")
                      (5 . "FROM golang:${GO} AS build")
                      (6 . "Dockerfile")
                      (7 . "FROM alpine:3.20")
                      (8 . "FROM alpine:3.20")))
        (set-window-start nil (+test-sticky--goto-line (car case)))
        (should (equal (cons (car case) (substring-no-properties (+my/sticky-header))) case))))))

(ert-deftest sticky/python-without-tree-sitter ()
  "A mode without tree-sitter: the enclosing defun only."
  (+test-sticky "sticky/plain.py" +test-sticky--python #'python-mode
    (setq-local display-line-numbers nil)
    (set-window-start nil (+test-sticky--goto-line 5))
    (should (equal (substring-no-properties (+my/sticky-header)) "def bar(self):"))))

;;; test-sticky.el ends here
