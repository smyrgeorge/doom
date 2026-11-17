;;; $DOOMDIR/config/agent-workspace/worktree.el -*- lexical-binding: t; -*-
;; Every agent's own git worktree, and a branch there for each piece of its
;; work. Loaded from config/agent-workspace.el. No Doom here.
;;
;; Named after its agent: the folder .agent-shell/worktrees/ROLE-NAME of its
;; project (builder-ada). Made when the agent is, on the branch agent/NAME;
;; kept when it's killed, put to sleep or its crew closed (the next start
;; reuses it, on the branch it's on); moved when it's renamed or its role
;; changes. One of its found elsewhere in .agent-shell/worktrees (on
;; agent/NAME, or locked with its name: worktrees/NAME, as they were named
;; before; its role's before crew.json changed it) is moved to its folder as
;; it starts.
;;
;; Each piece of work gets a branch of its own there (A BRANCH FOR EACH PIECE
;; OF WORK below); between them, the agent rests on agent/NAME.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)

;; ====== VARIABLES ======

(defcustom agent-workspace-worktrees-directory ".agent-shell/worktrees"
  "Where agents' worktrees go, in their project (.agent-shell/ is kept out
of git: see `agent-workspace--keep-out-of-git')."
  :type 'string
  :group 'agent-workspace)

(defconst agent-workspace--slug-length 48
  "At most this many characters of a title (or a prompt) in a branch's name.")

(defvar agent-workspace--branch-next (make-hash-table :test #'eq :weakness 'key)
  "An agent given an issue while it worked: (ISSUE TYPE TITLE), its worktree put
on the issue's branch as its next turn starts (if it's still its issue).")

(defvar agent-workspace--branch-quiet (make-hash-table :test #'eq :weakness 'key)
  "An agent to texts sent to it that are no work of its own (it's told of a
merge, given an event): the turns they start make no branch.")

;; ====== A WORKTREE ======

(defun agent-workspace-worktree-directory (project name role)
  "The worktree of the agent NAME, of ROLE, of PROJECT's crew: ROLE-NAME."
  (file-name-as-directory
   (expand-file-name (concat role "-" name) (expand-file-name agent-workspace-worktrees-directory project))))

(defun agent-workspace--worktree-file (dir file)
  "The text of FILE (HEAD, locked) in the worktree DIR's git folder (its .git
file's gitdir:), or nil: read from its files, git not run (a mode line
asks, a turn starts)."
  (ignore-errors
    (let ((gitdir (with-temp-buffer
                    (insert-file-contents (expand-file-name ".git" dir))
                    (and (looking-at "gitdir: \\(.*\\)") (match-string 1)))))
      (with-temp-buffer
        (insert-file-contents (expand-file-name file (expand-file-name gitdir dir)))
        (buffer-string)))))

(defun agent-workspace--worktree-head (dir)
  "The branch the worktree DIR is on, or nil (none, a commit checked out; or
not a worktree): read from its git files, git not run."
  (when-let* ((head (agent-workspace--worktree-file dir "HEAD")))
    (and (string-match "\\`ref: refs/heads/\\([^\n]+\\)" head)
         (match-string 1 head))))

(defun agent-workspace--worktree-branch-name (dir)
  "The agent's name the worktree DIR's branch says (agent/NAME: at rest), or
nil: read from its git files, git not run."
  (when-let* ((branch (agent-workspace--worktree-head dir)))
    (and (string-match "\\`agent/\\(.+\\)" branch) (match-string 1 branch))))

(defun agent-workspace--worktree-agent-name (dir)
  "The name of the agent whose worktree DIR is, or nil: its lock's reason
says it (\"agent ada (builder), crew of doom\"), else its branch (agent/NAME,
at rest). Read from its git files, git not run."
  (or (when-let* ((reason (agent-workspace--worktree-file dir "locked")))
        (and (string-match "\\`agent \\([^ \n]+\\) (" reason) (match-string 1 reason)))
      (agent-workspace--worktree-branch-name dir)))

(defun agent-workspace-branch (name)
  "The branch the agent NAME rests on, between pieces of work: agent/NAME."
  (concat "agent/" name))

(defun agent-workspace--git (&rest args)
  "Run git with ARGS in `default-directory': its output, or a user error
with what git said."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil args)))
      (unless (eql status 0)
        (user-error "git %s: %s" (car args) (string-trim (buffer-string))))
      (string-trim (buffer-string)))))

