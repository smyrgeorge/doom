;;; $DOOMDIR/config/agent-workspace/handover.el -*- lexical-binding: t; -*-
;; Issues as the crew's channel: work handed from role to role by labels and
;; status. Loaded from config/agent-workspace.el, after messages.el. No Doom
;; here.
;;
;; A role's file names the roles its finished issues go to (hands-to:
;; builder), in order: the first one the crew has an agent of (awake or
;; asleep) takes them; any: every role with labels, the agent choosing; none
;; in the crew, it tells you. returns-to: where work goes back (changes
;; asked, a test failing), to the one who made it. The starters hand work
;; along one chain: builder, tester, documenter, reviewer (which merges what
;; it approves), a role the crew has none of skipped; changes asked, a test
;; or the suite failing, back to the builder who made it. An
;; investigator's findings (and a designer's, security's, a profiler's) go to
;; the builders. Every agent is told the project's roles and their labels.
;; Each agent is told how: the issue's label changed from its role's to the
;; next one's,
;; the issue open again and unassigned, what they need in its notes (bd, as
;; itself: Beads' history says who did what); a reviewer asking for changes
;; gives it back to the builder who made it. The first free agent of that role
;; takes it: the room offers it you ([Give it to ken], once per issue, when one
;; is free), or it takes it itself with its loop on. Claiming is bd's,
;; atomic: two agents never get the same issue. The room says each hand-over
;; (room.el, as the issue changed: its label moved, open again).
;;
;; Only with `agent-workspace-agents-talk' (config/agent-workspace.el):
;; without it, an agent whose role hands on is told to hand nothing on, only to
;; tell you (its role's instructions say it hands on "as you're told"). The
;; offers stay: a ready issue of a role, for you to give.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defun agent-workspace--role-labels (project role)
  "ROLE's labels in PROJECT (the issues it's for)."
  (plist-get (cdr (assoc role (agent-workspace-roles project))) :labels))

(defun agent-workspace-label-role (project label)
  "The role of PROJECT whose issues LABEL marks, or nil."
  (car (seq-find (lambda (role) (member label (plist-get (cdr role) :labels)))
                 (agent-workspace-roles project))))

(defun agent-workspace--crew-has-p (project role)
  "Non-nil if PROJECT's crew has an agent of ROLE, awake or asleep (not
gone home)."
  (seq-some (lambda (agent)
              (and (equal (agent-workspace-agent-role agent) role)
                   (not (eq (agent-workspace-agent-state agent) 'home))))
            (agent-workspace-agents project)))

(defun agent-workspace-hands-to (project role &optional key)
  "Where ROLE's work goes in PROJECT's crew, by its KEY (:hands-to, the
default, or :returns-to): of the roles it names, in order, the first one
the crew has an agent of, as a list; `any' (hands-to): every role of the
project with labels the crew has one of, but ROLE. nil: none."
  (let* ((roles (agent-workspace-roles project))
         (names (plist-get (agent-workspace--project-role project role) (or key :hands-to))))
    (if (and (member "any" names) (not (eq key :returns-to)))
        (seq-filter (lambda (name)
                      (and (not (equal name role))
                           (plist-get (cdr (assoc name roles)) :labels)
                           (agent-workspace--crew-has-p project name)))
                    (mapcar #'car roles))
      (when-let* ((first (seq-find (lambda (name)
                                     (and (agent-workspace--role-labels project name)
                                          (agent-workspace--crew-has-p project name)))
                                   names)))
        (list first)))))

(defun agent-workspace--handover-roles (project role &optional key)
  "The roles ROLE's work may go to in PROJECT by its KEY (:hands-to, the
default, or :returns-to), whatever the crew has: those it names that take
issues (have labels), in order; `any' (hands-to): every role with labels
but ROLE. `agent-workspace-hands-to' picks among them by the crew."
  (let ((roles (agent-workspace-roles project))
        (names (plist-get (agent-workspace--project-role project role) (or key :hands-to))))
    (if (and (member "any" names) (not (eq key :returns-to)))
        (seq-filter (lambda (name) (and (not (equal name role)) (plist-get (cdr (assoc name roles)) :labels)))
                    (mapcar #'car roles))
      (seq-filter (lambda (name) (agent-workspace--role-labels project name)) names))))

(defun agent-workspace--handover-context (agent)
  "How AGENT hands an issue on, if its role hands to others: in what it's
told. Not the crew as its session starts (it changes while it runs: an
agent made, forgotten, gone home): the roles its hands-to names, in order,
each with its bd command, to hand to the first the crew has an agent of
then (`cmd/agent-workspace status' says), else to tell you; with `any',
the role it's for of those; its returns-to the same for work going back.
While agents may not talk (`agent-workspace-agents-talk'), that it hands
nothing on. In `agent-workspace-context-functions'."
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-role agent))
         (role (agent-workspace-role agent))
         (named (or (plist-get role :hands-to) (plist-get role :returns-to)))
         (any (member "any" (plist-get role :hands-to)))
         ;; Every one of its role's: one left, its loop takes the issue back.
         (mine (agent-workspace--role-labels project name))
         (next (agent-workspace--handover-roles project name))
         (back (agent-workspace--handover-roles project name :returns-to))
         (status "cmd/agent-workspace status says who is in it now; asleep counts, gone home doesn't")
         (command (lambda (to assignee)
                    (format "bd update ID %s--add-label %s --status open --assignee %s --append-notes \"...\""
                            (mapconcat (lambda (label) (format "--remove-label %s " label)) mine "")
                            (car (agent-workspace--role-labels project to))
                            assignee)))
         (described (lambda (name)
                      (let ((what (plist-get (agent-workspace--project-role project name) :description)))
                        (if what (format "the %ss (%s)" name what) (format "the %ss" name)))))
         (listed (lambda (roles assignee)
                   (mapconcat (lambda (to) (format "\n- %s: %s" (funcall described to) (funcall command to assignee)))
                              roles "")))
         (plural (lambda (roles) (string-join (mapcar (lambda (to) (format "the %ss" to)) roles) ", "))))
    (cond
     ((and named (not agent-workspace-agents-talk))
      (concat
       "You work only with the user, never with the other agents of your crew: hand nothing on to \
them, whatever your role's instructions say. When your part of an issue is done, leave its labels, \
status and assignee as they are, tell the user what you did"
       (cond
        ((null next) "")
        (any " and which role it's for next")
        ((null (cdr next)) (format " and which role is next (\"next: the %ss\")" (car next)))
        (t (format " and which role is next: the first of %s the crew has an agent of (%s), as \"next: the %ss\""
                   (funcall plural next) status (car next))))
       ", and end your turn: the user decides what comes next, and who takes it."))
     ((not named) nil)
     (t
      (concat
       "Work moves between roles through the project's issues."
       (cond
        ((null next)
         (if (plist-get role :hands-to)
             " When your part of an issue is done, leave its labels, status and assignee as they are, tell \
the user what you did and that it's ready for them, and end your turn."
           ""))
        (t
         (concat
          (cond
           (any (format " When your part of an issue is done, hand it to the role it's for, of those the \
crew has an agent of (%s): its labels changed from yours (all of them) to that role's first (the \
project's roles list them), the issue open again and unassigned, what they need in its notes: %s. Then \
tell the user, and end your turn: the first free agent of that role takes it."
                        status
                        (format "bd update ID %s--add-label LABEL --status open --assignee \"\" --append-notes \"...\""
                                (mapconcat (lambda (label) (format "--remove-label %s " label)) mine ""))))
           ((null (cdr next))
            (format " When your part of an issue is done, hand it to the %ss, if the crew has one (%s): \
its labels changed from yours (all of them) to theirs, the issue open again and unassigned, what they \
need in its notes: %s. Then tell the user, and end your turn: the first free %s takes it."
                    (car next) status (funcall command (car next) "\"\"") (car next)))
           (t (format " When your part of an issue is done, hand it to the first of these roles the crew \
has an agent of (%s): its labels changed from yours (all of them) to theirs, the issue open again and \
unassigned, what they need in its notes. Then tell the user, and end your turn: the first free agent of \
that role takes it." status)))
          (if (or any (null (cdr next)))
              " "
            (concat (funcall listed next "\"\"") "\n"))
          (format "If the crew has %s, leave its labels, status and assignee as they are, tell the user \
what you did and that it's ready for them, and end your turn."
                  (if (or any (cdr next)) "none of them" (format "no %s" (car next)))))))
       (when back
         (if (null (cdr back))
             (format " When it must go back instead (changes asked, a test failing), give it back to the \
%ss, assigned to the one who made it (its notes or bd history ID say who): %s."
                     (car back) (funcall command (car back) "NAME"))
           (format " When it must go back instead (changes asked, a test failing), give it back to the \
first of these roles the crew has an agent of, assigned to the one who made it (its notes or bd history \
ID say who):%s" (funcall listed back "NAME")))))))))

(add-hook 'agent-workspace-context-functions #'agent-workspace--handover-context)

(defun agent-workspace--roles-context (agent)
  "The roles of AGENT's project, a line each (its name, what it does, the
labels of the issues it's for), from their files: the starters, the
project's own and your local ones. In `agent-workspace-context-functions',
before how it hands on."
  (let ((roles (agent-workspace-roles (agent-workspace-agent-project agent))))
    (when roles
      (concat "The project's roles, and the labels of the issues each is for (an issue goes to a \
role by its label):"
              (mapconcat (lambda (role)
                           (let ((labels (plist-get (cdr role) :labels))
                                 (what (plist-get (cdr role) :description)))
                             (format "\n- %s%s: %s" (car role) (if what (concat ", " what) "")
                                     (if labels (string-join labels ", ") "no labels"))))
                         roles "")))))

(add-hook 'agent-workspace-context-functions #'agent-workspace--roles-context -10)

;; ====== A READY ISSUE OFFERED ======

(defvar agent-workspace--offered (make-hash-table :test #'equal)
  "A project's issues offered in the room: ((ID ROLE ASSIGNEE) . NAME)s,
once each: offered again once handed to another role (or back to an
agent).")

(defvar agent-workspace-offer-skip-functions nil
  "Called with an agent: non-nil if it's never offered an issue (it takes
them itself: its loop).")

(defun agent-workspace--issues-data (project)
  "PROJECT's issues as last fetched (the issue list's), or nil."
  (when-let* (((agent-workspace--app project))
              (buffer (agent-workspace--issues-buffer project)))
    (buffer-local-value 'agent-workspace--issues-data buffer)))

(defun agent-workspace--free-to-offer-p (agent)
  "Non-nil if AGENT is free to be offered an issue: at the desk or done, on
none, nothing skipping it (its loop)."
  (and (memq (agent-workspace-agent-state agent) '(desk done))
       (not (agent-workspace-agent-issue agent))
       (not (run-hook-with-args-until-success 'agent-workspace-offer-skip-functions agent))))

(defun agent-workspace--free-for (project role)
  "PROJECT's first agent of ROLE free to take an issue: at the desk or done,
on none, nothing skipping it."
  (seq-find (lambda (agent)
              (and (equal (agent-workspace-agent-role agent) role)
                   (agent-workspace--free-to-offer-p agent)))
            (agent-workspace--ordered project)))

(defun agent-workspace--offer-ready (project &optional data)
  "PROJECT's ready issues for a role (DATA, else as last fetched) offered in
the room to its first free agent, once each; one handed back to an agent
\(open, assigned to it), to that agent, once it's free."
  (let* ((key (agent-workspace--root project))
         (data (or data (agent-workspace--issues-data project)))
         (ready (mapcar (lambda (issue) (list (plist-get issue :id) (plist-get issue :role) (plist-get issue :assignee)))
                        (plist-get data :ready))))
    ;; One ready no more (taken, handed on): forgotten, offered again the
    ;; next time it's ready so (a re-review after changes, a second return).
    (when data
      (puthash key (seq-filter (lambda (entry) (member (car entry) ready)) (gethash key agent-workspace--offered))
               agent-workspace--offered))
    (dolist (issue (plist-get data :ready))
      (let* ((id (plist-get issue :id))
             (role (plist-get issue :role))
             (assignee (plist-get issue :assignee))
             (back (and assignee (agent-workspace-agent assignee project)))
             (offer (list id role assignee)))
        (when-let* (((not (assoc offer (gethash key agent-workspace--offered))))
                    (agent (cond (assignee (and back (agent-workspace--free-to-offer-p back) back))
                                 (role (agent-workspace--free-for project role)))))
          (push (cons offer (agent-workspace-agent-name agent)) (gethash key agent-workspace--offered))
          (agent-workspace-room-post project :kind 'offer :agent (agent-workspace-agent-name agent)
                                     :issue-id id :role role
                                     :text (if back
                                               (format "%s is back for %s, free now" id assignee)
                                             (format "%s is ready for the %ss: %s is free"
                                                     id role (agent-workspace-agent-name agent)))))))))

(defun agent-workspace--offer-fetched-h (project data)
  "PROJECT's issues fetched: the ready ones offered, the offers' buttons
drawn again (gone with their issue). In
`agent-workspace-issues-fetched-functions'."
  (agent-workspace--offer-ready project data)
  (when (fboundp 'agent-workspace--room-redraw-soon)
    (agent-workspace--room-redraw-soon project)))

(defun agent-workspace--offer-state-h (agent _old new)
  "AGENT free: its crew's ready issues offered (as last fetched). In
`agent-workspace-state-change-functions'."
  (when (memq new '(desk done))
    (agent-workspace--offer-ready (agent-workspace-agent-project agent))))

(add-hook 'agent-workspace-issues-fetched-functions #'agent-workspace--offer-fetched-h)
(add-hook 'agent-workspace-state-change-functions #'agent-workspace--offer-state-h)

(defun agent-workspace--still-ready (project id &optional name)
  "PROJECT's issue ID if it's still ready (as last fetched), not given
since, and nobody's (or the agent NAME's: handed back to it)."
  (seq-find (lambda (issue) (and (equal (plist-get issue :id) id)
                                 (not (plist-get issue :given))
                                 (member (plist-get issue :assignee) (list nil name))))
            (plist-get (agent-workspace--issues-data project) :ready)))

(defun agent-workspace-offer-take (project id name)
  "PROJECT's ready issue ID given to the agent NAME: free, it takes it now;
working, after its turn. Claimed for it in bd at once, its branch for it
first (`agent-workspace-give-issue'): refused if another agent has it, or
its worktree has changes not committed."
  (let ((issue (or (agent-workspace--still-ready project id name) (user-error "%s is not ready any more" id)))
        (agent (or (agent-workspace-agent name project) (user-error "%s is not in the crew now" name))))
    (agent-workspace-give-issue agent id (plist-get issue :title) (plist-get issue :type))
    ;; Its until it's fetched again: its offer's button gone.
    (plist-put issue :assignee name)
    (plist-put issue :given name)
    (agent-workspace--room-redraw-soon project)
    (agent-workspace-room-post project :kind 'issue :agent name :text (format "given %s (you)" id))))

(defun agent-workspace--room-offer-line (project entry)
  "An offer's button while its issue is still ready, for the role it was
offered for (not since handed to another): [Give it to NAME]."
  (let* ((id (plist-get entry :issue-id))
         (name (plist-get entry :agent))
         (issue (and id name (agent-workspace--still-ready project id name))))
    (when (and issue (agent-workspace-agent name project)
               (or (not (plist-member entry :role)) (equal (plist-get issue :role) (plist-get entry :role))))
      (concat (make-string agent-workspace--room-indent ?\s)
              (agent-workspace--inbox-button (format "Give it to %s" name)
                                             (lambda () (agent-workspace-offer-take project id name)))))))
