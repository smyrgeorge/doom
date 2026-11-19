;;; $DOOMDIR/config/agent-workspace/new.el -*- lexical-binding: t; -*-
;; Making an agent: what you're asked, a name made for it. Loaded from
;; config/agent-workspace.el, after roles.el. No Doom here.
;;
;; `agent-workspace-new' (what the app's c runs) asks its role or a crew, a
;; row of columns each (what it does, how many of it run against its max, its
;; model, mode, issues: see WHAT YOU'RE ASKED; one at its max is refused),
;; grouped by where the roles come from (local, project, starters), then the
;; crews, then the files left out; a role picked, its name: left empty, one
;; from `agent-workspace-names'. With C-u, its model, permission mode and
;; colour too. Then `agent-workspace-create' makes it: its worktree, its
;; session; given an issue, that issue is its first message (and no crews
;; offered). A crew picked: the agents it lacks made at once
;; (`agent-workspace-crew-make', crews.el), nothing more asked.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; look.el's and issues.el's, loaded after.
(declare-function agent-workspace-glyph "agent-workspace/look")
(declare-function agent-workspace-mode-label "agent-workspace/look")
(declare-function agent-workspace--fit "agent-workspace/look")
(declare-function agent-workspace-issues-ready "agent-workspace/issues")
(declare-function agent-workspace-crew-members "agent-workspace/saved")
(declare-function agent-ui-even-glyphs "agent-ui/core")
(declare-function vertico--goto "vertico")
(declare-function vertico--exhibit "vertico")
(defvar agent-workspace-mode)
(defvar vertico--candidates)

;; ====== VARIABLES ======

(defcustom agent-workspace-names
  '("ada" "grace" "linus" "ken" "margaret" "barbara" "edsger" "dennis" "frances" "hedy" "joan" "radia"
    "tim" "ivan" "niklaus" "ole" "peter" "sophie" "vint" "whitfield" "yukihiro")
  "The names a new agent gets when you leave its name empty, in order: one
in use, whose initial an agent has, or left by a forgotten agent (its
worktree or branch there) is passed over. None left: its role and a number
\(builder-3)."
  :type '(repeat string)
  :group 'agent-workspace)

