;;; $DOOMDIR/config/agent-workspace.el -*- lexical-binding: t; -*-
;; The agent workspace: a crew of coding agents on one project, each with a
;; name, a role, a colour and a state, run from one app in Emacs
;; (docs/agent-workspace.md). Loaded from config.el; its code is in
;; config/agent-workspace/.

;; ====== VARIABLES ======

;; WHO AN AGENT WORKS WITH
;; You, always. Its crew's other agents, and events from outside, only while
;; these say so (both on here; config.el turns them off for now): each one off,
;; refused, its keys saying so, what was left queued kept and not delivered.
(defcustom agent-workspace-agents-talk t
  "Non-nil: the crew's agents talk to each other: their messages (as the
crew's switch says: `agent-workspace-talk', T) and their issues handed on
from role to role (a role's hands-to). nil: they never do, each works only
with you: a message refused, T off, a role's hands-to ignored (it's told to
hand nothing on), messages left queued not delivered (see AGENTS ASKING EACH
OTHER and WORK HANDED ON THROUGH ISSUES below)."
  :type 'boolean
  :group 'agent-workspace)

(defcustom agent-workspace-outside-events t
  "Non-nil: events from outside (cmd/agent-workspace send from the shell or
a script, --from SOURCE) reach the crew, through its inbox. nil: refused,
nothing but you prompts an agent; events left queued not delivered (see THE
INBOX below)."
  :type 'boolean
  :group 'agent-workspace)

;; ITS PERMISSION MODE
;; Claude Code's (`agent-workspace-modes'): an agent's own (e, C-u c), else
;; its role's (its file's mode:; the starters have none), else
;; `agent-workspace-mode': auto, Claude deciding what needs your OK. The bar
;; shows it.
(defcustom agent-workspace-mode "auto"
  "The permission mode an agent starts in (Claude Code's id) when neither
you (e, C-u c) nor its role (mode:) chose one. auto: Claude decides what
needs your OK. nil: Claude Code's own default."
  :type '(choice (const :tag "Claude Code's" nil) string)
  :group 'agent-workspace)

;; AGENTS
;; An agent of a project's crew (config/agent-workspace/core.el): a name
;; ("ada": a lowercase letter, then lowercase letters, digits or -), a role
;; ("builder"), a colour (one of the theme's ANSI faces, its role's or a free
;; one by default: `agent-workspace-colours'), an agent kind (Claude Code:
;; `agent-workspace-kinds'), its session, its worktree, its state and the issue
;; you gave it.

;; MAKING ONE
;; M-x agent-workspace-new (config/agent-workspace/new.el; the app's c) asks
;; its role (what it does, how many run of its max), then its name: left
;; empty, one from `agent-workspace-names' whose initial no agent has; C-u:
;; its model, permission mode and colour too. From Lisp:
;;   (agent-workspace-create :role "builder" :name "ada" :issue "doom-a1b")
;; (an issue's id: its worktree on the issue's branch, see ITS BRANCHES; its
;; first message, "Work on doom-a1b: TITLE"); from the shell, cmd/agent-workspace new --role builder [--name ada] [--prompt TEXT]
;; (config/agent-workspace/request.el), replying JSON. A step failing says
;; which: its worktree not made, nothing is; its session not started, it's
;; stuck saying why.

