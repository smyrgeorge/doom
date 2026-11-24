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
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
;; The stand-in's modes: Claude Code's, as it lists them; it starts in auto.
(add-to-list 'agent-workspace-kinds `(mock :config agent-shell-mock-agent-make-agent-config :modes ,agent-workspace-modes :mode "auto"))

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
       (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore))
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

(ert-deftest agent-workspace-hands/A-answers-only-what-it-showed ()
  "A's prompt open on ada's request, another asked meanwhile (output read
as it waits): what you picked answers nothing, said; the new one still
waits (doom-pbk.150: it got your answer)."
  (+test-awh "A-changed"
    (agent-workspace-send ada "permission please" :submit t)
    (should (+test-awh--wait (lambda () (eq (agent-workspace-agent-state ada) 'hand))))
    (agent-workspace-select ada)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt options &rest _)
                 (agent-workspace--raise-hand ada (list :kind 'permission :title "rm -rf build"
                                                        :tool-kind "execute" :request-id 99))
                 (car options))))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (should (string-search "ada no longer asks that: nothing answered"
                               (cadr (should-error (agent-workspace-answer) :type 'user-error))))))
    (should (eq (agent-workspace-agent-state ada) 'hand))
    (should (eql (plist-get (agent-workspace-agent-ask ada) :request-id) 99))))

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
a view of its Agent UI, \"ask\", the cursor left where it was; its raised
hand's Go to it, and a, show it, the cursor on the question; answered there,
sam gets the answer, the ask view goes, its Agent UI closes."
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
        (should (+test-awh--wait (lambda () (not (agent-workspace--views-window sam)))))
        (should (get-buffer-window session))
        (should (eq (window-buffer (get-buffer-window session)) session))))))

(ert-deftest agent-workspace-hands/a-button-answers-only-its-own-request ()
  "A room line's buttons answer only the request it names: a line from an
earlier session with the same request id gets none; a second request
while the first waits posts its own line with the buttons, the first's
gone, and a button of the first pressed still says so and answers nothing
\(doom-pbk.44)."
  (+test-awh "own"
    (let ((pressed nil))
      (cl-letf (((symbol-function 'agent-workspace--go-to-hand)
                 (lambda (agent) (push (plist-get (agent-workspace-agent-ask agent) :title) pressed))))
        (cl-flet ((count (text) (with-temp-buffer
                                  (insert (+test-awh--feed project))
                                  (count-matches (regexp-quote text) (point-min) (point-max)))))
          ;; (a) An earlier session's line, its request's id 7, as this one's.
          (agent-workspace-room-post project :kind 'hand :agent "ada" :text "wants to run rm -rf build" :ask 7)
          (agent-workspace--raise-hand ada '(:kind question :title "git status" :request-id 7))
          (let ((feed (+test-awh--feed project)))
            (should (= (count "[Go to it]") 1))
            (should (< (string-search "asks: git status" feed) (string-search "[Go to it]" feed))))
          ;; (b) A second request while it waits: a line of its own, the buttons there.
          (let ((first (with-current-buffer (agent-workspace--room-buffer project)
                         (goto-char (point-min))
                         (search-forward "[Go to it]")
                         (lookup-key (get-text-property (1- (point)) 'keymap) (kbd "RET")))))
            (agent-workspace--raise-hand ada '(:kind question :title "git push --force" :request-id 8))
            (let ((feed (+test-awh--feed project)))
              (should (= (count "asks: git status") 1))
              (should (= (count "asks: git push --force") 1))
              (should (= (count "[Go to it]") 1))
              (should (< (string-search "asks: git push --force" feed) (string-search "[Go to it]" feed))))
            ;; The first's button, pressed: said, nothing answered.
            (should (equal (cadr (should-error (funcall first) :type 'user-error))
                           "ada no longer asks that: nothing answered"))
            (should-not pressed)
            (+test-awh--press project "Go to it")
            (should (equal pressed '("git push --force")))))))))

(ert-deftest agent-workspace-hands/a-hand-wraps-under-the-text ()
  "A raised hand's lines in a narrow room (60, 78 columns), its buttons'
too: each wraps under the room's text column, never at column 0
\(doom-pbk.89)."
  (+test-awh "wraps"
    (agent-workspace--raise-hand ada '(:kind question :title "Which of the three parsers should the lexer feed, the old one or the new one?"))
    (dolist (width '(60 78))
      (let ((lines (agent-workspace--room-entry-lines
                    project (car (last (with-current-buffer (agent-workspace--room-buffer project)
                                         agent-workspace--room-entries)))
                    width)))
        (should (= (length lines) 2))
        (dolist (line lines)
          (should (equal (get-text-property 0 'wrap-prefix line)
                         (make-string agent-workspace--room-indent ?\s))))))))

(ert-deftest agent-workspace-hands/no-hand-no-options ()
  (+test-awh "none"
    (should-not (agent-workspace-hand-options ada))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (should-error (agent-workspace-answer) :type 'user-error))))

;; ====== IN A TURN IT STARTS BY ITSELF ======

(ert-deftest agent-workspace-hands/a-question-asked-in-a-turn-it-started ()
  "Woken by a background task (the stand-in's \"background\"), it asks a
question on its canvas in that turn: at the turn's end (its model's
result) its hand is raised for it, as at a prompt's answer; its reply in
the room (doom-pbk.143: done, nothing said)."
  (+test-awh "self-asked"
    (agent-workspace-send ada "background" :submit t)
    (should (+test-awh--wait (lambda () (memq (agent-workspace-agent-state ada) '(done desk)))))
    (should (+test-awh--wait (lambda () (eq (agent-workspace-agent-state ada) 'working)) 10))
    (let ((agent-ui-display-function #'ignore))
      (agent-ui-show '(:id "q1" :type "choice" :question "Merge it?" :options ("Merge" "Wait"))
                     :canvas (agent-ui--session-name (agent-workspace-agent-buffer ada))))
    (should (+test-awh--wait (lambda () (eq (agent-workspace-agent-state ada) 'hand)) 10))
    (should (equal (plist-get (agent-workspace-agent-ask ada) :id) "q1"))
    (should (equal (mapcar #'car (agent-workspace-hand-options ada)) '("Merge" "Wait")))
    (should-not (gethash ada agent-workspace--self-turns))
    (should (+test-awh--wait (lambda () (string-search "the suite passed" (+test-awh--feed project))) 5))))

(ert-deftest agent-workspace-hands/its-canvas-question-through-a-turn-it-started ()
  "Its hand raised for a question on its canvas, then woken by a background
task: the hand stays raised through that turn and after it (its answer is
a prompt), its options still there; answered, it works."
  (+test-awh "self-hand"
    (agent-workspace-send ada "background" :submit t)
    (should (+test-awh--wait (lambda () (memq (agent-workspace-agent-state ada) '(done desk)))))
    (+test-awh--canvas-question ada)
    (should (eq (agent-workspace-agent-state ada) 'hand))
    (should (+test-awh--wait (lambda () (gethash ada agent-workspace--self-turns)) 10))
    (should (eq (agent-workspace-agent-state ada) 'hand))
    (should (+test-awh--wait (lambda () (not (gethash ada agent-workspace--self-turns))) 10))
    (should (eq (agent-workspace-agent-state ada) 'hand))
    (should (equal (plist-get (agent-workspace-agent-ask ada) :id) "q1"))
    (should (equal (mapcar #'car (agent-workspace-hand-options ada)) '("Restore" "Rebuild")))
    (+test-awh--press project "Rebuild")
    (should (+test-awh--wait (lambda () (member "Answer to choice q1 (Restore or rebuild?): Rebuild"
                                                (+test-awh--prompts "ada")))))
    (should (+test-awh--wait (lambda () (memq (agent-workspace-agent-state ada) '(done desk)))))))
