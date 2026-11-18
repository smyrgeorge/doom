;;; tests/unit/test-agent-workspace-sidebar.el -*- lexical-binding: t; -*-
;; config/agent-workspace/sidebar.el: the crew under treemacs once you've left
;; the app. Its lanes at treemacs's widths (cells that fit, the │ lined up, no
;; "where now", never past the edge); shown under treemacs's window while it
;; shows the crew's project, gone when it's hidden or on another project, not
;; in the crew's frame; the mode line's tally meanwhile; RET on a lane. treemacs
;; stood in for (its window, its project); agents' sessions plain buffers (no
;; agent runs); bd not run.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-ui" "config/tiling" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

;; ====== HELPERS ======

(defun +test-aws--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aws/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory (expand-file-name "src" dir) t)
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "(a)\n" nil "src/a.el")
      (call-process "git" nil nil nil "add" ".")
      (call-process "git" nil nil nil "-c" "user.name=Test" "-c" "user.email=test@example.com"
                    "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defvar +test-aws--treemacs nil
  "(WINDOW . PATH): treemacs as it's stood in for: its window, the project
it shows; nil, hidden.")

(defmacro +test-aws (name &rest body)
  "BODY in a new project NAME (`project'), its crew made, no app before or
after; agents' sessions plain buffers, at the desk; treemacs stood in for
\(`+test-aws--treemacs')."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-aws--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
            (agent-workspace--sidebar-projects (make-hash-table :test #'equal))
            (agent-workspace--sidebar-timers (make-hash-table :test #'equal))
            (agent-workspace-minimap nil)
            (+test-aws--treemacs nil))
       (set-frame-size (selected-frame) 160 40)
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
                 ((symbol-function 'treemacs-get-local-window)
                  (lambda () (and +test-aws--treemacs (window-live-p (car +test-aws--treemacs))
                                  (car +test-aws--treemacs))))
                 ((symbol-function 'treemacs-current-workspace) (lambda () 'workspace))
                 ((symbol-function 'treemacs-workspace->projects) (lambda (_) (list 'project)))
                 ((symbol-function 'treemacs-project->path) (lambda (_) (cdr +test-aws--treemacs))))
         (unwind-protect (progn ,@body)
           (when (agent-workspace--app project) (agent-workspace--close-app project))
           (agent-workspace-close-all)
           (agent-workspace--sidebar-sync))))))

(defun +test-aws--treemacs-show (path)
  "treemacs shown on the left, on PATH: its window."
  (let ((window (or (car-safe +test-aws--treemacs)
                    (display-buffer-in-side-window (get-buffer-create " *Treemacs-Scoped-Buffer-test*")
                                                   '((side . left) (slot . -1) (window-width . 35))))))
    (setq +test-aws--treemacs (cons window (directory-file-name path)))
    (agent-workspace--sidebar-sync)
    window))

(defun +test-aws--treemacs-hide ()
  (when (window-live-p (car-safe +test-aws--treemacs))
    (delete-window (car +test-aws--treemacs)))
  (setq +test-aws--treemacs nil)
  (agent-workspace--sidebar-sync))

(defun +test-aws--tool (agent kind)
  "AGENT's tool call of KIND (ACP's)."
  (agent-workspace--activity-event
   agent `((:event . tool-call-update) (:data . ((:tool-call . ((:kind . ,kind))))))))

(defun +test-aws--bar-column (lane)
  "Where LANE's │ goes: the space before it, aligned."
  (get-text-property (1- (string-search "│" lane)) 'display lane))

;; ====== ITS LINES ======

(ert-deftest agent-workspace-sidebar/the-minimap-s-lines ()
  "Under treemacs, the minimap's lines as the app shows them (doom-pbk.127):
a lane each (its minutes, │, its state's glyph, where it is now), the axis
and legend while a lane has cells, cut to treemacs's width, never past it;
the lane's agent for RET and a click."
  (+test-aws "lanes"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (_ken (agent-workspace-create :role "builder" :name "ken")))
      (setf (agent-workspace-agent-state ada) 'working)
      (+test-aws--tool ada "edit")
      (agent-workspace-open t)
      (agent-workspace-leave)
      (+test-aws--treemacs-show project)
      (let* ((window (agent-workspace--sidebar-window (selected-frame)))
             (text (with-current-buffer (window-buffer window) (buffer-string))))
        (should (equal (substring-no-properties text)
                       (concat (mapconcat #'substring-no-properties
                                          (agent-workspace-minimap-text project (1- (window-body-width window)))
                                          "\n")
                               "\n")))
        (should (string-match-p "\\` ▌A ⚙ ·+✎ │" text))
        (should (string-match-p "\n ▌K ⚙ ken +│ ○  ?at th…\n" text))
        (should (string-search "-15m" text))
        (should (string-search "⌕ read" text))
        (dolist (line (split-string text "\n"))
          (should (< (string-width line) (window-body-width window))))
        (should (eq (get-text-property 1 'agent-workspace-minimap-agent text) ada))))))

;; ====== SHOWN UNDER TREEMACS ======

(ert-deftest agent-workspace-sidebar/under-treemacs-while-it-shows-the-crew ()
  "The app left: treemacs on the crew's project, its lanes under it (as wide,
a line each and its header); the mode line's tally leaves this frame. treemacs
on another project, or hidden: gone, the tally (what needs you) back. Not
while the crew isn't open, nor in the crew's own frame."
  (+test-aws "under"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (other (+test-aws--project "elsewhere")))
      (agent-workspace-create :role "builder" :name "ken")
      ;; No crew open: nothing.
      (+test-aws--treemacs-show project)
      (should-not (agent-workspace--sidebar-window (selected-frame)))
      (agent-workspace-open t)
      ;; In the crew's own frame: nothing.
      (should (frame-parameter nil 'agent-workspace))
      (agent-workspace--sidebar-sync)
      (should-not (agent-workspace--sidebar-window (selected-frame)))
      (agent-workspace-leave)
      (+test-aws--treemacs-show project)
      (let ((window (agent-workspace--sidebar-window (selected-frame)))
            (treemacs (car +test-aws--treemacs)))
        (should window)
        (should (eq (window-in-direction 'below treemacs t) window))
        (should (= (window-total-width window) (window-total-width treemacs)))
        ;; Its header line, a lane each, its padding (a terminal's: a line
        ;; under them).
        (should (= (window-total-height window) 4))
        (should (string-search "ken" (with-current-buffer (window-buffer window) (buffer-string))))
        (with-selected-window window
          (should (string-match-p "CREW · under" (substring-no-properties (agent-workspace--sidebar-header)))))
        ;; Its tally isn't in this frame's mode line.
        (setf (agent-workspace-agent-state ada) 'hand)
        (should (equal (agent-workspace--tally-mode-line) "")))
      ;; treemacs on another project: gone, its tally back.
      (+test-aws--treemacs-show other)
      (should-not (agent-workspace--sidebar-window (selected-frame)))
      (should (string-match-p "!1" (agent-workspace--tally-mode-line)))
      ;; Back on the crew's, then hidden: gone, no timer left.
      (+test-aws--treemacs-show project)
      (should (agent-workspace--sidebar-window (selected-frame)))
      (+test-aws--treemacs-hide)
      (should-not (agent-workspace--sidebar-window (selected-frame)))
      (+test-aws--tool ada "edit")
      (agent-workspace--changed ada 'state)
      (should (= (hash-table-count agent-workspace--sidebar-timers) 0)))))

(ert-deftest agent-workspace-sidebar/drawn-again-as-agents-change ()
  "Shown: a change drawn again in a moment (a timer), a new agent a line
more (its window taller)."
  (+test-aws "drawn"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-open t)
    (agent-workspace-leave)
    (+test-aws--treemacs-show project)
    (let ((window (agent-workspace--sidebar-window (selected-frame))))
      (should (= (window-total-height window) 3))
      (agent-workspace-create :role "builder" :name "ken")
      (should (gethash project agent-workspace--sidebar-timers))
      (agent-workspace--sidebar-draw project)
      (should (= (window-total-height window) 4))
      (should (string-search "ken" (with-current-buffer (window-buffer window) (buffer-string)))))))

(ert-deftest agent-workspace-sidebar/as-tall-as-the-minimap-s-lanes ()
  "Under treemacs as tall as the minimap: its header line, a line an agent,
its padding (a terminal's: a blank line under them), the cursor on a lane;
twelve agents, 10 lanes (`agent-workspace-minimap-lines'), then it scrolls;
the axis and legend under them while a lane has cells. Whatever made it otherwise, back to that as its frame's windows
change: treemacs quit and shown again at once (a workspace switch: its new
window split from the crew's, half each), a border dragged (doom-pbk.127)."
  (+test-aws "tall"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-open t)
    (agent-workspace-leave)
    (+test-aws--treemacs-show project)
    (let ((window (agent-workspace--sidebar-window (selected-frame))))
      (should (= (window-total-height window) 3))
      (with-current-buffer (window-buffer window)
        (should (string-suffix-p "│ ○  at th…\n" (buffer-string)))
        (should (get-text-property (window-point window) 'agent-workspace-minimap-agent)))
      ;; treemacs quit and shown again, nothing in between (treemacs--change-
      ;; buffer-on-scope-change): the crew's window the whole column, then
      ;; split, half each.
      (delete-window (car +test-aws--treemacs))
      (setcar +test-aws--treemacs (display-buffer-in-side-window
                                   (get-buffer-create " *Treemacs-Scoped-Buffer-test*")
                                   '((side . left) (slot . -1) (window-width . 35))))
      (should (> (window-total-height window) 10))
      (agent-workspace--sidebar-sync)
      (should (eq (agent-workspace--sidebar-window (selected-frame)) window))
      (should (= (window-total-height window) 3))
      ;; A border dragged: back.
      (window-resize window 6 nil t)
      (should (= (window-total-height window) 9))
      (agent-workspace--sidebar-sync)
      (should (= (window-total-height window) 3))
      ;; Twelve agents: 10 lanes, then it scrolls.
      (pcase-dolist (`(,name ,role) '(("bo" "builder") ("cy" "builder") ("di" "builder") ("ed" "investigator")
                                      ("sam" "investigator") ("kim" "reviewer") ("fay" "reviewer")
                                      ("gus" "tester") ("hal" "tester") ("ivy" "designer") ("jo" "planner")))
        (agent-workspace-create :role role :name name))
      (agent-workspace--sidebar-draw project)
      (should (= (window-total-height window) 12))
      (should (= (agent-workspace--lanes project) 10))
      ;; ada edits: her lane has cells, the axis and legend under the lanes.
      (+test-aws--tool (agent-workspace-agent "ada" project) "edit")
      (agent-workspace--sidebar-draw project)
      (should (= (window-total-height window) 14)))))

(ert-deftest agent-workspace-sidebar/ret-opens-the-app-its-agent-selected ()
  (+test-aws "ret"
    (let ((_ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken"))
          (opened nil)
          (selected nil))
      (agent-workspace-open t)
      (agent-workspace-leave)
      (+test-aws--treemacs-show project)
      (cl-letf (((symbol-function 'agent-workspace-open) (lambda (&rest _) (setq opened default-directory)))
                ((symbol-function 'agent-workspace-select) (lambda (agent &rest _) (setq selected agent))))
        (with-current-buffer (window-buffer (agent-workspace--sidebar-window (selected-frame)))
          (goto-char (point-min))
          (search-forward "ken")
          (should (eq (key-binding (kbd "RET")) #'agent-workspace-sidebar-open))
          (agent-workspace-sidebar-open)))
      (should (equal opened project))
      (should (eq selected ken)))))

;; ====== THE TALLY ======

(ert-deftest agent-workspace-sidebar/the-mode-line-s-tally ()
  "Elsewhere, the mode line says what needs you: hands raised, done, stuck
\(not who works); all: who works too; nil: nothing."
  (+test-aws "tally"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken")))
      (agent-workspace-open t)
      (agent-workspace-leave)
      (setf (agent-workspace-agent-state ada) 'working
            (agent-workspace-agent-state ken) 'done)
      (let ((agent-workspace-mode-line-tally 'needs-you))
        (should (equal (substring-no-properties (agent-workspace--tally-mode-line)) " ✓1 ")))
      (let ((agent-workspace-mode-line-tally 'all))
        (should (string-match-p "1 ✓1" (substring-no-properties (agent-workspace--tally-mode-line)))))
      (let ((agent-workspace-mode-line-tally nil))
        (should-not (agent-workspace--tally-mode-line)))
      (setf (agent-workspace-agent-state ken) 'desk)
      (should (equal (agent-workspace--tally-mode-line) "")))))
