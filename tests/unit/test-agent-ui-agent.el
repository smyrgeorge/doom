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
      ;; Its references read only when needed (doom-9sf).
      (should (string-search "which of its references to read only when needed" text))
      ;; Issues and plans: on the canvas without being asked, each in its form.
      (should (string-search "Issues and plans go there too, always, without being asked" text))
      (should (string-search "as the issues board" text))
      (should (string-search "as steps (its acceptance criteria)" text))
      ;; Questions: a list to pick from on the canvas, the turn ended.
      (should (string-search "To have the user pick from a list" text))
      (should (string-search "end your turn: the answer comes as your next prompt" text))
      (should (string-search "before something risky (a force-push, a deploy, deleting data), a confirm" text))
      (should (string-search "Ask on a canvas of its own (--canvas ask)" text))
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
  "The skill's text, all of it: SKILL.md and its references."
  (+test-agent-ui-skill))

(defconst +test-aua-skill-budget (* 12 1024)
  "The most SKILL.md may weigh, in bytes: read whole by each agent using
the canvas, what's needed only at times goes into its references.")

(ert-deftest agent-ui-agent/the-skill ()
  (let ((skill (+test-aua-skill))
        (core (+test-agent-ui-skill "SKILL.md")))
    (should (string-prefix-p "---\nname: agent-ui\ndescription: >-\n" core))
    ;; Each type has its section, in SKILL.md or a reference; each section a
    ;; type, once.
    (should (equal (let ((pos 0) names)
                     (while (string-match "^### `\\([a-z-]+\\)`$" skill pos)
                       (push (intern (match-string 1 skill)) names)
                       (setq pos (match-end 0)))
                     (sort names (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
                   (agent-ui-types)))
    ;; Issues and plans: shown without being asked (doom-nwj.20).
    (should (string-search "**Issues and plans, always, without being asked:**" core))
    ;; Each operation it names, the command's, in the core.
    (dolist (op agent-ui-operations)
      (should (string-match-p (concat "^agent-ui " op "\\b") core)))))

(ert-deftest agent-ui-agent/the-skill-loaded-as-needed ()
  "SKILL.md, read whole, kept small: every type named in its catalog, the
rest in references it points to, each read when the task needs it
(doom-9sf)."
  (let* ((dir (file-name-directory agent-ui-skill))
         (core (+test-agent-ui-skill "SKILL.md"))
         (catalog (progn (string-match "^## The types\n\\(\\(?:.\\|\n\\)*?\\)\n### " core)
                         (match-string 1 core)))
         (references (directory-files (expand-file-name "references/" dir) nil "\\.md\\'")))
    (should (< (file-attribute-size (file-attributes agent-ui-skill)) +test-aua-skill-budget))
    ;; Every type in the catalog.
    (dolist (type (agent-ui-types))
      (should (string-search (format "`%s`" type) catalog)))
    ;; Every reference linked from what to read when; every link a file.
    (should (equal references '("asking.md" "bugs.md" "content.md" "custom-types.md" "data.md" "sources.md")))
    (let ((guide (substring core (string-search "## What to read when" core))))
      (dolist (file references)
        (should (string-search (format "(references/%s)" file) guide))))
    (let ((pos 0))
      (while (string-match "](references/\\([^)#]+\\))" core pos)
        (should (file-exists-p (expand-file-name (concat "references/" (match-string 1 core)) dir)))
        (setq pos (match-end 0))))
    ;; Each reference says where it belongs, and links to files there.
    (dolist (file references)
      (let ((text (+test-agent-ui-skill (concat "references/" file)))
            (pos 0))
        (should (string-match-p "\\`# " text))
        (should (string-search "read [SKILL.md](../SKILL.md) first" text))
        (while (string-match "](\\([a-z-]+\\.md\\))" text pos)
          (should (file-exists-p (expand-file-name (concat "references/" (match-string 1 text)) dir)))
          (setq pos (match-end 0)))))))

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
      ;; A question's on a canvas of its own (--canvas ask): all on this one here.
      (while (string-match "^agent-ui \\(show\\|update\\|append\\)\\(?: --canvas [a-z]+\\)? \\(?:\\([a-z]+\\) \\)?'\\({.*}\\)'$"
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

(ert-deftest agent-ui-agent/an-answer-sent-its-question-answered ()
  "agent-shell, inserting an answer, selects its session's window, its
buffer current then: the question is answered still, in its canvas (it was
left asking, its buttons there, the mode line's mark on), the session's
buffer still where agent-shell put it (doom-vb9)."
  (+test-aua
    (let* ((session (+test-aua-session "Claude Agent @ answer" "/tmp/answer/"))
           (name (agent-ui--session-name session))
           (canvas (agent-ui-canvas-buffer-name name))
           (sent nil))
      (agent-ui-show '(:id "plan" :type "steps" :approve t :steps ("Reproduce it" "Fix it")) :canvas name)
      (agent-ui-show '(:id "push" :type "confirm" :question "Push?") :canvas name)
      (cl-letf (((symbol-function 'agent-shell-insert)
                 (lambda (&rest args)
                   (push (plist-get args :text) sent)
                   ;; As agent-shell--display-buffer's select-window does.
                   (set-buffer (plist-get args :shell-buffer)))))
        (+test-aua-press canvas "⏵ Approve")
        (+test-aua-press canvas "⏵ Proceed"))
      (should (equal (reverse sent)
                     '("Answer to steps plan (Go ahead with this plan?): approved: 1. Reproduce it; 2. Fix it"
                       "Answer to confirm push (Push?): proceed")))
      (should (equal (plist-get (agent-ui-get "plan" :canvas name) :answered) "approved"))
      (should (equal (plist-get (agent-ui-get "push" :canvas name) :answered) "proceed"))
      (should-not (agent-ui-ask-waiting-p (agent-ui-get "plan" :canvas name)))
      (should-not (agent-ui-ask-waiting-p (agent-ui-get "push" :canvas name)))
      (with-current-buffer canvas
        (agent-ui--flush)
        (should-not (string-search "⏵ Approve" (buffer-string)))
        (should (string-search "✓ Approved" (buffer-string)))))))

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

(ert-deftest agent-ui-agent/a-canvas-closed-its-question-gone ()
  "The canvas with the question waiting killed (q closes it): the session's
mark gone at once (it stayed until the next turn's end); kept while another
of its canvases has one."
  (+test-aua-turns
    (let ((other (agent-ui-sub-canvas name "more")))
      (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?" :options ("Test" "Revert")) :canvas name)
      (agent-ui-show '(:id "pick" :type "tags" :tags ("bug" "docs") :select (:question "Which?")) :canvas other)
      (funcall turn-end)
      (should (buffer-local-value 'agent-ui--question-waiting session))
      ;; One closed, the other's still waiting: the mark stays.
      (kill-buffer canvas)
      (should (buffer-local-value 'agent-ui--question-waiting session))
      ;; Both closed: gone, before any turn ends.
      (kill-buffer (get-buffer (agent-ui-canvas-buffer-name other)))
      (should-not (buffer-local-value 'agent-ui--question-waiting session))
      (should (equal (with-current-buffer session (agent-ui--question-mode-line)) "")))))

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

;; ====== A QUESTION TAKES THE FOCUS; ANSWERED, IT GOES ======

(defun +test-aua-settle ()
  "Timers due now run (an answer's question goes after its command)."
  (let ((end (+ (float-time) 0.2)))
    (while (< (float-time) end) (accept-process-output nil 0.02))))

(ert-deftest agent-ui-agent/a-question-takes-the-focus ()
  "A question shown: once Emacs is idle a moment, its pane selected, the
cursor on it. Not another element, not one coming back with its session,
not with the option off (the library's own default)."
  (should (memq #'agent-ui--focus-question-h (default-value 'agent-ui-shown-functions)))
  (should-not (default-value 'agent-ui-focus-questions))
  (+test-aua
    (let* ((session (+test-aua-session "Claude Agent @ focus" "/tmp/focus/"))
           (name (agent-ui--session-name session))
           (ask (concat name " / ask"))
           (agent-ui-focus-questions t)
           (agent-ui-display-function #'agent-ui-display-canvas)
           (idle nil))
      (cl-letf (((symbol-function 'run-with-idle-timer)
                 (lambda (secs _repeat f &rest args) (push (cons secs (lambda () (apply f args))) idle))))
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer session)
          (agent-ui-show '(:id "note" :type "text" :text "Working on it") :canvas name)
          (should-not idle)
          (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?" :options ("Test" "Revert")) :canvas ask)
          (should (equal (mapcar #'car idle) (list agent-ui-focus-questions-delay)))
          ;; Not before Emacs is idle: the focus where it was.
          (should (eq (window-buffer (selected-window)) session))
          (funcall (cdar idle))
          (let ((canvas (get-buffer (agent-ui-canvas-buffer-name ask))))
            (should (eq (window-buffer (selected-window)) canvas))
            (should (equal (get-text-property (window-point) 'agent-ui-id canvas) "fix")))
          ;; Answered before the moment came: nothing.
          (select-window (get-buffer-window session))
          (agent-ui-update "fix" '(:answered "Test") :canvas ask)
          (funcall (cdar idle))
          (should (eq (window-buffer (selected-window)) session))
          ;; Coming back with its session; the option off: none.
          (let ((agent-ui--restoring t))
            (agent-ui-show '(:id "go" :type "confirm" :question "Go?") :canvas ask))
          (let ((agent-ui-focus-questions nil))
            (agent-ui-show '(:id "go2" :type "confirm" :question "Go?") :canvas ask))
          (should (= (length idle) 1)))))))

(ert-deftest agent-ui-agent/answered-the-question-goes ()
  "An answer sent: the question leaves its canvas; a canvas left empty is
closed and killed, the cursor back in the session. Beside other elements,
they stay; a plan approved goes too (doom-q49); the option off (the
library's own default), all stay."
  (should (memq #'agent-ui--close-answered-h (default-value 'agent-ui-changed-hook)))
  (should-not (default-value 'agent-ui-close-answered))
  (+test-aua
    (let* ((session (+test-aua-session "Claude Agent @ close" "/tmp/close/"))
           (name (agent-ui--session-name session))
           (ask (concat name " / ask"))
           (agent-ui-close-answered t)
           (agent-ui-display-function #'agent-ui-display-canvas)
           (sent nil)
           (agent-ui-action-function (lambda (prompt submit) (push (list prompt submit) sent))))
      (save-window-excursion
        (delete-other-windows)
        (switch-to-buffer session)
        ;; On a canvas of its own.
        (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?" :options ("Test" "Revert")) :canvas ask)
        (let ((canvas (get-buffer (agent-ui-canvas-buffer-name ask))))
          (select-window (get-buffer-window canvas))
          (+test-aua-press canvas "Test")
          (+test-aua-press canvas "⏵ Answer")
          (should (equal (caar sent) "Answer to choice fix (Which fix?): Test"))
          (+test-aua-settle)
          (should-not (buffer-live-p canvas))
          (should (equal (mapcar #'window-buffer (window-list)) (list session))))
        ;; Beside other elements: only the question goes.
        (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
        (agent-ui-show '(:id "go" :type "confirm" :question "Deploy?") :canvas name)
        (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name))))
          (+test-aua-press canvas "⏵ Proceed")
          (+test-aua-settle)
          (should (buffer-live-p canvas))
          (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas canvas)) '("build")))
          ;; A plan approved: it goes too (the agent shows its steps again,
          ;; as its checklist, if it works through them).
          (agent-ui-show '(:id "plan" :type "steps" :approve t :steps ("Reproduce" "Fix")) :canvas name)
          (+test-aua-press canvas "⏵ Approve")
          (+test-aua-settle)
          (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas canvas)) '("build")))
          ;; The option off: an answered question stays.
          (let ((agent-ui-close-answered nil))
            (agent-ui-show '(:id "go" :type "confirm" :question "Deploy?") :canvas name)
            (+test-aua-press canvas "⏵ Proceed")
            (+test-aua-settle)
            (should (member "go" (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas canvas))))))))))
