;;; tests/unit/test-agent-workspace-minimap.el -*- lexical-binding: t; -*-
;; config/agent-workspace/minimap.el: the crew's minimap under the issue list.
;; Its lanes from what the agents did (activity.el's, stood in for), drawn
;; again as they do things (a burst: once), not while it's hidden; m hides it,
;; crew.json keeps that; RET, o, d on a lane and on a conflict. Agents' sessions
;; plain buffers (no agent runs); bd not run. A terminal's glyphs (batch).

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-ui" "config/tiling" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

;; ====== HELPERS ======

(defun +test-awm--git (&rest args)
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awm--project (name)
  "A git repository NAME in the temp folder, with a commit (README,
src/a.el): its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awm/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory (expand-file-name "src" dir) t)
    (let ((default-directory dir))
      (+test-awm--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (write-region "(a)\n(b)\n(c)\n(d)\n" nil "src/a.el")
      (+test-awm--git "add" ".")
      (+test-awm--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awm (name &rest body)
  "BODY in a new project NAME (`project'), a frame 220x40, no app or crew
before or after; agents' sessions plain buffers, at the desk; bd not run;
the minimap shown (as by default)."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awm--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
            (agent-workspace--minimap-shown (make-hash-table :test #'equal))
            (agent-workspace-minimap t))
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer
                            (agent-workspace-agent-state agent) 'desk)
                      (agent-workspace--changed agent 'session)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil
                          (agent-workspace-agent-state agent) state)
                    nil))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil))))
         (unwind-protect (progn ,@body)
           (when (agent-workspace--app project) (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awm--windows ()
  "The frame's windows: (BUFFER-NAME WIDTH HEIGHT), from its first."
  (mapcar (lambda (window) (list (buffer-name (window-buffer window))
                                 (window-total-width window) (window-total-height window)))
          (window-list nil 'nomini (frame-first-window))))

(defun +test-awm--text (project)
  "PROJECT's minimap as drawn, without properties."
  (with-current-buffer (agent-workspace--minimap-buffer project)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-awm--tool (agent kind &optional file line)
  "AGENT's tool call of KIND (ACP's), at FILE (in its worktree) and LINE."
  (agent-workspace--activity-event
   agent `((:event . tool-call-update)
           (:data . ((:tool-call . ((:kind . ,kind)
                                    (:locations . ,(and file (vector `((path . ,(expand-file-name
                                                                                 file (agent-workspace-agent-worktree agent)))
                                                                       (line . ,line))))))))))))

(defun +test-awm--goto (project text)
  "Point (and the minimap's window's) at the line with TEXT in PROJECT's
minimap; its buffer current."
  (set-buffer (agent-workspace--minimap-buffer project))
  (goto-char (point-min))
  (should (search-forward text nil t))
  (beginning-of-line)
  (when-let* ((window (get-buffer-window (current-buffer))))
    (set-window-point window (point))))

;; ====== TESTS ======

