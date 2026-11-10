;;; tests/unit/test-agent-ui-agent.el -*- lexical-binding: t; -*-
;; config/agent-ui/agent.el: agent-shell's sessions and their canvases. The
;; agent started with AGENT_UI_SESSION; a request finding its session by it,
;; else by its directory; the canvas named after the session, killed with it.
;; No agent runs: sessions are buffers the tests make.

(+test-load "config/agent-ui")
(require 'agent-shell)
;; agent-shell-elicitation.el's (loaded with agent-shell, or not): special.
(defvar agent-shell-elicitation--experimental-feature-enabled)

;; ====== HELPERS ======

(defvar +test-aua-sessions nil "The sessions `agent-ui--sessions' gives, most recent first.")

(defmacro +test-aua (&rest body)
  "BODY with no window shown and only `+test-aua-sessions' as agent-shell's
sessions (each's directory its `default-directory'); the buffers it makes,
killed after."
  (declare (indent 0))
  `(let ((agent-ui-display-function #'ignore)
         (+test-aua-sessions nil)
         (before (buffer-list)))
     (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () +test-aua-sessions))
               ((symbol-function 'agent-shell-cwd) (lambda () default-directory)))
       (unwind-protect (progn ,@body)
         (dolist (b (buffer-list))
           (unless (memq b before) (kill-buffer b)))))))

(defun +test-aua-session (name dir)
  "A session's buffer NAME working in DIR, the most recent."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer (setq default-directory (file-name-as-directory dir)))
    (push buffer +test-aua-sessions)
    buffer))

;; ====== THE AGENT'S ENVIRONMENT ======

(ert-deftest agent-ui-agent/the-session-in-the-agents-environment ()
  (+test-aua
    (should (advice-member-p 'agent-ui-session-environment 'agent-shell--make-acp-client))
    (let* ((session (+test-aua-session "Claude Agent @ proj" "/tmp/"))
           (client (agent-shell--make-acp-client :command "true"
                                                 :environment-variables '("A=1")
                                                 :context-buffer session)))
      (should (equal (map-elt client :environment-variables)
                     '("AGENT_UI_SESSION=Claude Agent @ proj" "A=1")))
      ;; Its name kept: renamed, and through a change of major mode.
      (with-current-buffer session
        (rename-buffer "Renamed")
        (fundamental-mode)
        (should (equal agent-ui-session "Claude Agent @ proj")))
      (should (equal (map-elt (agent-shell--make-acp-client :command "true" :context-buffer session)
                              :environment-variables)
                     '("AGENT_UI_SESSION=Claude Agent @ proj"))))
    ;; No session buffer: nothing added.
    (should (equal (map-elt (agent-shell--make-acp-client :command "true"
                                                          :environment-variables '("A=1"))
                            :environment-variables)
                   '("A=1")))))

;; ====== FINDING THE SESSION ======

(ert-deftest agent-ui-agent/the-session-by-name ()
  (+test-aua
    (let ((a (+test-aua-session "A" "/tmp/x/"))
          (b (+test-aua-session "B" "/tmp/x/")))
      (with-current-buffer a (setq agent-ui-session "sa"))
      (with-current-buffer b (setq agent-ui-session "sb"))
      (should (eq (agent-ui--session-buffer "sa" "/tmp/x/") a))
      (should (eq (agent-ui--session-buffer "sb" nil) b)))))

(ert-deftest agent-ui-agent/the-session-by-directory ()
  (+test-aua
    (let* ((root (+test-aua-session "root" "/tmp/proj/"))
           (deep (+test-aua-session "deep" "/tmp/proj/sub/"))
           (other (+test-aua-session "other" "/tmp/elsewhere/")))
      (ignore other)
      ;; The deepest working at or above it.
      (should (eq (agent-ui--session-buffer nil "/tmp/proj/sub/dir") deep))
      (should (eq (agent-ui--session-buffer nil "/tmp/proj/sub") deep))
      (should (eq (agent-ui--session-buffer nil "/tmp/proj/lib") root))
      (should (eq (agent-ui--session-buffer nil "/tmp/proj") root))
      (should-not (agent-ui--session-buffer nil "/tmp/pro"))
      (should-not (agent-ui--session-buffer nil nil))
      ;; Two as deep: the most recently used.
      (let ((recent (+test-aua-session "recent" "/tmp/proj/")))
        (should (eq (agent-ui--session-buffer nil "/tmp/proj/lib") recent)))
      ;; A name no session has: by its directory.
      (should (eq (agent-ui--session-buffer "gone" "/tmp/proj/sub") deep)))))

;; ====== THE SESSION'S CANVAS ======

(ert-deftest agent-ui-agent/the-sessions-canvas ()
  (+test-aua
    (should (eq agent-ui-canvas-function #'agent-ui-session-canvas))
    (let* ((session (+test-aua-session "Claude Agent @ proj" "/tmp/proj/"))
           (name (agent-ui-session-canvas nil "/tmp/proj/src")))
      ;; Its name, the session's; no canvas made just for asking.
      (should (equal name "Claude Agent @ proj"))
      (should (equal (agent-ui-session-canvas "Claude Agent @ proj" nil) name))
      (should-not (get-buffer "Agent UI: Claude Agent @ proj"))
      ;; Made by the first element shown: tied to its session.
      (agent-ui-show '(:id "a" :type "text" :text "x") :canvas name)
      (let ((canvas (get-buffer "Agent UI: Claude Agent @ proj")))
        (should (eq (buffer-local-value 'agent-ui--session-buffer canvas) session))
        ;; Killed with its session.
        (kill-buffer session)
        (should-not (buffer-live-p canvas))))))

(ert-deftest agent-ui-agent/the-sessions-other-canvases ()
  (+test-aua
    (let* ((session (+test-aua-session "Claude Agent @ proj" "/tmp/proj/"))
           (other (+test-aua-session "Claude Agent @ proj / x" "/tmp/x/")))
      ;; Named as their agents start.
      (mapc #'agent-ui--session-name (list session other))
      (agent-ui-show '(:id "a" :type "text" :text "x") :canvas "Claude Agent @ proj")
      (agent-ui-show '(:id "a" :type "text" :text "y") :canvas "Claude Agent @ proj / tests")
      (let ((main (get-buffer "Agent UI: Claude Agent @ proj"))
            (tests (get-buffer "Agent UI: Claude Agent @ proj / tests")))
        ;; Tied to its session, its own name known.
        (should (eq (buffer-local-value 'agent-ui--session-buffer tests) session))
        (should (equal (buffer-local-value 'agent-ui--canvas-part tests) "tests"))
        (should-not (buffer-local-value 'agent-ui--canvas-part main))
        (should (equal (sort (mapcar #'buffer-name (agent-ui-session-canvases session)) #'string<)
                       '("Agent UI: Claude Agent @ proj" "Agent UI: Claude Agent @ proj / tests")))
        ;; A session whose name looks like another's canvas: its own.
        (agent-ui-show '(:id "a" :type "text" :text "z") :canvas "Claude Agent @ proj / x")
        (should (eq (buffer-local-value 'agent-ui--session-buffer
                                        (get-buffer "Agent UI: Claude Agent @ proj / x"))
                    other))
        ;; All killed with their session.
        (kill-buffer session)
        (should-not (buffer-live-p main))
        (should-not (buffer-live-p tests))
        (should (get-buffer "Agent UI: Claude Agent @ proj / x"))))))

(ert-deftest agent-ui-agent/no-session ()
  (+test-aua
    ;; By the name given, else the default.
    (should (equal (agent-ui-session-canvas "named" "/tmp/") "named"))
    (should (equal (agent-ui-session-canvas nil "/tmp/") agent-ui-default-canvas))
    (should (equal (agent-ui-session-canvas "" nil) agent-ui-default-canvas))))

(ert-deftest agent-ui-agent/a-canvas-another-session-took-kept ()
  (+test-aua
    ;; Two sessions named alike in turn: killing the first leaves the
    ;; second's canvas.
    (let* ((first (+test-aua-session "S" "/tmp/a/"))
           (name (agent-ui-session-canvas nil "/tmp/a/"))
           (canvas (agent-ui-canvas name)))
      (with-current-buffer canvas (setq agent-ui--session-buffer (generate-new-buffer "other")))
      (kill-buffer first)
      (should (buffer-live-p canvas)))))

(ert-deftest agent-ui-agent/a-canvas-without-its-session ()
  (+test-aua
    ;; A canvas named after no session: tied to none.
    (let ((canvas (agent-ui-canvas (make-temp-name "nobody-"))))
      (should-not (buffer-local-value 'agent-ui--session-buffer canvas)))))

;; ====== WHAT THE AGENT IS TOLD ======

(ert-deftest agent-ui-agent/told-in-its-system-prompt ()
  (should (memq #'agent-ui-agent-context +my/agent-shell-claude-context-functions))
  (should (file-executable-p agent-ui-command))
  (should (equal agent-ui-command (expand-file-name "cmd/agent-ui" +test-root)))
  (should (equal agent-ui-skill (expand-file-name "skills/agent-ui/SKILL.md" +test-root)))
  (should (file-exists-p agent-ui-skill))
  ;; Without a server, nothing: the command couldn't reach Emacs.
  (cl-letf (((symbol-function 'server-running-p) #'ignore))
    (should-not (agent-ui-agent-context)))
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
    (let ((text (agent-ui-agent-context)))
      (should (string-prefix-p "Agent UI: beside this session" text))
      ;; Where the command and the skill are.
      (should (string-search (concat (abbreviate-file-name agent-ui-command) " show '{\"id\":\"build\"")
                             text))
      (should (string-search (concat "then " (abbreviate-file-name agent-ui-command)
                                     " update build '{\"value\":5}'")
                             text))
      (should (string-search (concat "read " (abbreviate-file-name agent-ui-skill)) text))
      ;; Issues and plans: on the canvas without being asked, each in its form.
      (should (string-search "Issues and plans go there too, always, without being asked" text))
      (should (string-search "as the issues board" text))
      (should (string-search "as steps (its acceptance criteria)" text))
      ;; Questions: a list to pick from on the canvas, the turn ended.
      (should (string-search "To have the user pick from a list" text))
      (should (string-search "end your turn: the answer comes as your next prompt" text))
      ;; A bug in Agent UI itself: asked, filed in its own issues.
      (should (string-search (concat "When Agent UI itself misbehaves") text))
      (should (string-search (concat (abbreviate-file-name agent-ui-command) " bug '{\"title\"") text))
      (should (string-search "never this project's" text))
      ;; Its example is right.
      (string-match "show '\\([^']+\\)'" text)
      (should (agent-ui-check "progress" (agent-ui-parse-json (match-string 1 text)))))))

(ert-deftest agent-ui-agent/small-questions-in-the-conversation ()
  "AskUserQuestion named only while agent-shell shows its forms (else the
agent hasn't the tool)."
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
    (let ((agent-shell-elicitation--experimental-feature-enabled t))
      (should (string-search "ask it with AskUserQuestion, in the conversation" (agent-ui-agent-context))))
    (let ((agent-shell-elicitation--experimental-feature-enabled nil))
      (should-not (string-search "AskUserQuestion" (agent-ui-agent-context))))))

(defun +test-aua-skill ()
  (with-temp-buffer
    (insert-file-contents agent-ui-skill)
    (buffer-string)))

(ert-deftest agent-ui-agent/the-skill ()
  (let ((skill (+test-aua-skill)))
    (should (string-prefix-p "---\nname: agent-ui\ndescription: >-\n" skill))
    ;; Each type has its section; each section a type.
    (should (equal (let ((pos 0) names)
                     (while (string-match "^### `\\([a-z-]+\\)`$" skill pos)
                       (push (intern (match-string 1 skill)) names)
                       (setq pos (match-end 0)))
                     (sort names (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
                   (agent-ui-types)))
    ;; Issues and plans: shown without being asked (doom-nwj.20).
    (should (string-search "**Issues and plans, always, without being asked:**" skill))
    ;; Each operation it names, the command's.
    (dolist (op agent-ui-operations)
      (should (string-match-p (concat "^agent-ui " op "\\b") skill)))))

(ert-deftest agent-ui-agent/the-skills-examples-right ()
  "Each `agent-ui show/update/append ... '{...}'' in the skill: its JSON is
right, and does what it says on a canvas, in order. Its issues board isn't
fetched: bd would read this repository's own issues."
  (cl-letf (((symbol-function 'agent-ui-issues-refresh) #'ignore))
  (+test-aua
    (let ((agent-ui-default-canvas (make-temp-name "skill-"))
          (skill (+test-aua-skill))
          (pos 0)
          (count 0))
      (while (string-match "^agent-ui \\(show\\|update\\|append\\) \\(?:\\([a-z]+\\) \\)?'\\({.*}\\)'$"
                           skill pos)
        (let ((op (match-string 1 skill))
              (id (match-string 2 skill))
              (json (agent-ui-parse-json (match-string 3 skill))))
          (setq pos (match-end 0))
          (cl-incf count)
          (pcase op
            ("show" (should (agent-ui-show json)))
            ("update" (should (agent-ui-update id json)))
            ("append" (should (agent-ui-append id json))))))
      (should (>= count 12))
      ;; Drawn without an error.
      (with-current-buffer (agent-ui-canvas)
        (agent-ui--flush)
        (should-not (string-search "⚠" (buffer-string))))))))

;; ====== ACTIONS ======

(ert-deftest agent-ui-agent/an-action-into-the-sessions-prompt ()
  (+test-aua
    (should (eq agent-ui-action-function #'agent-ui--act))
    (let* ((session (+test-aua-session "Claude Agent @ act" "/tmp/act/"))
           (name (agent-ui--session-name session))
           (inserted nil))
      (agent-ui-show '(:id "t" :type "text" :text "2 failed"
                       :actions ((:label "Retry" :prompt "Run the 2 failing tests again" :submit t)))
                     :canvas name)
      ;; Wrong actions: refused with the element.
      (should (string-match-p "action 1's prompt"
                              (agent-ui-error-message
                               (should-error (agent-ui-show '(:id "u" :type "text" :text "x" :actions ((:label "a")))
                                                            :canvas name)
                                             :type 'agent-ui-error))))
      (cl-letf (((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted))))
        (with-current-buffer (agent-ui-canvas-buffer-name name)
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Retry")
          (goto-char (match-beginning 0))
          (agent-ui-button-press)))
      (should (equal (car inserted) (list :text "Run the 2 failing tests again" :submit t :shell-buffer session)))
      ;; A canvas of no session: said.
      (let ((agent-ui-default-canvas (make-temp-name "lonely-")))
        (agent-ui-show '(:id "t" :type "text" :text "x" :actions ((:label "Go" :prompt "go"))))
        (with-current-buffer (agent-ui-canvas)
          (goto-char (point-min))
          (search-forward "⏵ Go")
          (goto-char (match-beginning 0))
          (should (string-match-p "no agent-shell session"
                                  (cadr (should-error (agent-ui-button-press) :type 'user-error)))))))))

(defun +test-aua-press (canvas label)
  "The button LABEL in CANVAS's buffer, pressed."
  (with-current-buffer canvas
    (agent-ui--flush)
    (goto-char (point-min))
    (search-forward label)
    (goto-char (match-beginning 0))
    (agent-ui-button-press)))

(ert-deftest agent-ui-agent/an-action-while-the-agent-works ()
  "While the session's prompt takes no text (its agent working): a button
sending its prompt queues it; one putting it into the prompt offers it,
changed or not, to queue. Never agent-shell's \"Busy, try later\"."
  (+test-aua
    (let* ((session (+test-aua-session "Claude Agent @ busy" "/tmp/busy/"))
           (name (agent-ui--session-name session))
           (busy t) inserted queued offered)
      (agent-ui-show '(:id "t" :type "text" :text "2 failed"
                       :actions ((:label "Retry" :prompt "Run them again" :submit t)
                                 (:label "Fix" :prompt "Fix the 2 failing tests")))
                     :canvas name)
      (cl-letf (((symbol-function 'agent-shell--can-insert-into-prompt-p) (lambda (&rest _) (not busy)))
                ((symbol-function 'agent-shell-insert)
                 (lambda (&rest _) (if busy (user-error "Busy, try later") (push 'inserted inserted))))
                ((symbol-function 'agent-shell-prompt-queue)
                 (lambda (prompt) (push (list prompt (current-buffer)) queued)))
                ((symbol-function 'agent-shell--prompt-queue-read)
                 (lambda (&rest args) (push args offered) "Fix the 2 failing tests, the parser's first")))
        (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name))))
          ;; Sent: queued as it is, in its session.
          (+test-aua-press canvas "⏵ Retry")
          (should (equal queued (list (list "Run them again" session))))
          ;; Into the prompt: offered to queue, as changed.
          (+test-aua-press canvas "⏵ Fix")
          (should (equal offered '((:initial "Fix the 2 failing tests"))))
          (should (equal (car queued) (list "Fix the 2 failing tests, the parser's first" session)))
          (should-not inserted)
          ;; Done working: into the prompt again.
          (setq busy nil)
          (+test-aua-press canvas "⏵ Fix")
          (should (equal inserted '(inserted)))
          (should (= (length queued) 2)))))))

;; ====== A QUESTION WAITING ======

(ert-deftest agent-ui-agent/what-waits-for-an-answer ()
  "A choice, an element with select, not answered: waits. Answered, or not
asking: doesn't."
  (should (agent-ui-ask-waiting-p '(:type "choice" :question "q" :options ("a"))))
  (should-not (agent-ui-ask-waiting-p '(:type "choice" :question "q" :options ("a") :answered "a")))
  (should (agent-ui-ask-waiting-p '(:type "table" :rows (("x")) :select (:question "Which?"))))
  (should-not (agent-ui-ask-waiting-p '(:type "table" :rows (("x")) :select (:question "Which?") :answered "x")))
  (should-not (agent-ui-ask-waiting-p '(:type "text" :text "x")))
  (should (equal (agent-ui-ask-question '(:type "choice" :question "Which fix?")) "Which fix?"))
  (should (equal (agent-ui-ask-question '(:type "files" :select (:question "Which files?"))) "Which files?")))

(defmacro +test-aua-turns (&rest body)
  "BODY with a session (`session') and its canvas (`canvas'), its turn's end
`turn-end' (a function of a new event), the panes shown recorded in
`shown', `agent-ui-question-waiting-functions' calls in `said'."
  (declare (indent 0))
  `(+test-aua
     (let* ((session (+test-aua-session "Claude Agent @ ask" "/tmp/ask/"))
            (name (agent-ui--session-name session))
            (shown nil) (said nil) (on-event nil)
            (agent-ui-display-function (lambda (b) (push b shown)))
            (agent-ui-question-waiting-functions (list (lambda (&rest args) (push args said)))))
       (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                  (lambda (&rest args)
                    (should (eq (plist-get args :event) 'turn-complete))
                    (setq on-event (plist-get args :on-event)))))
         (with-current-buffer session (agent-ui--watch-questions-h)))
       (agent-ui-show '(:id "intro" :type "text" :text "Two ways to fix it:") :canvas name)
       ;; Its first element showed its pane: not the question's.
       (setq shown nil)
       (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name)))
             (turn-end (lambda () (let ((event (list (cons :event 'turn-complete))))
                                    (with-current-buffer session (funcall on-event event))
                                    event))))
         (ignore canvas turn-end)
         ,@body))))

(ert-deftest agent-ui-agent/a-question-waiting-at-the-turns-end ()
  "The turn ended with a question not answered: its pane shown, the cursor on
it, said (the hook); the session's mode line says so until it's answered."
  (should (memq #'agent-ui--watch-questions-h (default-value 'agent-shell-mode-hook)))
  (should (member '(:eval (agent-ui--question-mode-line)) mode-line-misc-info))
  (+test-aua-turns
    ;; Nothing asked: nothing.
    (funcall turn-end)
    (should-not (or shown said (buffer-local-value 'agent-ui--question-waiting session)))
    ;; A choice: shown, the cursor on it, said.
    (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?" :options ("Test" "Revert")) :canvas name)
    (setq shown nil)
    (funcall turn-end)
    (should (equal shown (list canvas)))
    (should (equal said (list (list session canvas "fix"))))
    (with-current-buffer canvas
      (should (equal (get-text-property (point) 'agent-ui-id) "fix"))
      (should (looking-at-p "Which fix?")))
    (with-current-buffer session
      (should agent-ui--question-waiting)
      (should (string-match-p "question waiting" (agent-ui--question-mode-line))))
    ;; Another turn, the same question still waiting: not said again.
    (setq said nil shown nil)
    (funcall turn-end)
    (should-not (or said shown))
    (should (buffer-local-value 'agent-ui--question-waiting session))
    ;; Answered: the mark gone.
    (agent-ui-update "fix" '(:answered "Test") :canvas canvas)
    (should-not (buffer-local-value 'agent-ui--question-waiting session))
    (should (equal (with-current-buffer session (agent-ui--question-mode-line)) ""))))

(ert-deftest agent-ui-agent/a-panels-question-and-rows-to-pick ()
  "A panel's child asking, a table's rows to pick: waiting too, the cursor on
the child; the mark there until each is answered."
  (+test-aua-turns
    (agent-ui-show '(:id "box" :type "panel" :title "Decide"
                     :children ((:id "note" :type "text" :text "Before I go on")
                                (:id "how" :type "choice" :question "How?" :options ("A" "B"))))
                   :canvas name)
    (agent-ui-show '(:id "pick" :type "table" :columns ("Test") :rows (("a") ("b"))
                     :select (:question "Which to rerun?" :multiple t))
                   :canvas name)
    (funcall turn-end)
    ;; The first one: the panel's child.
    (should (equal said (list (list session canvas "how"))))
    (with-current-buffer canvas
      (should (equal (get-text-property (point) 'agent-ui-child) "how")))
    (agent-ui-update "how" '(:answered "A") :canvas canvas)
    (should (buffer-local-value 'agent-ui--question-waiting session))
    (agent-ui-update "pick" '(:answered "a") :canvas canvas)
    (should-not (buffer-local-value 'agent-ui--question-waiting session))))

(ert-deftest agent-ui-agent/a-new-question-said-once-the-same-for-all ()
  "Each turn's end says the questions new since the last one; everyone
looking at the same turn's end (its notification) gets the same."
  (+test-aua-turns
    (agent-ui-show '(:id "q1" :type "choice" :question "One?" :options ("a")) :canvas name)
    (let ((event (funcall turn-end)))
      ;; The same event asked again (the notification, after): the same.
      (should (equal (agent-ui-questions-new session event) (list (cons canvas "q1"))))
      (should (equal (agent-ui-questions-new session event) (list (cons canvas "q1")))))
    ;; A second question, the first still waiting: the second said.
    (agent-ui-show '(:id "q2" :type "choice" :question "Two?" :options ("b")) :canvas name)
    (setq said nil)
    (funcall turn-end)
    (should (equal said (list (list session canvas "q2"))))
    (with-current-buffer canvas
      (should (equal (get-text-property (point) 'agent-ui-id) "q2")))
    ;; Another session's canvas: not this one's.
    (let* ((other (+test-aua-session "Claude Agent @ other" "/tmp/other/")))
      (agent-ui-show '(:id "q3" :type "choice" :question "Three?" :options ("c"))
                     :canvas (agent-ui--session-name other))
      (should (equal (mapcar #'cdr (agent-ui--waiting session)) '("q1" "q2")))
      (should (equal (mapcar #'cdr (agent-ui--waiting other)) '("q3"))))))

(ert-deftest agent-ui-agent/going-to-the-question-waiting ()
  "C-c C-q in a session: its canvas's pane selected, the cursor on its
question; none waiting: said."
  (should (eq (keymap-lookup agent-shell-mode-map "C-c C-q") #'agent-ui-goto-question))
  (+test-aua-turns
    (setq agent-ui-display-function #'agent-ui-display-canvas)
    (dotimes (i 60)
      (agent-ui-show (list :id (format "line%d" i) :type "text" :text (format "line %d" i)) :canvas name))
    (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?" :options ("Test" "Revert")) :canvas name)
    (delete-other-windows)
    (switch-to-buffer session)
    (with-current-buffer session
      (agent-ui-goto-question))
    (should (eq (window-buffer (selected-window)) canvas))
    (should (equal (get-text-property (window-point) 'agent-ui-id canvas) "fix"))
    ;; From the canvas, its session's.
    (with-current-buffer canvas
      (goto-char (point-min))
      (agent-ui-goto-question)
      (should (equal (get-text-property (point) 'agent-ui-id) "fix")))
    (agent-ui-update "fix" '(:answered "Test") :canvas canvas)
    (switch-to-buffer session)
    (should (equal (cadr (should-error (agent-ui-goto-question) :type 'user-error)) "No question waits"))))
