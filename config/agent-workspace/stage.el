;;; $DOOMDIR/config/agent-workspace/stage.el -*- lexical-binding: t; -*-
;; The stage: the app's centre, every agent a pane. Loaded from
;; config/agent-workspace.el, after look.el. No Doom here.
;;
;; Every agent has a pane, in role order (they never move). One is open, the
;; selected agent's: its session, its line as its header line, and its Agent
;; UI below it, as in any session's pane (config/agent-ui/pane.el): its
;; canvases, when they show something (its own, then its others: ask...), and
;; its panels, laid out to use the room, each with a bar naming it, a bar under
;; them, as high as they need. Full size (V): its Agent UI may take the pane's
;; whole room, the session keeping its last lines. The others are folded: a
;; one-row window each showing the agent's bar (a window can't be its header
;; line alone). Every pane folded: a hint below the bars. The stage arranges
;; itself: no border to drag; a border dragged or the frame resized, it's tiled
;; again (sizes taken as they are after 3 layouts in 3 seconds: never a loop).
;; Agent UI's own changes (its views fitted to what they show) are the stage's
;; own, no border dragged; the stage takes its windows out before it lays out
;; or tiles again, and puts them back in the open pane.
;;
;; The stage never changes an agent's session buffer: its windows' own
;; parameters hide their mode line and tab line and give the open pane its
;; header line. A canvas or panel it shows gets `agent-workspace-side-mode'
;; (the app's v and V in it).

(require 'cl-lib)
(require 'subr-x)

(declare-function agent-ui-canvas-buffer-name "agent-ui/canvas")
(declare-function agent-ui-pane-attach-window "agent-ui/pane")
(declare-function agent-ui-pane-detach "agent-ui/pane")
(declare-function agent-ui-pane-cells "agent-ui/pane")
(declare-function agent-ui--session-name "agent-ui/agent")
(declare-function agent-ui-panels--name "agent-ui/panels")
(declare-function agent-ui-session-canvases "agent-ui/agent")
(declare-function evil-normalize-keymaps "evil-core")
(declare-function agent-workspace-agent-panels "agent-workspace/panels")
(defvar agent-ui-display-function)
(defvar agent-ui-panels--state)
(defvar agent-ui--canvas-part)
(defvar agent-ui-focus-questions)

;; ====== VARIABLES ======

(defconst agent-workspace--folded-rows 1 "A folded pane: its bar, one row.")
(defconst agent-workspace--open-rows 6 "An open pane, at least: its header line and 5 lines.")

(defvar agent-workspace--canvas-fallback nil
  "Agent UI's display function before the stage's: for canvases not an
agent's of a crew.")

(defvar agent-workspace-bar-mode-map (make-sparse-keymap)
  "Keys on a folded pane's bar (set in config/agent-workspace.el).")

(defvar-local agent-workspace--bar-of nil
  "In a bar's buffer: its agent.")

(defvar agent-workspace-side-mode-map (make-sparse-keymap)
  "Keys in an agent's canvas or panel on the stage (set in
config/agent-workspace.el).")

;; ====== A BAR ======

(define-derived-mode agent-workspace-bar-mode special-mode "Bar"
  "A folded pane's bar: one line, its agent's line."
  ;; Its window's least height is its one line (Emacs reads it in the
  ;; window's buffer): counted as `window-min-height' (4), a few bars left
  ;; the minibuffer no room to grow in a small frame (doom-pbk.78).
  (setq-local window-min-height 1)
  (setq-local truncate-lines t
              mode-line-format nil
              header-line-format nil
              tab-line-exclude t
              cursor-type nil
              cursor-in-non-selected-windows nil
              left-fringe-width 0
              right-fringe-width 0
              left-margin-width 0
              right-margin-width 0
              fringe-indicator-alist (append '((truncation nil nil) (continuation nil nil))
                                             (default-value 'fringe-indicator-alist)))
  (setq buffer-display-table (make-display-table)))

(defun agent-workspace--bar-buffer (agent)
  "AGENT's bar's buffer (made the first time)."
  (let ((name (format " *bar · %s · %s*" (agent-workspace-agent-name agent)
                      (file-name-nondirectory (directory-file-name (agent-workspace-agent-project agent))))))
    (or (seq-find (lambda (buffer) (eq (buffer-local-value 'agent-workspace--bar-of buffer) agent))
                  (agent-workspace--app-buffers (agent-workspace-agent-project agent)))
        (with-current-buffer (generate-new-buffer name)
          (agent-workspace-bar-mode)
          (setq agent-workspace--bar-of agent
                agent-workspace--agent agent)
          (agent-workspace--app-buffer-add (agent-workspace-agent-project agent) (current-buffer))
          (current-buffer)))))

(defun agent-workspace--clickable (line map &optional header)
  "LINE with MAP on it (a click selects its agent), hovered as `hl-line',
saying so where its text says nothing else on hover (its context's usage,
its panels); its buttons (a raised hand's) keep their own. HEADER: LINE
is a header line's (MAP its local-map too, as a header line's clicks
need); a buffer's (a bar's), MAP over the buffer's own keys, never in
their place."
  (let ((line (copy-sequence line))
        (pos 0))
    (while (< pos (length line))
      (let ((next (or (next-single-property-change pos 'agent-workspace-button line) (length line))))
        (unless (get-text-property pos 'agent-workspace-button line)
          (add-text-properties pos next (append (list 'keymap map 'mouse-face 'agent-workspace-hover)
                                                (and header (list 'local-map map)))
                               line)
          (let ((at pos))
            (while (< at next)
              (let ((end (or (next-single-property-change at 'help-echo line next) next)))
                (unless (get-text-property at 'help-echo line)
                  (put-text-property at end 'help-echo "Select this agent: its pane opens (mouse-3: its actions)"
                                     line))
                (setq at end)))))
        (setq pos next)))
    line))

(defun agent-workspace--bar-draw (window)
  "WINDOW's bar drawn again, as wide as WINDOW."
  (with-current-buffer (window-buffer window)
    (agent-workspace--in-drawing-frame
      (when-let* ((agent agent-workspace--bar-of))
        (let* ((inhibit-read-only t)
               (line (agent-workspace--clickable
                      (agent-workspace-line agent (window-body-width window) nil t)
                      agent-workspace-line-map))
               (tint (plist-get (seq-find (lambda (f) (and (consp f) (plist-get f :background)))
                                          (let ((f (get-text-property 0 'face line)))
                                            (if (and (consp f) (keywordp (car f))) (list f) f)))
                                :background)))
          (erase-buffer)
          (insert line)
          ;; No right fringe: the last column is kept for a $ (a line too
          ;; long): a space in the bar's tint instead.
          (when tint
            (set-display-table-slot buffer-display-table 'truncation
                                    (make-glyph-code ?\s (agent-workspace--tint-face tint))))
          (goto-char (point-min))
          (set-window-start window (point-min) t))))))

(defun agent-workspace--tint-face (colour)
  "A face whose background is COLOUR (a display table's glyph needs a named
one)."
  (let ((face (intern (format "agent-workspace-tint-%s" (string-remove-prefix "#" colour)))))
    (unless (facep face)
      (make-face face)
      (set-face-background face colour))
    face))

(defvar agent-workspace--headers (make-hash-table :test #'equal)
  "The header lines made: (KIND AGENT WIDTH SIDE BUFFER FRAME) to its text,
until an agent changes (`agent-workspace--headers-stale'): a header line is
made again at every redisplay of its window (a streamed chunk, a cursor
move), its agent's line costly to make.")

(defun agent-workspace--headers-stale (&rest _)
  "The header lines kept made again when next shown: an agent changed, a
turn's time ticked, the app drawn again. In
`agent-workspace-change-functions', first."
  (clrhash agent-workspace--headers))

(add-hook 'agent-workspace-change-functions #'agent-workspace--headers-stale -90)

(defmacro agent-workspace--header-kept (kind agent &rest body)
  "BODY's text, a header line of KIND for AGENT in the selected window, made
once until the headers go stale (`agent-workspace--headers')."
  (declare (indent 2))
  `(let ((key (list ,kind ,agent (window-total-width) (window-buffer) (selected-frame))))
     (or (gethash key agent-workspace--headers)
         (puthash key (progn ,@body) agent-workspace--headers))))

(defun agent-workspace--pane-header ()
  "The open pane's header line: its agent's line (in its window's width).
Kept until something changes (`agent-workspace--headers')."
  (when-let* ((agent (or (agent-workspace-buffer-agent) (window-parameter nil 'agent-workspace-pane))))
    (agent-workspace--header-kept 'pane agent
      (agent-workspace--percent-escaped
       (agent-workspace--clickable
        (agent-workspace-line agent (window-total-width) t nil nil)
        agent-workspace-line-map t)))))

;; ====== THE STACK ======

(defun agent-workspace--sizes (agents open height)
  "AGENTS' panes in a stack HEIGHT rows high: (AGENT . ROWS) in order, all
folded but OPEN's, which takes the rows left (if there are enough)."
  (let* ((budget (- height (* agent-workspace--folded-rows (length agents))))
         (grow (- agent-workspace--open-rows agent-workspace--folded-rows))
         (open (and open (memq open agents) (>= budget grow) open)))
    (mapcar (lambda (agent)
              (cons agent (if (eq agent open)
                              (+ agent-workspace--folded-rows budget)
                            agent-workspace--folded-rows)))
            agents)))

(define-derived-mode agent-workspace-hint-mode special-mode "Stage"
  "The stage's hint: no agents yet (c makes one), or every pane folded. The
app's keys (config/agent-workspace.el): c, q, Q there are the app's, not
evil's (a change, a macro recorded, the last one run)."
  (setq-local mode-line-format nil header-line-format nil tab-line-exclude t cursor-type nil
              ;; The rows left below the bars, maybe fewer than 4: its least.
              window-min-height 1))

(defun agent-workspace--hint-buffer (project)
  "What's below the bars when every pane is folded (or there's no agent):
how to open one, or make one."
  (let ((name (format "*stage · %s*" (file-name-nondirectory (directory-file-name project)))))
    ;; Its project's: another of the same folder name has its own.
    (or (seq-find (lambda (buffer) (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-hint-mode))
                  (agent-workspace--app-buffers project))
        (with-current-buffer (generate-new-buffer name)
          (agent-workspace-hint-mode)
          (setq default-directory (agent-workspace--root project))
          (agent-workspace--app-buffer-add project (current-buffer))
          (current-buffer)))))

(defun agent-workspace--hint-draw (project agents)
  "The hint below the bars: none yet, or every pane folded."
  (with-current-buffer (agent-workspace--hint-buffer project)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize (if agents
                              "\n  Every pane is folded.\n\n  Open one: TAB, a click or RET on its bar, j/k on the bars,\n  moving onto its issue in the list.\n"
                            "\n  No agents yet.\n\n  c: a new agent, or a crew\n")
                          'face 'shadow)))))

(defvar agent-workspace--pane-places nil
  "While the stage is tiled again or laid out: where its panes' sessions
were shown, ((BUFFER POINT START END)...), END non-nil if at their end
\(`agent-workspace--pane-places'): shown there again.")

(defun agent-workspace--pane-places (frame)
  "Where FRAME's panes show their sessions now: ((BUFFER POINT START
END)...), END non-nil if at its end (following what comes)."
  (delq nil (mapcar (lambda (window)
                      (when-let* ((agent (window-parameter window 'agent-workspace-pane))
                                  ((agent-workspace-agent-p agent))
                                  (buffer (window-buffer window))
                                  ((eq buffer (agent-workspace-agent-buffer agent))))
                        (list buffer (window-point window) (window-start window)
                              (>= (window-point window) (with-current-buffer buffer (point-max))))))
                    (window-list frame 'nomini))))

(defun agent-workspace--show-pane (window agent)
  "AGENT's session (or its bar, if it has none) in WINDOW: where it was
shown, the stage tiled again or laid out (`agent-workspace--pane-places'),
else (opened now, or following its end) at its end."
  (set-window-dedicated-p window nil)
  (set-window-parameter window 'agent-workspace-side nil)
  (let ((buffer (agent-workspace-agent-buffer agent)))
    (if (not (buffer-live-p buffer))
        (progn (set-window-buffer window (agent-workspace--bar-buffer agent))
               ;; Its bar's own display table (its tinted truncation glyph).
               (set-window-display-table window nil)
               (agent-workspace--bar-draw window))
      (set-window-buffer window buffer)
      (set-window-parameter window 'header-line-format '(:eval (agent-workspace--pane-header)))
      (let ((place (assq buffer agent-workspace--pane-places)))
        (if (and place (not (nth 3 place)))
            (progn (set-window-point window (nth 1 place))
                   ;; Its start too, unless the cursor isn't in view then.
                   (set-window-start window (nth 2 place) t))
          (with-current-buffer buffer
            (set-window-point window (point-max))))))
    (set-window-parameter window 'mode-line-format 'none)
    (set-window-parameter window 'tab-line-format 'none)
    (set-window-fringes window 0 0)
    (set-window-margins window 0 0)
    ;; No fringes: a wrapped line's mark, a cut one's, a space (not a \ or $
    ;; in the text), the window's own: its buffer untouched.
    (when (buffer-live-p buffer)
      (let ((table (make-display-table)))
        (set-display-table-slot table 'wrap ?\s)
        (set-display-table-slot table 'truncation ?\s)
        (set-window-display-table window table)))))

(defun agent-workspace--show-bar (window agent)
  "AGENT's bar in WINDOW: its buffer's display table (its tinted truncation
glyph), not a pane's the window had (a window's wins over its buffer's)."
  (set-window-dedicated-p window nil)
  (set-window-parameter window 'agent-workspace-side nil)
  (set-window-buffer window (agent-workspace--bar-buffer agent))
  (set-window-display-table window nil)
  (dolist (parameter '(header-line-format mode-line-format tab-line-format))
    (set-window-parameter window parameter 'none))
  (set-window-fringes window 0 0)
  (set-window-margins window 0 0)
  (agent-workspace--bar-draw window))

(defun agent-workspace--stack (area agents open)
  "AGENTS' panes stacked in window AREA, all folded but OPEN's (its side
area in it, or full size): their windows."
  (let* ((window-min-height 1)
         (window-resize-pixelwise t)       ; else a split's pixels round to lines
         (sizes (agent-workspace--sizes agents open (window-total-height area)))
         (any-open (cl-some (lambda (entry) (> (cdr entry) agent-workspace--folded-rows)) sizes))
         ;; A row: a line and the divider below it (Doom's: 1 pixel).
         (line (+ (frame-char-height (window-frame area)) (window-bottom-divider-width area)))
         (rest (- (window-total-height area) (length sizes)))
         (sizes (if (and (not any-open) (> rest 0)) (append sizes (list (cons :hint rest))) sizes))
         (pixels (mapcar (lambda (entry) (* (cdr entry) line)) sizes))
         (big (or (cl-position-if (lambda (entry) (> (cdr entry) agent-workspace--folded-rows)) sizes)
                  (1- (length sizes))))
         (windows nil)
         (open-panes nil)
         (w area))
    ;; The pixels left over to the open pane (or the hint).
    (when sizes
      (setf (nth big pixels) (+ (nth big pixels) (- (window-pixel-height area) (apply #'+ pixels)))))
    ;; Split from a bar: a window with a header line can't be split down to a row.
    (when agents (agent-workspace--show-bar area (car agents)))
    (cl-loop for (agent . rows) in sizes for i from 0
             do (let ((next (and (< i (1- (length sizes)))
                                 (condition-case nil
                                     (let ((window-combination-limit (= i 0)))
                                       (split-window w (nth i pixels) 'below t))
                                   (error nil)))))
                  (cond ((eq agent :hint)
                         (set-window-buffer w (agent-workspace--hint-buffer (agent-workspace-agent-project (car agents))))
                         (set-window-display-table w nil)
                         (dolist (parameter '(header-line-format mode-line-format tab-line-format))
                           (set-window-parameter w parameter 'none))
                         (set-window-parameter w 'agent-workspace-side nil))
                        ((<= rows agent-workspace--folded-rows)
                         (agent-workspace--show-bar w agent))
                        (t
                         (agent-workspace--show-pane w agent)
                         ;; Its Agent UI below its session, after the panes
                         ;; are split (its views aren't the stage's to size).
                         (push (cons w agent) open-panes)))
                  (set-window-parameter w 'agent-workspace-pane (and (not (eq agent :hint)) agent))
                  (push w windows)
                  (if next (setq w next) (cl-return))))
    (pcase-dolist (`(,window . ,agent) open-panes)
      (agent-workspace--views-attach window agent))
    (nreverse windows)))

;; ====== ITS AGENT UI: ITS CANVASES AND PANELS ======
;; The open pane's Agent UI holds the agent's canvas, its other canvases
;; (--canvas NAME: a question's, ask) when they show something, and its
;; panels (panels.el): Agent UI lays them out below its session (config/
;; agent-ui/pane.el), the panels its views too
;; (`agent-ui-pane-views-functions'). Full size (V): it may take the pane's
;; whole room (`agent-ui-pane-full').

(defun agent-workspace--canvas-buffer (agent)
  "AGENT's Agent UI canvas, if it has one (empty or not)."
  (when-let* (((fboundp 'agent-ui-canvas-buffer-name))
              (session (agent-workspace-agent-buffer agent))
              ((buffer-live-p session)))
    (get-buffer (agent-ui-canvas-buffer-name (agent-ui--session-name session)))))

(defun agent-workspace--canvas (agent)
  "AGENT's Agent UI canvas, if it shows something."
  (when-let* ((canvas (agent-workspace--canvas-buffer agent)))
    (and (> (buffer-size canvas) 0) canvas)))

(defun agent-workspace--other-canvases (agent)
  "AGENT's other Agent UI canvases (its session's, --canvas NAME) that show
something, by name."
  (when-let* (((fboundp 'agent-ui-session-canvases))
              (session (agent-workspace-agent-buffer agent))
              ((buffer-live-p session)))
    (seq-sort-by (lambda (canvas) (buffer-local-value 'agent-ui--canvas-part canvas)) #'string<
                 (seq-filter (lambda (canvas)
                               (and (buffer-local-value 'agent-ui--canvas-part canvas)
                                    (> (buffer-size canvas) 0)))
                             (agent-ui-session-canvases session)))))

(defun agent-workspace-agent-tabs (agent)
  "AGENT's Agent UI's views: its canvas, then its other canvases, if they
show something, then its panels; their buffers."
  (let ((canvas (agent-workspace--canvas agent)))
    (append (and canvas (list canvas))
            (agent-workspace--other-canvases agent)
            (and (fboundp 'agent-workspace-agent-panels) (agent-workspace-agent-panels agent)))))

(defun agent-workspace--full-p (agent)
  "Non-nil if AGENT's open pane shows its Agent UI full size (V)."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent))))
    (eq (agent-workspace--app-full app) agent)))

(defun agent-workspace--tab-name (tab)
  "TAB's name: its panel's (\"tests\"), its other canvas's (\"ask\"), as
they were named, or \"Canvas\": the app's word for its main one, as CREW
is the minimap's."
  (if-let* (((boundp 'agent-ui-panels--state))
            (panel (buffer-local-value 'agent-ui-panels--state tab)))
      (agent-ui-panels--name panel)
    (or (and (boundp 'agent-ui--canvas-part) (buffer-local-value 'agent-ui--canvas-part tab))
        "Canvas")))

(define-minor-mode agent-workspace-side-mode
  "An agent's canvas or panel shown in its pane on the stage: v goes to the
next one, V its Agent UI full size."
  :lighter nil
  ;; Evil's keys of its map, in this buffer from now.
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(defun agent-workspace--views-attach (window agent)
  "AGENT's Agent UI below its session in its open pane WINDOW (see above):
its views' windows, each with the stage's keys (v, V)."
  (when-let* (((fboundp 'agent-ui-pane-attach-window))
              (session (agent-workspace-agent-buffer agent))
              ((buffer-live-p session)))
    (with-current-buffer session
      (setq-local agent-ui-pane-full (agent-workspace--full-p agent)))
    (let ((cells (agent-ui-pane-attach-window window session)))
      (dolist (cell cells)
        (with-current-buffer (window-buffer cell)
          (unless agent-workspace-side-mode
            (agent-workspace-side-mode 1))))
      cells)))

(defun agent-workspace--views-windows (agent)
  "The windows of AGENT's Agent UI views in its pane, in order (none while
its app isn't shown)."
  (when-let* (((fboundp 'agent-ui-pane-cells))
              (app (agent-workspace--app (agent-workspace-agent-project agent)))
              ((agent-workspace--shown-p app))
              (session (agent-workspace-agent-buffer agent))
              ((buffer-live-p session)))
    (agent-ui-pane-cells (agent-workspace--app-frame app) session)))

(defun agent-workspace--views-window (agent)
  "The first window of AGENT's Agent UI views in its pane, or nil."
  (car (agent-workspace--views-windows agent)))

;; ====== ITS CANVASES: NEVER POPPED UP ======
;; A canvas of a crew's agent (its own, or another of its session's: ask,
;; tests) isn't shown by Agent UI on its own: the stage lays its agent's open
;; pane out again when it shows something new, its Agent UI with it. A
;; question there takes no focus: the agent's raised hand says it, as for a
;; permission (a goes there). Closed or emptied (q, a question answered), its
;; view goes (app.el): the others laid out again, or its Agent UI gone.

(defun agent-workspace--canvas-agent (canvas)
  "The crew's agent whose session CANVAS is, or nil."
  (when-let* ((session (and (boundp 'agent-ui--session-buffer)
                            (buffer-local-value 'agent-ui--session-buffer canvas))))
    (and (buffer-live-p session) (agent-workspace-buffer-agent session))))

(defun agent-workspace--no-focus (canvas)
  "CANVAS, a crew's agent's: a question there takes no focus (see above)."
  (with-current-buffer canvas
    (setq-local agent-ui-focus-questions nil)))

(defun agent-workspace--canvas-no-focus-h ()
  "A new canvas, a crew's agent's: a question there takes no focus. In
`agent-ui-canvas-hook', after Agent UI ties it to its session."
  (when (agent-workspace--canvas-agent (current-buffer))
    (agent-workspace--no-focus (current-buffer))))

(defun agent-workspace--display-canvas (canvas)
  "Agent UI's display function: a crew's agent's CANVAS goes in its open
pane, its tab shown (the stage laid out again); any other as Agent UI shows
it."
  (if-let* ((agent (agent-workspace--canvas-agent canvas)))
      (progn
        (agent-workspace--no-focus canvas)
        (agent-workspace--canvas-changed agent canvas))
    (funcall (or agent-workspace--canvas-fallback #'ignore) canvas)))

(defun agent-workspace--take-canvases ()
  "Agent UI's canvases of crews' agents shown by the stage (see above)."
  (when (and (boundp 'agent-ui-display-function)
             (not (eq agent-ui-display-function #'agent-workspace--display-canvas)))
    (setq agent-workspace--canvas-fallback agent-ui-display-function
          agent-ui-display-function #'agent-workspace--display-canvas)))

(agent-workspace--take-canvases)
(add-hook 'agent-ui-canvas-hook #'agent-workspace--canvas-no-focus-h 90)

;; An agent's panels are its Agent UI's views too.
(defun agent-workspace--pane-views (session)
  "SESSION's more views (`agent-ui-pane-views-functions'): its agent's
panels, if it's a crew's agent's."
  (when-let* ((agent (agent-workspace-buffer-agent session)))
    (agent-workspace-agent-panels agent)))

(add-hook 'agent-ui-pane-views-functions #'agent-workspace--pane-views)
