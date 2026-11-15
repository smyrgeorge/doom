;;; $DOOMDIR/config/agent-workspace/issues.el -*- lexical-binding: t; -*-
;; The app's issues, on its left: the work, beside the agents. Loaded from
;; config/agent-workspace.el, after app.el. No Doom here.
;;
;; The project's Beads issues (bd, in the background): in progress (each with
;; the avatar and state of the agent on it), ready (grouped by the role
;; they're for: a role whose labels they have; a role nobody in the crew has,
;; flagged), blocked (by what), done today (who, when). A title in full, on a
;; second row when long. Moving onto an issue in progress selects its agent.
;; Fetched again when the app opens, gr, and after an agent's bd command.

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

(defvar-local agent-workspace--issues-project nil "In the issue list: its project.")
(defvar-local agent-workspace--issues-data nil
  "In the issue list: its issues as last fetched, a plist: :doing :ready
:blocked :done (issue plists), :error.")
(defvar-local agent-workspace--issues-pending nil "In the issue list: its fetches running.")
(defvar-local agent-workspace--issues-hl nil "In the issue list: its highlight.")
(defvar-local agent-workspace--issues-timer nil "In the issue list: a fetch to come.")

(define-derived-mode agent-workspace-issues-mode special-mode "Issues"
  "A crew's issues: the work, beside its agents."
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
list of alists), or the symbol `error' and its output."
  (let* ((output (generate-new-buffer " *agent-workspace bd*"))
         (default-directory dir))
    (make-process :name "agent-workspace-bd" :buffer output
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

(defun agent-workspace--issues-refresh (project)
  "PROJECT's issues fetched again (bd, in the background), then drawn."
  (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--issues-buffer project))))
    (if (not (and (executable-find "bd") (file-directory-p (expand-file-name ".beads" project))))
        (with-current-buffer buffer
          (setq agent-workspace--issues-data (list :error "This project doesn't track its issues with Beads."))
          (agent-workspace--issues-redraw project))
      (with-current-buffer buffer
        (unless agent-workspace--issues-pending
          (let ((answers (list :all nil :ready nil :done nil))
                (left 3)
                (today (format-time-string "%Y-%m-%d")))
            (setq agent-workspace--issues-pending t)
            (cl-flet ((got (key)
                        (lambda (json)
                          (setq answers (plist-put answers key json))
                          (when (= (cl-decf left) 0)
                            (when (buffer-live-p buffer)
                              (with-current-buffer buffer
                                (setq agent-workspace--issues-pending nil
                                      agent-workspace--issues-data
                                      (agent-workspace--issues-parse project answers))
                                (agent-workspace--issues-redraw project)))))))
              (agent-workspace--bd project '("list" "--json" "--limit" "0") (got :all))
              (agent-workspace--bd project '("ready" "--json" "--limit" "0") (got :ready))
              (agent-workspace--bd project (list "list" "--json" "--status" "closed"
                                                 "--closed-after" today "--limit" "0")
                                   (got :done)))))))))

(defun agent-workspace--issues-refresh-soon (project)
  "PROJECT's issues fetched again in a moment (a burst of bd commands: once)."
  (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--issues-buffer project))))
    (with-current-buffer buffer
      (when (timerp agent-workspace--issues-timer) (cancel-timer agent-workspace--issues-timer))
      (setq agent-workspace--issues-timer
            (run-at-time 0.5 nil #'agent-workspace--issues-refresh project)))))

(defun agent-workspace--issue (alist &optional status)
  "Bd's ALIST as an issue plist (STATUS: its section's)."
  (list :id (alist-get 'id alist)
        :title (or (alist-get 'title alist) "")
        :status (or status (intern (or (alist-get 'status alist) "open")))
        :assignee (alist-get 'assignee alist)
        :labels (alist-get 'labels alist)
        :priority (alist-get 'priority alist)
        :type (alist-get 'issue_type alist)
        :closed (alist-get 'closed_at alist)
        :blocks (seq-keep (lambda (dep) (and (equal (alist-get 'type dep) "blocks")
                                             (alist-get 'depends_on_id dep)))
                          (alist-get 'dependencies alist))))

(defun agent-workspace--issue-role (project labels)
  "The first of PROJECT's roles whose labels LABELS has, or nil."
  (car (seq-find (lambda (role) (seq-intersection (plist-get (cdr role) :labels) labels))
                 (agent-workspace-roles project))))

(defun agent-workspace--issues-parse (project answers)
  "ANSWERS (bd's: :all, :ready, :done) as the list's sections."
  (if (seq-some (lambda (key) (eq (plist-get answers key) 'error)) '(:all :ready :done))
      (list :error "bd didn't answer: SPC o i shows why.")
    (let* ((all (mapcar #'agent-workspace--issue (plist-get answers :all)))
           (open-ids (mapcar (lambda (issue) (plist-get issue :id)) all))
           (ready-ids (mapcar (lambda (alist) (alist-get 'id alist)) (plist-get answers :ready)))
           (work (lambda (issue) (not (equal (plist-get issue :type) "epic"))))
           (by-priority (lambda (issues) (seq-sort-by (lambda (issue) (or (plist-get issue :priority) 9)) #'< issues))))
      (list :doing (seq-filter (lambda (issue) (eq (plist-get issue :status) 'in_progress)) all)
            :ready (funcall by-priority
                            (mapcar (lambda (issue)
                                      (plist-put (plist-put issue :status 'ready)
                                                 :role (agent-workspace--issue-role project (plist-get issue :labels))))
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
rest in REST, cut with … if longer still."
  (if (<= (string-width text) first)
      (list text)
    (let ((cut (let ((pos nil) (start 0))
                 (while (and (string-match " " text start) (<= (match-beginning 0) first))
                   (setq pos (match-beginning 0) start (1+ (match-beginning 0))))
                 (or pos first))))
      (list (substring text 0 cut)
            (agent-workspace--fit (string-trim-left (substring text cut)) rest)))))

(defun agent-workspace--issue-lines (project issue width)
  "ISSUE's rows (one, or two when its title is long): its agent's avatar,
its id, its title; on the right its agent's state, what blocks it, its
priority, or when it was done."
  (let* ((status (plist-get issue :status))
         (agent (and (memq status '(in_progress closed)) (agent-workspace--issue-agent project issue)))
         (avatar (if agent (agent-workspace-agent-avatar agent) "  "))
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
         (indent (+ 1 2 1 (string-width (plist-get issue :id)) 1))
         (titles (agent-workspace--wrap-title (plist-get issue :title)
                                              (max 8 (- width indent (string-width tail) 1))
                                              (max 8 (- width indent 1))))
         (first (concat " " avatar " " id " " (propertize (car titles) 'face title-face)
                        (propertize " " 'display `(space :align-to (- right ,end)))
                        tail)))
    (cons first
          (when (cadr titles)
            (list (concat (make-string indent ?\s) (propertize (cadr titles) 'face title-face)))))))

(defun agent-workspace--issues-lines (project data width)
  "The issue list's lines, each carrying its issue (and its agent)."
  (let ((lines nil))
    (cl-flet* ((head (title count)
                 (push (agent-workspace--at-right (concat " " (propertize title 'face '(shadow bold)))
                                                  (propertize (format "%s " count) 'face 'shadow)
                                                  width)
                       lines))
               (add (issue)
                 (let ((agent (and (eq (plist-get issue :status) 'in_progress)
                                   (agent-workspace--issue-agent project issue))))
                   (dolist (line (agent-workspace--issue-lines project issue width))
                     (push (propertize line 'agent-workspace-issue issue 'agent-workspace-agent agent) lines))))
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
                (mapc #'add issues))))
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
    (string-replace
     "%" "%%"
     (agent-workspace--at-right
      (concat " " (propertize "ISSUES" 'face 'bold) "  "
              (propertize (file-name-nondirectory (directory-file-name agent-workspace--issues-project))
                          'face 'shadow)
              (if agent-workspace--issues-pending (propertize "  ⟳" 'face 'shadow) ""))
      (concat (or (agent-workspace-tally (agent-workspace-agents agent-workspace--issues-project)) "") " ")
      (window-total-width)))))

(defun agent-workspace--issues-redraw (project)
  "PROJECT's issue list drawn again, the cursor on the issue it was on."
  (when-let* ((app (agent-workspace--app project))
              (buffer (agent-workspace--issues-buffer project)))
    (with-current-buffer buffer
      (let* ((window (get-buffer-window buffer t))
             (pos (if window (window-point window) (point)))
             (issue (plist-get (get-text-property pos 'agent-workspace-issue) :id))
             (start (and window (line-number-at-pos (window-start window))))
             (width (if window (max 20 (1- (window-body-width window))) (1- agent-workspace-issues-width)))
             (inhibit-read-only t))
        (erase-buffer)
        (if (not agent-workspace--issues-data)
            (insert (propertize "\n   Fetching the issues…\n" 'face 'shadow))
          (dolist (line (agent-workspace--issues-lines project agent-workspace--issues-data width))
            (insert (agent-ui-even-glyphs line)
                    (propertize "\n" 'agent-workspace-issue (get-text-property 0 'agent-workspace-issue line)
                                'agent-workspace-agent (get-text-property 0 'agent-workspace-agent line)))))
        (goto-char (point-min))
        (unless (and issue (agent-workspace--issues-goto-id issue))
          (unless (and (agent-workspace--app-selected app)
                       (agent-workspace--issues-goto-agent (agent-workspace--app-selected app)))
            (goto-char (point-min))
            (agent-workspace-issue-next 1)))
        (when window
          (set-window-start window (save-excursion (goto-char (point-min)) (forward-line (1- (or start 1))) (point)) t)
          (set-window-point window (point)))
        (agent-workspace--issues-highlight)))))

(defun agent-workspace--issues-goto-id (id)
  "The cursor on issue ID; non-nil if it's there."
  (goto-char (point-min))
  (when-let* ((match (text-property-search-forward 'agent-workspace-issue id
                                                   (lambda (id issue) (equal id (plist-get issue :id))))))
    (goto-char (prop-match-beginning match))))

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
  "RET on an issue: the pane of the agent on it, else the issue itself."
  (interactive)
  (let ((issue (get-text-property (point) 'agent-workspace-issue))
        (agent (get-text-property (point) 'agent-workspace-agent)))
    (cond (agent (agent-workspace-select agent t))
          ((and issue agent-workspace-open-issue-function)
           (funcall agent-workspace-open-issue-function (plist-get issue :id) agent-workspace--issues-project))
          (issue (message "%s: %s" (plist-get issue :id) (plist-get issue :title))))))

(defun agent-workspace-issue-give ()
  "Give the issue at point to an agent (the selected one offered first, then
its role's): free, it takes it now; working, after its turn."
  (interactive)
  (let* ((issue (or (get-text-property (point) 'agent-workspace-issue) (user-error "No issue here")))
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
           (how (agent-workspace-send agent (agent-workspace-issue-prompt (plist-get issue :id) (plist-get issue :title))
                                      :submit t)))
      (agent-workspace-give agent (plist-get issue :id) (plist-get issue :title))
      (message (if (eq how 'queued) "%s gets %s after its turn (busy)" "%s works on %s")
               name (plist-get issue :id))
      (agent-workspace-select agent))))

(defun agent-workspace-issues-refresh ()
  "The issues fetched again, the app laid out again."
  (interactive)
  (let ((app (agent-workspace--here-or-error)))
    (agent-workspace--issues-refresh (agent-workspace--app-project app))
    (agent-workspace-layout app)))

;; ====== AN AGENT'S BD COMMANDS ======

(defun agent-workspace--issues-watch (agent buffer)
  "AGENT's session BUFFER followed: a bd command done fetches its crew's
issues again. In `agent-workspace-session-functions'."
  (agent-shell-subscribe-to
   :shell-buffer buffer
   :event 'tool-call-update
   :on-event (lambda (event)
               (let* ((tool-call (map-nested-elt event '(:data :tool-call)))
                      (command (map-elt tool-call :command)))
                 (when (and (member (map-elt tool-call :status) '("completed" "failed"))
                            (stringp command)
                            (string-match-p "\\(?:^\\|[;&| ]\\)bd " command))
                   (agent-workspace--issues-refresh-soon (agent-workspace-agent-project agent)))))))

(add-hook 'agent-workspace-session-functions #'agent-workspace--issues-watch)

(defun agent-workspace--issues-changed-h (agent what)
  "AGENT's issue or state changed: the list's states drawn again, its issues
fetched again when given one."
  (when (eq what 'issue)
    (agent-workspace--issues-refresh-soon (agent-workspace-agent-project agent))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--issues-changed-h)
