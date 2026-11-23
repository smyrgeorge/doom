;;; $DOOMDIR/config/agent-workflow/worktree.el -*- lexical-binding: t; -*-
;; An issue's worktree: where the agents of its run's jobs work, one after
;; another, on the issue's branch. Loaded from config/agent-workflow.el,
;; after core.el. No Doom here.
;;
;; One per issue, not per agent: an agent is a job's, gone once its job ends,
;; and git checks a branch out in one worktree only. It's
;; .agent-shell/agent-workflow/worktrees/ISSUE (out of git: .agent-shell/ in
;; the repository's info/exclude), on the issue's branch, TYPE/ID-WORDS
;; (fix/ for a bug, feat/ for a feature: fix/doom-a1b-lexer-escapes), made
;; from your checkout's HEAD the first time a job needs it, else reused as
;; it is. It's locked with the issue as its reason, so `git worktree prune'
;; and `remove' leave it alone, and kept until its run ends.
;;
;; A workflow's own run (no ticket, runs.el) has its workflow's name for
;; ISSUE and a branch of its own, run/NAME-N, made anew each run.
;;
;; The branch's name as agent-workspace makes an issue's (copied from
;; config/agent-workspace/worktree.el, never required).

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)                ; macOS's Emacs has it loaded, Linux's not

;; ====== GIT ======

(defun agent-workflow--git (&rest args)
  "Run git with ARGS in `default-directory': its output, or a user error
with what git said."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil args)))
      (unless (eql status 0)
        (user-error "git %s: %s" (car args) (string-trim (buffer-string))))
      (string-trim (buffer-string)))))

