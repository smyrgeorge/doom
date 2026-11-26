;;; tests/unit/test-agent-workflow-pick.el -*- lexical-binding: t; -*-
;; config/agent-workflow/queue.el's issue picker (M-x agent-workflow-run-ticket's
;; "Run on:"), keys typed into it, vertico on as in Doom and without it: a
;; title with a comma picked with RET (the comma no longer cutting it in
;; two), several separated by what no title has, an epic for its issues;
;; each issue drawn as the issue list draws it (config/beads/look.el): its
;; status, priority and type before it, its labels after. Stand-in issues: no
;; bd.

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(let ((build (file-name-directory (directory-file-name (file-name-directory (locate-library "vertico"))))))
  (dolist (package '("vertico" "orderless"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))
(+test-load "config/emacs" "config/tiling" "config/banner" "config/beads"
            "config/agent-workflow")

(require 'vertico)
(require 'orderless)
(setq completion-styles '(orderless basic))  ; as Doom
(require 'beads-faces)
(require 'doom-themes)                  ; doom-blend
(require 'nerd-icons)                   ; the types' icons

;; ====== HELPERS ======

(defun +test-awk--issue (id title type &rest more)
  "A stand-in open issue ID, as `agent-workflow-open-issues' has it: MORE
bd's other keys (status, priority, labels...) as a plist."
  (list id title type
        (append `((id . ,id) (title . ,title) (issue_type . ,type))
                (let (alist)
                  (while more
                    (push (cons (intern (substring (symbol-name (pop more)) 1)) (pop more)) alist))
                  (nreverse alist)))))

(defconst +test-awk--issues
  (list (+test-awk--issue "demo-1" "Parser rewrite" "epic" :status "open" :priority 1 :labels '("parser"))
        (+test-awk--issue "demo-2" "Examples: the screenshots taken again, each as it looks today" "chore"
                          :status "open" :priority 3 :labels '("workflow:quick"))
        (+test-awk--issue "demo-3" "Crash on an empty file" "bug" :status "in_progress" :priority 0)
        (+test-awk--issue "demo-4" "Release 2.0" "task" :status "open" :priority 2
                          :dependencies '(((type . "blocks") (depends_on_id . "demo-3")))))
  "Open issues: a title with a comma, an epic, one blocked by another.")

(defmacro +test-awk (&rest body)
  "BODY with `+test-awk--issues' as the project's open issues, demo-1's
issues demo-11 and demo-12."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'agent-workflow-open-issues) (lambda (_) +test-awk--issues))
             ((symbol-function 'agent-workflow-epic-issues)
              (lambda (_ id) (and (equal id "demo-1") '("demo-11" "demo-12")))))
     ,@body))

(defun +test-awk--pick (keys &optional vertico)
  "The issues picked by typing KEYS (`kbd' syntax) in the picker, with
VERTICO on: their ids, or (error MESSAGE)."
  (let* ((picked nil)
         (map (define-keymap "<f5>" (lambda () (interactive)
                                      (setq picked (condition-case err (agent-workflow--read-issues "/tmp/")
                                                     (user-error (list 'error (cadr err)))))))))
    (with-current-buffer (switch-to-buffer (get-buffer-create "*awk*"))
      (use-local-map map)
      (when vertico (vertico-mode 1))
      (unwind-protect
          (+test-awk (execute-kbd-macro (vconcat (kbd "<f5>") (kbd keys))))
        (when vertico (vertico-mode -1))
        (use-local-map nil)))
    picked))

;; ====== PICKING ======

(ert-deftest agent-workflow-pick/a-title-with-a-comma-picked-with-ret ()
  "RET on an issue whose title has a comma picks it: the prompt closes (it
only filled the input, never a match, a comma separating several)."
  (should (equal (+test-awk--pick "screenshots RET" t) '("demo-2")))
  (should (equal (+test-awk--pick "empty SPC file RET" t) '("demo-3"))))

(ert-deftest agent-workflow-pick/several-separated-by-what-no-title-has ()
  "Several picked, separated by ; when a title has a comma (the prompt says
so), by a comma when none has; an epic for its open issues."
  (should (equal (+test-awk--pick "crash TAB ; screenshots RET" t) '("demo-3" "demo-2")))
  (should (equal (+test-awk--pick "parser TAB ; release RET" t) '("demo-11" "demo-12" "demo-4")))
  (let ((+test-awk--issues (list (nth 2 +test-awk--issues) (nth 3 +test-awk--issues))))
    (should (equal (+test-awk--pick "crash TAB , release RET" t) '("demo-3" "demo-4"))))
  (should (equal (agent-workflow--separator '("demo-2  a, b" "demo-3  c")) "[ \t]*;[ \t]*"))
  (should (equal (get-text-property 0 'separator (agent-workflow--separator '("a, b; c"))) "|"))
  (should (equal (get-text-property 0 'description (agent-workflow--separator '("a"))) "comma-separated list")))

(ert-deftest agent-workflow-pick/without-vertico ()
  "Emacs's own completion: an issue completed with TAB, RET picks it, a
title with a comma too."
  (should (equal (+test-awk--pick "demo-2 TAB RET") '("demo-2")))
  (should (equal (+test-awk--pick "demo-3 TAB ; demo-2 TAB RET") '("demo-3" "demo-2"))))

(ert-deftest agent-workflow-pick/nothing-picked ()
  "RET on nothing typed, with vertico off: no issue, said."
  (should (equal (+test-awk--pick "RET") '(error "No issue picked"))))

;; ====== THE LOOK ======

(defun +test-awk--affixes ()
  "Each candidate's (NAME PREFIX SUFFIX), as the picker draws them, in its
order."
  (let (seen)
    (+test-awk
      (cl-letf (((symbol-function 'completing-read-multiple)
                 (lambda (_prompt table &rest _)
                   (let* ((names (all-completions "" table))
                          (metadata (completion-metadata "" table nil)))
                     (setq seen (funcall (completion-metadata-get metadata 'affixation-function) names))
                     (list (car names))))))
        (agent-workflow--read-issues "/tmp/")))
    seen))

(defun +test-awk--faces (string)
  "The faces in STRING, flattened (inherited ones too, as given)."
  (let (faces)
    (dotimes (i (length string))
      (let ((face (get-text-property i 'face string)))
        (dolist (face (if (and (listp face) (not (keywordp (car face)))) face (list face)))
          (when face (push face faces)))))
    faces))

(ert-deftest agent-workflow-pick/drawn-as-the-issue-list ()
  "Each issue as the list draws it: its status (blocked by an open issue:
⊘1), its priority (P0 a badge), its type's icon before its id and title (the
ids padded: the titles in a column); its labels as tags after, an epic said;
in bd's order."
  (let ((rows (+test-awk--affixes)))
    (should (equal (mapcar #'car rows)
                   '("demo-1  Parser rewrite"
                     "demo-2  Examples: the screenshots taken again, each as it looks today"
                     "demo-3  Crash on an empty file"
                     "demo-4  Release 2.0")))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 0 rows)))
      (should (string-match-p "\\`○  P1 " (substring-no-properties prefix)))
      (should (string-match-p "(epic: its issues)" suffix))
      (should (string-match-p " parser \\'" suffix))
      (should (+test-awk--faces suffix)))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 1 rows)))
      (should (string-match-p "\\`○  P3 " (substring-no-properties prefix)))
      (should (memq 'shadow (+test-awk--faces prefix)))
      (should (string-match-p " workflow:quick \\'" suffix)))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 2 rows)))
      (should (string-match-p "\\`◔  P0 " (substring-no-properties prefix)))
      (should (memq 'beads-status-in-progress (+test-awk--faces prefix)))
      (should (equal suffix "")))
    (pcase-let ((`(,_ ,prefix ,_) (nth 3 rows)))
      (should (string-match-p "\\`⊘1 P2 " (substring-no-properties prefix)))
      (should (memq 'beads-status-blocked (+test-awk--faces prefix))))))

(ert-deftest agent-workflow-pick/without-the-issue-list ()
  "config/beads/look.el not loaded: no status, priority or type before an
issue; its labels after, muted."
  (cl-letf (((symbol-function '+my/beads-format-status) nil))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 1 (+test-awk--affixes))))
      (should (equal prefix ""))
      (should (equal (substring-no-properties suffix) "  workflow:quick"))
      (should (memq 'shadow (+test-awk--faces suffix))))))

;; ====== ITS WORKFLOW ======

(defconst +test-awk--workflows
  '(("mine" :origin local :description "My own" :for ("feature") :jobs (("build")))
    ("github" :origin project :description "Pushed" :ticketless t :jobs (("green")))
    ("ours" :origin project :description "The project's" :for ("bug") :jobs (("fix") ("review")))
    ("feature" :origin starter :description "A feature, built with its tests" :for ("feature" "task")
     :jobs (("build") ("review") ("merge")))
    ("bugfix" :origin starter :description "A bug" :for ("bug") :jobs (("reproduce") ("fix"))))
  "Workflows of every origin, one with no ticket.")

(defun +test-awk--rows (info &optional width)
  (cl-letf (((symbol-function 'agent-workflow-workflows) (lambda (_) +test-awk--workflows)))
    (agent-workflow--workflow-rows "/tmp/" info (or width 120))))

(ert-deftest agent-workflow-pick/its-workflow-s-rows ()
  "Every workflow taking a ticket (one with none left out), grouped by
where it comes from (yours, the project's, the starters), those that fit
the issue first in each: ● and their types in green; the others ○, dimmed.
Its workflow:NAME label: that one alone fits, said."
  (let ((rows (+test-awk--rows '(:type "feature"))))
    (should (equal (mapcar #'car rows) '("mine" "ours" "feature" "bugfix")))
    (should (equal (mapcar (lambda (row) (nth 3 row)) rows) '(local project starter starter)))
    (should (equal (mapcar (lambda (row) (nth 4 row)) rows) '(t nil t nil)))
    (pcase-let ((`(,_ ,prefix ,suffix) (assoc "feature" rows)))
      (should (equal (substring-no-properties prefix) "● "))
      (should (string-match-p "A feature, built with its tests +build · review · merge +for feature, task"
                              (substring-no-properties suffix)))
      (should (memq 'success (+test-awk--faces suffix))))
    (pcase-let ((`(,_ ,prefix ,suffix) (assoc "bugfix" rows)))
      (should (equal (substring-no-properties prefix) "○ "))
      (should (memq 'shadow (+test-awk--faces suffix)))))
  (let ((rows (+test-awk--rows '(:type "feature" :labels ("workflow:bugfix")))))
    (should (equal (mapcar #'car (seq-filter (lambda (row) (nth 4 row)) rows)) '("bugfix")))
    (should (string-search "its workflow:bugfix" (nth 2 (assoc "bugfix" rows))))))

(ert-deftest agent-workflow-pick/its-workflow-s-rows-narrow ()
  "Narrow: its jobs dropped first, then its types; its description cut
with …; never wider than the width."
  (let ((rows (+test-awk--rows '(:type "feature") 50)))
    (should-not (string-search "review · merge" (nth 2 (assoc "feature" rows))))
    (dolist (row rows)
      (should (<= (+ 2 (string-width (car row)) (string-width (nth 2 row))) 50)))))

(ert-deftest agent-workflow-pick/its-workflow-always-asked ()
  "Its workflow always asked, even when one alone fits: the first that fits
selected, RET taking it."
  (cl-letf (((symbol-function 'agent-workflow-workflows) (lambda (_) +test-awk--workflows))
            ((symbol-function 'agent-workflow-issue) (lambda (&rest _) '(:type "bug" :title "Crash"))))
    (let* ((asked nil)
           (picked nil)
           (map (define-keymap "<f5>" (lambda () (interactive)
                                        (setq picked (agent-workflow--read-workflow "/tmp/" "demo-3"))))))
      (with-current-buffer (switch-to-buffer (get-buffer-create "*awk*"))
        (use-local-map map)
        (vertico-mode 1)
        (unwind-protect
            (minibuffer-with-setup-hook (lambda () (setq asked (minibuffer-prompt)))
              (execute-kbd-macro (vconcat (kbd "<f5>") (kbd "RET"))))
          (vertico-mode -1)
          (use-local-map nil)))
      (should (equal asked "Workflow for demo-3 (a bug: Crash): "))
      (should (equal picked "ours")))))

;; ====== A WORKFLOW WITHOUT A TICKET, A DRY RUN ======

(defconst +test-awk--more-workflows
  (append '(("deploy" :origin local :description "Deployed from here" :ticketless t :jobs (("ship") ("check")))
            ("nightly" :origin starter :description "Every night" :ticketless t :jobs (("all"))))
          +test-awk--workflows)
  "Workflows that run without a ticket of each origin, and those that take one.")

(defun +test-awk--picker (command)
  "What COMMAND (interactively) asks to pick from: (PROMPT NAMES ROWS
GROUPS), ROWS each (NAME PREFIX SUFFIX) as its affixation function gives
them, GROUPS each name's divider."
  (cl-letf (((symbol-function 'agent-workflow-workflows) (lambda (_) +test-awk--more-workflows))
            ((symbol-function 'agent-workflow-project) (lambda (&rest _) "/tmp/"))
            ((symbol-function 'completing-read)
             (lambda (prompt names &rest _)
               (let ((props completion-extra-properties))
                 (throw 'asked (list prompt names
                                     (funcall (plist-get props :affixation-function) names)
                                     (mapcar (lambda (name) (funcall (plist-get props :group-function) name nil))
                                             names)))))))
    (catch 'asked (call-interactively command))))

(ert-deftest agent-workflow-pick/run-s-rows ()
  "M-x agent-workflow-run: the workflows that run without a ticket, as the
ticket's picker has them: a row of columns each (▶, its name, its
description, its jobs, lined up), grouped by where it comes from (yours,
the project's, the starters), none dimmed."
  (pcase-let ((`(,prompt ,names ,rows ,groups) (+test-awk--picker #'agent-workflow-run)))
    (should (equal prompt "Run the workflow: "))
    (should (equal names '("deploy" "github" "nightly")))
    (should (equal groups (mapcar #'agent-workflow--workflow-group-title '(local project starter))))
    (pcase-dolist (`(,candidate ,prefix ,_) rows)
      (should (equal (substring-no-properties prefix) "▶ "))
      (should-not (memq 'shadow (+test-awk--faces candidate))))
    (let ((lines (mapcar (lambda (row) (substring-no-properties (concat (nth 0 row) (nth 2 row)))) rows)))
      (should (string-match-p "\\`deploy +Deployed from here +ship · check\\'" (nth 0 lines)))
      (should (string-match-p "\\`github +Pushed +green\\'" (nth 1 lines)))
      ;; Lined up: the descriptions start in one column, the jobs in another.
      (should (= (string-search "Deployed" (nth 0 lines)) (string-search "Pushed" (nth 1 lines))
                 (string-search "Every" (nth 2 lines))))
      (should (= (string-search "ship" (nth 0 lines)) (string-search "green" (nth 1 lines)))))))

(ert-deftest agent-workflow-pick/dry-run-s-rows ()
  "M-x agent-workflow-dry-run: every workflow, in rows as agent-workflow-run's,
grouped, the tickets each takes said (for its types; no ticket)."
  (pcase-let ((`(,prompt ,names ,rows ,_) (+test-awk--picker #'agent-workflow-dry-run)))
    (should (equal prompt "Dry run of the workflow: "))
    (should (equal names '("deploy" "mine" "github" "ours" "nightly" "feature" "bugfix")))
    (should (string-search "no ticket" (nth 2 (nth (seq-position names "github") rows))))
    (should (string-search "for feature, task" (nth 2 (nth (seq-position names "feature") rows))))
    (should (equal (substring-no-properties (nth 1 (car rows))) "▶ "))))
