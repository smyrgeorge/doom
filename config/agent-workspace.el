;;; $DOOMDIR/config/agent-workspace.el -*- lexical-binding: t; -*-
;; The agent workspace: a crew of coding agents on one project, each with a
;; name, a role, a colour and a state, run from one app in Emacs
;; (docs/agent-workspace.md). Loaded from config.el; its code is in
;; config/agent-workspace/.

;; ====== VARIABLES ======

;; WHO AN AGENT WORKS WITH
;; You, always. Its crew's other agents, and events from outside, only while
;; these say so (both on here; config.el turns events from outside off for
;; now): each one off, refused, its keys saying so, what was left queued kept
;; and not delivered.
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
;; one by default: `agent-workspace-colours'), an agent kind (its role's kind:,
;; else `agent-workspace-kind'; one of `agent-workspace-kinds': claude-code,
;; codex, gemini-cli...), its session, its worktree, its state and the issue
;; you gave it.
(defcustom agent-workspace-kind 'claude-code
  "The kind of agent a role without kind: runs: a key of
`agent-workspace-kinds' (agent-shell's identifier: claude-code, codex...)."
  :type 'symbol
  :group 'agent-workspace)

;; MAKING ONE
;; M-x agent-workspace-new (config/agent-workspace/new.el; the app's c) asks
;; its role or a crew, "Role or crew:" (a row of columns each: its icon, what
;; it does, how many run of its max, its model, mode, labels with their ready
;; issues, hands-to, the role it replaced; fewer in a narrow minibuffer; one
;; at its max dimmed, refused; grouped under dividers: local, project,
;; starters, then the crews (see CREWS below), then the role and crew files
;; left out, refused naming file and line), then, a role picked, its name:
;; left empty, one from `agent-workspace-names' whose initial no agent has;
;; C-u: its model, permission mode and colour too. A crew picked: the agents
;; it lacks made at once, nothing more asked. c on a ready issue makes an
;; agent for it: no crews offered there. From Lisp:
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
;; permission mode, labels, how many may run, whether it leads, icon, verb,
;; colour), then its instructions. The starters ship in config/agent-workspace/roles/ (scribe,
;; investigator, builder, reviewer, tester, documenter, triager, planner,
;; designer, security, profiler, lead); a project's own, in its
;; .agent-workspace/roles/ (committed), and yours for it, in its
;; .agent-shell/agent-workspace/roles/ (out of git), add to them; a later
;; one replaces one of the same name: starter < project < local (M-x
;; agent-workspace-copy-role copies a starter, or a project's role into your
;; local ones, to change it there). Its tools and permission mode are
;; enforced by Claude Code (its options), not only told. Its tools, deny and
;; instructions may name {main} (the main checkout), {main-branch}, {name}
;; and {project}, filled in as its session starts: the reviewer's rules name
;; its two merges exactly, no * before merge. A file's problems
;; are warnings naming its file and line (an error leaves the role out: no
;; description, a name, mode, max, colour or tool that isn't one); M-x
;; agent-workspace-check-roles lists them all.

;; CREWS
;; The agents a crew should have, made at once (config/agent-workspace/
;; crews.el): a Markdown file each, NAME.md, its front matter as a role's: a
;; description and its agents (roles with counts: agents: scribe, builder 2,
;; reviewer); its new agents loop as any new one does (see LOOPS).
;; The starters ship in config/agent-workspace/crews/: small
;; (scribe, builder: you merge), full (scribe, builder, reviewer: it merges),
;; extended (full, with two builders); a project's own go in
;; its .agent-workspace/crews/ (committed), yours in its
;; .agent-shell/agent-workspace/crews/ (out of git), a later one replacing
;; one of the same name: starter < project < local. In c's menu, after the
;; roles: a row each, its icon, name, description, its agents, and what it
;; would add here (+ builder, reviewer), or, dimmed and refused, nothing to
;; add. Picked, it makes for each role its count less the crew's agents of
;; that role (asleep and gone home ones counting, and those crew.json keeps
;; while the crew isn't running), no name asked, as c makes one with its
;; name left empty; the room says who was made ("crew full: +
;; builder ada, reviewer ken"). It only adds: an agent beyond its count,
;; or of a role it doesn't list, stays as it is. A file's problems are
;; warnings naming file and line; an error leaves it out (a role that isn't
;; the project's, a count that isn't one, over its role's max:); M-x
;; agent-workspace-check-roles lists them too.
;; From the shell, cmd/agent-workspace crew NAME, replying JSON with the
;; agents made.
(defcustom agent-workspace-crews-directory ".agent-workspace/crews"
  "Where a project keeps its own crew files, committed: shared with whoever
works on it."
  :type 'string
  :group 'agent-workspace)

(defcustom agent-workspace-local-crews-directory ".agent-shell/agent-workspace/crews"
  "Where a project keeps your own crew files, out of git (.agent-shell/ is
ignored): relative to its main checkout. They replace the project's and
the starters of the same name."
  :type 'string
  :group 'agent-workspace)

;; ITS STATES
;; waking up, at the desk (waiting for you), working (its turn's time counted
;; from its start), hand raised (a permission, a question: agent-shell's, or
;; one waiting on its Agent UI canvas), done (until you look: its session
;; shown), napping (it loops and nothing is ready for it: see LOOPS), stuck
;; (an error), asleep, gone home. They follow its session's events, never
;; polled.

;; LOOPS
;; (config/agent-workspace/loops.el) On for a new agent whose role has labels
;; (the issues it's for; a project whose issues Beads tracks), off for the
;; others (a scribe); L turns one's on or off (↻ on its bar; kept in
;; crew.json). Once free (its turn ended, the issue it
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
;; crew started again brings a looping agent back awake: it takes the next
;; ready issue (one you put to sleep stays asleep).
(defcustom agent-workspace-loop t
  "Non-nil: loops run without you: a new agent whose role has labels loops
from the start (said in the room), and a crew started again brings its
looping agents back awake, taking ready issues. nil: a new agent doesn't
loop (L turns its loop on), and a crew started again brings its looping
agents back asleep: reopening never starts work by itself, waking one
does."
  :type 'boolean
  :group 'agent-workspace)

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
;; b in the app: the branches waiting to be merged, in the stage's place
;; (config/agent-workspace/branches.el; the issues, minimap and room stay):
;; each crew agent's with commits the main branch hasn't (in the stage's
;; order, the one it's on first), then those kept from forgotten agents
;; (noted as theirs; dimmed). A row: its agent, the branch (cut with … to
;; fit), its commits ahead of the main branch and behind it, whether it
;; merges cleanly or with conflicts (git merge-tree: no checkout touched;
;; nothing said with a git older than 2.38), its agent's state. RET its
;; commits, d its changes (both where you came from, as d on a bar), M merges
;; it (asking nothing; a forgotten agent's the same way, deleted once merged,
;; nobody told), D deletes it (asked, its commits shown; never one checked
;; out), gr again, q the stage back as it was. Worked out as it opens, on gr,
;; after RET, d, M or D, and at an agent's turn's end while it's shown; never
;; on a timer.

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
;; started again, stuck), raised hands, your messages (the compose line's,
;; and those typed in an agent's session or answered on its canvas: you →
;; ada; what the app sends an agent isn't yours); F filters it. Its compose
;; line: #ada to ada, #builders to the first free builder, #all to everyone,
;; no # to the selected agent; busy, it gets it after its turn; # at its start
;; offers the agents, roles and all as it's typed (with Corfu; TAB completes
;; it), M-p / M-n your messages; a line of text
;; (`agent-workspace-compose-lines'), growing into the feed as its text needs,
;; up to 5 (`agent-workspace-compose-max-lines') or half the room. # in the app
;; talks to the agent there. Kept per project, per machine, in
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
;; instructions; the turn it starts runs in its own mode (or
;; `agent-workspace-event-mode''s: plan, it reads and investigates, editing
;; asks you, its own mode back after). In the room:
;; queued ([Send now] [Drop]), delivered, dropped; ✉N on its agent's bar; P
;; pauses them all. Limits: 20 an hour from a source, 100 a day for an agent.
;; E lists them in the room's place: RET sends one now, d drops it, M-up /
;; M-down move it, o turns its source off for its agent or everyone (kept in
;; crew.json), q back. None delivered in `agent-workspace-inbox-quiet-hours'.
;; Only with `agent-workspace-outside-events' (E and P: while messages use
;; it too).

;; AGENTS ASKING EACH OTHER
;; A direct message for a question (config/agent-workspace/messages.el), from
;; an agent's shell: cmd/agent-workspace send --to ken TEXT. T in the app: may
;; they, off / ask me (each waits in the room for [Send] [Edit] [Drop]) / on,
;; kept in crew.json; on for a new crew (`agent-workspace-talk'); a role's
;; talks-to: names the roles it may message without your OK while it asks.
;; Through the inbox: delivered when free, framed as from the sender
;; (data, not your instructions); the reply goes back to the sender, as an
;; answer. In the room, each exchange a thread: TAB folds it, x stops it (or
;; lets it go again), [Answer] answers for the agent it's for. A thread waits
;; for your OK after 5 messages without you; an agent sends at most 10 an
;; hour. Each agent is told its crew and how to message (what it may without
;; your OK, never waiting on another agent). Only with
;; `agent-workspace-agents-talk'.

;; THE CREW FROM THE SHELL
;; (config/agent-workspace/request.el) cmd/agent-workspace status: the crew
;; as JSON, each agent's state in its bar's words, loop, issue, branch,
;; changed files, raised hand and events waiting, then the files two agents
;; changed, the room's offers still standing and the talk setting. give
;; ISSUE --to NAME, wake NAME, sleep NAME and loop NAME on|off do what t, Z
;; and L do, said in the room by who did them ("shell gave doom-a1b to
;; grace"). From an agent's shell (AGENT_WORKSPACE_AGENT) those four are
;; refused unless its role leads (leads: true in its file: the starter
;; lead, which answers about the crew and runs it on your word, never
;; starting work by itself, its context saying so: session.el); status
;; answers anyone.

;; WORK HANDED ON THROUGH ISSUES
;; (config/agent-workspace/handover.el) A role's hands-to: names where its
;; finished issues go (investigator -> builder -> reviewer, a reviewer's
;; changes back to the builder): roles in order, the first the crew has an
;; agent of; any: every role with labels, the agent picking; returns-to:
;; where work goes back. Every agent is told the project's roles and their
;; labels. Each agent is told how: the label changed to
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
;; there, asleep ones asleep, looping ones awake taking ready issues (asleep
;; with `agent-workspace-loop' nil), the others waiting for you; one that
;; can't start stuck, saying why; a panel whose file is gone skipped, said; a
;; wrong agent left out, said by its place and name; a file that isn't JSON or
;; isn't a crew said, nothing started. gR reads it again (after an edit),
;; asking before it starts or forgets one, or turns a loop on.

;; THE APP
;; SPC o w, from inside a project (outside one, asked which): its crew's own
;; workspace, "crew · PROJECT" (config/agent-workspace/app.el); SPC o W: in
;; the window you're in. A project that can't have a crew (not a git
;; repository, no commit yet) says why and offers a terminal with git init
;; typed. The first time, the stage is empty: c makes an agent, or a crew
;; (see CREWS). Two columns (the room comes on the right, doom-51z.6):
;; - the issues (config/agent-workspace/issues.el), on the left: in progress
;;   (each with its agent), ready by the role they're for then by epic (its
;;   heading, its issues under it, those of none last), blocked, done today,
;;   each its type before its id (the Beads panel's icon, config/beads/look.el;
;;   its first letter in a terminal); moving onto one in progress selects its
;;   agent;
;; - the stage (config/agent-workspace/stage.el): every agent a pane, in role
;;   order; the selected one's open (its session; below it its Agent UI, as in
;;   any session's pane (agent-ui-pane.el): its canvases (its own,
;;   ask...) and panels laid out to use the room; v into them (again: the
;;   next), V Agent UI taking the whole pane; a question there takes no focus,
;;   its hand says it), the others folded to a bar (◫2: its panels). Its line (a
;;   bar, the open pane's header line) shows first on its right its context
;;   used, 20% (agent-shell's colours: yellow from 60%, red from 85%; its
;;   tokens and cost on hover), drawn again as agent-shell reports it. It
;;   arranges itself: tiling leaves its frame alone (config/tiling.el).
;; q leaves it (the crew goes on: see THE CREW UNDER TREEMACS below); Q,
;; SPC TAB d, or quitting Emacs close it at once: every agent exits, no
;; question asked.
;;
;; THE CREW UNDER TREEMACS (config/agent-workspace/sidebar.el)
;; Once you've left the app, while treemacs shows the crew's project (in any
;; frame but the crew's), its lanes are under treemacs: a line an agent (its
;; avatar and role's icon, its last minutes that fit, its state), CREW ·
;; PROJECT and the tally over them; RET or a click on a lane: the app, that
;; agent selected. treemacs hidden, or on another project: the mode line
;; shows the crew's hands raised, done and stuck (` !1 ✓1 `; nothing for
;; working agents), a click opening the app. `agent-workspace-sidebar' nil:
;; never under treemacs; `agent-workspace-minimap-lines' its most lanes, as
;; the minimap's; `agent-workspace-mode-line-tally': needs-you, all (working
;; too) or nil.
;;
;; Keys, in evil's normal state:
;;   the issues   j / k the next / previous issue, RET (l, o) its agent's pane
;;                or the issue (on an epic's heading, the epic), t give it to
;;                an agent, c a new agent (for it), gr read them again
;;   the bars     j / k the next / previous agent (the cursor in its pane),
;;                RET its pane, TAB open or fold
;;   both         c a new agent, i interrupt, K kill (gone home), X forget
;;                (out of the crew, asked first), r restart
;;                fresh, Z sleep or wake, e edit (name, colour, role, mode,
;;                model), d its branch's changes, M merge its branch, b the
;;                branches to merge (see ITS BRANCHES), v its
;;                Agent UI (the cursor there; again: the next view), V
;;                Agent UI full size (again: back), I its issue, L its
;;                loop on or off, a the next raised hand, A answer it, f + a
;;                letter the agent whose name starts with it, gr lay the app
;;                out again, gR read crew.json again, q leave, Q close, ? the
;;                keys of where you are (its own first), then the app's
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
(load! "agent-workspace/crews")
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
(load! "agent-workspace/branches")
(load! "agent-workspace/messages")
(load! "agent-workspace/handover")
(load! "agent-workspace/panels")
(load! "agent-workspace/activity")
(load! "agent-workspace/minimap")
(load! "agent-workspace/sidebar")
(load! "agent-workspace/loops")
(load! "agent-workspace/saved")
(load! "agent-workspace/doom")

;; The app's keys, in its buffers (see THE APP above). Set here, at top level:
;; a reload sets them again. A view's own keys are bound after them: they
;; win where both have a key (gr refreshes the issues, d in the minimap).
(defvar +my/agent-workspace-keys
  '(("c" . agent-workspace-new-here) ("i" . agent-workspace-interrupt-here)
    ("K" . agent-workspace-kill-here) ("X" . agent-workspace-forget-here)
    ("r" . agent-workspace-restart-here)
    ("Z" . agent-workspace-sleep-here) ("e" . agent-workspace-edit)
    ("d" . agent-workspace-review-here) ("M" . agent-workspace-merge-here)
    ("v" . agent-workspace-panels-here) ("V" . agent-workspace-full-here) ("I" . agent-workspace-issue-here)
    ("L" . agent-workspace-loop-here)
    ("a" . agent-workspace-next-hand) ("A" . agent-workspace-answer) ("f" . agent-workspace-jump)
    ("gr" . agent-workspace-layout) ("gR" . agent-workspace-crew-reload) ("q" . agent-workspace-leave)
    ("Q" . agent-workspace-quit) ("?" . agent-workspace-help)
    ("#" . agent-workspace-talk) ("1" . agent-workspace-view-stage) ("2" . agent-workspace-view-room)
    ("m" . agent-workspace-minimap-toggle) ("P" . agent-workspace-inbox-pause)
    ("T" . agent-workspace-talk-cycle) ("E" . agent-workspace-inbox-view)
    ("b" . agent-workspace-branches))
  "The keys every buffer of the app has (see THE APP above).")

;; ? tells them from a view's own (config/agent-workspace/app.el's THE KEYS).
(setq agent-workspace-app-commands (mapcar #'cdr +my/agent-workspace-keys))

(+my/agent-workspace-bind agent-workspace-issues-mode-map
                          (append +my/agent-workspace-keys
                                  '(("j" . agent-workspace-issue-next) ("k" . agent-workspace-issue-previous)
                                   ("<down>" . agent-workspace-issue-next) ("<up>" . agent-workspace-issue-previous)
                                   ("RET" . agent-workspace-issue-open) ("<return>" . agent-workspace-issue-open)
                                   ("l" . agent-workspace-issue-open) ("o" . agent-workspace-issue-open)
                                   ("t" . agent-workspace-issue-give) ("gr" . agent-workspace-issues-refresh))))

;; The minimap, under the issues (config/agent-workspace/minimap.el): a lane
;; each agent (its avatar and role's icon, its name and role on hover), what
;; it did minute by minute (a quiet one's all ·), a cell a column on the
;; screen (a glyph the font draws wider: its fallback, ± for ✎), every lane's
;; │ at the same column, a line too long cut with …; RET its agent, o the
;; file it's in, d its changes (on a ⚠: both agents'). m shows or hides it,
;; anywhere.
(+my/agent-workspace-bind agent-workspace-minimap-mode-map
                          (append +my/agent-workspace-keys
                                  '(("j" . agent-workspace-minimap-next) ("k" . agent-workspace-minimap-previous)
                                   ("<down>" . agent-workspace-minimap-next) ("<up>" . agent-workspace-minimap-previous)
                                   ("RET" . agent-workspace-minimap-select) ("<return>" . agent-workspace-minimap-select)
                                   ("o" . agent-workspace-minimap-open) ("d" . agent-workspace-minimap-diff))))

(+my/agent-workspace-bind agent-workspace-bar-mode-map
                          (append +my/agent-workspace-keys
                                  '(("j" . agent-workspace-next) ("k" . agent-workspace-previous)
                                   ("<down>" . agent-workspace-next) ("<up>" . agent-workspace-previous)
                                   ("RET" . agent-workspace-go) ("<return>" . agent-workspace-go)
                                   ("TAB" . agent-workspace-toggle) ("<tab>" . agent-workspace-toggle))))

;; The stage's hint (no agents yet: c makes one; every pane folded): the app's
;; keys, not evil's change, macro recorded and last macro run. j/k: nowhere to
;; go, nothing said (no "Beginning of buffer").
(+my/agent-workspace-bind agent-workspace-hint-mode-map
                          (append +my/agent-workspace-keys
                                  '(("j" . ignore) ("k" . ignore) ("<down>" . ignore) ("<up>" . ignore))))

;; An agent's canvas or panel, in its pane on the stage: v and V there too, in
;; place of evil's visual state.
(+my/agent-workspace-bind agent-workspace-side-mode-map
                          '(("v" . agent-workspace-panels-here) ("V" . agent-workspace-full-here)))

;; The crew under treemacs: RET on a lane, the app with its agent selected.
(+my/agent-workspace-bind agent-workspace-sidebar-mode-map
                          '(("RET" . agent-workspace-sidebar-open) ("<return>" . agent-workspace-sidebar-open)))

;; The inbox's view (E).
(+my/agent-workspace-bind agent-workspace-inbox-mode-map
                          '(("RET" . agent-workspace-inbox-view-send-now) ("<return>" . agent-workspace-inbox-view-send-now)
                            ("d" . agent-workspace-inbox-view-drop) ("o" . agent-workspace-inbox-view-source-off)
                            ("M-<up>" . agent-workspace-inbox-view-up) ("M-<down>" . agent-workspace-inbox-view-down)
                            ("M-k" . agent-workspace-inbox-view-up) ("M-j" . agent-workspace-inbox-view-down)
                            ("q" . agent-workspace-inbox-view-quit) ("Q" . agent-workspace-quit)
                            ("?" . agent-workspace-help)))

;; The branches to merge (b), in the stage's place: the app's keys, and these
;; on the branch at point (see ITS BRANCHES above).
(+my/agent-workspace-bind agent-workspace-branches-mode-map
                          (append +my/agent-workspace-keys
                                  '(("j" . agent-workspace-branches-next) ("k" . agent-workspace-branches-previous)
                                    ("<down>" . agent-workspace-branches-next) ("<up>" . agent-workspace-branches-previous)
                                    ("RET" . agent-workspace-branches-commits) ("<return>" . agent-workspace-branches-commits)
                                    ("d" . agent-workspace-branches-review) ("M" . agent-workspace-branches-merge)
                                    ("D" . agent-workspace-branches-delete) ("gr" . agent-workspace-branches-refresh)
                                    ("q" . agent-workspace-branches-quit))))

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
      :n "q" #'agent-workspace-leave
      ;; As in the app's other buffers, not evil's last macro run.
      :n "Q" #'agent-workspace-quit)

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

(setq agent-workspace-session-keymap +my/agent-workspace-pane-map)

(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c w" +my/agent-workspace-pane-map
      :localleader
      :desc "Agent crew" "w" +my/agent-workspace-pane-map)


;; WHAT AN AGENT IS TOLD (see ITS SESSION above), after what every session is.
(add-hook '+my/agent-shell-context-functions #'agent-workspace-agent-context t)

;; AN AGENT'S PANELS (config/agent-workspace/panels.el): a project dashboard an
;; agent opens runs in its worktree, "tests · ada", never popped up (its pane
;; on the stage shows it), trusted as its project, closed with the agent;
;; saved with the crew by name, opened again with it (see THE SAVED CREW).
(setq agent-ui-dashboard-name-function #'agent-workspace--panel-name
      agent-ui-trust-root-function #'agent-workspace--panel-trust-root
      agent-ui-dashboard-display-function #'agent-workspace--panel-display)

;; NO CREW HERE (see THE APP above): a terminal offered, git init typed in it.
(setq agent-workspace-no-crew-function #'+my/agent-workspace-git-init)

;; AN ISSUE SHOWN (I, RET on one nobody's on): Beads' issue view
;; (config/agent-ui.el's, config/beads.el).
(setq agent-workspace-open-issue-function #'+my/agent-ui-open-issue)

;; ITS AVATAR on its worktree's tabs (see above).
(add-hook '+my/tabs-prefix-functions #'agent-workspace-tab-prefix)

;; A QUESTION WAITING on an agent's canvas (agent-ui-agent.el): its hand
;; raised.
(add-hook 'agent-ui-question-waiting-functions #'agent-workspace--question-waiting)
