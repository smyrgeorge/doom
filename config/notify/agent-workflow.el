;;; $DOOMDIR/config/notify/agent-workflow.el -*- lexical-binding: t; -*-
;; Notifications of agent workflows (config/agent-workflow.el): a run waits
;; for you (an approval, the loop guard, retries used up, its budget...),
;; however it was started. Loaded from config/notify.el.

;; THE KIND (see config/notify.el)
(+my/notify-define 'agent-workflow-needs-you "Agent workflow" "A workflow's run waits for you")

(defun +my/notify-agent-workflow--needs-you (run why)
  "RUN waits for you on WHY (`agent-workflow-needs-you-functions'): said, a
click opening its pane."
  (+my/notify 'agent-workflow-needs-you
              (format "%s: %s" (agent-workflow-run-name run) why)
              :action (lambda () (agent-workflow-pane run 'select))))

(add-hook 'agent-workflow-needs-you-functions #'+my/notify-agent-workflow--needs-you)
