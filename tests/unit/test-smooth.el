;;; tests/unit/test-smooth.el -*- lexical-binding: t; -*-
;; config/editor/smooth.el: mouse-wheel notches glide (ultra-scroll), heavy idle jobs
;; wait for a glide to end, every window's scroll limit past the end, good-scroll's
;; timer only while scrolling, the wheel over the minibuffer.

;; What Doom's smooth-scroll module does to ultra-scroll; its config runs before
;; this config's `after!' blocks, as here.
(with-eval-after-load 'ultra-scroll
  (add-hook 'ultra-scroll-hide-functions #'hl-todo-mode)
  (setq ultra-scroll-throttle-mode-line t))

;; As config.el: the stripe (its scroll limit), then the editor.
(+test-load "config/childframe" "config/stripe" "config/editor")

(require 'mwheel)
(require 'ultra-scroll)
(require 'good-scroll)
(require 'so-long)
(require 'vertico nil t)
(defvar vertico-mode)
(defvar vertico--input)

;; ====== HELPERS ======

(defvar +test-smooth--now 0.0 "The time, standing still in `+test-smooth--gliding'.")
(defvar +test-smooth--steps nil "(PIXELS . WINDOW) scrolled, latest first.")
(defvar +test-smooth--prepared nil "Windows ultra-scroll prepared, latest first.")
(defvar +test-smooth--timers nil "(TIMER TIME REPEAT FUNCTION) started, latest first.")

(defmacro +test-smooth--gliding (&rest body)
  "BODY with time standing still (`+test-smooth--tick' moves it), ultra-scroll's
scrolling recorded instead of done, timers recorded instead of started; no glide
before or after."
  (declare (indent 0))
  `(let ((+test-smooth--now 1000.0)
         (+test-smooth--steps nil)
         (+test-smooth--prepared nil)
         (+test-smooth--timers nil))
     (cl-letf (((symbol-function 'float-time) (lambda (&optional _) +test-smooth--now))
               ((symbol-function 'ultra-scroll--scroll)
                (lambda (delta window) (push (cons delta window) +test-smooth--steps)))
               ((symbol-function 'ultra-scroll--prepare-to-scroll)
                (lambda (window) (push window +test-smooth--prepared)))
               ((symbol-function 'run-at-time)
                (lambda (time repeat fn &rest _)
                  (let ((timer (timer-create)))
                    (push (list timer time repeat fn) +test-smooth--timers)
                    timer))))
       (unwind-protect
           (progn (+my/smooth--stop) ,@body)
         (+my/smooth--stop)
         (setq +my/smooth--window nil)))))

(defun +test-smooth--tick (&optional frames)
  "Let FRAMES (default 1) frames of time pass."
  (setq +test-smooth--now (+ +test-smooth--now (* (or frames 1) +my/smooth-scroll-frame))))

(defun +test-smooth--share (seconds)
  "The share of what's left a frame SECONDS after the last covers."
  (- 1 (exp (/ (- seconds) +my/smooth-scroll-time-constant))))

(defun +test-smooth--glide-steps (window delta)
  "Glide WINDOW by DELTA, a frame every frame time: the steps, first first."
  (+my/smooth--glide window delta)
  (let ((frames 0))
    (while (and +my/smooth--timer (< (cl-incf frames) 100))
      (+test-smooth--tick)
      (+my/smooth--frame)))
  (reverse (mapcar #'car +test-smooth--steps)))

(defun +test-smooth--wheel (window dy &optional type lines)
  "A wheel event over WINDOW: DY pixels (negative: down; nil: no pixel delta),
of TYPE (by DY's sign), LINES lines."
  (list (or type (if (and dy (> dy 0)) 'wheel-up 'wheel-down))
        (list window 1 '(0 . 0) 0)
        1
        lines
        (and dy (cons 0.0 (float dy)))))

(defun +test-smooth--text (lines)
  (mapconcat (lambda (n) (format "line %d\n" n)) (number-sequence 1 lines) ""))

(defun +test-smooth--line-start (line)
  (save-excursion (goto-char (point-min)) (forward-line (1- line)) (point)))

(defmacro +test-smooth--minibuffer (&rest body)
  "BODY with a vertico session open in the minibuffer (as far as the wheel can
tell); `+test-smooth--moves' gets vertico's moves: (next N) or (previous N)."
  (declare (indent 0))
  `(let* ((mini (minibuffer-window))
          (+my/smooth--minibuffer-pixels 0)
          (vertico-mode t)
          (+test-smooth--moves nil))
     (with-current-buffer (window-buffer mini)
       (setq-local vertico--input t))
     (unwind-protect
         (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () mini))
                   ((symbol-function 'vertico-next)
                    (lambda (&optional n)
                      (should (eq (selected-window) mini))
                      (push (list 'next n) +test-smooth--moves)))
                   ((symbol-function 'vertico-previous)
                    (lambda (&optional n)
                      (should (eq (selected-window) mini))
                      (push (list 'previous n) +test-smooth--moves))))
           ,@body)
       (with-current-buffer (window-buffer mini)
         (kill-local-variable 'vertico--input)))))

(defvar +test-smooth--moves nil)

;; ====== SETTINGS ======

(ert-deftest smooth/settings ()
  (should (= (default-value '+my/smooth-scroll-min-step) 20))
  (should (= (default-value '+my/smooth-scroll-frame) (/ 1.0 60)))
  (should (= (default-value '+my/smooth-scroll-time-constant) 0.05)))

;; ====== GLIDE ======

(ert-deftest smooth/glide-starts-at-once ()
  "From rest: ultra-scroll prepared, the first frame right away (as if one had
just passed), then a frame per refresh."
  (+test-smooth--gliding
    (let ((window (selected-window)))
      (+my/smooth--glide window -51)
      (should (equal +test-smooth--prepared (list window)))
      (let ((first (round (* -51 (+test-smooth--share +my/smooth-scroll-frame)))))
        (should (equal +test-smooth--steps (list (cons first window))))
        (should (= +my/smooth--remaining (- -51 first))))
      (should (eq +my/smooth--window window))
      (should (= (length +test-smooth--timers) 1))
      (pcase-let ((`(,timer ,time ,repeat ,fn) (car +test-smooth--timers)))
        (should (eq +my/smooth--timer timer))
        (should (= time +my/smooth-scroll-frame))
        (should (= repeat +my/smooth-scroll-frame))
        (should (eq fn #'+my/smooth--frame))))))

(ert-deftest smooth/glide-eases-out-to-the-pixel ()
  "A notch glides by all its pixels in about three time constants, fast at first
then slowing down; then the glide stops."
  (+test-smooth--gliding
    (let ((steps (+test-smooth--glide-steps (selected-window) -51)))
      (should (= (apply #'+ steps) -51))
      (should (cl-every #'cl-minusp steps))
      (should (<= (length steps)
                  (ceiling (* 3.5 +my/smooth-scroll-time-constant) +my/smooth-scroll-frame)))
      ;; Ease-out: each step no bigger than the one before (the last few pixels
      ;; may go at once).
      (let ((sizes (mapcar #'abs (butlast steps))))
        (should (equal sizes (sort (copy-sequence sizes) #'>=)))
        (should (> (car sizes) (car (last sizes)))))
      (should (<= (abs (car (last steps))) 4))
      (should-not +my/smooth--timer)
      (should (= +my/smooth--remaining 0))))
  ;; Upwards too.
  (+test-smooth--gliding
    (let ((steps (+test-smooth--glide-steps (selected-window) 153)))
      (should (= (apply #'+ steps) 153))
      (should (cl-every #'cl-plusp steps)))))

(ert-deftest smooth/glide-late-frame-catches-up ()
  "A frame's share of what's left depends on the time since the last one."
  (+test-smooth--gliding
    (+my/smooth--glide (selected-window) -100)
    (let ((left +my/smooth--remaining))
      (+test-smooth--tick 3)
      (+my/smooth--frame)
      (should (= (car (car +test-smooth--steps))
                 (round (* left (+test-smooth--share (* 3 +my/smooth-scroll-frame))))))
      (should (> (abs (car (car +test-smooth--steps)))
                 (abs (round (* left (+test-smooth--share +my/smooth-scroll-frame)))))))))

(ert-deftest smooth/glide-at-least-a-pixel-a-frame ()
  (+test-smooth--gliding
    (setq +my/smooth--window (selected-window)
          +my/smooth--last +test-smooth--now)
    ;; No time passed: no share, but a pixel all the same.
    (setq +my/smooth--remaining 10)
    (+my/smooth--frame)
    (should (equal (car (car +test-smooth--steps)) 1))
    (should (= +my/smooth--remaining 9))
    (setq +my/smooth--remaining -10)
    (+my/smooth--frame)
    (should (equal (car (car +test-smooth--steps)) -1))
    ;; The last few pixels in one go.
    (setq +my/smooth--remaining 3)
    (+my/smooth--frame)
    (should (equal (car (car +test-smooth--steps)) 3))
    (should (= +my/smooth--remaining 0))))

(ert-deftest smooth/glide-notches-add-up ()
  "Another notch the same way while gliding adds to what's left, no restart."
  (+test-smooth--gliding
    (let ((window (selected-window)))
      (+my/smooth--glide window -51)
      (let ((timer +my/smooth--timer)
            (left +my/smooth--remaining))
        (+test-smooth--tick)
        (+my/smooth--glide window -51)
        (should (eq +my/smooth--timer timer))
        (should (= (length +test-smooth--timers) 1))
        (should (= (length +test-smooth--steps) 1)) ; no extra frame
        (should (= +my/smooth--remaining (+ left -51)))
        (should (= (length +test-smooth--prepared) 2))))
    ;; All of both notches.
    (let ((frames 0))
      (while (and +my/smooth--timer (< (cl-incf frames) 100))
        (+test-smooth--tick)
        (+my/smooth--frame)))
    (should (= (apply #'+ (mapcar #'car +test-smooth--steps)) -102))))

(ert-deftest smooth/glide-other-way-or-window-restarts ()
  "Scrolling the other way, or another window, drops what's left of the glide."
  (+test-smooth--gliding
    (let ((window (selected-window)))
      (+my/smooth--glide window -51)
      (let ((timer +my/smooth--timer))
        (+my/smooth--glide window 51)
        (should-not (eq +my/smooth--timer timer))
        (should (= (length +test-smooth--timers) 2))
        (should (= +my/smooth--remaining (- 51 (car (car +test-smooth--steps)))))
        (should (> (car (car +test-smooth--steps)) 0)))))
  (+test-with-reset
    (+test-smooth--gliding
      (let* ((left (selected-window))
             (right (split-window-right)))
        (+my/smooth--glide left -51)
        (+my/smooth--glide right -51)
        (should (eq +my/smooth--window right))
        (should (= (length +test-smooth--timers) 2))
        (should (eq (cdr (car +test-smooth--steps)) right))
        (should (= +my/smooth--remaining (- -51 (car (car +test-smooth--steps)))))))))

(ert-deftest smooth/glide-stops ()
  "Nothing left, the window gone, or ultra-scroll failing: the glide stops."
  (+test-smooth--gliding
    (+my/smooth--glide (selected-window) -51)
    (setq +my/smooth--remaining 0)
    (+my/smooth--frame)
    (should-not +my/smooth--timer))
  (+test-with-reset
    (+test-smooth--gliding
      (let ((window (split-window)))
        (+my/smooth--glide window -51)
        (delete-window window)
        (let ((steps (length +test-smooth--steps)))
          (+test-smooth--tick)
          (+my/smooth--frame)
          (should (= (length +test-smooth--steps) steps)))
        (should-not +my/smooth--timer)
        (should (= +my/smooth--remaining 0)))))
  (+test-smooth--gliding
    (+my/smooth--glide (selected-window) -51)
    (cl-letf (((symbol-function 'ultra-scroll--scroll)
               (lambda (&rest _) (signal 'end-of-buffer nil))))
      (+test-smooth--tick)
      (+my/smooth--frame))
    (should-not +my/smooth--timer)
    (should (= +my/smooth--remaining 0))))

(ert-deftest smooth/stop ()
  (let ((timer (run-at-time 100 nil #'ignore)))
    (setq +my/smooth--timer timer
          +my/smooth--remaining 30)
    (+my/smooth--stop)
    (should-not +my/smooth--timer)
    (should (= +my/smooth--remaining 0))
    (should-not (memq timer timer-list))
    (+my/smooth--stop)))                        ; nothing to stop

;; ====== THE WHEEL ======

(ert-deftest smooth/wheel-big-steps-glide ()
  "Mouse-wheel notches (more than `+my/smooth-scroll-min-step' pixels) glide;
a trackpad's small steps, and events without pixels, go to ultra-scroll as is."
  (let ((window (selected-window))
        called glided)
    (cl-letf (((symbol-function '+my/smooth--glide)
               (lambda (w delta) (push (cons w delta) glided))))
      (let ((fn (lambda (&rest args) (push args called))))
        (dolist (dy '(-51 51 -21 21 -20.6))
          (+my/smooth-scroll-glide-a fn (+test-smooth--wheel window dy)))
        (should (equal (reverse glided)
                       (mapcar (lambda (d) (cons window d)) '(-51 51 -21 21 -21))))
        (should-not called)
        (setq glided nil)
        (dolist (event (list (+test-smooth--wheel window -20)
                             (+test-smooth--wheel window 20)
                             (+test-smooth--wheel window -5.4)
                             (+test-smooth--wheel window nil 'wheel-down 3)))
          (+my/smooth-scroll-glide-a fn event 'arg)
          (should (equal (car called) (list event 'arg))))
        (should-not glided)
        (let ((+my/smooth-scroll-min-step 60))
          (+my/smooth-scroll-glide-a fn (+test-smooth--wheel window -51))
          (should-not glided))))))

(ert-deftest smooth/wheel-glide-is-ultra-scrolls ()
  "Installed around `ultra-scroll' (the wheel's command in Doom)."
  (should (advice-member-p '+my/smooth-scroll-glide-a 'ultra-scroll))
  (let (glided)
    (cl-letf (((symbol-function '+my/smooth--glide)
               (lambda (w delta) (push (cons w delta) glided))))
      (ultra-scroll (+test-smooth--wheel (selected-window) -51)))
    (should (equal glided (list (cons (selected-window) -51))))))

(ert-deftest smooth/ultra-scroll-settings ()
  "TODO/NOTE/FIXME keep their highlight while scrolling; the mode line isn't
frozen (that broke popups' mode lines)."
  (should-not (memq #'hl-todo-mode ultra-scroll-hide-functions))
  (should-not ultra-scroll-throttle-mode-line))

;; ====== NOTHING HEAVY MID-GLIDE ======

(ert-deftest smooth/after-glide-runs-now-at-rest ()
  (let ((+my/smooth--timer nil)
        args)
    (should (eq (+my/smooth--after-glide-a (lambda (&rest a) (setq args a) 'done) 1 2)
                'done))
    (should (equal args '(1 2)))))

(ert-deftest smooth/after-glide-waits-for-the-glide ()
  "During a glide: retried every 0.1 s until it ends."
  (let ((+my/smooth--timer (timer-create))
        later ran)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (time repeat fn) (push (list time repeat fn) later))))
      (+my/smooth--after-glide-a (lambda (&rest a) (push a ran)) 'x)
      (should-not ran)
      (should (equal (mapcar #'butlast later) '((0.1 nil))))
      ;; Still gliding.
      (funcall (nth 2 (pop later)))
      (should-not ran)
      (should (= (length later) 1))
      ;; Done.
      (setq +my/smooth--timer nil)
      (funcall (nth 2 (pop later)))
      (should (equal ran '((x))))
      (should-not later))))

(ert-deftest smooth/heavy-idle-jobs-wait ()
  "gcmh's idle garbage collection and treemacs' refresh wait for the glide."
  (should (advice-member-p #'+my/smooth--after-glide-a 'gcmh-idle-garbage-collect))
  (should (advice-member-p #'+my/smooth--after-glide-a '+my/treemacs-refresh-all))
  (let ((refreshed 0))
    (unless (fboundp '+my/treemacs-refresh-all)
      ;; config/treemacs.el isn't loaded here: a stand-in, advised as it would be.
      (defalias '+my/treemacs-refresh-all (lambda () (cl-incf refreshed))))
    (let ((+my/smooth--timer (timer-create))
          later)
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _repeat fn) (push fn later))))
        (+my/treemacs-refresh-all)
        (should (= refreshed 0))
        (should (= (length later) 1))
        (setq +my/smooth--timer nil)
        (funcall (pop later))
        (should (= refreshed 1))))))

(ert-deftest smooth/gcmh-waits-for-the-glide ()
  (skip-unless (require 'gcmh nil t))
  (let ((+my/smooth--timer (timer-create))
        (collected 0)
        later)
    (cl-letf (((symbol-function 'run-at-time) (lambda (_time _repeat fn) (push fn later)))
              ((symbol-function 'garbage-collect) (lambda () (cl-incf collected))))
      (gcmh-idle-garbage-collect)
      (should (= collected 0))
      (should later)
      (setq +my/smooth--timer nil)
      (funcall (pop later))
      (should (= collected 1)))))

;; ====== SCROLL LIMIT ======

(ert-deftest smooth/limit-in-every-window ()
  "Every window stops with at most the allowed space past the end, not only
file windows (*Messages*, help...)."
  (+test-with-reset
    (switch-to-buffer (+test-buffer "*smooth-log*" (+test-smooth--text 100) #'special-mode))
    (set-window-parameter nil '+my/smooth-limit nil)
    (set-window-start nil (+test-smooth--line-start 99))
    (+my/smooth--limit-h (selected-window))
    (should (= (window-start) (car (+my/stripe--end-limit (selected-window)))))
    (should (equal (window-parameter nil '+my/smooth-limit) (cons (window-start) 0)))
    ;; Within the limit: left alone.
    (set-window-start nil (+test-smooth--line-start 50))
    (+my/smooth--limit-h (selected-window))
    (should (= (window-start) (+test-smooth--line-start 50)))
    ;; Run from redisplay.
    (should (memq #'+my/smooth--limit-h (default-value 'pre-redisplay-functions)))
    (set-window-start nil (+test-smooth--line-start 100))
    (run-hook-with-args 'pre-redisplay-functions (selected-window))
    (should (= (window-start) (car (+my/stripe--end-limit (selected-window)))))))

(ert-deftest smooth/limit-only-when-scrolled ()
  (+test-with-reset
    (switch-to-buffer (+test-buffer "*smooth-log*" (+test-smooth--text 100) #'special-mode))
    (set-window-parameter nil '+my/smooth-limit nil)
    (let ((clamps 0))
      (cl-letf (((symbol-function '+my/stripe--clamp-start) (lambda (_) (cl-incf clamps))))
        (+my/smooth--limit-h (selected-window))
        (+my/smooth--limit-h (selected-window))
        (should (= clamps 1))
        (set-window-start nil (+test-smooth--line-start 10))
        (+my/smooth--limit-h (selected-window))
        (should (= clamps 2))
        ;; Not the minibuffer, nor "all windows".
        (+my/smooth--limit-h (minibuffer-window))
        (+my/smooth--limit-h t)
        (should (= clamps 2)))
      ;; Without stripe.el: nothing to limit with.
      (set-window-start nil (+test-smooth--line-start 20))
      (cl-letf (((symbol-function '+my/stripe--clamp-start) nil))
        (+my/smooth--limit-h (selected-window))))))

(ert-deftest smooth/limit-p ()
  "Not where the stripe does it, nor in buffers that scroll within a line or
manage their own view."
  (+test-with-reset
    (let ((window (selected-window)))
      (dolist (case '((fundamental-mode . t) (special-mode . t) (text-mode . t)
                      (image-mode . nil) (doc-view-mode . nil) (pdf-view-mode . nil)
                      (term-mode . nil) (vterm-mode . nil) (ghostel-mode . nil)
                      (xwidget-webkit-mode . nil) (+test-smooth-ghostel-term-mode . nil)))
        (with-current-buffer (window-buffer window)
          (setq major-mode (car case))
          (should (eq (and (+my/smooth--limit-p window) t) (cdr case)))))
      (with-current-buffer (window-buffer window) (fundamental-mode))
      ;; Modes derived from those.
      (define-derived-mode +test-smooth-term-mode term-mode "Term*")
      (switch-to-buffer (+test-buffer "*smooth-term*"))
      (setq major-mode '+test-smooth-term-mode)
      (should-not (+my/smooth--limit-p window))
      ;; File windows: the stripe's own limit.
      (switch-to-buffer (+test-buffer "*smooth-file*" "x\n" #'text-mode))
      (should (+my/smooth--limit-p window))
      (+my/stripe-mode 1)
      (should-not (+my/smooth--limit-p window)))))

(ert-deftest smooth/limit-left-to-others ()
  "Terminals, images... aren't held back (the parameter still follows them)."
  (+test-with-reset
    (switch-to-buffer (+test-buffer "*smooth-term*" (+test-smooth--text 100)))
    (setq major-mode 'term-mode)
    (set-window-parameter nil '+my/smooth-limit nil)
    (set-window-start nil (+test-smooth--line-start 99))
    (+my/smooth--limit-h (selected-window))
    (should (= (window-start) (+test-smooth--line-start 99)))
    (should (equal (window-parameter nil '+my/smooth-limit) (cons (window-start) 0)))))

;; ====== GOOD-SCROLL ======

(ert-deftest smooth/good-scroll-stop-timer ()
  (let ((timer (run-at-time 100 1 #'ignore)))
    (setq good-scroll--timer timer)
    (+my/good-scroll-stop-timer)
    (should-not good-scroll--timer)
    (should-not (memq timer timer-list))
    (+my/good-scroll-stop-timer)))

(ert-deftest smooth/good-scroll-idle-until-a-scroll ()
  "Its timer doesn't run while nothing scrolls: off when the mode starts, on
when a scroll starts, off once it's done."
  (should (memq #'+my/good-scroll-idle-h good-scroll-mode-hook))
  (should (advice-member-p '+my/good-scroll-start-timer-a 'good-scroll-move))
  (should (advice-member-p '+my/good-scroll-stop-when-done-a 'good-scroll--render))
  (unwind-protect
      (progn
        (good-scroll-mode 1)
        (should-not good-scroll--timer)
        ;; A scroll starts it.
        (good-scroll-move 10)
        (should (timerp good-scroll--timer))
        (should (memq good-scroll--timer timer-list))
        (should (eq (timer--function good-scroll--timer) #'good-scroll--render))
        (should (= (timer--repeat-delay good-scroll--timer) good-scroll-render-rate))
        ;; Another one: the same timer.
        (let ((timer good-scroll--timer))
          (good-scroll-move 10)
          (should (eq good-scroll--timer timer)))
        ;; Still on its way: kept.
        (let ((good-scroll--window nil)) ; nothing for the render to do
          (good-scroll--render))
        (should (timerp good-scroll--timer))
        ;; Done: stopped.
        (setq good-scroll-destination 0)
        (good-scroll--render)
        (should-not good-scroll--timer))
    (good-scroll-mode -1)
    (+my/good-scroll-stop-timer)
    (setq good-scroll-destination 0)))

(ert-deftest smooth/good-scroll-off-no-timer ()
  (let ((good-scroll-mode nil))
    (+my/good-scroll-stop-timer)
    (good-scroll-move 10)
    (should-not good-scroll--timer)
    (setq good-scroll-destination 0)))

;; ====== THE MINIBUFFER ======

(ert-deftest smooth/minibuffer-wheel-elsewhere ()
  "Over other windows the wheel isn't handled here."
  (should-not (+my/smooth--minibuffer-wheel (+test-smooth--wheel (selected-window) -51))))

(ert-deftest smooth/minibuffer-wheel-does-not-scroll-it ()
  "Over the minibuffer / echo area the wheel does nothing (it always fits)."
  (let ((mini (minibuffer-window))
        (+my/smooth--minibuffer-pixels 0))
    (cl-letf (((symbol-function 'active-minibuffer-window) #'ignore))
      (should (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -51))))
    ;; An open minibuffer, but no completion list.
    (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () mini)))
      (let ((vertico-mode nil))
        (should (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -51))))
      (let ((vertico-mode t))
        (with-current-buffer (window-buffer mini) (setq-local vertico--input nil))
        (should (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -51)))
        (with-current-buffer (window-buffer mini) (kill-local-variable 'vertico--input))))
    (should (= +my/smooth--minibuffer-pixels 0))))

(ert-deftest smooth/minibuffer-wheel-moves-through-candidates ()
  "With a completion list open: about a candidate per line scrolled."
  (+test-smooth--minibuffer
    (let ((h (frame-char-height)))
      (should (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini (* -3 h))))
      (should (equal +test-smooth--moves '((next 3))))
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini (* 2 h)))
      (should (equal (car +test-smooth--moves) '(previous 2)))
      ;; No pixels: the lines, the way the event goes.
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini nil 'wheel-down 4))
      (should (equal (car +test-smooth--moves) '(next 4)))
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini nil 'mouse-4 nil))
      (should (equal (car +test-smooth--moves) '(previous 1)))
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini nil 'mouse-5 2))
      (should (equal (car +test-smooth--moves) '(next 2)))
      ;; Sideways: nothing.
      (setq +test-smooth--moves nil)
      (should (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -40 'wheel-left)))
      (should-not +test-smooth--moves))))

(ert-deftest smooth/minibuffer-wheel-adds-up-small-steps ()
  "A trackpad's small steps add up to a candidate."
  (+test-smooth--minibuffer
    (cl-letf (((symbol-function 'frame-char-height) (lambda (&optional _) 20)))
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -10))
      (should-not +test-smooth--moves)
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -10))
      (should (equal +test-smooth--moves '((next 1))))
      (should (= +my/smooth--minibuffer-pixels 0))
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini -45))
      (should (equal (car +test-smooth--moves) '(next 2)))
      (should (= +my/smooth--minibuffer-pixels -5))
      ;; Back the other way: what was left counts.
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini 15))
      (should (= (length +test-smooth--moves) 2))
      (should (= +my/smooth--minibuffer-pixels 10))
      (+my/smooth--minibuffer-wheel (+test-smooth--wheel mini 10))
      (should (equal (car +test-smooth--moves) '(previous 1))))))

(ert-deftest smooth/minibuffer-wheel-in-mwheel-and-ultra-scroll ()
  "In an open minibuffer the wheel runs `mwheel-scroll', elsewhere ultra-scroll:
both leave the minibuffer to it."
  (should (advice-member-p '+my/smooth-minibuffer-wheel-a 'mwheel-scroll))
  (let ((mini (minibuffer-window))
        called)
    (cl-letf (((symbol-function 'active-minibuffer-window) #'ignore))
      (+my/smooth-minibuffer-wheel-a (lambda (&rest a) (push a called))
                                     (+test-smooth--wheel mini -51))
      (+my/smooth-scroll-glide-a (lambda (&rest a) (push a called))
                                 (+test-smooth--wheel mini -51))
      (should-not called)
      (let ((event (+test-smooth--wheel (selected-window) -5)))
        (+my/smooth-minibuffer-wheel-a (lambda (&rest a) (push a called)) event 'arg)
        (should (equal called (list (list event 'arg))))))))

;;; test-smooth.el ends here
