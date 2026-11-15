;;; $DOOMDIR/config/agent-workspace/stage.el -*- lexical-binding: t; -*-
;; The stage: the app's centre, every agent a pane. Loaded from
;; config/agent-workspace.el, after look.el. No Doom here.
;;
;; Every agent has a pane, in role order (they never move). One is open, the
;; selected agent's: its session, its line as its header line, its Agent UI
;; canvas below it (beside it from 140 columns) when the canvas shows
;; something. The others are folded: a one-row window each showing the
;; agent's bar (a window can't be its header line alone). Every pane folded:
;; a hint below the bars. The stage arranges itself: no border to drag; a
;; border dragged or the frame resized, it's tiled again (sizes taken as they
;; are after 3 layouts in 3 seconds: never a loop).
;;
;; The stage never changes an agent's session buffer: its windows' own
;; parameters hide their mode line and tab line and give the open pane its
;; header line.

(require 'cl-lib)
(require 'subr-x)

(declare-function agent-ui-canvas-buffer-name "agent-ui/canvas")
(declare-function agent-ui--session-name "agent-ui/agent")
(defvar agent-ui-display-function)

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
  "LINE with MAP on it (a click selects its agent), hovered as `hl-line'."
  (let ((line (copy-sequence line)))
    (add-text-properties 0 (length line)
                         (list 'keymap map 'local-map map 'mouse-face 'agent-workspace-hover
                               'help-echo "Select this agent: its pane opens (mouse-3: its actions)")
                         line)
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
  "The open pane's header line: its agent's line (in its window's width)."
  (when-let* ((agent (agent-workspace-buffer-agent)))
    (string-replace "%" "%%" (agent-workspace--clickable
                              (agent-workspace-line agent (window-total-width) t)
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
  (set-window-buffer window (agent-workspace--bar-buffer agent))
  (dolist (parameter '(header-line-format mode-line-format tab-line-format))
    (set-window-parameter window parameter 'none))
  (set-window-fringes window 0 0)
  (set-window-margins window 0 0)
  (agent-workspace--bar-draw window))

(defun agent-workspace--canvas (agent)
  "AGENT's Agent UI canvas, if it shows something."
  (when-let* (((fboundp 'agent-ui-canvas-buffer-name))
              (session (agent-workspace-agent-buffer agent))
              ((buffer-live-p session))
              (canvas (get-buffer (agent-ui-canvas-buffer-name (agent-ui--session-name session)))))
    (and (with-current-buffer canvas (> (buffer-size) 0)) canvas)))

(defun agent-workspace--canvas-split (window agent)
  "AGENT's canvas in its open pane WINDOW: below its session, or beside it
in a pane 140 columns wide or more. The canvas's window, or nil."
  (when-let* ((canvas (agent-workspace--canvas agent)))
    (let* ((wide (>= (window-total-width window) 140))
           (new (condition-case nil
                    (let ((window-min-height 4) (window-min-width 30))
                      (if wide
                          (split-window window (- (round (* 0.45 (window-total-width window)))) 'right)
                        (split-window window (- (max 8 (round (* 0.45 (window-total-height window))))) 'below)))
                  (error nil))))
      (when new
        (set-window-buffer new canvas)
        (dolist (parameter '(mode-line-format tab-line-format))
          (set-window-parameter new parameter 'none))
        (set-window-parameter new 'agent-workspace-canvas agent)
        new))))

(defun agent-workspace--stack (area agents open)
  "AGENTS' panes stacked in window AREA, all folded but OPEN's (its canvas in
it): their windows."
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
                                   (error nil)))))
                  (cond ((eq agent :hint)
                         (set-window-buffer w (agent-workspace--hint-buffer (agent-workspace-agent-project (car agents))))
                         (dolist (parameter '(header-line-format mode-line-format tab-line-format))
                           (set-window-parameter w parameter 'none)))
                        ((<= rows agent-workspace--folded-rows)
                         (agent-workspace--show-bar w agent))
                        (t
                         (agent-workspace--show-pane w agent)
                         (when-let* ((canvas (agent-workspace--canvas-split w agent)))
                           (push canvas windows))))
                  (set-window-parameter w 'agent-workspace-pane (and (not (eq agent :hint)) agent))
                  (push w windows)
                  (if next (setq w next) (cl-return))))
    (nreverse windows)))

;; ====== ITS CANVAS: NEVER POPPED UP ======
;; A canvas of a crew's agent isn't shown by Agent UI where it would (a pane of
;; its own, tiled): the stage puts it in its agent's open pane, when it shows
;; something.

(defun agent-workspace--canvas-agent (canvas)
  "The crew's agent whose session CANVAS is, or nil."
  (when-let* ((session (and (boundp 'agent-ui--session-buffer)
                            (buffer-local-value 'agent-ui--session-buffer canvas))))
    (and (buffer-live-p session) (agent-workspace-buffer-agent session))))

(defun agent-workspace--display-canvas (canvas)
  "Agent UI's display function: a crew's agent's CANVAS goes in its open
pane (the stage laid out again); any other as Agent UI shows it."
  (if-let* ((agent (agent-workspace--canvas-agent canvas)))
      (agent-workspace--canvas-changed agent)
    (funcall (or agent-workspace--canvas-fallback #'ignore) canvas)))

(defun agent-workspace--take-canvases ()
  "Agent UI's canvases of crews' agents shown by the stage (see above)."
  (when (and (boundp 'agent-ui-display-function)
             (not (eq agent-ui-display-function #'agent-workspace--display-canvas)))
    (setq agent-workspace--canvas-fallback agent-ui-display-function
          agent-ui-display-function #'agent-workspace--display-canvas)))

(agent-workspace--take-canvases)
