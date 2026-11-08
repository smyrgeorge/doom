;;; tests/unit/test-beads.el -*- lexical-binding: t; -*-
;; config/beads.el: SPC o i / SPC o I, the project's issues; beads.el mended
;; for bd 1.x, each operation run against the real bd (skipped without it:
;; scripts/tools.sh installs it), in a temp git repo with a temp HOME; its
;; keys over Vim's; its colours the theme's.

;; ====== LOADING ======

(load (expand-file-name "beads-autoloads"
                        (file-name-directory (locate-library "beads")))
      nil t)
(+test-load "config/beads")

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

(defmacro +test-beads-with-project (&rest body)
  "BODY in a new git repo tracking its issues with bd (`default-directory'),
with a temp HOME and global gitconfig; skipped without bd. One window on
*scratch*, and again after (Beads' buffers killed)."
  (declare (indent 0))
  `(progn
     (unless (executable-find "bd")
       (ert-skip "No bd (scripts/tools.sh installs it)"))
     (+test-with-reset
       (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "beads-home-") t)))
              (repo (file-name-as-directory (make-temp-file (+test-tmp-file "beads-repo-") t)))
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
         (+test-beads--run "bd" "init" "--quiet" "--prefix" "t")
         (unwind-protect (progn ,@body)
           (dolist (buffer (buffer-list))
             (when (string-prefix-p "*Beads" (buffer-name buffer))
               (kill-buffer buffer)))))))))

(defun +test-beads--create (title &rest args)
  "A new issue TITLE (with ARGS, as `beads-client-create' takes them): its id."
  (alist-get 'id (apply #'beads-client-create title args)))

(defun +test-beads--text (buffer)
  (with-current-buffer buffer
    (buffer-substring-no-properties (point-min) (point-max))))

;; ====== KEYS ======

(ert-deftest beads/keys ()
  (should-not +test-beads--loaded-before)
  (should (eq (lookup-key doom-leader-map (kbd "o i")) #'+my/beads-project))
  (should (eq (lookup-key doom-leader-map (kbd "o I")) #'+my/beads-new-issue)))

(ert-deftest beads/a-project-without-issues-says-so ()
  "SPC o i, SPC o I where no .beads/ is: what to run, nothing opened."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "beads-none-") t)))
         (default-directory dir))
    (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) dir)))
      (should-not (+my/beads-root))
      (let ((err (should-error (+my/beads-project) :type 'user-error)))
        (should (string-match-p "run .bd init. in" (cadr err))))
      (should-error (+my/beads-new-issue) :type 'user-error)
      (make-directory (expand-file-name ".beads" dir))
      (should (equal (+my/beads-root) dir)))))

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
                 '("list" "--type" "epic")))
  (should-not (member "--no-daemon" (beads-backend-bd--cli-extra-flags "duplicates"))))

(ert-deftest beads/show-one-issue ()
  (should (equal (+my/beads--one-issue-a '(((id . "t-1") (title . "T")))) '((id . "t-1") (title . "T"))))
  (should (equal (+my/beads--one-issue-a '((id . "t-1") (title . "T"))) '((id . "t-1") (title . "T"))))
  (should-not (+my/beads--one-issue-a nil)))

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
      (beads-client-delete (list id) :force t)
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
