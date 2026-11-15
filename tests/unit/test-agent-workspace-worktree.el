;;; tests/unit/test-agent-workspace-worktree.el -*- lexical-binding: t; -*-
;; config/agent-workspace/worktree.el and names.el: every agent's own git
;; worktree, named after it (.agent-shell/worktrees/ROLE-NAME, agent/NAME, its lock's
;; reason), in throwaway git repositories; a branch there for each piece of
;; its work (an issue's, TYPE/ID from the main branch, renamed by its agent
;; once; a prompt's at rest;
;; taken from another agent; refused over changes not committed); forgetting
;; it without losing work, on any of its branches; reviewing and merging a
;; branch (deleted after, the agent at rest); a crew's project found from
;; them; its name on it in Emacs (the project's name, the mode line, its
;; tabs).
;; run.sh: slow (~50 s: git worktrees).

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-workspace")

;; ====== HELPERS ======

(defun +test-aww--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-aww--commit (message)
  "Commit what's staged, MESSAGE."
  (+test-aww--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" message))

(defun +test-aww--project (name &optional gitignore)
  "A git repository NAME in the temp folder, with a commit (GITIGNORE: a
.gitignore with it): its folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aww/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-aww--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil (expand-file-name "README" dir))
      (when gitignore (write-region gitignore nil (expand-file-name ".gitignore" dir)))
      (+test-aww--git "add" ".")
      (+test-aww--commit "first"))
    (file-name-as-directory (file-truename dir))))

(defun +test-aww--agent (project name)
  "An agent NAME of PROJECT's crew (a record: no session)."
  (agent-workspace--make-agent :name name :role "builder" :colour "blue" :project project))

(defun +test-aww--exclude (project)
  "PROJECT's info/exclude."
  (let ((file (expand-file-name ".git/info/exclude" project)))
    (if (file-exists-p file)
        (with-temp-buffer (insert-file-contents file) (buffer-string))
      "")))

;; ====== MAKING ONE ======

(defun +test-aww--dir (name)
  "A new, empty folder NAME in the temp folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aww/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun +test-aww--porcelain (project)
  "git worktree list --porcelain in PROJECT."
  (let ((default-directory project)) (+test-aww--git "worktree" "list" "--porcelain")))

(defun +test-aww--change (dir file text &optional message)
  "FILE in DIR now holds TEXT; MESSAGE: committed with it."
  (let ((default-directory dir))
    (write-region text nil file)
    (when message
      (+test-aww--git "add" file)
      (+test-aww--commit message))))

(defun +test-aww--read (file)
  "FILE's text."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun +test-aww--head (dir)
  "The branch the worktree DIR is on."
  (let ((default-directory dir)) (+test-aww--git "branch" "--show-current")))

(defun +test-aww--rev (project ref)
  "REF's commit in PROJECT."
  (let ((default-directory project)) (+test-aww--git "rev-parse" ref)))

