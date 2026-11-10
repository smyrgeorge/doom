;;; $DOOMDIR/config/agent-ui/elements/slider.el -*- lexical-binding: t; -*-
;; Agent UI's slider: a number the user tunes in a range (a threshold, a
;; timeout, how many to take). Loaded from config/agent-ui/elements.el.
;;
;; Its track, the knob at its value, MIN and MAX at its ends; on the track's
;; line, h / l (or ← / →) move it a STEP, H / L ten, a click puts it there:
;; its own keys there (a text property's map: elsewhere h and l are the
;; cursor's). Set puts "Answer to slider ID (LABEL): 42 ms" into the
;; session's prompt (sent at once); then it shows the
;; value set, and can't be changed. LIVE: each value sent once the knob rests
;; (`agent-ui-slider-live-delay'), no Set: for a canvas the agent redraws from
;; it. Its value is the element's own (:value, saved with the session).
;;
;;   Timeout
;;    0 ━━━━━━━━━━━●──────────────────── 120   42 ms
;;    h / l move it (H / L ten steps), a click puts it there
;;    ⏵ Set

(require 'cl-lib)
(require 'subr-x)

(defvar agent-ui-slider-live-delay 1.0
  "Seconds a live slider's knob rests before its value is sent.")

(defvar agent-ui-slider--live-timers (make-hash-table :test #'equal)
  "Live sliders' timers waiting to send, by (CANVAS . ID).")

;; ====== ITS VALUE ======

(defun agent-ui-slider--step (props)
  (or (plist-get props :step) 1))

(defun agent-ui-slider--decimals (number)
  "How many decimals NUMBER has (0.05: 2), 10 at most."
  (let ((decimals 0))
    (while (and (< decimals 10)
                (let ((scaled (* number (expt 10.0 decimals))))
                  (> (abs (- scaled (fround scaled))) 1e-9)))
      (cl-incf decimals))
    decimals))

(defun agent-ui-slider--snap (props value)
  "VALUE on PROPS' steps from its min, within min and max: as many decimals
as its step and min have (0.1 six times: 0.6, not 0.6000000000000001)."
  (let* ((min (plist-get props :min))
         (max (plist-get props :max))
         (step (agent-ui-slider--step props))
         (snapped (+ min (* step (round (/ (float (- value min)) step))))))
    (setq snapped (if (and (integerp min) (integerp step))
                      ;; Integers stay integers.
                      (round snapped)
                    (let ((scale (expt 10.0 (max (agent-ui-slider--decimals step) (agent-ui-slider--decimals min)))))
                      (/ (fround (* snapped scale)) scale))))
    (max min (min max snapped))))

(defun agent-ui-slider--value (props)
  (agent-ui-slider--snap props (or (plist-get props :value) (plist-get props :min))))

(defun agent-ui-slider--shown (props value)
  "VALUE with PROPS' unit: \"42 ms\"."
  (concat (agent-ui-format-number value)
          (if-let* ((unit (plist-get props :unit))) (concat " " unit) "")))

(defun agent-ui-slider--check (props)
  (let ((min (plist-get props :min))
        (max (plist-get props :max))
        (step (plist-get props :step))
        (value (plist-get props :value)))
    (unless (< min max)
      (agent-ui--fail "slider: min must be below max"))
    (when (and step (<= step 0))
      (agent-ui--fail "slider: step must be above 0"))
    (when (and value (or (< value min) (> value max)))
      (agent-ui--fail "slider: value %s is outside %s to %s"
                      (agent-ui-format-number value) (agent-ui-format-number min) (agent-ui-format-number max))))
  props)

;; ====== MOVING IT ======

(defun agent-ui-slider--set (props ctx value)
  "The knob put at VALUE (snapped); a live one's value sent once it rests."
  (let ((value (agent-ui-slider--snap props value)))
    (agent-ui-ask-change ctx (list :value value))
    (when (plist-get props :live)
      (agent-ui-slider--send-later props ctx value))))

(defun agent-ui-slider--send-later (props ctx value)
  "A live slider's VALUE sent once its knob rests."
  (let* ((canvas (current-buffer))
         (key (cons canvas (plist-get ctx :id)))
         (old (gethash key agent-ui-slider--live-timers)))
    (when (timerp old) (cancel-timer old))
    (puthash key
             (run-with-timer agent-ui-slider-live-delay nil
                             (lambda ()
                               (remhash key agent-ui-slider--live-timers)
                               (when (buffer-live-p canvas)
                                 (with-current-buffer canvas
                                   (funcall agent-ui-action-function
                                            (format "Slider %s (%s) set to %s" (plist-get ctx :id)
                                                    (plist-get props :label) (agent-ui-slider--shown props value))
                                            t)))))
             agent-ui-slider--live-timers)))

(defun agent-ui-slider--slide (steps)
  "Move the knob on point's line STEPS steps (below 0: left)."
  (agent-ui--flush)
  (let ((slide (get-text-property (point) 'agent-ui-slide)))
    (unless slide
      (user-error "No slider here"))
    (funcall slide steps)
    (agent-ui--flush)))

(defun agent-ui-slider-left ()
  "Move the slider's knob a step left."
  (interactive)
  (agent-ui-slider--slide -1))

(defun agent-ui-slider-right ()
  "Move the slider's knob a step right."
  (interactive)
  (agent-ui-slider--slide 1))

(defun agent-ui-slider-left-more ()
  "Move the slider's knob ten steps left."
  (interactive)
  (agent-ui-slider--slide -10))

(defun agent-ui-slider-right-more ()
  "Move the slider's knob ten steps right."
  (interactive)
  (agent-ui-slider--slide 10))

(defun agent-ui-slider-click (event)
  "Put the slider's knob where EVENT clicked its track."
  (interactive "e")
  (let* ((pos (posn-point (event-start event)))
         (buffer (window-buffer (posn-window (event-start event)))))
    (with-current-buffer buffer
      (when-let* ((to (and pos (get-text-property pos 'agent-ui-slide-to))))
        (funcall to)
        (agent-ui--flush)))))

(defvar agent-ui-slider-track-map
  (let ((map (make-sparse-keymap)))
    (dolist (key '("h" "<left>")) (keymap-set map key #'agent-ui-slider-left))
    (dolist (key '("l" "<right>")) (keymap-set map key #'agent-ui-slider-right))
    (dolist (key '("H" "S-<left>")) (keymap-set map key #'agent-ui-slider-left-more))
    (dolist (key '("L" "S-<right>")) (keymap-set map key #'agent-ui-slider-right-more))
    (keymap-set map "<mouse-1>" #'agent-ui-slider-click)
    (keymap-set map "<down-mouse-1>" #'ignore)
    map)
  "The keys on a slider's track (a text property's map: above Vim's there).")

;; ====== DRAWING ======

(defun agent-ui-slider--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (min (plist-get props :min))
         (max (plist-get props :max))
         (value (agent-ui-slider--value props))
         (answered (agent-ui-ask-answered-p props))
         (moving (not (or answered (plist-get ctx :still))))
         (low (agent-ui-format-number min))
         (high (agent-ui-format-number max))
         ;; The value's column as wide as its widest (it doesn't jump).
         (shown-width (apply #'max (mapcar (lambda (v) (string-width (agent-ui-slider--shown props v)))
                                           (list min max value))))
         (track-width (max 5 (- width 1 (string-width low) 1 1 (string-width high) 3 shown-width)))
         (knob (round (* (1- track-width) (/ (float (- value min)) (- max min)))))
         (track (apply #'concat
                       (cl-loop for i below track-width
                                collect (let ((char (cond ((= i knob) (propertize "●" 'face 'agent-ui-accent))
                                                          ((< i knob) (propertize "━" 'face 'agent-ui-accent))
                                                          (t (propertize "─" 'face 'agent-ui-muted)))))
                                          (if moving
                                              (let ((to (+ min (* (- max min) (/ (float i) (1- track-width))))))
                                                (propertize char 'agent-ui-slide-to
                                                            (lambda () (agent-ui-slider--set props ctx to))
                                                            'mouse-face 'highlight))
                                            char)))))
         (line (concat " " (propertize low 'face 'agent-ui-muted) " " track " "
                       (propertize high 'face 'agent-ui-muted) "   "
                       (propertize (agent-ui-slider--shown props value) 'face 'bold))))
    (string-join
     (append
      (and (plist-get props :label) (list (propertize (agent-ui-truncate (plist-get props :label) width) 'face 'bold)))
      (list (if moving
                (propertize line
                            'keymap agent-ui-slider-track-map
                            'agent-ui-slide (lambda (steps)
                                              (agent-ui-slider--set props ctx (+ value (* steps (agent-ui-slider--step props)))))
                            'help-echo "h / l: a step, H / L: ten, a click: there")
              line))
      (cond
       (answered
        (list (concat " " (propertize "✓ " 'face 'agent-ui-success)
                      (propertize (concat "Set: " (agent-ui-slider--shown props value)) 'face 'agent-ui-muted))))
       ((not moving) nil)
       (t
        (append
         (list (propertize (concat " " (string-join (split-string (agent-ui-wrap "h / l move it (H / L ten steps), a click puts it there"
                                                                                 (- width 1))
                                                                   "\n")
                                                     "\n "))
                           'face 'agent-ui-muted))
         (unless (plist-get props :live)
           (list (concat " " (agent-ui-button
                              (propertize "⏵ Set" 'face 'agent-ui-action)
                              (lambda ()
                                (funcall agent-ui-action-function
                                         (format "Answer to slider %s (%s): %s" (plist-get ctx :id)
                                                 (or (plist-get props :label) "value") (agent-ui-slider--shown props value))
                                         t)
                                (agent-ui-ask-change ctx (list :answered (agent-ui-slider--shown props value))))
                              "RET: send the value"))))))))
     "\n")))

(agent-ui-define slider
  "A number the user tunes in a range (a threshold, a timeout, how many to
take): LABEL, MIN, MAX, STEP, UNIT, VALUE (where it starts). They move the
knob and press Set: \"Answer to slider ID (LABEL): 42 ms\" comes into your
prompt (at once). LIVE: each value, once the knob
rests, comes as \"Slider ID (LABEL) set to 42 ms\", no Set: for something you
redraw from it."
  :props ((label string "What it sets")
          (min number "Its lowest value" :required t)
          (max number "Its highest value" :required t)
          (step number "How much a step moves it (default 1)")
          (unit string "Its unit, after the value (ms, %)")
          (value number "Its value: where it starts, then the user's")
          (live boolean "Send each value once the knob rests (no Set)" :default :false)
          (answered string "The value set (then it can't be changed)"))
  :example (:title "Before I retry"
            :label "Timeout" :min 0 :max 120 :step 5 :unit "s" :value 30)
  :check #'agent-ui-slider--check
  :text #'agent-ui-slider--draw)
