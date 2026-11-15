;;; tests/unit/test-agent-workspace-app.el -*- lexical-binding: t; -*-
;; config/agent-workspace/app.el, stage.el, issues.el and look.el: the crew's
;; app. Its layout (the issues on the left, the stage: one pane open, the
;; others a bar each), selecting and folding, the crew changing, an agent's
;; canvas and panels as tabs in its pane (v, V, a click, its badge), the issue
;; list from bd's answers, its tally elsewhere, tiling leaving its frame alone;
;; opening, leaving and closing it in real persp-mode workspaces, its stand-in
;; agents (examples/agent-workspace/stand-in.el) exiting with no process left.

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'persp-mode)
(require 'json)

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-ui" "config/tiling" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)
;; The stage's layout, the minimap off (test-agent-workspace-minimap.el's).
(setq agent-workspace-minimap nil)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))

;; ====== HELPERS ======

(defun +test-awa--git (&rest args)
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awa--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awa/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awa--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (+test-awa--git "add" "README")
      (+test-awa--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awa (name &rest body)
  "BODY in a new project NAME (`project'), a frame 160x40, no app or crew
before or after; agents' sessions plain buffers (no agent runs), at the
desk; bd not run (`issues': what it answers, plists of bd's JSON)."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awa--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace-new-asked nil))
       (ignore agent-workspace-new-asked)
       ;; Wide enough for the room on the right (its own tests: test-agent-workspace-room.el).
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
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
         (unwind-protect (progn ,@body)
           (dolist (project (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app project))
           (agent-workspace-close-all)
           (set-frame-parameter nil 'agent-workspace nil))))))

(defun +test-awa--windows ()
  "The frame's windows but the room's: (BUFFER-NAME WIDTH HEIGHT), in order."
  (mapcar (lambda (w) (list (buffer-name (window-buffer w)) (window-total-width w) (window-total-height w)))
          (seq-remove (lambda (w) (window-parameter w 'agent-workspace-room))
                      (window-list nil 'nomini (frame-first-window)))))

(defun +test-awa--height ()
  "The frame's windows' height, in rows."
  (window-total-height (frame-root-window)))

(defun +test-awa--crew (&rest specs)
  "Agents made from SPECS ((NAME ROLE)...): the agents."
  (mapcar (lambda (spec) (agent-workspace-create :role (cadr spec) :name (car spec)))
          specs))

;; ====== THE LAYOUT ======

(ert-deftest agent-workspace-app/sizes ()
  "A stack's rows: every pane folded to a row but the open one, which takes
the rest; not enough rows to open it: all folded."
  (should (equal (agent-workspace--sizes '(a b c) 'b 20) '((a . 1) (b . 18) (c . 1))))
  (should (equal (agent-workspace--sizes '(a b c) nil 20) '((a . 1) (b . 1) (c . 1))))
  (should (equal (agent-workspace--sizes '(a b c) 'b 7) '((a . 1) (b . 1) (c . 1))))
  (should (equal (agent-workspace--sizes '(a b c) 'b 8) '((a . 1) (b . 6) (c . 1)))))

(ert-deftest agent-workspace-app/laid-out ()
  "The issues on the left (50 columns, full height); the stage beside them,
in role order: the selected agent's pane open (no mode line or tab line, its
line as its header line), the others a bar a row high; its frame marked (tiling
leaves it alone)."
  (+test-awa "layout"
    (pcase-let ((`(,sam ,ada ,ken) (+test-awa--crew '("sam" "investigator") '("ada" "builder") '("ken" "builder"))))
      (let ((app (agent-workspace-open t)))
        (should (equal (+test-awa--windows)
                       `(("*issues · layout*" 50 ,(+test-awa--height))
                         ("ada · builder" 92 ,(- (+test-awa--height) 2)) (" *bar · ken · layout*" 92 1)
                         (" *bar · sam · layout*" 92 1))))
        (should (eq (agent-workspace--app-selected app) ada))
        (let ((pane (get-buffer-window (agent-workspace-agent-buffer ada))))
          (should (eq (window-parameter pane 'mode-line-format) 'none))
          (should (eq (window-parameter pane 'tab-line-format) 'none))
          (should (equal (window-parameter pane 'header-line-format) '(:eval (agent-workspace--pane-header))))
          (with-selected-window pane
            (should (string-match-p "\\`▾ ▌A ada · builder · ○ at the desk"
                                    (substring-no-properties (agent-workspace--pane-header))))))
        (should (equal (with-current-buffer (agent-workspace--bar-buffer sam) (buffer-string))
                       (substring-no-properties (agent-workspace-line sam 92 nil t))))
        (should (string-prefix-p "▸ ▌S sam · investigator · ○ at the desk"
                                 (with-current-buffer (agent-workspace--bar-buffer sam)
                                   (buffer-substring-no-properties (point-min) (point-max)))))
        ;; Its role, mode, branch glyph and the dots between readable on its
        ;; colour's tint, the same for every agent; a dot between its mode and
        ;; its branch.
        (dolist (agent (list sam ada))
          (let* ((line (agent-workspace-line agent 120))
                 (at (lambda (text) (ensure-list (get-text-property (string-search text line) 'face line)))))
            (should (memq 'agent-workspace-label (funcall at (agent-workspace-agent-role agent))))
            (should (memq 'agent-workspace-label (funcall at " · ")))
            (should (memq 'agent-workspace-label (funcall at "auto")))
            (should (string-match-p "auto · .+agent/" (substring-no-properties line)))
            (let ((glyph (1- (string-search "agent/" line))))
              (while (eq (aref line glyph) ?\s) (setq glyph (1- glyph)))
              (should (memq 'agent-workspace-label (ensure-list (get-text-property glyph 'face line)))))))
        (should (agent-workspace-frame-p))
        (should (+my/tiling--left-alone-p))
        (ignore ken)))))

(ert-deftest agent-workspace-app/its-time-as-its-state ()
  "An agent's turn time on its line (its pane's header line, its bar) in its
state's words' face: the text's while it works or is at the desk, readable on
its colour's tint (shadow wasn't); its state's own (a raised hand's, done's);
dimmed while it isn't there to work."
  (let ((agent (agent-workspace--make-agent :name "ada" :role "builder" :colour "cyan"
                                            :project "/tmp/awa-time/" :since (- (float-time) 250)))
        (agent-workspace-role-function (lambda (_project name) (list :name name :verb "building")))
        ;; A text's faces but its tint's background (and gone home's strike).
        (faces (lambda (line at)
                 (let ((face (get-text-property at 'face line)))
                   (seq-remove (lambda (f) (and (consp f) (or (plist-member f :background) (plist-member f :strike-through))))
                               (if (keywordp (car-safe face)) (list face) (ensure-list face)))))))
    (pcase-dolist (`(,state . ,face) '((working) (desk) (hand . warning) (done . success) (stuck . error)
                                       (waking . shadow) (asleep . shadow) (home . shadow)))
      (setf (agent-workspace-agent-state agent) state
            (agent-workspace-agent-ask agent) (and (eq state 'hand) '(:kind permission :title "npm install")))
      (dolist (how '((t) (nil t)))
        (let* ((line (apply #'agent-workspace-line agent 120 how))
               (time (+ 3 (string-search " · 4m" line)))
               (words (string-search (agent-workspace-state-text agent) line)))
          (should (equal (funcall faces line time) (funcall faces line words)))
          (should (equal (funcall faces line time) (ensure-list face))))))))

(ert-deftest agent-workspace-app/selecting-and-folding ()
  "Selecting an agent opens its pane and folds the others, the issue list
kept; TAB folds it: every pane a bar, the hint below them."
  (+test-awa "select"
    (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
      (agent-workspace-open t)
      (agent-workspace-select ken t)
      (should (equal (+test-awa--windows)
                     `(("*issues · select*" 50 ,(+test-awa--height)) (" *bar · ada · select*" 92 1)
                       ("ken · builder" 92 ,(1- (+test-awa--height))))))
      (should (eq (window-buffer) (agent-workspace-agent-buffer ken)))
      ;; Done becomes at the desk when selected.
      (setf (agent-workspace-agent-state ada) 'done)
      (with-current-buffer (agent-workspace--bar-buffer ada) (agent-workspace-go))
      (should (eq (agent-workspace-agent-state ada) 'desk))
      (should (eq (window-buffer) (agent-workspace-agent-buffer ada)))
      ;; ] (k on a bar): the previous agent, wrapping, the cursor in its pane.
      (with-current-buffer (agent-workspace-agent-buffer ada) (agent-workspace-previous))
      (should (eq (window-buffer) (agent-workspace-agent-buffer ken)))
      ;; TAB: folded.
      (agent-workspace-toggle)
      (should (equal (mapcar #'car (+test-awa--windows))
                     '("*issues · select*" " *bar · ada · select*" " *bar · ken · select*" "*stage · select*")))
      (should (string-search "Every pane is folded" (with-current-buffer "*stage · select*" (buffer-string))))
      (should (eq (window-buffer) (agent-workspace--bar-buffer ken))))))

(ert-deftest agent-workspace-app/the-crew-changing ()
  "A new agent: its pane opens, selected; one forgotten: gone from the stage;
a state changed: its bar drawn again."
  (+test-awa "changing"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (agent-workspace-open t)
      (let ((ken (agent-workspace-create :role "builder" :name "ken")))
        (should (equal (mapcar #'car (+test-awa--windows))
                       '("*issues · changing*" " *bar · ada · changing*" "ken · builder")))
        (setf (agent-workspace-agent-state ada) 'working
              (agent-workspace-agent-since ada) (- (float-time) 125))
        (agent-workspace--changed ada 'state)
        (should (string-search "⚙ building · 2m" (with-current-buffer (agent-workspace--bar-buffer ada) (buffer-string))))
        ;; Its time ticking, while the app's shown.
        (agent-workspace--tick)
        (should (timerp agent-workspace--timer))
        (agent-workspace-forget ken 'keep)
        (should (equal (mapcar #'car (+test-awa--windows)) '("*issues · changing*" "ada · builder")))))))

(ert-deftest agent-workspace-app/no-agents-yet ()
  "Opened with no agent: its first is asked for; asked nothing (C-g), the
stage says how to make one."
  (+test-awa "empty"
    (let ((asked nil))
      (cl-letf (((symbol-function 'agent-workspace-new) (lambda (&rest _) (setq asked t) (signal 'quit nil))))
        (agent-workspace-open t))
      (should asked)
      (should (equal (mapcar #'car (+test-awa--windows)) '("*issues · empty*" "*stage · empty*")))
      (should (string-search "No agents yet" (with-current-buffer "*stage · empty*" (buffer-string)))))))

(ert-deftest agent-workspace-app/leave-and-quit-without-workspaces ()
  "Without workspaces: q gives your windows back, the crew going on; Q
closes it: its agents exit, its buffers go, your windows back."
  (+test-awa "here"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (switch-to-buffer (get-buffer-create "mine"))
      (split-window-right)
      (agent-workspace-open t)
      (agent-workspace-leave)
      (should (equal (mapcar #'car (+test-awa--windows)) '("mine" "mine")))
      (should-not (agent-workspace-frame-p))
      (should (agent-workspace-agents project))
      ;; Its tally, elsewhere: a click goes back.
      (should (string-match-p "crew · here" (agent-workspace--tally-mode-line)))
      (agent-workspace-open t)
      (agent-workspace-quit)
      (should (equal (mapcar #'car (+test-awa--windows)) '("mine" "mine")))
      (should-not (agent-workspace-agents project))
      (should (eq (agent-workspace-agent-state ada) 'home))
      (should-not (get-buffer "*issues · here*"))
      (should-not (get-buffer " *bar · ada · here*"))
      (should (equal (agent-workspace--tally-mode-line) "")))))

(ert-deftest agent-workspace-app/no-crew-here ()
  "Outside git: no app, the reason given to `agent-workspace-no-crew-function'."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "awa-nogit-") t)))
         (default-directory dir)
         (said nil)
         (agent-workspace-no-crew-function (lambda (d reason) (setq said (list d reason)))))
    ;; Not a project either: asked which, this folder answered.
    (cl-letf (((symbol-function 'agent-workspace--read-project) (lambda () dir)))
      (agent-workspace-open))
    (should (equal (car said) dir))
    (should (string-prefix-p "not a git repository" (cadr said)))))

(ert-deftest agent-workspace-app/a-file-shown-elsewhere ()
  "A file shown from the app (an agent's reply): where you came from, the app
left, the crew going on."
  (+test-awa "elsewhere"
    (+test-awa--crew '("ada" "builder"))
    (switch-to-buffer (get-buffer-create "mine"))
    (agent-workspace-open t)
    (let ((file (find-file-noselect (expand-file-name "README" project))))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (pop-to-buffer file))
      (should-not (agent-workspace-frame-p))
      (should (get-buffer-window file))
      (should (agent-workspace-agents project)))))

;; ====== ITS CANVAS AND PANELS ======

(defconst +test-awa--panel
  ";;; -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type \"text\" :id \"t\" :text \"\")
 :every 60
 :fetch (lambda (panel) (agent-ui-panel-update panel \"t\" :text default-directory)))
"
  "A panel showing where it runs.")

(defun +test-awa--panels (project &rest names)
  "Panels NAMES committed in PROJECT (before its agents' worktrees are made),
the project trusted."
  (let ((default-directory project))
    (make-directory ".agent-ui/panels" t)
    (dolist (name names)
      (write-region +test-awa--panel nil (format ".agent-ui/panels/%s.el" name)))
    (+test-awa--git "add" ".")
    (+test-awa--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "panels"))
  (agent-ui-panel-trust-project project))

(defun +test-awa--open-panel (agent name)
  "AGENT's panel NAME opened, as its request opens it: its canvas."
  (agent-ui-open-panel name (agent-workspace-agent-worktree agent) t))

(defun +test-awa--canvas-show (agent element)
  "ELEMENT shown on AGENT's canvas, as its session shows it: the canvas."
  (let* ((session (agent-workspace-agent-buffer agent))
         (canvas (agent-ui-canvas (agent-ui--session-name session))))
    ;; Tied to its session as Agent UI ties an agent-shell session's.
    (with-current-buffer canvas (setq agent-ui--session-buffer session))
    (agent-ui-show element :canvas canvas)
    canvas))

(defun +test-awa--header (window)
  "WINDOW's header line, as text (its :eval's, as redisplay has it: no
`format-mode-line' in batch)."
  (with-selected-window window
    (substring-no-properties
     (string-replace "%%" "%" (eval (cadr (window-parameter window 'header-line-format)) t)))))

(defun +test-awa--side ()
  "The selected agent's side area's window."
  (agent-workspace--side-window (agent-workspace--app-selected (agent-workspace--here))))

(defmacro +test-awa--in (window &rest body)
  "BODY in WINDOW, selected, its buffer current, as a key typed there (the
window it selects stays selected)."
  (declare (indent 1))
  `(progn (select-window ,window)
          (with-current-buffer (window-buffer ,window) ,@body)))

(defun +test-awa--timers ()
  "The timers due run, not redisplay (in batch it resizes the frame)."
  (dotimes (_ 3) (accept-process-output nil 0.02)))

(ert-deftest agent-workspace-app/panels-as-tabs ()
  "An agent with a canvas and two panels: below its session (under 140
columns), its side area holds them as tabs, one shown (the canvas, its
panels hidden: they fetch nothing); its header line counts its panels (◫2),
a bar of an agent with none says nothing. v goes to the one shown, then
shows the next, wrapping; a click on a tab shows it; something new on its
canvas brings its tab back. The stage still arranged: one pane open, the
other a row."
  (+test-awa "tabs"
    (let ((agent-ui-panel-trust-file (+test-tmp-file "awa-tabs-trust.eld")))
      (+test-awa--panels project "logs" "tests")
      (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
        (agent-workspace-open t)
        (agent-workspace-select ada)
        (let* ((canvas (+test-awa--canvas-show ada '(:type "text" :id "hello" :text "Hello")))
               (logs (+test-awa--open-panel ada "logs"))
               (tests (+test-awa--open-panel ada "tests"))
               (pane (get-buffer-window (agent-workspace-agent-buffer ada)))
               (side (+test-awa--side)))
          (should (equal (+test-awa--windows)
                         `(("*issues · tabs*" 50 ,(+test-awa--height))
                           ("ada · builder" 92 ,(window-total-height pane))
                           ("Agent UI: ada · builder" 92 ,(- (+test-awa--height) 1 (window-total-height pane)))
                           (" *bar · ken · tabs*" 92 1))))
          (should (eq (window-buffer side) canvas))
          (should-not (get-buffer-window logs))
          (should-not (get-buffer-window tests))
          (should (string-prefix-p " canvas │ logs │ tests" (+test-awa--header side)))
          (should (string-search "v: next · V: full size" (+test-awa--header side)))
          ;; Its badge, its panels counted; none on ken's bar.
          (should (string-search "◫2" (+test-awa--header pane)))
          (should-not (string-search "◫" (with-current-buffer (agent-workspace--bar-buffer ken) (buffer-string))))
          ;; v and V in a canvas or panel there, not evil's visual state.
          (with-current-buffer canvas
            (should (eq (key-binding "v") #'agent-workspace-panels-here))
            (should (eq (key-binding "V") #'agent-workspace-full-here)))
          ;; v from the issue list: the cursor in the one shown.
          (with-current-buffer (agent-workspace--issues-buffer project)
            (agent-workspace-panels-here))
          (should (eq (selected-window) (+test-awa--side)))
          (should (eq (window-buffer) canvas))
          ;; v there: the next one, the cursor in it; the others hidden.
          (+test-awa--in (selected-window) (agent-workspace-panels-here))
          (should (eq (window-buffer) logs))
          (should (eq (selected-window) (+test-awa--side)))
          (should-not (get-buffer-window canvas))
          (should (string-prefix-p " canvas │ logs │ tests" (+test-awa--header (selected-window))))
          (+test-awa--in (selected-window) (agent-workspace-panels-here))
          (should (eq (window-buffer) tests))
          (should-not (get-buffer-window logs))
          ;; Wrapping.
          (+test-awa--in (selected-window) (agent-workspace-panels-here))
          (should (eq (window-buffer) canvas))
          ;; A click on a tab shows it.
          (let* ((side (selected-window))
                 (text (with-selected-window side (agent-workspace--side-header)))
                 (at (string-search "logs" text)))
            (agent-workspace-tab-click `(mouse-1 (,side header-line (0 . 0) 0 (,text . ,at))))
            (should (eq (window-buffer (+test-awa--side)) logs)))
          ;; Something new on its canvas: its tab shown again.
          (agent-ui-show '(:type "text" :id "news" :text "News") :canvas canvas)
          (should (eq (window-buffer (+test-awa--side)) canvas))
          ;; The stage as it was: ada's pane open, ken's a row.
          (should (equal (mapcar #'car (+test-awa--windows))
                         '("*issues · tabs*" "ada · builder" "Agent UI: ada · builder" " *bar · ken · tabs*")))
          (should (= (window-total-height (get-buffer-window (agent-workspace--bar-buffer ken))) 1))
          ;; Their code started (a timer, last: a wait gives the batch frame
          ;; its own size back): the one shown fetches, a hidden one doesn't.
          (+test-awa--in (+test-awa--side) (agent-workspace-panels-here))
          (should (eq (window-buffer) logs))
          (+test-awa--timers)
          (should (agent-ui-panel-fetched (buffer-local-value 'agent-ui-panels--state logs)))
          (should-not (agent-ui-panel-fetched (buffer-local-value 'agent-ui-panels--state tests)))
          (should (agent-ui-panels--stale (buffer-local-value 'agent-ui-panels--state tests))))))))

(ert-deftest agent-workspace-app/a-tab-full-size ()
  "V: the tab shown takes its pane's whole room (its session hidden), the
tabs at its line's right, the cursor in it; v there shows the next one; V
again: back beside its session. Another agent selected, it's back too; a
raised hand gone to shows its session."
  (+test-awa "full"
    (let ((agent-ui-panel-trust-file (+test-tmp-file "awa-full-trust.eld")))
      (+test-awa--panels project "logs")
      (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
        (agent-workspace-open t)
        (agent-workspace-select ada)
        (let ((canvas (+test-awa--canvas-show ada '(:type "text" :id "hello" :text "Hello")))
              (logs (+test-awa--open-panel ada "logs"))
              (session (agent-workspace-agent-buffer ada)))
          (with-current-buffer (agent-workspace--issues-buffer project)
            (agent-workspace-full-here))
          (should (equal (+test-awa--windows)
                         `(("*issues · full*" 50 ,(+test-awa--height))
                           ("Agent UI: ada · builder" 92 ,(1- (+test-awa--height)))
                           (" *bar · ken · full*" 92 1))))
          (should (eq (window-buffer) canvas))
          (should-not (get-buffer-window session))
          (let ((header (+test-awa--header (selected-window))))
            (should (string-prefix-p "▾ ▌A ada · builder · ○ at the desk" header))
            (should (string-match-p "canvas │ logs *\\'" header)))
          ;; v: the next one, full size.
          (+test-awa--in (selected-window) (agent-workspace-panels-here))
          (should (eq (window-buffer) logs))
          (should (= (window-total-height) (1- (+test-awa--height))))
          ;; V again: back beside its session, the cursor in the side.
          (+test-awa--in (selected-window) (agent-workspace-full-here))
          (should (equal (mapcar #'car (+test-awa--windows))
                         '("*issues · full*" "ada · builder" "Agent UI: logs · ada" " *bar · ken · full*")))
          (should (eq (window-buffer) logs))
          ;; Full size, then ken selected and ada again: beside its session.
          (+test-awa--in (selected-window) (agent-workspace-full-here))
          (should-not (get-buffer-window session))
          (agent-workspace-select ken)
          (agent-workspace-select ada)
          (should (get-buffer-window session))
          ;; Full size, a raised hand gone to (a): its session shown.
          (+test-awa--in (+test-awa--side) (agent-workspace-full-here))
          (should-not (get-buffer-window session))
          (setf (agent-workspace-agent-state ada) 'hand)
          (with-current-buffer (agent-workspace--issues-buffer project)
            (agent-workspace-next-hand))
          (should (get-buffer-window session)))))))

(ert-deftest agent-workspace-app/panels-coming-and-going ()
  "A panel opened for the agent whose pane is open: its side area comes;
for a folded one: its bar's badge only, the stage as it was. Closed: gone
from its pane and its badge. With nothing to show, v and V say so. In a
pane 140 columns wide or more, the side area is beside its session."
  (+test-awa "coming"
    (let ((agent-ui-panel-trust-file (+test-tmp-file "awa-coming-trust.eld")))
      (+test-awa--panels project "logs")
      (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
        (agent-workspace-open t)
        (agent-workspace-select ada)
        (should (equal (mapcar #'car (+test-awa--windows))
                       '("*issues · coming*" "ada · builder" " *bar · ken · coming*")))
        (with-current-buffer (agent-workspace--issues-buffer project)
          (should-error (agent-workspace-panels-here) :type 'user-error)
          (should-error (agent-workspace-full-here) :type 'user-error))
        (let ((logs (+test-awa--open-panel ada "logs")))
          (should (equal (mapcar #'car (+test-awa--windows))
                         '("*issues · coming*" "ada · builder" "Agent UI: logs · ada" " *bar · ken · coming*")))
          ;; ken's: its bar says so, nothing else moves.
          (let ((theirs (+test-awa--open-panel ken "logs")))
            (should (equal (mapcar #'car (+test-awa--windows))
                           '("*issues · coming*" "ada · builder" "Agent UI: logs · ada" " *bar · ken · coming*")))
            (should (string-search "◫1" (with-current-buffer (agent-workspace--bar-buffer ken) (buffer-string))))
            (should-not (get-buffer-window theirs)))
          ;; Wide: beside its session, as high as it.
          (let ((agent-workspace-room-side 'bottom))
            (agent-workspace-layout)
            (let ((pane (get-buffer-window (agent-workspace-agent-buffer ada)))
                  (side (get-buffer-window logs)))
              (should (= (window-total-width (frame-root-window)) 220))
              (should (>= (+ (window-total-width pane) (window-total-width side)) 140))
              (should (= (window-top-line pane) (window-top-line side)))
              (should (= (window-total-height pane) (window-total-height side)))))
          ;; Closed: its side area gone, its badge too.
          (kill-buffer logs)
          (+test-awa--timers)
          (should (equal (mapcar #'car (+test-awa--windows))
                         '("*issues · coming*" "ada · builder" " *bar · ken · coming*")))
          (should-not (string-search "◫" (+test-awa--header (get-buffer-window (agent-workspace-agent-buffer ada))))))))))

(ert-deftest agent-workspace-app/its-canvas-closed ()
  "q on an agent's canvas on the stage (it's killed): its side area closes
at once, its session takes the whole pane, the cursor in it; with a panel,
the panel shown there, the cursor in it, the canvas's tab gone. Full size:
its pane back to its session. Its canvas emptied (cleared, its last element
removed): the same. Never another buffer in its side area (Emacs's
replacement for a killed buffer, Agent UI's for an emptied canvas's pane).
Something new on it: its side area back."
  (+test-awa "closed"
    (let ((agent-ui-panel-trust-file (+test-tmp-file "awa-closed-trust.eld"))
          ;; The room low, below the stage: room for a side area.
          (agent-workspace-room-height 4))
      (+test-awa--panels project "logs")
      (pcase-let ((`(,ada ,_ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
        (agent-workspace-open t)
        (agent-workspace-select ada)
        ;; The batch frame its own size again (a wait gives it back, the
        ;; stage laid out again 0.2 s later), then laid out there: the waits
        ;; below change nothing but what they're for.
        (accept-process-output nil 0.3)
        (agent-workspace-layout)
        (let ((session (agent-workspace-agent-buffer ada))
              (alone '("*issues · closed*" "ada · builder" " *bar · ken · closed*"))
              (beside '("*issues · closed*" "ada · builder" "Agent UI: logs · ada" " *bar · ken · closed*")))
          ;; q, no panel: its session alone, the cursor in it.
          (let ((canvas (+test-awa--canvas-show ada '(:type "text" :id "a" :text "A"))))
            (should (eq (window-buffer (+test-awa--side)) canvas))
            (+test-awa--in (+test-awa--side) (kill-current-buffer))
            (+test-awa--timers)
            (should (equal (mapcar #'car (+test-awa--windows)) alone))
            (should (eq (window-buffer) session)))
          ;; Something new: back. Cleared, its last element removed: gone.
          (let ((canvas (+test-awa--canvas-show ada '(:type "text" :id "b" :text "B"))))
            (should (equal (mapcar #'car (+test-awa--windows))
                           '("*issues · closed*" "ada · builder" "Agent UI: ada · builder" " *bar · ken · closed*")))
            (agent-ui-clear :canvas canvas)
            (+test-awa--timers)
            (should (equal (mapcar #'car (+test-awa--windows)) alone))
            (+test-awa--canvas-show ada '(:type "text" :id "c" :text "C"))
            (should (eq (window-buffer (+test-awa--side)) canvas))
            (agent-ui-remove "c" :canvas canvas)
            (+test-awa--timers)
            (should (equal (mapcar #'car (+test-awa--windows)) alone)))
          ;; With a panel: q shows it, the canvas's tab gone, the cursor in it.
          (let* ((logs (+test-awa--open-panel ada "logs"))
                 (canvas (+test-awa--canvas-show ada '(:type "text" :id "d" :text "D"))))
            (should (eq (window-buffer (+test-awa--side)) canvas))
            (should (equal (agent-workspace-agent-tabs ada) (list canvas logs)))
            (+test-awa--in (+test-awa--side) (kill-current-buffer))
            (+test-awa--timers)
            (should (equal (mapcar #'car (+test-awa--windows)) beside))
            (should (eq (window-buffer) logs))
            (should (equal (agent-workspace-agent-tabs ada) (list logs)))
            (should-not (string-search "canvas" (+test-awa--header (+test-awa--side))))
            ;; Full size: q, its pane back to its session, the panel beside it.
            (let ((canvas (+test-awa--canvas-show ada '(:type "text" :id "e" :text "E"))))
              (with-current-buffer (agent-workspace--issues-buffer project)
                (agent-workspace-full-here))
              (should (eq (window-buffer) canvas))
              (should-not (get-buffer-window session))
              (+test-awa--in (selected-window) (kill-current-buffer))
              (+test-awa--timers)
              (should (equal (mapcar #'car (+test-awa--windows)) beside))
              (should (eq (window-buffer) logs)))
            ;; Full size, cleared: the same.
            (let ((canvas (+test-awa--canvas-show ada '(:type "text" :id "f" :text "F"))))
              (with-current-buffer (agent-workspace--issues-buffer project)
                (agent-workspace-full-here))
              (should-not (get-buffer-window session))
              (agent-ui-clear :canvas canvas)
              (+test-awa--timers)
              (should (equal (mapcar #'car (+test-awa--windows)) beside))
              ;; Its panel shown, its canvas a hidden tab, emptied: its tab gone.
              (+test-awa--canvas-show ada '(:type "text" :id "g" :text "G"))
              (+test-awa--in (+test-awa--side) (agent-workspace-panels-here))
              (should (eq (window-buffer (+test-awa--side)) logs))
              (agent-ui-remove "g" :canvas canvas)
              (+test-awa--timers)
              (should (equal (mapcar #'car (+test-awa--windows)) beside))
              (should (equal (agent-workspace-agent-tabs ada) (list logs)))
              (should-not (string-search "canvas" (+test-awa--header (+test-awa--side)))))))))))

;; ====== THE ISSUES ======

(defconst +test-awa--bd
  (list :all (json-parse-string
              "[{\"id\":\"p-1\",\"title\":\"Fix the parser\",\"status\":\"in_progress\",\"assignee\":\"ada\",\"priority\":1,\"labels\":[\"build\"]},
                {\"id\":\"p-2\",\"title\":\"Build the lexer, a title long enough to need two rows in a column fifty wide\",\"status\":\"open\",\"priority\":1,\"labels\":[\"build\"]},
                {\"id\":\"p-3\",\"title\":\"Why does it crash\",\"status\":\"open\",\"priority\":2,\"labels\":[\"investigation\"]},
                {\"id\":\"p-4\",\"title\":\"Docs\",\"status\":\"open\",\"priority\":3},
                {\"id\":\"p-5\",\"title\":\"Release\",\"status\":\"open\",\"priority\":2,\"dependencies\":[{\"depends_on_id\":\"p-2\",\"type\":\"blocks\"}]},
                {\"id\":\"p-6\",\"title\":\"The epic\",\"status\":\"open\",\"issue_type\":\"epic\"}]"
              :object-type 'alist :array-type 'list)
        :ready (json-parse-string "[{\"id\":\"p-2\"},{\"id\":\"p-3\"},{\"id\":\"p-4\"},{\"id\":\"p-6\"}]"
                                  :object-type 'alist :array-type 'list)
        :done (json-parse-string "[{\"id\":\"p-0\",\"title\":\"Set up\",\"status\":\"closed\",\"assignee\":\"ken\",\"closed_at\":\"2026-01-01T10:00:00Z\"}]"
                                 :object-type 'alist :array-type 'list))
  "What bd answers, for the issue list's tests.")

(ert-deftest agent-workspace-app/the-issues ()
  "In progress (its agent's avatar and state), ready by the role it's for
(one nobody in the crew takes, flagged), blocked (by what), done today; a
long title on a second row; epics left out."
  (+test-awa "issues"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (agent-workspace-open t)
      (with-current-buffer "*issues · issues*"
        (setq agent-workspace--issues-data (agent-workspace--issues-parse project +test-awa--bd))
        (agent-workspace--issues-redraw project)
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (dolist (part '(" IN PROGRESS" " ▌A p-1 Fix the parser" " READY" "builders  1" "p-2 Build the lexer, a"
                          "investigators  1" "nobody in the crew takes these" "p-3 Why does it crash"
                          "for any role  1" "p-4 Docs" " BLOCKED" "p-5 Release" "⊘ p-2" " DONE TODAY" "p-0 Set up"))
            (should (string-search part text)))
          (should-not (string-search "The epic" text))
          ;; The long title's second row, under its title.
          (should (string-match-p "\n +[a-z ]*column fifty wide" text)))
        ;; Its agent on its issue in progress; the cursor follows the selection.
        (goto-char (point-min))
        (should (agent-workspace--issues-goto-agent ada))
        (should (eq (agent-workspace--issues-agent-at) ada))
        ;; j goes issue by issue, a two-row issue one.
        (agent-workspace-issue-next)
        (should (equal (plist-get (get-text-property (point) 'agent-workspace-issue) :id) "p-2"))
        (agent-workspace-issue-next)
        (should (equal (plist-get (get-text-property (point) 'agent-workspace-issue) :id) "p-3"))))))

(ert-deftest agent-workspace-app/giving-an-issue ()
  "t gives a ready issue to an agent (the selected one first): sent \"Work on
ID: TITLE\" now, or after its turn; noted as its."
  (+test-awa "give"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (agent-workspace-open t)
      (let ((sent nil))
        (cl-letf (((symbol-function 'agent-workspace-send)
                   (lambda (agent text &rest args) (push (list (agent-workspace-agent-name agent) text args) sent) 'sent))
                  ((symbol-function 'completing-read) (lambda (_prompt names &rest _) (car names))))
          (with-current-buffer "*issues · give*"
            (setq agent-workspace--issues-data (agent-workspace--issues-parse project +test-awa--bd))
            (agent-workspace--issues-redraw project)
            (agent-workspace--issues-goto-id "p-2")
            (agent-workspace-issue-give)
            (should (equal sent '(("ada" "Work on p-2: Build the lexer, a title long enough to need two rows in a column fifty wide" (:submit t)))))
            (should (equal (agent-workspace-agent-issue ada) "p-2"))
            ;; Not one in progress.
            (agent-workspace--issues-goto-id "p-1")
            (should-error (agent-workspace-issue-give) :type 'user-error)))))))

;; ====== WORKSPACES ======

(defmacro +test-awa--persp (&rest body)
  "BODY with persp-mode on, in its workspace \"main\"; off after."
  (declare (indent 0))
  `(let ((persp-auto-save-opt 0)
         (persp-auto-resume-time -1)
         (persp-save-dir (file-name-as-directory (+test-tmp-file "persp"))))
     (persp-mode 1)
     (persp-add-new "main")
     (persp-frame-switch "main")
     (unwind-protect (progn ,@body)
       (persp-mode -1))))

(ert-deftest agent-workspace-app/its-own-workspace ()
  "SPC o w: the crew's own workspace, made; q back to the one you came from
\(the crew on, its tally there); its workspace killed however (SPC TAB d):
the crew closes, its agents exit, its buffers go."
  (+test-awa "persp"
    (+test-awa--persp
      (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
        (agent-workspace-open)
        (should (equal (safe-persp-name (get-current-persp)) "crew · persp"))
        (should (memq (agent-workspace-agent-buffer ada) (persp-buffers (get-current-persp))))
        (agent-workspace-leave)
        (should (equal (safe-persp-name (get-current-persp)) "main"))
        (should (string-match-p "crew · persp" (agent-workspace--tally-mode-line)))
        (agent-workspace-open)
        (should (equal (safe-persp-name (get-current-persp)) "crew · persp"))
        ;; Killed as SPC TAB d kills it.
        (persp-kill "crew · persp")
        (should-not (agent-workspace--app project))
        (should-not (agent-workspace-agents project))
        (should (eq (agent-workspace-agent-state ada) 'home))
        (should-not (get-buffer "*issues · persp*"))
        (should-not (persp-get-by-name "crew · persp" *persp-hash* nil))))))

(ert-deftest agent-workspace-app/quit-leaves-no-process ()
  "Q with real (stand-in) agents, one working: no question, every agent
exits, none of their processes left; back in the workspace you came from."
  (+test-with-reset
    (let* ((project (+test-awa--project "quit"))
           (default-directory project)
           (agent-workspace-exit-timeout 1)
           (log (expand-file-name "awa/quit.log" +test-tmp))
           (process-environment (cons (concat "MOCK_ACP_LOG=" log) process-environment)))
      (ignore-errors (delete-file log))
      (set-frame-size (selected-frame) 160 40)
      (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                ((symbol-function 'y-or-n-p) (lambda (&rest args) (error "Asked: %S" args))))
        (+test-awa--persp
          (let* ((ada (agent-workspace-create :role "builder" :name "ada" :kind 'mock))
                 (ken (agent-workspace-create :role "builder" :name "ken" :kind 'mock)))
            (let ((end (+ (float-time) 20)))
              (while (and (not (eq (agent-workspace-agent-state ken) 'desk)) (< (float-time) end))
                (accept-process-output nil 0.05)))
            (agent-workspace-open)
            (agent-workspace-send ada "hold" :submit t)
            (let ((end (+ (float-time) 10)))
              (while (and (not (eq (agent-workspace-agent-state ada) 'working)) (< (float-time) end))
                (accept-process-output nil 0.05)))
            (let ((pids (with-temp-buffer
                          (insert-file-contents log)
                          (cl-loop for line in (split-string (buffer-string) "\n" t)
                                   for entry = (json-parse-string line :object-type 'plist :null-object nil)
                                   when (plist-get entry :start)
                                   collect (plist-get (plist-get entry :start) :pid)))))
              (should (= (length pids) 2))
              (with-current-buffer (agent-workspace--issues-buffer project)
                (agent-workspace-quit))
              (should (equal (safe-persp-name (get-current-persp)) "main"))
              (should-not (persp-get-by-name "crew · quit" *persp-hash* nil))
              (should-not (agent-workspace-crews))
              (should-not (seq-some (lambda (agent) (buffer-live-p (agent-workspace-agent-buffer agent)))
                                    (list ada ken)))
              (let ((end (+ (float-time) 10)))
                (while (and (seq-some #'process-attributes pids) (< (float-time) end))
                  (accept-process-output nil 0.1)))
              (should-not (seq-some (lambda (pid)
                                      (when-let* ((attributes (process-attributes pid)))
                                        (not (member (alist-get 'state attributes) '("Z" "X")))))
                                    pids)))))))))

;; ====== NO TIMER WHILE HIDDEN ======

(ert-deftest agent-workspace-app/no-timer-while-hidden ()
  "The turns' times tick while the app is shown with an agent working, not
once it's left."
  (+test-awa "timer"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (agent-workspace-open t)
      (setf (agent-workspace-agent-since ada) (float-time)
            (agent-workspace-agent-state ada) 'working)
      (agent-workspace--tick)
      (should (timerp agent-workspace--timer))
      (agent-workspace-leave)
      (agent-workspace--tick)
      (should-not agent-workspace--timer))))
