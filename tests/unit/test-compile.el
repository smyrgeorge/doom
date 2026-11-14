;;; tests/unit/test-compile.el -*- lexical-binding: t; -*-
;; config/emacs/compile.el: this config's functions byte-compiled in place when
;; Emacs is idle (stopping at a key press), again after anything loads;
;; functions compiled before a variable they bind became special, or a function
;; they call became a macro (its package loaded), go back to their source.

(setq native-comp-enable-subr-trampolines nil) ; mocking `input-pending-p' compiles none
(+test-load "config/emacs")

;; ====== HELPERS ======

(defmacro +test-compile--isolated (&rest body)
  "BODY with its own watch list and pending flag."
  (declare (indent 0))
  `(let ((+my/compile--watch (make-hash-table :test #'eq))
         (+my/compile--pending nil)
         (byte-compile-warnings nil))
     ,@body))

(defun +test-compile--define (name &rest body)
  "Define NAME (no arguments) with BODY, interpreted (as Doom loads config
files: from source, lexical binding)."
  (eval `(defun ,name () ,@body) t)
  name)

(defun +test-compile--compiled-p (symbol)
  (compiled-function-p (symbol-function symbol)))

(defun +test-compile--load (name content)
  "Write CONTENT (lexical binding) to NAME in the temp folder and load it, as a
package loads (`after-load-functions' run)."
  (let ((file (+test-file name (concat ";;; -*- lexical-binding: t; -*-\n" content))))
    (load file nil t)
    file))

;; ====== SETTINGS AND TIMER ======

(ert-deftest compile/idle-delay-default ()
  (should (eql (default-value '+my/compile-idle-delay) 2)))

(ert-deftest compile/idle-timer ()
  "A repeating idle timer runs the pass after `+my/compile-idle-delay' s."
  (should (timerp +my/compile--timer))
  (should (memq +my/compile--timer timer-idle-list))
  (should (eq (timer--function +my/compile--timer) #'+my/compile-config-functions-h))
  (should (timer--repeat-delay +my/compile--timer))
  (should (= (float-time (timer--time +my/compile--timer)) +my/compile-idle-delay)))

(ert-deftest compile/reload-keeps-one-timer ()
  "Loading the file again replaces its timer (and hook) instead of adding one."
  (let ((old +my/compile--timer))
    (+test-load "config/emacs/compile")
    (should-not (memq old timer-idle-list))
    (should (memq +my/compile--timer timer-idle-list))
    (should (= (cl-count #'+my/compile-config-functions-h timer-idle-list
                         :key #'timer--function)
               1))
    (should (= (cl-count #'+my/compile-pending-h after-load-functions) 1))))

(ert-deftest compile/pending-at-start ()
  "The first pass compiles what the config defined."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config/emacs/compile.el" +test-root))
    (should (search-forward "(defvar +my/compile--pending t" nil t))))

(ert-deftest compile/after-load-marks-pending-and-rechecks ()
  (should (memq #'+my/compile-pending-h after-load-functions))
  (+test-compile--isolated
    (let ((rechecks 0))
      (cl-letf (((symbol-function '+my/compile--recheck) (lambda () (cl-incf rechecks))))
        (+test-compile--load "compile/any.el" "(defvar +test-compile-any 1)\n"))
      (should +my/compile--pending)
      (should (= rechecks 1)))))

;; ====== WHAT GETS COMPILED ======

(ert-deftest compile/interpreted-p ()
  (should-not (+my/compile--interpreted-p '+test-compile-never-defined))
  (+test-compile--define '+test-compile-interp 1)
  (should (+my/compile--interpreted-p '+test-compile-interp))
  (byte-compile '+test-compile-interp)
  (should-not (+my/compile--interpreted-p '+test-compile-interp))
  ;; Built-ins, macros and dynamic-binding code.
  (should-not (+my/compile--interpreted-p 'car))
  (should-not (+my/compile--interpreted-p 'when))
  (eval '(defun +test-compile-dynamic () 1) nil)
  (should (+my/compile--interpreted-p '+test-compile-dynamic)))

(ert-deftest compile/candidates-by-name ()
  "Interpreted functions named +my/... or +md-...; compiled ones left out."
  (+test-compile--define '+my/test-compile-cand 1)
  (+test-compile--define '+md-test-compile-cand 1)
  (+test-compile--define '+my-test-compile-cand 1)
  (+test-compile--define '+mdtest-compile-cand 1)
  (+test-compile--define 'my/test-compile-cand 1)
  (+test-compile--define '+my/test-compile-done 1)
  (byte-compile '+my/test-compile-done)
  (let ((candidates (+my/compile--candidates)))
    (should (memq '+my/test-compile-cand candidates))
    (should (memq '+md-test-compile-cand candidates))
    (should-not (memq '+my-test-compile-cand candidates))
    (should-not (memq '+mdtest-compile-cand candidates))
    (should-not (memq 'my/test-compile-cand candidates))
    (should-not (memq '+my/test-compile-done candidates))
    (should (equal candidates (delete-dups (copy-sequence candidates))))))

(ert-deftest compile/candidates-from-config-files ()
  "Any function a file of this config defines, whatever its name; not those of
files elsewhere."
  (let* ((doom-user-dir (+test-tmp-file "compile-config/"))
         (inside (+test-file "compile-config/config/extra.el"
                             ";;; -*- lexical-binding: t; -*-\n(defun test-compile-inside () 1)\n(defun +my/test-compile-inside2 () 2)\n"))
         (outside (+test-file "compile-elsewhere/pkg.el"
                              ";;; -*- lexical-binding: t; -*-\n(defun test-compile-outside () 1)\n")))
    (load inside nil t)
    (load outside nil t)
    (let ((candidates (+my/compile--candidates)))
      (should (memq 'test-compile-inside candidates))
      (should (memq '+my/test-compile-inside2 candidates))
      (should (= (cl-count '+my/test-compile-inside2 candidates) 1)) ; by name and file
      (should-not (memq 'test-compile-outside candidates)))
    ;; Compiled already: no longer a candidate.
    (byte-compile 'test-compile-inside)
    (should-not (memq 'test-compile-inside (+my/compile--candidates)))))

(ert-deftest compile/candidates-the-real-config ()
  "This config's own functions (compile.el's here) are candidates while
interpreted."
  (should (file-equal-p doom-user-dir +test-root))
  (let ((fn '+my/compile--recheck))
    (if (+my/compile--interpreted-p fn)
        (should (memq fn (+my/compile--candidates)))
      (should-not (memq fn (+my/compile--candidates))))))

;; ====== UNKNOWNS ======

(defvar +test-compile-special 1)

(ert-deftest compile/unknowns-let-bound-variables ()
  "Variables bound with let / let* that aren't special (yet)."
  (+test-compile--define '+test-compile-u1
                         '(let ((a 1) (+test-compile-special 2) b)
                            (let* ((c a) (d c)) (list a b c d))))
  (let ((unknowns (+my/compile--unknowns (symbol-function '+test-compile-u1))))
    (should (consp unknowns))
    (should (equal (sort (copy-sequence (car unknowns)) #'string<) '(a b c d)))
    (should-not (memq '+test-compile-special (car unknowns)))))

(ert-deftest compile/unknowns-undefined-calls ()
  "Functions called that aren't defined; quoted data isn't a call."
  (+test-compile--define '+test-compile-u2
                         '(progn (+test-compile-undefined-a 1)
                                 (car (+test-compile-undefined-b))
                                 '(+test-compile-quoted-call)
                                 (when t (+test-compile-undefined-c))
                                 (+test-compile-undefined-a 2)))
  (let ((calls (cdr (+my/compile--unknowns (symbol-function '+test-compile-u2)))))
    (should (memq '+test-compile-undefined-a calls))
    (should (memq '+test-compile-undefined-b calls))
    (should (memq '+test-compile-undefined-c calls))       ; inside a macro
    (should (= (cl-count '+test-compile-undefined-a calls) 1))
    (should-not (memq '+test-compile-quoted-call calls))
    (should-not (memq 'car calls))
    (should-not (memq 'when calls))
    (should-not (memq 'progn calls))))

(ert-deftest compile/unknowns-after-macro-expansion ()
  "Macros are expanded first: a let they expand to counts."
  (eval '(defmacro +test-compile-binding-macro (&rest body)
           `(let ((+test-compile-from-macro 1)) ,@body))
        t)
  (+test-compile--define '+test-compile-u3 '(+test-compile-binding-macro (ignore)))
  (let ((unknowns (+my/compile--unknowns (symbol-function '+test-compile-u3))))
    (should (memq '+test-compile-from-macro (car unknowns)))
    (should-not (memq '+test-compile-binding-macro (cdr unknowns)))))

(ert-deftest compile/unknowns-none ()
  (+test-compile--define '+test-compile-u4 '(list (car '(1)) +test-compile-special))
  (should (equal (+my/compile--unknowns (symbol-function '+test-compile-u4)) '(nil))))

(ert-deftest compile/unknowns-expansion-error ()
  "A body that can't be expanded: `error' (left interpreted)."
  (+test-compile--define '+test-compile-u5 '(+test-compile-broken-macro))
  (eval '(defmacro +test-compile-broken-macro () (error "Can't expand")) t)
  (should (eq (+my/compile--unknowns (symbol-function '+test-compile-u5)) 'error)))

(ert-deftest compile/unknowns-old-closure-format ()
  "Emacs before 30: interpreted functions are (closure ENV ARGS . BODY)."
  (let ((unknowns (+my/compile--unknowns
                   '(closure (t) (x) (let ((v x)) (+test-compile-undefined-old v))))))
    (should (equal (car unknowns) '(v)))
    (should (memq '+test-compile-undefined-old (cdr unknowns)))))

;; ====== COMPILING ONE ======

(ert-deftest compile/function-compiled-in-place ()
  (+test-compile--isolated
    (+test-compile--define '+test-compile-f1 '(+ 1 2))
    (+my/compile--function '+test-compile-f1)
    (should (+test-compile--compiled-p '+test-compile-f1))
    (should (= (+test-compile-f1) 3))
    ;; Nothing unknown: nothing to watch.
    (should-not (gethash '+test-compile-f1 +my/compile--watch))))

(ert-deftest compile/function-watched-when-unknowns ()
  "Compiled with unknowns: noted as (SOURCE COMPILED VARIABLES CALLS)."
  (+test-compile--isolated
    (+test-compile--define '+test-compile-f2
                           '(let ((+test-compile-not-yet 1)) (+test-compile-later +test-compile-not-yet)))
    (let ((source (symbol-function '+test-compile-f2)))
      (+my/compile--function '+test-compile-f2)
      (let ((entry (gethash '+test-compile-f2 +my/compile--watch)))
        (should entry)
        (should (eq (nth 0 entry) source))
        (should (eq (nth 1 entry) (symbol-function '+test-compile-f2)))
        (should (compiled-function-p (nth 1 entry)))
        (should (equal (nth 2 entry) '(+test-compile-not-yet)))
        ;; (The walk also takes a binding's (VAR VALUE) for a call: more
        ;; watched than needed, never less.)
        (should (memq '+test-compile-later (nth 3 entry)))))))

(ert-deftest compile/function-watch-entry-dropped-when-known ()
  "Compiled again with nothing unknown: no longer watched."
  (+test-compile--isolated
    (+test-compile--define '+test-compile-f3 '(+test-compile-f3-callee))
    (+my/compile--function '+test-compile-f3)
    (should (gethash '+test-compile-f3 +my/compile--watch))
    (+test-compile--define '+test-compile-f3-callee 1)
    (+test-compile--define '+test-compile-f3 '(+test-compile-f3-callee))
    (+my/compile--function '+test-compile-f3)
    (should-not (gethash '+test-compile-f3 +my/compile--watch))))

(ert-deftest compile/function-left-interpreted-on-expansion-error ()
  (+test-compile--isolated
    (+test-compile--define '+test-compile-f4 '(+test-compile-broken-macro2))
    (eval '(defmacro +test-compile-broken-macro2 () (error "Can't expand")) t)
    (let ((source (symbol-function '+test-compile-f4)))
      (+my/compile--function '+test-compile-f4)
      (should (eq (symbol-function '+test-compile-f4) source))
      (should-not (gethash '+test-compile-f4 +my/compile--watch)))))

(ert-deftest compile/function-not-changed-by-compiler ()
  "If the compiler left it as it was, nothing is watched."
  (+test-compile--isolated
    (+test-compile--define '+test-compile-f5 '(+test-compile-unknown-f5))
    (cl-letf (((symbol-function 'byte-compile) #'ignore))
      (+my/compile--function '+test-compile-f5))
    (should-not (gethash '+test-compile-f5 +my/compile--watch))))

;; ====== THE IDLE PASS ======

(defmacro +test-compile--pass-with (candidates &rest body)
  "BODY with CANDIDATES as the config's interpreted functions, `compiled'
listing what the pass compiled."
  (declare (indent 1))
  `(let ((compiled nil))
     (cl-letf (((symbol-function '+my/compile--candidates) (lambda () (copy-sequence ,candidates)))
               ((symbol-function '+my/compile--function) (lambda (fn) (push fn compiled))))
       ,@body)))

(ert-deftest compile/pass-only-when-pending ()
  (+test-compile--isolated
    (let ((asked nil))
      (cl-letf (((symbol-function '+my/compile--candidates) (lambda () (setq asked t) nil)))
        (+my/compile-config-functions-h))
      (should-not asked))))

(ert-deftest compile/pass-compiles-all-then-done ()
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (+test-compile--pass-with '(a b c)
      (cl-letf (((symbol-function 'input-pending-p) (lambda (&rest _) nil)))
        (+my/compile-config-functions-h))
      (should (equal (sort compiled #'string<) '(a b c))))
    (should-not +my/compile--pending)))

(ert-deftest compile/pass-stops-at-a-key-press ()
  "Input pending: stop, and go on at the next idle pass."
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (+test-compile--pass-with '(a b c d)
      (cl-letf (((symbol-function 'input-pending-p) (lambda (&rest _) (>= (length compiled) 2))))
        (+my/compile-config-functions-h))
      (should (= (length compiled) 2)))
    (should +my/compile--pending)
    ;; Next pass: the rest (no key pressed).
    (+test-compile--pass-with '(c d)
      (cl-letf (((symbol-function 'input-pending-p) (lambda (&rest _) nil)))
        (+my/compile-config-functions-h))
      (should (= (length compiled) 2)))
    (should-not +my/compile--pending)))

(ert-deftest compile/pass-key-pressed-before-start ()
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (+test-compile--pass-with '(a b)
      (cl-letf (((symbol-function 'input-pending-p) (lambda (&rest _) t)))
        (+my/compile-config-functions-h))
      (should-not compiled))
    (should +my/compile--pending)))

(ert-deftest compile/pass-nothing-to-compile ()
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (+test-compile--pass-with nil
      (+my/compile-config-functions-h)
      (should-not compiled))
    (should-not +my/compile--pending)))

(ert-deftest compile/pass-errors-skip-one-function ()
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (let ((compiled nil))
      (cl-letf (((symbol-function '+my/compile--candidates) (lambda () (list 'a 'bad 'c)))
                ((symbol-function '+my/compile--function)
                 (lambda (fn) (if (eq fn 'bad) (error "Boom") (push fn compiled))))
                ((symbol-function 'input-pending-p) (lambda (&rest _) nil)))
        (+my/compile-config-functions-h))
      (should (equal (sort compiled #'string<) '(a c))))
    (should-not +my/compile--pending)))

(ert-deftest compile/pass-is-quiet ()
  "No warnings and no messages while compiling."
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (let ((seen nil))
      (cl-letf (((symbol-function '+my/compile--candidates) (lambda () (list 'a)))
                ((symbol-function '+my/compile--function)
                 (lambda (_) (setq seen (list byte-compile-warnings inhibit-message))))
                ((symbol-function 'input-pending-p) (lambda (&rest _) nil)))
        (+my/compile-config-functions-h))
      (should (equal seen '(nil t))))))

(ert-deftest compile/pass-real ()
  "The real pass: interpreted config functions end up compiled, still
working; no .elc files written."
  (+test-compile--isolated
    (setq +my/compile--pending t)
    (+test-compile--define '+my/test-compile-real '(list 'real (+ 2 3)))
    (+my/compile-config-functions-h)
    (should (+test-compile--compiled-p '+my/test-compile-real))
    (should (equal (+my/test-compile-real) '(real 5)))
    (should-not +my/compile--pending)
    (should-not (directory-files (expand-file-name "config/" +test-root) nil "\\.elc\\'"))
    (should-not (file-exists-p (expand-file-name "config.elc" +test-root)))))

(ert-deftest compile/pass-again-after-a-package-loads ()
  "Functions defined when something loads (`after!' blocks) are compiled at
the next pass."
  (+test-compile--isolated
    (+test-compile--load "compile/pkg-after.el"
                         "(defun +my/test-compile-after-load () 'after)\n")
    (should +my/compile--pending)
    (should (+my/compile--interpreted-p '+my/test-compile-after-load))
    (+my/compile-config-functions-h)
    (should (+test-compile--compiled-p '+my/test-compile-after-load))
    (should (eq (+my/test-compile-after-load) 'after))))

;; ====== RECHECK ======

(ert-deftest compile/recheck-special-variable ()
  (+test-compile--isolated
    (+test-compile--define '+test-compile-r1 '(let ((+test-compile-r1-var 1)) +test-compile-r1-var))
    (let ((source (symbol-function '+test-compile-r1)))
      (+my/compile--function '+test-compile-r1)
      (+my/compile--recheck)                          ; nothing changed
      (should (+test-compile--compiled-p '+test-compile-r1))
      (should (gethash '+test-compile-r1 +my/compile--watch))
      (eval '(defvar +test-compile-r1-var nil))
      (+my/compile--recheck)
      (should (eq (symbol-function '+test-compile-r1) source))
      (should-not (gethash '+test-compile-r1 +my/compile--watch)))))

(ert-deftest compile/recheck-macro ()
  (+test-compile--isolated
    (+test-compile--define '+test-compile-r2 '(+test-compile-r2-later 1))
    (let ((source (symbol-function '+test-compile-r2)))
      (+my/compile--function '+test-compile-r2)
      (eval '(defun +test-compile-r2-later (x) x) t)  ; a function: fine
      (+my/compile--recheck)
      (should (+test-compile--compiled-p '+test-compile-r2))
      (eval '(defmacro +test-compile-r2-later (x) `(list 'macro ,x)) t)
      (+my/compile--recheck)
      (should (eq (symbol-function '+test-compile-r2) source))
      (should (equal (+test-compile-r2) '(macro 1)))
      (should-not (gethash '+test-compile-r2 +my/compile--watch)))))

(ert-deftest compile/recheck-redefined-since ()
  "Redefined since (e.g. the file reloaded): left alone, no longer watched."
  (+test-compile--isolated
    (+test-compile--define '+test-compile-r3 '(let ((+test-compile-r3-var 1)) +test-compile-r3-var))
    (+my/compile--function '+test-compile-r3)
    (+test-compile--define '+test-compile-r3 '(list 'new))
    (let ((new (symbol-function '+test-compile-r3)))
      (eval '(defvar +test-compile-r3-var nil))
      (+my/compile--recheck)
      (should (eq (symbol-function '+test-compile-r3) new))
      (should-not (gethash '+test-compile-r3 +my/compile--watch)))))

(ert-deftest compile/recheck-only-the-affected ()
  (+test-compile--isolated
    (+test-compile--define '+test-compile-r4a '(let ((+test-compile-r4-var 1)) +test-compile-r4-var))
    (+test-compile--define '+test-compile-r4b '(let ((+test-compile-r4-other 1)) +test-compile-r4-other))
    (+my/compile--function '+test-compile-r4a)
    (+my/compile--function '+test-compile-r4b)
    (eval '(defvar +test-compile-r4-var nil))
    (+my/compile--recheck)
    (should-not (+test-compile--compiled-p '+test-compile-r4a))
    (should (+test-compile--compiled-p '+test-compile-r4b))
    (should (gethash '+test-compile-r4b +my/compile--watch))))

;; ====== THE CATCHES (config/emacs/compile.el's comments) ======

(ert-deftest compile/let-binding-a-package-variable ()
  "SPC g d's catch: a function binding a package's variable, compiled before
the package loaded, bound a local; once the package loads it's back to its
source, and binds the package's variable again."
  (+test-compile--isolated
    (+test-compile--define '+my/test-compile-diff
                           '(let ((+test-compile-pkg-display 'mine))
                              (+test-compile-pkg-show)))
    (+my/compile--function '+my/test-compile-diff)
    (let ((compiled (symbol-function '+my/test-compile-diff)))
      (+test-compile--load "compile/pkg-display.el"
                           "(defvar +test-compile-pkg-display 'global)
(defun +test-compile-pkg-show () +test-compile-pkg-display)\n")
      ;; Compiled early, it would bind a local: the package never sees it.
      (should (eq (funcall compiled) 'global))
      ;; Back to its source: the package sees it.
      (should (+my/compile--interpreted-p '+my/test-compile-diff))
      (should (eq (+my/test-compile-diff) 'mine))
      ;; The next pass compiles it again, now right.
      (setq +my/compile--pending t)
      (+my/compile-config-functions-h)
      (should (+test-compile--compiled-p '+my/test-compile-diff))
      (should (eq (+my/test-compile-diff) 'mine)))))

(ert-deftest compile/call-to-a-package-macro ()
  "treemacs' catch: a call to a package's macro, compiled before the package
loaded, was a function call (invalid-function); once it loads, back to source."
  (+test-compile--isolated
    (+test-compile--define '+my/test-compile-refresh
                           '(+test-compile-pkg-each 5))
    (+my/compile--function '+my/test-compile-refresh)
    (let ((compiled (symbol-function '+my/test-compile-refresh)))
      (+test-compile--load "compile/pkg-macro.el"
                           "(defmacro +test-compile-pkg-each (n) `(list 'each ,n))\n")
      (should-error (funcall compiled))
      (should (+my/compile--interpreted-p '+my/test-compile-refresh))
      (should (equal (+my/test-compile-refresh) '(each 5)))
      (setq +my/compile--pending t)
      (+my/compile-config-functions-h)
      (should (+test-compile--compiled-p '+my/test-compile-refresh))
      (should (equal (+my/test-compile-refresh) '(each 5))))))
