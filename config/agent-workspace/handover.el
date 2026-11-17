;;; $DOOMDIR/config/agent-workspace/handover.el -*- lexical-binding: t; -*-
;; Issues as the crew's channel: work handed from role to role by labels and
;; status. Loaded from config/agent-workspace.el, after messages.el. No Doom
;; here.
;;
;; A role's file names the role its finished issues go to (hands-to:
;; builder): an investigator's findings to the builders, a builder's branch to
;; the reviewers, a reviewer's changes asked back to the builders. Each agent
;; is told how: the issue's label changed from its role's to the next one's,
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

(defun agent-workspace--handover-context (agent)
  "How AGENT hands an issue on, if its role hands to another: in what it's
told. While agents may not talk (`agent-workspace-agents-talk'), that it
hands nothing on. In `agent-workspace-context-functions'."
  (let* ((project (agent-workspace-agent-project agent))
         (next (plist-get (agent-workspace-role agent) :hands-to))
         (next (if (listp next) (car next) next))
         ;; Every one of its role's: one left, its loop takes the issue back.
         (mine (agent-workspace--role-labels project (agent-workspace-agent-role agent)))
         (theirs (and next (car (agent-workspace--role-labels project next)))))
    (cond
     ((and next (not agent-workspace-agents-talk))
      "You work only with the user, never with the other agents of your crew: hand nothing on to \
them, whatever your role's instructions say. When your part of an issue is done, leave its labels, \
status and assignee as they are, tell the user what you did, and end your turn: the user decides what \
comes next, and who takes it.")
     (theirs
      (format "Work moves between roles through the project's issues. When your part of an issue is \
done, hand it to the %ss: its labels changed from yours (all of them) to theirs, the issue open again \
and unassigned (or assigned to the one it goes back to), what they need in its notes: bd update ID \
%s--add-label %s --status open --assignee \"\" --append-notes \"...\". Then tell the user, and end your \
turn: the first free %s takes it."
              next (mapconcat (lambda (label) (format "--remove-label %s " label)) mine "") theirs next)))))

(add-hook 'agent-workspace-context-functions #'agent-workspace--handover-context)

;; ====== A READY ISSUE OFFERED ======

(defvar agent-workspace--offered (make-hash-table :test #'equal)
  "A project's issues offered in the room: (ID . NAME)s, once each.")

(defvar agent-workspace-offer-skip-functions nil
  "Called with an agent: non-nil if it's never offered an issue (it takes
them itself: its loop).")

(defun agent-workspace--issues-data (project)
  "PROJECT's issues as last fetched (the issue list's), or nil."
  (when-let* (((agent-workspace--app project))
              (buffer (agent-workspace--issues-buffer project)))
    (buffer-local-value 'agent-workspace--issues-data buffer)))

(defun agent-workspace--free-for (project role)
  "PROJECT's first agent of ROLE free to take an issue: at the desk or done,
on none, nothing skipping it."
  (seq-find (lambda (agent)
              (and (equal (agent-workspace-agent-role agent) role)
                   (memq (agent-workspace-agent-state agent) '(desk done))
                   (not (agent-workspace-agent-issue agent))
                   (not (run-hook-with-args-until-success 'agent-workspace-offer-skip-functions agent))))
            (agent-workspace--ordered project)))

(defun agent-workspace--offer-ready (project &optional data)
  "PROJECT's ready issues for a role (DATA, else as last fetched) offered in
the room to its first free agent, once each."
  (let ((key (agent-workspace--root project)))
    (dolist (issue (plist-get (or data (agent-workspace--issues-data project)) :ready))
      (let ((id (plist-get issue :id))
            (role (plist-get issue :role)))
        (when-let* (((and role (not (plist-get issue :assignee))
                          (not (assoc id (gethash key agent-workspace--offered)))))
                    (agent (agent-workspace--free-for project role)))
          (push (cons id (agent-workspace-agent-name agent)) (gethash key agent-workspace--offered))
          (agent-workspace-room-post project :kind 'offer :agent (agent-workspace-agent-name agent)
                                     :issue-id id
                                     :text (format "%s is ready for the %ss: %s is free"
                                                   id role (agent-workspace-agent-name agent))))))))

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

(defun agent-workspace--still-ready (project id)
  "PROJECT's issue ID if it's still ready and nobody's (as last fetched)."
  (seq-find (lambda (issue) (and (equal (plist-get issue :id) id) (not (plist-get issue :assignee))))
            (plist-get (agent-workspace--issues-data project) :ready)))

(defun agent-workspace-offer-take (project id name)
  "PROJECT's ready issue ID given to the agent NAME: free, it takes it now;
working, after its turn. Claimed for it in bd at once, its branch for it
first (`agent-workspace-give-issue'): refused if another agent has it, or
its worktree has changes not committed."
  (let ((issue (or (agent-workspace--still-ready project id) (user-error "%s is not ready any more" id)))
        (agent (or (agent-workspace-agent name project) (user-error "%s is not in the crew now" name))))
    (agent-workspace-give-issue agent id (plist-get issue :title) (plist-get issue :type))
    ;; Its until it's fetched again: its offer's button gone.
    (plist-put issue :assignee name)
    (agent-workspace--room-redraw-soon project)
    (agent-workspace-room-post project :kind 'issue :agent name :text (format "given %s (you)" id))))

(defun agent-workspace--room-offer-line (project entry)
  "An offer's button while its issue is still ready: [Give it to NAME]."
  (let ((id (plist-get entry :issue-id))
        (name (plist-get entry :agent)))
    (when (and id name (agent-workspace--still-ready project id) (agent-workspace-agent name project))
      (concat (make-string agent-workspace--room-indent ?\s)
              (agent-workspace--inbox-button (format "Give it to %s" name)
                                             (lambda () (agent-workspace-offer-take project id name)))))))
