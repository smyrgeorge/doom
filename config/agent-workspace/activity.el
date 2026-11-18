;;; $DOOMDIR/config/agent-workspace/activity.el -*- lexical-binding: t; -*-
;; What each agent of a crew did, minute by minute: the minimap's data.
;; Loaded from config/agent-workspace.el, after app.el. No Doom here.
;;
;; From agent-shell's events, never polled: each tool call's kind (read,
;; edit, run, search...) and where (its locations: a file, a line, taken
;; relative to the agent's worktree, so every agent is on the same map of the
;; project); a hand raised (asked you). Kept in memory, for the last
;; `agent-workspace-activity-minutes' minutes, a minute a bucket of what it
;; did; and where it was last, and when: where it is in its turn while it
;; works (`agent-workspace-activity-where'). Never saved.
;;
;; Each agent's changed files: the files it writes (agent-shell's
;; file-write), and at its turn's end its branch's changes against the main
;; checkout's branch and its uncommitted files (git, in its worktree). A file
;; two agents change means a merge conflict later: `agent-workspace-conflicts'.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'map)

(declare-function agent-shell-subscribe-to "agent-shell")

;; ====== VARIABLES ======

(defcustom agent-workspace-activity-minutes 15
  "How many minutes of each agent's activity are kept (the minimap's lanes)."
  :type 'natnum
  :group 'agent-workspace)

(defvar agent-workspace--activity (make-hash-table :test #'eq :weakness 'key)
  "Each agent's activity: a plist, :minutes ((MINUTE . KINDS)...), the
latest first, MINUTE a minute's number (`float-time' / 60), KINDS what it did
then (read, edit, run, asked); :location (FILE . LINE), where it was last,
in this turn or one before; :located, when (a `float-time'); :changed, the
files it changed (relative to its worktree).")

(defconst agent-workspace--tool-kinds
  '(("read" . read) ("search" . read) ("fetch" . read) ("think" . read)
    ("edit" . edit) ("delete" . edit) ("move" . edit)
    ("execute" . run))
  "A tool call's kind (ACP's) as an activity.")

;; ====== RECORDING IT ======

(defun agent-workspace--minute (&optional time)
  "TIME's minute (default: now): its number."
  (floor (or time (float-time)) 60))

(defun agent-workspace-activity (agent)
  "AGENT's activity (see `agent-workspace--activity')."
  (gethash agent agent-workspace--activity))

