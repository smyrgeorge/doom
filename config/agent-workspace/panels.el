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
;; across a restart, and a rename (opened again in its moved worktree). Saved
;; with the crew, by name (crew.json's panels, never their data: saved.el),
;; opened again when it starts again.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function agent-ui-panel-default-canvas-name "agent-ui/panels")
(declare-function agent-ui-open-panel "agent-ui/panels")
(declare-function agent-ui-error-message "agent-ui/core")
(defvar agent-ui-panels--state)
(defvar agent-ui-panel-directory)
(declare-function agent-ui-panels--root "agent-ui/panels")
(declare-function agent-ui-panels--file "agent-ui/panels")
(declare-function agent-ui-panels--name "agent-ui/panels")

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

;; ====== ITS WORKTREE MOVED ======

(defvar agent-workspace--panels-moving (make-hash-table :test #'eq :weakness 'key)
  "An agent whose worktree is moving: its panels, as crew.json keeps them, to
open again once it has.")

(defun agent-workspace--panels-moving-h (agent)
  "AGENT's worktree about to move (a rename, a role changed): its panels
closed, kept to open again. In `agent-workspace-moving-functions'."
  (when-let* ((names (agent-workspace-agent-panel-names agent)))
    (puthash agent names agent-workspace--panels-moving)
    (agent-workspace--close-panels agent)))

(defun agent-workspace--panels-moved-h (agent what)
  "AGENT renamed or given a role, its worktree moved: its panels opened again
there, named after it; not moved after all (`unmoved'), where they were. In
`agent-workspace-change-functions'."
  (when-let* (((memq what '(renamed role unmoved)))
              (names (gethash agent agent-workspace--panels-moving)))
    (remhash agent agent-workspace--panels-moving)
    (agent-workspace-open-panels agent names)))

(add-hook 'agent-workspace-moving-functions #'agent-workspace--panels-moving-h)
(add-hook 'agent-workspace-change-functions #'agent-workspace--panels-moved-h)

;; ====== SAVED WITH THE CREW ======

(defun agent-workspace--panel-saved-name (canvas)
  "Panel CANVAS as crew.json keeps it, as agent-ui open takes it: its name
\(one opened from a file elsewhere in its worktree: that file, relative to
it)."
  (let* ((panel (buffer-local-value 'agent-ui-panels--state canvas))
         (name (agent-ui-panels--name panel))
         (file (agent-ui-panels--file panel))
         (root (agent-ui-panels--root panel)))
    (if (file-equal-p file (expand-file-name (concat name ".el")
                                             (expand-file-name agent-ui-panel-directory root)))
        name
      (file-relative-name file root))))

(defun agent-workspace-agent-panel-names (agent)
  "AGENT's open panels as crew.json keeps them, sorted (see
`agent-workspace--panel-saved-name')."
  (sort (mapcar #'agent-workspace--panel-saved-name (agent-workspace-agent-panels agent))
        #'string<))

(defun agent-workspace-set-panels (agent names)
  "AGENT's panels made NAMES (crew.json's, edited): the ones missing opened,
the others closed."
  (dolist (canvas (agent-workspace-agent-panels agent))
    (unless (member (agent-workspace--panel-saved-name canvas) names)
      (let ((kill-buffer-query-functions nil))
        (kill-buffer canvas))))
  (agent-workspace-open-panels
   agent (seq-difference names (agent-workspace-agent-panel-names agent))))

(defun agent-workspace-open-panels (agent names)
  "AGENT's panels NAMES (crew.json's) opened again, in its worktree, as its
session opens one. One that can't open (its file gone): skipped, said; the
others open. None without Agent UI."
  (when (fboundp 'agent-ui-open-panel)
    (dolist (name names)
      (condition-case err
          (agent-ui-open-panel name (agent-workspace-agent-worktree agent) t)
        (error
         (display-warning 'agent-workspace
                          (format "%s's panel %s: %s: skipped" (agent-workspace-agent-name agent) name
                                  (string-remove-prefix (format "panel %s: " name)
                                                        (agent-ui-error-message err)))))))))
