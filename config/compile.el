;;; $DOOMDIR/config/compile.el -*- lexical-binding: t; -*-
;; Byte-compile this config's functions in the background. Loaded last from
;; config.el.

;; ====== VARIABLES ======

;; COMPILE
;; Doom loads config.el and config/*.el as source, so their functions ran
;; interpreted, several times slower than compiled: e.g. the stripe's redraw on
;; each frame of a scroll took 1.5 ms instead of 0.2. Once Emacs has been idle
;; for a moment they're byte-compiled in place, a few milliseconds each,
;; stopping at the first key press (no files written, so nothing gets stale).
;; Again after anything loads: functions in `after!' blocks are defined when
;; their package loads.
;;
;; A catch: compiled before a package loaded, code using it can go wrong,
;; where the interpreter (which looks at things as it runs) didn't:
;; - a `let' binding the package's variable, e.g. SPC g d's
;;   (let ((magit-display-buffer-function ...)) ...), binds a local instead
;;   (the compiler can't tell it's the package's): magit never saw it, and
;;   SPC g d opened the diff in the same window;
;; - a call to the package's macro, e.g. treemacs-run-in-every-buffer, is
;;   compiled as a function call: "Error running timer
;;   `+my/treemacs-refresh-all': (invalid-function ...)".
;; So the variables a function binds and the functions it calls that aren't
;; known yet are noted, and when one becomes a special variable or a macro (its
;; package loaded), the function goes back to its source and is compiled again.
(defvar +my/compile-idle-delay 2
  "Seconds of idleness before this config's functions get compiled.")

;; ====== CODE ======

(defvar +my/compile--pending t "Something loaded since the last pass.")

(defvar +my/compile--timer nil)

(defvar +my/compile--watch (make-hash-table :test #'eq)
  "FUNCTION -> (SOURCE COMPILED VARIABLES CALLS): compiled while VARIABLES,
which it binds with `let', weren't special variables, and CALLS, which it
calls, weren't defined (see above).")

(defun +my/compile--interpreted-p (symbol)
  (and (fboundp symbol)
       (let ((fn (symbol-function symbol)))
         (if (fboundp 'interpreted-function-p)
             (interpreted-function-p fn)
           (eq (car-safe fn) 'closure)))))

(defun +my/compile--candidates ()
  "This config's functions that still run interpreted."
  (let ((dir (file-name-as-directory (expand-file-name doom-user-dir)))
        (fns nil))
    (mapatoms (lambda (symbol)
                (when (and (string-match-p "\\`\\+\\(my/\\|md-\\)" (symbol-name symbol))
                           (+my/compile--interpreted-p symbol))
                  (push symbol fns))))
    (dolist (entry load-history)
      (when (and (stringp (car entry)) (string-prefix-p dir (car entry)))
        (dolist (item (cdr entry))
          (when (and (eq (car-safe item) 'defun)
                     (+my/compile--interpreted-p (cdr item)))
            (push (cdr item) fns)))))
    (delete-dups fns)))

(defun +my/compile--unknowns (source)
  "(VARIABLES . CALLS) for SOURCE (an interpreted function), its body's macros
expanded: the symbols it binds with `let' or `let*' that aren't special
variables, and those it calls that aren't defined; `error' if the body can't
be expanded."
  (let ((body (if (consp source) (nthcdr 3 source) (aref source 1)))
        (variables nil)
        (calls nil))
    (cl-labels ((walk (form)
                  (when (and (consp form) (not (eq (car form) 'quote)))
                    (let ((head (car form)))
                      (when (and (memq head '(let let*)) (listp (cadr form)))
                        (dolist (binding (cadr form))
                          (let ((symbol (if (consp binding) (car binding) binding)))
                            (when (and symbol (symbolp symbol)
                                       (not (special-variable-p symbol)))
                              (push symbol variables)))))
                      (when (and head (symbolp head) (not (fboundp head)))
                        (push head calls)))
                    (while (consp form)
                      (walk (car form))
                      (setq form (cdr form))))))
      (condition-case nil
          (progn (walk (macroexpand-all (cons 'progn body)))
                 (cons (delete-dups variables) (delete-dups calls)))
        (error 'error)))))

(defun +my/compile--function (fn)
  "Byte-compile FN in place, noting what it uses that isn't known yet."
  (let* ((source (symbol-function fn))
         (unknowns (+my/compile--unknowns source)))
    (unless (eq unknowns 'error)          ; left interpreted
      (byte-compile fn)
      (let ((compiled (symbol-function fn)))
        (if (and (or (car unknowns) (cdr unknowns)) (not (eq compiled source)))
            (puthash fn (list source compiled (car unknowns) (cdr unknowns))
                     +my/compile--watch)
          (remhash fn +my/compile--watch))))))

(defun +my/compile-config-functions-h ()
  (when +my/compile--pending
    (let ((fns (+my/compile--candidates))
          (byte-compile-warnings nil)
          (inhibit-message t))
      (while (and fns (not (input-pending-p)))
        (ignore-errors (+my/compile--function (pop fns))))
      (setq +my/compile--pending (and fns t)))))

(defun +my/compile--recheck ()
  "Functions compiled before a variable they bind or a macro they call became
known: back to their source, to be compiled again."
  (maphash (lambda (fn entry)
             (pcase-let ((`(,source ,compiled ,variables ,calls) entry))
               (cond ((not (eq (symbol-function fn) compiled)) ; redefined since
                      (remhash fn +my/compile--watch))
                     ((or (seq-some #'special-variable-p variables)
                          (seq-some #'macrop calls))
                      (fset fn source)
                      (remhash fn +my/compile--watch)))))
           +my/compile--watch))

(when (timerp +my/compile--timer)       ; reloading this file
  (cancel-timer +my/compile--timer))

(setq +my/compile--timer
      (run-with-idle-timer +my/compile-idle-delay t #'+my/compile-config-functions-h))

(add-hook 'after-load-functions
          (defun +my/compile-pending-h (&rest _)
            (setq +my/compile--pending t)
            (+my/compile--recheck)))
