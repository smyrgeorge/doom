;;; $DOOMDIR/config/agent-workflow/crew.el -*- lexical-binding: t; -*-
;; The agent workspace's crew and agent workflow's pool: a project whose crew
;; runs has no agents of the pool, its loops would take the same issues.
;; Read from its lock and agents, never requiring it. Loaded from
;; config/agent-workflow.el.

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
