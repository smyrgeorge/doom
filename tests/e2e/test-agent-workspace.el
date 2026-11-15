;;; tests/e2e/test-agent-workspace.el -*- lexical-binding: t; -*-
;; config/agent-workspace's app in a GUI Emacs: what needs real windows and
;; redisplay. Its agents' lines (a bar, the open pane's header line) drawn to
;; the window's right edge, their avatars images; the stage tiled again after
;; a border dragged; closing it; an agent's canvas and panels as tabs, a panel
;; fetching once its tab is shown; the minimap's lanes, even. No agent runs:
;; sessions are buffers.

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

(ert-deftest e2e-agent-workspace/the-room ()
  "The room beside the stage in a wide frame: its feed above its compose line
(3 rows); a message sent from it said in the feed, which follows its end."
  (let ((+test-e2e-frame-size '(230 . 50)))
    (+test-e2e-aw
      (let* ((sent nil)
             (feed (get-buffer-window (agent-workspace--room-buffer project)))
             (compose (get-buffer-window (agent-workspace--compose-buffer project))))
        (should (window-live-p feed))
        (should (window-live-p compose))
        (should (= (window-total-height compose) 3))
        (should (= (window-total-width feed) agent-workspace-room-width))
        (cl-letf (((symbol-function 'agent-workspace-send)
                   (lambda (agent text &rest _) (push (list (agent-workspace-agent-name agent) text) sent) 'sent)))
          (dotimes (i 40)
            (agent-workspace-room-post project :kind 'note :text (format "note %d" i)))
          (with-selected-window compose
            (insert "#sam look at this")
            (agent-workspace-compose-send)))
        (+test--pump 0.2)
        (should (equal sent '(("sam" "look at this"))))
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
