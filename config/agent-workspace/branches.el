;;; $DOOMDIR/config/agent-workspace/branches.el -*- lexical-binding: t; -*-
;; The branches waiting to be merged: every crew agent's branch with commits
;; the main checkout's branch hasn't, then those kept from agents forgotten
;; since, in a view of their own in the stage's place (b; q gives the stage
;; back). Loaded from config/agent-workspace.el, after inbox.el. No Doom here.
;;
;; A row a branch: its agent, its name, its commits ahead of the main branch
;; and behind it, whether it merges cleanly or with conflicts (git merge-tree:
;; no checkout touched), its agent's state. RET its commits, d its changes, M
;; merges it, D deletes it (asked first), gr again, q back.
;;
;; Worked out (git) as the view opens, on gr, after RET, d, M or D, and at an
;; agent's turn's end while it's shown; drawn again from that as agents change
;; (their states), never worked out on a timer or as it's drawn.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function agent-ui-even-glyphs "agent-ui/core")

;; ====== WHICH ======

(defun agent-workspace--branch-counts (project main branch)
  "PROJECT's BRANCH against MAIN: (AHEAD . BEHIND), the commits BRANCH has
that MAIN hasn't and MAIN's it hasn't; nil if git can't say."
  (let ((default-directory project))
    (when-let* ((line (agent-workspace--git-line "rev-list" "--left-right" "--count" (concat main "..." branch)))
                (counts (split-string line)))
      (cons (string-to-number (nth 1 counts)) (string-to-number (nth 0 counts))))))

