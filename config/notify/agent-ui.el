;;; $DOOMDIR/config/notify/agent-ui.el -*- lexical-binding: t; -*-
;; Notifications of Agent UI (config/agent-ui.el): a bug filed in its own
;; issues, by the agent or you. Loaded from config/notify.el.

;; THE KIND (see config/notify.el)
(+my/notify-define 'agent-ui-bug "Agent UI" "A bug filed in Agent UI's own issues")

(defun +my/notify-agent-ui--bug-filed (id title new _dir)
  "A bug filed (`agent-ui-bug-filed-functions'): ID, TITLE, NEW or added to
a similar open one."
  (+my/notify 'agent-ui-bug (format "%s %s: %s" (if new "Filed" "Added to") id title)))

(add-hook 'agent-ui-bug-filed-functions #'+my/notify-agent-ui--bug-filed)
