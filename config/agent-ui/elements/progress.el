;;; $DOOMDIR/config/agent-ui/elements/progress.el -*- lexical-binding: t; -*-
;; Agent UI's progress bar: VALUE of MAX, a label; without MAX, a block going
;; to and fro until it's done. Loaded from
;; config/agent-ui/elements.el.
;;
;;   ███████████████▎░░░░░░░░░░  7/12  58%  linking
;;
;; On a canvas it notes when its value rose (its times, kept with it: saved
;; with the canvas), and tells by itself how it goes. Values seconds apart (a
;; download, a build): its rate and, with a max, the time left, once they're
;; steady (a few values over a few seconds):
;;
;;   █████████▌░░░░░░░░░░░░░░░░  37/100 MB  37%  3.4 MB/s  19s left  downloading
;;
;; Minutes apart (work items: bugs fixed one by one), a second line: the time
;; elapsed (from its first value, or STARTED), ticking; the time an item
;; takes (the median of its latest, pauses left out); the time left (a range
;; when they vary a lot) and when it should end. Stopped: the time it took.
;;
;;   ████████▌░░░░░░░░░░░░░░░░░░░  12/58 bugs  20%  tiling: SPC w SPC
;;   1h 48m elapsed · ~9 min a bug (last 8) · ~6h 50m left, about 01:40
;;
;; With pie, drawn small (a panel's corner; a pie in the GUI, core.el's), the
;; time elapsed and left after its counts, as room allows:
;;
;;   ◑ 7/12  58%  linking

