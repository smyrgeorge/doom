;;; $DOOMDIR/config/agent-ui/elements/countdown.el -*- lexical-binding: t; -*-
;; Agent UI's countdown: time that matters while waiting, ticking on the
;; canvas. Loaded from config/agent-ui/elements.el.
;;
;; SINCE a start: the time elapsed (a long job). UNTIL an end: the time left
;; (a deploy window, a rate limit's reset), in the warning colour its last
;; WARN seconds; past it: "ended 2m 05s ago", never negative. Each a
;; timestamp ("2026-11-10T18:30:00Z"), epoch seconds, or seconds from now (a
;; number under a billion: until in that many, since that many ago), made a
;; time when shown (redrawn, it doesn't start again). Animated: redrawn while
;; its canvas is in a window only (`agent-ui-animated').
;;
;;   Rate limit resets  4m 12s left
;;   Build running      12m 40s

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-countdown--time (value)
  "VALUE (a timestamp, epoch seconds, or seconds from now) as epoch
seconds; a relative one left as it is (made a time when shown); nil if it
isn't a time."
  (cond ((numberp value) value)
        ((stringp value)
         (ignore-errors (float-time (parse-iso8601-time-string value))))
        (t nil)))

(defun agent-ui-countdown--check (props)
  (let ((since (plist-get props :since))
        (until (plist-get props :until)))
    (unless (xor since until)
      (agent-ui--fail "countdown: give since (a start: the time elapsed) or until (an end: the time left)"))
    (unless (agent-ui-countdown--time (or since until))
      (agent-ui--fail "countdown: %s is a timestamp (\"2026-11-10T18:30:00Z\"), epoch seconds, or seconds from now"
                      (if since "since" "until")))
    (when (and (plist-get props :warn) (< (plist-get props :warn) 0))
      (agent-ui--fail "countdown: warn is seconds before the end, 0 or more")))
  props)

(defun agent-ui-countdown--prepare (element)
  "ELEMENT as it's kept: its since or until a time (seconds from now made
one, from the clock now; a timestamp in epoch seconds)."
  (let ((element (copy-sequence element))
        (now (funcall agent-ui-clock)))
    (dolist (key '(:since :until))
      (when-let* ((value (plist-get element key))
                  (time (agent-ui-countdown--time value)))
        (setq element (plist-put element key
                                 (if (and (numberp value) (< value 1e9))
                                     (if (eq key :since) (- now value) (+ now value))
                                   time)))))
    element))

(defun agent-ui-countdown--state (props)
  "PROPS now: (TEXT FACE WORD), the time and what it is: elapsed, left, or
\"ended ... ago\"."
  (let* ((now (funcall agent-ui-clock))
         ;; Seconds from now still (drawn without being shown: a render):
         ;; from now.
         (at (lambda (key sign)
               (let ((value (plist-get props key)))
                 (if (and (numberp value) (< value 1e9))
                     (+ now (* sign value))
                   (agent-ui-countdown--time value)))))
         (since (funcall at :since -1))
         (until (funcall at :until 1)))
    (cond
     (since (list (agent-ui-format-duration (max 0 (- now since))) 'bold "elapsed"))
     ((>= now until) (list (format "ended %s ago" (agent-ui-format-duration (- now until))) 'agent-ui-muted nil))
     (t (let ((left (- until now)))
          (list (agent-ui-format-duration left)
                (if (and (plist-get props :warn) (<= left (plist-get props :warn))) 'agent-ui-warning 'bold)
                "left"))))))

(defun agent-ui-countdown--text (props ctx)
  "Its label, then the time and its word: the time kept whole, the label cut
first (4 columns at least, else left out), then the word left out (the
whole line was cut: \"Rate limit resets in  4…\")."
  (pcase-let* ((`(,time ,face ,word) (agent-ui-countdown--state props))
               (width (plist-get ctx :width))
               (label (plist-get props :label))
               (word (and word (plist-get props :until)
                          (<= (+ (string-width time) 1 (string-width word)) width)
                          word))
               (shown (concat (propertize time 'face face) (if word (concat " " word) "")))
               (room (- width (string-width shown) 2)))
    (if (and label (>= room (min 4 (string-width label))))
        (concat (propertize (agent-ui-truncate label room) 'face 'agent-ui-muted) "  " shown)
      (agent-ui-truncate shown width))))

(defun agent-ui-countdown--gui (props ctx)
  (pcase-let* ((`(,time ,face ,word) (agent-ui-countdown--state props))
               (cw (plist-get ctx :char-width))
               (lh (plist-get ctx :line-height))
               (w (min (* cw (plist-get ctx :width)) (* 28 cw)))
               (h (* 3 lh))
               (room (- w (* 2 cw)))
               ;; The time big, smaller if it doesn't fit; its word beside it
               ;; where there's room, else left out (they overlapped).
               (size (agent-ui-svg-fit-size time (* (if word 1.4 1.0) lh) room))
               (word-size (* 0.8 lh))
               (word (and word (<= (+ (agent-ui-svg-text-width time size) cw
                                      (agent-ui-svg-text-width word word-size))
                                   room)
                          word))
               (font (agent-ui--svg-font))
               (svg (svg-create w h)))
    (if (< (plist-get ctx :width) 16)
        (agent-ui-countdown--text props ctx)
      (svg-rectangle svg 0 0 w h :rx 6
                     :fill (agent-ui-blend (agent-ui-background) (agent-ui-color 'default) 0.07))
      (when-let* ((label (plist-get props :label)))
        (svg-text svg (agent-ui-truncate label (floor room (* 0.5 lh)))
                  :x cw :y (* 0.95 lh) :font-size (round (* 0.8 lh)) :font-family font
                  :fill (agent-ui-color 'agent-ui-muted)))
      (svg-text svg time :x cw :y (* 2.4 lh) :font-size (round size) :font-weight "bold"
                :font-family font :fill (agent-ui-color (if (eq face 'bold) 'default face)))
      (when word
        (svg-text svg word :x (- w cw) :y (* 2.4 lh) :text-anchor "end" :font-size (round word-size)
                  :font-family font :fill (agent-ui-color 'agent-ui-muted)))
      (propertize "countdown" 'display (agent-ui-svg-image svg)))))

(agent-ui-define countdown
  "Time that matters while waiting, ticking: SINCE a start (the time
elapsed: a long job) or UNTIL an end (the time left: a deploy window, a rate
limit's reset), each a timestamp, epoch seconds or seconds from now; LABEL;
WARN seconds before the end in the warning colour. Past the end: \"ended
2m ago\"."
  :props ((since any "A start: a timestamp, epoch seconds, or seconds ago")
          (until any "An end: a timestamp, epoch seconds, or seconds from now")
          (label string "What it counts")
          (warn number "Seconds before the end it's in the warning colour"))
  :example (:title "Rate limit" :label "Resets in" :until 252 :warn 60)
  :animated t
  :check #'agent-ui-countdown--check
  :prepare #'agent-ui-countdown--prepare
  :text #'agent-ui-countdown--text
  :gui #'agent-ui-countdown--gui)
