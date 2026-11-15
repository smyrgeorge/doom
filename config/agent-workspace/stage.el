;;; $DOOMDIR/config/agent-workspace/stage.el -*- lexical-binding: t; -*-
;; The stage: the app's centre, every agent a pane. Loaded from
;; config/agent-workspace.el, after look.el. No Doom here.
;;
;; Every agent has a pane, in role order (they never move). One is open, the
;; selected agent's: its session, its line as its header line, and its side
;; area below it (beside it from 140 columns): its Agent UI canvases, when
;; they show something (its own, then its others: ask...), and its panels, as
;; tabs ("canvas │ ask │ logs"), one shown at a time, the tabs its header
;; line. Full size (V), the one shown takes the pane's whole room, the tabs at
;; its line's right. The others are folded: a one-row window each showing the
;; agent's bar (a window can't be its header line alone). Every pane folded:
;; a hint below the bars. The stage arranges itself: no border to drag; a
;; border dragged or the frame resized, it's tiled again (sizes taken as they
;; are after 3 layouts in 3 seconds: never a loop).
;;
;; The stage never changes an agent's session buffer: its windows' own
;; parameters hide their mode line and tab line and give the open pane its
;; header line. A canvas or panel it shows gets `agent-workspace-side-mode'
;; (the app's v and V in it).

(require 'cl-lib)
(require 'subr-x)

(declare-function agent-ui-canvas-buffer-name "agent-ui/canvas")
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

(defvar agent-workspace-tab-map (make-sparse-keymap)
  "Keys on a tab of an agent's side area: a click shows it.")

;; ====== A BAR ======

(define-derived-mode agent-workspace-bar-mode special-mode "Bar"
  "A folded pane's bar: one line, its agent's line."
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

(defun agent-workspace--clickable (line map)
  "LINE with MAP on it (a click selects its agent), hovered as `hl-line';
