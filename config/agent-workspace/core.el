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
(declare-function agent-workspace-worktree-move "agent-workspace/worktree")
(declare-function agent-workspace-worktree-move-blocker "agent-workspace/worktree")
(declare-function agent-workspace--name-left-p "agent-workspace/new")
(declare-function agent-workspace-crew-members "agent-workspace/saved")
(declare-function agent-workspace-crew-saved "agent-workspace/saved")
(declare-function agent-workspace--bd-give-back "agent-workspace/issues")
(declare-function agent-workspace-worktree-fate "agent-workspace/worktree")
(declare-function agent-workspace-worktree-remove "agent-workspace/worktree")
(declare-function agent-workspace-issue-branch-open "agent-workspace/worktree")
(declare-function agent-workspace--turn-branch "agent-workspace/worktree")
(declare-function agent-workspace--branch-sync "agent-workspace/worktree")
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
`branch' (the one its worktree is on), `panels' (one opened or closed), `canvas' (one of its Agent UI canvases
closed or emptied), `loop' (turned on or off),
`session' (a new one started), `forgotten', `closed' (its crew closed).")

(defvar agent-workspace-closing-functions nil
  "Called with a project as its crew closes, before any agent stops.")

(defvar agent-workspace-moving-functions nil
  "Called with an agent whose worktree is about to move (it's renamed),
its session stopped: what's open there closed, to open again in the new one
once it's `renamed' (or given a `role'), or where it was if it's `unmoved'
\(the move failed).")

