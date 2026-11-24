;;; $DOOMDIR/config/agent-ui/elements/activity.el -*- lexical-binding: t; -*-
;; Agent UI's activity: what one thing is doing now (a script running, an
;; agent at work), a box of a few lines. Loaded from
;; config/agent-ui/elements.el, after log.el (its lines read as a log's).
;;
;; Its header a line: a mark (its state: ● running, ◆ asks you), its
;; owner in its colour (as a log's sources: by its place in SOURCES, else
;; by its name), its label, its detail muted, RIGHT at its end (how long it's
;; run). Under it its last SHOW lines on a rail, each cut to the width (a
;; line a log's: text, its level found by its words, or {text, level,
;; mark, mark-face}, its text pieces), EMPTY said while it has none; its
;; FOOTER closing the rail.
;;
;;   ●  capture  screenshots.sh · step 1 of 2 · try 2           1m 23s
;;      │ ❯ .agent-workflow/scripts/screenshots.sh
;;      │ wrote .agent-ui/screens/pane.png (182 KB)
;;      │ error: window "Agent UI: review" not found
;;      ╰ the last 3 of 214 lines · 1 error

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-activity--rail "   │ "
  "A line's start under an activity's header.")

(defun agent-ui-activity--header (props width)
  "PROPS' header line, WIDTH wide: its mark, owner, label, detail, its
right at its end (left out if it'd leave less than 8 columns before it);
cut with … if too long."
  (let* ((mark (plist-get props :mark))
         (owner (plist-get props :owner))
         (detail (plist-get props :detail))
         (left (concat (if (and mark (not (string-empty-p mark)))
                           (concat (propertize mark 'face (agent-ui-log--face (plist-get props :mark-face))) "  ")
                         "")
                       (if owner
                           (concat (propertize owner 'face (agent-ui-log--source-face owner props)) "  ")
                         "")
                       (or (plist-get props :label) "")
                       (if (and detail (not (string-empty-p detail)))
                           (propertize (concat " · " detail) 'face 'agent-ui-muted)
                         "")))
         (right (plist-get props :right))
         (right (and right (not (string-empty-p right))
                     (propertize right 'face (or (agent-ui-log--face (plist-get props :right-face)) 'agent-ui-muted))))
         (room (- width (if right (+ 2 (string-width right)) 0))))
    (if (and right (>= room (min (string-width left) 8)))
        (let ((left (agent-ui-truncate left room)))
          (concat left (make-string (max 2 (- width (string-width left) (string-width right))) ?\s) right))
      (agent-ui-truncate left width))))

(defun agent-ui-activity--line (line width)
  "LINE (a log's, parsed: (LEVEL . TEXT), or (LEVEL . PARTS) in columns) on
the rail, WIDTH wide: its mark, its text, cut with … (one line each: its
whole elsewhere)."
  (let* ((parts (and (consp (cdr line)) (cdr line)))
         (mark (and parts (plist-get parts :mark)))
         (text (if parts
                   (plist-get parts :text)
                 (let ((face (nth 2 (assq (car line) agent-ui-log--levels))))
                   (if face (propertize (cdr line) 'face face) (cdr line)))))
         (text (replace-regexp-in-string "[\n\r]+" " " (agent-ui-untabify text)))
         (head (concat (propertize agent-ui-activity--rail 'face 'agent-ui-muted)
                       (if mark (concat (propertize mark 'face (plist-get parts :mark-face)) " ") ""))))
    (concat head (agent-ui-truncate text (max 1 (- width (string-width head)))))))

(defun agent-ui-activity--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (lines (last (agent-ui-log--lines (list :lines (plist-get props :lines) :keep 1000))
                      (plist-get props :show)))
         (footer (plist-get props :footer)))
    (concat (agent-ui-activity--header props width)
            (if lines
                (mapconcat (lambda (line) (concat "\n" (agent-ui-activity--line line width))) lines "")
              (let ((empty (plist-get props :empty)))
                (if (and empty (not (string-empty-p empty)))
                    (concat "\n" (propertize (concat agent-ui-activity--rail empty) 'face 'agent-ui-muted))
                  "")))
            (if footer
                ;; Muted, but its pieces given their own face.
                (let ((text (agent-ui-log--pieces (if (consp footer)
                                                      (mapcar (lambda (piece)
                                                                (if (consp piece) piece (list :text piece :face "muted")))
                                                              footer)
                                                    footer)
                                                  'agent-ui-muted)))
                  (concat "\n" (propertize "   ╰ " 'face 'agent-ui-muted)
                          (agent-ui-truncate (replace-regexp-in-string "[\n\r]+" " " text) (max 1 (- width 5)))))
              ""))))

(defun agent-ui-activity--check (props)
  (dolist (key '(:mark-face :right-face))
    (when-let* ((face (plist-get props key)))
      (unless (assoc (format "%s" face) agent-ui-log--faces)
        (agent-ui--fail "activity: %s %S is none of %s" (substring (symbol-name key) 1) face
                        (mapconcat #'car agent-ui-log--faces ", ")))))
  (unless (>= (plist-get props :show) 0)
    (agent-ui--fail "activity: show must be 0 or more, not %d" (plist-get props :show)))
  ;; Its lines a log's, checked as one's.
  (agent-ui-log--check (list :lines (plist-get props :lines) :keep 1000 :show 0))
  (let ((footer (plist-get props :footer)))
    (when (and footer (not (stringp footer)))
      (agent-ui-log--check-parts (list :text footer) 0)))
  props)

(agent-ui-define activity
  "What one thing is doing now (a script running, an agent at work): a
header line (a MARK for its state, coloured by MARK-FACE; its OWNER in its
colour, by its place in SOURCES as a log's; its LABEL; its DETAIL muted;
RIGHT at its end: how long it's run), its last SHOW LINES under it on a
rail, each cut to the width (a log's lines: text, its level found by its
words, or {\"text\", \"level\", \"mark\", \"mark-face\"}), EMPTY while it has
none, its FOOTER (text, muted, or pieces) closing them."
  :props ((label string "What it runs: screenshots.sh, agent build" :default "")
          (mark string "Its state's mark: ● running, ◆ asks you" :default "●")
          (mark-face string "Its mark's face: plain, muted, accent, success, warning, error, bold" :default "accent")
          (owner string "Whose it is (a job, a service): in its colour")
          (sources list "The owners in order: each its colour, as a log's sources")
          (detail string "Muted after its label: step 1 of 2 · try 2")
          (right string "At its header's end: how long it's run")
          (right-face string "Its right's face (default muted)")
          (lines any "Its lines, a log's: text, one per line, or a list (text, or {\"text\", \"level\", \"mark\", \"mark-face\"})" :default "")
          (show integer "How many of its last lines are shown" :default 5)
          (empty string "Said while it has no lines: No output yet.")
          (footer any "Closing its lines, muted: text, or pieces (text or {\"text\", \"face\"})"))
  :example (:label "screenshots.sh" :owner "capture" :detail "step 1 of 2" :right "1m 23s"
            :lines ((:mark "❯" :mark-face "muted" :level "debug" :text ".agent-workflow/scripts/screenshots.sh")
                    "wrote .agent-ui/screens/pane.png"
                    "error: window \"Agent UI: review\" not found")
            :footer "the last 3 of 214 lines")
  :check #'agent-ui-activity--check
  :text #'agent-ui-activity--draw)
