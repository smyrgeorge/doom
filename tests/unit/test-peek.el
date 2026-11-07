;;; tests/unit/test-peek.el -*- lexical-binding: t; -*-
;; config/lsp/peek.el: lsp-ui's peek (usages with gD or Cmd+B on a declaration,
;; definitions...) made calmer and more informative: soft colours from the
;; theme, a title saying what's listed, each usage's function/class, line
;; numbers in the preview, key hints, as tall as the list needs, the
;; declaration left out of the usages.

;; `use-package!' (config/sticky.el...) reads it; not in tests/helper.el yet.
(defvar doom-disabled-packages nil)

;; config/sticky.el first, as config.el loads it: its tree-sitter helpers tell
;; which nodes are functions/classes.
(+test-load "config/sticky" "config/lsp")

;; Before lsp-ui loads (Doom loads it with the first language server).
(defconst +test-peek--before-load
  (list :loaded (featurep 'lsp-ui-peek)
        :faces-h (condition-case err (progn (+my/peek-faces-h) 'ok) (error err)))
  "lsp-ui-peek loaded yet, and what `+my/peek-faces-h' did then.")

(require 'python)
(require 'hl-line)                      ; Doom's: on in every buffer
(require 'doom-themes)                  ; `doom-darken', `doom-blend', `doom-color'

;; The grammars Doom built (read only).
(add-to-list 'treesit-extra-load-path
             (expand-file-name ".local/etc/tree-sitter" +test-doom-emacs-dir))

(defun +test-peek--doom-color (name &optional _type)
  "`doom-color' as doom-one answers it."
  (pcase name ('blue "#51afef") ('yellow "#ecbe7b")))

;; lsp-ui loads now, with a theme's colours: config/lsp/peek.el's `after!' block
;; runs.
(set-face-attribute 'default nil :background "#282c34" :foreground "#bbc2cf")
(cl-letf (((symbol-function 'doom-color) #'+test-peek--doom-color))
  (require 'lsp-ui))

(defconst +test-peek--at-load
  (list :list-width lsp-ui-peek-list-width
        :peek (face-background 'lsp-ui-peek-peek nil t)
        :list (face-background 'lsp-ui-peek-list nil t)
        :selection (face-background 'lsp-ui-peek-selection nil t))
  "The peek's settings right after lsp-ui-peek loaded.")

;; Doom's :ui indent-guides (not loaded here) redraws the bars under the peek's
;; overlay before it's hidden, without checking there is one.
(defvar +test-peek--restored nil "The overlay spans the indent bars were redrawn under.")

(defun +indent-guides--restore-after-lsp-ui-peek-a (&rest _)
  (push (cons (overlay-start lsp-ui-peek--overlay) (overlay-end lsp-ui-peek--overlay))
        +test-peek--restored))

;; ====== HELPERS ======

(defun +test-peek--loc (file line col end-line end-col)
  "An LSP Location in FILE (0-based lines and columns)."
  (lsp-make-location
   :uri (lsp--path-to-uri file)
   :range (lsp-make-range :start (lsp-make-position :line line :character col)
                          :end (lsp-make-position :line end-line :character end-col))))

(defun +test-peek--item (line &optional scope summary file)
  "A usage as lsp-ui lists it (LINE 0-based), in SCOPE."
  (append (list :line line :column 0 :file (or file "/p/a.py")
                :summary (or summary (format "  code%d  " line)))
          (and scope (list :scope scope))))

(defun +test-peek--rows (string)
  "STRING's lines, without text properties."
  (split-string (substring-no-properties string) "\n"))

(defun +test-peek--faces-at (pos string)
  "The faces at POS in STRING, as a list."
  (let ((face (get-text-property pos 'face string)))
    (if (and (consp face) (not (keywordp (car face)))) face (list face))))

(defun +test-peek--brightness (color)
  "R + G + B of COLOR, a #RRGGBB."
  (apply #'+ (mapcar (lambda (i) (string-to-number (substring color i (+ i 2)) 16))
                     '(1 3 5))))

(defun +test-peek--grammar (language)
  "Skip the test unless LANGUAGE's tree-sitter grammar is there."
  (unless (treesit-language-available-p language)
    (ert-skip (format "No %s grammar" language))))

;; Faces

(defconst +test-peek--saved-faces
  '((default :background :foreground)
    (lsp-ui-peek-peek :background)
    (lsp-ui-peek-list :background)
    (lsp-ui-peek-header :background)
    (+my/peek-separator :background :inherit :extend)
    (lsp-ui-peek-selection :background :foreground :weight)
    (lsp-ui-peek-highlight :background :foreground :box :distant-foreground)
    (lsp-ui-peek-line-number :foreground)
    (font-lock-comment-face :foreground)
    (hl-line :background :inherit))
  "The faces (and attributes) the tests change.")

(defmacro +test-peek--with-faces (&rest body)
  "BODY with `doom-color' answering as doom-one, the faces tests change
restored after."
  (declare (indent 0))
  `(let ((saved (mapcar (lambda (spec)
                          (cons (car spec)
                                (cl-loop for attr in (cdr spec)
                                         append (list attr (face-attribute (car spec) attr)))))
                        +test-peek--saved-faces)))
     (unwind-protect
         (cl-letf (((symbol-function 'doom-color) #'+test-peek--doom-color))
           ,@body)
       (dolist (entry saved)
         (apply #'set-face-attribute (car entry) nil (cdr entry))))))

;; A whole peek

(defconst +test-peek--main
  "def foo():\n    return 1\n\nfoo()\nfoo()\n\nclass K:\n    def m(self):\n        foo()\n        foo()\n")

(defconst +test-peek--other
  "# – Ελληνικά\nfrom main import foo\n\nX = foo()\n")

(defvar +test-peek--request nil "What was asked of the language server: (METHOD PARAMS).")

(defun +test-peek--close ()
  "Close the peek (as Esc does), no timer left behind."
  (lsp-ui-peek--disable)
  (cancel-function-timers #'lsp-ui-peek--disable))

(defmacro +test-peek--with-usages (locations &rest body)
  "BODY after gD on foo's declaration in main.py, the language server
answering LOCATIONS (a form; MAIN and OTHER are the paths of main.py and
other.py, in one project). The peek is closed after."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((main (file-truename (+test-file "peek/main.py" +test-peek--main)))
            (other (file-truename (+test-file "peek/other.py" +test-peek--other)))
            (+test-peek--request nil))
       (ignore other)
       (cl-letf (((symbol-function 'lsp-request)
                  (lambda (method params)
                    (setq +test-peek--request (list method params))
                    (vconcat ,locations)))
                 ((symbol-function 'lsp-workspace-root)
                  (lambda (&rest _) (file-name-directory main))))
         (let ((vc-handled-backends nil))
           (find-file main))
         (goto-char (point-min))
         (search-forward "def fo")
         (unwind-protect
             (progn (lsp-ui-peek-find-references)
                    ,@body)
           (+test-peek--close))))))

(defun +test-peek--shown ()
  "The peek's rows (its overlay's text), as a string with its properties."
  (overlay-get lsp-ui-peek--overlay 'after-string))

(defun +test-peek--usages-in-main ()
  "foo's usages in main.py, not in order, and one in other.py."
  (list (+test-peek--loc (file-truename (+test-tmp-file "peek/main.py")) 8 8 8 11)
        (+test-peek--loc (file-truename (+test-tmp-file "peek/main.py")) 3 0 3 3)
        (+test-peek--loc (file-truename (+test-tmp-file "peek/main.py")) 9 8 9 11)
        (+test-peek--loc (file-truename (+test-tmp-file "peek/main.py")) 4 0 4 3)
        (+test-peek--loc (file-truename (+test-tmp-file "peek/other.py")) 3 4 3 7)))

;; ====== SETTINGS ======

(ert-deftest peek/settings ()
  (should (= (default-value '+my/peek-min-height) 10))
  (should (= (default-value '+my/peek-scope-width) 24))
  ;; The peek's own: lsp-ui's 20 rows at most.
  (should (= (default-value 'lsp-ui-peek-peek-height) 20))
  (should (local-variable-if-set-p '+my/peek--symbol))
  (should (equal (face-default-spec '+my/peek-separator)
                 '((t :inherit lsp-ui-peek-header)))))

(ert-deftest peek/list-width-when-lsp-ui-loads ()
  "Room for the function column: 60 instead of lsp-ui's 50, set as it loads."
  (should-not (plist-get +test-peek--before-load :loaded))
  (should (= (eval (car (get 'lsp-ui-peek-list-width 'standard-value)) t) 50))
  (should (= (plist-get +test-peek--at-load :list-width) 60))
  (should (= lsp-ui-peek-list-width 60)))

(ert-deftest peek/advice-in-place ()
  (dolist (entry '((+my/peek-usages-a . lsp-ui-peek-find-references)
                   (+my/peek-remember-symbol-a . lsp-ui-peek--find-xrefs)
                   (+my/peek-fit-height-a . lsp-ui-peek--show)
                   (+my/peek-reset-height-a . lsp-ui-peek--peek-hide)
                   (+my/peek-decode-files-a . lsp-ui-peek--get-xrefs-in-file)
                   (+my/peek-file-mode-a . lsp-ui-peek--fontify-buffer)
                   (+my/peek-item-a . lsp-ui-peek--xref-make-item)
                   (+my/peek-insert-xrefs-a . lsp-ui-peek--insert-xrefs)
                   (+my/peek-frame-a . lsp-ui-peek--peek-new)
                   (+my/peek-footer-a . lsp-ui-peek--make-footer)
                   (+my/peek-separators-a . lsp-ui-peek--peek-new)
                   (+my/indent-guides-peek-guard-a . +indent-guides--restore-after-lsp-ui-peek-a)))
    (should (advice-member-p (car entry) (cdr entry)))))

;; ====== COLOURS ======

(ert-deftest peek/faces-before-lsp-ui-loads ()
  "Run (theme change) before lsp-ui-peek and doom-themes loaded: nothing to do."
  (should (eq (plist-get +test-peek--before-load :faces-h) 'ok)))

(ert-deftest peek/faces-set-when-lsp-ui-loads ()
  (should (equal (plist-get +test-peek--at-load :peek) (doom-darken "#282c34" 0.2)))
  (should (equal (plist-get +test-peek--at-load :list) (doom-darken "#282c34" 0.12)))
  (should (equal (plist-get +test-peek--at-load :selection)
                 (doom-blend "#51afef" (doom-darken "#282c34" 0.12) 0.3))))

(ert-deftest peek/faces-from-the-theme ()
  (+test-peek--with-faces
    (set-face-attribute 'default nil :background "#282c34")
    (set-face-attribute 'lsp-ui-peek-header nil :background "#3f444a")
    (set-face-attribute 'font-lock-comment-face nil :foreground "#5b6268")
    (+my/peek-faces-h)
    (let ((list (doom-darken "#282c34" 0.12))
          (peek (doom-darken "#282c34" 0.2)))
      (should (equal (face-background 'lsp-ui-peek-peek nil t) peek))
      (should (equal (face-background 'lsp-ui-peek-list nil t) list))
      ;; Clearly darker than the editor, the preview more than the list.
      (should (< (+test-peek--brightness peek) (+test-peek--brightness list)
                 (+test-peek--brightness "#282c34")))
      ;; The rows above and below: the colour of the peek's own bars.
      (should (equal (face-background '+my/peek-separator nil t) "#3f444a"))
      (should (eq (face-attribute '+my/peek-separator :inherit) 'unspecified))
      (should (eq (face-attribute '+my/peek-separator :extend) t))
      ;; Soft selection and matches (no bright blue boxes).
      (should (equal (face-background 'lsp-ui-peek-selection nil t) (doom-blend "#51afef" list 0.3)))
      (should (eq (face-attribute 'lsp-ui-peek-selection :foreground) 'unspecified))
      (should (eq (face-attribute 'lsp-ui-peek-selection :weight) 'unspecified))
      (should (equal (face-background 'lsp-ui-peek-highlight nil t) (doom-blend "#ecbe7b" list 0.25)))
      (dolist (attr '(:foreground :box :distant-foreground))
        (should (eq (face-attribute 'lsp-ui-peek-highlight attr) 'unspecified)))
      ;; Line numbers as dim as comments.
      (should (equal (face-foreground 'lsp-ui-peek-line-number nil t) "#5b6268")))))

(ert-deftest peek/faces-separator-without-a-bar-colour ()
  "The peek's bars have no colour of their own (a name, not #RRGGBB): darker
than the panel."
  (+test-peek--with-faces
    (set-face-attribute 'default nil :background "#282c34")
    (set-face-attribute 'lsp-ui-peek-header nil :background "white")
    (+my/peek-faces-h)
    (should (equal (face-background '+my/peek-separator nil t) (doom-darken "#282c34" 0.3)))))

(ert-deftest peek/faces-follow-theme-changes ()
  (should (memq #'+my/peek-faces-h doom-load-theme-hook))
  (+test-peek--with-faces
    (set-face-attribute 'lsp-ui-peek-header nil :background "white")
    (set-face-attribute 'default nil :background "#fafafa") ; a light theme
    (run-hooks 'doom-load-theme-hook)
    (should (equal (face-background 'lsp-ui-peek-peek nil t) (doom-darken "#fafafa" 0.2)))
    (should (equal (face-background 'lsp-ui-peek-list nil t) (doom-darken "#fafafa" 0.12)))
    (should (equal (face-background '+my/peek-separator nil t) (doom-darken "#fafafa" 0.3)))))

(ert-deftest peek/faces-editor-colour-unknown ()
  "The editor's background isn't #RRGGBB: the panel keeps its colours; the
selection still follows the list's."
  (+test-peek--with-faces
    (set-face-attribute 'lsp-ui-peek-peek nil :background "#101010")
    (set-face-attribute 'lsp-ui-peek-list nil :background "#181818")
    (set-face-attribute '+my/peek-separator nil :background "#202020")
    (set-face-attribute 'default nil :background "black")
    (+my/peek-faces-h)
    (should (equal (face-background 'lsp-ui-peek-peek nil t) "#101010"))
    (should (equal (face-background 'lsp-ui-peek-list nil t) "#181818"))
    (should (equal (face-background '+my/peek-separator nil t) "#202020"))
    (should (equal (face-background 'lsp-ui-peek-selection nil t) (doom-blend "#51afef" "#181818" 0.3)))
    (should (equal (face-background 'lsp-ui-peek-highlight nil t) (doom-blend "#ecbe7b" "#181818" 0.25)))))

(ert-deftest peek/faces-list-colour-unknown ()
  "Neither the editor's nor the list's background is #RRGGBB: nothing changes."
  (+test-peek--with-faces
    (set-face-attribute 'default nil :background "black")
    (set-face-attribute 'lsp-ui-peek-list nil :background "gray")
    (set-face-attribute 'lsp-ui-peek-selection nil :background "white" :foreground "black")
    (set-face-attribute 'lsp-ui-peek-highlight nil :background "yellow")
    (set-face-attribute 'lsp-ui-peek-line-number nil :foreground "grey25")
    (+my/peek-faces-h)
    (should (equal (face-background 'lsp-ui-peek-list nil t) "gray"))
    (should (equal (face-background 'lsp-ui-peek-selection nil t) "white"))
    (should (equal (face-foreground 'lsp-ui-peek-selection nil t) "black"))
    (should (equal (face-background 'lsp-ui-peek-highlight nil t) "yellow"))
    (should (equal (face-foreground 'lsp-ui-peek-line-number nil t) "grey25"))))

(ert-deftest peek/faces-without-doom-themes ()
  "Without doom-themes' colour functions, the faces are left alone."
  (dolist (missing '(doom-blend doom-color doom-darken))
    (+test-peek--with-faces
      (set-face-attribute 'default nil :background "#282c34")
      (set-face-attribute 'lsp-ui-peek-peek nil :background "#101010")
      (set-face-attribute 'lsp-ui-peek-selection nil :background "white")
      (cl-letf (((symbol-function missing) nil))
        (+my/peek-faces-h))
      (should (equal (face-background 'lsp-ui-peek-peek nil t) "#101010"))
      (should (equal (face-background 'lsp-ui-peek-selection nil t) "white")))))

(ert-deftest peek/faces-without-lsp-ui-faces ()
  "A theme loaded before lsp-ui-peek (its faces not defined yet): nothing to do."
  (+test-peek--with-faces
    (set-face-attribute 'default nil :background "#282c34")
    (set-face-attribute 'lsp-ui-peek-peek nil :background "#101010")
    (let ((facep (symbol-function 'facep)))
      (cl-letf (((symbol-function 'facep)
                 (lambda (face) (and (not (eq face 'lsp-ui-peek-selection)) (funcall facep face)))))
        (+my/peek-faces-h)))
    (should (equal (face-background 'lsp-ui-peek-peek nil t) "#101010"))))

;; ====== WHAT'S LISTED ======

(ert-deftest peek/usages-leave-out-the-declaration ()
  "gD asks the server for the usages without the declaration (lsp-ui passes
its argument on as \"exclude\": by default it included it)."
  (+test-with-reset
    (let ((file (file-truename (+test-file "peek/decl.py" "def foo():\n    pass\n")))
          (got nil))
      (with-current-buffer (+test-buffer "decl.py" "def foo():\n    pass\n" #'python-mode)
        (setq buffer-file-name file)
        (search-forward "fo")
        (cl-letf (((symbol-function 'lsp-ui-peek--find-xrefs)
                   (lambda (&rest args) (setq got args))))
          (should (commandp #'lsp-ui-peek-find-references))
          (call-interactively #'lsp-ui-peek-find-references)
          (should (eq (nth 0 got) 'foo))
          (should (equal (nth 1 got) "textDocument/references"))
          (should (eq (plist-get (plist-get (nth 2 got) :context) :includeDeclaration) :json-false))
          (should (equal (plist-get (nth 2 got) :position) '(:line 0 :character 6)))
          (should (string-suffix-p "/decl.py" (plist-get (plist-get (nth 2 got) :textDocument) :uri)))
          ;; lsp-ui's first argument changes nothing.
          (lsp-ui-peek-find-references t)
          (should (eq (plist-get (plist-get (nth 2 got) :context) :includeDeclaration) :json-false))
          ;; Extra parameters go first.
          (lsp-ui-peek-find-references nil '(:extra 1))
          (should (equal (seq-take (nth 2 got) 2) '(:extra 1)))
          (should (eq (plist-get (plist-get (nth 2 got) :context) :includeDeclaration) :json-false)))))))

(ert-deftest peek/remembers-the-symbol ()
  "The symbol the peek is about, plain (in Markdown it came with its
heading's face), set before the server is asked."
  (with-temp-buffer
    (cl-letf (((symbol-function 'lsp-ui-peek--get-references) #'ignore))
      (should-error (lsp-ui-peek--find-xrefs 'foo "textDocument/references" nil)
                    :type 'user-error)
      (should (equal +my/peek--symbol "foo"))
      (should (equal lsp-ui-peek--method "textDocument/references"))
      (should-error (lsp-ui-peek--find-xrefs (propertize "Setup" 'face 'bold) "textDocument/references" nil)
                    :type 'user-error)
      (should (equal +my/peek--symbol "Setup"))
      (should-not (text-properties-at 0 +my/peek--symbol))
      ;; Nothing at point.
      (should-error (lsp-ui-peek--find-xrefs nil "textDocument/references" nil) :type 'user-error)
      (should-not +my/peek--symbol))
    ;; The buffer's own.
    (should (local-variable-p '+my/peek--symbol)))
  (with-temp-buffer
    (should-not +my/peek--symbol)))

(ert-deftest peek/remember-symbol-numbers-and-strings ()
  (with-temp-buffer
    (+my/peek-remember-symbol-a 42 "m" nil)
    (should (equal +my/peek--symbol "42"))
    (+my/peek-remember-symbol-a "pattern" "workspace/symbol" nil)
    (should (equal +my/peek--symbol "pattern"))))

;; ====== HEIGHT ======

(defun +test-peek--fit (counts)
  "The height the peek gets for files with COUNTS usages (nil: no :count)."
  (with-temp-buffer
    (let* ((xrefs (cl-loop for count in counts for i from 1
                           collect (append (list :file (format "/p/%d.py" i))
                                           (and count (list :count count)))))
           (seen nil)
           (value (+my/peek-fit-height-a
                   (lambda (arg)
                     (should (eq arg xrefs))
                     (setq seen lsp-ui-peek-peek-height)
                     'shown)
                   xrefs)))
      (should (eq value 'shown))
      (should (local-variable-p 'lsp-ui-peek-peek-height))
      seen)))

(ert-deftest peek/height-fits-the-list ()
  "A row for the title, one per file and per usage, within 10 and 20 rows,
even (as lsp-ui wants it)."
  (should (= (+test-peek--fit nil) 10))
  (should (= (+test-peek--fit '(3)) 10))
  (should (= (+test-peek--fit '(3 3)) 10))      ; 1 + 2 + 6 = 9 rows: 10
  (should (= (+test-peek--fit '(4 3)) 12))      ; 10 rows: 11, made even
  (should (= (+test-peek--fit '(12)) 16))       ; 14 rows: 15, made even
  (should (= (+test-peek--fit '(13)) 16))
  (should (= (+test-peek--fit '(14)) 18))
  (should (= (+test-peek--fit '(17)) 20))
  (should (= (+test-peek--fit '(30)) 20))
  (should (= (+test-peek--fit '(10 10)) 20))
  (should (= (+test-peek--fit '(nil nil)) 10))) ; no count: no usages

(ert-deftest peek/height-settings ()
  (let ((+my/peek-min-height 11))
    (should (= (+test-peek--fit '(1)) 12)))     ; even
  (let ((+my/peek-min-height 4))
    (should (= (+test-peek--fit '(1)) 4)))
  ;; The most: lsp-ui's own height.
  (cl-letf (((default-value 'lsp-ui-peek-peek-height) 14))
    (should (= (+test-peek--fit '(30)) 14)))
  (cl-letf (((default-value 'lsp-ui-peek-peek-height) 21))
    (should (= (+test-peek--fit '(30)) 22))))   ; even, as lsp-ui makes it

(ert-deftest peek/height-from-the-default-not-the-last-peek ()
  (with-temp-buffer
    (setq-local lsp-ui-peek-peek-height 10)
    (let (seen)
      (+my/peek-fit-height-a (lambda (_) (setq seen lsp-ui-peek-peek-height))
                             (list (list :file "/p/a.py" :count 30)))
      (should (= seen 20)))))

(ert-deftest peek/height-back-when-closed ()
  (with-temp-buffer
    (setq-local lsp-ui-peek-peek-height 12)
    (lsp-ui-peek--peek-hide)
    (should-not (local-variable-p 'lsp-ui-peek-peek-height))
    (should (= lsp-ui-peek-peek-height 20))
    ;; Closing again (no peek): fine.
    (lsp-ui-peek--peek-hide)
    (should (= lsp-ui-peek-peek-height 20))))

;; ====== THE FUNCTION/CLASS OF EACH USAGE ======

(defun +test-peek--scope (mode text at &optional from)
  "What `+my/peek--scope-at' says in TEXT (in MODE, without its hooks) at the
start of the first AT, point at FROM (default: the buffer's start)."
  (with-temp-buffer
    (insert text)
    (delay-mode-hooks (funcall mode))
    (goto-char (point-min))
    (search-forward at)
    (let ((pos (match-beginning 0))
          (point (or from (point-min))))
      (goto-char point)
      (prog1 (+my/peek--scope-at pos)
        (should (= (point) point))))))

(ert-deftest peek/scope-emacs-lisp ()
  "Without tree-sitter: the enclosing defun (add-log)."
  (let ((text "(defun foo ()\n  (bar 1))\n\n;; end\n"))
    (should (equal (+test-peek--scope #'emacs-lisp-mode text "bar") "foo"))
    (should-not (+test-peek--scope #'emacs-lisp-mode text "end"))))

(ert-deftest peek/scope-python-without-tree-sitter ()
  (let ((text "X = 1\n\nclass Foo:\n    def bar(self):\n        return 1\n"))
    (should (equal (+test-peek--scope #'python-mode text "return") "Foo.bar"))
    ;; On the declaration's line: itself.
    (should (equal (+test-peek--scope #'python-mode text "def bar") "Foo.bar"))
    ;; Top level, no tree-sitter: no name.
    (should-not (+test-peek--scope #'python-mode text "1\n"))))

(ert-deftest peek/scope-python-tree-sitter ()
  "Nested scopes, outermost first; outside them, the top-level variable."
  (+test-peek--grammar 'python)
  (let ((text "X = 1\n\nclass Foo:\n    def bar(self):\n        return 1\n\nBIG = {\n  'a': 1,\n}\n\nprint(2)\n"))
    (should (equal (+test-peek--scope #'python-ts-mode text "return") "Foo.bar"))
    (should (equal (+test-peek--scope #'python-ts-mode text "return" (point-max)) "Foo.bar"))
    (should (equal (+test-peek--scope #'python-ts-mode text "'a'") "BIG"))
    (should (equal (+test-peek--scope #'python-ts-mode text "1\n") "X"))
    (should-not (+test-peek--scope #'python-ts-mode text "print"))))

(ert-deftest peek/scope-tree-sitter-name-fallbacks ()
  "The node's name field when the mode can't name it."
  (+test-peek--grammar 'python)
  (let ((text "class Foo:\n    def bar(self):\n        return 1\n"))
    (cl-letf (((symbol-function 'treesit-defun-name) #'ignore))
      (should (equal (+test-peek--scope #'python-ts-mode text "return") "Foo.bar")))
    (cl-letf (((symbol-function 'treesit-defun-name) (lambda (&rest _) (error "Boom"))))
      (should (equal (+test-peek--scope #'python-ts-mode text "return") "Foo.bar")))))

(ert-deftest peek/scope-kotlin ()
  "Kotlin (its mode doesn't declare its scopes: config/sticky.el's): classes,
functions, a nameless companion object left out."
  (unless (require 'kotlin-ts-mode nil t) (ert-skip "No kotlin-ts-mode"))
  (+test-peek--grammar 'kotlin)
  (let ((text "package x\n\nval BIG = mapOf(\n  1 to 2,\n)\n\nclass A {\n  companion object {\n    fun f() {\n      g()\n    }\n  }\n  fun h() = listOf(1).map { it + 1 }\n}\n\nprintln(1)\n"))
    (should (equal (+test-peek--scope #'kotlin-ts-mode text "g()") "A.f"))
    (should (equal (+test-peek--scope #'kotlin-ts-mode text "it + 1") "A.h"))
    (should (equal (+test-peek--scope #'kotlin-ts-mode text "1 to 2") "BIG"))
    (should-not (+test-peek--scope #'kotlin-ts-mode text "println"))
    ;; Named by its identifiers when the mode can't name it.
    (cl-letf (((symbol-function 'treesit-defun-name) #'ignore))
      (should (equal (+test-peek--scope #'kotlin-ts-mode text "g()") "A.f")))))

(ert-deftest peek/scope-without-config-sticky ()
  "Without config/sticky.el's tree-sitter helpers: add-log only, no
top-level names."
  (cl-letf (((symbol-function '+my/sticky--treesit-p) nil))
    (should (equal (+test-peek--scope #'emacs-lisp-mode "(defun foo ()\n  (bar))\n" "bar") "foo"))
    (when (treesit-language-available-p 'python)
      (should-not (+test-peek--scope #'python-ts-mode "X = 1\n" "1")))))

(ert-deftest peek/scope-add-log-failing ()
  (cl-letf (((symbol-function 'add-log-current-defun) (lambda () (error "Boom"))))
    (should-not (+test-peek--scope #'emacs-lisp-mode "(defun foo ()\n  (bar))\n" "bar"))))

;; ====== READING THE FILES WITH USAGES ======

(ert-deftest peek/files-read-decoded ()
  "A file with usages that isn't open shows its non-ASCII text as such."
  (let* ((file (file-truename (+test-file "peek/greek.py" "# Τιμή – foo\nfoo()\n")))
         (xrefs (cons file (list (+test-peek--loc file 0 9 0 12))))
         (literally (symbol-function 'insert-file-contents-literally))
         (items (lsp-ui-peek--get-xrefs-in-file xrefs)))
    (should (equal (plist-get (car items) :summary) "# Τιμή – foo"))
    (should (string-match-p "Τιμή – foo" (plist-get (car items) :chunk)))
    ;; Only while lsp-ui reads them.
    (should (eq (symbol-function 'insert-file-contents-literally) literally))
    ;; lsp-ui alone showed bytes.
    (let ((plain (funcall (advice--cd*r (symbol-function 'lsp-ui-peek--get-xrefs-in-file)) xrefs)))
      (should-not (string-match-p "–" (plist-get (car plain) :summary))))))

(ert-deftest peek/files-unreadable ()
  (should-error (lsp-ui-peek--get-xrefs-in-file
                 (list (+test-tmp-file "peek/missing.py")
                       (+test-peek--loc (+test-tmp-file "peek/missing.py") 0 0 0 1)))
                :type 'user-error))

(defvar +test-peek--evaluated nil "Set by a file's local variables, if applied.")

(defun +test-peek--boom-mode ()
  "A major mode that fails."
  (error "Boom"))

(ert-deftest peek/file-gets-its-mode-without-hooks ()
  "The file's major mode, from its name (no language server starts: no
hooks, no local variables)."
  (with-temp-buffer
    (insert "# -*- mode: emacs-lisp -*-\nx = 1\n\n# Local Variables:\n# eval: (setq +test-peek--evaluated t)\n# End:\n")
    (let ((ran nil)
          (lsp-ui-peek-fontify 'on-demand))
      (let ((python-mode-hook (list (lambda () (setq ran t))))
            (prog-mode-hook (list (lambda () (setq ran t)))))
        (lsp-ui-peek--fontify-buffer "/p/x.py"))
      (should (eq major-mode 'python-mode))
      (should-not ran)
      (should-not +test-peek--evaluated)
      (should-not buffer-file-name)
      (should (local-variable-p 'delay-mode-hooks)))))

(ert-deftest peek/file-mode-kept ()
  "A buffer lsp-ui gave a mode already keeps it."
  (with-temp-buffer
    (text-mode)
    (lsp-ui-peek--fontify-buffer "/p/x.py")
    (should (eq major-mode 'text-mode)))
  ;; lsp-ui fontifying everything sets the mode itself: once.
  (with-temp-buffer
    (insert "x = 1\n")
    (let* ((calls 0)
           (set-auto-mode (symbol-function 'set-auto-mode))
           (lsp-ui-peek-fontify 'always))
      (cl-letf (((symbol-function 'set-auto-mode)
                 (lambda (&rest args) (cl-incf calls) (apply set-auto-mode args))))
        (lsp-ui-peek--fontify-buffer "/p/x.py"))
      (should (eq major-mode 'python-mode))
      (should (= calls 1)))))

(ert-deftest peek/file-mode-failing ()
  (with-temp-buffer
    (let ((auto-mode-alist (cons '("\\.boom\\'" . +test-peek--boom-mode) auto-mode-alist)))
      (lsp-ui-peek--fontify-buffer "/p/x.boom")
      (should (eq major-mode 'fundamental-mode)))))

(ert-deftest peek/file-without-mode ()
  (with-temp-buffer
    (lsp-ui-peek--fontify-buffer "/p/notes")
    (should (eq major-mode 'fundamental-mode))))

;; ====== EACH USAGE ======

(defconst +test-peek--long-python
  (concat (mapconcat (lambda (i) (format "x%d = %d" i i)) (number-sequence 1 25) "\n")
          "\nclass Foo:\n    def bar(self):\n"
          (mapconcat (lambda (i) (format "        y%d = %d" i i)) (number-sequence 28 40) "\n")
          "\n")
  "Lines 1-25 top level, 26 class Foo, 27 def bar, 28-40 in bar.")

(defun +test-peek--make-item (line col)
  "lsp-ui's item for a usage at LINE (0-based), COL of `+test-peek--long-python'."
  (with-temp-buffer
    (insert +test-peek--long-python)
    (delay-mode-hooks (python-mode))
    (goto-char (point-min))
    (let ((lsp--peek-save-major-mode 'fundamental-mode)
          (item (lsp-ui-peek--xref-make-item "/p/a.py" (+test-peek--loc "/p/a.py" line col line (1+ col)))))
      (should (= (point) (point-min)))
      item)))

(defun +test-peek--line (n)
  "Line N (1-based) of `+test-peek--long-python'."
  (nth (1- n) (split-string +test-peek--long-python "\n")))

(ert-deftest peek/item-scope-and-first-line ()
  (let ((item (+test-peek--make-item 29 8)))  ; line 30, in Foo.bar
    (should (equal (plist-get item :scope) "Foo.bar"))
    (should (= (plist-get item :line) 29))
    ;; Where lsp-ui's preview (the chunk) starts.
    (should (= (plist-get item :first-line) 21))
    (should (equal (car (split-string (plist-get item :chunk) "\n")) (+test-peek--line 21)))))

(ert-deftest peek/item-near-the-top ()
  "The preview can't start before line 1; top level: no scope (no tree-sitter)."
  (let ((item (+test-peek--make-item 2 0)))
    (should (= (plist-get item :first-line) 1))
    (should (equal (car (split-string (plist-get item :chunk) "\n")) (+test-peek--line 1)))
    (should-not (plist-member item :scope))))

(ert-deftest peek/item-first-line-follows-the-height ()
  (dolist (height '(14 15))                     ; odd: as lsp-ui cuts it
    (let* ((lsp-ui-peek-peek-height height)
           (item (+test-peek--make-item 29 8)))
      (should (= (plist-get item :first-line) 24))
      (should (equal (car (split-string (plist-get item :chunk) "\n")) (+test-peek--line 24))))))

(ert-deftest peek/item-columns ()
  "Past the line's end, or no column: the line's own scope."
  (with-temp-buffer
    (insert "class Foo:\n    def bar(self):\n        x\n")
    (delay-mode-hooks (python-mode))
    (should (equal (plist-get (+my/peek-item-a (list :line 2 :column 999)) :scope) "Foo.bar"))
    (should (equal (plist-get (+my/peek-item-a (list :line 2)) :scope) "Foo.bar"))
    ;; Past the end of the buffer.
    (should (plist-get (+my/peek-item-a (list :line 99 :column 0)) :first-line))))

(ert-deftest peek/item-scope-failing ()
  (with-temp-buffer
    (insert "x\n")
    (cl-letf (((symbol-function '+my/peek--scope-at) (lambda (_) (error "Boom"))))
      (let ((item (+my/peek-item-a (list :line 0 :column 0))))
        (should-not (plist-member item :scope))
        (should (= (plist-get item :first-line) 1))))))

;; ====== THE LIST ======

(ert-deftest peek/fit ()
  (should (equal (+my/peek--fit "abc" 5) "abc  "))
  (should (equal (+my/peek--fit "abcde" 5) "abcde"))
  (should (equal (+my/peek--fit "abcdefgh" 5) "abcd…"))
  (should (equal (+my/peek--fit "日本語の" 5) "日本…"))
  (should (equal (+my/peek--fit "" 3) "   ")))

(ert-deftest peek/ref-lines-group-by-function ()
  "The function/class on the first usage of each run, ×N when it has several."
  (let ((lines (+my/peek--ref-lines
                (list (+test-peek--item 0 "A") (+test-peek--item 1 "A") (+test-peek--item 2 "B")
                      (+test-peek--item 3) (+test-peek--item 4 "A")))))
    (should (equal (mapcar #'substring-no-properties lines)
                   '("1  A ×2  code0"
                     "2        code1"
                     "3  B     code2"
                     "4        code3"
                     "5  A     code4")))))

(ert-deftest peek/ref-lines-without-functions ()
  "No usage in a function: no column, no ×N."
  (should (equal (mapcar #'substring-no-properties
                         (+my/peek--ref-lines (list (+test-peek--item 0) (+test-peek--item 1))))
                 '("1  code0" "2  code1")))
  (should (equal (mapcar #'substring-no-properties
                         (+my/peek--ref-lines (list (+test-peek--item 0 "") (+test-peek--item 1 ""))))
                 '("1  code0" "2  code1")))
  (should-not (+my/peek--ref-lines nil)))

(ert-deftest peek/ref-lines-function-column-width ()
  "At most `+my/peek-scope-width' columns, cut with …"
  (let ((lines (+my/peek--ref-lines
                (list (+test-peek--item 0 "VeryLongClassName.veryLongMethodName")
                      (+test-peek--item 1 "Short")))))
    (should (equal (mapcar #'substring-no-properties lines)
                   (list "1  VeryLongClassName.veryL…  code0"
                         (concat "2  Short" (make-string 19 ?\s) "  code1")))))
  (let ((+my/peek-scope-width 6))
    (should (equal (mapcar #'substring-no-properties
                           (+my/peek--ref-lines (list (+test-peek--item 0 "Foo.bar") (+test-peek--item 1 "Foo.bar")
                                                      (+test-peek--item 2 "K.m") (+test-peek--item 3 "K.m"))))
                   '("1  Foo.b…  code0" "2          code1" "3  K.m ×2  code2" "4          code3")))))

(ert-deftest peek/ref-lines-number-width ()
  "Line numbers (1-based) right-aligned to the widest."
  (should (equal (mapcar #'substring-no-properties
                         (+my/peek--ref-lines (list (+test-peek--item 8) (+test-peek--item 9))))
                 '(" 9  code8" "10  code9")))
  (should (equal (mapcar #'substring-no-properties
                         (+my/peek--ref-lines (list (+test-peek--item 7) (+test-peek--item 99))))
                 '("  8  code7" "100  code99"))))

(ert-deftest peek/ref-lines-properties ()
  "Each line knows its usage and file (lsp-ui moves through them so)."
  (let* ((items (list (+test-peek--item 0 "A") (+test-peek--item 1 "A")))
         (lines (+my/peek--ref-lines (copy-tree items))))
    (cl-loop for line in lines for item in items
             do (should (equal (get-text-property 0 'lsp-ui-peek line) item))
             (should (equal (get-text-property 0 'file line) "/p/a.py"))
             (should (memq 'lsp-ui-peek-line-number (+test-peek--faces-at 0 line))))
    (should (memq 'font-lock-function-name-face (+test-peek--faces-at 3 (car lines))))
    (should-not (memq 'font-lock-function-name-face
                      (+test-peek--faces-at (- (length (car lines)) 1) (car lines))))))

(ert-deftest peek/insert-xrefs-in-line-order ()
  "Opening a file in the list: its usages in line order, with their functions,
under it; the file marked open."
  (with-temp-buffer
    (let ((got nil))
      (setq lsp-ui-peek--list (list (propertize "a.py 3" 'file "/p/a.py" 'xrefs '(x1 x2 x3))
                                    (propertize "b.py 1" 'file "/p/b.py" 'xrefs '(y1)))
            lsp-ui-peek--selection 0)
      (cl-letf (((symbol-function 'lsp-ui-peek--get-xrefs-in-file)
                 (lambda (file)
                   (setq got file)
                   (list (+test-peek--item 7 "B") (+test-peek--item 2 "A") (+test-peek--item 3 "A")))))
        (lsp-ui-peek--insert-xrefs '(x1 x2 x3) "/p/a.py" 0))
      (should (equal got '("/p/a.py" x1 x2 x3)))
      (should (equal (mapcar #'substring-no-properties lsp-ui-peek--list)
                     '("a.py 3" "3  A ×2  code2" "4        code3" "8  B     code7" "b.py 1")))
      (should-not (get-text-property 0 'xrefs (nth 0 lsp-ui-peek--list)))
      (should (equal (get-text-property 0 'xrefs (nth 4 lsp-ui-peek--list)) '(y1)))
      (should (equal (plist-get (get-text-property 0 'lsp-ui-peek (nth 1 lsp-ui-peek--list)) :line) 2)))))

(ert-deftest peek/insert-xrefs-second-file ()
  (with-temp-buffer
    (setq lsp-ui-peek--list (list (propertize "a.py 1" 'file "/p/a.py")
                                  (propertize "1  code0" 'lsp-ui-peek '(:line 0))
                                  (propertize "b.py 2" 'file "/p/b.py" 'xrefs '(y1 y2)))
          lsp-ui-peek--selection 2)
    (cl-letf (((symbol-function 'lsp-ui-peek--get-xrefs-in-file)
               (lambda (_) (list (+test-peek--item 5 nil nil "/p/b.py") (+test-peek--item 1 nil nil "/p/b.py")))))
      (lsp-ui-peek--insert-xrefs '(y1 y2) "/p/b.py" 2))
    (should (equal (mapcar #'substring-no-properties lsp-ui-peek--list)
                   '("a.py 1" "1  code0" "b.py 2" "2  code1" "6  code5")))
    (should (equal (get-text-property 0 'file (nth 3 lsp-ui-peek--list)) "/p/b.py"))))

;; ====== TITLE ======

(defun +test-peek--title (method symbol size files)
  "The title for SIZE usages in FILES files, found with METHOD about SYMBOL."
  (with-temp-buffer
    (setq lsp-ui-peek--method method
          +my/peek--symbol symbol
          lsp-ui-peek--size-list size
          lsp-ui-peek--list (append (cl-loop repeat files collect (copy-sequence "file"))
                                    (cl-loop repeat size collect
                                             (propertize "usage" 'lsp-ui-peek '(:line 0)))))
    (+my/peek--title)))

(ert-deftest peek/title-says-what-is-listed ()
  (should (equal (+test-peek--title "textDocument/references" "HOLD1" 22 1)
                 " Usages of HOLD1 · 22 in 1 file"))
  (should (equal (+test-peek--title "textDocument/definition" "foo" 1 1)
                 " Definitions of foo · 1 in 1 file"))
  (should (equal (+test-peek--title "textDocument/implementation" "Shape" 3 2)
                 " Implementations of Shape · 3 in 2 files"))
  ;; Others: their method's last part.
  (should (equal (+test-peek--title "workspace/symbol" "Foo" 4 3)
                 " Symbol of Foo · 4 in 3 files"))
  (should (equal (+test-peek--title "custom/callers" "foo" 2 1)
                 " Callers of foo · 2 in 1 file")))

(ert-deftest peek/title-without-symbol ()
  (should (equal (+test-peek--title "textDocument/references" nil 5 2)
                 " Usages · 5 in 2 files"))
  (should (equal (+test-peek--title "textDocument/references" nil 0 0)
                 " Usages · 0 in 0 files")))

(ert-deftest peek/title-counts-hidden-usages ()
  "Files whose usages are hidden (closed in the list) still count."
  (with-temp-buffer
    (setq lsp-ui-peek--method "textDocument/references"
          +my/peek--symbol "x"
          lsp-ui-peek--size-list 2
          lsp-ui-peek--list (list "a.py 1"
                                  (propertize "1 x" 'lsp-ui-peek '(:line 0) 'lsp-ui-peek-hidden t)
                                  "b.py 1"))
    (should (equal (+my/peek--title) " Usages of x · 2 in 2 files"))))

;; ====== PREVIEW ======

(defun +test-peek--preview (first usage count height &optional lines)
  "The preview of a usage at USAGE (1-based), its chunk COUNT lines from
FIRST (\"lN\" each, or LINES), the peek HEIGHT rows tall."
  (let ((lsp-ui-peek-peek-height height)
        (xref (list :file "/p/a.py" :line (1- usage) :first-line first)))
    (cl-letf (((symbol-function 'lsp-ui-peek--get-selection) (lambda () xref))
              ((symbol-function 'lsp-ui--workspace-path) #'file-name-nondirectory))
      (+my/peek--preview
       (cons " /p/a.py" (or lines (cl-loop for n from first repeat count collect (format "l%d" n))))))))

(ert-deftest peek/preview-numbers-the-lines ()
  (let ((preview (+test-peek--preview 1 4 20 10)))
    ;; The header says where.
    (should (equal (car preview) " a.py:4"))
    ;; As many lines as the peek has rows (its title row aside).
    (should (equal (mapcar #'substring-no-properties (cdr preview))
                   '("1 l1" "2 l2" "3 l3" "4 l4" "5 l5" "6 l6" "7 l7" "8 l8" "9 l9")))))

(ert-deftest peek/preview-centred-on-the-usage ()
  (let ((preview (+test-peek--preview 11 20 20 10)))
    (should (equal (car preview) " a.py:20"))
    (should (equal (mapcar #'substring-no-properties (cdr preview))
                   '("16 l16" "17 l17" "18 l18" "19 l19" "20 l20" "21 l21" "22 l22" "23 l23" "24 l24")))))

(ert-deftest peek/preview-at-the-chunk-end ()
  "Near the end, the window stays full: it starts earlier."
  (let ((preview (+test-peek--preview 81 99 20 10)))
    (should (equal (mapcar #'substring-no-properties (cdr preview))
                   '(" 92 l92" " 93 l93" " 94 l94" " 95 l95" " 96 l96" " 97 l97" " 98 l98" " 99 l99" "100 l100")))))

(ert-deftest peek/preview-number-width-of-the-last-line-shown ()
  "As wide as the last line shown's number (99: two columns, not three)."
  (let ((preview (+test-peek--preview 91 95 9 10)))
    (should (equal (mapcar #'substring-no-properties (cdr preview))
                   '("91 l91" "92 l92" "93 l93" "94 l94" "95 l95" "96 l96" "97 l97" "98 l98" "99 l99"))))
  (let ((preview (+test-peek--preview 2 5 9 10)))
    (should (equal (mapcar #'substring-no-properties (cdr preview))
                   '(" 2 l2" " 3 l3" " 4 l4" " 5 l5" " 6 l6" " 7 l7" " 8 l8" " 9 l9" "10 l10")))))

(ert-deftest peek/preview-short-chunk ()
  "Fewer lines than rows: all of them."
  (let ((preview (+test-peek--preview 1 2 5 10)))
    (should (equal (mapcar #'substring-no-properties (cdr preview))
                   '("1 l1" "2 l2" "3 l3" "4 l4" "5 l5"))))
  (let ((preview (+test-peek--preview 1 1 1 10)))
    (should (equal (mapcar #'substring-no-properties (cdr preview)) '("1 l1")))))

(ert-deftest peek/preview-highlights-the-usage-line ()
  (+test-peek--with-faces
    (set-face-attribute 'hl-line nil :background "#2c323c")
    (let* ((preview (+test-peek--preview 1 4 20 10))
           (usage (nth 4 preview))
           (other (nth 3 preview)))
      (should (memq 'line-number-current-line (+test-peek--faces-at 0 usage)))
      (should (member '(:background "#2c323c") (+test-peek--faces-at 0 usage)))
      (should (member '(:background "#2c323c") (+test-peek--faces-at 3 usage)))
      (should (memq 'line-number (+test-peek--faces-at 0 other)))
      (should-not (member '(:background "#2c323c") (+test-peek--faces-at 0 other)))
      (should-not (get-text-property 3 'face other)))))

(ert-deftest peek/preview-current-line-without-colour ()
  "hl-line without a background: the number still marks the line."
  (+test-peek--with-faces
    (set-face-attribute 'hl-line nil :background 'unspecified :inherit 'unspecified)
    (let ((usage (nth 4 (+test-peek--preview 1 4 20 10))))
      (should (equal (+test-peek--faces-at 0 usage) '(line-number-current-line)))
      (should-not (get-text-property 3 'face usage)))))

(ert-deftest peek/preview-taller-peek ()
  (let ((preview (+test-peek--preview 1 12 20 20)))
    ;; 19 rows, from line 2 (the chunk's last 19 lines: 12 is the 11th).
    (should (= (length (cdr preview)) 19))
    (should (equal (substring-no-properties (nth 1 preview)) " 2 l2"))
    (should (equal (substring-no-properties (car (last preview))) "20 l20"))))

(ert-deftest peek/preview-unchanged-without-a-usage ()
  "A file's line selected and no usage seen yet, or a usage without a line or
its preview's first line: lsp-ui's preview as it is."
  (let ((src (list " /p/a.py" "code")))
    (cl-letf (((symbol-function 'lsp-ui-peek--get-selection) #'ignore))
      (with-temp-buffer
        (should (eq (+my/peek--preview src) src))
        (setq lsp-ui-peek--last-xref (list :file "/p/a.py" :line 3))
        (should (eq (+my/peek--preview src) src))
        (setq lsp-ui-peek--last-xref (list :file "/p/a.py" :first-line 1))
        (should (eq (+my/peek--preview src) src))))))

(ert-deftest peek/preview-last-usage-seen ()
  "A file's line selected: the usage seen last."
  (cl-letf (((symbol-function 'lsp-ui-peek--get-selection) #'ignore)
            ((symbol-function 'lsp-ui--workspace-path) #'file-name-nondirectory))
    (with-temp-buffer
      (setq lsp-ui-peek--last-xref (list :file "/p/b.py" :line 1 :first-line 1))
      (let ((lsp-ui-peek-peek-height 10))
        (should (equal (car (+my/peek--preview (list " /p/b.py" "x" "y"))) " b.py:2"))))))

(ert-deftest peek/frame-title-over-the-list ()
  "lsp-ui's \"N references\" row becomes the title; the rest is kept."
  (with-temp-buffer
    (setq lsp-ui-peek--method "textDocument/references"
          +my/peek--symbol "foo"
          lsp-ui-peek--size-list 2
          lsp-ui-peek--list (list "a.py 2"
                                  (propertize "1 x" 'lsp-ui-peek '(:line 0))
                                  (propertize "2 y" 'lsp-ui-peek '(:line 1))))
    (let* ((src1 (list " /p/a.py" "code"))
           (src2 (list " 2 references" "a.py 2" "1 x" "2 y"))
           (args (+my/peek-frame-a (list src1 src2))))
      (should (= (length args) 2))
      (should (eq (nth 0 args) src1))       ; a file's line selected: as it was
      (should (equal (nth 1 args) (list " Usages of foo · 2 in 1 file" "a.py 2" "1 x" "2 y"))))))

;; ====== FOOTER, SEPARATORS ======

(ert-deftest peek/footer-shows-the-keys ()
  "The keys instead of an empty bar, in terminals too (lsp-ui showed none)."
  (should-not (display-graphic-p))
  (let ((footer (lsp-ui-peek--make-footer)))
    (should (= (length footer) 1))
    (let ((row (car footer)))
      (should (string-prefix-p
               "  j/k  next/previous   C-j/C-k  file   RET  open   M-RET  other window   Esc  close"
               row))
      (should (string-suffix-p "\n" row))
      (should (eq (get-text-property 2 'face row) 'lsp-ui-peek-footer))
      (should (eq (get-text-property (1- (length row)) 'face row) 'lsp-ui-peek-footer))
      ;; The bar across the window.
      (should (seq-find (lambda (i) (equal (get-text-property i 'display row)
                                           '(space :align-to (- right-fringe 0))))
                        (number-sequence 0 (1- (length row))))))))

(ert-deftest peek/footer-keys-are-the-peeks ()
  "What the footer lists is bound in the peek: lsp-ui's RET / M-RET, Doom's
j/k, C-j/C-k (its :tools lsp module)."
  (should (eq (lookup-key lsp-ui-peek-mode-map (kbd "RET")) #'lsp-ui-peek--goto-xref))
  (should (eq (lookup-key lsp-ui-peek-mode-map (kbd "M-RET")) #'lsp-ui-peek--goto-xref-other-window))
  (let ((file (car (append (file-expand-wildcards
                            (expand-file-name "sources/*/modules/tools/lsp/+lsp.el" +test-doom-emacs-dir))
                           (file-expand-wildcards
                            (expand-file-name "modules/tools/lsp/+lsp.el" +test-doom-emacs-dir))))))
    (unless file (ert-skip "Doom's :tools lsp module not found"))
    (let ((form (with-temp-buffer
                  (insert-file-contents file)
                  (and (search-forward "(map! :map lsp-ui-peek-mode-map" nil t)
                       (progn (goto-char (match-beginning 0)) (read (current-buffer)))))))
      (should form)
      (let ((noninteractive nil)) (eval form t))
      (should (eq (lookup-key lsp-ui-peek-mode-map "j") #'lsp-ui-peek--select-next))
      (should (eq (lookup-key lsp-ui-peek-mode-map "k") #'lsp-ui-peek--select-prev))
      (should (eq (lookup-key lsp-ui-peek-mode-map (kbd "C-j")) #'lsp-ui-peek--select-next-file))
      (should (eq (lookup-key lsp-ui-peek-mode-map (kbd "C-k")) #'lsp-ui-peek--select-prev-file)))))

(ert-deftest peek/separator-row ()
  (let ((row (+my/peek--separator)))
    (should (equal (substring-no-properties row) " \n"))
    (should (eq (get-text-property 0 'face row) '+my/peek-separator))
    (should (eq (get-text-property 1 'face row) '+my/peek-separator))
    (should (equal (get-text-property 0 'display row) '(space :align-to (- right-fringe 1))))))

(ert-deftest peek/separators-around-the-peek ()
  (with-temp-buffer
    (insert "a\nb\n")
    (setq lsp-ui-peek--overlay (make-overlay 3 3))
    (overlay-put lsp-ui-peek--overlay 'after-string "PEEK\n")
    (+my/peek-separators-a)
    (should (equal (substring-no-properties (overlay-get lsp-ui-peek--overlay 'after-string))
                   " \nPEEK\n \n"))
    (let ((shown (overlay-get lsp-ui-peek--overlay 'after-string)))
      (should (eq (get-text-property 0 'face shown) '+my/peek-separator))
      (should (eq (get-text-property (- (length shown) 2) 'face shown) '+my/peek-separator))
      (should-not (get-text-property 2 'face shown)))))

(ert-deftest peek/separators-without-a-peek ()
  (with-temp-buffer
    (setq lsp-ui-peek--overlay nil)
    (should-not (+my/peek-separators-a))
    (should-not lsp-ui-peek--overlay)))

;; ====== DOOM'S INDENT GUIDES ======

(ert-deftest peek/indent-guides-only-with-an-overlay ()
  (with-temp-buffer
    (insert "a\nb\n")
    (let ((+test-peek--restored nil))
      (setq lsp-ui-peek--overlay nil)
      (should-not (+indent-guides--restore-after-lsp-ui-peek-a))
      (should-not +test-peek--restored)
      (setq lsp-ui-peek--overlay (make-overlay 1 3))
      (+indent-guides--restore-after-lsp-ui-peek-a)
      (should (equal +test-peek--restored '((1 . 3)))))))

(ert-deftest peek/closing-twice-with-indent-guides ()
  "Closing hides the peek twice, the second time without its overlay: Doom's
indent guides redraw only the first time, no error."
  (advice-add 'lsp-ui-peek--peek-hide :before #'+indent-guides--restore-after-lsp-ui-peek-a)
  (unwind-protect
      (with-temp-buffer
        (insert "a\nb\n")
        (let ((+test-peek--restored nil))
          (setq lsp-ui-peek--overlay (make-overlay 3 3))
          (lsp-ui-peek--peek-hide)
          (lsp-ui-peek--peek-hide)
          (should (equal +test-peek--restored '((3 . 3))))
          (should-not lsp-ui-peek--overlay)))
    (advice-remove 'lsp-ui-peek--peek-hide #'+indent-guides--restore-after-lsp-ui-peek-a)))

;; ====== A WHOLE PEEK (gD) ======

(ert-deftest peek/usages-peek ()
  "gD on foo's declaration: its usages (the declaration left out), titled,
grouped by function, in a peek as tall as they need, with the keys."
  (+test-peek--with-usages (+test-peek--usages-in-main)
    (should (equal (car +test-peek--request) "textDocument/references"))
    (should (eq (plist-get (plist-get (cadr +test-peek--request) :context) :includeDeclaration)
                :json-false))
    (should (equal +my/peek--symbol "foo"))
    ;; 1 title + 2 files + 5 usages: 10 rows (the least).
    (should (= lsp-ui-peek-peek-height 10))
    (should (equal (mapcar #'substring-no-properties lsp-ui-peek--list)
                   '("main.py 4"
                     " 4          foo()"
                     " 5          foo()"
                     " 9  K.m ×2  foo()"
                     "10          foo()"
                     "other.py 1")))
    (let* ((shown (+test-peek--shown))
           (rows (+test-peek--rows shown)))
      ;; Separator, title, 9 rows, footer, separator.
      (should (= (cl-count ?\n shown) 13))
      (should (string-match-p "Usages of foo · 5 in 2 files" (nth 1 rows)))
      (should (string-match-p "j/k  next/previous" (nth 11 rows)))
      (should (eq (get-text-property 0 'face shown) '+my/peek-separator))
      (should (eq (get-text-property (1- (length shown)) 'face shown) '+my/peek-separator)))))

(ert-deftest peek/usages-peek-preview ()
  "The preview of the selected usage: where it is, numbered lines, its line
highlighted."
  (+test-peek--with-usages (+test-peek--usages-in-main)
    (let ((rows (+test-peek--rows (+test-peek--shown))))
      (should (string-prefix-p " main.py:4" (nth 1 rows)))
      (cl-loop for n from 1 to 9
               for row in (seq-subseq rows 2 11)
               do (should (string-prefix-p (format "%d %s" n (nth (1- n) (split-string +test-peek--main "\n")))
                                           row)))
      (let* ((shown (+test-peek--shown))
             (pos (string-match (concat "^" (regexp-quote "4 foo()")) shown)))
        (should (memq 'line-number-current-line (+test-peek--faces-at pos shown)))))))

(ert-deftest peek/usages-peek-moving ()
  "Moving to the next usage: its preview; still one separator above and below."
  (+test-peek--with-usages (+test-peek--usages-in-main)
    (lsp-ui-peek--select-next)
    (let* ((shown (+test-peek--shown))
           (rows (+test-peek--rows shown)))
      (should (string-prefix-p " main.py:5" (nth 1 rows)))
      (should (= (cl-count ?\n shown) 13))
      (should (= (cl-loop for i from 0 below (length shown)
                          count (and (eq (aref shown i) ?\n)
                                     (eq (get-text-property i 'face shown) '+my/peek-separator)))
                 2)))))

(ert-deftest peek/usages-peek-other-file ()
  "The next file's usages, read decoded from disk (it isn't open)."
  (+test-peek--with-usages (+test-peek--usages-in-main)
    (should-not (find-buffer-visiting other))
    (lsp-ui-peek--select-next-file)
    (should (member "4  X = foo()" (mapcar #'substring-no-properties lsp-ui-peek--list)))
    (let ((rows (+test-peek--rows (+test-peek--shown))))
      (should (string-prefix-p " other.py:4" (nth 1 rows)))
      (should (string-prefix-p "1 # – Ελληνικά" (nth 2 rows))))))

(ert-deftest peek/usages-peek-closed ()
  "Closed: the next peek's height starts from lsp-ui's again."
  (+test-peek--with-usages (+test-peek--usages-in-main)
    (should (local-variable-p 'lsp-ui-peek-peek-height))
    (+test-peek--close)
    (should-not (overlayp lsp-ui-peek--overlay))
    (should-not (local-variable-p 'lsp-ui-peek-peek-height))
    (should (= lsp-ui-peek-peek-height 20))))

(ert-deftest peek/usages-peek-many ()
  "Many usages: as tall as lsp-ui's peek, the list scrolls."
  (+test-peek--with-usages
      (cl-loop for i from 0 below 30
               collect (+test-peek--loc main (mod i 10) 0 (mod i 10) 1))
    (should (= lsp-ui-peek-peek-height 20))
    (should (string-match-p "Usages of foo · 30 in 1 file" (nth 1 (+test-peek--rows (+test-peek--shown)))))))

(ert-deftest peek/usages-peek-tree-sitter-scopes ()
  "With tree-sitter modes (Doom's), usages outside functions name their
top-level variable."
  (+test-peek--grammar 'python)
  (let ((major-mode-remap-alist '((python-mode . python-ts-mode))))
    (+test-peek--with-usages (+test-peek--usages-in-main)
      (lsp-ui-peek--select-next-file)
      (should (member "4  X  X = foo()" (mapcar #'substring-no-properties lsp-ui-peek--list))))))

;;; test-peek.el ends here
