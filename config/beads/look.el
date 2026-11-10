;;; $DOOMDIR/config/beads/look.el -*- lexical-binding: t; -*-
;; The issue list's look: icons, colours, badges, tags, epics with their
;; issues. Loaded from config/beads.el.

;; THE LOOK
;; beads.el shows its columns as words (a status, "P1", a type); here, through
;; its own columns (their formatters replaced, not forked), easier to scan:
;; - a status: an icon in its colour (○ ready, nothing blocking it; ◔ in
;;   progress; ⊘ blocked, by how many open issues; ✓ closed; ◇ deferred), the
;;   blocked ones in the Blocked section, by their blockers too;
;; - a priority: P0 and P1 as red and orange badges, P2 plain, P3/P4 muted;
;; - a type: its icon (nerd-icons, in a graphic frame) in its colour;
;; - a title: as wide as the window leaves it, its labels as tags after it (a
;;   colour each, the same each time), an epic's progress (its issues done of
;;   all, closed ones too); an epic's issues under it, indented (sections
;;   kept: where they're in the epic's);
;; - a closed issue's row dimmed; a P0's tinted under its badges and tags.
;; In a terminal the same, the types as words. Symbols the usual coding fonts
;; have (JetBrains Mono: not ◐ ❄ ⛓ ▰, drawn small from another font).
(defvar-local +my/beads--statuses nil
  "This list's issues' statuses, closed ones too: a table, id -> status.")

(defvar-local +my/beads--children nil
  "This list's epics' issues: a table, parent id -> (DONE . ALL).")

(defvar-local +my/beads--depth nil
  "How deep each issue is drawn under its epic: a table, id -> depth.")

