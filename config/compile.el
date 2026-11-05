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
(defvar +my/compile-idle-delay 2
  "Seconds of idleness before this config's functions get compiled.")

;; ====== CODE ======

(defvar +my/compile--pending t "Something loaded since the last pass.")

(defvar +my/compile--timer nil)

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

(defun +my/compile-config-functions-h ()
  (when +my/compile--pending
    (let ((fns (+my/compile--candidates))
          (byte-compile-warnings nil)
          (inhibit-message t))
      (while (and fns (not (input-pending-p)))
        (ignore-errors (byte-compile (pop fns))))
      (setq +my/compile--pending (and fns t)))))

(when (timerp +my/compile--timer)       ; reloading this file
  (cancel-timer +my/compile--timer))

(setq +my/compile--timer
      (run-with-idle-timer +my/compile-idle-delay t #'+my/compile-config-functions-h))

(add-hook 'after-load-functions
          (defun +my/compile-pending-h (&rest _)
            (setq +my/compile--pending t)))
