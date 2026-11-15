;;; tests/e2e/test-agent-workspace.el -*- lexical-binding: t; -*-
;; config/agent-workspace's app in a GUI Emacs: what needs real windows and
;; redisplay. Its agents' lines (a bar, the open pane's header line) drawn to
;; the window's right edge, their avatars images; the stage tiled again after
;; a border dragged; closing it. No agent runs: sessions are buffers.

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

(+test-e2e-run)
