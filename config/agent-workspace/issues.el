;;; $DOOMDIR/config/agent-workspace/issues.el -*- lexical-binding: t; -*-
;; The app's issues, on its left: the work, beside the agents. Loaded from
;; config/agent-workspace.el, after app.el. No Doom here.
;;
;; The project's Beads issues (bd, in the background), each with its type
;; before its id (the Beads panel's icon): in progress (each with the avatar
;; and state of the agent on it), ready (grouped by the role they're for: a
;; role whose labels they have; a role nobody in the crew has, flagged; then
;; by epic, their nearest open ancestor of that type, under its heading),
;; blocked (by what), done today (who, when). A title in full, on a second
;; row when long. Moving onto an issue in progress selects its agent.
;; Fetched again when the app opens, gr, after an agent's bd command (that
;; agent noted with what's fetched: the room says what it did, room.el) and
;; at the end of each of its turns; asked while a fetch runs, once it's done.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'map)

(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-ui-even-glyphs "agent-ui/core")

;; ====== VARIABLES ======

(defvar agent-workspace-issues-mode-map (make-sparse-keymap)
  "Keys in the issue list (set in config/agent-workspace.el).")

(defvar agent-workspace-issues-fetched-functions nil
  "Called with a project and its issues as just fetched (a plist: :doing
:ready :blocked :done, issue plists, for the list; :issues, every one as bd
has it, the open ones and those done today; :actor, the agent whose bd
command led to the fetch, its name; :error).")

