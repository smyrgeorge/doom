;;; tests/unit/test-agent-workspace-new.el -*- lexical-binding: t; -*-
;; config/agent-workspace/new.el and request.el, with cmd/agent-workspace:
;; making an agent. Its name made from the pool, what you're asked, made from
;; an issue, a failing step said; from the shell. In throwaway git
;; repositories; no session starts (test-agent-workspace-session.el runs them).

(require 'server)

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-workspace")
(load (expand-file-name "../helper-agent-workspace" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defconst +test-awn-script (expand-file-name "cmd/agent-workspace" +test-root))

;; ====== HELPERS ======

(defun +test-awn--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awn--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awn/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awn--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (+test-awn--git "add" "README")
      (+test-awn--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awn (name &rest body)
  "BODY in a new project NAME (`project', `default-directory'), with crews of
its own and no session started: an agent's start leaves it at the desk;
`started' lists the agents started, `sent' what they were sent."
  (declare (indent 1))
  `(let* ((project (+test-awn--project ,name))
          (default-directory project)
          (agent-workspace--crews (make-hash-table :test #'equal))
          (started nil)
          (sent nil))
     (ignore started sent)
     (cl-letf (((symbol-function 'agent-workspace--start)
                (lambda (agent)
                  (push (agent-workspace-agent-name agent) started)
                  (setf (agent-workspace-agent-state agent) 'desk)
                  t))
               ((symbol-function 'agent-workspace-send)
                (lambda (agent text &rest args)
                  (push (list (agent-workspace-agent-name agent) text args) sent)
                  'sent)))
       ,@body)))

(defun +test-awn--agent (project name &optional role state)
  "An agent record NAME (ROLE, STATE) put in PROJECT's crew."
  (let ((agent (agent-workspace--make-agent :name name :role (or role "builder") :colour "blue"
                                            :state (or state 'desk) :project project)))
    (puthash project (append (gethash project agent-workspace--crews) (list agent))
             agent-workspace--crews)
    agent))

(defmacro +test-awn--answering (answers &rest body)
  "BODY with the minibuffer's questions answered with ANSWERS, in order
\(`completing-read' and `read-string' alike); `asked' lists their prompts."
  (declare (indent 1))
  `(let ((answers ,answers)
         (asked nil))
     (cl-letf* ((answer (lambda (prompt &rest _)
                          (push prompt asked)
                          (or (pop answers) (error "Asked more: %s" prompt))))
                ((symbol-function 'completing-read) answer)
                ((symbol-function 'read-string) answer)
                ((symbol-function 'sit-for) #'ignore))
       ,@body)))

;; ====== A NAME ======

(ert-deftest agent-workspace-new/names ()
  "A name is typed after # in the room: a lowercase letter, then lowercase
letters, digits or -."
  (dolist (name '("ada" "builder-3" "a" "x2" "abcdefghijabcdefghij"))
    (should (agent-workspace-name-valid-p name)))
  (dolist (name '("Ada" "x_y" "3ada" "-ada" "ada lovelace" "abcdefghijabcdefghijk" "ádá" ""))
    (should-not (agent-workspace-name-valid-p name))))

(ert-deftest agent-workspace-new/a-name-from-the-pool ()
  "The pool's first name not in use, whose initial no agent has, not left by
a forgotten agent; none left, its role and a number."
  (+test-awn "pool"
    (should (equal (agent-workspace-pool-name project "builder") "ada"))
    (+test-awn--agent project "ada")
    (should (equal (agent-workspace-pool-name project "builder") "grace"))
    ;; An initial taken: george has g, so grace is passed over.
    (+test-awn--agent project "george")
    (should (equal (agent-workspace-pool-name project "builder") "linus"))
    ;; Left by a forgotten agent: its branch, or its worktree.
    (+test-awn--git "branch" "agent/linus")
    (make-directory (expand-file-name ".agent-shell/worktrees/builder-ken" project) t)
    (should (equal (agent-workspace-pool-name project "builder") "margaret"))
    ;; The pool run out.
    (let ((agent-workspace-names '("ada" "grace")))
      (should (equal (agent-workspace-pool-name project "builder") "builder-1"))
      (+test-awn--agent project "builder-1")
      (+test-awn--git "branch" "agent/builder-2")
      (should (equal (agent-workspace-pool-name project "builder") "builder-3")))))

;; ====== WHAT YOU'RE ASKED ======

(defun +test-awn--rows (project width &optional names)
  "The role picker's rows for PROJECT's roles (or NAMES), WIDTH columns
wide, as shown: icon, name, the rest; each (NAME . TEXT)."
  (mapcar (lambda (row) (cons (car row) (substring-no-properties (concat (nth 2 row) (nth 1 row) (nth 3 row)))))
          (agent-workspace--role-rows
           (agent-workspace--role-facts project (or names (mapcar #'car (agent-workspace-roles project))))
           width)))

(defun +test-awn--crew-of-three (project)
  "ada and sam (scribe: its max) at work in PROJECT's crew, ken asleep."
  (+test-awn--agent project "ada" "builder")
  (+test-awn--agent project "ken" "builder" 'asleep)
  (+test-awn--agent project "sam" "scribe"))

(ert-deftest agent-workspace-new/the-role-picker-s-columns ()
  "Each role a row of columns lined up from row to row: its icon (its
glyph in a terminal), name, description, how many run of its max, its model
\(none: your default), its mode (none: auto), its labels, who it hands its
issues to; a role without labels or hands-to, nothing there; one at its max,
dimmed, \"at its max\" in place of its last columns."
  (+test-aw-with-four-starters
    (+test-awn "columns"
      (+test-awn--crew-of-three project)
      (let ((default-directory project))
        (make-directory ".agent-workspace/roles" t)
        (write-region "---\ndescription: triages\nmodel: haiku\nmode: plan\n---\nTriage.\n" nil
                      ".agent-workspace/roles/triager.md")
        (write-region "---\ndescription: tidies\n---\nTidy.\n" nil ".agent-workspace/roles/tidier.md"))
      (should (equal (mapcar #'cdr (+test-awn--rows project 200))
                     '("⚙ builder       builds what you give it           1 of 4  your default  auto  build                    → reviewer"
                       "⌕ investigator  investigates what you give it     0 of 2  your default  auto  investigation, incident  → builder"
                       "◎ reviewer      reviews a branch you point it to  0 of 2  your default  auto  review                   → builder"
                       "✎ scribe        writes issues with you            1 of 1  at its max"
                       "▶ tidier        tidies                                    your default  auto"
                       "▶ triager       triages                                   haiku         plan")))
      ;; Their faces: the icon its colour, the count the text's, the rest
      ;; dimmed; the role at its max, all of it.
      (pcase-let ((`(_ ,name ,icon ,rest ,_) (car (agent-workspace--role-rows
                                                   (agent-workspace--role-facts project '("builder" "scribe")) 200))))
        (should (equal (get-text-property 0 'face icon)
                       (list :foreground (face-foreground 'ansi-color-blue nil t))))
        (should-not (get-text-property 0 'face name))
        (should-not (get-text-property (string-search "1 of 4" rest) 'face rest))
        (should (eq (get-text-property (string-search "your default" rest) 'face rest) 'shadow)))
      (pcase-let ((`(_ ,name ,icon ,rest ,_) (cadr (agent-workspace--role-rows
                                                    (agent-workspace--role-facts project '("builder" "scribe")) 200))))
        (should (memq 'shadow (ensure-list (get-text-property 0 'face name))))
        (should (eq (get-text-property 0 'face icon) 'shadow))
        (should (memq 'shadow (ensure-list (get-text-property (string-search "at its max" rest) 'face rest))))))))

(ert-deftest agent-workspace-new/the-role-picker-narrower ()
  "In a narrower minibuffer, columns go from the right: hands-to, then the
labels (at 80 columns), the mode, the model; the description cut with …
last; icon, name and count always there; no row wider than it."
  (+test-aw-with-four-starters
    (+test-awn "narrower"
      (+test-awn--crew-of-three project)
      (should (equal (mapcar #'cdr (+test-awn--rows project 80))
                     '("⚙ builder       builds what you give it           1 of 4  your default  auto"
                       "⌕ investigator  investigates what you give it     0 of 2  your default  auto"
                       "◎ reviewer      reviews a branch you point it to  0 of 2  your default  auto"
                       "✎ scribe        writes issues with you            1 of 1  at its max")))
      (should (equal (mapcar #'cdr (+test-awn--rows project 74))
                     '("⚙ builder       builds what you give it           1 of 4  your default"
                       "⌕ investigator  investigates what you give it     0 of 2  your default"
                       "◎ reviewer      reviews a branch you point it to  0 of 2  your default"
                       "✎ scribe        writes issues with you            1 of 1  at its max")))
      (should (equal (mapcar #'cdr (+test-awn--rows project 60))
                     '("⚙ builder       builds what you give it   1 of 4"
                       "⌕ investigator  investigates what you g…  0 of 2"
                       "◎ reviewer      reviews a branch you po…  0 of 2"
                       "✎ scribe        writes issues with you    1 of 1  at its max")))
      ;; Narrower still: down to its icon, name and count (at its max: the
      ;; row dimmed says it).
      (should (equal (mapcar #'cdr (+test-awn--rows project 30))
                     '("⚙ builder       build…  1 of 4" "⌕ investigator  inves…  0 of 2"
                       "◎ reviewer      revie…  0 of 2" "✎ scribe        write…  1 of 1")))
      (should (equal (mapcar #'cdr (+test-awn--rows project 24))
                     '("⚙ builder       1 of 4" "⌕ investigator  0 of 2" "◎ reviewer      0 of 2" "✎ scribe        1 of 1")))
      (dolist (width '(200 113 100 80 74 60 50 40 34 30 24 22))
        (dolist (row (+test-awn--rows project width))
          (should (<= (string-width (cdr row)) width))
          (should (string-match-p (format "\\`. %s +.*[0-9] of [0-9]" (car row)) (cdr row))))))))

(ert-deftest agent-workspace-new/the-role-picker-s-ready-issues ()
  "After a role's labels, how many issues the app's issue list has ready
for it; none fetched (no app), nothing."
  (+test-awn "ready"
    (should-not (string-search "ready" (cdr (assoc "builder" (+test-awn--rows project 200)))))
    (cl-letf (((symbol-function 'agent-workspace-issues-ready)
               (lambda (_project) '((:id "p-1" :role "builder") (:id "p-2" :role "builder")
                                    (:id "p-3" :role "reviewer") (:id "p-4" :role nil)))))
      (let ((rows (+test-awn--rows project 200)))
        (should (string-search "  build ·2 ready  " (cdr (assoc "builder" rows))))
        (should (string-search "  review ·1 ready" (cdr (assoc "reviewer" rows))))
        (should-not (string-search "ready" (cdr (assoc "investigator" rows))))))))

(ert-deftest agent-workspace-new/the-role-picker-s-icons ()
  "A role's icon: its nerd icon in the GUI, its glyph in a terminal, ▶
without one; a column, then a space, before its name."
  (+test-awn "icons"
    (let ((facts (agent-workspace--role-facts project '("builder"))))
      (should (equal (substring-no-properties (nth 2 (car (agent-workspace--role-rows facts 200)))) "⚙ "))
      (skip-unless (require 'nerd-icons nil t))
      (cl-letf (((symbol-function 'agent-workspace--graphic-p) #'always)
                ;; Its font installed (batch Emacs has none).
                ((symbol-function 'agent-workspace--nerd-font-p) #'always))
        (let ((icon (nth 2 (car (agent-workspace--role-rows facts 200)))))
          (should (equal (substring-no-properties icon)
                         (concat (substring-no-properties (nerd-icons-mdicon "nf-md-hammer")) " "))))))))

(ert-deftest agent-workspace-new/the-role-picker-reads-nothing ()
  "The picker's rows, as the completion UI asks for them (moving through
the list, the minibuffer resized), with its crews too: nothing read from
disk, nothing run."
  (+test-aw-with-four-starters
    (+test-awn "nothing"
      (+test-awn--crew-of-three project)
      (let ((touched nil))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt roles &rest _)
                     (let ((affix (plist-get completion-extra-properties :affixation-function))
                           (spy (lambda (&rest args) (push args touched))))
                       (dolist (fn '(agent-workspace--roles-read agent-workspace--crew-specs-read
                                                                 file-attributes insert-file-contents
                                                                 directory-files call-process make-process))
                         (advice-add fn :before spy '((name . +test-awn-spy))))
                       (unwind-protect
                           (progn
                             (dotimes (_ 3)
                               (should (equal (mapcar #'car (funcall affix roles)) roles)))
                             ;; What the completion UI gives: (CANDIDATE PREFIX SUFFIX), the
                             ;; candidate as it gave it (its matches highlighted), dimmed
                             ;; at its max.
                             (let ((rows (funcall affix (list (propertize "builder" 'face 'completions-common-part)
                                                              "scribe"))))
                               (should (string-match-p "\\`builds what you give it +1 of 4"
                                                       (string-trim (substring-no-properties (nth 2 (car rows))))))
                               (should (eq (get-text-property 0 'face (car (car rows))) 'completions-common-part))
                               (should (memq 'shadow (ensure-list (get-text-property 0 'face (car (cadr rows))))))))
                         (dolist (fn '(agent-workspace--roles-read agent-workspace--crew-specs-read
                                                                   file-attributes insert-file-contents
                                                                   directory-files call-process make-process))
                           (advice-remove fn '+test-awn-spy))))
                     "builder")))
          (should (equal (agent-workspace-read-role project) "builder"))
          (should (equal (agent-workspace-read-role-or-crew project) "builder"))
          (should-not touched))))))

(ert-deftest agent-workspace-new/a-full-role-refused ()
  "A role at its max is refused, and asked again; the role given is
offered first, where it is in its group; an empty answer is it."
  (+test-aw-with-four-starters
    (+test-awn "full"
      (+test-awn--agent project "sam" "scribe")
      (+test-awn--answering '("scribe" "investigator")
        (let ((collection nil))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (prompt roles &rest args)
                       (push prompt asked)
                       (setq collection roles)
                       (should (equal (nth 4 args) "reviewer"))
                       (pop answers))))
            (should (equal (agent-workspace-read-role project "reviewer") "investigator"))
            (should (equal collection '("builder" "investigator" "reviewer" "scribe")))
            (should (= (length asked) 2)))))
      (+test-awn--answering '("")
        (should (equal (agent-workspace-read-role project "reviewer") "reviewer"))))))

(ert-deftest agent-workspace-new/the-lead-one-per-crew ()
  "c's menu offers the starter lead, one per crew: with one in it, a second
is refused and asked again."
  (let ((agent-workspace--roles-cache (make-hash-table :test #'equal)))
    (+test-awn "lead"
      (let ((collection nil))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt roles &rest _) (setq collection roles) "lead")))
          (should (equal (agent-workspace-read-role project) "lead")))
        (should (member "lead" collection)))
      (+test-awn--agent project "max" "lead")
      (+test-awn--answering '("lead" "scribe")
        (should (equal (agent-workspace-read-role project) "scribe"))
        (should (= (length asked) 2))))))

(defun +test-awn--four-kinds (project)
  "PROJECT's roles of all four kinds: a local one of its own (mine), a local
one replacing the project's (tester) and one replacing a starter
\(reviewer), a project's one replacing a starter (builder), the other
starters, and two files left out (broken; a local scribe, named as the
starter it fails to replace)."
  (let ((own (expand-file-name ".agent-workspace/roles/" project))
        (local (expand-file-name ".agent-shell/agent-workspace/roles/" project)))
    (make-directory own t)
    (make-directory local t)
    (write-region "---\ndescription: makes things\n---\n" nil (expand-file-name "builder.md" own))
    (write-region "---\ndescription: tests\nlabels: test\n---\n" nil (expand-file-name "tester.md" own))
    (write-region "---\ndescription: my tests\nlabels: test\n---\n" nil (expand-file-name "tester.md" local))
    (write-region "---\ndescription: my reviews\n---\n" nil (expand-file-name "reviewer.md" local))
    (write-region "---\ndescription: mine\n---\n" nil (expand-file-name "mine.md" local))
    (write-region "---\ndescription: broken\nmode: autoo\n---\n" nil (expand-file-name "broken.md" own))
    (write-region "---\nmax: lots\n---\n" nil (expand-file-name "scribe.md" local))))

(defmacro +test-awn--no-warnings (&rest body)
  "BODY, its warnings not shown."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'display-warning) #'ignore)) ,@body))

(ert-deftest agent-workspace-new/the-role-picker-s-groups ()
  "The roles grouped by where they come from (local, project, starters),
then the role files left out; a replaced role says so at its row's end, the
one it replaced not listed; a left-out file: ✗, its first error in place of
what it does, dimmed, named ORIGIN/NAME when a role listed has its name;
the columns lined up across the groups."
  (+test-aw-with-four-starters
    (+test-awn "groups"
      (+test-awn--four-kinds project)
      (+test-awn--no-warnings
        (let ((facts (agent-workspace--role-picker project)))
          (should (equal (mapcar (lambda (fact) (cons (car fact) (agent-workspace--role-group fact))) facts)
                         '(("reviewer" . local) ("tester" . local) ("mine" . local)
                           ("builder" . project)
                           ("investigator" . starter) ("scribe" . starter)
                           ("broken" . out) ("local/scribe" . out))))
          (should (equal (mapcar #'agent-workspace--role-group-title agent-workspace--role-groups)
                         '("local · .agent-shell/agent-workspace/roles" "project · .agent-workspace/roles"
                           "starters" "crews" "left out")))
          (should (equal (mapcar (lambda (row) (substring-no-properties (concat (nth 2 row) (nth 1 row) (nth 3 row))))
                                 (agent-workspace--role-rows facts 200))
                         '("▶ reviewer      my reviews                             your default  auto                                      replaces the starter"
                           "▶ tester        my tests                               your default  auto  test                                replaces the project's"
                           "▶ mine          mine                                   your default  auto"
                           "▶ builder       makes things                           your default  auto                                      replaces the starter"
                           "⌕ investigator  investigates what you give it  0 of 2  your default  auto  investigation, incident  → builder"
                           "✎ scribe        writes issues with you         0 of 1  your default  auto"
                           "✗ broken        line 3: mode autoo: not one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions"
                           "✗ local/scribe  line 1: no description: say what it does (description: ...)")))
          ;; Narrower: the role replaced goes first, then hands-to; a left-out
          ;; file's error cut to fit; no row wider than the minibuffer.
          (should (equal (mapcar (lambda (row) (substring-no-properties (concat (nth 2 row) (nth 1 row) (nth 3 row))))
                                 (agent-workspace--role-rows facts 100))
                         '("▶ reviewer      my reviews                             your default  auto"
                           "▶ tester        my tests                               your default  auto  test"
                           "▶ mine          mine                                   your default  auto"
                           "▶ builder       makes things                           your default  auto"
                           "⌕ investigator  investigates what you give it  0 of 2  your default  auto  investigation, incident"
                           "✎ scribe        writes issues with you         0 of 1  your default  auto"
                           "✗ broken        line 3: mode autoo: not one of default, acceptEdits, plan, auto, dontAsk, bypassPer…"
                           "✗ local/scribe  line 1: no description: say what it does (description: ...)")))
          (dolist (width '(200 140 100 80 60 40 30 24))
            (dolist (row (agent-workspace--role-rows facts width))
              (should (<= (string-width (substring-no-properties (concat (nth 2 row) (nth 1 row) (nth 3 row))))
                          width))))
          ;; A left-out row: its icon, name and the rest dimmed.
          (pcase-let ((`(_ ,name ,icon ,rest ,dim) (assoc "broken" (agent-workspace--role-rows facts 200))))
            (should dim)
            (should (memq 'shadow (ensure-list (get-text-property 0 'face name))))
            (should (eq (get-text-property 0 'face icon) 'shadow))
            (should (memq 'shadow (ensure-list (get-text-property (string-search "line 3" rest) 'face rest)))))
          ;; The role replaced, dimmed.
          (let ((rest (nth 3 (assoc "builder" (agent-workspace--role-rows facts 200)))))
            (should (eq (get-text-property (string-search "replaces" rest) 'face rest) 'shadow))))))))

(ert-deftest agent-workspace-new/the-role-picker-s-dividers ()
  "The completion is told its groups (each its divider's title) and to keep
their order; the default is selected where it is: under vertico, given as
none (vertico would move it to the top, out of its group)."
  (+test-aw-with-four-starters
    (+test-awn "dividers"
      (+test-awn--four-kinds project)
      (+test-awn--no-warnings
        (let (seen)
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt roles &rest args)
                       (let ((group (plist-get completion-extra-properties :group-function)))
                         (setq seen (list (mapcar (lambda (role) (funcall group role nil)) roles)
                                          (funcall group "builder" 'transform)
                                          (funcall (plist-get completion-extra-properties :display-sort-function)
                                                   (reverse roles))
                                          (nth 4 args))))
                       "mine")))
            (should (equal (agent-workspace-read-role project "builder") "mine"))
            (should (equal (car seen)
                           '("local · .agent-shell/agent-workspace/roles" "local · .agent-shell/agent-workspace/roles"
                             "local · .agent-shell/agent-workspace/roles" "project · .agent-workspace/roles"
                             "starters" "starters" "left out" "left out")))
            (should (equal (nth 1 seen) "builder"))
            (should (equal (nth 2 seen) (reverse '("reviewer" "tester" "mine" "builder" "investigator" "scribe"
                                                   "broken" "local/scribe"))))
            (should (equal (nth 3 seen) "builder"))
            (dlet ((vertico-mode t))
              (agent-workspace-read-role project "builder")
              (should-not (nth 3 seen)))))))))

(ert-deftest agent-workspace-new/a-left-out-role-refused ()
  "A role file left out is refused, naming its file and line, and asked
again; never offered first."
  (+test-aw-with-four-starters
    (+test-awn "left-out"
      (+test-awn--four-kinds project)
      (+test-awn--no-warnings
        (let ((messages nil))
          (cl-letf (((symbol-function 'message)
                     (lambda (format &rest args) (push (apply #'format format args) messages))))
            (+test-awn--answering '("broken" "")
              (should (equal (agent-workspace-read-role project "broken") "reviewer"))
              (should (= (length asked) 2))))
          (should (string-match-p
                   "\\`Left out: .*/\\.agent-workspace/roles/broken\\.md:3: mode autoo: not one of"
                   (car (last messages)))))))))

;; ====== CREWS IN THE MENU ======

(defun +test-awn--three-crews (project)
  "PROJECT's own crews: pair (in place of the starter), scribe (named as a
role) and broken (left out)."
  (let ((own (expand-file-name ".agent-workspace/crews/" project)))
    (make-directory own t)
    (write-region "---\ndescription: mine, with a long description for once\nagents: builder 3\n---\n" nil
                  (expand-file-name "pair.md" own))
    (write-region "---\ndescription: named as a role\nagents: scribe\n---\n" nil (expand-file-name "scribe.md" own))
    (write-region "---\ndescription: broken\nagents: wizard\n---\n" nil (expand-file-name "broken.md" own))))

(defun +test-awn--crew-rows (facts width)
  "The picker's rows for FACTS, WIDTH columns wide, as shown."
  (mapcar (lambda (row) (substring-no-properties (concat (nth 2 row) (nth 1 row) (nth 3 row))))
          (agent-workspace--role-rows facts width)))

(ert-deftest agent-workspace-new/the-crews-in-the-menu ()
  "With crews: a section of them after the roles' groups, before the files
left out (a crew file's among them): the local ones, the project's, then
the starters. A row each: its icon, its name (crew/NAME when a role has
it), its description in the roles' column, then its agents, what it would
add and where it comes from, lined up; nothing to add: dimmed, saying so.
Narrower: where it comes from goes first, then its agents; what it would
add is cut last; no row wider than the minibuffer."
  (+test-aw-with-four-starters
    (+test-awn "crews"
      (+test-awn--agent project "ada" "scribe")
      (+test-awn--three-crews project)
      (+test-awn--no-warnings
        (let ((facts (agent-workspace--role-picker project t)))
          (should (equal (mapcar (lambda (fact) (cons (car fact) (agent-workspace--role-group fact))) facts)
                         '(("builder" . starter) ("investigator" . starter) ("reviewer" . starter)
                           ("scribe" . starter) ("crew/scribe" . crew) ("pair" . crew) ("review" . crew)
                           ("broken" . out))))
          (should (equal (agent-workspace--role-group-title 'crew) "crews"))
          (should (equal (+test-awn--crew-rows facts 200)
                         '("⚙ builder       builds what you give it                 0 of 4  your default  auto  build                    → reviewer"
                           "⌕ investigator  investigates what you give it           0 of 2  your default  auto  investigation, incident  → builder"
                           "◎ reviewer      reviews a branch you point it to        0 of 2  your default  auto  review                   → builder"
                           "✎ scribe        writes issues with you                  1 of 1  at its max"
                           "⁂ crew/scribe   named as a role                         scribe                       nothing to add         project"
                           "⁂ pair          mine, with a long description for once  builder 3                    + builder 3            project, replaces the starter"
                           "⁂ review        write, build, review                    scribe, builder 2, reviewer  + builder 2, reviewer"
                           "✗ broken        line 3: agents wizard: no such role (builder, investigator, reviewer, scribe)")))
          (should (equal (+test-awn--crew-rows facts 100)
                         '("⚙ builder       builds what you give it                 0 of 4  your default  auto"
                           "⌕ investigator  investigates what you give it           0 of 2  your default  auto"
                           "◎ reviewer      reviews a branch you point it to        0 of 2  your default  auto"
                           "✎ scribe        writes issues with you                  1 of 1  at its max"
                           "⁂ crew/scribe   named as a role                         nothing to add"
                           "⁂ pair          mine, with a long description for once  + builder 3"
                           "⁂ review        write, build, review                    + builder 2, reviewer"
                           "✗ broken        line 3: agents wizard: no such role (builder, investigator, reviewer, scribe)")))
          (should (equal (+test-awn--crew-rows facts 60)
                         '("⚙ builder       builds what you give it   0 of 4"
                           "⌕ investigator  investigates what you g…  0 of 2"
                           "◎ reviewer      reviews a branch you po…  0 of 2"
                           "✎ scribe        writes issues with you    1 of 1  at its max"
                           "⁂ crew/scribe   named as a role           nothing to add"
                           "⁂ pair          mine, with a long descr…  + builder 3"
                           "⁂ review        write, build, review      + builder 2, revi…"
                           "✗ broken        line 3: agents wizard: no such role (builde…")))
          (dolist (width '(200 140 100 80 60 40 30 24))
            (dolist (row (+test-awn--crew-rows facts width))
              (should (<= (string-width row) width))))
          ;; Nothing to add: dimmed, the whole of it; what it would add, not.
          (pcase-let ((`(_ ,name ,icon ,rest ,dim) (assoc "crew/scribe" (agent-workspace--role-rows facts 200))))
            (should dim)
            (should (memq 'shadow (ensure-list (get-text-property 0 'face name))))
            (should (eq (get-text-property 0 'face icon) 'shadow))
            (should (memq 'shadow (ensure-list (get-text-property (string-search "nothing" rest) 'face rest)))))
          (pcase-let ((`(_ ,_ ,icon ,rest ,dim) (assoc "review" (agent-workspace--role-rows facts 200))))
            (should-not dim)
            (should-not (get-text-property 0 'face icon))
            (should (eq (get-text-property (string-search "scribe" rest) 'face rest) 'shadow))
            (should-not (get-text-property (string-search "+ builder" rest) 'face rest))))
        ;; Without crews (a role to change, e), as before.
        (should-not (seq-some (lambda (fact) (plist-get (cdr fact) :crew)) (agent-workspace--role-picker project)))))))

(ert-deftest agent-workspace-new/a-crew-picked ()
  "c, a crew picked: what the crew lacks made, no name asked, nor with C-u
its model, mode and colour; returned. Again: nothing to add, refused, asked
again. A crew file left out: refused, naming its file and line."
  (+test-aw-with-four-starters
    (+test-awn "crew-picked"
      (+test-awn--three-crews project)
      (+test-awn--no-warnings
        (+test-awn--answering '("review")
          (let ((made (agent-workspace-new '(4))))
            (should (equal (car asked) "Role or crew: "))
            (should (= (length asked) 1))
            (should (equal (mapcar (lambda (agent) (list (agent-workspace-agent-name agent)
                                                         (agent-workspace-agent-role agent)))
                                   made)
                           '(("ada" "scribe") ("grace" "builder") ("linus" "builder") ("ken" "reviewer"))))
            (should (equal (agent-workspace-agents project) made))
            (should (equal (reverse started) '("ada" "grace" "linus" "ken")))))
        (let ((messages nil))
          (cl-letf (((symbol-function 'message)
                     (lambda (format &rest args) (when format (push (apply #'format format args) messages)))))
            (+test-awn--answering '("review" "broken" "investigator" "")
              (let ((agent (agent-workspace-new)))
                (should (equal (agent-workspace-agent-role agent) "investigator"))
                (should (= (length asked) 4))))
            (should (member "Nothing to add: the crew has every agent of review already (scribe, builder 2, reviewer)"
                            messages))
            (should (seq-some (lambda (message)
                                (string-match-p "\\`Left out: .*/\\.agent-workspace/crews/broken\\.md:3: agents wizard"
                                                message))
                              messages))))))))

(ert-deftest agent-workspace-new/no-crews-for-an-issue ()
  "c on a ready issue makes an agent for it: no crews offered, its prompt
Role:."
  (+test-aw-with-four-starters
    (+test-awn "crews-issue"
      (let ((collection nil))
        (+test-awn--answering '("builder" "")
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (prompt names &rest _)
                       (push prompt asked)
                       (setq collection names)
                       (pop answers))))
            (agent-workspace-new nil "builder" "doom-a1b" "Fix it" "bug")
            (should (equal (car (last asked)) "Role: "))
            (should (equal collection '("builder" "investigator" "reviewer" "scribe")))))
        ;; Without one: the crews after the roles.
        (+test-awn--answering '("pair")
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (prompt names &rest _)
                       (push prompt asked)
                       (setq collection names)
                       (pop answers))))
            (agent-workspace-new)
            (should (equal collection '("builder" "investigator" "reviewer" "scribe" "pair" "review")))))))))

(ert-deftest agent-workspace-new/its-name-asked ()
  "Left empty, the name made for it; one taken or not valid, asked again."
  (+test-awn "name"
    (+test-awn--agent project "ada")
    (+test-awn--answering '("Ada" "no good" "" )
      (should (equal (agent-workspace-read-name project "builder") "grace"))
      (should (equal (car asked) "Name (empty: grace): "))
      (should (= (length asked) 3)))
    (+test-awn--answering '(" linus ")
      (should (equal (agent-workspace-read-name project "builder") "linus")))))

(ert-deftest agent-workspace-new/made-from-what-you-answer ()
  "Its role and name asked, then made: its worktree, in the crew, started;
with C-u its model, mode and colour asked too (its role's by default)."
  (+test-awn "new"
    (+test-awn--answering '("investigator" "")
      (let ((agent (agent-workspace-new)))
        (should (equal (agent-workspace-agent-name agent) "ada"))
        (should (equal (agent-workspace-agent-role agent) "investigator"))
        (should (equal (agent-workspace-agent-colour agent) "magenta"))
        (should (equal started '("ada")))
        (should (file-directory-p (expand-file-name ".agent-shell/worktrees/investigator-ada" project)))
        (should (equal (agent-workspace-agents project) (list agent)))
        (should-not sent)))
    (+test-awn--answering '("builder" "ken" "haiku" "plan" "yellow")
      (let ((agent (agent-workspace-new '(4))))
        (should (equal (list (agent-workspace-agent-model agent) (agent-workspace-agent-mode agent)
                             (agent-workspace-agent-colour agent))
                       '("haiku" "plan" "yellow")))
        (should (equal (nth 2 (reverse asked)) "Model (builder's: inherit): "))))
    (+test-awn--answering '("reviewer" "linus" "inherit" "default" "green")
      (should-not (agent-workspace-agent-model (agent-workspace-new '(4)))))))

(ert-deftest agent-workspace-new/made-from-an-issue ()
  "Made for an issue: its role offered first, its worktree on the issue's
branch (TYPE/ID-SLUG: task/ when its type isn't known, no words without a
title), the issue its first
message, noted as its."
  (+test-awn "issue"
    (+test-awn--answering '("builder" "")
      (let ((agent (agent-workspace-new nil "builder" "doom-a1b" "Fix the thing" "bug")))
        (should (equal (agent-workspace-agent-issue agent) "doom-a1b"))
        (should (equal (agent-workspace-agent-issue-title agent) "Fix the thing"))
        (should (equal (agent-workspace-agent-branch agent) "fix/doom-a1b-fix-thing"))
        (should (equal sent '(("ada" "Work on doom-a1b: Fix the thing" (:submit t)))))))
    ;; A prompt of its own wins.
    (let ((ken (agent-workspace-create :role "builder" :name "ken" :issue "doom-b2c" :prompt "Look at it")))
      (should (equal (car sent) '("ken" "Look at it" (:submit t))))
      (should (equal (agent-workspace-agent-branch ken) "task/doom-b2c")))))

(ert-deftest agent-workspace-new/made-for-an-issue-claims-it ()
  "Made for an issue: claimed in bd as the new agent at once, as t does
\(no looping agent takes it meanwhile); claimed by another first: nothing
made, said (doom-pbk.153: never claimed)."
  (skip-unless (executable-find "bd"))
  (+test-awn "claimed"
    (+test-bd-init "--quiet" "--skip-agents" "--prefix" "cl")
    (cl-flet ((issue (title)
                (with-temp-buffer
                  (should (eql 0 (call-process "bd" nil t nil "create" "--title" title "--type" "task" "--json")))
                  (goto-char (point-min))
                  (search-forward "{")
                  (backward-char)
                  (plist-get (json-parse-buffer :object-type 'plist) :id)))
              (shown (id)
                (with-temp-buffer
                  (should (eql 0 (call-process "bd" nil t nil "show" id "--json")))
                  (goto-char (point-min))
                  (re-search-forward "[[{]")
                  (backward-char)
                  (let ((issue (json-parse-buffer :object-type 'plist :array-type 'list)))
                    (if (consp issue) (car issue) issue)))))
      (let ((one (issue "One")) (two (issue "Two")))
        (+test-awn--answering '("builder" "")
          (let ((agent (agent-workspace-new nil "builder" one "One" "task")))
            (should (equal (agent-workspace-agent-issue agent) one))
            (let ((issue (shown one)))
              (should (equal (plist-get issue :status) "in_progress"))
              (should (equal (plist-get issue :assignee) (agent-workspace-agent-name agent))))))
        ;; Claimed by another first.
        (let ((process-environment (cons "BEADS_ACTOR=zed" process-environment)))
          (should (eql 0 (call-process "bd" nil nil nil "update" two "--claim"))))
        (+test-awn--answering '("builder" "")
          (should (string-search (format "%s not given to" two)
                                 (cadr (should-error (agent-workspace-new nil "builder" two "Two" "task")
                                                     :type 'user-error)))))
        (should (= (length (agent-workspace-agents project)) 1))
        (should (equal (plist-get (shown two) :assignee) "zed"))))))

(ert-deftest agent-workspace-new/no-crew-here ()
  "Outside git, or with no commit: no crew, saying why; nothing asked."
  (let ((default-directory (file-name-as-directory (make-temp-file (+test-tmp-file "awn-nogit-") t))))
    (+test-awn--answering nil
      (should (string-match-p "No crew here: not a git repository"
                              (cadr (should-error (agent-workspace-new) :type 'user-error)))))))

(ert-deftest agent-workspace-new/a-failing-step-said ()
  "Its worktree not made: nothing is, saying so; its session not started:
it's in the crew, stuck, saying why."
  (+test-awn "failing"
    ;; A file where its worktree goes.
    (make-directory (expand-file-name ".agent-shell/worktrees" project) t)
    (write-region "" nil (expand-file-name ".agent-shell/worktrees/builder-ada" project))
    (should (string-match-p "\\`ada.s worktree: git worktree"
                             (cadr (should-error (agent-workspace-create :role "builder" :name "ada")
                                                 :type 'user-error))))
    (should-not (agent-workspace-agents project))
    (should-not started))
  (+test-awn "failing-session"
    (cl-letf (((symbol-function 'agent-workspace--start)
                (symbol-function (if (fboundp '+test-awn--real-start) '+test-awn--real-start 'ignore))))
      (let* ((agent-workspace-kinds '((claude-code :config (lambda () (error "No agent here")))))
             (agent (agent-workspace-create :role "builder" :name "ada" :prompt "hi")))
        (should (eq (agent-workspace-agent-state agent) 'stuck))
        (should (equal (agent-workspace-agent-error agent) "its session: No agent here"))
        (should (equal (agent-workspace-agents project) (list agent)))
        ;; Its first message not sent to a session that isn't.
        (should-not sent)))))

;; The real session start (the tests above stand it in), for the failing one.
(defalias '+test-awn--real-start (symbol-function 'agent-workspace--start))

;; ====== FROM THE SHELL ======

(defun +test-awn--request (op &optional payload cwd)
  "OP's reply (parsed) as cmd/agent-workspace gets it: a request folder with
PAYLOAD (JSON text), from CWD."
  (let ((dir (make-temp-file (+test-tmp-file "awn-request-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert op "\n" (or cwd default-directory) "\n"))
    (when payload
      (with-temp-file (expand-file-name "payload" dir) (insert payload)))
    (should (eq (agent-workspace-request dir) t))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "reply" dir))
      (json-parse-buffer :object-type 'plist :false-object nil :null-object nil))))

(ert-deftest agent-workspace-new/a-request ()
  "new from the shell: made in the shell's folder's project, its name made
if not given, the reply saying where it works; a wrong request said."
  (+test-aw-with-four-starters
    (+test-awn "request"
      (let ((reply (+test-awn--request "new" "{\"role\":\"builder\",\"name\":\"\",\"prompt\":\"\"}"
                                       (expand-file-name ".git/../" project))))
        (should (equal reply (list :ok t :name "ada" :role "builder"
                                   :worktree (expand-file-name ".agent-shell/worktrees/builder-ada" project)
                                   :branch "agent/ada" :state "desk")))
        (should-not sent))
      (should (equal (plist-get (+test-awn--request "new" "{\"role\":\"investigator\",\"name\":\"sam\",\"prompt\":\"Look\"}")
                                :name)
                     "sam"))
      (should (equal (car sent) '("sam" "Look" (:submit t))))
      (dolist (case '(("new" "{\"name\":\"x\"}" "new: which role? --role ROLE")
                      ("new" "{\"role\":\"wizard\"}" "No role wizard: builder, investigator, reviewer, scribe")
                      ("new" "{\"role\":\"builder\",\"name\":\"Bad Name\"}" "Not a name for an agent")
                      ("new" "{nope" "not JSON")
                      ("old" "{}" "unknown operation \"old\"; operations: new")))
        (let ((reply (+test-awn--request (nth 0 case) (nth 1 case))))
          (should-not (plist-get reply :ok))
          (should (string-search (nth 2 case) (plist-get reply :error))))))))

(ert-deftest agent-workspace-new/a-crew-request ()
  "crew from the shell: what the crew lacks made, the reply listing them;
again, none; an unknown crew refused, naming the crews there are."
  (+test-aw-with-four-starters
    (+test-awn "crew-request"
      (let ((reply (+test-awn--request "crew" "{\"name\":\"pair\"}")))
        (should (equal reply
                       (list :ok t
                             :made (vector (list :name "ada" :role "scribe"
                                                 :worktree (expand-file-name ".agent-shell/worktrees/scribe-ada" project)
                                                 :branch "agent/ada" :state "desk")
                                           (list :name "grace" :role "builder"
                                                 :worktree (expand-file-name ".agent-shell/worktrees/builder-grace" project)
                                                 :branch "agent/grace" :state "desk"))))))
      (should (equal (+test-awn--request "crew" "{\"name\":\"pair\"}") (list :ok t :made [])))
      (dolist (case '(("{\"name\":\"nope\"}" "No crew nope: pair, review")
                      ("{}" "crew: which one? crew NAME")))
        (let ((reply (+test-awn--request "crew" (car case))))
          (should-not (plist-get reply :ok))
          (should (equal (plist-get reply :error) (cadr case))))))))

(defmacro +test-awn--with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/aws-" t))
          (server-name "test")
          (process-environment
           (cons (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                 process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-awn--run (&rest args)
  "Run cmd/agent-workspace with ARGS: (STATUS . OUTPUT). Asynchronously:
this Emacs, its server, answers it meanwhile."
  (let* ((output (generate-new-buffer " *agent-workspace-run*"))
         (process (make-process :name "agent-workspace" :buffer output
                                :command (cons +test-awn-script args)
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *agent-workspace-stderr*"))))
    (with-timeout (30 (delete-process process) (ert-fail "cmd/agent-workspace didn't end"))
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(ert-deftest agent-workspace-new/the-script ()
  "cmd/agent-workspace new: the agent made through Emacs's server, the
reply JSON; its exit status 0, 1 when not done."
  (+test-awn "script"
    (+test-awn--with-server
      (let ((run (+test-awn--run "new" "--role" "reviewer" "--prompt" "Review \"main\"")))
        (should (= (car run) 0))
        (should (string-prefix-p "{\"ok\":true,\"name\":\"ada\",\"role\":\"reviewer\"" (cdr run))))
      (should (equal (car sent) '("ada" "Review \"main\"" (:submit t))))
      (let ((run (+test-awn--run "new" "--role=builder" "--name=ada")))
        (should (= (car run) 1))
        (should (string-match-p "\\`{\"ok\":false,\"error\":\"There.s an agent named ada" (cdr run)))))))

(ert-deftest agent-workspace-new/the-script-makes-a-crew ()
  "cmd/agent-workspace crew NAME: what the crew lacks made through Emacs's
server, the reply JSON; an unknown crew: 1, saying so; a wrong use: 2."
  (+test-aw-with-four-starters
    (+test-awn "script-crew"
      (+test-awn--with-server
        (let ((run (+test-awn--run "crew" "pair")))
          (should (= (car run) 0))
          (should (string-prefix-p "{\"ok\":true,\"made\":[{\"name\":\"ada\",\"role\":\"scribe\"" (cdr run))))
        (should (= (length (agent-workspace-agents project)) 2))
        (should (equal (+test-awn--run "crew" "pair") '(0 . "{\"ok\":true,\"made\":[]}")))
        (let ((run (+test-awn--run "crew" "nope")))
          (should (= (car run) 1))
          (should (equal (cdr run) "{\"ok\":false,\"error\":\"No crew nope: pair, review\"}"))))
      (dolist (case '((("crew") "crew: which one?")
                      (("crew" "pair" "extra") "crew: unknown argument \\\"extra\\\"")
                      (("crew" "--name" "pair") "crew: unknown argument \\\"--name\\\"")))
        (let ((run (apply #'+test-awn--run (car case))))
          (should (= (car run) 2))
          (should (string-search (cadr case) (cdr run))))))))

(ert-deftest agent-workspace-new/the-script-sends ()
  "cmd/agent-workspace send: an event queued for a role through Emacs's
server (its agent asleep: nobody of it free), its words joined; wrong uses:
2, saying why."
  (+test-awn "script-send"
    (let ((agent-workspace--inboxes (make-hash-table :test #'equal))
          (agent-workspace--inbox-sent (make-hash-table :test #'equal)))
      (+test-awn--agent project "ada" "builder" 'asleep)
      (+test-awn--with-server
        (let ((run (+test-awn--run "send" "--to" "#builder" "--from=ci" "the" "build broke")))
          (should (= (car run) 0))
          (should (equal (cdr run) "{\"ok\":true,\"events\":[{\"id\":1,\"to\":\"#builder\",\"state\":\"queued\"}]}")))
        (should (equal (plist-get (car (agent-workspace-inbox project)) :text) "the build broke"))
        (let ((run (+test-awn--run "send" "--to" "nobody" "hi")))
          (should (= (car run) 1))
          (should (string-search "No agent nobody in this crew" (cdr run)))))
      (dolist (case '((("send" "hi") "send: to whom?")
                      (("send" "--to" "ada") "send: what?")
                      (("send" "--to" "ada" "--bcc" "x") "send: unknown argument \\\"--bcc\\\"")))
        (let ((run (apply #'+test-awn--run (car case))))
          (should (= (car run) 2))
          (should (string-search (cadr case) (cdr run))))))))

(ert-deftest agent-workspace-new/the-script-sends-control-characters ()
  "cmd/agent-workspace send: a text with a log's colours (ESC) and other
control characters arrives as it was (doom-pbk.37)."
  (+test-awn "script-control"
    (let ((agent-workspace--inboxes (make-hash-table :test #'equal))
          (agent-workspace--inbox-sent (make-hash-table :test #'equal))
          (text "build failed:\n\e[31mFAIL\e[0m lexer\a\x01\x1f\tdone \"ok\" \\o/"))
      (+test-awn--agent project "ada" "builder" 'asleep)
      (+test-awn--with-server
        (let ((run (+test-awn--run "send" "--to" "#builder" "--from=ci" text)))
          (should (= (car run) 0))
          (should (string-prefix-p "{\"ok\":true" (cdr run))))
        (should (equal (plist-get (car (agent-workspace-inbox project)) :text) text))))))

(ert-deftest agent-workspace-new/the-script-from-cron ()
  "Run without XDG_RUNTIME_DIR nor EMACS_SOCKET_NAME (cron): the script
reaches an Emacs whose server is RUNTIME/emacs/server, as a desktop
Emacs's is in /run/user/UID/emacs/ on Linux (doom-pbk.77)."
  (+test-awn "script-cron"
    (let* ((agent-workspace--inboxes (make-hash-table :test #'equal))
           (agent-workspace--inbox-sent (make-hash-table :test #'equal))
           (runtime (make-temp-file "/tmp/awr-" t))
           (server-socket-dir (expand-file-name "emacs" runtime))
           (server-name "server")
           (process-environment
            ;; TMPDIR empty: emacsclient's own guess finds no server (never
            ;; the Emacs running these tests' user's).
            (append (list (concat "AGENT_WORKSPACE_RUNTIME_DIR=" runtime)
                          (concat "TMPDIR=" (make-temp-file "/tmp/awt-" t)))
                    (seq-remove (lambda (var) (string-match-p "\\`\\(XDG_RUNTIME_DIR\\|EMACS_SOCKET_NAME\\)=" var))
                                process-environment))))
      (+test-awn--agent project "ada" "builder" 'asleep)
      (unwind-protect
          (progn
            (server-start nil t)
            (let ((run (+test-awn--run "send" "--to" "#builder" "--from=cron" "nightly build broke")))
              (should (= (car run) 0))
              (should (string-prefix-p "{\"ok\":true" (cdr run))))
            (should (equal (plist-get (car (agent-workspace-inbox project)) :text) "nightly build broke")))
        (server-force-delete)
        (delete-directory runtime t)))))

(ert-deftest agent-workspace-new/the-script-s-wrong-uses ()
  "Wrong uses: 2, saying what's wrong; no Emacs: 3."
  (let ((process-environment (cons "EMACS_SOCKET_NAME=/tmp/no-such-agent-workspace-server"
                                   process-environment)))
    (dolist (case '((("new") "new: which role?")
                    (("new" "--role") "--role: give it a value")
                    (("new" "--role" "x" "extra") "new: unknown argument \\\"extra\\\"")
                    (("old") "unknown operation \\\"old\\\"; operations: new")))
      (let ((run (apply #'+test-awn--run (car case))))
        (should (= (car run) 2))
        (should (string-search (cadr case) (cdr run)))))
    (should (= (car (+test-awn--run)) 2))
    (should (string-search "agent-workspace new --role ROLE" (cdr (+test-awn--run "--help"))))
    (let ((run (+test-awn--run "new" "--role" "builder")))
      (should (= (car run) 3))
      (should (string-match-p "no Emacs server answered" (cdr run))))))
