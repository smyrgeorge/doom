;;; tests/unit/test-agent-shell-beads.el -*- lexical-binding: t; -*-
;; config/agent-shell/beads.el: a project's Beads issues in its Claude Code
;; sessions. What Claude is told (in a project with .beads/ only, Beads' guide
;; after), the issues open in Emacs refreshed after Claude's bd commands, an
;; issue into the prompt (C-c C-i in agent-shell, C-c C-a on an issue). No
;; agent: agent-shell's prompt and subscriptions are stubbed; bd is the real
;; one where it's needed (skipped without it), in a temp git repo with a temp
;; HOME.

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

(require 'evil)
(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(+test-load "config/childframe" "config/banner" "config/webkit" "config/excalidraw"
            "config/agent-shell" "config/beads")
(require 'agent-shell)
(require 'beads)
(require 'beads-detail)

;; ====== HELPERS ======

(defun +test-asb--dir (&optional beads)
  "A new folder, by its true name; with a .beads/ folder if BEADS."
  (let ((dir (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "asb-") t)))))
    (when beads
      (make-directory (expand-file-name ".beads" dir)))
    dir))

(defun +test-asb--run (program &rest args)
  (with-temp-buffer
    (unless (zerop (apply #'call-process program nil t nil args))
      (error "%s %s: %s" program (string-join args " ") (buffer-string)))
    (buffer-string)))

(defmacro +test-asb-with-bd (&rest body)
  "BODY in a new git repo tracking its issues with bd (`default-directory',
also `root'), with a temp HOME; skipped without bd."
  (declare (indent 0))
  `(progn
     (unless (executable-find "bd")
       (ert-skip "No bd (scripts/tools.sh installs it)"))
     (let* ((home (+test-asb--dir))
            (root (+test-asb--dir))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1"
                           (concat "XDG_CONFIG_HOME=" home ".config")
                           "BD_ACTOR=Tester")
                     process-environment))
            (default-directory root))
       (with-temp-file (expand-file-name ".gitconfig" home)
         (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                 "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
       (+test-asb--run "git" "init" "-q")
       (+test-asb--run "bd" "init" "--quiet" "--prefix" "t")
       (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () root)))
         ,@body))))

