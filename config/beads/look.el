;;; $DOOMDIR/config/beads/look.el -*- lexical-binding: t; -*-
;; The issue list's look: icons, colours, badges, tags, epics with their
;; issues. Loaded from config/beads.el.

;; THE LOOK
;; beads.el shows its columns as words (a status, "P1", a type); here, through
;; its own columns (their formatters replaced, not forked), easier to scan,
;; and narrow, the title keeping most of the width (doom-o5t.1: at 99
;; columns, 59 went before the title, titles cut at ~20):
;; - a status: an icon in its colour (○ ready, nothing blocking it; ◔ in
;;   progress; ⊘3 blocked, by 3 open issues; ✓ closed; ◇ deferred), its word
;;   in its help; the blocked ones in the Blocked section, by their blockers
;;   too;
;; - a priority: P0 and P1 as red and orange badges, P2 plain, P3/P4 muted;
;; - a type: its icon (nerd-icons) in its colour in a graphic frame, its word
;;   in a terminal;
;; - no date (its column there, empty, no gap after it: beads.el sorts by it);
;; - nothing before a row's mark (beads.el padded it by 2 columns, never used);
;; - a title: on one line, cut at the window's edge; or whole, a long one
;;   going on to the next lines under itself (`+my/beads-titles-wrapped');
;;   after it an epic's progress (its issues done of all, closed ones too)
;;   and its labels as tags (a colour each, the same each time); an epic's
;;   issues under it, indented, without the lead they share with it
;;   ("Agent workspace: "); sections kept: where they're in the epic's);
;; - a closed issue's row dimmed; a P0's tinted under its badges and tags.
;; Symbols the usual coding fonts have (JetBrains Mono: not ◐ ❄ ⛓ ▰, drawn
;; small from another font).
(defvar-local +my/beads--statuses nil
  "This list's issues' statuses, closed ones too: a table, id -> status.")

(defvar-local +my/beads--children nil
  "This list's epics' issues: a table, parent id -> (DONE . ALL).")

(defvar-local +my/beads--depth nil
  "How deep each issue is drawn under its epic: a table, id -> depth.")

(defvar-local +my/beads--titles nil
  "This list's issues' titles: a table, id -> title (an epic's, for its
issues' lead).")

(defun +my/beads--note-issues-a (issues)
  "`beads-client-list''s ISSUES, while a list is refreshed: their statuses and
their epics' counts noted (before the closed ones are hidden,
config/beads/hidden.el)."
  (when (and +my/beads--listing (eq (current-buffer) +my/beads--listing))
    (let ((statuses (make-hash-table :test #'equal))
          (children (make-hash-table :test #'equal))
          (titles (make-hash-table :test #'equal)))
      (dolist (issue issues)
        (puthash (alist-get 'id issue) (alist-get 'status issue) statuses)
        (puthash (alist-get 'id issue) (alist-get 'title issue) titles)
        (when-let* ((parent (alist-get 'parent issue)))
          (let ((counts (gethash parent children (cons 0 0))))
            (puthash parent (cons (+ (car counts) (if (+my/beads--closed-p issue) 1 0))
                                  (1+ (cdr counts)))
                     children))))
      (setq +my/beads--statuses statuses
            +my/beads--children children
            +my/beads--titles titles
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
  "ISSUE's status: its icon in its colour, a blocked one's count of open
blockers after it (⊘3); its word in its help (see above)."
  (let* ((status (alist-get 'status issue))
         (blockers (+my/beads--blockers issue))
         (status (cond ((and (equal status "open") (> blockers 0)) "blocked")
                       ((equal status "open") "ready")
                       (t status)))
         (look (or (assoc status +my/beads--statuses-look) (list status "•" 'default)))
         (blocked (and (equal status "blocked") (> blockers 0))))
    (propertize (concat (nth 1 look) (if blocked (format "%d" blockers) ""))
                'face (nth 2 look)
                'help-echo (concat (or (nth 3 look) status)
                                   (if blocked (format " by %d" blockers) "")))))

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

(defun +my/beads--graphic-p ()
  "Whether the list is drawn in a graphic frame: the one of a window showing
it, else the selected one."
  (display-graphic-p (window-frame (or (get-buffer-window (current-buffer) 'visible) (selected-window)))))

(defun +my/beads-format-type (issue)
  "ISSUE's type in its colour: its icon alone in a graphic frame (its word in
its help), its word in a terminal."
  (let* ((type (or (alist-get 'issue_type issue) ""))
         (look (assoc type +my/beads--types-look))
         (face (or (nth 2 look) 'default))
         (icon (and look (+my/beads--graphic-p) (fboundp 'nerd-icons-codicon)
                    (ignore-errors (nerd-icons-codicon (nth 1 look))))))
    (if icon
        (let ((icon (copy-sequence icon)))
          (add-face-text-property 0 (length icon) face nil icon)
          (propertize icon 'help-echo type))
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
  "An epic's progress: DONE of ALL, short (1/11), green once all are done."
  (propertize (format "%d/%d" done all) 'face (if (= done all) 'success 'shadow)))

(defvar-local +my/beads--wrapped-at nil
  "The title's width the list's rows were drawn for: drawn again (in the
background) when its window's width makes it another.")

(defun +my/beads--title-column ()
  "Where the title starts in a row, in columns (the title the last column),
or nil if it isn't the last."
  (when-let* ((format tabulated-list-format)
              ((equal (car (aref format (1- (length format)))) "Title")))
    (+ tabulated-list-padding
       (seq-reduce (lambda (sum column) (+ sum (nth 1 column) (or (plist-get (nthcdr 3 column) :pad-right) 1)))
                   (seq-take format (1- (length format)))
                   0))))

(defun +my/beads--title-width (&optional window)
  "Columns the title has in WINDOW (default: one showing the list), the
window's width less those before it, or nil (no window, the title not the
last column)."
  (when-let* ((window (or window (get-buffer-window (current-buffer) 'visible)))
              (column (+my/beads--title-column)))
    (- (window-body-width window) column 1)))

(defun +my/beads--wrap (words width)
  "WORDS (strings, each kept whole: a tag, an epic's progress) in lines of
WIDTH columns at most, a space between two; a word wider than WIDTH alone on
its line, cut. A list of lines."
  (let ((lines nil) (line nil) (used 0))
    (dolist (word words)
      (let ((w (string-width word)))
        (when (and line (> (+ used 1 w) width))
          (push (string-join (nreverse line) " ") lines)
          (setq line nil used 0))
        (if (and (null line) (> w width))
            (push (truncate-string-to-width word width nil nil "…") lines)
          (push word line)
          (setq used (+ used (if (cdr line) 1 0) w)))))
    (when line (push (string-join (nreverse line) " ") lines))
    (nreverse lines)))

(defun +my/beads--lead-less (title parent)
  "TITLE without the lead (\"Agent workspace: \") it shares with its epic
PARENT's title."
  (let ((case-fold-search nil))
    (if (and parent
             (string-match "\\`[^:\n]\\{1,30\\}: " parent)
             (string-prefix-p (match-string 0 parent) title)
             (> (length title) (match-end 0)))
        (substring title (match-end 0))
      title)))

(defun +my/beads-format-title (issue)
  "ISSUE's title, under its epic's indented and without the lead it shares
with it; after it its progress if it's an epic, its labels as tags. On one
line; with `+my/beads-titles-wrapped', whole: a title too long for the window
goes on to the next lines, under itself (no window, or under 20 columns for
it: on one line)."
  (let* ((id (alist-get 'id issue))
         (depth (or (and +my/beads--depth (gethash id +my/beads--depth)) 0))
         (indent (if (> depth 0)
                     (concat (make-string (* 2 (1- depth)) ?\s) (propertize "└ " 'face 'shadow))
                   ""))
         (counts (and +my/beads--children (gethash id +my/beads--children)))
         (title (or (alist-get 'title issue) ""))
         (title (if (> depth 0)
                    (+my/beads--lead-less title (and +my/beads--titles
                                                     (gethash (alist-get 'parent issue) +my/beads--titles)))
                  title))
         (words (append (split-string title " " t)
                        (and counts (list (+my/beads--progress (car counts) (cdr counts))))
                        (mapcar #'+my/beads--label-tag (append (alist-get 'labels issue) nil))))
         (room (and +my/beads-titles-wrapped (+my/beads--title-width)))
         (column (+my/beads--title-column)))
    ;; Not wrapped: nothing to draw again when the window's resized.
    (setq +my/beads--wrapped-at room)
    ;; Not wrapped (the default), no window, or one so narrow the title would
    ;; be a word a line: on one line, cut at the window's edge.
    (if (or (not room) (< (- room (string-width indent)) 20))
        (concat indent (string-join words " "))
      (let ((lines (+my/beads--wrap words (- room (string-width indent)))))
        (concat indent (car lines)
                ;; The next lines under the first: at the title's column (as
                ;; tabulated-list places its columns), its indent's width on.
                (mapconcat (lambda (line)
                             (concat "\n" (propertize " " 'display `(space :align-to ,column))
                                     (make-string (string-width indent) ?\s) line))
                           (cdr lines) ""))))))

(defconst +my/beads--columns
  '((date 0 +my/beads--no-date)
    (status 3 +my/beads-format-status "St")
    (priority 4 +my/beads-format-priority)
    (type 8 +my/beads-format-type)
    (title 50 +my/beads-format-title))
  "beads.el's list columns drawn here: (COLUMN WIDTH FORMATTER [HEADER]).
The date's empty, its column kept (no gap after it): beads.el's column sort
names it. The type's 2 columns wide in a graphic frame (its icon), 8 in a
terminal (its word).")

(defun +my/beads--no-date (_issue)
  "The date's column: empty (see `+my/beads--columns'). Its text would show
anyway, tabulated-list letting it spill over the room beside it; beads.el's
date sort doesn't read it (it compares the rows' second column)."
  "")

(defun +my/beads-columns ()
  "beads.el's list columns with the look above (see `+my/beads--columns')."
  (setq beads-list--column-defs
        (mapcar (lambda (def)
                  (pcase-let ((`(,column ,header ,width ,sortable ,formatter) def))
                    (if-let* ((look (assq column +my/beads--columns)))
                        (list column (or (nth 3 look) header) (nth 1 look) sortable (nth 2 look))
                      (list column header width sortable formatter))))
                beads-list--column-defs)))

(defun +my/beads-format-a (format)
  "`beads-list--build-format''s FORMAT: no gap after the date's empty column;
the type's column as wide as its icon in a graphic frame (see
`+my/beads--columns')."
  (let ((format (copy-sequence format))
        (graphic (+my/beads--graphic-p)))
    (dotimes (n (length format))
      (pcase (aref format n)
        (`("Date" ,width ,sort . ,props)
         (aset format n `("Date" ,width ,sort :pad-right 0 ,@props)))
        ((and `("Type" ,_ . ,rest) (guard graphic))
         (aset format n (cons "Type" (cons 2 rest))))))
    format))

(defun +my/beads--no-padding-h ()
  "A list: nothing before its rows' marks (beads.el's padding of 2 columns
was for tabulated-list's tags, which it never puts: its marks have their own
column), its header drawn again for it (beads.el's mode drew it already)."
  (setq-local tabulated-list-padding 0)
  (tabulated-list-init-header))

(defun +my/beads--header-string (format)
  "The column headers' string in a header line's FORMAT (tabulated-list's,
maybe within another's: config/banner's), or nil."
  (cond ((and (stringp format) (text-property-not-all 0 (length format) 'tabulated-list-column-name nil format))
         format)
        ((consp format)
         (or (+my/beads--header-string (car format)) (+my/beads--header-string (cdr format))))))

(defun +my/beads-header-a (&rest _)
  "`tabulated-list-init-header', in a list: the date's header shown as
nothing, its column being empty (tabulated-list put \"Date…\" over the
status's header: its 0 columns can't cut it)."
  (when-let* (((derived-mode-p 'beads-list-mode))
              (header (+my/beads--header-string (or tabulated-list--header-string header-line-format)))
              (start (let ((pos 0))
                       ;; By `equal' (`text-property-any' compares with `eq').
                       (while (and pos (not (equal (get-text-property pos 'tabulated-list-column-name header) "Date")))
                         (setq pos (next-single-property-change pos 'tabulated-list-column-name header)))
                       pos))
              (end (next-single-property-change start 'tabulated-list-column-name header (length header))))
    ;; In place: the header line holds this string.
    (put-text-property start end 'display "" header)))

;; A ROW ON SEVERAL LINES: moved over and highlighted whole
(defun +my/beads--row-bounds ()
  "Where the row at point starts and ends: (START . END), its lines' (a
title on several), or nil off a row."
  (when-let* ((id (tabulated-list-get-id)))
    (save-excursion
      (let ((start (line-beginning-position)) (end (line-end-position)))
        (while (and (not (bobp)) (equal (get-text-property (1- start) 'tabulated-list-id) id))
          (goto-char (1- start))
          (setq start (line-beginning-position)))
        (goto-char end)
        (while (and (not (eobp)) (equal (get-text-property (1+ end) 'tabulated-list-id) id))
          (forward-line 1)
          (setq end (line-end-position)))
        (cons start (min (point-max) (1+ end)))))))

(defun +my/beads-next-row (&optional n)
  "To the Nth next row's first line (a title on several lines is a row)."
  (interactive "p")
  (dotimes (_ (abs (or n 1)))
    (if (> (or n 1) 0)
        (let ((bounds (+my/beads--row-bounds)))
          (if bounds (goto-char (cdr bounds)) (forward-line 1))
          (when (eobp) (forward-line -1)))
      (let ((bounds (+my/beads--row-bounds)))
        (goto-char (or (car bounds) (line-beginning-position)))
        (forward-line -1))))
  (when-let* ((bounds (+my/beads--row-bounds)))
    (goto-char (car bounds))))

(defun +my/beads-previous-row (&optional n)
  "To the Nth previous row's first line."
  (interactive "p")
  (+my/beads-next-row (- (or n 1))))

(defun +my/beads--hl-range ()
  "The current line's highlight (hl-line): its whole row."
  (or (+my/beads--row-bounds)
      (cons (line-beginning-position) (line-beginning-position 2))))

(defvar-local +my/beads--rewrap-timer nil)

(defun +my/beads--resized-h (window)
  "WINDOW showing the list, resized: its titles wrapped again for its width
\(in the background, a moment after its last change: a border dragged)."
  (let ((buffer (window-buffer window)))
    (with-current-buffer buffer
      (when (and +my/beads--wrapped-at
                 (not (equal (+my/beads--title-width window) +my/beads--wrapped-at)))
        (when (timerp +my/beads--rewrap-timer) (cancel-timer +my/beads--rewrap-timer))
        (setq +my/beads--rewrap-timer
              (run-with-timer 0.3 nil (lambda ()
                                        (when (buffer-live-p buffer)
                                          (with-current-buffer buffer
                                            (setq +my/beads--rewrap-timer nil)
                                            (+my/beads-refresh-async buffer t))))))))))

(defun +my/beads--rows-h ()
  "A list: its rows highlighted whole, redrawn when its window's width changes."
  (setq-local hl-line-range-function #'+my/beads--hl-range)
  (add-hook 'window-size-change-functions #'+my/beads--resized-h nil t))

;; AN EPIC'S ISSUES UNDER IT
(defun +my/beads--child< (a b)
  "Whether issue A comes before B under their epic (see below)."
  (let ((key (lambda (issue)
               (list (if (equal (alist-get 'status issue) "in_progress") 0 1)
                     (alist-get 'priority issue 2)))))
    (let ((ka (funcall key a)) (kb (funcall key b)))
      (if (equal ka kb)
          (string-version-lessp (alist-get 'id a) (alist-get 'id b))
        (or (< (car ka) (car kb))
            (and (= (car ka) (car kb)) (< (cadr ka) (cadr kb))))))))

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
    ;; In a steady order (bd's changes for issues made in the same second):
    ;; in progress first, then by priority, then by id (.2 before .10).
    (maphash (lambda (parent issues)
               (puthash parent (sort issues #'+my/beads--child<) children))
             children)
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
  (advice-add 'beads-list--build-format :filter-return #'+my/beads-format-a)
  (advice-add 'tabulated-list-init-header :after #'+my/beads-header-a)
  (add-hook 'beads-list-mode-hook #'+my/beads--no-padding-h)
  (add-hook 'beads-list-mode-hook #'+my/beads--rows-h)
  (advice-add 'beads-list--issue-section :around #'+my/beads-section-a)
  (advice-add 'beads-list--sectioned-sort :filter-return #'+my/beads-nest-a)
  (advice-add 'beads-list--print-entry :override #'+my/beads-print-entry-a))
