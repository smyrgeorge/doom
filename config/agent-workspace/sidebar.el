;;; $DOOMDIR/config/agent-workspace/sidebar.el -*- lexical-binding: t; -*-
;; The crew under treemacs: its agents' lanes, once you've left the app.
;; Loaded from config/agent-workspace.el, after minimap.el. No Doom here.
;;
;; THE CREW UNDER TREEMACS
;; While treemacs is shown in a frame and the project it shows has a crew
;; open in this Emacs (the app left with q), a side window under treemacs's
;; shows the minimap's left part: a line an agent, its avatar and role's
;; icon, its last minutes that fit (the newest at the right), │, its state's
;; glyph; a quiet agent, its name in the cells' place and its state in
;; words. No "where now", axis or legend; a conflict's line kept, cut to fit.
;; Its header line: CREW · PROJECT, the tally at its right. As wide as
;; treemacs (one column of side windows), as tall as its lines, at most
;; `agent-workspace-sidebar-lines' (then it scrolls); never in the crew's own
;; frame (the app has its minimap). treemacs hidden, or on a project without
;; a crew: gone. RET or a click on a lane: the app, that agent selected; on
;; its header: the app.
;;
;; Drawn again as the minimap is (as agents change, a few times a second at
;; most; once a minute while a lane has cells), only while it's shown: no
;; timer otherwise. Whether it's shown is worked out as a frame's windows
;; change (nothing while no crew is open) and as treemacs follows another
;; project.
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'text-property-search)

(declare-function treemacs-get-local-window "treemacs-scope")
(declare-function treemacs-current-workspace "treemacs-scope")
(declare-function treemacs-workspace->projects "treemacs-core-utils")
(declare-function treemacs-project->path "treemacs-core-utils")

;; ====== VARIABLES ======

(defcustom agent-workspace-sidebar t
  "Non-nil: a crew's lanes under treemacs while treemacs shows its project
\(see THE CREW UNDER TREEMACS)."
  :type 'boolean
  :group 'agent-workspace)

(defcustom agent-workspace-sidebar-lines 8
  "The most lines the crew under treemacs takes, its header line not
counted: past them it scrolls."
  :type 'natnum
  :group 'agent-workspace)

(defvar agent-workspace-sidebar-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'agent-workspace-sidebar-click)
    (define-key map [header-line mouse-1] #'agent-workspace-sidebar-click)
    map)
  "Keys under treemacs (RET: set in config/agent-workspace.el).")

(defvar-local agent-workspace--sidebar-project nil
  "Under treemacs: the crew's project.")

(defvar agent-workspace--sidebar-timers (make-hash-table :test #'equal)
  "A project's lanes under treemacs: their redraw to come.")

(defvar agent-workspace--sidebar-projects (make-hash-table :test #'equal)
  "A folder treemacs shows: its project's root, or :none (asked of git once).")

(define-derived-mode agent-workspace-sidebar-mode special-mode "Crew"
  "A crew's lanes under treemacs (see THE CREW UNDER TREEMACS)."
  (setq-local truncate-lines t
              mode-line-format nil
              tab-line-exclude t
              cursor-in-non-selected-windows nil
              header-line-format '(:eval (agent-workspace--sidebar-header))))

;; ====== ITS LINES ======

(defun agent-workspace--sidebar-cells (width)
  "How many minutes' cells a lane has in WIDTH columns: the avatar and icon
before them, \" │ \" and room for a quiet agent's state after (\"at the
desk\"); 3 at least."
  (max 3 (min agent-workspace-activity-minutes
              (- width (length agent-workspace--minimap-indent) 3 11))))

(defun agent-workspace--sidebar-lane (agent width &optional now)
  "AGENT's line under treemacs, WIDTH columns (see THE CREW UNDER
TREEMACS), fitted to them on the screen, never wrapping."
  (let* ((who (concat " " (agent-workspace--minimap-who agent)))
         (cells (agent-workspace--sidebar-cells width))
         (busy (agent-workspace--minimap-busy-p agent now))
         (line (concat who
                       (if busy
                           (mapconcat (lambda (kinds) (agent-workspace--minimap-cell agent kinds))
                                      (last (agent-workspace-activity-lane agent now) cells) "")
                         (agent-workspace--fit (agent-workspace-agent-name-text agent) (1- cells)))
                       (propertize " " 'display `(space :align-to ,(+ (string-width who) cells 1)))
                       (propertize "│" 'face 'shadow) " "
                       (if busy
                           (agent-workspace-state-glyph agent)
                         (propertize (agent-workspace-state-text agent) 'face 'shadow)))))
    (propertize (agent-workspace--minimap-fit line width) 'agent-workspace-sidebar-agent agent)))

(defun agent-workspace-sidebar-text (project width &optional now)
  "PROJECT's crew under treemacs, WIDTH columns, up to NOW: its lines."
  (let ((agents (agent-workspace--ordered project)))
    (append (mapcar (lambda (agent) (agent-workspace--sidebar-lane agent width now)) agents)
            (mapcar (lambda (conflict) (agent-workspace--minimap-conflict conflict width))
                    (agent-workspace-conflicts project))
            (and (not agents) (list (propertize "  No agents yet." 'face 'shadow))))))

(defun agent-workspace--sidebar-header ()
  "The header line under treemacs: CREW · PROJECT, its tally at the right."
  (when agent-workspace--sidebar-project
    (agent-workspace--percent-escaped
     (agent-workspace--at-right
      (concat " " (propertize "CREW" 'face 'bold) (propertize " · " 'face 'shadow)
              (file-name-nondirectory (directory-file-name agent-workspace--sidebar-project)))
      (concat (or (agent-workspace-tally (agent-workspace-agents agent-workspace--sidebar-project)) "") " ")
      (window-total-width)))))

;; ====== ITS WINDOW ======

(defun agent-workspace--sidebar-buffer (project)
  "PROJECT's lanes under treemacs (made the first time)."
  (let ((name (format " *crew · %s*" (file-name-nondirectory (directory-file-name project)))))
    (or (seq-find (lambda (buffer)
                    (equal (buffer-local-value 'agent-workspace--sidebar-project buffer) project))
                  (buffer-list))
        (with-current-buffer (generate-new-buffer name)
          (agent-workspace-sidebar-mode)
          (setq agent-workspace--sidebar-project project
                default-directory project)
          (current-buffer)))))

(defun agent-workspace--sidebar-window (frame)
  "The window showing a crew under treemacs in FRAME, or nil."
  (seq-find (lambda (window)
              (buffer-local-value 'agent-workspace--sidebar-project (window-buffer window)))
            (window-list frame 'nomini)))

(defun agent-workspace--sidebar-project-of (path)
  "The project of PATH, a folder treemacs shows, as the crews' key, or nil
\(asked of git once a folder)."
  (let ((known (gethash path agent-workspace--sidebar-projects)))
    (unless known
      (setq known (puthash path (or (ignore-errors
                                      (when-let* ((project (agent-workspace-project path)))
                                        (agent-workspace--root project)))
                                    :none)
                           agent-workspace--sidebar-projects)))
    (and (stringp known) known)))

(defun agent-workspace--sidebar-wanted (frame)
  "The project whose crew goes under treemacs in FRAME, or nil (see THE
CREW UNDER TREEMACS)."
  (when (and agent-workspace-sidebar
             (fboundp 'treemacs-get-local-window)
             (frame-live-p frame)
             (not (frame-parameter frame 'agent-workspace))
             (not (frame-parent frame))
             (> (hash-table-count agent-workspace--apps) 0))
    (with-selected-frame frame
      (when-let* ((window (treemacs-get-local-window))
                  (path (with-current-buffer (window-buffer window)
                          (ignore-errors
                            (treemacs-project->path
                             (car (treemacs-workspace->projects (treemacs-current-workspace)))))))
                  (project (agent-workspace--sidebar-project-of (file-name-as-directory path)))
                  ((agent-workspace--app project)))
        project))))

(defun agent-workspace--sidebar-height (project)
  "The total height of PROJECT's lanes' window: its header line and a line
each, at most `agent-workspace-sidebar-lines' of them."
  (1+ (max 1 (min agent-workspace-sidebar-lines
                  (+ (length (agent-workspace-agents project))
                     (length (agent-workspace-conflicts project)))))))

(defun agent-workspace--sidebar-show (frame project)
  "PROJECT's lanes under treemacs in FRAME: their window."
  (with-selected-frame frame
    (when-let* ((window (display-buffer-in-side-window
                         (agent-workspace--sidebar-buffer project)
                         `((side . ,(or (bound-and-true-p treemacs-position) 'left))
                           ;; treemacs's is -1 or 0 (as shown): under it.
                           (slot . 1)
                           (window-height . ,(agent-workspace--sidebar-height project))
                           (dedicated . t)
                           (preserve-size . (nil . t))
                           (window-parameters . ((no-delete-other-windows . t)
                                                 (no-other-window . t)
                                                 (mode-line-format . none)
                                                 (tab-line-format . none)))))))
      (set-window-fringes window 0 0)
      window)))

(defun agent-workspace--sidebar-sync (&optional frame)
  "FRAME's crew under treemacs as it should be (see THE CREW UNDER
TREEMACS): shown, for the project treemacs shows, or gone."
  (let* ((frame (or frame (selected-frame)))
         (project (agent-workspace--sidebar-wanted frame))
         (window (agent-workspace--sidebar-window frame)))
    (when (and window (not (equal (buffer-local-value 'agent-workspace--sidebar-project (window-buffer window))
                                  project)))
      (ignore-errors (delete-window window))
      (setq window nil))
    (unless (equal (frame-parameter frame 'agent-workspace-sidebar) project)
      (set-frame-parameter frame 'agent-workspace-sidebar project)
      (force-mode-line-update t))
    (when (and project (not window) (agent-workspace--sidebar-show frame project))
      (agent-workspace--sidebar-draw project))))

(defun agent-workspace--sidebar-state-h (frame)
  "FRAME's windows changed: its crew under treemacs as it should be. Nothing
while no crew is open and none is shown. In `window-state-change-functions'."
  (when (or (> (hash-table-count agent-workspace--apps) 0)
            (frame-parameter frame 'agent-workspace-sidebar))
    (agent-workspace--sidebar-sync frame)))

(add-hook 'window-state-change-functions #'agent-workspace--sidebar-state-h)

(defun agent-workspace--sidebar-sync-all (&rest _)
  "Every frame's crew under treemacs as it should be."
  (mapc #'agent-workspace--sidebar-sync (frame-list)))

;; treemacs following another project (treemacs-project-follow-mode): its
;; crew, or none.
(with-eval-after-load 'treemacs-project-follow-mode
  (advice-add 'treemacs--do-follow-project :after #'agent-workspace--sidebar-sync-all))

;; ====== DRAWING IT ======

(defun agent-workspace--sidebar-windows (project)
  "The windows showing PROJECT's lanes under treemacs."
  (seq-filter (lambda (window)
                (equal (buffer-local-value 'agent-workspace--sidebar-project (window-buffer window)) project))
              (apply #'append (mapcar (lambda (frame) (window-list frame 'nomini)) (frame-list)))))

(defun agent-workspace--sidebar-draw (project)
  "PROJECT's lanes under treemacs drawn again where they're shown, their
window as tall as they are; again at the next minute while a lane has
cells."
  (let ((project (agent-workspace--root project)))
    (agent-workspace--sidebar-cancel project)
    (when-let* ((windows (agent-workspace--sidebar-windows project)))
      (with-current-buffer (window-buffer (car windows))
        (let* ((window (car windows))
               (pos (window-point window))
               (agent (get-text-property pos 'agent-workspace-sidebar-agent))
               (lines (with-selected-frame (window-frame window)
                        (agent-workspace-sidebar-text project (max 12 (1- (window-body-width window))))))
               (inhibit-read-only t))
          (erase-buffer)
          (insert (string-join lines "\n"))
          (goto-char (point-min))
          (when-let* ((match (and agent (text-property-search-forward 'agent-workspace-sidebar-agent agent #'eq))))
            (goto-char (prop-match-beginning match)))
          (dolist (window windows)
            (set-window-point window (point))
            (set-window-start window (point-min) t)
            (let ((delta (- (agent-workspace--sidebar-height project) (window-total-height window))))
              (unless (zerop delta)
                (ignore-errors
                  (let ((window-size-fixed nil))
                    (window-preserve-size window t nil)
                    (window-resize window delta nil t)
                    (window-preserve-size window t t))))))))
      (when (seq-some (lambda (agent) (seq-some #'identity (agent-workspace-activity-lane agent)))
                      (agent-workspace-agents project))
        (agent-workspace--sidebar-later project (- 60.5 (mod (float-time) 60)))))))

(defun agent-workspace--sidebar-cancel (project)
  "PROJECT's lanes' redraw to come, cancelled."
  (when-let* ((timer (gethash project agent-workspace--sidebar-timers)))
    (cancel-timer timer))
  (remhash project agent-workspace--sidebar-timers))

(defun agent-workspace--sidebar-later (project seconds)
  "PROJECT's lanes drawn again in SECONDS, unless a redraw comes first."
  (unless (gethash project agent-workspace--sidebar-timers)
    (puthash project (run-at-time seconds nil #'agent-workspace--sidebar-draw project)
             agent-workspace--sidebar-timers)))

(defun agent-workspace--sidebar-changed-h (agent what)
  "AGENT did something, or its crew changed: its lanes under treemacs drawn
again soon, if they're shown; a crew made or gone, the frames' worked out
again. In `agent-workspace-change-functions'."
  (let ((project (agent-workspace--root (agent-workspace-agent-project agent))))
    (when (memq what '(activity state created forgotten renamed colour role closed))
      (when (agent-workspace--sidebar-windows project)
        (let ((timer (gethash project agent-workspace--sidebar-timers)))
          (when (and timer (> (- (timer-until timer (current-time))) 0.25))
            (agent-workspace--sidebar-cancel project)))
        (agent-workspace--sidebar-later project 0.25)))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--sidebar-changed-h)

(defun agent-workspace--sidebar-closing-h (project)
  "PROJECT's crew closing: its lanes' redraw cancelled; shown under treemacs
somewhere, the frames worked out again once it's gone (no timer
otherwise). In `agent-workspace-closing-functions'."
  (let ((root (agent-workspace--root project)))
    (agent-workspace--sidebar-cancel root)
    (when (seq-some (lambda (frame) (equal (frame-parameter frame 'agent-workspace-sidebar) root))
                    (frame-list))
      (run-at-time 0 nil #'agent-workspace--sidebar-sync-all))))

(add-hook 'agent-workspace-closing-functions #'agent-workspace--sidebar-closing-h)

;; ====== ITS COMMANDS ======

(defun agent-workspace--sidebar-go (project agent)
  "PROJECT's app, AGENT selected (nil: as it was)."
  (let ((default-directory project))
    (agent-workspace-open))
  (when (and agent (memq agent (agent-workspace-agents project)))
    (agent-workspace-select agent t)))

(defun agent-workspace-sidebar-open ()
  "RET under treemacs: the crew's app, the lane's agent selected."
  (interactive)
  (when agent-workspace--sidebar-project
    (agent-workspace--sidebar-go agent-workspace--sidebar-project
                                 (get-text-property (point) 'agent-workspace-sidebar-agent))))

(defun agent-workspace-sidebar-click (event)
  "A click under treemacs (EVENT): on a lane, the app with its agent
selected; on the header line, the app."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn)))
    (when (window-live-p window)
      (with-current-buffer (window-buffer window)
        (when agent-workspace--sidebar-project
          (agent-workspace--sidebar-go
           agent-workspace--sidebar-project
           (and (not (eq (posn-area posn) 'header-line))
                (posn-point posn)
                (get-text-property (posn-point posn) 'agent-workspace-sidebar-agent))))))))