(defvar agent-workspace-state-change-functions nil
  "Called with an agent, its old state and its new one, when its state
changes (before `agent-workspace-change-functions').")

(defvar agent-workspace-renamed-functions nil
  "Called with an agent just renamed and its name before: what's kept by
its name (its queued events, its threads) follows it.")

(defvar agent-workspace-hand-functions nil
  "Called with an agent that raised its hand, its ask set: for each request,
a second one while the first still waits too.")

(defvar agent-workspace--hand-count 0 "Hands raised in this Emacs.")

(defvar agent-workspace-role-function #'agent-workspace--bare-role
  "Called with a project and a role's name: the role, a plist. Its keys:
:name, :description, :verb (\"building\"), :instructions (added to the
agent's system prompt), :model, :mode (Claude Code's permission mode),
:tools (allowed), :deny (disallowed), :mcp-servers. Roles (doom-51z.3) set it.")

(defvar agent-workspace--crews (make-hash-table :test #'equal)
  "The crews: a project's root (the main checkout's) to its agents, in the
order they were made.")

;; ====== ONE EMACS A CREW ======
;; A project's crew runs in one Emacs: .agent-shell/agent-workspace/crew.lock
;; names it (its pid) while it does. Another Emacs opening the project (its
;; app, an agent made) is refused, saying where it runs; a lock whose Emacs
;; is gone is taken over.

(defun agent-workspace--crew-lock-file (project)
  "PROJECT's crew lock."
  (expand-file-name ".agent-shell/agent-workspace/crew.lock" project))

(defun agent-workspace--crew-lock-holder (project)
  "The pid of another Emacs running PROJECT's crew (its lock's, alive, an
Emacs), or nil: none, this one, or a lock left by an Emacs gone."
  (when-let* ((file (agent-workspace--crew-lock-file project))
              ((file-readable-p file))
              (pid (ignore-errors
                     (with-temp-buffer (insert-file-contents file)
                                       (string-to-number (car (split-string (buffer-string)))))))
              ((and (> pid 0) (/= pid (emacs-pid))))
              (attributes (process-attributes pid)))
    (and (not (member (alist-get 'state attributes) '("Z" "X")))
         (string-match-p "emacs" (downcase (or (alist-get 'comm attributes) "")))
         pid)))

(defun agent-workspace--crew-lock-check (project)
  "A user error if PROJECT's crew runs in another Emacs, saying where."
  (when-let* ((pid (agent-workspace--crew-lock-holder project)))
    (user-error "The crew of %s runs in another Emacs (pid %d): open it there"
                (file-name-nondirectory (directory-file-name project)) pid)))

(defun agent-workspace--crew-lock-take (project)
  "PROJECT's crew noted as running in this Emacs (after
`agent-workspace--crew-lock-check')."
  (let ((file (agent-workspace--crew-lock-file project)))
    (ignore-errors
      (make-directory (file-name-directory file) t)
      (write-region (format "%d %s\n" (emacs-pid) (system-name)) nil file nil 'silent))))

(defun agent-workspace--crew-lock-release (project)
  "PROJECT's crew no longer running in this Emacs: its lock gone, if it's
this Emacs's."
  (let ((file (agent-workspace--crew-lock-file project)))
    (when (and (file-readable-p file)
               (eql (ignore-errors (with-temp-buffer (insert-file-contents file)
                                                     (string-to-number (car (split-string (buffer-string))))))
                    (emacs-pid)))
      (ignore-errors (delete-file file)))))

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
  branch                     ; the branch its worktree is on: "agent/ada" at rest
  buffer                     ; its agent-shell session's buffer, while it runs
  (state 'asleep)            ; see THE STATES below
  since                      ; when its turn started (`float-time'), working
  ask                        ; its raised hand: (:kind permission :title ...)
  error                      ; why it's stuck: the error's message
  issue                      ; the issue you gave it: "doom-a1b"
  issue-title                ; that issue's title
  loop                       ; non-nil: it loops, taking the next ready issue (loops.el)
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
  "PROJECT as the crews' key: its folder's true name, with a slash. A
crew's key is its own, no file looked at: this is called a few times for
each line drawn, and `file-truename' reads each of its folders (in a
tick, every second of a turn, most of its time)."
  (if (not (eq (gethash project agent-workspace--crews :none) :none))
      project
    (file-name-as-directory (file-truename (expand-file-name project)))))

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
;; until you look: its pane shown), nap (napping: it loops, and no issue is
;; ready for it: loops.el), stuck (an error), asleep (its session stopped by
;; you: Z wakes it), home (gone home: killed, or its process ended).

(defconst agent-workspace-states '(waking desk working hand done nap stuck asleep home)
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
    ('nap (format "napping: nothing to %s"
                  (or (agent-workspace--verb-base (plist-get (agent-workspace-role agent) :verb)) "do")))
    ('stuck (if-let* ((issue (agent-workspace-agent-issue agent)))
                (format "stuck on %s" issue)
              "stuck"))
    ('asleep "asleep")
    ('home "gone home")))

(defun agent-workspace--verb-base (verb)
  "VERB, a role's (\"building\"), as its base form (\"build\"), roughly as
English has it: running, run; writing, write; investigating, investigate.
nil if it isn't a word ending in -ing."
  (when (and (stringp verb) (string-match-p "\\`[a-z]\\{2,\\}ing\\'" verb))
    (let ((stem (substring verb 0 -3)))
      (cond
       ;; A consonant doubled (not adding, telling, passing).
       ((and (> (length stem) 3) (string-match-p "\\([bdgmnprt]\\)\\1\\'" stem))
        (substring stem 0 -1))
       ;; An e dropped.
       ((or (string-match-p "\\`[^aeiou]?[^aeiou][aeiouy][^aeiouwxy]\\'" stem)
            (string-match-p (concat "\\(?:[^aeiou]at\\|[iy]z\\|ag\\|uc\\|[lr]v\\|ov\\|[^aeiou]ar\\|[^aeiou]ir"
                                    "\\|quir\\|[^aeiou]in\\|ib\\|[^aeiou]id\\|[^aeiou]ud\\|um\\|[^aeiou]ut"
                                    "\\|os\\|iv\\|[^aeiou]ok\\|[^aeiou]ak\\|[^aeiou]ul\\|[^aeiou]il\\|[^aeiou]al"
                                    "\\|ur\\|rg\\|dg\\|[^aeiou]eas\\)\\'")
                            stem))
        (concat stem "e"))
       (t stem)))))

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
       ;; Its branch first (worktree.el), before its agent gets the prompt:
       ;; the issue's it was given while it worked, or one made for it at rest.
       ;; Not for a steer into the turn running (working, its hand raised):
       ;; that turn goes on on its branch.
       (agent-workspace--turn-branch agent (alist-get :prompt data) (memq state '(working hand)))
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
       ;; Its branch as its worktree is: renamed by it, once (worktree.el).
       (agent-workspace--branch-sync agent)
       (agent-workspace--set-state
        agent (if (or (equal (alist-get :stop-reason data) "cancelled")
                      (agent-workspace--looked-at-p agent))
                  'desk
                'done)))
      ('error
       ;; Its error first: the state's hooks say it (the room's stuck line).
       (setf (agent-workspace-agent-error agent) (alist-get :message data))
       (agent-workspace--set-state agent 'stuck)
       (agent-workspace--changed agent 'state))
      ('clean-up
       (unless (agent-workspace-agent-stopping agent)
         (agent-workspace--set-state agent 'home))))))

(defun agent-workspace--raise-hand (agent ask)
  "AGENT raises its hand: ASK says what for, given a :key of its own (no
other hand's, in this session or any before: a request's id is counted per
connection)."
  (let ((since (agent-workspace-agent-since agent)))
    (setf (agent-workspace-agent-ask agent)
          (append ask (list :key (format "%x.%d" (truncate (* 1000000 (float-time)))
                                         (cl-incf agent-workspace--hand-count)))))
    (if (eq (agent-workspace-agent-state agent) 'hand)
        (agent-workspace--changed agent 'state)
      (agent-workspace--set-state agent 'hand))
    (setf (agent-workspace-agent-since agent) (or since (float-time)))
    (run-hook-with-args 'agent-workspace-hand-functions agent)))

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
EXCEPT's, an agent being renamed): taken by one running or one its saved
crew keeps while it doesn't run (`agent-workspace-crew-members')."
  (unless (agent-workspace-name-valid-p name)
    (user-error "Not a name for an agent: %S (a lowercase letter, then lowercase letters, digits or -)" name))
  (when-let* ((other (car (seq-find (lambda (member) (string-equal-ignore-case (car member) name))
                                    (agent-workspace-crew-members project)))))
    (unless (and except (equal other (agent-workspace-agent-name except)))
      (user-error "There's an agent named %s already" other))))

(defun agent-workspace-free-colour (&optional project prefer)
  "A colour no agent of PROJECT's crew has, running or saved
\(`agent-workspace-crew-saved'): PREFER (its role's) if it's free, else the
first of `agent-workspace-colours'; all in use, the one fewest have."
  (let* ((project (or project (agent-workspace-project)))
         (used (append (mapcar #'agent-workspace-agent-colour (agent-workspace-agents project))
                       (seq-keep (lambda (entry) (plist-get entry :colour))
                                 (and project (agent-workspace-crew-saved project))))))
    (or (and prefer (not (member prefer used)) prefer)
        (seq-find (lambda (colour) (not (member colour used))) agent-workspace-colours)
        (car (seq-sort-by (lambda (colour) (seq-count (lambda (c) (equal c colour)) used))
                          #'< agent-workspace-colours)))))

(cl-defun agent-workspace-create (&key role name colour model mode prompt issue issue-title
                                       issue-type project (kind 'claude-code))
  "Make an agent in PROJECT's crew (default: the current project's) and start
it: ROLE (its name, required), NAME (required), COLOUR (default: its role's
while free, else a free one), MODEL and MODE (default: its role's), KIND (an
agent of `agent-workspace-kinds'). It gets its own worktree, always, and its
session starts there. PROMPT, if given, is its first message, sent once it's
ready; ISSUE (an id, and ISSUE-TITLE, ISSUE-TYPE), the issue it's for (its
branch for it opened in its worktree: `agent-workspace-give'): its first
message unless PROMPT, \"Work on ID: TITLE\". Return the agent.

A step failing says which: its worktree (or its issue's branch) not made,
nothing is; its session not started, it's stuck saying why, in the crew."
  (let ((project (or project (agent-workspace-project)
                     (user-error "Not in a git repository: a crew needs one"))))
    (unless (and (stringp role) (not (string-empty-p role)))
      (user-error "An agent needs a role"))
    (agent-workspace--check-role project role)
    (agent-workspace--check-name name project)
    ;; Its first agent here: not if the crew runs in another Emacs.
    (unless (agent-workspace-agents project)
      (agent-workspace--crew-lock-check project))
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
          (progn
            (agent-workspace-worktree-ensure agent)
            (when issue
              (agent-workspace-issue-branch-open agent issue issue-type issue-title)))
        (error (user-error "%s's worktree: %s" name (error-message-string err))))
      (let ((key (agent-workspace--root project)))
        (puthash key (append (gethash key agent-workspace--crews) (list agent))
                 agent-workspace--crews)
        (agent-workspace--crew-lock-take key))
      (when issue
        (agent-workspace-give agent issue issue-title issue-type))
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
  "Start AGENT again, with a fresh session; not running (asleep, gone
home), only if its role has room for one more, as when it's woken."
  (unless (agent-workspace-live-p agent)
    (agent-workspace--check-room (agent-workspace-agent-project agent) (agent-workspace-agent-role agent)))
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
asked: no work is lost without asking. The issue you gave it goes back,
as when it's killed (`agent-workspace--give-back')."
  (let ((how (agent-workspace-worktree-fate agent worktree)))
    (agent-workspace--stop agent 'home)
    (agent-workspace--give-back agent)
    (let ((key (agent-workspace-agent-project agent)))
      (puthash key (remq agent (gethash key agent-workspace--crews)) agent-workspace--crews)
      (unless (gethash key agent-workspace--crews)
        (remhash key agent-workspace--crews)
        (agent-workspace--crew-lock-release key)))
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
while it works, nor to a name a forgotten agent left (its worktree or
branch still there); a running session starts again, fresh (its worktree
moved)."
  (let ((project (agent-workspace-agent-project agent)))
    (agent-workspace--check-name name project agent)
    (when (memq (agent-workspace-agent-state agent) '(working hand))
      (user-error "%s is working: rename it once it's done" (agent-workspace-agent-name agent)))
    (when (and (not (equal name (agent-workspace-agent-name agent)))
               (agent-workspace--name-left-p project name))
      (user-error "%s is the name of a forgotten agent: its worktree or branch is still there" name))
    (agent-workspace--move agent name (agent-workspace-agent-role agent) 'renamed)))

(defun agent-workspace-set-role (agent role)
  "Give AGENT ROLE: its worktree moved after it (ROLE-NAME). Not while it
works; a running session starts again, fresh, as ROLE says."
  (unless (equal role (agent-workspace-agent-role agent))
    (when (memq (agent-workspace-agent-state agent) '(working hand))
      (user-error "%s is working: change its role once it's done" (agent-workspace-agent-name agent)))
    (agent-workspace--move agent (agent-workspace-agent-name agent) role 'role)))

(defun agent-workspace--move (agent name role what)
  "AGENT renamed NAME or given ROLE (WHAT: `renamed', `role'): its worktree
moved after them, its session stopped meanwhile and started again. Refused
before anything changes if its worktree can't move
\(`agent-workspace-worktree-move-blocker'); failing midway, AGENT as it was
\(its name, its worktree, locked, its branch; its session started again,
what was open there opened again: changed `unmoved'), a user error saying
why."
  (when-let* ((why (agent-workspace-worktree-move-blocker agent name role)))
    (user-error "%s" why))
  (let ((live (agent-workspace-live-p agent))
        (state (agent-workspace-agent-state agent))
        (was (agent-workspace-agent-name agent)))
    (when live (agent-workspace--stop agent 'waking))
    (run-hook-with-args 'agent-workspace-moving-functions agent)
    (let ((failed (condition-case err
                      (progn (agent-workspace-worktree-move agent name role) nil)
                    (error (error-message-string err)))))
      (when (and (not failed) (eq what 'renamed) (not (equal was name)))
        (run-hook-with-args 'agent-workspace-renamed-functions agent was))
      (agent-workspace--changed agent (if failed 'unmoved what))
      (if live
          (agent-workspace--start agent)
        (agent-workspace--set-state agent state))
      (when failed
        (user-error "%s %s: %s" was (if (eq what 'renamed) "isn't renamed" "keeps its role") failed)))))

(defun agent-workspace-give (agent issue &optional title type)
  "Give AGENT ISSUE (its TITLE, its TYPE: bd's issue_type) to work on, before
its prompt is sent (t, the room's offer, its loop, :issue as it's made all
come here): its branch for it opened in its worktree first (worktree.el:
TYPE/ID-SLUG, from the main checkout's branch; as its next turn starts if it's
working), a user error if it can't be (changes not committed there):
nothing given. Then noted: what its state says. nil: none, its branch as
it is."
  (when issue
    (agent-workspace-issue-branch-open agent issue type title))
  (agent-workspace--note-issue agent issue title))

(defun agent-workspace--note-issue (agent issue &optional title)
  "Note that AGENT works on ISSUE (its TITLE): what its state says. nil:
none. Its branch as it is (an issue it claimed itself: loops.el)."
  (setf (agent-workspace-agent-issue agent) issue
        (agent-workspace-agent-issue-title agent) (and issue title))
  (agent-workspace--changed agent 'issue))

(defun agent-workspace--give-back (agent)
  "The issue AGENT had, if it's still in progress and assigned to AGENT:
open again, unassigned (bd as AGENT, in the background; a failure said in
its room: `agent-workspace--bd-give-back'). AGENT then has none."
  (when-let* ((issue (agent-workspace-agent-issue agent)))
    (agent-workspace--bd-give-back agent issue)
    (agent-workspace--note-issue agent nil)))

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
    (agent-workspace--crew-lock-release key)
    (let ((table (and (seq-some #'agent-workspace-live-p agents)
                      (agent-workspace--process-table))))
      (mapcan (lambda (agent)
                (prog1 (agent-workspace--stop agent 'home table)
                  (agent-workspace--changed agent 'closed)))
              agents))))

(defun agent-workspace-close-all ()
  "Close every crew (as Emacs quits: session.el). Return their processes."
  (mapcan #'agent-workspace-close (agent-workspace-crews)))
