;;; $DOOMDIR/config/notify/agent-shell.el -*- lexical-binding: t; -*-
;; agent-shell's sessions' notifications, whatever their agent (each titled
;; by it: Claude, Codex...). Loaded from config/notify.el.
;; A session finished its turn (or stopped on an error), asks for your
;; permission, asks you a question, or sends a message of its own.

;; THE KINDS (see config/notify.el)
(+my/notify-define 'agent-shell-message "Agent shell" "A session's message, in its own words")
(+my/notify-define 'agent-shell-turn-done "Agent shell" "A session finished its turn, or stopped on an error")
(+my/notify-define 'agent-shell-permission "Agent shell" "A session asks for your permission")
(+my/notify-define 'agent-shell-question "Agent shell" "A session asks you a question")

;; A TURN DONE, PERMISSION ASKED, A QUESTION (agent-shell's events)
;; A question in the conversation (AskUserQuestion, agent-shell's form) is
;; agent-shell's elicitation-request: its turn waits for the answer, no
;; turn-complete comes. With its forms off, the adapter asks it as a
;; permission (agent-shell-permission says it). A turn that fails (the API
;; overloaded, the login expired, a rate limit) ends in agent-shell's error,
;; not turn-complete: agent-shell-turn-done says it too.

(declare-function shell-maker-busy "shell-maker")
(defvar agent-shell--state)

(defun +my/notify-agent-shell--agent (buffer)
  "BUFFER's session's agent, a notification's title: its config's name
\(Claude, Codex); nil if not known (its kind's then: Agent shell)."
  (and (buffer-live-p buffer)
       (buffer-local-boundp 'agent-shell--state buffer)
       (map-nested-elt (buffer-local-value 'agent-shell--state buffer)
                       '(:agent-config :mode-line-name))))

(defun +my/notify-agent-shell--folder (directory)
  "DIRECTORY's folder's name; nil for none (the root)."
  (let ((name (file-name-nondirectory (directory-file-name directory))))
    (unless (string-empty-p name)
      name)))

(defun +my/notify-agent-shell--sessions (directory)
  "The sessions working in DIRECTORY, the most recently used
first."
  (and directory
       (seq-filter (lambda (buffer)
                     (with-current-buffer buffer
                       (and (derived-mode-p 'agent-shell-mode)
                            (ignore-errors (file-equal-p (agent-shell-cwd) directory)))))
                   (buffer-list))))

(defun +my/notify-agent-shell--name (buffer)
  "BUFFER's session, as a notification names it: its project's folder;
with another session working there, the folder and its buffer's name
\(\"doom · Claude<2>\"): else the two read alike. No folder: its buffer's
name."
  (with-current-buffer buffer
    (let* ((cwd (ignore-errors (agent-shell-cwd)))
           (folder (and cwd (+my/notify-agent-shell--folder cwd))))
      (cond ((not folder) (buffer-name))
            ((cdr (+my/notify-agent-shell--sessions cwd)) (format "%s · %s" folder (buffer-name)))
            (t folder)))))

(define-obsolete-variable-alias '+my/notify-claude-own-functions '+my/notify-agent-shell-own-functions "2026-11-24")
(defvar +my/notify-agent-shell-own-functions nil
  "Called with a session's buffer: one returning non-nil notifies of that
session itself (an agent of a crew: config/notify/agent-workspace.el), its turns, its
permissions, questions, errors and messages; these kinds then don't.")

(defun +my/notify-agent-shell--own-p (buffer)
  "Non-nil if BUFFER's session is notified of by another (see
`+my/notify-agent-shell-own-functions')."
  (run-hook-with-args-until-success '+my/notify-agent-shell-own-functions buffer))

(define-obsolete-variable-alias '+my/notify-claude-turn-said-functions '+my/notify-agent-shell-turn-said-functions "2026-11-24")
(defvar +my/notify-agent-shell-turn-said-functions nil
  "Called with a session's buffer and agent-shell's turn-complete event when
its turn ends: one returning non-nil says it in a notification of its own
\(Agent UI's question waiting), the turn's one not shown.")

(defun +my/notify-agent-shell--turn-done (buffer event)
  "BUFFER's session finished its turn (agent-shell's turn-complete EVENT)."
  (let ((reason (map-nested-elt event '(:data :stop-reason))))
    (unless (run-hook-with-args-until-success '+my/notify-agent-shell-turn-said-functions buffer event)
      (+my/notify 'agent-shell-turn-done
                  (format "%s: %s" (+my/notify-agent-shell--name buffer)
                          (pcase reason
                            ((or 'nil "end_turn") "finished")
                            ("max_tokens" "stopped: the answer was too long")
                            ("max_turn_requests" "stopped: too many steps")
                            ("refusal" "stopped: it refused")
                            ("cancelled" "cancelled")
                            (_ (format "stopped (%s)" reason))))
                  :buffer buffer :title (+my/notify-agent-shell--agent buffer)))))

(defun +my/notify-agent-shell--failed (buffer event)
  "BUFFER's session stopped on an error (agent-shell's error EVENT): its
message, the first line."
  (let* ((message (map-nested-elt event '(:data :message)))
         (line (and (stringp message)
                    (string-trim (car (split-string (string-trim message) "\n"))))))
    (+my/notify 'agent-shell-turn-done
                (if (and line (not (string-empty-p line)))
                    (format "%s: stopped: %s" (+my/notify-agent-shell--name buffer) line)
                  (format "%s: stopped on an error" (+my/notify-agent-shell--name buffer)))
                :buffer buffer :title (+my/notify-agent-shell--agent buffer))))

(defun +my/notify-agent-shell--permission (buffer event)
  "BUFFER's session asks for permission (agent-shell's permission-request
EVENT): what for, the tool call's title."
  (let ((title (map-nested-elt event '(:data :tool-call :title))))
    (+my/notify 'agent-shell-permission
                (format "%s needs your permission%s" (+my/notify-agent-shell--name buffer)
                        (if (and (stringp title) (not (string-empty-p title)))
                            (format ": %s" title)
                          ""))
                :buffer buffer :title (+my/notify-agent-shell--agent buffer))))

(defun +my/notify-agent-shell--question (buffer event)
  "BUFFER's session asks you a question in its conversation (agent-shell's
elicitation-request EVENT, a form): the question, its first line."
  (let* ((message (map-nested-elt event '(:data :message)))
         (question (and (stringp message)
                        (string-trim (car (split-string (string-trim message) "\n"))))))
    (+my/notify 'agent-shell-question
                (if (and question (not (string-empty-p question)))
                    (format "%s asks: %s" (+my/notify-agent-shell--name buffer) question)
                  (format "%s asks you a question" (+my/notify-agent-shell--name buffer)))
                :buffer buffer :title (+my/notify-agent-shell--agent buffer))))

(defun +my/notify-agent-shell--watch-h ()
  "A new session: notify when it finishes its turn or stops on an error, asks
for permission, or asks you a question; not one another notifies of
\(`+my/notify-agent-shell-own-functions'), asked as each event comes (a crew's
agent is known once its session started)."
  (let ((buffer (current-buffer)))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'turn-complete
     :on-event (lambda (event) (unless (+my/notify-agent-shell--own-p buffer)
                                 (+my/notify-agent-shell--turn-done buffer event))))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'error
     :on-event (lambda (event) (unless (+my/notify-agent-shell--own-p buffer)
                                 (+my/notify-agent-shell--failed buffer event))))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'permission-request
     :on-event (lambda (event) (unless (+my/notify-agent-shell--own-p buffer)
                                 (+my/notify-agent-shell--permission buffer event))))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'elicitation-request
     :on-event (lambda (event) (unless (+my/notify-agent-shell--own-p buffer)
                                 (+my/notify-agent-shell--question buffer event))))))

(add-hook 'agent-shell-mode-hook #'+my/notify-agent-shell--watch-h)

;; A MESSAGE FROM THE AGENT
;; The caller words it: the agent itself, through emacsclient (it's told how,
;; below), or any code. Given the session's working directory, the
;; notification names its project and a click shows the session. Of two
;; sessions in one folder, the caller's: the one named, else one whose turn
;; is running (the agent runs emacsclient in its turn).
(defun +my/notify-agent-shell--session (directory &optional session)
  "The session a message is from: SESSION (a buffer or its
name), else of those working in DIRECTORY one whose turn is running, else
the most recently used; nil if none is."
  (or (when-let* ((buffer (and session (get-buffer session))))
        (and (buffer-live-p buffer) buffer))
      (let ((sessions (+my/notify-agent-shell--sessions directory)))
        (or (seq-find (lambda (buffer)
                        (with-current-buffer buffer
                          (ignore-errors (shell-maker-busy))))
                      sessions)
            (car sessions)))))

(defun +my/notify-agent-shell (text &optional directory session)
  "Notify of a message from a session's agent: TEXT, as the caller words it.
DIRECTORY: the session's working directory, the notification naming its
project, a click showing the session; SESSION: that session (its buffer
or its name), of several working there. Shown as every notification is
\(see config/notify.el): only while Emacs isn't in front, `agent-shell-message' on.
Non-nil if it was shown."
  (unless (and (stringp text) (not (string-empty-p (string-trim text))))
    (user-error "No message to notify of"))
  (let* ((session (+my/notify-agent-shell--session directory session))
         (name (cond (session (+my/notify-agent-shell--name session))
                     (directory (+my/notify-agent-shell--folder directory)))))
    (if (and session (+my/notify-agent-shell--own-p session))
        (run-hook-with-args-until-success '+my/notify-agent-shell-message-functions session text)
      (+my/notify 'agent-shell-message (if name (format "%s: %s" name text) text)
                  :buffer session :title (+my/notify-agent-shell--agent session)))))

(define-obsolete-function-alias '+my/notify-claude #'+my/notify-agent-shell "2026-11-24")

(define-obsolete-variable-alias '+my/notify-claude-message-functions '+my/notify-agent-shell-message-functions "2026-11-24")
(defvar +my/notify-agent-shell-message-functions nil
  "Called with a session's buffer and a message of its own, for a session
another notifies of (`+my/notify-agent-shell-own-functions'): one notifies of it
\(non-nil if shown).")

;; What every session is told about it: appended to what it's told about Emacs
;; (config/agent-shell.el's `+my/agent-shell-context', loaded before),
;; once.
(defconst +my/notify-agent-shell--context
  "Notifications: the user may be in another app while you work. When they \
asked you to tell them when something is done, or something needs them, \
notify them on their desktop: emacsclient --eval \
'(+my/notify-agent-shell \"The tests pass\" \"/absolute/working/directory\")', your \
message and your working directory. It shows only while Emacs isn't in front \
(it prints t if shown, nil if not). They already get one when you finish a \
turn, when you ask for permission and when you ask a question in the \
conversation: don't send those again."
  "What every session is told about notifying (see above).")

(when (and (boundp '+my/agent-shell-context)
           (stringp +my/agent-shell-context)
           (not (string-search +my/notify-agent-shell--context +my/agent-shell-context)))
  (setq +my/agent-shell-context
        (concat +my/agent-shell-context "\n\n" +my/notify-agent-shell--context)))
