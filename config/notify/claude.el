;;; $DOOMDIR/config/notify/claude.el -*- lexical-binding: t; -*-
;; Claude Code's notifications: a session finished its turn, asks for your
;; permission, asks you a question, or sends a message of its own.
;; Loaded from config/notify.el.

;; THE KINDS (see config/notify.el)
(+my/notify-define 'claude "Claude Code" "A session's message, in its own words")
(+my/notify-define 'claude-turn-done "Claude Code" "A session finished its turn")
(+my/notify-define 'claude-permission "Claude Code" "A session asks for your permission")
(+my/notify-define 'claude-question "Claude Code" "A session asks you a question")

;; A TURN DONE, PERMISSION ASKED, A QUESTION (agent-shell's events)
;; A question in the conversation (AskUserQuestion, agent-shell's form) is
;; agent-shell's elicitation-request: its turn waits for the answer, no
;; turn-complete comes. With its forms off, the adapter asks it as a
;; permission (claude-permission says it).

(defun +my/notify-claude--name (buffer)
  "BUFFER's session, as a notification names it: its project's folder."
  (with-current-buffer buffer
    (or (ignore-errors
          (file-name-nondirectory (directory-file-name (agent-shell-cwd))))
        (buffer-name))))

(defvar +my/notify-claude-turn-said-functions nil
  "Called with a session's buffer and agent-shell's turn-complete event when
its turn ends: one returning non-nil says it in a notification of its own
\(Agent UI's question waiting), the turn's one not shown.")

(defun +my/notify-claude--turn-done (buffer event)
  "BUFFER's session finished its turn (agent-shell's turn-complete EVENT)."
  (let ((reason (map-nested-elt event '(:data :stop-reason))))
    (unless (run-hook-with-args-until-success '+my/notify-claude-turn-said-functions buffer event)
      (+my/notify 'claude-turn-done
                  (format "%s: %s" (+my/notify-claude--name buffer)
                          (pcase reason
                            ((or 'nil "end_turn") "finished")
                            ("max_tokens" "stopped: the answer was too long")
                            ("max_turn_requests" "stopped: too many steps")
                            ("refusal" "stopped: it refused")
                            ("cancelled" "cancelled")
                            (_ (format "stopped (%s)" reason))))
                  :buffer buffer))))

(defun +my/notify-claude--permission (buffer event)
  "BUFFER's session asks for permission (agent-shell's permission-request
EVENT): what for, the tool call's title."
  (let ((title (map-nested-elt event '(:data :tool-call :title))))
    (+my/notify 'claude-permission
                (format "%s needs your permission%s" (+my/notify-claude--name buffer)
                        (if (and (stringp title) (not (string-empty-p title)))
                            (format ": %s" title)
                          ""))
                :buffer buffer)))

(defun +my/notify-claude--question (buffer event)
  "BUFFER's session asks you a question in its conversation (agent-shell's
elicitation-request EVENT, a form): the question, its first line."
  (let* ((message (map-nested-elt event '(:data :message)))
         (question (and (stringp message)
                        (string-trim (car (split-string (string-trim message) "\n"))))))
    (+my/notify 'claude-question
                (if (and question (not (string-empty-p question)))
                    (format "%s asks: %s" (+my/notify-claude--name buffer) question)
                  (format "%s asks you a question" (+my/notify-claude--name buffer)))
                :buffer buffer)))

(defun +my/notify-claude--watch-h ()
  "A new session: notify when it finishes its turn, asks for permission, or
asks you a question."
  (let ((buffer (current-buffer)))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'turn-complete
     :on-event (lambda (event) (+my/notify-claude--turn-done buffer event)))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'permission-request
     :on-event (lambda (event) (+my/notify-claude--permission buffer event)))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'elicitation-request
     :on-event (lambda (event) (+my/notify-claude--question buffer event)))))

(add-hook 'agent-shell-mode-hook #'+my/notify-claude--watch-h)

;; A MESSAGE FROM CLAUDE CODE
;; The caller words it: Claude itself, through emacsclient (it's told how,
;; below), or any code. Given the session's working directory, the
;; notification names its project and a click shows the session.
(defun +my/notify-claude--session (directory)
  "The Claude Code session working in DIRECTORY, if one is."
  (and directory
       (seq-find (lambda (buffer)
                   (with-current-buffer buffer
                     (and (derived-mode-p 'agent-shell-mode)
                          (ignore-errors (file-equal-p (agent-shell-cwd) directory)))))
                 (buffer-list))))

(defun +my/notify-claude (text &optional directory)
  "Notify of a message from Claude Code: TEXT, as the caller words it.
DIRECTORY: the session's working directory, the notification naming its
project, a click showing the session. Shown as every notification is (see
config/notify.el): only while Emacs isn't in front, `claude' on.
Non-nil if it was shown."
  (unless (and (stringp text) (not (string-empty-p (string-trim text))))
    (user-error "No message to notify of"))
  (let* ((session (+my/notify-claude--session directory))
         (name (cond (session (+my/notify-claude--name session))
                     (directory (file-name-nondirectory (directory-file-name directory))))))
    (+my/notify 'claude (if name (format "%s: %s" name text) text)
                :buffer session)))

;; What Claude Code is told about it: appended to what it's told about Emacs
;; (config/agent-shell.el's `+my/agent-shell-claude-context', loaded before),
;; once.
(defconst +my/notify-claude--context
  "Notifications: the user may be in another app while you work. When they \
asked you to tell them when something is done, or something needs them, \
notify them on their desktop: emacsclient --eval \
'(+my/notify-claude \"The tests pass\" \"/absolute/working/directory\")', your \
message and your working directory. It shows only while Emacs isn't in front \
(it prints t if shown, nil if not). They already get one when you finish a \
turn, when you ask for permission and when you ask a question in the \
conversation: don't send those again."
  "What Claude Code is told about notifying (see above).")

(when (and (boundp '+my/agent-shell-claude-context)
           (stringp +my/agent-shell-claude-context)
           (not (string-search +my/notify-claude--context +my/agent-shell-claude-context)))
  (setq +my/agent-shell-claude-context
        (concat +my/agent-shell-claude-context "\n\n" +my/notify-claude--context)))
