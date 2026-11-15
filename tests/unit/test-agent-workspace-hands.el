;;; tests/unit/test-agent-workspace-hands.el -*- lexical-binding: t; -*-
;; config/agent-workspace/hands.el: raised hands answered from one place. Two
;; stand-in agents (examples/agent-workspace/stand-in.el) in a crew's app: one asks for
;; a permission, the other a question on its Agent UI canvas; both answered
;; from the room's buttons (agent-shell's own pressed, the canvas's answer
;; given), and with A; their buttons on their bars; a hand answered elsewhere
;; leaving the room.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))

;; ====== HELPERS ======

(defvar +test-awh--log nil "The stand-in's log, this test's.")

(defun +test-awh--project (name)
  (let ((dir (file-name-as-directory (expand-file-name (concat "awh/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defun +test-awh--wait (predicate &optional timeout)
  (let ((end (+ (float-time) (or timeout 20))) value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defun +test-awh--prompts (name)
  "The prompts the agent NAME's agent got."
  (when (file-exists-p +test-awh--log)
    (with-temp-buffer
      (insert-file-contents +test-awh--log)
      (cl-loop for line in (split-string (buffer-string) "\n" t)
               for entry = (json-parse-string line :object-type 'plist :null-object nil :array-type 'list)
               when (and (equal (plist-get entry :agent) name) (equal (plist-get entry :method) "session/prompt"))
               collect (mapconcat (lambda (b) (plist-get b :text)) (plist-get (plist-get entry :params) :prompt) "")))))

(defmacro +test-awh (name &rest body)
  "BODY with two stand-in agents, ada and sam, at the desk in project NAME
\(`project'), its app open (220x40)."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awh--project ,name))
            (default-directory project)
            (+test-awh--log (expand-file-name (concat "awh/" ,name ".log") +test-tmp))
            (process-environment (cons (concat "MOCK_ACP_LOG=" +test-awh--log) process-environment)))
       (ignore-errors (delete-file +test-awh--log))
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ((symbol-function 'agent-workspace-new) (lambda (&rest _) (signal 'quit nil))))
         (unwind-protect
             (let ((ada (agent-workspace-create :role "builder" :name "ada" :kind 'mock))
                   (sam (agent-workspace-create :role "investigator" :name "sam" :kind 'mock)))
               (should (+test-awh--wait (lambda () (and (eq (agent-workspace-agent-state ada) 'desk)
                                                        (eq (agent-workspace-agent-state sam) 'desk)))))
               (agent-workspace-open t)
               ,@body)
           (when (agent-workspace--app project) (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awh--feed (project)
  (with-current-buffer (agent-workspace--room-buffer project)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-awh--press (project label)
  "Press the button LABEL in PROJECT's room, as RET on it does."
  (with-current-buffer (agent-workspace--room-buffer project)
    (goto-char (point-min))
    (should (search-forward (concat "[" label "]") nil t))
    (let ((map (get-text-property (1- (point)) 'keymap)))
      (call-interactively (lookup-key map (kbd "RET"))))))

(defun +test-awh--canvas-question (agent)
  "A choice waiting on AGENT's canvas, its turn ended: its hand raised."
  (let* ((session (agent-workspace-agent-buffer agent))
         (name (agent-ui--session-name session))
         (agent-ui-display-function #'ignore))
    (agent-ui-show '(:id "q1" :type "choice" :question "Restore or rebuild?" :options ("Restore" "Rebuild"))
                   :canvas name)
    (run-hook-with-args 'agent-ui-question-waiting-functions session
                        (get-buffer (agent-ui-canvas-buffer-name name)) "q1")))

;; ====== TESTS ======

(ert-deftest agent-workspace-hands/a-permission-and-a-question-from-the-room ()
  "ada asks for a permission, sam a question on its canvas: both answered
from the room's buttons; each goes on (its turn over: done, or at the desk
if its pane is open); the room says what you answered."
  (+test-awh "room"
    (agent-workspace-send ada "permission please" :submit t)
    (should (+test-awh--wait (lambda () (eq (agent-workspace-agent-state ada) 'hand))))
    (+test-awh--canvas-question sam)
    (should (eq (agent-workspace-agent-state sam) 'hand))
    (should (equal (mapcar #'car (agent-workspace-hand-options sam)) '("Restore" "Rebuild")))
    (should (string-prefix-p "Allow" (car (car (agent-workspace-hand-options ada)))))
    (let ((feed (+test-awh--feed project)))
      (should (string-search "wants to run npm install" feed))
      (should (string-search "asks: Restore or rebuild?" feed))
      (should (string-search "[Restore] [Rebuild]" feed)))
    ;; ada: Allow, agent-shell's own button pressed.
    (+test-awh--press project (car (car (agent-workspace-hand-options ada))))
    (should (+test-awh--wait (lambda () (memq (agent-workspace-agent-state ada) '(done desk)))))
    ;; sam: Rebuild, the canvas's answer sent.
    (+test-awh--press project "Rebuild")
    (should (+test-awh--wait (lambda () (member "Answer to choice q1 (Restore or rebuild?): Rebuild"
                                                (+test-awh--prompts "sam")))))
    (should (+test-awh--wait (lambda () (memq (agent-workspace-agent-state sam) '(done desk)))))
    ;; Answered, the question leaves its canvas (as answered there).
    (should (+test-awh--wait (lambda () (not (ignore-errors
                                               (agent-ui-get "q1" :canvas (agent-ui--session-name
                                                                           (agent-workspace-agent-buffer sam))))))))
    (let ((feed (+test-awh--feed project)))
      (should (string-search "→ Rebuild (you)" feed))
      (should (string-match-p "→ Allow[^\n]* (you)" feed))
      (should-not (string-search "[Restore]" feed)))))

(ert-deftest agent-workspace-hands/answered-with-A-and-from-a-bar ()
  "a: the next raised hand, its agent selected; A: its options picked
from; a hand's buttons on its agent's bar."
  (+test-awh "keys"
    (agent-workspace-send ada "permission please" :submit t)
    (should (+test-awh--wait (lambda () (eq (agent-workspace-agent-state ada) 'hand))))
    (agent-workspace-select sam)
    ;; Its bar (folded) shows its buttons.
    (should (string-search "[Allow" (with-current-buffer (agent-workspace--bar-buffer ada) (buffer-string))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-next-hand))
    (should (eq (agent-workspace--app-selected (agent-workspace--app project)) ada))
    (cl-letf (((symbol-function 'completing-read) (lambda (_prompt options &rest _) (car options))))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-answer)))
    (should (+test-awh--wait (lambda () (memq (agent-workspace-agent-state ada) '(done desk)))))))

(ert-deftest agent-workspace-hands/answered-elsewhere-leaves-the-room ()
  "A hand answered in its own session: its buttons leave the room (nothing
said answered from here)."
  (+test-awh "elsewhere"
    (agent-workspace-send ada "permission please" :submit t)
    (should (+test-awh--wait (lambda () (eq (agent-workspace-agent-state ada) 'hand))))
    (should (string-search "[Allow" (+test-awh--feed project)))
    (with-current-buffer (agent-workspace-agent-buffer ada)
      (agent-shell--send-permission-response
       :client (map-elt agent-shell--state :client)
       :request-id (plist-get (agent-workspace-agent-ask ada) :request-id)
       :option-id "allow" :state agent-shell--state :tool-call-id "t1"))
    (should (+test-awh--wait (lambda () (not (eq (agent-workspace-agent-state ada) 'hand)))))
    (should-not (string-search "[Allow" (+test-awh--feed project)))
    (should-not (string-search "(you)" (+test-awh--feed project)))))

(ert-deftest agent-workspace-hands/a-question-on-its-ask-canvas ()
  "sam asks on a canvas of its own (--canvas ask), as agents are told to:
it's a tab of its pane, \"ask\", the cursor left where it was; its raised
hand's Go to it, and a, show it, the cursor on the question; answered there,
sam gets the answer, the ask tab goes, its side area closes."
  (+test-awh "ask"
    (agent-workspace-select ada)
    (let* ((session (agent-workspace-agent-buffer sam))
           (name (agent-ui-sub-canvas (agent-ui--session-name session) "ask"))
           (was (selected-window)))
      (agent-ui-show '(:id "push" :type "confirm" :question "Push?") :canvas name)
      (let ((ask (get-buffer (agent-ui-canvas-buffer-name name))))
        ;; Agent UI tied it to sam's session: the stage's, a tab of its pane.
        (should (eq (agent-workspace--canvas-agent ask) sam))
        (should (equal (agent-workspace-agent-tabs sam) (list ask)))
        (should (equal (agent-workspace--tab-name ask) "ask"))
        (should-not (buffer-local-value 'agent-ui-focus-questions ask))
        (should (eq (selected-window) was))
        ;; Its turn ended with it waiting: its hand raised, Go to it.
        (run-hook-with-args 'agent-ui-question-waiting-functions session ask "push")
        (should (eq (agent-workspace-agent-state sam) 'hand))
        (should (equal (mapcar #'car (agent-workspace-hand-options sam)) '("Go to it")))
        ;; Go to it: sam's pane open, its ask tab shown, the cursor on it.
        (agent-workspace-hand-answer sam "Go to it")
        (should (eq (agent-workspace--app-selected (agent-workspace--app project)) sam))
        (should (eq (window-buffer) ask))
        (should (equal (get-text-property (window-point) 'agent-ui-id ask) "push"))
        ;; a, from elsewhere: the same.
        (agent-workspace-select ada t)
        (with-current-buffer (agent-workspace--issues-buffer project)
          (agent-workspace-next-hand))
        (should (eq (agent-workspace--app-selected (agent-workspace--app project)) sam))
        (should (eq (window-buffer) ask))
        (should (equal (get-text-property (window-point) 'agent-ui-id ask) "push"))
        ;; Proceed: sam gets it; the ask canvas emptied, killed, its tab gone,
        ;; sam's session alone in its pane.
        (with-current-buffer ask
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Proceed")
          (goto-char (match-beginning 0))
          (agent-ui-button-press))
        (should (+test-awh--wait (lambda () (member "Answer to confirm push (Push?): proceed"
                                                    (+test-awh--prompts "sam")))))
        (should (+test-awh--wait (lambda () (not (buffer-live-p ask)))))
        (should (+test-awh--wait (lambda () (not (agent-workspace--side-window sam)))))
        (should (get-buffer-window session))
        (should (eq (window-buffer (get-buffer-window session)) session))))))

(ert-deftest agent-workspace-hands/no-hand-no-options ()
  (+test-awh "none"
    (should-not (agent-workspace-hand-options ada))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (should-error (agent-workspace-answer) :type 'user-error))))
