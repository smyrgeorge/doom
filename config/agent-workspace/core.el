;;; $DOOMDIR/config/agent-workspace/core.el -*- lexical-binding: t; -*-
;; The agent workspace's model: a project's crew of agents, each with a name, a
;; role, a colour and a state, and what you do to one. Loaded from
;; config/agent-workspace.el. No Doom here (see docs/agent-workspace.md).
;;
;; An agent is a record (`agent-workspace-agent'), kept in its project's crew
;; while Emacs runs. Its session is agent-shell's (session.el), in its own
;; worktree (worktree.el); its state follows the session's events, never
;; polled. The other parts (the app, the room) read the records and listen to
;; `agent-workspace-change-functions'.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ansi-color)               ; its faces: the agents' colours

;; worktree.el and session.el, loaded after.
(declare-function agent-workspace-worktree-ensure "agent-workspace/worktree")
(declare-function agent-workspace-worktree-rename "agent-workspace/worktree")
(declare-function agent-workspace-worktree-fate "agent-workspace/worktree")
(declare-function agent-workspace-worktree-remove "agent-workspace/worktree")
(declare-function agent-workspace--start "agent-workspace/session")
(declare-function agent-workspace--stop "agent-workspace/session")
(declare-function agent-workspace--process-table "agent-workspace/session")
(declare-function agent-workspace-send "agent-workspace/session")
(declare-function agent-workspace--check-role "agent-workspace/roles")
(declare-function agent-workspace--check-room "agent-workspace/roles")
(declare-function agent-shell-interrupt "agent-shell")

;; ====== VARIABLES ======

(defgroup agent-workspace nil
  "A crew of coding agents on one project, run from one app."
  :group 'tools
  :prefix "agent-workspace-")

(defcustom agent-workspace-colours
  '("blue" "magenta" "green" "yellow" "cyan" "red" "white" "black")
  "The colours agents get, in the order a free one is taken: the theme's
ANSI faces (`ansi-color-blue'...), their foreground. Red last: on a bar it
reads as an error."
  :type '(repeat string))

(defvar agent-workspace-change-functions nil
  "Called with an agent and what changed, a symbol: `created', `state',
`renamed', `colour', `role', `settings' (its model or mode), `issue',
`panels' (one opened or closed),
`session' (a new one started), `forgotten', `closed' (its crew closed).")

(defvar agent-workspace-closing-functions nil
  "Called with a project as its crew closes, before any agent stops.")

(defvar agent-workspace-moving-functions nil
  "Called with an agent whose worktree is about to move (it's renamed),
its session stopped: what's open there closed, to open again in the new one
once it's `renamed'.")

(defvar agent-workspace-state-change-functions nil
  "Called with an agent, its old state and its new one, when its state
changes (before `agent-workspace-change-functions').")

(defvar agent-workspace-role-function #'agent-workspace--bare-role
  "Called with a project and a role's name: the role, a plist. Its keys:
:name, :description, :verb (\"building\"), :instructions (added to the
agent's system prompt), :model, :mode (Claude Code's permission mode),
:tools (allowed), :deny (disallowed), :mcp-servers. Roles (doom-51z.3) set it.")

(defvar agent-workspace--crews (make-hash-table :test #'equal)
  "The crews: a project's root (the main checkout's) to its agents, in the
order they were made.")

;; ====== AN AGENT ======

(cl-defstruct (agent-workspace-agent
               (:constructor agent-workspace--make-agent)
               (:copier nil))
  "An agent of a crew."
  name                       ; "ada": short, typed after # in the room
  role                       ; its role's name: "builder"
  colour                     ; one of `agent-workspace-colours': "blue"
  (kind 'claude-code)        ; which agent: a key of `agent-workspace-kinds'
  model                      ; its model, when not its role's
  mode                       ; its permission mode, when not its role's
  project                    ; its crew's project: the main checkout's root
  worktree                   ; its worktree's folder (worktree.el)
  branch                     ; its worktree's branch: "agent/ada"
  buffer                     ; its agent-shell session's buffer, while it runs
  (state 'asleep)            ; see THE STATES below
  since                      ; when its turn started (`float-time'), working
  ask                        ; its raised hand: (:kind permission :title ...)
  error                      ; why it's stuck: the error's message
  issue                      ; the issue you gave it: "doom-a1b"
  issue-title                ; that issue's title
  stopping)                  ; non-nil while its session is stopped on purpose

(defun agent-workspace-agent-face (agent)
  "AGENT's colour as a face: the theme's ANSI face (use its foreground)."
  (intern (concat "ansi-color-" (or (agent-workspace-agent-colour agent) "blue"))))

(defun agent-workspace-buffer-name (agent)
  "The name of AGENT's session buffer: \"ada · builder\"."
  (format "%s · %s" (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)))

(defun agent-workspace-role (agent)
  "AGENT's role, a plist (see `agent-workspace-role-function')."
  (funcall agent-workspace-role-function
           (agent-workspace-agent-project agent)
           (agent-workspace-agent-role agent)))

(defun agent-workspace--bare-role (_project name)
  "A role named NAME, with nothing of its own (before roles are defined)."
  (list :name name))

;; ====== THE CREWS ======

(defun agent-workspace-project (&optional directory)
  "The project of DIRECTORY (default: `default-directory'): its git
repository's main checkout (from one of its worktrees too), or nil. In an
agent's buffer, its crew's project."
  (if-let* ((agent (and (not directory) (agent-workspace-buffer-agent))))
      (agent-workspace-agent-project agent)
    (let ((default-directory (file-name-as-directory
                              (expand-file-name (or directory default-directory)))))
      (when-let* ((common (and (file-directory-p default-directory)
                               (agent-workspace--git-line "rev-parse" "--path-format=absolute"
                                                          "--git-common-dir"))))
        ;; The common folder is the main checkout's .git (a bare repository
        ;; has none: no crew).
        (when (equal (file-name-nondirectory (directory-file-name common)) ".git")
          (file-name-as-directory (file-truename (file-name-directory (directory-file-name common)))))))))

(defun agent-workspace--git-line (&rest args)
  "The first line git prints for ARGS in `default-directory', or nil if it
fails."
  (with-temp-buffer
    (when (eql 0 (apply #'process-file "git" nil '(t nil) nil args))
      (goto-char (point-min))
      (let ((line (buffer-substring-no-properties (point) (line-end-position))))
        (unless (string-empty-p line) line)))))

(defun agent-workspace--root (project)
  "PROJECT as the crews' key: its folder's true name, with a slash."
  (file-name-as-directory (file-truename (expand-file-name project))))

(defun agent-workspace-agents (&optional project)
  "PROJECT's crew (default: the current project's): its agents, in the order
they were made."
  (when-let* ((project (or project (agent-workspace-project))))
    (gethash (agent-workspace--root project) agent-workspace--crews)))

(defun agent-workspace-agent (name &optional project)
  "The agent named NAME in PROJECT's crew (default: the current project's)."
  (seq-find (lambda (agent) (equal (agent-workspace-agent-name agent) name))
            (agent-workspace-agents project)))

(defun agent-workspace-read-agent (prompt &optional project)
  "An agent of PROJECT's crew (default: the current project's), read in the
minibuffer with PROMPT; the buffer's own agent (its session's, its
worktree's) offered first."
  (let* ((agents (or (agent-workspace-agents project) (user-error "No crew here")))
         (own (or (agent-workspace-buffer-agent)
                  (and (fboundp 'agent-workspace-file-agent) (agent-workspace-file-agent))))
         (name (completing-read prompt (mapcar #'agent-workspace-agent-name agents) nil t nil nil
                                (and (memq own agents) (agent-workspace-agent-name own)))))
    (seq-find (lambda (agent) (equal (agent-workspace-agent-name agent) name)) agents)))

(defun agent-workspace-crews ()
  "The projects with a crew."
  (hash-table-keys agent-workspace--crews))

(defvar-local agent-workspace--agent nil
  "In an agent's session (and the app's buffers drawing it): the agent.")
;; A major mode run again in the buffer keeps it (its header line is drawn
;; from it).
(put 'agent-workspace--agent 'permanent-local t)

(defun agent-workspace-buffer-agent (&optional buffer)
  "The agent of BUFFER (default: the current one), or nil."
  (buffer-local-value 'agent-workspace--agent (or buffer (current-buffer))))

;; ====== THE STATES ======
;; waking (its session starting), desk (at the desk: waiting for you), working,
;; hand (its hand raised: a permission, a question), done (its turn over,
;; until you look: its pane shown), stuck (an error), asleep (its session
;; stopped by you: s wakes it), home (gone home: killed, or its process ended).

(defconst agent-workspace-states '(waking desk working hand done stuck asleep home)
  "An agent's states (see above).")

(defun agent-workspace-live-p (agent)
  "Non-nil if AGENT's session runs (gone home, its buffer may stay: what it
said before its process ended)."
  (and (buffer-live-p (agent-workspace-agent-buffer agent))
       (not (memq (agent-workspace-agent-state agent) '(home asleep)))))

(defun agent-workspace--set-state (agent state)
  "AGENT now in STATE, said to the hooks if it changed."
  (let ((old (agent-workspace-agent-state agent)))
    (unless (memq state '(hand)) (setf (agent-workspace-agent-ask agent) nil))
    (unless (eq state 'stuck) (setf (agent-workspace-agent-error agent) nil))
    (unless (memq state '(working hand)) (setf (agent-workspace-agent-since agent) nil))
    (unless (eq old state)
      (setf (agent-workspace-agent-state agent) state)
      (run-hook-with-args 'agent-workspace-state-change-functions agent old state)
      (agent-workspace--changed agent 'state))))

(defun agent-workspace--changed (agent what)
  "Say to `agent-workspace-change-functions' that WHAT changed in AGENT."
  (run-hook-with-args 'agent-workspace-change-functions agent what))

(defun agent-workspace-state-text (agent)
  "What AGENT's state says, in words: \"building doom-a1b\", \"wants to run
npm install\", \"at the desk\"..."
  (pcase (agent-workspace-agent-state agent)
    ('waking "waking up")
    ('desk "at the desk")
    ('working (let ((verb (or (plist-get (agent-workspace-role agent) :verb) "working")))
                (if-let* ((issue (agent-workspace-agent-issue agent)))
                    (format "%s %s" verb issue)
                  verb)))
    ('hand (agent-workspace--ask-text (agent-workspace-agent-ask agent)))
    ('done "done, have a look")
    ('stuck (if-let* ((issue (agent-workspace-agent-issue agent)))
                (format "stuck on %s" issue)
              "stuck"))
    ('asleep "asleep")
    ('home "gone home")))

(defun agent-workspace--ask-text (ask)
  "What a raised hand, ASK, wants, in words."
  (let ((title (plist-get ask :title)))
    (pcase (plist-get ask :kind)
      ('permission
       (if title
           (format "wants to %s %s"
                   (pcase (plist-get ask :tool-kind)
                     ("execute" "run") ("edit" "edit") ("delete" "delete") ("move" "move")
                     ("fetch" "fetch") ("read" "read") (_ "use"))
                   title)
         "wants your permission"))
      (_ (if title (format "asks: %s" title) "asks you something")))))

;; ====== EVENTS ======
;; agent-shell's events (session.el subscribes to them all) move an agent
;; from state to state.

(defun agent-workspace--event (agent event)
  "AGENT's session emitted EVENT (agent-shell's: an alist with :event and
:data): its state follows."
  (let ((state (agent-workspace-agent-state agent))
        (data (alist-get :data event)))
    (pcase (alist-get :event event)
      ((or 'init-started 'init-client 'init-subscriptions 'init-handshake 'init-authenticate
           'init-session 'init-model 'init-session-mode 'init-config-options)
       (unless (memq state '(working hand))
         (agent-workspace--set-state agent 'waking)))
      ;; Not prompt-ready: its prompt shows before its model and mode are set.
      ('init-finished
       (when (eq state 'waking)
         (agent-workspace--set-state agent 'desk)))
      ('input-submitted
       ;; A turn starts: its time counts from here, a raised hand and its
       ;; answer don't reset it.
       (unless (memq state '(working hand))
         (setf (agent-workspace-agent-since agent) (float-time)))
       (agent-workspace--set-state agent 'working))
      ((or 'tool-call-update 'agent-message-chunk 'permission-response)
       ;; A hand answered: back to work. (Updates also come after a turn's
       ;; end: those leave it as it is.)
       (when (eq state 'hand)
         (let ((since (agent-workspace-agent-since agent)))
           (agent-workspace--set-state agent 'working)
           (setf (agent-workspace-agent-since agent) since))))
      ('permission-request
       (let ((tool-call (alist-get :tool-call data)))
         (agent-workspace--raise-hand
          agent (list :kind 'permission
                      :title (alist-get :title tool-call)
                      :tool-kind (alist-get :kind tool-call)
                      :request-id (alist-get :request-id data)))))
      ('elicitation-request
       (agent-workspace--raise-hand
        agent (list :kind 'question :title (alist-get :message data))))
      ('turn-complete
       (agent-workspace--set-state
        agent (if (or (equal (alist-get :stop-reason data) "cancelled")
                      (agent-workspace--looked-at-p agent))
                  'desk
                'done)))
      ('error
       (agent-workspace--set-state agent 'stuck)
       (setf (agent-workspace-agent-error agent) (alist-get :message data))
       (agent-workspace--changed agent 'state))
      ('clean-up
       (unless (agent-workspace-agent-stopping agent)
         (agent-workspace--set-state agent 'home))))))

(defun agent-workspace--raise-hand (agent ask)
  "AGENT raises its hand: ASK says what for."
  (let ((since (agent-workspace-agent-since agent)))
    (setf (agent-workspace-agent-ask agent) ask)
    (if (eq (agent-workspace-agent-state agent) 'hand)
        (agent-workspace--changed agent 'state)
      (agent-workspace--set-state agent 'hand))
    (setf (agent-workspace-agent-since agent) (or since (float-time)))))

(defun agent-workspace--looked-at-p (agent)
  "Non-nil if AGENT's session is shown, in a window of a visible frame."
  (when-let* ((buffer (agent-workspace-agent-buffer agent)))
    (and (buffer-live-p buffer)
         (seq-some (lambda (window) (frame-visible-p (window-frame window)))
                   (get-buffer-window-list buffer nil t)))))

(defun agent-workspace-seen (agent)
  "You looked at AGENT (its pane shown): done becomes at the desk."
  (when (eq (agent-workspace-agent-state agent) 'done)
    (agent-workspace--set-state agent 'desk)))

;; ====== MAKING ONE ======

(defun agent-workspace-name-valid-p (name)
  "Non-nil if NAME can be an agent's: typed after # in the room, it's a
lowercase letter, then lowercase letters, digits or -, at most 20 (it names
its branch and folder too)."
  (and (stringp name)
       (let ((case-fold-search nil))
         (string-match-p "\\`[a-z][a-z0-9-]\\{0,19\\}\\'" name))))

(defun agent-workspace--check-name (name project &optional except)
  "Signal a user error if NAME can't be an agent's in PROJECT's crew (but
EXCEPT's, an agent being renamed)."
  (unless (agent-workspace-name-valid-p name)
    (user-error "Not a name for an agent: %S (a lowercase letter, then lowercase letters, digits or -)" name))
  (when-let* ((other (seq-find (lambda (agent) (string-equal-ignore-case
                                                (agent-workspace-agent-name agent) name))
                               (agent-workspace-agents project))))
    (unless (eq other except)
      (user-error "There's an agent named %s already" (agent-workspace-agent-name other)))))

(defun agent-workspace-free-colour (&optional project prefer)
  "A colour no agent of PROJECT's crew has: PREFER (its role's) if it's
free, else the first of `agent-workspace-colours'; all in use, the one
fewest have."
  (let ((used (mapcar #'agent-workspace-agent-colour (agent-workspace-agents project))))
    (or (and prefer (not (member prefer used)) prefer)
        (seq-find (lambda (colour) (not (member colour used))) agent-workspace-colours)
        (car (seq-sort-by (lambda (colour) (seq-count (lambda (c) (equal c colour)) used))
                          #'< agent-workspace-colours)))))

(cl-defun agent-workspace-create (&key role name colour model mode prompt issue issue-title
                                       project (kind 'claude-code))
  "Make an agent in PROJECT's crew (default: the current project's) and start
it: ROLE (its name, required), NAME (required), COLOUR (default: its role's
while free, else a free one), MODEL and MODE (default: its role's), KIND (an
agent of `agent-workspace-kinds'). It gets its own worktree, always, and its
session starts there. PROMPT, if given, is its first message, sent once it's
ready; ISSUE (an id, and ISSUE-TITLE), the issue it's for: its first
message unless PROMPT, \"Work on ID: TITLE\". Return the agent.

A step failing says which: its worktree not made, nothing is; its session
not started, it's stuck saying why, in the crew."
  (let ((project (or project (agent-workspace-project)
                     (user-error "Not in a git repository: a crew needs one"))))
    (unless (and (stringp role) (not (string-empty-p role)))
      (user-error "An agent needs a role"))
    (agent-workspace--check-role project role)
    (agent-workspace--check-name name project)
    (when (and colour (not (member colour agent-workspace-colours)))
      (user-error "Not a colour for an agent: %s (one of %s)"
                  colour (string-join agent-workspace-colours ", ")))
    (let ((agent (agent-workspace--make-agent
                  :name name :role role :kind kind :state 'waking
                  :colour (or colour (agent-workspace-free-colour
                                      project (plist-get (funcall agent-workspace-role-function project role)
                                                         :colour)))
                  :model model :mode mode
                  :project (agent-workspace--root project))))
      (condition-case err
          (agent-workspace-worktree-ensure agent)
        (error (user-error "%s's worktree: %s" name (error-message-string err))))
      (let ((key (agent-workspace--root project)))
        (puthash key (append (gethash key agent-workspace--crews) (list agent))
                 agent-workspace--crews))
      (when issue
        (agent-workspace-give agent issue issue-title))
      (agent-workspace--changed agent 'created)
      (when (and (agent-workspace--start agent)
                 (or prompt issue))
        (agent-workspace-send agent (or prompt (agent-workspace-issue-prompt issue issue-title))
                              :submit t))
      agent)))

(defun agent-workspace-issue-prompt (issue &optional title)
  "Your message giving an agent ISSUE (with its TITLE)."
  (if title (format "Work on %s: %s" issue title) (format "Work on %s" issue)))

;; ====== WHAT YOU DO TO ONE ======

(defun agent-workspace--live-or-error (agent)
  "AGENT's session buffer, or a user error saying it doesn't run."
  (or (and (agent-workspace-live-p agent) (agent-workspace-agent-buffer agent))
      (user-error "%s is %s" (agent-workspace-agent-name agent) (agent-workspace-state-text agent))))

(defun agent-workspace-interrupt (agent)
  "Interrupt AGENT's turn (its raised hands refused)."
  (with-current-buffer (agent-workspace--live-or-error agent)
    (agent-shell-interrupt t)))

(defun agent-workspace-kill (agent)
  "End AGENT's session: it's gone home, its worktree kept. The issue you gave
it, if still in progress and assigned to it, goes back: open, unassigned."
  (agent-workspace--stop agent 'home)
  (agent-workspace--give-back agent))

(defun agent-workspace-restart (agent)
  "Start AGENT again, with a fresh session."
  (agent-workspace--start agent))

(defun agent-workspace-sleep (agent)
  "Put AGENT to sleep: its session stopped, it stays in the crew."
  (agent-workspace--stop agent 'asleep))

(defun agent-workspace-wake (agent)
  "Wake AGENT (asleep or gone home): a fresh session."
  (when (agent-workspace-live-p agent)
    (user-error "%s is awake" (agent-workspace-agent-name agent)))
  (agent-workspace--check-room (agent-workspace-agent-project agent) (agent-workspace-agent-role agent))
  (agent-workspace--start agent))

(defun agent-workspace-forget (agent &optional worktree)
  "Take AGENT out of its crew, its session stopped first. Its worktree and
branch: WORKTREE (`keep' or `remove'), or if nil, removed when they hold
nothing the main checkout hasn't, else you're shown what they hold and
asked: no work is lost without asking."
  (let ((how (agent-workspace-worktree-fate agent worktree)))
    (agent-workspace--stop agent 'home)
    (let ((key (agent-workspace-agent-project agent)))
      (puthash key (remq agent (gethash key agent-workspace--crews)) agent-workspace--crews)
      (unless (gethash key agent-workspace--crews)
        (remhash key agent-workspace--crews)))
    (when (eq how 'remove)
      (agent-workspace-worktree-remove agent))
    (agent-workspace--changed agent 'forgotten)))

(defun agent-workspace-recolour (agent colour)
  "Give AGENT COLOUR, one of `agent-workspace-colours'."
  (unless (member colour agent-workspace-colours)
    (user-error "Not a colour for an agent: %s" colour))
  (setf (agent-workspace-agent-colour agent) colour)
  (agent-workspace--changed agent 'colour))

(defun agent-workspace-rename (agent name)
  "Rename AGENT to NAME: its session, its worktree and its branch too. Not
while it works; a running session starts again, fresh (its worktree moved)."
  (agent-workspace--check-name name (agent-workspace-agent-project agent) agent)
  (when (memq (agent-workspace-agent-state agent) '(working hand))
    (user-error "%s is working: rename it once it's done" (agent-workspace-agent-name agent)))
  (let ((live (agent-workspace-live-p agent))
        (state (agent-workspace-agent-state agent)))
    (when live (agent-workspace--stop agent 'waking))
    (run-hook-with-args 'agent-workspace-moving-functions agent)
    (agent-workspace-worktree-rename agent name)
    (setf (agent-workspace-agent-name agent) name)
    (agent-workspace--changed agent 'renamed)
    (if live
        (agent-workspace--start agent)
      (agent-workspace--set-state agent state))))

(defun agent-workspace-give (agent issue &optional title)
  "Note that AGENT works on ISSUE (its TITLE): what its state says. nil:
none."
  (setf (agent-workspace-agent-issue agent) issue
        (agent-workspace-agent-issue-title agent) (and issue title))
  (agent-workspace--changed agent 'issue))

(defun agent-workspace--give-back (agent)
  "The issue AGENT had, if it's still in progress and assigned to AGENT:
open again, unassigned (bd, in the background). AGENT then has none."
  (when-let* ((issue (agent-workspace-agent-issue agent)))
    (let ((default-directory (agent-workspace-agent-project agent))
          (name (agent-workspace-agent-name agent)))
      (when (executable-find "bd")
        ;; Guarded: only if it's still AGENT's (the assignee checked by bd).
        (start-process "agent-workspace-give-back" nil "bd" "update" issue
                       (concat "--if-assignee=" name) "--if-status=in_progress"
                       "--status=open" "--assignee=")))
    (agent-workspace-give agent nil)))

(defun agent-workspace-close (&optional project)
  "Close PROJECT's crew (default: the current project's) at once: every
agent exits, without asking, even one working or with its hand raised; no
process of theirs is left (session.el). Their worktrees and branches stay.
The crew is then gone from Emacs (started again from what's saved). Return
their processes, (PID . START) each."
  (when-let* ((project (or project (agent-workspace-project)))
              (key (agent-workspace--root project))
              (agents (gethash key agent-workspace--crews)))
    (run-hook-with-args 'agent-workspace-closing-functions key)
    (remhash key agent-workspace--crews)
    (let ((table (and (seq-some #'agent-workspace-live-p agents)
                      (agent-workspace--process-table))))
      (mapcan (lambda (agent)
                (prog1 (agent-workspace--stop agent 'home table)
                  (agent-workspace--changed agent 'closed)))
              agents))))

(defun agent-workspace-close-all ()
  "Close every crew (as Emacs quits: session.el). Return their processes."
  (mapcan #'agent-workspace-close (agent-workspace-crews)))
