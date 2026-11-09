;;; $DOOMDIR/config/agent-ui/elements/progress.el -*- lexical-binding: t; -*-
;; Agent UI's progress bar: VALUE of MAX, a label; without MAX, a block going
;; to and fro until it's done. Loaded from
;; config/agent-ui/elements.el.
;;
;;   ███████████████▎░░░░░░░░░░  7/12  58%  linking

(require 'cl-lib)
(require 'subr-x)
(require 'color)

(defconst agent-ui-progress--eighths [" " "▏" "▎" "▍" "▌" "▋" "▊" "▉"]
  "A cell partly filled, by eighths.")

(defun agent-ui-progress--fill-face (status)
  (pcase status ('done 'agent-ui-success) ('failed 'agent-ui-error) (_ 'agent-ui-accent)))

(defun agent-ui-progress--bar (fraction width face)
  "A bar WIDTH cells wide, FRACTION (0 to 1) of it filled in FACE."
  (let* ((cells (* (min 1.0 (max 0.0 fraction)) width))
         (full (floor cells))
         (part (if (< full width) (floor (* (- cells full) 8)) 0))
         (filled (concat (make-string full ?█)
                         (if (> part 0) (aref agent-ui-progress--eighths part) ""))))
    (concat (propertize filled 'face face)
            (propertize (make-string (- width (length filled)) ?░) 'face 'agent-ui-muted))))

(defun agent-ui-progress--bounce (tick width face)
  "A bar WIDTH cells wide, a block in FACE at a place TICK says, going to
and fro."
  (let* ((block (min 4 width))
         (span (- width block))
         (period (max 1 (* 2 span)))
         (step (mod tick period))
         (at (if (<= step span) step (- period step))))
    (concat (propertize (make-string at ?░) 'face 'agent-ui-muted)
            (propertize (make-string block ?█) 'face face)
            (propertize (make-string (- width at block) ?░) 'face 'agent-ui-muted))))

(defun agent-ui-progress--color (face)
  "FACE's foreground, a colour (#RRGGBB where it can say)."
  (let ((color (face-foreground face nil 'default)))
    (if (and (stringp color) (not (string-prefix-p "unspecified" color))) color "gray")))

(defun agent-ui-progress--blend (a b share)
  "Colour A with SHARE (0 to 1) of colour B in it."
  (let ((ra (color-name-to-rgb a)) (rb (color-name-to-rgb b)))
    (if (and ra rb)
        (apply #'color-rgb-to-hex (append (cl-mapcar (lambda (x y) (+ (* x (- 1 share)) (* y share))) ra rb)
                                          '(2)))
      a)))

(defun agent-ui-progress--seamless (text)
  "TEXT, a bar's line, its blocks as spaces on their colour: in a graphic
frame, glyphs drawn one by one leave seams between them."
  (let ((bg (or (face-background 'default nil t) "black"))
        (pos 0)
        (out nil))
    (while (< pos (length text))
      (let* ((c (aref text pos))
             (next (or (next-single-property-change pos 'face text) (length text)))
             (run-end (let ((i pos)) (while (and (< i next) (eq (aref text i) c)) (cl-incf i)) i)))
        (push (pcase c
                (?█ (propertize (make-string (- run-end pos) ?\s)
                                'face (list :background (agent-ui-progress--color (get-text-property pos 'face text)))))
                (?░ (propertize (make-string (- run-end pos) ?\s)
                                'face (list :background (agent-ui-progress--blend
                                                         bg (agent-ui-progress--color 'agent-ui-muted) 0.3))))
                (_ (substring text pos run-end)))
              out)
        (setq pos run-end)))
    (apply #'concat (nreverse out))))

(defun agent-ui-progress--counts (props)
  "\"7/12 files  58%\", or without a max \"37 files\" (\"\" if nothing done)."
  (let* ((value (plist-get props :value))
         (max (plist-get props :max))
         (unit (plist-get props :unit))
         (unit (if (and unit (not (string-empty-p unit))) (concat " " unit) "")))
    (if max
        (format "%s/%s%s  %d%%"
                (agent-ui-format-number value) (agent-ui-format-number max) unit
                (floor (* 100 (min 1.0 (max 0.0 (/ (float value) max))))))
      (if (and (numberp value) (/= value 0))
          (concat (agent-ui-format-number value) unit)
        ""))))

(defun agent-ui-progress--text (props ctx)
  (let* ((status (plist-get props :status))
         (max (plist-get props :max))
         (face (agent-ui-progress--fill-face status))
         (counts (agent-ui-progress--counts props))
         (mark (pcase status ('done "✓") ('failed "✗") (_ "")))
         (width (plist-get ctx :width))
         (text (or (plist-get props :label) ""))
         (label (string-join (seq-remove #'string-empty-p
                                         (list (propertize mark 'face face) text))
                             " "))
         ;; What's left after the counts: all the bar's without a label (but
         ;; its mark), else shared with it.
         (rest (- width (string-width counts) 4))
         (bar-width (max 10 (min 40 (if (string-empty-p text)
                                        (- rest (string-width label))
                                      (floor (* rest 0.6))))))
         (bar (cond
               (max (agent-ui-progress--bar (/ (float (plist-get props :value)) max) bar-width face))
               ((eq status 'running)
                (agent-ui-progress--bounce (plist-get ctx :tick) bar-width face))
               (t (agent-ui-progress--bar 1.0 bar-width face))))
         (line (string-join (seq-remove #'string-empty-p (list bar counts)) "  "))
         (room (- width (string-width line) 2)))
    (if (or (string-empty-p label) (< room 4))
        line
      (concat line "  " (agent-ui-truncate label room)))))

(agent-ui-define progress
  "A progress bar: VALUE of MAX, with a LABEL saying what's being done.
Without MAX, no end is known: a block goes to and fro while it's running.
STATUS done or failed colours it and stops it."
  :props ((value number "Done so far" :default 0)
          (max number "The total; none: no end known")
          (label string "What's being done now, after the bar")
          (unit string "What VALUE counts (files, MB), after it")
          (status (choice running done failed) "running; done or failed colour it and stop it"
                  :default running))
  :example (:title "Build" :value 7 :max 12 :label "linking")
  :animated (lambda (props)
              (and (null (plist-get props :max)) (eq (plist-get props :status) 'running)))
  :check (lambda (props)
           (let ((max (plist-get props :max)))
             (when (and max (<= max 0))
               (agent-ui--fail "progress: max must be above 0, not %s" (agent-ui-format-number max))))
           props)
  :text #'agent-ui-progress--text
  :gui (lambda (props ctx) (agent-ui-progress--seamless (agent-ui-progress--text props ctx))))
