;;; tests/unit/test-agent-workspace-saved.el -*- lexical-binding: t; -*-
;; config/agent-workspace/saved.el: the crew's configuration in
;; .agent-workspace/crew.el. Written when the crew changes (stable, only what
;; differs), read as data (never evaluated, its problems by line), the crew
;; started again from it (fresh, asleep ones asleep, one that can't start
;; saying why, the layout as it was), read again by hand. In throwaway git
;; repositories; sessions are plain buffers (no agent runs).

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(+test-load "config/agent-ui" "config/agent-workspace")

;; ====== HELPERS ======

(defun +test-aws2--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aws2/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-aws2 (name &rest body)
  "BODY in a new project NAME (`project'), no crew or app before or after;
sessions plain buffers (`started' lists the agents started); crew.el written
at once (no wait)."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-aws2--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--crew-timers (make-hash-table :test #'equal))
            (started nil))
       (ignore started)
       (set-frame-size (selected-frame) 160 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (push (agent-workspace-agent-name agent) started)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer)
                      (agent-workspace--set-state agent 'desk)
                      (agent-workspace--changed agent 'session)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil)
                    (agent-workspace--set-state agent state)
                    nil))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil)))
                 ((symbol-function 'run-at-time)
                  (let ((run-at-time (symbol-function 'run-at-time)))
                    (lambda (time repeat fn &rest args)
                      (if (eq fn #'agent-workspace-crew-save)
                          (progn (apply fn args) nil)
                        (apply run-at-time time repeat fn args))))))
         (unwind-protect (progn ,@body)
           (dolist (project (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-aws2--file (project)
  "PROJECT's crew.el's text, or nil."
  (let ((file (expand-file-name ".agent-workspace/crew.el" project)))
    (and (file-exists-p file) (with-temp-buffer (insert-file-contents file) (buffer-string)))))

(defun +test-aws2--write (project text)
  "PROJECT's crew.el now TEXT."
  (let ((file (expand-file-name ".agent-workspace/crew.el" project)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

;; ====== WRITTEN ======

(ert-deftest agent-workspace-saved/its-text ()
  "One agent a line, in role order then by name; its model and mode only
when not its role's; asleep said; the layout."
  (+test-aws2 "text"
    (let ((sam (agent-workspace-create :role "investigator" :name "sam" :model "opus"))
          (ken (agent-workspace-create :role "builder" :name "ken" :colour "green" :mode "acceptEdits"))
          (ada (agent-workspace-create :role "builder" :name "ada" :mode "plan")))
      (agent-workspace-sleep ken)
      (ignore sam ada)
      (should (equal (agent-workspace-crew-text project)
                     ";;; crew.el --- Agent workspace: the crew -*- lexical-binding: t; -*-
;; Read as data, never evaluated (config/agent-workspace/saved.el). SPC o w starts it again.
(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"blue\" :mode \"plan\")
          (:name \"ken\" :role \"builder\" :colour \"green\" :asleep t)
          (:name \"sam\" :role \"investigator\" :colour \"magenta\" :model \"opus\"))
 :layout (:view stage :room right :selected nil :open nil))
")))))

(ert-deftest agent-workspace-saved/written-when-the-crew-changes ()
  "Made, recoloured, put to sleep, woken, forgotten: written; a state alone
\(working, done): not."
  (+test-aws2 "written"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (should (string-search "(:name \"ada\" :role \"builder\" :colour \"blue\")" (+test-aws2--file project)))
      (agent-workspace-recolour ada "cyan")
      (should (string-search ":colour \"cyan\"" (+test-aws2--file project)))
      (agent-workspace-sleep ada)
      (should (string-search ":asleep t" (+test-aws2--file project)))
      (agent-workspace-wake ada)
      (should-not (string-search ":asleep" (+test-aws2--file project)))
      (let ((before (file-attribute-modification-time
                     (file-attributes (expand-file-name ".agent-workspace/crew.el" project)))))
        (agent-workspace--set-state ada 'working)
        (agent-workspace--set-state ada 'done)
        (should (equal (file-attribute-modification-time
                        (file-attributes (expand-file-name ".agent-workspace/crew.el" project)))
                       before)))
      (agent-workspace-create :role "builder" :name "ken")
      (agent-workspace-forget ada 'keep)
      (should-not (string-search "ada" (+test-aws2--file project)))
      (should (string-search "ken" (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/closing-keeps-it ()
  "Closing the crew leaves crew.el as it was (every agent in it, none asleep
that wasn't); a write still to come is done first."
  (+test-aws2 "closing"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (let ((text (+test-aws2--file project)))
      (agent-workspace-close project)
      (should (equal (+test-aws2--file project) text))))
  ;; Debounced for real: closing flushes it.
  (+test-aws2 "flushed"
    (cl-letf* ((run-at-time (symbol-function 'run-at-time))
               ((symbol-function 'run-at-time)
                (lambda (&rest _) (funcall run-at-time 3600 nil #'ignore))))
      (agent-workspace-create :role "builder" :name "ada")
      (should-not (+test-aws2--file project))
      (agent-workspace-close project)
      (should (string-search "ada" (+test-aws2--file project))))))

;; ====== READ ======

(ert-deftest agent-workspace-saved/read-as-data ()
  "Read, never evaluated: what isn't a crew is said, nothing run."
  (+test-aws2 "read"
    (+test-aws2--write project "(progn (setq +test-aws2-evaluated t))\n")
    (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
      (should-not crew)
      (should (string-match-p "\\`\\.agent-workspace/crew\\.el:1: not a crew" (car problems))))
    (should-not (boundp '+test-aws2-evaluated))
    (should-not (agent-workspace-crew-read (+test-aws2--project "none")))))

(ert-deftest agent-workspace-saved/a-wrong-agent-left-out ()
  "A wrong agent entry is left out, its line said; the others read."
  (+test-aws2 "wrong"
    (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"blue\")
          (:name \"Bad Name\" :role \"builder\")
          (:name \"ken\" :role \"builder\" :colour \"pink\")
          (:name \"sam\" :role \"investigator\" :mode \"yolo\")
          (:name \"ada\" :role \"scribe\")
          (:name \"tim\"))
 :colours 3
 :layout (:selected \"ada\" :open t))
")
    (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
      (should (equal (mapcar (lambda (entry) (plist-get entry :name)) (plist-get crew :agents)) '("ada")))
      (should (equal (plist-get crew :layout) '(:selected "ada" :open t)))
      (should (equal problems
                     '(".agent-workspace/crew.el:4: not a name: \"Bad Name\": left out"
                       ".agent-workspace/crew.el:5: ken's colour \"pink\" isn't one of blue, magenta, green, yellow, cyan, red, white, black: left out"
                       ".agent-workspace/crew.el:6: sam's mode \"yolo\" isn't one of default, acceptEdits, plan, dontAsk, bypassPermissions: left out"
                       ".agent-workspace/crew.el:7: ada twice: left out"
                       ".agent-workspace/crew.el:8: tim has no role: left out"
                       ".agent-workspace/crew.el:9: unknown key :colours: ignored"))))))

;; ====== STARTED AGAIN ======

(ert-deftest agent-workspace-saved/started-again ()
  "SPC o w with no crew running: every agent in crew.el again, fresh, in its
worktree (reused), its colour, model, mode; asleep ones asleep (no session);
one whose role is gone stuck, saying why; the selected one's pane open."
  (+test-aws2 "again"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (write-region "work\n" nil (expand-file-name "wip" (agent-workspace-agent-worktree ada))))
    (agent-workspace-close project)
    (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"blue\")
          (:name \"ken\" :role \"builder\" :colour \"green\" :asleep t)
          (:name \"sam\" :role \"investigator\" :colour \"magenta\" :model \"opus\" :mode \"plan\")
          (:name \"tim\" :role \"wizard\" :colour \"cyan\"))
 :layout (:view stage :room right :selected \"sam\" :open t))
")
    (setq started nil)
    (let ((app (agent-workspace-open t)))
      (should (equal (sort (copy-sequence started) #'string<) '("ada" "sam")))
      (let ((ada (agent-workspace-agent "ada" project))
            (ken (agent-workspace-agent "ken" project))
            (sam (agent-workspace-agent "sam" project))
            (tim (agent-workspace-agent "tim" project)))
        (should (eq (agent-workspace-agent-state ada) 'desk))
        (should (file-exists-p (expand-file-name "wip" (agent-workspace-agent-worktree ada))))
        (should (eq (agent-workspace-agent-state ken) 'asleep))
        (should-not (agent-workspace-agent-buffer ken))
        (should (file-directory-p (agent-workspace-agent-worktree ken)))
        (should (equal (list (agent-workspace-agent-colour sam) (agent-workspace-agent-model sam)
                             (agent-workspace-agent-mode sam))
                       '("magenta" "opus" "plan")))
        (should (eq (agent-workspace-agent-state tim) 'stuck))
        (should (equal (agent-workspace-agent-error tim) "its role wizard is gone"))
        (should (eq (agent-workspace--app-selected app) sam))
        (should (eq (agent-workspace--app-open app) sam))
        (should (get-buffer-window (agent-workspace-agent-buffer sam)))))
    ;; Started again: crew.el as it was (nothing written meanwhile).
    (should (string-search "\"tim\" :role \"wizard\"" (+test-aws2--file project)))))

(ert-deftest agent-workspace-saved/closed-and-opened-again ()
  "Q, then SPC o w: the same agents (names, roles, colours, models, modes),
fresh, waiting; the asleep one asleep; the same agent selected."
  (+test-aws2 "cycle"
    (agent-workspace-open t)
    (agent-workspace-create :role "builder" :name "ada" :colour "yellow")
    (agent-workspace-create :role "investigator" :name "sam" :model "haiku")
    (let ((ken (agent-workspace-create :role "builder" :name "ken")))
      (agent-workspace-sleep ken))
    (agent-workspace-select (agent-workspace-agent "sam" project))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (should-not (agent-workspace-agents project))
    (setq started nil)
    (let ((app (agent-workspace-open t)))
      (should (equal (mapcar (lambda (agent)
                               (list (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)
                                     (agent-workspace-agent-colour agent) (agent-workspace-agent-model agent)
                                     (agent-workspace-agent-state agent)))
                             (agent-workspace--ordered project))
                     '(("ada" "builder" "yellow" nil desk) ("ken" "builder" "blue" nil asleep)
                       ("sam" "investigator" "magenta" "haiku" desk))))
      (should (equal (sort (copy-sequence started) #'string<) '("ada" "sam")))
      (should (equal (agent-workspace-agent-name (agent-workspace--app-selected app)) "sam")))))

(ert-deftest agent-workspace-saved/read-again ()
  "gR: an agent added to crew.el started, one taken out forgotten, each
asked first; a colour changed applied."
  (+test-aws2 "reload"
    (agent-workspace-open t)
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"red\")
          (:name \"sam\" :role \"scribe\" :colour \"cyan\"))
 :layout (:view stage :room right :selected \"ada\" :open t))
")
    (let ((asked nil))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) t)))
        (with-current-buffer (agent-workspace--issues-buffer project)
          (agent-workspace-crew-reload)))
      (should (equal (reverse asked) '("Start sam (scribe), new in crew.el? "
                                       "Forget ken, gone from crew.el (its worktree kept)? "))))
    (should (equal (mapcar #'agent-workspace-agent-name (agent-workspace--ordered project)) '("ada" "sam")))
    (should (equal (agent-workspace-agent-colour (agent-workspace-agent "ada" project)) "red"))
    (should (eq (agent-workspace-agent-state (agent-workspace-agent "sam" project)) 'desk))))