(defun +test-aww--branches (project)
  "PROJECT's branches, sorted."
  (let ((default-directory project))
    (sort (split-string (+test-aww--git "for-each-ref" "--format=%(refname:short)" "refs/heads/") "\n" t)
          #'string<)))

(defun +test-aww--turn (agent prompt)
  "AGENT's turn starts with PROMPT, as agent-shell says it (input-submitted)."
  (agent-workspace--event agent `((:event . input-submitted) (:data (:prompt . ,prompt)))))

(defmacro +test-aww--merging (&rest body)
  "BODY, git's merges made as a test user (no ~/.gitconfig here)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'process-file)
              (let ((process-file (symbol-function 'process-file)))
                (lambda (program &optional infile buffer display &rest args)
                  (apply process-file program infile buffer display
                         (if (equal (car args) "merge")
                             (append '("-c" "user.name=Test" "-c" "user.email=test@example.com") args)
                           args))))))
     ,@body))

(defmacro +test-aww--saying (said &rest body)
  "BODY, its messages pushed onto SAID, a variable."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'message)
              (lambda (format &rest args) (push (apply #'format format args) ,said))))
     ,@body))

(defmacro +test-aww--with-crew (project agents &rest body)
  "BODY with AGENTS (records) PROJECT's crew."
  (declare (indent 2))
  `(let ((agent-workspace--crews (make-hash-table :test #'equal)))
     (puthash ,project ,agents agent-workspace--crews)
     ,@body))

(ert-deftest agent-workspace-worktree/made-named-after-it ()
  "Its worktree: .agent-shell/worktrees/ROLE-NAME, on a new branch agent/NAME
from the project's HEAD; the project's checkout untouched."
  (let* ((project (+test-aww--project "made"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (should (equal dir (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
    (should (equal (agent-workspace-agent-worktree agent) dir))
    (should (equal (agent-workspace-agent-branch agent) "agent/ada"))
    (should (file-exists-p (expand-file-name "README" dir)))
    (let ((default-directory dir))
      (should (equal (+test-aww--git "branch" "--show-current") "agent/ada")))
    (let ((default-directory project))
      (should (equal (+test-aww--git "branch" "--show-current") "main"))
      ;; Nothing new in the project: .agent-shell/ kept out of git.
      (should (equal (+test-aww--git "status" "--porcelain") ""))
      (should (equal (+test-aww--git "rev-parse" "agent/ada") (+test-aww--git "rev-parse" "main"))))))

(ert-deftest agent-workspace-worktree/kept-out-of-git ()
  ".agent-shell/ goes in the repository's info/exclude once, when no
.gitignore keeps it out; with one that does, nothing is added."
  (let ((project (+test-aww--project "exclude")))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (agent-workspace-worktree-ensure (+test-aww--agent project "grace"))
    (should (= (cl-count "/.agent-shell/" (split-string (+test-aww--exclude project) "\n") :test #'equal) 1))
    ;; In the agent's worktree too (it shares info/exclude).
    (let ((default-directory (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
      (make-directory ".agent-shell/transcripts" t)
      (write-region "x" nil ".agent-shell/transcripts/a.md")
      (should (equal (+test-aww--git "status" "--porcelain") ""))))
  (let ((project (+test-aww--project "ignored" "/.agent-shell/\n")))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (should-not (string-search ".agent-shell" (+test-aww--exclude project)))))

(ert-deftest agent-workspace-worktree/reused ()
  "There already: reused as it is, its work kept."
  (let* ((project (+test-aww--project "reused"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (write-region "work in progress\n" nil (expand-file-name "wip" dir))
    (should (equal (agent-workspace-worktree-ensure (+test-aww--agent project "ada")) dir))
    (should (file-exists-p (expand-file-name "wip" dir)))))

(ert-deftest agent-workspace-worktree/its-branch-reused ()
  "Its folder gone (removed, or deleted by hand), its branch is checked out
again, with its commits."
  (let* ((project (+test-aww--project "branch"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (let ((default-directory dir))
      (write-region "done\n" nil "work")
      (+test-aww--git "add" "work")
      (+test-aww--commit "ada's work"))
    ;; Deleted by hand: still registered with git.
    (delete-directory dir t)
    (should (equal (agent-workspace-worktree-ensure (+test-aww--agent project "ada")) dir))
    (should (file-exists-p (expand-file-name "work" dir)))
    ;; Removed with git (locked: forced twice).
    (let ((default-directory project))
      (+test-aww--git "worktree" "remove" "-f" "-f" (directory-file-name dir)))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (should (file-exists-p (expand-file-name "work" dir)))))

(ert-deftest agent-workspace-worktree/git-s-refusal-said ()
  "git refusing: a user error with what it said."
  (let* ((project (+test-aww--project "refused"))
         (agent (+test-aww--agent project "ada")))
    ;; A file where its folder goes.
    (make-directory (expand-file-name ".agent-shell/worktrees/" project) t)
    (write-region "" nil (expand-file-name ".agent-shell/worktrees/builder-ada" project))
    (should-error (agent-workspace-worktree-ensure agent) :type 'user-error)))

(ert-deftest agent-workspace-worktree/renamed ()
  "Renamed: its worktree moved and its branch renamed, its work kept; its
role changed: moved, its branch as it was."
  (let* ((project (+test-aww--project "renamed"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (write-region "wip\n" nil (expand-file-name "wip" dir))
    (agent-workspace-worktree-move agent "grace" "builder")
    (let ((new (expand-file-name ".agent-shell/worktrees/builder-grace/" project)))
      (should (equal (agent-workspace-agent-worktree agent) new))
      (should (equal (agent-workspace-agent-branch agent) "agent/grace"))
      (should-not (file-exists-p dir))
      (should (file-exists-p (expand-file-name "wip" new)))
      (let ((default-directory new))
        (should (equal (+test-aww--git "branch" "--show-current") "agent/grace")))
      (let ((default-directory project))
        (should-not (string-search "agent/ada" (+test-aww--git "branch" "--list"))))
      ;; A reviewer now.
      (agent-workspace-worktree-move agent "grace" "reviewer")
      (let ((moved (expand-file-name ".agent-shell/worktrees/reviewer-grace/" project)))
        (should (equal (agent-workspace-agent-worktree agent) moved))
        (should (equal (agent-workspace-agent-role agent) "reviewer"))
        (should (equal (agent-workspace-agent-branch agent) "agent/grace"))
        (should-not (file-exists-p new))
        (should (file-exists-p (expand-file-name "wip" moved)))
        (should (string-search "locked agent grace (reviewer)" (+test-aww--porcelain project)))))))

(ert-deftest agent-workspace-worktree/named-otherwise-moved ()
  "A worktree on its branch named as before (worktrees/NAME), or for its
role before (crew.json edited): moved to ROLE-NAME as its agent starts, its
work kept, locked as it. Its branch checked out outside the agents' folder
\(yours): never moved, git's refusal said."
  (let* ((project (+test-aww--project "before"))
         (old (expand-file-name ".agent-shell/worktrees/ada/" project)))
    (let ((default-directory project))
      (make-directory (expand-file-name ".agent-shell/worktrees/" project) t)
      (+test-aww--git "worktree" "add" "-q" "-b" "agent/ada" (directory-file-name old) "HEAD")
      (+test-aww--git "worktree" "lock" "--reason" "agent ada (builder), crew of before" (directory-file-name old)))
    (write-region "wip\n" nil (expand-file-name "wip" old))
    (let* ((agent (+test-aww--agent project "ada"))
           (dir (agent-workspace-worktree-ensure agent)))
      (should (equal dir (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
      (should-not (file-exists-p old))
      (should (file-exists-p (expand-file-name "wip" dir)))
      (should (string-search "locked agent ada (builder)" (+test-aww--porcelain project)))
      ;; Its role changed in crew.json meanwhile.
      (setf (agent-workspace-agent-role agent) "reviewer")
      (let ((moved (agent-workspace-worktree-ensure agent)))
        (should (equal moved (expand-file-name ".agent-shell/worktrees/reviewer-ada/" project)))
        (should (file-exists-p (expand-file-name "wip" moved)))
        (should-not (file-exists-p dir))))
    ;; Its branch checked out outside the agents' folder.
    (let ((yours (expand-file-name "aww/yours/" +test-tmp)))
      (when (file-exists-p yours) (delete-directory yours t))
      (let ((default-directory project))
        (+test-aww--git "worktree" "add" "-q" "-b" "agent/ken" (directory-file-name yours) "HEAD"))
      (should-error (agent-workspace-worktree-ensure (+test-aww--agent project "ken")) :type 'user-error)
      (should (file-exists-p (expand-file-name "README" yours))))))

;; ====== A BRANCH FOR EACH PIECE OF WORK ======

(ert-deftest agent-workspace-worktree/a-slug ()
  "A branch's words from a title or a prompt: lowercased, its area dropped,
apostrophes and accents too, the rest one - a run, at most 48 characters,
cut at a -."
  (dolist (case '(("Agent workspace: an agent's other canvases on the stage" . "an-agents-other-canvases-on-the-stage")
                  ("Fix the parser" . "fix-the-parser")
                  ("  Lexer: strings with \"escapes\"!  " . "strings-with-escapes")
                  ("Café, naïve résumé" . "cafe-naive-resume")
                  ("What’s left on the lexer?" . "whats-left-on-the-lexer")
                  ("Docs:" . "docs")
                  ("Look at this: http://x.org/a_b" . "http-x-org-a-b")
                  ("An agent works on a properly named branch per issue, not one for life"
                   . "an-agent-works-on-a-properly-named-branch-per")
                  ("Supercalifragilisticexpialidocious-and-then-some-more-words-to-cut"
                   . "supercalifragilisticexpialidocious-and-then-some")
                  ("Pneumonoultramicroscopicsilicovolcanoconiosisxxxxxxxxxx"
                   . "pneumonoultramicroscopicsilicovolcanoconiosisxxx")
                  ("???" . "")))
    (should (equal (agent-workspace-slug (car case)) (cdr case))))
  (should (<= (length (agent-workspace-slug (make-string 80 ?a))) 48)))

(ert-deftest agent-workspace-worktree/an-issue-s-branch-name ()
  "An issue's branch, as it's made: its type, then its id: fix/ for a bug,
feat/ for a feature, its own type else, task/ when it isn't known."
  (should (equal (agent-workspace-issue-branch "doom-pbk.18" "bug") "fix/doom-pbk.18"))
  (should (equal (agent-workspace-issue-branch "doom-pbk.21" "feature") "feat/doom-pbk.21"))
  (should (equal (agent-workspace-issue-branch "demo-1" "chore") "chore/demo-1"))
  (should (equal (agent-workspace-issue-branch "demo-1" "task") "task/demo-1"))
  (should (equal (agent-workspace-issue-branch "demo-1") "task/demo-1"))
  ;; Its title's first 4 words, small ones and an "Area: " prefix dropped.
  (should (equal (agent-workspace-issue-branch
                  "doom-pbk.18" "bug"
                  "Agent workspace: the minimap's dividers don't line up, and a long lane ends in $")
                 "fix/doom-pbk.18-minimaps-dividers-dont-line"))
  (should (equal (agent-workspace-issue-branch "demo-1" "feature" "Lexer: strings with escapes")
                 "feat/demo-1-strings-escapes"))
  (should (equal (agent-workspace-issue-branch "demo-1" "task" "The one") "task/demo-1"))
  (should (equal (agent-workspace-branch-words "a an the") "")))

(ert-deftest agent-workspace-worktree/a-branch-per-issue ()
  "Given an issue, its worktree goes on a branch of its own, TYPE/ID, from
the main checkout's branch as it is then (not where its worktree was),
noted as its; its slot follows, said. Renamed by its agent (TYPE/ID-WORDS),
the note goes with it. Another issue: the next one, the first kept with its
work. Given back (its type changed since too): its branch as its agent
renamed it, checked out again, its work there; a branch left holding
nothing, deleted."
  (let* ((project (+test-aww--project "per-issue"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (changes nil)
         (agent-workspace-change-functions (list (lambda (_agent what) (push what changes)))))
    ;; Your branch moved on since its worktree was made.
    (+test-aww--change project "yours" "mine\n" "my work")
    (agent-workspace-give agent "demo-1" "Lexer: strings with escapes" "bug")
    (should (equal (+test-aww--head dir) "fix/demo-1-strings-escapes"))
    (should (equal (agent-workspace-agent-branch agent) "fix/demo-1-strings-escapes"))
    (should (equal (agent-workspace-agent-issue agent) "demo-1"))
    (should (equal (reverse changes) '(branch issue)))
    (should (equal (+test-aww--rev project "fix/demo-1-strings-escapes") (+test-aww--rev project "main")))
    (should (file-exists-p (expand-file-name "yours" dir)))
    ;; Its agent names it, once, then commits.
    (let ((default-directory dir))
      (+test-aww--git "branch" "-m" "fix/demo-1-lexer-escapes"))
    (+test-aww--change dir "lexer" "strings\n" "ada's lexer")
    (let ((default-directory project))
      (should (equal (+test-aww--git "config" "branch.fix/demo-1-lexer-escapes.agent-workspace-agent") "ada")))
    ;; Another: from the main branch; the first kept, its work on it.
    (agent-workspace-give agent "demo-2" "Parser" "feature")
    (should (equal (+test-aww--head dir) "feat/demo-2-parser"))
    (should-not (file-exists-p (expand-file-name "lexer" dir)))
    ;; Given back, a task now: its branch as ada named it, its work there;
    ;; the one it left held nothing: gone.
    (agent-workspace-give agent "demo-1" "Lexer: strings with escapes" "task")
    (should (equal (+test-aww--head dir) "fix/demo-1-lexer-escapes"))
    (should (equal (agent-workspace-agent-branch agent) "fix/demo-1-lexer-escapes"))
    (should (file-exists-p (expand-file-name "lexer" dir)))
    (should (equal (+test-aww--branches project) '("agent/ada" "fix/demo-1-lexer-escapes" "main")))
    (should (equal (agent-workspace-agent-branches agent) '("fix/demo-1-lexer-escapes" "agent/ada")))
    ;; No issue: its branch as it is.
    (agent-workspace-give agent nil)
    (should (equal (+test-aww--head dir) "fix/demo-1-lexer-escapes"))))

(ert-deftest agent-workspace-worktree/an-issue-refused-over-changes ()
  "Its worktree with changes not committed: an issue refused, saying which
branch has them; nothing given, its branch and changes as they were. The
one it's on given again: fine. Committed, the next is given."
  (let* ((project (+test-aww--project "changes"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (agent-workspace-give agent "demo-1" "One")
    (+test-aww--change dir "wip" "half\n")
    (should (equal (cadr (should-error (agent-workspace-give agent "demo-2" "Two") :type 'user-error))
                   "ada has changes not committed, on task/demo-1"))
    (should (equal (agent-workspace-agent-issue agent) "demo-1"))
    (should (equal (+test-aww--head dir) "task/demo-1"))
    (should (file-exists-p (expand-file-name "wip" dir)))
    (agent-workspace-give agent "demo-1" "One")
    (let ((default-directory dir))
      (+test-aww--git "add" "wip")
      (+test-aww--commit "wip"))
    (agent-workspace-give agent "demo-2" "Two")
    (should (equal (+test-aww--head dir) "task/demo-2-two"))))

(ert-deftest agent-workspace-worktree/an-issue-given-while-it-works ()
  "Given an issue while it works, its worktree stays as it is until its next
turn starts (the issue's prompt, queued): then it's on the issue's branch.
Changes not committed by then: it stays, said."
  (let* ((project (+test-aww--project "while-working"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (said nil))
    (agent-workspace-give agent "demo-1" "One")
    (setf (agent-workspace-agent-state agent) 'working)
    (+test-aww--change dir "wip" "half\n")
    (agent-workspace-give agent "demo-2" "Two")
    (should (equal (agent-workspace-agent-issue agent) "demo-2"))
    (should (equal (+test-aww--head dir) "task/demo-1"))
    ;; It commits; its turn ends; the issue's prompt starts the next.
    (let ((default-directory dir))
      (+test-aww--git "add" "wip")
      (+test-aww--commit "wip"))
    (setf (agent-workspace-agent-state agent) 'done)
    (+test-aww--turn agent "Work on demo-2: Two")
    (should (equal (+test-aww--head dir) "task/demo-2-two"))
    (should (equal (agent-workspace-agent-branch agent) "task/demo-2-two"))
    (should (eq (agent-workspace-agent-state agent) 'working))
    ;; Again, its changes not committed this time: it stays, said.
    (agent-workspace-give agent "demo-3" "Three")
    (+test-aww--change dir "more" "half\n")
    (+test-aww--saying said
      (+test-aww--turn agent "Work on demo-3: Three"))
    (should (equal (+test-aww--head dir) "task/demo-2-two"))
    (should (member "ada stays on task/demo-2-two for demo-3: ada has changes not committed, on task/demo-2-two" said))
    ;; Its next turn: nothing more.
    (+test-aww--turn agent "go on")
    (should (equal (+test-aww--head dir) "task/demo-2-two"))
    ;; Given one while it works, then given back (killed) before its next
    ;; turn: no longer its, no branch for it.
    (let ((default-directory dir))
      (+test-aww--git "add" "more")
      (+test-aww--commit "more"))
    (agent-workspace-give agent "demo-4" "Four")
    (agent-workspace--note-issue agent nil)
    (+test-aww--turn agent "something else")
    (should (equal (+test-aww--head dir) "task/demo-2-two"))))

(ert-deftest agent-workspace-worktree/a-prompt-at-rest ()
  "A turn starting at rest (on agent/NAME, holding nothing the main branch
hasn't): a branch named from its prompt's first words, where it is (the
same commit, its changes kept), noted as its; its next turn stays there. A /
command, or a text it's only told, makes none; a name taken, -2. Work from
before on agent/NAME (a crew of before): it goes on there."
  (let* ((project (+test-aww--project "prompt"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (base (+test-aww--rev project "agent/ada")))
    (+test-aww--change project "yours" "mine\n" "my work")
    (+test-aww--change dir "wip" "half\n")
    (+test-aww--turn agent "/compact")
    (agent-workspace-branch-quiet agent "The user merged your branch x")
    (+test-aww--turn agent "The user merged your branch x into main.")
    (should (equal (+test-aww--head dir) "agent/ada"))
    (+test-aww--turn agent "Why does the REPL hang on paste? It's slow too.")
    (should (equal (+test-aww--head dir) "why-does-the-repl-hang-on-paste-its-slow-too"))
    (should (equal (agent-workspace-agent-branch agent) "why-does-the-repl-hang-on-paste-its-slow-too"))
    (should (equal (+test-aww--rev project "why-does-the-repl-hang-on-paste-its-slow-too") base))
    (should (file-exists-p (expand-file-name "wip" dir)))
    (let ((default-directory project))
      (should (equal (+test-aww--git "config" "branch.why-does-the-repl-hang-on-paste-its-slow-too.agent-workspace-agent")
                     "ada")))
    (+test-aww--turn agent "And the tests?")
    (should (equal (+test-aww--head dir) "why-does-the-repl-hang-on-paste-its-slow-too"))
    ;; The same words to another: -2.
    (let* ((ken (+test-aww--agent project "ken"))
           (his (agent-workspace-worktree-ensure ken)))
      (+test-aww--turn ken "Why does the REPL hang on paste? It's slow too.")
      (should (equal (+test-aww--head his) "why-does-the-repl-hang-on-paste-its-slow-too-2")))
    (let* ((linus (+test-aww--agent project "linus"))
           (his (agent-workspace-worktree-ensure linus)))
      (+test-aww--change his "old" "work\n" "linus's work from before")
      (+test-aww--turn linus "Finish it")
      (should (equal (+test-aww--head his) "agent/linus")))))

(ert-deftest agent-workspace-worktree/an-issue-s-branch-taken-from-another ()
  "An issue's branch checked out in another agent's worktree (handed on):
taken from it while that agent rests (it goes back on agent/NAME), the work
on it there for the next; refused while it works, or has changes there;
checked out somewhere else, refused saying where."
  (let* ((project (+test-aww--project "taken"))
         (ken (+test-aww--agent project "ken"))
         (sam (+test-aww--agent project "sam"))
         (his (agent-workspace-worktree-ensure ken))
         (hers (agent-workspace-worktree-ensure sam)))
    (+test-aww--with-crew project (list ken sam)
      (agent-workspace-give ken "demo-1" "One")
      (+test-aww--change his "lexer" "done\n" "ken's lexer")
      (setf (agent-workspace-agent-state ken) 'working)
      ;; (A user error's quotes as Emacs shows them: format-message's.)
      (should (equal (cadr (should-error (agent-workspace-give sam "demo-1" "One") :type 'user-error))
                     (format-message "task/demo-1 is ken's: it's working on it")))
      (setf (agent-workspace-agent-state ken) 'done)
      (+test-aww--change his "wip" "half\n")
      (should (equal (cadr (should-error (agent-workspace-give sam "demo-1" "One") :type 'user-error))
                     (format-message "task/demo-1 is ken's: ken has changes not committed, on task/demo-1")))
      (delete-file (expand-file-name "wip" his))
      (agent-workspace-give sam "demo-1" "One")
      (should (equal (+test-aww--head hers) "task/demo-1"))
      (should (file-exists-p (expand-file-name "lexer" hers)))
      (should (equal (+test-aww--head his) "agent/ken"))
      (should (equal (agent-workspace-agent-branch ken) "agent/ken"))
      (should (equal (+test-aww--rev project "agent/ken") (+test-aww--rev project "main")))
      ;; Yours, elsewhere: refused.
      (let ((yours (expand-file-name "aww/taken-yours/" +test-tmp)))
        (when (file-exists-p yours) (delete-directory yours t))
        (let ((default-directory project))
          (+test-aww--git "worktree" "add" "-q" "-b" "task/demo-2" (directory-file-name yours) "HEAD"))
        (should (string-prefix-p "task/demo-2 is checked out in "
                                 (cadr (should-error (agent-workspace-give ken "demo-2" "Two")
                                                     :type 'user-error))))
        (should (equal (+test-aww--head his) "agent/ken"))))))

(ert-deftest agent-workspace-worktree/started-again-on-its-branch ()
  "Started again (restarted, its crew opened again), its worktree stays on
the branch it was on, its slot says it; moved from elsewhere (its role
changed in crew.json), found by its lock's reason, on its branch still."
  (let* ((project (+test-aww--project "again"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (agent-workspace-give agent "demo-1" "One")
    (let ((again (+test-aww--agent project "ada")))
      (should (equal (agent-workspace-worktree-ensure again) dir))
      (should (equal (agent-workspace-agent-branch again) "task/demo-1"))
      (setf (agent-workspace-agent-role again) "reviewer")
      (let ((moved (agent-workspace-worktree-ensure again)))
        (should (equal moved (expand-file-name ".agent-shell/worktrees/reviewer-ada/" project)))
        (should (equal (+test-aww--head moved) "task/demo-1"))
        (should (equal (agent-workspace-agent-branch again) "task/demo-1"))
        (should-not (file-exists-p dir))))))

(ert-deftest agent-workspace-worktree/renamed-on-an-issue-s-branch ()
  "Renamed while on an issue's branch: that branch kept, its name too, now
the new name's; agent/NAME, where it rests, renamed."
  (let* ((project (+test-aww--project "renamed-issue"))
         (agent (+test-aww--agent project "ada")))
    (agent-workspace-worktree-ensure agent)
    (agent-workspace-give agent "demo-1" "One")
    (agent-workspace-worktree-move agent "grace" "builder")
    (should (equal (+test-aww--head (expand-file-name ".agent-shell/worktrees/builder-grace/" project))
                   "task/demo-1"))
    (should (equal (agent-workspace-agent-branch agent) "task/demo-1"))
    (should (equal (+test-aww--branches project) '("agent/grace" "main" "task/demo-1")))
    (let ((default-directory project))
      (should (equal (+test-aww--git "config" "branch.task/demo-1.agent-workspace-agent") "grace")))
    (should (equal (agent-workspace-agent-branches agent) '("task/demo-1" "agent/grace")))))

;; ====== A CREW'S PROJECT ======

(ert-deftest agent-workspace-worktree/the-project ()
  "A crew's project: the repository's main checkout, from inside it, a
folder of it, or an agent's worktree; none outside git."
  (let* ((project (+test-aww--project "project"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (make-directory (expand-file-name "src" project) t)
    (should (equal (agent-workspace-project project) project))
    (should (equal (agent-workspace-project (expand-file-name "src" project)) project))
    (should (equal (agent-workspace-project dir) project))
    (let ((default-directory dir))
      (should (equal (agent-workspace-project) project)))
    (let ((outside (expand-file-name "aww/outside/" +test-tmp)))
      (make-directory outside t)
      (should-not (agent-workspace-project outside)))
    (should-not (agent-workspace-project (expand-file-name "aww/nowhere/" +test-tmp)))))


;; ====== LOCKED, ITS NAME ON IT ======

(ert-deftest agent-workspace-worktree/locked-with-its-name ()
  "Its worktree is locked as it's made, its reason naming it; git's own name
for it is its folder's; prune leaves it; one found unlocked is locked;
renamed, its reason too."
  (let* ((project (+test-aww--project "locked"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (should (string-search (concat "worktree " (directory-file-name dir)) (+test-aww--porcelain project)))
    (should (string-search "locked agent ada (builder), crew of locked" (+test-aww--porcelain project)))
    (should (file-directory-p (expand-file-name ".git/worktrees/builder-ada" project)))
    (let ((default-directory project))
      (+test-aww--git "worktree" "prune")
      (should (file-directory-p dir))
      (+test-aww--git "worktree" "unlock" (directory-file-name dir)))
    (should-not (string-search "\nlocked" (+test-aww--porcelain project)))
    (agent-workspace-worktree-ensure agent)
    (should (string-search "locked agent ada (builder)" (+test-aww--porcelain project)))
    (agent-workspace-worktree-move agent "grace" "builder")
    (should (string-search "locked agent grace (builder), crew of locked" (+test-aww--porcelain project)))
    (should-not (string-search "agent ada" (+test-aww--porcelain project)))))

(ert-deftest agent-workspace-worktree/no-crew-without-a-commit ()
  "A folder outside git, or a repository with no commit: no crew, saying
why; nothing made."
  (should (string-prefix-p "not a git repository"
                           (agent-workspace-no-crew-reason (+test-aww--dir "outside-git"))))
  (let ((empty (+test-aww--dir "no-commit")))
    (let ((default-directory empty)) (+test-aww--git "init" "-q" "-b" "main"))
    (should (string-prefix-p "no commit yet" (agent-workspace-no-crew-reason empty)))
    (should-error (agent-workspace-worktree-ensure (+test-aww--agent empty "ada")) :type 'user-error)
    (should-not (file-exists-p (expand-file-name ".agent-shell/worktrees/builder-ada" empty))))
  (should-not (agent-workspace-no-crew-reason (+test-aww--project "fine"))))

(ert-deftest agent-workspace-worktree/two-agents-at-once ()
  "Two agents change the same file at once, each in its worktree, and
commit: neither sees the other's change, and your checkout is untouched."
  (let* ((project (+test-aww--project "together"))
         (head (let ((default-directory project)) (+test-aww--git "rev-parse" "HEAD")))
         (ada (agent-workspace-worktree-ensure (+test-aww--agent project "ada")))
         (grace (agent-workspace-worktree-ensure (+test-aww--agent project "grace"))))
    (+test-aww--change ada "README" "ada's\n" "ada's change")
    (+test-aww--change grace "README" "grace's\n" "grace's change")
    (should (equal (+test-aww--read (expand-file-name "README" ada)) "ada's\n"))
    (should (equal (+test-aww--read (expand-file-name "README" grace)) "grace's\n"))
    (let ((default-directory project))
      (should (equal (+test-aww--git "rev-parse" "HEAD") head))
      (should (equal (+test-aww--git "status" "--porcelain") ""))
      (should (equal (+test-aww--read "README") "hello\n")))))

;; ====== FORGETTING IT ======

(ert-deftest agent-workspace-worktree/forgotten-with-nothing-left ()
  "Holding nothing the main checkout hasn't: removed, its branch deleted,
without asking."
  (let* ((project (+test-aww--project "forget-clean"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (+test-aww--with-crew project (list agent)
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) (error "Asked"))))
        (agent-workspace-forget agent))
      (should-not (agent-workspace-agents project))
      (should-not (file-exists-p dir))
      (should-not (string-search "ada" (+test-aww--porcelain project)))
      (let ((default-directory project))
        (should (equal (+test-aww--git "branch" "--list" "agent/ada") ""))))))

(ert-deftest agent-workspace-worktree/forgotten-with-work-asks ()
  "Holding work (not committed, or commits not on the main branch): you're
shown it and asked; kept, it's all there; removed, it's gone."
  (let* ((project (+test-aww--project "forget-work"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (shown nil))
    (+test-aww--change dir "new" "work\n")
    (+test-aww--change dir "done" "work\n" "ada's work")
    (should (equal (agent-workspace-worktree-work agent)
                   (list :changes '("?? new")
                         :commits (list (list "agent/ada"
                                              (let ((default-directory project))
                                                (+test-aww--git "log" "--oneline" "-1" "agent/ada")))))))
    (should (= (agent-workspace-branch-ahead agent) 1))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (&rest _)
                 (setq shown (with-current-buffer "*ada's work*" (buffer-string)))
                 '(?k "keep it"))))
      (+test-aww--with-crew project (list agent)
        (agent-workspace-forget agent)
        (should-not (agent-workspace-agents project))))
    (should (string-search "Not committed:\n  ?? new" shown))
    (should (string-search "Not on main:\n  agent/ada\n    " shown))
    (should (string-search "ada's work" shown))
    (should-not (get-buffer "*ada's work*"))
    (should (file-exists-p (expand-file-name "new" dir)))
    ;; Forgotten again (another agent named so), removed this time.
    (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) '(?r "remove it anyway"))))
      (+test-aww--with-crew project (list agent)
        (agent-workspace-forget agent)))
    (should-not (file-exists-p dir))
    (let ((default-directory project))
      (should (equal (+test-aww--git "branch" "--list" "agent/ada") "")))))

;; ====== FORGETTING IT, ITS BRANCHES ======

(ert-deftest agent-workspace-worktree/forgotten-with-work-on-its-branches ()
  "Its work on the branch of an issue before (not the one it's on): shown,
its branch with its commits; removed, every branch of its deleted, others
left."
  (let* ((project (+test-aww--project "forget-branches"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (shown nil))
    (agent-workspace-give agent "demo-1" "One")
    (+test-aww--change dir "one" "done\n" "ada's one")
    (agent-workspace-give agent "demo-2" "Two")
    (let ((default-directory project)) (+test-aww--git "branch" "yours"))
    (should (equal (mapcar #'car (plist-get (agent-workspace-worktree-work agent) :commits)) '("task/demo-1")))
    (should (= (agent-workspace-branch-ahead agent) 0))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (&rest _)
                 (setq shown (with-current-buffer "*ada's work*" (buffer-string)))
                 '(?r "remove it anyway"))))
      (+test-aww--with-crew project (list agent)
        (agent-workspace-forget agent)))
    (should (string-search ", on task/demo-2-two, holds work" shown))
    (should (string-search "Not on main:\n  task/demo-1\n    " shown))
    (should (string-search "ada's one" shown))
    (should-not (file-exists-p dir))
    (should (equal (+test-aww--branches project) '("main" "yours")))))

;; ====== REVIEW AND MERGE ======

(ert-deftest agent-workspace-worktree/review ()
  "Its branch's changes since it left the main branch, in magit: the one
it's on, or another of its."
  (require 'magit)
  (let* ((project (+test-aww--project "review"))
         (agent (+test-aww--agent project "ada"))
         (called nil))
    (agent-workspace-worktree-ensure agent)
    (cl-letf (((symbol-function 'magit-diff-range)
               (lambda (range &rest _) (push (list range default-directory) called))))
      (agent-workspace-review agent)
      (agent-workspace-give agent "demo-1" "One")
      (agent-workspace-review agent)
      (agent-workspace-review agent "agent/ada"))
    (should (equal (reverse called) (list (list "main...agent/ada" project) (list "main...task/demo-1" project)
                                          (list "main...agent/ada" project))))))

(ert-deftest agent-workspace-worktree/which-branch ()
  "d and M: the branch it's on, asking nothing; others of its holding work:
you're asked, the one it's on first."
  (let* ((project (+test-aww--project "which"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (asked nil))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt choices &rest args) (setq asked (list prompt choices (nth 4 args))) (car choices))))
      (should (equal (agent-workspace-read-branch agent "Merge %s's branch: ") "agent/ada"))
      (should-not asked)
      (agent-workspace-give agent "demo-1" "One")
      (+test-aww--change dir "one" "done\n" "one")
      (agent-workspace-give agent "demo-2" "Two")
      (should (equal (agent-workspace-read-branch agent "Merge %s's branch: ") "task/demo-2-two"))
      (should (equal asked '("Merge ada's branch: " ("task/demo-2-two" "task/demo-1") "task/demo-2-two"))))))

(ert-deftest agent-workspace-worktree/merge ()
  "Merged into the main checkout: a merge commit naming its branch, the
agent told; the branch deleted, the agent at rest, on agent/NAME at the
merged tip, ready for the next; nothing ahead after."
  (let* ((project (+test-aww--project "merge"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (told nil))
    (agent-workspace-give agent "demo-1" "Lexer: strings with escapes" "bug")
    ;; Named by its agent (the bar follows as M merges it).
    (let ((default-directory dir))
      (+test-aww--git "branch" "-m" "fix/demo-1-lexer-escapes"))
    (+test-aww--change dir "feature" "done\n" "ada's feature")
    (+test-aww--change project "other" "mine\n" "my own work")
    (cl-letf (((symbol-function 'agent-workspace-live-p) (lambda (_) t))
              ((symbol-function 'agent-workspace-send)
               (lambda (_agent text &rest args) (push (cons text args) told))))
      (+test-aww--merging
        (should (agent-workspace-merge agent))))
    (should (equal (+test-aww--read (expand-file-name "feature" project)) "done\n"))
    (let ((default-directory project))
      (should (equal (+test-aww--git "log" "-1" "--format=%s" "main") "Merge branch 'fix/demo-1-lexer-escapes'")))
    (should (equal told '(("The user merged your branch fix/demo-1-lexer-escapes into main and deleted it: \
your worktree is back on agent/ada, at main's tip. Your next work gets a branch of its own."
                           :submit t :no-branch t))))
    (should (equal (+test-aww--branches project) '("agent/ada" "main")))
    (should (equal (+test-aww--head dir) "agent/ada"))
    (should (equal (agent-workspace-agent-branch agent) "agent/ada"))
    (should (equal (+test-aww--rev project "agent/ada") (+test-aww--rev project "main")))
    (should (file-exists-p (expand-file-name "other" dir)))
    (should (= (agent-workspace-branch-ahead agent) 0))))

(ert-deftest agent-workspace-worktree/merge-left-for-later ()
  "Merged while it works, or with changes not committed: its branch kept,
said, the agent where it is; M again once it's done: deleted, at rest. A
branch of its it isn't on (an issue before this one): deleted at once, its
worktree as it is."
  (let* ((project (+test-aww--project "merge-later"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (said nil))
    (agent-workspace-give agent "demo-1" "One")
    (+test-aww--change dir "one" "done\n" "one")
    (setf (agent-workspace-agent-state agent) 'working)
    (+test-aww--saying said
      (+test-aww--merging (should (agent-workspace-merge agent))))
    (should (equal (car said) "Merged task/demo-1 into main; task/demo-1 kept for now (M again later): ada is working"))
    (should (equal (+test-aww--head dir) "task/demo-1"))
    (setf (agent-workspace-agent-state agent) 'done)
    (+test-aww--change dir "wip" "half\n")
    (+test-aww--merging (should (agent-workspace-merge agent)))
    (should (equal (+test-aww--head dir) "task/demo-1"))
    (delete-file (expand-file-name "wip" dir))
    (+test-aww--merging (should (agent-workspace-merge agent)))
    (should (equal (+test-aww--head dir) "agent/ada"))
    (should (equal (+test-aww--branches project) '("agent/ada" "main")))
    ;; A branch of its it isn't on.
    (agent-workspace-give agent "demo-2" "Two")
    (+test-aww--change dir "two" "done\n" "two")
    (agent-workspace-give agent "demo-3" "Three")
    (+test-aww--saying said
      (+test-aww--merging (should (agent-workspace-merge agent "task/demo-2-two"))))
    (should (equal (car said) "Merged task/demo-2-two into main: task/demo-2-two deleted"))
    (should (equal (+test-aww--head dir) "task/demo-3-three"))
    (should (equal (+test-aww--branches project) '("agent/ada" "main" "task/demo-3-three")))
    (should (file-exists-p (expand-file-name "two" project)))))

(ert-deftest agent-workspace-worktree/merge-never-fast-forwards ()
  "Merged when a fast-forward could do (the main branch hasn't moved since
it left): a merge commit all the same, two parents, naming its branch; its
branch reset to it, nothing ahead after."
  (let* ((project (+test-aww--project "merge-no-ff"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (before nil)
         (ada nil))
    (+test-aww--change dir "feature" "done\n" "ada's feature")
    (let ((default-directory project))
      (setq before (+test-aww--git "rev-parse" "main")
            ada (+test-aww--git "rev-parse" "agent/ada")))
    (cl-letf (((symbol-function 'agent-workspace-live-p) (lambda (_) nil)))
      (let ((default-directory project))
        (cl-letf (((symbol-function 'process-file)
                   (let ((process-file (symbol-function 'process-file)))
                     (lambda (program &optional infile buffer display &rest args)
                       (apply process-file program infile buffer display
                              (if (equal (car args) "merge")
                                  (append '("-c" "user.name=Test" "-c" "user.email=test@example.com")
                                          args)
                                args))))))
          (should (agent-workspace-merge agent)))))
    (should (equal (+test-aww--read (expand-file-name "feature" project)) "done\n"))
    (let ((default-directory project))
      (should (equal (split-string (+test-aww--git "rev-list" "--parents" "-n" "1" "main"))
                     (list (+test-aww--git "rev-parse" "main") before ada)))
      (should (equal (+test-aww--git "log" "-1" "--format=%s" "main") "Merge branch 'agent/ada'"))
      (should (equal (+test-aww--git "rev-parse" "agent/ada") (+test-aww--git "rev-parse" "main"))))
    (should (= (agent-workspace-branch-ahead agent) 0))))

(ert-deftest agent-workspace-worktree/merge-stopped-on-conflicts ()
  "A merge that conflicts is left to you, said; nothing reset or told."
  (let* ((project (+test-aww--project "conflict"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (told nil))
    (+test-aww--change dir "README" "ada's\n" "ada's change")
    (+test-aww--change project "README" "mine\n" "my change")
    (cl-letf (((symbol-function 'agent-workspace-send) (lambda (&rest args) (push args told))))
      (should-not (agent-workspace-merge agent)))
    (should-not told)
    (let ((default-directory project))
      (should (string-search "UU README" (+test-aww--git "status" "--porcelain")))
      (+test-aww--git "merge" "--abort"))
    (should (= (agent-workspace-branch-ahead agent) 1))))

;; ====== IN EMACS ======

(ert-deftest agent-workspace-worktree/a-file-s-agent ()
  "A file of an agent's worktree (ROLE-NAME): its project and agent, found
through the crew (the outermost worktree); a folder nobody's and unreadable,
its own name; none for the main checkout's files."
  (+test-aww--with-crew "/p/doom/" (list (agent-workspace--make-agent :name "ada" :role "builder"
                                                                      :project "/p/doom/"))
    (should (equal (agent-workspace-worktree-of "/p/doom/.agent-shell/worktrees/builder-ada/src/a.el")
                   '("/p/doom/" "ada")))
    (should (equal (agent-workspace-worktree-of "/p/doom/.agent-shell/worktrees/builder-ada")
                   '("/p/doom/" "ada")))
    (should (equal (agent-workspace-worktree-of
                    "/p/doom/.agent-shell/worktrees/builder-ada/.agent-shell/worktrees/x/a.el")
                   '("/p/doom/" "ada")))
    (should (equal (agent-workspace-worktree-of "/p/doom/.agent-shell/worktrees/scribe-bob/a.el")
                   '("/p/doom/" "scribe-bob")))
    (should-not (agent-workspace-worktree-of "/p/doom/src/a.el"))
    (should (equal (agent-workspace-project-name "/p/doom/.agent-shell/worktrees/builder-ada/") "doom · ada"))
    (should-not (agent-workspace-project-name "/p/doom/"))))

(ert-deftest agent-workspace-worktree/its-project-s-name ()
  "projectile's and project.el's name for its worktree: \"PROJECT · NAME\"."
  (require 'projectile)
  (require 'project)
  (let* ((project (+test-aww--project "named"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (should (equal (projectile-default-project-name dir) "named · ada"))
    (should (equal (projectile-default-project-name project) "named"))
    (should (equal (project-name (project-current nil dir)) "named · ada"))
    (should (equal (project-name (project-current nil project)) "named"))))

(ert-deftest agent-workspace-worktree/its-mode-line-and-tabs ()
  "Its files' mode line shows the agent (avatar, name, role), a click
selecting it; their tab starts with its avatar. A forgotten agent's
worktree: its name dimmed."
  (let* ((project (+test-aww--project "mode-line"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (selected nil)
         (agent-workspace-select-function (lambda (a) (setq selected a))))
    (+test-with-reset
      (find-file (expand-file-name "README" dir))
      (+test-aww--with-crew project (list agent)
        (let ((text (agent-workspace-mode-line)))
          (should (equal (substring-no-properties text) " ▌A ada · builder "))
          (should (member '(:eval (agent-workspace-mode-line)) mode-line-misc-info))
          (should (eq (lookup-key (get-text-property 1 'local-map text) [mode-line mouse-1])
                      #'agent-workspace-mode-line-select))
          (should (equal (plist-get (get-text-property 1 'face text) :foreground)
                         (face-foreground 'ansi-color-blue nil t)))
          ;; Its role readable, the same for every agent.
          (should (eq (get-text-property (string-search "builder" text) 'face text) 'agent-workspace-label)))
        (agent-workspace-mode-line-select (list 'mouse-1 (list (selected-window) 1 '(0 . 0) 0)))
        (should (eq selected agent))
        (should (equal (substring-no-properties (agent-workspace-tab-prefix (current-buffer))) "▌A ")))
      ;; No longer in the crew.
      (let ((agent-workspace--crews (make-hash-table :test #'equal)))
        (let ((text (agent-workspace-mode-line)))
          (should (equal (substring-no-properties text) " ▌A ada "))
          (should (eq (get-text-property 1 'face text) 'shadow)))
        (should (eq (get-text-property 0 'face (agent-workspace-tab-prefix (current-buffer))) 'shadow)))
      (find-file (expand-file-name "README" project))
      (should-not (agent-workspace-mode-line))
      (should-not (agent-workspace-tab-prefix (current-buffer))))))

(ert-deftest agent-workspace-worktree/a-forgotten-agent-s-name-on-an-issue-s-branch ()
  "A worktree a forgotten agent left on an issue's branch: its name from its
lock's reason; unlocked, from agent/NAME if it rests there, else its
folder's."
  (let* ((project (+test-aww--project "forgotten-name"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (file (expand-file-name "README" dir)))
    (agent-workspace-give agent "demo-1" "One")
    (let ((agent-workspace--crews (make-hash-table :test #'equal)))
      (should (equal (agent-workspace-worktree-of file) (list project "ada")))
      (let ((default-directory project))
        (+test-aww--git "worktree" "unlock" (directory-file-name dir)))
      (should (equal (agent-workspace-worktree-of file) (list project "builder-ada")))
      (let ((default-directory dir))
        (+test-aww--git "switch" "-q" "agent/ada"))
      (should (equal (agent-workspace-worktree-of file) (list project "ada"))))))
