;;; $DOOMDIR/config/agent-workflow.el -*- lexical-binding: t; -*-
;; Agent workflows: the work on an issue described as GitHub Actions does,
;; jobs and their steps, some steps an LLM in agent-shell (docs/agent-workflow.md).
;; Loaded from config.el; its code is in config/agent-workflow/. Being built
;; (epic doom-38o): for now its files, read and checked.

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
(load! "agent-workflow/check")
(load! "agent-workflow/request")
