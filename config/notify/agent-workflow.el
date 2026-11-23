;;; $DOOMDIR/config/notify/agent-workflow.el -*- lexical-binding: t; -*-
;; Notifications of agent workflows (config/agent-workflow.el): a run waits
;; for you (an approval, the loop guard, retries used up, its budget, its
;; agent asking in its session...), or failed (a script's exit 3), however
;; it was started. Loaded from
;; config/notify.el.

;; THE KIND (see config/notify.el)
(+my/notify-define 'agent-workflow-needs-you "Agent workflow" "A workflow's run waits for you")

(defun +my/notify-agent-workflow--needs-you (run why)
  "RUN waits for you on WHY (`agent-workflow-needs-you-functions'): said, a
click opening its pane."
  (+my/notify 'agent-workflow-needs-you
              (format "%s: %s" (agent-workflow-run-name run) why)
              :action (lambda () (agent-workflow-pane run 'select))))

(add-hook 'agent-workflow-needs-you-functions #'+my/notify-agent-workflow--needs-you)

;; A run's agent asking in its session (a permission, a question), its turn
;; over, an error: its run says what needs you (above), Claude Code's kinds
;; don't say it again.
(defun +my/notify-agent-workflow--own-p (buffer)
  "Non-nil if BUFFER is a run's agent's session. In
`+my/notify-claude-own-functions'."
  (and (boundp 'agent-workflow--agent)
       (buffer-local-value 'agent-workflow--agent buffer)))

(add-hook '+my/notify-claude-own-functions #'+my/notify-agent-workflow--own-p)