(ert-deftest agent-workspace-minimap/under-the-issues ()
  "Under the issue list, 12 lines; m hides it (the issues the whole column)
and shows it again; crew.json keeps it hidden, and a crew started again from it
opens without it."
  (+test-awm "under"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-open t)
    (let ((windows (+test-awm--windows)))
      (should (equal (nth 0 windows) '("*issues · under*" 50 27)))
      (should (equal (nth 1 windows) '("*minimap · under*" 50 12))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    (should (equal (nth 0 (+test-awm--windows)) '("*issues · under*" 50 39)))
    (should-not (get-buffer-window (agent-workspace--minimap-buffer project)))
    (agent-workspace-crew-save project)
    (should (string-search "\"minimap\": false" (with-temp-buffer
                                              (insert-file-contents (agent-workspace--crew-path project))
                                              (buffer-string))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    (should (equal (nth 1 (+test-awm--windows)) '("*minimap · under*" 50 12)))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    ;; Closed, then started again from crew.json: hidden as it was.
    (agent-workspace-crew-save project)
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (clrhash agent-workspace--minimap-shown)
    (agent-workspace-open t)
    (should (agent-workspace-agent "ada" project))
    (should-not (seq-find (lambda (window) (string-prefix-p "*minimap" (car window))) (+test-awm--windows)))))

(ert-deftest agent-workspace-minimap/the-lanes ()
  "A lane for each agent that did something: a cell a minute (what it did
most), its state's glyph, where it is now (its file and line, what it asks);
the quiet ones on a line; a file two agents changed, ⚠; the axis and the
legend."
  (+test-awm "lanes"
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (sam (agent-workspace-create :role "investigator" :name "sam"))
           (ken (agent-workspace-create :role "builder" :name "ken"))
           (now (float-time)))
      (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now)))
        (setq now (- (float-time) 180))
        (+test-awm--tool ada "read" "README" 1)
        (+test-awm--tool ada "search")
        (setq now (+ now 180))
        (+test-awm--tool ada "read" "src/a.el" 2)
        (+test-awm--tool ada "edit" "src/a.el" 3)
        (+test-awm--tool sam "execute")
        (+test-awm--tool sam "read" "src/a.el" 1))
      (agent-workspace--set-state sam 'hand)
      (setf (agent-workspace-agent-ask sam) '(:kind permission :title "npm install"))
      (agent-workspace--set-state ada 'working)
      (agent-workspace--add-changed ada '("src/a.el"))
      (agent-workspace--add-changed sam '("src/a.el" "README"))
      (agent-workspace-open t)
      (let ((lines (split-string (+test-awm--text project) "\n")))
        ;; ada: read 3 minutes ago, edited now; working, at src/a.el:3.
        (should (string-match-p (concat "\\`  ?▌A " (make-string (- agent-workspace-activity-minutes 4) ?·)
                                        "⌕··✎ │ .  ?src/a\\.el:3\\'")
                                (nth 0 lines)))
        ;; sam: ran a command now (over a read), its hand raised.
        (should (string-match-p "▌S ·+▶ │ !  ?wants to use npm insta…" (nth 1 lines)))
        (should (string-match-p "\\`  ?quiet +▌K ken ○\\'" (nth 2 lines)))
        (should (string-match-p "⚠ ada \\+ sam: src/a\\.el" (nth 3 lines)))
        (should (equal (string-trim (nth 4 lines)) "-15m    -5m now"))
        (should (string-search "⌕ read  ✎ edit  ▶ run  ! asks you" (nth 5 lines)))
        (should (= (length lines) 6)))
      (ignore ken))))

(ert-deftest agent-workspace-minimap/drawn-as-they-do-things ()
  "Drawn again as an agent does things, a burst once, a quarter of a second
on; not while the app is left; no redraw waiting once it's closed."
  (+test-awm "live"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (draws 0))
      (agent-workspace-open t)
      (should (string-search "quiet" (+test-awm--text project)))
      (cl-letf* ((draw (symbol-function 'agent-workspace--minimap-draw))
                 ((symbol-function 'agent-workspace--minimap-draw)
                  (lambda (project) (cl-incf draws) (funcall draw project))))
        (dotimes (_ 5) (+test-awm--tool ada "read" "README" 1))
        (should (= draws 0))
        (should (+test-wait-for (lambda () (string-search "README:1" (+test-awm--text project))) 2))
        (should (= draws 1))
        ;; A redraw waits for the next minute (its cells move on).
        (should (timerp (gethash project agent-workspace--minimap-timers)))
        ;; Left: nothing drawn, nothing waiting for it.
        (with-current-buffer (agent-workspace--issues-buffer project)
          (agent-workspace-leave t))
        (+test-awm--tool ada "edit" "src/a.el" 2)
        (+test-sleep 0.4)
        (should (= draws 1))
        (should (string-search "README:1" (+test-awm--text project)))
        ;; Back: drawn as it is now (the frame's size again: a wait in batch
        ;; gives it the terminal's).
        (set-frame-size (selected-frame) 220 40)
        (agent-workspace-open t)
        (should (string-search "src/a.el:2" (+test-awm--text project)))
        (agent-workspace--close-app project)
        (should-not (gethash project agent-workspace--minimap-timers))))))

(ert-deftest agent-workspace-minimap/its-keys ()
  "On a lane: j/k between lanes, RET selects its agent, o opens its file in
its worktree at its line. On a ⚠: d shows both agents' changes to its file."
  (+test-awm "keys"
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (ken (agent-workspace-create :role "builder" :name "ken")))
      (write-region "(a ada)\n" nil (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)))
      (write-region "(a ken)\n(b)\n(c)\n" nil (expand-file-name "src/a.el" (agent-workspace-agent-worktree ken)))
      (+test-awm--tool ada "edit" "src/a.el" 1)
      (+test-awm--tool ken "read" "src/a.el" 3)
      (agent-workspace--activity-event ada '((:event . turn-complete)))
      (agent-workspace--activity-event ken '((:event . turn-complete)))
      (agent-workspace-open t)
      (agent-workspace-select ada)
      ;; j from ada's lane: ken's; RET selects ken.
      (+test-awm--goto project "▌A")
      (agent-workspace-minimap-next)
      (should (eq (get-text-property (point) 'agent-workspace-minimap-agent) ken))
      (agent-workspace-minimap-select)
      (should (eq (agent-workspace--app-selected (agent-workspace--app project)) ken))
      ;; A key of the app's acts on the lane's agent.
      (+test-awm--goto project "▌A")
      (should (eq (agent-workspace--current) ada))
      ;; o: ken's file, in its worktree, at its line.
      (+test-awm--goto project "▌K")
      (save-window-excursion
        (agent-workspace-minimap-open)
        (should (equal (buffer-file-name)
                       (expand-file-name "src/a.el" (agent-workspace-agent-worktree ken))))
        (should (= (line-number-at-pos) 3))
        (kill-buffer))
      ;; d on the conflict: both diffs.
      (agent-workspace-open t)
      (+test-awm--goto project "⚠")
      (save-window-excursion
        (agent-workspace-minimap-diff)
        (should (equal (buffer-name) "*ada + ken: src/a.el*"))
        (let ((text (buffer-string)))
          (should (string-search "# ada (agent/ada)" text))
          (should (string-search "+(a ada)" text))
          (should (string-search "# ken (agent/ken)" text))
          (should (string-search "+(a ken)" text)))
        (kill-buffer)))))
