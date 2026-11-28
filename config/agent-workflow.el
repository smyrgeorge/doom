;;; $DOOMDIR/config/agent-workflow.el -*- lexical-binding: t; -*-
;; Agent workflows: the work on an issue described as GitHub Actions does,
;; jobs and their steps, some steps an LLM in agent-shell. Loaded from
;; config.el. Its own package now (~/dev/agent-workflow, packages.el; its
;; docs: docs/ there); here, this config's layer over it: where its files
;; go, what a session is told, its permissions, its picker's look, the
;; agent workspace's crew, its keys (docs/agent-workflow.md).

(require 'agent-workflow)

;; Only agent-workflow.el is loaded with Emacs: its parts the first time
;; it's used (a command, cmd/agent-workflow, runs coming back once Emacs is
;; idle).

;; ====== VARIABLES ======

;; RUNS COMING BACK: the projects that had runs, noted in Doom's data
;; folder, read back once Emacs has started (`agent-workflow-mode'). Trust
;; is Agent UI's (config/agent-ui.el: `agent-ui-trust-file').
(setq agent-workflow-projects-file (expand-file-name "agent-workflow-projects.eld" doom-data-dir))

;; WHAT THE AGENT IS TOLD
;; This config tells every session about Emacs itself (config/agent-shell/
;; context.el: also the agents that take no system prompt): agent workflows'
;; lines among it, not the package's own (`agent-workflow-system-prompt'),
;; which would say them twice. An agent of the pool: its job; every
;; session: where the skill is.
(setq agent-workflow-system-prompt nil)

(defun +my/agent-workflow-agent-context ()
  "What an agent of the pool starting is told (`agent-workflow-agent-context');
nil for any other session, the pool not loaded (none of its agents then)."
  (and (featurep 'agent-workflow-pool) (agent-workflow-agent-context)))

(add-hook '+my/agent-shell-context-functions #'+my/agent-workflow-agent-context t)
(add-hook '+my/agent-shell-context-functions #'agent-workflow-skill-context t)

;; ITS PERMISSIONS: an agent other than Claude Code (which takes its rules as
;; options) has its permission requests answered by its agent's rules, in
;; Claude Code's syntax, as an agent workspace's role's are
;; (config/agent-shell/permissions.el).
(defun +my/agent-workflow-session-rules (rules)
  "RULES, an agent of the pool's, its session's (`+my/agent-shell-permission-rules')."
  (setq-local +my/agent-shell-permission-rules rules))

(setq agent-workflow-session-rules-function #'+my/agent-workflow-session-rules)

;; THE ISSUE PICKER (M-x agent-workflow-run-ticket): each issue as the issue
;; list draws it (config/beads/look.el, once it's loaded): a status icon, a
;; priority badge and a type icon before it, its labels as tags after.
(defvar +my/beads--statuses)

(defun +my/agent-workflow-issue-affixes (info statuses)
  "INFO's (PREFIX . SUFFIX), an issue as the issue list draws it, STATUSES
the open issues' (those blocking it); the package's own look without the
list's (`agent-workflow-issue-affixes')."
  (if (not (fboundp '+my/beads-format-status))
      (agent-workflow-issue-affixes info statuses)
    ;; The statuses' faces: beads.el's, in the theme's colours once loaded
    ;; (config/beads/theme.el); the list may not have been opened yet.
    (let ((+my/beads--statuses statuses)
          (labels (alist-get 'labels info)))
      (require 'beads-faces nil t)
      (cons (concat (string-pad (+my/beads-format-status info) 2)
                    (+my/beads-format-priority info) " "
                    (+my/beads-format-type info) " ")
            (when labels
              (concat "  " (mapconcat #'+my/beads--label-tag labels " ")))))))

(setq agent-workflow-issue-affixes-function #'+my/agent-workflow-issue-affixes)

;; THE AGENT WORKSPACE: a project whose crew runs has no agents of the pool,
;; its loops would take the same issues. Read from its lock and agents,
;; never requiring it.
(declare-function agent-workspace-agents "agent-workspace/core")
(declare-function agent-workspace-agent-state "agent-workspace/core")

(defun +my/agent-workflow-crew-running (project)
  "Why the pool runs no agent in PROJECT: its agent-workspace crew runs (its
agents in this Emacs, or its lock held by an Emacs alive); nil if it doesn't.
One of `agent-workflow-project-busy-functions'."
  (when (or (and (fboundp 'agent-workspace-agents)
                 (seq-some (lambda (agent) (not (memq (agent-workspace-agent-state agent) '(asleep home))))
                           (ignore-errors (agent-workspace-agents project))))
            (when-let* ((file (expand-file-name ".agent-shell/agent-workspace/crew.lock" project))
                        ((file-readable-p file))
                        (pid (ignore-errors
                               (with-temp-buffer (insert-file-contents file)
                                                 (string-to-number (car (split-string (buffer-string)))))))
                        ((> pid 0))
                        (attributes (process-attributes pid)))
              (and (not (member (alist-get 'state attributes) '("Z" "X")))
                   (string-match-p "emacs" (downcase (or (alist-get 'comm attributes) ""))))))
    (format "The agent-workspace crew of %s runs: its agents would take the same issues"
            (file-name-nondirectory (directory-file-name project)))))

(add-hook 'agent-workflow-project-busy-functions #'+my/agent-workflow-crew-running)

;; ====== KEYS ======

;; THE RUNS' LIST (M-x agent-workflow-list): RET opens a run's pane; Vim's
;; keys, as Doom's other lists. Once its file is loaded (when first used).
(map! :after agent-workflow-list
      :map agent-workflow-list-mode-map
      :n "RET" #'agent-workflow-list-open
      :n "gr"  #'revert-buffer
      :n "q"   #'quit-window)

;; ====== ON ======

;; Runs not over come back once Emacs has started (and been idle a second);
;; the pool's sessions end with Emacs, asking nothing.
(agent-workflow-mode 1)
