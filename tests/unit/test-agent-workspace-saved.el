;;; tests/unit/test-agent-workspace-saved.el -*- lexical-binding: t; -*-
;; config/agent-workspace/saved.el: the crew's configuration in
;; .agent-workspace/crew.el. Written when the crew changes (stable, only what
;; differs), read as data (never evaluated, its problems by line), the crew
;; started again from it (fresh, asleep ones asleep, one that can't start
;; saying why, the layout as it was), read again by hand. An agent's open
;; panels in it by name, kept as the crew closes, opened again with it. In
;; throwaway git repositories; sessions are plain buffers (no agent runs).

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
            (agent-workspace--crew-closed (make-hash-table :test #'equal))
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
 :layout (:view stage :room right :selected nil :open nil :minimap t :talk ask :sources-off nil))
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

(ert-deftest agent-workspace-saved/nothing-written-once-closed ()
  "Closed with its app still open: whatever changes after (an agent
selected, the minimap hidden) writes nothing, crew.el keeping every agent;
a new agent made there, a new crew, written again (doom-51z.15)."
  (+test-aws2 "closed-app-open"
    (agent-workspace-open t)
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (let ((text (+test-aws2--file project)))
      (should (string-search "ken" text))
      (agent-workspace-close project)
      (should (agent-workspace--app project))
      (run-hook-with-args 'agent-workspace-layout-functions project)
      (agent-workspace-crew-save project)
      (should (equal (+test-aws2--file project) text)))
    (agent-workspace-create :role "builder" :name "sam")
    (should (string-search "sam" (+test-aws2--file project)))))

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

;; ====== AN AGENT'S PANELS ======

(defconst +test-aws2--panel
  ";;; panel.el --- Agent UI panel -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type \"text\" :id \"t\" :text \"\")
 :every 60
 :fetch (lambda (panel) (agent-ui-panel-update panel \"t\" :text default-directory)))
"
  "A panel showing where it runs.")

(defmacro +test-aws2-panels (name &rest body)
  "BODY as `+test-aws2' runs it, its project with two panels committed, logs
and tests, and trusted (the trust file the test's own); the panels open
closed after."
  (declare (indent 1))
  `(let ((agent-ui-panel-trust-file (+test-tmp-file (format "aws2-trust-%s.eld" ,name))))
     (unwind-protect
         (+test-aws2 ,name
           (let ((default-directory project))
             (make-directory ".agent-ui/panels" t)
             (dolist (panel '("logs" "tests"))
               (write-region +test-aws2--panel nil (format ".agent-ui/panels/%s.el" panel)))
             (call-process "git" nil nil nil "add" ".agent-ui")
             (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "panels"))
           (agent-ui-panel-trust-project project)
           ,@body)
       (dolist (buffer (buffer-list))
         (when (buffer-local-value 'agent-ui-panels--state buffer)
           (let ((kill-buffer-query-functions nil))
             (kill-buffer buffer)))))))

(defun +test-aws2--open-panel (agent name)
  "Panel NAME opened as AGENT's session opens one (agent-ui open NAME)."
  (agent-ui-open-panel name (agent-workspace-agent-worktree agent) t))

(defun +test-aws2--open-panels ()
  "The panels open: their canvases' names."
  (sort (mapcar #'buffer-name
                (seq-filter (lambda (buffer) (buffer-local-value 'agent-ui-panels--state buffer))
                            (buffer-list)))
        #'string<))

(defun +test-aws2--draft (agent)
  "A panel's file elsewhere in AGENT's worktree: drafts/try.el."
  (let ((draft (expand-file-name "drafts/try.el" (agent-workspace-agent-worktree agent))))
    (make-directory (file-name-directory draft) t)
    (write-region +test-aws2--panel nil draft)))

(ert-deftest agent-workspace-saved/panels-kept-across-a-rename ()
  "An agent renamed (its worktree moved): its panels open again in its new
worktree, named after it, one from a file there too; crew.el keeps them
(doom-ukm.6)."
  (+test-aws2-panels "panels-renamed"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (+test-aws2--draft ada)
      (+test-aws2--open-panel ada "tests")
      (+test-aws2--open-panel ada "drafts/try.el")
      (agent-workspace-rename ada "grace")
      (+test-sleep 0.1)
      (should (equal (+test-aws2--open-panels) '("Agent UI: tests · grace" "Agent UI: try · grace")))
      (dolist (canvas (agent-workspace-agent-panels ada))
        (should (equal (file-name-as-directory
                        (file-truename (agent-ui-panels--root (buffer-local-value 'agent-ui-panels--state canvas))))
                       (file-name-as-directory (file-truename (agent-workspace-agent-worktree ada))))))
      (should (string-search "(:name \"grace\" :role \"builder\" :colour \"blue\" :panels (\"drafts/try.el\" \"tests\"))"
                             (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/an-agents-panels-written ()
  "An agent's open panels in its entry, by name, sorted: written as one opens
or closes; none, no :panels (put to sleep, they close: gone from it). One
opened from a file of its worktree: that file. Yours, from the main
checkout: in no agent's."
  (+test-aws2-panels "panels-written"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken")))
      (+test-aws2--open-panel ada "tests")
      (should (string-search "(:name \"ada\" :role \"builder\" :colour \"blue\" :panels (\"tests\"))"
                             (+test-aws2--file project)))
      (let ((logs (+test-aws2--open-panel ada "logs")))
        (+test-aws2--open-panel ken "tests")
        (agent-ui-open-panel "tests" project)
        (should (string-search ":colour \"blue\" :panels (\"logs\" \"tests\"))" (+test-aws2--file project)))
        (should (string-search "(:name \"ken\" :role \"builder\" :colour \"magenta\" :panels (\"tests\"))"
                               (+test-aws2--file project)))
        (kill-buffer logs)
        (+test-sleep 0.1)
        (should (string-search ":colour \"blue\" :panels (\"tests\"))" (+test-aws2--file project))))
      (+test-aws2--draft ada)
      (+test-aws2--open-panel ada "drafts/try.el")
      (should (equal (agent-workspace-agent-panel-names ada) '("drafts/try.el" "tests")))
      (should (string-search ":panels (\"drafts/try.el\" \"tests\"))" (+test-aws2--file project)))
      (agent-workspace-sleep ken)
      (+test-sleep 0.1)
      (should (string-search "(:name \"ken\" :role \"builder\" :colour \"magenta\" :asleep t)"
                             (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/closing-keeps-the-panels ()
  "The crew closed: its agents' panels close with them, crew.el keeps them
\(Q; agent-workspace-close with its app open); a write still to come, with
them, done first."
  (+test-aws2-panels "panels-closing"
    (agent-workspace-open t)
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (tests (+test-aws2--open-panel ada "tests"))
           (text (+test-aws2--file project)))
      (should (string-search ":panels (\"tests\")" text))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-quit))
      (should-not (buffer-live-p tests))
      (+test-sleep 0.2)
      (should (equal (+test-aws2--file project) text))))
  (+test-aws2-panels "panels-closing-app-open"
    (agent-workspace-open t)
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (tests (+test-aws2--open-panel ada "tests"))
           (text (+test-aws2--file project)))
      (agent-workspace-close project)
      (should-not (buffer-live-p tests))
      (+test-sleep 0.2)
      (should (equal (+test-aws2--file project) text))))
  ;; One closed as the crew closes (its change said after): nothing written
  ;; after, its crew gone.
  (+test-aws2-panels "panels-closing-at-once"
    (agent-workspace-open t)
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (logs (+test-aws2--open-panel ada "logs"))
           (text (progn (+test-aws2--open-panel ada "tests") (+test-aws2--file project))))
      (kill-buffer logs)
      (agent-workspace-close project)
      (+test-sleep 0.2)
      (should (equal (+test-aws2--file project) text))))
  ;; Debounced for real: the write closing does has them.
  (+test-aws2-panels "panels-flushed"
    (cl-letf* ((run-at-time (symbol-function 'run-at-time))
               ((symbol-function 'run-at-time)
                (lambda (time repeat fn &rest args)
                  (if (eq fn #'agent-workspace-crew-save)
                      (funcall run-at-time 3600 nil #'ignore)
                    (apply run-at-time time repeat fn args)))))
      (let ((ada (agent-workspace-create :role "builder" :name "ada")))
        (+test-aws2--open-panel ada "tests")
        (should-not (+test-aws2--file project))
        (agent-workspace-close project)
        (+test-sleep 0.2)
        (should (string-search "(:name \"ada\" :role \"builder\" :colour \"blue\" :panels (\"tests\"))"
                               (+test-aws2--file project)))))))

(ert-deftest agent-workspace-saved/wrong-panels-left-out ()
  "An entry whose :panels isn't a list of names is left out, its line said."
  (+test-aws2 "wrong-panels"
    (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :panels (\"tests\"))
          (:name \"ken\" :role \"builder\" :panels \"tests\")
          (:name \"sam\" :role \"builder\" :panels (\"tests\" logs))
          (:name \"tim\" :role \"builder\" :panels (\"tests\" . \"logs\"))
          (:name \"una\" :role \"builder\" :panels (\"\")))
 :layout nil)
")
    (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
      (should (equal (plist-get crew :agents) '((:name "ada" :role "builder" :panels ("tests")))))
      (should (equal problems
                     '(".agent-workspace/crew.el:4: ken's panels \"tests\" aren't a list of names: left out"
                       ".agent-workspace/crew.el:5: sam's panels (\"tests\" logs) aren't a list of names: left out"
                       ".agent-workspace/crew.el:6: tim's panels (\"tests\" . \"logs\") aren't a list of names: left out"
                       ".agent-workspace/crew.el:7: una's panels (\"\") aren't a list of names: left out"))))))

(ert-deftest agent-workspace-saved/panels-opened-again ()
  "Started again from crew.el: each agent that starts opens its panels again,
in its worktree (its own, shown only as its pane's tabs: one at a time); an
asleep one, none; one whose file is gone skipped, said, the others open.
Nothing written meanwhile."
  (+test-aws2-panels "panels-again"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (agent-workspace-close project)
    (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"blue\" :panels (\"gone\" \"logs\" \"tests\"))
          (:name \"ken\" :role \"builder\" :colour \"green\" :asleep t :panels (\"tests\")))
 :layout (:view stage :room right :selected \"ada\" :open t))
")
    (let ((warned nil))
      (cl-letf (((symbol-function 'display-warning) (lambda (_type message &rest _) (push message warned))))
        (agent-workspace-open t))
      (let ((ada (agent-workspace-agent "ada" project)))
        (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ada" "Agent UI: tests · ada")))
        (dolist (canvas (agent-workspace-agent-panels ada))
          (should (equal (file-truename (agent-ui-panels--root (buffer-local-value 'agent-ui-panels--state canvas)))
                         (file-truename (agent-workspace-agent-worktree ada))))
          (dolist (window (get-buffer-window-list canvas nil t))
            (should (eq (window-parameter window 'agent-workspace-side) ada))))
        (should (<= (seq-count (lambda (canvas) (get-buffer-window canvas t)) (agent-workspace-agent-panels ada))
                    1)))
      (should (equal warned '("ada's panel gone: not one of this project's: logs, tests: skipped"))))
    (should (string-search ":panels (\"gone\" \"logs\" \"tests\")" (+test-aws2--file project)))))

(ert-deftest agent-workspace-saved/an-asleep-agents-panels-when-it-wakes ()
  "Started again asleep: its panels kept in crew.el (written meanwhile), none
open; woken, they open (doom-ukm.7)."
  (+test-aws2-panels "asleep-panels"
    (agent-workspace-create :role "builder" :name "ken")
    (agent-workspace-close project)
    (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ken\" :role \"builder\" :colour \"green\" :asleep t :panels (\"logs\" \"tests\")))
 :layout (:view stage :room right :selected \"ken\" :open t))
")
    (agent-workspace-open t)
    (let ((ken (agent-workspace-agent "ken" project)))
      (should (eq (agent-workspace-agent-state ken) 'asleep))
      (should-not (+test-aws2--open-panels))
      (agent-workspace-recolour ken "blue")
      (should (string-search "(:name \"ken\" :role \"builder\" :colour \"blue\" :asleep t :panels (\"logs\" \"tests\"))"
                             (+test-aws2--file project)))
      (agent-workspace-wake ken)
      (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ken" "Agent UI: tests · ken")))
      (+test-sleep 0.1)
      (should (string-search "(:name \"ken\" :role \"builder\" :colour \"blue\" :panels (\"logs\" \"tests\"))"
                             (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/read-again-applies-panels ()
  "gR after crew.el's :panels edited: a running agent's opened and closed as
listed; an asleep one's kept for when it wakes (doom-ukm.7)."
  (+test-aws2-panels "reload-panels"
    (agent-workspace-open t)
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken")))
      (+test-aws2--open-panel ada "tests")
      (agent-workspace-sleep ken)
      (+test-sleep 0.1)
      (+test-aws2--write project "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"blue\" :panels (\"logs\"))
          (:name \"ken\" :role \"builder\" :colour \"magenta\" :asleep t :panels (\"tests\")))
 :layout (:view stage :room right :selected \"ada\" :open t))
")
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-crew-reload))
      (+test-sleep 0.1)
      (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ada")))
      (agent-workspace-wake ken)
      (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ada" "Agent UI: tests · ken"))))))

(ert-deftest agent-workspace-saved/panels-closed-and-opened-again ()
  "Q, then SPC o w: each agent's panels open again with it, in its worktree
\(one from a file there too); the one put to sleep closed its own: none."
  (+test-aws2-panels "panels-cycle"
    (agent-workspace-open t)
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken"))
          (sam (agent-workspace-create :role "builder" :name "sam")))
      (+test-aws2--draft ada)
      (+test-aws2--open-panel ada "tests")
      (+test-aws2--open-panel ada "logs")
      (+test-aws2--open-panel ada "drafts/try.el")
      (+test-aws2--open-panel ken "tests")
      (+test-aws2--open-panel sam "logs")
      (agent-workspace-sleep sam)
      (+test-sleep 0.1))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (should-not (+test-aws2--open-panels))
    (agent-workspace-open t)
    (should (equal (+test-aws2--open-panels)
                   '("Agent UI: logs · ada" "Agent UI: tests · ada" "Agent UI: tests · ken" "Agent UI: try · ada")))
    (should (equal (agent-workspace-agent-panel-names (agent-workspace-agent "ada" project))
                   '("drafts/try.el" "logs" "tests")))
    (should (eq (agent-workspace-agent-state (agent-workspace-agent "sam" project)) 'asleep))))
