;;; tests/e2e/test-agent-workspace.el -*- lexical-binding: t; -*-
;; config/agent-workspace's app in a GUI Emacs: what needs real windows and
;; redisplay. Its agents' lines (a bar, the open pane's header line) drawn to
;; the window's right edge, their avatars images; the stage tiled again after
;; a border dragged; closing it; an agent's canvas and panels as tabs, a panel
;; fetching once its tab is shown; the minimap's lanes, even, their │ lined
;; up (each its role's icon) and no line past its edge in a font without ✎; a
;; napping loop's watch on its project's issues (file-notify's events, which
;; batch Emacs doesn't get). No agent runs: sessions are buffers.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(+test-load "config/agent-ui" "config/agent-workspace")

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
(3 lines of text, its header line above them); the compose line growing as
its text needs, the app not laid out again for it, the feed following its
end; a message sent from it said in the feed, the compose line 3 lines
again."
  (let ((+test-e2e-frame-size '(230 . 50)))
    (+test-e2e-aw
      (let* ((sent nil)
             (app (agent-workspace--app project))
             (feed (get-buffer-window (agent-workspace--room-buffer project)))
             (compose (get-buffer-window (agent-workspace--compose-buffer project))))
        (should (window-live-p feed))
        (should (window-live-p compose))
        (should (= (+test-e2e-aw--text-lines compose) 3))
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
          (should (= (+test-e2e-aw--text-lines compose) 6))
          (should-not (agent-workspace--app-resizes app))
          (should (= (window-end feed t) (with-current-buffer (window-buffer feed) (point-max))))
          (with-selected-window compose
            (agent-workspace-compose-send)
            (agent-workspace--compose-typed)))
        (+test--pump 0.2)
        (should (equal sent '(("sam" "look at this\n2\n3\n4\n5\n6"))))
        (should (= (+test-e2e-aw--text-lines compose) 3))
        (should-not (agent-workspace--app-resizes app))
        (with-current-buffer (window-buffer feed)
          (should (string-search "→ sam look at this" (buffer-string))))
        ;; The feed shows its end.
        (should (= (window-end feed t) (with-current-buffer (window-buffer feed) (point-max))))))))

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
            (should (string-prefix-p " canvas │ logs │ tests" (+test-e2e-aw--header side)))
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
            (should (string-match-p "▾ .*ada · builder.*canvas │ logs │ tests *\\'"
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

(ert-deftest e2e-agent-workspace/the-minimap ()
  "The minimap under the issue list: a lane each as ada and sam do things,
drawn a moment later; its avatars images; every lane's cells and bar at the
same pixels (its glyphs evened)."
  (+test-e2e-aw
    (let ((window (get-buffer-window (agent-workspace--minimap-buffer project))))
      (should (window-live-p window))
      (should (eq (window-parameter window 'window-side) 'left))
      (should (string-search "quiet" (with-current-buffer (window-buffer window) (buffer-string))))
      (+test-e2e-aw--did ada "read" "README" 1)
      (+test-e2e-aw--did ada "edit" "README" 1)
      (+test-e2e-aw--did sam "execute" "README" 1)
      (should (+test-wait-for (lambda () (with-current-buffer (window-buffer window)
                                           (and (string-search "README:1" (buffer-string))
                                                (not (string-search "quiet" (buffer-string))))))
                              3))
      (redisplay t)
      (with-current-buffer (window-buffer window)
        (goto-char (point-min))
        (should (text-property-search-forward 'display nil (lambda (_ value) (eq (car-safe value) 'image))))
        (let ((bars nil))
          (goto-char (point-min))
          (while (search-forward "│" nil t)
            (push (car (window-text-pixel-size window (line-beginning-position) (1- (point)))) bars))
          (should (= (length bars) 2))
          (should (= (car bars) (cadr bars))))))))

(ert-deftest e2e-agent-workspace/the-minimap-s-bars-line-up ()
  "Lanes of different minutes (an edit every minute, none, mixed), each
its role's icon after its avatar (a project's role without one: ▶): every
lane's │ at the same x, its cells a column each, an edit's glyph one too
(the legend's); no line past the window's edge (no $), a file named with
glyphs drawn wider cut. In JetBrains Mono if it's here: it has no ✎, drawn
from another font, 12 px for a column of 8."
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
                ;; ada's lane, its file's name drawn wider than its columns: cut.
                (goto-char (point-min))
                (should (search-forward "▌A" nil t))
                (should (string-suffix-p "…" (buffer-substring (point) (line-end-position))))
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
