;;; $DOOMDIR/config/agent-workspace/look.el -*- lexical-binding: t; -*-
;; How an agent looks in the app. Loaded from config/agent-workspace.el,
;; after names.el. No Doom here.
;;
;; Glyphs: nerd icons in the GUI, in 2-column cells (Agent UI's
;; `agent-ui-even-glyphs'); in a terminal a Unicode set whose widths Emacs and
;; the terminal agree on. Avatars: in the GUI a rounded square in the agent's
;; colour with its initial (dimmed while it waits; a dot for a raised hand,
;; done, stuck), in a terminal "▌A". A state is never shown by colour alone:
;; its glyph and words always. Colours are faces only: the agent's ANSI face's
;; foreground; success, warning, error and shadow for states.
;;
;; An agent's line (its pane's header line, or its bar when its pane is
;; folded): ▾/▸, avatar, name (↻ while it loops), role, state glyph and words,
;; time; on the right its context used (20%, agent-shell's colours for it),
;; its panels counted (◫2), its permission mode, model and branch, at the
;; edge to the pixel; its canvas or a panel full size in its pane (V): their
;; tabs there instead. Tinted in its colour (30% its open pane's, 14% a bar),
;; the warning colour for a raised hand, its options then buttons before them
;; (hands.el). Under 90 columns: name, state, buttons, context and panels
;; only.

(require 'cl-lib)
(require 'subr-x)

(declare-function nerd-icons-mdicon "nerd-icons")
(declare-function nerd-icons-codicon "nerd-icons")
;; The Beads panel's types' look (config/beads/look.el), if it's loaded.
(defvar +my/beads--types-look)
;; Agent UI's (agent-ui-core.el), loaded before.
(declare-function agent-ui-even-glyphs "agent-ui/core")
(declare-function agent-ui-svg-image "agent-ui/core")
(declare-function agent-ui--svg-font "agent-ui/core")
(declare-function agent-ui-blend "agent-ui/core")
(declare-function agent-ui-color "agent-ui/core")
(declare-function agent-ui-background "agent-ui/core")
(declare-function agent-workspace-agent-panels "agent-workspace/panels")
(declare-function agent-workspace--tab-name "agent-workspace/stage")
(declare-function agent-workspace--ask-key "agent-workspace/hands")
;; agent-shell's own, internal: guarded.
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell--context-usage-face "agent-shell-usage")
(declare-function agent-shell--format-usage "agent-shell-usage")
(defvar agent-shell--state)

;; ====== VARIABLES ======

(defvar agent-workspace-glyphs
  ;; what          nerd icon                        terminal
  '((waking       "nf-md-progress_clock"            "◌")
    (working      "nf-md-play_circle_outline"       "▶")
    (hand         "nf-md-hand_back_right"           "!")
    (done         "nf-md-check_circle_outline"      "✓")
    (desk         "nf-md-circle_outline"            "○")
    (nap          "nf-md-weather_night"             "☾")
    (loop         "nf-md-autorenew"                 "↻")
    (asleep       "nf-md-power_sleep"               "⏻")
    (stuck        "nf-md-alert_outline"             "⚠")
    (home         "nf-md-home_outline"              "×")
    (canvas       "nf-md-view_dashboard_outline"    "◫")
    (branch       "nf-md-source_branch"             "⑂"))
  "Each glyph: a nerd icon (GUI) and its terminal glyph. A role's comes from
its file (icon: NERD GLYPH).")

(defconst agent-workspace--state-faces
  '((waking . shadow) (hand . warning) (done . success) (nap . shadow) (stuck . error)
    (asleep . shadow) (home . shadow))
  "A state's face (none: the default's).")

(defconst agent-workspace--mode-labels
  '(("default" . "default") ("acceptEdits" . "accept-edits") ("plan" . "plan")
    ("dontAsk" . "dont-ask") ("bypassPermissions" . "bypass-permissions"))
  "Claude Code's permission modes as they're shown: kebab-case.")

(defface agent-workspace-hover '((t :inherit hl-line))
  "An agent's line under the mouse."
  :group 'agent-workspace)

(defface agent-workspace-label '((t))
  "An agent's role, permission mode, branch glyph and the dots between, on
its line (its bar, its pane's header line) and in its files' mode line: the
same for every agent, the colour of its state's words at the desk (none of
its own: the text's), readable on any agent's colour's tint (3.9 to 6.5 on
doom-one's; shadow was 1.1 to 1.9)."
  :group 'agent-workspace)

;; ====== GLYPHS ======

(defun agent-workspace--drawing-frame ()
  "The frame the current buffer is drawn for: the one of a window showing
it, else the selected one (a GUI frame and a terminal one on one Emacs:
each app drawn for its own, whichever is selected)."
  (window-frame (or (get-buffer-window (current-buffer) 'visible) (selected-window))))

(defun agent-workspace--graphic-p ()
  "Non-nil when drawing for a graphical frame: the current buffer's
\(`agent-workspace--drawing-frame')."
  (display-graphic-p (agent-workspace--drawing-frame)))