(require 'cl-lib)
(require 'subr-x)
(require 'color)
(require 'parse-time)

(defconst agent-ui-progress--eighths [" " "▏" "▎" "▍" "▌" "▋" "▊" "▉"]
  "A cell partly filled, by eighths.")

(defconst agent-ui-progress-window 30
  "Seconds of values its rate is taken over, back from the latest.")

(defconst agent-ui-progress-items 8
  "How many of its latest items the time an item takes is taken from.")

(defconst agent-ui-progress-item-gap (/ agent-ui-progress-window 2)
  "Seconds between its values (their median) over which it counts work
items (minutes apart) rather than a rate: its rate is steady only with 3
values in `agent-ui-progress-window'.")

(defcustom agent-ui-progress-pause (* 45 60)
  "Seconds an item took over which it was a pause (a night, lunch): left out
of the time an item takes."
  :type 'number :group 'agent-ui)

;; ====== ITS TIMES ======
;; Noted as it's shown and changed (its type's :prepare), in its own times
;; property: (:from TIME :values ((TIME VALUE)...) :ended TIME), its first
;; value's time, its values as they rose (the latest first: those of the
;; window, its latest items' at least), when it stopped.

(defun agent-ui-progress--time (value now)
  "VALUE (a timestamp, epoch seconds, or seconds ago: a number under a
billion) as epoch seconds, from NOW; nil if it isn't a time."
  (cond ((and (numberp value) (< value 1e9)) (- now value))
        ((numberp value) value)
        ((stringp value) (ignore-errors (float-time (parse-iso8601-time-string value))))))

(defun agent-ui-progress--times (props)
  "PROPS' times noted: a plist, nil if none (or not right)."
  (let ((times (plist-get props :times)))
    (and (agent-ui--plist-p times) times)))

(defun agent-ui-progress--samples (props)
  "PROPS' values noted, the latest first: ((TIME VALUE)...)."
  (let ((values (plist-get (agent-ui-progress--times props) :values)))
    (and (proper-list-p values)
         (seq-filter (lambda (s) (and (proper-list-p s) (numberp (car s)) (numberp (cadr s)))) values))))

(defun agent-ui-progress--stopped-p (props)
  "Whether it stopped: done, failed, or at its max."
  (let ((max (plist-get props :max))
        (value (plist-get props :value)))
    (or (member (format "%s" (or (plist-get props :status) "running")) '("done" "failed"))
        (and (numberp max) (numberp value) (>= value max)))))

(defun agent-ui-progress--noted (element now)
  "ELEMENT with its times noted at NOW (see above): a new value (a lower one
starts them again; one within a second of the one before the latest
replaces the latest), its first value's time, when it stopped; STARTED made
epoch seconds. Noted already: as it is."
  (let* ((element (copy-sequence element))
         (value (or (plist-get element :value) 0))
         (times (copy-sequence (agent-ui-progress--times element)))
         (samples (agent-ui-progress--samples element))
         (last (car samples))
         (started (plist-get element :started)))
    (when (numberp value)
      (setq samples (cond ((or (null last) (< value (cadr last))) (list (list now value)))
                          ((= value (cadr last)) samples)
                          ((and (cadr samples) (< (- now (car (cadr samples))) 1))
                           (cons (list now value) (cdr samples)))
                          (t (cons (list now value) samples))))
      ;; Those of the window, the latest items' at least (pauses among them).
      (let ((from (- (caar samples) agent-ui-progress-window)))
        (setq samples (seq-take samples (max (cl-count-if (lambda (s) (>= (car s) from)) samples)
                                             (+ 4 agent-ui-progress-items))))))
    (setq times (plist-put times :values samples))
    (unless (numberp (plist-get times :from))
      (setq times (plist-put times :from now)))
    (setq times (cond ((not (agent-ui-progress--stopped-p element)) (agent-ui--plist-delete times :ended))
                      ((numberp (plist-get times :ended)) times)
                      (t (plist-put times :ended now))))
    (when-let* ((time (and started (agent-ui-progress--time started now))))
      (setq element (plist-put element :started time)))
    (plist-put element :times times)))

;; ====== ITS RATE: VALUES SECONDS APART ======

(defun agent-ui-progress--rate (samples)
  "SAMPLES' rate, a second, once it's steady (3 values or more, over 2
seconds or more); else nil."
  (let ((newest (car samples)) (oldest (car (last samples))))
    (when (and (>= (length samples) 3) (>= (- (car newest) (car oldest)) 2))
      (/ (float (- (cadr newest) (cadr oldest))) (- (car newest) (car oldest))))))

(defun agent-ui-progress--per (rate unit)
  "RATE (a second) as text, with UNIT: 12 files/s, 3.4 MB/s, 20/min."
  (let ((unit (if (and unit (not (string-empty-p unit))) (concat " " unit) "")))
    (cl-flet ((amount (n) (agent-ui-format-number (if (< n 10) (/ (round (* n 10)) 10.0) (round n)))))
      (cond ((>= rate 1) (format "%s%s/s" (amount rate) unit))
            ((>= (* rate 60) 1) (format "%s%s/min" (amount (* rate 60)) unit))
            (t (format "%s%s/h" (amount (* rate 3600)) unit))))))

(defun agent-ui-progress--pace (props)
  "Its rate and time left (\"3.4 MB/s\" \"19s left\"), from its values
noted on a canvas: a list; nil when not running, not steady, or its values
come minutes apart (then see `agent-ui-progress--timing')."
  (let* ((value (plist-get props :value))
         (max (plist-get props :max))
         (samples (agent-ui-progress--samples props))
         (now (funcall agent-ui-clock))
         (from (and samples (- (caar samples) agent-ui-progress-window)))
         ;; Not moved for longer than the window: stalled, no rate (it
         ;; kept its last one, and \"1s left\" forever).
         (rate (and samples
                    (eq (plist-get props :status) 'running)
                    (not (and max (>= value max)))
                    (not (agent-ui-progress--items-p samples))
                    (<= (- now (caar samples)) agent-ui-progress-window)
                    (agent-ui-progress--rate (seq-take-while (lambda (s) (>= (car s) from)) samples)))))
    (when (and rate (> rate 0))
      (cons (agent-ui-progress--per rate (plist-get props :unit))
            (when max
              (let ((left (- (/ (- max (cadar samples)) rate) (- now (caar samples)))))
                ;; Past the end it foresaw: no time left to say.
                (when (>= left 1)
                  (list (concat (agent-ui-format-duration left) " left")))))))))

;; ====== ITS ITEMS: VALUES MINUTES APART ======

(defun agent-ui-progress--quantile (sorted q)
  "The Q quantile (0 to 1) of SORTED numbers, between its two nearest."
  (let* ((at (* q (1- (length sorted))))
         (low (floor at)))
    (if (>= (1+ low) (length sorted))
        (float (nth low sorted))
      (+ (nth low sorted) (* (- at low) (- (nth (1+ low) sorted) (nth low sorted)))))))

(defun agent-ui-progress--gaps (samples)
  "The gaps between SAMPLES, the latest first: ((SECONDS . RISE)...)."
  (cl-loop for (newer older) on samples
           while older
           collect (cons (- (car newer) (car older)) (- (cadr newer) (cadr older)))))

(defun agent-ui-progress--items-p (samples)
  "Whether SAMPLES came minutes apart: their latest gaps' median (pauses left
out, if not all) over `agent-ui-progress-item-gap'."
  (when-let* ((gaps (mapcar #'car (agent-ui-progress--gaps samples)))
              (gaps (seq-take (or (seq-remove (lambda (gap) (> gap agent-ui-progress-pause)) gaps) gaps)
                              agent-ui-progress-items)))
    (> (agent-ui-progress--quantile (sort gaps #'<) 0.5) agent-ui-progress-item-gap)))

(defun agent-ui-progress--item-times (samples)
  "The times its latest items took, the latest first: a gap shared by the
items it brought (a rise of 3: 3 items), one over `agent-ui-progress-pause'
left out; `agent-ui-progress-items' at most."
  (seq-take (cl-loop for (gap . rise) in (agent-ui-progress--gaps samples)
                     for each = (/ (float gap) rise)
                     unless (> each agent-ui-progress-pause)
                     append (make-list (max 1 (min agent-ui-progress-items (round rise))) each))
            agent-ui-progress-items))

(defun agent-ui-progress--about (seconds)
  "SECONDS, roughly: 40s, 9 min, 6h 50m (to 5 minutes)."
  (let ((s (round seconds)))
    (cond ((< s 60) (format "%ds" (max 1 s)))
          ((< s 3570) (format "%d min" (round s 60)))
          (t (let ((m (* 5 (round s 300)))) (format "%dh %02dm" (/ m 60) (% m 60)))))))

(defun agent-ui-progress--span (low high)
  "LOW to HIGH seconds, roughly: 6–8h, 20–35 min, 40 min–2h; nil when they
read the same."
  (cond ((>= low 3600)
         (let ((a (round low 3600)) (b (round high 3600)))
           (and (/= a b) (format "%d–%dh" a b))))
        ((>= high 3600) (format "%d min–%dh" (max 1 (round low 60)) (round high 3600)))
        (t (let ((a (max 1 (round low 60))) (b (max 1 (round high 60))))
             (and (/= a b) (format "%d–%d min" a b))))))

(defun agent-ui-progress--one (unit)
  "An item of UNIT: \"a bug\" (bugs), \"an issue\"; without one: \"each\"."
  (if (or (null unit) (string-empty-p unit))
      "each"
    (let ((one (cond ((string-match "\\(.\\)ies\\'" unit) (replace-match "\\1y" t nil unit))
                     ((string-match "\\(?:ch\\|sh\\|ss\\|x\\|z\\)\\(es\\)\\'" unit) (replace-match "" t t unit 1))
                     ((string-match "[^s]\\(s\\)\\'" unit) (replace-match "" t t unit 1))
                     (t unit))))
      (concat (if (string-match-p "\\`[aeiouAEIOU]" one) "an " "a ") one))))

(defun agent-ui-progress--clock (time now)
  "TIME, an end foreseen from NOW, as a clock's time: 01:40; its day too
past 12 hours from now (Tue 01:40)."
  (format-time-string (if (< (- time now) (* 12 3600)) "%H:%M" "%a %H:%M") time))

(defun agent-ui-progress--timing (props)
  "What its second line says, from its times noted on a canvas: (:elapsed
TEXT :each TEXT :left TEXT :end TEXT), those it has; nil without a second
line (its values seconds apart, or one only so far; no STARTED given).
Stopped: the time it took only."
  (let* ((now (funcall agent-ui-clock))
         (samples (agent-ui-progress--samples props))
         (times (agent-ui-progress--times props))
         (start (or (and (plist-get props :started) (agent-ui-progress--time (plist-get props :started) now))
                    (and (numberp (plist-get times :from)) (plist-get times :from))))
         (items (agent-ui-progress--items-p samples))
         (stopped (agent-ui-progress--stopped-p props)))
    (when (and start (or items (plist-get props :started)))
      (let* ((ended (and stopped (numberp (plist-get times :ended)) (plist-get times :ended)))
             (timing (list :elapsed (concat (agent-ui-format-duration (max 0 (- (or ended now) start)))
                                            " elapsed")))
             (each (and items (not stopped) (agent-ui-progress--item-times samples))))
        (when each
          (let* ((sorted (sort (copy-sequence each) #'<))
                 (median (agent-ui-progress--quantile sorted 0.5))
                 (max (plist-get props :max))
                 (count (and max (- max (cadar samples))))
                 (since (- now (caar samples)))
                 ;; The time left at PER an item, the item going on begun
                 ;; SINCE ago (taking longer: done any time now).
                 (left (lambda (per) (max (- (* count per) since) (* (max 0 (1- count)) per))))
                 (single (and count (> count 0) (funcall left median)))
                 ;; They vary a lot: a range, from a quarter's to three
                 ;; quarters' time.
                 (spread (and single (>= single 1) (>= (length each) 4)
                              (let ((q1 (agent-ui-progress--quantile sorted 0.25))
                                    (q3 (agent-ui-progress--quantile sorted 0.75)))
                                (and (> (- q3 q1) (* 0.5 median))
                                     (cons (funcall left q1) (funcall left q3))))))
                 (span (and spread (agent-ui-progress--span (car spread) (cdr spread)))))
            (setq timing (append timing
                                 (list :each (concat "~" (agent-ui-progress--about median) " "
                                                     (agent-ui-progress--one (plist-get props :unit))
                                                     (if (cdr each) (format " (last %d)" (length each)) "")))))
            (when (and single (>= single 1))
              (setq timing
                    (append timing
                            (if span
                                (let ((from (agent-ui-progress--clock (+ now (car spread)) now))
                                      (to (agent-ui-progress--clock (+ now (cdr spread)) now)))
                                  (list :left (concat span " left")
                                        :end (concat "about " from (if (equal from to) "" (concat "–" to)))))
                              (list :left (concat "~" (agent-ui-progress--about single) " left")
                                    :end (concat "about " (agent-ui-progress--clock (+ now single) now)))))))))
        timing))))

(defun agent-ui-progress--timing-line (timing width)
  "TIMING (`agent-ui-progress--timing') as a line WIDTH wide at most, muted:
where it doesn't fit, the items an item's time is taken from left out, then
its figures dropped from the right, the first cut."
  (cl-flet ((parts (timing)
              (cl-loop for (key joiner) in '((:elapsed "") (:each " · ") (:left " · ") (:end ", "))
                       for text = (plist-get timing key)
                       when text collect (concat joiner text))))
    (let ((parts (parts timing)))
      (when-let* (((> (string-width (apply #'concat parts)) width))
                  (each (plist-get timing :each)))
        (setq parts (parts (plist-put (copy-sequence timing) :each
                                      (replace-regexp-in-string " (last [0-9]+)\\'" "" each)))))
      (while (and (cdr parts) (> (string-width (apply #'concat parts)) width))
        (setq parts (butlast parts)))
      (propertize (agent-ui-truncate (apply #'concat parts) (max 0 width)) 'face 'agent-ui-muted))))

;; ====== DRAWING ======

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

(defun agent-ui-progress--bounce-at (tick width)
  "(AT . BLOCK): where a bar WIDTH cells wide without an end has its block
at TICK (going to and fro), and how many cells it is."
  (let* ((block (min 4 width))
         (span (- width block))
         (period (max 1 (* 2 span)))
         (step (mod tick period)))
    (cons (if (<= step span) step (- period step)) block)))

(defun agent-ui-progress--bounce (tick width face)
  "A bar WIDTH cells wide, a block in FACE at a place TICK says, going to
and fro."
  (pcase-let ((`(,at . ,block) (agent-ui-progress--bounce-at tick width)))
    (concat (propertize (make-string at ?░) 'face 'agent-ui-muted)
            (propertize (make-string block ?█) 'face face)
            (propertize (make-string (- width at block) ?░) 'face 'agent-ui-muted))))

;; ROUNDED IN THE GUI
;; In a graphic frame the bar is drawn over its cells (as many columns, so
;; what follows it doesn't move): a rounded track (rx 2, as a chart's bars,
;; 0.6 of the line's height from 0.2) in the muted blend, and over it a
;; rounded rectangle in its fill's face: the fraction done, to the pixel
;; (nothing at 0), or the block going to and fro of a bar without an end.
;; Its cells' text stays the terminal's.
(defun agent-ui-progress--gui-bar (text width ctx face &optional fraction bounce)
  "TEXT, a bar WIDTH cells wide, drawn in the GUI (CTX: its cells' size)
over its cells (see ROUNDED IN THE GUI): FRACTION (0 to 1) of it filled in
FACE, or BOUNCE's block (AT . BLOCK cells)."
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (w (* cw width))
         (y (* 0.2 lh))
         (h (* 0.6 lh))
         (color (agent-ui-color face))
         (svg (svg-create w lh)))
    (svg-rectangle svg 0 y w h :rx 2 :fill (agent-ui-blend (agent-ui-background) (agent-ui-color 'agent-ui-muted) 0.3))
    (cond (bounce
           (svg-rectangle svg (* cw (car bounce)) y (* cw (cdr bounce)) h :rx 2 :fill color))
          ((and fraction (> fraction 0))
           (svg-rectangle svg 0 y (max 1 (* w (min 1.0 fraction))) h :rx 2 :fill color)))
    (propertize text 'display (agent-ui-svg-image svg))))

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

(defun agent-ui-progress--counts (props)
  "Its counts' parts: (\"7/12 files\" \"58%\"), or without a max (\"37 files\")
\(none if nothing done)."
  (let* ((value (plist-get props :value))
         (max (plist-get props :max))
         (unit (plist-get props :unit))
         (unit (if (and unit (not (string-empty-p unit))) (concat " " unit) "")))
    (if max
        (list (format "%s/%s%s" (agent-ui-format-number value) (agent-ui-format-number max) unit)
              (format "%d%%" (floor (* 100 (min 1.0 (max 0.0 (/ (float value) max)))))))
      (when (and (numberp value) (/= value 0))
        (list (concat (agent-ui-format-number value) unit))))))

(defun agent-ui-progress--line (props ctx)
  "Its bar's line: the bar, its counts and figures, its label."
  (let* ((status (plist-get props :status))
         (max (plist-get props :max))
         (face (agent-ui-progress--fill-face status))
         (width (plist-get ctx :width))
         ;; Its figures, the last left out while they don't fit beside a bar of
         ;; 3 cells (time left, rate, percentage), the counts cut last of all
         ;; (they were never cut: lines past the width).
         (parts (append (agent-ui-progress--counts props)
                        (mapcar (lambda (p) (propertize p 'face 'agent-ui-muted))
                                (agent-ui-progress--pace props))))
         (parts (progn (while (and (cdr parts) (> (+ 3 2 (string-width (string-join parts "  "))) width))
                         (setq parts (butlast parts)))
                       parts))
         (counts (agent-ui-truncate (string-join parts "  ") (max 0 (- width 5))))
         (mark (pcase status ('done "✓") ('failed "✗") (_ "")))
         (text (or (plist-get props :label) ""))
         (label (string-join (seq-remove #'string-empty-p
                                         (list (propertize mark 'face face) text))
                             " "))
         ;; What's left after the counts: all the bar's without a label (but
         ;; its mark), else shared with it.
         (rest (- width (string-width counts) 4))
         ;; 3 cells at least (it was 10: past narrow widths), no more than
         ;; the width leaves beside the counts.
         (bar-width (max 1 (min (max 3 (min 40 (if (string-empty-p text)
                                                    (- rest (string-width label))
                                                  (floor (* rest 0.6)))))
                                (- width (if (string-empty-p counts) 0 (+ 2 (string-width counts)))))))
         (fraction (cond (max (/ (float (plist-get props :value)) max))
                         ((not (eq status 'running)) 1.0)))
         (bar (if fraction
                  (agent-ui-progress--bar fraction bar-width face)
                (agent-ui-progress--bounce (plist-get ctx :tick) bar-width face)))
         ;; In the GUI: rounded, over its cells (see ROUNDED IN THE GUI).
         (bar (if (agent-ui--gui-p ctx)
                  (agent-ui-progress--gui-bar bar bar-width ctx face fraction
                                              (unless fraction
                                                (agent-ui-progress--bounce-at (plist-get ctx :tick) bar-width)))
                bar))
         (line (string-join (seq-remove #'string-empty-p (list bar counts)) "  "))
         (room (- width (string-width line) 2)))
    ;; A label with room (4 columns, or less if it's only a mark: a done bar
    ;; without a label lost its ✓, the bar taking all but its column).
    (if (or (string-empty-p label) (< room (min 4 (string-width label))))
        line
      (concat line "  " (agent-ui-truncate label room)))))

(defun agent-ui-progress--text (props ctx)
  "Its bar's line; its values minutes apart, a second line under it: the
time elapsed, an item takes, left (`agent-ui-progress--timing')."
  (let ((line (agent-ui-progress--line props ctx)))
    (if-let* ((timing (agent-ui-progress--timing props)))
        (concat line "\n" (agent-ui-progress--timing-line timing (plist-get ctx :width)))
      line)))

(defun agent-ui-progress--pie (props ctx)
  "PROPS drawn small (pie): a pie (a spinner while running without a max),
its counts, the time elapsed and left as room allows, its label, on one
line."
  (let* ((status (plist-get props :status))
         (max (plist-get props :max))
         (face (agent-ui-progress--fill-face status))
         (width (max 1 (- (plist-get ctx :width) 2)))
         (pie (cond (max (agent-ui-pie (/ (float (plist-get props :value)) max) ctx face))
                    ((eq status 'running) (concat (agent-ui-spinner ctx face) " "))
                    (t (agent-ui-pie 1.0 ctx face))))
         (mark (pcase status ('done (propertize "✓" 'face face)) ('failed (propertize "✗" 'face face)) (_ nil)))
         (label (plist-get props :label))
         (timing (agent-ui-progress--timing props))
         (figures (delq nil (list (plist-get timing :elapsed) (plist-get timing :left))))
         (head (append (agent-ui-progress--counts props) (and mark (list mark)))))
    ;; The figures dropped from the right while they leave the label less
    ;; than 4 columns (all of it if shorter).
    (while (and figures
                (> (+ (string-width (string-join (append head figures) "  "))
                      (if label (+ 2 (min 4 (string-width label))) 0))
                   width))
      (setq figures (butlast figures)))
    (concat pie (agent-ui-truncate
                 (string-join (append head (mapcar (lambda (f) (propertize f 'face 'agent-ui-muted)) figures)
                                      (and label (list label)))
                              "  ")
                 width))))

(defun agent-ui-progress--draw (props ctx _gui)
  (cond ((plist-get props :pie) (agent-ui-progress--pie props ctx))
        ;; In the GUI its bar drawn over its cells (see ROUNDED IN THE GUI).
        (t (agent-ui-progress--text props ctx))))

(agent-ui-define progress
  "A progress bar: VALUE of MAX, with a LABEL saying what's being done.
Without MAX, no end is known: a block goes to and fro while it's running.
STATUS done or failed colours it and stops it. On a canvas, its values
over time give its rate and, with MAX, the time left; values minutes apart
\(work items, one by one), a line under it: the time elapsed (since its
first value, or STARTED), the time an item takes, the time left and when
it should end."
  :props ((value number "Done so far" :default 0)
          (max number "The total; none: no end known")
          (label string "What's being done now, after the bar")
          (unit string "What VALUE counts (files, MB, bugs), after it")
          (status (choice running done failed) "running; done or failed colour it and stop it"
                  :default running)
          (started any "When the work began, if before the bar: a timestamp, epoch seconds, or seconds ago")
          (times any "Noted by the canvas from your updates, kept with it (don't give it)")
          (pie boolean "Drawn small: a pie, its counts and label on one line (a panel's corner)" :default :false))
  :example (:title "Build" :value 7 :max 12 :label "linking")
  ;; Moving: a block to and fro (no max), or its time elapsed ticking.
  :animated (lambda (props)
              (and (eq (plist-get props :status) 'running)
                   (or (null (plist-get props :max))
                       (and (agent-ui-progress--timing props)
                            (not (agent-ui-progress--stopped-p props))))))
  :check (lambda (props)
           (let ((max (plist-get props :max))
                 (started (plist-get props :started)))
             (when (and max (<= max 0))
               (agent-ui--fail "progress: max must be above 0, not %s" (agent-ui-format-number max)))
             (when (and started (not (agent-ui-progress--time started 0)))
               (agent-ui--fail "progress: started is a timestamp (\"2026-11-10T18:30:00Z\"), epoch seconds, or seconds ago")))
           props)
  :prepare (lambda (element) (agent-ui-progress--noted element (funcall agent-ui-clock)))
  ;; Finished: done, or at its max (not failed); failed: failed.
  :finished (lambda (props)
              (pcase (plist-get props :status)
                ('failed 'failed)
                ('done 'done)
                (_ (let ((max (plist-get props :max)))
                     (and max (>= (plist-get props :value) max) 'done)))))
  :text (lambda (props ctx) (agent-ui-progress--draw props ctx nil))
  :gui (lambda (props ctx) (agent-ui-progress--draw props ctx t)))
