;;; tests/unit/test-agent-workspace-room.el -*- lexical-binding: t; -*-
;; config/agent-workspace/room.el: the room. Its place in the app (a column on
;; the right, at the bottom, the room alone), its feed (the crew's changes,
;; raised hands, issue events, turns' answers, your messages; filtered), its
;; compose line (#name, #roles, #all, the selected agent; queued when busy;
;; completion, history), what's kept. A real turn of a stand-in agent
;; (examples/agent-workspace/stand-in.el) in the feed.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))

;; ====== HELPERS ======

(defun +test-awr2--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awr2/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awr2 (name &rest body)
  "BODY in a new project NAME (`project'), its app open (a frame 220x40),
agents' sessions plain buffers; `sent' what they were sent."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awr2--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (sent nil))
       (ignore sent)
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
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
                 ((symbol-function 'agent-workspace-send)
                  (lambda (agent text &rest _)
                    (push (list (agent-workspace-agent-name agent) text) sent)
                    (if (eq (agent-workspace-agent-state agent) 'working) 'queued 'sent)))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil))))
         (unwind-protect (progn (agent-workspace-open t) ,@body)
           (dolist (project (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awr2--feed (project)
  "PROJECT's feed's text."
  (with-current-buffer (agent-workspace--room-buffer project)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-awr2--room-windows ()
  "The room's windows: (BUFFER-NAME WIDTH HEIGHT)."
  (mapcar (lambda (w) (list (buffer-name (window-buffer w)) (window-total-width w) (window-total-height w)))
          (seq-filter (lambda (w) (window-parameter w 'agent-workspace-room))
                      (window-list nil 'nomini (frame-first-window)))))

;; ====== ITS PLACE ======

(ert-deftest agent-workspace-room/its-place ()
  "A column on the right, 78 wide: the feed, the compose line (3 rows) below
it; at the bottom (16 rows) in a narrower frame; the room alone (2) the whole
stage's place, the stage back with 1."
  (+test-awr2 "place"
    (agent-workspace-create :role "builder" :name "ada")
    (should (equal (+test-awr2--room-windows)
                   `(("*room · place*" 78 ,(- (window-total-height (frame-root-window)) 3))
                     ("*compose · place*" 78 3))))
    (with-current-buffer (agent-workspace--compose-buffer project)
      (should (string-search "→ ada" (overlay-get agent-workspace--compose-prompt 'before-string))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-view-room))
    (should (equal (mapcar #'car (+test-awr2--room-windows)) '("*room · place*" "*compose · place*")))
    (should-not (get-buffer-window (agent-workspace-agent-buffer (agent-workspace-agent "ada" project))))
    (should (= (window-total-width (get-buffer-window (agent-workspace--room-buffer project))) 170))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-view-stage))
    (should (get-buffer-window (agent-workspace-agent-buffer (agent-workspace-agent "ada" project))))
    ;; A narrower frame: at the bottom.
    (set-frame-size (selected-frame) 160 40)
    (agent-workspace-layout (agent-workspace--app project))
    (should (equal (mapcar #'cdr (+test-awr2--room-windows)) '((110 13) (110 3))))))

;; ====== THE FEED ======

(ert-deftest agent-workspace-room/the-crew-s-changes ()
  "An agent joining (its worktree, its branch), its hand raised, stuck, gone
home, started again, leaving: each a line, its time and name."
  (+test-awr2 "changes"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (agent-workspace--raise-hand ada '(:kind permission :title "npm install" :tool-kind "execute"))
      (agent-workspace--set-state ada 'stuck)
      (agent-workspace-restart ada)
      (agent-workspace-kill ada)
      (agent-workspace-forget ada 'keep))
    (let ((feed (+test-awr2--feed project)))
      (dolist (part '("ada (builder) joined · .agent-shell/worktrees/builder-ada ⑂ agent/ada"
                      "wants to run npm install" "stuck" "started again, fresh" "went home" "left the crew"))
        (should (string-search part feed)))
      (should (string-match-p "\\` [0-9][0-9]:[0-9][0-9] ▌A ada" feed)))))

(ert-deftest agent-workspace-room/what-it-says-of-commands-and-turns ()
  "An agent's bd commands: what they did to an issue; a turn's answer: its
first lines, on one."
  (should (equal (agent-workspace--bd-said "bd close doom-a1b --reason=done") "closed doom-a1b"))
  (should (equal (agent-workspace--bd-said "cd x && bd update doom-a1b --claim --json") "claimed doom-a1b"))
  (should (equal (agent-workspace--bd-said "bd create --title=\"Fix it\" --type=bug") "filed: Fix it"))
  (should (equal (agent-workspace--bd-said "bd create --type=bug --title 'Two words'") "filed: Two words"))
  (should-not (agent-workspace--bd-said "bd list --json"))
  (should-not (agent-workspace--bd-said "git commit -m 'bd close x'"))
  (should (equal (agent-workspace--first-lines "First.\n\nSecond line.\nThird.\nFourth.") "First. Second line. Third."))
  (should (= (length (agent-workspace--first-lines (make-string 400 ?x))) 160)))

(ert-deftest agent-workspace-room/filtered ()
  "F: raised hands only, then the selected agent's only, then all."
  (+test-awr2 "filter"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (agent-workspace-create :role "builder" :name "ken")
      (agent-workspace--raise-hand ada '(:kind question :title "restore or rebuild?"))
      (agent-workspace-select (agent-workspace-agent "ken" project))
      (with-current-buffer (agent-workspace--room-buffer project)
        (agent-workspace-room-filter)
        ;; Only the hand (and its buttons).
        (should (string-search "asks: restore or rebuild?" (+test-awr2--feed project)))
        (should-not (string-search "joined" (+test-awr2--feed project)))
        (agent-workspace-room-filter)
        (should (string-search "ken" (+test-awr2--feed project)))
        (should-not (string-search "ada" (+test-awr2--feed project)))
        (agent-workspace-room-filter)
        (should (string-search "ada" (+test-awr2--feed project)))))))

;; ====== THE COMPOSE LINE ======

(ert-deftest agent-workspace-room/who-a-message-goes-to ()
  "#name to it, #roles to the first free one (else the first live one), #all
to every live agent, no # to the selected one; an unknown name said."
  (+test-awr2 "recipients"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken"))
          (sam (agent-workspace-create :role "investigator" :name "sam")))
      (should (equal (agent-workspace--recipients project "#ken fix it") (cons (list ken) "fix it")))
      (setf (agent-workspace-agent-state ada) 'working)
      (should (equal (agent-workspace--recipients project "#builders go") (cons (list ken) "go")))
      (setf (agent-workspace-agent-state ken) 'working)
      (should (equal (agent-workspace--recipients project "#builders go") (cons (list ada) "go")))
      (should (equal (car (agent-workspace--recipients project "#all hi")) (list ada ken sam)))
      (agent-workspace-select sam)
      (should (equal (agent-workspace--recipients project "look at it") (cons (list sam) "look at it")))
      (should (equal (agent-workspace--recipients project "#nobody hi") (cons nil "No agent or role named nobody"))))))

(ert-deftest agent-workspace-room/sending ()
  "RET sends: to the agent named, said in the feed (queued when it's busy),
the agent selected; the line emptied, the message in its history."
  (+test-awr2 "send"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken")))
      (setf (agent-workspace-agent-state ken) 'working)
      (with-current-buffer (agent-workspace--compose-buffer project)
        (insert "#ken run the tests")
        (agent-workspace-compose-send)
        (should (equal (buffer-string) ""))
        (should (equal sent '(("ken" "run the tests"))))
        (should (eq (agent-workspace--app-selected (agent-workspace--app project)) ken))
        (should (string-search "→ ken run the tests  (queued for ken: busy)" (+test-awr2--feed project)))
        (should (string-search "→ ken" (overlay-get agent-workspace--compose-prompt 'before-string)))
        ;; No #: the selected agent.
        (insert "and the lint")
        (agent-workspace-compose-send)
        (should (equal (car sent) '("ken" "and the lint")))
        ;; #all.
        (insert "#all stop")
        (agent-workspace-compose-send)
        (should (equal (seq-take sent 2) '(("ken" "stop") ("ada" "stop"))))
        (should (string-search "→ all stop" (+test-awr2--feed project)))
        ;; M-p, M-n: what you sent.
        (agent-workspace-compose-previous)
        (should (equal (buffer-string) "#all stop"))
        (agent-workspace-compose-previous)
        (should (equal (buffer-string) "and the lint"))
        (agent-workspace-compose-next)
        (should (equal (buffer-string) "#all stop"))
        (erase-buffer)
        ;; Nothing, or nobody: said.
        (insert "#nobody hi")
        (should-error (agent-workspace-compose-send) :type 'user-error)
        (ignore ada)))))

(ert-deftest agent-workspace-room/typing-a-name-selects-it ()
  "\"#ada \" typed in the compose line selects ada (its pane opens)."
  (+test-awr2 "typing"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (with-current-buffer (agent-workspace--compose-buffer project)
      (insert "#ada ")
      (agent-workspace--compose-typed)
      (should (equal (agent-workspace-agent-name (agent-workspace--app-selected (agent-workspace--app project))) "ada")))))

(ert-deftest agent-workspace-room/completion ()
  "TAB after #: the agents (their role and state), their roles, all."
  (+test-awr2 "completion"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "investigator" :name "sam")
    (with-current-buffer (agent-workspace--compose-buffer project)
      (insert "#")
      (pcase-let ((`(,start ,end ,candidates . ,props) (agent-workspace--compose-capf)))
        (should (= start end))
        (should (equal candidates '("ada" "sam" "builders" "investigators" "all")))
        (should (equal (funcall (plist-get props :annotation-function) "ada") "  builder · at the desk")))
      (erase-buffer)
      (insert "no hash")
      (should-not (agent-workspace--compose-capf)))))

;; ====== KEPT ======

(ert-deftest agent-workspace-room/kept ()
  "Each entry kept in .agent-shell/agent-workspace/room.jsonl; read back when
the app opens again, the file trimmed to the last ones kept."
  (+test-awr2 "kept"
    (agent-workspace-create :role "builder" :name "ada")
    (let ((file (expand-file-name ".agent-shell/agent-workspace/room.jsonl" project)))
      (should (file-exists-p file))
      (with-current-buffer (agent-workspace--issues-buffer project) (agent-workspace-quit))
      (should (string-search "\"kind\":\"joined\"" (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (let ((agent-workspace-room-kept 3))
        (dotimes (i 5)
          (agent-workspace-room-post project :kind 'note :text (format "note %d" i)))
        (agent-workspace-open t)
        (should (string-search "note 4" (+test-awr2--feed project)))
        (should-not (string-search "note 1" (+test-awr2--feed project)))
        (should (= (length (split-string (with-temp-buffer (insert-file-contents file) (buffer-string)) "\n" t)) 3))))))

;; ====== A REAL TURN ======

(ert-deftest agent-workspace-room/a-turn-in-the-feed ()
  "A stand-in agent's turn: its answer's first lines in the feed."
  (+test-with-reset
    (let* ((project (+test-awr2--project "turn"))
           (default-directory project))
      (set-frame-size (selected-frame) 220 40)
      (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore))
        (unwind-protect
            (let ((ada (agent-workspace-create :role "builder" :name "ada" :kind 'mock)))
              (agent-workspace-open t)
              (let ((end (+ (float-time) 20)))
                (while (and (not (eq (agent-workspace-agent-state ada) 'desk)) (< (float-time) end))
                  (accept-process-output nil 0.05)))
              (with-current-buffer (agent-workspace--compose-buffer project)
                (insert "#ada hello there")
                (agent-workspace-compose-send))
              (let ((end (+ (float-time) 20)))
                (while (and (not (string-search "↳ ok: hello there" (+test-awr2--feed project)))
                            (< (float-time) end))
                  (accept-process-output nil 0.05)))
              (should (string-search "→ ada hello there" (+test-awr2--feed project)))
              (should (string-search "↳ ok: hello there" (+test-awr2--feed project))))
          (when (agent-workspace--app project) (agent-workspace--close-app project))
          (agent-workspace-close-all))))))
