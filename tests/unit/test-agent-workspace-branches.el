;;; tests/unit/test-agent-workspace-branches.el -*- lexical-binding: t; -*-
;; config/agent-workspace/branches.el: the branches waiting to be merged, in
;; a view of their own in the stage's place (b; q gives the stage back), in
;; throwaway git repositories with the agents' real worktrees (their sessions
;; plain buffers): which (each crew agent's with commits main hasn't, the one
;; it's on first; those kept from a forgotten agent; nothing else), the
;; columns (ahead, behind, cleanly / conflicts, the agent's state; lined up, a
;; long name cut), the keys (RET, d, M, D, gr, q), when it's worked out.

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...); its
;; commits and merges made as a test user.
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")
(dolist (var '("GIT_AUTHOR_NAME" "GIT_COMMITTER_NAME")) (setenv var "Test"))
(dolist (var '("GIT_AUTHOR_EMAIL" "GIT_COMMITTER_EMAIL")) (setenv var "test@example.com"))

(require 'agent-shell)
(+test-load "config/agent-shell" "config/agent-ui" "config/tiling" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)
(setq agent-workspace-minimap nil)

;; ====== HELPERS ======

(defun +test-awb--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awb--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awb/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awb--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (+test-awb--git "add" "README")
      (+test-awb--git "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defun +test-awb--commit (dir file text message)
  "FILE in DIR now holds TEXT, committed with MESSAGE."
  (let ((default-directory dir))
    (write-region text nil file)
    (+test-awb--git "add" file)
    (+test-awb--git "commit" "-q" "-m" message)))

(defvar +test-awb--told nil "What the agents were sent this test: (NAME TEXT) each.")

(defmacro +test-awb (name &rest body)
  "BODY in a new project NAME (`project'), a frame 220x40, no app or crew
before or after; agents' sessions plain buffers (no agent runs), at the
desk, what they're sent kept in `+test-awb--told'; bd not run."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awb--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (+test-awb--told nil))
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer
                            (agent-workspace-agent-state agent) 'desk)
                      (agent-workspace--changed agent 'session)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil
                          (agent-workspace-agent-state agent) state)
                    nil))
                 ((symbol-function 'agent-workspace-send)
                  (lambda (agent text &rest _) (push (list (agent-workspace-agent-name agent) text) +test-awb--told)))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
         (unwind-protect (progn ,@body)
           (dolist (project (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app project))
           (agent-workspace-close-all)
           (set-frame-parameter nil 'agent-workspace nil))))))

(defun +test-awb--agent (name)
  "A builder NAME of the project's crew, its worktree made (on agent/NAME)."
  (let ((agent (agent-workspace-create :role "builder" :name name)))
    (agent-workspace-worktree-ensure agent)
    agent))

(defun +test-awb--work (agent issue title type commits)
  "AGENT given ISSUE (TITLE, TYPE), then COMMITS commits on its branch."
  (agent-workspace-give agent issue title type)
  (dotimes (i commits)
    (+test-awb--commit (agent-workspace-agent-worktree agent) (format "%s-%d" issue i) "work\n"
                       (format "%s, part %d" issue i))))

(defun +test-awb--crew ()
  "ken (on feat/demo-6-tokens-numbers, 3 commits, after fix/demo-2-parser-recover,
1, a parser file), ada (feat/demo-1-strings-escapes, 2) and mia (feat/demo-9-comments,
1, then task/demo-10-nothing, none), forgotten, her worktree kept: (KEN ADA)."
  (let ((ken (+test-awb--agent "ken"))
        (ada (+test-awb--agent "ada"))
        (mia (+test-awb--agent "mia")))
    (agent-workspace-give ken "demo-2" "Parser recover" "bug")
    (+test-awb--commit (agent-workspace-agent-worktree ken) "parser" "ken's\n" "the parser recovers")
    (+test-awb--work ken "demo-6" "Tokens numbers" "feature" 3)
    (+test-awb--work ada "demo-1" "Strings escapes" "feature" 2)
    (+test-awb--work mia "demo-9" "Comments" "feature" 1)
    (+test-awb--work mia "demo-10" "Nothing" "task" 0)
    (agent-workspace-forget mia 'keep)
    (list ken ada)))

(defun +test-awb--rows (project)
  "PROJECT's branches to merge: (NAME BRANCH AHEAD BEHIND MERGES FORGOTTEN) each."
  (mapcar (lambda (row) (list (plist-get row :name) (plist-get row :branch) (plist-get row :ahead)
                              (plist-get row :behind) (plist-get row :merges) (not (plist-get row :agent))))
          (agent-workspace-branches-to-merge project)))

(defun +test-awb--windows ()
  "The frame's windows: (BUFFER-NAME WIDTH HEIGHT), in order."
  (mapcar (lambda (w) (list (buffer-name (window-buffer w)) (window-total-width w) (window-total-height w)))
          (window-list nil 'nomini (frame-first-window))))

(defun +test-awb--idle (project)
  "PROJECT's branches' view's work-out waiting for Emacs to be idle, run
now (no idle time in batch Emacs): non-nil if there was one."
  (when-let* ((timer (gethash (agent-workspace--root project) agent-workspace--branches-soon)))
    (timer-event-handler timer)
    t))

(defun +test-awb--view (project)
  "PROJECT's branches' view."
  (agent-workspace--branches-find project))

(defun +test-awb--shown (project)
  "PROJECT's branches' view as it's shown: its rows' branches, in order."
  (with-current-buffer (+test-awb--view project)
    (mapcar (lambda (row) (plist-get row :branch)) agent-workspace--branches-rows)))

(defun +test-awb--branches (project)
  "PROJECT's branches, sorted."
  (let ((default-directory project))
    (sort (split-string (+test-awb--git "for-each-ref" "--format=%(refname:short)" "refs/heads/") "\n" t)
          #'string<)))

(defun +test-awb--on (project branch)
  "The cursor in PROJECT's branches' view on BRANCH's row."
  (set-buffer (+test-awb--view project))
  (should (agent-workspace--branches-goto branch))
  (when-let* ((window (get-buffer-window (current-buffer))))
    (set-window-point window (point))))

;; ====== WHICH ======

(ert-deftest agent-workspace-branches/which ()
  "Each crew agent's branches with commits main hasn't, in the stage's
order, the one it's on first; then those kept from a forgotten agent (noted
as hers in git's config). Not a branch with nothing to merge (agent/NAME at
rest, hers she's on), nor one of yours."
  (+test-awb "which"
    (+test-awb--crew)
    (let ((default-directory project))
      (+test-awb--git "branch" "yours" "feat/demo-1-strings-escapes"))
    (should (equal (+test-awb--rows project)
                   '(("ken" "feat/demo-6-tokens-numbers" 3 0 cleanly nil)
                     ("ken" "fix/demo-2-parser-recover" 1 0 cleanly nil)
                     ("ada" "feat/demo-1-strings-escapes" 2 0 cleanly nil)
                     ("mia" "feat/demo-9-comments" 1 0 cleanly t))))))

(ert-deftest agent-workspace-branches/none-to-merge ()
  "Nothing to merge (agents at rest): no row; the view says so, its count 0."
  (+test-awb "none"
    (+test-awb--agent "ada")
    (should-not (agent-workspace-branches-to-merge project))
    (agent-workspace-open t)
    (agent-workspace-branches)
    (with-current-buffer (+test-awb--view project)
      (should (string-search "Nothing to merge" (buffer-string)))
      (should (string-suffix-p " 0 " (substring-no-properties (agent-workspace--branches-header)))))))

;; ====== THE COLUMNS ======

(ert-deftest agent-workspace-branches/behind-and-conflicts ()
  "Main moved on (a commit of yours): every branch behind it by one; one
changing the same file as yours merges with conflicts (git merge-tree,
nothing in your checkout touched), the others cleanly. A git without
merge-tree --write-tree: nothing said in that column."
  (+test-awb "columns"
    (+test-awb--crew)
    (+test-awb--commit project "parser" "mine\n" "my parser")
    (should (equal (+test-awb--rows project)
                   '(("ken" "feat/demo-6-tokens-numbers" 3 1 cleanly nil)
                     ("ken" "fix/demo-2-parser-recover" 1 1 conflicts nil)
                     ("ada" "feat/demo-1-strings-escapes" 2 1 cleanly nil)
                     ("mia" "feat/demo-9-comments" 1 1 cleanly t))))
    (let ((default-directory project))
      (should (equal (+test-awb--git "status" "--porcelain") ""))
      (should (equal (+test-awb--git "log" "-1" "--format=%s") "my parser")))
    ;; An older git: merge-tree has no --write-tree (an unknown option, 129).
    ;; Nothing kept from the work-out before (another git, as Emacs starts).
    (clrhash agent-workspace--branch-known)
    (cl-letf (((symbol-function 'process-file)
               (let ((process-file (symbol-function 'process-file)))
                 (lambda (program &optional infile buffer display &rest args)
                   (if (equal (car args) "merge-tree")
                       129
                     (apply process-file program infile buffer display args))))))
      (should (equal (mapcar (lambda (row) (nth 4 row)) (+test-awb--rows project)) '(nil nil nil nil))))))

;; ====== THE VIEW ======

(ert-deftest agent-workspace-branches/the-view ()
  "b: the view in the stage's place (the issue list and the room stay), the
cursor in it; its header (the project → main, how many); a row a branch, its
columns lined up, a long name cut with …; a forgotten agent's dimmed,
forgotten; its agent's state as its bar says it, drawn again as it changes.
q: the stage back as it was."
  (+test-awb "view"
    (pcase-let ((`(,ken ,_ada) (+test-awb--crew)))
      ;; A long branch kept from zed, forgotten.
      (let ((default-directory project))
        (+test-awb--git "branch" "feat/demo-12-a-branch-name-much-too-long-for-its-column-in-the-view"
                        "feat/demo-1-strings-escapes")
        (agent-workspace--branch-note project "feat/demo-12-a-branch-name-much-too-long-for-its-column-in-the-view" "zed"))
      (agent-workspace-open t)
      (let ((laid-out (+test-awb--windows))
            (from (window-buffer (selected-window))))
        (agent-workspace-branches)
        (let* ((view (+test-awb--view project))
               (window (get-buffer-window view)))
          (should (eq (selected-window) window))
          (should (eq (agent-workspace--app-view (agent-workspace--app project)) 'branches))
          ;; In the stage's place: no pane or bar left; the issues, the room stay.
          (should-not (get-buffer-window (agent-workspace-agent-buffer ken)))
          (should-not (get-buffer-window (agent-workspace--bar-buffer ken)))
          (should (get-buffer-window (agent-workspace--issues-buffer project)))
          (should (get-buffer-window (agent-workspace--room-buffer project)))
          (should (= (window-total-width window)
                     (- 220 (window-total-width (get-buffer-window (agent-workspace--issues-buffer project)))
                        (window-total-width (get-buffer-window (agent-workspace--room-buffer project))))))
          (with-current-buffer view
            (with-selected-window window
              (let ((header (substring-no-properties (agent-workspace--branches-header))))
                (should (string-prefix-p " BRANCHES TO MERGE   view → main" header))
                (should (string-suffix-p " 5 " header))))
            (let* ((lines (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n" t))
                   (rows (seq-filter (lambda (line) (string-match-p "\\(cleanly\\|conflicts\\)" line)) lines)))
              (should (string-match-p "\\`  Agent +Branch +Ahead Behind  Merges +Now\\'" (car lines)))
              (should (= (length rows) 5))
              ;; Lined up: the counts end, and Merges starts, at the same column.
              (let ((ends (mapcar (lambda (line)
                                    (string-match " +[0-9]+ +[0-9]+  \\(cleanly\\|conflicts\\)" line)
                                    (list (string-width (substring line 0 (match-beginning 1)))))
                                  rows)))
                (should (= (length (delete-dups ends)) 1))
                (should (= (car (car ends))
                           (string-width (substring (car lines) 0 (string-search "Merges" (car lines)))))))
              (should (string-match-p "\\`  ▌K ken  feat/demo-6-tokens-numbers +3 +0  cleanly +at the desk\\'" (nth 0 rows)))
              (should (string-match-p "\\`  ▌M mia  feat/demo-9-comments +1 +0  cleanly +forgotten\\'" (nth 3 rows)))
              ;; Cut with …, the whole name nowhere.
              (should (string-match-p "  ▌Z zed  feat/demo-12-a-branch-name[^ ]*…  " (nth 4 rows)))
              (should-not (string-search "in-the-view" (buffer-string)))
              (should (string-match-p "RET its commits · d review · M merge · D delete · q back" (car (last lines)))))
            ;; A forgotten agent's row dimmed.
            (save-excursion
              (goto-char (point-min))
              (search-forward "mia")
              (should (memq 'shadow (ensure-list (get-text-property (1- (point)) 'face)))))
            ;; Its state, drawn again as it changes (nothing worked out).
            (cl-letf (((symbol-function 'agent-workspace-branches-to-merge) (lambda (&rest _) (error "Worked out"))))
              (agent-workspace--set-state ken 'done))
            (should (string-search "done, have a look" (buffer-string)))
            ;; The cursor on the first branch, ▸ before it.
            (should (equal (plist-get (get-text-property (window-point window) 'agent-workspace-branch-row) :branch)
                           "feat/demo-6-tokens-numbers"))
            (should (equal (overlay-get (cdr agent-workspace--branches-hl) 'display) "▸")))
          ;; q: the stage back, as it was.
          (with-current-buffer view (agent-workspace-branches-quit))
          (should (eq (agent-workspace--app-view (agent-workspace--app project)) 'stage))
          (should (equal (+test-awb--windows) laid-out))
          (should (eq (window-buffer (selected-window)) from)))))))

(ert-deftest agent-workspace-branches/from-the-room-alone ()
  "b from the room alone (2): the view with the room beside it; q, the room
alone again."
  (+test-awb "room"
    (+test-awb--crew)
    (agent-workspace-open t)
    (agent-workspace-view-room)
    (agent-workspace-branches)
    (should (get-buffer-window (+test-awb--view project)))
    (should (get-buffer-window (agent-workspace--room-buffer project)))
    (with-current-buffer (+test-awb--view project) (agent-workspace-branches-quit))
    (should (eq (agent-workspace--app-view (agent-workspace--app project)) 'room))
    (should-not (get-buffer-window (+test-awb--view project)))))

;; ====== ITS KEYS ======

(require 'magit)

(ert-deftest agent-workspace-branches/its-keys ()
  "j / k move between branches; RET its commits (magit's log, main..BRANCH)
and d its changes (main...BRANCH), the app left as d does; M merges it
without asking which: a crew agent's (it's told, back at rest, its branch
deleted), a forgotten one's (deleted, nobody told); D deletes one after
asking, its commits listed, never one checked out (said); the view worked
out again after each. The app's other keys act on the branch's agent."
  ;; b everywhere in the app; the view's own keys over the app's.
  (dolist (map (list agent-workspace-issues-mode-map agent-workspace-bar-mode-map
                     agent-workspace-minimap-mode-map +my/agent-workspace-pane-map))
    (should (eq (lookup-key map "b") #'agent-workspace-branches)))
  (pcase-dolist (`(,key . ,command) '(("j" . agent-workspace-branches-next) ("k" . agent-workspace-branches-previous)
                                      ("RET" . agent-workspace-branches-commits) ("d" . agent-workspace-branches-review)
                                      ("M" . agent-workspace-branches-merge) ("D" . agent-workspace-branches-delete)
                                      ("gr" . agent-workspace-branches-refresh) ("q" . agent-workspace-branches-quit)
                                      ("i" . agent-workspace-interrupt-here) ("b" . agent-workspace-branches)))
    (should (eq (lookup-key agent-workspace-branches-mode-map (kbd key)) command)))
  (+test-awb "keys"
    (pcase-let ((`(,ken ,ada) (+test-awb--crew)))
      (agent-workspace-open t)
      (agent-workspace-branches)
      (set-buffer (+test-awb--view project))
      (should (equal (plist-get (agent-workspace--branches-row) :branch) "feat/demo-6-tokens-numbers"))
      (agent-workspace-branches-next)
      (should (equal (plist-get (agent-workspace--branches-row) :branch) "fix/demo-2-parser-recover"))
      (should (eq (agent-workspace--current) ken))
      (agent-workspace-branches-next 2)
      (should (equal (plist-get (agent-workspace--branches-row) :branch) "feat/demo-9-comments"))
      (agent-workspace-branches-next)
      (should (equal (plist-get (agent-workspace--branches-row) :branch) "feat/demo-9-comments"))
      (agent-workspace-branches-previous)
      (should (eq (agent-workspace--current) ada))
      ;; RET and d: where you came from, in magit.
      (let ((called nil))
        (cl-letf (((symbol-function 'magit-log-other)
                   (lambda (revs &rest _) (push (list 'log revs default-directory) called)))
                  ((symbol-function 'magit-diff-range)
                   (lambda (range &rest _) (push (list 'diff range default-directory) called))))
          (agent-workspace-branches-commits)
          (should-not (agent-workspace-frame-p))
          (agent-workspace-open t)
          (should (get-buffer-window (+test-awb--view project)))
          (+test-awb--on project "feat/demo-9-comments")
          (agent-workspace-branches-review))
        (should (equal (reverse called)
                       `((log ("main..feat/demo-1-strings-escapes") ,project)
                         (diff "main...feat/demo-9-comments" ,project)))))
      (agent-workspace-open t)
      ;; D on the branch ken's on: refused, said.
      (+test-awb--on project "feat/demo-6-tokens-numbers")
      (should (equal (cadr (should-error (agent-workspace-branches-delete) :type 'user-error))
                     "feat/demo-6-tokens-numbers is checked out in ken's worktree: not deleted"))
      ;; D on his other one: asked, its commit listed; no: kept.
      (+test-awb--on project "fix/demo-2-parser-recover")
      (let ((asked nil))
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) nil)))
          (agent-workspace-branches-delete))
        (should (string-match-p "\\`fix/demo-2-parser-recover has 1 commit main hasn't:\n  [0-9a-f]+ the parser recovers\nDelete it, and them\\? \\'"
                                (car asked)))
        (should (member "fix/demo-2-parser-recover" (+test-awb--branches project)))
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
          (agent-workspace-branches-delete)))
      (should-not (member "fix/demo-2-parser-recover" (+test-awb--branches project)))
      (should (equal (+test-awb--shown project)
                     '("feat/demo-6-tokens-numbers" "feat/demo-1-strings-escapes" "feat/demo-9-comments")))
      ;; M on ken's: merged, no question, ken told and at rest.
      (+test-awb--on project "feat/demo-6-tokens-numbers")
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (error "Asked"))))
        (agent-workspace-branches-merge))
      (let ((default-directory project))
        (should (equal (+test-awb--git "log" "-1" "--format=%s" "main") "Merge branch 'feat/demo-6-tokens-numbers'")))
      (should (equal (agent-workspace-agent-branch ken) "agent/ken"))
      (should (string-prefix-p "The user merged your branch feat/demo-6-tokens-numbers into main"
                               (cadr (assoc "ken" +test-awb--told))))
      (should (equal (+test-awb--shown project) '("feat/demo-1-strings-escapes" "feat/demo-9-comments")))
      ;; The cursor on the row now in its place.
      (should (equal (plist-get (agent-workspace--branches-row) :branch) "feat/demo-1-strings-escapes"))
      ;; M on mia's, forgotten: merged, deleted, nobody told.
      (+test-awb--on project "feat/demo-9-comments")
      (setq +test-awb--told nil)
      (agent-workspace-branches-merge)
      (let ((default-directory project))
        (should (equal (+test-awb--git "log" "-1" "--format=%s" "main") "Merge branch 'feat/demo-9-comments'")))
      (should-not (member "feat/demo-9-comments" (+test-awb--branches project)))
      (should-not +test-awb--told)
      (should (equal (+test-awb--shown project) '("feat/demo-1-strings-escapes"))))))

(ert-deftest agent-workspace-branches/when-it-s-worked-out ()
  "Worked out as the view opens, on gr, and at an agent's turn's end while
it's shown; not as an agent starts working, nor while it isn't shown;
nothing on a timer."
  (+test-awb "when"
    (pcase-let ((`(,_ken ,ada) (+test-awb--crew)))
      (agent-workspace-open t)
      (agent-workspace-branches)
      (let ((dir (agent-workspace-agent-worktree ada))
            (ahead (lambda ()
                     (with-current-buffer (+test-awb--view project)
                       (plist-get (seq-find (lambda (row) (equal (plist-get row :name) "ada"))
                                            agent-workspace--branches-rows)
                                  :ahead)))))
        (should (= (funcall ahead) 2))
        ;; A commit: not seen until gr.
        (+test-awb--commit dir "more" "x\n" "more")
        (should (= (funcall ahead) 2))
        (with-current-buffer (+test-awb--view project) (agent-workspace-branches-refresh))
        (should (= (funcall ahead) 3))
        ;; Its turn: not as it starts; as it ends.
        (agent-workspace--set-state ada 'working)
        (+test-awb--commit dir "again" "x\n" "again")
        (should (= (funcall ahead) 3))
        (agent-workspace--set-state ada 'done)
        ;; Once Emacs is idle, not in the turn's end.
        (should (= (funcall ahead) 3))
        (should (+test-awb--idle project))
        (should (= (funcall ahead) 4))
        ;; Not shown (the stage back): a turn's end runs nothing.
        (with-current-buffer (+test-awb--view project) (agent-workspace-branches-quit))
        (agent-workspace--set-state ada 'working)
        (+test-awb--commit dir "unseen" "x\n" "unseen")
        (agent-workspace--set-state ada 'done)
        (should-not (+test-awb--idle project))
        (should (= (funcall ahead) 4))
        ;; Shown again: worked out.
        (agent-workspace-branches)
        (should (= (funcall ahead) 5))
        ;; Nothing on a timer: a second with timers running works nothing out.
        (let ((runs 0))
          (cl-letf (((symbol-function 'agent-workspace-branches-to-merge)
                     (lambda (&rest _) (setq runs (1+ runs)) nil)))
            (+test-wait-for #'ignore 1.5))
          (should (= runs 0)))))))

(ert-deftest agent-workspace-branches/only-what-moved ()
  "A turn's end with the view shown and nothing moved: git asked for the
main branch, the branches, the worktrees and the notes, once each, whatever
the crew; no branch counted or merged again. A commit on one branch: that
branch alone counted and merged again; main moved: each (doom-pbk.38)."
  (+test-awb "moved"
    (pcase-let ((`(,ken ,ada) (+test-awb--crew)))
      (agent-workspace-open t)
      (agent-workspace-branches)
      (let ((calls nil)
            (process-file (symbol-function 'process-file)))
        (cl-flet ((turn (agent)
                    (setq calls nil)
                    (cl-letf (((symbol-function 'process-file)
                               (lambda (program &rest args)
                                 (when (equal program "git") (push (nth 3 args) calls))
                                 (apply process-file program args))))
                      (agent-workspace--set-state agent 'working)
                      (agent-workspace--set-state agent 'done)
                      (should (+test-awb--idle project)))
                    (sort (copy-sequence calls) #'string<)))
          (should (equal (turn ada) '("branch" "config" "for-each-ref" "worktree")))
          ;; ada commits: her branch alone again.
          (+test-awb--commit (agent-workspace-agent-worktree ada) "more" "x\n" "more")
          (should (equal (turn ada) '("branch" "config" "for-each-ref" "merge-tree" "rev-list" "worktree")))
          (with-current-buffer (+test-awb--view project)
            (should (= (plist-get (seq-find (lambda (row) (equal (plist-get row :name) "ada"))
                                            agent-workspace--branches-rows)
                                  :ahead)
                       3)))
          ;; Main moves: every branch again.
          (+test-awb--commit project "yours" "y\n" "yours")
          (let ((again (turn ken)))
            (should (= (seq-count (lambda (call) (equal call "rev-list")) again)
                       (hash-table-count (gethash (agent-workspace--root project) agent-workspace--branch-known))))
            (should (> (seq-count (lambda (call) (equal call "rev-list")) again) 4))))))))
