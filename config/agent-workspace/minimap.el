;;; $DOOMDIR/config/agent-workspace/minimap.el -*- lexical-binding: t; -*-
;; The crew's minimap: what each agent did, minute by minute, under the issue
;; list. Loaded from config/agent-workspace.el, after activity.el. No Doom
;; here.
;;
;; A lane an agent (activity.el's data): its avatar, its last
;; `agent-workspace-activity-minutes' minutes a cell each (read, edit, run, a
;; hand raised: what it did most then), then its state's glyph and where it
;; is now (its file and line, what it asks you). The agents with nothing done
;; in those minutes (at the desk, asleep) on one line under the lanes; a file
;; two agents change on a line of its own (⚠ ada + ken: FILE). One column a
;; cell, the same glyphs in the GUI and a terminal; faces only.
;;
;; Drawn again as the agents do things, a few times a second at most, and once
;; a minute (its cells move on) while a lane has something; only while it's
;; shown: no timer otherwise. Shown or hidden with m, kept in crew.json's layout.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'text-property-search)

(declare-function agent-ui-even-glyphs "agent-ui/core")
(declare-function agent-ui-blend "agent-ui/core")
(declare-function agent-ui-color "agent-ui/core")
(declare-function agent-ui-background "agent-ui/core")

;; ====== VARIABLES ======

(defcustom agent-workspace-minimap t
  "Non-nil: a crew's app shows its minimap (under the issue list) until m
hides it; crew.json keeps what you chose."
  :type 'boolean
  :group 'agent-workspace)

(defcustom agent-workspace-minimap-height 12
  "The minimap's height, in lines."
  :type 'natnum
  :group 'agent-workspace)

(defvar agent-workspace-minimap-glyphs
  '((read . "⌕") (edit . "✎") (run . "▶") (asked . "!") (none . "·"))
  "A cell's glyph by what the agent did in its minute, one column each.")

(defconst agent-workspace--minimap-order '(asked edit run read)
  "What a minute's cell shows when the agent did several things: the first.")

(defvar agent-workspace-minimap-mode-map (make-sparse-keymap)
  "Keys in the minimap (set in config/agent-workspace.el).")

(defvar agent-workspace--minimap-shown (make-hash-table :test #'equal)
  "A project's minimap shown (t) or hidden (:hidden); else as
`agent-workspace-minimap' says.")

(defvar agent-workspace--minimap-timers (make-hash-table :test #'equal)
  "A project's minimap's redraw to come (soon, or at the next minute).")

(defvar-local agent-workspace--minimap-project nil "In the minimap: its project.")

(define-derived-mode agent-workspace-minimap-mode special-mode "Minimap"
  "A crew's minimap: what each agent did, minute by minute."
  (setq-local truncate-lines t
              mode-line-format nil
              tab-line-exclude t
              cursor-in-non-selected-windows nil
              header-line-format '(:eval (agent-workspace--minimap-header))))

;; ====== ITS BUFFER, ITS WINDOW ======

(defun agent-workspace--minimap-buffer (project)
  "PROJECT's minimap (made the first time)."
  (let ((root (agent-workspace--root project)))
    (or (seq-find (lambda (buffer) (equal (buffer-local-value 'agent-workspace--minimap-project buffer) root))
                  (agent-workspace--app-buffers project))
        (with-current-buffer (generate-new-buffer
                              (format "*minimap · %s*" (file-name-nondirectory (directory-file-name root))))
          (agent-workspace-minimap-mode)
          (setq agent-workspace--minimap-project root
                default-directory root)
          (agent-workspace--app-buffer-add project (current-buffer))
          (current-buffer)))))

(defun agent-workspace-minimap-shown-p (project)
  "Non-nil if PROJECT's app shows its minimap (see `agent-workspace-minimap')."
  (pcase (gethash (agent-workspace--root project) agent-workspace--minimap-shown)
    ('nil agent-workspace-minimap)
    (:hidden nil)
    (_ t)))

(defun agent-workspace--minimap-set (project shown)
  "PROJECT's minimap SHOWN or not."
  (puthash (agent-workspace--root project) (if shown t :hidden) agent-workspace--minimap-shown))

(defun agent-workspace--minimap-window (project)
  "The window showing PROJECT's minimap in its app, or nil."
  (when-let* ((app (agent-workspace--app project))
              ((agent-workspace--shown-p app))
              (buffer (seq-find (lambda (buffer)
                                  (equal (buffer-local-value 'agent-workspace--minimap-project buffer)
                                         (agent-workspace--root project)))
                                (agent-workspace--app-buffers project))))
    (get-buffer-window buffer (agent-workspace--app-frame app))))

(defun agent-workspace--minimap-place (app)
  "APP's minimap under its issue list, if it's shown and there's room for it
\(twice its height): drawn. Called as APP is laid out."
  (let ((project (agent-workspace--app-project app)))
    (when (and (agent-workspace-minimap-shown-p project)
               (>= (window-total-height (frame-root-window)) (* 2 agent-workspace-minimap-height)))
      (when-let* ((window (display-buffer-in-side-window
                           (agent-workspace--minimap-buffer project)
                           `((side . left) (slot . 1) (window-height . ,agent-workspace-minimap-height)
                             (dedicated . t) (preserve-size . (nil . t))
                             (window-parameters . ((no-delete-other-windows . t)
                                                   (mode-line-format . none) (tab-line-format . none)))))))
        (set-window-fringes window 0 0)
        (agent-workspace--minimap-draw project)))))

;; ====== ITS LINES ======

(defun agent-workspace--minimap-cell (agent kinds)
  "AGENT's cell for a minute it did KINDS in: a glyph, in its colour (read
dimmer, edit bold), a hand raised in the warning face."
  (let* ((kind (seq-find (lambda (kind) (memq kind kinds)) agent-workspace--minimap-order))
         (glyph (alist-get (or kind 'none) agent-workspace-minimap-glyphs))
         (fg (agent-workspace--fg agent)))
    (propertize glyph 'face
                (pcase kind
                  ('nil 'shadow)
                  ('asked '(warning bold))
                  ('edit (list fg 'bold))
                  ('run fg)
                  ('read (if (fboundp 'agent-ui-blend)
                             (list :foreground (agent-ui-blend (agent-ui-background)
                                                               (plist-get fg :foreground) 0.6))
                           fg))))))

(defun agent-workspace--minimap-where (agent width)
  "Where AGENT is now, WIDTH columns at most: its file and line (the file cut
on the left), what it asks you, else its state in words."
  (let ((location (plist-get (agent-workspace-activity agent) :location))
        (state (agent-workspace-agent-state agent)))
    (cond
     ((eq state 'hand)
      (agent-workspace--fit (propertize (agent-workspace-state-text agent) 'face 'warning) width))
     ((and location (memq state '(working done desk)))
      (let* ((line (and (cdr location) (propertize (format ":%s" (cdr location)) 'face 'shadow)))
             (room (- width (if line (string-width line) 0)))
             (file (car location)))
        (concat (if (> (string-width file) room)
                    (concat "…" (substring file (- (length file) (max 0 (1- room)))))
                  file)
                (or line ""))))
     (t (agent-workspace--fit (propertize (agent-workspace-state-text agent) 'face 'shadow) width)))))

(defun agent-workspace--minimap-lane (agent width &optional now)
  "AGENT's lane, WIDTH columns: avatar, its minutes up to NOW, │, its
state's glyph, where it is."
  (let* ((cells (mapconcat (lambda (kinds) (agent-workspace--minimap-cell agent kinds))
                           (agent-workspace-activity-lane agent now) ""))
         (head (concat " " (agent-workspace-agent-avatar agent) " " cells " "
                       (propertize "│" 'face 'shadow) " "
                       (agent-workspace-state-glyph agent) " ")))
    (propertize (concat head (agent-workspace--minimap-where agent (max 6 (- width (string-width head)))))
                'agent-workspace-minimap-agent agent)))

(defun agent-workspace--minimap-busy-p (agent &optional now)
  "Non-nil if AGENT gets a lane: it did something in the last minutes, or
it's working, its hand raised, stuck."
  (or (memq (agent-workspace-agent-state agent) '(working hand stuck))
      (seq-some #'identity (agent-workspace-activity-lane agent now))))

(defun agent-workspace--minimap-quiet (agents width)
  "AGENTS with nothing done in the last minutes, on one line: each its
avatar, name and state's glyph."
  (agent-workspace--fit
   (concat " " (propertize "quiet " 'face 'shadow)
           (mapconcat (lambda (agent)
                        (propertize (concat (agent-workspace-agent-avatar agent) " "
                                            (agent-workspace-agent-name-text agent) " "
                                            (string-trim-right (agent-workspace-state-glyph agent)))
                                    'agent-workspace-minimap-agent agent))
                      agents "  "))
   width))

(defun agent-workspace--minimap-conflict (conflict width)
  "CONFLICT (FILE AGENT...), a file several agents change: its line."
  (propertize
   (agent-workspace--fit
    (concat " " (propertize "⚠" 'face 'warning) " "
            (mapconcat #'agent-workspace-agent-name-text (cdr conflict) (propertize " + " 'face 'shadow))
            (propertize ": " 'face 'shadow)
            (propertize (car conflict) 'face 'warning))
    width)
   'agent-workspace-minimap-conflict conflict))

(defun agent-workspace--minimap-axis ()
  "The line under the lanes: how long ago its cells are (-15m, -5m, now),
a mark left out where it would touch the one before."
  (let* ((n agent-workspace-activity-minutes)
         (cells (make-string n ?\s))
         (free 0))
    (pcase-dolist (`(,at . ,text) `((0 . ,(format "-%dm" n)) (,(- n 7) . "-5m") (,(- n 3) . "now")))
      (when (and (>= at free) (<= (+ at (length text)) n))
        (setq cells (concat (substring cells 0 at) text (substring cells (+ at (length text))))
              free (+ at (length text) 1))))
    (propertize (concat "    " cells) 'face 'shadow)))

(defun agent-workspace--minimap-legend ()
  "What its glyphs say."
  (concat "    "
          (mapconcat (lambda (entry)
                       (propertize (format "%s %s" (alist-get (car entry) agent-workspace-minimap-glyphs) (cdr entry))
                                   'face 'shadow))
                     '((read . "read") (edit . "edit") (run . "run") (asked . "asks you"))
                     "  ")))

(defun agent-workspace--minimap-header ()
  "The minimap's header line."
  (when agent-workspace--minimap-project
    (string-replace
     "%" "%%"
     (agent-workspace--at-right
      (concat " " (propertize "CREW" 'face 'bold) "  "
              (propertize (format "%d minutes" agent-workspace-activity-minutes) 'face 'shadow))
      (concat (propertize "where now" 'face 'shadow) " ")
      (window-total-width)))))

(defun agent-workspace-minimap-text (project width &optional now)
  "PROJECT's minimap, WIDTH columns, up to NOW: its lines."
  (let* ((agents (agent-workspace--ordered project))
         (busy (seq-filter (lambda (agent) (agent-workspace--minimap-busy-p agent now)) agents))
         (quiet (seq-difference agents busy))
         (conflicts (agent-workspace-conflicts project)))
    (append (mapcar (lambda (agent) (agent-workspace--minimap-lane agent width now)) busy)
            (and quiet (list (agent-workspace--minimap-quiet quiet width)))
            (mapcar (lambda (conflict) (agent-workspace--minimap-conflict conflict width)) conflicts)
            (and busy (list (agent-workspace--minimap-axis) (agent-workspace--minimap-legend)))
            (and (not agents) (list (propertize "  No agents yet." 'face 'shadow))))))

;; ====== DRAWING IT ======

(defun agent-workspace--minimap-draw (project)
  "PROJECT's minimap drawn again, if it's shown: the cursor on the line it
was on; drawn again at the next minute while a lane has something."
  (agent-workspace--minimap-cancel project)
  (when-let* ((window (agent-workspace--minimap-window project)))
    (with-current-buffer (window-buffer window)
      (let* ((pos (window-point window))
             (agent (get-text-property pos 'agent-workspace-minimap-agent))
             (line (line-number-at-pos pos))
             (lines (agent-workspace-minimap-text project (max 20 (1- (window-body-width window)))))
             (inhibit-read-only t))
        (erase-buffer)
        (insert (string-join lines "\n"))
        (when (fboundp 'agent-ui-even-glyphs)
          (let ((text (buffer-string)))
            (erase-buffer)
            (insert (agent-ui-even-glyphs text))))
        (goto-char (point-min))
        (if-let* ((match (and agent (text-property-search-forward 'agent-workspace-minimap-agent agent #'eq))))
            (goto-char (prop-match-beginning match))
          (forward-line (1- line)))
        (set-window-point window (point))
        (set-window-start window (point-min) t)))
    (when (seq-some (lambda (agent) (seq-some #'identity (agent-workspace-activity-lane agent)))
                    (agent-workspace-agents project))
      (agent-workspace--minimap-later project (- 60.5 (mod (float-time) 60))))))

(defun agent-workspace--minimap-cancel (project)
  "PROJECT's minimap's redraw to come, cancelled."
  (let ((key (agent-workspace--root project)))
    (when-let* ((timer (gethash key agent-workspace--minimap-timers)))
      (cancel-timer timer))
    (remhash key agent-workspace--minimap-timers)))

(defun agent-workspace--minimap-later (project seconds)
  "PROJECT's minimap drawn again in SECONDS, unless a redraw comes first."
  (let ((key (agent-workspace--root project)))
    (unless (gethash key agent-workspace--minimap-timers)
      (puthash key (run-at-time seconds nil #'agent-workspace--minimap-draw key)
               agent-workspace--minimap-timers))))

(defun agent-workspace--minimap-soon (project)
  "PROJECT's minimap drawn again in a moment (a burst of activity: once), if
it's shown."
  (when (agent-workspace--minimap-window project)
    (let* ((key (agent-workspace--root project))
           (timer (gethash key agent-workspace--minimap-timers)))
      ;; A redraw at the next minute brought forward.
      (when (and timer (> (- (timer-until timer (current-time))) 0.25))
        (cancel-timer timer)
        (remhash key agent-workspace--minimap-timers))
      (agent-workspace--minimap-later project 0.25))))

(defun agent-workspace--minimap-changed-h (agent what)
  "AGENT did something, or its state changed: its minimap drawn again soon.
In `agent-workspace-change-functions'."
  (when (memq what '(activity state created forgotten renamed colour closed))
    (agent-workspace--minimap-soon (agent-workspace-agent-project agent))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--minimap-changed-h)
(add-hook 'agent-workspace-closing-functions #'agent-workspace--minimap-cancel)

;; ====== ITS COMMANDS ======

(defun agent-workspace-minimap-toggle ()
  "Show or hide the crew's minimap, under the issue list (m)."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app))
         (shown (not (agent-workspace-minimap-shown-p project))))
    (agent-workspace--minimap-set project shown)
    (run-hook-with-args 'agent-workspace-layout-functions project)
    (agent-workspace-layout app)
    (message (if shown "The minimap: m hides it" "The minimap hidden: m shows it"))))

(defun agent-workspace--minimap-at ()
  "The lane's agent or the conflict at point: (agent . AGENT), (conflict .
\(FILE AGENT...)), or a user error."
  (or (when-let* ((agent (get-text-property (point) 'agent-workspace-minimap-agent)))
        (cons 'agent agent))
      (when-let* ((conflict (get-text-property (point) 'agent-workspace-minimap-conflict)))
        (cons 'conflict conflict))
      (user-error "No agent on this line")))

(defun agent-workspace-minimap-next (&optional n)
  "The next line with an agent or a conflict (N: that many; back if negative)."
  (interactive "p")
  (let ((n (or n 1)))
    (dotimes (_ (abs n))
      (let ((start (point)))
        (forward-line (if (< n 0) -1 1))
        (while (and (not (if (< n 0) (bobp) (eobp)))
                    (not (or (get-text-property (point) 'agent-workspace-minimap-agent)
                             (get-text-property (point) 'agent-workspace-minimap-conflict))))
          (forward-line (if (< n 0) -1 1)))
        (unless (or (get-text-property (point) 'agent-workspace-minimap-agent)
                    (get-text-property (point) 'agent-workspace-minimap-conflict))
          (goto-char start))))))

(defun agent-workspace-minimap-previous (&optional n)
  "The previous line with an agent or a conflict."
  (interactive "p")
  (agent-workspace-minimap-next (- (or n 1))))

(defun agent-workspace-minimap-select ()
  "The lane's agent selected, its pane open, the cursor in it; on a
conflict, both agents' changes to its file."
  (interactive)
  (pcase (agent-workspace--minimap-at)
    (`(agent . ,agent) (agent-workspace-select agent t))
    (`(conflict . ,conflict) (agent-workspace-minimap-conflict-diff conflict))))

(defun agent-workspace-minimap-open ()
  "The file the lane's agent is in, in its worktree, at its line (where you
came from: the app left, the crew going on)."
  (interactive)
  (pcase (agent-workspace--minimap-at)
    (`(agent . ,agent)
     (let* ((location (or (plist-get (agent-workspace-activity agent) :location)
                          (user-error "%s is in no file yet" (agent-workspace-agent-name agent))))
            (file (expand-file-name (car location) (agent-workspace-agent-worktree agent))))
       (unless (file-exists-p file)
         (user-error "No %s in %s's worktree" (car location) (agent-workspace-agent-name agent)))
       (pop-to-buffer (find-file-noselect file))
       (when (cdr location)
         (goto-char (point-min))
         (forward-line (1- (cdr location))))))
    (`(conflict . ,conflict)
     (let ((agent (car (cdr conflict))))
       (pop-to-buffer (find-file-noselect (expand-file-name (car conflict) (agent-workspace-agent-worktree agent))))))))

(defun agent-workspace-minimap-diff ()
  "The lane's agent's branch's changes; on a conflict, both agents' changes
to its file."
  (interactive)
  (pcase (agent-workspace--minimap-at)
    (`(agent . ,agent)
     (when (agent-workspace-frame-p) (agent-workspace-leave t))
     (agent-workspace-review agent))
    (`(conflict . ,conflict) (agent-workspace-minimap-conflict-diff conflict))))

(defun agent-workspace-minimap-conflict-diff (conflict)
  "CONFLICT's agents' changes to its file, each against the main checkout's
branch (what each would merge), one after the other in a diff buffer."
  (let* ((file (car conflict))
         (agents (cdr conflict))
         (project (agent-workspace-agent-project (car agents)))
         (main (agent-workspace-main-branch project))
         (buffer (get-buffer-create (format "*%s: %s*" (mapconcat #'agent-workspace-agent-name agents " + ") file))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (agent agents)
          (insert (format "# %s (%s)\n" (agent-workspace-agent-name agent) (agent-workspace-agent-branch agent)))
          (let ((default-directory (agent-workspace-agent-worktree agent)))
            (call-process "git" nil t nil "diff" "--merge-base" main "--" file))
          (insert "\n"))
        (diff-mode)
        (setq buffer-read-only t)
        (goto-char (point-min))))
    (when (agent-workspace-frame-p) (agent-workspace-leave t))
    (pop-to-buffer buffer)))