;; WHAT YOU DO TO ONE
;; It's interrupted, killed (gone home: the issue you gave it, still in
;; progress and its, goes back to open), restarted fresh, put to sleep, woken,
;; renamed, recoloured, forgotten (out of the crew). Only you prompt it
;; (`agent-workspace-send').

;; ROLES
;; What each kind of agent does and may do (config/agent-workspace/roles.el):
;; a Markdown file each, NAME.md, as Claude Code's own agents are: a front
;; matter (its tools allowed without asking, its tools denied, its model,
;; permission mode, labels, how many may run, icon, verb, colour), then its
;; instructions. The starters ship in config/agent-workspace/roles/ (scribe,
;; investigator, builder, reviewer); a project's own, in its
;; .agent-workspace/roles/, add to them or replace one of the same name (M-x
;; agent-workspace-copy-role copies a starter there to change it). Its tools
;; and permission mode are enforced by Claude Code (its options), not only
;; told. A file's problems are warnings naming its file and line.

;; ITS STATES
;; waking up, at the desk (waiting for you), working (its turn's time counted
;; from its start), hand raised (a permission, a question: agent-shell's, or
;; one waiting on its Agent UI canvas), done (until you look: its session
;; shown), napping (it loops and nothing is ready for it: see LOOPS), stuck
;; (an error), asleep, gone home. They follow its session's events, never
;; polled.

;; LOOPS
;; (config/agent-workspace/loops.el) Off for every agent; L turns one's on
;; (↻ on its bar; kept in crew.json). Once free (its turn ended, the issue it
;; had closed or handed over: still in progress, it waits for you to look), it
;; takes the next issue by itself: one you gave it first, else the next ready
;; one its role's labels say, claimed as itself (bd ready --claim: two never
;; get the same one), on its branch (see ITS BRANCHES), its session fresh for
;; it. None left: it naps (☾ "napping: nothing to build"), said once in the
;; room and notified, and wakes when one comes (.beads changing; a look every
;; `agent-workspace-loop-check' minutes). A failure (its turn's error, its
;; session not started, bd failing, changes not committed in its worktree:
;; nothing claimed) is tried again
;; `agent-workspace-loop-retry' seconds later; after
;; `agent-workspace-loop-failures' in a row it stops, stuck, saying why. A
;; crew started again brings a looping agent back asleep: reopening never
;; starts work by itself.

