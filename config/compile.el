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
;; A catch: a `let' binding a package's variable, e.g. SPC g d's
;; (let ((magit-display-buffer-function ...)) ...), compiled before the package
;; loaded, binds a local instead (the compiler can't tell it's the package's):
;; the package never sees it, and SPC g d opened the diff in the same window.
;; So the variables a function binds that aren't known yet are noted, and when
;; one becomes known (its package loaded), the function goes back to its
;; source and is compiled again.
(defvar +my/compile-idle-delay 2
  "Seconds of idleness before this config's functions get compiled.")

;; ====== CODE ======

(defvar +my/compile--pending t "Something loaded since the last pass.")

(defvar +my/compile--timer nil)

(defvar +my/compile--watch (make-hash-table :test #'eq)
  "FUNCTION -> (SOURCE COMPILED VARIABLES): compiled while VARIABLES, which it
binds with `let', weren't known special variables (see above).")

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

(defun +my/compile--unknown-bindings (source)
  "The symbols SOURCE (an interpreted function) binds with `let' or `let*'
that aren't special variables now; `error' if its body can't be expanded."
  (let ((body (if (consp source) (nthcdr 3 source) (aref source 1)))
        (symbols nil))
    (cl-labels ((walk (form)
                  (when (consp form)
                    (when (and (memq (car form) '(let let*)) (listp (cadr form)))
                      (dolist (binding (cadr form))
                        (let ((symbol (if (consp binding) (car binding) binding)))
                          (when (and symbol (symbolp symbol)
                                     (not (special-variable-p symbol)))
                            (push symbol symbols)))))
                    (while (consp form)
                      (walk (car form))
                      (setq form (cdr form))))))
      (condition-case nil
          (walk (macroexpand-all (cons 'progn body)))
        (error (setq symbols 'error))))
    (if (eq symbols 'error) 'error (delete-dups symbols))))

(defun +my/compile--function (fn)
  "Byte-compile FN in place, noting the variables it binds that aren't known."
  (let* ((source (symbol-function fn))
         (unknown (+my/compile--unknown-bindings source)))
    (unless (eq unknown 'error)          ; left interpreted
      (byte-compile fn)
      (let ((compiled (symbol-function fn)))
        (if (and unknown (not (eq compiled source)))
            (puthash fn (list source compiled unknown) +my/compile--watch)
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
  "Functions compiled before a variable they bind became known: back to their
source, to be compiled again."
  (maphash (lambda (fn entry)
             (pcase-let ((`(,source ,compiled ,unknown) entry))
               (cond ((not (eq (symbol-function fn) compiled)) ; redefined since
                      (remhash fn +my/compile--watch))
                     ((seq-some #'special-variable-p unknown)
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
