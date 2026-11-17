;;; tests/unit/test-agent-workspace-roles.el -*- lexical-binding: t; -*-
;; config/agent-workspace/roles.el: role files read and checked (their
;; problems naming the file and line), the starters, a project's own roles,
;; your local ones (found from an agent's worktree too), how many of a role
;; may run, a role copied into a project or your local ones. That a role's
;; tools and mode reach its agent: test-agent-workspace-session.el.

(+test-load "config/agent-workspace")

;; ====== HELPERS ======

(defun +test-awr--dir (name)
  "A new, empty folder NAME in the temp folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awr/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun +test-awr--file (dir name text)
  "A file NAME in DIR holding TEXT: its name."
  (let ((file (expand-file-name name dir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))
    file))

(defun +test-awr--read (text &optional name)
  "TEXT read as the role file NAME (default tester.md): (ROLE . PROBLEMS)."
  (agent-workspace-role-read (+test-awr--file (+test-awr--dir "read") (or name "tester.md") text)))

(defun +test-awr--messages (problems)
  "PROBLEMS' messages, without their file's folder: (LEVEL \"FILE:LINE: ...\")."
  (mapcar (lambda (problem)
            (list (car problem) (replace-regexp-in-string "\\`.*/" "" (cadr problem))))
          problems))

(defmacro +test-awr--quietly (&rest body)
  "BODY, its warnings recorded in `warnings' rather than shown."
  (declare (indent 0))
  `(let ((warnings nil))
     (cl-letf (((symbol-function 'display-warning)
                (lambda (_type message &optional level &rest _) (push (list level message) warnings))))
       ,@body)))

;; ====== A ROLE FILE ======

(ert-deftest agent-workspace-roles/a-role-file ()
  "Every key read: lists inline, in brackets or as YAML items; quotes taken
off; a kebab-case mode as Claude Code's id; the icon and its glyph; the
body its instructions."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---
name: tester
description: \"writes and runs tests\"
tools:
  - Read
  - 'Bash(npm test:*)'
deny: [Edit, Write]
model: haiku
mode: accept-edits
labels: test, qa
max: 3
icon: md-flask ⚗
verb: testing
# a comment
colour: yellow
---

Write the tests first.

Then run them.
")))
    (should-not problems)
    (should (equal (plist-get role :name) "tester"))
    (should (equal (plist-get role :description) "writes and runs tests"))
    (should (equal (plist-get role :tools) '("Read" "Bash(npm test:*)")))
    (should (equal (plist-get role :deny) '("Edit" "Write")))
    (should (equal (plist-get role :model) "haiku"))
    (should (equal (plist-get role :mode) "acceptEdits"))
    (should (equal (plist-get role :labels) '("test" "qa")))
    (should (equal (plist-get role :max) 3))
    (should (equal (plist-get role :icon) "md-flask"))
    (should (equal (plist-get role :glyph) "⚗"))
    (should (equal (plist-get role :verb) "testing"))
    (should (equal (plist-get role :colour) "yellow"))
    (should (equal (plist-get role :instructions) "Write the tests first.\n\nThen run them."))
    (should (string-suffix-p "tester.md" (plist-get role :file)))))

(ert-deftest agent-workspace-roles/a-small-role ()
  "Only its front matter's lines: its name from its file, no model with
inherit, Claude Code's color spelling; no instructions, warned about."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\ndescription: triages\nmodel: inherit\ncolor: green\nmode: dontAsk\n---\n"
                                "triager.md")))
    (should (equal (+test-awr--messages problems)
                   '((warning "triager.md:6: no instructions after its front matter"))))
    (should (equal (plist-get role :name) "triager"))
    (should-not (plist-get role :model))
    (should (equal (plist-get role :colour) "green"))
    (should (equal (plist-get role :mode) "dontAsk"))
    (should-not (plist-get role :instructions))))

(ert-deftest agent-workspace-roles/errors-name-the-file-and-line ()
  "An error leaves the role out; each says its file and line."
  (dolist (case '(("No front matter.\n" (error "tester.md:1: no front matter: it starts with a line ---, its keys, then a line ---"))
                  ("---\nmax: 3\n" (error "tester.md:3: its front matter isn't closed: a line --- after its keys"))
                  ("---\ndescription: x\nmode: yolo\n---\nDo.\n"
                   (error "tester.md:3: mode yolo: not one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions"))
                  ("---\nmax: many\ndescription: x\n---\nDo.\n" (error "tester.md:2: max many: not a number above 0"))
                  ("---\nmax: 0\ndescription: x\n---\nDo.\n" (error "tester.md:2: max 0: not a number above 0"))
                  ("---\ncolour: #ff0000\ndescription: x\n---\nDo.\n"
                   (error "tester.md:2: colour #ff0000: not one of blue, magenta, green, yellow, cyan, red, white, black"))
                  ("---\nname: builder\ndescription: x\n---\nDo.\n"
                   (error "tester.md:2: its name is builder, its file's tester: they must agree"))
                  ("---\nthis line\ndescription: x\n---\nDo.\n" (error "tester.md:2: not a key: this line"))
                  ("---\n  - Read\ndescription: x\n---\nDo.\n" (error "tester.md:2: a list item with no key before it"))
                  ;; No description, or an empty one.
                  ("---\nmax: 2\n---\nDo.\n" (error "tester.md:1: no description: say what it does (description: ...)"))
                  ("---\ndescription:\n---\nDo.\n" (error "tester.md:2: description: empty: say what it does"))
                  ;; A tool not Tool or Tool(pattern), each on its line.
                  ("---\ndescription: x\ntools: Read, Bash(git:*\n---\nDo.\n"
                   (error "tester.md:3: tools Bash(git:*: not a tool, Tool or Tool(pattern)"))
                  ("---\ndescription: x\ndeny:\n  - Edit\n  - Web Fetch\n---\nDo.\n"
                   (error "tester.md:5: deny Web Fetch: not a tool, Tool or Tool(pattern)"))
                  ("---\ndescription: x\ntools: Bash(a)(b)\n---\nDo.\n"
                   (error "tester.md:3: tools Bash(a)(b): not a tool, Tool or Tool(pattern)"))))
    (pcase-let ((`(,role . ,problems) (+test-awr--read (car case))))
      (should-not role)
      (should (equal (+test-awr--messages problems) (cdr case)))))
  ;; Its name (its file's) a lowercase letter, then lowercase letters,
  ;; digits or -.
  (dolist (name '("Tester.md" "qa%.md" "1st.md" "my_role.md"))
    (pcase-let ((`(,role . ,problems) (+test-awr--read "---\ndescription: x\n---\nDo.\n" name)))
      (should-not role)
      (should (equal (+test-awr--messages problems)
                     (list (list 'error (format "%s:1: its name %s (its file's): a lowercase letter, then lowercase letters, digits or -"
                                                name (file-name-base name)))))))))

(ert-deftest agent-workspace-roles/tools-claude-code-takes ()
  "Tool, Tool(pattern) (parentheses inside closed), an MCP server's tool:
no problem."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\ndescription: x\ntools: Read, Bash(npm test:*), mcp__agent-ui__show, Bash(echo (a)), WebFetch(domain:example.com)\n---\nDo.\n")))
    (should-not problems)
    (should (equal (plist-get role :tools)
                   '("Read" "Bash(npm test:*)" "mcp__agent-ui__show" "Bash(echo (a))" "WebFetch(domain:example.com)")))))

(ert-deftest agent-workspace-roles/warnings-of-the-rest ()
  "Warned about, the role kept: a model not one there is, an icon no nerd
icon, a key given twice (the last used), a tool both allowed and denied
\(denied), no instructions."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\ndescription: x\nmodel: gpt-4\nicon: md-no_such_icon_here ⚗\nverb: a\nverb: b\ntools: Read, Edit\ndeny: Edit\n---\n")))
    (should role)
    (should (equal (plist-get role :verb) "b"))
    (should (equal (plist-get role :glyph) "⚗"))
    (should (equal (+test-awr--messages problems)
                   (append
                    '((warning "tester.md:3: model gpt-4: not inherit, one of opus, sonnet, haiku, nor a model's id (claude-...)"))
                    (and (require 'nerd-icons nil t)
                         '((warning "tester.md:4: icon md-no_such_icon_here: not a nerd icon (md-NAME or cod-NAME): ⚗ is shown")))
                    '((warning "tester.md:6: verb given twice (line 5 too): the last is used")
                      (warning "tester.md:8: Edit both allowed (tools) and denied (deny): denied")
                      (warning "tester.md:9: no instructions after its front matter"))))))
  ;; A model's id, inherit, one of the models; color for colour, twice.
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\ndescription: x\nmodel: claude-opus-4-1\ncolour: blue\ncolor: red\n---\nDo.\n")))
    (should (equal (plist-get role :model) "claude-opus-4-1"))
    (should (equal (plist-get role :colour) "red"))
    (should (equal (+test-awr--messages problems)
                   '((warning "tester.md:5: color given twice (line 4 too): the last is used"))))))

(ert-deftest agent-workspace-roles/talks-to-and-hands-to-name-roles ()
  "A talks-to, hands-to or returns-to naming no role of the project's, or
its own: warned about on its item's line, once all are read; the role
kept. hands-to any: every role, no warning."
  (let* ((project (+test-awr--dir "names"))
         (dir (expand-file-name ".agent-workspace/roles/" project)))
    (+test-awr--file dir "tester.md"
                     "---\ndescription: tests\nhands-to: tester\ntalks-to:\n  - builder\n  - nobody\n---\nTest.\n")
    (+test-awr--file dir "helper.md" "---\ndescription: helps\nhands-to: tester, reviewer\nreturns-to: builder\n---\nHelp.\n")
    (+test-awr--file dir "router.md" "---\ndescription: routes\nhands-to: any\nreturns-to: nobody\n---\nRoute.\n")
    (+test-awr--quietly
      (should (member "tester" (mapcar #'car (agent-workspace-roles project))))
      (should (equal (plist-get (alist-get "helper" (agent-workspace-roles project) nil nil #'equal) :returns-to)
                     '("builder")))
      (should (equal (+test-awr--messages (agent-workspace-role-problems project))
                     '((warning "router.md:4: returns-to nobody: no such role (builder, investigator, reviewer, scribe, helper, router, tester)")
                       (warning "tester.md:3: hands-to tester: its own role")
                       (warning "tester.md:6: talks-to nobody: no such role (builder, investigator, reviewer, scribe, helper, router, tester)"))))
      (should (= (length warnings) 3)))))

(ert-deftest agent-workspace-roles/warnings-keep-the-role ()
  "An unknown key, or a worktree key (every agent has its own): warned
about, ignored; the role kept."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\nloop: true\nworktree: false\nverb: testing\ndescription: x\n---\nDo.\n")))
    (should (equal (plist-get role :verb) "testing"))
    (should (equal (+test-awr--messages problems)
                   '((warning "tester.md:2: unknown key loop: ignored")
                     (warning "tester.md:3: worktree: ignored (every agent has its own worktree)"))))))

;; ====== THE STARTERS ======

(ert-deftest agent-workspace-roles/the-starters ()
  "The four starters read without a problem; the ones that mustn't edit
can't (Edit, Write denied), and what each does alone is allowed (bd, git's
reading); the builder edits without asking, and never pushes."
  (let ((dir agent-workspace-starter-roles-directory))
    (should (equal (mapcar #'file-name-base (directory-files dir nil "\\.md\\'"))
                   '("builder" "investigator" "reviewer" "scribe")))
    (should-not (agent-workspace-role-problems (+test-awr--dir "starters")))
    (dolist (file (directory-files dir t "\\.md\\'"))
      (pcase-let ((`(,role . ,problems) (agent-workspace-role-read file)))
        (should-not problems)
        (dolist (key '(:description :verb :icon :glyph :colour :max :instructions :tools))
          (should (plist-get role key)))
        ;; None has a mode: each agent starts in agent-workspace-mode's (auto).
        (should-not (plist-get role :mode))
        (should (member "Bash(bd:*)" (plist-get role :tools)))
        (should (string-width (plist-get role :glyph)))
        (if (equal (plist-get role :name) "builder")
            (progn
              (should (member "Edit" (plist-get role :tools)))
              (should (equal (plist-get role :deny) '("Bash(git push:*)")))
              (should (equal (plist-get role :labels) '("build"))))
          (should (equal (plist-get role :deny) '("Edit" "Write" "NotebookEdit")))
          (should-not (seq-intersection '("Edit" "Write") (plist-get role :tools))))))))

(ert-deftest agent-workspace-roles/a-project-with-none-of-its-own ()
  "A project with no roles of its own has the starters."
  (let ((project (+test-awr--dir "none")))
    (should (equal (mapcar #'car (agent-workspace-roles project))
                   '("builder" "investigator" "reviewer" "scribe")))
    (should (equal (plist-get (agent-workspace--project-role project "builder") :verb) "building"))
    ;; A role gone (its file deleted): its agents have one with nothing of its own.
    (should (equal (agent-workspace--project-role project "gone") '(:name "gone")))))

(ert-deftest agent-workspace-roles/a-project-s-own ()
  "A project's own roles add to the starters, or replace one of the same
name; one with errors is left out, warned about once."
  (let* ((project (+test-awr--dir "own"))
         (dir (expand-file-name ".agent-workspace/roles/" project)))
    (+test-awr--file dir "tester.md" "---\ndescription: tests\nverb: testing\n---\nTest it.\n")
    (+test-awr--file dir "builder.md" "---\ndescription: makes\nverb: making\nmodel: haiku\n---\nMake.\n")
    (+test-awr--file dir "broken.md" "---\nmax: lots\ndescription: broken\n---\nBreak.\n")
    (+test-awr--quietly
      (let ((roles (agent-workspace-roles project)))
        (should (equal (mapcar #'car roles) '("builder" "investigator" "reviewer" "scribe" "tester")))
        (should (equal (plist-get (alist-get "builder" roles nil nil #'equal) :verb) "making"))
        (should (equal (plist-get (alist-get "builder" roles nil nil #'equal) :model) "haiku")))
      (should (equal (+test-awr--messages (agent-workspace-role-problems project))
                     '((error "broken.md:2: max lots: not a number above 0"))))
      (should (= (length warnings) 1))
      (should (string-match-p "broken\\.md:2: max lots" (cadr (car warnings))))
      ;; Read again: the same, not warned again.
      (agent-workspace-roles project)
      (should (= (length warnings) 1))
      ;; A file changed: read again.
      (+test-awr--file dir "broken.md" "---\nmax: 2\ndescription: broken\n---\nBreak.\n")
      (set-file-times (expand-file-name "broken.md" dir) (time-add nil 5))
      (should (member "broken" (mapcar #'car (agent-workspace-roles project))))
      (should-not (agent-workspace-role-problems project)))))

(ert-deftest agent-workspace-roles/local-ones ()
  "Your local roles (.agent-shell/agent-workspace/roles/) add to the
starters and the project's: same name, local replaces project replaces
starter, each role saying where it comes from and what it replaced; a
local file's problems name it; one added, changed or removed is read
again."
  (let* ((project (+test-awr--dir "local"))
         (own (expand-file-name ".agent-workspace/roles/" project))
         (local (expand-file-name ".agent-shell/agent-workspace/roles/" project)))
    (+test-awr--file own "builder.md" "---\ndescription: d\nverb: making\n---\nDo.\n")
    (+test-awr--file own "tester.md" "---\ndescription: d\nverb: testing\n---\nDo.\n")
    (+test-awr--file local "builder.md" "---\ndescription: d\nverb: crafting\nmode: plan\ntools: Read\n---\nMine.\n")
    (+test-awr--file local "tester.md" "---\ndescription: d\nverb: checking\n---\nDo.\n")
    (+test-awr--file local "reviewer.md" "---\ndescription: d\nverb: reading\n---\nDo.\n")
    (+test-awr--file local "mine.md" "---\ndescription: d\nverb: helping\n---\nDo.\n")
    (+test-awr--quietly
      (let ((roles (agent-workspace-roles project)))
        (cl-flet ((role (name) (alist-get name roles nil nil #'equal)))
          (should (equal (mapcar #'car roles)
                         '("builder" "investigator" "reviewer" "scribe" "tester" "mine")))
          ;; Local replaces project replaces starter.
          (should (equal (plist-get (role "builder") :verb) "crafting"))
          (should (equal (plist-get (role "builder") :mode) "plan"))
          (should (equal (plist-get (role "builder") :tools) '("Read")))
          (should (equal (plist-get (role "builder") :instructions) "Mine."))
          (should (equal (plist-get (role "builder") :origin) 'local))
          (should (equal (plist-get (role "builder") :replaces) 'project))
          ;; Local replaces project.
          (should (equal (plist-get (role "tester") :verb) "checking"))
          (should (equal (plist-get (role "tester") :replaces) 'project))
          ;; Local replaces starter.
          (should (equal (plist-get (role "reviewer") :verb) "reading"))
          (should (equal (plist-get (role "reviewer") :origin) 'local))
          (should (equal (plist-get (role "reviewer") :replaces) 'starter))
          ;; Its own, and a starter untouched.
          (should (equal (plist-get (role "mine") :origin) 'local))
          (should-not (plist-get (role "mine") :replaces))
          (should (equal (plist-get (role "scribe") :origin) 'starter))
          (should-not (plist-get (role "scribe") :replaces))))
      ;; Its agents get it.
      (should (equal (plist-get (agent-workspace--project-role project "builder") :verb) "crafting"))
      ;; Project replaces starter, without a local one.
      (delete-file (expand-file-name "builder.md" local))
      (let ((builder (alist-get "builder" (agent-workspace-roles project) nil nil #'equal)))
        (should (equal (plist-get builder :verb) "making"))
        (should (equal (plist-get builder :origin) 'project))
        (should (equal (plist-get builder :replaces) 'starter)))
      ;; Added: read again.
      (+test-awr--file local "extra.md" "---\ndescription: d\nverb: extra\n---\nDo.\n")
      (should (member "extra" (mapcar #'car (agent-workspace-roles project))))
      ;; Changed: read again, its problem naming its file and line.
      (+test-awr--file local "extra.md" "---\ndescription: d\nmax: none\n---\nDo.\n")
      (set-file-times (expand-file-name "extra.md" local) (time-add nil 5))
      (should-not (member "extra" (mapcar #'car (agent-workspace-roles project))))
      (should (equal (mapcar #'cadr (agent-workspace-role-problems project))
                     (list (concat (abbreviate-file-name (expand-file-name "extra.md" local))
                                   ":3: max none: not a number above 0"))))
      (should (string-match-p "extra\\.md:3: max none" (cadr (car warnings))))
      ;; Removed: gone.
      (delete-file (expand-file-name "extra.md" local))
      (should-not (agent-workspace-role-problems project)))))

(ert-deftest agent-workspace-roles/local-ones-from-a-worktree ()
  "From one of a project's worktrees (an agent's), its main checkout's local
roles: they're not in the worktree's checkout."
  (let* ((project (+test-awr--dir "worktree"))
         (worktree (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
    (let ((default-directory project))
      (dolist (args '(("init" "-q" "-b" "main") ("-c" "user.name=t" "-c" "user.email=t@t"
                                                 "commit" "-q" "--allow-empty" "-m" "one")
                      ("worktree" "add" "-q" "-b" "agent/ada" ".agent-shell/worktrees/builder-ada")))
        (should (eql 0 (apply #'call-process "git" nil nil nil args)))))
    (+test-awr--file (expand-file-name ".agent-shell/agent-workspace/roles/" project)
                     "mine.md" "---\ndescription: d\nverb: helping\n---\nDo.\n")
    (let ((default-directory worktree))
      (should (equal (agent-workspace-project) project))
      (should (equal (plist-get (alist-get "mine" (agent-workspace-roles) nil nil #'equal) :verb)
                     "helping")))))

;; ====== MAKING AN AGENT OF IT ======

(defun +test-awr--agent (project name role state)
  "An agent NAME of ROLE in STATE, a record of PROJECT's crew."
  (agent-workspace--make-agent :name name :role role :state state :colour "blue" :project project))

(ert-deftest agent-workspace-roles/how-many-may-run ()
  "A role's max: as many running (not asleep, not gone home), the next is
refused; an unknown role is refused, naming the roles."
  (let* ((project (+test-awr--dir "max"))
         (agent-workspace--crews (make-hash-table :test #'equal)))
    (puthash project (list (+test-awr--agent project "sam" "scribe" 'desk)
                           (+test-awr--agent project "ada" "investigator" 'working)
                           (+test-awr--agent project "ken" "investigator" 'asleep))
             agent-workspace--crews)
    (should (= (agent-workspace-role-count project "investigator") 1))
    (should-error (agent-workspace--check-role project "scribe") :type 'user-error)
    (should (string-match-p "1 scribe run already"
                            (cadr (should-error (agent-workspace--check-role project "scribe")))))
    (should-not (agent-workspace--check-role project "investigator"))
    (should (string-match-p "No role tester: builder, investigator, reviewer, scribe"
                            (cadr (should-error (agent-workspace--check-role project "tester")))))
    ;; Waking one counts it too.
    (setf (agent-workspace-agent-state (car (agent-workspace-agents project))) 'asleep)
    (should-not (agent-workspace--check-room project "scribe"))
    ;; create refuses before making anything.
    (setf (agent-workspace-agent-state (car (agent-workspace-agents project))) 'desk)
    (cl-letf (((symbol-function 'agent-workspace-worktree-ensure) (lambda (&rest _) (error "Made one"))))
      (should-error (agent-workspace-create :project project :role "scribe" :name "grace") :type 'user-error)
      (should-error (agent-workspace-create :project project :role "nope" :name "grace") :type 'user-error))))

(ert-deftest agent-workspace-roles/its-colour-while-free ()
  "An agent gets its role's colour while no agent has it."
  (let* ((project (+test-awr--dir "colour"))
         (agent-workspace--crews (make-hash-table :test #'equal))
         (made nil))
    (cl-letf (((symbol-function 'agent-workspace-worktree-ensure) #'ignore)
              ((symbol-function 'agent-workspace--start) #'ignore))
      (push (agent-workspace-create :project project :role "investigator" :name "ada") made)
      (push (agent-workspace-create :project project :role "investigator" :name "ken") made)
      (push (agent-workspace-create :project project :role "reviewer" :name "linus") made))
    (should (equal (mapcar #'agent-workspace-agent-colour (reverse made)) '("magenta" "blue" "green")))))

(ert-deftest agent-workspace-roles/its-instructions-told ()
  "A starter's instructions follow who the agent is, in what it's told."
  (let* ((project (+test-awr--dir "told"))
         (agent (agent-workspace--make-agent :name "sam" :role "investigator" :project project
                                             :worktree (expand-file-name ".agent-shell/worktrees/sam/" project)
                                             :branch "agent/sam"))
         (text (let ((agent-workspace--starting agent)) (agent-workspace-agent-context))))
    (should (string-match-p "\\`You are sam, the investigator" text))
    (should (string-search "\n\nYou're an investigator" text))
    (should (string-search "hand it to the builders, as you're told" text))))

(ert-deftest agent-workspace-roles/copied-into-a-project ()
  "A starter copied into the project's roles, to change there; not over one
it has."
  (let ((project (+test-awr--dir "copy")))
    (let ((file (agent-workspace-copy-role "builder" project)))
      (should (equal file (expand-file-name ".agent-workspace/roles/builder.md" project)))
      (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                     (with-temp-buffer
                       (insert-file-contents (expand-file-name "builder.md" agent-workspace-starter-roles-directory))
                       (buffer-string)))))
    (should-error (agent-workspace-copy-role "builder" project) :type 'user-error)
    (should-error (agent-workspace-copy-role "nope" project) :type 'user-error)
    ;; Into the project's: only a starter.
    (+test-awr--file (expand-file-name ".agent-workspace/roles/" project) "tester.md" "---\ndescription: d\nverb: testing\n---\nDo.\n")
    (should-error (agent-workspace-copy-role "tester" project 'project) :type 'user-error)))

(ert-deftest agent-workspace-roles/copied-into-your-local-ones ()
  "A starter, or the project's own (its own replacing a starter), copied
into your local roles; not over one there already."
  (let* ((project (+test-awr--dir "copy-local"))
         (own (expand-file-name ".agent-workspace/roles/" project))
         (local (expand-file-name ".agent-shell/agent-workspace/roles/" project)))
    (+test-awr--file own "tester.md" "---\nverb: testing\n---\nTest.\n")
    (+test-awr--file own "builder.md" "---\ndescription: d\nverb: making\n---\nDo.\n")
    (should (equal (mapcar #'car (agent-workspace--copy-role-sources project 'local))
                   '("builder" "investigator" "reviewer" "scribe" "tester")))
    (should (equal (mapcar #'car (agent-workspace--copy-role-sources project 'project))
                   '("builder" "investigator" "reviewer" "scribe")))
    (let ((file (agent-workspace-copy-role "tester" project 'local)))
      (should (equal file (expand-file-name "tester.md" local)))
      (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                     "---\nverb: testing\n---\nTest.\n")))
    ;; The project's own builder, not the starter.
    (should (equal (with-temp-buffer (insert-file-contents (agent-workspace-copy-role "builder" project 'local))
                                     (buffer-string))
                   "---\ndescription: d\nverb: making\n---\nDo.\n"))
    (should (file-exists-p (agent-workspace-copy-role "scribe" project 'local)))
    (should (string-match-p "a local tester already"
                            (cadr (should-error (agent-workspace-copy-role "tester" project 'local)))))
    (should-error (agent-workspace-copy-role "nope" project 'local) :type 'user-error)))

;; ====== CHECKED ======

(ert-deftest agent-workspace-roles/check-roles ()
  "M-x agent-workspace-check-roles: every problem of the three places read
anew, a line FILE:LINE: error|warning: what, each visiting its file and
line; none: said."
  (let* ((project (+test-awr--dir "check"))
         (own (expand-file-name ".agent-workspace/roles/" project))
         (local (expand-file-name ".agent-shell/agent-workspace/roles/" project))
         (said nil))
    (cl-letf (((symbol-function 'message) (lambda (format &rest args) (push (apply #'format format args) said))))
      (should-not (agent-workspace-check-roles project))
      (should (equal (car said) "4 roles, no problems")))
    (+test-awr--file own "tester.md" "---\ndescription: tests\nmode: autoo\n---\nTest.\n")
    (+test-awr--file local "mine.md" "---\ndescription: mine\nhands-to: nobody\n---\n")
    (+test-awr--quietly
      ;; Read once: the warnings shown then.
      (agent-workspace-roles project)
      (setq warnings nil)
      (let ((problems (agent-workspace-check-roles project)))
        (should (= (length problems) 3))
        ;; Read anew, nothing popped up.
        (should-not warnings))
      (with-current-buffer "*agent-workspace roles*"
        (should (derived-mode-p 'compilation-mode))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       (concat "The roles of " (abbreviate-file-name (directory-file-name project))
                               ": 1 error, 2 warnings\n\n"
                               ".agent-workspace/roles/tester.md:3: error: mode autoo: not one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions\n"
                               ".agent-shell/agent-workspace/roles/mine.md:4: warning: no instructions after its front matter\n"
                               ".agent-shell/agent-workspace/roles/mine.md:3: warning: hands-to nobody: no such role (builder, investigator, reviewer, scribe, mine)\n")))
        ;; Each line visits its file at its line.
        (goto-char (point-min))
        (let ((visited nil))
          (dotimes (_ 3)
            (compilation-next-error 1)
            (save-window-excursion
              (compile-goto-error)
              (push (cons (file-name-nondirectory (buffer-file-name)) (line-number-at-pos)) visited)
              (kill-buffer)))
          (should (equal (nreverse visited) '(("tester.md" . 3) ("mine.md" . 4) ("mine.md" . 3)))))))))
