;;; $DOOMDIR/config/agent-workspace/new.el -*- lexical-binding: t; -*-
;; Making an agent: what you're asked, a name made for it. Loaded from
;; config/agent-workspace.el, after roles.el. No Doom here.
;;
;; `agent-workspace-new' (what the app's c runs) asks its role, a row of
;; columns each (what it does, how many of it run against its max, its model,
;; mode, issues: see WHAT YOU'RE ASKED; one at its max is refused), then its
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
(defvar agent-workspace-mode)

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
;; has ready for it), who it hands them to. A role at its max: dimmed, "at its
;; max" in place of its last columns (still refused). Fitted to the
;; minibuffer: as it narrows, hands-to goes first, then the labels, the mode,
;; the model; the description is cut with … last; icon, name and count stay.
;; All of it gathered as the picker opens: nothing read from disk or bd as you
;; move through it.

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

(defun agent-workspace--role-cells (fact)
  "FACT's columns (one of `agent-workspace--role-facts'), each its text in
its face: (:icon :name :description :count :model :mode :labels :hands
:full)."
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
          :full full)))

(defun agent-workspace--role-rows (facts width)
  "The role picker's rows for FACTS (`agent-workspace--role-facts'), WIDTH
columns at most: ((NAME CANDIDATE PREFIX SUFFIX FULL)...), CANDIDATE PREFIX
SUFFIX as an `:affixation-function' gives them (see above), FULL non-nil
for a role at its max."
  (let* ((cells (mapcar #'agent-workspace--role-cells facts))
         (gap agent-workspace--role-gap)
         (at-max "at its max")
         (widest (lambda (key) (apply #'max 0 (mapcar (lambda (cell) (string-width (plist-get cell key))) cells))))
         ;; A column no role says anything in takes no room.
         (room (lambda (key) (let ((w (funcall widest key))) (if (> w 0) (+ gap w) 0))))
         (start (+ 2 (funcall widest :name) (funcall room :count)))
         (others (seq-remove (lambda (cell) (plist-get cell :full)) cells))
         ;; A full role's "at its max", while there's room for it (its row
         ;; dimmed says it too).
         (fulls (and (<= (+ start gap (string-width at-max)) width)
                     (seq-filter (lambda (cell) (plist-get cell :full)) cells)))
         ;; After the count: the columns SHOWN, or a full role's "at its max".
         (tail (lambda (shown) (max (if others (apply #'+ (mapcar room shown)) 0)
                                    (if fulls (+ gap (string-width at-max)) 0))))
         (shown (seq-filter (lambda (key) (> (funcall widest key) 0)) '(:model :mode :labels :hands))))
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
                (pad (lambda (text w) (concat text (make-string (max 0 (- w (string-width text))) ?\s))))
                (parts (append
                        (and (> described 0)
                             (list (funcall pad (agent-workspace--fit (plist-get cell :description) described)
                                            described)))
                        (and (> (funcall widest :count) 0)
                             (list (funcall pad (plist-get cell :count) (funcall widest :count))))
                        (if full
                            (and fulls (list at-max))
                          (mapcar (lambda (key) (funcall pad (plist-get cell key) (funcall widest key))) shown))))
                (suffix (string-trim-right
                         (concat (make-string (- (funcall widest :name) (string-width (car fact))) ?\s)
                                 (mapconcat (lambda (part) (concat (make-string gap ?\s) part)) parts ""))))
                (icon (plist-get cell :icon)))
           ;; At its max: dimmed, the whole of it.
           (when full
             (add-face-text-property 0 (length suffix) 'shadow t suffix))
           ;; Its icon a column in the GUI too, whatever the font draws.
           (list (car fact) (agent-workspace--role-candidate (car fact) full)
                 (if (fboundp 'agent-ui-even-glyphs) (agent-ui-even-glyphs icon) icon)
                 suffix full)))
       facts cells))))

(defun agent-workspace--role-candidate (name full)
  "NAME as the role picker shows it, its matches highlighted as the
completion UI has them; FULL (its role at its max), dimmed."
  (if (not full)
      name
    (let ((name (copy-sequence name)))
      (add-face-text-property 0 (length name) 'shadow t name)
      name)))

(defun agent-workspace--picker-width ()
  "The columns a completion's row has in the minibuffer: its window's, less
one (a terminal's last column, where a line wraps)."
  (1- (window-body-width (or (active-minibuffer-window) (minibuffer-window)))))

(defun agent-workspace-read-role (project &optional default)
  "A role of PROJECT's read in the minibuffer (DEFAULT first), each a row of
columns (see above); one with as many agents as it allows is refused, and
asked again."
  (let* ((roles (mapcar #'car (agent-workspace-roles project)))
         (roles (if (member default roles) (cons default (delete default roles)) roles))
         (facts (agent-workspace--role-facts project roles))
         (rows nil)
         (completion-extra-properties
          (list :affixation-function
                (lambda (names)
                  (let ((width (agent-workspace--picker-width)))
                    (unless (eq (car rows) width)
                      (setq rows (cons width (agent-workspace--role-rows facts width)))))
                  (mapcar (lambda (name)
                            (pcase (assoc name (cdr rows))
                              (`(,_ ,_ ,prefix ,suffix ,full)
                               (list (agent-workspace--role-candidate name full) prefix suffix))
                              (_ (list name "" ""))))
                          names)))))
    (catch 'role
      (while t
        (let ((role (completing-read "Role: " roles nil t nil nil (car roles))))
          (condition-case err
              (progn (agent-workspace--check-room project role)
                     (throw 'role role))
            (user-error (message "%s" (error-message-string err))
                        (sit-for 1.5))))))))

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