(defun agent-workspace--branch-merges (project main branch)
  "How PROJECT's BRANCH would merge into MAIN: `cleanly' or `conflicts' (git
merge-tree --write-tree: merged in git's objects, no checkout touched); nil
if git can't say (one older than 2.38: no --write-tree)."
  (let ((default-directory project))
    (pcase (process-file "git" nil nil nil "merge-tree" "--write-tree" main branch)
      (0 'cleanly)
      (1 'conflicts))))

(defun agent-workspace--branch-to-merge (project main branch agent name)
  "PROJECT's BRANCH, of AGENT (nil: forgotten) named NAME, as a row: a plist
\(:branch :agent :name :ahead :behind :merges); nil if it has nothing MAIN
hasn't."
  (when-let* ((counts (agent-workspace--branch-counts project main branch))
              ((> (car counts) 0)))
    (list :branch branch :agent agent :name name :ahead (car counts) :behind (cdr counts)
          :merges (agent-workspace--branch-merges project main branch))))

(defun agent-workspace-branches-to-merge (project &optional main)
  "PROJECT's branches waiting to be merged into MAIN (its main checkout's
branch): each crew agent's with commits MAIN hasn't, in the stage's order,
the one it's on first (`agent-workspace-agent-branches'); then those noted
as the work of agents no longer in the crew (forgotten, their branches
kept), by name. Rows, as `agent-workspace--branch-to-merge' has them."
  (let* ((main (or main (agent-workspace-main-branch project)))
         (agents (agent-workspace--ordered project))
         (names (mapcar #'agent-workspace-agent-name agents))
         (theirs nil)
         (rows nil))
    (dolist (agent agents)
      (dolist (branch (agent-workspace-agent-branches agent))
        (push branch theirs)
        (when-let* ((row (agent-workspace--branch-to-merge project main branch agent
                                                           (agent-workspace-agent-name agent))))
          (push row rows))))
    (pcase-dolist (`(,branch . ,name) (seq-sort-by #'cdr #'string< (agent-workspace--branch-notes project)))
      (unless (or (member name names) (member branch theirs))
        (when-let* ((row (agent-workspace--branch-to-merge project main branch nil name)))
          (push row rows))))
    (nreverse rows)))

;; ====== ITS VIEW ======

(defvar agent-workspace-branches-mode-map (make-sparse-keymap)
  "Keys in the branches' view (set in config/agent-workspace.el).")

(defvar-local agent-workspace--branches-project nil "In the branches' view: its project.")
(defvar-local agent-workspace--branches-rows nil
  "In the branches' view: its rows as last worked out (see
`agent-workspace-branches-to-merge').")
(defvar-local agent-workspace--branches-main nil
  "In the branches' view: the main checkout's branch, as last worked out.")
(defvar-local agent-workspace--branches-worked nil
  "In the branches' view: non-nil once it's been worked out.")
(defvar-local agent-workspace--branches-back nil
  "In the branches' view: what q goes back to, (VIEW . BUFFER): the app's
view b came from, the buffer the cursor was in.")
(defvar-local agent-workspace--branches-hl nil
  "In the branches' view: the row at point's highlight and its ▸.")

(define-derived-mode agent-workspace-branches-mode special-mode "Branches"
  "A crew's branches waiting to be merged."
  (setq-local truncate-lines t
              mode-line-format nil
              tab-line-exclude t
              cursor-in-non-selected-windows nil
              header-line-format '(:eval (agent-workspace--branches-header)))
  (add-hook 'post-command-hook #'agent-workspace--branches-highlight nil t))

(defun agent-workspace--branches-find (project)
  "PROJECT's branches' view, if it's been made."
  (let ((root (agent-workspace--root project)))
    (seq-find (lambda (buffer) (equal (buffer-local-value 'agent-workspace--branches-project buffer) root))
              (agent-workspace--app-buffers project))))

(defun agent-workspace--branches-buffer (project)
  "PROJECT's branches' view (made the first time)."
  (or (agent-workspace--branches-find project)
      (let ((root (agent-workspace--root project)))
        (with-current-buffer (generate-new-buffer
                              (format "*branches · %s*" (file-name-nondirectory (directory-file-name root))))
          (agent-workspace-branches-mode)
          (setq agent-workspace--branches-project root
                default-directory root)
          (agent-workspace--app-buffer-add project (current-buffer))
          (current-buffer)))))

(defun agent-workspace--branches-header ()
  "The branches' view's header line: the project, its main branch, how
many branches wait."
  (when agent-workspace--branches-project
    (agent-workspace--percent-escaped
     (agent-workspace--at-right
      (concat " " (propertize "BRANCHES TO MERGE" 'face 'bold) "   "
              (propertize (concat (file-name-nondirectory (directory-file-name agent-workspace--branches-project))
                                  " → " (or agent-workspace--branches-main ""))
                          'face 'shadow))
      (concat (number-to-string (length agent-workspace--branches-rows)) " ")
      (window-total-width)))))

(defun agent-workspace--branches-agent (row)
  "ROW's agent, while it's in its crew; nil: forgotten."
  (when-let* ((agent (plist-get row :agent)))
    (and (memq agent (agent-workspace-agents (agent-workspace-agent-project agent))) agent)))

(defun agent-workspace--branches-now (row)
  "ROW's Now: its agent's state as its bar says it, or forgotten."
  (if-let* ((agent (agent-workspace--branches-agent row)))
      (agent-workspace-state-words agent)
    (propertize "forgotten" 'face 'shadow)))

(defun agent-workspace--branches-who (row)
  "ROW's agent: its avatar and name (a forgotten one's dimmed)."
  (if-let* ((agent (agent-workspace--branches-agent row)))
      (concat (agent-workspace-agent-avatar agent) " " (agent-workspace-agent-name-text agent))
    (concat (agent-workspace-avatar (plist-get row :name) t) " "
            (propertize (plist-get row :name) 'face 'shadow))))

(defun agent-workspace--pad (text width &optional left)
  "TEXT padded with spaces to WIDTH columns, on its right (LEFT: on its
left, lined up to the right)."
  (let ((pad (make-string (max 0 (- width (string-width text))) ?\s)))
    (if left (concat pad text) (concat text pad))))

(defun agent-workspace--branches-lines (rows width)
  "ROWS drawn WIDTH columns wide, every column lined up (a branch's name cut
with … to fit): the columns' heads, a line a row (the row on it, as its
`agent-workspace-branch-row' property), the keys. None: a line saying so."
  (if (not rows)
      (list (propertize "  Nothing to merge: no branch of the crew has commits its main branch hasn't." 'face 'shadow)
            ""
            (propertize "  gr again · q back" 'face 'shadow))
    (let* ((whos (mapcar #'agent-workspace--branches-who rows))
           (nows (mapcar #'agent-workspace--branches-now rows))
           (who-w (apply #'max 5 (mapcar #'string-width whos)))
           (now-w (min 18 (apply #'max 3 (mapcar #'string-width nows))))
           ;; The columns but the branch's, and the gaps between them.
           (fixed (+ 2 who-w 2 2 5 1 6 2 9 2 now-w))
           (branch-w (max 8 (min (apply #'max 6 (mapcar (lambda (row) (string-width (plist-get row :branch))) rows))
                                 (- width fixed)))))
      (append
       (list (propertize (concat "  " (agent-workspace--pad "Agent" who-w) "  " (agent-workspace--pad "Branch" branch-w)
                                 "  Ahead Behind  " (agent-workspace--pad "Merges" 9) "  Now")
                         'face 'shadow))
       (cl-mapcar
        (lambda (row who now)
          (let ((line (concat "  " (agent-workspace--pad who who-w) "  "
                              (agent-workspace--pad (agent-workspace--fit (plist-get row :branch) branch-w) branch-w)
                              "  " (agent-workspace--pad (number-to-string (plist-get row :ahead)) 5 t)
                              " " (agent-workspace--pad (number-to-string (plist-get row :behind)) 6 t)
                              "  " (agent-workspace--pad (pcase (plist-get row :merges)
                                                           ('cleanly (propertize "cleanly" 'face 'success))
                                                           ('conflicts (propertize "conflicts" 'face 'warning))
                                                           (_ ""))
                                                         9)
                              "  " now)))
            ;; A forgotten agent's, dimmed (its Merges keeps its colour).
            (unless (agent-workspace--branches-agent row)
              (add-face-text-property 0 (length line) 'shadow t line))
            (propertize line 'agent-workspace-branch-row row)))
        rows whos nows)
       (list (propertize "  RET its commits · d review · M merge · D delete · q back" 'face 'shadow))))))

(defun agent-workspace--branches-goto (branch)
  "The cursor on BRANCH's row; non-nil if it's there."
  (goto-char (point-min))
  (when-let* ((match (text-property-search-forward 'agent-workspace-branch-row branch
                                                   (lambda (branch row) (equal branch (plist-get row :branch))))))
    (goto-char (prop-match-beginning match))))

(defun agent-workspace--branches-draw (project)
  "PROJECT's branches' view drawn again from its rows as last worked out
\(nothing run), the cursor on the branch it was on (it gone: the row now in
its place)."
  (when-let* ((buffer (agent-workspace--branches-find project)))
    (with-current-buffer buffer
      (let* ((window (get-buffer-window buffer t))
             (pos (if window (window-point window) (point)))
             (branch (plist-get (get-text-property pos 'agent-workspace-branch-row) :branch))
             (line (line-number-at-pos pos))
             (width (if window (window-body-width window) 100))
             (inhibit-read-only t))
        (erase-buffer)
        (dolist (text (agent-workspace--branches-lines agent-workspace--branches-rows width))
          (let ((row (get-text-property 0 'agent-workspace-branch-row text)))
            (insert (if row (propertize (agent-ui-even-glyphs text) 'agent-workspace-branch-row row) text)
                    (propertize "\n" 'agent-workspace-branch-row row))))
        (unless (and branch (agent-workspace--branches-goto branch))
          (goto-char (point-min))
          (forward-line (1- line))
          (unless (get-text-property (point) 'agent-workspace-branch-row)
            (goto-char (point-min))
            (agent-workspace-branches-next (max 1 (1- line)))))
        (when window (set-window-point window (point)))
        (agent-workspace--branches-highlight)))))

(defun agent-workspace--branches-work-out (project)
  "PROJECT's branches to merge worked out again (git), its view drawn again."
  (when-let* ((buffer (agent-workspace--branches-find project)))
    (let* ((main (agent-workspace-main-branch project))
           (rows (agent-workspace-branches-to-merge project main)))
      (with-current-buffer buffer
        (setq agent-workspace--branches-rows rows
              agent-workspace--branches-main main
              agent-workspace--branches-worked t)))
    (agent-workspace--branches-draw project)))

(defun agent-workspace--branches-highlight ()
  "The row at point highlighted, ▸ before it."
  (let* ((window (get-buffer-window (current-buffer) t))
         (pos (if window (window-point window) (point))))
    (unless agent-workspace--branches-hl
      (setq agent-workspace--branches-hl (cons (make-overlay 1 1) (make-overlay 1 1)))
      (overlay-put (car agent-workspace--branches-hl) 'face 'hl-line)
      (overlay-put (cdr agent-workspace--branches-hl) 'display "▸"))
    (if (get-text-property pos 'agent-workspace-branch-row)
        (save-excursion
          (goto-char pos)
          (move-overlay (car agent-workspace--branches-hl) (line-beginning-position) (1+ (line-end-position)))
          (move-overlay (cdr agent-workspace--branches-hl) (line-beginning-position) (1+ (line-beginning-position))))
      (move-overlay (car agent-workspace--branches-hl) 1 1)
      (move-overlay (cdr agent-workspace--branches-hl) 1 1))))

(defun agent-workspace--branches-shown (project)
  "PROJECT's branches' view, if it's shown: its app's view, in a window."
  (when-let* ((app (agent-workspace--app project))
              ((eq (agent-workspace--app-view app) 'branches))
              (buffer (agent-workspace--branches-find project))
              ((get-buffer-window buffer t)))
    buffer))

;; ====== ITS PLACE IN THE APP ======

(defun agent-workspace--branches-place (app area anew)
  "APP's branches' view in window AREA, the stage's place (the issue list,
the minimap and the room stay). Worked out if it's shown ANEW (the app
shown again) or never was; else drawn again (laid out anew: a border
dragged, a popup gone)."
  (let* ((project (agent-workspace--app-project app))
         (buffer (agent-workspace--branches-buffer project)))
    (set-window-dedicated-p area nil)
    (set-window-buffer area buffer)
    (set-window-parameter area 'header-line-format nil)
    (dolist (parameter '(mode-line-format tab-line-format))
      (set-window-parameter area parameter 'none))
    (set-window-display-table area nil)
    (if (or anew (not (buffer-local-value 'agent-workspace--branches-worked buffer)))
        (agent-workspace--branches-work-out project)
      (agent-workspace--branches-draw project))))

;; ====== ITS COMMANDS ======

(defun agent-workspace-branches ()
  "The crew's branches waiting to be merged, in the stage's place (b; q
gives it back): each agent's with commits the main branch hasn't, then those
kept from agents forgotten; RET its commits, d its changes, M merges it, D
deletes it, gr again."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app))
         (from (window-buffer (selected-window)))
         (buffer (agent-workspace--branches-buffer project)))
    (unless (eq (agent-workspace--app-view app) 'branches)
      (with-current-buffer buffer
        (setq agent-workspace--branches-back (cons (agent-workspace--app-view app) from))))
    (agent-workspace--branches-work-out project)
    (setf (agent-workspace--app-view app) 'branches)
    (agent-workspace-layout app)
    (when-let* ((window (get-buffer-window buffer)))
      (select-window window))))

(defun agent-workspace-branches-quit ()
  "q: the stage back in the branches' place, as it was (the room alone, if
b came from there), the cursor where it was."
  (interactive)
  (let* ((project agent-workspace--branches-project)
         (app (or (agent-workspace--app project) (user-error "The crew's app is closed")))
         (back agent-workspace--branches-back)
         (open (agent-workspace--app-open app)))
    (setf (agent-workspace--app-view app) (if (eq (car back) 'room) 'room 'stage))
    (agent-workspace-layout app)
    (when-let* ((window (or (and (buffer-live-p (cdr back)) (get-buffer-window (cdr back)))
                            (and open (get-buffer-window (agent-workspace-agent-buffer open)))
                            (get-buffer-window (agent-workspace--issues-buffer project)))))
      (select-window window))))

(defun agent-workspace-branches-next (&optional n)
  "The next branch in the view (N: that many; back if negative)."
  (interactive "p")
  (let ((n (or n 1)))
    (dotimes (_ (abs n))
      (let ((pos (save-excursion
                   (forward-line (if (> n 0) 1 -1))
                   (and (get-text-property (point) 'agent-workspace-branch-row) (point)))))
        (when pos (goto-char pos))))))

(defun agent-workspace-branches-previous (&optional n)
  "The previous branch in the view."
  (interactive "p")
  (agent-workspace-branches-next (- (or n 1))))

(defun agent-workspace--branches-row ()
  "The row at point (see `agent-workspace--branch-to-merge'), or a user
error."
  (or (get-text-property (point) 'agent-workspace-branch-row) (user-error "No branch here")))

(defun agent-workspace--branches-agent-at ()
  "In the branches' view, the agent whose branch is at point, while it's in
its crew; else nil."
  (and (derived-mode-p 'agent-workspace-branches-mode)
       (when-let* ((row (get-text-property (point) 'agent-workspace-branch-row)))
         (agent-workspace--branches-agent row))))

(defun agent-workspace-branches-commits ()
  "RET: the branch here's commits the main branch hasn't (MAIN..BRANCH),
in magit's log (else git log's), where you came from (the app left, the crew
going on, as d does). The view worked out again."
  (interactive)
  (let ((row (agent-workspace--branches-row))
        (project agent-workspace--branches-project))
    (when (agent-workspace-frame-p) (agent-workspace-leave t))
    (unwind-protect
        (agent-workspace-branch-commits project (plist-get row :branch) (plist-get row :name))
      (agent-workspace--branches-work-out project))))

(defun agent-workspace-branches-review ()
  "d: the branch here's changes since it left the main branch (MAIN...BRANCH),
in magit, where you came from (as d on a bar: the app left, the crew going
on); a forgotten agent's too. The view worked out again."
  (interactive)
  (let ((row (agent-workspace--branches-row))
        (project agent-workspace--branches-project))
    (when (agent-workspace-frame-p) (agent-workspace-leave t))
    (unwind-protect
        (if-let* ((agent (agent-workspace--branches-agent row)))
            (agent-workspace-review agent (plist-get row :branch))
          (agent-workspace-review-branch project (plist-get row :branch) (plist-get row :name)))
      (agent-workspace--branches-work-out project))))

(defun agent-workspace-branches-merge ()
  "M: the branch here merged into your checkout, asking nothing: a crew
agent's as M on its bar does (`agent-workspace-merge': a merge commit naming
it, its agent told and back at rest), a forgotten agent's the same way, no
agent told, deleted once merged (`agent-workspace-merge-kept'). The view
worked out again."
  (interactive)
  (let ((row (agent-workspace--branches-row))
        (project agent-workspace--branches-project))
    (unwind-protect
        (if-let* ((agent (agent-workspace--branches-agent row)))
            (agent-workspace-merge agent (plist-get row :branch))
          (agent-workspace-merge-kept project (plist-get row :branch)))
      (agent-workspace--branches-work-out project))))

(defun agent-workspace--holder-text (project dir)
  "Where PROJECT's worktree DIR is, for a sentence: \"your checkout\",
\"ada's worktree\" (its agent's, forgotten too), else its folder."
  (cond ((equal (file-name-as-directory (file-truename dir)) (file-name-as-directory (file-truename project)))
         "your checkout")
        ((agent-workspace--worktree-agent-name dir)
         (format "%s's worktree" (agent-workspace--worktree-agent-name dir)))
        (t (abbreviate-file-name dir))))

(defun agent-workspace-branches-delete ()
  "D: the branch here deleted, whatever it holds, once you say so, shown its
commits the main branch hasn't; never one checked out in a worktree (an
agent on it: said). The view worked out again."
  (interactive)
  (let* ((row (agent-workspace--branches-row))
         (project agent-workspace--branches-project)
         (branch (plist-get row :branch))
         (main (or agent-workspace--branches-main (agent-workspace-main-branch project))))
    (when-let* ((holder (agent-workspace--branch-holder project branch)))
      (user-error "%s is checked out in %s: not deleted" branch (agent-workspace--holder-text project holder)))
    (unwind-protect
        (let* ((default-directory project)
               (commits (agent-workspace--git-lines "log" "--oneline" (concat main ".." branch)))
               (shown (seq-take commits 10)))
          (when (y-or-n-p (format "%s has %d commit%s %s hasn't:\n%s%s\nDelete it, and them? "
                                  branch (length commits) (if (= (length commits) 1) "" "s") main
                                  (mapconcat (lambda (line) (concat "  " line)) shown "\n")
                                  (if (> (length commits) 10) (format "\n  … and %d more" (- (length commits) 10)) "")))
            (agent-workspace--git "branch" "-D" branch)
            (message "Deleted %s" branch)))
      (agent-workspace--branches-work-out project))))

(defun agent-workspace-branches-refresh ()
  "gr: the branches to merge worked out again."
  (interactive)
  (agent-workspace--branches-work-out agent-workspace--branches-project))

;; ====== KEPT UP TO DATE ======

(defun agent-workspace--branches-turn-end-h (agent old new)
  "AGENT's turn ended (it worked or had its hand raised, now neither): its
crew's branches' view, shown, worked out again. In
`agent-workspace-state-change-functions'."
  (when (and (memq old '(working hand)) (not (memq new '(working hand))))
    (let ((project (agent-workspace-agent-project agent)))
      (when (agent-workspace--branches-shown project)
        ;; In an agent's event: git failing mustn't stop it.
        (with-demoted-errors "Branches to merge: %S"
          (agent-workspace--branches-work-out project))))))

(add-hook 'agent-workspace-state-change-functions #'agent-workspace--branches-turn-end-h)

(defun agent-workspace--branches-changed-h (agent _what)
  "AGENT changed (its state, name, colour...): its crew's branches' view,
shown, drawn again (nothing worked out). In `agent-workspace-change-functions'."
  (let ((project (agent-workspace-agent-project agent)))
    (when (agent-workspace--branches-shown project)
      (agent-workspace--branches-draw project))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--branches-changed-h)
