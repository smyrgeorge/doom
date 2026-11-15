;;; tests/unit/test-beads.el -*- lexical-binding: t; -*-
;; config/beads.el: SPC o i / SPC o I, the project's issues; beads.el mended
;; for bd 1.x, each operation run against the real bd (skipped without it:
;; scripts/tools.sh installs it), in a temp git repo with a temp HOME: its keys,
;; starting, bd 1.x, the list against the real bd, what it hides. The look, the
;; place kept and refreshes, panes and colours: test-beads-*.el (shared:
;; tests/helper-beads.el).

(load (expand-file-name "../helper-beads" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== KEYS ======

(ert-deftest beads/keys ()
  (should-not +test-beads--loaded-before)
  (should (eq (lookup-key doom-leader-map (kbd "o i")) #'+my/beads-project))
  (should (eq (lookup-key doom-leader-map (kbd "o I")) #'+my/beads-new-issue)))

(ert-deftest beads/the-root ()
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "beads-none-") t)))
         (default-directory dir))
    (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) dir)))
      (should-not (+my/beads-root))
      (make-directory (expand-file-name ".beads" dir))
      (should (equal (+my/beads-root) dir)))))

;; ====== STARTING ======

(defmacro +test-beads--untracked (&rest body)
  "BODY in a new folder (`dir', Doom's project root) whose issues aren't
tracked; the terminals it would open (`terminals') and what they'd be typed
(`typed') recorded, its timers run at once."
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "beads-none-") t)))
          (default-directory dir)
          (terminals nil)
          (typed nil))
     (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) dir))
               ((symbol-function 'ghostel-new)
                (lambda ()
                  (let ((buffer (generate-new-buffer "*test terminal*")))
                    (with-current-buffer buffer (insert "~/project $ "))
                    (push (cons buffer default-directory) terminals)
                    buffer)))
               ((symbol-function 'ghostel-send-string)
                (lambda (text) (push (cons (current-buffer) text) typed)))
               ((symbol-function 'run-at-time)
                (lambda (_time _repeat fn &rest args) (apply fn args) nil)))
       (unwind-protect (progn ,@body)
         (dolist (terminal terminals) (kill-buffer (car terminal)))))))

(ert-deftest beads/untracked-offers-a-terminal-with-bd-init-typed ()
  "SPC o i where no .beads/ is: asked; yes, a terminal at the project's root,
bd init typed there, not run (no RET); nothing else done."
  (+test-beads--untracked
    (let (asked)
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) t))
                ((symbol-function 'beads-list) (lambda () (error "The list opened"))))
        (+my/beads-project))
      (should (string-match-p "doesn't track its issues with Beads. Open a terminal with .bd init --skip-agents. to run\\?"
                              (car asked)))
      (should (equal (mapcar #'cdr terminals) (list dir)))
      (should (equal typed (list (cons (caar terminals) "bd init --skip-agents"))))
      (should-not (string-match-p "[\r\n]" (cdar typed)))
      (should-not (file-exists-p (expand-file-name ".beads" dir))))))

(ert-deftest beads/untracked-declined-nothing-opened ()
  (+test-beads--untracked
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
      (+my/beads-project)
      (+my/beads-new-issue))
    (should-not terminals)
    (should-not typed)))

(ert-deftest beads/spc-o-I-offers-it-too ()
  (+test-beads--untracked
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t))
              ((symbol-function 'beads-create-issue) (lambda () (interactive) (error "Created"))))
      (+my/beads-new-issue))
    (should (= (length terminals) 1))
    (should (equal (cdar typed) "bd init --skip-agents"))))

