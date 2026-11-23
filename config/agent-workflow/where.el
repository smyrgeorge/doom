;;; $DOOMDIR/config/agent-workflow/where.el -*- lexical-binding: t; -*-
;; Where a run's work is (its branch, base, commits, files changed), and
;; its own commits in your checkout (runs-in: checkout).
;; Loaded from config/agent-workflow.el, after queue.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)


;; ====== WHERE ITS WORK IS ======
;; A run's work is on its issue's branch, in its worktree: where it started
;; (your checkout's branch and commit then: its base), what its merge goes
;; into (the main branch), its own commits, those of its base branch the
;; merge takes too (a branch other than the main one), what isn't
;; committed, the snapshots its reading jobs read. Read from git when asked,
;; again a few seconds after.

(defvar agent-workflow--where-cache (make-hash-table :test #'eq :weakness 'key)
  "Each run's `agent-workflow-run-where' and when it was read: (TIME . WHERE).")

(defconst agent-workflow--where-age 3
  "Seconds after which a run's `agent-workflow-run-where' is read again.")

(defun agent-workflow-run-where (run &optional fresh)
  "Where RUN's work is: a plist, :worktree its folder (nil, gone), :branch
its issue's (nil: none yet), :deleted non-nil once its run deleted it
\(merged), :empty non-nil if it got no commit since it started (known), :base where it started (:branch B :commit C;
nil: unknown), :into what its merge goes into, :own its commits, :with
its base branch's the merge takes too, :uncommitted the files changed and
not committed, :merged non-nil once it's merged, :files its files changed
since its base (`agent-workflow--where-files'), :commits its latest
\((SHORT SUBJECT)...), :snapshots its reading jobs' ((JOB DIR COMMIT)...). Read from git if it was more than
`agent-workflow--where-age' seconds ago, or FRESH; nil if git can't say."
  (let ((cached (gethash run agent-workflow--where-cache)))
    (if (and cached (not fresh) (< (- (float-time) (car cached)) agent-workflow--where-age))
        (cdr cached)
      (let ((where (ignore-errors (agent-workflow--where-read run))))
        (puthash run (cons (float-time) where) agent-workflow--where-cache)
        where))))

(defun agent-workflow--where-read (run)
  "Where RUN's work is, read from git (see `agent-workflow-run-where')."
  (if (agent-workflow-run-checkout-p run)
      (agent-workflow--where-checkout run)
    (agent-workflow--where-worktree run)))

(defun agent-workflow--where-checkout (run)
  "Where RUN's work is, in your checkout (runs-in: checkout): its branch,
where it started, its own commits (its agents', not yours:
`agent-workflow--checkout-track') and the files they changed, how many
files aren't committed there; :checkout t, nothing merged or deleted."
  (let* ((project (file-name-as-directory (agent-workflow-run-project run)))
         (default-directory project)
         (branch (agent-workflow--checkout-branch project))
         (base (let ((base (agent-workflow-run-base run))) (and (plist-get base :commit) base)))
         (commits (agent-workflow--run-own-commits run))
         (own (length commits)))
    (list :checkout t
          :worktree project
          :branch (or branch "HEAD")
          :deleted nil
          :empty (and base (zerop own))
          :base base
          :into branch
          :own own
          :with 0
          :uncommitted (length (agent-workflow--git-lines "status" "--porcelain"))
          :merged nil
          :files (agent-workflow--where-own-files project commits)
          :commits (agent-workflow--where-own-commits project commits)
          :snapshots (delq nil (mapcar (lambda (job)
                                         (when-let* (((memq (plist-get (cdr job) :status) '(running waiting)))
                                                     (snapshot (plist-get (cdr job) :snapshot))
                                                     ((file-directory-p (nth 0 snapshot))))
                                           (list (car job) (nth 0 snapshot) (nth 2 snapshot))))
                                       (agent-workflow-run-jobs run))))))

(defun agent-workflow--where-worktree (run)
  "Where RUN's work is, on its own branch (`agent-workflow--where-read')."
  (let* ((project (agent-workflow-run-project run))
         (issue (agent-workflow-run-issue run))
         (default-directory project)
         (dir (agent-workflow-worktree-directory project issue))
         (live (file-exists-p (expand-file-name ".git" dir)))
         (made (or (and live (let ((default-directory dir))
                               (car (agent-workflow--git-lines "branch" "--show-current"))))
                   (agent-workflow--run-branch-made run)))
         (end (agent-workflow-run-branch-end run))
         (deleted (and (not made) (plist-get end :deleted) (plist-get end :branch)))
         (branch (or made deleted))
         (base (let ((base (agent-workflow-run-base run))) (and (plist-get base :commit) base)))
         (into (agent-workflow-main-branch project))
         (count (lambda (range)
                  (string-to-number (or (car (agent-workflow--git-lines "rev-list" "--count" range)) "0"))))
         (own (if made (funcall count (concat (or (plist-get base :commit) into) ".." made)) 0)))
    (list :worktree (and live dir)
          :branch branch
          :deleted (and deleted t)
          ;; No commit since it started (where it started known).
          :empty (if deleted (plist-get end :empty) (and made base (zerop own)))
          :base base
          :into into
          :own own
          :with (if (and base (not (equal (plist-get base :branch) into)))
                    (funcall count (concat into ".." (plist-get base :commit)))
                  0)
          :uncommitted (if live (let ((default-directory dir)) (length (agent-workflow--git-lines "status" "--porcelain")))
                         0)
          :merged (or (and made (> own 0)
                           (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" made into)))
                      deleted
                      ;; Its own commits unknown (where it started is), its
                      ;; merge done.
                      (seq-some (lambda (job)
                                  (and (eq (plist-get (cdr job) :status) 'done)
                                       (seq-some (lambda (step) (equal (plist-get step :uses) "merge"))
                                                 (plist-get (agent-workflow--job-spec run (car job)) :steps))))
                                (agent-workflow-run-jobs run)))
          :files (and live (agent-workflow--where-files dir (or (plist-get base :commit) into)))
          :commits (and made (agent-workflow--where-commits (if live dir project)
                                                            (or (plist-get base :commit) into) made))
          :snapshots (delq nil (mapcar (lambda (job)
                                         (when-let* (((memq (plist-get (cdr job) :status) '(running waiting)))
                                                     (snapshot (plist-get (cdr job) :snapshot))
                                                     ((file-directory-p (nth 0 snapshot))))
                                           (list (car job) (nth 0 snapshot) (nth 2 snapshot))))
                                       (agent-workflow-run-jobs run))))))

(defconst agent-workflow--where-commits-shown 5
  "A run's latest commits its where has, at most.")

(defun agent-workflow--where-own-files (dir commits)
  "The files COMMITS (a run's own in your checkout DIR, oldest first)
changed, as `agent-workflow--where-files' says them, in the order they
were first changed: added if its first change added it, deleted if its last deleted
it, its lines summed; a commit gone (rebased away, pruned) left out."
  (when commits
    (let* ((default-directory dir)
           (files nil))
      (dolist (line (apply #'agent-workflow--git-lines "log" "--no-walk=unsorted" "--ignore-missing" "--no-renames"
                           "--format=" "--numstat" commits))
        (pcase-let ((`(,added ,removed ,path) (split-string line "\t")))
          (when path
            (let ((file (or (assoc path files) (car (push (list path :added 0 :removed 0) files)))))
              (when (string-match-p "\\`[0-9]+\\'" added)
                (plist-put (cdr file) :added (+ (plist-get (cdr file) :added) (string-to-number added))))
              (when (string-match-p "\\`[0-9]+\\'" removed)
                (plist-put (cdr file) :removed (+ (plist-get (cdr file) :removed) (string-to-number removed))))))))
      (let ((statuses (mapcar (lambda (line) (split-string line "\t"))
                              (apply #'agent-workflow--git-lines "log" "--no-walk=unsorted" "--ignore-missing" "--no-renames"
                                     "--format=" "--name-status" commits))))
        (mapcar (lambda (file)
                  (let* ((path (car file))
                         (kinds (mapcar #'car (seq-filter (lambda (status) (equal (nth 1 status) path)) statuses))))
                    (list :path path
                          ;; Its statuses oldest first.
                          :status (cond ((equal (car (last kinds)) "D") 'deleted)
                                        ((equal (car kinds) "A") 'added)
                                        (t 'changed))
                          :added (plist-get (cdr file) :added)
                          :removed (plist-get (cdr file) :removed))))
                (nreverse files))))))

(defun agent-workflow--where-own-commits (dir commits)
  "COMMITS (a run's own in your checkout DIR, oldest first), the latest
first: ((SHORT SUBJECT)...), `agent-workflow--where-commits-shown' at most;
one gone left out."
  (when commits
    (let ((default-directory dir))
      ;; Unsorted, its order kept (sorted by date, those of one second came
      ;; in any order); never --max-count: git walks their parents then.
      (seq-take (mapcar (lambda (line) (split-string line "\t"))
                        (apply #'agent-workflow--git-lines "log" "--no-walk=unsorted" "--ignore-missing" "--format=%h%x09%s"
                               (reverse commits)))
                agent-workflow--where-commits-shown))))

;; ====== ITS COMMITS IN YOUR CHECKOUT ======
;; A run in your checkout (runs-in: checkout) works among your own commits:
;; its are those made while one of its agents worked, from its step's start
;; (or its fix's) to its done (or the run's end), noted then in its job's
;; state (:own; :head where it began), saved with it. Yours, before, between
;; and after, aren't its; one made while its agent worked is counted as its
;; (git can't tell them apart).

(defun agent-workflow--run-own-commits (run)
  "RUN's own commits in your checkout: its jobs' (:own, each oldest
first), each once."
  (delete-dups (cl-loop for job in (agent-workflow-run-jobs run) append (copy-sequence (plist-get (cdr job) :own)))))

(defun agent-workflow--checkout-head (run)
  "RUN's checkout's HEAD (a commit), or nil."
  (let ((default-directory (file-name-as-directory (agent-workflow-run-project run))))
    (car (agent-workflow--git-lines "rev-parse" "HEAD"))))

(defun agent-workflow--checkout-note (run job)
  "JOB of RUN's agent's work over: the commits made in your checkout since
it began (its :head) noted as its own (:own)."
  (when-let* ((head (plist-get (agent-workflow--job run job) :head)))
    (let* ((default-directory (file-name-as-directory (agent-workflow-run-project run)))
           (own (plist-get (agent-workflow--job run job) :own))
           (new (seq-remove (lambda (commit) (member commit own))
                            (agent-workflow--git-lines "rev-list" "--reverse" (concat head "..HEAD")))))
      (agent-workflow--job-set run job :head nil :own (append own new)))))

(defun agent-workflow--checkout-track (run event data)
  "RUN in your checkout: its agents' work's start and end (EVENT, its DATA)
noted, the commits made in between its own. In
`agent-workflow-journal-functions'."
  (when (agent-workflow-run-checkout-p run)
    (pcase event
      ((or "step-started" "fixing" "fix-script")
       ;; An agent at work, or an on-fail script: where HEAD was (a fix
       ;; after its step: still from its step's start).
       (when-let* (((or (plist-get data :agent) (equal event "fix-script")))
                   (job (plist-get data :job))
                   ((not (plist-get (agent-workflow--job run job) :head)))
                   (head (agent-workflow--checkout-head run)))
         (agent-workflow--job-set run job :head head)))
      ((or "step-ended" "fix-script-ended") (agent-workflow--checkout-note run (plist-get data :job)))
      ;; Over: its agents' work too (interrupted, it goes on: not over).
      ((or "cancelled" "failed" "run-done")
       (dolist (job (agent-workflow-run-jobs run))
         (agent-workflow--checkout-note run (car job)))))))

;; Before the pane's: it draws what's noted.
(add-hook 'agent-workflow-journal-functions #'agent-workflow--checkout-track -50)

(defun agent-workflow--where-files (dir base)
  "The files changed in the worktree DIR since BASE (a commit, a branch),
committed or not: ((:path P :status added|changed|deleted :added N
:removed N :uncommitted BOOL)...), in their order; a file new and not
tracked yet, added."
  (let* ((default-directory dir)
         (stats (mapcar (lambda (line) (split-string line "\t"))
                        (agent-workflow--git-lines "diff" "--numstat" "--no-renames" base)))
         (statuses (mapcar (lambda (line) (split-string line "\t"))
                           (agent-workflow--git-lines "diff" "--name-status" "--no-renames" base)))
         (untracked (agent-workflow--git-lines "ls-files" "--others" "--exclude-standard"))
         (uncommitted (append (agent-workflow--git-lines "diff" "--name-only" "HEAD") untracked))
         (count (lambda (text) (and text (string-match-p "\\`[0-9]+\\'" text) (string-to-number text)))))
    (append
     (mapcar (lambda (status)
               (let* ((path (nth 1 status))
                      (stat (seq-find (lambda (stat) (equal (nth 2 stat) path)) stats)))
                 (list :path path
                       :status (pcase (car status) ("A" 'added) ("D" 'deleted) (_ 'changed))
                       :added (funcall count (nth 0 stat))
                       :removed (funcall count (nth 1 stat))
                       :uncommitted (and (member path uncommitted) t))))
             statuses)
     (mapcar (lambda (path) (list :path path :status 'added :uncommitted t)) untracked))))

(defun agent-workflow--where-stamp (run)
  "What changes as RUN's place is worked on, read without git: the times
of its git folder's HEAD, index and HEAD's log (a commit, a reset, a
checkout, a file staged), nil if it has none. Equal twice: nothing
committed or staged there in between."
  (let* ((dir (if (agent-workflow-run-checkout-p run)
                  (agent-workflow-run-project run)
                (agent-workflow-worktree-directory (agent-workflow-run-project run) (agent-workflow-run-issue run))))
         (dot (expand-file-name ".git" dir))
         (git (cond ((file-directory-p dot) dot)
                    ((file-readable-p dot)
                     (with-temp-buffer
                       (insert-file-contents dot)
                       (and (re-search-forward "^gitdir: *\\(.+\\)$" nil t)
                            (expand-file-name (match-string 1) dir)))))))
    (when git
      (mapcar (lambda (name) (file-attribute-modification-time (file-attributes (expand-file-name name git))))
              '("HEAD" "index" "logs/HEAD")))))

(defun agent-workflow--where-commits (dir base branch)
  "BRANCH's commits since BASE, read in DIR, the latest first: ((SHORT
SUBJECT)...), `agent-workflow--where-commits-shown' at most."
  (let ((default-directory dir))
    (mapcar (lambda (line) (split-string line "\t"))
            (agent-workflow--git-lines "log" (format "--max-count=%d" agent-workflow--where-commits-shown)
                                       "--format=%h%x09%s" (concat base ".." branch)))))
