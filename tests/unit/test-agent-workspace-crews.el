;;; tests/unit/test-agent-workspace-crews.el -*- lexical-binding: t; -*-
;; config/agent-workspace/crews.el: crew files read and checked (their
;; problems naming the file and line), the starters as they ship, a project's
;; own and your local ones, what a crew lacks of one, and making it: each
;; agent as c makes one with its name left empty, looping as any new one
;; does, one failing while the others go on, the room told. In throwaway git
;; repositories; no session starts. c's menu with crews and the shell's crew:
;; test-agent-workspace-new.el.

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-workspace")
(load (expand-file-name "../helper-agent-workspace" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== HELPERS ======

(defun +test-awc--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awc--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awc/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awc--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (+test-awc--git "add" "README")
      (+test-awc--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defun +test-awc--file (dir name text)
  "A file NAME in DIR holding TEXT: its name."
  (let ((file (expand-file-name name dir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))
    file))

(defun +test-awc--messages (problems)
  "PROBLEMS' messages, without their file's folder: (LEVEL \"FILE:LINE: ...\")."
  (mapcar (lambda (problem)
            (list (car problem) (replace-regexp-in-string "\\`.*/" "" (cadr problem))))
          problems))

(defmacro +test-awc--quietly (&rest body)
  "BODY, its warnings recorded in `warnings' rather than shown."
  (declare (indent 0))
  `(let ((warnings nil))
     (ignore warnings)
     (cl-letf (((symbol-function 'display-warning)
                (lambda (_type message &optional level &rest _) (push (list level message) warnings))))
       ,@body)))

(defmacro +test-awc (name &rest body)
  "BODY in a new project NAME (`project', `default-directory') with the four
first starters and their two crews (pair, review), crews of its own and no
session started: an agent's start leaves it at the desk; `started' lists
the agents started, `said' what the room was told (its notes)."
  (declare (indent 1))
  `(+test-aw-with-four-starters
     (let* ((project (+test-awc--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (started nil)
            (said nil))
       (ignore started said)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (push (agent-workspace-agent-name agent) started)
                    (setf (agent-workspace-agent-state agent) 'desk)
                    t))
                 ((symbol-function 'agent-workspace-room-post)
                  (lambda (_project &rest entry)
                    (when (eq (plist-get entry :kind) 'note)
                      (push (plist-get entry :text) said))
                    entry)))
         ,@body))))

(defun +test-awc--agent (project name &optional role state)
  "An agent record NAME (ROLE, STATE) put in PROJECT's crew."
  (let ((agent (agent-workspace--make-agent :name name :role (or role "builder") :colour "blue"
                                            :state (or state 'desk) :project project)))
    (puthash project (append (gethash project agent-workspace--crews) (list agent))
             agent-workspace--crews)
    agent))

(defun +test-awc--crew (project)
  "PROJECT's crew: (NAME ROLE) each, in order."
  (mapcar (lambda (agent) (list (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)))
          (agent-workspace-agents project)))

;; ====== A CREW FILE ======

(ert-deftest agent-workspace-crews/a-crew-file ()
  "Its keys read: its agents inline with their counts (none: 1), or as YAML
items (ROLE: N too); quotes taken off; what's after its front matter not
read."
  (+test-aw-with-four-starters
    (let* ((dir (make-temp-file (+test-tmp-file "awc-read-") t))
           (roles (agent-workspace-roles dir)))
      (pcase-let ((`(,crew . ,problems)
                   (agent-workspace-crew-spec-read
                    (+test-awc--file dir "team.md" "---
name: team
description: \"a team\"
# a comment
agents: scribe, builder 2, reviewer
---
Notes for you: builder 9, not read.
")
                    roles)))
        (should-not problems)
        (should (equal (plist-get crew :name) "team"))
        (should (equal (plist-get crew :description) "a team"))
        (should (equal (plist-get crew :agents) '(("scribe" . 1) ("builder" . 2) ("reviewer" . 1))))
        (should (= (agent-workspace-crew-size crew) 4))
        (should (equal (agent-workspace-crew-agents-text (plist-get crew :agents)) "scribe, builder 2, reviewer")))
      (pcase-let ((`(,crew . ,problems)
                   (agent-workspace-crew-spec-read
                    (+test-awc--file dir "listed.md" "---
description: listed
agents:
  - investigator
  - builder: 3
---
")
                    roles)))
        (should-not problems)
        (should (equal (plist-get crew :agents) '(("investigator" . 1) ("builder" . 3))))
        (should-not (plist-member crew :loop))))))

(ert-deftest agent-workspace-crews/a-crew-file-s-problems ()
  "Each problem names the file and line. Errors leave the crew out: no
description, no agents, a role that isn't the project's, a count that isn't
one, over its role's max:, a name not its file's; warnings don't: an
unknown key (loop:, of crew files before doom-pbk.137: a new agent loops by
itself now), a role given twice."
  (+test-aw-with-four-starters
    (let* ((dir (make-temp-file (+test-tmp-file "awc-problems-") t))
           (roles (agent-workspace-roles dir))
           (read (lambda (name text) (agent-workspace-crew-spec-read (+test-awc--file dir name text) roles))))
      (pcase-let ((`(,crew . ,problems)
                   (funcall read "bad.md" "---
name: good
agents: scribe, wizard, builder x2, reviewer 0, builder 5, scribe 2
---
")))
        (should-not crew)
        (should (equal (+test-awc--messages problems)
                       '((error "bad.md:2: its name is good, its file's bad: they must agree")
                         (error "bad.md:3: agents wizard: no such role (builder, investigator, reviewer, scribe)")
                         (error "bad.md:3: agents builder x2: x2 isn't a count, a whole number above 0")
                         (error "bad.md:3: agents reviewer 0: 0 isn't a count, a whole number above 0")
                         (error "bad.md:3: agents builder 5: more than the role allows (max: 4)")
                         (error "bad.md:3: agents scribe 2: more than the role allows (max: 1)")
                         (warning "bad.md:3: agents scribe given twice (line 3 too): the last is used")
                         (error "bad.md:1: no description: say what it's for (description: ...)")))))
      (pcase-let ((`(,crew . ,problems) (funcall read "none.md" "---\ndescription: none\nagents:\n---\n")))
        (should-not crew)
        (should (equal (+test-awc--messages problems)
                       '((error "none.md:3: no agents: its roles, each with how many (agents: scribe, builder 2)")))))
      (pcase-let ((`(,crew . ,problems) (funcall read "open.md" "---\ndescription: open\nagents: scribe\n")))
        (should-not crew)
        (should (equal (+test-awc--messages problems)
                       '((error "open.md:4: its front matter isn't closed: a line --- after its keys")))))
      ;; Only warnings: kept; loop: (crew files before doom-pbk.137) unknown now.
      (pcase-let ((`(,crew . ,problems) (funcall read "warned.md" "---\ndescription: warned\nagents: scribe\nloop: scribe\ncolour: blue\n---\n")))
        (should crew)
        (should-not (plist-member crew :loop))
        (should (equal (+test-awc--messages problems)
                       '((warning "warned.md:4: unknown key loop: ignored")
                         (warning "warned.md:5: unknown key colour: ignored"))))))))

;; ====== A PROJECT'S CREWS ======

(ert-deftest agent-workspace-crews/the-starters ()
  "The starters as they ship, with the starter roles: small, full,
extended, the smallest first, no problem."
  (let* ((agent-workspace--roles-cache (make-hash-table :test #'equal))
         (agent-workspace--crew-specs-cache (make-hash-table :test #'equal))
         (dir (make-temp-file (+test-tmp-file "awc-starters-") t)))
    (should-not (agent-workspace-crew-spec-problems dir))
    (should (equal (mapcar (lambda (crew) (list (car crew) (plist-get (cdr crew) :agents)
                                                (plist-get (cdr crew) :origin)))
                           (agent-workspace-crew-specs dir))
                   '(("small" (("scribe" . 1) ("builder" . 1)) starter)
                     ("full" (("scribe" . 1) ("builder" . 1) ("reviewer" . 1) ("merger" . 1)) starter)
                     ("extended" (("scribe" . 1) ("builder" . 2) ("reviewer" . 1) ("merger" . 1)) starter))))
    (dolist (crew (agent-workspace-crew-specs dir))
      (should (plist-get (cdr crew) :description)))))

(ert-deftest agent-workspace-crews/layered ()
  "A project's crew file replaces a starter of its name, your local one the
project's (each saying what it replaced); one with an error is left out,
the one it would have replaced kept; read again when a file changes, or a
role does (a role gone: its crews left out); their warnings shown once."
  (+test-awc "layered"
    (let ((own (expand-file-name ".agent-workspace/crews/" project))
          (local (expand-file-name ".agent-shell/agent-workspace/crews/" project)))
      (+test-awc--file own "pair.md" "---\ndescription: our pair\nagents: investigator, builder\n---\n")
      (+test-awc--file own "solo.md" "---\ndescription: solo\nagents: builder\nshape: round\n---\n")
      (+test-awc--file local "solo.md" "---\ndescription: my solo\nagents: builder\n---\n")
      (+test-awc--file local "review.md" "---\ndescription: my review\nagents: scribe, wizard\n---\n")
      (+test-awc--quietly
        (should (equal (mapcar (lambda (crew) (list (car crew) (plist-get (cdr crew) :description)
                                                    (plist-get (cdr crew) :origin) (plist-get (cdr crew) :replaces)))
                               (agent-workspace-crew-specs project))
                       '(("solo" "my solo" local project)
                         ("pair" "our pair" project starter)
                         ("review" "write, build, review" starter nil))))
        (should (equal (mapcar (lambda (out) (list (car out) (plist-get (cdr out) :origin) (plist-get (cdr out) :error)))
                               (agent-workspace-crew-specs-left-out project))
                       '(("review" local "line 3: agents wizard: no such role (builder, investigator, reviewer, scribe)"))))
        ;; Shown once, the warning too.
        (should (= (length warnings) 2))
        (agent-workspace-crew-specs project)
        (should (= (length warnings) 2))
        ;; A role of the project's in place of a starter, allowing fewer: the
        ;; crew asking more of it left out.
        (+test-awc--file (expand-file-name ".agent-workspace/roles/" project) "builder.md"
                         "---\ndescription: builds\nlabels: build\nmax: 1\n---\nBuild.\n")
        (should (equal (mapcar #'car (agent-workspace-crew-specs project)) '("solo" "pair")))
        (should (equal (mapcar (lambda (out) (list (car out) (plist-get (cdr out) :origin) (plist-get (cdr out) :error)))
                               (agent-workspace-crew-specs-left-out project))
                       '(("review" starter "line 3: agents builder 2: more than the role allows (max: 1)")
                         ("review" local "line 3: agents wizard: no such role (builder, investigator, reviewer, scribe)"))))))))

;; ====== WHAT A CREW LACKS ======

(ert-deftest agent-workspace-crews/what-a-crew-lacks ()
  "For each of its roles, its count less the crew's agents of that role,
asleep and gone home ones counting; none below 0; in its file's order."
  (+test-awc "lacks"
    (let ((review (alist-get "review" (agent-workspace-crew-specs project) nil nil #'equal)))
      (should (equal (agent-workspace-crew-missing project review)
                     '(("scribe" . 1) ("builder" . 2) ("reviewer" . 1))))
      (+test-awc--agent project "ada" "scribe")
      (+test-awc--agent project "ken" "builder" 'asleep)
      (should (equal (agent-workspace-crew-missing project review) '(("builder" . 1) ("reviewer" . 1))))
      (+test-awc--agent project "sam" "builder" 'home)
      (+test-awc--agent project "tom" "builder")
      (+test-awc--agent project "ian" "investigator")
      (should (equal (agent-workspace-crew-missing project review) '(("reviewer" . 1))))
      (+test-awc--agent project "rob" "reviewer" 'asleep)
      (should-not (agent-workspace-crew-missing project review)))))

;; ====== MAKING IT ======

(ert-deftest agent-workspace-crews/made ()
  "On an empty stage: each agent of the crew made and started, in its
file's order, named from the pool as c names one, its role's colour; the
room told who. Again: nothing to add, nothing made, nothing said."
  (+test-awc "made"
    (pcase-let ((`(,made ,failed ,text) (agent-workspace-crew-make project "review")))
      (should (equal (mapcar #'agent-workspace-agent-name made) '("ada" "grace" "linus" "ken")))
      (should-not failed)
      (should (equal text "crew review: + scribe ada, builder grace, builder linus, reviewer ken"))
      (should (equal said (list text))))
    (should (equal (+test-awc--crew project)
                   '(("ada" "scribe") ("grace" "builder") ("linus" "builder") ("ken" "reviewer"))))
    (should (equal (reverse started) '("ada" "grace" "linus" "ken")))
    (should (equal (mapcar #'agent-workspace-agent-colour (agent-workspace-agents project))
                   '("cyan" "blue" "magenta" "green")))
    (should (file-directory-p (expand-file-name ".agent-shell/worktrees/builder-linus" project)))
    (should-not (seq-some #'agent-workspace-agent-loop (agent-workspace-agents project)))
    (should (equal (agent-workspace-crew-make project "review") '(nil nil nil)))
    (should (= (length (agent-workspace-agents project)) 4))
    (should (= (length said) 1))))

(ert-deftest agent-workspace-crews/each-told-the-whole-crew ()
  "A crew made at once: every agent in the crew before any session starts,
so each is told the whole crew, the first made too (doom-pbk.147: told
\"nobody else yet\", a builder made before its reviewer handing to
nobody)."
  (+test-awc "told"
    (let ((told nil)
          (start (symbol-function 'agent-workspace--start)))
      (cl-letf (((symbol-function 'agent-workspace--start)
                 (lambda (agent)
                   (push (cons (agent-workspace-agent-name agent)
                               (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)))
                         told)
                   (funcall start agent))))
        (agent-workspace-crew-make project "review"))
      (should (equal (reverse started) '("ada" "grace" "linus" "ken")))
      (dolist (name '("ada" "grace" "linus" "ken"))
        (should (equal (cdr (assoc name told)) '("ada" "grace" "linus" "ken"))))
      (let ((agent-workspace-agents-talk t))
        (should (string-search "Your crew as your session started: grace (builder), linus (builder), ken (reviewer)."
                               (agent-workspace--message-context (agent-workspace-agent "ada" project))))))))

(ert-deftest agent-workspace-crews/only-adds ()
  "It adds what's missing and leaves the crew's agents as they are: a
builder beyond its count, an investigator it doesn't list, one asleep."
  (+test-awc "only-adds"
    (+test-awc--agent project "ada" "scribe" 'asleep)
    (+test-awc--agent project "bob" "builder")
    (+test-awc--agent project "ian" "investigator")
    (pcase-let ((`(,made ,_ ,text) (agent-workspace-crew-make project "review")))
      (should (equal (mapcar #'agent-workspace-agent-name made) '("grace" "linus")))
      (should (equal text "crew review: + builder grace, reviewer linus")))
    (should (equal (+test-awc--crew project)
                   '(("ada" "scribe") ("bob" "builder") ("ian" "investigator") ("grace" "builder")
                     ("linus" "reviewer"))))
    (should (eq (agent-workspace-agent-state (agent-workspace-agent "ada" project)) 'asleep))
    ;; A third builder kept: nothing for review to add.
    (+test-awc--agent project "tom" "builder")
    (should (equal (agent-workspace-crew-make project "review") '(nil nil nil)))
    (should (= (length (agent-workspace-agents project)) 6))))

(ert-deftest agent-workspace-crews/its-agents-loop-as-any-new-one ()
  "A crew's new agents loop as any new agent does (`agent-workspace-loop',
loops.el: a role with labels, a project whose issues Beads tracks); one
there already keeps its loop as it was; the room says only who was made
\(doom-pbk.137: no crew file loop: any more)."
  (+test-awc "loop"
    (let ((looped nil))
      (cl-letf (((symbol-function 'agent-workspace--loop-beads-p) #'always)
                ((symbol-function 'agent-workspace-loop-set)
                 (lambda (agent on &rest _)
                   ;; Not its watch, nor its look.
                   (push (agent-workspace-agent-name agent) looped)
                   (setf (agent-workspace-agent-loop agent) on))))
        (+test-awc--agent project "bob" "builder")
        (+test-awc--quietly
          (pcase-let ((`(,made ,_ ,text) (agent-workspace-crew-make project "review")))
            (should (equal (mapcar #'agent-workspace-agent-role made) '("scribe" "builder" "reviewer")))
            ;; The builder and the reviewer loop; the scribe's role has no labels.
            (should (equal (mapcar #'agent-workspace-agent-loop made) '(nil t t)))
            (should (equal (sort looped #'string<)
                           (sort (mapcar #'agent-workspace-agent-name (cdr made)) #'string<)))
            (should (string-match-p "\\`crew review: \\+ scribe [a-z]+, builder [a-z]+, reviewer [a-z]+\\'" text))))
        (should-not (agent-workspace-agent-loop (agent-workspace-agent "bob" project)))))))

(ert-deftest agent-workspace-crews/one-failing ()
  "One whose worktree can't be made isn't made, said (the next of its role
takes its name); one whose session doesn't start is stuck, saying why; the
others are made."
  (+test-awc "failing"
    (let ((start (symbol-function 'agent-workspace--start))
          (ensure (symbol-function 'agent-workspace-worktree-ensure))
          (failed-once nil))
      (cl-letf (((symbol-function 'agent-workspace--start)
                 (lambda (agent)
                   (if (equal (agent-workspace-agent-role agent) "scribe")
                       (progn (setf (agent-workspace-agent-error agent) "its session: no agent here")
                              (agent-workspace--set-state agent 'stuck)
                              nil)
                     (funcall start agent))))
                ;; The first builder's worktree not made.
                ((symbol-function 'agent-workspace-worktree-ensure)
                 (lambda (agent)
                   (if (and (equal (agent-workspace-agent-role agent) "builder") (not failed-once))
                       (progn (setq failed-once t) (error "git worktree add: no room"))
                     (funcall ensure agent)))))
        (pcase-let ((`(,made ,failed ,text) (agent-workspace-crew-make project "review")))
          (should (equal (mapcar #'agent-workspace-agent-name made) '("ada" "grace" "linus")))
          (should (equal (mapcar #'car failed) '("builder")))
          (should (string-match-p "\\`grace.s worktree: git worktree add: no room\\'" (cdar failed)))
          (should (string-match-p (concat "\\`crew review: \\+ scribe ada, builder grace, reviewer linus; "
                                          "builder not made: grace.s worktree: git worktree add: no room\\'")
                                  text)))
        (should (eq (agent-workspace-agent-state (agent-workspace-agent "ada" project)) 'stuck))
        (should (eq (agent-workspace-agent-state (agent-workspace-agent "grace" project)) 'desk))
        ;; Made again: the builder it lacks.
        (pcase-let ((`(,made ,_ ,_) (agent-workspace-crew-make project "review")))
          (should (equal (mapcar #'agent-workspace-agent-name made) '("ken"))))))))

(ert-deftest agent-workspace-crews/an-unknown-crew ()
  "An unknown crew: refused, naming the crews there are; one left out:
refused, naming its file and line."
  (+test-awc "unknown"
    (+test-awc--file (expand-file-name ".agent-workspace/crews/" project) "broken.md"
                     "---\ndescription: broken\nagents: wizard\n---\n")
    (+test-awc--quietly
      (should (equal (cadr (should-error (agent-workspace-crew-make project "nope") :type 'user-error))
                     "No crew nope: pair, review"))
      (should (string-match-p "\\`Left out: .*/\\.agent-workspace/crews/broken\\.md:3: agents wizard: no such role"
                              (cadr (should-error (agent-workspace-crew-make project "broken") :type 'user-error)))))
    (should-not (agent-workspace-agents project))))

(ert-deftest agent-workspace-crews/check-roles-lists-them ()
  "M-x agent-workspace-check-roles lists the crew files' problems after the
roles'."
  (+test-awc "check"
    (+test-awc--file (expand-file-name ".agent-workspace/crews/" project) "broken.md"
                     "---\ndescription: broken\nagents: builder 9\n---\n")
    (+test-awc--quietly
      (let ((problems (agent-workspace-check-roles project)))
        (should (equal (+test-awc--messages problems)
                       '((error "broken.md:3: agents builder 9: more than the role allows (max: 4)"))))
        (should-not warnings)))
    (with-current-buffer "*agent-workspace roles*"
      (should (string-search ".agent-workspace/crews/broken.md:3: error: agents builder 9: more than the role allows (max: 4)"
                             (buffer-string))))))
