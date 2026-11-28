;;; tests/unit/test-agent-workflow-beads.el -*- lexical-binding: t; -*-
;; config/agent-workflow/beads.el: Beads, agent workflow's issue tracker
;; here (`agent-workflow-trackers'). The real bd: an issue read (its
;; blockers still open), the open ones, an epic's, the tracker for a
;; project with .beads/ only; what agents get (BEADS_ACTOR, BEADS_DIR, bd
;; show, told so). A stand-in bd (a script logging what it's asked,
;; slowly): what a run writes queued and written in the background, one
;; after another, in order; a run's summary once while it waits, the newest;
;; its job labels; a read after the writes queued before it; what fails
;; said, the rest written; Emacs quitting after them.

(load (expand-file-name "../helper-beads" (file-name-directory (or load-file-name buffer-file-name))) nil t)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workflow")
(require 'agent-workflow-parts)

;; ====== THE TRACKER ======

(ert-deftest agent-workflow-beads/the-tracker-of-a-beads-project ()
  "Registered; a project's tracker where it has .beads/ (and bd), not
elsewhere: a run there is on a task."
  (should (memq +my/agent-workflow-beads-tracker agent-workflow-trackers))
  (should (eq agent-workflow-issue-affixes-function #'+my/agent-workflow-issue-affixes))
  (let ((tracked (file-name-as-directory (+test-tmp-file "awbd-tracker/tracked/")))
        (other (file-name-as-directory (+test-tmp-file "awbd-tracker/other/")))
        (agent-workflow-trackers (list +my/agent-workflow-beads-tracker)))
    (make-directory (expand-file-name ".beads" tracked) t)
    (make-directory other t)
    (cl-letf (((symbol-function 'executable-find) (lambda (name &rest _) (and (equal name "bd") "/bin/bd"))))
      (should (eq (agent-workflow-tracker tracked) +my/agent-workflow-beads-tracker))
      (should-not (agent-workflow-tracker other)))
    (should (equal (plist-get +my/agent-workflow-beads-tracker :types) +my/agent-workflow-beads-types))
    (should (equal (plist-get +my/agent-workflow-beads-tracker :tools) '("Bash(bd show:*)")))))

(ert-deftest agent-workflow-beads/what-an-agent-gets ()
  "An agent (and the scripts) doing a job on one of its issues: bd as
ISSUE/JOB, on the project's issues; told how it reads the issue."
  (should (equal (+my/agent-workflow-beads-environment "/p/" "demo-1" "build")
                 '("BEADS_ACTOR=demo-1/build" "BEADS_DIR=/p/.beads")))
  (should (equal (+my/agent-workflow-beads-context "/p/" "demo-1" "build")
                 "Its issue is Beads': bd show demo-1 reads it; your bd commands run as demo-1/build (BEADS_ACTOR).")))

(ert-deftest agent-workflow-beads/issues-read-by-bd ()
  "The real bd: an issue (its blockers those still open), the open ones (each
its bd JSON as :data), an epic's (not epics), through the package."
  (+test-beads-with-project
    (let* ((agent-workflow-trackers (list +my/agent-workflow-beads-tracker))
           (epic (+test-beads--create "An epic" :issue-type "epic"))
           (blocker (+test-beads--create "First" :issue-type "task"))
           (one (+test-beads--create "One" :issue-type "feature" :parent epic :priority 1))
           (sub (+test-beads--create "A sub-epic" :issue-type "epic" :parent epic)))
      (+test-beads--run "bd" "dep" "add" one blocker)
      (let ((issue (agent-workflow-issue repo one)))
        (should (equal (plist-get issue :title) "One"))
        (should (equal (plist-get issue :type) "feature"))
        (should (equal (plist-get issue :priority) 1))
        (should (equal (plist-get issue :status) "open"))
        (should (equal (plist-get issue :blockers) (list blocker))))
      (+test-beads--run "bd" "close" blocker)
      (should-not (plist-get (agent-workflow-issue repo one) :blockers))
      (should (equal (cadr (should-error (agent-workflow-issue repo "t-nope") :type 'user-error))
                     (cadr (should-error (+my/agent-workflow--bd-json repo "show" "t-nope") :type 'user-error))))
      (let ((open (agent-workflow-open-issues repo)))
        (should (equal (sort (mapcar (lambda (issue) (plist-get issue :id)) open) #'string<)
                       (sort (list epic one sub) #'string<)))
        (should (equal (alist-get 'title (plist-get (seq-find (lambda (issue) (equal (plist-get issue :id) one)) open)
                                                    :data))
                       "One")))
      (should (equal (agent-workflow-epic-issues repo epic) (list one)))
      (ignore sub))))

(ert-deftest agent-workflow-beads/a-summary-s-labels-as-bd-has-them ()
  "The real bd: a run's summary in the issue's metadata, the job running as
its label, taken off once it's over."
  (+test-beads-with-project
    (let* ((id (+test-beads--create "One" :issue-type "feature"))
           (summary (lambda (state jobs running)
                      (list :workflow "feature" :run 1 :state state :jobs jobs :running running))))
      (agent-workflow-issue repo id)
      (+my/agent-workflow-beads-update repo id (list :status "in_progress"
                                                     :summary (funcall summary "running" '(("build" . "running"))
                                                                       "build")))
      (should (+my/agent-workflow-bd-writes-wait 30))
      (let ((shown (car (+my/agent-workflow--bd-json repo "show" id))))
        (should (equal (alist-get 'status shown) "in_progress"))
        (should (member "job:build" (alist-get 'labels shown)))
        (should (equal (alist-get 'workflow_jobs (alist-get 'metadata shown)) "build:running")))
      (+my/agent-workflow-beads-update repo id (list :notes "build (done): built"
                                                     :summary (funcall summary "done" '(("build" . "done")) nil)))
      (+my/agent-workflow-beads-close repo id "Merged")
      (should (+my/agent-workflow-bd-writes-wait 30))
      (let ((shown (car (+my/agent-workflow--bd-json repo "show" id))))
        (should (equal (alist-get 'status shown) "closed"))
        (should-not (seq-find (lambda (label) (string-prefix-p "job:" label)) (alist-get 'labels shown)))
        (should (equal (alist-get 'workflow_state (alist-get 'metadata shown)) "done"))
        (should (string-match-p "build (done): built" (alist-get 'notes shown)))))))

;; ====== WRITES: A STAND-IN BD ======

(defconst +test-awbd--script "#!/bin/sh
# bd's stand-in: each call a line in $BD_LOG (its actor, its arguments),
# after $BD_SLEEP seconds; one with fail in it exits 1, saying so.
sleep \"${BD_SLEEP:-0}\"
echo \"$BEADS_ACTOR $*\" >> \"$BD_LOG\"
case \"$*\" in *fail*) echo 'no such issue' >&2; exit 1 ;; esac
case \"$1\" in show|list) echo '[]' ;; esac
")

(defmacro +test-awbd (sleep &rest body)
  "BODY with bd a stand-in taking SLEEP seconds a call (`log' its file,
`project' a folder with .beads/), the queue empty before and after."
  (declare (indent 1))
  `(let* ((bin (file-name-as-directory (make-temp-file (+test-tmp-file "awbd-bin-") t)))
          (project (file-name-as-directory (make-temp-file (+test-tmp-file "awbd-project-") t)))
          (log (expand-file-name "bd.log" project))
          (exec-path (cons bin exec-path))
          (process-environment (append (list (concat "PATH=" bin path-separator (getenv "PATH"))
                                             (concat "BD_LOG=" log)
                                             (format "BD_SLEEP=%s" ,sleep))
                                       process-environment))
          (+my/agent-workflow--bd-queue nil)
          (+my/agent-workflow--bd-process nil)
          (+my/agent-workflow--beads-labels (make-hash-table :test #'equal)))
     (make-directory (expand-file-name ".beads" project))
     (let ((script (expand-file-name "bd" bin)))
       (write-region +test-awbd--script nil script nil 'silent)
       (set-file-modes script #o755))
     (unwind-protect (progn ,@body)
       (+my/agent-workflow-bd-writes-wait 10))))

(defun +test-awbd--log (log)
  "The stand-in's calls, in order: a line each."
  (if (file-exists-p log)
      (with-temp-buffer (insert-file-contents log) (split-string (buffer-string) "\n" t))
    nil))

(defun +test-awbd--summary (state jobs running)
  (list :workflow "feature" :run 1 :state state :jobs jobs :running running))

(ert-deftest agent-workflow-beads/writes-wait-for-nothing ()
  "Queued, Emacs not waiting on bd (0.5 s a call here; ~0.6 s for real);
written one after another, in order, as the engine; a close after the
writes before it."
  (+test-awbd 0.5
    (let ((start (float-time)))
      (+my/agent-workflow-beads-update project "demo-1" '(:status "in_progress"))
      (+my/agent-workflow-beads-update project "demo-1" '(:notes "build (done): built"))
      (+my/agent-workflow-beads-close project "demo-1" "Merged it")
      (should (< (- (float-time) start) 0.2))
      ;; Nothing started before this turn is over.
      (should-not +my/agent-workflow--bd-process)
      (should-not (+test-awbd--log log))
      (should (+my/agent-workflow-bd-writes-wait 10))
      (should (equal (+test-awbd--log log)
                     '("agent-workflow update demo-1 --status in_progress"
                       "agent-workflow update demo-1 --append-notes build (done): built"
                       "agent-workflow close demo-1 --reason Merged it"))))))

(ert-deftest agent-workflow-beads/a-run-s-summary-once-the-newest ()
  "Asked for again and again while it waits (its jobs changing): written
once, the newest; its job's label added, taken off once it's over."
  (+test-awbd 0
    (+my/agent-workflow-beads-update project "demo-1"
                                     (list :summary (+test-awbd--summary "running" '(("build" . "running") ("review" . "pending")) "build")))
    (+my/agent-workflow-beads-update project "demo-1"
                                     (list :summary (+test-awbd--summary "running" '(("build" . "done") ("review" . "pending")) nil)))
    (+my/agent-workflow-beads-update project "demo-1"
                                     (list :summary (+test-awbd--summary "running" '(("build" . "done") ("review" . "running")) "review")))
    (should (= (length +my/agent-workflow--bd-queue) 1))
    (should (+my/agent-workflow-bd-writes-wait 10))
    (should (equal (+test-awbd--log log)
                   '("agent-workflow update demo-1 --set-metadata workflow=feature --set-metadata workflow_run=1 --set-metadata workflow_state=running --set-metadata workflow_jobs=build:done,review:running --add-label job:review")))
    (+my/agent-workflow-beads-update project "demo-1"
                                     (list :summary (+test-awbd--summary "done" '(("build" . "done") ("review" . "done")) nil)))
    (should (+my/agent-workflow-bd-writes-wait 10))
    (should (string-suffix-p "workflow_jobs=build:done,review:done --remove-label job:review"
                             (car (last (+test-awbd--log log)))))))

(ert-deftest agent-workflow-beads/a-read-after-the-writes-before-it ()
  "A read (bd show, list) waits for the writes queued before it: it reads
what they wrote."
  (+test-awbd 0.3
    (+my/agent-workflow-beads-update project "demo-1" '(:status "in_progress"))
    (+my/agent-workflow-beads-update project "demo-1" '(:notes "x"))
    (+my/agent-workflow--bd-json project "show" "demo-1")
    (should-not +my/agent-workflow--bd-queue)
    (should (equal (+test-awbd--log log)
                   '("agent-workflow update demo-1 --status in_progress"
                     "agent-workflow update demo-1 --append-notes x"
                     "agent-workflow show demo-1 --json")))))

(ert-deftest agent-workflow-beads/a-wait-ends-a-write-its-sentinel-hasn-t ()
  "A write's bd over, its sentinel not run yet (`accept-process-output' on
a process that has exited returns at once, not running it): the wait ends
it and goes on (it spun at 100% CPU until its time was up)."
  (+test-awbd 0
    (+my/agent-workflow-beads-update project "demo-1" '(:notes "one"))
    (+my/agent-workflow-beads-update project "demo-1" '(:notes "two"))
    (+my/agent-workflow--bd-next)
    (let ((process +my/agent-workflow--bd-process))
      (set-process-sentinel process #'ignore)
      (while (process-live-p process) (accept-process-output process 0.05))
      (let ((start (float-time)))
        (should (+my/agent-workflow-bd-writes-wait 3))
        (should (< (- (float-time) start) 2))))
    (should (equal (+test-awbd--log log)
                   '("agent-workflow update demo-1 --append-notes one"
                     "agent-workflow update demo-1 --append-notes two")))))

(ert-deftest agent-workflow-beads/a-wait-runs-nothing-else ()
  "While a read or Emacs quitting waits for the writes, nothing else runs,
as with a synchronous bd: no timer, no other process's output (an agent's
turn ending: Emacs quitting saved its runs with their agents' turns over
meanwhile, not interrupted)."
  (+test-awbd 0.3
    (let* ((timer-ran nil)
           (output nil)
           (other (make-process :name "awbd-other" :command '("sh" "-c" "echo other; sleep 2")
                                :connection-type 'pipe :noquery t
                                :filter (lambda (_process string) (push string output))))
           (timer (run-at-time 0 nil (lambda () (setq timer-ran t)))))
      (unwind-protect
          (progn
            (+my/agent-workflow-beads-update project "demo-1" '(:status "open"))
            (+my/agent-workflow-beads-update project "demo-1" '(:notes "x"))
            (should (+my/agent-workflow-bd-writes-wait 10))
            (should (= (length (+test-awbd--log log)) 2))
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
  (+test-awbd 0
    (let ((said nil))
      (cl-letf (((symbol-function 'message) (lambda (format &rest args) (push (apply #'format format args) said))))
        (+my/agent-workflow-beads-update project "demo-1" '(:notes "fail"))
        (+my/agent-workflow-beads-update project "demo-1" '(:notes "fine"))
        (should (+my/agent-workflow-bd-writes-wait 10)))
      (should (member "agent workflow: bd update demo-1: no such issue" said))
      (should (equal (length (+test-awbd--log log)) 2)))))

(ert-deftest agent-workflow-beads/no-beads-said-nothing-run ()
  (+test-awbd 0
    (delete-directory (expand-file-name ".beads" project))
    (let ((said nil))
      (cl-letf (((symbol-function 'message) (lambda (format &rest args) (push (apply #'format format args) said))))
        (+my/agent-workflow-beads-update project "demo-1" '(:status "open"))
        (should (+my/agent-workflow-bd-writes-wait 10)))
      (should (string-match-p "\\`agent workflow: bd update demo-1: .* tracks no issues with Beads" (car said)))
      (should-not (+test-awbd--log log)))))

(ert-deftest agent-workflow-beads/written-before-emacs-quits ()
  "Emacs quitting (the package's quit handlers: its trackers' :wait): what's
queued written first."
  (should (memq 'agent-workflow--tracker-quit-h agent-workflow--quit-handlers))
  (+test-awbd 0.2
    (let ((agent-workflow-trackers (list +my/agent-workflow-beads-tracker)))
      (+my/agent-workflow-beads-update project "demo-1" '(:status "open"))
      (+my/agent-workflow-beads-close project "demo-1" "Done")
      (agent-workflow--tracker-quit-h)
      (should-not (or +my/agent-workflow--bd-queue +my/agent-workflow--bd-process))
      (should (= (length (+test-awbd--log log)) 2)))))
