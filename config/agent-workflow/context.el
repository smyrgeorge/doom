;;; $DOOMDIR/config/agent-workflow/context.el -*- lexical-binding: t; -*-
;; What an agent of agent workflow's pool is told, and its permissions.
;; Loaded from config/agent-workflow.el.

;; WHAT THE AGENT IS TOLD: through this config's (config/agent-shell/
;; context.el), which tells every session about Emacs itself (also the
;; agents that take no system prompt): an agent of the pool, its job; every
;; session, where the skill is.
(defun +my/agent-workflow-agent-context ()
  "What an agent of the pool starting is told (`agent-workflow-agent-context');
nil for any other session, the pool not loaded (none of its agents then)."
  (and (featurep 'agent-workflow-pool) (agent-workflow-agent-context)))

;; ITS PERMISSIONS: an agent other than Claude Code (which takes its rules as
;; options) has its permission requests answered by its agent's rules, in
;; Claude Code's syntax, as an agent workspace's role's are
;; (config/agent-shell/permissions.el).
(defun +my/agent-workflow-session-rules (rules)
  "RULES, an agent of the pool's, its session's (`+my/agent-shell-permission-rules')."
  (setq-local +my/agent-shell-permission-rules rules))
