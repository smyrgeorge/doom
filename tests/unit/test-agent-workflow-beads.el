;;; tests/unit/test-agent-workflow-beads.el -*- lexical-binding: t; -*-
;; config/agent-workflow/beads.el: what the engine writes on issues, queued
;; and written by bd in the background, one after another, in order; a run's
;; summary once while it waits, as the run is then; a read after the writes
;; queued before it; what fails said, the rest written; Emacs quitting
;; after them. A stand-in bd: a script logging what it's asked, slowly.

(+test-load "config/agent-workflow")

;; ====== HELPERS ======

(defconst +test-awb--bd-script "#!/bin/sh
# bd's stand-in: each call a line in $BD_LOG (its actor, its arguments),
# after $BD_SLEEP seconds; one with fail in it exits 1, saying so.
sleep \"${BD_SLEEP:-0}\"
echo \"$BEADS_ACTOR $*\" >> \"$BD_LOG\"
case \"$*\" in *fail*) echo 'no such issue' >&2; exit 1 ;; esac
case \"$1\" in show|list) echo '[]' ;; esac
")

(defmacro +test-awb (sleep &rest body)
  "BODY with bd a stand-in taking SLEEP seconds a call (`log' its file,
`project' a folder with .beads/), the queue empty before and after."
  (declare (indent 1))
  `(let* ((bin (file-name-as-directory (make-temp-file (+test-tmp-file "awb-bin-") t)))
          (project (file-name-as-directory (make-temp-file (+test-tmp-file "awb-project-") t)))
          (log (expand-file-name "bd.log" project))
          (exec-path (cons bin exec-path))
          (process-environment (append (list (concat "PATH=" bin path-separator (getenv "PATH"))
                                             (concat "BD_LOG=" log)
                                             (format "BD_SLEEP=%s" ,sleep))
                                       process-environment))
          (agent-workflow--bd-queue nil)
          (agent-workflow--bd-process nil))
     (make-directory (expand-file-name ".beads" project))
     (let ((script (expand-file-name "bd" bin)))
       (write-region +test-awb--bd-script nil script nil 'silent)
       (set-file-modes script #o755))
     (unwind-protect (progn ,@body)
       (agent-workflow-bd-writes-wait 10))))

(defun +test-awb--log (log)
  "The stand-in's calls, in order: a line each."
  (if (file-exists-p log)
      (with-temp-buffer (insert-file-contents log) (split-string (buffer-string) "\n" t))
    nil))

(defun +test-awb--run (project issue state jobs)
  "A run on ISSUE of PROJECT in STATE, its JOBS ((NAME . STATUS)...)."
  (agent-workflow-run--make :project project :issue issue :n 1 :state state
                            :workflow (list :name "feature") :info (list :labels nil)
                            :jobs (mapcar (lambda (job) (list (car job) :status (cdr job))) jobs)))

;; ====== WRITES ======

(ert-deftest agent-workflow-beads/writes-wait-for-nothing ()
  "Queued, Emacs not waiting on bd (0.5 s a call here; ~0.6 s for real, a
job's every change, doom-8aj); written one after another, in order, as the
engine; a close after the writes before it."
  (+test-awb 0.5
    (let ((start (float-time)))
      (agent-workflow--bd-write project "demo-1" "--status" "in_progress")
      (agent-workflow--bd-write project "demo-1" "--append-notes" "build (done): built")
      (agent-workflow--bd-close project "demo-1" "Merged it")
      (should (< (- (float-time) start) 0.2))
      ;; Nothing started before this turn is over.
      (should-not agent-workflow--bd-process)
      (should-not (+test-awb--log log))
      (should (agent-workflow-bd-writes-wait 10))
      (should (equal (+test-awb--log log)
                     '("agent-workflow update demo-1 --status in_progress"
                       "agent-workflow update demo-1 --append-notes build (done): built"
                       "agent-workflow close demo-1 --reason Merged it"))))))

(ert-deftest agent-workflow-beads/a-run-s-summary-once-as-it-is-then ()
  "Asked for again and again while it waits (its jobs changing): written
once, the run as it is when its turn comes."
  (+test-awb 0
    (let ((run (+test-awb--run project "demo-1" 'running '(("build" . running) ("review" . pending)))))
      (agent-workflow--issue-summary run)
      (setf (plist-get (cdr (assoc "build" (agent-workflow-run-jobs run))) :status) 'done)
      (agent-workflow--issue-summary run)
      (setf (plist-get (cdr (assoc "review" (agent-workflow-run-jobs run))) :status) 'running)
      (agent-workflow--issue-summary run)
      (should (= (length agent-workflow--bd-queue) 1))
      (should (agent-workflow-bd-writes-wait 10))
      (should (equal (+test-awb--log log)
                     '("agent-workflow update demo-1 --set-metadata workflow=feature --set-metadata workflow_run=1 --set-metadata workflow_state=running --set-metadata workflow_jobs=build:done,review:running --add-label job:review")))
      ;; Its labels as written: job:review's taken off once it's over.
      (setf (plist-get (cdr (assoc "review" (agent-workflow-run-jobs run))) :status) 'done
            (agent-workflow-run-state run) 'done)
      (agent-workflow--issue-summary run)
      (should (agent-workflow-bd-writes-wait 10))
      (should (string-suffix-p "workflow_jobs=build:done,review:done --remove-label job:review"
                               (car (last (+test-awb--log log))))))))

(ert-deftest agent-workflow-beads/no-summary-without-a-ticket ()
  (+test-awb 0
    (let ((run (+test-awb--run project "solo" 'running '(("build" . running)))))
      (setf (agent-workflow-run-workflow run) (list :name "solo" :ticketless t))
      (agent-workflow--issue-summary run)
      (agent-workflow--run-bd-write run "--status" "open")
      (should-not agent-workflow--bd-queue))))

(ert-deftest agent-workflow-beads/a-read-after-the-writes-before-it ()
  "A read (bd show, list) waits for the writes queued before it: it reads
what they wrote."
  (+test-awb 0.3
    (agent-workflow--bd-write project "demo-1" "--status" "in_progress")
    (agent-workflow--bd-write project "demo-1" "--append-notes" "x")
    (agent-workflow--bd-json project "show" "demo-1")
    (should-not agent-workflow--bd-queue)
    (should (equal (+test-awb--log log)
                   '("agent-workflow update demo-1 --status in_progress"
                     "agent-workflow update demo-1 --append-notes x"
                     "agent-workflow show demo-1 --json")))))

(ert-deftest agent-workflow-beads/a-wait-ends-a-write-its-sentinel-hasn-t ()
  "A write's bd over, its sentinel not run yet (`accept-process-output' on
a process that has exited returns at once, not running it): the wait ends
it and goes on. It spun at 100% CPU until its time was up, again at each
read: agent-workflow-runs/its-concurrency-for-every-agent ran for minutes."
  (+test-awb 0
    (agent-workflow--bd-write project "demo-1" "--append-notes" "one")
    (agent-workflow--bd-write project "demo-1" "--append-notes" "two")
    (agent-workflow--bd-next)
    (let ((process agent-workflow--bd-process))
      (set-process-sentinel process #'ignore)
      (while (process-live-p process) (accept-process-output process 0.05))
      (let ((start (float-time)))
        (should (agent-workflow-bd-writes-wait 3))
        (should (< (- (float-time) start) 2))))
    (should (equal (+test-awb--log log)
                   '("agent-workflow update demo-1 --append-notes one"
                     "agent-workflow update demo-1 --append-notes two")))))

(ert-deftest agent-workflow-beads/a-wait-runs-nothing-else ()
  "While a read or Emacs quitting waits for the writes, nothing else runs,
as with a synchronous bd: no timer, no other process's output (an agent's
turn ending). It did: Emacs quitting saved its runs with their agents'
turns over meanwhile, not interrupted (agent-workflow-runs/
back-after-emacs-stopped, on Linux's slower bd)."
  (+test-awb 0.3
    (let* ((timer-ran nil)
           (output nil)
           (other (make-process :name "awb-other" :command '("sh" "-c" "echo other; sleep 2")
                                :connection-type 'pipe :noquery t
                                :filter (lambda (_process string) (push string output))))
           (timer (run-at-time 0 nil (lambda () (setq timer-ran t)))))
      (unwind-protect
          (progn
            (agent-workflow--bd-write project "demo-1" "--status" "open")
            (agent-workflow--bd-write project "demo-1" "--append-notes" "x")
            (should (agent-workflow-bd-writes-wait 10))
            (should (= (length (+test-awb--log log)) 2))
            (should-not timer-ran)
            (should-not output)
            ;; Both there, once Emacs reads again.
            (let ((end (+ (float-time) 5)))
              (while (and (not (and timer-ran output)) (< (float-time) end))
                (accept-process-output nil 0.05)))
            (should timer-ran)
            (should output))
        (cancel-timer timer)
        (delete-process other)))))

(ert-deftest agent-workflow-beads/a-failed-write-said-the-rest-written ()
  (+test-awb 0
    (let ((said nil))
      (cl-letf (((symbol-function 'message) (lambda (format &rest args) (push (apply #'format format args) said))))
        (agent-workflow--bd-write project "demo-1" "--append-notes" "fail")
        (agent-workflow--bd-write project "demo-1" "--append-notes" "fine")
        (should (agent-workflow-bd-writes-wait 10)))
      (should (member "agent workflow: bd update demo-1: no such issue" said))
      (should (equal (length (+test-awb--log log)) 2)))))

(ert-deftest agent-workflow-beads/no-beads-said-nothing-run ()
  (+test-awb 0
    (delete-directory (expand-file-name ".beads" project))
    (let ((said nil))
      (cl-letf (((symbol-function 'message) (lambda (format &rest args) (push (apply #'format format args) said))))
        (agent-workflow--bd-write project "demo-1" "--status" "open")
        (should (agent-workflow-bd-writes-wait 10)))
      (should (string-match-p "\\`agent workflow: bd update demo-1: .* tracks no issues with Beads" (car said)))
      (should-not (+test-awb--log log)))))

(ert-deftest agent-workflow-beads/written-before-emacs-quits ()
  "Emacs quitting (`agent-workflow-quit-hook', from `kill-emacs-hook'):
what's queued written first."
  (should (memq 'agent-workflow--bd-writes-quit-h agent-workflow-quit-hook))
  (+test-awb 0.2
    (agent-workflow--bd-write project "demo-1" "--status" "open")
    (agent-workflow--bd-close project "demo-1" "Done")
    (agent-workflow--bd-writes-quit-h)
    (should-not (or agent-workflow--bd-queue agent-workflow--bd-process))
    (should (= (length (+test-awb--log log)) 2))))