(defmacro agent-workspace--in-drawing-frame (&rest body)
  "BODY with the current buffer's frame (`agent-workspace--drawing-frame')
selected, its glyphs measured with its fonts, if it's another live frame
than the selected one (a redraw from a timer while another is selected)."
  (declare (indent 0) (debug t))
  `(let ((frame (agent-workspace--drawing-frame)))
     (if (or (eq frame (selected-frame)) (not (frame-live-p frame)))
         (progn ,@body)
       (with-selected-frame frame ,@body))))

(defvar agent-workspace--nerd-font 'unknown
  "Whether the nerd icons' font is installed: t, nil, or `unknown' (not
looked for yet).")

(defun agent-workspace--nerd-family ()
  "The nerd icons' font family (nerd-icons's, \"Symbols Nerd Font Mono\")."
  (or (bound-and-true-p nerd-icons-font-family) "Symbols Nerd Font Mono"))

(defun agent-workspace--nerd-font-p ()
  "Non-nil if the nerd icons' font is installed (looked for once): without
it (Linux by default) every icon is a box."
  (when (eq agent-workspace--nerd-font 'unknown)
    (setq agent-workspace--nerd-font
          (and (ignore-errors (find-font (font-spec :family (agent-workspace--nerd-family)))) t)))
  agent-workspace--nerd-font)

(defun agent-workspace--nerd (name)
  "The nerd icon NAME (\"nf-md-hammer\", a codicon \"nf-cod-bug\"), or nil
without nerd-icons or its font (the plain glyphs then, as in a terminal)."
  (when (and name (require 'nerd-icons nil t) (agent-workspace--nerd-font-p))
    (ignore-errors
      (substring-no-properties
       (cond ((string-prefix-p "nf-md-" name) (nerd-icons-mdicon name))
             ((string-prefix-p "nf-cod-" name) (nerd-icons-codicon name)))))))

(defun agent-workspace-glyph (what &optional face)
  "WHAT's glyph (a key of `agent-workspace-glyphs', or (NERD . GLYPH)), in
FACE: two columns wide."
  (let* ((entry (if (consp what) (list (car what) (cdr what)) (alist-get what agent-workspace-glyphs)))
         (nerd (and (agent-workspace--graphic-p) (agent-workspace--nerd (car entry))))
         (glyph (if nerd
                    (propertize nerd 'face (delq nil (list (list :family (agent-workspace--nerd-family)) face)))
                  (propertize (or (cadr entry) "?") 'face face))))
    (concat glyph (make-string (max 0 (- 2 (string-width glyph))) ?\s))))

(defun agent-workspace--type-look (type)
  "How the Beads panel draws an issue's TYPE (bd's issue_type: \"bug\"...):
\(TYPE ICON FACE), from config/beads/look.el's `+my/beads--types-look' (read
there, never copied: the two never differ); nil for a type it doesn't
know, or none, or without it (no Doom)."
  (and type (boundp '+my/beads--types-look) (assoc type +my/beads--types-look)))

(defun agent-workspace-type-glyph (type &optional dim)
  "An issue's TYPE (bd's issue_type), one column, its word on hover: in the
GUI the Beads panel's icon in its colour (`agent-workspace--type-look'); in
a terminal, where its word is too wide, its first letter in that colour; a
type it has no look for, or none, a dim ·. DIM (a done issue's): shadow,
not its colour."
  (let* ((look (agent-workspace--type-look type))
         (face (if (or dim (not look)) 'shadow (nth 2 look)))
         (icon (and look (agent-workspace--graphic-p) (agent-workspace--nerd (nth 1 look))))
         (glyph (cond (icon (propertize icon 'face (list (list :family (agent-workspace--nerd-family)) face)))
                      (look (propertize (substring type 0 1) 'face face))
                      (t (propertize "·" 'face 'shadow)))))
    (if (and type (not (string-empty-p type)))
        (propertize glyph 'help-echo type)
      glyph)))

(defun agent-workspace-role-glyph (agent &optional face)
  "AGENT's role's glyph (its icon), in FACE."
  (let* ((role (agent-workspace-role agent))
         (icon (plist-get role :icon)))
    (agent-workspace-glyph (cons (and icon (concat "nf-" (string-remove-prefix "nf-" icon)))
                                 (or (plist-get role :glyph) "▶"))
                           face)))

;; ====== AN AGENT ======

(defun agent-workspace--fg (agent)
  "AGENT's colour as a face: its ANSI face's foreground only (those have a
background too)."
  (list :foreground (face-foreground (agent-workspace-agent-face agent) nil t)))

(defun agent-workspace-dim-p (agent)
  "Non-nil if AGENT is drawn dimmed: it isn't there to work (waking,
asleep, gone home)."
  (memq (agent-workspace-agent-state agent) '(waking asleep home)))

(defun agent-workspace-state-face (agent)
  "AGENT's state's face, or nil."
  (alist-get (agent-workspace-agent-state agent) agent-workspace--state-faces))

(defun agent-workspace-state-glyph (agent)
  "AGENT's state's glyph: its role's while it works."
  (let ((face (agent-workspace-state-face agent)))
    (if (eq (agent-workspace-agent-state agent) 'working)
        (agent-workspace-role-glyph agent face)
      (agent-workspace-glyph (agent-workspace-agent-state agent) face))))

(defun agent-workspace-state-words (agent)
  "AGENT's state in words, in its face (gone home struck through)."
  (let ((text (agent-workspace-state-text agent))
        (face (agent-workspace-state-face agent)))
    (pcase (agent-workspace-agent-state agent)
      ('home (propertize text 'face '(shadow (:strike-through t))))
      ('stuck (propertize (if-let* ((error (agent-workspace-agent-error agent)))
                              (format "%s: %s" text (car (split-string error "\n")))
                            text)
                          'face 'error))
      (_ (if face (propertize text 'face face) text)))))

(defun agent-workspace-time (agent)
  "How long AGENT's turn has run (\"4m\", \"1h 12m\"), or nil."
  (when-let* ((since (agent-workspace-agent-since agent)))
    (let ((m (floor (- (float-time) since) 60)))
      (cond ((< m 1) (format "%ds" (floor (- (float-time) since))))
            ((< m 60) (format "%dm" m))
            (t (format "%dh %dm" (/ m 60) (% m 60)))))))

(defun agent-workspace-time-text (agent time)
  "AGENT's turn TIME in its state's face, as its state's words: the text's
while it works (shadow was 1.1 to 1.6 contrast on its colour's tint),
dimmed while it isn't there to work."
  (if-let* ((face (agent-workspace-state-face agent))) (propertize time 'face face) time))

(defun agent-workspace-agent-avatar (agent)
  "AGENT's avatar, two columns: in the GUI its initial on its colour (dimmed
while it isn't there to work, a dot for a raised hand, done, stuck); in a
terminal ▌A."
  (let* ((initial (upcase (substring (agent-workspace-agent-name agent) 0 1)))
         (dim (agent-workspace-dim-p agent))
         (fg (agent-workspace--fg agent))
         (text (concat (propertize "▌" 'face fg)
                       (propertize initial 'face (if dim '(shadow bold) (list fg 'bold))))))
    (if (not (and (agent-workspace--graphic-p) (image-type-available-p 'svg)
                  (fboundp 'agent-ui-svg-image)))
        text
      (let* ((cw (frame-char-width)) (lh (frame-char-height))
             (w (* 2 cw))
             (bg (agent-ui-background))
             (colour (agent-ui-color (agent-workspace-agent-face agent)))
             (fill (if dim (agent-ui-blend bg colour 0.4) colour))
             (badge (pcase (agent-workspace-agent-state agent)
                      ('hand 'warning) ('stuck 'error) ('done 'success)))
             (svg (svg-create w lh)))
        (svg-rectangle svg 1 1 (- w 2) (- lh 2) :rx 3.5 :fill fill)
        (svg-text svg initial :x (/ w 2.0) :y (* 0.74 lh) :text-anchor "middle"
                  :font-size (round (* 0.66 lh)) :font-weight "bold"
                  :font-family (agent-ui--svg-font) :fill bg)
        (when badge
          (svg-circle svg (- w 3.5) 3.5 3.2 :fill (agent-ui-color badge) :stroke bg :stroke-width 1.2))
        (propertize text 'display (agent-ui-svg-image svg))))))

(defun agent-workspace-agent-name-text (agent)
  "AGENT's name, bold in its colour (dimmed while it isn't there to work)."
  (propertize (agent-workspace-agent-name agent)
              'face (if (agent-workspace-dim-p agent) '(shadow bold) (list (agent-workspace--fg agent) 'bold))))

(defun agent-workspace-mode-label (mode)
  "MODE (Claude Code's id) as it's shown: kebab-case."
  (or (cdr (assoc mode agent-workspace--mode-labels)) mode))

;; ====== ITS CONTEXT ======

(defun agent-workspace-usage (agent)
  "How full AGENT's context is: its session's usage (agent-shell's :usage,
:context-used of :context-size tokens), or nil before it says."
  (when-let* ((buffer (agent-workspace-agent-buffer agent))
              ((buffer-live-p buffer))
              ((local-variable-p 'agent-shell--state buffer))
              (usage (map-elt (buffer-local-value 'agent-shell--state buffer) :usage))
              (used (map-elt usage :context-used))
              (size (map-elt usage :context-size))
              ((and (numberp used) (numberp size) (> used 0) (> size 0))))
    usage))

(defun agent-workspace-usage-text (agent)
  "AGENT's context used, a whole percentage (\"20%\") in agent-shell's
colour for it (green, from 60% yellow, from 85% red); its tokens and cost
on hover, as agent-shell's own indicator. nil before its session says, or
with an agent-shell that lacks these (internal) functions."
  (when-let* (((fboundp 'agent-shell--context-usage-face))
              (usage (agent-workspace-usage agent)))
    (let ((percent (floor (* 100.0 (map-elt usage :context-used)) (map-elt usage :context-size))))
      (propertize (format "%d%%" percent)
                  'face (agent-shell--context-usage-face percent)
                  'help-echo (and (fboundp 'agent-shell--format-usage) (agent-shell--format-usage usage))))))

(defun agent-workspace--usage-watch (agent buffer)
  "AGENT's session BUFFER followed: its line drawn again as its context's
usage changes (agent-shell's usage-update) and at a turn's end. In
`agent-workspace-session-functions'."
  (agent-shell-subscribe-to
   :shell-buffer buffer
   :on-event (lambda (event)
               (when (and (memq (alist-get :event event) '(usage-update turn-complete))
                          (eq (agent-workspace-agent-buffer agent) buffer))
                 (agent-workspace--changed agent 'usage)))))

(add-hook 'agent-workspace-session-functions #'agent-workspace--usage-watch)

;; ====== ITS LINE ======

(defun agent-workspace--fit (text width)
  "TEXT cut to WIDTH columns, … where cut."
  (if (<= (string-width text) width) text (truncate-string-to-width text width nil nil "…")))

(defun agent-workspace--tint (text face share)
  "TEXT with FACE's colour (SHARE of it) behind it. Not with 256 colours or
fewer (a terminal's): a blend from the theme's background there maps to odd
colours (amber as dark red, magenta as navy), dim text on it unreadable. (No
display, 0 colours: batch Emacs, tinted.)"
  (if (< 0 (display-color-cells) 257)
      text
    (let ((tint (agent-ui-blend (agent-ui-background) (agent-ui-color face) share))
          (text (copy-sequence text)))
      (add-face-text-property 0 (length text) (list :background tint) t text)
      text)))

(defun agent-workspace--percent-escaped (text)
  "TEXT for a header or mode line, where a % starts a construct: each %
doubled as itself, its colour, hover and keys kept (`string-replace''s %%
has none: a coloured 20% lost its colour)."
  (let ((parts nil) (start 0) at)
    (while (setq at (string-search "%" text start))
      (push (substring text start (1+ at)) parts)
      (push (substring text at (1+ at)) parts)
      (setq start (1+ at)))
    (apply #'concat (nreverse (cons (substring text start) parts)))))

(defun agent-workspace--at-right (left right width &optional fill)
  "LEFT, then RIGHT at the window's right edge (to the pixel in the GUI, its
glyphs evened), LEFT cut to WIDTH's columns left; the line to the edge in
the GUI, and in a terminal too with FILL (an agent's line, tinted to its
window's last column: a bar's $ there is a space in its tint)."
  (let* ((right (agent-ui-even-glyphs right))
         (gui (agent-workspace--graphic-p))
         ;; In a terminal `right' is past the window's border column, and the
         ;; last column is kept for a $: two short of it; LEFT a column
         ;; shorter still, a gap between them (the two columns aren't one).
         (end (if gui (list (string-pixel-width right)) (+ 2 (string-width right))))
         (left (agent-workspace--fit left (max 10 (- width (string-width right) (if gui 2 3))))))
    (concat left
            (propertize " " 'display `(space :align-to (- right ,end)))
            right
            (if (or gui fill) (propertize " " 'display '(space :align-to right)) ""))))

(defun agent-workspace-badge (agent)
  "AGENT's panels counted, \"◫2\" (their names its help), or nil if it has
none."
  (when-let* (((fboundp 'agent-workspace-agent-panels))
              (panels (agent-workspace-agent-panels agent)))
    (propertize (concat (string-trim-right (agent-workspace-glyph 'canvas)) (number-to-string (length panels)))
                'help-echo (format "Its panels: %s (v shows them)"
                                   (mapconcat #'agent-workspace--tab-name panels ", ")))))

(defun agent-workspace-line (agent width &optional open folded tabs)
  "AGENT's line, WIDTH columns: its pane's header line (OPEN: its pane is the
open one, tinted brighter) or its bar (FOLDED: ▸). TABS (its canvas and
panels', one shown full size in its pane) at its right, for its mode, model
and branch."
  (let* ((hand (eq (agent-workspace-agent-state agent) 'hand))
         (sep (propertize " · " 'face 'agent-workspace-label))
         (narrow (< width 90))
         (time (agent-workspace-time agent))
         (left (concat (if folded "▸" "▾") " "
                       (agent-workspace-agent-avatar agent) " "
                       (agent-workspace-agent-name-text agent)
                       (if (agent-workspace-agent-loop agent)
                           (concat " " (propertize (string-trim-right (agent-workspace-glyph 'loop))
                                                   'help-echo "It loops: once free, it takes the next ready issue (L)"))
                         "")
                       (if narrow "" (concat sep (propertize (agent-workspace-agent-role agent) 'face 'agent-workspace-label)))
                       sep
                       (agent-workspace-state-glyph agent)
                       (agent-workspace-state-words agent)
                       (if time (concat sep (agent-workspace-time-text agent time)) "")
                       ;; Its events waiting (inbox.el).
                       (if-let* ((mail (and (fboundp 'agent-workspace-inbox-badge)
                                            (agent-workspace-inbox-badge agent))))
                           (concat sep mail)
                         "")))
         (mode (agent-workspace-mode-of agent))
         (model (agent-workspace-model-of agent))
         (buttons (and hand (fboundp 'agent-workspace--hand-buttons)
                       (agent-workspace--hand-buttons
                        agent (agent-workspace--ask-key (agent-workspace-agent-ask agent)))))
         (badge (and (not tabs) (agent-workspace-badge agent)))
         ;; Its context used, first after a raised hand's buttons.
         (usage (agent-workspace-usage-text agent))
         (right (cond
                 (tabs (concat (if buttons (concat buttons "  ") "") (if usage (concat usage "  ") "") tabs " "))
                 (narrow (concat (string-join (delq nil (list buttons usage badge)) " ") " "))
                 (t (let ((settings (string-join (delq nil (list (and mode (agent-workspace-mode-label mode)) model))
                                                 " ")))
                      (concat (if buttons (concat buttons "  ") "")
                              (if usage (concat usage "  ") "")
                              (if badge (concat badge "  ") "")
                              (propertize settings 'face 'agent-workspace-label)
                              (when-let* ((branch (agent-workspace-agent-branch agent)))
                                (concat (if (string-empty-p settings) "" sep)
                                        (propertize (concat (agent-workspace-glyph 'branch 'agent-workspace-label) branch)
                                                    'help-echo (format "Its worktree: %s"
                                                                       (abbreviate-file-name
                                                                        (or (agent-workspace-agent-worktree agent) ""))))))
                              " ")))))
         (line (agent-workspace--at-right left right width t)))
    (agent-ui-even-glyphs
     (agent-workspace--tint line (if hand 'warning (agent-workspace-agent-face agent)) (if open 0.3 0.14)))))

;; ====== THE TALLY ======

(defun agent-workspace-tally (agents &optional states)
  "AGENTS counted by what needs you: working, hands raised, done, stuck
\(\"▶2 !1 ✓1\"), each its glyph and count; nil if none. STATES: only
those (`hand', `done', `stuck': what needs you)."
  (let ((parts nil))
    (pcase-dolist (`(,state . ,face) '((working . nil) (hand . warning) (done . success) (stuck . error)))
      (let ((n (if (and states (not (memq state states)))
                   0
                 (seq-count (lambda (agent) (eq (agent-workspace-agent-state agent) state)) agents))))
        (when (> n 0)
          (push (concat (string-trim-right (agent-workspace-glyph state face))
                        (propertize (number-to-string n) 'face face))
                parts))))
    (when parts (string-join (nreverse parts) " "))))
