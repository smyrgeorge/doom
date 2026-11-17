;;; $DOOMDIR/config/agent-workspace/app.el -*- lexical-binding: t; -*-
;; The app: a crew's own workspace, its issues on the left, its stage beside
;; them. Loaded from config/agent-workspace.el, after stage.el. No Doom here:
;; persp-mode's own functions for workspaces (Doom's are persp-mode's), a
;; window configuration kept without it.
;;
;; Opening it (`agent-workspace-open') from inside a project switches to its
;; workspace, "crew · PROJECT" (made the first time); a project that can have
;; no crew says why (`agent-workspace-no-crew-function' offers git init); a
;; crew with no agent asks for its first (`agent-workspace-new'). Leaving it
;; (`agent-workspace-leave', q) goes back to the workspace you came from: the
;; crew goes on, its tally in the other workspaces' mode line (a click comes
;; back). Closing it (`agent-workspace-quit', Q, or its workspace killed
;; however: SPC TAB d...) closes the crew at once (core.el): every agent
;; exits; then the app's windows, buffers and workspace go.
;;
;; One timer ticks the turns' times, and only while an app is shown.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function persp-frame-switch "persp-mode")
(declare-function project-root "project")
(declare-function persp-add-new "persp-mode")
(declare-function persp-kill "persp-mode")
(declare-function persp-add-buffer "persp-mode")
(declare-function persp-get-by-name "persp-mode")
(declare-function get-current-persp "persp-mode")
(declare-function safe-persp-name "persp-mode")
(declare-function agent-workspace--go-to-hand "agent-workspace/hands")
(declare-function agent-workspace--issues-buffer "agent-workspace/issues")
(declare-function agent-workspace--issues-redraw "agent-workspace/issues")
(declare-function agent-workspace--issues-refresh "agent-workspace/issues")
(declare-function agent-workspace--issues-goto-agent "agent-workspace/issues")
(declare-function agent-workspace--issues-agent-at "agent-workspace/issues")
(declare-function agent-workspace--branches-place "agent-workspace/branches")
(declare-function agent-workspace--branches-agent-at "agent-workspace/branches")
(defvar persp-mode)
(defvar *persp-hash*)
(defvar +workspaces-main)

;; ====== VARIABLES ======

(defcustom agent-workspace-issues-width 50
  "The issue list's width, in columns."
  :type 'natnum
  :group 'agent-workspace)

(defvar agent-workspace-no-crew-function nil
  "Called with a folder whose project can have no crew, and why (a
sentence): offer what would make one (git init). nil: just say why.")

(defvar agent-workspace-open-functions nil
  "Called with a project as its app opens anew, until one returns non-nil:
start the project's saved crew again (doom-51z.5), what of it isn't
running (doom-pbk.56).")

(defvar agent-workspace-layout-functions nil
  "Called with a project when its app's layout changes: an agent selected, a
pane opened or folded.")

(defvar agent-workspace-open-issue-function nil
  "Called with an issue's id and its project's folder to show the issue.")

(defvar agent-workspace-line-map (make-sparse-keymap)
  "Keys on an agent's line (a bar, a header line): a click selects it.")

(cl-defstruct (agent-workspace--app (:constructor agent-workspace--make-app) (:copier nil))
  "A crew's app."
  project            ; the crew's project
  selected           ; the selected agent
  open               ; the agent whose pane is open, or nil: every pane folded
  (view 'stage)      ; the stage (and the room beside it), the room alone, or the branches (b) in the stage's place
  came-from          ; the workspace q goes back to (or a window configuration)
  own                ; its own buffers: the issue list, the bars, the hint
  windows            ; the stage's windows, as last laid out
  frame              ; the frame it's laid out in
  plan               ; what decided its layout
  sizes              ; its frame's windows' sizes, as laid out
  others             ; its frame's windows that aren't its own (a popup...), as last seen
  resizes            ; when it was last laid out after a resize
  tabs               ; ((AGENT TAB...)...): the tabs each agent's side area showed, the last first
  full)              ; the agent whose open pane shows its tab full size, or nil

(defvar agent-workspace--apps (make-hash-table :test #'equal)
  "The apps open: a project to its app.")

(defvar agent-workspace--timer nil
  "The timer ticking turns' times, while an app is shown.")

(defvar agent-workspace--closing nil
  "Non-nil while an app closes (its workspace killed by it).")

;; ====== ITS STATE ======

(defun agent-workspace-frame-p (&optional frame)
  "Non-nil if FRAME (the selected one) shows a crew's app: laid out by it,
tiling leaves it alone (config/tiling.el's frames left alone)."
  (and (frame-parameter frame 'agent-workspace) t))

(defun agent-workspace--app (project)
  "PROJECT's app, if it's open."
  (and project (gethash (agent-workspace--root project) agent-workspace--apps)))

(defun agent-workspace--app-buffers (project)
  "PROJECT's app's own buffers, live."
  (when-let* ((app (agent-workspace--app project)))
    (setf (agent-workspace--app-own app)
          (seq-filter #'buffer-live-p (agent-workspace--app-own app)))))

(defun agent-workspace--app-buffer-add (project buffer)
  "BUFFER one of PROJECT's app's own (killed with it, in its workspace)."
  (when-let* ((app (agent-workspace--app project)))
    (cl-pushnew buffer (agent-workspace--app-own app))
    (agent-workspace--persp-add project buffer)))

(defun agent-workspace-workspace-name (project)
  "The name of PROJECT's crew's workspace: \"crew · doom\"."
  (concat "crew · " (file-name-nondirectory (directory-file-name project))))

(defun agent-workspace--ordered (project)
  "PROJECT's agents in role order (the roles' order), then as they were
made: the stage's order, which never changes."
  (let ((roles (mapcar #'car (agent-workspace-roles project))))
    (seq-sort-by (lambda (agent) (or (cl-position (agent-workspace-agent-role agent) roles :test #'equal)
                                     (length roles)))
                 #'< (agent-workspace-agents project))))

(defun agent-workspace--here ()
  "The app the current buffer or workspace is of, or nil."
  (or (when-let* ((agent (or (agent-workspace-buffer-agent)
                             (and (window-live-p (selected-window))
                                  (window-parameter (selected-window) 'agent-workspace-pane)))))
        (agent-workspace--app (agent-workspace-agent-project agent)))
      (when-let* ((project (frame-parameter nil 'agent-workspace)))
        (agent-workspace--app project))
      (seq-find (lambda (app) (memq (current-buffer) (agent-workspace--app-own app)))
                (hash-table-values agent-workspace--apps))))

(defun agent-workspace--here-or-error ()
  "The app here (see `agent-workspace--here'), or a user error."
  (or (agent-workspace--here) (user-error "Not in a crew's app (SPC o w opens it)")))

(defun agent-workspace--shown-p (app)
  "Non-nil if APP is laid out in a live frame."
  (let ((frame (agent-workspace--app-frame app)))
    (and (frame-live-p frame)
         (equal (frame-parameter frame 'agent-workspace) (agent-workspace--app-project app)))))

(defun agent-workspace--own-window-p (window app)
  "Non-nil if WINDOW is one of APP's own: its issue list, its minimap, its
room, a pane, a bar or a side area of its stage."
  (or (window-parameter window 'agent-workspace-pane)
      (window-parameter window 'agent-workspace-room)
      (window-parameter window 'agent-workspace-side)
      (memq (window-buffer window) (agent-workspace--app-buffers (agent-workspace--app-project app)))))

(defun agent-workspace--others (app &optional frame)
  "FRAME's windows (the selected frame's) that aren't APP's own: a popup
\(the *Messages* an echo area click opens, help, *Warnings*), a window
something else split off."
  (seq-remove (lambda (window) (agent-workspace--own-window-p window app))
              (window-list frame 'nomini (frame-first-window frame))))

;; ====== ITS WORKSPACE ======

(defun agent-workspace--persp-p ()
  "Non-nil if workspaces (persp-mode's) are on."
  (and (bound-and-true-p persp-mode) (fboundp 'persp-frame-switch)))

(defun agent-workspace--switch (name)
  "The selected frame's workspace NAME (made if it isn't there), as Doom
switches."
  (unless (persp-get-by-name name *persp-hash* nil)
    (persp-add-new name))
  (persp-frame-switch name))

(defun agent-workspace--workspace ()
  "The current workspace's name, or nil."
  (and (agent-workspace--persp-p) (safe-persp-name (get-current-persp))))

(defun agent-workspace--persp-add (project buffer)
  "BUFFER in PROJECT's crew's workspace, if there is one."
  (when-let* (((agent-workspace--persp-p))
              (persp (persp-get-by-name (agent-workspace-workspace-name project)))
              ((not (symbolp persp))))
    (ignore-errors (persp-add-buffer buffer persp nil nil))))

(defun agent-workspace--crew-workspace-p (name)
  "The project whose crew's workspace NAME is, or nil."
  (seq-find (lambda (project) (equal (agent-workspace-workspace-name project) name))
            (hash-table-keys agent-workspace--apps)))

;; ====== OPENING, LEAVING, CLOSING ======

(defun agent-workspace--read-project ()
  "A project read in the minibuffer: one projectile or project.el knows."
  (let ((projects (delete-dups
                   (append (and (fboundp 'projectile-relevant-known-projects)
                                (ignore-errors (projectile-relevant-known-projects)))
                           (and (fboundp 'project-known-project-roots)
                                (ignore-errors (project-known-project-roots)))))))
    (expand-file-name (completing-read "The crew of: " projects nil t))))

(defun agent-workspace-open (&optional here)
  "Open the crew of the project you're in, in its own workspace (\"crew ·
PROJECT\"); outside a project, asked which (one not a git repository, or
without a commit, says why it has no crew). HERE (SPC o W): in the window
you're in, the workspace kept (q gives its windows back). The first time,
its first agent is asked for."
  (interactive "P")
  (let* ((dir (or (agent-workspace-project)
                  (and (fboundp 'project-current) (ignore-errors (project-root (project-current))))
                  (and (fboundp 'projectile-project-root) (ignore-errors (projectile-project-root)))
                  (agent-workspace--read-project)))
         (reason (agent-workspace-no-crew-reason dir)))
    (if reason
        (if agent-workspace-no-crew-function
            (funcall agent-workspace-no-crew-function dir reason)
          (user-error "No crew in %s: %s" (abbreviate-file-name dir) reason))
      (let* ((project (agent-workspace-project dir))
             (app (agent-workspace--app project))
             (new (not app)))
        (unless app
          (setq app (agent-workspace--make-app :project (agent-workspace--root project)))
          (puthash (agent-workspace--root project) app agent-workspace--apps))
        (let ((from (agent-workspace--workspace)))
          (if (and (agent-workspace--persp-p) (not here))
              (progn
                (unless (equal from (agent-workspace-workspace-name project))
                  (setf (agent-workspace--app-came-from app) from))
                (agent-workspace--switch (agent-workspace-workspace-name project)))
            (unless (agent-workspace--shown-p app)
              (setf (agent-workspace--app-came-from app) (current-window-configuration)))))
        (when new
          (run-hook-with-args-until-success 'agent-workspace-open-functions project))
        (agent-workspace--issues-buffer project)
        (agent-workspace-layout app)
        (agent-workspace--issues-refresh project)
        (when-let* ((window (get-buffer-window (agent-workspace--issues-buffer project))))
          (select-window window))
        ;; Its first agent, the first time.
        (unless (agent-workspace-agents project)
          (condition-case nil
              (let ((default-directory project))
                (agent-workspace-new))
            (quit (message "No agents yet: c makes one"))))
        app))))

(defun agent-workspace-open-here ()
  "Open the crew of the project you're in, in the window you're in (see
`agent-workspace-open')."
  (interactive)
  (agent-workspace-open t))

(defun agent-workspace--unmark (app)
  "APP no longer laid out in its frame."
  (let ((frame (agent-workspace--app-frame app)))
    (when (and (frame-live-p frame)
               (equal (frame-parameter frame 'agent-workspace) (agent-workspace--app-project app)))
      (set-frame-parameter frame 'agent-workspace nil))))

(defun agent-workspace-leave (&optional quiet)
  "Leave the crew's app, back where you came from. The crew goes on (said,
unless QUIET)."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (from (agent-workspace--app-came-from app)))
    (agent-workspace--unmark app)
    (cond ((window-configuration-p from)
           (set-window-configuration from)
           (setf (agent-workspace--app-came-from app) nil))
          ((agent-workspace--persp-p)
           (agent-workspace--switch (or from (bound-and-true-p +workspaces-main) "main"))))
    (unless quiet
      (message "The crew goes on: its tally is in the mode line (a click comes back)"))))

;; A FILE SHOWN FROM THE APP (opened from an agent's reply, its review): where
;; you came from (the project's own workspace), not the crew's: its stage
;; arranges itself, nothing else goes in it.
(defun agent-workspace--shown-elsewhere-p (buffer-or-name _action)
  "Non-nil if BUFFER-OR-NAME, a file's buffer, is shown from a crew's app."
  (and (agent-workspace-frame-p)
       (buffer-local-value 'buffer-file-name (get-buffer buffer-or-name))
       (agent-workspace--here)
       t))

(defun agent-workspace--display-elsewhere (buffer _alist)
  "Show BUFFER, a file, where you came from: the app left (the crew goes
on). A `display-buffer' action."
  (agent-workspace-leave t)
  (display-buffer buffer))

(defconst agent-workspace--display-rule
  '(agent-workspace--shown-elsewhere-p (agent-workspace--display-elsewhere))
  "The `display-buffer-alist' rule showing a file from a crew's app where
you came from. Doom's popups keep it too (doom.el).")

(add-to-list 'display-buffer-alist agent-workspace--display-rule)

(defun agent-workspace--close-app (project)
  "Close PROJECT's app: its windows, then the crew (every agent exits), then
its buffers. Its workspace is left to its caller."
  (when-let* ((app (agent-workspace--app project)))
    (let ((agent-workspace--closing t)
          (buffers (agent-workspace--app-buffers project)))
      (remhash (agent-workspace--root project) agent-workspace--apps)
      (agent-workspace--unmark app)
      ;; Its windows first: a dedicated window's buffer killed errs, and the
      ;; windows freed fill with other buffers. Its frame (the app had it
      ;; whole) down to one window, showing something else; elsewhere, its
      ;; buffers' windows deleted.
      (let ((ignore-window-parameters t)
            (frame (agent-workspace--app-frame app))
            (shown (append buffers (delq nil (mapcar #'agent-workspace-agent-buffer
                                                     (agent-workspace-agents project))))))
        (when (frame-live-p frame)
          (with-selected-frame frame
            (let ((window (or (seq-find (lambda (window) (not (window-parameter window 'window-side)))
                                        (window-list frame 'nomini))
                              (frame-first-window frame))))
              (select-window window)
              (dolist (parameter '(window-side header-line-format mode-line-format tab-line-format
                                               agent-workspace-pane))
                (set-window-parameter window parameter nil))
              (set-window-dedicated-p window nil)
              (delete-other-windows window)
              (when (memq (window-buffer window) shown)
                (switch-to-buffer (other-buffer (window-buffer window) t) t)))))
        (dolist (buffer shown)
          (dolist (window (get-buffer-window-list buffer nil t))
            (ignore-errors (delete-window window)))))
      (agent-workspace-close project)
      ;; Its issue list's bd commands stopped: nothing written in the project
      ;; after (an example's folder deleted with its buffers).
      (when (fboundp 'agent-workspace--issues-stop)
        (agent-workspace--issues-stop project))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer)))))
    (agent-workspace--tick)))

(defun agent-workspace-quit ()
  "Close the crew's app at once, asking nothing: every agent exits (no
process of theirs left), its windows, buffers and workspace go, and you're
back where you came from. Its worktrees and its saved crew stay."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app))
         (from (agent-workspace--app-came-from app))
         (name (agent-workspace-workspace-name project)))
    (agent-workspace--close-app project)
    (cond ((window-configuration-p from)
           (set-window-configuration from))
          ((agent-workspace--persp-p)
           (let ((agent-workspace--closing t))
             (when (equal (agent-workspace--workspace) name)
               (agent-workspace--switch (or from (bound-and-true-p +workspaces-main) "main")))
             (ignore-errors (persp-kill name)))))
    (message "The crew of %s is closed" (file-name-nondirectory (directory-file-name project)))))

(defun agent-workspace--workspace-killed-h (persp &rest _)
  "A crew's workspace killed however (SPC TAB d, C-u SPC TAB d, SPC TAB x):
its app closed, every agent exiting. In `persp-before-kill-functions'."
  (unless agent-workspace--closing
    (when-let* ((project (agent-workspace--crew-workspace-p (safe-persp-name persp))))
      (agent-workspace--close-app project))))

(defun agent-workspace--workspace-shown-h (&rest _)
  "A workspace now current: a crew's laid out again; any other frees its
frame of the app. In `persp-activated-functions'."
  (let ((project (agent-workspace--crew-workspace-p (agent-workspace--workspace))))
    (dolist (app (hash-table-values agent-workspace--apps))
      (unless (equal (agent-workspace--app-project app) project)
        (when (eq (agent-workspace--app-frame app) (selected-frame))
          (agent-workspace--unmark app))))
    (when project
      (let ((app (agent-workspace--app project)))
        (run-at-time 0 nil (lambda ()
                             (when (and (agent-workspace--app project)
                                        (equal (agent-workspace--workspace)
                                               (agent-workspace-workspace-name project)))
                               (agent-workspace-layout app))))))))

(with-eval-after-load 'persp-mode
  (add-hook 'persp-before-kill-functions #'agent-workspace--workspace-killed-h)
  (add-hook 'persp-activated-functions #'agent-workspace--workspace-shown-h))

;; ====== THE LAYOUT ======

(defun agent-workspace--plan (app)
  "What decides APP's layout: laid out anew when it changes."
  (let ((open (agent-workspace--app-open app)))
    (list (frame-width) (frame-height) (agent-workspace--app-view app)
          (agent-workspace--ordered (agent-workspace--app-project app))
          open
          (mapcar (lambda (agent) (buffer-live-p (agent-workspace-agent-buffer agent)))
                  (agent-workspace-agents (agent-workspace--app-project app)))
          ;; Its open pane's side: its tabs, the one shown, full size.
          (and open (list (agent-workspace-agent-tabs open) (agent-workspace--side-tab open)
                          (agent-workspace--full-tab open))))))

(defun agent-workspace--sizes-now (frame)
  "FRAME's windows' sizes: (FRAME-SIZE ROOT-HEIGHT WINDOWS...), ROOT-HEIGHT
its windows' height above the echo area."
  (cons (cons (frame-width frame) (frame-height frame))
        (cons (window-total-height (frame-root-window frame))
              ;; From its first window: the list starts from the selected one.
              (mapcar (lambda (window) (list (window-total-width window) (window-total-height window)))
                      (window-list frame 'nomini (frame-first-window frame))))))

(defun agent-workspace--settle (app agents)
  "APP's selection among AGENTS: the selected agent gone (or none yet), the
first selected, its pane open; an open pane whose agent went, none. Full
size only while its pane is the open one, with a tab to show."
  (unless (memq (agent-workspace--app-selected app) agents)
    (setf (agent-workspace--app-selected app) (car agents)
          (agent-workspace--app-open app) (car agents)))
  (unless (memq (agent-workspace--app-open app) agents)
    (setf (agent-workspace--app-open app) nil))
  (let ((full (agent-workspace--app-full app)))
    (unless (and full (eq full (agent-workspace--app-open app)) (agent-workspace--side-tab full))
      (setf (agent-workspace--app-full app) nil)))
  (setf (agent-workspace--app-tabs app)
        (delq nil (mapcar (lambda (entry)
                            (when-let* (((memq (car entry) agents))
                                        (tabs (seq-filter #'buffer-live-p (cdr entry))))
                              (cons (car entry) tabs)))
                          (agent-workspace--app-tabs app)))))

(defun agent-workspace--clear (app base)
  "The selected frame's windows deleted but BASE and the side windows that
aren't APP's own (a popup: the *Messages* an echo area click opens, help,
*Warnings*): those stay as they are, the app laid out in the room they
leave."
  (let ((ignore-window-parameters t)
        (kept (seq-filter (lambda (window) (window-parameter window 'window-side))
                          (agent-workspace--others app))))
    (if (not kept)
        (delete-other-windows base)
      (dolist (window (window-list nil 'nomini))
        (unless (or (eq window base) (memq window kept) (not (window-live-p window)))
          (delete-window window))))))

(defun agent-workspace-layout (&optional app)
  "APP (the one here) laid out anew in the selected frame: its issues on the
left, its stage beside them, the selected agent's pane open. A popup open
\(see `agent-workspace--clear') stays, the app laid out beside it."
  (interactive)
  (let* ((app (or app (agent-workspace--here-or-error)))
         (project (agent-workspace--app-project app))
         (agents (agent-workspace--ordered project))
         (was (current-buffer))
         ;; Shown anew (opened, come back to), not laid out again where it was.
         (anew (not (agent-workspace--shown-p app)))
         (base (or (seq-find (lambda (window) (not (window-parameter window 'window-side)))
                             (window-list nil 'nomini))
                   (frame-first-window))))
    (agent-workspace--settle app agents)
    (set-frame-parameter nil 'agent-workspace project)
    (setf (agent-workspace--app-frame app) (selected-frame))
    (agent-workspace--clear app base)
    (dolist (parameter '(window-side agent-workspace-room agent-workspace-pane agent-workspace-side))
      (set-window-parameter base parameter nil))
    (set-window-dedicated-p base nil)
    (let ((issues (display-buffer-in-side-window
                   (agent-workspace--issues-buffer project)
                   `((side . left) (slot . 0) (window-width . ,agent-workspace-issues-width)
                     (dedicated . t) (preserve-size . (t . nil))
                     (window-parameters . ((no-delete-other-windows . t)
                                           (mode-line-format . none) (tab-line-format . none)))))))
      (ignore issues))
    ;; The minimap: under the issue list.
    (when (fboundp 'agent-workspace--minimap-place)
      (agent-workspace--minimap-place app))
    (agent-workspace--hint-draw project agents)
    ;; The room: beside the stage, below it, or all of it.
    (when (fboundp 'agent-workspace--room-place)
      (setq base (agent-workspace--room-place app base)))
    (setf (agent-workspace--app-windows app)
          (cond
           ((not base) nil)
           ;; The branches to merge in the stage's place (b: branches.el).
           ((and (eq (agent-workspace--app-view app) 'branches) (fboundp 'agent-workspace--branches-place))
            (agent-workspace--branches-place app base anew)
            nil)
           (agents
            (agent-workspace--stack base agents (agent-workspace--app-open app)))
           (t (set-window-buffer base (agent-workspace--hint-buffer project))
              (dolist (parameter '(header-line-format mode-line-format tab-line-format))
                (set-window-parameter base parameter 'none))
              (list base))))
    (dolist (buffer (cons (agent-workspace--issues-buffer project)
                          (delq nil (mapcar #'agent-workspace-agent-buffer agents))))
      (agent-workspace--persp-add project buffer))
    (setf (agent-workspace--app-plan app) (agent-workspace--plan app)
          (agent-workspace--app-sizes app) (agent-workspace--sizes-now (selected-frame))
          (agent-workspace--app-others app) (agent-workspace--others app))
    (agent-workspace--issues-redraw project)
    (when-let* ((window (get-buffer-window was)))
      (select-window window))
    (agent-workspace--tick)
    app))

(defun agent-workspace--retile (app)
  "APP's stage sized again (its selection, an open pane changed): its windows
made anew where they were, the issue list and the cursor kept; laid out anew
when the stage isn't as it was."
  (let ((windows (agent-workspace--app-windows app)))
    (if (not (and (agent-workspace--shown-p app)
                  windows (cl-every #'window-live-p windows)
                  (eq (window-frame (car windows)) (selected-frame))))
        (when (agent-workspace--shown-p app) (agent-workspace-layout app))
      (let* ((was (selected-window))
             (buffer (window-buffer was))
             (agents (agent-workspace--ordered (agent-workspace--app-project app)))
             (first (car windows)))
        (let ((ignore-window-parameters t))
          (dolist (window (cdr windows))
            (when (window-live-p window) (delete-window window))))
        (agent-workspace--settle app agents)
        (if (not agents)
            (agent-workspace-layout app)
          (setf (agent-workspace--app-windows app)
                (agent-workspace--stack first agents (agent-workspace--app-open app)))
          (setf (agent-workspace--app-plan app) (agent-workspace--plan app)
                (agent-workspace--app-sizes app) (agent-workspace--sizes-now (selected-frame))
                (agent-workspace--app-others app) (agent-workspace--others app))
          (select-window (cond ((window-live-p was) was)
                               ((get-buffer-window buffer))
                               (t (or (get-buffer-window (agent-workspace--issues-buffer
                                                          (agent-workspace--app-project app)))
                                      (selected-window)))))
          (force-mode-line-update t))))))

(defun agent-workspace--redraw (app)
  "APP's bars, issue list and header lines drawn again (nothing laid out)."
  (when (agent-workspace--shown-p app)
    (dolist (window (window-list (agent-workspace--app-frame app) 'nomini))
      (when (buffer-local-value 'agent-workspace--bar-of (window-buffer window))
        (agent-workspace--bar-draw window)))
    (agent-workspace--issues-redraw (agent-workspace--app-project app))
    (force-mode-line-update t)))

(defun agent-workspace--tab-pick (agent tab)
  "TAB the one AGENT's side area shows, from its next layout; it gone, the
one shown before it."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent))))
    (setf (alist-get agent (agent-workspace--app-tabs app))
          (seq-take (cons tab (delq tab (alist-get agent (agent-workspace--app-tabs app)))) 8))))

(defun agent-workspace--canvas-changed (agent &optional canvas)
  "AGENT's CANVAS (its own, by default) shows something new: its tab the
one its side area shows, in its pane if it's open and it isn't there yet."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent)))
              (canvas (or canvas (agent-workspace--canvas agent)))
              ((memq canvas (agent-workspace-agent-tabs agent))))
    (agent-workspace--tab-pick agent canvas)
    (when (and (eq (agent-workspace--app-open app) agent)
               (agent-workspace--shown-p app)
               (not (get-buffer-window canvas (agent-workspace--app-frame app))))
      (with-selected-frame (agent-workspace--app-frame app)
        (agent-workspace--retile app)))))

;; ====== ITS CANVAS CLOSED ======
;; An agent's canvas (its own, or another: ask) closed (q kills it) or
;; emptied (cleared, its last element removed or closed by itself, a
;; question answered): its stage laid out again at once, as for a panel
;; closed (panels.el). Its side area shows the tab shown before, or its
;; next, else it's gone, its session taking the whole pane; shown full
;; size, its pane is back to its session. Never what Emacs put in its window
;; instead of a killed buffer (Doom's dashboard), or Agent UI in an emptied
;; canvas's pane (its session again). The cursor, there, goes to what's
;; there now: its next tab, else its session.

(defun agent-workspace--canvas-gone (canvas)
  "CANVAS, killed or emptied: if it's a crew's agent's (its own, or another
of its session's: ask), its stage laid out again (see above)."
  (when-let* ((agent (agent-workspace--canvas-agent canvas))
              (app (agent-workspace--app (agent-workspace-agent-project agent))))
    ;; Shown full size: the tab shown as if it were still one.
    (when (and (eq (agent-workspace--app-full app) agent)
               (eq (agent-workspace--side-tab
                    agent (let ((tabs (agent-workspace-agent-tabs agent)))
                            (if (memq canvas tabs) tabs (cons canvas tabs))))
                   canvas))
      (setf (agent-workspace--app-full app) nil))
    (run-at-time 0 nil #'agent-workspace--canvas-gone-later agent
                 (eq (window-parameter nil 'agent-workspace-side) agent))))

(defun agent-workspace--canvas-gone-later (agent focused)
  "AGENT's canvas gone, done with: its stage laid out again; FOCUSED (the
cursor was in its side area), the cursor in its side area, else in its
session."
  (agent-workspace--changed agent 'canvas)
  (when-let* ((focused)
              (app (agent-workspace--app (agent-workspace-agent-project agent)))
              ((agent-workspace--shown-p app))
              (window (or (agent-workspace--side-window agent)
                          (let ((session (agent-workspace-agent-buffer agent)))
                            (and (buffer-live-p session)
                                 (get-buffer-window session (agent-workspace--app-frame app)))))))
    (select-window window)))

(defun agent-workspace--canvas-killed-h ()
  "A canvas killed showing something: said to the stage (see above). In
its `kill-buffer-hook'."
  (when (> (buffer-size) 0)
    (agent-workspace--canvas-gone (current-buffer))))

(defun agent-workspace--canvas-made-h ()
  "A canvas made: its kill said to the stage. In `agent-ui-canvas-hook'."
  (add-hook 'kill-buffer-hook #'agent-workspace--canvas-killed-h nil t))

(defun agent-workspace--canvas-emptied-h ()
  "A canvas changed, emptied: said to the stage (see above). In
`agent-ui-changed-hook'."
  (when (= (buffer-size) 0)
    (agent-workspace--canvas-gone (current-buffer))))

(add-hook 'agent-ui-canvas-hook #'agent-workspace--canvas-made-h)
(add-hook 'agent-ui-changed-hook #'agent-workspace--canvas-emptied-h)

;; ====== A FRAME RESIZED, A BORDER DRAGGED ======

(defun agent-workspace--resized-h (frame)
  "FRAME, an app's, resized or a border dragged: laid out again, tiled; after
3 layouts in 3 seconds the sizes are taken as they are (never a loop). A
window not the app's coming (a popup) is no resize; one going, laid out
again once. In `window-size-change-functions'."
  (when-let* ((app (agent-workspace--app (frame-parameter frame 'agent-workspace))))
    (let ((now (agent-workspace--sizes-now frame))
          (was (agent-workspace--app-sizes app)))
      (unless (equal now was)
        (let ((others (agent-workspace--others app frame))
              (before (agent-workspace--app-others app)))
          (cond
           ;; A window not the app's came or went (a popup: the *Messages* an
           ;; echo area click opens, help...): Emacs took the app's rows for
           ;; it, or gave them back; nothing dragged (taken for a drag, the
           ;; layout after it deleted the popup at once). One gone: the app
           ;; laid out again, once, its windows as they were before it came.
           ((not (seq-set-equal-p others before #'eq))
            (setf (agent-workspace--app-others app) others
                  (agent-workspace--app-sizes app) now)
            (when (seq-difference before others #'eq)
              (agent-workspace--relayout-soon app frame)))
           ;; The echo area grew or shrank (a message on several lines): Emacs
           ;; gave or took its rows; nothing dragged.
           ((and (equal (car now) (car was)) (not (equal (cadr now) (cadr was))))
            (setf (agent-workspace--app-sizes app) now))
           (t (agent-workspace--resized app frame))))))))

(defun agent-workspace--resized (app frame)
  "APP's FRAME resized, or a border dragged: laid out again (see
`agent-workspace--resized-h')."
  (let ((recent (seq-filter (lambda (time) (< (- (float-time) time) 3))
                            (agent-workspace--app-resizes app))))
    (if (>= (length recent) 3)
        (setf (agent-workspace--app-sizes app) (agent-workspace--sizes-now frame))
      (setf (agent-workspace--app-resizes app) (cons (float-time) recent))
      (agent-workspace--relayout-soon app frame))))

(defun agent-workspace--relayout-soon (app frame)
  "APP laid out again in FRAME in 0.2 s (a drag's last move), if it's still
shown there and the minibuffer isn't active."
  (run-at-time 0.2 nil #'agent-workspace--relayout app frame))

(defun agent-workspace--relayout (app frame)
  "APP laid out again in FRAME, if it's still shown there and the minibuffer
isn't active (see `agent-workspace--relayout-soon')."
  (when (and (frame-live-p frame) (agent-workspace--shown-p app)
             (not (active-minibuffer-window)))
    (with-selected-frame frame
      (agent-workspace-layout app))))

(defun agent-workspace--resize-own (frame fun)
  "FUN called to resize FRAME's windows, the app's own change (the room's
compose line fitted to its text), not a border dragged: the sizes it leaves
taken as laid out, neither laid out again nor counted by
`agent-workspace--resized-h'. Not called while the sizes aren't as laid out
\(a resize not seen yet: the layout after it does it)."
  (when-let* ((app (agent-workspace--app (frame-parameter frame 'agent-workspace)))
              ((equal (agent-workspace--sizes-now frame) (agent-workspace--app-sizes app))))
    (funcall fun)
    (setf (agent-workspace--app-sizes app) (agent-workspace--sizes-now frame))))

(add-hook 'window-size-change-functions #'agent-workspace--resized-h)

;; ====== THE CREW CHANGING ======

(defun agent-workspace--changed-h (agent what)
  "AGENT's WHAT changed: its app drawn again, or laid out again (a new
agent selected, one gone, its session new); not for what it did (the minimap's).
In `agent-workspace-change-functions'."
  (when-let* (((not (eq what 'activity)))
              (app (agent-workspace--app (agent-workspace-agent-project agent))))
    (pcase what
      ('created
       (setf (agent-workspace--app-selected app) agent
             (agent-workspace--app-open app) agent)
       (run-hook-with-args 'agent-workspace-layout-functions (agent-workspace--app-project app)))
      ((or 'forgotten 'closed)
       (when (eq (agent-workspace--app-selected app) agent)
         (setf (agent-workspace--app-selected app) nil))
       (when (eq (agent-workspace--app-open app) agent)
         (setf (agent-workspace--app-open app) nil))))
    (when (and (not agent-workspace--closing) (agent-workspace--shown-p app))
      (with-selected-frame (agent-workspace--app-frame app)
        (if (or (memq what '(created forgotten session renamed))
                (not (equal (agent-workspace--plan app) (agent-workspace--app-plan app))))
            (agent-workspace--retile app)
          (agent-workspace--redraw app))))
    (when (memq what '(state created forgotten issue))
      (agent-workspace--tick))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--changed-h)

;; ====== THE TIMER ======

(defun agent-workspace--tick ()
  "The turns' times drawn again in the apps shown; the timer kept only while
one is shown with an agent working."
  (let ((shown (seq-filter #'agent-workspace--shown-p (hash-table-values agent-workspace--apps))))
    (dolist (app shown)
      (when (seq-some (lambda (agent) (agent-workspace-agent-since agent))
                      (agent-workspace-agents (agent-workspace--app-project app)))
        (agent-workspace--redraw app)))
    (if (seq-some (lambda (app)
                    (seq-some #'agent-workspace-agent-since
                              (agent-workspace-agents (agent-workspace--app-project app))))
                  shown)
        (unless (timerp agent-workspace--timer)
          (setq agent-workspace--timer (run-at-time 1 1 #'agent-workspace--tick)))
      (when (timerp agent-workspace--timer)
        (cancel-timer agent-workspace--timer))
      (setq agent-workspace--timer nil))))

;; ====== THE TALLY, ELSEWHERE ======

(defvar agent-workspace-tally-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'agent-workspace-tally-open)
    map)
  "Keys on a crew's tally in a mode line.")

(defun agent-workspace--tally-mode-line ()
  "Each open crew's tally but the one shown in this frame: a click opens it.
A % in it (its project's name) doubled, as itself: the mode line's text."
  (let (parts)
    (dolist (app (hash-table-values agent-workspace--apps))
      (let ((project (agent-workspace--app-project app)))
        (unless (equal (frame-parameter nil 'agent-workspace) project)
          (push (propertize (concat " " (agent-workspace-workspace-name project)
                                    (if-let* ((tally (agent-workspace-tally (agent-workspace-agents project))))
                                        (concat " " tally) "")
                                    " ")
                            'agent-workspace-project project
                            'local-map agent-workspace-tally-map 'mouse-face 'mode-line-highlight
                            'help-echo "The crew: click to go there")
                parts))))
    (agent-workspace--percent-escaped (apply #'concat parts))))

(add-to-list 'mode-line-misc-info '(:eval (agent-workspace--tally-mode-line)) t)

(defun agent-workspace-tally-open (event)
  "Open the crew whose tally was clicked (EVENT)."
  (interactive "e")
  (let* ((posn (event-start event))
         (text (posn-string posn))
         (project (and text (get-text-property (cdr text) 'agent-workspace-project (car text)))))
    (when project
      (let ((default-directory project))
        (agent-workspace-open)))))

;; ====== SELECTING ======

(defun agent-workspace-select (agent &optional go)
  "Select AGENT in its app: its pane opens, the others fold, the issue list's
cursor on its issue; done, it's seen. GO: the cursor in its pane."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent))))
    (setf (agent-workspace--app-selected app) agent
          (agent-workspace--app-open app) agent)
    (run-hook-with-args 'agent-workspace-layout-functions (agent-workspace--app-project app))
    (agent-workspace-seen agent)
    (agent-workspace--issues-goto-agent agent)
    (when (agent-workspace--shown-p app)
      (with-selected-frame (agent-workspace--app-frame app)
        (agent-workspace--retile app)
        (agent-workspace--redraw app)
        (when go
          (when-let* ((window (or (get-buffer-window (agent-workspace-agent-buffer agent))
                                  (get-buffer-window (agent-workspace--bar-buffer agent)))))
            (select-window window)))))))

(defun agent-workspace--select-from-anywhere (agent)
  "Select AGENT (a click on its name in a file's mode line): its crew's app
opened, its pane open, the cursor in it."
  (let ((default-directory (agent-workspace-agent-project agent)))
    (agent-workspace-open))
  (agent-workspace-select agent t))

(setq agent-workspace-select-function #'agent-workspace--select-from-anywhere)

(defun agent-workspace--side-agent (buffer)
  "The agent whose canvas or panel BUFFER is, or nil."
  (or (agent-workspace--canvas-agent buffer)
      (and (fboundp 'agent-workspace--panel-agent) (agent-workspace--panel-agent buffer))))

(defun agent-workspace--window-agent (window)
  "The agent whose line, pane or side area WINDOW shows, or nil."
  (when (window-live-p window)
    (or (with-current-buffer (window-buffer window)
          (or agent-workspace--bar-of (agent-workspace-buffer-agent)))
        (window-parameter window 'agent-workspace-side))))

(defun agent-workspace--current ()
  "The agent the command is about: the bar's, the pane's, the issue's, the
minimap's lane's or the branch's at point, the canvas's or panel's, else the
selected one."
  (or (buffer-local-value 'agent-workspace--bar-of (current-buffer))
      (agent-workspace-buffer-agent)
      (get-text-property (point) 'agent-workspace-minimap-agent)
      (and (fboundp 'agent-workspace--issues-agent-at) (agent-workspace--issues-agent-at))
      (and (fboundp 'agent-workspace--branches-agent-at) (agent-workspace--branches-agent-at))
      (agent-workspace--side-agent (current-buffer))
      (when-let* ((app (agent-workspace--here)))
        (agent-workspace--app-selected app))
      (user-error "No agent here")))

(defun agent-workspace--step (n)
  "The agent N after the current one, in the stage's order (wrapping)."
  (let* ((agent (agent-workspace--current))
         (agents (agent-workspace--ordered (agent-workspace-agent-project agent)))
         (i (or (cl-position agent agents) 0)))
    (nth (mod (+ i n) (length agents)) agents)))

;; ====== THE COMMANDS ======

(defun agent-workspace-next (&optional n)
  "The next agent (N: that many) selected, the cursor in its pane."
  (interactive "p")
  (agent-workspace-select (agent-workspace--step (or n 1)) t))

(defun agent-workspace-previous (&optional n)
  "The previous agent selected, the cursor in its pane."
  (interactive "p")
  (agent-workspace-next (- (or n 1))))

(defun agent-workspace-go ()
  "The agent here selected, the cursor in its pane."
  (interactive)
  (agent-workspace-select (agent-workspace--current) t))

(defun agent-workspace-toggle ()
  "Open the agent's pane (it's selected), or fold it (every pane folded)."
  (interactive)
  (let* ((agent (agent-workspace--current))
         (app (agent-workspace--app (agent-workspace-agent-project agent))))
    (if (eq (agent-workspace--app-open app) agent)
        (progn (setf (agent-workspace--app-open app) nil)
               (run-hook-with-args 'agent-workspace-layout-functions (agent-workspace--app-project app))
               (agent-workspace--retile app)
               (when-let* ((window (get-buffer-window (agent-workspace--bar-buffer agent))))
                 (select-window window)))
      (agent-workspace-select agent (not (derived-mode-p 'agent-workspace-issues-mode))))))

(defun agent-workspace-line-click (event)
  "A click on an agent's line (a bar, a header line): it's selected, the
cursor in its pane."
  (interactive "e")
  (when-let* ((agent (agent-workspace--window-agent (posn-window (event-start event)))))
    (agent-workspace-select agent t)))

(defun agent-workspace-line-menu (event)
  "mouse-3 on an agent's line: its actions, as a menu."
  (interactive "e")
  (let* ((window (posn-window (event-start event)))
         (agent (agent-workspace--window-agent window))
         (choice (and agent
                      (x-popup-menu
                       event
                       (list (agent-workspace-agent-name agent)
                             (cons ""
                                   '(("Interrupt" . agent-workspace-interrupt-here)
                                     ("Sleep or wake" . agent-workspace-sleep-here)
                                     ("Loop on or off" . agent-workspace-loop-here)
                                     ("Restart fresh" . agent-workspace-restart-here)
                                     ("Kill (gone home)" . agent-workspace-kill-here)
                                     ("Edit..." . agent-workspace-edit)
                                     ("Its branch's changes" . agent-workspace-review-here)
                                     ("Merge its branch" . agent-workspace-merge-here)
                                     ("Its issue" . agent-workspace-issue-here))))))))
    (when choice
      (with-current-buffer (window-buffer window)
        (call-interactively choice)))))

;; Here, not in the defvar: loading the file again sets them again.
(define-key agent-workspace-line-map [header-line mouse-1] #'agent-workspace-line-click)
(define-key agent-workspace-line-map [mouse-1] #'agent-workspace-line-click)
(define-key agent-workspace-line-map [header-line mouse-3] #'agent-workspace-line-menu)
(define-key agent-workspace-line-map [mouse-3] #'agent-workspace-line-menu)

(defun agent-workspace-interrupt-here ()
  "Interrupt the agent's turn."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (if (not (memq (agent-workspace-agent-state agent) '(working hand)))
        (message "%s isn't working" (agent-workspace-agent-name agent))
      (agent-workspace-interrupt agent))))

(defun agent-workspace-kill-here ()
  "Kill the agent's session: it's gone home (r brings it back)."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (when (y-or-n-p (format "Send %s home (its session ends)? " (agent-workspace-agent-name agent)))
      (agent-workspace-kill agent))))

(defun agent-workspace-restart-here ()
  "Restart the agent, with a fresh session."
  (interactive)
  (agent-workspace-restart (agent-workspace--current)))

(defun agent-workspace-sleep-here ()
  "Put the agent to sleep, or wake it (asleep or gone home)."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (if (memq (agent-workspace-agent-state agent) '(asleep home))
        (agent-workspace-wake agent)
      (agent-workspace-sleep agent))))

(defun agent-workspace-review-here ()
  "The agent's branch's changes (magit), where you came from (the app
left, the crew going on): the one it's on, or which of its holding work
you choose (`agent-workspace-read-branch')."
  (interactive)
  (let* ((agent (agent-workspace--current))
         (branch (agent-workspace-read-branch agent "Review %s's branch: ")))
    (when (agent-workspace-frame-p) (agent-workspace-leave t))
    (agent-workspace-review agent branch)))

(defun agent-workspace-merge-here ()
  "Merge the agent's branch into your checkout: the one it's on, or which of
its holding work you choose (`agent-workspace-read-branch')."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (agent-workspace-merge agent (agent-workspace-read-branch agent "Merge %s's branch: "))))

(defun agent-workspace-issue-here ()
  "The issue the agent works on."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (if-let* ((issue (agent-workspace-agent-issue agent)))
        (if agent-workspace-open-issue-function
            (funcall agent-workspace-open-issue-function issue (agent-workspace-agent-project agent))
          (message "%s: %s" issue (or (agent-workspace-agent-issue-title agent) "")))
      (message "%s has no issue" (agent-workspace-agent-name agent)))))

(defun agent-workspace--tabs-or-error (agent)
  "AGENT's tabs (its canvas, its panels), or a user error: it has none."
  (or (agent-workspace-agent-tabs agent)
      (user-error "%s shows nothing: its canvas is empty, it has no panel" (agent-workspace-agent-name agent))))

(defun agent-workspace--app-shown (agent)
  "AGENT's crew's app, shown (opened if it isn't)."
  (let ((app (agent-workspace--app (agent-workspace-agent-project agent))))
    (if (and app (agent-workspace--shown-p app))
        app
      (let ((default-directory (agent-workspace-agent-project agent)))
        (agent-workspace-open)))))

(defun agent-workspace--side-show (agent &optional tab)
  "AGENT's side area showing TAB (else the one it shows), its pane open (its
crew's app opened if it isn't shown), the cursor in it."
  (agent-workspace--app-shown agent)
  (when tab
    (agent-workspace--tab-pick agent tab))
  (agent-workspace-select agent)
  (when-let* ((window (agent-workspace--side-window agent)))
    (select-window window)))

(defun agent-workspace-panels-here ()
  "The agent's canvas and panels, in its pane (opened): the cursor in the
one shown; in it already, the next one shown."
  (interactive)
  (let* ((agent (agent-workspace--current))
         (tabs (agent-workspace--tabs-or-error agent))
         (window (agent-workspace--side-window agent)))
    (agent-workspace--side-show
     agent (and window (eq window (selected-window))
                (or (cadr (memq (window-buffer window) tabs)) (car tabs))))))

(defun agent-workspace-full-here ()
  "The agent's canvas or panel shown full size, in its pane's whole room,
the cursor in it; full size already: back beside its session."
  (interactive)
  (let* ((agent (agent-workspace--current))
         (app (progn (agent-workspace--tabs-or-error agent)
                     (agent-workspace--app-shown agent))))
    (setf (agent-workspace--app-full app)
          (unless (and (eq (agent-workspace--app-full app) agent)
                       (eq (agent-workspace--app-open app) agent))
            agent))
    (agent-workspace--side-show agent)))

(defun agent-workspace--session-shown (agent)
  "AGENT's pane back to its session (beside its side area) if it showed a
tab full size: what it asks is there."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent))))
    (when (eq (agent-workspace--app-full app) agent)
      (setf (agent-workspace--app-full app) nil))))

(defun agent-workspace-tab-click (event)
  "A click on a tab of an agent's side area (EVENT): it's shown, the cursor
in it."
  (interactive "e")
  (let* ((posn (event-start event))
         (text (posn-string posn))
         (tab (and text (get-text-property (cdr text) 'agent-workspace-tab (car text))))
         (agent (agent-workspace--window-agent (posn-window posn))))
    (when (and agent (buffer-live-p tab))
      (agent-workspace--side-show agent tab))))

;; Here, not in the defvar (stage.el's): loading the file again sets them again.
(define-key agent-workspace-tab-map [header-line mouse-1] #'agent-workspace-tab-click)
(define-key agent-workspace-tab-map [mouse-1] #'agent-workspace-tab-click)

(defun agent-workspace-new-here (&optional more)
  "Make a new agent in this crew (MORE, C-u: its model, mode and colour too).
On a ready issue: its role offered first, the issue its first message."
  (interactive "P")
  (let* ((app (agent-workspace--here-or-error))
         (default-directory (agent-workspace--app-project app))
         (issue (and (derived-mode-p 'agent-workspace-issues-mode)
                     (get-text-property (point) 'agent-workspace-issue))))
    (agent-workspace-new more
                         (or (plist-get issue :role)
                             (get-text-property (point) 'agent-workspace-role))
                         (plist-get issue :id) (plist-get issue :title) (plist-get issue :type))))

(defun agent-workspace-edit ()
  "Change the agent: its name, colour, role, permission mode or model."
  (interactive)
  (let* ((agent (agent-workspace--current))
         (name (agent-workspace-agent-name agent))
         (project (agent-workspace-agent-project agent))
         (what (completing-read (format "Change %s's: " name) '("name" "colour" "role" "mode" "model") nil t)))
    (pcase what
      ("name" (agent-workspace-rename agent (read-string (format "Rename %s to: " name))))
      ("colour" (agent-workspace-recolour
                 agent (completing-read "Colour: " agent-workspace-colours nil t nil nil
                                        (agent-workspace-agent-colour agent))))
      ("role"
       (agent-workspace-set-role agent (agent-workspace-read-role project (agent-workspace-agent-role agent))))
      ((or "mode" "model")
       (let* ((more (agent-workspace--read-more project (agent-workspace-agent-role agent))))
         (if (equal what "mode")
             (setf (agent-workspace-agent-mode agent) (plist-get more :mode))
           (setf (agent-workspace-agent-model agent) (plist-get more :model)))
         (agent-workspace--changed agent 'settings)
         (when (and (agent-workspace-live-p agent)
                    (y-or-n-p (format "Restart %s for it to take effect? " name)))
           (agent-workspace-restart agent)))))))

(defun agent-workspace-jump ()
  "The agent whose name starts with the letter typed, selected."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (c (downcase (read-char "Agent's initial: ")))
         (agent (seq-find (lambda (agent) (eq (aref (agent-workspace-agent-name agent) 0) c))
                          (agent-workspace--ordered (agent-workspace--app-project app)))))
    (if agent
        (agent-workspace-select agent (not (derived-mode-p 'agent-workspace-issues-mode)))
      (message "No agent's name starts with %c" c))))

(defun agent-workspace-next-hand ()
  "The next raised hand, across the crew: its agent selected, the cursor on
what it asks."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (agents (agent-workspace--ordered (agent-workspace--app-project app)))
         (from (1+ (or (cl-position (agent-workspace--app-selected app) agents) -1)))
         (agent (seq-find (lambda (agent) (eq (agent-workspace-agent-state agent) 'hand))
                          (append (nthcdr from agents) (seq-take agents from)))))
    (if (not agent)
        (message "No hand raised")
      (agent-workspace--go-to-hand agent)
      (message "%s %s" (agent-workspace-agent-name agent) (agent-workspace-state-text agent)))))

(defun agent-workspace-help ()
  "The app's keys (not those of what's off: the inbox, agents talking)."
  (interactive)
  (message "%s" (substitute-command-keys
                 (concat "\\<agent-workspace-bar-mode-map>j/k agents · RET its pane · TAB open/fold · c new · i interrupt · K kill · r restart · s sleep/wake · e edit · d its changes · M merge · b branches to merge · v canvas, panels · V full size · I issue · L loop · a next hand · f+initial · m minimap · "
                         (if (or (bound-and-true-p agent-workspace-outside-events)
                                 (bound-and-true-p agent-workspace-agents-talk))
                             "P pause events · E inbox · "
                           "")
                         (if (bound-and-true-p agent-workspace-agents-talk) "T talk · " "")
                         "gr lay out · q leave · Q close"))))
