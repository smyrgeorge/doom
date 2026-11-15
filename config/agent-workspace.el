;;; $DOOMDIR/config/agent-workspace.el -*- lexical-binding: t; -*-
;; The agent workspace: a crew of coding agents on one project, each with a
;; name, a role, a colour and a state, run from one app in Emacs
;; (docs/agent-workspace.md). Loaded from config.el; its code is in
;; config/agent-workspace/.

;; ====== VARIABLES ======

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
;; (an issue's id: its first message, "Work on doom-a1b: TITLE"); from the
;; shell, cmd/agent-workspace new --role builder [--name ada] [--prompt TEXT]
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
;; shown), stuck (an error), asleep, gone home. They follow its session's
;; events, never polled.

;; ITS WORKTREE
;; Always its own (config/agent-workspace/worktree.el): .agent-shell/worktrees/NAME
;; of its project, on the branch agent/NAME (from the main checkout's HEAD),
;; made with it, locked with its name as the reason ("agent ada (builder),
;; crew of doom"), kept when it stops, moved when it's renamed. A project
;; that isn't a git repository, or has no commit, has no crew. .agent-shell/
;; is kept out of git (the repository's info/exclude, if no .gitignore does
;; it). Forgetting an agent removes its worktree and branch when they hold
;; nothing the main checkout hasn't; else you're shown what they hold and
;; asked. M-x agent-workspace-review: its branch's changes in magit
;; (MAIN...agent/NAME); M-x agent-workspace-merge: merged into the main
;; checkout, the agent told, its branch reset to it if you say so.

;; ITS NAME ON IT, IN EMACS
;; (config/agent-workspace/names.el) Its worktree's files belong to the
;; project "PROJECT · NAME"; their mode line shows the agent ("▌A ada ·
;; builder", in its colour; a click selects it) and their tab starts with its
;; avatar. A worktree a forgotten agent left shows its name dimmed.

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

;; THE SAVED CREW
;; What the crew is, not its state, saved in the project and committed:
;; .agent-workspace/crew.el (config/agent-workspace/saved.el), read as data,
;; never evaluated. Each agent's name, role, colour (its model and mode when
;; not its role's), whether it's asleep; the layout. Written when the crew
;; changes. SPC o w with no crew running starts it again from there: every
;; agent fresh, in its worktree, its role as it is now, asleep ones asleep,
;; each waiting for you; one that can't start stuck, saying why. gR reads it
;; again (after an edit, a pull), asking before it starts or forgets one.

;; THE APP
;; SPC o w, from inside a project (outside one, asked which): its crew's own
;; workspace, "crew · PROJECT" (config/agent-workspace/app.el); SPC o W: in
;; the window you're in. A project that can't have a crew (not a git
;; repository, no commit yet) says why and offers a terminal with git init
;; typed. The first time, its first agent is asked for. Two columns (the room
;; comes on the right, doom-51z.6):
;; - the issues (config/agent-workspace/issues.el), on the left: in progress
;;   (each with its agent), ready by the role they're for, blocked, done today;
;;   moving onto one in progress selects its agent;
;; - the stage (config/agent-workspace/stage.el): every agent a pane, in role
;;   order; the selected one's open (its session, its canvas below it), the
;;   others folded to a bar. It arranges itself: tiling leaves its frame
;;   alone (config/tiling.el).
;; q leaves it (the crew goes on, its tally in the other workspaces' mode
;; line: a click comes back); Q, SPC TAB d, or quitting Emacs close it at
;; once: every agent exits, no question asked.
;;
;; Keys, in evil's normal state:
;;   the issues   j / k the next / previous issue, RET (l, o) its agent's pane
;;                or the issue, t give it to an agent, c a new agent (for it)
;;   the bars     j / k the next / previous agent (the cursor in its pane),
;;                RET its pane, TAB open or fold
;;   both         c a new agent, i interrupt, K kill (gone home), r restart
;;                fresh, s sleep or wake, e edit (name, colour, role, mode,
;;                model), d its branch's changes, M merge its branch, v its
;;                canvas, I its issue, a the next raised hand, f + an initial
;;                that agent, gr lay out again, gR read crew.el again, q leave,
;;                Q close, ? the keys
;;   its session  the same after SPC m w (C-c w in insert state), and ] / [
;;                the next / previous agent; a click on its header line or a
;;                bar selects it, mouse-3 its actions

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
(load! "agent-workspace/saved")
(load! "agent-workspace/doom")

;; The app's keys, in its buffers (see THE APP above). Set here, at top level:
;; a reload sets them again.
(defvar +my/agent-workspace-keys
  '(("c" . agent-workspace-new-here) ("i" . agent-workspace-interrupt-here)
    ("K" . agent-workspace-kill-here) ("r" . agent-workspace-restart-here)
    ("s" . agent-workspace-sleep-here) ("e" . agent-workspace-edit)
    ("d" . agent-workspace-review-here) ("M" . agent-workspace-merge-here)
    ("v" . agent-workspace-canvas-here) ("I" . agent-workspace-issue-here)
    ("a" . agent-workspace-next-hand) ("f" . agent-workspace-jump)
    ("gr" . agent-workspace-layout) ("gR" . agent-workspace-crew-reload) ("q" . agent-workspace-leave)
    ("Q" . agent-workspace-quit) ("?" . agent-workspace-help))
  "The keys every buffer of the app has (see THE APP above).")

(+my/agent-workspace-bind agent-workspace-issues-mode-map
                          (append '(("j" . agent-workspace-issue-next) ("k" . agent-workspace-issue-previous)
                                    ("<down>" . agent-workspace-issue-next) ("<up>" . agent-workspace-issue-previous)
                                    ("RET" . agent-workspace-issue-open) ("<return>" . agent-workspace-issue-open)
                                    ("l" . agent-workspace-issue-open) ("o" . agent-workspace-issue-open)
                                    ("t" . agent-workspace-issue-give) ("gr" . agent-workspace-issues-refresh))
                                  +my/agent-workspace-keys))

(+my/agent-workspace-bind agent-workspace-bar-mode-map
                          (append '(("j" . agent-workspace-next) ("k" . agent-workspace-previous)
                                    ("<down>" . agent-workspace-next) ("<up>" . agent-workspace-previous)
                                    ("RET" . agent-workspace-go) ("<return>" . agent-workspace-go)
                                    ("TAB" . agent-workspace-toggle) ("<tab>" . agent-workspace-toggle))
                                  +my/agent-workspace-keys))

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
