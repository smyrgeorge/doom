;;; tests/e2e/test-agent-workspace.el -*- lexical-binding: t; -*-
;; config/agent-workspace's app in a GUI Emacs: what needs real windows and
;; redisplay. Its agents' lines (a bar, the open pane's header line) drawn to
;; the window's right edge, their avatars images; the stage tiled again after
;; a border dragged; closing it; an agent's canvas and panels as tabs, a panel
;; fetching once its tab is shown; the minimap's lanes, even, their │ lined
;; up (each its role's icon) and no line past its edge in a font without ✎; a
;; napping loop's watch on its project's issues (file-notify's events, which
;; batch Emacs doesn't get). No agent runs: sessions are buffers.
;; run.sh: slow (~40 s beside the others: started first).

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'nerd-icons)
(+test-load "config/agent-ui" "config/agent-workspace")
;; The Beads panel's look: the issue list's types are drawn as it draws them.
(+test-load "config/beads/look")

(defun +test-e2e-aw--project ()
  "A git repository with a commit: its folder."
  (let ((dir (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "aw-e2e-") t)))))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    dir))

(defmacro +test-e2e-aw (&rest body)
  "BODY with a crew (ada, a builder; sam, an investigator) in a new project,
its app open in the frame; sessions plain buffers; closed after."
  (declare (indent 0))
  `(let* ((project (+test-e2e-aw--project))
          (default-directory project))
     (cl-letf (((symbol-function 'agent-workspace--start)
                (lambda (agent)
                  (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                    (with-current-buffer buffer
                      (setq agent-workspace--agent agent)
                      (insert "A session.\n"))
                    (setf (agent-workspace-agent-buffer agent) buffer
                          (agent-workspace-agent-state agent) 'desk)
                    (agent-workspace--changed agent 'session)
                    buffer)))
               ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
       (+test-e2e-frame-reset)
       (delete-other-windows)
       (let ((ada (agent-workspace-create :role "builder" :name "ada"))
             (sam (agent-workspace-create :role "investigator" :name "sam")))
         (ignore ada sam)
         (unwind-protect
             (progn (agent-workspace-open t)
                    ;; Laid out again if its first redisplay resized it.
                    (+test-sleep 0.8)
                    ,@body)
           (when (agent-workspace--app project)
             (agent-workspace--close-app project))
           (agent-workspace-close-all)
           (delete-other-windows))))))

(defun +test-e2e-aw--line-width (window)
  "The pixel width WINDOW's first line is drawn at."
  (car (window-text-pixel-size window (window-start window)
                               (with-current-buffer (window-buffer window)
                                 (save-excursion (goto-char (window-start window)) (line-end-position))))))

(ert-deftest e2e-agent-workspace/lines-to-the-edge ()
  "A bar's line reaches its window's right edge, its avatar an image; the open
pane's header line is the agent's."
  (+test-e2e-aw
    (let ((bar (get-buffer-window (agent-workspace--bar-buffer sam)))
          (pane (get-buffer-window (agent-workspace-agent-buffer ada))))
      (should (window-live-p bar))
      (should (window-live-p pane))
      (should (= (window-total-height bar) 1))
      (should (>= (+test-e2e-aw--line-width bar) (- (window-body-width bar t) (frame-char-width))))
      (with-current-buffer (window-buffer bar)
        (goto-char (point-min))
        (should (text-property-search-forward 'display nil (lambda (_ value) (eq (car-safe value) 'image)))))
      (should (string-match-p "▌A ada · builder"
                              (substring-no-properties
                               (with-selected-window pane
                                 (format-mode-line (window-parameter pane 'header-line-format) nil pane))))))))

(ert-deftest e2e-agent-workspace/tiled-again-after-a-drag ()
  "A border dragged in the stage: it's tiled again (its bar a row)."
  (+test-e2e-aw
    ;; Not laid out again by itself: the echo area's messages, the window
    ;; selected, don't count.
    (should-not (agent-workspace--app-resizes (agent-workspace--app project)))
    (let ((bar (get-buffer-window (agent-workspace--bar-buffer sam))))
      (ignore-errors (window-resize bar 5))
      (+test-wait-for (lambda ()
                        (let ((bar (get-buffer-window (agent-workspace--bar-buffer sam))))
                          (and bar (= (window-total-height bar) 1))))
                      3)
      (should (= (window-total-height (get-buffer-window (agent-workspace--bar-buffer sam))) 1)))))

(defun +test-e2e-aw--windows ()
  "The frame's windows: (BUFFER-NAME WIDTH HEIGHT), in order."
  (mapcar (lambda (w) (list (buffer-name (window-buffer w)) (window-total-width w) (window-total-height w)))
          (window-list nil 'nomini (frame-first-window))))

(declare-function +popup/quit-window "ui/popup/+hacks")

(ert-deftest e2e-agent-workspace/a-popup-stays ()
  "A click on the echo area opens *Messages* (Doom's popup, at the bottom):
it stays, the app not laid out again for it; a border dragged meanwhile
tiles the stage again, the popup kept. q closes it: its rows back to the
app, laid out as before."
  (+test-with-doom-popups
    (+test-e2e-aw
      (should (eq (lookup-key minibuffer-inactive-mode-map [mouse-1]) #'view-echo-area-messages))
      (let ((app (agent-workspace--app project))
            (laid-out (+test-e2e-aw--windows)))
        (view-echo-area-messages)
        (+test-sleep 1)
        (should (get-buffer-window "*Messages*"))
        (should-not (agent-workspace--app-resizes app))
        ;; A border dragged, the popup open: tiled again, it stays.
        (ignore-errors (window-resize (get-buffer-window (agent-workspace--bar-buffer sam)) 3))
        (should (+test-wait-for (lambda ()
                                  (when-let* ((bar (get-buffer-window (agent-workspace--bar-buffer sam))))
                                    (= (window-total-height bar) 1)))
                                3))
        (should (get-buffer-window "*Messages*"))
        ;; q: gone, the app as it was.
        (with-selected-window (get-buffer-window "*Messages*")
          (+popup/quit-window))
        (should (+test-wait-for (lambda () (equal (+test-e2e-aw--windows) laid-out)) 3))))))

(ert-deftest e2e-agent-workspace/quit ()
  "Q: the crew closed at once, its windows and buffers gone, the frame back
to what it was."
  (+test-e2e-aw
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (+test--pump 0.2)
    (should-not (agent-workspace-agents project))
    (should-not (agent-workspace-frame-p))
    (should-not (seq-some (lambda (w) (buffer-local-value 'agent-workspace--bar-of (window-buffer w)))
                          (window-list nil 'nomini)))
    (should-not (get-buffer (format "*issues · %s*" (file-name-nondirectory (directory-file-name project)))))))

(defun +test-e2e-aw--text-lines (window)
  "The lines of text WINDOW shows whole, as drawn."
  (/ (window-body-height window t) (window-default-line-height window)))

(ert-deftest e2e-agent-workspace/the-room ()
  "The room beside the stage in a wide frame: its feed above its compose line
(a line of text, its header line above it); the compose line growing as its
text needs (5 lines at most), the app not laid out again for it, the feed
following its end; a message sent from it said in the feed, the compose
line a line again."
  (let ((+test-e2e-frame-size '(230 . 50)))
    (+test-e2e-aw
      (let* ((sent nil)
             (app (agent-workspace--app project))
             (feed (get-buffer-window (agent-workspace--room-buffer project)))
             (compose (get-buffer-window (agent-workspace--compose-buffer project))))
        (should (window-live-p feed))
        (should (window-live-p compose))
        (should (= (+test-e2e-aw--text-lines compose) 1))
        (should (= (window-total-width feed) agent-workspace-room-width))
        (cl-letf (((symbol-function 'agent-workspace-send)
                   (lambda (agent text &rest _) (push (list (agent-workspace-agent-name agent) text) sent) 'sent)))
          (dotimes (i 40)
            (agent-workspace-room-post project :kind 'note :text (format "note %d" i)))
          (+test--pump 0.2)
          (with-selected-window compose
            (insert "#sam look at this\n2\n3\n4\n5\n6")
            (agent-workspace--compose-typed))
          (+test--pump 0.5)
          (should (eq (get-buffer-window (agent-workspace--compose-buffer project)) compose))
          (should (= (+test-e2e-aw--text-lines compose) 5))
          (should-not (agent-workspace--app-resizes app))
          (should (= (window-end feed t) (with-current-buffer (window-buffer feed) (point-max))))
          (with-selected-window compose
            (agent-workspace-compose-send)
            (agent-workspace--compose-typed)))
        (+test--pump 0.2)
        (should (equal sent '(("sam" "look at this\n2\n3\n4\n5\n6"))))
        (should (= (+test-e2e-aw--text-lines compose) 1))
        (should-not (agent-workspace--app-resizes app))
        (with-current-buffer (window-buffer feed)
          (should (string-search "→ sam look at this" (buffer-string))))
        ;; The feed shows its end.
        (should (= (window-end feed t) (with-current-buffer (window-buffer feed) (point-max))))))))

(ert-deftest e2e-agent-workspace/an-empty-crew-with-window-dividers ()
  "An empty crew opened in a frame with window dividers (Doom's, a pixel):
laid out whole, the stage's hint in it (no agents yet, c makes one), the
compose line a line of text; the frame resized, no error. In whole lines a
divider made the compose line's least 3 lines, more than its line of text
needed: its rows never given back (\"No resizable window below this one\"),
the layout stopped half done, the hint never shown."
  (let* ((project (+test-e2e-aw--project))
         (default-directory project)
         (window-divider-default-places t)
         (window-divider-default-bottom-width 1)
         (window-divider-default-right-width 1))
    (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore))
      (+test-e2e-frame-reset)
      (delete-other-windows)
      (window-divider-mode 1)
      (unwind-protect
          (progn
            (agent-workspace-open t)
            (+test-sleep 0.5)
            (let ((hint (get-buffer-window (agent-workspace--hint-buffer project)))
                  (compose (get-buffer-window (agent-workspace--compose-buffer project))))
              (should (window-live-p hint))
              (with-current-buffer (window-buffer hint)
                (should (string-search "No agents yet" (buffer-string))))
              (should (window-live-p compose))
              (should (= (window-bottom-divider-width compose) 1))
              (should (= (window-body-height compose t) (window-default-line-height compose))))
            ;; Resized: the compose line fitted again, no error.
            (let ((from (with-current-buffer "*Messages*" (point-max))))
              (set-frame-size nil 120 50)
              (+test-sleep 0.8)
              (+test-e2e-frame-reset)
              (+test-sleep 0.8)
              (with-current-buffer "*Messages*"
                (should-not (string-search "No resizable window" (buffer-substring from (point-max)))))))
        (window-divider-mode -1)
        (when (agent-workspace--app project)
          (agent-workspace--close-app project))
        (agent-workspace-close-all)
        (delete-other-windows)))))

(ert-deftest e2e-agent-workspace/c-then-a-crew ()
  "On an empty stage (its hint saying c: a new agent, or a crew), c then
full typed in its menu: a scribe, a builder, a reviewer and a merger made
and started, named from the pool, none looping, no name asked; the room
says who was made, the stage has them. c then full again: nothing to add,
refused, nothing made."
  (let* ((project (+test-e2e-aw--project))
         (default-directory project))
    (cl-letf (((symbol-function 'agent-workspace--start)
               (lambda (agent)
                 (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                   (with-current-buffer buffer
                     (setq agent-workspace--agent agent)
                     (insert "A session.\n"))
                   (setf (agent-workspace-agent-buffer agent) buffer
                         (agent-workspace-agent-state agent) 'desk)
                   (agent-workspace--changed agent 'session)
                   buffer)))
              ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
      (+test-e2e-frame-reset)
      (delete-other-windows)
      (unwind-protect
          (progn
            (agent-workspace-open t)
            (+test-sleep 0.5)
            (let ((hint (get-buffer-window (agent-workspace--hint-buffer project))))
              (should (window-live-p hint))
              (with-current-buffer (window-buffer hint)
                (should (string-search "c: a new agent, or a crew" (buffer-string))))
              (select-window hint))
            (with-timeout (20 (ert-fail "c then full: still asking"))
              (execute-kbd-macro (vconcat "c" "full" (kbd "RET"))))
            (+test-sleep 0.5)
            (let ((agents (agent-workspace-agents project)))
              (should (equal (mapcar (lambda (agent) (list (agent-workspace-agent-name agent)
                                                           (agent-workspace-agent-role agent)))
                                     agents)
                             '(("ada" "scribe") ("grace" "builder") ("linus" "reviewer") ("ken" "merger"))))
              (should (seq-every-p (lambda (agent) (eq (agent-workspace-agent-state agent) 'desk)) agents))
              (should-not (seq-some #'agent-workspace-agent-loop agents))
              ;; Each on the stage: its pane open, or its bar.
              (dolist (agent agents)
                (should (or (get-buffer-window (agent-workspace-agent-buffer agent))
                            (get-buffer-window (agent-workspace--bar-buffer agent)))))
              (with-current-buffer (agent-workspace--room-buffer project)
                (should (string-search "crew full: + scribe ada, builder grace, reviewer linus, merger ken"
                                       (buffer-string))))
              ;; Again, from a bar: refused (C-g ends the question asked again).
              (select-window (seq-some (lambda (agent) (get-buffer-window (agent-workspace--bar-buffer agent)))
                                       agents))
              (let ((from (with-current-buffer "*Messages*" (point-max))))
                (cl-letf (((symbol-function 'sit-for) #'ignore))
                  (with-timeout (20 (ert-fail "c then full again: still asking"))
                    (condition-case nil
                        (execute-kbd-macro (vconcat "c" "full" (kbd "RET") (kbd "C-g")))
                      (quit nil))))
                (should (equal (agent-workspace-agents project) agents))
                (with-current-buffer "*Messages*"
                  (should (string-search "Nothing to add: the crew has every agent of full already"
                                         (buffer-substring from (point-max))))))))
        (when (agent-workspace--app project)
          (agent-workspace--close-app project))
        (agent-workspace-close-all)
        (delete-other-windows)))))

(defconst +test-e2e-aw--panel
  ";;; -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type \"text\" :id \"t\" :text \"\")
 :every 60
 :fetch (lambda (panel) (agent-ui-panel-update panel \"t\" :text default-directory)))
"
  "A panel showing where it runs.")

(defun +test-e2e-aw--header (window)
  "WINDOW's header line, as it's drawn."
  (with-selected-window window
    (substring-no-properties (format-mode-line (window-parameter window 'header-line-format) nil window))))

(ert-deftest e2e-agent-workspace/panels-as-tabs ()
  "ada with a canvas and two panels (logs, tests): its side area's tabs drawn
as its header line, the canvas shown; its badge on its pane's header line;
a hidden panel fetches nothing until v shows it (then it does, as shown);
V: the one shown full size, the tabs at its line's right edge; V again:
back."
  (+test-e2e-aw
    (let ((agent-ui-panel-trust-file (+test-tmp-file "aw-e2e-trust.eld"))
          (worktree (agent-workspace-agent-worktree ada)))
      (make-directory (expand-file-name ".agent-ui/panels" worktree) t)
      (dolist (name '("logs" "tests"))
        (write-region +test-e2e-aw--panel nil (expand-file-name (format ".agent-ui/panels/%s.el" name) worktree)))
      (agent-ui-panel-trust-project project)
      (let* ((session (agent-workspace-agent-buffer ada))
             (canvas (agent-ui-canvas (agent-ui--session-name session))))
        (with-current-buffer canvas (setq agent-ui--session-buffer session))
        (agent-ui-show '(:type "text" :id "hello" :text "Hello") :canvas canvas)
        (let* ((logs (agent-ui-open-panel "logs" worktree t))
               (tests (agent-ui-open-panel "tests" worktree t))
               (state (lambda (panel) (buffer-local-value 'agent-ui-panels--state panel))))
          (+test--pump 0.3)
          (let ((side (agent-workspace--side-window ada))
                (pane (get-buffer-window session)))
            (should (eq (window-buffer side) canvas))
            (should (string-prefix-p " Canvas │ logs │ tests" (+test-e2e-aw--header side)))
            (should (string-search (substring-no-properties (agent-workspace-badge ada))
                                   (+test-e2e-aw--header pane)))
            ;; Hidden, not fetched.
            (should-not (agent-ui-panel-fetched (funcall state logs)))
            (should-not (agent-ui-panel-fetched (funcall state tests)))
            ;; v (from its session): in the canvas; again: logs, shown, fetched.
            (with-current-buffer session (agent-workspace-panels-here))
            (with-current-buffer (window-buffer) (agent-workspace-panels-here))
            (should (eq (window-buffer) logs))
            (should (+test-wait-for (lambda () (agent-ui-panel-fetched (funcall state logs))) 3))
            (should-not (agent-ui-panel-fetched (funcall state tests)))
            ;; V: logs full size, its pane's whole room, the tabs at the
            ;; right of its line.
            (with-current-buffer (window-buffer) (agent-workspace-full-here))
            (+test--pump 0.3)
            (should (eq (window-buffer) logs))
            (should-not (get-buffer-window session))
            (should (string-match-p "▾ .*ada · builder.*Canvas │ logs │ tests *\\'"
                                    (+test-e2e-aw--header (selected-window))))
            ;; V again: back beside its session.
            (with-current-buffer (window-buffer) (agent-workspace-full-here))
            (+test--pump 0.3)
            (should (get-buffer-window session))
            (should (eq (window-buffer (agent-workspace--side-window ada)) logs))))))))

(+test-e2e-run)

(defun +test-e2e-aw--did (agent kind file line)
  "AGENT's tool call of KIND (ACP's) at FILE (in its worktree) and LINE."
  (agent-workspace--activity-event
   agent `((:event . tool-call-update)
           (:data . ((:tool-call . ((:kind . ,kind)
                                    (:locations . ,(vector `((path . ,(expand-file-name
                                                                       file (agent-workspace-agent-worktree agent)))
                                                             (line . ,line)))))))))))

(ert-deftest e2e-agent-workspace/the-issues-types-line-up ()
  "The issue list's types, the Beads panel's icons in their colours (a dim
· for one with none): each a column, every id after them at the same x, an
agent's avatar before them or not; an epic's heading's id there too (its
icon the epic type's), the issues under it and under \"no epic\" 2 columns
further in."
  (+test-e2e-aw
    (let ((window (get-buffer-window (agent-workspace--issues-buffer project)))
          (types '("bug" "feature" "task" "chore" "decision" "spike")))
      (with-current-buffer (window-buffer window)
        (setq agent-workspace--issues-data
              (agent-workspace--issues-parse
               project
               (list :all (append
                           `(((id . "t-0") (title . "On it") (status . "in_progress") (assignee . "ada")
                              (issue_type . "task"))
                             ((id . "e-1") (title . "An epic") (status . "open") (issue_type . "epic")))
                           (seq-map-indexed (lambda (type i)
                                              `((id . ,(format "t-%d" (1+ i))) (title . ,(concat "A " type))
                                                (status . "open") (issue_type . ,type)
                                                (parent . ,(and (< i 3) "e-1"))))
                                            types))
                     :ready (seq-map-indexed (lambda (_ i) `((id . ,(format "t-%d" (1+ i))))) types)
                     :done nil)))
        (agent-workspace--issues-redraw project)
        (redisplay t)
        (let ((icons (cons ?· (mapcar (lambda (icon) (aref (nerd-icons-codicon icon) 0))
                                      '("nf-cod-milestone" "nf-cod-bug" "nf-cod-sparkle" "nf-cod-checklist"
                                        "nf-cod-tools" "nf-cod-law"))))
              (xs nil))
          (goto-char (point-min))
          (while (re-search-forward " \\([te]-[0-9]\\) " nil t)
            (push (cons (match-string 1)
                        (car (window-text-pixel-size window (line-beginning-position) (match-beginning 1))))
                  xs)
            ;; Its type, the column before.
            (should (memq (char-after (- (match-beginning 1) 2)) icons)))
          (should (= (length xs) 8))
          ;; The epic's heading: the epic type's icon.
          (should (eq (save-excursion (goto-char (point-min))
                                      (search-forward " e-1 ")
                                      (char-before (match-beginning 0)))
                      (aref (nerd-icons-codicon "nf-cod-milestone") 0)))
          (let ((at (cdr (assoc "t-0" xs))))
            (should (= (cdr (assoc "e-1" xs)) at))
            (dolist (id '("t-1" "t-2" "t-3" "t-4" "t-5" "t-6"))
              (should (= (cdr (assoc id xs)) (+ at (* 2 (frame-char-width))))))))))))

(ert-deftest e2e-agent-workspace/opened-in-a-second-frame ()
  "The app opened in a second frame: the first unmarked, given back the
windows it had; q in the second acts there: unmarked, its own windows
back; no frame left marked (doom-pbk.71)."
  (+test-e2e-aw
    (let* ((first (selected-frame))
           (second (make-frame `((visibility . nil) (width . 220) (height . 40)))))
      (unwind-protect
          (progn
            (should (agent-workspace-frame-p first))
            (with-selected-frame second
              (switch-to-buffer (get-buffer-create "*second*"))
              (agent-workspace-open t)
              (should (agent-workspace-frame-p second))
              (should (get-buffer-window (agent-workspace--issues-buffer project) second)))
            ;; The first: unmarked, the app's windows gone from it.
            (should-not (agent-workspace-frame-p first))
            (should-not (get-buffer-window (agent-workspace--issues-buffer project) first))
            ;; q in the second: there.
            (with-selected-frame second
              (agent-workspace-leave t)
              (should (eq (window-buffer (frame-first-window second)) (get-buffer "*second*"))))
            (should-not (seq-some #'agent-workspace-frame-p (frame-list))))
        (delete-frame second)
        (kill-buffer "*second*")))))

(ert-deftest e2e-agent-workspace/the-minimap ()
  "The minimap under the issue list: a lane each, quiet ones dots (their
names only on hover), the axis and legend under them; ada's and sam's
cells as they do things, drawn a moment later, as tall; its avatars images;
every lane's cells and bar at the same pixels (its glyphs evened); half a
line of padding above its lanes and half a line under its last line
\(doom-pbk.125), the cursor on its first lane (doom-pbk.130)."
  (+test-e2e-aw
    (let* ((window (get-buffer-window (agent-workspace--minimap-buffer project)))
           (line (window-default-line-height window))
           (pad (/ line 2)))
      (should (window-live-p window))
      (should (eq (window-parameter window 'window-side) 'left))
      ;; Each agent its line, quiet ones too (doom-pbk.91): a lane of dots,
      ;; no name; the axis and legend under them; as tall as they are, and
      ;; their padding.
      (with-current-buffer (window-buffer window)
        (let ((none (with-selected-frame (window-frame window) (agent-workspace--minimap-glyph 'none))))
          (should (= 2 (how-many (concat (regexp-quote (apply #'concat (make-list agent-workspace-activity-minutes none)))
                                         " │ ")
                                 (point-min) (point-max)))))
        (should (= 2 (how-many "at the desk" (point-min) (point-max))))
        (should-not (string-search "ada" (buffer-string)))
        (should (string-search "-15m" (buffer-string))))
      (should (= (window-body-height window t) (+ pad (* 4 line) pad)))
      (redisplay t)
      (with-current-buffer (window-buffer window)
        ;; The first lane half a line down, the cursor on it; the window's
        ;; end, under the last lane, half a line further.
        (should (get-text-property (window-point window) 'agent-workspace-minimap-agent))
        (should (= (cdr (posn-x-y (posn-at-point (window-point window) window))) pad))
        (should (= (cdr (window-text-pixel-size window (point-min) (point-max))) (+ pad (* 4 line) pad)))
        (should (pos-visible-in-window-p (point-max) window)))
      ;; At work, a turn each, as a prompt sent starts it: its tool calls'
      ;; files shown.
      (dolist (agent (list ada sam))
        (agent-workspace--set-state agent 'working)
        (setf (agent-workspace-agent-since agent) (float-time)))
      (+test-e2e-aw--did ada "read" "README" 1)
      (+test-e2e-aw--did ada "edit" "README" 1)
      (+test-e2e-aw--did sam "execute" "README" 1)
      (should (+test-wait-for (lambda () (with-current-buffer (window-buffer window)
                                           (and (string-search "README:1" (buffer-string))
                                                (not (string-search "at the desk" (buffer-string))))))
                              3))
      (redisplay t)
      ;; As tall: the axis and legend there already.
      (should (= (window-body-height window t) (+ pad (* 4 line) pad)))
      (with-current-buffer (window-buffer window)
        (goto-char (point-min))
        (should (text-property-search-forward 'display nil (lambda (_ value) (eq (car-safe value) 'image))))
        (let ((bars nil))
          (goto-char (point-min))
          (while (search-forward "│" nil t)
            (push (car (window-text-pixel-size window (line-beginning-position) (1- (point)))) bars))
          (should (= (length bars) 2))
          (should (= (car bars) (cadr bars))))))))

(ert-deftest e2e-agent-workspace/the-minimap-scrolls-past-10-lanes ()
  "Fourteen agents in a frame with window dividers (Doom's, a pixel): the
minimap as tall as 10 lanes, the axis and legend, and its padding, its
lines whole (in whole lines a divider cut the last by a pixel, the cursor
there scrolling them): its first 12 lanes; j to the last lane scrolls it
into view, whole."
  (+test-e2e-aw
    (let ((window-divider-default-places t)
          (window-divider-default-bottom-width 1)
          (window-divider-default-right-width 1))
      (window-divider-mode 1)
      (unwind-protect
          (progn
            (dolist (spec '(("bo" "builder") ("cy" "builder") ("di" "builder") ("ed" "investigator")
                            ("kim" "reviewer") ("fay" "reviewer") ("gus" "tester") ("hal" "tester")
                            ("ivy" "designer") ("jo" "planner") ("lu" "merger") ("mo" "documenter")))
              (agent-workspace-create :role (cadr spec) :name (car spec)))
            (agent-workspace-layout (agent-workspace--app project))
            (+test-sleep 0.5)
            (agent-workspace--minimap-draw project)
            (let ((window (get-buffer-window (agent-workspace--minimap-buffer project))))
              (should (= (window-bottom-divider-width window) 1))
              (should (= (window-body-height window t) (let ((line (window-default-line-height window)))
                                                         (+ (* 12 line) (* 2 (/ line 2))))))
              (with-selected-window window
                (redisplay t)
                ;; Its first 12 lanes whole, the padding above them.
                (goto-char (point-min))
                (agent-workspace-minimap-next 12)
                (should (pos-visible-in-window-p (point) window))
                (should-not (nth 2 (pos-visible-in-window-p (point) window t)))
                (agent-workspace-minimap-next 1)
                (should (get-text-property (point) 'agent-workspace-minimap-agent))
                (agent-workspace-minimap-next 1)
                (should (get-text-property (point) 'agent-workspace-minimap-agent))
                (redisplay t)
                (should (> (window-start window) (point-min)))
                ;; Whole: nothing of it cut at the bottom.
                (should (equal (nth 3 (pos-visible-in-window-p (point) window t)) nil))
                (should (pos-visible-in-window-p (point) window)))))
        (window-divider-mode -1)))))

(ert-deftest e2e-agent-workspace/the-minimap-s-bars-line-up ()
  "Lanes of different minutes (an edit every minute, none, mixed), each
its role's icon after its avatar (a project's role without one: ▶): every
lane's │ at the same x, its cells a column each, an edit's glyph one too
(the legend's); no line past the window's edge (no $), a file named with
glyphs drawn wider cut, else whole. In JetBrains Mono if it's here: it has
no ✎, drawn from another font, 12 px for a column of 8 (not there, as on
Linux: a column)."
  (let ((font (frame-parameter nil 'font)))
    (when (find-font (font-spec :family "JetBrains Mono"))
      (set-frame-font (font-spec :family "JetBrains Mono" :size 13) nil t))
    (unwind-protect
        (+test-e2e-aw
          (let* ((window (get-buffer-window (agent-workspace--minimap-buffer project)))
                 (ken (progn
                        (make-directory (expand-file-name ".agent-workspace/roles" project) t)
                        (write-region "---\ndescription: triages\n---\nTriage.\n" nil
                                      (expand-file-name ".agent-workspace/roles/triager.md" project))
                        (agent-workspace-create :role "triager" :name "ken")))
                 (start (float-time))
                 (now start))
            ;; ada and sam at work, their turns started before their first
            ;; tool calls: their files shown.
            (dolist (agent (list ada sam))
              (agent-workspace--set-state agent 'working)
              (setf (agent-workspace-agent-since agent) (- start (* 60 15))))
            (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now)))
              (dotimes (i 14)
                (setq now (- start (* 60 (- 14 i))))
                (+test-e2e-aw--did ada "edit" "notes/✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎.md" 1)
                (+test-e2e-aw--did sam (if (cl-oddp i) "edit" "read") "README" 1)))
            (agent-workspace--set-state ken 'working)
            (agent-workspace--minimap-draw project)
            (redisplay t)
            (with-current-buffer (window-buffer window)
              (let ((bars nil)
                    (edit (agent-workspace--minimap-glyph 'edit)))
                (goto-char (point-min))
                (while (search-forward "│" nil t)
                  (push (car (posn-x-y (posn-at-point (1- (point)) window))) bars))
                (should (= (length bars) 3))
                (should (= (length (delete-dups bars)) 1))
                ;; Each lane its role's icon after its avatar.
                (dolist (agent (list ada sam ken))
                  (goto-char (point-min))
                  (should (search-forward (concat " ▌" (upcase (substring (agent-workspace-agent-name agent) 0 1)) " "
                                                  (substring-no-properties (agent-workspace-role-glyph agent)))
                                          nil t)))
                (goto-char (point-min))
                (while (not (eobp))
                  (should (< (car (window-text-pixel-size window (line-beginning-position) (line-end-position)))
                             (window-body-width window t)))
                  (forward-line 1))
                ;; ada's lane, its file's name drawn wider than its columns:
                ;; cut; a column each: whole.
                (goto-char (point-min))
                (should (search-forward "▌A" nil t))
                (if (> (with-selected-window window (string-pixel-width "✎")) (frame-char-width))
                    (should (string-suffix-p "…" (buffer-substring (point) (line-end-position))))
                  (should (string-suffix-p ".md:1" (buffer-substring (point) (line-end-position)))))
                (should (= (string-pixel-width edit) (frame-char-width)))
                (should (string-search (concat edit " edit") (buffer-string)))))))
      (set-frame-font font nil t))))

(ert-deftest e2e-agent-workspace/a-napping-loop-wakes-on-its-issues-changing ()
  "A napping agent's loop watches its project's .beads (a GUI Emacs gets
file-notify's events): bd making its last-touched, then changing it, each
time a look a moment later."
  (skip-unless (executable-find "bd"))
  (let* ((project (+test-e2e-aw--project))
         (default-directory project)
         (root (agent-workspace--root project))
         (agent-workspace--crews (make-hash-table :test #'equal))
         (session (generate-new-buffer "ada · builder"))
         (ada (agent-workspace--make-agent :name "ada" :role "builder" :colour "blue" :state 'nap
                                           :project root :buffer session :loop t))
         (looks 0))
    (call-process "bd" nil nil nil "init" "--quiet" "--skip-agents" "--prefix" "demo")
    (puthash root (list ada) agent-workspace--crews)
    (cl-letf (((symbol-function 'agent-workspace--loop-look) (lambda (_agent) (cl-incf looks))))
      (unwind-protect
          (let ((agent-workspace-loop-check nil))
            (agent-workspace--loop-watch-update root)
            (should (gethash root agent-workspace--loop-watches))
            (should-not (file-exists-p (expand-file-name ".beads/last-touched" project)))
            ;; Its first issue: last-touched made (the folder's watch).
            (call-process "bd" nil nil nil "create" "--title" "one" "--labels" "build" "--quiet")
            (should (+test-wait-for (lambda () (> looks 0)) 10))
            (should (rassoc (expand-file-name ".beads/last-touched" project)
                            (plist-get (gethash root agent-workspace--loop-watches) :notify)))
            ;; Another: last-touched changed (its own watch).
            (+test-sleep 1.5)
            (setq looks 0)
            (call-process "bd" nil nil nil "create" "--title" "two" "--labels" "build" "--quiet")
            (should (+test-wait-for (lambda () (> looks 0)) 10))
            ;; Its loop off: no longer watched.
            (setf (agent-workspace-agent-loop ada) nil)
            (agent-workspace--loop-watch-update root)
            (should-not (gethash root agent-workspace--loop-watches)))
        (agent-workspace--loop-unwatch root)
        (kill-buffer session)))))
