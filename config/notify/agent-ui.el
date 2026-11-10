;;; $DOOMDIR/config/notify/agent-ui.el -*- lexical-binding: t; -*-
;; Notifications of Agent UI (config/agent-ui.el): a bug filed in its own
;; issues, by the agent or you; a question waiting for you on a canvas. Loaded
;; from config/notify.el.

;; THE KIND (see config/notify.el)
(+my/notify-define 'agent-ui-bug "Agent UI" "A bug filed in Agent UI's own issues")

(defun +my/notify-agent-ui--bug-filed (id title new _dir)
  "A bug filed (`agent-ui-bug-filed-functions'): ID, TITLE, NEW or added to
a similar open one."
  (+my/notify 'agent-ui-bug (format "%s %s: %s" (if new "Filed" "Added to") id title)))

(add-hook 'agent-ui-bug-filed-functions #'+my/notify-agent-ui--bug-filed)

;; A QUESTION WAITING: the agent's turn ended with a question on its canvas.
(+my/notify-define 'agent-ui-question "Agent UI" "A question waits for you on a canvas")

(defun +my/notify-agent-ui--question (session canvas id)
  "SESSION's turn ended with question ID waiting on CANVAS: said, a click
showing the canvas (`agent-ui-question-waiting-functions')."
  (let ((question (and (buffer-live-p canvas)
                       (agent-ui-ask-question (agent-ui-get id :canvas canvas)))))
    (+my/notify 'agent-ui-question
                (format "%s asks: %s" (if (buffer-live-p session) (buffer-name session) "Claude Code")
                        (or question "a question"))
                :buffer canvas)))

(add-hook 'agent-ui-question-waiting-functions #'+my/notify-agent-ui--question)

(defun +my/notify-agent-ui--question-said-p (session event)
  "Whether SESSION's turn's end, EVENT, has a new question waiting, said by
its own notification (on): the turn's not said too."
  (and (+my/notify-on-p 'agent-ui-question)
       (fboundp 'agent-ui-questions-new)
       (agent-ui-questions-new session event)
       t))

(add-hook '+my/notify-claude-turn-said-functions #'+my/notify-agent-ui--question-said-p)