(defcustom agent-workspace-models '("opus" "sonnet" "haiku")
  "The models offered when you choose one (C-u c); \"inherit\": your
default."
  :type '(repeat string)
  :group 'agent-workspace)

;; ====== A NAME ======

(defun agent-workspace--name-left-p (project name)
  "Non-nil if a forgotten agent NAME left its worktree or branch in PROJECT."
  (let ((default-directory project)
        (worktrees (expand-file-name agent-workspace-worktrees-directory project)))
    (or (agent-workspace--branch-p (agent-workspace-branch name))
        ;; Its folder: NAME, as they were named before, or ROLE-NAME (one
        ;; whose lock or branch says another name isn't its: ROLE-mary-NAME).
        (seq-some (lambda (folder)
                    (or (equal folder name)
                        (and (string-suffix-p (concat "-" name) folder)
                             (member (agent-workspace--worktree-agent-name (expand-file-name folder worktrees))
                                     (list name nil)))))
                  (and (file-directory-p worktrees) (directory-files worktrees nil "\\`[^.]"))))))

(defun agent-workspace-pool-name (project role)
  "A name for a new agent of ROLE in PROJECT's crew (see
`agent-workspace-names'): none of its agents' names or initials, those
crew.json keeps while it doesn't run too (`agent-workspace-crew-members')."
  (let* ((names (mapcar #'car (agent-workspace-crew-members project)))
         (initials (mapcar (lambda (name) (aref name 0)) names)))
    (or (seq-find (lambda (name)
                    (and (not (member name names))
                         (not (memq (aref name 0) initials))
                         (not (agent-workspace--name-left-p project name))))
                  agent-workspace-names)
        (cl-loop for n from 1
                 for name = (format "%s-%d" role n)
                 unless (or (member name names) (agent-workspace--name-left-p project name))
                 return name))))

;; ====== WHAT YOU'RE ASKED ======
;; The role picker: a row for each role, its columns lined up from row to
;; row: its icon (in its colour, before its name: not typed nor matched), its
;; name, what it does, how many run of its max, its model, its permission
;; mode, the issues it takes (its labels, with how many the app's issue list
;; has ready for it), who it hands them to, and, dimmed, the role it replaced
;; ("replaces the starter"). A role at its max: dimmed, "at its max" in place
;; of its last columns (still refused). Grouped by where the roles come from,
;; each group under a divider (the completion's group titles, vertico's
;; lines): your local ones, the project's, the starters, then the role files
;; left out for an error (✗, dimmed, the first error in place of what it
;; does; refused, naming its file and line). The role offered first (an
;; issue's) is selected where it is, in its group. Fitted to the minibuffer:
;; as it narrows, the role replaced goes first, then hands-to, the labels,
;; the mode, the model; the description is cut with … last; icon, name and
;; count stay. All of it gathered as the picker opens: nothing read from disk
;; or bd as you move through it.
;;
;; With crews (`agent-workspace-read-role-or-crew', c with no issue): a
;; section of them after the roles' groups, before the files left out (crew
;; files with an error among them): the local ones, the project's, then the
;; starters, each a row: its icon (⁂), its name (crew/NAME when a role has
;; it), its description in the roles' column, then, over the columns the
;; roles have after it, its agents, what it would add here (+ builder,
;; reviewer) and, dimmed, where it comes from (local, project; the one it
;; replaced): each lined up from crew to crew. Narrowed, where it comes from
;; goes first, then its agents; what it would add is cut with … last.
;; Nothing to add: dimmed, "nothing to add", refused as a role at its max.

(defconst agent-workspace--role-gap 2
  "The columns between two of the role picker's.")

(defun agent-workspace--role-facts (project roles)
  "What the role picker shows of each of PROJECT's ROLES (their names),
gathered once: ((NAME . (:spec ROLE :count N :ready N))...), :ready nil when
the app's issue list has fetched nothing (no app: M-x outside it)."
  (let ((specs (agent-workspace-roles project))
        (ready (and (fboundp 'agent-workspace-issues-ready) (agent-workspace-issues-ready project))))
    (mapcar (lambda (name)
              (cons name (list :spec (or (alist-get name specs nil nil #'equal) (list :name name))
                               :count (agent-workspace-role-count project name)
                               :ready (and (listp ready)
                                           (seq-count (lambda (issue) (equal (plist-get issue :role) name))
                                                      ready)))))
            roles)))

(defconst agent-workspace--role-groups '(local project starter crew out)
  "The role picker's groups, in order: where roles come from, the crews,
then the role and crew files left out.")

(defun agent-workspace--role-group (fact)
  "The group of FACT (one of `agent-workspace--role-picker'): local,
project, starter, crew, or out (left out)."
  (cond ((plist-get (cdr fact) :out) 'out)
        ((plist-get (cdr fact) :crew) 'crew)
        (t (or (plist-get (plist-get (cdr fact) :spec) :origin) 'starter))))

(defun agent-workspace--role-group-title (group)
  "The role picker's divider for GROUP (`agent-workspace--role-groups')."
  (pcase group
    ('local (concat "local · " agent-workspace-local-roles-directory))
    ('project (concat "project · " agent-workspace-roles-directory))
    ('crew "crews")
    ('out "left out")
    (_ "starters")))

(defun agent-workspace--crew-facts (project)
  "What the picker shows of PROJECT's crews, gathered once: ((NAME . (:crew
CREW :missing MISSING :count 0))...), the local ones, the project's, then
the starters, MISSING what the crew lacks of it
\(`agent-workspace-crew-missing'), its agents running or not read once."
  (let ((specs (agent-workspace-crew-specs project))
        (members (agent-workspace-crew-members project)))
    (seq-mapcat (lambda (origin)
                  (seq-keep (lambda (spec)
                              (and (eq (plist-get (cdr spec) :origin) origin)
                                   (cons (car spec)
                                         (list :crew (cdr spec)
                                               :missing (agent-workspace-crew-missing project (cdr spec) members)
                                               :count 0))))
                            specs))
                '(local project starter))))

(defun agent-workspace--role-picker (project &optional crews)
  "What the role picker offers for PROJECT, gathered once, in its order:
its roles grouped by where they come from (local, project, starters), as
`agent-workspace--role-facts' gives them; CREWS non-nil, its crews, as
`agent-workspace--crew-facts' gives them (NAME is crew/NAME when a role
has its name); then its role files left out for an error, (NAME . (:out
LEFT-OUT :count 0)) each, LEFT-OUT one of `agent-workspace-roles-left-out'
\(NAME is ORIGIN/NAME when one listed has its name), and with CREWS its
crew files left out the same way."
  (let* ((specs (agent-workspace-roles project))
         (names (seq-mapcat (lambda (group)
                              (seq-keep (lambda (role)
                                          (and (eq (or (plist-get (cdr role) :origin) 'starter) group)
                                               (car role)))
                                        specs))
                            '(local project starter)))
         (taken (copy-sequence names))
         ;; The first of NAMES no row has: its row's name, taken.
         (unique (lambda (&rest names)
                   (let ((name (or (seq-find (lambda (name) (not (member name taken))) names)
                                   (car (last names)))))
                     (push name taken)
                     name)))
         (out (lambda (entry)
                (cons (funcall unique (car entry)
                               (format "%s/%s" (plist-get (cdr entry) :origin) (car entry))
                               (format "crew/%s/%s" (plist-get (cdr entry) :origin) (car entry)))
                      (list :out (cdr entry) :count 0)))))
    (append (agent-workspace--role-facts project names)
            (and crews
                 (mapcar (lambda (fact) (cons (funcall unique (car fact) (concat "crew/" (car fact))) (cdr fact)))
                         (agent-workspace--crew-facts project)))
            (mapcar out (agent-workspace-roles-left-out project))
            (and crews (mapcar out (agent-workspace-crew-specs-left-out project))))))

(defun agent-workspace--role-cells (fact)
  "FACT's columns (one of `agent-workspace--role-picker'), each its text in
its face: (:icon :name :description :count :model :mode :labels :hands
:replaces :full :out); a crew's, :crew and its own (:agents :adds
:origin)."
  (cond
   ((plist-get (cdr fact) :out)
    (list :icon (agent-workspace-glyph '(nil . "✗") 'shadow) :name (car fact)
          :description (plist-get (plist-get (cdr fact) :out) :error) :count "" :model "" :mode "" :labels ""
          :hands "" :replaces "" :out t))
   ((plist-get (cdr fact) :crew) (agent-workspace--crew-cells fact))
   (t (agent-workspace--role-cells-1 fact))))

(defun agent-workspace--crew-cells (fact)
  "FACT's columns, a crew's (see `agent-workspace--role-cells'): nothing
to add, :full."
  (let* ((crew (plist-get (cdr fact) :crew))
         (missing (plist-get (cdr fact) :missing)))
    (list :icon (agent-workspace-glyph '("nf-md-account_group" . "⁂") (unless missing 'shadow))
          :name (car fact)
          :description (or (plist-get crew :description) "")
          :count "" :model "" :mode "" :labels "" :hands "" :replaces ""
          :agents (propertize (agent-workspace-crew-agents-text (plist-get crew :agents)) 'face 'shadow)
          :adds (if missing (concat "+ " (agent-workspace-crew-agents-text missing)) "nothing to add")
          :origin (propertize (string-join (delq nil (list (pcase (plist-get crew :origin)
                                                             ('local "local")
                                                             ('project "project"))
                                                           (pcase (plist-get crew :replaces)
                                                             ('starter "replaces the starter")
                                                             ('project "replaces the project's"))))
                                           ", ")
                              'face 'shadow)
          :crew t
          :full (not missing))))

(defun agent-workspace--role-cells-1 (fact)
  "FACT's columns, a role's (see `agent-workspace--role-cells')."
  (let* ((spec (plist-get (cdr fact) :spec))
         (max (plist-get spec :max))
         (count (plist-get (cdr fact) :count))
         (ready (plist-get (cdr fact) :ready))
         (labels (plist-get spec :labels))
         (hands (plist-get spec :hands-to))
         (full (and max (>= count max)))
         (colour (and (plist-get spec :colour) (intern (concat "ansi-color-" (plist-get spec :colour)))))
         (icon (plist-get spec :icon)))
    (list :icon (agent-workspace-glyph (cons (and icon (concat "nf-" (string-remove-prefix "nf-" icon)))
                                             (or (plist-get spec :glyph) "▶"))
                                       (cond (full 'shadow)
                                             ((and colour (facep colour))
                                              (list :foreground (face-foreground colour nil t)))))
          :name (car fact)
          :description (or (plist-get spec :description) "")
          :count (cond (max (format "%d of %d" count max))
                       ((> count 0) (format "%d" count))
                       (t ""))
          :model (propertize (or (plist-get spec :model) "your default") 'face 'shadow)
          :mode (propertize (agent-workspace-mode-label (or (plist-get spec :mode) agent-workspace-mode "default"))
                            'face 'shadow)
          :labels (concat (propertize (string-join labels ", ") 'face 'shadow)
                          (if (and labels ready (> ready 0)) (propertize (format " ·%d ready" ready) 'face 'success) ""))
          :hands (if hands (propertize (concat "→ " (string-join hands ", ")) 'face 'shadow) "")
          :replaces (pcase (plist-get spec :replaces)
                      ('starter (propertize "replaces the starter" 'face 'shadow))
                      ('project (propertize "replaces the project's" 'face 'shadow))
                      (_ ""))
          :full full)))

(defun agent-workspace--role-rows (facts width)
  "The role picker's rows for FACTS (`agent-workspace--role-picker' or
`agent-workspace--role-facts'), WIDTH columns at most: ((NAME CANDIDATE
PREFIX SUFFIX DIM)...), CANDIDATE PREFIX SUFFIX as an
`:affixation-function' gives them (see above), DIM non-nil for a role at
its max, a crew with nothing to add, or left out (refused)."
  (let* ((cells (mapcar #'agent-workspace--role-cells facts))
         (gap agent-workspace--role-gap)
         (at-max "at its max")
         (roles (seq-remove (lambda (cell) (or (plist-get cell :out) (plist-get cell :crew))) cells))
         (crews (seq-filter (lambda (cell) (plist-get cell :crew)) cells))
         ;; A left-out file's error doesn't widen the description's column:
         ;; it has the rest of its row; a crew's description is in it.
         (widest (lambda (key) (apply #'max 0 (mapcar (lambda (cell) (string-width (plist-get cell key)))
                                                      (pcase key
                                                        (:name cells)
                                                        (:description (append roles crews))
                                                        (_ roles))))))
         ;; A column no role says anything in takes no room.
         (room (lambda (key) (let ((w (funcall widest key))) (if (> w 0) (+ gap w) 0))))
         (start (+ 2 (funcall widest :name) (funcall room :count)))
         (others (seq-remove (lambda (cell) (plist-get cell :full)) roles))
         ;; A full role's "at its max", while there's room for it (its row
         ;; dimmed says it too).
         (fulls (and (<= (+ start gap (string-width at-max)) width)
                     (seq-filter (lambda (cell) (plist-get cell :full)) roles)))
         ;; After the count: the columns SHOWN, or a full role's "at its max".
         (tail (lambda (shown) (max (if others (apply #'+ (mapcar room shown)) 0)
                                    (if fulls (+ gap (string-width at-max)) 0))))
         (shown (seq-filter (lambda (key) (> (funcall widest key) 0)) '(:model :mode :labels :hands :replaces))))
    ;; Dropped from the right while the description can't have its width.
    (while (and shown (> (+ start (funcall room :description) (funcall tail shown)) width))
      (setq shown (butlast shown)))
    ;; What's left for the description: cut with … to fit; next to nothing,
    ;; none.
    (let* ((described (let ((w (min (funcall widest :description) (- width start (funcall tail shown) gap))))
                        (if (< w 4) 0 w)))
           ;; A crew's columns after its description, each lined up from
           ;; crew to crew, in what's left of its row: where it comes from
           ;; dropped first, then its agents.
           (crew-room (- width 2 (funcall widest :name) (if (> described 0) (+ gap described) 0) gap))
           (crew-widest (lambda (key) (apply #'max 0 (mapcar (lambda (cell) (string-width (plist-get cell key)))
                                                             crews))))
           (crew-shown (let ((keys (seq-filter (lambda (key) (> (funcall crew-widest key) 0))
                                               '(:agents :adds :origin))))
                         (while (and (cdr keys)
                                     (> (+ (apply #'+ (mapcar crew-widest keys)) (* gap (1- (length keys))))
                                        crew-room))
                           (setq keys (remq (if (memq :origin keys) :origin :agents) keys)))
                         keys)))
      (cl-mapcar
       (lambda (fact cell)
         (let* ((full (plist-get cell :full))
                (out (plist-get cell :out))
                (dim (or full out))
                (pad (lambda (text w) (concat text (make-string (max 0 (- w (string-width text))) ?\s))))
                ;; A left-out file's error: what's left of its row after its
                ;; name, cut with … to fit; next to nothing, none.
                (said (- width 2 (funcall widest :name) gap))
                (parts (cond
                        (out (and (>= said 4) (list (agent-workspace--fit (plist-get cell :description) said))))
                        ((plist-get cell :crew)
                         (append
                          (and (> described 0)
                               (list (funcall pad (agent-workspace--fit (plist-get cell :description) described)
                                              described)))
                          (if (and (equal crew-shown '(:adds)) (> (funcall crew-widest :adds) crew-room))
                              ;; What it would add alone, cut with … to fit.
                              (and (>= crew-room 4) (list (agent-workspace--fit (plist-get cell :adds) crew-room)))
                            (mapcar (lambda (key) (funcall pad (plist-get cell key) (funcall crew-widest key)))
                                    crew-shown))))
                        (t (append
                            (and (> described 0)
                                 (list (funcall pad (agent-workspace--fit (plist-get cell :description) described)
                                                described)))
                            (and (> (funcall widest :count) 0)
                                 (list (funcall pad (plist-get cell :count) (funcall widest :count))))
                            (if full
                                (and fulls (list at-max))
                              (mapcar (lambda (key) (funcall pad (plist-get cell key) (funcall widest key)))
                                      shown))))))
                (suffix (string-trim-right
                         (concat (make-string (- (funcall widest :name) (string-width (car fact))) ?\s)
                                 (mapconcat (lambda (part) (concat (make-string gap ?\s) part)) parts ""))))
                (icon (plist-get cell :icon)))
           ;; At its max, nothing to add or left out: dimmed, the whole of it.
           (when dim
             (add-face-text-property 0 (length suffix) 'shadow t suffix))
           ;; Its icon a column in the GUI too, whatever the font draws.
           (list (car fact) (agent-workspace--role-candidate (car fact) dim)
                 (if (fboundp 'agent-ui-even-glyphs) (agent-ui-even-glyphs icon) icon)
                 suffix dim)))
       facts cells))))

(defun agent-workspace--role-candidate (name dim)
  "NAME as the role picker shows it, its matches highlighted as the
completion UI has them; DIM (its role at its max, or left out), dimmed."
  (if (not dim)
      name
    (let ((name (copy-sequence name)))
      (add-face-text-property 0 (length name) 'shadow t name)
      name)))

(defun agent-workspace--picker-width ()
  "The columns a completion's row has in the minibuffer: its window's, less
one (a terminal's last column, where a line wraps)."
  (1- (window-body-width (or (active-minibuffer-window) (minibuffer-window)))))

(defun agent-workspace--read-pick (project prompt default crews)
  "One of PROJECT's roles, or with CREWS one of its crews, read in the
minibuffer with PROMPT (DEFAULT, a role, selected), each a row of columns,
grouped (see above): its fact, as `agent-workspace--role-picker' gives
them. A role with as many agents as it allows, a crew with nothing to add,
or a file left out, is refused, and asked again."
  (let* ((facts (agent-workspace--role-picker project crews))
         (names (mapcar #'car facts))
         (default (and (member default names)
                       (not (plist-get (cdr (assoc default facts)) :out))
                       (not (plist-get (cdr (assoc default facts)) :crew))
                       default))
         (rows nil)
         (completion-extra-properties
          (list :affixation-function
                (lambda (names)
                  (let ((width (agent-workspace--picker-width)))
                    (unless (eq (car rows) width)
                      (setq rows (cons width (agent-workspace--role-rows facts width)))))
                  (mapcar (lambda (name)
                            (pcase (assoc name (cdr rows))
                              (`(,_ ,_ ,prefix ,suffix ,dim)
                               (list (agent-workspace--role-candidate name dim) prefix suffix))
                              (_ (list name "" ""))))
                          names))
                :group-function
                (lambda (name transform)
                  (if transform
                      name
                    (when-let* ((fact (assoc name facts)))
                      (agent-workspace--role-group-title (agent-workspace--role-group fact)))))
                ;; In their order: by group, then as they're read.
                :display-sort-function #'identity
                :cycle-sort-function #'identity)))
    (catch 'picked
      (while t
        (let* ((name (agent-workspace--read-in-place prompt names (or default (car names))))
               (fact (assoc name facts)))
          (condition-case err
              (progn (when-let* ((out (plist-get (cdr fact) :out)))
                       (user-error "Left out: %s (M-x agent-workspace-check-roles lists every problem)"
                                   (plist-get out :message)))
                     (if-let* ((crew (plist-get (cdr fact) :crew)))
                         (unless (plist-get (cdr fact) :missing)
                           (user-error "Nothing to add: the crew has every agent of %s already (%s)"
                                       (plist-get crew :name)
                                       (agent-workspace-crew-agents-text (plist-get crew :agents))))
                       (agent-workspace--check-room project name))
                     (throw 'picked fact))
            (user-error (message "%s" (error-message-string err))
                        (sit-for 1.5))))))))

(defun agent-workspace-read-role (project &optional default)
  "A role of PROJECT's read in the minibuffer (DEFAULT selected), each a
row of columns, grouped (see above); one with as many agents as it allows,
or a role file left out, is refused, and asked again."
  (car (agent-workspace--read-pick project "Role: " default nil)))

(defun agent-workspace-read-role-or-crew (project &optional default)
  "A role of PROJECT's or one of its crews read in the minibuffer (DEFAULT,
a role, selected), the crews after the roles (see above): the role's name,
or (crew . NAME). A role at its max, a crew with nothing to add, or a file
left out, is refused, and asked again."
  (let ((fact (agent-workspace--read-pick project "Role or crew: " default t)))
    (if-let* ((crew (plist-get (cdr fact) :crew)))
        (cons 'crew (plist-get crew :name))
      (car fact))))

(defun agent-workspace--read-in-place (prompt names default)
  "One of NAMES read in the minibuffer with PROMPT (a match required),
DEFAULT selected where it is: vertico moves a default to the top, out of
its group, so there it's given none and DEFAULT is selected once vertico
has listed them. An empty answer is DEFAULT."
  (let* ((vertico (bound-and-true-p vertico-mode))
         (answer
          (minibuffer-with-setup-hook
              (lambda ()
                (when (and vertico default (fboundp 'vertico--goto))
                  ;; After vertico's own, which lists them as the minibuffer
                  ;; opens; once.
                  (letrec ((select (lambda ()
                                     (remove-hook 'post-command-hook select t)
                                     (when-let* ((index (and (local-variable-p 'vertico--input)
                                                             (seq-position vertico--candidates default))))
                                       (vertico--goto index)
                                       (vertico--exhibit)))))
                    (add-hook 'post-command-hook select 90 t))))
            (completing-read prompt names nil t nil nil (unless vertico default)))))
    (if (string-empty-p answer) (or default answer) answer)))

(defun agent-workspace-read-name (project role)
  "A name for a new agent of ROLE read in the minibuffer: left empty, one
made for it; one taken or not valid is refused, and asked again."
  (let ((made (agent-workspace-pool-name project role)))
    (catch 'name
      (while t
        (let ((name (string-trim (read-string (format "Name (empty: %s): " made)))))
          (if (string-empty-p name)
              (throw 'name made)
            (condition-case err
                (progn (agent-workspace--check-name name project)
                       (throw 'name name))
              (user-error (message "%s" (error-message-string err))
                          (sit-for 1.5)))))))))

(defun agent-workspace--read-more (project role)
  "Its model, permission mode and colour, read (its role's, else
`agent-workspace-mode', and a free one by default): (:model :mode :colour)."
  (let* ((spec (agent-workspace--project-role project role))
         (model (completing-read (format "Model (%s's: %s): " role (or (plist-get spec :model) "inherit"))
                                 (cons "inherit" agent-workspace-models) nil nil nil nil
                                 (or (plist-get spec :model) "inherit")))
         (mode (completing-read "Permission mode: " agent-workspace-modes nil t nil nil
                                (or (plist-get spec :mode) agent-workspace-mode "default")))
         (colour (completing-read "Colour: " agent-workspace-colours nil t nil nil
                                  (agent-workspace-free-colour project (plist-get spec :colour)))))
    (list :model (unless (member model '("" "inherit")) model)
          :mode mode
          :colour colour)))

(defun agent-workspace-new (&optional more role issue title type)
  "Make a new agent in this project's crew: you're asked its role (or a
crew), then its name (left empty, one is made for it); MORE (C-u): its
model, permission mode and colour too. ROLE is offered first. ISSUE (with
its TITLE, TYPE): the issue it's for, its first message (no crews offered).
It gets its worktree, its session starts, then it waits for you. Return
it. A crew picked: the agents the crew lacks of it made, nothing more
asked (`agent-workspace-crew-make'): return them."
  (interactive "P")
  (let ((project (agent-workspace-project)))
    (when-let* ((reason (agent-workspace-no-crew-reason)))
      (user-error "No crew here: %s" reason))
    (let ((picked (if issue
                      (agent-workspace-read-role project role)
                    (agent-workspace-read-role-or-crew project role))))
      (if (eq (car-safe picked) 'crew)
          (pcase-let ((`(,made ,_ ,text) (agent-workspace-crew-make project (cdr picked))))
            (message "%s" text)
            made)
        (let* ((role picked)
               (name (agent-workspace-read-name project role))
               (more (and more (agent-workspace--read-more project role))))
          (apply #'agent-workspace-create
                 :project project :role role :name name :issue issue :issue-title title :issue-type type
                 more))))))
