;;; $DOOMDIR/config/agent-workflow.el -*- lexical-binding: t; -*-
;; Agent workflows: the work on an issue described as GitHub Actions does,
;; jobs and their steps, some steps an LLM in agent-shell. Loaded from
;; config.el. Its own package (~/dev/agent-workflow, packages.el; its docs:
;; docs/ there); here, this config's layer over it: Beads its issue tracker,
;; where its files go, what a session is told, its permissions, its picker's
;; look, the agent workspace's crew, its keys (docs/agent-workflow.md). Its
;; code in config/agent-workflow/.

(require 'agent-workflow)

;; Only agent-workflow.el is loaded with Emacs: its parts the first time
;; it's used (a command, cmd/agent-workflow, runs coming back once Emacs is
;; idle).

;; ====== VARIABLES ======

;; RUNS COMING BACK: the projects that had runs, noted in Doom's data
;; folder, read back once Emacs has started (`agent-workflow-mode'). Trust
;; is Agent UI's (config/agent-ui.el: `agent-ui-trust-file').
(setq agent-workflow-projects-file (expand-file-name "agent-workflow-projects.eld" doom-data-dir))

;; WHAT THE AGENT IS TOLD: this config's lines (config/agent-shell/
;; context.el), not the package's own system prompt, which would say them
;; twice (config/agent-workflow/context.el).
(setq agent-workflow-system-prompt nil)

;; Who the engine's writes are in Beads' history (BEADS_ACTOR); an agent of a
;; run writes as ISSUE/JOB (config/agent-workflow/beads.el).
(defvar +my/agent-workflow-bd-actor "agent-workflow"
  "Who the engine's writes are in the issues' history (BEADS_ACTOR).")

;; ====== KEYS ======

;; THE RUNS' LIST (M-x agent-workflow-list): RET opens a run's pane; Vim's
;; keys, as Doom's other lists. Once its file is loaded (when first used).
(map! :after agent-workflow-list
      :map agent-workflow-list-mode-map
      :n "RET" #'agent-workflow-list-open
      :n "gr"  #'revert-buffer
      :n "q"   #'quit-window)

;; ====== CODE ======

(load! "agent-workflow/beads")          ; Beads, its issue tracker; the picker's look
(load! "agent-workflow/context")        ; what an agent is told, its permissions
(load! "agent-workflow/crew")           ; no pool where a crew runs

;; ====== ON ======

;; ISSUES: Beads' (a project with .beads/); elsewhere a run is on a task you
;; type (M-x agent-workflow-run-task), or a workflow's own.
(add-to-list 'agent-workflow-trackers +my/agent-workflow-beads-tracker)
;; THE ISSUE PICKER (M-x agent-workflow-run-ticket): each issue as the issue
;; list draws it (config/beads/look.el).
(setq agent-workflow-issue-affixes-function #'+my/agent-workflow-issue-affixes)
;; What a session is told: an agent of the pool, its job; every session,
;; where the skill is.
(add-hook '+my/agent-shell-context-functions #'+my/agent-workflow-agent-context t)
(add-hook '+my/agent-shell-context-functions #'agent-workflow-skill-context t)
;; An agent other than Claude Code: its requests answered by its rules.
(setq agent-workflow-session-rules-function #'+my/agent-workflow-session-rules)
;; A project whose agent-workspace crew runs: no pool there.
(add-hook 'agent-workflow-project-busy-functions #'+my/agent-workflow-crew-running)

;; Runs not over come back once Emacs has started (and been idle a second);
;; the pool's sessions end with Emacs, asking nothing.
(agent-workflow-mode 1)
