;;; tests/unit/test-agent-workspace-roles.el -*- lexical-binding: t; -*-
;; config/agent-workspace/roles.el: role files read and checked (their
;; problems naming the file and line), the starters, a project's own roles,
;; how many of a role may run, a starter copied into a project. That a role's
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
inherit, Claude Code's color spelling."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\nmodel: inherit\ncolor: green\nmode: dontAsk\n---\n" "triager.md")))
    (should-not problems)
    (should (equal (plist-get role :name) "triager"))
    (should-not (plist-get role :model))
    (should (equal (plist-get role :colour) "green"))
    (should (equal (plist-get role :mode) "dontAsk"))
    (should-not (plist-get role :instructions))))

(ert-deftest agent-workspace-roles/errors-name-the-file-and-line ()
  "An error leaves the role out; each says its file and line."
  (dolist (case '(("No front matter.\n" (error "tester.md:1: no front matter: it starts with a line ---, its keys, then a line ---"))
                  ("---\nmax: 3\n" (error "tester.md:3: its front matter isn't closed: a line --- after its keys"))
                  ("---\ndescription: x\nmode: yolo\n---\n"
                   (error "tester.md:3: mode yolo: not one of default, acceptEdits, plan, dontAsk, bypassPermissions"))
                  ("---\nmax: many\n---\n" (error "tester.md:2: max many: not a number above 0"))
                  ("---\nmax: 0\n---\n" (error "tester.md:2: max 0: not a number above 0"))
                  ("---\ncolour: #ff0000\n---\n"
                   (error "tester.md:2: colour #ff0000: not one of blue, magenta, green, yellow, cyan, red, white, black"))
                  ("---\nname: builder\n---\n" (error "tester.md:2: its name is builder, its file's tester: they must agree"))
                  ("---\nthis line\n---\n" (error "tester.md:2: not a key: this line"))
                  ("---\n  - Read\n---\n" (error "tester.md:2: a list item with no key before it"))))
    (pcase-let ((`(,role . ,problems) (+test-awr--read (car case))))
      (should-not role)
      (should (equal (+test-awr--messages problems) (cdr case))))))

(ert-deftest agent-workspace-roles/warnings-keep-the-role ()
  "An unknown key, or a worktree key (every agent has its own): warned
about, ignored; the role kept."
  (pcase-let ((`(,role . ,problems)
               (+test-awr--read "---\nloop: true\nworktree: false\nverb: testing\n---\n")))
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
    (dolist (file (directory-files dir t "\\.md\\'"))
      (pcase-let ((`(,role . ,problems) (agent-workspace-role-read file)))
        (should-not problems)
        (dolist (key '(:description :verb :icon :glyph :colour :max :mode :instructions :tools))
          (should (plist-get role key)))
        (should (member "Bash(bd:*)" (plist-get role :tools)))
        (should (string-width (plist-get role :glyph)))
        (if (equal (plist-get role :name) "builder")
            (progn
              (should (equal (plist-get role :mode) "acceptEdits"))
              (should (member "Edit" (plist-get role :tools)))
              (should (equal (plist-get role :deny) '("Bash(git push:*)")))
              (should (equal (plist-get role :labels) '("build"))))
          (should (equal (plist-get role :mode) "default"))
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
    (+test-awr--file dir "tester.md" "---\nverb: testing\n---\nTest it.\n")
    (+test-awr--file dir "builder.md" "---\nverb: making\nmodel: haiku\n---\n")
    (+test-awr--file dir "broken.md" "---\nmax: lots\n---\n")
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
      (+test-awr--file dir "broken.md" "---\nmax: 2\n---\n")
      (set-file-times (expand-file-name "broken.md" dir) (time-add nil 5))
      (should (member "broken" (mapcar #'car (agent-workspace-roles project))))
      (should-not (agent-workspace-role-problems project)))))

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
    (should-error (agent-workspace-copy-role "nope" project) :type 'user-error)))