(defun +test-asb--shell (dir)
  "A buffer standing for an agent-shell in DIR (its mode only, no agent)."
  (let ((buffer (generate-new-buffer "*test agent-shell*")))
    (with-current-buffer buffer
      (setq-local major-mode 'agent-shell-mode)
      (setq default-directory dir))
    buffer))

;; ====== KEYS ======

(ert-deftest agent-shell-beads/keys ()
  "C-c C-i (SPC m i) in agent-shell; C-c C-a (SPC m a) on an issue."
  (should (eq (lookup-key agent-shell-mode-map (kbd "C-c C-i")) #'+my/agent-shell-beads-insert))
  (should (eq (lookup-key (evil-get-auxiliary-keymap agent-shell-mode-map 'normal) (kbd "SPC m i"))
              #'+my/agent-shell-beads-insert))
  (dolist (map (list beads-list-mode-map beads-detail-mode-map beads-detail-vui-mode-map))
    (should (eq (lookup-key map (kbd "C-c C-a")) #'+my/agent-shell-beads-send)))
  (should (eq (lookup-key (evil-get-auxiliary-keymap beads-list-mode-map 'normal) (kbd "SPC m a"))
              #'+my/agent-shell-beads-send))
  ;; Theirs stay: agent-shell's C-c C-c, the list's menu.
  (should (eq (lookup-key agent-shell-mode-map (kbd "C-c C-c")) #'agent-shell-interrupt))
  (should (eq (lookup-key beads-list-mode-map (kbd "C-c m")) #'beads-menu))
  (should (commandp #'+my/agent-shell-beads-insert))
  (should (commandp #'+my/agent-shell-beads-send)))

;; ====== WHAT CLAUDE IS TOLD ======

(ert-deftest agent-shell-beads/context-only-where-beads-is ()
  (let ((plain (+test-asb--dir)))
    (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () plain)))
      (should-not (+my/agent-shell-beads-context))))
  (should (memq #'+my/agent-shell-beads-context +my/agent-shell-claude-context-functions))
  ;; After the theme's line.
  (should (eq (car +my/agent-shell-claude-context-functions) #'+my/agent-shell-claude-theme)))

(ert-deftest agent-shell-beads/context-with-beads-guide ()
  (+test-asb-with-bd
    (let ((text (+my/agent-shell-beads-context)))
      (should (string-prefix-p +my/agent-shell-beads-context text))
      ;; bd prime's guide after it.
      (should (string-match-p "bd ready" text))
      (should (> (length text) (+ (length +my/agent-shell-beads-context) 500))))
    (let ((+my/agent-shell-beads-prime nil))
      (should (equal (+my/agent-shell-beads-context) +my/agent-shell-beads-context)))))

(ert-deftest agent-shell-beads/context-in-the-system-prompt ()
  "A session started in the project: its system prompt has it, after the
editor's text."
  (+test-asb-with-bd
    (let* ((config (agent-shell-anthropic-make-claude-code-config))
           (text (map-nested-elt (alist-get :session-meta config) '(systemPrompt append))))
      (should (string-prefix-p +my/agent-shell-claude-context text))
      (should (string-match-p (regexp-quote +my/agent-shell-beads-context) text)))))

(ert-deftest agent-shell-beads/context-text-is-clean ()
  (should-not (string-match-p "  \\|\\\\\n\\| $" +my/agent-shell-beads-context))
  (should (string-match-p "bd show ID" +my/agent-shell-beads-context))
  (should (string-match-p "Never run bd edit" +my/agent-shell-beads-context)))

;; ====== EMACS FOLLOWS CLAUDE'S CHANGES ======

(ert-deftest agent-shell-beads/bd-commands-recognised ()
  (dolist (command '("bd list" "bd" "bd close t-1 --reason done" "cd x && bd ready --json"
                     "true; bd show t-2" "(bd ready)" "echo $(bd q New)" "x | bd create --stdin"))
    (should (string-match-p +my/agent-shell-beads--command-regexp command)))
  (dolist (command '("ls" "abd list" "./bdx" "git log -- bd.el" "rg bdtest"))
    (should-not (string-match-p +my/agent-shell-beads--command-regexp command))))

(defun +test-asb--event (status command)
  `((:event . tool-call-update)
    (:data . ((:tool-call-id . "1")
              (:tool-call . ((:status . ,status) (:command . ,command)))))))

(ert-deftest agent-shell-beads/a-bd-command-done-refreshes-soon ()
  (let (scheduled (+my/agent-shell-beads--refresh-timer nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_time _repeat fn &rest args) (push (cons fn args) scheduled) 'timer))
              ((symbol-function 'timerp) (lambda (x) (eq x 'timer)))
              ((symbol-function 'cancel-timer) (lambda (_) (pop scheduled))))
      ;; Running, or not bd: nothing.
      (+my/agent-shell-beads--tool-call "/p/" (+test-asb--event "in_progress" "bd close t-1"))
      (+my/agent-shell-beads--tool-call "/p/" (+test-asb--event "completed" "ls"))
      (+my/agent-shell-beads--tool-call "/p/" (+test-asb--event "completed" nil))
      (should-not scheduled)
      ;; Done (or failed): once, for a burst.
      (+my/agent-shell-beads--tool-call "/p/" (+test-asb--event "completed" "bd close t-1"))
      (+my/agent-shell-beads--tool-call "/p/" (+test-asb--event "failed" "bd update t-2 --claim"))
      (should (equal scheduled '((+my/agent-shell-beads-refresh "/p/")))))))

(ert-deftest agent-shell-beads/refresh-the-project-s-issues-only ()
  (let* ((here (+test-asb--dir t))
         (there (+test-asb--dir t))
         refreshed
         (mine (generate-new-buffer "*Beads: here*"))
         (mine-detail (generate-new-buffer "*Beads Detail: here*"))
         (theirs (generate-new-buffer "*Beads: there*")))
    (unwind-protect
        (progn
          (with-current-buffer mine (beads-list-mode) (setq default-directory here))
          (with-current-buffer mine-detail (beads-detail-mode) (setq default-directory (concat here "sub/")))
          (with-current-buffer theirs (beads-list-mode) (setq default-directory there))
          ;; In the background (config/beads/refresh.el).
          (cl-letf (((symbol-function '+my/beads-refresh-async)
                     (lambda (buffer &optional silent) (when silent (push buffer refreshed)))))
            (+my/agent-shell-beads-refresh here))
          (should (equal (sort (mapcar #'buffer-name refreshed) #'string<)
                         (list (buffer-name mine-detail) (buffer-name mine)))))
      (mapc #'kill-buffer (list mine mine-detail theirs)))))

(ert-deftest agent-shell-beads/a-refresh-error-stays-quiet ()
  "A list that can't refresh (bd failing): the others still are."
  (let* ((here (+test-asb--dir t))
         (a (generate-new-buffer "*Beads: a*"))
         (b (generate-new-buffer "*Beads: b*"))
         refreshed)
    (unwind-protect
        (progn
          (dolist (buffer (list a b))
            (with-current-buffer buffer (beads-list-mode) (setq default-directory here)))
          (cl-letf (((symbol-function '+my/beads-refresh-async)
                     (lambda (buffer &optional _silent)
                       (if (eq buffer a) (error "bd failed") (push buffer refreshed)))))
            (+my/agent-shell-beads-refresh here))
          (should (equal refreshed (list b))))
      (mapc #'kill-buffer (list a b)))))

(ert-deftest agent-shell-beads/sessions-watch-where-beads-is ()
  (should (memq #'+my/agent-shell-beads--watch-h agent-shell-mode-hook))
  (let (subscribed)
    (cl-letf (((symbol-function 'agent-shell-subscribe-to)
               (lambda (&rest args) (push args subscribed))))
      (let ((shell (+test-asb--shell (+test-asb--dir))))
        (with-current-buffer shell
          (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () default-directory)))
            (+my/agent-shell-beads--watch-h)))
        (kill-buffer shell))
      (should-not subscribed)
      (let ((shell (+test-asb--shell (+test-asb--dir t))))
        (with-current-buffer shell
          (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () default-directory)))
            (+my/agent-shell-beads--watch-h)))
        (should (eq (plist-get (car subscribed) :shell-buffer) shell))
        (should (eq (plist-get (car subscribed) :event) 'tool-call-update))
        (kill-buffer shell)))))

;; ====== AN ISSUE INTO THE PROMPT ======

(ert-deftest agent-shell-beads/insert-picks-an-open-issue-ready-first ()
  (+test-asb-with-bd
    (let* ((blocked (alist-get 'id (beads-client-create "Blocked one" :priority 0)))
           (blocker (alist-get 'id (beads-client-create "Blocker" :priority 3)))
           (closed (alist-get 'id (beads-client-create "Done already")))
           (shell (+test-asb--shell root))
           offered inserted)
      (beads-client-request "dep_add" `((from_id . ,blocked) (to_id . ,blocker)))
      (beads-client-close closed "done")
      (unwind-protect
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt candidates &rest _)
                       (setq offered (mapcar #'car candidates))
                       (car offered)))
                    ((symbol-function 'agent-shell-insert)
                     (lambda (&rest args) (push args inserted))))
            (with-current-buffer shell
              (+my/agent-shell-beads-insert))
            ;; Open ones only, the ready one first though its priority is lower.
            (should (= (length offered) 2))
            (should (string-prefix-p blocker (car offered)))
            (should (string-match-p "ready" (car offered)))
            (should (string-prefix-p blocked (cadr offered)))
            (should (equal (plist-get (car inserted) :text) (format "Beads issue %s: Blocker" blocker)))
            (should (eq (plist-get (car inserted) :shell-buffer) shell)))
        (kill-buffer shell)))))

(ert-deftest agent-shell-beads/insert-says-why-not ()
  (should-error (with-temp-buffer (+my/agent-shell-beads-insert)) :type 'user-error)
  (let ((shell (+test-asb--shell (+test-asb--dir))))
    (unwind-protect
        (with-current-buffer shell
          (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () default-directory)))
            (let ((err (should-error (+my/agent-shell-beads-insert) :type 'user-error)))
              (should (string-match-p "bd init" (cadr err))))))
      (kill-buffer shell))))

(ert-deftest agent-shell-beads/send-the-issue-at-point ()
  (let ((shell (+test-asb--shell (+test-asb--dir t)))
        inserted)
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell--shell-buffer) (lambda (&rest _) shell))
                  ((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted))))
          ;; The list: the issue at point.
          (with-temp-buffer
            (beads-list-mode)
            (cl-letf (((symbol-function 'beads-list--get-issue-at-point)
                       (lambda () '((id . "t-7") (title . "Fix it")))))
              (+my/agent-shell-beads-send)))
          (should (equal (car inserted) (list :text "Beads issue t-7: Fix it" :shell-buffer shell)))
          ;; An issue's buffer: the issue shown.
          (with-temp-buffer
            (beads-detail-mode)
            (setq-local beads-detail--current-issue '((id . "t-8") (title . "Shown")))
            (+my/agent-shell-beads-send))
          (should (equal (plist-get (car inserted) :text) "Beads issue t-8: Shown")))
      (kill-buffer shell))))

(ert-deftest agent-shell-beads/send-says-why-not ()
  ;; No issue there.
  (with-temp-buffer
    (beads-list-mode)
    (cl-letf (((symbol-function 'beads-list--get-issue-at-point) #'ignore))
      (should-error (+my/agent-shell-beads-send) :type 'user-error)))
  ;; No session in the project.
  (with-temp-buffer
    (beads-list-mode)
    (cl-letf (((symbol-function 'beads-list--get-issue-at-point) (lambda () '((id . "t-1") (title . "T"))))
              ((symbol-function 'agent-shell--shell-buffer) #'ignore))
      (let ((err (should-error (+my/agent-shell-beads-send) :type 'user-error)))
        (should (string-match-p "SPC o C" (cadr err)))))))
