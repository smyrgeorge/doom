;;; $DOOMDIR/config/agent-workflow/log.el -*- lexical-binding: t; -*-
;; A run's log, and what needs you said. Loaded from config/agent-workflow.el,
;; after watch.el. No Doom here.
;;
;; Each event of a run's journal is a line you read, appended to its log.txt
;; as it comes: the time, the issue, the job, what happened.
;;
;;   10:42:07  doom-a1b  review  waits for you: review: its result waits for
;;             your OK → agent-workflow approve doom-a1b, or reject doom-a1b NOTE
;;
;; cmd/agent-workflow logs reads it, and run follows it; the pane's Log
;; shows its last lines (`agent-workflow-log-functions'). The journal stays
;; the truth: log.txt is made again from it when it's gone.
;;
;; A run starting to wait for you (or for something else of yours) is said:
;; `agent-workflow-needs-you-functions' (config/notify/agent-workflow.el, a
;; notification while Emacs isn't in front).

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow-log-functions nil
  "Called with a run and a line of its log, once it's in its log.txt.")

(defvar agent-workflow-needs-you-functions nil
  "Called with a run and what it waits for you on (words), once it starts
waiting for you, or for something else.")

(defconst agent-workflow--log-name "log.txt" "A run's log, in its folder.")

;; ====== AN EVENT AS A LINE ======

(defun agent-workflow--log-hint (issue kind)
  "How to answer, from the shell, a run of ISSUE asking KIND: a job's
:ask's (a symbol; nil: the loop guard), `none' for a wait with no question."
  (pcase kind
    ('approve (format "agent-workflow approve %s, or reject %s NOTE" issue issue))
    ('nil (format "agent-workflow confirm %s go|accept|stop [--note-to JOB NOTE]" issue))
    ('budget (format "agent-workflow confirm %s go --more-cost N (or --more-tokens N, --more-time 1h), or stop"
                     issue))
    ((or 'merge 'moved 'protected) (format "agent-workflow confirm %s go|stop" issue))
    ('closed (format "agent-workflow confirm %s go|cancel" issue))
    ('none (format "agent-workflow continue %s, back %s JOB NOTE, or cancel %s" issue issue issue))
    (_ (format "agent-workflow confirm %s go|skip|stop" issue))))

(defun agent-workflow--log-value (value)
  "VALUE as the journal's data has it, JSON's null and false as nil."
  (if (memq value '(:null :false)) nil value))

(defun agent-workflow--log-what (issue event data kind)
  "What EVENT of ISSUE's run with DATA (a plist) says, in words; nil for
one the log leaves out. KIND: what a wait asks (`agent-workflow--log-hint')."
  (cl-flet ((get (key) (agent-workflow--log-value (plist-get data key)))
            (step () (format "step %d" (1+ (or (agent-workflow--log-value (plist-get data :step)) 0)))))
    (pcase event
      ("run-started" (format "started, with %s, by %s" (get :workflow) (or (get :by) "you")))
      ("state" (and (equal (get :state) "queued") (get :why) (format "queued: %s" (get :why))))
      ("job-started" "started")
      ("job-skipped" (if (get :if) (format "skipped (if: %s)" (string-trim (format "%s" (get :if)))) "skipped"))
      ("job-done" (concat "done"
                          (let ((outcome (get :outcome)))
                            (if (and outcome (not (equal outcome "done"))) (format ": %s" outcome) ""))
                          (if (get :accepted) ", accepted as it is" "")))
      ("step-started" (format "%s started%s" (step)
                              (cond ((get :agent) " (its agent)")
                                    ((get :kind) (format " (%s)" (get :kind)))
                                    (t ""))))
      ("step-ended" (format "%s done" (step)))
      ("step-skipped" (format "%s skipped" (step)))
      ("script-ended" (if (get :exit) (format "%s: its script exited %s" (step) (get :exit))
                        (format "%s: its script ended" (step))))
      ("fixing" (format "%s failed: its agent fixes it" (step)))
      ("waiting" (format "waits for you: %s → %s" (get :why) (agent-workflow--log-hint issue kind)))
      ("answered" (concat (format "%s, by %s" (get :choice) (or (get :by) "you"))
                          (if (get :note) (format ": %s" (get :note)) "")
                          (mapconcat (lambda (note)
                                       (format "; for %s: %s" (plist-get note :job) (plist-get note :note)))
                                     (append (get :notes) nil) "")))
      ("went-back" (concat (format "sent back to %s, by %s" (step) (or (get :by) "you"))
                           (if (get :note) (format ": %s" (get :note)) "")))
      ("rerun" (let ((edge (split-string (or (get :edge) ">") ">")))
                 (format "sent back by %s (round %s)" (car edge) (get :round))))
      ("interrupted" "interrupted")
      ("continued" (format "continued, by %s" (or (get :by) "you")))
      ("cancelled" (format "run cancelled, by %s" (or (get :by) "you")))
      ("run-done" "run done")
      ("merged" (format "%s merged into %s%s" (get :branch) (get :into) (if (get :already) " (it was)" "")))
      ("rebased" (format "rebased onto %s" (get :onto)))
      ("issue-changed" (format "its issue's %s changed" (get :what)))
      ("branch-moved" (format "its branch moved: the commits of %s are gone"
                              (string-join (mapcar (lambda (job) (format "%s" job)) (append (get :jobs) nil)) ", ")))
      ("budget-near" (format "near its budget: %s" (get :spent)))
      ("budget-used-up" (format "its budget is used up: %s" (get :spent)))
      ("budget-more" "its budget raised")
      ("restored" "read back: Emacs started again")
      ("workflow-changed" (format "now with %s as it is now" (get :workflow)))
      ((or "step-starting" "asked") nil)
      (_ event))))

(defun agent-workflow--log-line (issue event data time &optional kind)
  "EVENT of ISSUE's run with DATA, at TIME (a Lisp time), a line of its log;
nil if it says nothing (see `agent-workflow--log-what')."
  (when-let* ((what (agent-workflow--log-what issue event data kind)))
    (format "%s  %s  %s  %s" (format-time-string "%H:%M:%S" time) issue
            (or (agent-workflow--log-value (plist-get data :job)) "·")
            (replace-regexp-in-string "[\n\r]+" " " what))))

;; ====== ITS FILE ======

(defun agent-workflow--log-path (run)
  "RUN's log.txt."
  (expand-file-name agent-workflow--log-name (agent-workflow-run-dir run)))

(defun agent-workflow--log-append (file line)
  "LINE appended to FILE."
  (let ((coding-system-for-write 'utf-8-unix)
        (create-lockfiles nil))
    (write-region (concat line "\n") nil file t 'silent)))

(defun agent-workflow--journal-events (dir)
  "The events of the run in DIR, its journal's lines: plists (:t :ev ...),
a line that can't be read (half written) left out."
  (let ((file (expand-file-name "journal.jsonl" dir)))
    (when (file-readable-p file)
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents file))
        (delq nil (mapcar (lambda (line)
                            (ignore-errors
                              (json-parse-string line :object-type 'plist :array-type 'list
                                                 :null-object nil :false-object nil)))
                          (split-string (buffer-string) "\n" t)))))))

(defun agent-workflow--log-replay (issue events)
  "EVENTS of ISSUE's run (`agent-workflow--journal-events') as its log's
lines; a wait's hint from its job's last question."
  (let ((asked nil))
    (delq nil (mapcar (lambda (event)
                        (let ((name (plist-get event :ev))
                              (job (plist-get event :job)))
                          (pcase name
                            ("asked" (setf (alist-get job asked nil nil #'equal)
                                           (if (plist-get event :edge) 'guard
                                             (intern (or (plist-get event :kind) "none")))))
                            ("answered" (setf (alist-get job asked nil 'remove #'equal) nil)))
                          (agent-workflow--log-line issue name event
                                                    (or (ignore-errors (date-to-time (plist-get event :t)))
                                                        (current-time))
                                                    (let ((kind (alist-get job asked nil nil #'equal)))
                                                      (cond ((null kind) 'none) ((eq kind 'guard) nil) (t kind))))))
                      events))))

(defun agent-workflow-log-file (run)
  "RUN's log.txt, made from its journal if it isn't there."
  (let ((file (agent-workflow--log-path run)))
    (unless (file-exists-p file)
      (let ((coding-system-for-write 'utf-8-unix)
            (lines (agent-workflow--log-replay (agent-workflow-run-issue run)
                                               (agent-workflow--journal-events (agent-workflow-run-dir run)))))
        (write-region (mapconcat (lambda (line) (concat line "\n")) lines "") nil file nil 'silent)))
    file))

(defun agent-workflow-log-lines (run &optional count)
  "RUN's log's lines, its last COUNT of them (all: nil)."
  (let ((lines (with-temp-buffer
                 (let ((coding-system-for-read 'utf-8))
                   (insert-file-contents (agent-workflow-log-file run)))
                 (split-string (buffer-string) "\n" t))))
    (if count (last lines count) lines)))

(defun agent-workflow--log-event (run event data)
  "EVENT of RUN with DATA, in its journal now: its line appended to its log
\(made first from the journal if it's gone), said
\(`agent-workflow-log-functions'). In `agent-workflow-journal-functions'."
  (let* ((file (agent-workflow--log-path run))
         (fresh (not (file-exists-p file)))
         (job (plist-get data :job))
         (ask (and job (plist-get (agent-workflow--job run job) :ask)))
         (line (agent-workflow--log-line (agent-workflow-run-issue run) event data (current-time)
                                         (if ask (plist-get ask :kind) 'none))))
    (if fresh
        ;; Made from the journal: this event's in it already.
        (agent-workflow-log-file run)
      (when line (agent-workflow--log-append file line)))
    (when line
      (run-hook-with-args 'agent-workflow-log-functions run line))))

(add-hook 'agent-workflow-journal-functions #'agent-workflow--log-event)

;; ====== WHAT NEEDS YOU ======

(defvar agent-workflow--needs-said (make-hash-table :test #'eq :weakness 'key)
  "What each run waiting for you was said to wait on, last.")

(defun agent-workflow--needs-you-check (run)
  "RUN changed: waiting for you on something new, said
\(`agent-workflow-needs-you-functions'). In `agent-workflow-run-functions'."
  (if (not (eq (agent-workflow-run-state run) 'waiting))
      (remhash run agent-workflow--needs-said)
    (let ((why (or (agent-workflow-run-why run) "it waits for you")))
      (unless (equal (gethash run agent-workflow--needs-said) why)
        (puthash run why agent-workflow--needs-said)
        (run-hook-with-args 'agent-workflow-needs-you-functions run why)))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--needs-you-check)