(defun +my/beads--note-issues-a (issues)
  "`beads-client-list''s ISSUES, while a list is refreshed: their statuses and
their epics' counts noted (before the closed ones are hidden,
config/beads/hidden.el)."
  (when (and +my/beads--listing (eq (current-buffer) +my/beads--listing))
    (let ((statuses (make-hash-table :test #'equal))
          (children (make-hash-table :test #'equal)))
      (dolist (issue issues)
        (puthash (alist-get 'id issue) (alist-get 'status issue) statuses)
        (when-let* ((parent (alist-get 'parent issue)))
          (let ((counts (gethash parent children (cons 0 0))))
            (puthash parent (cons (+ (car counts) (if (+my/beads--closed-p issue) 1 0))
                                  (1+ (cdr counts)))
                     children))))
      (setq +my/beads--statuses statuses
            +my/beads--children children
            +my/beads--depth nil)))
  issues)

(defun +my/beads--blockers (issue)
  "How many open issues block ISSUE (its blocks dependencies not closed). Its
dependencies as bd list has them (type, depends_on_id) or bd show (the
issues: dependency_type, id, status)."
  (seq-count (lambda (dependency)
               (and (equal (or (alist-get 'type dependency) (alist-get 'dependency_type dependency))
                           "blocks")
                    (let ((status (or (and +my/beads--statuses
                                           (gethash (or (alist-get 'depends_on_id dependency)
                                                        (alist-get 'id dependency))
                                                    +my/beads--statuses))
                                      (alist-get 'status dependency))))
                      (and status (not (equal status "closed"))))))
             (alist-get 'dependencies issue)))

(defun +my/beads-section-a (fn issue)
  "`beads-list--issue-section': an open issue blocked by open ones, Blocked."
  (let ((section (funcall fn issue)))
    (if (and (eql section 0)
             (not (equal (alist-get 'status issue) "in_progress"))
             (> (+my/beads--blockers issue) 0))
        1
      section)))

;; Colours: the theme's (doom-themes' names), else its faces.
(defun +my/beads--colours (name)
  "The theme's colour NAME and its background, as (COLOUR . BACKGROUND), if
both are known (#rrggbb)."
  (let ((colour (and (fboundp 'doom-color) (ignore-errors (doom-color name))))
        (bg (face-background 'default nil t)))
    (and (stringp colour) (string-prefix-p "#" colour)
         (stringp bg) (string-prefix-p "#" bg)
         (cons colour bg))))

(defun +my/beads--badge (text colour face)
  "TEXT as a badge: in the theme's COLOUR on a tint of it, else in FACE's
(inverted). Its text in its colour: still seen on a line's own background
\(the current line's, a P0 row's)."
  (propertize text 'face (if-let* ((colours (and (fboundp 'doom-blend) (+my/beads--colours colour))))
                             `(:foreground ,(car colours)
                               :background ,(doom-blend (car colours) (cdr colours) 0.25)
                               :weight bold)
                           `(:inherit ,face :inverse-video t :weight bold))))

;; THE COLUMNS
(defconst +my/beads--statuses-look
  '(("ready"       "○" success)
    ("in_progress" "◔" beads-status-in-progress "in progress")
    ("blocked"     "⊘" beads-status-blocked)
    ("closed"      "✓" beads-status-closed)
    ("deferred"    "◇" shadow)
    ("hooked"      "◆" beads-status-hooked))
  "(STATUS ICON FACE [WORD]): how a status is drawn; ready is open with
nothing open blocking it.")

(defun +my/beads-format-status (issue)
  "ISSUE's status: its icon in its colour, its word (see above)."
  (let* ((status (alist-get 'status issue))
         (blockers (+my/beads--blockers issue))
         (status (cond ((and (equal status "open") (> blockers 0)) "blocked")
                       ((equal status "open") "ready")
                       (t status)))
         (look (or (assoc status +my/beads--statuses-look) (list status "•" 'default))))
    (concat (propertize (nth 1 look) 'face (nth 2 look))
            " "
            (propertize (or (nth 3 look) status)
                        'face (if (member status '("ready" "closed")) 'default (nth 2 look)))
            (if (and (equal status "blocked") (> blockers 0))
                (propertize (format " by %d" blockers) 'face 'beads-status-blocked) ""))))

(defun +my/beads-format-priority (issue)
  "ISSUE's priority: P0 and P1 badges, P2 plain, P3/P4 muted."
  (let ((priority (alist-get 'priority issue 2)))
    (pcase priority
      (0 (+my/beads--badge " P0 " 'red 'error))
      (1 (+my/beads--badge " P1 " 'orange 'warning))
      (2 " P2 ")
      (_ (propertize (format " P%s " priority) 'face 'shadow)))))

(defconst +my/beads--types-look
  '(("bug"      "nf-cod-bug"       error)
    ("feature"  "nf-cod-sparkle"   success)
    ("task"     "nf-cod-checklist" font-lock-function-name-face)
    ("epic"     "nf-cod-milestone" font-lock-constant-face)
    ("chore"    "nf-cod-tools"     shadow)
    ("decision" "nf-cod-law"       font-lock-type-face))
  "(TYPE ICON FACE): how a type is drawn, ICON a codicon (nerd-icons).")

(defun +my/beads-format-type (issue)
  "ISSUE's type: its icon (a graphic frame) and its word, in its colour."
  (let* ((type (or (alist-get 'issue_type issue) ""))
         (look (assoc type +my/beads--types-look))
         (face (or (nth 2 look) 'default))
         (icon (and look (display-graphic-p) (fboundp 'nerd-icons-codicon)
                    (ignore-errors (nerd-icons-codicon (nth 1 look))))))
    (concat (if icon
                (let ((icon (copy-sequence icon)))
                  (add-face-text-property 0 (length icon) face nil icon)
                  (concat icon " "))
              "")
            (propertize type 'face face))))

(defconst +my/beads--tag-colours
  '((blue . font-lock-keyword-face) (magenta . font-lock-function-name-face)
    (cyan . font-lock-builtin-face) (green . font-lock-string-face)
    (yellow . font-lock-type-face) (orange . warning)
    (violet . font-lock-constant-face) (teal . success))
  "The labels' colours: (THEME-COLOUR . FACE), FACE where the theme's unknown.")

(defun +my/beads--label-tag (label)
  "LABEL as a tag: its colour on a tint of it, the same each time (from its
letters)."
  (pcase-let* ((`(,name . ,face)
                (nth (mod (seq-reduce (lambda (hash char) (mod (+ (* hash 31) char) 65521)) label 7)
                          (length +my/beads--tag-colours))
                     +my/beads--tag-colours))
               (colours (+my/beads--colours name)))
    (propertize (concat " " label " ")
                'face (if (and colours (fboundp 'doom-blend))
                          `(:foreground ,(car colours) :background ,(doom-blend (car colours) (cdr colours) 0.25))
                        `(:inherit ,face :inverse-video t)))))

(defun +my/beads--progress (done all)
  "An epic's progress: DONE of ALL as a bar and figures."
  (let* ((cells 6)
         (full (if (> all 0) (round (* cells (/ (float done) all))) 0)))
    (concat (propertize (make-string full ?━) 'face 'success)
            (propertize (make-string (- cells full) ?─) 'face 'shadow)
            (propertize (format " %d/%d" done all) 'face (if (= done all) 'success 'shadow)))))

(defun +my/beads--title-width ()
  "Columns the title has, the window's width less those before it (the
title the last column), or nil (no window, or not the last)."
  (when-let* ((window (get-buffer-window (current-buffer) 'visible))
              (format tabulated-list-format)
              ((equal (car (aref format (1- (length format)))) "Title")))
    (- (window-body-width window)
       tabulated-list-padding
       (seq-reduce (lambda (sum column) (+ sum (nth 1 column) 1))
                   (seq-take format (1- (length format)))
                   0)
       1)))

(defun +my/beads-format-title (issue)
  "ISSUE's title, under its epic's indented; its progress if it's an epic,
its labels as tags; cut to the room the window leaves it."
  (let* ((id (alist-get 'id issue))
         (depth (or (and +my/beads--depth (gethash id +my/beads--depth)) 0))
         (indent (if (> depth 0)
                     (concat (make-string (* 2 (1- depth)) ?\s) (propertize "└ " 'face 'shadow))
                   ""))
         (counts (and +my/beads--children (gethash id +my/beads--children)))
         (progress (if counts (concat "  " (+my/beads--progress (car counts) (cdr counts))) ""))
         (labels (append (alist-get 'labels issue) nil))
         (tags (if labels (concat " " (mapconcat #'+my/beads--label-tag labels " ")) ""))
         (title (or (alist-get 'title issue) ""))
         (room (+my/beads--title-width)))
    ;; Cut for its tags and progress to be seen, if it keeps 20 columns: in a
    ;; narrower window the title first, cut at its edge.
    (let ((left (and room (- room (string-width indent) (string-width progress) (string-width tags)))))
      (when (and left (>= left 20) (> (string-width title) left))
        (setq title (truncate-string-to-width title left nil nil "…"))))
    (concat indent title progress tags)))

(defconst +my/beads--columns
  '((status 14 +my/beads-format-status)
    (priority 4 +my/beads-format-priority)
    (type 10 +my/beads-format-type)
    (title 50 +my/beads-format-title))
  "beads.el's list columns drawn here: (COLUMN WIDTH FORMATTER).")

(defun +my/beads-columns ()
  "beads.el's list columns with the look above (see `+my/beads--columns')."
  (setq beads-list--column-defs
        (mapcar (lambda (def)
                  (pcase-let ((`(,column ,header ,width ,sortable ,formatter) def))
                    (if-let* ((look (assq column +my/beads--columns)))
                        (list column header (nth 1 look) sortable (nth 2 look))
                      (list column header width sortable formatter))))
                beads-list--column-defs)))

;; AN EPIC'S ISSUES UNDER IT
(defun +my/beads-nest-a (issues)
  "`beads-list--sectioned-sort''s ISSUES, each issue right under its epic (if
listed, in the same section), indented (`+my/beads--depth'); in order."
  (let* ((ids (make-hash-table :test #'equal))
         (children (make-hash-table :test #'equal))
         (depth (make-hash-table :test #'equal))
         (nested nil))
    (dolist (issue issues)
      (puthash (alist-get 'id issue) issue ids))
    (dolist (issue issues)
      (when-let* ((parent (gethash (alist-get 'parent issue) ids))
                  ((eql (beads-list--issue-section parent) (beads-list--issue-section issue))))
        (puthash (alist-get 'id parent)
                 (append (gethash (alist-get 'id parent) children) (list issue))
                 children)))
    (cl-labels ((walk (issue level)
                  (let ((id (alist-get 'id issue)))
                    (unless (gethash id depth)
                      (puthash id level depth)
                      (push issue nested)
                      (dolist (child (gethash id children))
                        (walk child (1+ level)))))))
      (dolist (issue issues)
        (let ((parent (gethash (alist-get 'parent issue) ids)))
          (unless (and parent (memq issue (gethash (alist-get 'id parent) children)))
            (walk issue 0)))))
    ;; Each issue once, even in a loop of parents.
    (dolist (issue issues)
      (unless (gethash (alist-get 'id issue) depth)
        (puthash (alist-get 'id issue) 0 depth)
        (push issue nested)))
    (setq +my/beads--depth depth)
    (nreverse nested)))

;; A ROW: A P0'S TINTED, A CLOSED ONE'S DIMMED
(defun +my/beads-print-entry-a (id cols)
  "`beads-list--print-entry': a P0's row tinted under its columns' colours
\(beads.el laid it over them: its badge's and tags' backgrounds gone), a
closed issue's in the theme's muted colour."
  (let ((start (point)))
    (tabulated-list-print-entry id cols)
    (when-let* ((face (beads-list--row-face-for-id id)))
      (add-face-text-property start (point) face t))
    (when (equal (and +my/beads--statuses (gethash id +my/beads--statuses)) "closed")
      (add-face-text-property start (point) 'shadow))))

(after! beads-client
  ;; Inside the closed ones' hiding (config/beads/hidden.el): it sees them all.
  (advice-add 'beads-client-list :filter-return #'+my/beads--note-issues-a '((depth . -40))))
(after! beads-list
  (+my/beads-columns)
  (advice-add 'beads-list--issue-section :around #'+my/beads-section-a)
  (advice-add 'beads-list--sectioned-sort :filter-return #'+my/beads-nest-a)
  (advice-add 'beads-list--print-entry :override #'+my/beads-print-entry-a))
