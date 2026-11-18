;;; tests/unit/test-agent-workspace-room.el -*- lexical-binding: t; -*-
;; config/agent-workspace/room.el: the room. Its place in the app (a column on
;; the right, at the bottom, the room alone), its feed (the crew's changes,
;; raised hands, what agents did to issues (fetches compared, from the first
;; after the app opens), turns' answers, your messages; filtered), its
;; compose line (#name, #roles, #all, the selected agent; queued when busy;
;; completion, history), what's kept. A real turn of a stand-in agent
;; (examples/agent-workspace/stand-in.el) in the feed.
;; run.sh: slow (~55 s in a full run: a stand-in turn, bd).

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
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
         (unwind-protect (progn (agent-workspace-open t) ,@body)
           (dolist (project (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awr2--feed (project)
  "PROJECT's feed's text."
  (with-current-buffer (agent-workspace--room-buffer project)
    (buffer-substring-no-properties (point-min) (point-max))))

(defconst +test-awr2--refresh (symbol-function 'agent-workspace--issues-refresh)
  "issues.el's fetch, as it is (the tests' crews stub it).")

(defun +test-awr2--issue (id &rest props)
  "An issue as fetched (issues.el's :issues): ID, open, no labels; PROPS
over that."
  (append props (list :id id :title (concat "Title of " id) :status 'open :labels nil)))

(defun +test-awr2--room-windows ()
  "The room's windows: (BUFFER-NAME WIDTH HEIGHT)."
  (mapcar (lambda (w) (list (buffer-name (window-buffer w)) (window-total-width w) (window-total-height w)))
          (seq-filter (lambda (w) (window-parameter w 'agent-workspace-room))
                      (window-list nil 'nomini (frame-first-window)))))

;; ====== ITS PLACE ======

(defun +test-awr2--compose-window (project)
  "PROJECT's compose line's window."
  (get-buffer-window (agent-workspace--compose-buffer project)))

(ert-deftest agent-workspace-room/its-place ()
  "A column on the right, 78 wide: the feed, the compose line (its header
line, a line of text) below it; at the bottom (16 rows) in a narrower
frame; the room alone (2) the whole stage's place, the stage back with 1."
  (+test-awr2 "place"
    (agent-workspace-create :role "builder" :name "ada")
    (should (equal (+test-awr2--room-windows)
                   `(("*room · place*" 78 ,(- (window-total-height (frame-root-window)) 2))
                     ("*compose · place*" 78 2))))
    (should (= (window-body-height (+test-awr2--compose-window project)) 1))
    (with-current-buffer (agent-workspace--compose-buffer project)
      (should (string-search "→ ada" (overlay-get agent-workspace--compose-prompt 'before-string))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-view-room))
    (should (equal (mapcar #'car (+test-awr2--room-windows)) '("*room · place*" "*compose · place*")))
    (should-not (get-buffer-window (agent-workspace-agent-buffer (agent-workspace-agent "ada" project))))
    (should (= (window-total-width (get-buffer-window (agent-workspace--room-buffer project))) 170))
    (should (= (window-body-height (+test-awr2--compose-window project)) 1))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-view-stage))
    (should (get-buffer-window (agent-workspace-agent-buffer (agent-workspace-agent "ada" project))))
    ;; A narrower frame: at the bottom.
    (set-frame-size (selected-frame) 160 40)
    (agent-workspace-layout (agent-workspace--app project))
    (should (equal (mapcar #'cdr (+test-awr2--room-windows)) '((110 14) (110 2))))
    (should (= (window-body-height (+test-awr2--compose-window project)) 1))))

;; ====== THE FEED ======

(ert-deftest agent-workspace-room/alone-its-own-header ()
  "The room alone (2), in the window the stage's open pane had: its own
header line, ROOM and its filter, not the pane's (doom-pbk.86)."
  (+test-awr2 "alone-header"
    (agent-workspace-create :role "builder" :name "ada")
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-view-room))
    (let ((window (get-buffer-window (agent-workspace--room-buffer project))))
      (should-not (window-parameter window 'header-line-format))
      (with-selected-window window
        (should (equal header-line-format '(:eval (agent-workspace--room-header))))
        (should (string-search "ROOM" (substring-no-properties (agent-workspace--room-header))))))))

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

(ert-deftest agent-workspace-room/what-it-says-of-a-turn ()
  "A turn's answer: its first lines, on one."
  (should (equal (agent-workspace--first-lines "First.\n\nSecond line.\nThird.\nFourth.") "First. Second line. Third."))
  (should (= (length (agent-workspace--first-lines (make-string 400 ?x))) 160)))

;; ====== WHAT AGENTS DID TO ISSUES ======

(ert-deftest agent-workspace-room/what-agents-did-to-issues ()
  "Two fetches compared, as the issues say it: filed (by its creator, an
agent), claimed (by its assignee), closed (by its assignee; no one's, the
agent whose bd command it was), a label added (that agent's: labelled);
what's no agent's (you, another program; assigned to you), nothing; an
issue reopened, not filed."
  (let* ((project (agent-workspace--root (+test-awr2--project "said")))
         (agent-workspace--crews (make-hash-table :test #'equal))
         (since (float-time))
         (now (format-time-string "%FT%TZ" nil t))
         (before (list (+test-awr2--issue "p-1")
                       (+test-awr2--issue "p-2")
                       (+test-awr2--issue "p-3" :status 'in_progress :assignee "ken")
                       (+test-awr2--issue "p-4")
                       (+test-awr2--issue "p-5" :labels '("docs"))
                       (+test-awr2--issue "p-6" :status 'in_progress :assignee "Yorgos")))
         (after (list (+test-awr2--issue "p-1" :status 'in_progress :assignee "ken")
                      (+test-awr2--issue "p-2" :status 'in_progress :assignee "Yorgos")
                      (+test-awr2--issue "p-3" :status 'closed :assignee "ken")
                      (+test-awr2--issue "p-4" :status 'closed)
                      (+test-awr2--issue "p-5" :labels '("docs" "build"))
                      (+test-awr2--issue "p-6" :status 'closed :assignee "Yorgos")
                      (+test-awr2--issue "p-7" :title "Fix the lexer" :created-by "ada" :created now)
                      (+test-awr2--issue "p-8" :created-by "Yorgos" :created now)
                      (+test-awr2--issue "p-9" :created-by "ada" :created "2020-01-01T00:00:00Z"))))
    (puthash project (list (agent-workspace--make-agent :name "ada" :role "scribe" :project project)
                           (agent-workspace--make-agent :name "ken" :role "builder" :project project))
             agent-workspace--crews)
    ;; After ada's bd command.
    (should (equal (agent-workspace--issues-said project before after "ada" since)
                   '(("ken" . "claimed p-1") ("ken" . "closed p-3") ("ada" . "closed p-4")
                     ("ada" . "labelled p-5 build") ("ada" . "filed: Fix the lexer"))))
    ;; No agent's bd command led to it (gr): only what the issues say.
    (should (equal (agent-workspace--issues-said project before after nil since)
                   '(("ken" . "claimed p-1") ("ken" . "closed p-3") ("ada" . "filed: Fix the lexer"))))
    ;; Nothing changed: nothing said.
    (should-not (agent-workspace--issues-said project after after "ada" since))))

(ert-deftest agent-workspace-room/what-agents-did-to-issues-in-the-feed ()
  "An agent's command with bd in it (on several lines, through a variable)
asks for a fetch, noted as its: the first after the app opens is the
baseline (nothing said for what was there); then what changed, under the
agent's name, in the feed. One asked while a fetch runs is done after it. A
change of yours (gr: no agent's), nothing. The app opened again: a baseline
again."
  (should (agent-workspace--bd-command-p "bd create \\\n  --title 'Fix it' \\\n  --description \"$(cat <<'EOF'\nx\nEOF\n)\""))
  (should (agent-workspace--bd-command-p "cd x && bd update doom-a1b --claim"))
  (should (agent-workspace--bd-command-p "B=bd; $B close doom-a1b"))
  (should-not (agent-workspace--bd-command-p "abd --x; bd-tool run; git status"))
  (+test-awr2 "fetched"
    (make-directory (expand-file-name ".beads" project))
    (agent-workspace-create :role "scribe" :name "ada")
    (let* ((calls nil)
           (now (format-time-string "%FT%TZ" nil t))
           ;; bd answering the fetch running: ALL open, DONE closed today.
           (answer (lambda (all &optional done)
                     (dolist (call (prog1 (nreverse calls) (setq calls nil)))
                       (funcall (cdr call) (cond ((member "ready" (car call)) nil)
                                                 ((member "closed" (car call)) done)
                                                 (t all))))))
           (issue (lambda (id &rest more)
                    (append more `((id . ,id) (title . ,(concat "Title of " id)) (status . "open")
                                   (created_by . "ada") (created_at . "2020-01-01T00:00:00Z"))))))
      (cl-letf (((symbol-function 'agent-workspace--issues-refresh) +test-awr2--refresh)
                ((symbol-function 'executable-find) (lambda (name &rest _) (and (equal name "bd") "/usr/bin/bd")))
                ((symbol-function 'agent-workspace--bd)
                 (lambda (_dir args callback) (push (cons args callback) calls) nil)))
        ;; The baseline: what's there, nothing said.
        (agent-workspace--issues-refresh project)
        (should (= (length calls) 3))
        (funcall answer (list (funcall issue "p-1")))
        (should-not (string-search "p-1" (+test-awr2--feed project)))
        ;; Ada's bd command; another while its fetch runs.
        (agent-workspace--issues-refresh-soon project "ada")
        (should (+test-wait-for (lambda () calls) 5))
        (agent-workspace--issues-refresh-soon project "ada")
        (+test-sleep 0.7)
        (should (= (length calls) 3))
        (funcall answer (list (funcall issue "p-1" '(status . "in_progress") '(assignee . "ada"))
                              (funcall issue "p-2" '(title . "Fix the lexer") `(created_at . ,now))))
        (let ((feed (+test-awr2--feed project)))
          (should (string-search "◆ claimed p-1" feed))
          (should (string-search "◆ filed: Fix the lexer" feed))
          (should-not (string-search "Title of p-1" feed)))
        ;; Fetched again, after it.
        (should (= (length calls) 3))
        (funcall answer (list (funcall issue "p-1" '(status . "in_progress") '(assignee . "ada"))
                              (funcall issue "p-2" '(title . "Fix the lexer") '(labels "build"))))
        (should (string-search "◆ labelled p-2 build" (+test-awr2--feed project)))
        ;; Yours (gr): closed, nobody's: nothing.
        (agent-workspace--issues-refresh project)
        (funcall answer (list (funcall issue "p-1" '(status . "in_progress") '(assignee . "ada")))
                 (list (funcall issue "p-2" '(status . "closed") '(title . "Fix the lexer"))))
        (should-not (string-search "closed p-2" (+test-awr2--feed project)))
        ;; The app opened again (its crew with it, from crew.json): its first
        ;; fetch a baseline again.
        (agent-workspace--close-app project)
        (setq calls nil)
        (agent-workspace-open t)
        (unless (agent-workspace-agent "ada" project)
          (agent-workspace-create :role "scribe" :name "ada"))
        (unless calls (agent-workspace--issues-refresh project))
        (funcall answer (list (funcall issue "p-3" `(created_at . ,now))))
        (should-not (string-search "p-3" (+test-awr2--feed project)))
        (agent-workspace--issues-refresh-soon project "ada")
        (should (+test-wait-for (lambda () calls) 5))
        (funcall answer (list (funcall issue "p-3" `(created_at . ,now))
                              (funcall issue "p-4" '(title . "Again") `(created_at . ,now))))
        (should (string-search "◆ filed: Again" (+test-awr2--feed project)))))))

(ert-deftest agent-workspace-room/a-fetch-that-hangs ()
  "bd hanging on a fetch: stopped after `agent-workspace-issues-timeout', its
bd commands killed, the list saying so; a fetch asked for meanwhile done
after it. gr while one hangs: it's stopped and a new one started; bd
answering again, the list as fetched (doom-pbk.43)."
  (+test-awr2 "hangs"
    (make-directory (expand-file-name ".beads" project))
    (let* ((bin (file-name-as-directory (make-temp-file (+test-tmp-file "hanging-bd-") t)))
           (hang (expand-file-name "hang" bin))
           (exec-path (cons bin exec-path))
           (process-environment (cons (concat "PATH=" bin path-separator (getenv "PATH")) process-environment))
           (agent-workspace-issues-timeout 1)
           (buffer (agent-workspace--issues-buffer project))
           (bds (lambda () (seq-filter (lambda (process) (and (equal (process-get process 'agent-workspace-project)
                                                                     (agent-workspace--root project))
                                                              (process-live-p process)))
                                       (process-list)))))
      (with-temp-file (expand-file-name "bd" bin)
        (insert "#!/bin/sh\n[ \"$1\" = ready ] && [ -f " (shell-quote-argument hang) " ] && exec sleep 300\n"
                "echo '[{\"id\":\"p-1\",\"title\":\"Fix it\",\"status\":\"open\"}]'\n"))
      (set-file-modes (expand-file-name "bd" bin) #o755)
      (write-region "" nil hang)
      (cl-letf (((symbol-function 'agent-workspace--issues-refresh) +test-awr2--refresh))
        (agent-workspace--issues-refresh project)
        (should (buffer-local-value 'agent-workspace--issues-pending buffer))
        ;; Another asked for meanwhile: waits for it.
        (agent-workspace--issues-refresh project)
        (should (buffer-local-value 'agent-workspace--issues-again buffer))
        (should (+test-wait-for (lambda () (plist-get (buffer-local-value 'agent-workspace--issues-data buffer) :error))
                                5))
        (should (equal (plist-get (buffer-local-value 'agent-workspace--issues-data buffer) :error)
                       "bd didn't answer in 1s: gr fetches again."))
        (should (string-search "bd didn't answer in 1s" (with-current-buffer buffer (buffer-string))))
        ;; The one asked for meanwhile, started (hanging too).
        (should (buffer-local-value 'agent-workspace--issues-pending buffer))
        (should-not (buffer-local-value 'agent-workspace--issues-again buffer))
        ;; gr: stopped, a new one started.
        (let ((before (buffer-local-value 'agent-workspace--issues-pending buffer))
              (killed (funcall bds)))
          (should killed)
          (with-current-buffer buffer (agent-workspace-issues-refresh))
          (should-not (seq-some #'process-live-p killed))
          (should (buffer-local-value 'agent-workspace--issues-pending buffer))
          (should-not (eq (buffer-local-value 'agent-workspace--issues-pending buffer) before)))
        ;; bd answering again: gr fetches.
        (delete-file hang)
        (with-current-buffer buffer (agent-workspace-issues-refresh))
        (should (+test-wait-for (lambda () (not (buffer-local-value 'agent-workspace--issues-pending buffer))) 10))
        (should-not (plist-get (buffer-local-value 'agent-workspace--issues-data buffer) :error))
        (should (string-search "p-1" (with-current-buffer buffer (buffer-string))))
        (should-not (funcall bds))))))

(ert-deftest agent-workspace-room/a-post-appends-its-lines ()
  "A post with nothing above it changed appends its lines, the feed not
drawn again; at its kept limit the oldest line goes from the top. Several
changes in a command (an #all event to 4 agents, 500 entries kept): drawn
again once, after it, the command well under 100 ms. Neither the room nor
the issue list keeps undo (doom-pbk.48)."
  (+test-awr2 "appends"
    (dolist (spec '(("ada" "builder") ("ken" "builder") ("sam" "investigator") ("liz" "builder")))
      (agent-workspace-create :role (cadr spec) :name (car spec)))
    (let* ((agent-workspace-room-kept 500)
          (redraws 0)
          (count (lambda (&rest _) (setq redraws (1+ redraws))))
          (buffer (agent-workspace--room-buffer project)))
      (dotimes (i 500)
        (agent-workspace-room-post project :kind 'note :agent "ada" :text (format "note %d, some words" i)))
      (agent-workspace--room-buffer project)
      (advice-add 'agent-workspace--room-redraw :before count)
      (unwind-protect
          (progn
            ;; A post: appended, the first line gone, nothing drawn again.
            (let ((lines (with-current-buffer buffer (count-lines (point-min) (point-max)))))
              (agent-workspace-room-post project :kind 'note :agent "ada" :text "the last one")
              (should (= redraws 0))
              (with-current-buffer buffer
                (should (= (count-lines (point-min) (point-max)) lines))
                (should (string-suffix-p "the last one\n" (buffer-substring-no-properties (point-min) (point-max))))
                (should-not (string-search "note 0," (buffer-string)))
                (should (string-search "note 1," (buffer-string)))))
            ;; An #all event to the 4 of them: drawn again once, after it.
            (cl-letf (((symbol-function 'agent-workspace--set-session-mode) #'ignore))
              (let ((times nil))
                (dotimes (_ 3)
                  (setq redraws 0)
                  (let ((start (float-time)))
                    (agent-workspace-inbox-add project "#all" "build 42 broke" :from "ci" :limits nil)
                    (push (- (float-time) start) times))
                  (should (= redraws 0))
                  (agent-workspace--room-buffer project)
                  (should (= redraws 1)))
                (should (< (apply #'min times) 0.1))))
            (with-current-buffer buffer
              (should (string-search "✉ → liz build 42 broke" (buffer-string)))))
        (advice-remove 'agent-workspace--room-redraw count))
      (should (eq (buffer-local-value 'buffer-undo-list buffer) t))
      (should (eq (buffer-local-value 'buffer-undo-list (agent-workspace--issues-buffer project)) t)))))

(ert-deftest agent-workspace-room/several-lines-on-one ()
  "An event or a message of several lines shows its first lines on one,
cut as a reply's, never a line at column 0; kept whole (doom-pbk.52)."
  (+test-awr2 "lines"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-room-post project :kind 'event :agent "ci" :to "ada"
                               :text "Build 42 failed:\nerror: test_lexer failed\nerror: test_parser failed\n  at line 12")
    (agent-workspace-room-post project :kind 'you :to "ada" :text "First line\nsecond\nthird")
    (let ((lines (split-string (+test-awr2--feed project) "\n" t)))
      (should (seq-find (lambda (line) (string-search "✉ → ada Build 42 failed: error: test_lexer failed error: test_parser failed" line))
                        lines))
      (should (seq-find (lambda (line) (string-search "→ ada First line second third" line)) lines))
      (should-not (seq-find (lambda (line) (string-prefix-p "error:" line)) lines))
      (should-not (seq-find (lambda (line) (string-prefix-p "  at line 12" line)) lines)))
    ;; Kept whole.
    (should (string-search "\\n  at line 12" (with-temp-buffer
                                                (insert-file-contents (expand-file-name ".agent-shell/agent-workspace/room.jsonl" project))
                                                (buffer-string))))))

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

;; ====== WHERE IT STAYS ======

(defun +test-awr2--notes (project from to)
  "Notes FROM to TO posted in PROJECT's room: \"note 01\"..."
  (cl-loop for i from from to to
           do (agent-workspace-room-post project :kind 'note :text (format "note %02d" i))))

(defun +test-awr2--window (project)
  "PROJECT's feed's window."
  (get-buffer-window (agent-workspace--room-buffer project)))

(defun +test-awr2--put (window what text &optional offset)
  "WINDOW's WHAT (`start' or `point') at TEXT's line in it (OFFSET in it),
or at TEXT itself (OFFSET `at')."
  (with-current-buffer (window-buffer window)
    (save-excursion
      (goto-char (point-min))
      (should (search-forward text nil t))
      (let ((at (if (eq offset 'at) (match-beginning 0) (+ (line-beginning-position) (or offset 0)))))
        (if (eq what 'start) (set-window-start window at) (set-window-point window at))))))

(defun +test-awr2--line (window what)
  "The line at WINDOW's WHAT (`start' or `point'), and how far in it is:
\(TEXT . COLUMN)."
  (with-current-buffer (window-buffer window)
    (save-excursion
      (goto-char (if (eq what 'start) (window-start window) (window-point window)))
      (cons (buffer-substring-no-properties (line-beginning-position) (line-end-position))
            (- (point) (line-beginning-position))))))

(defun +test-awr2--at-end-p (window)
  "Non-nil if WINDOW's point is at its buffer's end."
  (= (window-point window) (with-current-buffer (window-buffer window) (point-max))))

(ert-deftest agent-workspace-room/follows-from-its-last-line ()
  "Its cursor on the last line (at its end or not): a new line keeps it at
the end; moved off it, it stays; back on the last line, it follows again."
  (+test-awr2 "follow"
    (agent-workspace-create :role "builder" :name "ada")
    (+test-awr2--notes project 1 60)
    (let ((window (+test-awr2--window project)))
      (should (+test-awr2--at-end-p window))
      (should (> (window-start window) 1))
      ;; On the last line, at its start: it follows.
      (+test-awr2--put window 'point "note 60")
      (+test-awr2--notes project 61 61)
      (should (+test-awr2--at-end-p window))
      ;; Off it: it stays.
      (+test-awr2--put window 'point "note 30" 4)
      (+test-awr2--notes project 62 62)
      (should (= (cdr (+test-awr2--line window 'point)) 4))
      (should (string-search "note 30" (car (+test-awr2--line window 'point))))
      ;; Back on the last line: it follows again.
      (+test-awr2--put window 'point "note 62" 3)
      (+test-awr2--notes project 63 63)
      (should (+test-awr2--at-end-p window))
      (should (string-suffix-p "note 63\n" (+test-awr2--feed project))))))

(ert-deftest agent-workspace-room/stays-where-it-is ()
  "Its cursor on an earlier line (a line clicked, scrolled up): a new line
leaves its window where it was, its start and its cursor on the same lines,
never at the top; the same with the oldest entries dropped (their positions
shifted), its window selected or not; its start's entry dropped, the
nearest one after it."
  (+test-awr2 "stay"
    (agent-workspace-create :role "builder" :name "ada")
    (+test-awr2--notes project 1 60)
    (let* ((window (+test-awr2--window project))
           (buffer (window-buffer window))
           (kept (lambda () (length (buffer-local-value 'agent-workspace--room-entries buffer)))))
      (+test-awr2--put window 'start "note 20")
      (+test-awr2--put window 'point "note 25" 15)
      (+test-awr2--notes project 61 61)
      (should (string-search "note 20" (car (+test-awr2--line window 'start))))
      (should (= (cdr (+test-awr2--line window 'start)) 0))
      (should (string-search "note 25" (car (+test-awr2--line window 'point))))
      (should (= (cdr (+test-awr2--line window 'point)) 15))
      ;; The oldest dropped: positions shift, it stays on its lines.
      (let ((agent-workspace-room-kept (funcall kept))
            (start (window-start window)))
        (+test-awr2--notes project 62 63)
        (should (< (window-start window) start))
        (should (string-search "note 20" (car (+test-awr2--line window 'start))))
        (should (string-search "note 25" (car (+test-awr2--line window 'point))))
        (should (= (cdr (+test-awr2--line window 'point)) 15)))
      ;; Its window selected (the cursor in the feed): the same.
      (with-selected-window window
        (+test-awr2--notes project 64 64)
        (should (string-search "note 25" (car (+test-awr2--line window 'point))))
        (should (string-search "note 25" (buffer-substring (line-beginning-position) (line-end-position)))))
      (should (string-search "note 20" (car (+test-awr2--line window 'start))))
      (should (string-search "note 25" (car (+test-awr2--line window 'point))))
      ;; Its start's entry dropped (the oldest): the nearest one after it.
      (set-window-start window 1)
      (let ((first (car (+test-awr2--line window 'start)))
            (agent-workspace-room-kept (funcall kept)))
        (+test-awr2--notes project 65 65)
        (should (= (window-start window) 1))
        (should-not (equal (car (+test-awr2--line window 'start)) first))
        (should (string-search "note 25" (car (+test-awr2--line window 'point))))))))

(ert-deftest agent-workspace-room/each-window-on-its-own ()
  "Two windows on the feed: the one at the end follows, the other stays."
  (+test-awr2 "windows"
    (agent-workspace-create :role "builder" :name "ada")
    (+test-awr2--notes project 1 60)
    (let* ((window (+test-awr2--window project))
           (other (split-window window nil 'below)))
      (unwind-protect
          (progn
            (set-window-point window (with-current-buffer (window-buffer window) (point-max)))
            (+test-awr2--put other 'start "note 10")
            (+test-awr2--put other 'point "note 12")
            (+test-awr2--notes project 61 61)
            (should (+test-awr2--at-end-p window))
            (should (string-search "note 10" (car (+test-awr2--line other 'start))))
            (should (string-search "note 12" (car (+test-awr2--line other 'point)))))
        (delete-window other)))))

(ert-deftest agent-workspace-room/stays-on-a-hand-s-buttons ()
  "Its cursor on a hand's button: a new line leaves it there; the hand
answered, its buttons gone, the cursor on the hand's line, not at the top."
  (+test-awr2 "buttons"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (cl-letf (((symbol-function 'agent-workspace-hand-options)
                 (lambda (agent) (and (eq (agent-workspace-agent-state agent) 'hand)
                                      '(("Yes" . ignore) ("No" . ignore))))))
        (+test-awr2--notes project 1 20)
        (agent-workspace--raise-hand ada '(:kind question :title "restore or rebuild?"))
        (+test-awr2--notes project 21 60)
        (let ((window (+test-awr2--window project)))
          (+test-awr2--put window 'start "note 10")
          (+test-awr2--put window 'point "[No]" 'at)
          (+test-awr2--notes project 61 61)
          (should (string-search "note 10" (car (+test-awr2--line window 'start))))
          (with-current-buffer (window-buffer window)
            (should (equal (buffer-substring-no-properties (window-point window) (+ (window-point window) 4))
                           "[No]")))
          ;; Answered elsewhere: its buttons go.
          (agent-workspace--set-state ada 'desk)
          (should-not (string-search "[No]" (+test-awr2--feed project)))
          (should (string-search "note 10" (car (+test-awr2--line window 'start))))
          (should (string-search "restore or rebuild?" (car (+test-awr2--line window 'point)))))))))

(ert-deftest agent-workspace-room/stays-when-a-thread-folds ()
  "A thread folded, then unfolded: the window stays on its lines; its
start on a line folded away, on the nearest one after it."
  (+test-awr2 "fold"
    (agent-workspace-create :role "builder" :name "ada")
    (+test-awr2--notes project 1 10)
    (dotimes (i 10)
      (agent-workspace-room-post project :kind 'note :thread "t1" :text (format "thread %02d" i)))
    (+test-awr2--notes project 11 60)
    (let* ((window (+test-awr2--window project))
           (buffer (window-buffer window)))
      (+test-awr2--put window 'start "thread 05")
      (+test-awr2--put window 'point "note 30" 12)
      (with-current-buffer buffer
        (setq agent-workspace--room-folded '("t1"))
        (agent-workspace--room-redraw project))
      (should (string-search "9 more" (+test-awr2--feed project)))
      (should (string-search "note 11" (car (+test-awr2--line window 'start))))
      (should (= (cdr (+test-awr2--line window 'point)) 12))
      (should (string-search "note 30" (car (+test-awr2--line window 'point))))
      (+test-awr2--put window 'start "note 05")
      (with-current-buffer buffer
        (setq agent-workspace--room-folded nil)
        (agent-workspace--room-redraw project))
      (should (string-search "note 05" (car (+test-awr2--line window 'start))))
      (should (string-search "note 30" (car (+test-awr2--line window 'point)))))))

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

(ert-deftest agent-workspace-room/all-with-nobody-awake ()
  "#all with no agent awake: refused, saying nobody is awake, not your
message as the error (doom-pbk.53)."
  (+test-awr2 "all-asleep"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (agent-workspace-sleep ada)
      (should (equal (agent-workspace--recipients project "#all please rebase on main")
                     '(nil . "Nobody awake to send it to")))
      (with-current-buffer (agent-workspace--compose-buffer project)
        (insert "#all please rebase on main")
        (should (equal (cadr (should-error (agent-workspace-compose-send) :type 'user-error))
                       "Nobody awake to send it to")))
      (should-not sent))))

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
  "# at the start of a message: the agents (their role and state), their
roles, all, whatever follows it (none or more); a # further on is text."
  (+test-awr2 "completion"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "investigator" :name "sam")
    (with-current-buffer (agent-workspace--compose-buffer project)
      (insert "#")
      (pcase-let ((`(,start ,end ,candidates . ,props) (agent-workspace--compose-capf)))
        (should (= start end (point-max)))
        (should (equal candidates '("ada" "sam" "builders" "investigators" "all")))
        (should (equal (funcall (plist-get props :annotation-function) "ada") "  builder · at the desk"))
        ;; Corfu shows it whatever's typed after the #.
        (should (eq (plist-get props :company-prefix-length) t)))
      (insert "ad")
      (should (equal (seq-take (agent-workspace--compose-capf) 2) (list 2 4)))
      ;; Its start as `agent-workspace--recipients' reads it: blanks before it.
      (erase-buffer)
      (insert " \n#")
      (should (agent-workspace--compose-capf))
      ;; Further on, a # is text.
      (dolist (text '("fix the #" "fix the #ad" "#ada look at #" "#ada look at #sa" "no hash"))
        (erase-buffer)
        (insert text)
        (should-not (agent-workspace--compose-capf))))))

(ert-deftest agent-workspace-room/completion-takes-one ()
  "Without Corfu, TAB completes the # (as now): taking a name or a role adds
its space (or goes past the one there), \"#ada \" selecting ada."
  (+test-awr2 "completion-takes"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "investigator" :name "sam")
    (with-current-buffer (agent-workspace--compose-buffer project)
      (should-not (bound-and-true-p corfu-mode))
      (insert "#ad")
      (completion-at-point)
      (agent-workspace--compose-typed)
      (should (equal (buffer-string) "#ada "))
      (should (= (point) (point-max)))
      (should (equal (agent-workspace-agent-name (agent-workspace--app-selected (agent-workspace--app project))) "ada"))
      ;; Its space there already: the cursor after it.
      (erase-buffer)
      (insert "#sa fix it")
      (goto-char 4)
      (completion-at-point)
      (should (equal (buffer-string) "#sam fix it"))
      (should (= (point) 6))
      (erase-buffer)
      (insert "#bu")
      (completion-at-point)
      (should (equal (buffer-string) "#builders ")))))

(ert-deftest agent-workspace-room/completion-at-once-with-corfu ()
  "With Corfu, # typed at the start of the compose line opens its list at
once (its trigger, a short delay: there only; Corfu's settings elsewhere
stay); what follows narrows it; a # further on opens nothing."
  (require 'corfu)
  (+test-awr2 "completion-corfu"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "investigator" :name "sam")
    (let ((shown 'none))
      (cl-letf (((symbol-function 'corfu--popup-support-p) #'always)
                ((symbol-function 'corfu--setup)
                 (lambda (beg end table pred)
                   (setq shown (all-completions (buffer-substring beg end) table pred))))
                ((symbol-function 'corfu--exhibit) #'ignore))
        (with-current-buffer (agent-workspace--compose-buffer project)
          ;; Corfu turned on there (its auto completion loaded as it does).
          (let ((corfu-auto t)) (corfu-mode 1))
          (should (local-variable-p 'corfu-auto-trigger))
          (should (equal corfu-auto-trigger "#"))
          (should (equal corfu-auto-delay 0.05))
          ;; # typed: the list straight away, no prefix, no timer.
          (insert "#")
          (let ((this-command 'self-insert-command) (last-command-event ?#))
            (corfu-auto--post-command))
          (should (equal shown '("ada" "sam" "builders" "investigators" "all")))
          ;; A letter after it (the list closed): narrowed, a single letter.
          (setq shown 'none)
          (insert "a")
          (let ((last-command-event ?a)) (corfu-auto--complete-deferred))
          (should (equal shown '("ada" "all")))
          ;; A # further on: nothing.
          (erase-buffer)
          (insert "fix the #")
          (setq shown 'none)
          (let ((this-command 'self-insert-command) (last-command-event ?#))
            (corfu-auto--post-command))
          (should (eq shown 'none)))
        ;; Elsewhere, Corfu's own settings.
        (should (equal (default-value 'corfu-auto-trigger) ""))
        (should (equal (default-value 'corfu-auto-delay) (eval (car (get 'corfu-auto-delay 'standard-value)))))
        (with-temp-buffer
          (text-mode)
          (let ((corfu-auto t)) (corfu-mode 1))
          (should-not (local-variable-p 'corfu-auto-trigger))
          (should-not (local-variable-p 'corfu-auto-delay)))))))

;; ====== THE COMPOSE LINE'S HEIGHT ======

(defun +test-awr2--typed (project text)
  "TEXT typed at the end of PROJECT's compose line, its post-command-hook
after it: its window's body height then."
  (let ((window (+test-awr2--compose-window project)))
    (with-selected-window window
      (goto-char (point-max))
      (insert text)
      (agent-workspace--compose-typed))
    (window-body-height window)))

(ert-deftest agent-workspace-room/compose-grows ()
  "The compose line grows as its text needs, as shown (a long line wrapped,
newlines), its rows the feed's; up to 5 lines; shrinking back as text goes,
never under 1 (doom-pbk.114)."
  (+test-awr2 "grows"
    (agent-workspace-create :role "builder" :name "ada")
    (let* ((window (+test-awr2--compose-window project))
           (feed (+test-awr2--window project))
           (room (+ (window-total-height feed) (window-total-height window)))
           (shown (lambda () (with-selected-window window
                               (count-screen-lines (point-min) (point-max) t window)))))
      (should (= (+test-awr2--typed project "fix the test") 1))
      ;; A line wrapping past 1 line: all of it shown.
      (let ((height (+test-awr2--typed project (concat " " (string-join (make-list 20 "word") " ")))))
        (should (> height 1))
        (should (<= height 3))
        (should (= height (funcall shown)))
        ;; Newlines.
        (should (= (+test-awr2--typed project "\n\nmore") (+ height 2))))
      (should (= (+ (window-total-height feed) (window-total-height window)) room))
      ;; At most 5.
      (should (= (+test-awr2--typed project (apply #'concat (make-list 12 "\nline"))) 5))
      (should (> (funcall shown) 5))
      (should (= (+ (window-total-height feed) (window-total-height window)) room))
      ;; Text deleted: shrinking back, never under 1.
      (with-selected-window window
        (erase-buffer)
        (insert "one\ntwo\nthree\nfour\nfive")
        (agent-workspace--compose-typed)
        (should (= (window-body-height window) 5))
        (should (= (window-start window) (point-min)))
        (delete-region (save-excursion (goto-char (point-min)) (line-end-position 2)) (point-max))
        (should (equal (buffer-string) "one\ntwo"))
        (agent-workspace--compose-typed)
        (should (= (window-body-height window) 2))
        (erase-buffer)
        (agent-workspace--compose-typed)
        (should (= (window-body-height window) 1)))
      (should (= (+ (window-total-height feed) (window-total-height window)) room)))))

(ert-deftest agent-workspace-room/compose-lines-1-to-5 ()
  "The compose line's lines: 1 for an empty text, as many as its text's up
to 5 (doom-pbk.114)."
  (should (= agent-workspace-compose-lines 1))
  (should (= agent-workspace-compose-max-lines 5))
  (+test-awr2 "one-to-five"
    (agent-workspace-create :role "builder" :name "ada")
    (let ((window (+test-awr2--compose-window project)))
      (pcase-dolist (`(,text . ,lines) '((0 . 1) (1 . 1) (3 . 3) (5 . 5) (8 . 5)))
        (cl-letf (((symbol-function 'agent-workspace--compose-text-lines) (lambda (_) text)))
          (should (= (agent-workspace--compose-lines window) lines)))))))

(ert-deftest agent-workspace-room/compose-back-to-1 ()
  "A message sent, the compose line is a line again; M-p / M-n bring one
back, the line sized to it."
  (+test-awr2 "back-to-1"
    (agent-workspace-create :role "builder" :name "ada")
    (should (= (+test-awr2--typed project "#ada one\ntwo\nthree\nfour\nfive") 5))
    (with-selected-window (+test-awr2--compose-window project)
      (agent-workspace-compose-send)
      (agent-workspace--compose-typed)
      (should (equal (buffer-string) ""))
      (should (= (window-body-height) 1))
      (agent-workspace-compose-previous)
      (agent-workspace--compose-typed)
      (should (= (window-body-height) 5))
      (agent-workspace-compose-next)
      (agent-workspace--compose-typed)
      (should (= (window-body-height) 1)))))

(ert-deftest agent-workspace-room/compose-grows-as-the-app-s-own ()
  "The compose line growing is the app's own change, not a border dragged:
not laid out again nor counted; a layout keeps its height; a feed following
its end still shows its last line. Its width changed, fitted again (not
while the app's to be laid out again). At the bottom, half the room at
most."
  (+test-awr2 "own"
    (agent-workspace-create :role "builder" :name "ada")
    (+test-awr2--notes project 1 60)
    (let ((app (agent-workspace--app project))
          (feed (+test-awr2--window project)))
      (should (+test-awr2--at-end-p feed))
      (should (= (+test-awr2--typed project "1\n2\n3\n4") 4))
      ;; The feed's last line still in view.
      (with-current-buffer (window-buffer feed)
        (should (<= (count-screen-lines (window-start feed) (point-max) nil feed)
                    (window-body-height feed))))
      ;; Not a border dragged.
      (should (equal (agent-workspace--app-sizes app) (agent-workspace--sizes-now (selected-frame))))
      (agent-workspace--resized-h (selected-frame))
      (should-not (agent-workspace--app-resizes app))
      ;; Laid out again: its height kept.
      (agent-workspace-layout app)
      (should (= (window-body-height (+test-awr2--compose-window project)) 4))
      ;; Narrower, a long line wraps on more lines: fitted, once the app has
      ;; its sizes (3 layouts in 3 seconds); before, it's the layout's.
      (with-selected-window (+test-awr2--compose-window project)
        (erase-buffer)
        (insert (string-join (make-list 40 "word") " "))
        (agent-workspace--compose-typed)
        (should (= (window-body-height) 3)))
      (window-resize (+test-awr2--window project) -20 t)
      (agent-workspace--compose-resized-h (selected-frame))
      (should (= (window-body-height (+test-awr2--compose-window project)) 3))
      (setf (agent-workspace--app-sizes app) (agent-workspace--sizes-now (selected-frame)))
      (agent-workspace--compose-resized-h (selected-frame))
      (should (> (window-body-height (+test-awr2--compose-window project)) 3))
      ;; At the bottom (16 rows): half of it at most.
      (set-frame-size (selected-frame) 160 40)
      (agent-workspace-layout app)
      (should (= (+test-awr2--typed project (apply #'concat (make-list 12 "\nline"))) 5))
      (should (equal (mapcar #'cdr (+test-awr2--room-windows)) '((110 10) (110 6)))))))

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

;; ====== WHAT YOU SEND IN A SESSION ======

(defmacro +test-awr2--real (name &rest body)
  "BODY with `ada', a stand-in agent of a new project NAME (`project'), at
the desk, its crew's app open (`app'); closed after."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awr2--project ,name))
            (default-directory project))
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore))
         (unwind-protect
             (let ((ada (agent-workspace-create :role "builder" :name "ada" :kind 'mock)))
               (+test-awr2--until (lambda () (eq (agent-workspace-agent-state ada) 'desk)))
               (let ((app (agent-workspace-open t)))
                 (ignore app)
                 ,@body))
           (when (agent-workspace--app project) (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awr2--until (predicate &optional seconds)
  "Wait until PREDICATE is non-nil, SECONDS at most (20): its value."
  (let ((end (+ (float-time) (or seconds 20)))
        value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defun +test-awr2--yours (project)
  "PROJECT's room's entries of yours: (TO TEXT) each, in order."
  (with-current-buffer (agent-workspace--room-buffer project)
    (mapcar (lambda (entry) (list (plist-get entry :to) (plist-get entry :text)))
            (seq-filter (lambda (entry) (eq (plist-get entry :kind) 'you)) agent-workspace--room-entries))))

(defun +test-awr2--type (agent text)
  "TEXT typed in AGENT's session, and RET."
  (with-current-buffer (agent-workspace-agent-buffer agent)
    (goto-char (point-max))
    (insert text)
    (call-interactively #'agent-shell-submit)))

(defun +test-awr2--answered (project text)
  "Non-nil once PROJECT's feed has the stand-in's answer TEXT (\"↳ TEXT\")."
  (+test-awr2--until (lambda () (string-search (concat "↳ " text) (+test-awr2--feed project)))))

(ert-deftest agent-workspace-room/what-you-type-in-a-session ()
  "A message typed in an agent's session: in the feed as yours (you → ada,
its first lines), before its answer; RET on it opens its pane; shown with
its agent's filter, not another's; kept, read back once the app opens
again."
  (+test-awr2--real "typed"
    (+test-awr2--type ada "typed here\n\nand a second line")
    (should (+test-awr2--answered project "ok: typed here"))
    (should (equal (+test-awr2--yours project) '(("ada" "typed here and a second line"))))
    (let ((feed (+test-awr2--feed project)))
      (should (string-match-p " you +→ ada typed here and a second line\n" feed))
      (should (< (string-search "→ ada typed here" feed) (string-search "↳ ok: typed here" feed))))
    ;; RET on it: its pane, open.
    (agent-workspace-toggle)
    (should-not (agent-workspace--app-open app))
    (select-window (get-buffer-window (agent-workspace--room-buffer project)))
    (goto-char (point-min))
    (search-forward "→ ada typed here")
    (agent-workspace-room-open)
    (should (eq (agent-workspace--app-open app) ada))
    (should (eq (window-buffer (selected-window)) (agent-workspace-agent-buffer ada)))
    ;; Its agent's filter shows it, another's doesn't.
    (with-current-buffer (agent-workspace--room-buffer project)
      (setq agent-workspace--room-filter "ada")
      (agent-workspace--room-redraw project)
      (should (string-search "→ ada typed here" (+test-awr2--feed project)))
      (setq agent-workspace--room-filter "ken")
      (agent-workspace--room-redraw project)
      (should-not (string-search "typed here" (+test-awr2--feed project)))
      (setq agent-workspace--room-filter nil))
    ;; Kept: there again once the app opens again.
    (with-current-buffer (agent-workspace--issues-buffer project) (agent-workspace-quit))
    (agent-workspace-open t)
    (should (string-search "→ ada typed here and a second line" (+test-awr2--feed project)))))

(require 'agent-shell-prompt-queue)

(ert-deftest agent-workspace-room/what-the-app-sends-isn-t-yours ()
  "A message sent from the compose line: in the feed once, not again as
it's submitted, nor when it was queued (said so) and sent after the turn.
A prompt the app sends (an issue given, a loop's next one, an event, a hand
answered from the room: `agent-workspace-send'): not said as yours. One you
type while the agent works: said as it's sent, after its turn."
  (+test-awr2--real "app"
    (with-current-buffer (agent-workspace--compose-buffer project)
      (insert "#ada hello there")
      (agent-workspace-compose-send))
    (should (+test-awr2--answered project "ok: hello there"))
    (should (equal (+test-awr2--yours project) '(("ada" "hello there"))))
    ;; The app's: not yours.
    (agent-workspace-send ada "the app's own" :submit t)
    (should (+test-awr2--answered project "ok: the app's own"))
    (should (equal (+test-awr2--yours project) '(("ada" "hello there"))))
    ;; Queued: from the compose line, said once; typed, said once sent.
    ;; As agent-shell has it: what's queued during a turn sent as one.
    (should agent-shell-prompt-queue-merge)
    (agent-workspace-send ada "slow" :submit t)
    (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state ada) 'working))))
    (with-current-buffer (agent-workspace--compose-buffer project)
      (insert "#ada after that")
      (agent-workspace-compose-send))
    (should (string-search "→ ada after that  (queued for ada: busy)" (+test-awr2--feed project)))
    (+test-awr2--type ada "typed meanwhile")
    (should (equal (mapcar #'cadr (+test-awr2--yours project)) '("hello there" "after that  (queued for ada: busy)")))
    ;; Both sent as one after its turn: what you typed said, not the
    ;; compose line's again.
    (should (+test-awr2--answered project "ok: after that typed meanwhile"))
    (should (equal (mapcar #'cadr (+test-awr2--yours project))
                   '("hello there" "after that  (queued for ada: busy)" "typed meanwhile")))
    (let ((feed (+test-awr2--feed project)))
      (should (< (string-search "↳ slowly" feed) (string-search "→ ada typed meanwhile" feed)
                 (string-search "↳ ok: after that typed meanwhile" feed))))
    (with-current-buffer (agent-workspace-agent-buffer ada)
      (should-not agent-workspace--sent))))

(defun +test-awr2--held (agent &rest queued)
  "AGENT working on a prompt it holds, the app's QUEUED prompts waiting for
its turn's end; then interrupted, agent-shell's question whether to go on
with them answered no: AGENT at the desk."
  (agent-workspace-send agent "hold" :submit t)
  (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state agent) 'working))))
  (dolist (text queued)
    (should (eq (agent-workspace-send agent text :submit t) 'queued)))
  (cl-letf (((symbol-function 'y-or-n-p) #'ignore))
    (agent-workspace-interrupt agent)
    (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state agent) 'desk))))))

(defun +test-awr2--queue (agent)
  "AGENT's queue (agent-shell's): the prompts waiting for its turn's end."
  (with-current-buffer (agent-workspace-agent-buffer agent)
    (map-elt agent-shell--state :pending-prompts)))

(defun +test-awr2--marks (agent)
  "The marks of the prompts the app sent AGENT, not submitted yet."
  (buffer-local-value 'agent-workspace--sent (agent-workspace-agent-buffer agent)))

(defun +test-awr2--times (text part)
  "How many times PART is in TEXT."
  (let ((count 0) (start 0))
    (while (setq start (string-search part text start))
      (setq count (1+ count) start (1+ start)))
    count))

(ert-deftest agent-workspace-room/a-queue-removed ()
  "The app's prompts queued, the turn interrupted (go on? no: they stay
queued), then removed (agent-shell's M-x agent-shell-prompt-queue-remove:
one, then all): never sent, their marks go with them; a message you type
after with the same text shows in the room."
  (+test-awr2--real "removed"
    (+test-awr2--held ada "the app's next" "and another")
    (should (equal (+test-awr2--queue ada) '("the app's next" "and another")))
    (should (equal (+test-awr2--marks ada) '("and another" "the app's next")))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (with-current-buffer (agent-workspace-agent-buffer ada)
        (agent-shell-prompt-queue-remove 0))
      (should (equal (+test-awr2--queue ada) '("and another")))
      (should (equal (+test-awr2--marks ada) '("and another")))
      (with-current-buffer (agent-workspace-agent-buffer ada)
        (agent-shell-prompt-queue-remove)))
    (should-not (+test-awr2--queue ada))
    (should-not (+test-awr2--marks ada))
    (+test-awr2--type ada "the app's next")
    (should (+test-awr2--answered project "ok: the app's next"))
    (should (equal (+test-awr2--yours project) '(("ada" "the app's next"))))))

(ert-deftest agent-workspace-room/a-queue-kept-after-an-interrupt ()
  "The app's prompt queued, the turn interrupted (go on? no): it stays
queued for a turn after, its mark with it. A message you type meanwhile
with the same text shows in the room, before its answer; the app's, sent
after that turn, doesn't."
  (+test-awr2--real "kept"
    (+test-awr2--held ada "again please")
    (should (equal (+test-awr2--queue ada) '("again please")))
    (should (equal (+test-awr2--marks ada) '("again please")))
    (+test-awr2--type ada "again please")
    (should (+test-awr2--answered project "ok: again please"))
    (should (equal (+test-awr2--yours project) '(("ada" "again please"))))
    (let ((feed (+test-awr2--feed project)))
      (should (< (string-search "→ ada again please" feed) (string-search "↳ ok: again please" feed))))
    ;; The app's, sent after that turn: answered too, not said as yours.
    (should (+test-awr2--until (lambda () (= (+test-awr2--times (+test-awr2--feed project) "↳ ok: again please") 2))))
    (should (equal (+test-awr2--yours project) '(("ada" "again please"))))
    (should-not (+test-awr2--queue ada))
    (should-not (+test-awr2--marks ada))))

;; Steered instead (agent-shell's reroute): the stand-in steers, as agents
;; saying they can do (its answer: examples/agent-workspace/stand-in.el).
;; agent-shell pinned to a commit that has it (packages.el); one without it
;; (another build): skipped, said.
(defun +test-awr2--steering ()
  "Skip the test, saying why, unless agent-shell steers a queued prompt."
  (unless (fboundp 'agent-shell-busy-submit-reroute-queue-to-steer)
    (ert-skip "agent-shell has no steering (agent-shell-busy-submit-reroute-queue-to-steer): not the pinned one")))

(defun +test-awr2--steer (agent answer)
  "agent-shell's override at an empty prompt in AGENT's session, while it
works: its last queued prompt offered as a steer instead, ANSWER (non-nil:
yes) given; AGENT saying it can steer."
  (with-current-buffer (agent-workspace-agent-buffer agent)
    (map-put! agent-shell--state :supports-steering t)
    (goto-char (point-max))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) answer)))
      (call-interactively #'agent-shell-submit-override))))

(ert-deftest agent-workspace-room/a-steer-declined ()
  "The app's prompt queued, then steered into the turn instead (agent-shell's
reroute) and declined: dropped, the turn interrupted; its mark goes with it,
and the same text typed after shows in the room."
  (+test-awr2--steering)
  (+test-awr2--real "declined"
    (agent-workspace-send ada "hold" :submit t)
    (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state ada) 'working))))
    (should (eq (agent-workspace-send ada "the app's next, decline it" :submit t) 'queued))
    (+test-awr2--steer ada t)
    (should-not (+test-awr2--queue ada))
    (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state ada) 'desk))))
    (should (string-search "Steered prompt declined"
                           (with-current-buffer (agent-workspace-agent-buffer ada) (buffer-string))))
    (should-not (+test-awr2--marks ada))
    (+test-awr2--type ada "the app's next, decline it")
    (should (+test-awr2--answered project "ok: the app's next, decline it"))
    (should (equal (+test-awr2--yours project) '(("ada" "the app's next, decline it"))))))

(ert-deftest agent-workspace-room/a-steer-injected ()
  "The app's prompt queued, offered as a steer instead: no, it stays queued,
its mark with it; yes, injected into the turn: said submitted, not yours
(not in the room), its mark taken. The same text typed after shows."
  (+test-awr2--steering)
  (+test-awr2--real "injected"
    (agent-workspace-send ada "hold" :submit t)
    (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state ada) 'working))))
    (should (eq (agent-workspace-send ada "the app's next, steered" :submit t) 'queued))
    (should-error (+test-awr2--steer ada nil) :type 'user-error)
    (should (equal (+test-awr2--queue ada) '("the app's next, steered")))
    (should (equal (+test-awr2--marks ada) '("the app's next, steered")))
    (+test-awr2--steer ada t)
    (should (+test-awr2--until (lambda () (string-search "[steer] the app's next, steered"
                                                         (with-current-buffer (agent-workspace-agent-buffer ada)
                                                           (buffer-string))))))
    (should-not (+test-awr2--marks ada))
    (should-not (+test-awr2--yours project))
    (agent-workspace-interrupt ada)
    (should (+test-awr2--until (lambda () (eq (agent-workspace-agent-state ada) 'desk))))
    (+test-awr2--type ada "the app's next, steered")
    (should (+test-awr2--answered project "ok: the app's next, steered"))
    (should (equal (+test-awr2--yours project) '(("ada" "the app's next, steered"))))))

(ert-deftest agent-workspace-room/an-answer-on-a-canvas ()
  "An answer you give on an agent's canvas (Agent UI's Answer): yours, its
first line."
  (+test-awr2--real "answer"
    (let* ((session (agent-workspace-agent-buffer ada))
           (canvas (agent-ui-canvas (agent-ui--session-name session))))
      (with-current-buffer canvas
        (setq agent-ui--session-buffer session)
        (funcall agent-ui-action-function "Answer to choice c1 (Which one?): A. Note: first\nsecond" t))
      (should (+test-awr2--answered project "ok: Answer to choice c1"))
      (should (equal (+test-awr2--yours project) '(("ada" "Answer to choice c1 (Which one?): A. Note: first")))))))
