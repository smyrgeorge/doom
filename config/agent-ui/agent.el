;;; $DOOMDIR/config/agent-ui/agent.el -*- lexical-binding: t; -*-
;; Agent UI and agent-shell's sessions: each session's agent finds its own
;; canvas, which closes with it. Loaded from config/agent-ui.el, after
;; request.el. No Doom here (see docs/agent-ui.md).
;;
;; - agent-shell starts each session's agent with AGENT_UI_SESSION in its
;;   environment, the session's name (its buffer's, when it started); the
;;   agent's shell inherits it, so cmd/agent-ui says whose request it is.
;; - Without it (an agent started otherwise, a session older than this), the
;;   session working in the request's directory: the deepest one, of those
;;   the most recently used.
;; - A canvas is named after its session, its others after it ("SESSION /
;;   tests"); killing the session kills them.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defvar-local agent-ui-session nil
  "In an agent-shell buffer: its session's name for Agent UI (its canvas's).")

;; Kept if the buffer's major mode is set after its agent was started.
(put 'agent-ui-session 'permanent-local t)

(defvar-local agent-ui--session-buffer nil
  "In a canvas: its session's agent-shell buffer, if it has one.")

(defvar-local agent-ui--canvas-part nil
  "In a session's other canvas: its own name (\"tests\"); nil in the
session's canvas.")

;; ====== THE SESSION'S ENVIRONMENT ======

(defun agent-ui--session-name (buffer)
  "BUFFER's session name (`agent-ui-session'): given once, its name then."
  (with-current-buffer buffer
    (or agent-ui-session
        (setq agent-ui-session (buffer-name)))))

(defun agent-ui--client-environment-a (args)
  "`agent-shell--make-acp-client''s ARGS, AGENT_UI_SESSION added to its
environment when it has a context buffer (the session's)."
  (let ((buffer (plist-get args :context-buffer)))
    (if (buffer-live-p buffer)
        (plist-put (copy-sequence args) :environment-variables
                   (cons (concat "AGENT_UI_SESSION=" (agent-ui--session-name buffer))
                         (plist-get args :environment-variables)))
      args)))

(advice-add 'agent-shell--make-acp-client :filter-args
            (lambda (args) (agent-ui--client-environment-a args))
            '((name . agent-ui-session-environment)))

;; ====== FINDING THE SESSION ======

(defun agent-ui--sessions ()
  "agent-shell's session buffers, the most recently used first."
  (when (fboundp 'agent-shell-buffers)
    (seq-filter #'buffer-live-p (agent-shell-buffers))))

(defun agent-ui--session-cwd (buffer)
  (file-name-as-directory
   (expand-file-name (with-current-buffer buffer
                       (if (fboundp 'agent-shell-cwd) (agent-shell-cwd) default-directory)))))

(defun agent-ui--session-buffer (session cwd)
  "The session buffer named SESSION (its `agent-ui-session'); else the one
working in CWD or above it, the deepest, then the most recently used."
  (let ((sessions (agent-ui--sessions)))
    (or (and session
             (seq-find (lambda (b) (equal (buffer-local-value 'agent-ui-session b) session))
                       sessions))
        (and cwd
             (let* ((dir (file-name-as-directory (expand-file-name cwd)))
                    (matches (seq-filter (lambda (b)
                                           (string-prefix-p (agent-ui--session-cwd b) dir))
                                         sessions)))
               ;; Stable: of the deepest, the most recent first.
               (car (cl-stable-sort matches #'>
                                    :key (lambda (b) (length (agent-ui--session-cwd b))))))))))

(defun agent-ui-session-canvas (session cwd)
  "The canvas for an agent's request (`agent-ui-canvas-function'), its
name: its session's (SESSION, else the one in CWD), named after it; else
SESSION, else the default. Made when an element is first shown in it
\(`agent-ui--link-session' then ties it to its session)."
  (let ((buffer (agent-ui--session-buffer session cwd)))
    (if buffer
        (agent-ui--session-name buffer)
      (agent-ui-request-canvas session cwd))))

(setq agent-ui-canvas-function #'agent-ui-session-canvas)

(defun agent-ui--canvas-session (name)
  "The session a canvas named NAME is of: (BUFFER . PART), PART its other
canvas's name (nil for the session's canvas); nil if none."
  (let ((sessions (agent-ui--sessions)))
    (cl-flet ((named (session)
                (seq-find (lambda (b) (equal (buffer-local-value 'agent-ui-session b) session))
                          sessions)))
      (if-let* ((buffer (named name)))
          (cons buffer nil)
        ;; "SESSION / PART": the session's other canvas.
        (let ((at (string-search agent-ui-canvas-separator name)))
          (while (and at (not (named (substring name 0 at))))
            (setq at (string-search agent-ui-canvas-separator name (1+ at))))
          (when at
            (cons (named (substring name 0 at))
                  (substring name (+ at (length agent-ui-canvas-separator))))))))))

(defun agent-ui--link-session ()
  "In a new canvas: tied to the session it's named after, if there's one
\(killed with it)."
  (when-let* ((name agent-ui--canvas-name)
              (found (agent-ui--canvas-session name)))
    (setq agent-ui--session-buffer (car found)
          agent-ui--canvas-part (cdr found))
    (add-hook 'kill-buffer-hook #'agent-ui--question-closed-h nil t)
    (with-current-buffer (car found)
      (add-hook 'kill-buffer-hook #'agent-ui--kill-canvas nil t))))

(add-hook 'agent-ui-canvas-hook #'agent-ui--link-session)

(defun agent-ui-session-canvases (session)
  "SESSION's (an agent-shell buffer) canvases: its own and its others."
  (seq-filter (lambda (b) (eq (buffer-local-value 'agent-ui--session-buffer b) session))
              (agent-ui-canvases)))

(defun agent-ui--session-window (canvas)
  "A window of the selected frame showing another canvas of CANVAS's
session, its own first (`agent-ui-share-window-functions'): CANVAS goes
there, a tab beside it, not in a pane of its own (five canvases took five
panes, each a few lines high)."
  (when-let* ((session (buffer-local-value 'agent-ui--session-buffer canvas))
              ((buffer-live-p session)))
    (seq-some (lambda (other) (and (not (eq other canvas)) (get-buffer-window other)))
              (sort (agent-ui-session-canvases session)
                    (lambda (a b) (and (null (buffer-local-value 'agent-ui--canvas-part a))
                                       (buffer-local-value 'agent-ui--canvas-part b)
                                       t))))))

(add-hook 'agent-ui-share-window-functions #'agent-ui--session-window)

(defun agent-ui--kill-canvas ()
  "The session's buffer is killed: its canvases too."
  (mapc #'kill-buffer (agent-ui-session-canvases (current-buffer))))

;; ====== WHAT THE AGENT IS TOLD ======

(defvar agent-ui-agent-mcp nil
  "Non-nil when agents get Agent UI as MCP tools too (cmd/agent-ui-mcp.el):
their system prompt says so.")

(defcustom agent-ui-skill
  (expand-file-name "../../skills/agent-ui/SKILL.md"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The agent-ui skill: the guide the agent reads before using the canvas."
  :type 'file :group 'agent-ui)

(defun agent-ui--home-relative (file)
  "FILE as ~/..., if it's in the home folder."
  (abbreviate-file-name (expand-file-name file)))

(defun agent-ui-agent-context ()
  "What an agent starting in agent-shell is told of its canvas (for its system
prompt); nil while Emacs runs no server (the command couldn't reach it)."
  (when (and (fboundp 'server-running-p) (server-running-p))
    (let ((command (agent-ui--home-relative agent-ui-command))
          (skill (agent-ui--home-relative agent-ui-skill)))
      (format "Agent UI: beside this session, Emacs has a canvas (a pane of its \
own, opened without taking the user's focus when you first show something) \
where you show the user things as elements, each updated in place. It is where \
information goes: whatever you have to tell that has a shape (figures, records, \
a comparison, a trend, a structure, steps, changes, output), show it there as \
the element that fits it, and keep your reply to the words: what you found, \
what it means, what's next, and a line saying what's on the canvas, not the \
same again. What a sentence or two holds stays in the reply alone. The element \
by the information: figures, stats (one against a target or limits, gauge); \
records, results, a search's matches, table; a trend, a series or a \
distribution, chart; values across two dimensions, heatmap; a structure, \
dependencies or a flow, graph or mermaid; durations over time, timeline; code, \
code; changes, diff; files and their state, files; output, log; categories \
with counts, tags; formulas, math; a write-up, markdown; a picture, image; a \
web page, html; several of these together, a panel. Issues and plans go there \
too, always, without being asked: a project's or an epic's issues (bd ready, an \
epic's children) as the issues board, which follows your bd commands; a plan, \
or the ticket you're working on, as steps (its acceptance criteria), ticked as \
you go; a long build or test run as progress, steps, a table filling in. This \
comes before what's said above of tables, images and diagrams in your replies: \
they're for when the canvas can't be used (the command exits with 3).

Asking: to ask the user something, show it on a canvas of its own (--canvas \
ask: it takes the user's focus and closes once answered) as the interactive \
element that fits the question, say so in a line and end your turn: the answer \
comes as your next prompt. To pick from a list (which to fix, which files, \
which approach), a choice (multiple: several), or select on a table, files or \
issues you show; alternatives the user has to see, side by side, compare; \
before something risky (a force-push, a deploy, deleting data), a confirm, with \
what will happen; a plan to agree on before you start, steps with approve; \
changes you propose, diff with accept; several values at once, form; an order, \
rank; a number in a range, slider.%s

From your shell: %s show \
'{\"id\":\"build\",\"type\":\"progress\",\"title\":\"Build\",\"max\":12}', then \
%s update build '{\"value\":5}'; append adds a table's rows or a \
checklist's steps; remove ID; clear; --canvas NAME on any of them uses \
another canvas of this session, a tab beside its first. It replies with JSON. Before using it \
the first time, read %s: the core (when to use it, which element for what, the \
command, the everyday types), and which of its references to read only when \
needed (asking the user, charts, layouts, following a command, a type of \
your own). Remove what stops helping, and never leave something \
shown running once it stopped. When Agent UI itself misbehaves (a wrong drawing, \
an error, a property it lacks), ask the user, then file it: %s bug \
'{\"title\":...,\"description\":...,\"element\":\"ID\",\"repro\":{an element \
showing it}}' goes into Agent UI's own issues, never this project's (not filed: \
its reply's report, to show the user); then carry on with a workaround.%s"
              ;; Quick questions in the conversation, while agent-shell shows
              ;; them (its form); else the agent hasn't the tool.
              (if (bound-and-true-p agent-shell-elicitation--experimental-feature-enabled)
                  " Only a quick question (2 to 4 short options, nothing to \
show or compare) goes in the conversation instead, with AskUserQuestion \
(agent-shell shows it as a form): wait for its answer."
                "")
              command command skill command
              (if agent-ui-agent-mcp
                  " The same operations are MCP tools too (the agent-ui server: show, \
update, append, remove, list, types, render, snapshot, batch, define, bug), with \
their schemas: use whichever you like."
                "")))))

;; ====== ACTIONS ======

;; While the agent works, its prompt may take no text (agent-shell said "Busy,
;; try later"): a button sending its prompt queues it, sent when the agent's
;; done (agent-shell's queue); one putting it into the prompt offers it to
;; queue, to read and change first, as agent-shell's own commands do then.
(defun agent-ui--session-busy-p (session)
  "Whether SESSION's prompt takes no text now (its agent working, no prompt
kept live meanwhile). Not known (not a shell yet): not busy, agent-shell
then has its say."
  (ignore-errors
    (with-current-buffer session
      (if (fboundp 'agent-shell--can-insert-into-prompt-p)
          (not (agent-shell--can-insert-into-prompt-p :shell-buffer session))
        (and (fboundp 'shell-maker-busy) (shell-maker-busy))))))

(defun agent-ui--act (prompt submit)
  "An element's action pressed, in its canvas: PROMPT into the prompt of the
canvas's session (sent if SUBMIT); while its agent works, queued (see above).
The canvas still current after it: agent-shell selects the session's window
\(its buffer current then), and what the press does next (a question
answered) is the canvas's. A project's panel (config/agent-ui/panels.el),
of no session: the session working in its project, the latest."
  (let ((session (and (derived-mode-p 'agent-ui-canvas-mode)
                      (or agent-ui--session-buffer
                          (and (bound-and-true-p agent-ui-panels--state)
                               (agent-ui--session-buffer nil default-directory))))))
    (unless (buffer-live-p session)
      (user-error "%s" (if (bound-and-true-p agent-ui-panels--state)
                      "No agent-shell session in this panel's project"
                    "This canvas has no agent-shell session")))
    (unless (fboundp 'agent-shell-insert)
      (user-error "agent-shell isn't loaded"))
    (cond
     ((not (and (fboundp 'agent-shell-prompt-queue) (agent-ui--session-busy-p session)))
      (save-current-buffer
        (agent-shell-insert :text prompt :submit submit :shell-buffer session)))
     (submit
      (with-current-buffer session
        (agent-shell-prompt-queue prompt))
      (message "Queued: sent once the agent's done"))
     (t
      (let ((prompt (with-current-buffer session
                      (if (fboundp 'agent-shell--prompt-queue-read)
                          (agent-shell--prompt-queue-read :initial prompt)
                        (read-string "The agent's working; queue: " prompt)))))
        (with-current-buffer session
          (agent-shell-prompt-queue prompt)))))))

(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell-prompt-queue "agent-shell-prompt-queue")
(declare-function agent-shell--prompt-queue-read "agent-shell-prompt-queue")
(declare-function agent-shell--can-insert-into-prompt-p "agent-shell-prompt")
(declare-function shell-maker-busy "shell-maker")
(setq agent-ui-action-function #'agent-ui--act)

;; ====== A QUESTION WAITING ======
;; A session's turn ended with a question on its canvases not answered (a
;; choice, an element with select: `agent-ui-ask-waiting-p'), new since its
;; last turn's end: the user sees it, the canvas's pane shown, the cursor on
;; it, said by
;; `agent-ui-question-waiting-functions' (config/notify/agent-ui.el: a
;; notification while Emacs is away); the session's mode line says so until
;; it's answered; `agent-ui-goto-question' (C-c C-q in a session) goes there.

(defvar agent-ui-question-waiting-functions nil
  "Called when a session's turn ended with a question waiting on its canvas:
with the session's buffer, the canvas and the question's id.")

(defvar-local agent-ui--question-waiting nil
  "In a session: non-nil while a question waits on its canvases.")

(defvar-local agent-ui--question-said nil
  "In a session: its questions waiting at its last turn's end, ((CANVAS .
ID)...): said then, not again.")

(defvar-local agent-ui--question-turn nil
  "In a session: its last turn's end, (EVENT . QUESTIONS-SAID).")

(defun agent-ui--waiting (session &optional except)
  "SESSION's questions waiting on its canvases (a panel's children too), but
EXCEPT's (a canvas being killed): ((CANVAS . ID)...), in their order."
  (cl-loop for canvas in (agent-ui-canvases)
           when (and (not (eq canvas except))
                     (eq (buffer-local-value 'agent-ui--session-buffer canvas) session))
           append (with-current-buffer canvas
                    (cl-loop for id in agent-ui--order
                             for element = (agent-ui--entry-element (gethash id agent-ui--entries))
                             append (cl-loop for e in (cons (plist-put (copy-sequence element) :id id)
                                                            (agent-ui--descendants element))
                                             when (agent-ui-ask-waiting-p e)
                                             collect (cons canvas (plist-get e :id)))))))

(defun agent-ui--show-question (canvas id &optional select)
  "CANVAS's pane shown (SELECT: selected), the cursor on question ID, its
line in view."
  (unless (get-buffer-window canvas t)
    (agent-ui--display canvas))
  (let ((window (get-buffer-window canvas t))
        (pos (with-current-buffer canvas
               (agent-ui--flush)
               (agent-ui--element-start canvas id))))
    (when pos
      (with-current-buffer canvas (goto-char pos))
      (when window
        (set-window-point window pos)
        (agent-ui--question-in-view canvas id pos window)))
    (when (and select window)
      (select-window window))))

(defun agent-ui--element-end (id start)
  "Where element ID, from START in the current canvas, ends: after its last
character (a panel's child: its last line's, its panel's lines its too)."
  (let* ((top (get-text-property start 'agent-ui-id))
         (prop (if (equal top id) 'agent-ui-id 'agent-ui-child))
         (pos start)
         (end start))
    (while (and (< pos (point-max)) (equal (get-text-property pos 'agent-ui-id) top))
      (let ((next (or (next-single-property-change pos prop nil (point-max)) (point-max))))
        (when (equal (get-text-property pos prop) id)
          (setq end next))
        (setq pos next)))
    end))

(defun agent-ui--question-in-view (canvas id start window)
  "Question ID of CANVAS, from START, all in WINDOW's view, its Answer too:
WINDOW scrolled to its first line if that's needed, made taller if it must
and can (a short pane showed its first lines, the Answer below them)."
  (with-current-buffer canvas
    (let* ((first (save-excursion (goto-char start) (line-beginning-position)))
           (end (agent-ui--element-end id start))
           (lines (count-lines first end))
           (shown (window-body-height window)))
      (unless (and (pos-visible-in-window-p first window) (pos-visible-in-window-p (max first (1- end)) window))
        (set-window-start window first))
      (when (> lines shown)
        (let ((delta (min (- lines shown) (window-max-delta window))))
          (when (> delta 0)
            (ignore-errors (window-resize window delta))))))))

(defun agent-ui-questions-new (session event)
  "SESSION's questions waiting at its turn's end, EVENT (agent-shell's
turn-complete), that weren't at its last one: those said, once. The same
for everyone looking at EVENT (its notification too)."
  (with-current-buffer session
    (if (and agent-ui--question-turn (eq (car agent-ui--question-turn) event))
        (cdr agent-ui--question-turn)
      (let* ((waiting (agent-ui--waiting session))
             (new (cl-remove-if (lambda (q) (member q agent-ui--question-said)) waiting)))
        (setq agent-ui--question-said waiting
              agent-ui--question-turn (cons event new))
        new))))

(defun agent-ui--question-check (session &optional event except)
  "SESSION's questions waiting looked at again (but EXCEPT's, a canvas being
killed): its mode line's mark set or cleared; at its turn's end (EVENT), the
first new one shown and said."
  (when (buffer-live-p session)
    (let ((waiting (agent-ui--waiting session except)))
      (with-current-buffer session
        (setq agent-ui--question-waiting (and waiting t))
        (force-mode-line-update))
      (when-let* ((new (and event (car (agent-ui-questions-new session event)))))
        (agent-ui--show-question (car new) (cdr new))
        (run-hook-with-args 'agent-ui-question-waiting-functions session (car new) (cdr new))))))

(defun agent-ui--watch-questions-h ()
  "A new session: its questions waiting looked at when its turn ends."
  (let ((session (current-buffer)))
    (when (fboundp 'agent-shell-subscribe-to)
      (agent-shell-subscribe-to :shell-buffer session :event 'turn-complete
                                :on-event (lambda (event) (agent-ui--question-check session event))))))

(add-hook 'agent-shell-mode-hook #'agent-ui--watch-questions-h)

(defun agent-ui--question-changed-h ()
  "A canvas changed (an answer given): its session's mark looked at again,
if it had one."
  (when (and (buffer-live-p agent-ui--session-buffer)
             (buffer-local-value 'agent-ui--question-waiting agent-ui--session-buffer))
    (agent-ui--question-check agent-ui--session-buffer)))

(add-hook 'agent-ui-changed-hook #'agent-ui--question-changed-h)

(defun agent-ui--question-closed-h ()
  "A canvas killed (q closes it): its session's mark looked at again,
without it, if it had one (it stayed until the next turn's end)."
  (when (and (buffer-live-p agent-ui--session-buffer)
             (buffer-local-value 'agent-ui--question-waiting agent-ui--session-buffer))
    (agent-ui--question-check agent-ui--session-buffer nil (current-buffer))))

(defun agent-ui--question-mode-line ()
  "The mode line's mark, in a session with a question waiting."
  (if agent-ui--question-waiting
      (propertize " ❓ question waiting " 'face 'agent-ui-warning
                  'help-echo "A question waits on the canvas: agent-ui-goto-question (C-c C-q) goes there")
    ""))

(add-to-list 'mode-line-misc-info '(:eval (agent-ui--question-mode-line)) t)

;; ====== A QUESTION TAKES THE FOCUS; ANSWERED, IT GOES ======
;; Options, both on (nil in config.el turns one off): a question shown (an
;; element that asks, `agent-ui-ask-waiting-p') takes the focus: its pane
;; selected, the cursor on it, once Emacs is idle a moment (typing in the
;; session isn't taken over: the canvas's keys act), the minibuffer closed;
;; not a resumed session's coming back. Its answer sent (`agent-ui-ask-done-p'), it leaves its canvas;
;; a canvas left without elements is closed: its panes, its buffer killed, the
;; cursor back in the session.

(defvar agent-ui-focus-questions t
  "Non-nil: a question shown on a canvas takes the focus (see above).")

(defvar agent-ui-focus-questions-delay 1.0
  "Seconds Emacs is idle before a question shown takes the focus.")

(defvar agent-ui-close-answered t
  "Non-nil: a question answered leaves its canvas, a canvas left empty is
killed (see above).")

(defvar agent-ui--restoring)            ; persist.el's: canvases coming back

(defun agent-ui--focus-question (canvas id)
  "CANVAS's question ID, if it still waits: its pane selected, the cursor on
it. While the minibuffer is open, once it's closed and Emacs is idle a
moment again (the keys typed there aren't the canvas's)."
  (when (and (buffer-live-p canvas)
             (ignore-errors (agent-ui-ask-waiting-p (agent-ui-get id :canvas canvas))))
    (if (active-minibuffer-window)
        (agent-ui-after-minibuffer
         (lambda ()
           (run-with-idle-timer agent-ui-focus-questions-delay nil #'agent-ui--focus-question canvas id)))
      ;; As C-c C-q would: a command going there (a pane shown with none
      ;; running stays behind the one on the screen, tiling's fullscreen).
      (let ((this-command 'agent-ui-goto-question))
        (agent-ui--show-question canvas id t)))))

(defun agent-ui--focus-question-h (id element)
  "A question shown (`agent-ui-shown-functions'): it takes the focus, once
Emacs is idle a moment."
  (when (and agent-ui-focus-questions
             (not (bound-and-true-p agent-ui--restoring))
             (agent-ui-ask-waiting-p element))
    (run-with-idle-timer agent-ui-focus-questions-delay nil
                         #'agent-ui--focus-question (current-buffer) id)))

(add-hook 'agent-ui-shown-functions #'agent-ui--focus-question-h)

(defun agent-ui--close-answered (canvas)
  "CANVAS's questions answered gone; it left without elements: its panes
closed, its buffer killed, the cursor back in its session (if it was in
CANVAS's pane)."
  (when (buffer-live-p canvas)
    (with-current-buffer canvas
      (let ((session agent-ui--session-buffer)
            (focused (eq (window-buffer (selected-window)) canvas)))
        (dolist (id (seq-filter (lambda (id)
                                  (agent-ui-ask-done-p (agent-ui--entry-element (gethash id agent-ui--entries))))
                                agent-ui--order))
          (agent-ui-remove id :canvas canvas))
        (unless agent-ui--order
          ;; Its panes closed already (emptied: `agent-ui--close-if-empty').
          (kill-buffer canvas)
          (when-let* ((window (and focused (buffer-live-p session) (get-buffer-window session))))
            (select-window window)))))))

(defun agent-ui--close-answered-h ()
  "A canvas changed (`agent-ui-changed-hook'): an answer sent, the question
goes (after the command that sent it)."
  (when (and agent-ui-close-answered
             (seq-some (lambda (id) (agent-ui-ask-done-p (agent-ui--entry-element (gethash id agent-ui--entries))))
                       agent-ui--order))
    (run-with-timer 0 nil #'agent-ui--close-answered (current-buffer))))

(add-hook 'agent-ui-changed-hook #'agent-ui--close-answered-h)

(defun agent-ui-goto-question ()
  "Go to the question waiting on this session's canvases (in a canvas: its
session's; else any session's): its pane selected, the cursor on it."
  (interactive)
  (let ((found (cl-loop for session in (cond ((derived-mode-p 'agent-shell-mode) (list (current-buffer)))
                                             (agent-ui--session-buffer (list agent-ui--session-buffer))
                                             (t (agent-ui--sessions)))
                        thereis (car (agent-ui--waiting session)))))
    (unless found
      (user-error "No question waits"))
    (agent-ui--show-question (car found) (cdr found) t)))