(defun agent-workflow--git-lines (&rest args)
  "The lines git prints for ARGS in `default-directory'; none if it fails."
  (with-temp-buffer
    (when (eql 0 (apply #'process-file "git" nil '(t nil) nil args))
      (split-string (buffer-string) "\n" t))))

(defun agent-workflow--keep-out-of-git (project)
  "PROJECT's .agent-shell/ kept out of git, if it isn't: in the repository's
info/exclude (every worktree shares it), so neither the project nor a
branch gets a changed .gitignore."
  (let ((default-directory project))
    (unless (eql 0 (process-file "git" nil nil nil "check-ignore" "-q" ".agent-shell/agent-workflow"))
      (let ((exclude (expand-file-name
                      "info/exclude"
                      (agent-workflow--git "rev-parse" "--path-format=absolute" "--git-common-dir"))))
        (make-directory (file-name-directory exclude) t)
        (write-region "\n# Agents' worktrees, transcripts (agent-shell)\n/.agent-shell/\n"
                      nil exclude t 'silent)))))

;; ====== THE BRANCH ======

(defconst agent-workflow--slug-length 48 "A slug's most characters.")

(defun agent-workflow-slug (text)
  "TEXT as words of a branch's name: lowercased, a leading \"Area: \"
dropped (\"Agent workflow: \"), apostrophes dropped, accents too, every
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
    (when (> (length text) agent-workflow--slug-length)
      (let ((cut (substring text 0 (1+ agent-workflow--slug-length))))
        (setq text (if (string-match "-[^-]*\\'" cut)
                       (substring cut 0 (match-beginning 0))
                     (substring text 0 agent-workflow--slug-length)))))
    (string-trim text "-+" "-+")))

(defconst agent-workflow--small-words
  '("a" "an" "the" "and" "or" "of" "on" "in" "into" "to" "for" "its" "it" "is" "are" "be" "by"
    "with" "as" "at" "from" "that" "this" "not" "per" "one" "must" "always" "never" "than" "so")
  "Words an issue's branch leaves out of its title.")

(defun agent-workflow-issue-branch (issue &optional type title)
  "The branch of ISSUE (its id) of TYPE (bd's issue_type), titled TITLE:
TYPE/ID-WORDS, fix/ for a bug, feat/ for a feature, task/ when its type
isn't known, then 4 of its title's words, small ones left out
\(\"fix/doom-a1b-lexer-escapes\"); no words left: TYPE/ID."
  (let ((type (agent-workflow-slug (or type "")))
        (words (string-join (seq-take (seq-remove (lambda (word) (member word agent-workflow--small-words))
                                                  (split-string (agent-workflow-slug (or title "")) "-" t))
                                      4)
                            "-")))
    (concat (pcase type ("bug" "fix") ("feature" "feat") ("" "task") (_ type)) "/" issue
            (if (string-empty-p words) "" (concat "-" words)))))

(defun agent-workflow-main-branch (project)
  "PROJECT's main branch: origin's HEAD's, else main, else master, else
the branch your checkout is on."
  (let* ((default-directory project)
         (branches (agent-workflow--git-lines "for-each-ref" "--format=%(refname:short)" "refs/heads/")))
    (or (when-let* ((head (car (agent-workflow--git-lines "symbolic-ref" "--short" "refs/remotes/origin/HEAD")))
                    (name (string-remove-prefix "origin/" head)))
          (and (member name branches) name))
        (seq-find (lambda (name) (member name branches)) '("main" "master"))
        (car (agent-workflow--git-lines "branch" "--show-current"))
        "main")))

;; ====== THE WORKTREE ======

(defun agent-workflow-worktree-directory (project issue)
  "Where ISSUE's worktree is in PROJECT."
  (file-name-as-directory
   (expand-file-name issue (expand-file-name "worktrees" (expand-file-name agent-workflow-local-directory project)))))

(defun agent-workflow--worktree-reason (project issue)
  "Why ISSUE's worktree in PROJECT is locked: \"agent workflow: doom-a1b,
in doom\"."
  (format "agent workflow: %s, in %s" issue (file-name-nondirectory (directory-file-name project))))

(defun agent-workflow--worktrees (project)
  "PROJECT's worktrees as git lists them: a plist each (:dir, :branch,
:locked: its reason, or t)."
  (let ((default-directory project)
        worktrees current)
    (dolist (line (split-string (agent-workflow--git "worktree" "list" "--porcelain") "\n"))
      (cond ((string-prefix-p "worktree " line)
             (when current (push current worktrees))
             (setq current (list :dir (file-name-as-directory (substring line 9)))))
            ((string-prefix-p "branch refs/heads/" line)
             (setq current (plist-put current :branch (substring line 18))))
            ((string-match "\\`locked\\(?: \\(.*\\)\\)?\\'" line)
             (setq current (plist-put current :locked (or (match-string 1 line) t))))))
    (when current (push current worktrees))
    (nreverse worktrees)))

(defun agent-workflow--worktree-entry (project dir)
  "PROJECT's worktree DIR as git lists it, or nil."
  (let ((dir (file-name-as-directory (file-truename dir))))
    (seq-find (lambda (worktree) (equal (plist-get worktree :dir) dir))
              (agent-workflow--worktrees project))))

(defun agent-workflow-worktree-reason (&optional directory)
  "Why DIRECTORY's project (default: `default-directory''s) can't have a
worktree for an issue, or nil if it can."
  (let ((default-directory (file-name-as-directory (expand-file-name (or directory default-directory)))))
    (cond ((not (agent-workflow-project))
           "not a git repository: every issue's work is done in a git worktree of its own")
          ((not (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet" "HEAD")))
           "no commit yet: an issue's worktree branches from one"))))

(defun agent-workflow-issue-branch-made (project issue)
  "ISSUE's branch in PROJECT, made before (TYPE/ISSUE-words, whatever its
words): its name, or nil."
  (let ((default-directory (file-name-as-directory project)))
    (seq-find (lambda (name) (string-match-p (format "\\`[^/]+/%s\\(?:-\\|\\'\\)" (regexp-quote issue)) name))
              (agent-workflow--git-lines "for-each-ref" "--format=%(refname:short)" "refs/heads/"))))

(defun agent-workflow-worktree-base (project issue &optional branch)
  "Where ISSUE's worktree in PROJECT would branch from, made now: your
checkout's branch (nil: detached) and its commit, (:branch B :commit C);
nil if it's there already, or its branch (BRANCH, else the issue's) was
made before."
  (let ((default-directory (file-name-as-directory project)))
    (unless (or (file-exists-p (expand-file-name ".git" (agent-workflow-worktree-directory project issue)))
                (if branch
                    (agent-workflow--git-lines "rev-parse" "--verify" "--quiet" (concat "refs/heads/" branch))
                  (agent-workflow-issue-branch-made project issue))
                (agent-workflow-worktree-reason project))
      (list :branch (let ((name (car (agent-workflow--git-lines "branch" "--show-current"))))
                      (and name (not (string-empty-p name)) name))
            :commit (agent-workflow--git "rev-parse" "HEAD")))))

(cl-defun agent-workflow-worktree (project issue &key type title branch)
  "ISSUE's worktree in PROJECT, made if it isn't there yet, on its branch
\(`agent-workflow-issue-branch' from its TYPE and TITLE, or BRANCH: a
workflow's own run's; made from your checkout's HEAD if there's none),
else reused as it is; locked with ISSUE as its reason. Return (DIR .
BRANCH), BRANCH the one it's on."
  (let* ((project (file-name-as-directory project))
         (dir (agent-workflow-worktree-directory project issue))
         (default-directory project))
    (unless (file-exists-p (expand-file-name ".git" dir))
      (when-let* ((reason (agent-workflow-worktree-reason project)))
        (user-error "%s: %s" (file-name-nondirectory (directory-file-name project)) reason))
      (agent-workflow--keep-out-of-git project)
      ;; Its folder gone by hand: git's note of it pruned first.
      (process-file "git" nil nil nil "worktree" "prune")
      (make-directory (file-name-directory (directory-file-name dir)) t)
      (let* ((own branch)
             (branch (or own (agent-workflow-issue-branch issue type title)))
             ;; One of its id's made before, under another name (its title
             ;; changed since): that one. Its own: that one, if it's there.
             (made (if own
                       (and (agent-workflow--git-lines "rev-parse" "--verify" "--quiet" (concat "refs/heads/" own)) own)
                     (agent-workflow-issue-branch-made project issue))))
        (if made
            (agent-workflow--git "worktree" "add" (directory-file-name dir) made)
          (agent-workflow--git "worktree" "add" "-b" branch (directory-file-name dir) "HEAD"))))
    (unless (plist-get (agent-workflow--worktree-entry project dir) :locked)
      (agent-workflow--git "worktree" "lock" "--reason" (agent-workflow--worktree-reason project issue)
                           (directory-file-name dir)))
    (cons dir (plist-get (agent-workflow--worktree-entry project dir) :branch))))

(defun agent-workflow-worktree-remove (project issue)
  "ISSUE's worktree in PROJECT unlocked and removed, its branch kept; a
user error if it has changes not committed (git refuses)."
  (let ((dir (agent-workflow-worktree-directory project issue))
        (default-directory project))
    (when (agent-workflow--worktree-entry project dir)
      (when (plist-get (agent-workflow--worktree-entry project dir) :locked)
        (agent-workflow--git "worktree" "unlock" (directory-file-name dir)))
      (agent-workflow--git "worktree" "remove" (directory-file-name dir)))))

;; ====== A SNAPSHOT ======
;; A job that only reads (its agent can't edit, or a script) works on a
;; snapshot of the issue's branch as it was when it started: a worktree of its
;; own, detached at that commit, .agent-shell/agent-workflow/worktrees/
;; ISSUE@JOB, removed once the job's over. Jobs that read run beside each
;; other and beside one that edits the branch.

(defun agent-workflow-snapshot-directory (project issue job)
  "Where JOB of ISSUE's snapshot is in PROJECT."
  (file-name-as-directory
   (expand-file-name (concat issue "@" job)
                     (expand-file-name "worktrees" (expand-file-name agent-workflow-local-directory project)))))

(cl-defun agent-workflow-snapshot (project issue job &key type title branch from)
  "A snapshot for JOB of ISSUE in PROJECT: a worktree detached at the
issue's branch's commit now (the issue's worktree made if it isn't there,
on its branch from TYPE and TITLE, or BRANCH). FROM: (DIR . BRANCH), where
its commit is instead (your checkout, for a run there). One there from
before is replaced. Return (DIR BRANCH COMMIT)."
  (pcase-let* ((`(,worktree . ,branch) (or from (agent-workflow-worktree project issue :type type :title title
                                                                          :branch branch)))
               (dir (agent-workflow-snapshot-directory project issue job))
               (default-directory project)
               (commit (let ((default-directory worktree)) (agent-workflow--git "rev-parse" "HEAD"))))
    (agent-workflow-snapshot-remove project issue job)
    (agent-workflow--git "worktree" "add" "--detach" (directory-file-name dir) commit)
    (list dir branch commit)))

(defun agent-workflow-snapshot-remove (project issue job)
  "JOB of ISSUE's snapshot in PROJECT removed, whatever it has: nothing of
it is kept."
  (let ((dir (agent-workflow-snapshot-directory project issue job))
        (default-directory project))
    (when (or (file-exists-p dir) (agent-workflow--worktree-entry project dir))
      (process-file "git" nil nil nil "worktree" "remove" "--force" (directory-file-name dir))
      (when (file-exists-p dir) (delete-directory dir t))
      (process-file "git" nil nil nil "worktree" "prune"))))
