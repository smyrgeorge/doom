;;; $DOOMDIR/config/agent-workspace/panels.el -*- lexical-binding: t; -*-
;; An agent's panels: the project panels it opens and keeps open while it
;; works. Loaded from config/agent-workspace.el, after app.el. No Doom here.
;;
;; A panel an agent opens (agent-ui open NAME, from its session) runs in its
;; worktree: its branch's .agent-ui/panels/NAME.el, its commands there. It's
;; the agent's own, named "NAME · AGENT" ("tests · ada"): two agents opening
;; tests get one each; one you open from the main checkout stays its own.
;; Never popped up in a pane: the stage shows it in its agent's pane. Hidden,
;; it fetches only when its agent reads it and its data is old (Agent UI's
;; agent-ui get). Its trust is its project's: trusting the project trusts its
;; agents' worktrees; a file changed on an agent's branch is asked about
;; again (Agent UI remembers a file's trust by its content). Closed when its
;; agent is killed, put to sleep or forgotten, and when its crew closes; kept
;; across a restart.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function agent-ui-panel-default-canvas-name "agent-ui/panels")
(defvar agent-ui-panels--state)
(declare-function agent-ui-panels--root "agent-ui/panels")

;; ====== WHOSE ======

(defun agent-workspace--panel-agent (canvas)
  "The agent whose panel CANVAS (a project panel's) is, or nil."
  (when-let* (((buffer-live-p canvas))
              ((boundp 'agent-ui-panels--state))
              (panel (buffer-local-value 'agent-ui-panels--state canvas))
              (root (agent-ui-panels--root panel))
              (where (agent-workspace-worktree-of (file-name-as-directory root))))
    (agent-workspace-agent (cadr where) (car where))))

(defun agent-workspace-agent-panels (agent)
  "AGENT's open panels: their canvases, by name (none without Agent UI)."
  (let ((worktree (and (agent-workspace-agent-worktree agent)
                       (file-truename (agent-workspace-agent-worktree agent)))))
    (when (and worktree (boundp 'agent-ui-panels--state))
      (seq-sort-by
       #'buffer-name #'string<
       (seq-filter (lambda (buffer)
                     (when-let* ((panel (buffer-local-value 'agent-ui-panels--state buffer)))
                       (equal (file-name-as-directory (file-truename (agent-ui-panels--root panel)))
                              (file-name-as-directory worktree))))
                   (buffer-list))))))

;; ====== AGENT UI, TOLD ======

(defun agent-workspace--panel-name (name root)
  "Panel NAME's canvas's name, of ROOT: an agent's worktree's \"NAME ·
AGENT\", else as Agent UI names it. `agent-ui-panel-name-function'."
  (if-let* ((where (agent-workspace-worktree-of (file-name-as-directory root))))
      (format "%s · %s" name (cadr where))
    (agent-ui-panel-default-canvas-name name root)))

(defun agent-workspace--panel-trust-root (root)
  "The root whose trust ROOT's panels share: an agent's worktree's
project's. `agent-ui-panel-trust-root-function'."
  (or (car (agent-workspace-worktree-of (file-name-as-directory root))) root))

(defun agent-workspace--panel-display (canvas)
  "A panel's CANVAS opened for an agent: an agent's of a crew isn't shown
\(its pane on the stage shows it), any other as Agent UI shows it.
`agent-ui-panel-display-function'."
  (if-let* ((agent (agent-workspace--panel-agent canvas)))
      (progn
        (with-current-buffer canvas
          (add-hook 'kill-buffer-hook #'agent-workspace--panel-closed-h nil t))
        (agent-workspace--changed agent 'panels))
    (display-buffer canvas)))

(defun agent-workspace--panel-closed-h ()
  "An agent's panel closed: said (its pane, its bar)."
  (when-let* ((agent (agent-workspace--panel-agent (current-buffer))))
    (run-at-time 0 nil #'agent-workspace--changed agent 'panels)))

;; ====== CLOSED WITH IT ======

(defun agent-workspace--close-panels (agent)
  "AGENT's panels closed."
  (dolist (canvas (agent-workspace-agent-panels agent))
    (let ((kill-buffer-query-functions nil))
      (kill-buffer canvas))))

(defun agent-workspace--panels-state-h (agent _old new)
  "AGENT put to sleep or gone home (killed, forgotten, its crew closed): its
panels closed. A restart keeps them. In
`agent-workspace-state-change-functions'."
  (when (memq new '(asleep home))
    (agent-workspace--close-panels agent)))

(add-hook 'agent-workspace-state-change-functions #'agent-workspace--panels-state-h)