(ert-deftest beads/typed-once-the-prompt-is-drawn ()
  "Not before the shell drew something and it settled; given up after a
while without one."
  (let ((buffer (generate-new-buffer "*test terminal*"))
        (scheduled 0) typed)
    (unwind-protect
        (cl-letf (((symbol-function 'ghostel-send-string) (lambda (text) (push text typed)))
                  ((symbol-function 'run-at-time)
                   (lambda (_time _repeat fn &rest args)
                     (cl-incf scheduled)
                     (when (< scheduled 100) (apply fn args)))))
          ;; Nothing drawn: never typed, 50 tries.
          (+my/beads--type-when-ready buffer "bd init")
          (should-not typed)
          (should (= scheduled 50))
          ;; Drawn and settled: typed, once.
          (setq scheduled 0)
          (with-current-buffer buffer (insert "$ "))
          (+my/beads--type-when-ready buffer "bd init")
          (should (equal typed '("bd init")))
          ;; Its buffer gone: nothing.
          (kill-buffer buffer)
          (+my/beads--type-when-ready buffer "bd init")
          (should (equal typed '("bd init"))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest beads/the-command-typed ()
  (should (equal +my/beads-init-command "bd init --skip-agents"))
  (let ((+my/beads-init-command "bd init --skip-hooks"))
    (+test-beads--untracked
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (+my/beads-project))
      (should (equal (cdar typed) "bd init --skip-hooks")))))

(ert-deftest beads/no-terminal-says-what-to-run ()
  (+test-beads--untracked
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t))
              ((symbol-function 'fboundp)
               (let ((fboundp (symbol-function 'fboundp)))
                 (lambda (f) (and (not (eq f 'ghostel-new)) (funcall fboundp f))))))
      (let ((err (should-error (+my/beads-project) :type 'user-error)))
        (should (string-match-p "run .bd init --skip-agents. in" (cadr err)))))))

(ert-deftest beads/bd-the-command-typed-adds-no-agent-files ()
  "The command typed, run: .beads/ and .gitignore committed, no files for AI
tools."
  (+test-beads-with-repo
    (+test-beads--run "git" "commit" "-q" "--allow-empty" "-m" "First")
    (apply #'+test-beads--run (split-string-shell-command +my/beads-init-command))
    (should (file-directory-p (expand-file-name ".beads" repo)))
    (dolist (file '("CLAUDE.md" "AGENTS.md" ".claude" ".codex" ".cursor" ".agents"))
      (should-not (file-exists-p (expand-file-name file repo))))
    (should (equal (split-string (+test-beads--run "git" "status" "--porcelain") "\n" t) nil))
    (should (string-match-p "^\\.gitignore$" (+test-beads--run "git" "ls-files")))))

;; ====== BD 1.x ======

(ert-deftest beads/cli-only ()
  (should (eq beads-client-connection-strategy 'cli)))

(ert-deftest beads/arguments-keys-made-symbols ()
  (should (equal (+my/beads--symbol-keys-a '("create" (("title" . "T") ("issue_type" . "bug") (priority . 1)) "/p"))
                 '("create" ((title . "T") (issue_type . "bug") (priority . 1)) "/p")))
  (should (equal (+my/beads--symbol-keys-a '("stats" nil)) '("stats" nil))))

(ert-deftest beads/flags-bd-renamed ()
  (should (equal (beads-backend-bd--operation-to-cli-args
                  "create" '((title . "T") (issue_type . "bug") (acceptance_criteria . "ok")))
                 '("create" "T" "--type" "bug" "--acceptance" "ok")))
  (should (equal (beads-backend-bd--operation-to-cli-args "list" '((issue_type . "epic")))
                 '("list" "--type" "epic" "--limit" "0" "--all")))
  (should-not (member "--no-daemon" (beads-backend-bd--cli-extra-flags "duplicates")))
  ;; A delete forced (bd 1.x only previews it otherwise), once.
  (should (equal (beads-backend-bd--operation-to-cli-args "delete" '((ids . ("t-1"))))
                 '("delete" "t-1" "--force")))
  (should (equal (beads-backend-bd--operation-to-cli-args "delete" '((ids . ("t-1")) (force . t)))
                 '("delete" "t-1" "--force"))))

(ert-deftest beads/show-one-issue ()
  (should (equal (+my/beads--one-issue-a '(((id . "t-1") (title . "T")))) '((id . "t-1") (title . "T"))))
  (should (equal (+my/beads--one-issue-a '((id . "t-1") (title . "T"))) '((id . "t-1") (title . "T"))))
  (should-not (+my/beads--one-issue-a nil)))

(ert-deftest beads/stats-summary-at-the-top ()
  "bd 1.x's stats, its counts under summary: at the top, the rest kept; bd
0.49's flat answer as it was."
  (let ((stats (+my/beads--stats-summary-a
                '((schema_version . 1) (summary (total_issues . 7) (open_issues . 3))))))
    (should (eql (alist-get 'total_issues stats) 7))
    (should (eql (alist-get 'open_issues stats) 3))
    (should (eql (alist-get 'schema_version stats) 1))
    (should-not (alist-get 'summary stats)))
  (should (equal (+my/beads--stats-summary-a '((total_issues . 7))) '((total_issues . 7))))
  (should-not (+my/beads--stats-summary-a nil)))

(ert-deftest beads/gone-from-bd-say-so ()
  (should-error (beads-activity) :type 'user-error)
  (should-error (beads-conflicts) :type 'user-error))

;; ====== AGAINST THE REAL BD ======

(ert-deftest beads/bd-issues-created-edited-closed ()
  (+test-beads-with-project
    (let ((id (+test-beads--create "From Emacs" :issue-type "bug" :priority 1 :description "It broke")))
      (should (string-prefix-p "t-" id))
      (let ((issue (beads-client-show id)))
        (should (equal (alist-get 'title issue) "From Emacs"))
        (should (equal (alist-get 'issue_type issue) "bug"))
        (should (eql (alist-get 'priority issue) 1))
        (should (equal (alist-get 'description issue) "It broke")))
      ;; Every field the detail view and the form edit.
      (beads-client-update id :title "Renamed" :status "in_progress" :issue-type "task"
                           :design "The design" :notes "Notes" :acceptance-criteria "It works"
                           :external-ref "gh-1")
      (let ((issue (beads-client-show id)))
        (should (equal (alist-get 'title issue) "Renamed"))
        (should (equal (alist-get 'status issue) "in_progress"))
        (should (equal (alist-get 'issue_type issue) "task"))
        (should (equal (alist-get 'design issue) "The design"))
        (should (equal (alist-get 'notes issue) "Notes"))
        (should (equal (alist-get 'acceptance_criteria issue) "It works"))
        (should (equal (alist-get 'external_ref issue) "gh-1")))
      ;; A preview creates nothing.
      (beads-client-create "Only a preview" :issue-type "task" :priority 2 :dry-run t)
      (should (= (length (beads-client-list)) 1))
      (beads-client-close id "Done")
      (should (equal (alist-get 'status (beads-client-show id)) "closed"))
      (beads-client-update id :status "open")
      (should (equal (alist-get 'status (beads-client-show id)) "open"))
      ;; Deleted as beads.el's D deletes it (asked first): no :force.
      (beads-client-delete (list id))
      (should-not (beads-client-list)))))

(ert-deftest beads/bd-labels-comments-dependencies ()
  (+test-beads-with-project
    (let ((a (+test-beads--create "Blocked one"))
          (b (+test-beads--create "Blocker")))
      (beads-client-request "label_add" `((id . ,a) (label . "emacs")))
      (should (equal (append (alist-get 'labels (beads-client-show a)) nil) '("emacs")))
      (beads-client-request "label_remove" `((id . ,a) (label . "emacs")))
      (should-not (alist-get 'labels (beads-client-show a)))
      (beads-client-request "comments-add" `((id . ,a) (text . "A comment")))
      (should (= (alist-get 'comment_count (beads-client-show a)) 1))
      (beads-client-request "dep_add" `((from_id . ,a) (to_id . ,b)))
      ;; Ready: the blocker, not the blocked.
      (should (equal (mapcar (lambda (i) (alist-get 'id i)) (beads-client-ready)) (list b)))
      (should (beads-client-request "dep_tree" `((id . ,a))))
      (beads-client-request "dep_remove" `((from_id . ,a) (to_id . ,b)))
      (should (= (length (beads-client-ready)) 2)))))

(ert-deftest beads/bd-views ()
  "SPC o i's list, an issue's view, its dependencies, the reports: drawn."
  (+test-beads-with-project
    (let ((id (+test-beads--create "Shown in the list" :issue-type "feature" :priority 0)))
      (+test-beads--create "Another one")
      (+my/beads-project)
      (let ((list (seq-find (lambda (b) (with-current-buffer b (derived-mode-p 'beads-list-mode)))
                            (buffer-list))))
        (should list)
        (should (string-match-p "Shown in the list" (+test-beads--text list)))
        (should (string-match-p "Another one" (+test-beads--text list))))
      (beads-detail-open (beads-client-show id))
      (let ((detail (get-buffer (format "*Beads Detail: %s*" id))))
        (should detail)
        (should (string-match-p "Shown in the list" (+test-beads--text detail))))
      (beads-hierarchy-show id)
      (should (get-buffer (format "*Beads Deps: %s*" id)))
      (should (listp (beads-stale--fetch 1)))  ; none stale: nil, no error
      (should (alist-get 'results (beads-core-cli-request "lint")))
      (should (beads-client-stats))
      (should (member "bug" (beads-get-types))))))

(ert-deftest beads/bd-the-list-s-counts ()
  "The list's bar and the S view: bd's counts (open, in progress, blocked,
closed), not 0s."
  (+test-beads-with-project
    (let ((blocked (+test-beads--create "Blocked"))
          (blocker (+test-beads--create "Blocker"))
          (working (+test-beads--create "Working on it"))
          (done (+test-beads--create "Done")))
      (beads-client-request "dep_add" `((from_id . ,blocked) (to_id . ,blocker)))
      (beads-client-update working :status "in_progress")
      (beads-client-close done "Done")
      (let ((stats (beads-client-stats)))
        (should (eql (alist-get 'total_issues stats) 4))
        (should (eql (alist-get 'closed_issues stats) 1))
        (should (eql (alist-get 'in_progress_issues stats) 1))
        (should (eql (alist-get 'blocked_issues stats) 1)))
      (+my/beads-project)
      (let ((list (seq-find (lambda (b) (with-current-buffer b (derived-mode-p 'beads-list-mode)))
                            (buffer-list))))
        (with-current-buffer list
          (should (string-match-p "4 total | 2 open | 1 in progress | 1 blocked | 1 ready"
                                  (+test-beads--bar)))))
      (beads-stats)
      (let ((text (+test-beads--text "*Beads Stats*")))
        (should (string-match-p "Total Issues: +4" text))
        (should (string-match-p "Closed: +1" text))
        (should (string-match-p "Blocked: +1" text))))))

;; doom-o5t.15
(ert-deftest beads/bd-the-bar-in-a-narrow-pane ()
  "The list's bar: its counts in words after its name where that fits; else
first, short, as the list's icons (○ ready, ◔ in progress, ⊘ blocked, ✓
closed), then its name: seen at 40 columns (beads.el's, 84 columns, cut
there)."
  (+test-beads-with-project
    (let ((blocked (+test-beads--create "Blocked"))
          (blocker (+test-beads--create "Blocker"))
          (working (+test-beads--create "Working on it"))
          (done (+test-beads--create "Done")))
      (beads-client-request "dep_add" `((from_id . ,blocked) (to_id . ,blocker)))
      (beads-client-update working :status "in_progress")
      (beads-client-close done "Done")
      (+my/beads-project)
      (with-current-buffer (+test-beads--list)
        (should (equal mode-line-format '((:eval (+my/beads--bar)))))
        (let ((full (+my/beads--bar 1000))
              (short (+my/beads--bar 40)))
          (should (equal (substring-no-properties full)
                         (concat " " (buffer-name) "   4 total | 2 open | 1 in progress | 1 blocked | 1 ready")))
          (should (equal (substring-no-properties short) (concat " ○1 ◔1 ⊘1 ✓1  " (buffer-name))))
          (should (eq (get-text-property 1 'face short) 'success)))
        ;; Drawn in its window (40 columns or so here): by its width.
        (let ((window (get-buffer-window (current-buffer))))
          (should (< (window-total-width window) (string-width (+my/beads--bar 1000))))
          (should (string-prefix-p " ○1 ◔1 ⊘1 ✓1  " (with-selected-window window (+my/beads--bar)))))))))

;; ====== WHAT THE LIST HIDES ======

(ert-deftest beads/bd-every-issue-the-closed-ones-hidden-said ()
  "60 open and 44 closed issues: the 60 shown (more than bd's 50), a notice
over the column titles says 44 closed are hidden; Show closed, Hide closed;
f s closed shows them; a filter said, Clear filter; one bd list and one bd
stats a refresh, in the background too."
  (+test-beads-with-project
    (+test-beads--bulk 58 44)
    (should (= (length (beads-client-list)) 102))
    (+test-beads--create "Urgent one" :priority 0)
    (+test-beads--create "Urgent two" :priority 0)
    (+my/beads-project)
    (with-current-buffer (+test-beads--list)
      (should (= (+test-beads--rows) 60))
      (should (equal (+test-beads--notices) '(("44 closed issues hidden." ("Show closed")))))
      ;; Over the list's column titles, kept under them.
      (should (equal (car header-line-format) +my/banner--header))
      (should (string-match-p "Title" (format "%s" (cadr header-line-format))))
      ;; A refresh: bd list and bd stats, no more.
      (let ((bd 0))
        (cl-letf* ((call-process (symbol-function 'call-process))
                   ((symbol-function 'call-process)
                    (lambda (program &rest args)
                      (when (equal (file-name-nondirectory program) "bd") (cl-incf bd))
                      (apply call-process program args))))
          (beads-list-refresh t))
        (should (= bd 2)))
      (should (equal (+test-beads--notices) '(("44 closed issues hidden." ("Show closed")))))
      (+test-beads--press "Show closed")
      (should (= (+test-beads--rows) 104))
      (should (equal (+test-beads--notices) '(("44 closed issues shown." ("Hide closed")))))
      (+test-beads--press "Hide closed")
      (should (= (+test-beads--rows) 60))
      ;; f s closed: the closed ones, the filter said.
      (setq beads-list--filter (beads-filter-by-status "closed"))
      (beads-list-refresh t)
      (should (= (+test-beads--rows) 44))
      (should (equal (+test-beads--notices) '(("Filtered: status closed." ("Clear filter")))))
      (+test-beads--press "Clear filter")
      (should-not beads-list--filter)
      (should (= (+test-beads--rows) 60))
      ;; Another filter: closed ones it'd show hidden (none here).
      (setq beads-list--filter (beads-filter-by-priority 0))
      (beads-list-refresh t)
      (should (= (+test-beads--rows) 2))
      (should (equal (+test-beads--notices) '(("Filtered: priority P0." ("Clear filter")))))
      (setq beads-list--filter (beads-filter-by-priority 2))
      (beads-list-refresh t)
      (should (= (+test-beads--rows) 58))
      (should (equal (sort (+test-beads--notices) (lambda (a b) (string< (car a) (car b))))
                     '(("44 closed issues hidden." ("Show closed"))
                       ("Filtered: priority P2." ("Clear filter")))))
      (+test-beads--press "Clear filter")
      ;; In the background: the same.
      (+my/beads-refresh-async (current-buffer))
      (+test-beads--settle (current-buffer))
      (should (= (+test-beads--rows) 60))
      (should (equal (+test-beads--notices) '(("44 closed issues hidden." ("Show closed")))))
      ;; Sorted (beads.el draws its column titles again): still there.
      (beads-list-cycle-sort)
      (should (equal (car header-line-format) +my/banner--header))
      (should (equal (+test-beads--notices) '(("44 closed issues hidden." ("Show closed"))))))))

(ert-deftest beads/bd-nothing-hidden-no-notice ()
  (+test-beads-with-project
    (+test-beads--create "Open")
    (+test-beads--create "Also open")
    (+my/beads-project)
    (with-current-buffer (+test-beads--list)
      (should (= (+test-beads--rows) 2))
      (should-not +my/banner--list)
      (should-not (equal (car-safe header-line-format) +my/banner--header)))))

(ert-deftest beads/the-closed-ones-shown-by-default-if-set ()
  (+test-beads-with-project
    (+test-beads--create "Open")
    (beads-client-close (+test-beads--create "Closed") "Done")
    (let ((+my/beads-closed-shown t))
      (+my/beads-project))
    (with-current-buffer (+test-beads--list)
      (should (= (+test-beads--rows) 2))
      (should (equal (+test-beads--notices) '(("1 closed issue shown." ("Hide closed"))))))))

(ert-deftest beads/filters-said ()
  (should-not +my/beads-closed-shown)
  (should (equal (+my/beads--filter-text (beads-filter-by-status "in_progress")) "status in progress"))
  (should (equal (+my/beads--filter-text (beads-filter-by-type "bug")) "type bug"))
  (should (equal (+my/beads--filter-text (beads-filter-unassigned)) "unassigned"))
  (should (equal (+my/beads--filter-text (beads-filter-by-search "parser")) "search \"parser\""))
  (should (equal (+my/beads--filter-text (beads-filter-ready)) "ready"))
  (should (equal (+my/beads--filter-text (beads-filter-compose (beads-filter-by-label "emacs")
                                                               (beads-filter-by-priority 1)))
                 "label emacs, priority P1"))
  (should (+my/beads--status-filter-p (beads-filter-compose (beads-filter-by-type "bug")
                                                            (beads-filter-by-status "closed"))))
  (should-not (+my/beads--status-filter-p (beads-filter-by-type "bug"))))

(ert-deftest beads/bd-ready-every-issue ()
  (should (equal (beads-backend-bd--operation-to-cli-args "ready" nil) '("ready" "--limit" "0")))
  (should (equal (beads-backend-bd--operation-to-cli-args "ready" '((limit . 5))) '("ready" "--limit" "5")))
  (should (equal (beads-backend-bd--operation-to-cli-args "list" '((status . "open")))
                 '("list" "--status" "open" "--limit" "0"))))
