;;; $DOOMDIR/config/beads/bd.el -*- lexical-binding: t; -*-
;; beads.el mended for bd 1.x (it was written for bd 0.49). Loaded from
;; config/beads.el.

;; BD 1.x
;; beads.el (0.1.0) was written for bd 0.49, which ran a daemon it talked to;
;; bd 1.x has none, only its command line (`bd ... --json'), where beads.el
;; trips: its arguments built with string keys but read with symbols (create,
;; update, close, labels, dependencies all failed), flags bd renamed, `bd
;; show' answering a list, `bd delete' only previewing without --force.
;; Mended here; the activity feed (`bd mutations')
;; and the merge conflicts view (`bd resolve-conflicts') are gone from bd and
;; say so. Only bd's command line is used (config/beads.el).
;; tests/unit/test-beads.el runs each against the real bd.
(defconst +my/beads--flags
  '(("--issue-type" . "--type")
    ("--acceptance-criteria" . "--acceptance"))
  "beads.el's flags bd renamed: (OLD . NEW).")

(defun +my/beads--symbol-keys-a (args)
  "`beads-backend-cli-execute''s ARGS (OPERATION ALIST ...) with ALIST's
keys symbols: beads.el's client makes them strings, its CLI reads symbols."
  (pcase-let ((`(,operation ,alist . ,rest) args))
    `(,operation
      ,(mapcar (lambda (pair)
                 (if (and (consp pair) (stringp (car pair)))
                     (cons (intern (car pair)) (cdr pair))
                   pair))
               alist)
      ,@rest)))

(defun +my/beads--flags-a (args)
  "bd's command line ARGS, with the flags bd renamed (see above); a delete
forced: without --force bd 1.x only previews it (and exits 0: beads.el said
\"Deleted\", nothing was), and beads.el has asked first."
  (let ((args (mapcar (lambda (arg) (or (cdr (assoc arg +my/beads--flags)) arg)) args)))
    (if (and (equal (car args) "delete") (not (member "--force" args)))
        (append args '("--force"))
      args)))

(defun +my/beads--no-daemon-a (flags)
  "beads.el's extra FLAGS, without --no-daemon (bd 1.x has no daemon, nor the flag)."
  (remove "--no-daemon" flags))

(defun +my/beads--one-issue-a (result)
  "`bd show''s RESULT, a list of the one issue: the issue."
  (if (and (consp result) (consp (car result)) (consp (caar result)))
      (car result)
    result))

(defun +my/beads--gone (what)
  (user-error "Beads: bd %s has no %s (beads.el was written for bd 0.49)"
              (or (ignore-errors (car (process-lines "bd" "version"))) "1.x")
              what))

(defun +my/beads-activity-a (&rest _)
  (+my/beads--gone "activity feed"))

(defun +my/beads-conflicts-a (&rest _)
  (+my/beads--gone "merge conflicts view (bd conflicts, in a terminal)"))

(after! beads-backend
  (advice-add 'beads-backend-cli-execute :filter-args #'+my/beads--symbol-keys-a))
(after! beads-backend-bd
  (advice-add 'beads-backend-bd--operation-to-cli-args :filter-return #'+my/beads--flags-a)
  (advice-add 'beads-backend-bd--cli-extra-flags :filter-return #'+my/beads--no-daemon-a))
(after! beads-client
  (advice-add 'beads-client-show :filter-return #'+my/beads--one-issue-a))
(advice-add 'beads-activity :override #'+my/beads-activity-a)
(advice-add 'beads-conflicts :override #'+my/beads-conflicts-a)
