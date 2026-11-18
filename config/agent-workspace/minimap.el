;;; $DOOMDIR/config/agent-workspace/minimap.el -*- lexical-binding: t; -*-
;; The crew's minimap: what each agent did, minute by minute, under the issue
;; list. Loaded from config/agent-workspace.el, after activity.el. No Doom
;; here.
;;
;; A line an agent, in the crew's order, never moving as it starts or stops
;; working (activity.el's data): its avatar and its role's icon (its name and
;; role on hover), its last `agent-workspace-activity-minutes' minutes a cell
;; each (read, edit, run, a hand raised: what it did most then), then its
;; state's glyph and where it is now (its file and line, what it asks you).
;; One with nothing done in those minutes (at the desk, asleep): its name in
;; the cells' place, then its state in words. A file two agents change on a
;; line of its own (⚠ ada + ken: FILE). One column a
;; cell on the screen: a glyph drawn wider (a font lacking it draws it from
;; another) replaced by its fallback, measured once a frame; the │ at its
;; column whatever comes before it; every line evened and cut to its window's
;; pixels, never past its edge. Faces only. As tall as its lines: a lane each,
;; growing as agents come, at most `agent-workspace-minimap-lines' (then it
;; scrolls), the axis and legend under them while a lane has cells; half a
;; line of padding above them and half a line under them (in a terminal,
;; where a line can't be halved, a blank line under them).
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

(defcustom agent-workspace-minimap-lines 10
  "The most lanes the minimap shows at once (an agent's, a file two agents
change): past them it scrolls. Its header line, axis and legend not
counted. Fewer lanes, it's as tall as they are."
  :type 'natnum
  :group 'agent-workspace)

(defvar agent-workspace-minimap-glyphs
  '((read "⌕" "≡" "=") (edit "✎" "±" "+") (run "▶" ">") (asked "!") (none "·" "."))
  "A cell's glyphs by what the agent did in its minute: the first drawn one
column wide in the frame, else the next (its last at worst: the frame's
font has it). JetBrains Mono has no ✎: drawn from another font, wider, ±.")

(defvar agent-workspace--minimap-measured (make-hash-table :test #'eq :weakness 'key)
  "A frame's cells' glyphs, measured there: (FONT (KIND . GLYPH)...), FONT
what they were measured with.")

(defconst agent-workspace--minimap-indent "      "
  "Before a lane's cells: a space, its avatar, a space, its role's icon
\(two columns each); the axis and the legend start there too.")

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

(defun agent-workspace--minimap-lines (project &optional now)
  "The lines PROJECT's minimap shows at once: a lane each (an agent's, a
conflict's), at most `agent-workspace-minimap-lines', its one line with no
agents; the axis and legend under them while a lane has cells."
  (let ((agents (agent-workspace-agents project)))
    (+ (max 1 (min agent-workspace-minimap-lines
                   (+ (length agents) (length (agent-workspace-conflicts project)))))
       (if (seq-some (lambda (agent) (agent-workspace--minimap-busy-p agent now)) agents) 2 0))))

(defun agent-workspace--minimap-height (project)
  "PROJECT's minimap's rows: its lines, its header line and its padding (a
line: half above, half under; a terminal's under)."
  (+ 2 (agent-workspace--minimap-lines project)))

(defun agent-workspace--minimap-pads (window)
  "WINDOW's padding, a minimap's, in pixels: (ABOVE . UNDER), half a line
each; in a terminal, where a line can't be halved, a line under."
  (let ((line (window-default-line-height window)))
    (if (display-graphic-p (window-frame window))
        (cons (/ line 2) (/ line 2))
      (cons 0 line))))

(defun agent-workspace--minimap-pad (pixels &optional last)
  "An empty line PIXELS tall, padding: a newline that high (`line-height'),
in a tiny font (the default one made it a whole line). The LAST line, with
no newline: a space that tall, a pixel wide (of no width, a truncated
line's first glyph counts for nothing)."
  (propertize (if last
                  (propertize " " 'display `(space :width (1) :height (,pixels)))
                (propertize "\n" 'face '(:height 0.1) 'line-height pixels))
              'agent-workspace-minimap-pad t))

(defun agent-workspace--minimap-size (window project)
  "WINDOW, PROJECT's minimap's, as tall as its lines, header line and
padding, to the pixel: in whole lines a window divider (Doom's, a pixel)
cut its last line, and the cursor there scrolled the lanes. What the issue
list above it can give at most."
  (let* ((window-resize-pixelwise t)
         (pads (agent-workspace--minimap-pads window))
         (want (+ (window-header-line-height window)
                  (car pads)
                  (* (agent-workspace--minimap-lines project) (window-default-line-height window))
                  (cdr pads)
                  (window-mode-line-height window)
                  (window-scroll-bar-height window)
                  (window-bottom-divider-width window)))
         (delta (window-resizable window (- want (window-pixel-height window)) nil 'preserved t)))
    (unless (zerop delta)
      (window-resize window delta nil 'preserved t))))

(defun agent-workspace--minimap-place (app)
  "APP's minimap under its issue list, if it's shown and there's room for it
\(twice its height), as tall as its lines: drawn. Called as APP is laid
out."
  (let ((project (agent-workspace--app-project app)))
    (when (and (agent-workspace-minimap-shown-p project)
               (>= (window-total-height (frame-root-window)) (* 2 (agent-workspace--minimap-height project))))
      (when-let* ((window (display-buffer-in-side-window
                           (agent-workspace--minimap-buffer project)
                           `((side . left) (slot . 1) (window-height . ,(agent-workspace--minimap-height project))
                             (dedicated . t) (preserve-size . (nil . t))
                             (window-parameters . ((no-delete-other-windows . t)
                                                   (mode-line-format . none) (tab-line-format . none)))))))
        (set-window-fringes window 0 0)
        (agent-workspace--minimap-size window project)
        (agent-workspace--minimap-draw project)))))

;; ====== ITS LINES ======

(defun agent-workspace--minimap-glyph (kind)
  "KIND's glyph for a cell in the selected frame: the first of its
`agent-workspace-minimap-glyphs' drawn as wide as a column there (bold, as
its cell, for an edit or a hand raised), else its last. Measured once a
frame, again when its font changes; in a terminal, where a glyph is its
cell (a pixel a column), its first."
  (let* ((glyphs (alist-get kind agent-workspace-minimap-glyphs))
         (font (list (frame-char-width) (face-font 'default) agent-workspace-minimap-glyphs))
         (measured (gethash (selected-frame) agent-workspace--minimap-measured)))
    (unless (equal (car measured) font)
      (setq measured (puthash (selected-frame) (list font) agent-workspace--minimap-measured)))
    (or (alist-get kind (cdr measured))
        (let* ((face (if (memq kind '(edit asked)) 'bold 'default))
               (glyph (or (seq-find (lambda (glyph)
                                      (= (string-pixel-width (propertize glyph 'face face)) (frame-char-width)))
                                    glyphs)
                          (car (last glyphs)))))
          (setcdr measured (cons (cons kind glyph) (cdr measured)))
          glyph))))

(defun agent-workspace--minimap-cell (agent kinds)
  "AGENT's cell for a minute it did KINDS in: a glyph, in its colour (read
dimmer, edit bold), a hand raised in the warning face."
  (let* ((kind (seq-find (lambda (kind) (memq kind kinds)) agent-workspace--minimap-order))
         (glyph (agent-workspace--minimap-glyph (or kind 'none)))
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

(defun agent-workspace--minimap-fit (line width)
  "LINE, a line of the minimap, its glyphs evened (`agent-ui-even-glyphs')
and cut to WIDTH columns' pixels, … where cut: never past its window's
edge (no $ there), however wide a glyph is drawn. In a terminal a pixel is
a column."
  (let ((line (if (fboundp 'agent-ui-even-glyphs) (agent-ui-even-glyphs line) line))
        (pixels (* width (frame-char-width))))
    (if (<= (string-pixel-width line) pixels)
        line
      ;; The most of it that fits with … after it.
      (let ((low 0) (high (1- (length line))))
        (while (< low high)
          (let ((mid (/ (+ low high 1) 2)))
            (if (<= (string-pixel-width (concat (substring line 0 mid) "…")) pixels)
                (setq low mid)
              (setq high (1- mid)))))
        (concat (substring line 0 low) "…")))))

(defun agent-workspace--minimap-who (agent)
  "AGENT's avatar, then its role's icon (`agent-workspace-role-glyph', as on
its line), two columns each: the icon in its colour, dimmed while it is, as
its avatar (not shadow: hard to read on the minimap's background); its name
and role on hover, \"ada · scribe\"."
  (let ((face (if (and (agent-workspace-dim-p agent) (fboundp 'agent-ui-blend))
                  (list :foreground (agent-ui-blend (agent-ui-background)
                                                    (agent-ui-color (agent-workspace-agent-face agent)) 0.4))
                (agent-workspace--fg agent))))
    (propertize (concat (agent-workspace-agent-avatar agent) " " (agent-workspace-role-glyph agent face))
                'help-echo (format "%s · %s" (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)))))

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
  "AGENT's line, WIDTH columns: avatar and role's icon, its minutes up to
NOW (with nothing done in them: its name in their place), │ at the lanes'
column (a space aligned to it: a cell a pixel off can't move it), its
state's glyph, where it is (or its state in words); fitted to WIDTH columns
on the screen."
  (let* ((who (concat " " (agent-workspace--minimap-who agent)))
         (minutes (concat who
                          (if (agent-workspace--minimap-busy-p agent now)
                              (mapconcat (lambda (kinds) (agent-workspace--minimap-cell agent kinds))
                                         (agent-workspace-activity-lane agent now) "")
                            (agent-workspace--fit (agent-workspace-agent-name-text agent)
                                                  (1- agent-workspace-activity-minutes)))))
         (head (concat minutes
                       (propertize " " 'display `(space :align-to ,(+ (string-width who)
                                                                       agent-workspace-activity-minutes 1)))
                       (propertize "│" 'face 'shadow) " "
                       (agent-workspace-state-glyph agent) " ")))
    (propertize (agent-workspace--minimap-fit
                 (concat head (agent-workspace--minimap-where agent (max 6 (- width (string-width head)))))
                 width)
                'agent-workspace-minimap-agent agent)))

(defun agent-workspace--minimap-busy-p (agent &optional now)
  "Non-nil if AGENT gets a lane: it did something in the last minutes, or
it's working, its hand raised, stuck."
  (or (memq (agent-workspace-agent-state agent) '(working hand stuck))
      (seq-some #'identity (agent-workspace-activity-lane agent now))))

(defun agent-workspace--minimap-conflict (conflict width)
  "CONFLICT (FILE AGENT...), a file several agents change: its line."
  (propertize
   (agent-workspace--minimap-fit
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
    (propertize (concat agent-workspace--minimap-indent cells) 'face 'shadow)))

(defun agent-workspace--minimap-legend (width)
  "What its glyphs say (the ones its cells use), WIDTH columns at most."
  (agent-workspace--minimap-fit
   (concat agent-workspace--minimap-indent
           (mapconcat (lambda (entry)
                        (propertize (format "%s %s" (agent-workspace--minimap-glyph (car entry)) (cdr entry))
                                    'face 'shadow))
                      '((read . "read") (edit . "edit") (run . "run") (asked . "asks you"))
                      "  "))
   width))

(defun agent-workspace--minimap-header ()
  "The minimap's header line."
  (when agent-workspace--minimap-project
    (agent-workspace--percent-escaped
     (agent-workspace--at-right
      (concat " " (propertize "CREW" 'face 'bold) "  "
              (propertize (format "%d minutes" agent-workspace-activity-minutes) 'face 'shadow))
      (concat (propertize "where now" 'face 'shadow) " ")
      (window-total-width)))))

(defun agent-workspace-minimap-text (project width &optional now)
  "PROJECT's minimap, WIDTH columns, up to NOW: its lines."
  (let* ((agents (agent-workspace--ordered project))
         (busy (seq-filter (lambda (agent) (agent-workspace--minimap-busy-p agent now)) agents))
         (conflicts (agent-workspace-conflicts project)))
    ;; Every agent a line, in the crew's order; the axis and legend while a
    ;; lane has cells.
    (append (mapcar (lambda (agent) (agent-workspace--minimap-lane agent width now)) agents)
            (mapcar (lambda (conflict) (agent-workspace--minimap-conflict conflict width)) conflicts)
            (and busy (list (agent-workspace--minimap-axis) (agent-workspace--minimap-legend width)))
            (and (not agents) (list (propertize "  No agents yet." 'face 'shadow))))))

;; ====== DRAWING IT ======

(defun agent-workspace--minimap-draw (project)
  "PROJECT's minimap drawn again, if it's shown, padded: the cursor on the
line it was on (off the padding); drawn again at the next minute while a
lane has something."
  (agent-workspace--minimap-cancel project)
  (when-let* ((window (agent-workspace--minimap-window project)))
    (with-current-buffer (window-buffer window)
      (agent-workspace--in-drawing-frame
        (let* ((pos (window-point window))
               (agent (get-text-property pos 'agent-workspace-minimap-agent))
               (line (line-number-at-pos pos))
               ;; Its glyphs measured in its own frame.
               (lines (with-selected-frame (window-frame window)
                        (agent-workspace-minimap-text project (max 20 (1- (window-body-width window))))))
               (pads (agent-workspace--minimap-pads window))
               (inhibit-read-only t))
          (erase-buffer)
          ;; Half a line above its lines and half a line under them, each an
          ;; empty line that tall; a terminal's line under them the empty one
          ;; after their last newline.
          (unless (zerop (car pads))
            (insert (agent-workspace--minimap-pad (car pads))))
          (insert (string-join lines "\n") "\n")
          (when (display-graphic-p (window-frame window))
            (insert (agent-workspace--minimap-pad (cdr pads) t)))
          (goto-char (point-min))
          (if-let* ((match (and agent (text-property-search-forward 'agent-workspace-minimap-agent agent #'eq))))
              (goto-char (prop-match-beginning match))
            (forward-line (1- line)))
          ;; Off the padding: on its first line.
          (when (or (get-text-property (line-beginning-position) 'agent-workspace-minimap-pad)
                    (and (eobp) (bolp)))
            (goto-char (point-min))
            (when (get-text-property (point) 'agent-workspace-minimap-pad)
              (forward-line 1)))
          (set-window-point window (point))
          (set-window-start window (point-min) t))))
    ;; As tall as its lines: an agent come or gone, a lane's first cells (the
    ;; axis and legend). The app's own change, not a border dragged; while
    ;; it's being laid out (its sizes not taken yet), placing it did it.
    (agent-workspace--resize-own (window-frame window)
                                 (lambda () (agent-workspace--minimap-size window project)))
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
  "Show or hide the crew's minimap, under the issue list (m); in a frame too
low for it, not shown, saying so."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app))
         (shown (not (agent-workspace-minimap-shown-p project)))
         (rows (window-total-height (frame-root-window))))
    (when (and shown (< rows (* 2 (agent-workspace--minimap-height project))))
      (user-error "No room for the minimap: it needs %d rows, the frame has %d"
                  (* 2 (agent-workspace--minimap-height project)) rows))
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
