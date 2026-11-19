;;; $DOOMDIR/config/agent-workspace/crews.el -*- lexical-binding: t; -*-
;; Crews: the agents a crew should have, made at once. Loaded from
;; config/agent-workspace.el, after roles.el. No Doom here.
;;
;; A crew file is a Markdown file, NAME.md, read as a role file is (its front
;; matter: roles.el) and placed as roles are: the starters here, in crews/
;; (small, full, extended); a project's own in its .agent-workspace/crews/
;; (committed: `agent-workspace-crews-directory'), and yours for it in its
;; .agent-shell/agent-workspace/crews/ (out of git:
;; `agent-workspace-local-crews-directory'); a later one replaces one of the
;; same name (starter < project < local).
;;
;;   ---
;;   name: full                      its file's name, if given
;;   description: write, build, review and merge
;;   agents: scribe, builder 2, reviewer
;;                                   its roles, each with how many (none: 1);
;;                                   a YAML list too (  - builder 2)
;;   ---
;;   Anything after it: notes for you, not read.
;;
;; Picked (in c's menu, new.el; cmd/agent-workspace crew NAME, request.el),
;; it makes what the crew lacks of it: for each of its roles, its count less
;; the crew's agents of that role (asleep and gone home ones too, and those
;; crew.json keeps while the crew doesn't run: saved.el), each as c
;; makes one with its name left empty, one after another (each in the crew
;; before the next one's name is picked), looping as any new one does
;; (loops.el). It only adds: an agent beyond its count, of a role it doesn't
;; list, or there already (its loop as it was) is left alone. One whose
;; worktree can't be made isn't made, said; one whose session doesn't start
;; is stuck, saying why; the others go on. The room says what was made
;; ("crew full: + builder ada, reviewer ken"). Not saved in crew.json:
;; the crew is still just its agents.
;;
;; A problem names the file and line: an error leaves the crew out (c's menu
;; lists it under left out, refused), a warning doesn't. Errors, as a role
;; file's: no front matter or not closed, a line not a key, no description
;; (or an empty one), a name (its file's) not a lowercase letter then
;; lowercase letters, digits or -, a name: not its file's; and no agents, a
;; role that isn't one of the project's, a count that isn't a whole number
;; above 0, more agents of a role than its max: allows. Warnings: an unknown
;; key (loop:, of crew files before: a new agent loops by itself now), a key
;; or a role given twice. M-x agent-workspace-check-roles lists them with the
;; roles'.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; Their own parts', loaded after.
(declare-function agent-workspace-pool-name "agent-workspace/new")
(declare-function agent-workspace-room-post "agent-workspace/room")
(declare-function agent-workspace-crew-members "agent-workspace/saved")

;; ====== VARIABLES ======

;; config/agent-workspace.el's.
(defvar agent-workspace-crews-directory)
(defvar agent-workspace-local-crews-directory)

(defvar agent-workspace-starter-crews-directory
  (expand-file-name "crews/" (file-name-directory (or load-file-name buffer-file-name)))
  "The starter crews, shipped with this module.")

(defconst agent-workspace--crew-keys '("name" "description" "agents")
  "A crew file's keys.")

(defvar agent-workspace--crew-specs-cache (make-hash-table :test #'equal)
  "A project's crew files, as last read: project to (STAMP (CREWS .
PROBLEMS) LEFT-OUT), STAMP its roles as read then (`eq': read again, its
crews are checked again) and the crew files with their modification
times.")

;; ====== A CREW FILE ======

(defun agent-workspace-crew-spec-read (file roles)
  "Read the crew FILE, against ROLES (its project's: an alist of a name and
its role): (CREW . PROBLEMS). CREW is a plist, :name, :file, :description,
:agents ((ROLE . COUNT)..., in its file's order); nil if FILE has
errors. PROBLEMS, as `agent-workspace-role-read' gives them."
  (let* ((name (file-name-sans-extension (file-name-nondirectory file)))
         (shown (abbreviate-file-name file))
         (case-fold-search nil)
         (crew (list :name name :file file))
         (problems nil)
         ;; Its agents, the last first: ((ROLE COUNT . LINE)...); how many
         ;; it listed (some maybe wrong).
         (agents nil)
         (listed 0))
    (cl-flet ((problem (level n format &rest args)
                (let ((what (apply #'format format args)))
                  (push (list level (format "%s:%d: %s" shown n what) file n what) problems))))
      (unless (string-match-p "\\`[a-z][a-z0-9-]*\\'" name)
        (problem 'error 1 "its name %s (its file's): a lowercase letter, then lowercase letters, digits or -"
                 name))
      (pcase-let
          ((`(,closed ,seen ,_)
            (agent-workspace--front-matter-read
             file
             :keys agent-workspace--crew-keys
             :list-keys '("agents")
             :problem #'problem
             :store
             (lambda (key value n)
               (pcase key
                 ("name"
                  (unless (equal value name)
                    (problem 'error n "its name is %s, its file's %s: they must agree" value name)))
                 ("description"
                  (if (string-empty-p value)
                      (problem 'error n "description: empty: say what it's for")
                    (setq crew (plist-put crew :description value))))
                 ("agents"
                  (setq agents nil listed (length value))
                  ;; ROLE, ROLE N or ROLE: N.
                  (pcase-dolist (`(,item . ,n) value)
                    (string-match "\\`\\([^ \t:]*\\):?[ \t]*\\(.*\\)\\'" item)
                    (let ((role (match-string 1 item))
                          (count (match-string 2 item)))
                      (cond
                       ((not (assoc role roles))
                        (problem 'error n "agents %s: no such role (%s)"
                                 role (string-join (mapcar #'car roles) ", ")))
                       ((not (or (string-empty-p count) (string-match-p "\\`[1-9][0-9]*\\'" count)))
                        (problem 'error n "agents %s %s: %s isn't a count, a whole number above 0" role count count))
                       (t
                        (let ((count (if (string-empty-p count) 1 (string-to-number count)))
                              (max (plist-get (cdr (assoc role roles)) :max)))
                          (when (and max (> count max))
                            (problem 'error n "agents %s %d: more than the role allows (max: %d)" role count max))
                          (when-let* ((before (assoc role agents)))
                            (problem 'warning n "agents %s given twice (line %d too): the last is used"
                                     role (cddr before))
                            (setq agents (delq before agents)))
                          (push (cons role (cons count n)) agents))))))))))))
        (when closed
          (unless (assoc "description" seen)
            (problem 'error 1 "no description: say what it's for (description: ...)"))
          (when (= listed 0)
            (problem 'error (or (cdr (assoc "agents" seen)) 1)
                     "no agents: its roles, each with how many (agents: scribe, builder 2)")))))
    (setq crew (plist-put crew :agents (mapcar (lambda (agent) (cons (car agent) (cadr agent)))
                                               (reverse agents))))
    (setq problems (nreverse problems))
    (cons (unless (assq 'error problems) crew) problems)))

(defun agent-workspace-crew-size (crew)
  "How many agents CREW (a crew file's) has."
  (apply #'+ (mapcar #'cdr (plist-get crew :agents))))

(defun agent-workspace-crew-agents-text (agents)
  "AGENTS ((ROLE . COUNT)...) as a crew file says them: \"scribe, builder 2\"."
  (mapconcat (lambda (agent)
               (if (= (cdr agent) 1) (car agent) (format "%s %d" (car agent) (cdr agent))))
             agents ", "))

;; ====== A PROJECT'S CREWS ======

(defun agent-workspace--crew-places (project)
  "Where PROJECT's crew files come from, in order (a later one's replace an
earlier one's of the same name): ((ORIGIN . FOLDER)...), ORIGIN starter,
project or local."
  (cons (cons 'starter agent-workspace-starter-crews-directory)
        (when project
          (list (cons 'project (expand-file-name agent-workspace-crews-directory (agent-workspace-dir project)))
                (cons 'local (expand-file-name agent-workspace-local-crews-directory (agent-workspace-dir project)))))))

(defun agent-workspace--crew-files (project)
  "PROJECT's crew files, in order: the starters, its own, then your local
ones: ((ORIGIN . FILE)...)."
  (seq-mapcat (lambda (place)
                (when (file-directory-p (cdr place))
                  (mapcar (lambda (file) (cons (car place) file))
                          (directory-files (cdr place) t "\\`[^.].*\\.md\\'"))))
              (agent-workspace--crew-places project)))

(defun agent-workspace--crew-specs-read (project)
  "PROJECT's crews and their problems, read again if a file changed, or its
roles did: (CREWS . PROBLEMS), CREWS an alist of a name and its crew, the
smallest first, whatever their origin (those of a size as they're read: the
starters, the project's, your local ones; c's menu groups them by origin),
each crew's :origin where its file is (starter, project, local), its
:replaces the origin of the one of its name it replaced. New
problems are shown as warnings. A project's, whichever of its crews asks
\(PROJECT a crew's key or its folder)."
  (let* ((project (and project (agent-workspace-dir project)))
         (files (agent-workspace--crew-files project))
         (roles (agent-workspace--roles-read project))
         (times (mapcar (lambda (file)
                          (cons (cdr file) (file-attribute-modification-time (file-attributes (cdr file)))))
                        files))
         (key (or project ""))
         (cached (gethash key agent-workspace--crew-specs-cache)))
    (if (and cached (eq (car (car cached)) roles) (equal (cdr (car cached)) times))
        (cadr cached)
      (let (crews problems left-out)
        (dolist (file files)
          (pcase-let ((`(,crew . ,found) (agent-workspace-crew-spec-read (cdr file) (car roles))))
            (setq problems (append problems found))
            (if crew
                (let* ((name (plist-get crew :name))
                       (replaced (alist-get name crews nil nil #'equal)))
                  (setq crew (plist-put crew :origin (car file)))
                  (when replaced
                    (setq crew (plist-put crew :replaces (plist-get replaced :origin))))
                  (setf (alist-get name crews nil nil #'equal) crew))
              (pcase-let ((`(,_ ,message ,_ ,n ,what) (assq 'error found)))
                (push (list (file-name-base (cdr file)) :file (cdr file) :origin (car file) :message message
                            :error (format "line %d: %s" n what))
                      left-out)))))
        ;; By size: sort is stable, those of a size kept as they're read.
        (setq crews (sort (nreverse crews)
                          (lambda (a b) (< (agent-workspace-crew-size (cdr a)) (agent-workspace-crew-size (cdr b))))))
        (unless agent-workspace--roles-quiet
          (dolist (problem problems)
            (unless (member problem (cdr (cadr cached)))
              (display-warning 'agent-workspace (cadr problem) (car problem)))))
        (let ((value (cons crews problems)))
          (puthash key (list (cons roles times) value (nreverse left-out)) agent-workspace--crew-specs-cache)
          value)))))

(defun agent-workspace-crew-specs (&optional project)
  "PROJECT's crews (default: the current project's): an alist of a name and
its crew (`agent-workspace-crew-spec-read'), the starters, the project's
own and your local ones, the smallest first."
  (car (agent-workspace--crew-specs-read (or project (agent-workspace-project)))))

(defun agent-workspace-crew-specs-left-out (&optional project)
  "PROJECT's crew files left out for their errors (default: the current
project's), as `agent-workspace-roles-left-out' gives role files."
  (let ((project (or project (agent-workspace-project))))
    (agent-workspace--crew-specs-read project)
    (nth 2 (gethash (if project (agent-workspace-dir project) "") agent-workspace--crew-specs-cache))))

(defun agent-workspace-crew-spec-problems (&optional project)
  "What's wrong with PROJECT's crew files: (error|warning MESSAGE) each."
  (cdr (agent-workspace--crew-specs-read (or project (agent-workspace-project)))))

;; ====== MAKING WHAT THE CREW LACKS ======

(cl-defun agent-workspace-crew-missing
    (project crew &optional (members (agent-workspace-crew-members project)))
  "What PROJECT's crew lacks of CREW (a crew file's): ((ROLE . COUNT)...),
in its file's order, each COUNT above 0: its count less the crew's agents
of that role, running or not (asleep, gone home, kept in crew.json while
the crew doesn't run): MEMBERS, as `agent-workspace-crew-members' gives
them (default: read now)."
  (let ((roles (mapcar #'cdr members)))
    (seq-keep (lambda (agent)
                (let ((count (- (cdr agent) (seq-count (lambda (role) (equal role (car agent))) roles))))
                  (and (> count 0) (cons (car agent) count))))
              (plist-get crew :agents))))

(defun agent-workspace--crew-spec (project name)
  "PROJECT's crew NAME; a user error if there's none, or its file was left
out (saying why)."
  (or (alist-get name (agent-workspace-crew-specs project) nil nil #'equal)
      (when-let* ((out (assoc name (agent-workspace-crew-specs-left-out project))))
        (user-error "Left out: %s (M-x agent-workspace-check-roles lists every problem)"
                    (plist-get (cdr out) :message)))
      (user-error "No crew %s: %s" name
                  (let ((names (mapcar #'car (agent-workspace-crew-specs project))))
                    (if names (string-join names ", ") "none")))))

(defun agent-workspace-crew-make (project name)
  "Make what PROJECT's crew lacks of the crew NAME (see the top of this
file), each agent as c makes one with its name left empty (looping as any
new one does: loops.el); the room says what was made. Return (MADE FAILED
TEXT): the agents made (a stuck one too), in order, those not made ((ROLE
. WHY)...), and what the room was told (nil: nothing to add, nothing
said)."
  (let* ((project (agent-workspace--root project))
         (crew (agent-workspace--crew-spec project name))
         (made nil)
         (failed nil))
    ;; All in the crew before any starts: each told the whole crew.
    (agent-workspace--together
     (lambda ()
       (pcase-dolist (`(,role . ,count) (agent-workspace-crew-missing project crew))
         (dotimes (_ count)
           (condition-case err
               (push (agent-workspace-create :project project :role role
                                             :name (agent-workspace-pool-name project role))
                     made)
             (error (push (cons role (error-message-string err)) failed)))))))
    (setq made (nreverse made) failed (nreverse failed))
    (let ((text (and (or made failed)
                     (concat (format "crew %s: " name)
                             (string-join
                              (delq nil
                                    (append
                                     (list (and made
                                                (concat "+ " (mapconcat
                                                              (lambda (agent)
                                                                (format "%s %s" (agent-workspace-agent-role agent)
                                                                        (agent-workspace-agent-name agent)))
                                                              made ", "))))
                                     (mapcar (lambda (failure) (format "%s not made: %s" (car failure) (cdr failure)))
                                             failed)))
                              "; ")))))
      (when text
        (agent-workspace-room-post project :kind 'note :text text))
      (list made failed text))))