(defun agent-workspace--git-lines (&rest args)
  "The lines git prints for ARGS in `default-directory'; none if it fails."
  (with-temp-buffer
    (when (eql 0 (apply #'process-file "git" nil '(t nil) nil args))
      (split-string (buffer-string) "\n" t))))

(defun agent-workspace--keep-out-of-git (project)
  "PROJECT's .agent-shell/ kept out of git, if it isn't: in the repository's
info/exclude (every worktree shares it), so neither the project nor an
agent's branch gets a changed .gitignore."
  (let ((default-directory project))
    (unless (eql 0 (process-file "git" nil nil nil "check-ignore" "-q" ".agent-shell/worktrees"))
      (let ((exclude (expand-file-name
                      "info/exclude"
                      (agent-workspace--git "rev-parse" "--path-format=absolute" "--git-common-dir"))))
        (make-directory (file-name-directory exclude) t)
        (write-region "\n# Agents' worktrees, transcripts (agent-shell)\n/.agent-shell/\n"
                      nil exclude t 'silent)))))

(defun agent-workspace-no-crew-reason (&optional directory)
  "Why DIRECTORY's project (default: `default-directory''s) can have no
crew, or nil if it can: every agent needs a worktree, branched from a
commit."
  (let ((default-directory (file-name-as-directory (expand-file-name (or directory default-directory)))))
    (cond ((not (agent-workspace-project))
           "not a git repository: every agent works in a git worktree of its own")
          ((not (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet" "HEAD")))
           "no commit yet: an agent's worktree branches from one"))))

(defun agent-workspace-worktree-reason (agent)
  "Why AGENT's worktree is locked, naming it: \"agent ada (builder), crew of
doom\"."
  (format "agent %s (%s), crew of %s"
          (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)
          (file-name-nondirectory (directory-file-name (agent-workspace-agent-project agent)))))

(defun agent-workspace--worktrees (project)
  "PROJECT's worktrees as git lists them: a plist each (:dir, :branch,
:locked: its reason, or t)."
  (let ((default-directory project)
        worktrees current)
    (dolist (line (split-string (agent-workspace--git "worktree" "list" "--porcelain") "\n"))
      (cond ((string-prefix-p "worktree " line)
             (when current (push current worktrees))
             (setq current (list :dir (file-name-as-directory (substring line 9)))))
            ((string-prefix-p "branch refs/heads/" line)
             (setq current (plist-put current :branch (substring line 18))))
            ((string-match "\\`locked\\(?: \\(.*\\)\\)?\\'" line)
             (setq current (plist-put current :locked (or (match-string 1 line) t))))))
    (when current (push current worktrees))
    (nreverse worktrees)))

(defun agent-workspace--worktree-entry (project dir)
  "PROJECT's worktree DIR as git lists it, or nil."
  (let ((dir (file-name-as-directory (file-truename dir))))
    (seq-find (lambda (worktree) (equal (plist-get worktree :dir) dir))
              (agent-workspace--worktrees project))))

(defun agent-workspace--worktree-lock (agent)
  "AGENT's worktree locked with its reason (`agent-workspace-worktree-reason'),
if it isn't: `git worktree prune' and `remove' leave it alone."
  (let ((default-directory (agent-workspace-agent-project agent))
        (dir (agent-workspace-agent-worktree agent)))
    (unless (plist-get (agent-workspace--worktree-entry default-directory dir) :locked)
      (agent-workspace--git "worktree" "lock" "--reason" (agent-workspace-worktree-reason agent)
                            (directory-file-name dir)))))

(defun agent-workspace--worktree-unlock (project dir)
  "PROJECT's worktree DIR unlocked, if it's locked."
  (when (plist-get (agent-workspace--worktree-entry project dir) :locked)
    (let ((default-directory project))
      (agent-workspace--git "worktree" "unlock" (directory-file-name dir)))))

(defun agent-workspace--agent-worktrees (project name)
  "PROJECT's worktrees in its agents' folder (`agent-workspace-worktrees-directory';
never its main checkout, nor one of yours elsewhere) that are the agent
NAME's: on its branch agent/NAME, or locked with its name. Their folders."
  (let ((under (file-name-as-directory
                (file-truename (expand-file-name agent-workspace-worktrees-directory project))))
        (branch (agent-workspace-branch name))
        (reason (concat "agent " name " (")))
    (delq nil (mapcar (lambda (worktree)
                        (let ((locked (plist-get worktree :locked)))
                          (and (string-prefix-p under (plist-get worktree :dir))
                               (or (equal (plist-get worktree :branch) branch)
                                   (and (stringp locked) (string-prefix-p reason locked)))
                               (plist-get worktree :dir))))
                      (agent-workspace--worktrees project)))))

(defun agent-workspace-worktree-ensure (agent)
  "AGENT's worktree, made if it isn't there yet (on agent/NAME, made from the
project's HEAD if there's none), else reused as it is, on the branch it's
on (moved to its folder if it's elsewhere in its agents' folder); locked
with AGENT's name. Its folder and branch are set in AGENT."
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-name agent))
         (dir (agent-workspace-worktree-directory project name (agent-workspace-agent-role agent)))
         (branch (agent-workspace-branch name))
         (default-directory project))
    (unless (file-exists-p (expand-file-name ".git" dir))
      (when-let* ((reason (agent-workspace-no-crew-reason project)))
        (user-error "%s: %s" (file-name-nondirectory (directory-file-name project)) reason))
      (agent-workspace--keep-out-of-git project)
      (let* ((here (file-name-as-directory (file-truename dir)))
             (others (remove here (agent-workspace--agent-worktrees project name)))
             (old (seq-find #'file-directory-p others)))
        ;; Its folder went (deleted by hand, the agents' folder with it)
        ;; while git still lists it: locked, it's never pruned. The agents'
        ;; folder made first: git finds a worktree by its path's parent.
        (make-directory (file-name-directory (directory-file-name dir)) t)
        (agent-workspace--worktree-unlock project dir)
        (dolist (gone (seq-remove #'file-directory-p others))
          (agent-workspace--worktree-unlock project gone))
        (agent-workspace--git "worktree" "prune")
        (cond
         ;; Its worktree, named otherwise (as before, or for its role before):
         ;; moved here, its work with it. git won't move a locked one.
         (old
          (agent-workspace--worktree-unlock project old)
          (agent-workspace--git "worktree" "move" (directory-file-name old) (directory-file-name dir)))
         ((agent-workspace--branch-p branch)
          (agent-workspace--git "worktree" "add" (directory-file-name dir) branch))
         (t (agent-workspace--git "worktree" "add" "-b" branch (directory-file-name dir) "HEAD")))))
    (setf (agent-workspace-agent-worktree agent) dir
          (agent-workspace-agent-branch agent) (agent-workspace--worktree-head dir))
    (agent-workspace--worktree-lock agent)
    dir))

(defun agent-workspace--branch-p (branch)
  "Non-nil if BRANCH is a branch of `default-directory''s repository."
  (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet" (concat "refs/heads/" branch))))

(defun agent-workspace-worktree-move-blocker (agent name role)
  "Why AGENT's worktree can't move to the folder of NAME and ROLE, or nil: a
folder there already (a forgotten agent's, kept), or renamed, its resting
branch agent/NAME there already."
  (let* ((project (agent-workspace-agent-project agent))
         (old (agent-workspace-agent-worktree agent))
         (dir (agent-workspace-worktree-directory project name role))
         (default-directory project))
    (cond ((and (file-exists-p dir)
                (not (and old (file-exists-p old) (equal (file-truename old) (file-truename dir)))))
           (format "%s is there already" (file-relative-name (directory-file-name dir) project)))
          ((and (not (equal name (agent-workspace-agent-name agent)))
                (agent-workspace--branch-p (agent-workspace-branch name)))
           (format "the branch %s is there already" (agent-workspace-branch name))))))

(defun agent-workspace-worktree-move (agent name role)
  "AGENT's worktree moved to the folder of NAME and ROLE, the branch it rests
on renamed after NAME (agent/NAME; those of its work keep their names, now
NAME's), its lock's reason too (AGENT renamed, given ROLE, meanwhile). The
branch it's on is kept. Its session must not run. git failing midway: what
was done put back, its worktree locked again, AGENT as it was, the error
signalled."
  (let* ((project (agent-workspace-agent-project agent))
         (old (agent-workspace-agent-worktree agent))
         (dir (agent-workspace-worktree-directory project name role))
         (old-name (agent-workspace-agent-name agent))
         (old-rest (agent-workspace-branch old-name))
         (rest (agent-workspace-branch name))
         (noted (unless (equal old-name name) (agent-workspace--noted-branches project old-name)))
         (default-directory project)
         moved renamed)
    (condition-case err
        (progn
          (when (and old (file-exists-p old) (not (equal (file-truename old) (file-truename dir))))
            ;; git won't move a locked worktree.
            (agent-workspace--worktree-unlock project old)
            (agent-workspace--git "worktree" "move" (directory-file-name old) (directory-file-name dir))
            (setq moved t))
          (unless (equal old-name name)
            (when (agent-workspace--branch-p old-rest)
              (agent-workspace--git "branch" "-m" old-rest rest)
              (setq renamed t))
            (dolist (branch noted)
              (agent-workspace--branch-note project branch name))))
      (error
        ;; Put back, its lock too: AGENT's slots are as they were.
        (when renamed (ignore-errors (agent-workspace--git "branch" "-m" rest old-rest)))
        (dolist (branch noted)
          (ignore-errors (agent-workspace--branch-note project branch old-name)))
        (when moved
          (ignore-errors (agent-workspace--git "worktree" "move" (directory-file-name dir) (directory-file-name old))))
        (when (and old (file-exists-p old))
          (ignore-errors (agent-workspace--worktree-lock agent)))
        (signal (car err) (cdr err))))
    (setf (agent-workspace-agent-worktree agent) dir
          (agent-workspace-agent-branch agent)
          (if (file-exists-p (expand-file-name ".git" dir))
              (agent-workspace--worktree-head dir)
            (let ((branch (agent-workspace-agent-branch agent)))
              (if (equal branch old-rest) rest branch)))
          (agent-workspace-agent-name agent) name
          (agent-workspace-agent-role agent) role)
    (when (file-exists-p dir)
      (agent-workspace--worktree-lock agent))))

;; ====== A BRANCH FOR EACH PIECE OF WORK ======
;; In the agent's own worktree, opened as the work starts: an issue given to
;; it (t, the room's offer, its loop, :issue as it's made: `agent-workspace-give'
;; in core.el), TYPE/ID-SLUG (fix/doom-pbk.18-minimaps-dividers-dont-line:
;; its title's first words, small ones dropped), from the main checkout's
;; branch as it is then. One of the issue's already there (TYPE/ID-..., any
;; type, any words: the issue given back, its title changed since) checked
;; out again, taken from the agent
;; at rest that has it. Given while it works, as its next turn starts (the
;; issue's prompt, queued). A prompt of yours while it
;; rests (on agent/NAME, holding nothing the main branch hasn't), a branch
;; named from its first words, where it is: the same commit, no file
;; changed. Its worktree with changes not committed can't take an issue's.
;;
;; Between pieces of work it rests on agent/NAME, at the main branch's tip:
;; nothing is merged from it (one holding work from before is left as it is,
;; and merged as it was). Merged (M), its branch is deleted and it rests. A
;; branch it leaves holding nothing the main branch hasn't (a question
;; asked, an investigation, one merged) is deleted. Each is noted as its
;; agent's in the repository's config (branch.BRANCH.agent-workspace-agent):
;; forgetting the agent finds them.

(defun agent-workspace-slug (text)
  "TEXT as words of a branch's name: lowercased, a leading \"Area: \"
dropped (\"Agent workspace: \"), apostrophes dropped, accents too, every
other run of characters but a-z and 0-9 one -, at most 48 characters, cut
at a -. \"\" when nothing's left."
  (let ((text (downcase (string-trim text))))
    (when (string-match "\\`[[:alnum:]][^:\n]\\{0,29\\}:[[:space:]]+" text)
      (let ((rest (substring text (match-end 0))))
        (when (string-match-p "[[:alnum:]]" rest)
          (setq text rest))))
    ;; Accents dropped: é decomposed, e and its mark, the mark gone.
    (setq text (replace-regexp-in-string "['\u2019\u0300-\u036f]" "" (ucs-normalize-NFD-string text)))
    (setq text (string-trim (replace-regexp-in-string "[^a-z0-9]+" "-" text) "-+" "-+"))
    (when (> (length text) agent-workspace--slug-length)
      (let ((cut (substring text 0 (1+ agent-workspace--slug-length))))
        (setq text (if (string-match "-[^-]*\\'" cut)
                       (substring cut 0 (match-beginning 0))
                     (substring text 0 agent-workspace--slug-length)))))
    (string-trim text "-+" "-+")))

(defconst agent-workspace--branch-words 4
  "How many of an issue title's words its branch's name takes.")

(defconst agent-workspace--small-words
  '("a" "an" "the" "and" "or" "of" "on" "in" "into" "to" "for" "its" "it" "is" "are" "be" "by"
    "with" "as" "at" "from" "that" "this" "not" "per" "one" "must" "always" "never" "than" "so")
  "Words an issue's branch leaves out of its title.")

(defun agent-workspace-branch-words (title)
  "TITLE's first words for a branch's name: its slug's
\(`agent-workspace-slug'), small words dropped, `agent-workspace--branch-words'
of them (\"minimaps-dividers-dont-line\"); \"\" when none are left."
  (string-join (seq-take (seq-remove (lambda (word) (member word agent-workspace--small-words))
                                     (split-string (agent-workspace-slug (or title "")) "-" t))
                         agent-workspace--branch-words)
               "-"))

(defun agent-workspace-issue-branch (issue &optional type title)
  "The branch made for ISSUE (its id) of TYPE (bd's issue_type), titled
TITLE: TYPE/ID-SLUG, fix/ for a bug, feat/ for a feature, task/ when its
type isn't known, then its title's first words
\(`agent-workspace-branch-words'): \"fix/doom-pbk.18-minimaps-dividers-dont-line\".
No title, or none of its words left: TYPE/ID."
  (let ((type (agent-workspace-slug (or type "")))
        (words (agent-workspace-branch-words title)))
    (concat (pcase type ("bug" "fix") ("feature" "feat") ("" "task") (_ type)) "/" issue
            (if (string-empty-p words) "" (concat "-" words)))))

(defun agent-workspace--branches (project)
  "PROJECT's branches, their names."
  (let ((default-directory project))
    (mapcar (lambda (ref) (string-remove-prefix "refs/heads/" ref))
            (agent-workspace--git-lines "for-each-ref" "--format=%(refname)" "refs/heads/"))))

(defun agent-workspace--branch-note (project branch name)
  "PROJECT's BRANCH noted as the work of the agent NAME (git config
branch.BRANCH.agent-workspace-agent): forgetting NAME finds it."
  (let ((default-directory project))
    (process-file "git" nil nil nil "config" (concat "branch." branch ".agent-workspace-agent") name)))

(defun agent-workspace--branch-notes (project)
  "PROJECT's branches noted as an agent's work, that are there: ((BRANCH .
NAME)...), as git's config lists them."
  (let ((default-directory project)
        (there (agent-workspace--branches project)))
    (seq-filter (lambda (note) (member (car note) there))
                (delq nil (mapcar (lambda (line)
                                    (and (string-match "\\`branch\\.\\(.+\\)\\.agent-workspace-agent \\(.*\\)\\'" line)
                                         (cons (match-string 1 line) (match-string 2 line))))
                                  (agent-workspace--git-lines "config" "--get-regexp"
                                                              "^branch\\..*\\.agent-workspace-agent$"))))))

(defun agent-workspace--noted-branches (project name)
  "PROJECT's branches noted as the agent NAME's work, that are there."
  (mapcar #'car (seq-filter (lambda (note) (equal (cdr note) name))
                            (agent-workspace--branch-notes project))))

(defun agent-workspace--branch-holder (project branch)
  "The folder of PROJECT's worktree BRANCH is checked out in (its main
checkout's too), or nil."
  (plist-get (seq-find (lambda (worktree) (equal (plist-get worktree :branch) branch))
                       (agent-workspace--worktrees project))
             :dir))

(defun agent-workspace-agent-branches (agent)
  "AGENT's branches: the one it's on, agent/NAME, and those of its work
\(noted as its); those there, none checked out in another worktree (taken
by another agent)."
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-name agent))
         (dir (agent-workspace--worktree-live agent))
         (here (and dir (file-name-as-directory (file-truename dir))))
         (there (agent-workspace--branches project))
         (elsewhere (delq nil (mapcar (lambda (worktree)
                                        (and (not (equal (plist-get worktree :dir) here))
                                             (plist-get worktree :branch)))
                                      (agent-workspace--worktrees project)))))
    (seq-filter (lambda (branch) (and (member branch there) (not (member branch elsewhere))))
                (delete-dups (delq nil (append (list (and dir (agent-workspace--worktree-head dir))
                                                     (agent-workspace-branch name))
                                               (agent-workspace--noted-branches project name)))))))

(defun agent-workspace--ahead-p (project branch main)
  "Non-nil if PROJECT's BRANCH has commits MAIN hasn't."
  (let ((default-directory project))
    (not (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" branch main)))))

(defun agent-workspace--worktree-live (agent)
  "AGENT's worktree's folder, if it's there; else nil."
  (when-let* ((dir (agent-workspace-agent-worktree agent)))
    (and (file-exists-p (expand-file-name ".git" dir)) dir)))

(defun agent-workspace--changes (dir)
  "What the worktree DIR has not committed: git status's lines."
  (let ((default-directory dir))
    (split-string (agent-workspace--git "status" "--porcelain") "\n" t)))

(defun agent-workspace-branch-blocker (agent &optional branch)
  "Why AGENT's worktree can't go to another branch now (but BRANCH, if it's
on it), or nil: changes it hasn't committed."
  (when-let* ((dir (agent-workspace--worktree-live agent)))
    (let ((head (agent-workspace--worktree-head dir)))
      (when (and (not (and branch (equal head branch)))
                 (agent-workspace--changes dir))
        (format "%s has changes not committed, on %s" (agent-workspace-agent-name agent)
                (or head "no branch"))))))

(defun agent-workspace--branch-drop (project branch)
  "PROJECT's BRANCH deleted if it holds nothing the main branch hasn't and
no worktree has it. Non-nil if it was."
  (let ((default-directory project))
    (when (and (agent-workspace--branch-p branch)
               (not (agent-workspace--branch-holder project branch))
               (not (agent-workspace--ahead-p project branch (agent-workspace-main-branch project))))
      (eql 0 (process-file "git" nil nil nil "branch" "-D" branch)))))

(defun agent-workspace--branch-switch (agent branch &optional start reset)
  "AGENT's worktree switched to BRANCH: made from START if it isn't there
\(RESET: made there even if it is; no START: where it is), noted as AGENT's
work (but agent/NAME). The branch it leaves is deleted if it holds nothing
the main branch hasn't (never agent/NAME). Its branch slot set, said."
  (let* ((project (agent-workspace-agent-project agent))
         (dir (agent-workspace-agent-worktree agent))
         (name (agent-workspace-agent-name agent))
         (rest (agent-workspace-branch name))
         (old (agent-workspace--worktree-head dir)))
    (let ((default-directory dir))
      (cond (reset (agent-workspace--git "switch" "--quiet" "--no-track" "-C" branch start))
            ((agent-workspace--branch-p branch)
             (unless (equal old branch)
               (agent-workspace--git "switch" "--quiet" branch)))
            (start (agent-workspace--git "switch" "--quiet" "--no-track" "-c" branch start))
            (t (agent-workspace--git "switch" "--quiet" "-c" branch))))
    (unless (equal branch rest)
      (agent-workspace--branch-note project branch name))
    (when (and old (not (member old (list branch rest))))
      (agent-workspace--branch-drop project old))
    (agent-workspace--branch-sync agent branch)))

(defun agent-workspace--branch-sync (agent &optional branch)
  "AGENT's branch slot as its worktree is (BRANCH: the one it's on, known),
said to `agent-workspace-change-functions' (`branch') if it changed."
  (when-let* ((dir (agent-workspace--worktree-live agent)))
    (let ((branch (or branch (agent-workspace--worktree-head dir))))
      (unless (equal branch (agent-workspace-agent-branch agent))
        (setf (agent-workspace-agent-branch agent) branch)
        (agent-workspace--changed agent 'branch)))))

(defun agent-workspace-rest (agent)
  "AGENT's worktree back at rest, between pieces of work: on agent/NAME, at
the main checkout's branch's tip (made there if it's gone; left as it is if
it holds commits that branch hasn't: work from before, kept). Its worktree
must have nothing uncommitted."
  (let* ((project (agent-workspace-agent-project agent))
         (main (agent-workspace-main-branch project))
         (rest (agent-workspace-branch (agent-workspace-agent-name agent))))
    (if (and (let ((default-directory project)) (agent-workspace--branch-p rest))
             (agent-workspace--ahead-p project rest main))
        (agent-workspace--branch-switch agent rest)
      (agent-workspace--branch-switch agent rest main t))))

(defun agent-workspace-branch-open (agent branch &optional start)
  "AGENT's worktree on BRANCH, for its next work: made from START if it
isn't there, else checked out again. Checked out in another agent's
worktree, that agent at rest (not working, nothing uncommitted there), it's
taken from it: that agent rests (`agent-workspace-rest'). A user error,
nothing changed, if it can't be: AGENT's worktree has changes not
committed, or BRANCH is held."
  (let* ((project (agent-workspace-agent-project agent))
         (dir (file-name-as-directory (file-truename (agent-workspace-agent-worktree agent)))))
    (unless (equal (agent-workspace--worktree-head dir) branch)
      (when-let* ((why (agent-workspace-branch-blocker agent branch)))
        (user-error "%s" why))
      (when-let* ((holder (agent-workspace--branch-holder project branch))
                  ((not (equal holder dir))))
        (let ((other (seq-find (lambda (other)
                                 (when-let* ((worktree (agent-workspace-agent-worktree other)))
                                   (equal (file-name-as-directory (file-truename worktree)) holder)))
                               (agent-workspace-agents project))))
          (cond
           ((not other)
            (user-error "%s is checked out in %s" branch (abbreviate-file-name (directory-file-name holder))))
           ((memq (agent-workspace-agent-state other) '(working hand))
            (user-error "%s is %s's: it's working on it" branch (agent-workspace-agent-name other)))
           ((when-let* ((why (agent-workspace-branch-blocker other)))
              (user-error "%s is %s's: %s" branch (agent-workspace-agent-name other) why))))
          (agent-workspace-rest other)))
      (agent-workspace--branch-switch agent branch start))))

(defun agent-workspace--issue-branch-there (project issue type &optional title)
  "The branch of PROJECT for ISSUE of TYPE, titled TITLE: the one there
already, as it'd be named now, else the issue's by its id, whatever its
type and words (TYPE/ID, TYPE/ID-...: its title changed since, or named
otherwise before); none, as it'd be named now (`agent-workspace-issue-branch')."
  (let* ((branch (agent-workspace-issue-branch issue type title))
         (there (agent-workspace--branches project)))
    (or (car (member branch there))
        (seq-find (lambda (other)
                    (and (not (string-prefix-p "agent/" other))
                         (string-match-p (concat "\\`[^/]+/" (regexp-quote issue) "\\(?:-\\|\\'\\)") other)))
                  there)
        branch)))

(defun agent-workspace-issue-branch-open (agent issue &optional type title)
  "AGENT given ISSUE (of TYPE, bd's issue_type; not given: as its issues
were last fetched, issues.el), titled TITLE: its worktree on the issue's
branch (`agent-workspace-issue-branch': TYPE/ID-SLUG), made from the main
checkout's branch as it is then, or checked out again (the issue given
back, whatever its branch's words). Now, or if AGENT is working, as its next turn
starts (the issue's prompt, queued). A user error if it can't be now
\(`agent-workspace-branch-open'). Nothing without its worktree."
  (when (agent-workspace--worktree-live agent)
    (let* ((project (agent-workspace-agent-project agent))
           (type (or type (and (fboundp 'agent-workspace-issue-type) (agent-workspace-issue-type project issue)))))
      (if (memq (agent-workspace-agent-state agent) '(working hand))
          (puthash agent (list issue type title) agent-workspace--branch-next)
        (remhash agent agent-workspace--branch-next)
        (agent-workspace-branch-open agent (agent-workspace--issue-branch-there project issue type title)
                                     (agent-workspace-main-branch project))))))

(defun agent-workspace-branch-quiet (agent text)
  "TEXT, sent to AGENT, is no work of its own (it's told of a merge, given
an event): the turn it starts makes no branch."
  (puthash agent (cons text (gethash agent agent-workspace--branch-quiet)) agent-workspace--branch-quiet))

(defun agent-workspace--branch-quiet-p (agent prompt)
  "Non-nil if PROMPT holds a text sent to AGENT that's no work of its own
\(`agent-workspace-branch-quiet'): forgotten then."
  (when-let* ((texts (gethash agent agent-workspace--branch-quiet))
              (text (and (stringp prompt) (seq-find (lambda (text) (string-search text prompt)) texts))))
    (puthash agent (remove text texts) agent-workspace--branch-quiet)
    t))

(defun agent-workspace--fresh-branch (project slug)
  "A name for a branch of PROJECT from SLUG that it hasn't yet: SLUG, else
SLUG-2, SLUG-3... (\"work\" for an empty SLUG)."
  (let ((slug (if (string-empty-p slug) "work" slug))
        (there (agent-workspace--branches project)))
    (if (member slug there)
        (cl-loop for n from 2
                 for name = (format "%s-%d" slug n)
                 unless (member name there) return name)
      slug)))

(defun agent-workspace--branch-say (agent text)
  "TEXT said of AGENT: in its room (once there's one), and as a message."
  (message "%s %s" (agent-workspace-agent-name agent) text)
  (when (fboundp 'agent-workspace-room-post)
    (agent-workspace-room-post (agent-workspace-agent-project agent)
                               :kind 'note :agent (agent-workspace-agent-name agent) :text text)))

(defun agent-workspace--turn-branch (agent prompt &optional steer)
  "AGENT's turn starts, with PROMPT (agent-shell's input-submitted, before
its agent gets it): its worktree on the branch of the issue it was given
while it worked; else, at rest (on agent/NAME, holding nothing the main
branch hasn't) and given work (not a / command, nor something it's told:
`agent-workspace-branch-quiet'), on a new branch named from PROMPT's first
words, where it is. What can't be done is said, never signalled. STEER:
PROMPT steered into the turn running: nothing switched (the issue's
branch waits for its next turn), PROMPT's quiet mark taken."
  (if steer
      (agent-workspace--branch-quiet-p agent prompt)
    (agent-workspace--turn-branch-1 agent prompt)))

(defun agent-workspace--turn-branch-1 (agent prompt)
  "`agent-workspace--turn-branch' for a turn that starts."
  (when-let* ((dir (agent-workspace--worktree-live agent)))
    (condition-case err
        (let* ((project (agent-workspace-agent-project agent))
               (head (agent-workspace--worktree-head dir))
               (next (gethash agent agent-workspace--branch-next))
               (quiet (agent-workspace--branch-quiet-p agent prompt)))
          ;; Its slot as its worktree is (switched by hand meanwhile).
          (agent-workspace--branch-sync agent head)
          (cond
           ;; Given back meanwhile (killed): no longer its.
           ((and next (progn (remhash agent agent-workspace--branch-next)
                             (equal (car next) (agent-workspace-agent-issue agent))))
            (condition-case err
                (agent-workspace-branch-open agent (apply #'agent-workspace--issue-branch-there project next)
                                             (agent-workspace-main-branch project))
              (user-error
               (agent-workspace--branch-say
                agent (format "stays on %s for %s: %s" (or head "no branch") (car next)
                              (error-message-string err))))))
           ((and (not quiet) (stringp prompt)
                 (not (string-prefix-p "/" (string-trim-left prompt)))
                 (equal head (agent-workspace-branch (agent-workspace-agent-name agent)))
                 (not (agent-workspace--ahead-p project head (agent-workspace-main-branch project))))
            (agent-workspace--branch-switch
             agent (agent-workspace--fresh-branch project (agent-workspace-slug prompt))))))
      (error (agent-workspace--branch-say agent (concat "got no branch of its own: " (error-message-string err)))))))

;; ====== ITS WORK ======

(defun agent-workspace-main-branch (project)
  "The branch PROJECT's main checkout is on (\"main\"), or its commit."
  (let ((default-directory project))
    (or (agent-workspace--git-line "branch" "--show-current")
        (agent-workspace--git "rev-parse" "HEAD"))))

(defun agent-workspace-worktree-work (agent)
  "What AGENT's worktree holds that the main checkout hasn't: a plist,
:changes (git status's lines: not committed) and :commits (each of its
branches with commits not on the main checkout's branch, the one it's on
first: (BRANCH LINE...), a line a commit; see `agent-workspace-agent-branches')."
  (let* ((project (agent-workspace-agent-project agent))
         (dir (agent-workspace-agent-worktree agent))
         (main (agent-workspace-main-branch project)))
    (list :changes (when (and dir (file-directory-p dir))
                     (agent-workspace--changes dir))
          :commits (let ((default-directory project))
                     (delq nil (mapcar (lambda (branch)
                                         (when-let* ((lines (split-string (agent-workspace--git
                                                                           "log" "--oneline" (concat main ".." branch))
                                                                          "\n" t)))
                                           (cons branch lines)))
                                       (agent-workspace-agent-branches agent)))))))

(defun agent-workspace-branch-ahead (agent)
  "How many commits the branch AGENT is on has that the main checkout's
hasn't."
  (length (cdr (assoc (agent-workspace-agent-branch agent)
                      (plist-get (agent-workspace-worktree-work agent) :commits)))))

(defun agent-workspace-worktree-remove (agent)
  "AGENT's worktree removed, and its branches deleted
\(`agent-workspace-agent-branches'), whatever they hold."
  (let* ((project (agent-workspace-agent-project agent))
         (dir (agent-workspace-agent-worktree agent))
         (branches (agent-workspace-agent-branches agent))
         (default-directory project))
    (when (and dir (agent-workspace--worktree-entry project dir))
      (agent-workspace--worktree-unlock project dir)
      (agent-workspace--git "worktree" "remove" "--force" (directory-file-name dir)))
    (dolist (branch branches)
      (when (agent-workspace--branch-p branch)
        (agent-workspace--git "branch" "-D" branch)))))

(defun agent-workspace--ask-about-work (agent work)
  "Ask whether to keep AGENT's worktree, which holds WORK (see
`agent-workspace-worktree-work'), shown meanwhile: `keep' or `remove'."
  (let ((buffer (get-buffer-create (format "*%s's work*" (agent-workspace-agent-name agent)))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s's worktree, %s, on %s, holds work the main checkout hasn't.\n"
                        (agent-workspace-agent-name agent)
                        (abbreviate-file-name (agent-workspace-agent-worktree agent))
                        (or (agent-workspace-agent-branch agent) "no branch")))
        (when-let* ((changes (plist-get work :changes)))
          (insert "\nNot committed:\n" (mapconcat (lambda (line) (concat "  " line)) changes "\n") "\n"))
        (when-let* ((commits (plist-get work :commits)))
          (insert (format "\nNot on %s:\n" (agent-workspace-main-branch (agent-workspace-agent-project agent)))
                  (mapconcat (lambda (branch)
                               (concat "  " (car branch) "\n"
                                       (mapconcat (lambda (line) (concat "    " line)) (cdr branch) "\n")))
                             commits "\n")
                  "\n")))
      (special-mode))
    (unwind-protect
        (save-window-excursion
          (pop-to-buffer buffer)
          (if (eq (car (read-multiple-choice
                        (format "Forget %s: its worktree " (agent-workspace-agent-name agent))
                        '((?k "keep it" "Keep its worktree and branches, as they are")
                          (?r "remove it anyway" "Remove its worktree and delete its branches, losing this work"))))
                  ?r)
              'remove
            'keep))
      (kill-buffer buffer))))

(defun agent-workspace-worktree-fate (agent &optional how)
  "What becomes of AGENT's worktree as AGENT is forgotten: HOW (`keep' or
`remove'), or if nil, `remove' when it holds nothing the main checkout
hasn't, else what you choose, shown what it holds."
  (or how
      (let ((work (agent-workspace-worktree-work agent)))
        (if (or (plist-get work :changes) (plist-get work :commits))
            (agent-workspace--ask-about-work agent work)
          'remove))))

;; ====== REVIEW AND MERGE ======

(declare-function magit-diff-range "magit-diff")
(declare-function magit-log-other "magit-log")
(declare-function magit-log-arguments "magit-log")

(defun agent-workspace-read-branch (agent prompt)
  "One of AGENT's branches, read with PROMPT (a format: AGENT's name): the
one it's on, unless others of its hold commits the main checkout's branch
hasn't: then you're asked, the one it's on first."
  ;; Its slot as its worktree is (the agent renamed its branch since).
  (agent-workspace--branch-sync agent)
  (let* ((work (mapcar #'car (plist-get (agent-workspace-worktree-work agent) :commits)))
         (choices (delete-dups (delq nil (cons (agent-workspace-agent-branch agent) work)))))
    (cond ((cdr choices)
           (completing-read (format prompt (agent-workspace-agent-name agent)) choices nil t nil nil
                            (car choices)))
          (choices (car choices))
          (t (user-error "%s is on no branch" (agent-workspace-agent-name agent))))))

(defun agent-workspace-review (agent &optional branch)
  "Show what AGENT's BRANCH (default: the one it's on) changed since it left
the main checkout's branch (MAIN...BRANCH): in magit, else as a diff."
  (interactive (let ((agent (agent-workspace-read-agent "Review the branch of: ")))
                 (list agent (agent-workspace-read-branch agent "Review %s's branch: "))))
  (agent-workspace--branch-sync agent)
  (agent-workspace-review-branch (agent-workspace-agent-project agent)
                                 (or branch (agent-workspace-agent-branch agent)
                                     (user-error "%s is on no branch" (agent-workspace-agent-name agent)))
                                 (agent-workspace-agent-name agent)))

(defun agent-workspace-review-branch (project branch name)
  "Show what PROJECT's BRANCH, the agent NAME's (one forgotten too: no agent
needed), changed since it left the main checkout's branch (MAIN...BRANCH):
in magit, else as a diff."
  (let ((range (concat (agent-workspace-main-branch project) "..." branch))
        (default-directory project))
    (if (require 'magit nil t)
        (magit-diff-range range)
      (let ((buffer (get-buffer-create (format "*%s's changes*" name))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (process-file "git" nil t nil "diff" range))
          (diff-mode)
          (setq buffer-read-only t)
          (goto-char (point-min)))
        (pop-to-buffer buffer)))))

(defun agent-workspace-branch-commits (project branch name)
  "Show PROJECT's BRANCH's commits (the agent NAME's, forgotten maybe) the
main checkout's branch hasn't (MAIN..BRANCH): magit's log, else git log's."
  (let ((range (concat (agent-workspace-main-branch project) ".." branch))
        (default-directory project))
    (if (require 'magit nil t)
        (apply #'magit-log-other (list range) (magit-log-arguments))
      (let ((buffer (get-buffer-create (format "*%s's commits*" name))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (process-file "git" nil t nil "log" range))
          (special-mode)
          (setq default-directory project)
          (goto-char (point-min)))
        (pop-to-buffer buffer)))))

(defun agent-workspace--merge-in (project branch)
  "BRANCH merged into PROJECT's main checkout, always with a merge commit
naming it (--no-ff: never a fast-forward, so its commits stay told apart
from yours). Non-nil if it merged; stopped on conflicts, said, left to you
in the main checkout."
  (let ((default-directory project))
    (with-temp-buffer
      (or (eql 0 (process-file "git" nil t nil "merge" "--no-ff" "--no-edit" branch))
          (progn
            (message "Merging %s stopped: %s" branch (string-trim (buffer-string)))
            nil)))))

(defun agent-workspace-merge (agent &optional branch)
  "Merge AGENT's BRANCH (default: the one it's on) into the main checkout's
branch, always with a merge commit naming it (--no-ff: never a
fast-forward, so its commits stay told apart from yours). Merged, the
branch is deleted and AGENT rests on agent/NAME at the merged tip
\(`agent-workspace-rest'): if it's on it, only while it isn't working and
its worktree has nothing uncommitted, else left for later (M again), said.
agent/NAME itself (work from before) isn't deleted: it rests there. AGENT
is told (if its session runs). A merge stopped on conflicts is left to you,
in the main checkout. Return non-nil if it merged."
  (interactive (let ((agent (agent-workspace-read-agent "Merge the branch of: ")))
                 (list agent (agent-workspace-read-branch agent "Merge %s's branch: "))))
  (agent-workspace--branch-sync agent)
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-name agent))
         (branch (or branch (agent-workspace-agent-branch agent) (user-error "%s is on no branch" name)))
         (main (agent-workspace-main-branch project))
         (rest (agent-workspace-branch name))
         (dir (agent-workspace--worktree-live agent))
         (on (and dir (equal (agent-workspace--worktree-head dir) branch)))
         (default-directory project))
    (when (agent-workspace--merge-in project branch)
      (let ((why (and on (if (memq (agent-workspace-agent-state agent) '(working hand))
                             (format "%s is working" name)
                           (agent-workspace-branch-blocker agent)))))
        (cond
         (why)
         ;; Back at rest: the branch it leaves, merged, deleted.
         (on (agent-workspace-rest agent))
         ;; agent/NAME, not checked out: at the tip, merged.
         ((equal branch rest)
          (unless (agent-workspace--branch-holder project rest)
            (agent-workspace--git "branch" "--force" rest main)))
         (t (agent-workspace--branch-drop project branch)))
        (let* ((gone (and (not why) (not (equal branch rest)) (not (agent-workspace--branch-p branch))))
               (said (cond
                      (why (format "; %s kept for now (M again later): %s" branch why))
                      ((equal branch rest) (format ": %s at its tip" rest))
                      ((and gone on) (format ": %s deleted, %s rests on %s" branch name rest))
                      (gone (format ": %s deleted" branch))
                      (t ""))))
          (when (agent-workspace-live-p agent)
            (agent-workspace-send
             agent (format "The user merged your branch %s into %s%s" branch main
                           (cond
                            ((and gone on)
                             (format " and deleted it: your worktree is back on %s, at %s's tip. Your \
next work gets a branch of its own." rest main))
                            ((and (not why) (equal branch rest))
                             (format ": it's at %s's tip now. Your next work gets a branch of its own." main))
                            (gone " and deleted it.")
                            (t ".")))
             :submit t :no-branch t))
          (message "Merged %s into %s%s" branch main said)
          t)))))

(defun agent-workspace-merge-kept (project branch)
  "Merge PROJECT's BRANCH, kept from an agent no longer in the crew, into
the main checkout's branch as `agent-workspace-merge' does (--no-ff, a
merge commit naming it), no agent told. Merged, it's deleted (unless a
worktree has it: a forgotten agent's kept). A merge stopped on conflicts
is left to you. Return non-nil if it merged."
  (let ((main (agent-workspace-main-branch project)))
    (when (agent-workspace--merge-in project branch)
      (let ((gone (agent-workspace--branch-drop project branch)))
        (message "Merged %s into %s%s" branch main (if gone (format ": %s deleted" branch) ""))
        t))))
