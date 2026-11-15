;;; tests/unit/test-beads-look.el -*- lexical-binding: t; -*-
;; config/beads.el: the issue list's and an issue's look: columns, tags, titles
;; wrapped, marks, two lists, narrow panes, an issue's sections (shared:
;; tests/helper-beads.el).
;; run.sh: slow (~125 s: the real bd).

(load (expand-file-name "../helper-beads" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== THE LOOK ======

(defun +test-beads--faces-at (text)
  "The faces on TEXT's first character (its case), in the current buffer: a
list of faces (names, plists)."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (search-forward text))
    (let ((face (get-text-property (match-beginning 0) 'face)))
      (if (keywordp (car-safe face)) (list face) (ensure-list face)))))

(ert-deftest beads/look-the-columns ()
  "Statuses as icons in their colours (ready: open, nothing open blocking), a
blocked one's count of blockers after it, their words in their help;
priorities as badges; types as their icons alone in a graphic frame, their
words in a terminal."
  (let ((+my/beads--statuses (make-hash-table :test #'equal)))
    (puthash "t-2" "open" +my/beads--statuses)
    (puthash "t-3" "closed" +my/beads--statuses)
    (should (equal (+my/beads-format-status '((status . "open"))) "○"))
    (should (equal (+my/beads-format-status '((status . "in_progress"))) "◔"))
    (should (equal (+my/beads-format-status '((status . "closed"))) "✓"))
    (should (equal (+my/beads-format-status '((status . "deferred"))) "◇"))
    (should (equal (get-text-property 0 'help-echo (+my/beads-format-status '((status . "in_progress"))))
                   "in progress"))
    ;; Blocked by an open issue, not by a closed one.
    (should (equal (+my/beads-format-status
                    '((status . "open") (dependencies . [((type . "blocks") (depends_on_id . "t-2"))
                                                         ((type . "blocks") (depends_on_id . "t-3"))
                                                         ((type . "parent-child") (depends_on_id . "t-2"))])))
                   "⊘1"))
    (should (equal (get-text-property
                    0 'help-echo (+my/beads-format-status
                                  '((status . "open") (dependencies . [((type . "blocks") (depends_on_id . "t-2"))]))))
                   "blocked by 1"))
    ;; Being worked on: in progress, blockers or not.
    (should (equal (+my/beads-format-status
                    '((status . "in_progress") (dependencies . [((type . "blocks") (depends_on_id . "t-2"))])))
                   "◔"))
    (should (memq 'success (ensure-list (get-text-property 0 'face (+my/beads-format-status '((status . "open"))))))))
  ;; Badges: the theme's red and orange (else its faces, inverted).
  (should (equal (get-text-property 1 'face (+my/beads-format-priority '((priority . 0))))
                 '(:inherit error :inverse-video t :weight bold)))
  (cl-letf (((symbol-function 'doom-color) (lambda (name &rest _) (if (eq name 'orange) "#da8548" "#ff6c6b")))
            ((symbol-function 'face-background)
             (lambda (face &rest _) (if (eq face 'default) "#282c34" "#000000"))))
    (should (equal (get-text-property 1 'face (+my/beads-format-priority '((priority . 1))))
                   `(:foreground "#da8548" :background ,(doom-blend "#da8548" "#282c34" 0.25) :weight bold)))
    (should (equal (get-text-property 1 'face (+my/beads--label-tag "parser"))
                   `(:foreground "#ff6c6b" :background ,(doom-blend "#ff6c6b" "#282c34" 0.25)))))
  (should (equal (+my/beads-format-priority '((priority . 2))) " P2 "))
  (should (eq (get-text-property 1 'face (+my/beads-format-priority '((priority . 4)))) 'shadow))
  ;; A type: its word in a terminal; its icon alone in a graphic frame.
  (should (equal (+my/beads-format-type '((issue_type . "bug"))) "bug"))
  (should (eq (get-text-property 0 'face (+my/beads-format-type '((issue_type . "bug")))) 'error))
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
    (let ((type (+my/beads-format-type '((issue_type . "epic")))))
      (should (= (length type) 1))
      (should (equal (get-text-property 0 'help-echo type) "epic"))
      (should (equal (plist-get (seq-find #'consp (ensure-list (get-text-property 0 'face type))) :family)
                     "Symbols Nerd Font Mono")))))

(ert-deftest beads/look-tags-and-progress ()
  "Labels as tags, a colour each, the same each time; an epic's progress."
  (let ((tag (+my/beads--label-tag "parser")))
    (should (equal (substring-no-properties tag) " parser "))
    (should (equal (get-text-property 0 'face tag) (get-text-property 0 'face (+my/beads--label-tag "parser"))))
    (should-not (equal (get-text-property 0 'face tag) (get-text-property 0 'face (+my/beads--label-tag "crash")))))
  (should (equal (substring-no-properties (+my/beads--progress 1 3)) "1/3"))
  (should (eq (get-text-property 0 'face (+my/beads--progress 1 3)) 'shadow))
  (should (equal (substring-no-properties (+my/beads--progress 0 0)) "0/0"))
  (should (eq (get-text-property 0 'face (+my/beads--progress 4 4)) 'success)))

;; doom-o5t.1
(ert-deftest beads/look-a-title-whole ()
  "A title on one line (the default); wrapped, one too long for the window
goes on to the next lines, under itself (at its column, its indent's width
on); its progress and tags after it, each kept whole; an epic's issue
without the lead it shares with it."
  (should (equal (+my/beads--wrap '("aa" "bb" "cc" "dd") 5) '("aa bb" "cc dd")))
  (should (equal (+my/beads--wrap '("aa" " tag one ") 9) '("aa" " tag one ")))
  (should (equal (+my/beads--wrap '("abcdefghij") 4) '("abc…")))
  (should (equal (+my/beads--lead-less "Agent workspace: core" "Agent workspace: a crew") "core"))
  (should (equal (+my/beads--lead-less "Agent UI: core" "Agent workspace: a crew") "Agent UI: core"))
  (should (equal (+my/beads--lead-less "Agent workspace: " "Agent workspace: a crew") "Agent workspace: "))
  (let ((+my/beads--depth (make-hash-table :test #'equal))
        (+my/beads--titles (make-hash-table :test #'equal))
        (+my/beads--children (make-hash-table :test #'equal))
        (+my/beads--wrapped-at nil))
    (puthash "e.1" 1 +my/beads--depth)
    (puthash "e" "Parser: the rewrite" +my/beads--titles)
    (puthash "e" '(1 . 3) +my/beads--children)
    (cl-letf (((symbol-function '+my/beads--title-width) (lambda (&rest _) 24))
              ((symbol-function '+my/beads--title-column) (lambda () 30)))
      ;; Not wrapped, the default: on one line, nothing to draw again on a
      ;; resize.
      (should-not +my/beads-titles-wrapped)
      (should (equal (substring-no-properties
                      (+my/beads-format-title '((id . "e") (title . "Parser: the rewrite of the lexer"))))
                     "Parser: the rewrite of the lexer 1/3"))
      (should (equal +my/beads--wrapped-at nil))
      (let ((+my/beads-titles-wrapped t))
        ;; An epic: its title on two lines, its progress after it.
        (let ((title (+my/beads-format-title '((id . "e") (title . "Parser: the rewrite of the lexer")))))
          (should (equal (substring-no-properties title) "Parser: the rewrite of\n the lexer 1/3"))
          (should (equal (get-text-property (string-search "\n" title) 'display title) nil))
          (should (equal (get-text-property (1+ (string-search "\n" title)) 'display title) '(space :align-to 30))))
        ;; Its issue, indented, its lead left out, its next line under its text.
        (let ((title (+my/beads-format-title '((id . "e.1") (parent . "e") (labels . ["ui"])
                                               (title . "Parser: errors recovered from, line by line")))))
          (should (equal (substring-no-properties title) "└ errors recovered from,\n   line by line  ui ")))
        (should (equal +my/beads--wrapped-at 24))))
    (let ((+my/beads-titles-wrapped t))
      ;; Under 20 columns for it: on one line.
      (cl-letf (((symbol-function '+my/beads--title-width) (lambda (&rest _) 19)))
        (should (equal (substring-no-properties (+my/beads-format-title '((id . "x") (title . "One line, however long"))))
                       "One line, however long")))
      ;; No window: on one line.
      (cl-letf (((symbol-function '+my/beads--title-width) #'ignore))
        (should (equal (substring-no-properties (+my/beads-format-title '((id . "x") (title . "One line, however long"))))
                       "One line, however long"))))))

(ert-deftest beads/look-a-row-on-several-lines ()
  "A row on several lines: j and k go from row to row, hl-line highlights it
whole."
  (with-temp-buffer
    (dolist (row '(("a" "a one") ("b" "b one\n  b two\n  b three") ("c" "c one")))
      (insert (propertize (concat (cadr row) "\n") 'tabulated-list-id (car row))))
    (goto-char (point-min))
    (+my/beads-next-row)
    (should (equal (tabulated-list-get-id) "b"))
    (should (looking-at "b one"))
    (should (equal (buffer-substring (car (+my/beads--hl-range)) (cdr (+my/beads--hl-range)))
                   "b one\n  b two\n  b three\n"))
    (forward-line 2)
    (should (equal (car (+my/beads--hl-range)) (save-excursion (search-backward "b one"))))
    (+my/beads-next-row)
    (should (looking-at "c one"))
    (+my/beads-next-row)
    (should (looking-at "c one"))
    (+my/beads-previous-row)
    (should (looking-at "b one"))
    (+my/beads-previous-row 1)
    (should (looking-at "a one"))
    (+my/beads-previous-row)
    (should (looking-at "a one"))))

(ert-deftest beads/an-epic-s-issues-in-a-steady-order ()
  "Whatever order bd gives them in: in progress first, then by priority, then
by id (.2 before .10)."
  (let* ((epic '((id . "t-1") (status . "open") (priority . 1)))
         (child (lambda (n status priority)
                  `((id . ,(format "t-1.%d" n)) (status . ,status) (priority . ,priority) (parent . "t-1"))))
         (issues (list epic (funcall child 10 "open" 2) (funcall child 2 "open" 2)
                       (funcall child 3 "open" 1) (funcall child 4 "in_progress" 3)))
         (ids (lambda (list) (mapcar (lambda (i) (alist-get 'id i)) list)))
         (+my/beads--statuses nil))
    (should (equal (funcall ids (+my/beads-nest-a issues)) '("t-1" "t-1.4" "t-1.3" "t-1.2" "t-1.10")))
    (should (equal (funcall ids (+my/beads-nest-a (cons epic (reverse (cdr issues)))))
                   '("t-1" "t-1.4" "t-1.3" "t-1.2" "t-1.10")))
    (should (equal (gethash "t-1.10" +my/beads--depth) 1))))

(ert-deftest beads/bd-the-look ()
  "An epic, its issues under it (indented, in its section), its progress
counting its closed one; labels as tags; one blocked by an open bug in the
Blocked section; a closed row dimmed."
  (+test-beads-with-project
    (let* ((epic (+test-beads--create "The parser rewrite" :issue-type "epic" :priority 1))
           (lexer (+test-beads--create "Lexer: tokens" :issue-type "task" :parent epic))
           (parser (+test-beads--create "Parser: recovery" :issue-type "feature" :parent epic))
           (old (+test-beads--create "Old parser removed" :issue-type "chore" :parent epic))
           (bug (+test-beads--create "Crash on an empty file" :issue-type "bug" :priority 0))
           (release (+test-beads--create "Release 2.0")))
      (ignore lexer parser)
      (beads-client-request "label_add" `((id . ,bug) (label . "crash")))
      (beads-client-request "dep_add" `((from_id . ,release) (to_id . ,bug)))
      (beads-client-close old "Done")
      (+my/beads-project)
      (with-current-buffer (+test-beads--list)
        (let ((lines (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n" t)))
          ;; The epic, then its two open issues, indented.
          (let ((at (seq-position lines (+test-beads--line "The parser rewrite"))))
            (should (string-match-p "The parser rewrite 1/3" (nth at lines)))
            (should (string-match-p "└ Lexer: tokens" (nth (1+ at) lines)))
            (should (string-match-p "└ Parser: recovery" (nth (+ 2 at) lines))))
          ;; Blocked: last of the open ones, in its section.
          (should (string-match-p "⊘1 .*Release 2.0" (car (last lines))))
          (should (= (beads-list--issue-section (beads-client-show release)) 1))
          (should (= (beads-list--issue-section (seq-find (lambda (i) (equal (alist-get 'id i) release))
                                                          beads-list--issues))
                     1)))
        (should (string-match-p "Crash on an empty file +crash" (+test-beads--line "Crash on")))
        ;; In a P0 row: the tag's face first, the row's tint under it.
        (let ((faces (+test-beads--faces-at " crash ")))
          (should (equal (car faces) (get-text-property 0 'face (+my/beads--label-tag "crash"))))
          (should (memq 'beads-list-row-p0 faces)))
        ;; Closed, shown: dimmed, in the Completed section (not under its epic).
        (+my/beads-show-closed)
        (should (string-match-p "✓ .*Old parser removed" (+test-beads--line "Old parser removed")))
        (should (memq 'shadow (+test-beads--faces-at "Old parser removed")))
        (should-not (memq 'shadow (+test-beads--faces-at "Crash on")))))))

;; doom-o5t.2
(ert-deftest beads/look-no-gap-after-the-date ()
  "The date's empty column has no gap after it, in a terminal and a graphic
frame; only a graphic frame narrows the type's to its icon."
  (let ((format (vector '(" " 1 nil) '("ID" 9 t) '("Date" 0 beads-list--sort-by-date)
                        '("St" 3 t) '("Type" 8 t) '("Title" 50 t))))
    (should (equal (aref (+my/beads-format-a format) 2) '("Date" 0 beads-list--sort-by-date :pad-right 0)))
    (should (equal (aref (+my/beads-format-a format) 4) '("Type" 8 t)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (should (equal (aref (+my/beads-format-a format) 2) '("Date" 0 beads-list--sort-by-date :pad-right 0)))
      (should (equal (aref (+my/beads-format-a format) 4) '("Type" 2 t))))
    ;; beads.el's own, untouched.
    (should (equal (aref format 2) '("Date" 0 beads-list--sort-by-date)))))

(ert-deftest beads/bd-the-columns-from-the-left-edge ()
  "A row starts with its mark's column (nothing before it), the id after its
gap, the status right after the id's (no gap for the empty date); the title
where it's said to start; the header over them; a marked row's *."
  (+test-beads-with-project
    (let ((id (+test-beads--create "Lexer: tokens" :issue-type "task")))
      (+my/beads-project)
      (with-current-buffer (+test-beads--list)
        (should (= tabulated-list-padding 0))
        (let ((line (+test-beads--line "Lexer: tokens")))
          ;; One issue: its id fills its column.
          (should (string-prefix-p (concat "  " id " ○") line))
          ;; Mark, id, status, priority, type (its word: a terminal), each
          ;; with its gap.
          (should (= (+my/beads--title-column) (+ 2 (1+ (length id)) 4 5 9)))
          (should (= (string-search "Lexer: tokens" line) (+my/beads--title-column))))
        ;; The header's ID over the ids.
        (let* ((header (+my/beads--header-string header-line-format))
               (at (string-search "ID" header)))
          (should (equal (get-text-property (1- at) 'display header)
                         '(space :align-to (+ header-line-indent-width 2)))))
        (goto-char (point-min))
        (search-forward id)
        (beads-list-mark)
        (should (string-prefix-p (concat "* " id " ○") (+test-beads--line "Lexer: tokens")))))))

;; doom-o5t.4
(defun +test-beads--view ()
  "The current list as it's seen: its text, the sections' separators (their
overlays' strings) where they are."
  (let ((overlays (sort (seq-filter (lambda (o) (overlay-get o 'before-string))
                                    (overlays-in (point-min) (point-max)))
                        (lambda (a b) (< (overlay-start a) (overlay-start b)))))
        (view "") (pos (point-min)))
    (dolist (o overlays)
      (setq view (concat view (buffer-substring-no-properties pos (overlay-start o))
                         (substring-no-properties (overlay-get o 'before-string)))
            pos (overlay-start o)))
    (concat view (buffer-substring-no-properties pos (point-max)))))

(ert-deftest beads/a-mark-on-a-row-of-several-lines ()
  "A row on several lines (its title wrapped): its mark on its first line
only, its next lines untouched."
  (with-temp-buffer
    (let ((entry (vector " " "b")) (beads-list--marked '("b")))
      (insert (propertize " " 'tabulated-list-column-name " ") " "
              (propertize "b one" 'tabulated-list-column-name "Title")
              (propertize "\n" 'tabulated-list-column-name "Title")
              (propertize " " 'tabulated-list-column-name "Title") "b two\n")
      (put-text-property (point-min) (point-max) 'tabulated-list-id "b")
      (put-text-property (point-min) (point-max) 'tabulated-list-entry entry)
      (+my/beads-update-marks)
      (should (equal (buffer-string) "* b one\n b two\n"))
      (should (equal (aref entry 0) "*"))
      (should (equal (get-text-property 0 'tabulated-list-id (buffer-string)) "b")))))

(ert-deftest beads/bd-a-mark-changes-only-the-marks ()
  "m, u, t and U change a row's mark, in place: the rows' order (an epic's
issues under it, the blocked one in Blocked), the separators, a P0's tint and
the place stay (beads.el printed the list again: Blocked at its top, every
issue under it)."
  (+test-beads-with-project
    (let* ((epic (+test-beads--create "The parser rewrite" :issue-type "epic" :priority 1))
           (lexer (+test-beads--create "Lexer: tokens" :issue-type "task" :parent epic))
           (bug (+test-beads--create "Crash on an empty file" :issue-type "bug" :priority 0))
           (release (+test-beads--create "Release 2.0")))
      (ignore lexer)
      (beads-client-request "dep_add" `((from_id . ,release) (to_id . ,bug)))
      (+my/beads-project)
      (with-current-buffer (+test-beads--list)
        (let ((before (+test-beads--view))
              (marked (lambda (view id) (replace-regexp-in-string (concat "^  " (regexp-quote id) " ")
                                                                  (concat "* " id " ") view t t))))
          (should (string-match-p "── Blocked ──\n  [^\n]*Release 2.0" before))
          (goto-char (point-min))
          (search-forward "The parser rewrite")
          (beads-list-mark)
          (should (equal (+test-beads--view) (funcall marked before epic)))
          ;; The place: the next row, as beads.el's m goes.
          (should (equal (tabulated-list-get-id) lexer))
          (should (equal (aref (tabulated-list-get-entry (save-excursion (search-backward epic))) 0) "*"))
          ;; A P0's row: its mark in its tint.
          (goto-char (point-min))
          (search-forward bug)
          (beads-list-mark)
          (should (equal (+test-beads--view) (funcall marked (funcall marked before epic) bug)))
          (should (memq 'beads-list-row-p0 (ensure-list (get-text-property (line-beginning-position 0) 'face))))
          ;; u, t, U.
          (forward-line -1)
          (beads-list-unmark)
          (should (equal (+test-beads--view) (funcall marked before epic)))
          (beads-list-toggle-marks)
          (should-not (member epic beads-list--marked))
          (should (string-match-p (concat "^\\* " (regexp-quote release)) (+test-beads--view)))
          (beads-list-unmark-all)
          (should (equal (+test-beads--view) before)))))))

;; doom-o5t.5
(ert-deftest beads/bd-two-lists-each-its-own-issues ()
  "Two projects' lists open: each keeps its own issues (beads.el kept one
list of them for all, the last refreshed): its separators, t (toggle marks)
and the issue at point are its own, the other refreshed after it."
  (+test-beads-with-project
    (let* ((bug (+test-beads--create "Crash" :issue-type "bug" :priority 0))
           (release (+test-beads--create "Release"))
           (other (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-other-") t))))
           (ids (lambda () (sort (mapcar (lambda (issue) (alist-get 'id issue)) beads-list--issues) #'string<)))
           (first nil) (second nil) (elsewhere nil))
      (beads-client-request "dep_add" `((from_id . ,release) (to_id . ,bug)))
      (+my/beads-project)
      (setq first (+test-beads--list))
      ;; Another project, its list opened (refreshed) after the first.
      (let ((default-directory other))
        (+test-bd-init "--quiet" "--prefix" "u")
        (setq elsewhere (+test-beads--create "Elsewhere"))
        (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) other)))
          (+my/beads-project)))
      (setq second (seq-find (lambda (b) (and (not (eq b first))
                                              (with-current-buffer b (derived-mode-p 'beads-list-mode))))
                             (buffer-list)))
      (should second)
      (should (local-variable-p 'beads-list--issues first))
      (with-current-buffer second
        (should (equal (funcall ids) (list elsewhere))))
      (with-current-buffer first
        (should (equal (funcall ids) (sort (list bug release) #'string<)))
        ;; t: its own issues marked.
        (beads-list-toggle-marks)
        (should (equal (sort (copy-sequence beads-list--marked) #'string<) (sort (list bug release) #'string<)))
        ;; Its separators drawn again (as a refresh does): Blocked over its own.
        (beads-list--add-section-separators)
        (should (string-match-p "── Blocked ──\n\\* [^\n]*Release" (+test-beads--view)))
        ;; The issue at point.
        (goto-char (point-min))
        (search-forward "Crash")
        (should (equal (alist-get 'id (beads-list--get-issue-at-point)) bug))))))

;; doom-o5t.6
(ert-deftest beads/bd-same-named-projects-each-its-list ()
  "Two projects of the same folder name: two lists, each with its own issues
when opened and after gr, bd run at its root (an issue made from it is its
project's); SPC o i again, the same list (beads.el named a list by the
folder's name only: one list, the first project's issues)."
  (+test-beads-with-project
    (let* ((name (file-name-nondirectory (directory-file-name repo)))
           (other (file-name-as-directory
                   (expand-file-name name (file-truename (make-temp-file (+test-tmp-file "beads-elsewhere-") t)))))
           (here (+test-beads--create "Here"))
           (ids (lambda (list) (with-current-buffer list (sort (mapcar #'car tabulated-list-entries) #'string<))))
           elsewhere first second)
      (make-directory other)
      (let ((default-directory other))
        (+test-bd-init "--quiet" "--prefix" "u")
        (setq elsewhere (+test-beads--create "Elsewhere")))
      (+my/beads-project)
      (setq first (window-buffer (selected-window)))
      ;; From a file of the other project.
      (let ((file (find-file-noselect (expand-file-name "README" other))))
        (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) other)))
          (switch-to-buffer file)
          (+my/beads-project)
          (setq second (window-buffer (selected-window)))
          (switch-to-buffer file)
          (+my/beads-project)
          (should (eq (window-buffer (selected-window)) second)))
        (kill-buffer file))
      (should (with-current-buffer second (derived-mode-p 'beads-list-mode)))
      (should-not (eq first second))
      (should (equal (buffer-name first) (format "*Beads: %s*" name)))
      (should (equal (buffer-name second)
                     (format "*Beads: %s/%s*" (file-name-nondirectory (directory-file-name (file-name-directory (directory-file-name other)))) name)))
      (should (equal (buffer-local-value 'default-directory first) repo))
      (should (equal (buffer-local-value 'default-directory second) other))
      (should (equal (funcall ids first) (list here)))
      (should (equal (funcall ids second) (list elsewhere)))
      ;; gr in each.
      (dolist (list (list first second))
        (with-current-buffer list (beads-list-refresh t)))
      (should (equal (funcall ids first) (list here)))
      (should (equal (funcall ids second) (list elsewhere)))
      ;; c (bd run where the list is): in its own project.
      (let ((new (with-current-buffer second (+test-beads--create "Made from the second list"))))
        (should (string-prefix-p "u-" new))
        (with-current-buffer second (beads-list-refresh t))
        (with-current-buffer first (beads-list-refresh t))
        (should (equal (funcall ids second) (sort (list elsewhere new) #'string<)))
        (should (equal (funcall ids first) (list here)))))))

;; doom-o5t.7
(ert-deftest beads/bd-an-issue-s-parent-and-children ()
  "P on an epic's issue opens the epic, its view says Parent: ID; C on the
epic shows the project's list, its issues only, the filter said (bd 1.x says
parent, beads.el read parent_id: no parent; C errored)."
  (+test-beads-with-project
    (let* ((epic (+test-beads--create "The parser rewrite" :issue-type "epic"))
           (lexer (+test-beads--create "Lexer" :parent epic))
           (parser (+test-beads--create "Parser" :parent epic))
           (other (+test-beads--create "Unrelated")))
      (ignore other)
      (should (equal (alist-get 'parent_id (beads-client-show lexer)) epic))
      (should (equal (alist-get 'parent_id (seq-find (lambda (i) (equal (alist-get 'id i) parser))
                                                     (beads-client-list)))
                     epic))
      (+my/beads-project)
      (let ((list (+test-beads--list)))
        (beads-detail-open (beads-client-show lexer))
        (with-current-buffer (format "*Beads Detail: %s*" lexer)
          (should (string-match-p (concat "Parent: +\\[" (regexp-quote epic) "\\]") (+test-beads--text (current-buffer))))
          (beads-detail-goto-parent))
        (should (equal (buffer-name (window-buffer (selected-window))) (format "*Beads Detail: %s*" epic)))
        (with-current-buffer (format "*Beads Detail: %s*" epic)
          (beads-detail-view-children))
        (should (eq (window-buffer (selected-window)) list))
        (with-current-buffer list
          (should (equal (sort (mapcar #'car tabulated-list-entries) #'string<)
                         (sort (list lexer parser) #'string<)))
          (should (equal (+test-beads--notices)
                         `((,(format "Filtered: children of %s." epic) ("Clear filter")))))
          ;; In the background too.
          (+my/beads-refresh-async list)
          (+test-beads--settle list)
          (should (equal (sort (mapcar #'car tabulated-list-entries) #'string<)
                         (sort (list lexer parser) #'string<))))))))

;; doom-o5t.8
(ert-deftest beads/bd-an-issue-s-notes-comments-dependents ()
  "An issue's view: its notes, as Markdown; a comment added with c, after
the refresh; a blocker's lists what it blocks, an epic's its issues
\(beads.el drew no notes, and bd 1.x leaves comments and dependents out
unless asked)."
  (+test-beads-with-project
    (let* ((epic (+test-beads--create "The epic" :issue-type "epic"))
           (child (+test-beads--create "Its issue" :parent epic))
           (blocker (+test-beads--create "The blocker"))
           (blocked (+test-beads--create "The blocked one")))
      (beads-client-request "dep_add" `((from_id . ,blocked) (to_id . ,blocker)))
      (beads-client-update child :notes "Reported again, **twice**")
      (should (equal (beads-backend-bd--operation-to-cli-args "show" `((id . ,child)))
                     (list "show" child "--include-comments" "--include-dependents")))
      (beads-detail-open (beads-client-show child))
      (with-current-buffer (format "*Beads Detail: %s*" child)
        (should (string-match-p "^Notes: +\\[edit\\]\n +Reported again, \\*\\*twice\\*\\*"
                                (+test-beads--text (current-buffer))))
        (should (memq 'markdown-bold-face (+test-beads--faces-at "twice")))
        ;; c: a comment, shown once added.
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "A comment from Emacs")))
          (beads-detail-add-comment))
        (should (string-match-p "Comments (1):\n\n\\[Tester\\] .*\nA comment from Emacs"
                                (+test-beads--text (current-buffer)))))
      (beads-detail-open (beads-client-show blocker))
      (with-current-buffer (format "*Beads Detail: %s*" blocker)
        (should (string-match-p (format "Dependents:\n +\\[%s\\] +The blocked one" (regexp-quote blocked))
                                (+test-beads--text (current-buffer)))))
      (beads-detail-open (beads-client-show epic))
      (with-current-buffer (format "*Beads Detail: %s*" epic)
        (should (string-match-p (format "Dependents:\n +\\[%s\\] +Its issue" (regexp-quote child))
                                (+test-beads--text (current-buffer))))))))

;; doom-o5t.9
(defun +test-beads--header-shown ()
  "The current list's column titles as shown: without those shown as nothing."
  (let ((header (+my/beads--header-string header-line-format))
        (shown ""))
    (dotimes (n (length header))
      (unless (equal (get-text-property n 'display header) "")
        (setq shown (concat shown (substring-no-properties header n (1+ n))))))
    shown))

(ert-deftest beads/bd-a-narrow-pane-the-title-s-room ()
  "A list in a pane under 60 columns (a graphic frame's): no id, the title
from column 14 (25 of its characters at 40 columns, some at 25), from the
start (SPC o i: drawn once shown) and when a pane narrows; 60 columns or
more, the id back where it was. No column title cut (\"T…\")."
  (+test-beads-with-project
    (let* ((+my/beads--narrow-width 60)
           (id (+test-beads--create "Lexer: tokens, read in a pane narrower than the title is long"))
           (row (lambda () (+test-beads--line "Lexer: tokens"))))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
        (+my/beads-project)
        (let* ((list (+test-beads--list))
               (window (get-buffer-window list)))
          (should (< (window-body-width window) 60))
          (with-current-buffer list
            (should +my/beads--narrow)
            (should (= (+my/beads--title-column) 14))
            (should-not (string-search id (funcall row)))
            (should (string-prefix-p "  ○ " (funcall row)))
            (should-not (string-search "…" (+test-beads--header-shown)))
            (should-not (string-search "ID" (+test-beads--header-shown)))
            (should (string-search "Title" (+test-beads--header-shown))))
          ;; 40 and 25 columns: the title's room.
          (+test-beads--width window 40)
          (with-current-buffer list
            (should (>= (+my/beads--title-width window) 25)))
          (+test-beads--width window 25)
          (with-current-buffer list
            (should (> (+my/beads--title-width window) 0)))
          ;; Wider: drawn again (in the background), the id back.
          (delete-other-windows window)
          (+test-beads--width window (window-body-width window))
          (should (>= (window-body-width window) 60))
          (with-current-buffer list
            (should +my/beads--rewrap-timer)
            (should (+test-wait-for (lambda () (not +my/beads--rewrap-timer)) 5))
            (+test-beads--settle list)
            (should-not +my/beads--narrow)
            (should (string-prefix-p (concat "  " id " ○") (funcall row)))
            (should (= (+my/beads--title-column) (+ 2 (1+ (length id)) 4 5 3)))
            (should-not (string-search "…" (+test-beads--header-shown)))
            (should (string-search "ID" (+test-beads--header-shown))))
          ;; Narrower again: drawn again, narrow.
          (split-window window nil 'right)
          (+test-beads--width window 40)
          (with-current-buffer list
            (should (+test-wait-for (lambda () (not +my/beads--rewrap-timer)) 5))
            (+test-beads--settle list)
            (should +my/beads--narrow)
            (should-not (string-search id (funcall row)))))))))

;; doom-o5t.11
(defun +test-beads--row-lines (text)
  "How many lines the current list's row showing TEXT takes."
  (save-excursion
    (goto-char (point-min))
    (search-forward text)
    (let ((bounds (+my/beads--row-bounds)))
      (count-lines (car bounds) (cdr bounds)))))

(defun +test-beads--redrawn (list)
  "LIST's redraw on its way (a window's width changed) done."
  (with-current-buffer list
    (should (+test-wait-for (lambda () (not +my/beads--rewrap-timer)) 5)))
  (+test-beads--settle list))

(ert-deftest beads/bd-titles-wrapped-in-every-window ()
  "Titles wrapped: a list drawn in no window (M-x beads-list: beads.el draws
it, then shows it) wrapped once a window shows it; in two windows, for the
narrower (no word cut in it). beads.el's: not wrapped until resized; wrapped
for one window, cut in the other."
  (+test-beads-with-project
    (let ((+my/beads-titles-wrapped t)
          (title "Lexer: tokens read from a file far longer than the pane is wide, on two lines"))
      (+test-beads--create title)
      (delete-other-windows)
      (beads-list)
      (let* ((list (+test-beads--list))
             (window (get-buffer-window list)))
        (should (eq (window-buffer (selected-window)) list))
        (with-current-buffer list
          (should (eq +my/beads--wrapped-at 'unshown))
          (should (= (+test-beads--row-lines "Lexer") 1))
          ;; The first row's bounds, point off its start.
          (goto-char (point-min))
          (forward-char 3)
          (should (equal (+my/beads--hl-range) (cons (point-min) (line-beginning-position 2)))))
        ;; Shown (as redisplay calls the window change functions).
        (with-current-buffer list
          (run-hook-with-args 'window-buffer-change-functions window))
        (+test-beads--redrawn list)
        (with-current-buffer list
          (should (equal +my/beads--wrapped-at (+my/beads--title-width window)))
          (should (= (+test-beads--row-lines "Lexer") 2)))
        ;; Another window on it, narrower (the first one selected); both
        ;; narrow, in a graphic frame: room for titles in both.
        (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
          (let* ((+my/beads--narrow-width 60)
                 (narrower (split-window window 41 'right)))
            (set-window-buffer narrower list)
            (should (< (window-body-width narrower) (window-body-width window)))
            (with-current-buffer list
              (run-hook-with-args 'window-buffer-change-functions narrower))
            (+test-beads--redrawn list)
            (with-current-buffer list
              (should (equal +my/beads--wrapped-at (+my/beads--title-width narrower)))
              (should (< +my/beads--wrapped-at (+my/beads--title-width window)))
              (should (> (+test-beads--row-lines "Lexer") 2)))))))))

;; AN ISSUE'S SECTIONS
(defun +test-beads--section (width &rest props)
  "An issue's section (`beads-vui-content-section', PROPS) drawn in a pane
WIDTH columns wide: its lines."
  (require 'beads-vui)
  (let ((buffer (get-buffer-create "*test-beads-section*")))
    (delete-other-windows)
    (let ((window (split-window nil nil 'right)))
      (window-resize window (- width (window-width window)) t)
      (should (= (window-width window) width))
      (set-window-buffer window buffer)
      (vui-mount (apply #'vui-component 'beads-vui-content-section props) (buffer-name buffer) t)
      (split-string (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))
                    "\n"))))

(ert-deftest beads/an-issue-s-section-every-line-indented ()
  "A section's text (a description...): every line of it indented, not only
its first (vui's); empty lines left empty."
  (+test-with-reset
    (let ((beads-detail-section-style 'heading))
      (should (equal (seq-take (+test-beads--section 60 :title "Description"
                                                     :content "The first line.\nThe second.\n\n- an item\n  its next line")
                               6)
                     '("Description:" "  The first line." "  The second." "" "  - an item" "    its next line")))
      (should (equal (seq-take (+test-beads--section 60 :title "Notes" :content "") 2)
                     '("Notes:" "  (empty)"))))))

(ert-deftest beads/an-issue-s-section-separator-fits-the-pane ()
  "`beads-detail-section-style' separator: its rule across the pane at 25,
40 and 60 columns (but the last), its [edit] at its end (it drew 60
characters, two or three screen lines in a narrow pane)."
  (+test-with-reset
    (let ((beads-detail-section-style 'separator))
      (dolist (width '(25 40 60))
        (let ((lines (+test-beads--section width :title "Description" :content "One.\nTwo."
                                           :on-edit #'ignore)))
          (should (string-match-p "\\`─+ \\[edit\\]\\'" (car lines)))
          (should (= (string-width (car lines)) (1- width)))
          (should (equal (seq-take (cdr lines) 4) '("Description:" "" "One." "Two."))))
        (let ((lines (+test-beads--section width :title "Design Notes" :content "")))
          (should (string-match-p "\\`─+\\'" (car lines)))
          (should (= (string-width (car lines)) (1- width))))))))