(defun agent-workspace--did (agent kind &optional location)
  "AGENT did KIND now (read, edit, run, asked), at LOCATION (FILE . LINE),
FILE relative to its worktree; its old minutes forgotten."
  (let* ((activity (agent-workspace-activity agent))
         (minute (agent-workspace--minute))
         (minutes (seq-filter (lambda (entry) (> (car entry) (- minute agent-workspace-activity-minutes)))
                              (plist-get activity :minutes))))
    (if (eql (caar minutes) minute)
        (cl-pushnew kind (cdar minutes))
      (push (list minute kind) minutes))
    (setq activity (plist-put activity :minutes minutes))
    (when location
      (setq activity (plist-put (plist-put activity :location location) :located (float-time))))
    (puthash agent activity agent-workspace--activity)
    (agent-workspace--changed agent 'activity)))

(defun agent-workspace-activity-where (agent)
  "Where AGENT is in its turn: (FILE . LINE), its last tool call's with a
file, if it came in this turn (since it started:
`agent-workspace-agent-since', a prompt sent); nil before its turn's first
file, and at rest (done, at the desk: no turn). Where it was last, whatever
the turn: its activity's :location."
  (when-let* ((since (agent-workspace-agent-since agent))
              (activity (agent-workspace-activity agent))
              (located (plist-get activity :located))
              ((>= located since)))
    (plist-get activity :location)))

(defun agent-workspace--relative (agent path)
  "PATH relative to AGENT's worktree, if it's in it; else as it is. In it by
its name first, the file system not asked (`file-in-directory-p' is, its
truenames and inodes: on a busy machine it once said no, the path kept
whole); else by its truename (a link's name)."
  (let* ((worktree (agent-workspace-agent-worktree agent))
         (dir (and worktree (file-name-as-directory (expand-file-name worktree))))
         (path (and (stringp path) (expand-file-name path worktree))))
    (cond ((not path) nil)
          ((and dir (or (string-prefix-p dir path) (file-in-directory-p path dir)))
           (file-relative-name path dir))
          (t (abbreviate-file-name path)))))

(defun agent-workspace--tool-location (agent tool-call)
  "Where TOOL-CALL is: (FILE . LINE) from its first location, or nil."
  (when-let* ((locations (map-elt tool-call :locations))
              (first (if (vectorp locations) (and (> (length locations) 0) (aref locations 0)) (car locations)))
              (file (agent-workspace--relative agent (map-elt first 'path))))
    (cons file (map-elt first 'line))))

(defun agent-workspace--activity-event (agent event)
  "AGENT's session emitted EVENT: what it did, recorded."
  (let ((data (alist-get :data event)))
    (pcase (alist-get :event event)
      ('tool-call-update
       (let* ((tool-call (alist-get :tool-call data))
              (kind (cdr (assoc (map-elt tool-call :kind) agent-workspace--tool-kinds))))
         (when kind
           (agent-workspace--did agent kind (agent-workspace--tool-location agent tool-call)))))
      ((or 'permission-request 'elicitation-request)
       (agent-workspace--did agent 'asked))
      ('file-write
       (when-let* ((file (agent-workspace--relative agent (alist-get :path data))))
         (agent-workspace--add-changed agent (list file))
         (agent-workspace--did agent 'edit (cons file nil))))
      ('turn-complete
       (agent-workspace--branch-changes-later agent)))))

(defun agent-workspace--activity-watch (agent buffer)
  "AGENT's session BUFFER followed for what it does. In
`agent-workspace-session-functions'."
  (agent-shell-subscribe-to
   :shell-buffer buffer
   :on-event (lambda (event)
               (when (eq (agent-workspace-agent-buffer agent) buffer)
                 (agent-workspace--activity-event agent event)))))

(add-hook 'agent-workspace-session-functions #'agent-workspace--activity-watch)

;; ====== ITS CHANGED FILES ======

(defvar agent-workspace--changes-since (make-hash-table :test #'eq :weakness 'key)
  "An agent whose changed files git works out: those noted meanwhile (a
file written), kept with git's answer.")

(defun agent-workspace--main-head (project)
  "The branch PROJECT's main checkout is on, read from its .git/HEAD (git not
run), or nil (a commit checked out, a .git file)."
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents (expand-file-name ".git/HEAD" project))
      (and (looking-at "ref: refs/heads/\\(.+\\)") (match-string 1)))))

(defun agent-workspace--branch-changes-later (agent)
  "The files AGENT's worktree changed worked out in the background (git,
Emacs not waiting: a big worktree takes a while), then noted as all of
them: its branch's against the main checkout's branch, and its uncommitted
ones (relative to its worktree)."
  (when-let* ((dir (agent-workspace-agent-worktree agent))
              ((file-directory-p dir)))
    (let* ((project (agent-workspace-agent-project agent))
           (main (or (agent-workspace--main-head project)
                     (ignore-errors (agent-workspace-main-branch project))))
           (default-directory dir)
           (left 0)
           (files nil))
      (puthash agent nil agent-workspace--changes-since)
      (cl-flet ((run (args parse)
                  (setq left (1+ left))
                  (let ((output (generate-new-buffer " *agent-workspace changes*")))
                    (make-process
                     :name "agent-workspace-changes" :buffer output :noquery t :connection-type 'pipe
                     :command (cons "git" args)
                     :stderr (get-buffer-create " *agent-workspace changes errors*")
                     :sentinel (lambda (process _event)
                                 (unless (process-live-p process)
                                   (let ((lines (with-current-buffer output (split-string (buffer-string) "\n" t))))
                                     (kill-buffer output)
                                     (when (eql 0 (process-exit-status process))
                                       (setq files (append files (funcall parse lines))))
                                     (when (= (setq left (1- left)) 0)
                                       (let ((since (gethash agent agent-workspace--changes-since)))
                                         (remhash agent agent-workspace--changes-since)
                                         (agent-workspace--add-changed agent (delete-dups (append files since)) t))))))))))
        (when main
          (run (list "diff" "--name-only" (concat main "...HEAD")) #'identity))
        (run (list "status" "--porcelain")
             (lambda (lines)
               (mapcar (lambda (line) (string-trim (substring line 3)))
                       (seq-filter (lambda (line) (> (length line) 3)) lines))))))))

(defun agent-workspace--add-changed (agent files &optional replace)
  "FILES among AGENT's changed ones (REPLACE: they're all of them now)."
  ;; git working them out meanwhile: kept with its answer.
  (unless (or replace (eq (gethash agent agent-workspace--changes-since :none) :none))
    (puthash agent (append files (gethash agent agent-workspace--changes-since)) agent-workspace--changes-since))
  (let* ((activity (agent-workspace-activity agent))
         (changed (if replace files (delete-dups (append files (plist-get activity :changed))))))
    (unless (equal changed (plist-get activity :changed))
      (puthash agent (plist-put activity :changed changed) agent-workspace--activity)
      (agent-workspace--changed agent 'activity))))

(defun agent-workspace-conflicts (&optional project)
  "The files two agents or more of PROJECT's crew changed: ((FILE AGENT...)
...), by file."
  (let ((by-file (make-hash-table :test #'equal)))
    (dolist (agent (agent-workspace-agents project))
      (dolist (file (plist-get (agent-workspace-activity agent) :changed))
        (push agent (gethash file by-file))))
    (sort (cl-loop for file being the hash-keys of by-file using (hash-values agents)
                   when (cdr agents) collect (cons file (reverse agents)))
          (lambda (a b) (string< (car a) (car b))))))

;; ====== ITS LANE ======

(defun agent-workspace-activity-lane (agent &optional now)
  "AGENT's last `agent-workspace-activity-minutes' minutes up to NOW (a
`float-time'), the oldest first: what it did in each (a list of kinds, nil
for none)."
  (let ((minute (agent-workspace--minute now))
        (minutes (plist-get (agent-workspace-activity agent) :minutes)))
    (cl-loop for m from (- minute agent-workspace-activity-minutes -1) to minute
             collect (cdr (assq m minutes)))))
