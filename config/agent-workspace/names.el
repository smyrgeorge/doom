;;; $DOOMDIR/config/agent-workspace/names.el -*- lexical-binding: t; -*-
;; An agent's name on its worktree, in Emacs. Loaded from
;; config/agent-workspace.el, after worktree.el. No Doom here.
;;
;; A worktree's files belong to the project "PROJECT · NAME" (projectile's
;; and project.el's name for it, so a workspace made for it says it too).
;; Their mode line shows the agent: its avatar and name in its colour, its
;; role ("▌A ada · builder"); a click selects it. Their tab starts with its
;; avatar (`agent-workspace-tab-prefix'). A file's agent is found from its
;; worktree's folder (ROLE-NAME) through the crew, so it's there asleep or
;; gone home too; a worktree left by a forgotten agent shows its name (its
;; lock's reason says it; else its branch, agent/NAME, at rest) dimmed.

(require 'cl-lib)
(require 'subr-x)

(declare-function project-root "project")

;; ====== VARIABLES ======

(defvar agent-workspace-select-function #'agent-workspace--show-session
  "Called with an agent to select it (a click on its name in a mode line).
The app sets it; meanwhile the agent's session is shown.")

(defvar agent-workspace-mode-line-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'agent-workspace-mode-line-select)
    map)
  "Keys on an agent's name in a mode line.")

;; ====== A FILE'S AGENT ======

(defun agent-workspace-worktree-of (file)
  "If FILE is in an agent's worktree: (PROJECT NAME), the main checkout's
folder and the agent's name; the outermost, for a worktree's own
.agent-shell/."
  (let ((file (expand-file-name file)))
    (when (string-match (concat "\\`\\(.*?/\\)"
                                (regexp-quote (file-name-as-directory agent-workspace-worktrees-directory))
                                "\\([^/]+\\)\\(?:/\\|\\'\\)")
                        file)
      (let ((project (match-string 1 file))
            (folder (match-string 2 file)))
        (list project (agent-workspace--worktree-name project folder))))))

(defun agent-workspace--worktree-name (project folder)
  "The name of the agent whose worktree is FOLDER (ROLE-NAME) in PROJECT:
its crew's agent there, else a forgotten agent's (its lock's reason, else
its branch agent/NAME: `agent-workspace--worktree-agent-name'), else
FOLDER."
  (or (when-let* ((agent (seq-find (lambda (agent)
                                     (equal folder (file-name-nondirectory
                                                    (directory-file-name
                                                     (or (agent-workspace-agent-worktree agent)
                                                         (concat (agent-workspace-agent-role agent) "-"
                                                                 (agent-workspace-agent-name agent)))))))
                                   (ignore-errors (agent-workspace-agents project)))))
        (agent-workspace-agent-name agent))
      (agent-workspace--worktree-agent-name
       (expand-file-name folder (expand-file-name agent-workspace-worktrees-directory project)))
      folder))

(defun agent-workspace-file-agent (&optional file)
  "The agent whose worktree FILE (default: the buffer's) is in, or nil."
  (when-let* ((file (or file buffer-file-name))
              (where (agent-workspace-worktree-of file)))
    (agent-workspace-agent (cadr where) (car where))))

(defun agent-workspace-project-name (root)
  "The project name of ROOT if it's an agent's worktree: \"doom · ada\"."
  (when-let* ((where (agent-workspace-worktree-of (file-name-as-directory root))))
    (format "%s · %s" (file-name-nondirectory (directory-file-name (car where))) (cadr where))))

(defun agent-workspace--projectile-name-a (fn root)
  "projectile's name for ROOT: an agent's worktree's is \"PROJECT · NAME\"."
  (or (agent-workspace-project-name root) (funcall fn root)))

(defun agent-workspace--project-name-a (fn project)
  "project.el's name for PROJECT: an agent's worktree's is \"PROJECT · NAME\"."
  (or (ignore-errors (agent-workspace-project-name (project-root project)))
      (funcall fn project)))

(with-eval-after-load 'projectile
  (advice-add 'projectile-default-project-name :around #'agent-workspace--projectile-name-a))

(with-eval-after-load 'project
  (when (fboundp 'project-name)
    (advice-add 'project-name :around #'agent-workspace--project-name-a)))

;; ====== ITS NAME SHOWN ======

(defun agent-workspace-avatar (agent &optional dimmed)
  "AGENT's avatar as text: \"▌A\", in its colour (DIMMED: the shadow
face's). AGENT may be a name only (a forgotten agent's)."
  (let ((name (if (stringp agent) agent (agent-workspace-agent-name agent))))
    (propertize (concat "▌" (upcase (substring name 0 1)))
                'face (if (or dimmed (stringp agent))
                          'shadow
                        (list :foreground (face-foreground (agent-workspace-agent-face agent) nil t)
                              :weight 'bold)))))

(defun agent-workspace--name-text (agent)
  "AGENT's name in its colour."
  (propertize (agent-workspace-agent-name agent)
              'face (list :foreground (face-foreground (agent-workspace-agent-face agent) nil t))))

(defun agent-workspace-mode-line ()
  "In a buffer of an agent's worktree, the agent for its mode line:
\"▌A ada · builder\"; a forgotten agent's name, dimmed. Else nil. A % in
it (its role's name) doubled, as itself: the mode line's text."
  (when-let* ((file buffer-file-name)
              (where (agent-workspace-worktree-of file)))
    (agent-workspace--percent-escaped
     (if-let* ((agent (agent-workspace-agent (cadr where) (car where))))
         (concat " "
                 (propertize (concat (agent-workspace-avatar agent) " " (agent-workspace--name-text agent)
                                     (propertize " · " 'face 'agent-workspace-label)
                                     (propertize (agent-workspace-agent-role agent) 'face 'agent-workspace-label))
                             'help-echo (format "%s's worktree (%s, %s): click to select %s"
                                                (agent-workspace-agent-name agent)
                                                (agent-workspace-agent-role agent)
                                                (agent-workspace-state-text agent)
                                                (agent-workspace-agent-name agent))
                             'mouse-face 'mode-line-highlight
                             'local-map agent-workspace-mode-line-map)
                 " ")
       (concat " "
               (propertize (concat (agent-workspace-avatar (cadr where)) " " (cadr where))
                           'face 'shadow
                           'help-echo (format "%s's worktree: no longer in the crew" (cadr where)))
               " ")))))

(add-to-list 'mode-line-misc-info '(:eval (agent-workspace-mode-line)))

(defun agent-workspace-mode-line-select (event)
  "Select the agent whose name was clicked (EVENT) in a mode line."
  (interactive "e")
  (when-let* ((agent (with-current-buffer (window-buffer (posn-window (event-start event)))
                       (agent-workspace-file-agent))))
    (funcall agent-workspace-select-function agent)))

(defun agent-workspace--show-session (agent)
  "Show AGENT's session, if it runs."
  (if (agent-workspace-live-p agent)
      (pop-to-buffer (agent-workspace-agent-buffer agent))
    (message "%s is %s" (agent-workspace-agent-name agent) (agent-workspace-state-text agent))))

(defun agent-workspace-tab-prefix (buffer)
  "BUFFER's tab's start if it visits a file of an agent's worktree: the
agent's avatar (a forgotten one's dimmed), then a space. Else nil."
  (when-let* ((file (buffer-file-name buffer))
              (where (agent-workspace-worktree-of file)))
    (concat (agent-workspace-avatar (or (agent-workspace-agent (cadr where) (car where)) (cadr where)))
            " ")))
