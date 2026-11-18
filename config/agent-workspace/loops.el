;;; $DOOMDIR/config/agent-workspace/loops.el -*- lexical-binding: t; -*-
;; Loops: an agent that, once free, takes the next ready issue of its role by
;; itself, or naps and says so. Loaded from config/agent-workspace.el, after
;; minimap.el (saved.el, after it, keeps them in crew.json). No Doom here.
;;
;; On for a new agent whose role has labels, in a project whose issues Beads
;; tracks (`agent-workspace-loop', config/agent-workspace.el: said in the
;; room as it joins); off for the others. L turns an agent's on or off (its
;; bar shows ↻). A crew started again from crew.json brings a looping agent
;; back awake: it takes the next ready issue (one put to sleep stays asleep).
;; With `agent-workspace-loop' nil, a new agent doesn't loop, and one started
;; again comes back asleep, still looping: reopening never starts work by
;; itself, waking it does.
;;
;; Free: at rest (at the desk, done or napping), nothing queued for it, and no
;; issue in progress of its own (bd): the one it had is closed, or handed over.
;; A turn that ended with its issue still in progress is done, for you to
;; look: it waits (closed later, by it or you, it's free). A raised hand
;; isn't at rest. Free, it takes the next issue: one you gave it first (t:
;; sent to it at once, or after its turn), else the next ready one its role's
;; labels say, P0 first, then P1..., claimed as itself (bd ready --claim, as
;; BEADS_ACTOR): atomic, so two looping agents never get the same one. Its
;; branch for it is opened in its worktree (`agent-workspace-give': none
;; while its worktree has changes not committed, a failure: nothing claimed),
;; its session starts again for it (a fresh context per issue; not if it had
;; no turn yet), then it's given the issue as t gives one: "Work on ID:
;; TITLE".
;;
;; None left: it naps, "napping: nothing to build" (☾), said once in the room
;; and to `agent-workspace-nap-functions' (a notification), not again until it
;; took an issue. It wakes when one comes: its project's .beads changing
;; (file-notify, debounced), a look every `agent-workspace-loop-check' minutes,
;; or another part calling `agent-workspace-loop-wake'. A look that finds
;; nothing says nothing. A napping agent is free: a message to it starts a
;; turn, and it naps again after, quietly, if nothing came.
;;
;; A failure: its turn stopped on an error, its session didn't start, its
;; worktree had changes not committed (no branch for the issue), or bd
;; failed. It tries again `agent-workspace-loop-retry' seconds later: the same
;; issue again, in its session (a fresh one if it had none, or no issue); bd
;; again. After `agent-workspace-loop-failures' in a row it stops: stuck,
;; saying why. A turn that ends without an error breaks the row; r, s or L
;; start it again. (A turn that ends with its issue in progress isn't one: it
;; waits for you.)

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'map)
(require 'filenotify)

(defvar agent-shell--state)

;; config/agent-workspace.el's; saved.el's, loaded after.
(defvar agent-workspace-loop)
(defvar agent-workspace--crew-loading)

;; ====== VARIABLES ======

(defcustom agent-workspace-loop-failures 3
  "Failures in a row after which a looping agent stops: stuck, saying why."
  :type 'natnum
  :group 'agent-workspace)

(defcustom agent-workspace-loop-retry 30
  "Seconds a looping agent waits after a failure, before it tries again."
  :type 'number
  :group 'agent-workspace)

(defcustom agent-workspace-loop-check 5
  "Minutes between two looks at the project's issues for its napping agents
\(besides one each time its .beads changes). nil: none."
  :type '(choice number (const nil))
  :group 'agent-workspace)

(defvar agent-workspace-nap-functions nil
  "Called with a looping agent that found no issue left for it: it naps.
Once, until it takes an issue again.")

(defconst agent-workspace--loop-debounce 1.0
  "Seconds after the last change to a project's .beads before its looping
agents look (a burst of changes: one look).")

(defvar agent-workspace--loop-runs (make-hash-table :test #'eq :weakness 'key)
  "A looping agent's run, a plist: :failures (in a row), :busy (its bd
command running), :again (a look asked for meanwhile), :timer (its next try,
after a failure), :stopped (too many failures), :napped (its nap said),
:paused (its role without labels: said),
:waiting (the agent at work on the branch of the issue it claimed: it
looks again once that agent's turn ends).")

(defvar agent-workspace--loop-turned (make-hash-table :test #'eq :weakness 'key)
  "An agent to its session that had a turn: its next issue needs a fresh one.")

(defvar agent-workspace--loop-watches (make-hash-table :test #'equal)
  "A project to its watch, while an agent of it loops: a plist, :notify
\(file-notify's descriptors and their files), :timer (its look every few
minutes), :soon (a look to come, .beads changed).")

(defvar agent-workspace--loop-starting nil
  "Non-nil while a loop starts its agent's session: its run goes on (one you
start begins it again).")

;; ====== ITS RUN ======

(defun agent-workspace-loop-p (agent)
  "Non-nil if AGENT loops."
  (agent-workspace-agent-loop agent))

(defun agent-workspace--loop-get (agent key)
  "KEY of AGENT's run."
  (plist-get (gethash agent agent-workspace--loop-runs) key))

(defun agent-workspace--loop-put (agent key value)
  "KEY of AGENT's run now VALUE."
  (puthash agent (plist-put (gethash agent agent-workspace--loop-runs) key value)
           agent-workspace--loop-runs))

(defun agent-workspace--loop-cancel (agent)
  "AGENT's try again to come, cancelled."
  (when-let* ((timer (agent-workspace--loop-get agent :timer)))
    (cancel-timer timer)
    (agent-workspace--loop-put agent :timer nil)))

(defun agent-workspace--loop-reset (agent)
  "AGENT's run begun again: no failures, not stopped, its nap to be said."
  (agent-workspace--loop-cancel agent)
  (dolist (key '(:failures :stopped :napped :waiting :paused))
    (agent-workspace--loop-put agent key nil)))

(defun agent-workspace--loop-active-p (agent)
  "Non-nil if AGENT's loop runs: on, AGENT in its crew, its session running,
not stopped."
  (and (agent-workspace-agent-loop agent)
       (memq agent (agent-workspace-agents (agent-workspace-agent-project agent)))
       (agent-workspace-live-p agent)
       (not (agent-workspace--loop-get agent :stopped))))

(defun agent-workspace--loop-queued-p (agent)
  "Non-nil if a message waits for AGENT's next turn (agent-shell's queue)."
  (when-let* ((buffer (agent-workspace-agent-buffer agent)))
    (and (buffer-live-p buffer)
         (local-variable-p 'agent-shell--state buffer)
         (map-elt (buffer-local-value 'agent-shell--state buffer) :pending-prompts))))

(defun agent-workspace--loop-typed-p (agent)
  "Non-nil if text is typed at AGENT's prompt, not sent: a fresh session
would lose it. Asked of an agent-shell buffer only: elsewhere
`agent-shell--input' looks for a shell, and offers to make one (asking: a
GUI Emacs waits for the answer)."
  (when-let* ((buffer (agent-workspace-agent-buffer agent))
              ((buffer-live-p buffer))
              ((fboundp 'agent-shell--input)))
    (with-current-buffer buffer
      (and (derived-mode-p 'agent-shell-mode)
           (ignore-errors (agent-shell--input))))))

(defun agent-workspace--loop-at-rest-p (agent)
  "Non-nil if AGENT rests: at the desk, done or napping, nothing queued,
nothing typed at its prompt (you're writing to it: its loop waits)."
  (and (memq (agent-workspace-agent-state agent) '(desk done nap))
       (not (agent-workspace--loop-queued-p agent))
       (not (agent-workspace--loop-typed-p agent))))

(defun agent-workspace--loop-used-p (agent)
  "Non-nil if AGENT's session had a turn: its next issue needs a fresh one."
  (let ((buffer (agent-workspace-agent-buffer agent)))
    (and buffer (eq (gethash agent agent-workspace--loop-turned) buffer))))

(defun agent-workspace--loop-labels (agent)
  "AGENT's role's labels: the issues it's for."
  (plist-get (agent-workspace-role agent) :labels))

(defun agent-workspace--loop-beads-p (project)
  "Non-nil if PROJECT's issues are tracked with Beads (bd there to take
them)."
  (and (executable-find "bd") (file-directory-p (expand-file-name ".beads" project))))

(defun agent-workspace--loop-say (agent kind text)
  "TEXT said in AGENT's room, an entry of KIND."
  (agent-workspace-room-post (agent-workspace-agent-project agent)
                             :kind kind :agent (agent-workspace-agent-name agent) :text text))

;; ====== BD ======

(defun agent-workspace--loop-line (text)
  "TEXT's first line that isn't empty, or \"no output\"."
  (or (seq-find (lambda (line) (not (string-empty-p line)))
                (mapcar #'string-trim (split-string (or text "") "\n")))
      "no output"))

(defun agent-workspace--loop-bd (agent args callback)
  "Run bd with ARGS as AGENT (BEADS_ACTOR its name), in its project, in the
background; CALLBACK with (ok . JSON) or (error . WHY)."
  (let* ((default-directory (agent-workspace-agent-project agent))
         (process-environment (cons (concat "BEADS_ACTOR=" (agent-workspace-agent-name agent))
                                    process-environment))
         (output (generate-new-buffer " *agent-workspace loop bd*"))
         (errors (make-pipe-process :name "agent-workspace-loop-bd errors" :noquery t
                                    :buffer (generate-new-buffer " *agent-workspace loop bd errors*"))))
    (cl-flet ((done ()
                (let ((why (with-current-buffer (process-buffer errors) (buffer-string))))
                  (delete-process errors)
                  (kill-buffer (process-buffer errors))
                  (kill-buffer output)
                  why)))
      (condition-case err
          (make-process
           :name "agent-workspace-loop-bd" :buffer output :stderr errors
           :command (cons "bd" args) :connection-type 'pipe :noquery t
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let* ((text (with-current-buffer output (buffer-string)))
                      (why (done)))
                 (funcall callback
                          (if (eql (process-exit-status process) 0)
                              (condition-case nil
                                  (cons 'ok (json-parse-string text :object-type 'alist :array-type 'list
                                                               :null-object nil :false-object nil))
                                (error (cons 'error (concat "bd answered no JSON: "
                                                            (agent-workspace--loop-line text)))))
                            (cons 'error (format "bd %s failed: %s" (car args)
                                                 (agent-workspace--loop-line
                                                  (if (string-blank-p why) text why))))))))))
        (error
         (done)
         (funcall callback (cons 'error (concat "bd: " (error-message-string err)))))))))

;; ====== TAKING THE NEXT ISSUE ======

(defun agent-workspace--loop-soon (agent)
  "AGENT looks for its next issue in a moment (once agent-shell is done
with its turn: a message queued for it goes first)."
  (run-at-time 0 nil #'agent-workspace--loop-look agent))

(defun agent-workspace--loop-answered (agent)
  "AGENT's bd command answered (and its answer used): nothing running for it
now. Non-nil if a look was asked for meanwhile: done now."
  (agent-workspace--loop-put agent :busy nil)
  (when (agent-workspace--loop-get agent :again)
    (agent-workspace--loop-put agent :again nil)
    (agent-workspace--loop-look agent)
    t))

(defun agent-workspace--loop-safely (agent function)
  "Call FUNCTION, AGENT's loop going on: an error in it, a failure."
  (condition-case err
      (funcall function)
    (error (agent-workspace--loop-failed agent (error-message-string err)))))

(defun agent-workspace--loop-look (agent)
  "AGENT, looping and at rest, looks for its next issue: free, it takes
one or naps; its issue still in progress, it waits (for you to look)."
  (cond
   ((not (and (agent-workspace--loop-active-p agent) (agent-workspace--loop-at-rest-p agent))))
   ;; Its bd command running: it looks again once that answers.
   ((agent-workspace--loop-get agent :busy) (agent-workspace--loop-put agent :again t))
   ;; A try again to come, after a failure: it waits for it.
   ((agent-workspace--loop-get agent :timer))
   ;; Its issue's branch held by an agent at work: it waits for its turn's
   ;; end (that agent gone, or at rest: no longer).
   ((when-let* ((holder (agent-workspace--loop-get agent :waiting)))
      (or (and (memq holder (agent-workspace-agents (agent-workspace-agent-project agent)))
               (memq (agent-workspace-agent-state holder) '(working hand)))
          (progn (agent-workspace--loop-put agent :waiting nil) nil))))
   ((eq (agent-workspace-agent-state agent) 'nap) (agent-workspace--loop-claim agent))
   (t
    (agent-workspace--loop-put agent :busy t)
    (agent-workspace--loop-bd
     agent (list "list" "--status" "in_progress" "--assignee" (agent-workspace-agent-name agent)
                 "--json" "--limit" "0")
     (lambda (answer)
       ;; Its answer used even when another look was asked for meanwhile
       ;; (.beads changing, its look every few minutes), then that one:
       ;; thrown away instead, a bd slower than those never got anywhere.
       (unwind-protect
           (progn
             (agent-workspace--loop-put agent :busy nil)
             (when (and (agent-workspace--loop-active-p agent)
                        (agent-workspace--loop-at-rest-p agent))
               (agent-workspace--loop-safely
                agent
                (lambda ()
                  (pcase answer
                    (`(error . ,why) (agent-workspace--loop-failed agent why))
                    (`(ok . ,(and doing (pred consp)))
                     ;; Its issue still in progress: it waits. One it claimed
                     ;; itself noted as its issue.
                     (unless (seq-find (lambda (issue) (equal (alist-get 'id issue) (agent-workspace-agent-issue agent)))
                                       doing)
                       (agent-workspace--note-issue agent (alist-get 'id (car doing)) (alist-get 'title (car doing)))))
                    (_
                     ;; Free: the issue it had is done (closed, or handed over).
                     (when (agent-workspace-agent-issue agent)
                       (agent-workspace--note-issue agent nil))
                     (agent-workspace--loop-claim agent)))))))
         ;; A claim it started is busy now: its own answer looks again.
         (unless (agent-workspace--loop-get agent :busy)
           (agent-workspace--loop-answered agent))))))))

(defun agent-workspace--loop-claim (agent)
  "AGENT, free, claims the next ready issue of its role's labels (bd, as
itself): one handed back to it first (open, assigned to it: bd ready
--claim skips those), else the first nobody has; takes it, or naps if
there's none. Its worktree with changes not committed (no branch for an
issue there): found as it takes one (its branch not opened), the issue
given back, a failure; not before each look (git status on Emacs's
thread, for every napping agent at each change)."
  (if-let* ((labels (agent-workspace--loop-labels agent)))
      (progn
        (when (agent-workspace--loop-get agent :paused)
          (agent-workspace--loop-put agent :paused nil)
          (agent-workspace--loop-say agent 'note (format "▶ goes on: its role, %s, has labels again"
                                                         (agent-workspace-agent-role agent))))
        (let* ((filters (list "--label-any" (string-join labels ",") "--exclude-type" "epic" "--json"))
               (claimed
                (lambda (answer)
                  (unwind-protect
                      (agent-workspace--loop-safely
                       agent
                       (lambda ()
                         (let ((issue (and (eq (car answer) 'ok) (car (cdr answer)))))
                           (cond
                            ((not (and (agent-workspace--loop-active-p agent) (agent-workspace--loop-at-rest-p agent)))
                             ;; No longer free (its loop turned off, given a message,
                             ;; put to sleep, its crew closed): the issue claimed for
                             ;; it given back.
                             (when issue (agent-workspace--bd-give-back agent (alist-get 'id issue))))
                            ((eq (car answer) 'error) (agent-workspace--loop-failed agent (cdr answer)))
                            (issue (agent-workspace--loop-take agent (alist-get 'id issue) (alist-get 'title issue)
                                                               (alist-get 'issue_type issue)))
                            (t (agent-workspace--loop-nap agent))))))
                    (agent-workspace--loop-answered agent)))))
          (agent-workspace--loop-put agent :busy t)
          (agent-workspace--loop-bd
           agent (append (list "ready" "--assignee" (agent-workspace-agent-name agent)) filters)
           (lambda (answer)
             (let ((back (and (eq (car answer) 'ok) (car (cdr answer)))))
               (condition-case err
                   (cond
                    ((eq (car answer) 'error) (funcall claimed answer))
                    ;; Handed back to it: claimed (in progress, its).
                    (back (agent-workspace--loop-bd
                           agent (list "update" (alist-get 'id back) "--claim" "--json") claimed))
                    (t (agent-workspace--loop-bd agent (append (list "ready" "--claim") filters) claimed)))
                 (error (funcall claimed (cons 'error (error-message-string err))))))))))
    ;; Its role without labels now (its file being edited, broken, gone from
    ;; the branch checked out): paused, its loop kept.
    (agent-workspace--loop-pause agent)))

(defun agent-workspace--loop-pause (agent)
  "AGENT's role has no labels now: it naps, its loop on, said once; its
next look, its role's labels back, goes on (`agent-workspace--loop-claim')."
  (unless (eq (agent-workspace-agent-state agent) 'nap)
    (agent-workspace--set-state agent 'nap))
  (unless (agent-workspace--loop-get agent :paused)
    (agent-workspace--loop-put agent :paused t)
    (agent-workspace--loop-say agent 'note (format "⏸ paused: its role, %s, has no labels now; goes on once it has"
                                                   (agent-workspace-agent-role agent)))))

(defun agent-workspace--loop-take (agent id title &optional type)
  "AGENT takes issue ID (its TITLE, TYPE), claimed for it: its branch for it, its
session fresh (if it had a turn), then given it as t gives one. Its branch
not opened (changes there since): the issue given back, a failure. Its
branch held by an agent at work (one handing the issue on, its turn not
over yet): the issue given back, no failure: it waits for that turn's end,
said once, then looks again."
  (if-let* ((holder (agent-workspace-issue-branch-busy agent id type title)))
      (progn
        (agent-workspace--bd-give-back agent id)
        (agent-workspace--loop-put agent :waiting holder)
        (agent-workspace--loop-say agent 'note (format "waits for %s to finish with %s"
                                                       (agent-workspace-agent-name holder) id)))
    (agent-workspace--loop-take-1 agent id title type)))

(defun agent-workspace--loop-take-1 (agent id title &optional type)
  "`agent-workspace--loop-take', its branch free."
  (let ((woke (eq (agent-workspace-agent-state agent) 'nap)))
    (agent-workspace--loop-put agent :napped nil)
    (condition-case err
        (agent-workspace-give agent id title type)
      (user-error
       ;; Given back before the failure's counted and its try again timed:
       ;; that try finds it ready (given back in the background, it could
       ;; find nothing and nap, the failures never adding up).
       (let ((name (agent-workspace-agent-name agent)))
         (agent-workspace--bd-now (agent-workspace-agent-project agent) name
                                  (list "update" id (concat "--if-assignee=" name) "--if-status=in_progress"
                                        "--status=open" "--assignee=")))
       (signal (car err) (cdr err))))
    (agent-workspace--loop-say agent 'issue (format "%s %s: %s" (if woke "woke up, took" "took") id title))
    (when (agent-workspace--loop-used-p agent)
      (let ((agent-workspace--loop-starting t))
        (agent-workspace--start agent)))
    ;; Its session not started: stuck, a failure (tried again).
    (when (agent-workspace-live-p agent)
      (agent-workspace--loop-prompt agent))))

(defun agent-workspace--loop-prompt (agent)
  "AGENT given its issue, as t gives one: \"Work on ID: TITLE\". Not sent,
a failure."
  (condition-case err
      (agent-workspace-send agent (agent-workspace-issue-prompt (agent-workspace-agent-issue agent)
                                                                (agent-workspace-agent-issue-title agent))
                            :submit t)
    (error (agent-workspace--loop-failed agent (concat "its prompt: " (error-message-string err))))))

(defun agent-workspace--loop-nap (agent)
  "AGENT, free, found no issue for it: it naps, said once."
  (unless (eq (agent-workspace-agent-state agent) 'nap)
    (agent-workspace--set-state agent 'nap))
  (unless (agent-workspace--loop-get agent :napped)
    (agent-workspace--loop-put agent :napped t)
    (agent-workspace--loop-say agent 'note (concat "☾ " (agent-workspace-state-text agent)))
    (run-hook-with-args 'agent-workspace-nap-functions agent)))

;; ====== FAILURES ======

(defun agent-workspace--loop-failed (agent why)
  "AGENT's loop failed, WHY: it tries again in a moment, or stops after too
many in a row."
  (let ((n (1+ (or (agent-workspace--loop-get agent :failures) 0))))
    (agent-workspace--loop-put agent :failures n)
    (if (>= n agent-workspace-loop-failures)
        (agent-workspace--loop-stop agent n why)
      (agent-workspace--loop-cancel agent)
      (agent-workspace--loop-say agent 'note (format "↻ tries again in %ss: %d of %d failures in a row"
                                                     agent-workspace-loop-retry n agent-workspace-loop-failures))
      (agent-workspace--loop-put agent :timer (run-at-time agent-workspace-loop-retry nil
                                                           #'agent-workspace--loop-retry agent)))))

(defun agent-workspace--loop-stuck (agent)
  "AGENT, looping, got stuck (its turn's error, its session not started): a
failure, if it still is. Run once its error is set."
  (when (and (eq (agent-workspace-agent-state agent) 'stuck)
             (agent-workspace-agent-loop agent)
             (memq agent (agent-workspace-agents (agent-workspace-agent-project agent)))
             (not (agent-workspace--loop-get agent :stopped))
             (not (agent-workspace--loop-get agent :timer)))
    (agent-workspace--loop-failed agent (car (split-string (or (agent-workspace-agent-error agent) "an error")
                                                           "\n")))))

(defun agent-workspace--loop-retry (agent)
  "AGENT tries again after a failure: stuck, the same issue again in its
session (started again if it has none); at rest, it looks again."
  (agent-workspace--loop-put agent :timer nil)
  (when (and (agent-workspace-agent-loop agent)
             (memq agent (agent-workspace-agents (agent-workspace-agent-project agent)))
             (not (agent-workspace--loop-get agent :stopped)))
    (pcase (agent-workspace-agent-state agent)
      ('stuck
       ;; Its session started again if it has none, or no issue (then, at
       ;; the desk, it looks).
       (unless (and (agent-workspace-agent-issue agent) (buffer-live-p (agent-workspace-agent-buffer agent)))
         (let ((agent-workspace--loop-starting t))
           (agent-workspace--start agent)))
       (when (and (agent-workspace-agent-issue agent) (agent-workspace-live-p agent))
         (agent-workspace--loop-prompt agent)))
      ((or 'desk 'done 'nap) (agent-workspace--loop-look agent)))))

(defun agent-workspace--loop-stop (agent n why)
  "AGENT stops looping after N failures in a row, the last WHY: stuck,
saying so (its loop stays on: r, s or L start it again)."
  (let ((text (format "stopped looping, %d failures in a row: %s" n why)))
    (agent-workspace--loop-cancel agent)
    (agent-workspace--loop-put agent :stopped t)
    (setf (agent-workspace-agent-error agent) text)
    (if (eq (agent-workspace-agent-state agent) 'stuck)
        (progn (agent-workspace--changed agent 'state)
               (agent-workspace--loop-say agent 'stuck (concat "stuck: " text)))
      ;; Said by the room as it's stuck.
      (agent-workspace--set-state agent 'stuck))
    (agent-workspace--loop-watch-update (agent-workspace-agent-project agent))))

;; ====== WATCHING ITS ISSUES ======

(defun agent-workspace--loop-look-all (project)
  "PROJECT's looping agents at rest look for their next issue (a nap that
finds nothing says nothing)."
  (dolist (agent (agent-workspace-agents project))
    (when (and (agent-workspace--loop-active-p agent) (agent-workspace--loop-at-rest-p agent))
      (agent-workspace--loop-look agent))))

(defun agent-workspace--loop-changed (project)
  "PROJECT's .beads changed: its looping agents look in a moment (a burst
of changes: once)."
  (when-let* ((watch (gethash project agent-workspace--loop-watches)))
    (agent-workspace--loop-notify project watch)
    (when-let* ((timer (plist-get watch :soon)))
      (cancel-timer timer))
    (puthash project (plist-put watch :soon (run-at-time agent-workspace--loop-debounce nil
                                                         #'agent-workspace--loop-look-all project))
             agent-workspace--loop-watches)))

(defun agent-workspace--loop-notify (project watch)
  "WATCH's file-notify watches of PROJECT's .beads (the folder: files made
there; its last-touched: what bd changes), added where missing or gone."
  (let* ((beads (expand-file-name ".beads" project))
         (watches (seq-filter (lambda (entry) (file-notify-valid-p (car entry))) (plist-get watch :notify))))
    (dolist (file (list beads (expand-file-name "last-touched" beads)))
      (when (and (file-exists-p file) (not (rassoc file watches)))
        (when-let* ((descriptor (ignore-errors
                                  (file-notify-add-watch file '(change)
                                                         (lambda (_event) (agent-workspace--loop-changed project))))))
          (push (cons descriptor file) watches))))
    (puthash project (plist-put watch :notify watches) agent-workspace--loop-watches)))

(defun agent-workspace--loop-watch-update (project)
  "PROJECT's .beads watched, and looked at every few minutes, while an agent
of it loops (its session running); not otherwise."
  (let* ((key (agent-workspace--root project))
         (wanted (seq-some #'agent-workspace--loop-active-p (agent-workspace-agents key)))
         (watch (gethash key agent-workspace--loop-watches)))
    (cond
     ((and wanted (not watch))
      (let ((minutes agent-workspace-loop-check))
        (puthash key (list :timer (and (numberp minutes) (> minutes 0)
                                       (run-at-time (* 60 minutes) (* 60 minutes)
                                                    #'agent-workspace--loop-look-all key)))
                 agent-workspace--loop-watches)
        (agent-workspace--loop-notify key (gethash key agent-workspace--loop-watches))))
     ((and watch (not wanted))
      (agent-workspace--loop-unwatch key)))))

(defun agent-workspace--loop-unwatch (project)
  "PROJECT's .beads no longer watched."
  (when-let* ((watch (gethash project agent-workspace--loop-watches)))
    (dolist (entry (plist-get watch :notify))
      (ignore-errors (file-notify-rm-watch (car entry))))
    (dolist (key '(:timer :soon))
      (when-let* ((timer (plist-get watch key)))
        (cancel-timer timer)))
    (remhash project agent-workspace--loop-watches)))

;; ====== ITS HOOKS ======

(defun agent-workspace--loop-state-h (agent old new)
  "AGENT's state changed from OLD to NEW: its turn's end, a look (and one
for the looping agents waiting for it: `agent-workspace--loop-take');
stuck, a failure. In `agent-workspace-state-change-functions'."
  (when (and (memq old '(working hand)) (not (memq new '(working hand))))
    (dolist (other (agent-workspace-agents (agent-workspace-agent-project agent)))
      (when (eq (agent-workspace--loop-get other :waiting) agent)
        (agent-workspace--loop-put other :waiting nil)
        (agent-workspace--loop-soon other))))
  (when (eq new 'working)
    (puthash agent (agent-workspace-agent-buffer agent) agent-workspace--loop-turned))
  (when (agent-workspace-agent-loop agent)
    (when (memq new '(working hand asleep home))
      (agent-workspace--loop-cancel agent))
    (when (and (memq old '(working hand)) (memq new '(desk done)))
      ;; A turn that ended without an error: the row of failures broken.
      (agent-workspace--loop-put agent :failures nil)
      (agent-workspace--loop-put agent :stopped nil))
    (pcase new
      ((or 'desk 'done) (agent-workspace--loop-soon agent))
      ;; Its error is set after: read then.
      ('stuck (unless (agent-workspace--loop-get agent :stopped)
                (run-at-time 0 nil #'agent-workspace--loop-stuck agent))))
    (agent-workspace--loop-watch-update (agent-workspace-agent-project agent))))

(defun agent-workspace--loop-changed-h (agent what)
  "AGENT's WHAT changed: a session you started, its run begun again; gone
from its crew, its run ended. In `agent-workspace-change-functions'."
  (pcase what
    ('session
     (unless agent-workspace--loop-starting
       (agent-workspace--loop-reset agent)))
    ((or 'forgotten 'closed)
     (agent-workspace--loop-cancel agent)
     (agent-workspace--loop-watch-update (agent-workspace-agent-project agent)))))

(defun agent-workspace--loop-closing-h (project)
  "PROJECT's crew closing: its issues no longer watched. In
`agent-workspace-closing-functions'."
  (agent-workspace--loop-unwatch (agent-workspace--root project)))

(defun agent-workspace--loop-created-h (agent what)
  "AGENT just made (c, a crew, cmd/agent-workspace new, Lisp): its loop on,
said in the room after it joined, with `agent-workspace-loop', if its role
has labels and its project's issues are Beads'. Not one started again from
crew.json: its loop as crew.json says. In `agent-workspace-change-functions'."
  (when (and (eq what 'created)
             agent-workspace-loop
             (not (bound-and-true-p agent-workspace--crew-loading))
             (not (agent-workspace-agent-loop agent))
             (agent-workspace--loop-labels agent)
             (agent-workspace--loop-beads-p (agent-workspace-agent-project agent)))
    (agent-workspace-loop-set agent t)))

(add-hook 'agent-workspace-state-change-functions #'agent-workspace--loop-state-h)
(add-hook 'agent-workspace-change-functions #'agent-workspace--loop-changed-h)
;; After the others: the room says it joined first, crew.json keeps it.
(add-hook 'agent-workspace-change-functions #'agent-workspace--loop-created-h 90)
(add-hook 'agent-workspace-closing-functions #'agent-workspace--loop-closing-h)

;; ====== WHAT YOU DO ======

(defun agent-workspace-loop-set (agent on &optional why)
  "Turn AGENT's loop ON (non-nil) or off (WHY: said in the room). On, once
free it takes the next ready issue of its role's labels (now, if it is);
off, it no longer does (a napping one is at the desk). Return ON."
  (let ((on (and on t))
        (project (agent-workspace-agent-project agent)))
    (when (and on (not (agent-workspace-agent-loop agent)))
      (unless (agent-workspace--loop-labels agent)
        (user-error "%s's role, %s, has no labels: no issue is its to take"
                    (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)))
      (unless (agent-workspace--loop-beads-p project)
        (user-error "%s doesn't track its issues with Beads: a loop takes them"
                    (file-name-nondirectory (directory-file-name project)))))
    (unless (eq on (agent-workspace-agent-loop agent))
      (setf (agent-workspace-agent-loop agent) on)
      (agent-workspace--loop-reset agent)
      (agent-workspace--changed agent 'loop)
      (agent-workspace--loop-say
       agent 'note (if on
                       (format "↻ loops: once free, takes the next ready %s issue"
                               (string-join (agent-workspace--loop-labels agent) " or "))
                     (concat "stopped looping" (if why (concat ": " why) ""))))
      (cond (on (agent-workspace--loop-soon agent))
            ((eq (agent-workspace-agent-state agent) 'nap) (agent-workspace--set-state agent 'desk)))
      (agent-workspace--loop-watch-update project))
    on))

(defun agent-workspace-loop-here ()
  "Turn the agent's loop on or off (L): looping, once free it takes the
next ready issue of its role by itself, or naps."
  (interactive)
  (let* ((agent (agent-workspace--current))
         (name (agent-workspace-agent-name agent)))
    (if (agent-workspace-loop-set agent (not (agent-workspace-agent-loop agent)))
        (message "%s loops: once free, it takes the next ready %s issue%s" name
                 (string-join (agent-workspace--loop-labels agent) " or ")
                 (if (agent-workspace-live-p agent) "" " (once woken: s)"))
      (message "%s no longer loops" name))))

(defun agent-workspace-loop-wake (agent)
  "Wake AGENT if it naps: it looks for its next issue now, as when its
project's issues change (one ready, it takes it; none, it naps on, saying
nothing). For other parts (the inbox). Non-nil if it was napping."
  (when (and (eq (agent-workspace-agent-state agent) 'nap)
             (agent-workspace--loop-active-p agent))
    (agent-workspace--loop-look agent)
    t))

;; Looping, it takes its issues itself: never offered one in the room
;; (handover.el).
(add-hook 'agent-workspace-offer-skip-functions #'agent-workspace-agent-loop)
