;;; $DOOMDIR/config/agent-workspace.el -*- lexical-binding: t; -*-
;; The agent workspace: a crew of coding agents on one project, each with a
;; name, a role, a colour and a state, run from one app in Emacs
;; (docs/agent-workspace.md). Loaded from config.el; its code is in
;; config/agent-workspace/.

;; ====== VARIABLES ======

;; AGENTS
;; An agent of a project's crew (config/agent-workspace/core.el): a name
;; ("ada"), a role ("builder"), a colour (one of the theme's ANSI faces, a free
;; one by default: `agent-workspace-colours'), an agent kind (Claude Code:
;; `agent-workspace-kinds'), its session, its worktree, its state and the issue
;; you gave it. Made from Lisp for now:
;;   (agent-workspace-create :role "builder" :name "ada")
;; then interrupted, killed (gone home: the issue you gave it, still in
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
;; shown), stuck (an error), asleep, gone home. They follow its session's
;; events, never polled.

;; ITS WORKTREE
;; Always its own (config/agent-workspace/worktree.el): .agent-shell/worktrees/NAME
;; of its project, on the branch agent/NAME, made with it, kept when it stops,
;; moved when it's renamed. .agent-shell/ is kept out of git (the repository's
;; info/exclude, if no .gitignore does it).

;; ITS SESSION
;; agent-shell's (config/agent-workspace/session.el), in its worktree, its
;; buffer "ada · builder". Its role's model, permission mode, tools and MCP
;; servers; in its system prompt, after what every session is told, who it is
;; and how it works, then its role's instructions; in its environment its name
;; (BEADS_ACTOR, AGENT_WORKSPACE_AGENT) and the project's issues (BEADS_DIR).

;; CLOSING A CREW
;; `agent-workspace-close' (and quitting Emacs) stops every agent at once,
;; asking nothing, and leaves no process of theirs: what hasn't exited
;; `agent-workspace-exit-timeout' seconds later is killed. Their worktrees stay.

;; ====== CODE ======

;; In config/agent-workspace/, in this order: each part can use what the ones
;; before it define.
(load! "agent-workspace/core")
(load! "agent-workspace/worktree")
(load! "agent-workspace/session")
(load! "agent-workspace/roles")

;; WHAT AN AGENT IS TOLD (see ITS SESSION above), after what every session is.
(add-hook '+my/agent-shell-claude-context-functions #'agent-workspace-agent-context t)

;; A QUESTION WAITING on an agent's canvas (config/agent-ui/agent.el): its hand
;; raised.
(add-hook 'agent-ui-question-waiting-functions #'agent-workspace--question-waiting)
