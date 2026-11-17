;;; $DOOMDIR/config/agent-workspace/new.el -*- lexical-binding: t; -*-
;; Making an agent: what you're asked, a name made for it. Loaded from
;; config/agent-workspace.el, after roles.el. No Doom here.
;;
;; `agent-workspace-new' (what the app's c runs) asks its role, a row of
;; columns each (what it does, how many of it run against its max, its model,
;; mode, issues: see WHAT YOU'RE ASKED; one at its max is refused), grouped by
;; where the roles come from (local, project, starters, left out), then its
;; name: left empty, one from `agent-workspace-names'. With C-u, its model,
;; permission mode and colour too. Then `agent-workspace-create' makes it: its
;; worktree, its session; given an issue, that issue is its first message.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; look.el's and issues.el's, loaded after.
(declare-function agent-workspace-glyph "agent-workspace/look")
(declare-function agent-workspace-mode-label "agent-workspace/look")
(declare-function agent-workspace--fit "agent-workspace/look")
(declare-function agent-workspace-issues-ready "agent-workspace/issues")
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
`agent-workspace-names')."
  (let* ((names (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)))
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

(defconst agent-workspace--role-groups '(local project starter out)
  "The role picker's groups, in order: where roles come from, then the
role files left out.")

(defun agent-workspace--role-group (fact)
  "The group of FACT (one of `agent-workspace--role-picker'): local,
project, starter, or out (left out)."
  (if (plist-get (cdr fact) :out)
      'out
    (or (plist-get (plist-get (cdr fact) :spec) :origin) 'starter)))

(defun agent-workspace--role-group-title (group)
  "The role picker's divider for GROUP (`agent-workspace--role-groups')."
  (pcase group
    ('local (concat "local · " agent-workspace-local-roles-directory))
    ('project (concat "project · " agent-workspace-roles-directory))
    ('out "left out")
    (_ "starters")))

(defun agent-workspace--role-picker (project)
  "What the role picker offers for PROJECT, gathered once, in its order:
its roles grouped by where they come from (local, project, starters), as
`agent-workspace--role-facts' gives them, then its role files left out
for an error, (NAME . (:out LEFT-OUT :count 0)) each, LEFT-OUT one of
`agent-workspace-roles-left-out' (NAME is ORIGIN/NAME when a role listed
has its name)."
  (let* ((specs (agent-workspace-roles project))
         (names (seq-mapcat (lambda (group)
                              (seq-keep (lambda (role)
                                          (and (eq (or (plist-get (cdr role) :origin) 'starter) group)
                                               (car role)))
                                        specs))
                            '(local project starter)))
         (taken (copy-sequence names)))
    (append (agent-workspace--role-facts project names)
            (mapcar (lambda (entry)
                      (let ((name (if (member (car entry) taken)
                                      (format "%s/%s" (plist-get (cdr entry) :origin) (car entry))
                                    (car entry))))
                        (push name taken)
                        (cons name (list :out (cdr entry) :count 0))))
                    (agent-workspace-roles-left-out project)))))

(defun agent-workspace--role-cells (fact)
  "FACT's columns (one of `agent-workspace--role-picker'), each its text in
its face: (:icon :name :description :count :model :mode :labels :hands
:replaces :full :out)."
  (if-let* ((out (plist-get (cdr fact) :out)))
      (list :icon (agent-workspace-glyph '(nil . "✗") 'shadow) :name (car fact)
            :description (plist-get out :error) :count "" :model "" :mode "" :labels "" :hands ""
            :replaces "" :out t)
    (agent-workspace--role-cells-1 fact)))

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
its max or left out (refused)."
  (let* ((cells (mapcar #'agent-workspace--role-cells facts))
         (gap agent-workspace--role-gap)
         (at-max "at its max")
         (roles (seq-remove (lambda (cell) (plist-get cell :out)) cells))
         ;; A left-out file's error doesn't widen the description's column:
         ;; it has the rest of its row.
         (widest (lambda (key) (apply #'max 0 (mapcar (lambda (cell) (string-width (plist-get cell key)))
                                                      (if (eq key :name) cells roles)))))
         ;; A column no role says anything in takes no room.
         (room (lambda (key) (let ((w (funcall widest key))) (if (> w 0) (+ gap w) 0))))
         (start (+ 2 (funcall widest :name) (funcall room :count)))
         (others (seq-remove (lambda (cell) (plist-get cell :full)) roles))
         ;; A full role's "at its max", while there's room for it (its row
         ;; dimmed says it too).
         (fulls (and (<= (+ start gap (string-width at-max)) width)
                     (seq-filter (lambda (cell) (plist-get cell :full)) cells)))
         ;; After the count: the columns SHOWN, or a full role's "at its max".
         (tail (lambda (shown) (max (if others (apply #'+ (mapcar room shown)) 0)
                                    (if fulls (+ gap (string-width at-max)) 0))))
         (shown (seq-filter (lambda (key) (> (funcall widest key) 0)) '(:model :mode :labels :hands :replaces))))
    ;; Dropped from the right while the description can't have its width.
    (while (and shown (> (+ start (funcall room :description) (funcall tail shown)) width))
      (setq shown (butlast shown)))
    ;; What's left for the description: cut with … to fit; next to nothing,
    ;; none.
    (let ((described (min (funcall widest :description) (- width start (funcall tail shown) gap))))
      (when (< described 4) (setq described 0))
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
           ;; At its max or left out: dimmed, the whole of it.
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

(defun agent-workspace-read-role (project &optional default)
  "A role of PROJECT's read in the minibuffer (DEFAULT selected), each a
row of columns, grouped (see above); one with as many agents as it allows,
or a role file left out, is refused, and asked again."
  (let* ((facts (agent-workspace--role-picker project))
         (names (mapcar #'car facts))
         (default (and (member default names) (not (plist-get (cdr (assoc default facts)) :out))
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
    (catch 'role
      (while t
        (let ((role (agent-workspace--read-in-place "Role: " names (or default (car names)))))
          (condition-case err
              (progn (when-let* ((out (plist-get (cdr (assoc role facts)) :out)))
                       (user-error "Left out: %s" (plist-get out :message)))
                     (agent-workspace--check-room project role)
                     (throw 'role role))
            (user-error (message "%s" (error-message-string err))
                        (sit-for 1.5))))))))

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
  "Make a new agent in this project's crew: you're asked its role, then its
name (left empty, one is made for it); MORE (C-u): its model, permission
mode and colour too. ROLE is offered first. ISSUE (with its TITLE, TYPE):
the issue it's for, its first message. It gets its worktree, its session
starts, then it waits for you. Return it."
  (interactive "P")
  (let ((project (agent-workspace-project)))
    (when-let* ((reason (agent-workspace-no-crew-reason)))
      (user-error "No crew here: %s" reason))
    (let* ((role (agent-workspace-read-role project role))
           (name (agent-workspace-read-name project role))
           (more (and more (agent-workspace--read-more project role))))
      (apply #'agent-workspace-create
             :project project :role role :name name :issue issue :issue-title title :issue-type type
             more))))