its buttons (a raised hand's) keep their own."
  (let ((line (copy-sequence line))
        (pos 0))
    (while (< pos (length line))
      (let ((next (or (next-single-property-change pos 'agent-workspace-button line) (length line))))
        (unless (get-text-property pos 'agent-workspace-button line)
          (add-text-properties pos next
                               (list 'keymap map 'local-map map 'mouse-face 'agent-workspace-hover
                                     'help-echo "Select this agent: its pane opens (mouse-3: its actions)")
                               line))
        (setq pos next)))
    line))

(defun agent-workspace--bar-draw (window)
  "WINDOW's bar drawn again, as wide as WINDOW."
  (with-current-buffer (window-buffer window)
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
        (set-window-start window (point-min) t)))))

(defun agent-workspace--tint-face (colour)
  "A face whose background is COLOUR (a display table's glyph needs a named
one)."
  (let ((face (intern (format "agent-workspace-tint-%s" (string-remove-prefix "#" colour)))))
    (unless (facep face)
      (make-face face)
      (set-face-background face colour))
    face))

(defun agent-workspace--pane-header ()
  "The open pane's header line: its agent's line (in its window's width);
its canvas or a panel shown there full size, their tabs at its right."
  (when-let* ((agent (or (agent-workspace-buffer-agent) (window-parameter nil 'agent-workspace-pane))))
    (string-replace "%" "%%" (agent-workspace--clickable
                              (agent-workspace-line agent (window-total-width) t nil
                                                    (and (window-parameter nil 'agent-workspace-side)
                                                         (agent-workspace--tabs-text agent (window-buffer))))
                              agent-workspace-line-map))))

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

(defun agent-workspace--hint-buffer (project)
  "What's below the bars when every pane is folded (or there's no agent):
how to open one, or make one."
  (let ((name (format "*stage · %s*" (file-name-nondirectory (directory-file-name project)))))
    (or (get-buffer name)
        (with-current-buffer (get-buffer-create name)
          (special-mode)
          (setq-local mode-line-format nil header-line-format nil tab-line-exclude t cursor-type nil)
          (agent-workspace--app-buffer-add project (current-buffer))
          (current-buffer)))))

(defun agent-workspace--hint-draw (project agents)
  "The hint below the bars: none yet, or every pane folded."
  (with-current-buffer (agent-workspace--hint-buffer project)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize (if agents
                              "\n  Every pane is folded.\n\n  Open one: TAB, a click or RET on its bar, j/k on the bars,\n  moving onto its issue in the list.\n"
                            "\n  No agents yet.\n\n  c: a new agent\n")
                          'face 'shadow)))))

(defun agent-workspace--show-pane (window agent)
  "AGENT's session (or its bar, if it has none) in WINDOW, at its end."
  (set-window-dedicated-p window nil)
  (set-window-parameter window 'agent-workspace-side nil)
  (let ((buffer (agent-workspace-agent-buffer agent)))
    (if (not (buffer-live-p buffer))
        (progn (set-window-buffer window (agent-workspace--bar-buffer agent))
               (agent-workspace--bar-draw window))
      (set-window-buffer window buffer)
      (set-window-parameter window 'header-line-format '(:eval (agent-workspace--pane-header)))
      (with-current-buffer buffer
        (set-window-point window (point-max))))
    (set-window-parameter window 'mode-line-format 'none)
    (set-window-parameter window 'tab-line-format 'none)
    (set-window-fringes window 0 0)
    (set-window-margins window 0 0)
    ;; No fringes: a wrapped line's mark, a cut one's, a space (not a \ or $
    ;; in the text), the window's own: its buffer untouched.
    (let ((table (make-display-table)))
      (set-display-table-slot table 'wrap ?\s)
      (set-display-table-slot table 'truncation ?\s)
      (set-window-display-table window table))))

(defun agent-workspace--show-bar (window agent)
  "AGENT's bar in WINDOW."
  (set-window-dedicated-p window nil)
  (set-window-parameter window 'agent-workspace-side nil)
  (set-window-buffer window (agent-workspace--bar-buffer agent))
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
                                   (error nil))))
                      (full (and (not (eq agent :hint)) (> rows agent-workspace--folded-rows)
                                 (agent-workspace--full-tab agent))))
                  (cond ((eq agent :hint)
                         (set-window-buffer w (agent-workspace--hint-buffer (agent-workspace-agent-project (car agents))))
                         (dolist (parameter '(header-line-format mode-line-format tab-line-format))
                           (set-window-parameter w parameter 'none))
                         (set-window-parameter w 'agent-workspace-side nil))
                        ((<= rows agent-workspace--folded-rows)
                         (agent-workspace--show-bar w agent))
                        (full
                         (agent-workspace--show-tab w agent full '(:eval (agent-workspace--pane-header))))
                        (t
                         (agent-workspace--show-pane w agent)
                         (when-let* ((side (agent-workspace--side-split w agent)))
                           (push side windows))))
                  (set-window-parameter w 'agent-workspace-pane (and (not (eq agent :hint)) agent))
                  (push w windows)
                  (if next (setq w next) (cl-return))))
    (nreverse windows)))

;; ====== ITS SIDE: ITS CANVASES AND PANELS, AS TABS ======
;; The open pane's side area holds the agent's canvas, its other canvases
;; (--canvas NAME: a question's, ask) when they show something, and its
;; panels (panels.el), as tabs: one shown at a time, the one last shown (by
;; v, a click, a canvas showing something new) still there, else the first.
;; A panel hidden fetches nothing (Agent UI's: it fetches while it's in a
;; window). Full size (V): the one shown in the pane's whole room.

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
  "AGENT's side area's tabs: its canvas, then its other canvases, if they
show something, then its panels; their buffers."
  (let ((canvas (agent-workspace--canvas agent)))
    (append (and canvas (list canvas))
            (agent-workspace--other-canvases agent)
            (and (fboundp 'agent-workspace-agent-panels) (agent-workspace-agent-panels agent)))))

(defun agent-workspace--side-tab (agent &optional tabs)
  "The tab AGENT's side area shows, of TABS (its tabs): the one last shown
that's still there (one gone: the one shown before it), else the first; nil
if it has none."
  (let ((tabs (or tabs (agent-workspace-agent-tabs agent)))
        (app (agent-workspace--app (agent-workspace-agent-project agent))))
    (or (seq-find (lambda (tab) (memq tab tabs))
                  (and app (alist-get agent (agent-workspace--app-tabs app))))
        (car tabs))))

(defun agent-workspace--full-tab (agent)
  "The tab AGENT's open pane shows full size, or nil."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent)))
              ((eq (agent-workspace--app-full app) agent)))
    (agent-workspace--side-tab agent)))

(defun agent-workspace--tab-name (tab)
  "TAB's name: its panel's (\"tests\"), its other canvas's (\"ask\"), or
\"canvas\"."
  (if-let* (((boundp 'agent-ui-panels--state))
            (panel (buffer-local-value 'agent-ui-panels--state tab)))
      (agent-ui-panels--name panel)
    (or (and (boundp 'agent-ui--canvas-part) (buffer-local-value 'agent-ui--canvas-part tab))
        "canvas")))

(defun agent-workspace--tabs-text (agent shown)
  "AGENT's tabs between │, SHOWN's bold in its colour, the others dimmed:
each a button (a click shows it)."
  (mapconcat (lambda (tab)
               (propertize (agent-workspace--tab-name tab)
                           'face (if (eq tab shown) (list (agent-workspace--fg agent) 'bold) 'shadow)
                           'agent-workspace-tab tab
                           'agent-workspace-button t
                           'mouse-face 'agent-workspace-hover
                           'help-echo "Show it (v: the next one, V: full size)"
                           'keymap agent-workspace-tab-map
                           'local-map agent-workspace-tab-map))
             (agent-workspace-agent-tabs agent)
             (propertize " │ " 'face 'shadow)))

(defun agent-workspace--side-header ()
  "The side area's header line: its agent's tabs, the one shown marked; v
and V at its right. Tinted in its colour, as a bar."
  (when-let* ((agent (window-parameter nil 'agent-workspace-side)))
    (string-replace "%" "%%" (agent-workspace--clickable
                              (agent-workspace--tint
                               (agent-workspace--at-right
                                (concat " " (agent-workspace--tabs-text agent (window-buffer)))
                                (propertize "v: next · V: full size " 'face 'shadow)
                                (window-total-width))
                               (agent-workspace-agent-face agent) 0.14)
                              agent-workspace-line-map))))

(define-minor-mode agent-workspace-side-mode
  "An agent's canvas or panel shown in its pane on the stage: v shows the
next one, V the one there full size."
  :lighter nil
  ;; Evil's keys of its map, in this buffer from now.
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(defun agent-workspace--show-tab (window agent tab header)
  "TAB, of AGENT's side area, in WINDOW, its header line HEADER."
  (set-window-dedicated-p window nil)
  (set-window-buffer window tab)
  (dolist (parameter '(mode-line-format tab-line-format))
    (set-window-parameter window parameter 'none))
  (set-window-display-table window nil)
  (set-window-parameter window 'header-line-format header)
  (set-window-parameter window 'agent-workspace-side agent)
  (with-current-buffer tab
    (unless agent-workspace-side-mode
      (agent-workspace-side-mode 1))))

(defun agent-workspace--side-split (window agent)
  "AGENT's side area in its open pane WINDOW: below its session, or beside
it in a pane 140 columns wide or more; its tab shown (see above). Its
window, or nil (no tab)."
  (when-let* ((tab (agent-workspace--side-tab agent)))
    (let* ((wide (>= (window-total-width window) 140))
           (new (condition-case nil
                    (let ((window-min-height 4) (window-min-width 30))
                      (if wide
                          (split-window window (- (round (* 0.45 (window-total-width window)))) 'right)
                        (split-window window (- (max 8 (round (* 0.45 (window-total-height window))))) 'below)))
                  (error nil))))
      (when new
        (agent-workspace--show-tab new agent tab '(:eval (agent-workspace--side-header)))
        new))))

(defun agent-workspace--side-window (agent)
  "The window AGENT's side area shows its tab in (its pane's, full size),
or nil."
  (when-let* ((app (agent-workspace--app (agent-workspace-agent-project agent)))
              ((agent-workspace--shown-p app)))
    (seq-find (lambda (window) (eq (window-parameter window 'agent-workspace-side) agent))
              (window-list (agent-workspace--app-frame app) 'nomini))))

;; ====== ITS CANVASES: NEVER POPPED UP ======
;; A canvas of a crew's agent (its own, or another of its session's: ask,
;; tests) isn't shown by Agent UI where it would (a pane of its own, tiled):
;; the stage puts it in its agent's open pane, when it shows something new:
;; its tab shown. A question there takes no focus: the agent's raised hand
;; says it, as for a permission (a goes there). Closed or emptied (q, a
;; question answered), its tab goes (app.el): the side area shows the one
;; shown before, or closes.

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
