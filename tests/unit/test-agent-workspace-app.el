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
;; The Beads panel's look: the issue list's types are drawn as it draws them.
(+test-load "config/beads/look")
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

(defun +test-awa--fastest (function &optional times)
  "The seconds FUNCTION takes, the fastest of TIMES (5) calls, no garbage
collected during them: the code's time, not a busy machine's (the other
test files running beside it, a collection that falls in it)."
  (let ((gc-cons-threshold most-positive-fixnum))
    (garbage-collect)
    (cl-loop repeat (or times 5)
             minimize (let ((start (float-time)))
                        (funcall function)
                        (- (float-time) start)))))

;; ====== THE LAYOUT ======

(ert-deftest agent-workspace-app/sizes ()
  "A stack's rows: every pane folded to a row but the open one, which takes
the rest; not enough rows to open it: all folded."
  (should (equal (agent-workspace--sizes '(a b c) 'b 20) '((a . 1) (b . 18) (c . 1))))
  (should (equal (agent-workspace--sizes '(a b c) nil 20) '((a . 1) (b . 1) (c . 1))))
  (should (equal (agent-workspace--sizes '(a b c) 'b 7) '((a . 1) (b . 1) (c . 1))))
  (should (equal (agent-workspace--sizes '(a b c) 'b 8) '((a . 1) (b . 6) (c . 1)))))

(ert-deftest agent-workspace-app/a-pane-s-header-kept ()
  "An open pane's header line, made at every redisplay of its window: made
once, then kept (no role read again, under 0.1 ms a time) until its agent
changes, a tick, a redraw (doom-pbk.70)."
  (+test-awa "header-kept"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (agent-workspace-open t)
      (let ((pane (get-buffer-window (agent-workspace-agent-buffer ada)))
            (reads 0))
        (cl-letf* ((role (symbol-function 'agent-workspace-role))
                   ((symbol-function 'agent-workspace-role)
                    (lambda (&rest args) (cl-incf reads) (apply role args))))
          (with-selected-window pane
            (let ((first (agent-workspace--pane-header)))
              (should (> reads 0))
              (setq reads 0)
              (should (< (+test-awa--fastest (lambda () (dotimes (_ 100) (agent-workspace--pane-header))))
                         0.01))
              (should (= reads 0))
              (should (eq (agent-workspace--pane-header) first))
              ;; Its agent changed: made again, saying it.
              (agent-workspace--set-state ada 'working)
              (let ((again (agent-workspace--pane-header)))
                (should (> reads 0))
                (should-not (eq again first))
                (should (string-search "building" (substring-no-properties again)))))))))))

(ert-deftest agent-workspace-app/a-gap-between-a-line-s-parts ()
  "In a terminal a line's left part ends a column or more before its right
part starts (at WIDTH less its width and 2: the border's and the $'s
columns), however long the left is (doom-pbk.84)."
  (should-not (agent-workspace--graphic-p))
  (let* ((right "[Allow (y)] [Reject (C-c C-c)]")
         (width 80)
         (line (agent-workspace--at-right (concat "▸ ▌S sam · ! wants to run " (make-string 80 ?x)) right width))
         (at (next-single-property-change 0 'display line))
         (starts (- width (+ 2 (string-width right)))))
    (should at)
    (should (<= (string-width (substring line 0 at)) (1- starts)))))

(ert-deftest agent-workspace-app/tinted-to-the-last-column ()
  "In a terminal an agent's bar and its pane's header line end in a stretch
to the window's right edge, in its tint: the tint reaches the last column
\(doom-pbk.88)."
  (+test-awa "tint-edge"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (should-not (agent-workspace--graphic-p))
      (dolist (line (list (agent-workspace-line ada 80 nil t) (agent-workspace-line ada 80 t nil)))
        (let ((last (1- (length line))))
          (should (equal (get-text-property last 'display line) '(space :align-to right)))
          (should (seq-some (lambda (face) (and (consp face) (plist-get face :background)))
                            (let ((face (get-text-property last 'face line)))
                              (if (and (consp face) (keywordp (car face))) (list face) (ensure-list face))))))))))

(ert-deftest agent-workspace-app/keys-on-a-bar ()
  "On an agent's bar, from the keyboard: the bar's keys (j/k between agents,
TAB, RET) and the app's (c, i, K...) act, its line's map adding its clicks
over them, never in their place; a header line's line keeps its clicks
(doom-pbk.82)."
  (+test-awa "bar-keys"
    (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
      (agent-workspace-open t)
      (agent-workspace-select ada)
      (let ((bar (get-buffer-window (agent-workspace--bar-buffer ken))))
        (should bar)
        (with-selected-window bar
          (goto-char (+ (point-min) 4))
          (should (get-text-property (point) 'keymap))
          ;; The bar's own keys at its line, under its clicks (Evil's
          ;; states, or none).
          (should (memq agent-workspace-bar-mode-map (current-active-maps nil (point))))
          (should (eq (key-binding (kbd "j") nil nil (point)) #'agent-workspace-next))
          (should (eq (key-binding (kbd "k") nil nil (point)) #'agent-workspace-previous))
          (should (eq (key-binding (kbd "TAB") nil nil (point)) #'agent-workspace-toggle))
          (should (eq (key-binding (kbd "RET") nil nil (point)) #'agent-workspace-go))
          (should (eq (key-binding (kbd "K") nil nil (point)) (lookup-key agent-workspace-bar-mode-map (kbd "K"))))
          (should (lookup-key agent-workspace-bar-mode-map (kbd "K")))
          ;; Its clicks.
          (should (eq (key-binding [mouse-1] nil nil (point)) #'agent-workspace-line-click))
          ;; TAB on ken's bar: his pane opens.
          (call-interactively (key-binding (kbd "TAB") nil nil (point))))
        (should (get-buffer-window (agent-workspace-agent-buffer ken))))
      ;; A pane's header line: its clicks there.
      (with-selected-window (get-buffer-window (agent-workspace-agent-buffer ken))
        (let ((header (agent-workspace--pane-header)))
          (should (eq (lookup-key (get-text-property 3 'local-map header) [header-line mouse-1])
                      #'agent-workspace-line-click)))))))

(ert-deftest agent-workspace-app/no-tint-in-256-colours ()
  "In a 256-colour terminal, no agent's colour blended behind its bar, its
header or a raised hand's (they came out in wrong hues, dim text on them
unreadable); with more colours (24-bit, the GUI), tinted as before
\(doom-pbk.80)."
  (+test-awa "colours"
    (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
      (agent-workspace--raise-hand ken '(:kind question :title "Which one?"))
      (cl-flet ((backgrounds (text)
                  (let (found)
                    (dotimes (i (length text))
                      (let ((face (get-text-property i 'face text)))
                        (dolist (f (if (and (consp face) (keywordp (car face))) (list face) (ensure-list face)))
                          (when-let* (((consp f)) (bg (plist-get f :background)))
                            (cl-pushnew bg found :test #'equal)))))
                    found)))
        (cl-letf (((symbol-function 'display-color-cells) (lambda (&rest _) 256)))
          (should-not (backgrounds (agent-workspace-line ada 80 nil t)))
          (should-not (backgrounds (agent-workspace-line ada 80 t nil)))
          (should-not (backgrounds (agent-workspace-line ken 80 nil t))))
        (cl-letf (((symbol-function 'display-color-cells) (lambda (&rest _) 16777216)))
          (should (backgrounds (agent-workspace-line ada 80 nil t)))
          (should (backgrounds (agent-workspace-line ken 80 nil t))))))))

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

(ert-deftest agent-workspace-app/its-context-used ()
  "An agent's context used on its line, first on its right side (before its
mode and model): a whole percentage in agent-shell's colour for it (green
under 60%, yellow from 60%, red from 85%), its tokens and cost on hover
(kept as it's made clickable, its colour in a header line); its pane's
header line and its bar alike, under 90 columns too. Nothing, no gap,
before its session says."
  (let* ((buffer (generate-new-buffer " *ada's session*"))
         (agent (agent-workspace--make-agent :name "ada" :role "builder" :colour "cyan" :state 'desk
                                             :project "/tmp/awa-usage/" :buffer buffer))
         (agent-workspace-role-function (lambda (_project name) (list :name name :model "opus")))
         (usage (lambda (used size)
                  (with-current-buffer buffer
                    (setq-local agent-shell--state
                                `((:usage . ((:context-used . ,used) (:context-size . ,size)
                                             (:input-tokens . 1200) (:output-tokens . 300)
                                             (:cost-amount . 0.42)))))))))
    (unwind-protect
        (let ((none (substring-no-properties (agent-workspace-line agent 120))))
          ;; None yet (no state, then nothing used): nothing, no gap.
          (should-not (string-search "%" none))
          (funcall usage 0 0)
          (should (equal (substring-no-properties (agent-workspace-line agent 120)) none))
          ;; 204k of 1m: 20%, first on its right side.
          (funcall usage 204000 1000000)
          (let* ((line (agent-workspace-line agent 120))
                 (at (string-search "20%" line)))
            (should (string-match-p "at the desk +20%  [^ ]" (substring-no-properties line)))
            (should (< at (string-search "opus" line)))
            (should (memq 'agent-shell-success (ensure-list (get-text-property at 'face line))))
            (let ((hover (get-text-property at 'help-echo line)))
              (should (string-search "Context: 204k/1m (20.4%)" hover))
              (should (string-search "$0.42" hover)))
            ;; Made clickable, its hover kept; elsewhere the line's.
            (let ((clickable (agent-workspace--clickable line agent-workspace-line-map)))
              (should (equal (get-text-property at 'help-echo clickable) (get-text-property at 'help-echo line)))
              (should (string-prefix-p "Select this agent" (get-text-property 2 'help-echo clickable)))
              ;; In a header line: its % doubled, as itself (its colour).
              (let* ((header (agent-workspace--percent-escaped clickable))
                     (percent (+ at 2)))
                (should (equal (substring-no-properties header percent (+ percent 2)) "%%"))
                (should (memq 'agent-shell-success (ensure-list (get-text-property (1+ percent) 'face header))))
                (should (get-text-property (1+ percent) 'help-echo header)))))
          ;; Its bar, and under 90 columns.
          (should (string-search "20%" (agent-workspace-line agent 120 nil t)))
          (should (string-search "20%" (agent-workspace-line agent 80)))
          (should (string-search "20%" (agent-workspace-line agent 80 nil t)))
          ;; Its colours: agent-shell's levels.
          (pcase-dolist (`(,used . ,face) '((590000 . agent-shell-success) (599999 . agent-shell-success)
                                            (600000 . agent-shell-warning) (849999 . agent-shell-warning)
                                            (850000 . agent-shell-error) (1000000 . agent-shell-error)))
            (funcall usage used 1000000)
            (let* ((line (agent-workspace-line agent 120))
                   (text (format "%d%%" (/ used 10000))))
              (should (string-search text line))
              (should (memq face (ensure-list (get-text-property (string-search text line) 'face line)))))))
      (kill-buffer buffer))))

(ert-deftest agent-workspace-app/its-context-drawn-again ()
  "Its session's usage updates and its turn's end draw its line again (a
change said to the hooks), nothing else; not an old session's."
  (let* ((buffer (generate-new-buffer " *ada's session*"))
         (agent (agent-workspace--make-agent :name "ada" :role "builder" :colour "cyan" :buffer buffer))
         (on-event nil)
         (changed nil)
         (agent-workspace-change-functions (list (lambda (_agent what) (push what changed)))))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                     (lambda (&rest args) (setq on-event (plist-get args :on-event)))))
            (agent-workspace--usage-watch agent buffer))
          (dolist (event '(usage-update tool-call-update agent-message-chunk turn-complete))
            (funcall on-event `((:event . ,event))))
          (should (equal changed '(usage usage)))
          (setq changed nil)
          (setf (agent-workspace-agent-buffer agent) (generate-new-buffer " *ada's next session*"))
          (funcall on-event '((:event . usage-update)))
          (should-not changed)
          (kill-buffer (agent-workspace-agent-buffer agent)))
      (kill-buffer buffer))))

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

(defvar +popup--display-buffer-alist)
(defvar +popup--old-display-buffer-alist)

(ert-deftest agent-workspace-app/a-file-shown-elsewhere-with-doom-popups ()
  "With Doom's popups on, a file shown from the app still goes where you came
from, the app left, the crew going on: from the issue list, a link in an
agent's session, find-file in its pane (its rule lost, it went in a bar a
row high, or over the agent's session)."
  (+test-with-doom-popups
    (dolist (open (list (lambda (file _pane issues)
                          (with-current-buffer issues
                            (pop-to-buffer file)))
                        (lambda (file pane _issues)
                          (with-selected-window pane
                            (funcall agent-shell-markdown-open-file-function (buffer-file-name file))))
                        (lambda (file pane _issues)
                          (select-window pane)
                          (find-file (buffer-file-name file)))))
      (+test-awa "elsewhere"
        (pcase-let ((`(,ada ,_ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
          (switch-to-buffer (get-buffer-create "mine"))
          (agent-workspace-open t)
          (let ((file (find-file-noselect (expand-file-name "README" project)))
                (session (agent-workspace-agent-buffer ada)))
            (funcall open file (get-buffer-window session) (agent-workspace--issues-buffer project))
            (should-not (agent-workspace-frame-p))
            (should (equal (mapcar #'car (+test-awa--windows)) '("README")))
            (should-not (get-buffer-window session))
            (should (agent-workspace-agents project))))))))

(ert-deftest agent-workspace-app/display-rule-under-doom-popups ()
  "The app's display rule is in `display-buffer-alist' with Doom's popups on,
whichever came first: the app loaded before them (here), before popup mode
turned on (as in Doom), or with it on (loaded again); a popup rule set (Doom's
rules put back in the list) keeps it, popup mode turned off and on too."
  (cl-flet ((in-effect-p ()
              (and (member agent-workspace--display-rule display-buffer-alist) t))
            (dropped ()
              ;; Out of every list, as before the app loaded.
              (dolist (var '(display-buffer-alist +popup--display-buffer-alist
                                                  +popup--old-display-buffer-alist))
                (set var (remove agent-workspace--display-rule (symbol-value var)))))
            (loaded ()
              ;; As config/agent-workspace.el loads it: app.el adds the rule,
              ;; doom.el keeps it.
              (add-to-list 'display-buffer-alist agent-workspace--display-rule)
              (+test-load "config/agent-workspace/doom"))
            (a-popup-rule ()
              ;; A package loading sets one: Doom's rules put back in the list.
              (set-popup-rule! "^\\*test-awa-popup\\*" :size 0.3)
              (should (eq display-buffer-alist +popup--display-buffer-alist))))
    (+test-with-doom-popups
      (let ((rules +popup--display-buffer-alist))
        (unwind-protect
            (progn
              ;; This file loaded the app before Doom's popups.
              (should (in-effect-p))
              (a-popup-rule)
              (should (in-effect-p))
              (+popup-mode -1)
              (should (in-effect-p))
              (+popup-mode 1)
              (should (in-effect-p))
              ;; The same again, from scratch: the rule in the list alone (as
              ;; app.el adds it, Doom's popups not loaded), popup mode on after.
              (+popup-mode -1)
              (dropped)
              (add-to-list 'display-buffer-alist agent-workspace--display-rule)
              (+popup-mode 1)
              (should (in-effect-p))
              (a-popup-rule)
              (should (in-effect-p))
              ;; Loaded with Doom's popups loaded, before popup mode turned on
              ;; (as in Doom).
              (+popup-mode -1)
              (dropped)
              (loaded)
              (+popup-mode 1)
              (should (in-effect-p))
              (a-popup-rule)
              (should (in-effect-p))
              ;; Loaded with popup mode on.
              (dropped)
              (loaded)
              (should (in-effect-p))
              (a-popup-rule)
              (should (in-effect-p))
              (+popup-mode -1)
              (should (in-effect-p))
              (+popup-mode 1)
              (should (in-effect-p)))
          (setq +popup--display-buffer-alist rules
                display-buffer-alist rules)
          (+my/agent-workspace--keep-display-rule))))))

;; ====== A % IN A HEADER OR MODE LINE ======

(ert-deftest agent-workspace-app/a-percent-keeps-its-face ()
  "A % in a header or mode line's text, doubled there (else it starts a
%-construct), keeps its face, hover and keys: the issue list's header (its
project's name, dimmed), the tally in other workspaces' mode lines (its
click). (A role's name can't have one: its file is left out.)"
  (should (equal-including-properties
           (agent-workspace--percent-escaped (concat "a " (propertize "20%" 'face 'error 'help-echo "used") " b%"))
           (concat "a " (propertize "20%%" 'face 'error 'help-echo "used") " b%%")))
  (+test-awa "50%-off"
    (let ((default-directory project))
      (make-directory ".agent-workspace/roles" t)
      (write-region "---\ndescription: checks\n---\nCheck.\n" nil ".agent-workspace/roles/qa.md"))
    (let ((_ken (agent-workspace-create :role "qa" :name "ken")))
      (agent-workspace-open t)
      (cl-flet ((both (text part prop value)
                  ;; Each % of PART in TEXT, doubled, has PROP's VALUE.
                  (let ((at (string-search part text)))
                    (should at)
                    (dotimes (i (length part))
                      (when (eq (aref part i) ?%)
                        (should (equal (get-text-property (+ at i) prop text) value)))))))
        (with-selected-window (+test-awa--issues-window project)
          (both (agent-workspace--issues-header) "50%%-off" 'face 'shadow))
        ;; Its tally, elsewhere: a click goes back.
        (agent-workspace-leave t)
        (both (agent-workspace--tally-mode-line) "50%%-off" 'local-map agent-workspace-tally-map)
        (both (agent-workspace--tally-mode-line) "50%%-off" 'help-echo "The crew: click to go there")))))

;; ====== A WINDOW NOT ITS OWN: A POPUP ======

(defun +test-awa--relayouts ()
  "The app's layouts waiting (after a border dragged, a popup gone), run now
as their 0.2 s would: how many there were."
  (let ((timers (seq-filter (lambda (timer) (eq (timer--function timer) #'agent-workspace--relayout))
                            timer-list)))
    (dolist (timer timers)
      (cancel-timer timer)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +test-awa--issues-window (project)
  "PROJECT's issue list's window."
  (get-buffer-window (agent-workspace--issues-buffer project)))

(ert-deftest agent-workspace-app/a-window-not-its-own ()
  "A side window not the app's appearing (a popup) is no resize: nothing
laid out, it stays; laid out again (gr), the app keeps it, its own windows
in the room it leaves; a border dragged with it open still lays the app out
again, and it stays. Gone: its rows back to the app, laid out as before,
once."
  (+test-awa "others"
    (+test-awa--crew '("ada" "builder") '("ken" "builder"))
    (let* ((app (agent-workspace-open t))
           (laid-out (+test-awa--windows))
           (other (get-buffer-create "*other*"))
           (window (display-buffer-in-side-window other '((side . bottom) (window-height . 10)))))
      (should-not (agent-workspace--own-window-p window app))
      (should (seq-every-p (lambda (w) (agent-workspace--own-window-p w app))
                           (remq window (window-list nil 'nomini))))
      ;; Emacs gave it the app's rows: not a border dragged.
      (agent-workspace--resized-h (selected-frame))
      (should (= (+test-awa--relayouts) 0))
      (should-not (agent-workspace--app-resizes app))
      (should (eq (window-buffer window) other))
      ;; Laid out again: it's kept, the app above it.
      (agent-workspace-layout app)
      (should (window-live-p window))
      (should (eq (window-buffer window) other))
      (should (= (window-total-height window) 10))
      (should (equal (mapcar #'car (+test-awa--windows))
                     '("*issues · others*" "ada · builder" " *bar · ken · others*" "*other*")))
      (should (= (window-total-width (+test-awa--issues-window project)) 50))
      (should (= (window-total-height (+test-awa--issues-window project)) (- (+test-awa--height) 10)))
      ;; A border dragged with it open: laid out again, it stays.
      (window-resize (+test-awa--issues-window project) 6 t)
      (agent-workspace--resized-h (selected-frame))
      (should (= (+test-awa--relayouts) 1))
      (should (window-live-p window))
      (should (= (window-total-width (+test-awa--issues-window project)) 50))
      ;; Gone: laid out as before it came, once.
      (delete-window window)
      (agent-workspace--resized-h (selected-frame))
      (should (= (+test-awa--relayouts) 1))
      (should (equal (+test-awa--windows) laid-out))
      (agent-workspace--resized-h (selected-frame))
      (should (= (+test-awa--relayouts) 0)))))

(ert-deftest agent-workspace-app/a-drag-or-a-resize-laid-out-once-at-its-end ()
  "A border dragged (20 moves) or the frame widened (8 steps): one layout,
after the last change, for the final size: bars a row, the room on the
right once the frame is wide; a layout while the minibuffer is open done
once it closes (doom-pbk.68)."
  (+test-awa "drag"
    (+test-awa--crew '("ada" "builder") '("ken" "builder") '("sam" "investigator"))
    (set-frame-size (selected-frame) 142 40)
    (let ((app (agent-workspace-open t))
          (bars (lambda () (mapcar (lambda (name)
                                     (window-total-height (get-buffer-window (format " *bar · %s · drag*" name))))
                                   '("ken" "sam")))))
      (agent-workspace-layout app)
      ;; A drag: 20 moves of the issue list's border.
      (dotimes (_ 20)
        (ignore-errors (window-resize (+test-awa--issues-window project) 1 t))
        (agent-workspace--resized-h (selected-frame)))
      (should (= (+test-awa--relayouts) 1))
      (should (= (window-total-width (+test-awa--issues-window project)) 50))
      (should (equal (funcall bars) '(1 1)))
      ;; The frame widened in 8 steps: one layout, the room on the right.
      (dolist (width '(150 160 170 180 190 200 205 210))
        (set-frame-size (selected-frame) width 40)
        (agent-workspace--resized-h (selected-frame)))
      (should (= (+test-awa--relayouts) 1))
      (let ((room (get-buffer-window (agent-workspace--room-buffer project))))
        (should (= (window-total-height room) (- (window-total-height (frame-root-window)) 4)))
        (should (> (window-left-column room) 100)))
      (should (equal (funcall bars) '(1 1)))
      ;; While the minibuffer is open: done once it closes.
      (ignore-errors (window-resize (+test-awa--issues-window project) 3 t))
      (agent-workspace--resized-h (selected-frame))
      (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () (minibuffer-window))))
        (should (= (+test-awa--relayouts) 1))
        (should (= (window-total-width (+test-awa--issues-window project)) 53)))
      (should (= (+test-awa--relayouts) 1))
      (should (= (window-total-width (+test-awa--issues-window project)) 50)))))

(declare-function +popup/quit-window "ui/popup/+hacks")

(ert-deftest agent-workspace-app/doom-popups-stay ()
  "In the app, Doom's popups stay until closed: the *Messages* a click on
the echo area opens, help (C-h f), *Warnings*; through a layout (gr) too.
Closed (q), their rows go back to the app, laid out as before."
  (+test-with-doom-popups
    (+test-awa "popups"
      (+test-awa--crew '("ada" "builder"))
      (let ((app (agent-workspace-open t))
            (laid-out (+test-awa--windows)))
        (dolist (open (list (lambda () (view-echo-area-messages) "*Messages*")
                            (lambda () (describe-function 'car) "*Help*")
                            (lambda () (display-buffer (get-buffer-create "*Warnings*")) "*Warnings*")))
          (let* ((name (funcall open))
                 (popup (get-buffer-window name)))
            (should popup)
            (should (window-parameter popup 'popup))
            (should (eq (window-parameter popup 'window-side) 'bottom))
            ;; Its rows Emacs took: nothing laid out, it stays.
            (agent-workspace--resized-h (selected-frame))
            (should (= (+test-awa--relayouts) 0))
            (should (eq (get-buffer-window name) popup))
            ;; gr: it stays.
            (agent-workspace-layout app)
            (should (eq (get-buffer-window name) popup))
            ;; q: gone, the app as it was.
            (with-selected-window popup (+popup/quit-window))
            (should-not (window-live-p popup))
            (agent-workspace--resized-h (selected-frame))
            (should (= (+test-awa--relayouts) 1))
            (should (equal (+test-awa--windows) laid-out))))))))

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

(defun +test-awa--other-canvas-show (agent part element)
  "ELEMENT shown on AGENT's other canvas PART (--canvas PART), as its session
shows it: the canvas."
  (let* ((session (agent-workspace-agent-buffer agent))
         (canvas (agent-ui-canvas (agent-ui-sub-canvas (agent-ui--session-name session) part))))
    ;; Tied to its session as Agent UI ties an agent-shell session's.
    (with-current-buffer canvas
      (setq agent-ui--session-buffer session
            agent-ui--canvas-part part))
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

(defun +test-awa--due-timers ()
  "The timers due now run (and those they start for now), as Emacs runs
them, without waiting: a wait gives the batch frame its own size back."
  (dotimes (_ 5)
    (dolist (timer (copy-sequence timer-list))
      (when (and (memq timer timer-list) (time-less-p (timer--time timer) nil))
        (timer-event-handler timer)))))

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

(ert-deftest agent-workspace-app/other-canvases-as-tabs ()
  "An agent's other canvases (--canvas NAME) showing something: tabs of its
side area after its canvas, before its panels, named by their part, by
name; one showing something new picks its tab; a question there takes no
focus; v goes through them all, V shows one full size. Answered, the ask
canvas emptied and killed: its tab gone, the one shown before shown; its
last tab killed (q): the side area closes, nothing else shown there."
  (+test-awa "others"
    (let ((agent-ui-panel-trust-file (+test-tmp-file "awa-others-trust.eld")))
      (+test-awa--panels project "logs")
      (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
        (agent-workspace-open t)
        (agent-workspace-select ada)
        (let* ((canvas (+test-awa--canvas-show ada '(:type "text" :id "hello" :text "Hello")))
               (logs (+test-awa--open-panel ada "logs"))
               (tests (+test-awa--other-canvas-show ada "tests" '(:type "text" :id "t" :text "Tests")))
               (issues (get-buffer-window (agent-workspace--issues-buffer project))))
          (should (eq (window-buffer (+test-awa--side)) tests))
          (should (string-prefix-p " canvas │ tests │ logs" (+test-awa--header (+test-awa--side))))
          ;; A question on ask: its tab picked, before tests; the cursor
          ;; stays where it was.
          (select-window issues)
          (let ((ask (+test-awa--other-canvas-show ada "ask" '(:type "confirm" :id "q1" :question "Push?"))))
            (should (eq (window-buffer (+test-awa--side)) ask))
            (should (string-prefix-p " canvas │ ask │ tests │ logs" (+test-awa--header (+test-awa--side))))
            (should-not (buffer-local-value 'agent-ui-focus-questions ask))
            (+test-awa--due-timers)
            (should (eq (selected-window) issues))
            (should (equal (mapcar #'car (+test-awa--windows))
                           '("*issues · others*" "ada · builder" "Agent UI: ada · builder / ask" " *bar · ken · others*")))
            ;; v: each in turn, wrapping.
            (+test-awa--in (+test-awa--side) (agent-workspace-panels-here))
            (should (eq (window-buffer) tests))
            (+test-awa--in (selected-window) (agent-workspace-panels-here))
            (should (eq (window-buffer) logs))
            (+test-awa--in (selected-window) (agent-workspace-panels-here))
            (should (eq (window-buffer) canvas))
            (+test-awa--in (selected-window) (agent-workspace-panels-here))
            (should (eq (window-buffer) ask))
            ;; V: full size, the tabs at its line's right; V again: back.
            (+test-awa--in (selected-window) (agent-workspace-full-here))
            (should (eq (window-buffer) ask))
            (should-not (get-buffer-window (agent-workspace-agent-buffer ada)))
            (should (string-match-p "canvas │ ask │ tests │ logs *\\'" (+test-awa--header (selected-window))))
            (+test-awa--in (selected-window) (agent-workspace-full-here))
            (should (get-buffer-window (agent-workspace-agent-buffer ada)))
            ;; Something new on tests, hidden: its tab shown; then ask again.
            (agent-ui-show '(:type "text" :id "t2" :text "More") :canvas tests)
            (should (eq (window-buffer (+test-awa--side)) tests))
            (agent-workspace--side-show ada ask)
            (should (eq (window-buffer) ask))
            ;; Answered (its button's answer): the question leaves its canvas,
            ;; emptied it's killed, its tab gone: the one shown before shown.
            (agent-ui-update "q1" '(:answered "proceed") :canvas ask)
            (+test-awa--due-timers)
            (should-not (buffer-live-p ask))
            (should (equal (mapcar #'car (+test-awa--windows))
                           '("*issues · others*" "ada · builder" "Agent UI: ada · builder / tests" " *bar · ken · others*")))
            (should (string-prefix-p " canvas │ tests │ logs" (+test-awa--header (+test-awa--side))))))
        ;; ken's only tab, an ask canvas: answered, its side area closes,
        ;; its session alone in its pane.
        (agent-workspace-select ken)
        (let ((ask (+test-awa--other-canvas-show ken "ask" '(:type "confirm" :id "q2" :question "Deploy?"))))
          (should (eq (window-buffer (+test-awa--side)) ask))
          (should (string-prefix-p " ask" (+test-awa--header (+test-awa--side))))
          ;; q in it, full size: the same.
          (+test-awa--in (+test-awa--side) (agent-workspace-full-here))
          (+test-awa--in (selected-window) (kill-current-buffer))
          (+test-awa--due-timers)
          (should (equal (mapcar #'car (+test-awa--windows))
                         '("*issues · others*" " *bar · ada · others*" "ken · builder"))))))))

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
        (should (eq (agent-workspace-issues-ready project) 'none))
        (setq agent-workspace--issues-data (agent-workspace--issues-parse project +test-awa--bd))
        (agent-workspace--issues-redraw project)
        ;; The ready ones as fetched, each its role's: the role picker counts
        ;; them (new.el).
        (should (equal (mapcar (lambda (issue) (list (plist-get issue :id) (plist-get issue :role)))
                               (agent-workspace-issues-ready project))
                       '(("p-2" "builder") ("p-3" "investigator") ("p-4" nil))))
        (should (string-search "  build ·1 ready  "
                               (nth 3 (assoc "builder" (agent-workspace--role-rows
                                                        (agent-workspace--role-facts project '("builder")) 200)))))
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (dolist (part '(" IN PROGRESS" " ▌A · p-1 Fix the parser" " READY" "builders  1" "p-2 Build the lexer, a"
                          "investigators  1" "nobody in the crew takes these" "p-3 Why does it crash"
                          "for any role  1" "p-4 Docs" " BLOCKED" "p-5 Release" "⊘ p-2" " DONE TODAY" "p-0 Set up"))
            (should (string-search part text)))
          (should-not (string-search "The epic" text))
          ;; The long title's second row, under its title.
          (should (string-match-p "\n +[a-z ]*two rows in a column" text)))
        ;; Its agent on its issue in progress; the cursor follows the selection.
        (goto-char (point-min))
        (should (agent-workspace--issues-goto-agent ada))
        (should (eq (agent-workspace--issues-agent-at) ada))
        ;; j goes issue by issue, a two-row issue one.
        (agent-workspace-issue-next)
        (should (equal (plist-get (get-text-property (point) 'agent-workspace-issue) :id) "p-2"))
        (agent-workspace-issue-next)
        (should (equal (plist-get (get-text-property (point) 'agent-workspace-issue) :id) "p-3"))))))

(ert-deftest agent-workspace-app/a-title-of-wide-characters ()
  "A title of wide characters without spaces (CJK) wraps onto two rows, cut
by columns, never past its end; the issue list drawn and the app laid out
at 35, 50 and 80 columns (doom-pbk.42)."
  (let ((title "修复解析器的错误处理问题在边界"))
    (should (equal (agent-workspace--wrap-title title 20 30) '("修复解析器的错误处理" "问题在边界")))
    (should (equal (agent-workspace--wrap-title title 21 30) '("修复解析器的错误处理" "问题在边界")))
    (should (equal (agent-workspace--wrap-title title 20 6) '("修复解析器的错误处理" "问题…")))
    ;; Words of wide characters: cut at a space, by columns.
    (should (equal (agent-workspace--wrap-title "修复 解析器的错误 处理问题" 17 30)
                   '("修复 解析器的错误" "处理问题")))
    (should (equal (agent-workspace--wrap-title "Fix the parser's recovery" 10 30) '("Fix the" "parser's recovery"))))
  (+test-awa "wide"
    (+test-awa--crew '("ada" "builder"))
    (let ((data (list :all (json-parse-string
                            "[{\"id\":\"w-1\",\"title\":\"修复解析器的错误处理问题在边界情况下的崩溃\",\"status\":\"open\",\"priority\":1,\"labels\":[\"build\"]}]"
                            :object-type 'alist :array-type 'list)
                      :ready (json-parse-string "[{\"id\":\"w-1\"}]" :object-type 'alist :array-type 'list)
                      :done nil)))
      (dolist (width '(35 50 80))
        (let ((agent-workspace-issues-width width))
          (agent-workspace-open t)
          (with-current-buffer (agent-workspace--issues-buffer project)
            (setq agent-workspace--issues-data (agent-workspace--issues-parse project data))
            (agent-workspace--issues-redraw project)
            (agent-workspace-layout (agent-workspace--app project))
            (let ((rows (seq-filter (lambda (line) (string-match-p "[修复问题情况崩溃]" line))
                                    (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n"))))
              (should (<= 1 (length rows) 2))
              (should (string-search "修复" (car rows)))
              (dolist (row rows)
                (should (<= (string-width row) (window-width (get-buffer-window (current-buffer))))))))
          (agent-workspace--close-app project))))))

(ert-deftest agent-workspace-app/the-issues-redrawn-the-cursor-stays ()
  "The issue list drawn again (an agent's state changing, a fetch): the
cursor where it was in its issue (its line and column, a second row too),
a region kept, still active (doom-pbk.49)."
  (+test-awa "cursor-stays"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (agent-workspace-open t)
      (let* ((buffer (agent-workspace--issues-buffer project))
             (window (get-buffer-window buffer)))
        (with-current-buffer buffer
          (setq agent-workspace--issues-data (agent-workspace--issues-parse project +test-awa--bd))
          (agent-workspace--issues-redraw project))
        (with-selected-window window
          ;; In p-2's second row, mid-word; the mark in p-3's title.
          (goto-char (point-min))
          (search-forward "two rows")
          (backward-char 3)
          (let ((line (line-number-at-pos)) (column (current-column)))
            (save-excursion
              (goto-char (point-min))
              (search-forward "Why does")
              (set-mark (point)))
            (activate-mark)
            (let ((mark-line (line-number-at-pos (mark))) (mark-column (save-excursion (goto-char (mark)) (current-column)))
                  (deactivate-mark nil))
              (setf (agent-workspace-agent-state ada) 'working)
              (agent-workspace--issues-redraw project)
              (should (= (line-number-at-pos (window-point window)) line))
              (should (= (save-excursion (goto-char (window-point window)) (current-column)) column))
              (should (= (line-number-at-pos (mark)) mark-line))
              (should (= (save-excursion (goto-char (mark)) (current-column)) mark-column))
              (should mark-active)
              (should-not deactivate-mark))))))))

(defconst +test-awa--typed
  (list :all (json-parse-string
              "[{\"id\":\"t-1\",\"title\":\"Fix the parser\",\"status\":\"in_progress\",\"assignee\":\"ada\",\"issue_type\":\"bug\"},
                {\"id\":\"t-2\",\"title\":\"Sparkles, a title long enough to need two rows in a column fifty wide\",\"status\":\"open\",\"priority\":1,\"issue_type\":\"feature\"},
                {\"id\":\"t-3\",\"title\":\"A task\",\"status\":\"open\",\"priority\":2,\"issue_type\":\"task\"},
                {\"id\":\"t-4\",\"title\":\"A chore\",\"status\":\"open\",\"priority\":2,\"issue_type\":\"chore\"},
                {\"id\":\"t-5\",\"title\":\"A decision\",\"status\":\"open\",\"priority\":2,\"issue_type\":\"decision\"},
                {\"id\":\"t-6\",\"title\":\"A custom type\",\"status\":\"open\",\"priority\":3,\"issue_type\":\"spike\"},
                {\"id\":\"t-7\",\"title\":\"No type\",\"status\":\"open\",\"priority\":3},
                {\"id\":\"t-8\",\"title\":\"Blocked\",\"status\":\"open\",\"issue_type\":\"bug\",\"dependencies\":[{\"depends_on_id\":\"t-3\",\"type\":\"blocks\"}]}]"
              :object-type 'alist :array-type 'list)
        :ready (json-parse-string "[{\"id\":\"t-2\"},{\"id\":\"t-3\"},{\"id\":\"t-4\"},{\"id\":\"t-5\"},{\"id\":\"t-6\"},{\"id\":\"t-7\"}]"
                                  :object-type 'alist :array-type 'list)
        :done (json-parse-string "[{\"id\":\"t-0\",\"title\":\"Set up\",\"status\":\"closed\",\"issue_type\":\"task\",\"assignee\":\"ada\",\"closed_at\":\"2026-01-01T10:00:00Z\"}]"
                                 :object-type 'alist :array-type 'list))
  "What bd answers, issues of every type, for the type column's tests.")

(defun +test-awa--rows (project data)
  "PROJECT's issue list's rows from bd's answers DATA, as drawn 49 columns
wide: (ID . FIRST-ROW) each, its first row (its type at column 4), in order."
  (let ((rows nil))
    (dolist (line (agent-workspace--issues-lines project (agent-workspace--issues-parse project data) 49))
      (when-let* ((issue (get-text-property 0 'agent-workspace-issue line))
                  ((not (assoc (plist-get issue :id) rows))))
        (push (cons (plist-get issue :id) line) rows)))
    (nreverse rows)))

(defun +test-awa--type-at (row)
  "ROW's type column: (GLYPH FACE HELP)."
  (list (substring-no-properties row 4 5) (get-text-property 4 'face row) (get-text-property 4 'help-echo row)))

(ert-deftest agent-workspace-app/the-issues-types ()
  "Each issue's type before its id, a column of its own lined up from row to
row, in every section: in a terminal its first letter in the Beads panel's
colour (config/beads/look.el's, read there), its word on hover; a type with
no look, or none, a dim ·, the column kept; done today's dimmed. A long
title's second row starts under its title."
  (+test-awa "types"
    (+test-awa--crew '("ada" "builder"))
    (agent-workspace-open t)
    (let ((rows (+test-awa--rows project +test-awa--typed)))
      (should (equal (mapcar #'car rows) '("t-1" "t-2" "t-3" "t-4" "t-5" "t-6" "t-7" "t-8" "t-0")))
      ;; Lined up: the avatar's 2 columns (or none), the type, its id.
      (pcase-dolist (`(,id . ,row) rows)
        (should (string-prefix-p (concat " " (substring-no-properties row 1 3) " " (substring-no-properties row 4 5)
                                         " " id " ")
                                 (substring-no-properties row))))
      (should (string-prefix-p " ▌A b t-1 Fix the parser" (substring-no-properties (cdr (assoc "t-1" rows)))))
      (should (equal (mapcar (lambda (row) (+test-awa--type-at (cdr row))) rows)
                     '(("b" error "bug") ("f" success "feature") ("t" font-lock-function-name-face "task")
                       ("c" shadow "chore") ("d" font-lock-type-face "decision")
                       ("·" shadow "spike") ("·" shadow nil)
                       ("b" error "bug") ("t" shadow "task"))))
      ;; Read from the Beads panel's look: its change is the list's.
      (let ((+my/beads--types-look '(("bug" "nf-cod-debug" warning))))
        (should (equal (+test-awa--type-at (cdr (assoc "t-1" (+test-awa--rows project +test-awa--typed))))
                       '("b" warning "bug")))
        (should (equal (+test-awa--type-at (cdr (assoc "t-2" (+test-awa--rows project +test-awa--typed))))
                       '("·" shadow "feature"))))
      ;; Without it (no Doom): a dim · each, the column kept.
      (let ((+my/beads--types-look nil))
        (should (string-prefix-p " ▌A · t-1 Fix the parser"
                                 (substring-no-properties (cdr (assoc "t-1" (+test-awa--rows project +test-awa--typed))))))))
    ;; The long title's second row, under its title.
    (let* ((lines (agent-workspace--issues-lines project (agent-workspace--issues-parse project +test-awa--typed) 49))
           (first (seq-find (lambda (line) (string-search "t-2 Sparkles" line)) lines))
           (second (cadr (member first lines))))
      (should (equal (plist-get (get-text-property 0 'agent-workspace-issue second) :id) "t-2"))
      (should (string-match-p "\\` +[a-z ]*two rows in a column" second))
      (should (= (- (length second) (length (string-trim-left second)))
                 (string-search "Sparkles" first))))))

(ert-deftest agent-workspace-app/the-issues-types-in-the-gui ()
  "In the GUI, an issue's type is the Beads panel's icon, in its colour,
one column before its id; its word on hover; a type with no icon a dim ·."
  (+test-awa "types-gui"
    (+test-awa--crew '("ada" "builder"))
    (agent-workspace-open t)
    (skip-unless (require 'nerd-icons nil t))
    (cl-letf (((symbol-function 'agent-workspace--graphic-p) #'always)
              ;; Its font installed (batch Emacs has none).
              ((symbol-function 'agent-workspace--nerd-font-p) #'always))
      (let ((rows (+test-awa--rows project +test-awa--typed)))
        (pcase-dolist (`(,id ,icon ,face) '(("t-2" "nf-cod-sparkle" success) ("t-3" "nf-cod-checklist" font-lock-function-name-face)
                                           ("t-4" "nf-cod-tools" shadow) ("t-5" "nf-cod-law" font-lock-type-face)
                                           ("t-8" "nf-cod-bug" error) ("t-0" "nf-cod-checklist" shadow)))
          (let ((row (cdr (assoc id rows))))
            (should (equal (substring-no-properties row 4 5) (substring-no-properties (nerd-icons-codicon icon))))
            (should (memq face (ensure-list (get-text-property 4 'face row))))
            (should (string-prefix-p (concat " " id " ") (substring-no-properties row 5)))))
        (should (equal (+test-awa--type-at (cdr (assoc "t-6" rows))) '("·" shadow "spike")))
        (should (equal (get-text-property 4 'help-echo (cdr (assoc "t-8" rows))) "bug"))
        ;; The epic's icon, as the Beads panel's.
        (should (equal (substring-no-properties (agent-workspace-type-glyph "epic"))
                       (substring-no-properties (nerd-icons-codicon "nf-cod-milestone"))))))))

(ert-deftest agent-workspace-app/drawn-for-its-own-frame ()
  "A GUI frame and a terminal one on one Emacs: the app is drawn for the
frame of the window showing it, whichever is selected as it's redrawn (a
timer, a process): its issue list's types icons there, letters in the
terminal (doom-pbk.81)."
  (+test-awa "frames"
    (+test-awa--crew '("ada" "builder"))
    (agent-workspace-open t)
    (skip-unless (require 'nerd-icons nil t))
    (let* ((issues (agent-workspace--issues-buffer project))
           (list-window (get-buffer-window issues))
           (window-frame-real (symbol-function 'window-frame))
           (graphic-real (symbol-function 'display-graphic-p))
           (type-at (lambda (id)
                      (with-current-buffer issues
                        (agent-workspace--issues-goto-id id)
                        (buffer-substring-no-properties (+ (line-beginning-position) 4)
                                                        (+ (line-beginning-position) 5))))))
      (with-current-buffer issues
        (setq agent-workspace--issues-data (agent-workspace--issues-parse project +test-awa--typed)))
      ;; The issue list's window in a GUI frame, the selected one a terminal.
      (cl-letf (((symbol-function 'window-frame)
                 (lambda (&optional window)
                   (if (eq (or window (selected-window)) list-window) 'gui (funcall window-frame-real window))))
                ((symbol-function 'display-graphic-p)
                 (lambda (&optional frame) (if (eq frame 'gui) t (funcall graphic-real frame))))
                ((symbol-function 'agent-workspace--nerd-font-p) #'always))
        (should-not (display-graphic-p))
        (agent-workspace--issues-redraw project)
        (should (equal (funcall type-at "t-8") (substring-no-properties (nerd-icons-codicon "nf-cod-bug")))))
      ;; In the terminal, as it is: a letter.
      (agent-workspace--issues-redraw project)
      (should (equal (funcall type-at "t-8") "b")))))

(ert-deftest agent-workspace-app/no-nerd-font-plain-glyphs ()
  "In the GUI without the nerd icons' font (Linux's default): the plain
glyphs, as in a terminal (no box of a missing glyph), lined up as theirs
\(doom-pbk.76)."
  (skip-unless (require 'nerd-icons nil t))
  (let ((agent-workspace--nerd-font 'unknown)
        (asked nil))
    (cl-letf (((symbol-function 'agent-workspace--graphic-p) #'always)
              ((symbol-function 'find-font) (lambda (spec &rest _) (push (font-get spec :family) asked) nil)))
      (should (equal (substring-no-properties (agent-workspace-glyph 'hand))
                     (let ((agent-workspace--nerd-font nil))
                       (cl-letf (((symbol-function 'agent-workspace--graphic-p) #'ignore))
                         (substring-no-properties (agent-workspace-glyph 'hand))))))
      (should (= (string-width (agent-workspace-glyph 'hand)) 2))
      (should (equal (substring-no-properties (agent-workspace-type-glyph "bug")) "b"))
      ;; Looked for once.
      (agent-workspace-glyph 'done)
      (should (= (length asked) 1)))
    ;; With it: its icons.
    (let ((agent-workspace--nerd-font t))
      (cl-letf (((symbol-function 'agent-workspace--graphic-p) #'always))
        (should (equal (substring-no-properties (agent-workspace-type-glyph "bug"))
                       (substring-no-properties (nerd-icons-codicon "nf-cod-bug"))))))))

(defun +test-awa--bd-json (&rest issues)
  "ISSUES, plists of bd's fields, as bd's JSON answer reads."
  (mapcar (lambda (issue)
            (cl-loop for (key value) on issue by #'cddr
                     collect (cons (intern (substring (symbol-name key) 1)) value)))
          issues))

(defconst +test-awa--epics
  (list :all (+test-awa--bd-json
              '(:id "e-1" :title "Agent workspace: enhancements" :status "open" :issue_type "epic")
              '(:id "e-2" :title "Modules: each one used" :status "open" :issue_type "epic")
              '(:id "e-3" :title "Investigations" :status "open" :issue_type "epic")
              '(:id "e-4" :title "Nothing ready in it" :status "open" :issue_type "epic")
              '(:id "w-1" :title "On it" :status "in_progress" :assignee "ada" :issue_type "task" :parent "e-1"
                :labels ["build"])
              '(:id "b-1" :title "A bug, a title long enough to need two rows under its epic" :status "open"
                :priority 2 :issue_type "bug" :parent "e-1" :labels ["build"])
              '(:id "b-2" :title "Sparkles" :status "open" :priority 1 :issue_type "feature" :parent "e-2"
                :labels ["build"])
              '(:id "b-3" :title "Later" :status "open" :priority 3 :issue_type "task" :parent "e-1" :labels ["build"])
              '(:id "b-4" :title "A subtask" :status "open" :priority 2 :issue_type "task" :parent "w-1"
                :labels ["build"])
              '(:id "b-5" :title "Loose" :status "open" :priority 2 :issue_type "bug" :labels ["build"])
              '(:id "b-6" :title "Its epic closed" :status "open" :priority 2 :issue_type "bug" :parent "e-0"
                :labels ["build"])
              '(:id "i-1" :title "Why" :status "open" :priority 2 :issue_type "task" :parent "e-3"
                :labels ["investigation"])
              '(:id "a-1" :title "Docs" :status "open" :priority 2 :issue_type "chore")
              '(:id "x-1" :title "Waits" :status "open" :issue_type "task" :parent "e-4"
                :dependencies [((type . "blocks") (depends_on_id . "b-1"))]))
        :ready (+test-awa--bd-json '(:id "b-1") '(:id "b-2") '(:id "b-3") '(:id "b-4") '(:id "b-5") '(:id "b-6")
                                   '(:id "i-1") '(:id "a-1") '(:id "e-1"))
        :done (+test-awa--bd-json '(:id "d-1" :title "Set up" :status "closed" :issue_type "task" :parent "e-1"
                                         :assignee "ada" :closed_at "2026-01-01T10:00:00Z")))
  "What bd answers, issues of epics, for the epics' tests: e-2's issue a P1,
b-4 a subtask (of w-1, in progress, of e-1), b-6's epic closed, e-4 with
nothing ready.")

(defun +test-awa--text (lines)
  "LINES as text, each its right end trimmed."
  (mapcar (lambda (line) (string-trim-right (substring-no-properties line))) lines))

(ert-deftest agent-workspace-app/the-issues-by-epic ()
  "READY's role groups split by epic: each epic's heading (its icon, the
epic type's; its id; its title; how many of its issues the group has), its
issues under it 2 columns further in (their type column, their wrapped
second row too); epics by their first issue (a P1 brings one up), issues by
priority; a subtask under its nearest epic; none open, under \"no epic\",
last; a group with no epic as it was; an epic with nothing ready not shown.
IN PROGRESS, BLOCKED and DONE TODAY as they were. A narrow list cuts an
epic's title with …."
  (+test-awa "epics"
    (+test-awa--crew '("ada" "builder"))
    (agent-workspace-open t)
    (let* ((data (agent-workspace--issues-parse project +test-awa--epics))
           (lines (agent-workspace--issues-lines project data 49))
           (text (+test-awa--text lines)))
      (should (equal (seq-take (member " READY 8" text) 18)
                     '(" READY 8"
                       "  ⚙ builders  6"
                       "    e e-2 Modules: each one used 1"
                       "      f b-2 Sparkles P1"
                       "    e e-1 Agent workspace: enhancements 3"
                       "      b b-1 A bug, a title long enough to need"
                       "            two rows under its epic"
                       "      t b-4 A subtask"
                       "      t b-3 Later"
                       "    no epic 2"
                       "      b b-5 Loose"
                       "      b b-6 Its epic closed"
                       "  ⌕ investigators  1  nobody in the crew takes these"
                       "    e e-3 Investigations 1"
                       "      t i-1 Why"
                       "  for any role  1"
                       "    c a-1 Docs"
                       "")))
      ;; The rest as it was: no epic's heading, the type at column 4.
      (should (member " ▌A t w-1 On it ○" text))
      (should (member "    t x-1 Waits ⊘ b-1" text))
      (should (member " ▌A t d-1 Set up ada" (mapcar (lambda (line) (replace-regexp-in-string " [0-9]+h\\'" "" line)) text)))
      (should-not (seq-some (lambda (line) (string-search "e-4" line)) text))
      ;; A heading carries its epic and its role; the type's look, the epic's.
      (let ((heading (seq-find (lambda (line) (string-search "e-1 Agent" line)) lines)))
        (should (equal (get-text-property 0 'agent-workspace-epic heading) '(:id "e-1" :title "Agent workspace: enhancements")))
        (should (equal (get-text-property 0 'agent-workspace-role heading) "builder"))
        (should-not (get-text-property 0 'agent-workspace-issue heading))
        (should (equal (+test-awa--type-at heading) '("e" font-lock-constant-face "epic"))))
      ;; Narrow: the epic's title cut with ….
      (let ((narrow (+test-awa--text (agent-workspace--issues-lines project data 34))))
        ;; A column between it and its count (doom-pbk.84).
        (should (member "    e e-1 Agent workspace: e… 3" narrow))
        (should (member "  ⚙ builders  6" narrow))))))

(ert-deftest agent-workspace-app/an-epic-s-heading ()
  "On an epic's heading: j/k go from issue to issue over it, as over a
role's; RET opens the epic; t says it's an epic, nothing given; drawn
again, the cursor stays on it."
  (+test-awa "heading"
    (+test-awa--crew '("ada" "builder"))
    (agent-workspace-open t)
    (let ((opened nil) (sent nil))
      (with-current-buffer "*issues · heading*"
        (setq agent-workspace--issues-data (agent-workspace--issues-parse project +test-awa--epics))
        (agent-workspace--issues-redraw project)
        (cl-flet ((at () (plist-get (get-text-property (point) 'agent-workspace-issue) :id)))
          (agent-workspace--issues-goto-id "b-2")
          (agent-workspace-issue-next)
          (should (equal (at) "b-1"))
          (agent-workspace-issue-next 3)
          (should (equal (at) "b-5"))
          (agent-workspace-issue-previous 2)
          (should (equal (at) "b-4"))
          (agent-workspace-issue-previous 2)
          (should (equal (at) "b-2"))
          ;; On e-1's heading.
          (forward-line -1)
          (agent-workspace-issue-next)
          (should (equal (at) "b-2"))
          (forward-line 1)
          (should (equal (plist-get (get-text-property (point) 'agent-workspace-epic) :id) "e-1"))
          (let ((agent-workspace-open-issue-function (lambda (id dir) (push (list id dir) opened))))
            (agent-workspace-issue-open))
          (should (equal opened (list (list "e-1" (agent-workspace--root project)))))
          (cl-letf (((symbol-function 'agent-workspace-send) (lambda (&rest args) (push args sent))))
            (should (equal (cadr (should-error (agent-workspace-issue-give) :type 'user-error))
                           "e-1 is an epic: give one of its issues")))
          (should-not sent)
          (should-not (agent-workspace-agent-issue (car (agent-workspace-agents project))))
          ;; Drawn again: still on it.
          (agent-workspace--issues-redraw project)
          (should (equal (plist-get (get-text-property (point) 'agent-workspace-epic) :id) "e-1"))
          (should (equal (get-text-property (point) 'agent-workspace-role) "builder")))))))

(ert-deftest agent-workspace-app/giving-an-issue ()
  "t gives a ready issue to an agent (the selected one first): its worktree
on the issue's branch, then sent \"Work on ID: TITLE\" now, or after its
turn; noted as its. Its worktree with changes not committed: refused,
nothing sent."
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
            (should (equal (agent-workspace-agent-branch ada) "task/p-2-build-lexer-title-long"))
            ;; Changes there: refused, nothing sent, nothing given.
            (write-region "half\n" nil (expand-file-name "wip" (agent-workspace-agent-worktree ada)))
            (agent-workspace--issues-goto-id "p-3")
            (should-error (agent-workspace-issue-give) :type 'user-error)
            (should (= (length sent) 1))
            (should (equal (agent-workspace-agent-issue ada) "p-2"))
            ;; Not one in progress.
            (agent-workspace--issues-goto-id "p-1")
            (should-error (agent-workspace-issue-give) :type 'user-error)))))))

(ert-deftest agent-workspace-app/a-small-frame-leaves-the-minibuffer-room ()
  "In a frame 80x24 (a terminal's), the app laid out: its windows' least
height below the frame's, a bar's its one line, the stage's rows below the
bars theirs; the minibuffer grows (a prompt, vertico's list), the frame's
height as it was (doom-pbk.78)."
  (+test-awa "small"
    (+test-awa--crew '("ada" "builder") '("ken" "builder") '("sam" "investigator")
                     '("liz" "builder") '("tom" "builder"))
    (set-frame-size (selected-frame) 80 24)
    (agent-workspace-open t)
    (let ((height (frame-height)))
      (should (< (window-min-size (frame-root-window)) (window-total-height (frame-root-window))))
      (dolist (agent (agent-workspace-agents project))
        (when-let* ((bar (get-buffer-window (agent-workspace--bar-buffer agent))))
          (should (= (window-min-size bar) 1))))
      ;; Every pane folded: the rows below the bars, fewer than 4.
      (setf (agent-workspace--app-open (agent-workspace--app project)) nil)
      (agent-workspace-layout (agent-workspace--app project))
      (let ((hint (get-buffer-window (agent-workspace--hint-buffer project))))
        (should (= (window-min-size hint) 1)))
      (should (< (window-min-size (frame-root-window)) (window-total-height (frame-root-window))))
      (let ((before (window-total-height (frame-root-window))))
        (window-resize (minibuffer-window) 6)
        (should (= (window-total-height (minibuffer-window)) 7))
        (should (= (window-total-height (frame-root-window)) (- before 6)))
        (window-resize (minibuffer-window) -6))
      (should (= (frame-height) height)))))

(ert-deftest agent-workspace-app/at-80x24-a-pane-opens ()
  "In a frame 80x24 (a terminal's), three agents: the issue list 24 wide
\(the stage 56), the room at the bottom smaller, the stage keeping an open pane of
10 rows or more; another agent opened (TAB, a click): its pane, as tall;
the room alone (2) a key away. Lower still: no room at the bottom, the
pane bigger (doom-pbk.79)."
  (+test-awa "small-pane"
    (pcase-let ((`(,ada ,ken ,_sam) (+test-awa--crew '("ada" "builder") '("ken" "builder") '("sam" "investigator"))))
      (set-frame-size (selected-frame) 80 24)
      (let ((app (agent-workspace-open t)))
        (agent-workspace-layout app)
        (should (= (window-total-width (+test-awa--issues-window project)) 24))
        (let ((pane (get-buffer-window (agent-workspace-agent-buffer ada)))
              (room (get-buffer-window (agent-workspace--room-buffer project))))
          (should pane)
          (should (>= (window-body-height pane) 10))
          (should room)
          (should (get-buffer-window (agent-workspace--compose-buffer project))))
        ;; Another opened.
        (agent-workspace-select ken t)
        (let ((pane (get-buffer-window (agent-workspace-agent-buffer ken))))
          (should pane)
          (should (eq (selected-window) pane))
          (should (>= (window-body-height pane) 10)))
        ;; The room alone, a key away.
        (agent-workspace-view-room)
        (should (> (window-total-width (get-buffer-window (agent-workspace--room-buffer project))) 50))
        (agent-workspace-view-stage)
        ;; Lower: no room at the bottom.
        (set-frame-size (selected-frame) 80 18)
        (agent-workspace-layout app)
        (should-not (get-buffer-window (agent-workspace--room-buffer project)))
        (should (>= (window-body-height (get-buffer-window (agent-workspace-agent-buffer ken))) 10))))))

(ert-deftest agent-workspace-app/the-stage-away-the-cursor-stays ()
  "The stage not shown (the room alone, 2; the branches, b), the cursor in
the compose line or the branches: an agent's canvas showing something new
(Agent UI showing it, the canvas current), a panel, its session started
again, an agent made lay nothing out, the cursor where it was; a layout
with another buffer current (a resize's) keeps it there too. Back on the
stage, the canvas's tab is shown (doom-pbk.67)."
  (+test-awa "away"
    (pcase-let ((`(,ada) (+test-awa--crew '("ada" "builder"))))
      (let* ((app (agent-workspace-open t))
             (layouts 0)
             (count (lambda (&rest _) (cl-incf layouts)))
             (canvas nil))
        (advice-add 'agent-workspace-layout :before count)
        (unwind-protect
            (cl-flet ((changes (n)
                        ;; Shown on its canvas with the canvas current, as Agent UI does.
                        (with-current-buffer (or canvas (current-buffer))
                          (setq canvas (+test-awa--canvas-show ada (list :type "text" :id (format "t%d" n)
                                                                         :text "News"))))
                        (with-current-buffer canvas
                          (agent-workspace--changed ada 'panels)
                          (agent-workspace--changed ada 'session))))
              ;; The room alone, the cursor in the compose line.
              (agent-workspace-view-room)
              (let ((compose (get-buffer-window (agent-workspace--compose-buffer project))))
                (select-window compose)
                (setq layouts 0)
                (changes 1)
                (changes 2)
                (agent-workspace-create :role "builder" :name "ken")
                (should (= layouts 0))
                (should (eq (selected-window) compose))
                (should (eq (window-buffer) (agent-workspace--compose-buffer project)))
                ;; A layout with the canvas current: the cursor stays.
                (with-current-buffer canvas (agent-workspace-layout app))
                (should (eq (window-buffer) (agent-workspace--compose-buffer project))))
              ;; The branches in the stage's place, the cursor there.
              (agent-workspace-view-stage)
              (agent-workspace-branches)
              (let ((view (window-buffer)))
                (should (eq (agent-workspace--app-view app) 'branches))
                (setq layouts 0)
                (changes 3)
                (agent-workspace-create :role "builder" :name "liz")
                (should (= layouts 0))
                (should (eq (window-buffer) view))
                (with-current-buffer view (agent-workspace-branches-quit)))
              ;; The stage back: ada's pane open shows her canvas.
              (agent-workspace-select ada)
              (should (eq (agent-workspace--app-view app) 'stage))
              (should (get-buffer-window canvas)))
          (advice-remove 'agent-workspace-layout count))))))

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

(ert-deftest agent-workspace-app/a-tick-draws-only-the-times ()
  "While an agent works: a tick draws its bar's time again, not the issue
list nor every mode line; each second in a turn's first minute, then at
the next minute; with 100 issues, under 5 ms. A usage change draws its
lines only (doom-pbk.69)."
  (+test-awa "tick"
    (pcase-let ((`(,ada ,ken) (+test-awa--crew '("ada" "builder") '("ken" "builder"))))
      (agent-workspace-open t)
      (with-current-buffer (agent-workspace--issues-buffer project)
        (setq agent-workspace--issues-data
              (agent-workspace--issues-parse
               project
               (list :all (cl-loop for i from 1 to 100
                                   collect `((id . ,(format "p-%d" i)) (title . ,(format "Issue number %d, a title" i))
                                             (status . "open") (priority . 2) (labels "build")))
                     :ready (cl-loop for i from 1 to 100 collect `((id . ,(format "p-%d" i))))
                     :done nil)))
        (agent-workspace--issues-redraw project))
      (setf (agent-workspace-agent-state ken) 'working
            (agent-workspace-agent-since ken) (- (float-time) 10.3))
      (agent-workspace--changed ken 'state)
      ;; Its first minute: a tick in under a second.
      (should (timerp agent-workspace--timer))
      (should (< 0 (float-time (time-subtract (timer--time agent-workspace--timer) nil)) 1.01))
      (let ((issues 0) (all 0))
        (cl-letf* ((redraw (symbol-function 'agent-workspace--issues-redraw))
                   ((symbol-function 'agent-workspace--issues-redraw)
                    (lambda (&rest args) (cl-incf issues) (apply redraw args)))
                   (force (symbol-function 'force-mode-line-update))
                   ((symbol-function 'force-mode-line-update)
                    (lambda (&optional every) (when every (cl-incf all)) (funcall force every))))
          (setf (agent-workspace-agent-since ken) (- (float-time) 125))
          (should (< (+test-awa--fastest #'agent-workspace--tick) 0.005))
          (should (string-search "2m" (with-current-buffer (agent-workspace--bar-buffer ken) (buffer-string))))
          ;; Past its first minute: the next at the next minute.
          (should (< 50 (float-time (time-subtract (timer--time agent-workspace--timer) nil)) 56))
          ;; Its context's usage: its lines only.
          (agent-workspace--changed ken 'usage)
          (should (= issues 0))
          (should (= all 0))))
      (ignore ada))))

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