;; ITS WORKTREE
;; Always its own (config/agent-workspace/worktree.el):
;; .agent-shell/worktrees/ROLE-NAME of its project (builder-ada), made with
;; it on the branch agent/NAME (from the main checkout's HEAD), locked with
;; its name as the reason ("agent ada (builder), crew of doom"), kept when it
;; stops (started again on the branch it's on), moved when it's renamed or
;; its role changes (e; not while it works). One of its named otherwise in
;; .agent-shell/worktrees (worktrees/NAME, as they were named before) is
;; moved there as it starts, its work with it. A project that isn't a git
;; repository, or has no commit, has no crew. .agent-shell/ is kept out of
;; git (the repository's info/exclude, if no .gitignore does it). Forgetting
;; an agent removes its worktree and branches when they hold nothing the
;; main checkout hasn't; else you're shown what they hold (each of its
;; branches) and asked.

;; ITS BRANCHES
;; A branch of its own for each piece of work, in its worktree, made as the
;; work starts (worktree.el); its bar shows the one it's on. An issue given to
;; it (t, the room's offer, its loop, :issue: `agent-workspace-give', core.el)
;; gets TYPE/ID-SLUG (fix/doom-pbk.18-minimaps-dividers-dont-line: fix/ a
;; bug, feat/ a feature, else its type, task/...; then its title's first 4
;; words, small ones dropped), from the main checkout's branch as it is
;; then; the agent never renames it (it's told so, session.el). One of the
;; issue's there already (TYPE/ID-..., any type, any words: given back, its
;; title changed since) checked out again, taken from another agent at rest. Given while it works, as the
;; issue's prompt starts its next turn. Its worktree with changes not
;; committed takes none: refused, saying which branch has them (as its turn
;; starts: it stays, said). A prompt of yours at rest (the room, #, its
;; session: agent-shell's input-submitted) gets a branch named from its first
;; words (lowercase, an "Area: " dropped, at most 48 characters), where it is
;; (no file changes); not a / command, nor what it's only told (a merge, an
;; event). Between pieces of work it rests on
;; agent/NAME at the main branch's tip: nothing is merged from it (one with
;; work from before keeps it, merged as before). A branch it leaves holding
;; nothing (a question, an investigation) is deleted. Each is noted as its
;; agent's in the repository's config (branch.BRANCH.agent-workspace-agent).
;; M-x agent-workspace-review (d): a branch's changes in magit
;; (MAIN...BRANCH); M-x agent-workspace-merge (M): merged into the main
;; checkout, always with a merge commit naming it (--no-ff, never a
;; fast-forward), the agent told, the branch deleted and the agent back at
;; rest (not while it works or has changes not committed: M again later).
;; Both on the branch it's on, or asked which when others of its hold work.

;; ITS NAME ON IT, IN EMACS
;; (config/agent-workspace/names.el) Its worktree's files belong to the
;; project "PROJECT · NAME"; their mode line shows the agent ("▌A ada ·
;; builder", in its colour; a click selects it) and their tab starts with its
;; avatar. A worktree a forgotten agent left shows its name dimmed.

;; ITS SESSION
;; agent-shell's (config/agent-workspace/session.el), in its worktree, its
;; buffer "ada · builder". Its role's model, tools and MCP servers, its
;; permission mode (see ITS PERMISSION MODE above); in its system prompt, after what every session is told, who it is
;; and how it works, then its role's instructions; in its environment its name
;; (BEADS_ACTOR, AGENT_WORKSPACE_AGENT) and the project's issues (BEADS_DIR).

;; CLOSING A CREW
;; `agent-workspace-close' (and quitting Emacs) stops every agent at once,
;; asking nothing, and leaves no process of theirs: what hasn't exited
;; `agent-workspace-exit-timeout' seconds later is killed. Their worktrees stay.

;; THE ROOM
;; One chat for the whole crew (config/agent-workspace/room.el), the app's
;; right column (at the bottom, under the stage, in a frame under 200 columns,
;; or with `agent-workspace-room-side' bottom); 2 the room alone, 1 the stage
;; again. Its feed: each agent's turns (their answers' first lines; RET opens
;; its pane), the issues it files, claims, labels, hands on and closes (as
;; they change, fetched before and after: never yours, nor what was there as
;; the app opened), the crew's changes (an agent joining, going home,
;; started again, stuck), raised hands, your
;; messages; F filters it. Its compose line: #ada to ada, #builders to the
;; first free builder, #all to everyone, no # to the selected agent; busy, it
;; gets it after its turn; # at its start offers the agents, roles and all as
;; it's typed (with Corfu; TAB completes it), M-p / M-n your messages; 3
;; lines of text (`agent-workspace-compose-lines'), growing into the feed as
;; its text needs, up to `agent-workspace-compose-max-lines' or half the room.
;; # in the app talks to the agent there. Kept per project, per machine, in
;; .agent-shell/agent-workspace/room.jsonl.

;; RAISED HANDS, ANSWERED FROM ONE PLACE
;; (config/agent-workspace/hands.el) A permission's options are agent-shell's
;; own buttons, pressed as they are; a question on an agent's canvas (a
;; choice) its options, answered as its Answer button does; anything else,
;; "go to it". They're buttons under the hand in the room, on its agent's bar
;; and header line; A picks one, a goes to the next hand.

;; THE INBOX
;; Events from outside for an agent, a role or everyone
;; (config/agent-workspace/inbox.el): cmd/agent-workspace send --to ada|#builder
;; |#all [--from ci] TEXT. Queued, kept in .agent-shell/agent-workspace/
;; inbox.jsonl (a restart keeps them), delivered when the agent is free (never
;; waking one asleep), one at a time, as data from its source, never
;; instructions; the turn it starts runs in plan mode (it reads and
;; investigates; editing asks you), its own mode back after. In the room:
;; queued ([Send now] [Drop]), delivered, dropped; ✉N on its agent's bar; P
;; pauses them all. Limits: 6 an hour from a source, 40 a day for an agent.
;; E lists them in the room's place: RET sends one now, d drops it, M-up /
;; M-down move it, o turns its source off for its agent or everyone (kept in
;; crew.json), q back. None delivered in `agent-workspace-inbox-quiet-hours'.
;; Only with `agent-workspace-outside-events' (E and P: while messages use
;; it too).

;; AGENTS ASKING EACH OTHER
;; A direct message for a question (config/agent-workspace/messages.el), from
;; an agent's shell: cmd/agent-workspace send --to ken TEXT. T in the app: may
;; they, off / ask me (each waits in the room for [Send] [Edit] [Drop]) / on,
;; kept in crew.json; a role's talks-to: names the roles it may message without
;; your OK. Through the inbox: delivered when free, framed as from the sender
;; (data, not your instructions); the reply goes back to the sender, as an
;; answer. In the room, each exchange a thread: TAB folds it, x stops it (or
;; lets it go again), [Answer] answers for the agent it's for. A thread waits
;; for your OK after 5 messages without you; an agent sends at most 10 an
;; hour. Each agent is told its crew and how to message (what it may without
;; your OK, never waiting on another agent). Only with
;; `agent-workspace-agents-talk'.

;; WORK HANDED ON THROUGH ISSUES
;; (config/agent-workspace/handover.el) A role's hands-to: names where its
;; finished issues go (investigator -> builder -> reviewer, a reviewer's
;; changes back to the builder). Each agent is told how: the label changed to
;; the next role's, the issue open and unassigned, notes for them; given back
;; for changes, assigned to the builder who made it. The first free agent of
;; that role takes it (t, or its loop). The room says each hand-over. Only
;; with `agent-workspace-agents-talk': without it, an agent whose role hands
;; on is told to hand nothing on, only to tell you. A ready issue of a role
;; is still offered to its first free agent, for you to give.

;; THE SAVED CREW
;; What the crew is, not its state, saved per project on this machine, not
;; committed: .agent-shell/agent-workspace/crew.json, beside the room and the
;; inbox (config/agent-workspace/saved.el), JSON, read as data, never
;; evaluated. Each agent's name, role, colour (its model and mode when not its
;; role's), whether it's asleep, whether it loops, its open panels by name
;; (never their data); the layout; never its branch (its worktree keeps the
;; one it's on). Written when the crew changes (a panel
;; opened or closed too), one agent a line; closing the crew leaves it as it
;; was. SPC o w with no crew running starts it again from there: every agent
;; fresh, in its worktree, its role as it is now, its panels opened again
;; there, asleep ones and looping ones asleep, each waiting for you; one that
;; can't start stuck, saying why; a panel whose file is gone skipped, said; a
;; wrong agent left out, said by its place and name; a file that isn't JSON or
;; isn't a crew said, nothing started. gR reads it again (after an edit),
;; asking before it starts or forgets one, or turns a loop on.

;; THE APP
;; SPC o w, from inside a project (outside one, asked which): its crew's own
;; workspace, "crew · PROJECT" (config/agent-workspace/app.el); SPC o W: in
;; the window you're in. A project that can't have a crew (not a git
;; repository, no commit yet) says why and offers a terminal with git init
;; typed. The first time, its first agent is asked for. Two columns (the room
;; comes on the right, doom-51z.6):
;; - the issues (config/agent-workspace/issues.el), on the left: in progress
;;   (each with its agent), ready by the role they're for then by epic (its
;;   heading, its issues under it, those of none last), blocked, done today,
;;   each its type before its id (the Beads panel's icon, config/beads/look.el;
;;   its first letter in a terminal); moving onto one in progress selects its
;;   agent;
;; - the stage (config/agent-workspace/stage.el): every agent a pane, in role
;;   order; the selected one's open (its session; below it, beside it from
;;   140 columns, its canvases (its own, ask...) and panels as tabs, one
;;   shown: v the next, V it full size; a question there takes no focus, its
;;   hand says it), the others folded to a bar (◫2: its panels). Its line (a
;;   bar, the open pane's header line) shows first on its right its context
;;   used, 20% (agent-shell's colours: yellow from 60%, red from 85%; its
;;   tokens and cost on hover), drawn again as agent-shell reports it. It
;;   arranges itself: tiling leaves its frame alone (config/tiling.el).
;; q leaves it (the crew goes on, its tally in the other workspaces' mode
;; line: a click comes back); Q, SPC TAB d, or quitting Emacs close it at
;; once: every agent exits, no question asked.
;;
;; Keys, in evil's normal state:
;;   the issues   j / k the next / previous issue, RET (l, o) its agent's pane
;;                or the issue (on an epic's heading, the epic), t give it to
;;                an agent, c a new agent (for it)
;;   the bars     j / k the next / previous agent (the cursor in its pane),
;;                RET its pane, TAB open or fold
;;   both         c a new agent, i interrupt, K kill (gone home), r restart
;;                fresh, s sleep or wake, e edit (name, colour, role, mode,
;;                model), d its branch's changes, M merge its branch, v its
;;                canvas and panels (the cursor there; again: the next one), V
;;                the one there full size (again: back), I its issue, L its
;;                loop on or off, a the next raised hand, A answer it, f + an
;;                initial that agent, gr lay out again, gR read crew.json again,
;;                q leave, Q close, ? the keys
;;   its session  the same after SPC m w (C-c w in insert state), and ] / [
;;                the next / previous agent; a click on its header line or a
;;                bar selects it, mouse-3 its actions
;;   its canvas,  v / V as above; a click on a tab shows it
;;   its panels

;; ====== KEY BINDINGS ======

(map! :leader
      :desc "Agent crew"       "o w" #'agent-workspace-open
      :desc "Agent crew, here" "o W" #'agent-workspace-open-here)

;; ====== CODE ======

;; In config/agent-workspace/, in this order: each part can use what the ones
;; before it define.
(load! "agent-workspace/core")
(load! "agent-workspace/worktree")
(load! "agent-workspace/session")
(load! "agent-workspace/roles")
(load! "agent-workspace/names")
(load! "agent-workspace/new")
(load! "agent-workspace/request")
(load! "agent-workspace/look")
(load! "agent-workspace/stage")
(load! "agent-workspace/app")
(load! "agent-workspace/issues")
(load! "agent-workspace/room")
(load! "agent-workspace/hands")
(load! "agent-workspace/inbox")
(load! "agent-workspace/messages")
(load! "agent-workspace/handover")
(load! "agent-workspace/panels")
(load! "agent-workspace/activity")
(load! "agent-workspace/minimap")
(load! "agent-workspace/loops")
(load! "agent-workspace/saved")
(load! "agent-workspace/doom")

;; The app's keys, in its buffers (see THE APP above). Set here, at top level:
;; a reload sets them again.
(defvar +my/agent-workspace-keys
  '(("c" . agent-workspace-new-here) ("i" . agent-workspace-interrupt-here)
    ("K" . agent-workspace-kill-here) ("r" . agent-workspace-restart-here)
    ("s" . agent-workspace-sleep-here) ("e" . agent-workspace-edit)
    ("d" . agent-workspace-review-here) ("M" . agent-workspace-merge-here)
    ("v" . agent-workspace-panels-here) ("V" . agent-workspace-full-here) ("I" . agent-workspace-issue-here)
    ("L" . agent-workspace-loop-here)
    ("a" . agent-workspace-next-hand) ("A" . agent-workspace-answer) ("f" . agent-workspace-jump)
    ("gr" . agent-workspace-layout) ("gR" . agent-workspace-crew-reload) ("q" . agent-workspace-leave)
    ("Q" . agent-workspace-quit) ("?" . agent-workspace-help)
    ("#" . agent-workspace-talk) ("1" . agent-workspace-view-stage) ("2" . agent-workspace-view-room)
    ("m" . agent-workspace-minimap-toggle) ("P" . agent-workspace-inbox-pause)
    ("T" . agent-workspace-talk-cycle) ("E" . agent-workspace-inbox-view))
  "The keys every buffer of the app has (see THE APP above).")

(+my/agent-workspace-bind agent-workspace-issues-mode-map
                          (append '(("j" . agent-workspace-issue-next) ("k" . agent-workspace-issue-previous)
                                    ("<down>" . agent-workspace-issue-next) ("<up>" . agent-workspace-issue-previous)
                                    ("RET" . agent-workspace-issue-open) ("<return>" . agent-workspace-issue-open)
                                    ("l" . agent-workspace-issue-open) ("o" . agent-workspace-issue-open)
                                    ("t" . agent-workspace-issue-give) ("gr" . agent-workspace-issues-refresh))
                                  +my/agent-workspace-keys))

;; The minimap, under the issues (config/agent-workspace/minimap.el): a lane
;; each agent (its avatar and role's icon, its name and role on hover; the
;; quiet ones' too), what it did minute by minute, a cell a column on the
;; screen (a glyph the font draws wider: its fallback, ± for ✎), every lane's
;; │ at the same column, a line too long cut with …; RET its agent, o the
;; file it's in, d its changes (on a ⚠: both agents'). m shows or hides it,
;; anywhere.
(+my/agent-workspace-bind agent-workspace-minimap-mode-map
                          (append '(("j" . agent-workspace-minimap-next) ("k" . agent-workspace-minimap-previous)
                                    ("<down>" . agent-workspace-minimap-next) ("<up>" . agent-workspace-minimap-previous)
                                    ("RET" . agent-workspace-minimap-select) ("<return>" . agent-workspace-minimap-select)
                                    ("o" . agent-workspace-minimap-open) ("d" . agent-workspace-minimap-diff))
                                  +my/agent-workspace-keys))

(+my/agent-workspace-bind agent-workspace-bar-mode-map
                          (append '(("j" . agent-workspace-next) ("k" . agent-workspace-previous)
                                    ("<down>" . agent-workspace-next) ("<up>" . agent-workspace-previous)
                                    ("RET" . agent-workspace-go) ("<return>" . agent-workspace-go)
                                    ("TAB" . agent-workspace-toggle) ("<tab>" . agent-workspace-toggle))
                                  +my/agent-workspace-keys))

;; An agent's canvas or panel, in its pane on the stage: v and V there too, in
;; place of evil's visual state.
(+my/agent-workspace-bind agent-workspace-side-mode-map
                          '(("v" . agent-workspace-panels-here) ("V" . agent-workspace-full-here)))

;; The inbox's view (E).
(+my/agent-workspace-bind agent-workspace-inbox-mode-map
                          '(("RET" . agent-workspace-inbox-view-send-now) ("<return>" . agent-workspace-inbox-view-send-now)
                            ("d" . agent-workspace-inbox-view-drop) ("o" . agent-workspace-inbox-view-source-off)
                            ("M-<up>" . agent-workspace-inbox-view-up) ("M-<down>" . agent-workspace-inbox-view-down)
                            ("M-k" . agent-workspace-inbox-view-up) ("M-j" . agent-workspace-inbox-view-down)
                            ("q" . agent-workspace-inbox-view-quit) ("Q" . agent-workspace-quit)
                            ("?" . agent-workspace-help)))

;; The room: its feed, its compose line (RET sends there, in insert state too).
(+my/agent-workspace-bind agent-workspace-room-mode-map
                          '(("RET" . agent-workspace-room-open) ("<return>" . agent-workspace-room-open)
                            ("F" . agent-workspace-room-filter) ("i" . agent-workspace-room-compose)
                            ("TAB" . agent-workspace-room-fold) ("<tab>" . agent-workspace-room-fold)
                            ("x" . agent-workspace-room-stop)
                            ("a" . agent-workspace-room-compose) ("#" . agent-workspace-room-compose)
                            ("1" . agent-workspace-view-stage) ("2" . agent-workspace-view-room)
                            ("gr" . agent-workspace-layout) ("q" . agent-workspace-leave)
                            ("Q" . agent-workspace-quit) ("?" . agent-workspace-help)))

(map! :map agent-workspace-compose-mode-map
      "RET" #'agent-workspace-compose-send
      "M-p" #'agent-workspace-compose-previous
      "M-n" #'agent-workspace-compose-next
      "TAB" #'completion-at-point
      :ni "RET" #'agent-workspace-compose-send
      :ni "M-p" #'agent-workspace-compose-previous
      :ni "M-n" #'agent-workspace-compose-next
      :i "TAB" #'completion-at-point
      :n "q" #'agent-workspace-leave)

(after! evil
  (evil-set-initial-state 'agent-workspace-compose-mode 'insert))

;; In an agent's own session (agent-shell's keys): the same after a prefix.
(defvar +my/agent-workspace-pane-map (make-sparse-keymap)
  "The app's keys in an agent's session, after SPC m w or C-c w.")

(pcase-dolist (`(,key . ,command)
               (append '(("]" . agent-workspace-next) ("[" . agent-workspace-previous)
                         ("TAB" . agent-workspace-toggle) ("<tab>" . agent-workspace-toggle))
                       +my/agent-workspace-keys))
  (define-key +my/agent-workspace-pane-map (kbd key) command))

(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c w" +my/agent-workspace-pane-map
      :localleader
      :desc "Agent crew" "w" +my/agent-workspace-pane-map)


;; WHAT AN AGENT IS TOLD (see ITS SESSION above), after what every session is.
(add-hook '+my/agent-shell-claude-context-functions #'agent-workspace-agent-context t)

;; AN AGENT'S PANELS (config/agent-workspace/panels.el): a project panel an
;; agent opens runs in its worktree, "tests · ada", never popped up (its pane
;; on the stage shows it), trusted as its project, closed with the agent;
;; saved with the crew by name, opened again with it (see THE SAVED CREW).
(setq agent-ui-panel-name-function #'agent-workspace--panel-name
      agent-ui-panel-trust-root-function #'agent-workspace--panel-trust-root
      agent-ui-panel-display-function #'agent-workspace--panel-display)

;; NO CREW HERE (see THE APP above): a terminal offered, git init typed in it.
(setq agent-workspace-no-crew-function #'+my/agent-workspace-git-init)

;; AN ISSUE SHOWN (I, RET on one nobody's on): Beads' issue view
;; (config/agent-ui.el's, config/beads.el).
(setq agent-workspace-open-issue-function #'+my/agent-ui-open-issue)

;; ITS AVATAR on its worktree's tabs (see above).
(add-hook '+my/tabs-prefix-functions #'agent-workspace-tab-prefix)

;; A QUESTION WAITING on an agent's canvas (config/agent-ui/agent.el): its hand
;; raised.
(add-hook 'agent-ui-question-waiting-functions #'agent-workspace--question-waiting)
