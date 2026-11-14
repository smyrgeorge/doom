;;; $DOOMDIR/config/notify/claude.el -*- lexical-binding: t; -*-
;; Claude Code's notifications: a session finished its turn (or stopped on
;; an error), asks for your permission, asks you a question, or sends a
;; message of its own.
;; Loaded from config/notify.el.

;; THE KINDS (see config/notify.el)
(+my/notify-define 'claude "Claude Code" "A session's message, in its own words")
(+my/notify-define 'claude-turn-done "Claude Code" "A session finished its turn, or stopped on an error")
(+my/notify-define 'claude-permission "Claude Code" "A session asks for your permission")
(+my/notify-define 'claude-question "Claude Code" "A session asks you a question")

;; A TURN DONE, PERMISSION ASKED, A QUESTION (agent-shell's events)
;; A question in the conversation (AskUserQuestion, agent-shell's form) is
;; agent-shell's elicitation-request: its turn waits for the answer, no
;; turn-complete comes. With its forms off, the adapter asks it as a
;; permission (claude-permission says it). A turn that fails (the API
;; overloaded, the login expired, a rate limit) ends in agent-shell's error,
;; not turn-complete: claude-turn-done says it too.

(declare-function shell-maker-busy "shell-maker")

(defun +my/notify-claude--folder (directory)
  "DIRECTORY's folder's name; nil for none (the root)."
  (let ((name (file-name-nondirectory (directory-file-name directory))))
    (unless (string-empty-p name)
      name)))

(defun +my/notify-claude--sessions (directory)
  "The Claude Code sessions working in DIRECTORY, the most recently used
first."
  (and directory
       (seq-filter (lambda (buffer)
                     (with-current-buffer buffer
                       (and (derived-mode-p 'agent-shell-mode)
                            (ignore-errors (file-equal-p (agent-shell-cwd) directory)))))
                   (buffer-list))))

(defun +my/notify-claude--name (buffer)
  "BUFFER's session, as a notification names it: its project's folder;
with another session working there, its buffer's name, what follows its
\" @ \" (\"doom<2>\"): else the two read alike."
  (with-current-buffer buffer
    (let* ((cwd (ignore-errors (agent-shell-cwd)))
           (folder (and cwd (+my/notify-claude--folder cwd)))
           (own (replace-regexp-in-string "\\`.* @ " "" (buffer-name))))
      (cond ((and folder (not (cdr (+my/notify-claude--sessions cwd)))) folder)
            ((not (string-empty-p own)) own)
            (t (buffer-name))))))

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

(defun +my/notify-claude--failed (buffer event)
  "BUFFER's session stopped on an error (agent-shell's error EVENT): its
message, the first line."
  (let* ((message (map-nested-elt event '(:data :message)))
         (line (and (stringp message)
                    (string-trim (car (split-string (string-trim message) "\n"))))))
    (+my/notify 'claude-turn-done
                (if (and line (not (string-empty-p line)))
                    (format "%s: stopped: %s" (+my/notify-claude--name buffer) line)
                  (format "%s: stopped on an error" (+my/notify-claude--name buffer)))
                :buffer buffer)))

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
  "A new session: notify when it finishes its turn or stops on an error, asks
for permission, or asks you a question."
  (let ((buffer (current-buffer)))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'turn-complete
     :on-event (lambda (event) (+my/notify-claude--turn-done buffer event)))
    (agent-shell-subscribe-to
     :shell-buffer buffer :event 'error
     :on-event (lambda (event) (+my/notify-claude--failed buffer event)))
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
;; notification names its project and a click shows the session. Of two
;; sessions in one folder, the caller's: the one named, else one whose turn
;; is running (Claude runs emacsclient in its turn).
(defun +my/notify-claude--session (directory &optional session)
  "The Claude Code session a message is from: SESSION (a buffer or its
name), else of those working in DIRECTORY one whose turn is running, else
the most recently used; nil if none is."
  (or (when-let* ((buffer (and session (get-buffer session))))
        (and (buffer-live-p buffer) buffer))
      (let ((sessions (+my/notify-claude--sessions directory)))
        (or (seq-find (lambda (buffer)
                        (with-current-buffer buffer
                          (ignore-errors (shell-maker-busy))))
                      sessions)
            (car sessions)))))

(defun +my/notify-claude (text &optional directory session)
  "Notify of a message from Claude Code: TEXT, as the caller words it.
DIRECTORY: the session's working directory, the notification naming its
project, a click showing the session; SESSION: that session (its buffer
or its name), of several working there. Shown as every notification is
\(see config/notify.el): only while Emacs isn't in front, `claude' on.
Non-nil if it was shown."
  (unless (and (stringp text) (not (string-empty-p (string-trim text))))
    (user-error "No message to notify of"))
  (let* ((session (+my/notify-claude--session directory session))
         (name (cond (session (+my/notify-claude--name session))
                     (directory (+my/notify-claude--folder directory)))))
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