(defvar-local agent-workspace--issues-project nil "In the issue list: its project.")
(defvar-local agent-workspace--issues-data nil
  "In the issue list: its issues as last fetched, a plist: :doing :ready
:blocked :done (issue plists), :error.")
(defvar-local agent-workspace--issues-pending nil
  "In the issue list: the fetch running, a plist: :processes (its bd
commands), :timer (its timeout).")

(defvar agent-workspace-issues-timeout 30
  "Seconds a fetch of the issues may take: longer (bd hanging: a lock, a
prompt), it's stopped, the list says so, and the next refresh fetches
again.")
(defvar-local agent-workspace--issues-again nil
  "In the issue list: a fetch asked for while one ran: done once it's over.")
(defvar-local agent-workspace--issues-actor nil
  "In the issue list: the agent whose bd command asks for the next fetch,
its name.")
(defvar-local agent-workspace--issues-hl nil "In the issue list: its highlight.")
(defvar-local agent-workspace--issues-timer nil "In the issue list: a fetch to come.")

(define-derived-mode agent-workspace-issues-mode special-mode "Issues"
  "A crew's issues: the work, beside its agents."
  ;; Drawn again and again: no undo kept of it.
  (buffer-disable-undo)
  (setq-local truncate-lines t
              mode-line-format nil
              tab-line-exclude t
              cursor-in-non-selected-windows nil
              header-line-format '(:eval (agent-workspace--issues-header)))
  (add-hook 'post-command-hook #'agent-workspace--issues-moved nil t))

(defun agent-workspace--issues-buffer (project)
  "PROJECT's issue list (made the first time)."
  (let ((name (format "*issues · %s*" (file-name-nondirectory (directory-file-name project)))))
    (or (seq-find (lambda (buffer) (equal (buffer-local-value 'agent-workspace--issues-project buffer)
                                          (agent-workspace--root project)))
                  (agent-workspace--app-buffers project))
        (with-current-buffer (generate-new-buffer name)
          (agent-workspace-issues-mode)
          (setq agent-workspace--issues-project (agent-workspace--root project)
                default-directory (agent-workspace--root project))
          (agent-workspace--app-buffer-add project (current-buffer))
          (current-buffer)))))

;; ====== FETCHING ======

(defun agent-workspace--bd (dir args callback)
  "Run bd with ARGS in DIR, in the background; CALLBACK with its JSON (a
list of alists), or the symbol `error' and its output. The process, marked
with its project (`agent-workspace--issues-stop')."
  (let* ((output (generate-new-buffer " *agent-workspace bd*"))
         (default-directory dir)
         (process
          (make-process
           :name "agent-workspace-bd" :buffer output
           :command (cons "bd" args) :connection-type 'pipe :noquery t
           :stderr (get-buffer-create " *agent-workspace bd errors*")
           :sentinel (lambda (process _event)
                       (unless (process-live-p process)
                         (let ((text (with-current-buffer output (buffer-string))))
                           (kill-buffer output)
                           (funcall callback
                                    (if (eql (process-exit-status process) 0)
                                        (condition-case nil
                                            (json-parse-string text :object-type 'alist :array-type 'list
                                                               :null-object nil :false-object nil)
                                          (error 'error))
                                      'error))))))))
    (process-put process 'agent-workspace-project (agent-workspace--root dir))
    process))

(defun agent-workspace--issues-stop (project)
  "PROJECT's issue list fetching nothing more: its refresh to come
cancelled, its bd commands running stopped (its app closing)."
  (when-let* ((buffer (seq-find (lambda (buffer) (buffer-local-value 'agent-workspace--issues-project buffer))
                                (agent-workspace--app-buffers project))))
    (agent-workspace--issues-fetch-stop buffer)
    (with-current-buffer buffer
      (when (timerp agent-workspace--issues-timer) (cancel-timer agent-workspace--issues-timer))
      (setq agent-workspace--issues-timer nil)))
  (dolist (process (process-list))
    (when (equal (process-get process 'agent-workspace-project) (agent-workspace--root project))
      (delete-process process))))

(defun agent-workspace--issues-refresh (project)
  "PROJECT's issues fetched again (bd, in the background), then drawn."
  (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--issues-buffer project))))
    (if (not (and (executable-find "bd") (file-directory-p (expand-file-name ".beads" project))))
        (with-current-buffer buffer
          (setq agent-workspace--issues-data (list :error "This project doesn't track its issues with Beads."))
          (agent-workspace--issues-redraw project))
      (with-current-buffer buffer
        (if agent-workspace--issues-pending
            ;; What it fetches may be from before: fetched again after it.
            (setq agent-workspace--issues-again t)
          (let ((answers (list :all nil :ready nil :done nil))
                (left 3)
                (today (format-time-string "%Y-%m-%d"))
                (actor agent-workspace--issues-actor)
                (fetch (list :processes nil :timer nil)))
            (setq agent-workspace--issues-pending fetch
                  agent-workspace--issues-actor nil)
            (cl-flet ((got (key)
                        (lambda (json)
                          (setq answers (plist-put answers key json))
                          (when (and (= (cl-decf left) 0)
                                     (buffer-live-p buffer)
                                     ;; Not one stopped (timed out, gr).
                                     (eq (buffer-local-value 'agent-workspace--issues-pending buffer) fetch))
                            (cancel-timer (plist-get fetch :timer))
                            (with-current-buffer buffer
                              (setq agent-workspace--issues-pending nil
                                    agent-workspace--issues-data
                                    (append (agent-workspace--issues-parse project answers)
                                            (list :actor actor)))
                              (agent-workspace--issues-redraw project)
                              (run-hook-with-args 'agent-workspace-issues-fetched-functions
                                                  project agent-workspace--issues-data)
                              (when agent-workspace--issues-again
                                (setq agent-workspace--issues-again nil)
                                (agent-workspace--issues-refresh project)))))))
              (plist-put fetch :timer (run-at-time agent-workspace-issues-timeout nil
                                                   #'agent-workspace--issues-timed-out project fetch))
              (plist-put fetch :processes
                         (list (agent-workspace--bd project '("list" "--json" "--limit" "0") (got :all))
                               (agent-workspace--bd project '("ready" "--json" "--limit" "0") (got :ready))
                               (agent-workspace--bd project (list "list" "--json" "--status" "closed"
                                                                  "--closed-after" today "--limit" "0")
                                                    (got :done)))))))))))

(defun agent-workspace--issues-fetch-stop (buffer)
  "The fetch BUFFER's issue list runs, stopped: its bd commands killed, its
answers never used. Non-nil if there was one."
  (with-current-buffer buffer
    (when-let* ((fetch agent-workspace--issues-pending))
      (setq agent-workspace--issues-pending nil)
      (when (timerp (plist-get fetch :timer)) (cancel-timer (plist-get fetch :timer)))
      (dolist (process (plist-get fetch :processes))
        (when (process-live-p process) (delete-process process)))
      t)))

(defun agent-workspace--issues-timed-out (project fetch)
  "PROJECT's FETCH still running after `agent-workspace-issues-timeout':
stopped, the list says so; one asked for meanwhile, started."
  (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--issues-buffer project)))
              ((eq (buffer-local-value 'agent-workspace--issues-pending buffer) fetch)))
    (agent-workspace--issues-fetch-stop buffer)
    (with-current-buffer buffer
      (setq agent-workspace--issues-data
            (list :error (format "bd didn't answer in %ss: gr fetches again." agent-workspace-issues-timeout)))
      (agent-workspace--issues-redraw project)
      (when agent-workspace--issues-again
        (setq agent-workspace--issues-again nil)
        (agent-workspace--issues-refresh project)))))

(defun agent-workspace--issues-refresh-soon (project &optional actor)
  "PROJECT's issues fetched again in a moment (a burst of bd commands: once).
ACTOR: the agent whose bd command asks for it, its name (the last one's
goes with what's fetched)."
  (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--issues-buffer project))))
    (with-current-buffer buffer
      (when actor (setq agent-workspace--issues-actor actor))
      (when (timerp agent-workspace--issues-timer) (cancel-timer agent-workspace--issues-timer))
      (setq agent-workspace--issues-timer
            (run-at-time 0.5 nil #'agent-workspace--issues-refresh project)))))

(defun agent-workspace--issue (alist &optional status)
  "Bd's ALIST as an issue plist (STATUS: its section's)."
  (list :id (alist-get 'id alist)
        :title (or (alist-get 'title alist) "")
        :status (or status (intern (or (alist-get 'status alist) "open")))
        :assignee (alist-get 'assignee alist)
        :created-by (alist-get 'created_by alist)
        :created (alist-get 'created_at alist)
        :labels (alist-get 'labels alist)
        :priority (alist-get 'priority alist)
        :type (alist-get 'issue_type alist)
        :parent (alist-get 'parent alist)
        :closed (alist-get 'closed_at alist)
        :blocks (seq-keep (lambda (dep) (and (equal (alist-get 'type dep) "blocks")
                                             (alist-get 'depends_on_id dep)))
                          (alist-get 'dependencies alist))))

(defun agent-workspace--issue-role (project labels)
  "The first of PROJECT's roles whose labels LABELS has, or nil."
  (car (seq-find (lambda (role) (seq-intersection (plist-get (cdr role) :labels) labels))
                 (agent-workspace-roles project))))

(defun agent-workspace--issue-epic (issue open)
  "ISSUE's epic: its nearest ancestor of type epic (its parent, or its
parent's parent... for a subtask) among OPEN (the open issues, as fetched),
as (:id ID :title TITLE); nil if it has none open."
  (let ((seen nil)
        (parent (plist-get issue :parent))
        (epic nil))
    (while (and parent (not epic) (not (member parent seen)))
      (push parent seen)
      (let ((up (seq-find (lambda (other) (equal (plist-get other :id) parent)) open)))
        (if (equal (plist-get up :type) "epic")
            (setq epic (list :id parent :title (plist-get up :title)))
          (setq parent (plist-get up :parent)))))
    epic))

(defun agent-workspace--issues-parse (project answers)
  "ANSWERS (bd's: :all, :ready, :done) as the list's sections. A ready
issue knows its role (:role) and its epic (:epic, see
`agent-workspace--issue-epic')."
  (if (seq-some (lambda (key) (eq (plist-get answers key) 'error)) '(:all :ready :done))
      (list :error "bd didn't answer: SPC o i shows why.")
    (let* ((all (mapcar #'agent-workspace--issue (plist-get answers :all)))
           (open-ids (mapcar (lambda (issue) (plist-get issue :id)) all))
           (ready-ids (mapcar (lambda (alist) (alist-get 'id alist)) (plist-get answers :ready)))
           (work (lambda (issue) (not (equal (plist-get issue :type) "epic"))))
           (by-priority (lambda (issues) (seq-sort-by (lambda (issue) (or (plist-get issue :priority) 9)) #'< issues))))
      (list :issues (mapcar #'agent-workspace--issue (append (plist-get answers :all) (plist-get answers :done)))
            :doing (seq-filter (lambda (issue) (eq (plist-get issue :status) 'in_progress)) all)
            :ready (funcall by-priority
                            (mapcar (lambda (issue)
                                      (plist-put (plist-put (plist-put issue :status 'ready)
                                                            :role (agent-workspace--issue-role project (plist-get issue :labels)))
                                                 :epic (agent-workspace--issue-epic issue all)))
                                    (seq-filter (lambda (issue) (and (funcall work issue)
                                                                     (member (plist-get issue :id) ready-ids)
                                                                     (eq (plist-get issue :status) 'open)))
                                                all)))
            :blocked (mapcar (lambda (issue)
                               (plist-put (plist-put issue :status 'blocked)
                                          :blocked-by (seq-filter (lambda (id) (member id open-ids))
                                                                  (plist-get issue :blocks))))
                             (seq-filter (lambda (issue) (and (funcall work issue)
                                                              (eq (plist-get issue :status) 'open)
                                                              (not (member (plist-get issue :id) ready-ids))))
                                         all))
            :done (seq-sort-by (lambda (issue) (or (plist-get issue :closed) "")) #'string>
                               (mapcar (lambda (alist) (agent-workspace--issue alist 'closed))
                                       (plist-get answers :done)))))))

;; ====== DRAWING ======

(defun agent-workspace--issue-agent (project issue)
  "The agent of PROJECT's crew on ISSUE (its assignee, or given it)."
  (seq-find (lambda (agent) (or (equal (agent-workspace-agent-name agent) (plist-get issue :assignee))
                                (equal (agent-workspace-agent-issue agent) (plist-get issue :id))))
            (agent-workspace-agents project)))

(defun agent-workspace--ago (time)
  "How long ago TIME (an ISO 8601 string) was: \"now\", \"5m\", \"2h\"."
  (let ((m (floor (- (float-time) (float-time (date-to-time time))) 60)))
    (cond ((< m 1) "now") ((< m 60) (format "%dm" m)) (t (format "%dh" (/ m 60))))))

(defun agent-workspace--wrap-title (text first rest)
  "TEXT on two rows at most: the words that fit in FIRST columns, then the
rest in REST, cut with … if longer still. No space to cut at (wide
characters, CJK): cut where FIRST columns end."
  (if (<= (string-width text) first)
      (list text)
    (let ((cut (let ((pos nil) (start 0))
                 (while (and (string-match " " text start)
                             (<= (string-width text 0 (match-beginning 0)) first))
                   (setq pos (match-beginning 0) start (1+ (match-beginning 0))))
                 (or pos (length (truncate-string-to-width text first))))))
      (list (substring text 0 cut)
            (agent-workspace--fit (string-trim-left (substring text cut)) rest)))))

(defun agent-workspace--issue-lines (project issue width &optional deeper)
  "ISSUE's rows (one, or two when its title is long): its agent's avatar,
its type (`agent-workspace-type-glyph', a column of its own), its id, its
title; on the right its agent's state, what blocks it, its priority, or when
it was done. DEEPER: that many columns further in (under its epic's
heading), its second row too."
  (let* ((status (plist-get issue :status))
         (agent (and (memq status '(in_progress closed)) (agent-workspace--issue-agent project issue)))
         (avatar (if agent (agent-workspace-agent-avatar agent) "  "))
         (type (agent-workspace-type-glyph (plist-get issue :type) (eq status 'closed)))
         (id (propertize (plist-get issue :id) 'face (if (eq status 'closed) 'shadow 'link)))
         (title-face (if (memq status '(closed blocked)) 'shadow 'default))
         (right (pcase status
                  ('in_progress (if agent (agent-workspace-state-glyph agent)
                                  (propertize (or (plist-get issue :assignee) "") 'face 'shadow)))
                  ('blocked (propertize (concat "⊘ " (string-join (plist-get issue :blocked-by) " ")) 'face 'shadow))
                  ('ready (if (eql (plist-get issue :priority) 1) (propertize "P1" 'face 'warning)
                            (if (eql (plist-get issue :priority) 0) (propertize "P0" 'face 'error) "")))
                  (_ (propertize (concat (or (plist-get issue :assignee) "") " "
                                         (if (plist-get issue :closed) (agent-workspace--ago (plist-get issue :closed)) ""))
                                 'face 'shadow))))
         (tail (agent-ui-even-glyphs (concat right " ")))
         (end (if (agent-workspace--graphic-p) (list (string-pixel-width tail)) (+ 2 (string-width tail))))
         (lead (make-string (1+ (or deeper 0)) ?\s))
         (indent (+ (length lead) 2 1 1 1 (string-width (plist-get issue :id)) 1))
         (titles (agent-workspace--wrap-title (plist-get issue :title)
                                              (max 8 (- width indent (string-width tail) 1))
                                              (max 8 (- width indent 1))))
         (first (concat lead avatar " " type " " id " " (propertize (car titles) 'face title-face)
                        (propertize " " 'display `(space :align-to (- right ,end)))
                        tail)))
    (cons first
          (when (cadr titles)
            (list (concat (make-string indent ?\s) (propertize (cadr titles) 'face title-face)))))))

(defun agent-workspace--by-epic (issues)
  "ISSUES (a role group's, ready, by priority) by their epic (:epic):
\((EPIC . ITS-ISSUES)...), the epics in the order of their first issue (a P1
brings its epic up), those of none (EPIC nil) last; each epic's issues in
their order."
  (let ((groups nil))
    (dolist (issue issues)
      (let* ((epic (plist-get issue :epic))
             (group (assoc (plist-get epic :id) groups)))
        (if group
            (push issue (cddr group))
          (push (cl-list* (plist-get epic :id) epic (list issue)) groups))))
    (let ((groups (mapcar (lambda (group) (cons (cadr group) (reverse (cddr group)))) (nreverse groups))))
      (append (seq-filter #'car groups) (seq-remove #'car groups)))))

(defun agent-workspace--issues-lines (project data width)
  "The issue list's lines, each carrying its issue (and its agent); in
READY, each role group's split by epic (`agent-workspace--by-epic'), under
their headings (each carrying its epic), when it has one."
  (let ((lines nil))
    (cl-flet* ((head (title count)
                 (push (agent-workspace--at-right (concat " " (propertize title 'face '(shadow bold)))
                                                  (propertize (format "%s " count) 'face 'shadow)
                                                  width)
                       lines))
               (add (issue &optional deeper)
                 (let ((agent (and (eq (plist-get issue :status) 'in_progress)
                                   (agent-workspace--issue-agent project issue))))
                   (dolist (line (agent-workspace--issue-lines project issue width deeper))
                     (push (propertize line 'agent-workspace-issue issue 'agent-workspace-agent agent) lines))))
               ;; An epic's heading in a role group: its icon (the epic
               ;; type's), id and title (cut to fit), how many of its
               ;; issues the group has; nil, "no epic".
               (epic-head (epic count role)
                 (push (propertize
                        (agent-workspace--at-right
                         (if epic
                             (concat "    " (agent-workspace-type-glyph "epic") " "
                                     (propertize (plist-get epic :id) 'face 'shadow) " "
                                     (propertize (or (plist-get epic :title) "") 'face 'bold))
                           (concat "    " (propertize "no epic" 'face 'shadow)))
                         (propertize (format "%d " count) 'face 'shadow)
                         width)
                        'agent-workspace-epic epic 'agent-workspace-role role)
                       lines))
               (note (text) (push (propertize (concat "   " text) 'face 'shadow) lines)))
      (if-let* ((error (plist-get data :error)))
          (note error)
        (let ((doing (plist-get data :doing)))
          (head "IN PROGRESS" (length doing))
          (mapc #'add doing)
          (unless doing (note "nobody on an issue"))
          (push "" lines))
        (let* ((ready (plist-get data :ready))
               (crew-roles (delete-dups (mapcar #'agent-workspace-agent-role (agent-workspace-agents project)))))
          (head "READY" (length ready))
          (dolist (role (append (mapcar #'car (agent-workspace-roles project)) '(nil)))
            (let ((issues (seq-filter (lambda (issue) (equal (plist-get issue :role) role)) ready)))
              (when issues
                (push (propertize
                       (concat "  "
                               (if role
                                   (concat (agent-workspace-glyph (let ((spec (agent-workspace--project-role project role)))
                                                                    (cons (and (plist-get spec :icon)
                                                                               (concat "nf-" (plist-get spec :icon)))
                                                                          (or (plist-get spec :glyph) "·")))
                                                                  'shadow)
                                           (propertize (format "%ss  %d" role (length issues)) 'face 'shadow)
                                           (if (member role crew-roles) ""
                                             (propertize "  nobody in the crew takes these" 'face 'warning)))
                                 (propertize (format "for any role  %d" (length issues)) 'face 'shadow)))
                       'agent-workspace-role role)
                      lines)
                ;; Under their epics, 2 columns further in; with none at
                ;; all, as they are.
                (let ((groups (agent-workspace--by-epic issues)))
                  (if (not (caar groups))
                      (mapc #'add issues)
                    (pcase-dolist (`(,epic . ,its) groups)
                      (epic-head epic (length its) role)
                      (dolist (issue its) (add issue 2))))))))
          (push "" lines))
        (when-let* ((blocked (plist-get data :blocked)))
          (head "BLOCKED" (length blocked))
          (mapc #'add blocked)
          (push "" lines))
        (let ((done (plist-get data :done)))
          (head "DONE TODAY" (length done))
          (mapc #'add (seq-take done 8))
          (when (> (length done) 8)
            (note (format "… and %d more" (- (length done) 8)))))))
    (nreverse lines)))

(defun agent-workspace--issues-header ()
  "The issue list's header line: the project, the crew's tally."
  (when agent-workspace--issues-project
    (agent-workspace--percent-escaped
     (agent-workspace--at-right
      (concat " " (propertize "ISSUES" 'face 'bold) "  "
              (propertize (file-name-nondirectory (directory-file-name agent-workspace--issues-project))
                          'face 'shadow)
              (if agent-workspace--issues-pending (propertize "  ⟳" 'face 'shadow) ""))
      (concat (or (agent-workspace-tally (agent-workspace-agents agent-workspace--issues-project)) "") " ")
      (window-total-width)))))

(defun agent-workspace--issues-redraw (project)
  "PROJECT's issue list drawn again, the cursor on the issue (or the epic's
heading) it was on."
  (when-let* ((app (agent-workspace--app project))
              (buffer (agent-workspace--issues-buffer project)))
    (with-current-buffer buffer
      (agent-workspace--in-drawing-frame
        (let* ((window (get-buffer-window buffer t))
               (pos (if window (window-point window) (point)))
               (issue (plist-get (get-text-property pos 'agent-workspace-issue) :id))
               (epic (and (not issue) (get-text-property pos 'agent-workspace-epic)
                          (cons (plist-get (get-text-property pos 'agent-workspace-epic) :id)
                                (get-text-property pos 'agent-workspace-role))))
               (start (and window (line-number-at-pos (window-start window))))
               (width (if window (max 20 (1- (window-body-width window))) (1- agent-workspace-issues-width)))
               (inhibit-read-only t))
          (erase-buffer)
          (if (not agent-workspace--issues-data)
              (insert (propertize "\n   Fetching the issues…\n" 'face 'shadow))
            (dolist (line (agent-workspace--issues-lines project agent-workspace--issues-data width))
              (insert (agent-ui-even-glyphs line)
                      (propertize "\n" 'agent-workspace-issue (get-text-property 0 'agent-workspace-issue line)
                                  'agent-workspace-agent (get-text-property 0 'agent-workspace-agent line)
                                  'agent-workspace-epic (get-text-property 0 'agent-workspace-epic line)
                                  'agent-workspace-role (get-text-property 0 'agent-workspace-role line)))))
          (goto-char (point-min))
          (unless (or (and issue (agent-workspace--issues-goto-id issue))
                      (and epic (agent-workspace--issues-goto-epic epic)))
            (unless (and (agent-workspace--app-selected app)
                         (agent-workspace--issues-goto-agent (agent-workspace--app-selected app)))
              (goto-char (point-min))
              (agent-workspace-issue-next 1)))
          (when window
            (set-window-start window (save-excursion (goto-char (point-min)) (forward-line (1- (or start 1))) (point)) t)
            (set-window-point window (point)))
          (agent-workspace--issues-highlight))))))

(defun agent-workspace--issues-goto-id (id)
  "The cursor on issue ID; non-nil if it's there."
  (goto-char (point-min))
  (when-let* ((match (text-property-search-forward 'agent-workspace-issue id
                                                   (lambda (id issue) (equal id (plist-get issue :id))))))
    (goto-char (prop-match-beginning match))))

(defun agent-workspace--issues-goto-epic (epic)
  "The cursor on EPIC's heading, (ID . ROLE): its id's, in its role's group;
non-nil if it's there."
  (goto-char (point-min))
  (let ((found nil))
    (while (and (not found) (not (eobp)))
      (let ((heading (get-text-property (point) 'agent-workspace-epic)))
        (if (and heading (equal (plist-get heading :id) (car epic))
                 (equal (get-text-property (point) 'agent-workspace-role) (cdr epic)))
            (setq found t)
          (forward-line 1))))
    found))

(defun agent-workspace--issues-goto-agent (agent)
  "The issue list's cursor on AGENT's issue in progress, if it has one."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent)))
              (buffer (agent-workspace--issues-buffer (agent-workspace-agent-project agent))))
    (with-current-buffer buffer
      (let ((pos (point)))
        (goto-char (point-min))
        (if-let* ((match (text-property-search-forward 'agent-workspace-agent agent #'eq)))
            (progn (goto-char (prop-match-beginning match))
                   (when-let* ((window (get-buffer-window buffer t)))
                     (set-window-point window (point)))
                   (agent-workspace--issues-highlight)
                   t)
          (goto-char pos)
          nil)))))

(defun agent-workspace--issues-highlight ()
  "The issue at point highlighted: its rows."
  (let* ((window (get-buffer-window (current-buffer) t))
         (pos (if window (window-point window) (point))))
    (unless (overlayp agent-workspace--issues-hl)
      (setq agent-workspace--issues-hl (make-overlay 1 1))
      (overlay-put agent-workspace--issues-hl 'face 'hl-line))
    (if (get-text-property pos 'agent-workspace-issue)
        (move-overlay agent-workspace--issues-hl
                      (or (previous-single-property-change (1+ pos) 'agent-workspace-issue) (point-min))
                      (or (next-single-property-change pos 'agent-workspace-issue) (point-max)))
      (move-overlay agent-workspace--issues-hl 1 1))))

(defun agent-workspace--issues-agent-at ()
  "In the issue list, the agent on the issue at point, or nil."
  (and (derived-mode-p 'agent-workspace-issues-mode)
       (get-text-property (point) 'agent-workspace-agent)))

(defun agent-workspace--issues-moved ()
  "After a command in the issue list: on an issue in progress, its agent
selected (its pane opens). The highlight follows."
  (let ((agent (get-text-property (point) 'agent-workspace-agent)))
    (when (and agent (not (eq agent (agent-workspace--app-selected
                                     (agent-workspace--app agent-workspace--issues-project)))))
      (agent-workspace-select agent)))
  (agent-workspace--issues-highlight))

;; ====== ITS COMMANDS ======

(defun agent-workspace-issue-next (&optional n)
  "The next issue in the list (N: that many; back if negative)."
  (interactive "p")
  (let ((n (or n 1)))
    (dotimes (_ (abs n))
      (let* ((start (point))
             (here (get-text-property (point) 'agent-workspace-issue))
             (run-start (lambda (pos) (or (previous-single-property-change (1+ pos) 'agent-workspace-issue)
                                          (point-min)))))
        (if (> n 0)
            (let ((pos (or (and here (next-single-property-change (point) 'agent-workspace-issue)) (point))))
              (while (and pos (< pos (point-max)) (not (get-text-property pos 'agent-workspace-issue)))
                (setq pos (next-single-property-change pos 'agent-workspace-issue)))
              (goto-char (if (and pos (< pos (point-max))) pos start)))
          (let ((pos (if here (funcall run-start (point)) (point))))
            (setq pos (and (> pos (point-min)) (1- pos)))
            (while (and pos (> pos (point-min)) (not (get-text-property pos 'agent-workspace-issue)))
              (setq pos (1- pos)))
            (goto-char (if (and pos (get-text-property pos 'agent-workspace-issue)) (funcall run-start pos) start))))))))

(defun agent-workspace-issue-previous (&optional n)
  "The previous issue in the list."
  (interactive "p")
  (agent-workspace-issue-next (- (or n 1))))

(defun agent-workspace-issue-open ()
  "RET on an issue: the pane of the agent on it, else the issue itself; on
an epic's heading, the epic."
  (interactive)
  (let ((issue (or (get-text-property (point) 'agent-workspace-issue)
                   (get-text-property (point) 'agent-workspace-epic)))
        (agent (get-text-property (point) 'agent-workspace-agent)))
    (cond (agent (agent-workspace-select agent t))
          ((and issue agent-workspace-open-issue-function)
           (funcall agent-workspace-open-issue-function (plist-get issue :id) agent-workspace--issues-project))
          (issue (message "%s: %s" (plist-get issue :id) (plist-get issue :title))))))

;; ====== GIVING ONE ======

(defvar agent-workspace-claim-timeout 10
  "Seconds bd may take to claim an issue you give an agent: longer, it's
stopped and nothing is given.")

(defun agent-workspace--bd-claim (agent id)
  "Issue ID claimed in bd for AGENT, as AGENT (BEADS_ACTOR its name), now:
in progress and AGENT's, so no looping agent takes it while its prompt
waits for its turn to end. nil once claimed (AGENT's already too), or with
nothing to claim it in (no bd, its project's issues not tracked by Beads);
else why not, in bd's words (another agent has it)."
  (let ((project (agent-workspace-agent-project agent)))
    (when (and (executable-find "bd") (file-directory-p (expand-file-name ".beads" project)))
      (with-temp-buffer
        (let* ((default-directory project)
               (process-environment (cons (concat "BEADS_ACTOR=" (agent-workspace-agent-name agent))
                                          process-environment))
               (process (make-process :name "agent-workspace-claim" :buffer (current-buffer)
                                      :command (list "bd" "update" id "--claim")
                                      :connection-type 'pipe :noquery t :sentinel #'ignore))
               (end (+ (float-time) agent-workspace-claim-timeout)))
          (while (and (process-live-p process) (< (float-time) end))
            (accept-process-output process 0.05))
          (cond ((process-live-p process)
                 (delete-process process)
                 (format "bd didn't answer in %ss" agent-workspace-claim-timeout))
                ((not (eql (process-exit-status process) 0))
                 (let ((line (or (seq-find (lambda (line) (not (string-empty-p line)))
                                           (mapcar #'string-trim (split-string (buffer-string) "\n")))
                                 "bd failed")))
                   ;; "Error updating demo-1: issue already claimed by ken"
                   (if (string-match "\\`Error updating [^ ]+: \\(.+\\)" line) (match-string 1 line) line)))))))))

(defun agent-workspace--bd-give-back (agent id)
  "Issue ID, claimed for AGENT: open again, unassigned, if it's still
AGENT's and in progress (bd as AGENT, in the background; nothing without
bd or Beads in its project). bd failing is said in the room, in its words;
not the issue no longer AGENT's (closed, someone else's: bd's 13)."
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-name agent))
         (default-directory project)
         (process-environment (cons (concat "BEADS_ACTOR=" name) process-environment)))
    (when (and (executable-find "bd") (file-directory-p (expand-file-name ".beads" project)))
      (let ((output (generate-new-buffer " *agent-workspace give back*")))
        (condition-case err
            (make-process
             :name "agent-workspace-give-back" :buffer output :noquery t :connection-type 'pipe
             :command (list "bd" "update" id (concat "--if-assignee=" name) "--if-status=in_progress"
                            "--status=open" "--assignee=")
             :sentinel (lambda (process _event)
                         (unless (process-live-p process)
                           (let ((status (process-exit-status process))
                                 (text (with-current-buffer output (buffer-string))))
                             (kill-buffer output)
                             (unless (memq status '(0 13))
                               (agent-workspace--give-back-failed
                                project name id
                                (or (seq-find (lambda (line) (not (string-empty-p line)))
                                              (mapcar #'string-trim (split-string text "\n")))
                                    (format "bd failed (%s)" status))))))))
          (error
           (kill-buffer output)
           (agent-workspace--give-back-failed project name id (error-message-string err))))))))

(defun agent-workspace--give-back-failed (project name id why)
  "Issue ID not given back for the agent NAME of PROJECT, WHY: said in its
room (and as a message)."
  (let ((text (format "couldn't give %s back: %s" id why)))
    (message "%s %s" name text)
    (when (fboundp 'agent-workspace-room-post)
      (agent-workspace-room-post project :kind 'note :agent name :text text))))

(defun agent-workspace-give-issue (agent id title &optional type)
  "Issue ID (its TITLE, TYPE: bd's issue_type) given to AGENT by you (t,
an offer's button): claimed in bd as AGENT at once, so no looping agent
takes it meanwhile; its branch for it (`agent-workspace-give'); then sent
\"Work on ID: TITLE\", now if AGENT is free, after its turn if it's working
\(`queued' then). A user error, nothing given: AGENT asleep or gone, the
claim refused (another agent has it), its branch not opened (changes not
committed: the claim given back)."
  (agent-workspace--live-or-error agent)
  (when-let* ((why (agent-workspace--bd-claim agent id)))
    (user-error "%s not given to %s: %s" id (agent-workspace-agent-name agent) why))
  (condition-case err
      (agent-workspace-give agent id title type)
    (error
     (agent-workspace--bd-give-back agent id)
     (signal (car err) (cdr err))))
  (agent-workspace-send agent (agent-workspace-issue-prompt id title) :submit t))

(defun agent-workspace-issue-give ()
  "Give the issue at point to an agent (the selected one offered first, then
its role's): free, it takes it now; working, after its turn. Claimed for it
in bd at once, its branch for it first (`agent-workspace-give-issue'):
refused if another agent has it, or its worktree has changes not
committed."
  (interactive)
  (let* ((issue (or (get-text-property (point) 'agent-workspace-issue)
                    (when-let* ((epic (get-text-property (point) 'agent-workspace-epic)))
                      (user-error "%s is an epic: give one of its issues" (plist-get epic :id)))
                    (user-error "No issue here")))
         (project agent-workspace--issues-project)
         (app (agent-workspace--app project))
         (agents (agent-workspace--ordered project))
         (selected (agent-workspace--app-selected app))
         (agents (append (and selected (list selected))
                         (seq-filter (lambda (a) (equal (agent-workspace-agent-role a) (plist-get issue :role))) agents)
                         agents))
         (names (delete-dups (mapcar #'agent-workspace-agent-name agents))))
    (unless (memq (plist-get issue :status) '(ready blocked))
      (user-error "%s isn't waiting for anyone" (plist-get issue :id)))
    (unless names (user-error "No agents yet: c makes one"))
    (let* ((name (completing-read (format "Give %s to: " (plist-get issue :id)) names nil t nil nil (car names)))
           (agent (agent-workspace-agent name project))
           (how (agent-workspace-give-issue agent (plist-get issue :id) (plist-get issue :title)
                                            (plist-get issue :type))))
      (message (if (eq how 'queued) "%s gets %s after its turn (busy)" "%s works on %s")
               name (plist-get issue :id))
      (agent-workspace-select agent))))

(defun agent-workspace-issue-type (project id)
  "PROJECT's issue ID's type (bd's issue_type: \"bug\"...), as last fetched,
or nil."
  (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--issues-buffer project)))
              (data (buffer-local-value 'agent-workspace--issues-data buffer)))
    (plist-get (seq-find (lambda (issue) (equal (plist-get issue :id) id))
                         (append (plist-get data :doing) (plist-get data :ready)
                                 (plist-get data :blocked) (plist-get data :done)))
               :type)))

(defun agent-workspace-issues-ready (project)
  "PROJECT's ready issues, as its app's issue list last fetched them (each
with its :role), or `none' if it fetched none (no app, not yet, bd
failing): nothing run for it."
  (let ((data (and (agent-workspace--app project)
                   (buffer-local-value 'agent-workspace--issues-data (agent-workspace--issues-buffer project)))))
    (if (or (not data) (plist-get data :error)) 'none (plist-get data :ready))))

(defun agent-workspace-issues-refresh ()
  "The issues fetched again (a fetch still running stopped first: it may
hang), the app laid out again."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app)))
    (agent-workspace--issues-fetch-stop (agent-workspace--issues-buffer project))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (setq agent-workspace--issues-again nil))
    (agent-workspace--issues-refresh project)
    (agent-workspace-layout app)))

;; ====== AN AGENT'S BD COMMANDS ======

(defun agent-workspace--bd-command-p (command)
  "Non-nil if COMMAND, an agent's shell command, may run bd: bd in it, a
word of its own (on any of its lines, in a variable)."
  (string-match-p "\\(?:^\\|[^[:alnum:]_-]\\)bd\\(?:$\\|[^[:alnum:]_-]\\)" command))

(defun agent-workspace--issues-watch (agent buffer)
  "AGENT's session BUFFER followed: a command of its with bd in it, done,
fetches its crew's issues again, noted as AGENT's; its turn's end too
\(bd run otherwise: a script, a variable). In
`agent-workspace-session-functions'."
  (agent-shell-subscribe-to
   :shell-buffer buffer
   :event 'tool-call-update
   :on-event (lambda (event)
               (let* ((tool-call (map-nested-elt event '(:data :tool-call)))
                      (command (map-elt tool-call :command)))
                 (when (and (member (map-elt tool-call :status) '("completed" "failed"))
                            (stringp command)
                            (agent-workspace--bd-command-p command))
                   (agent-workspace--issues-refresh-soon (agent-workspace-agent-project agent)
                                                         (agent-workspace-agent-name agent))))))
  (agent-shell-subscribe-to
   :shell-buffer buffer
   :event 'turn-complete
   :on-event (lambda (_event)
               (agent-workspace--issues-refresh-soon (agent-workspace-agent-project agent)))))

(add-hook 'agent-workspace-session-functions #'agent-workspace--issues-watch)

(defun agent-workspace--issues-changed-h (agent what)
  "AGENT's issue or state changed: the list's states drawn again, its issues
fetched again when given one."
  (when (eq what 'issue)
    (agent-workspace--issues-refresh-soon (agent-workspace-agent-project agent))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--issues-changed-h)
