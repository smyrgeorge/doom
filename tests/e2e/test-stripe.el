;;; tests/e2e/test-stripe.el -*- lexical-binding: t; -*-
;; config/stripe.el in a GUI Emacs: the strip, one image in a child frame laid
;; over each file window's right margin; its pixels (band, marks), splits,
;; other buffers, a notice above, a press, the wheel, and images made (and
;; the strip's frame drawn anew) only when the strip changes.

(setq-default truncate-lines t)          ; as Doom
(+test-load "config/window" "config/childframe" "config/banner" "config/stripe")
(require 'diff-hl)

;; ====== HELPERS ======

(defun +test-stripe--file (name lines)
  "A file NAME of LINES lines, open in the selected window, its strip shown."
  (find-file (+test-file (concat "stripe/" name)
                         (mapconcat (lambda (i) (format "line %d" i)) (number-sequence 1 lines) "\n")))
  (emacs-lisp-mode)
  (+my/stripe-mode 1)
  (should (+test-stripe--shown (selected-window)))
  (current-buffer))

(defun +test-stripe--frame (window)
  (nth 1 (assq window +my/stripe--frames)))

(defun +test-stripe--shown (window)
  "WINDOW's strip frame, once shown and laid over its margin."
  (+test-wait-for
   (lambda ()
     (let ((frame (+test-stripe--frame window)))
       (and (frame-live-p frame)
            (+my/childframe-shown-p frame)
            (+test-stripe--placed-p frame window)
            frame)))
   5))

(defun +test-stripe--placed-p (frame window)
  "Non-nil if FRAME lies over WINDOW's right margin, as tall as its text, and
its image has all of it: no margin, fringe or horizontal scroll in its own
window (a margin of the file buffer it first showed once took all 8 px: the
strip took its room, drawn in nothing)."
  (pcase-let ((`(,left ,top ,width ,height) (+my/stripe--geometry window))
              (strip (frame-root-window frame)))
    (and (equal (frame-position frame) (cons left top))
         (= (frame-pixel-width frame) width)
         (= (frame-pixel-height frame) height)
         (= (window-body-width strip t) width)
         (= (window-hscroll strip) 0))))

(defun +test-stripe--pixels (window)
  "The strip WINDOW's frame shows, a palette character per pixel row."
  (let* ((image (with-current-buffer (window-buffer (frame-root-window (+test-stripe--frame window)))
                  (get-text-property (point-min) 'display)))
         (lines (split-string (plist-get (cdr image) :data) "\n"))
         (header (split-string (substring (nth 2 lines) 1 -2)))
         (height (string-to-number (nth 1 header)))
         (colors (string-to-number (nth 2 header))))
    (mapconcat (lambda (line) (substring line 1 2))
               (seq-take (nthcdr (+ 3 colors) lines) height)
               "")))

(defun +test-stripe--hunk (first last type)
  "A diff-hl hunk over lines FIRST..LAST, as diff-hl makes them."
  (let ((ov (make-overlay (save-excursion (goto-char (point-min)) (forward-line (1- first)) (point))
                          (save-excursion (goto-char (point-min)) (forward-line last) (point)))))
    (overlay-put ov 'diff-hl t)
    (overlay-put ov 'diff-hl-hunk t)
    (overlay-put ov 'diff-hl-hunk-type type)
    (+my/stripe--after-diff-hl-a)))

(defun +test-stripe--strip-posn (window y)
  "A position on WINDOW's strip, Y pixels down."
  (posn-at-x-y 2 y (frame-root-window (+test-stripe--frame window))))

(defmacro +test-stripe (&rest body)
  `(+test-with-reset
     (unwind-protect (progn ,@body)
       (+test-sleep 0.1))))

;; ====== THE FRAME ======

(ert-deftest e2e-stripe/a-child-frame-over-the-right-margin ()
  (+test-stripe
    (+test-stripe--file "a.el" 400)
    (let* ((window (selected-window))
           (frame (+test-stripe--frame window)))
      (should (eq (frame-parent frame) (window-frame window)))
      (should (+test-stripe--placed-p frame window))
      ;; Beside the text, at the window's right edge.
      (should (= (+ (car (frame-position frame)) (frame-pixel-width frame))
                 (- (nth 2 (window-pixel-edges window))
                    (window-right-divider-width window) (window-scroll-bar-width window))))
      (should (>= (car (frame-position frame)) (nth 2 (window-inside-pixel-edges window))))
      ;; It never takes the keyboard.
      (should (frame-parameter frame 'no-accept-focus))
      (should (eq (selected-frame) (window-frame window)))
      ;; The image as tall as the window's text, a pixel row each.
      (should (= (length (+test-stripe--pixels window)) (window-body-height window t)))
      ;; Nothing in the window's own rows.
      (should-not (seq-find (lambda (ov) (overlay-get ov '+my/stripe-row))
                            (overlays-in (point-min) (point-max)))))))

(ert-deftest e2e-stripe/made-from-a-file-with-the-stripe ()
  "The strip's frame made while a file with the stripe is the current buffer
(its window first shows it, with its margin): the image still has the whole
frame."
  (+test-stripe
    (let ((other (+test-stripe--file "made-from.md" 50)))
      (find-file (+test-file "stripe/target.el" (mapconcat #'number-to-string (number-sequence 1 400) "\n")))
      (emacs-lisp-mode)
      (with-current-buffer other               ; current as the frame's made
        (+my/stripe--sync))
      (+my/stripe-mode 1)
      (with-current-buffer other
        (+my/stripe--sync))
      (should (+test-stripe--shown (selected-window))))))

(ert-deftest e2e-stripe/a-frame-per-window ()
  "Split: each window its strip; another buffer in one: its strip hidden, back
when the file is; a window closed: its strip gone."
  (+test-stripe
    (+test-stripe--file "b.el" 400)
    (let* ((left (selected-window))
           (right (split-window-right))
           (a (+test-stripe--shown left))
           (b (+test-stripe--shown right)))
      (should (and a b (not (eq a b))))
      (let ((file (window-buffer right)))
        (set-window-buffer right (get-buffer-create "*scratch*"))
        (should (+test-wait-for (lambda () (not (+my/childframe-shown-p b))) 3))
        (set-window-buffer right file)
        (should (eq (+test-stripe--shown right) b)))
      (delete-window right)
      (should (+test-wait-for (lambda () (not (frame-live-p b))) 3))
      ;; The other follows its window's new size.
      (should (+test-stripe--shown left)))))

(ert-deftest e2e-stripe/below-a-notice ()
  "A notice above the text (a taller header line): the strip moves down with
the text, and back up when it goes."
  (+test-stripe
    (+test-stripe--file "c.el" 400)
    (let* ((window (selected-window))
           (frame (+test-stripe--frame window))
           (top (cdr (frame-position frame))))
      (+my/banner-show 'test "A notice")
      (should (+test-wait-for (lambda () (and (> (cdr (frame-position frame)) top)
                                              (+test-stripe--placed-p frame window)))
                              3))
      (+my/banner-close 'test)
      (should (+test-wait-for (lambda () (= (cdr (frame-position frame)) top)) 3)))))

;; ====== THE IMAGE ======

(ert-deftest e2e-stripe/the-band-and-the-marks ()
  (+test-stripe
    (+test-stripe--file "d.el" 1000)
    (let ((window (selected-window)))
      (+test-stripe--hunk 500 510 'insert)
      (+test-sleep 0.2)
      (pcase-let ((`(pixels ,scale ,_ ,thumb) (window-parameter window '+my/stripe-geometry)))
        (let ((pixels (+test-stripe--pixels window)))
          ;; The band at the top, the mark halfway down, green.
          (should (= (car thumb) 0))
          (should (eq (aref pixels 0) ?t))
          (should (eq (aref pixels (floor (* scale 499))) ?2))))
      ;; Scrolled halfway: the band there.
      (set-window-start window (save-excursion (goto-char (point-min)) (forward-line 699) (point)))
      (+test-sleep 0.2)
      (pcase-let ((`(pixels ,scale ,_ ,thumb) (window-parameter window '+my/stripe-geometry)))
        (should (= (car thumb) (floor (* scale 699))))
        (should (eq (aref (+test-stripe--pixels window) (car thumb)) ?t))
        (should (eq (aref (+test-stripe--pixels window) 0) ?\s))))))

(ert-deftest e2e-stripe/images-made-only-when-the-strip-changes ()
  "300 scrolls of one line in a 3000-line file: the band moves by under a pixel
most times, so few new images, each old one flushed from Emacs's cache, and
the strip's frame drawn anew with each (on macOS a reload left it showing the
old one), only the strip's."
  (+test-stripe
    (+test-stripe--file "e.el" 3000)
    (let ((made 0) (flushed 0) (redrawn nil)
          (strip (+test-stripe--frame (selected-window))))
      (advice-add '+my/stripe--image :after (lambda (&rest _) (cl-incf made)) '((name . count)))
      (advice-add 'image-flush :after (lambda (&rest _) (cl-incf flushed)) '((name . count)))
      (advice-add 'redraw-frame :after (lambda (&optional frame) (push frame redrawn)) '((name . count)))
      (unwind-protect
          (dotimes (_ 300) (scroll-up 1) (redisplay t))
        (advice-remove '+my/stripe--image 'count)
        (advice-remove 'image-flush 'count)
        (advice-remove 'redraw-frame 'count))
      (should (< 20 made 150))
      (should (= flushed made))
      (should (= (length redrawn) made))
      (should (seq-every-p (lambda (frame) (eq frame strip)) redrawn)))))

;; ====== THE MOUSE ======

(ert-deftest e2e-stripe/a-press-jumps-there ()
  "A press off the band: that part of the file, in the middle of the window."
  (+test-stripe
    (+test-stripe--file "f.el" 1000)
    (let* ((window (selected-window))
           (scale (nth 1 (window-parameter window '+my/stripe-geometry)))
           (y (round (* scale 600))))
      (+my/stripe-press (list 'down-mouse-1 (+test-stripe--strip-posn window y)))
      (should (eq (selected-window) window))
      (should (<= (abs (- (line-number-at-pos (point)) (1+ (floor (/ y scale))))) 1))
      (should (pos-visible-in-window-p (point) window)))))

(ert-deftest e2e-stripe/the-wheel-over-the-strip-scrolls-the-file ()
  (+test-stripe
    (+test-stripe--file "g.el" 1000)
    (let* ((window (selected-window))
           (start (window-start window)))
      (dotimes (_ 5)
        (execute-kbd-macro (vector (list 'wheel-down (+test-stripe--strip-posn window 200))))
        (+test--pump 0.02))
      (should (> (window-start window) start))
      (should (eq (selected-frame) (window-frame window))))))

(ert-deftest e2e-stripe/a-closed-buffer-s-strip-is-hidden ()
  (+test-stripe
    (+test-stripe--file "h.el" 100)
    (let* ((window (selected-window))
           (frame (+test-stripe--frame window)))
      (kill-buffer (current-buffer))
      (should-not (buffer-local-value '+my/stripe-mode (window-buffer window)))
      (should (+test-wait-for (lambda () (not (+my/childframe-shown-p frame))) 3)))))
