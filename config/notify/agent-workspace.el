;;; $DOOMDIR/config/notify/agent-workspace.el -*- lexical-binding: t; -*-
;; The agent workspace's notifications (config/agent-workspace.el).
;; Loaded from config/notify.el.
;;
;; An agent of a crew raises its hand, finishes its turn, is stuck, naps (it
;; loops and found nothing left), or sends you a message of its own; each
;; named by the agent ("ada (builder)"), a click opening its crew's app with
;; it selected, its pane open. agent-shell's own kinds leave a crew's
;; sessions to these (no notification twice).
;; Once per change of state, and not again for the same agent and kind
;; within `+my/notify-crew-quiet' seconds.

;; THE KINDS (see config/notify.el)
(+my/notify-define 'agent-workspace-hand "Agent crew" "An agent of a crew raises its hand: a permission, a question")
(+my/notify-define 'agent-workspace-done "Agent crew" "An agent of a crew finished its turn")
(+my/notify-define 'agent-workspace-stuck "Agent crew" "An agent of a crew is stuck: an error stopped it")
(+my/notify-define 'agent-workspace-message "Agent crew" "An agent of a crew's message, in its own words")
(+my/notify-define 'agent-workspace-napping "Agent crew" "A looping agent of a crew found nothing left to take: it naps")

(defvar +my/notify-crew-quiet 10
  "Seconds after a notification of an agent before another of the same kind
of it is shown.")

(defvar +my/notify-crew--last (make-hash-table :test #'equal)
  "When each (AGENT . KIND) was last notified of.")

(defun +my/notify-crew--name (agent)
  "AGENT as a notification names it: \"ada (builder)\"."
  (format "%s (%s)" (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)))

(defun +my/notify-crew--select (agent)
  "A click: AGENT's crew's app open, AGENT selected, the cursor in its pane."
  (lambda ()
    (let ((default-directory (agent-workspace-agent-project agent)))
      (agent-workspace-open))
    (agent-workspace-select agent t)))

(defun +my/notify-crew (kind agent text)
  "Notify of KIND about AGENT: \"ada (builder) TEXT\"; not again within
`+my/notify-crew-quiet' seconds. Non-nil if shown."
  (let ((key (cons agent kind)))
    (unless (< (- (float-time) (gethash key +my/notify-crew--last 0)) +my/notify-crew-quiet)
      (when (+my/notify kind (concat (+my/notify-crew--name agent) (if (string-prefix-p ":" text) "" " ") text)
                        :action (+my/notify-crew--select agent))
        (puthash key (float-time) +my/notify-crew--last)
        t))))

;; ITS STATES
(defun +my/notify-crew--state-h (agent old new)
  "AGENT's state changed from OLD to NEW: a hand raised, stuck, said.
In `agent-workspace-state-change-functions'."
  (unless (eq old new)
    (pcase new
      ('hand (+my/notify-crew 'agent-workspace-hand agent (agent-workspace-state-text agent)))
      ('stuck (+my/notify-crew 'agent-workspace-stuck agent
                               (if-let* ((error (agent-workspace-agent-error agent)))
                                   (concat "is stuck: " (car (split-string error "\n")))
                                 "is stuck"))))))

(add-hook 'agent-workspace-state-change-functions #'+my/notify-crew--state-h)

;; ITS NAPS (a loop with nothing left: once, until it takes an issue again)
(defun +my/notify-crew--nap-h (agent)
  "AGENT, looping, found nothing left to take: said. In
`agent-workspace-nap-functions'."
  (+my/notify-crew 'agent-workspace-napping agent (concat "is " (agent-workspace-state-text agent))))

(add-hook 'agent-workspace-nap-functions #'+my/notify-crew--nap-h)

;; ITS TURNS (agent-shell's turn-complete; interrupted by you: not said)
(defun +my/notify-crew--turn-done (agent event)
  "AGENT's turn ended (agent-shell's turn-complete EVENT): said, with the
issue it works on."
  (let ((reason (map-nested-elt event '(:data :stop-reason)))
        (issue (agent-workspace-agent-issue agent)))
    (pcase reason
      ("cancelled" nil)
      ((or 'nil "end_turn")
       (+my/notify-crew 'agent-workspace-done agent (if issue (format "finished %s" issue) "finished")))
      (_ (+my/notify-crew 'agent-workspace-done agent (format "stopped (%s)" reason))))))

(defun +my/notify-crew--watch (agent buffer)
  "AGENT's session BUFFER followed for its turns' ends. In
`agent-workspace-session-functions'."
  (agent-shell-subscribe-to
   :shell-buffer buffer :event 'turn-complete
   :on-event (lambda (event) (+my/notify-crew--turn-done agent event))))

(add-hook 'agent-workspace-session-functions #'+my/notify-crew--watch)

;; AGENT-SHELL'S KINDS LEAVE THEM TO THESE
(defun +my/notify-crew--own-p (buffer)
  "Non-nil if BUFFER is a crew's agent's session (its notifications are
these). In `+my/notify-agent-shell-own-functions'."
  (when-let* ((agent (agent-workspace-buffer-agent buffer)))
    (eq (agent-workspace-agent-buffer agent) buffer)))

(add-hook '+my/notify-agent-shell-own-functions #'+my/notify-crew--own-p)

;; ITS OWN MESSAGES (+my/notify-agent-shell, as it's told: named for it)
(defun +my/notify-crew--message (buffer text)
  "A crew's agent's message TEXT, from its session BUFFER: named by it. In
`+my/notify-agent-shell-message-functions'."
  (when-let* ((agent (agent-workspace-buffer-agent buffer)))
    (+my/notify-crew 'agent-workspace-message agent (concat ": " text))))

(add-hook '+my/notify-agent-shell-message-functions #'+my/notify-crew--message)
