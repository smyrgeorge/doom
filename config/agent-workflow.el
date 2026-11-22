;;; $DOOMDIR/config/agent-workflow.el -*- lexical-binding: t; -*-
;; Agent workflows: the work on an issue described as GitHub Actions does,
;; jobs and their steps, some steps an LLM in agent-shell (docs/agent-workflow.md).
;; Loaded from config.el; its code is in config/agent-workflow/. Being built
;; (epic doom-38o): for now its files, read and checked, and its pool of
;; agents.

;; ====== VARIABLES ======

(defgroup agent-workflow nil
  "Agent workflows: the work on an issue in jobs and steps, some an LLM."
  :group 'tools)

;; WHERE THEY ARE
;; A project's workflows (.yml) and profiles (.md) come from three places, a
;; later one's replacing an earlier one's of the same name: the starters
;; (config/agent-workflow/workflows/ and profiles/), the project's (committed,
;; read from your checkout, never an agent's worktree) and yours (out of
;; git). Each in its folder's workflows/ and profiles/.
(defcustom agent-workflow-directory ".agent-workflow"
  "Where a project keeps its workflows and profiles, committed: its
workflows/ and profiles/, relative to its main checkout."
  :type 'string
  :group 'agent-workflow)

(defcustom agent-workflow-local-directory ".agent-shell/agent-workflow"
  "Where a project keeps your own workflows and profiles, out of git
\(.agent-shell/ is ignored): its workflows/ and profiles/, relative to its
main checkout. They replace the project's and the starters of the same
name."
  :type 'string
  :group 'agent-workflow)

;; THE POOL
;; Agent sessions, as many at once as this says, in every project: an agent
;; has no role and no name, it's a job's (config/agent-workflow/pool.el),
;; known by its issue and job ("doom-a1b · review"), started with its step's
;; profile in the issue's worktree (config/agent-workflow/worktree.el).
(defcustom agent-workflow-pool 3
  "How many agent sessions of the pool run at once, in every project."
  :type 'natnum
  :group 'agent-workflow)

;; ITS PERMISSION MODE
;; Claude Code's (`agent-workflow-modes'): the step's profile's (mode:), else
;; this: auto, Claude deciding what needs your OK.
(defcustom agent-workflow-mode "auto"
  "The permission mode an agent starts in (Claude Code's id) when its
profile has none. auto: Claude decides what needs your OK. nil: Claude
Code's own default."
  :type '(choice (const :tag "Claude Code's" nil) string)
  :group 'agent-workflow)

(defcustom agent-workflow-kinds
  '((claude-code :config agent-shell-anthropic-make-claude-code-config :claude-code t))
  "The agents the pool can run: a kind (a symbol) and how its session
starts. :config, a function returning agent-shell's config for it;
:claude-code, non-nil if it's Claude Code (a profile's tools go to its
options)."
  :type '(alist :key-type symbol :value-type plist)
  :group 'agent-workflow)

(defcustom agent-workflow-kind 'claude-code
  "The kind of agent the pool runs: a key of `agent-workflow-kinds'."
  :type 'symbol
  :group 'agent-workflow)

(defcustom agent-workflow-exit-timeout 7
  "Seconds a stopped session's processes have to exit, before any left is
killed."
  :type 'number
  :group 'agent-workflow)

;; RUNS
;; You start them (M-x agent-workflow-run, cmd/agent-workflow run): their
;; jobs in order, Emacs the engine (config/agent-workflow/runs.el). A run
;; whose issue is blocked is queued, looked at again this often.
(defcustom agent-workflow-queue-check 30
  "Seconds between looks at runs waiting for something outside Emacs (their
issue's blockers closing)."
  :type 'number
  :group 'agent-workflow)

;; RUNS COMING BACK
;; Emacs starting, the runs not over of the projects that had some (noted
;; here) are read back, a job that was running interrupted, waiting for
;; continue (config/agent-workflow/resume.el); continued by themselves if
;; this says so.
(defcustom agent-workflow-projects-file
  (expand-file-name "agent-workflow-projects.eld"
                    (if (boundp 'doom-data-dir) doom-data-dir user-emacs-directory))
  "Where the projects that had runs are noted: their runs are read back as
Emacs starts."
  :type 'file
  :group 'agent-workflow)

(defcustom agent-workflow-continue-on-start nil
  "Non-nil: runs read back as Emacs starts are continued by themselves.
nil: they wait for M-x agent-workflow-continue."
  :type 'boolean
  :group 'agent-workflow)

;; SCRIPTS
;; A run: step's script, its suite's for a merge (config/agent-workflow/
;; steps.el): stopped once it's run this long, unless its step's timeout says.
(defcustom agent-workflow-script-timeout 1800
  "Seconds a step's script may run, unless its step's timeout: says."
  :type 'number
  :group 'agent-workflow)

;; LOOPS
;; An agent's outcome sending the work back (changes: rerun build) is
;; counted: past this many rounds (a job's or workflow's max-rounds says
;; otherwise), or 3 times that in all, the run asks you
;; (config/agent-workflow/runs.el, LOOPS).
(defcustom agent-workflow-max-rounds 10
  "How many times a job may send the work back before the run asks you."
  :type 'natnum
  :group 'agent-workflow)

;; CHECKING THEM
;; M-x agent-workflow-check (config/agent-workflow/check.el) reads them all
;; anew and lists every problem, each line taking you to its file and line;
;; cmd/agent-workflow check [FILE] does the same from the shell, as JSON
;; (config/agent-workflow/request.el). A file with an error is left out; a
;; warning leaves it in. What's checked: the tops of profiles.el and
;; workflows.el.

;; ====== ITS PARTS ======

(load! "agent-workflow/core")
(load! "agent-workflow/profiles")
(load! "agent-workflow/workflows")
(load! "agent-workflow/worktree")
(load! "agent-workflow/pool")
(load! "agent-workflow/beads")
(load! "agent-workflow/runs")
(load! "agent-workflow/steps")
(load! "agent-workflow/resume")
(load! "agent-workflow/check")
(load! "agent-workflow/request")

;; ====== HOOKS ======

;; WHAT AN AGENT IS TOLD
;; In its system prompt, after what every Claude Code session is: the job it
;; does, where, how it ends a step, then its profile's instructions
;; (config/agent-workflow/pool.el).
(add-hook '+my/agent-shell-claude-context-functions #'agent-workflow-agent-context t)

;; Its canvas opens no pane of its own: kept, for its ticket's pane.
(agent-workflow--take-canvases)

;; Emacs quits: the pool's sessions end with it, asking nothing.
(add-hook 'kill-emacs-hook #'agent-workflow--quit-h)

;; Emacs starting: the runs not over read back (and continued, if
;; `agent-workflow-continue-on-start').
(add-hook 'emacs-startup-hook #'agent-workflow-restore-all)
