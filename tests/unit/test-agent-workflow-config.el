;;; tests/unit/test-agent-workflow-config.el -*- lexical-binding: t; -*-
;; config/agent-workflow.el: this config's layer over the agent-workflow
;; package (its own tests are the package's, ~/dev/agent-workflow/tests):
;; where its files go, what a session is told (through config/agent-shell/
;; context.el), an agent other than Claude Code's rules answered by
;; config/agent-shell/permissions.el, the issue picker drawn as the issue
;; list (config/beads/look.el), the agent workspace's crew refusing the
;; pool, the runs' list's keys, the package's mode on; and this config's
;; own workflows (.agent-workflow/: github, screenshots), their scripts.
;; Beads, its issue tracker: test-agent-workflow-beads.el.

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(+test-load "config/emacs" "config/tiling" "config/banner" "config/beads"
            "config/agent-shell" "config/agent-ui" "config/agent-workflow")
(require 'agent-workflow-parts)
(require 'beads-faces)
(require 'doom-themes)                  ; doom-blend
(require 'nerd-icons)                   ; the types' icons
;; The picker's crm, loaded before a test stands in for its reading (loaded
;; by the picker inside, it would replace the stand-in).
(require 'crm)

;; ====== ON, AND WHERE ======

(ert-deftest agent-workflow-config/the-package-on ()
  (should (featurep 'agent-workflow))
  (should agent-workflow-mode)
  ;; Its own command, skills and starters: the package's.
  (should (file-executable-p agent-workflow-command))
  (should (file-exists-p agent-workflow-skill))
  (should (file-exists-p agent-workflow-step-skill))
  (should (file-directory-p (expand-file-name "workflows" agent-workflow-starters-directory)))
  ;; cmd/agent-workflow runs it.
  (should (file-executable-p (expand-file-name "cmd/agent-workflow" +test-root))))

(ert-deftest agent-workflow-config/where-its-files-go ()
  (should (equal agent-workflow-projects-file (expand-file-name "agent-workflow-projects.eld" doom-data-dir)))
  ;; Its trust: Agent UI's (config/agent-ui.el).
  (should (equal agent-ui-trust-file (expand-file-name "agent-ui/trusted-dashboards.eld" doom-data-dir))))

;; ====== WHAT THE AGENT IS TOLD ======

(ert-deftest agent-workflow-config/told-through-this-config ()
  "What a session is told: this config's (`+my/agent-shell-context-functions'),
not the package's own system prompt; an agent of the pool's job only once
the pool is loaded, every session where the skill is."
  (should-not agent-workflow-system-prompt)
  (should (memq #'+my/agent-workflow-agent-context +my/agent-shell-context-functions))
  (should (memq #'agent-workflow-skill-context +my/agent-shell-context-functions))
  ;; No agent of the pool starting: nothing.
  (should-not (+my/agent-workflow-agent-context)))

(ert-deftest agent-workflow-config/another-kind-s-rules ()
  "An agent other than Claude Code: its rules (`agent-workflow--rules') its
session's, answered by this config's permissions: done allowed, a denied
command, an edit of .agent-workflow/ refused, there or in the main
checkout; its own files not decided here."
  (should (eq agent-workflow-session-rules-function #'+my/agent-workflow-session-rules))
  (let* ((project (file-name-as-directory (+test-tmp-file "awfc-rules/project/")))
         (dir (file-name-as-directory (+test-tmp-file "awfc-rules/worktree/")))
         (rules (agent-workflow--rules '(:tools ("Read") :deny ("Bash(git push:*)")) project))
         (verdict (lambda (kind &rest more)
                    (+my/agent-shell-permission-by-rules
                     rules (append (list (cons :kind kind))
                                   (cl-loop for (key value) on more by #'cddr collect (cons key value)))
                     dir))))
    (with-temp-buffer
      (+my/agent-workflow-session-rules rules)
      (should (equal +my/agent-shell-permission-rules rules)))
    (should (eq (funcall verdict "execute" :raw-input `((command . ,(concat agent-workflow-command " done approved \"ok\""))))
                'allow))
    (should (eq (funcall verdict "execute" :raw-input '((command . "git push origin"))) 'reject))
    (should (eq (funcall verdict "read") 'allow))
    (should (eq (funcall verdict "edit" :raw-input `((file_path . ,(expand-file-name ".agent-workflow/workflows/x.yml" dir))))
                'reject))
    (should (eq (funcall verdict "edit" :raw-input `((file_path . ,(expand-file-name ".agent-workflow/scripts/a.sh" project))))
                'reject))
    (should-not (funcall verdict "edit" :raw-input `((file_path . ,(expand-file-name "src/a.el" dir)))))))

;; ====== THE AGENT WORKSPACE ======

(ert-deftest agent-workflow-config/no-pool-where-a-crew-runs ()
  "A project whose crew's lock an Emacs alive holds: the pool refuses it,
saying why; a lock left by an Emacs gone: not."
  (should (memq #'+my/agent-workflow-crew-running agent-workflow-project-busy-functions))
  (let* ((project (file-name-as-directory (+test-tmp-file "awfc-crew/refused/")))
         (lock (expand-file-name ".agent-shell/agent-workspace/crew.lock" project)))
    (should-not (agent-workflow-project-busy project))
    (make-directory (file-name-directory lock) t)
    (write-region (format "%d here\n" (emacs-pid)) nil lock)
    (should (equal (agent-workflow-project-busy project)
                   "The agent-workspace crew of refused runs: its agents would take the same issues"))
    (write-region "999999 gone\n" nil lock)
    (should-not (agent-workflow-project-busy project))))

;; ====== THE ISSUE PICKER ======

(defun +test-awfc--issue (id title type &rest more)
  "A stand-in open issue ID, as the Beads tracker lists it: a plist, :data
its bd JSON (MORE: bd's other keys, status, priority, labels..., as a
plist)."
  (let ((data (append `((id . ,id) (title . ,title) (issue_type . ,type))
                      (let (alist)
                        (while more
                          (push (cons (intern (substring (symbol-name (pop more)) 1)) (pop more)) alist))
                        (nreverse alist)))))
    (list :id id :title title :type type :status (alist-get 'status data) :labels (alist-get 'labels data)
          :data data)))

(defconst +test-awfc--issues
  (list (+test-awfc--issue "demo-1" "Parser rewrite" "epic" :status "open" :priority 1 :labels '("parser"))
        (+test-awfc--issue "demo-2" "Examples: the screenshots taken again, each as it looks today" "chore"
                           :status "open" :priority 3 :labels '("workflow:quick"))
        (+test-awfc--issue "demo-3" "Crash on an empty file" "bug" :status "in_progress" :priority 0)
        (+test-awfc--issue "demo-4" "Release 2.0" "task" :status "open" :priority 2
                           :dependencies '(((type . "blocks") (depends_on_id . "demo-3")))))
  "Open issues: a title with a comma, an epic, one blocked by another.")

(defun +test-awfc--affixes ()
  "Each candidate's (NAME PREFIX SUFFIX), as the picker draws them, in its order."
  (let ((seen nil)
        (agent-workflow-trackers
         (list (list :detect #'always :issues (lambda (_) +test-awfc--issues)
                     :children (lambda (_ id) (and (equal id "demo-1") '("demo-11" "demo-12")))))))
    (cl-letf (((symbol-function 'completing-read-multiple)
               (lambda (_prompt table &rest _)
                 (let* ((names (all-completions "" table))
                        (metadata (completion-metadata "" table nil)))
                   (setq seen (funcall (completion-metadata-get metadata 'affixation-function) names))
                   (list (car names))))))
      (agent-workflow--read-issues "/tmp/"))
    seen))

(defun +test-awfc--faces (string)
  "The faces in STRING, flattened (inherited ones too, as given)."
  (let (faces)
    (dotimes (i (length string))
      (let ((face (get-text-property i 'face string)))
        (dolist (face (if (and (listp face) (not (keywordp (car face)))) face (list face)))
          (when face (push face faces)))))
    faces))

(ert-deftest agent-workflow-config/picked-as-the-issue-list-draws-them ()
  "Each issue as the list draws it: its status (blocked by an open issue:
⊘1), its priority (P0 a badge), its type's icon before its id and title;
its labels as tags after, an epic said; in bd's order (config/agent-workflow/beads.el)."
  (should (eq agent-workflow-issue-affixes-function #'+my/agent-workflow-issue-affixes))
  (let ((rows (+test-awfc--affixes)))
    (should (equal (mapcar #'car rows)
                   '("demo-1  Parser rewrite"
                     "demo-2  Examples: the screenshots taken again, each as it looks today"
                     "demo-3  Crash on an empty file"
                     "demo-4  Release 2.0")))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 0 rows)))
      (should (string-match-p "\\`○  P1 " (substring-no-properties prefix)))
      (should (string-match-p "(epic: its issues)" suffix))
      (should (string-match-p " parser \\'" suffix))
      (should (+test-awfc--faces suffix)))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 1 rows)))
      (should (string-match-p "\\`○  P3 " (substring-no-properties prefix)))
      (should (memq 'shadow (+test-awfc--faces prefix)))
      (should (string-match-p " workflow:quick \\'" suffix)))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 2 rows)))
      (should (string-match-p "\\`◔  P0 " (substring-no-properties prefix)))
      (should (memq 'beads-status-in-progress (+test-awfc--faces prefix)))
      (should (equal suffix "")))
    (pcase-let ((`(,_ ,prefix ,_) (nth 3 rows)))
      (should (string-match-p "\\`⊘1 P2 " (substring-no-properties prefix)))
      (should (memq 'beads-status-blocked (+test-awfc--faces prefix))))))

(ert-deftest agent-workflow-config/picked-without-the-issue-list ()
  "config/beads/look.el not loaded: the package's own look, its labels after, muted."
  (cl-letf (((symbol-function '+my/beads-format-status) nil))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 1 (+test-awfc--affixes))))
      (should (equal prefix ""))
      (should (equal (substring-no-properties suffix) "  workflow:quick"))
      (should (memq 'shadow (+test-awfc--faces suffix))))))

;; ====== THE RUNS' LIST ======

(ert-deftest agent-workflow-config/the-runs-list-s-keys ()
  "Vim's keys in the runs' list, once its file is loaded."
  (should (eq (evil-get-auxiliary-keymap agent-workflow-list-mode-map 'normal) (evil-get-auxiliary-keymap agent-workflow-list-mode-map 'normal)))
  (should (eq (lookup-key (evil-get-auxiliary-keymap agent-workflow-list-mode-map 'normal) (kbd "RET"))
              #'agent-workflow-list-open)))

;; ====== THIS CONFIG'S OWN ======

(defun +test-awfc--dir (name)
  "A new, empty folder NAME in the temp folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awf/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun +test-awfc--file (dir name text)
  "A file NAME in DIR holding TEXT: its name."
  (let ((file (expand-file-name name dir)))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file file (insert text)))
    file))

(defun +test-awfc--dry-lines (result)
  "All RESULT's lines."
  (apply #'append (plist-get result :waves)))

(ert-deftest agent-workflow-config/this-config-s-samples ()
  "The workflows of this config (.agent-workflow/: github, screenshots,
their agents ci and screenshots) checked, no problem; each walked to its
end, its branch deleted once merged."
  (let ((agent-workflow--definitions-cache (make-hash-table :test #'equal))
        (agent-workflow--workflows-cache (make-hash-table :test #'equal)))
    (should-not (agent-workflow-check-problems +test-root))
    (let ((workflows (agent-workflow-workflows +test-root)))
      (should (equal (mapcar #'car (seq-filter (lambda (w) (eq (plist-get (cdr w) :origin) 'project)) workflows))
                     '("github" "screenshots")))
      (dolist (name '("github" "screenshots"))
        (ert-info (name :prefix "workflow: ")
          (let* ((workflow (cdr (assoc name workflows)))
                 (result (agent-workflow--dry-run workflow :info '(:id "demo-1" :type "task")
                                                 :definitions (agent-workflow-agent-definitions +test-root))))
            (should (equal (plist-get workflow :file)
                           (expand-file-name (format ".agent-workflow/workflows/%s.yml" name) +test-root)))
            (should-not (plist-get workflow :for))
            (should-not (plist-get result :stopped))
            (should (plist-get workflow :ticketless))
            (pcase name
              ;; In your checkout: no branch, nothing merged.
              ("github"
               (should (plist-get workflow :checkout))
               (should (equal (plist-get result :branch) "none: its commits are on your checkout's branch")))
              ;; No ticket: its merge merged, nothing to close.
              (_
               (should (member "merge: merged (no ticket to close)" (+test-awfc--dry-lines result)))
               (should (equal (plist-get result :branch) "deleted, merged into the main branch"))))))))
    (should (assoc "screenshots" (agent-workflow-agent-definitions +test-root)))
    (should (assoc "ci" (agent-workflow-agent-definitions +test-root)))))

;; github's scripts (check, push, watch): a stand-in gh (its runs and logs from
;; GH_RUNS, GH_PENDING, GH_LOGGED_OUT), a bare origin, a clone of it on main
;; standing in for your checkout and the issue's worktree.

(defun +test-awfc--gh (bin)
  "A stand-in gh in BIN: auth status fails with GH_LOGGED_OUT; run list
prints GH_RUNS (lines ID TAB STATUS TAB CONCLUSION TAB NAME, \\n between),
in_progress the first GH_PENDING times (counted in GH_COUNT); run view
prints a failed job's lines. Its arguments, a line each call, in GH_ARGS."
  (make-directory bin t)
  (let ((gh (expand-file-name "gh" bin)))
    (write-region "#!/bin/bash
[ -n \"$GH_ARGS\" ] && echo \"$*\" >> \"$GH_ARGS\"
case \"$1 $2\" in
  'auth status') [ -z \"$GH_LOGGED_OUT\" ] ;;
  'run list')
    n=$(cat \"$GH_COUNT\" 2>/dev/null || echo 0); echo $((n + 1)) > \"$GH_COUNT\"
    if [ \"$n\" -lt \"${GH_PENDING:-0}\" ]; then printf '1\\tin_progress\\t\\tTests\\n'
    else printf \"$GH_RUNS\"; fi ;;
  'run view') echo \"test-lexer.el: FAILED lexer/escapes\" ;;
  *) exit 3 ;;
esac
" nil gh)
    (set-file-modes gh #o755)
    gh))

(defun +test-awfc--github (name script &rest env)
  "SCRIPT (github-check.sh...) run in a clone on main of a bare origin (a
commit there), named NAME, ENV more of its environment (GH_RUNS ...) and
how it's set up (:ahead a commit origin hasn't, :behind origin one it
hasn't, :off-main, :no-remote, :no-gh, :logged-out; :workflows ((NAME .
TEXT)...) in .github/workflows/ and :message the message of origin's
commit): (EXIT OUTPUT CLONE ORIGIN), CLONE your checkout and its worktree."
  (let* ((dir (+test-awfc--dir name))
         (origin (expand-file-name "origin.git" dir))
         (clone (file-name-as-directory (expand-file-name "clone" dir)))
         (bin (expand-file-name "bin" dir))
         (git (lambda (where &rest args)
                (let ((default-directory where))
                  (apply #'call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" args)))))
    (funcall git dir "init" "-q" "--bare" "-b" "main" origin)
    (funcall git dir "clone" "-q" origin clone)
    (funcall git clone "checkout" "-q" "-b" "main")
    (+test-awfc--file clone "a.el" "one\n")
    (pcase-dolist (`(,name . ,text) (plist-get env :workflows))
      (+test-awfc--file clone (concat ".github/workflows/" name) text))
    (funcall git clone "add" "-A")
    (funcall git clone "commit" "-q" "-m" (or (plist-get env :message) "first"))
    (funcall git clone "push" "-q" "origin" "main")
    (+test-awfc--gh bin)
    (when (plist-get env :ahead)
      (+test-awfc--file clone "b.el" "two\n")
      (funcall git clone "add" "b.el")
      (funcall git clone "commit" "-q" "-m" "second"))
    (when (plist-get env :behind)
      (let ((other (expand-file-name "other" dir)))
        (funcall git dir "clone" "-q" origin other)
        (+test-awfc--file (file-name-as-directory other) "c.el" "theirs\n")
        (funcall git other "add" "c.el")
        (funcall git other "commit" "-q" "-m" "theirs")
        (funcall git other "push" "-q" "origin" "main")))
    (when (plist-get env :off-main)
      (funcall git clone "checkout" "-q" "-b" "other"))
    (when (plist-get env :no-remote)
      (funcall git clone "remote" "remove" "origin"))
    ;; Origin's URL a GitHub one, fetched from the bare origin all the same.
    (when-let* ((url (plist-get env :url)))
      (funcall git clone "remote" "set-url" "origin" url)
      (funcall git clone "config" (format "url.%s.insteadOf" origin) url))
    (with-temp-buffer
      (let* ((default-directory clone)
             (process-environment
              (append (list (concat "PATH=" (if (plist-get env :no-gh)
                                                   ;; Nothing: gh nowhere (the Linux runners have one in /usr/bin).
                                                   (let ((none (expand-file-name "none" dir))) (make-directory none t) none)
                                                 (concat bin ":" (getenv "PATH"))))
                            (concat "MAIN=" clone) "MAIN_BRANCH=main" "GITHUB_POLL=0"
                            (format "GITHUB_APPEAR=%s" (or (plist-get env :appear) 0))
                            (concat "GH_COUNT=" (expand-file-name "count" dir))
                            (concat "GH_ARGS=" (expand-file-name "args" dir))
                            (concat "GH_RUNS=" (or (plist-get env :runs) ""))
                            (format "GH_PENDING=%s" (or (plist-get env :pending) 0))
                            (concat "GH_LOGGED_OUT=" (if (plist-get env :logged-out) "1" "")))
                      process-environment))
             (exit (call-process "bash" nil t nil
                                 (expand-file-name (concat ".agent-workflow/scripts/" script) +test-root))))
        (list exit (string-trim (buffer-string)) clone origin)))))

(defun +test-awfc--origin-main (origin)
  "ORIGIN's main, its commit."
  (let ((default-directory origin))
    (string-trim (shell-command-to-string "git rev-parse main"))))

(ert-deftest agent-workflow-config/github-check-sh ()
  "github-check.sh: no gh, gh logged out, your checkout not on main, no
remote: the run fails (3), its last line why; else 0."
  (pcase-dolist (`(,name ,setup ,why)
                 '(("chk-none" (:no-gh t) "gh (GitHub's command line) isn't installed: brew install gh, then gh auth login")
                   ("chk-out" (:logged-out t) "gh isn't logged in to GitHub: gh auth login")
                   ("chk-off" (:off-main t) "your checkout is on other, not main: check out main, then run it again")
                   ("chk-remote" (:no-remote t) "no remote origin to push to")))
    (ert-info (name :prefix "case: ")
      (pcase-let ((`(,exit ,out) (apply #'+test-awfc--github name "github-check.sh" setup)))
        (should (eql exit 3))
        (should (equal (car (last (split-string out "\n"))) (concat "github-check.sh: " why))))))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "chk-ok" "github-check.sh")))
    (should (eql exit 0))
    (should (string-prefix-p "github-check.sh: gh logged in, your checkout on main, origin: " out))))

(ert-deftest agent-workflow-config/github-push-sh ()
  "github-push.sh: commits origin hasn't, pushed; none, said (0); origin
with commits yours hasn't, or your checkout off main: refused, the run
asks (2)."
  (pcase-let ((`(,exit ,out ,clone ,origin) (+test-awfc--github "push-ahead" "github-push.sh" :ahead t)))
    (should (eql exit 0))
    (should (string-match-p "pushed 1 commit(s): origin/main now" out))
    (should (equal (+test-awfc--origin-main origin)
                   (let ((default-directory clone)) (string-trim (shell-command-to-string "git rev-parse HEAD"))))))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "push-none" "github-push.sh")))
    (should (eql exit 0))
    (should (string-match-p "nothing to push: origin/main has" out)))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "push-refused" "github-push.sh" :ahead t :behind t)))
    (should (eql exit 2))
    (should (string-match-p "refused (origin/main has commits your main hasn't)" out)))
  ;; Your checkout moved off main meanwhile: not pushed.
  (pcase-let ((`(,exit ,out ,clone ,origin) (+test-awfc--github "push-off" "github-push.sh" :ahead t :off-main t)))
    (should (eql exit 2))
    (should (string-match-p "your checkout is on other now, not main" out))
    (should-not (equal (+test-awfc--origin-main origin)
                       (let ((default-directory clone)) (string-trim (shell-command-to-string "git rev-parse HEAD")))))))

(ert-deftest agent-workflow-config/github-watch-sh ()
  "github-watch.sh: origin's main's runs green: 0; one failed: 1, its
failed jobs' lines; still running: watched until done; none at all: 0,
said, if none was to run (no workflow runs on a push, or its message skips
them), else 2, the run asks (none was started: run 4 of the github
workflow went green, nothing checked); cancelled: 2."
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-green" "github-watch.sh"
                                                :runs "7\tcompleted\tsuccess\tTests\n8\tcompleted\tskipped\tLint\n")))
    (should (eql exit 0))
    (should (string-match-p "green: Tests, Lint passed" out)))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-fail" "github-watch.sh"
                                                :runs "8\tcompleted\tfailure\tTests\n9\tcompleted\tsuccess\tLint\n")))
    (should (eql exit 1))
    (should (string-match-p "GitHub Actions failed on main" out))
    (should (string-match-p "== Tests: failure (gh run view 8)" out))
    (should (string-match-p "FAILED lexer/escapes" out))
    (should-not (string-match-p "Lint:" out)))
  ;; Waiting: where they are said, once each time it changes.
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-wait" "github-watch.sh" :pending 2
                                                :runs "10\tcompleted\tsuccess\tTests\n9\tcompleted\tfailure\tLint\n"
                                                :appear 60)))
    (should (eql exit 1))
    (let ((lines (split-string out "\n")))
      (should (string-match-p "\\`[0-9a-f]\\{7\\}: 0 of 1 done · Tests …\\'" (nth 0 lines)))
      (should (string-match-p "\\`[0-9a-f]\\{7\\}: 2 of 2 done · Tests ✓ · Lint ✗\\'" (nth 1 lines)))
      (should (string-prefix-p "GitHub Actions failed on main" (nth 2 lines)))))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-late" "github-watch.sh" :pending 1
                                                :runs "10\tcompleted\tsuccess\tTests\n")))
    (should (eql exit 0))
    (should (string-match-p "green" out)))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-none" "github-watch.sh")))
    (should (eql exit 0))
    (should (string-match-p "no GitHub Actions run for [0-9a-f]\\{7\\} after 0s, and none runs on a push: nothing to check" out)))
  ;; A workflow running on a push (each way YAML says it), none started:
  ;; asked, the workflows named; one on other events only: nothing to check.
  (pcase-dolist (`(,name ,text)
                 '(("watch-expected-block" "name: Tests\non:\n  push:\n    branches: [main]\n  pull_request:\njobs: {}\n")
                   ("watch-expected-flow" "name: Tests\non: [push, pull_request]\njobs: {}\n")
                   ("watch-expected-word" "name: Tests\n\"on\": push\njobs: {}\n")
                   ("watch-expected-list" "name: Tests\non:\n  - pull_request\n  - push\njobs: {}\n")))
    (ert-info (name :prefix "case: ")
      (pcase-let ((`(,exit ,out) (+test-awfc--github name "github-watch.sh"
                                                    :workflows `(("tests.yml" . ,text) ("README.md" . "push:\n")))))
        (should (eql exit 2))
        (should (string-match-p "no GitHub Actions run for [0-9a-f]\\{7\\} after 0s, though tests.yml runs on a push: GitHub didn't start it" out)))))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-other-events" "github-watch.sh"
                                                :workflows '(("nightly.yaml" . "on:\n  schedule:\n    - cron: '0 3 * * *'\n  workflow_dispatch:\njobs: {}\n")))))
    (should (eql exit 0))
    (should (string-match-p "none runs on a push: nothing to check" out)))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-skipped" "github-watch.sh"
                                                :workflows '(("tests.yml" . "on: push\njobs: {}\n"))
                                                :message "Docs only [skip ci]")))
    (should (eql exit 0))
    (should (string-match-p "asks GitHub to skip its Actions (its message): nothing to check" out)))
  (pcase-let ((`(,exit ,out) (+test-awfc--github "watch-cancel" "github-watch.sh"
                                                :runs "11\tcompleted\tcancelled\tTests\n")))
    (should (eql exit 2))
    (should (string-match-p "was cancelled" out)))
  ;; gh asked about origin's own repository (-R), not its default one.
  (pcase-let ((`(,exit ,_out) (+test-awfc--github "watch-repo" "github-watch.sh" :url "git@github.com:me/doom.git"
                                                 :runs "8\tcompleted\tfailure\tTests\n")))
    (should (eql exit 1))
    (let ((calls (with-temp-buffer
                   (insert-file-contents (expand-file-name "awf/watch-repo/args" +test-tmp))
                   (split-string (buffer-string) "\n" t))))
      (should (string-prefix-p "run list -R github.com/me/doom --commit " (car calls)))
      (should (equal (cadr calls) "run view -R github.com/me/doom 8 --log-failed")))))
