;;; tests/unit/test-beads.el -*- lexical-binding: t; -*-
;; config/beads.el: SPC o i / SPC o I, the project's issues; beads.el mended
;; for bd 1.x, each operation run against the real bd (skipped without it:
;; scripts/tools.sh installs it), in a temp git repo with a temp HOME; its
;; keys over Vim's; its colours the theme's.

;; ====== LOADING ======

(load (expand-file-name "beads-autoloads"
                        (file-name-directory (locate-library "beads")))
      nil t)
(+test-load "config/window" "config/tiling" "config/childframe" "config/banner" "config/beads")

(defconst +test-beads--loaded-before (featurep 'beads)
  "Whether loading config/beads.el loaded beads.el (it mustn't).")

(require 'beads)
(require 'beads-stale)
(require 'beads-lint)
(require 'beads-hierarchy)
(require 'beads-activity)               ; its faces
(require 'doom-themes)                  ; doom-blend

;; ====== HELPERS ======

(defun +test-beads--run (program &rest args)
  "PROGRAM's output with ARGS in `default-directory' (an error if it failed)."
  (with-temp-buffer
    (let ((status (apply #'call-process program nil t nil args)))
      (unless (zerop status)
        (error "%s %s: %s" program (string-join args " ") (buffer-string)))
      (buffer-string))))

(defmacro +test-beads-with-repo (&rest body)
  "BODY in a new git repo (`default-directory', also `repo'), with a temp HOME
and global gitconfig, Doom's project root it; skipped without bd. One window
on *scratch*, and again after (Beads' buffers killed)."
  (declare (indent 0))
  `(progn
     (unless (executable-find "bd")
       (ert-skip "No bd (scripts/tools.sh installs it)"))
     (+test-with-reset
       (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
              (repo (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "beads-repo-") t))))
              (process-environment
               (append (list (concat "HOME=" home)
                             (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                             "GIT_CONFIG_NOSYSTEM=1"
                             (concat "XDG_CONFIG_HOME=" home ".config")
                             "BD_ACTOR=Tester")
                       process-environment))
              (default-directory repo))
         ;; Doom's project root (projectile's, not loaded here): the repo.
         (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) repo)))
           (with-temp-file (expand-file-name ".gitconfig" home)
             (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                     "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
           (+test-beads--run "git" "init" "-q")
           (unwind-protect (progn ,@body)
             (dolist (buffer (buffer-list))
               (when (string-prefix-p "*Beads" (buffer-name buffer))
                 (kill-buffer buffer)))))))))

(defmacro +test-beads-with-project (&rest body)
  "BODY in a new git repo tracking its issues with bd (see
`+test-beads-with-repo')."
  (declare (indent 0))
  `(+test-beads-with-repo
     (+test-beads--run "bd" "init" "--quiet" "--prefix" "t")
     ,@body))

(defun +test-beads--create (title &rest args)
  "A new issue TITLE (with ARGS, as `beads-client-create' takes them): its id."
  (alist-get 'id (apply #'beads-client-create title args)))

(defun +test-beads--text (buffer)
  (with-current-buffer buffer
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-beads--list ()
  "The issue list's buffer."
  (seq-find (lambda (b) (with-current-buffer b (derived-mode-p 'beads-list-mode)))
            (buffer-list)))

(defun +test-beads--settle (buffer &optional seconds)
  "Wait (SECONDS at most, else 30) for BUFFER's refresh on its way to end."
  (let ((end (+ (float-time) (or seconds 30))))
    (while (and (buffer-local-value '+my/beads--fetching buffer) (< (float-time) end))
      (accept-process-output nil 0.05))
    (should-not (buffer-local-value '+my/beads--fetching buffer))))

(defun +test-beads--slow-bd (seconds &optional code)
  "A stand-in bd: sleeps SECONDS, then runs the real one (or fails with CODE)."
  (let ((script (make-temp-file (+test-tmp-file "slow-bd-"))))
    (with-temp-file script
      (insert "#!/bin/sh\nsleep " (number-to-string seconds) "\n"
              (if code
                  (format "echo 'bd broke' >&2\nexit %d\n" code)
                (format "exec %s \"$@\"\n" (shell-quote-argument (executable-find "bd"))))))
    (set-file-modes script #o755)
    script))

(defun +test-beads--bar ()
  "The current issue list's bottom bar: its text (no window in batch to draw
it in), its counts."
  (mapconcat (lambda (part) (if (stringp part) (substring-no-properties part) ""))
             (flatten-tree (ensure-list mode-line-format)) ""))

(defun +test-beads--bulk (open closed)
  "OPEN + CLOSED new issues (t-1...), imported into bd at once: the first
CLOSED closed, the others open (P2 tasks). Not made one by one (slow), nor by
bd create -f: its short ids, chosen at random, can clash among a hundred."
  (let ((file (make-temp-file (+test-tmp-file "issues-") nil ".jsonl"
                              (mapconcat
                               (lambda (i)
                                 (json-encode
                                  `((id . ,(format "t-%d" i)) (title . ,(format "Issue %d" i))
                                    (status . ,(if (<= i closed) "closed" "open"))
                                    (priority . 2) (issue_type . "task")
                                    (created_at . "2026-11-01T10:00:00Z")
                                    (updated_at . "2026-11-01T10:00:00Z")
                                    ,@(and (<= i closed) '((closed_at . "2026-11-02T10:00:00Z"))))))
                               (number-sequence 1 (+ open closed)) "\n"))))
    (+test-beads--run "bd" "import" file "--quiet")))

(defun +test-beads--rows ()
  "How many issues the current list shows."
  (save-excursion
    (goto-char (point-min))
    (let ((rows 0))
      (while (not (eobp))
        (when (tabulated-list-get-id) (cl-incf rows))
        (forward-line 1))
      rows)))

(defun +test-beads--notices ()
  "The current buffer's notices: (TEXT ACTION-LABELS) each."
  (mapcar (lambda (notice) (list (nth 1 notice) (mapcar #'car (nth 2 notice))))
          +my/banner--list))

(defun +test-beads--press (label)
  "The notice action LABEL, pressed."
  (let ((action (seq-some (lambda (notice) (assoc label (nth 2 notice))) +my/banner--list)))
    (should action)
    (funcall (cdr action))))

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
      (should (string-match-p "doesn't track its issues with Beads. Open a terminal with .bd init. to run\\?"
                              (car asked)))
      (should (equal (mapcar #'cdr terminals) (list dir)))
      (should (equal typed (list (cons (caar terminals) "bd init"))))
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
    (should (equal (cdar typed) "bd init"))))

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
  (should (equal +my/beads-init-command "bd init"))
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
        (should (string-match-p "run .bd init. in" (cadr err)))))))

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

;; ====== IN THE BACKGROUND ======

(ert-deftest beads/the-timer-s-refresh-doesn-t-wait-for-bd ()
  "beads-autoupdate's refresh, bd taking 2 s: returns at once; the list
redrawn once bd answered, with what bd added meanwhile (its bar too)."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (slow (+test-beads--slow-bd 2)))
      (should (get-buffer-window list 'visible))
      (+test-beads--run "bd" "create" "Added by Claude" "--quiet")
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) slow)))
        (with-current-buffer list
          (let ((start (float-time)))
            (beads-autoupdate--refresh)
            (should (< (- (float-time) start) 1)))
          (should +my/beads--fetching)
          (should-not (string-match-p "Added by Claude" (+test-beads--text list)))
          (should (string-match-p "1 total" (+test-beads--bar))))
        (+test-beads--settle list))
      (should (string-match-p "Added by Claude" (+test-beads--text list)))
      (with-current-buffer list
        (should (string-match-p "2 total" (+test-beads--bar)))))))

(ert-deftest beads/a-refresh-on-its-way-not-started-again ()
  "Asked again while on its way: the same one; gr meanwhile: waited for, and
the one on its way cancelled (its older answer never drawn)."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (slow (+test-beads--slow-bd 2))
          drawn)
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) slow)))
        (with-current-buffer list
          (+my/beads-refresh-async list)
          (let ((fetching +my/beads--fetching))
            (should (= (length (cdr fetching)) 2)) ; bd list, bd stats
            (+my/beads-refresh-async list)
            (should (eq +my/beads--fetching fetching))
            ;; gr: bd asked and waited for (the real one), the other cancelled.
            (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) (executable-find "bd"))))
              (+test-beads--run "bd" "create" "Second" "--quiet")
              (beads-list-refresh t))
            (should-not +my/beads--fetching)
            (dolist (process (cdr fetching))
              (should (process-get process 'cancelled))
              (should-not (process-live-p process)))
            (should (string-match-p "Second" (+test-beads--text list))))))
      (cl-letf (((symbol-function '+my/beads--redraw) (lambda (&rest args) (push args drawn))))
        (accept-process-output nil 0.3))
      (should-not drawn))))

(ert-deftest beads/not-shown-not-refreshed-until-shown ()
  "A list in no window: no bd run, marked; shown again: refreshed."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list)))
      (should (memq #'+my/beads--shown-h (buffer-local-value 'window-buffer-change-functions list)))
      (dolist (window (get-buffer-window-list list nil t))
        (set-window-buffer window (get-buffer-create "*scratch*")))
      (should-not (get-buffer-window list 'visible))
      (+test-beads--run "bd" "create" "While hidden" "--quiet")
      (with-current-buffer list
        (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "bd run"))))
          (beads-autoupdate--refresh))
        (should-not +my/beads--fetching)
        (should +my/beads--stale))
      ;; Shown (batch Emacs runs no window change functions: called as
      ;; redisplay calls them).
      (set-window-buffer (selected-window) list)
      (with-current-buffer list
        (+my/beads--shown-h (selected-window))
        (should +my/beads--fetching)
        (should-not +my/beads--stale))
      (+test-beads--settle list)
      (should (string-match-p "While hidden" (+test-beads--text list))))))

(ert-deftest beads/an-issue-refreshed-in-the-background ()
  "An issue's buffer (Claude's bd commands refresh it): bd show not waited
for, the issue redrawn with bd's answer."
  (+test-beads-with-project
    (let ((id (+test-beads--create "Old title")))
      (beads-detail-open (beads-client-show id))
      (let ((detail (get-buffer (format "*Beads Detail: %s*" id))))
        (should (get-buffer-window detail 'visible))
        (+test-beads--run "bd" "update" id "--title" "New title" "--quiet")
        (+my/beads-refresh-async detail t)
        (should (buffer-local-value '+my/beads--fetching detail))
        (should (string-match-p "Old title" (+test-beads--text detail)))
        (+test-beads--settle detail)
        (should (string-match-p "New title" (+test-beads--text detail)))))))

(ert-deftest beads/bd-failing-in-the-background ()
  "bd failing: said as beads.el says it, the list as it was, nothing on its way."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (failing (+test-beads--slow-bd 0 3))
          messages)
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) failing))
                ((symbol-function 'message)
                 (lambda (format &rest args) (push (apply #'format-message format args) messages))))
        (+my/beads-refresh-async list)
        (+test-beads--settle list))
      (should (seq-find (lambda (m) (string-match-p "Failed to fetch issues: .*bd broke" m)) messages))
      (should (string-match-p "First" (+test-beads--text list))))))

(ert-deftest beads/background-refresh-wired ()
  (should (advice-member-p #'+my/beads-autoupdate-a 'beads-autoupdate--refresh))
  (should (advice-member-p #'+my/beads-refresh-lists-a 'beads-detail--refresh-list-buffers))
  (should (advice-member-p #'+my/beads-cancel-a 'beads-list-refresh))
  (should (advice-member-p #'+my/beads-cancel-a 'beads-detail-refresh)))

(ert-deftest beads/bd-an-issue-knows-its-issue ()
  "An issue opened (vui's view, beads.el's default): it keeps which issue it
shows, so gr refreshes it."
  (+test-beads-with-project
    (let ((id (+test-beads--create "Old title")))
      (beads-detail-open (beads-client-show id))
      (with-current-buffer (format "*Beads Detail: %s*" id)
        (should (derived-mode-p 'beads-detail-vui-mode))
        (should (equal beads-detail--current-issue-id id))
        (should (equal (alist-get 'id beads-detail--current-issue) id))
        (+test-beads--run "bd" "update" id "--title" "New title" "--quiet")
        (beads-detail-refresh)
        (should (string-match-p "New title" (+test-beads--text (current-buffer))))))))

;; ====== PANES ======

(ert-deftest beads/the-list-and-issues-in-panes ()
  "Tiling's applications: SPC o i, a new pane (its own, shown already); an
issue, a new pane, the next one in it; the preview, beads.el's side window."
  (+test-beads-with-project
    (let ((this-command 'test)
          (+my/tiling-strategy 'tall)
          (+my/focus-new-windows t)
          (first (+test-beads--create "First"))
          (second (+test-beads--create "Second"))
          (file (+test-buffer "notes.txt" "Notes\n")))
      (switch-to-buffer file)
      (+my/beads-project)
      (should (= (length (+my/tiling--panes)) 2))
      (should (eq (window-buffer (car (+my/tiling--panes))) file))
      (let ((list-window (selected-window)))
        (should (with-current-buffer (window-buffer list-window) (derived-mode-p 'beads-list-mode)))
        ;; Again, from the file: its pane.
        (select-window (car (+my/tiling--panes)))
        (+my/beads-project)
        (should (= (length (+my/tiling--panes)) 2))
        (should (eq (selected-window) list-window))
        ;; An issue: a new pane; the next one: that pane.
        (beads-detail-open (beads-client-show first))
        (should (= (length (+my/tiling--panes)) 3))
        (let ((issue-window (selected-window)))
          (should (string-match-p first (buffer-name (window-buffer issue-window))))
          ;; Not in the list's pane's history (drawn there, not shown).
          (should-not (seq-find (lambda (entry) (string-match-p "Beads Detail" (buffer-name (car entry))))
                                (window-prev-buffers list-window)))
          (select-window list-window)
          (beads-detail-open (beads-client-show second))
          (should (= (length (+my/tiling--panes)) 3))
          (should (eq (selected-window) issue-window))
          (should (string-match-p second (buffer-name (window-buffer issue-window)))))
        ;; The preview: beads.el's side window, no pane.
        (beads-detail-show (beads-client-show first))
        (should (= (length (+my/tiling--panes)) 3))
        (should (window-parameter (get-buffer-window "*Beads Preview*") 'window-side))))))

(ert-deftest beads/issues-are-tiling-s-applications ()
  (dolist (mode '(beads-list-mode beads-detail-mode beads-detail-vui-mode))
    (should (seq-find (lambda (app) (eq (if (consp app) (car app) app) mode)) +my/tiling-apps)))
  (with-temp-buffer
    (rename-buffer "*Beads Preview*" t)
    (when (equal (buffer-name) "*Beads Preview*")
      (should-not (+my/tiling-beads-issue-new-pane-p))))
  (with-temp-buffer
    (should (+my/tiling-beads-issue-new-pane-p))))

;; ====== EVIL ======

(ert-deftest beads/keys-over-vim-s ()
  "In the list, normal state: its letters, gr refreshing; Vim's gg and j."
  (with-temp-buffer
    (beads-list-mode)
    (evil-normal-state)
    (should (eq (key-binding "es") #'beads-list-edit-status))
    (should (eq (key-binding "et") #'beads-list-edit-title))
    (should (eq (key-binding "f") (lookup-key beads-list-mode-map "f")))
    (should (eq (key-binding "P") #'beads-preview-mode))
    (should (eq (key-binding "gr") #'beads-list-refresh))
    (should (eq (key-binding "gg") #'evil-goto-first-line))
    (should (eq (key-binding "j") #'evil-next-line))
    (should (eq (key-binding (kbd "RET")) #'beads-list-goto-issue))
    ;; Not what it inherits: SPC (Doom's leader) and h stay Vim's.
    (should-not (eq (key-binding " ") #'scroll-up-command))
    (should (eq (key-binding "h") #'evil-backward-char))))

(ert-deftest beads/forms-typed-into ()
  "beads.el's own: its forms in Emacs's state."
  (require 'beads-form)
  (should (eq (evil-initial-state 'beads-form-mode) 'emacs))
  (should (eq (evil-initial-state 'beads-form-vui-mode) 'emacs)))

;; ====== THE THEME'S COLOURS ======

(ert-deftest beads/faces-the-theme-s ()
  "No colour names: each face inherits the theme's; P0 rows tinted with its red."
  (+my/beads-faces)
  (pcase-dolist (`(,face . ,theme-face) +my/beads--faces)
    (should (eq (face-attribute face :inherit) theme-face))
    (should (eq (face-attribute face :foreground) 'unspecified)))
  ;; Each of beads.el's faces with a colour name is in the list.
  (dolist (face (face-list))
    (when (string-prefix-p "beads-" (symbol-name face))
      (let ((foreground (face-attribute face :foreground)))
        (should (or (eq foreground 'unspecified) (assq face +my/beads--faces))))))
  (should (memq #'+my/beads-faces doom-load-theme-hook)))

(ert-deftest beads/p0-row-tinted ()
  (cl-letf* ((face-background (symbol-function 'face-background))
             (face-foreground (symbol-function 'face-foreground))
             ((symbol-function 'face-background)
              (lambda (face &rest args) (if (eq face 'default) "#000000" (apply face-background face args))))
             ((symbol-function 'face-foreground)
              (lambda (face &rest args) (if (eq face 'error) "#ff0000" (apply face-foreground face args)))))
    (+my/beads-faces)
    (should (equal (face-attribute 'beads-list-row-p0 :background) (doom-blend "#ff0000" "#000000" 0.15)))
    (should (eq (face-attribute 'beads-list-row-p0 :extend) t))))
