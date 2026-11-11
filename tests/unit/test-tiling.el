;;; tests/unit/test-tiling.el -*- lexical-binding: t; -*-
;; config/tiling.el: SPC w SPC opens a pane where the tiling strategy puts it
;; (tall), SPC w a arranges the panes. Tiling first (config/tiling/apps.el):
;; applications in new panes (not where their rules say, not their size),
;; files as tabs in the panes of files, a pane closed with its last tab.

(+test-load "config/window" "config/tiling")
(require 'magit)

;; ====== HELPERS ======

(defun +test-tiling--layout ()
  "The panes as (BUFFER-NAME LEFT TOP) in order, left to right, top to bottom."
  (mapcar (lambda (window)
            (list (buffer-name (window-buffer window))
                  (car (window-edges window))
                  (cadr (window-edges window))))
          (+my/tiling--panes)))

(defmacro +test-tiling (&rest body)
  "BODY from one window on buffer A (B, C, D also there), as a command would
run (`this-command' set: new windows get focus, config/window.el)."
  (declare (indent 0))
  `(+test-with-reset
     (let ((this-command 'test)
           (+my/tiling-strategy 'tall)
           (+my/tiling-tall-ratio 0.5)
           (+my/focus-new-windows t))
       (dolist (name '("A" "B" "C" "D")) (+test-buffer name))
       (switch-to-buffer "A")
       ,@body)))

;; ====== STRATEGIES ======

(ert-deftest tiling/strategy-default-is-tall ()
  (should (eq (default-value '+my/tiling-strategy) 'tall))
  (should (assq 'tall +my/tiling-strategies))
  (should (functionp (plist-get (alist-get 'tall +my/tiling-strategies) :split)))
  (should (functionp (plist-get (alist-get 'tall +my/tiling-strategies) :arrange))))

(ert-deftest tiling/config-el-chooses-tall-before-loading ()
  "config.el sets the strategy (to tall) before it loads config/tiling.el,
whose defvar then keeps it."
  (let (forms)
    (with-temp-buffer
      (insert-file-contents (expand-file-name "config.el" +test-root))
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file)))
    (setq forms (nreverse forms))
    (let ((setq-at (seq-position forms '(setq +my/tiling-strategy 'tall)))
          (load-at (seq-position forms '(load! "config/tiling"))))
      (should setq-at)
      (should load-at)
      (should (< setq-at load-at)))))

(ert-deftest tiling/unknown-strategy-is-a-user-error ()
  (+test-tiling
    (let ((+my/tiling-strategy 'grid))
      (should-error (+my/tiling-split) :type 'user-error)
      (should-error (+my/tiling-arrange) :type 'user-error)
      (should (= (length (window-list)) 1)))))

(ert-deftest tiling/new-strategies-plug-in ()
  "A strategy added to `+my/tiling-strategies' gets the panes, and its :split
returns the new pane."
  (+test-tiling
    (let* ((got nil)
           (+my/tiling-strategies
            (cons (list 'below
                        :split (lambda (panes) (setq got panes)
                                 (split-window (car (last panes)) nil 'below))
                        :arrange #'ignore)
                  +my/tiling-strategies))
           (+my/tiling-strategy 'below))
      (let ((new (+my/tiling-split)))
        (should (equal got (list (next-window new))))
        (should (eq new (selected-window)))
        (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "A")))
        (should (= (car (window-edges (car (+my/tiling--panes))))
                   (car (window-edges (cadr (+my/tiling--panes))))))))))

;; ====== PANES ======

(ert-deftest tiling/panes-in-order-without-side-panels ()
  (+test-tiling
    (let ((top (selected-window)))
      (set-window-buffer (split-window top nil 'below) "B")
      (set-window-buffer (split-window top nil 'right) "C")
      (display-buffer-in-side-window (+test-buffer "SIDE") '((side . left) (window-width . 10)))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "C" "B")))
      (should-not (memq (get-buffer-window "SIDE") (+my/tiling--panes))))))

(ert-deftest tiling/tall-p ()
  (+test-tiling
    (should (+my/tiling--tall-p (window-main-window)))           ; one pane
    (set-window-buffer (split-window nil nil 'right) "B")
    (should (+my/tiling--tall-p (window-main-window)))           ; main | one
    (set-window-buffer (split-window (cadr (+my/tiling--panes)) nil 'below) "C")
    (should (+my/tiling--tall-p (window-main-window)))           ; main | stack
    (set-window-buffer (split-window (car (+my/tiling--panes)) nil 'below) "D")
    (should-not (+my/tiling--tall-p (window-main-window)))))     ; main split too

(ert-deftest tiling/tall-p-rejects-a-row-on-top ()
  (+test-tiling
    (let ((top (selected-window)))
      (set-window-buffer (split-window top nil 'below) "B")
      (set-window-buffer (split-window top nil 'right) "C")
      (should-not (+my/tiling--tall-p (window-main-window))))))

;; ====== SPC w SPC ======

(ert-deftest tiling/first-split-goes-right ()
  (+test-tiling
    (let* ((main (selected-window))
           (width (window-total-width main))
           (new (+my/tiling-split)))
      (should (eq new (selected-window)))
      (should (= (length (+my/tiling--panes)) 2))
      (should (eq (car (+my/tiling--panes)) main))
      (should (> (car (window-edges new)) (car (window-edges main))))
      (should (= (cadr (window-edges new)) (cadr (window-edges main))))
      ;; The main pane keeps its share of the width.
      (should (<= (abs (- (window-total-width main) (round (* 0.5 width)))) 1)))))

(ert-deftest tiling/next-splits-stack-on-the-right ()
  (+test-tiling
    (let* ((main (selected-window))
           (second (+my/tiling-split))
           (third (+my/tiling-split))
           (fourth (+my/tiling-split)))
      (should (= (length (+my/tiling--panes)) 4))
      (should (eq (car (+my/tiling--panes)) main))
      ;; One column on the right, top to bottom in the order they opened.
      (should (equal (cdr (+my/tiling--panes)) (list second third fourth)))
      (dolist (window (list second third fourth))
        (should (= (car (window-edges window)) (car (window-edges second)))))
      (should (< (cadr (window-edges second)) (cadr (window-edges third))
                 (cadr (window-edges fourth))))
      ;; Balanced: heights a line apart at most.
      (let ((heights (mapcar #'window-total-height (list second third fourth))))
        (should (<= (- (apply #'max heights) (apply #'min heights)) 1)))
      (should (+my/tiling--tall-p (window-main-window))))))

(ert-deftest tiling/split-from-main-still-stacks ()
  (+test-tiling
    (let ((main (selected-window)))
      (+my/tiling-split)
      (select-window main)
      (let ((new (+my/tiling-split)))
        (should (= (length (+my/tiling--panes)) 3))
        (should (eq (car (last (+my/tiling--panes))) new))
        (should (> (car (window-edges new)) (car (window-edges main))))))))

(ert-deftest tiling/new-pane-shows-the-buffer-alone ()
  "The new pane shows the current buffer at the same place, as its only tab."
  (+test-tiling
    (with-current-buffer "A"
      (dotimes (i 50) (insert (format "line %d\n" i))))
    (switch-to-buffer "B")
    (switch-to-buffer "A")                  ; A's pane has B in its history
    (goto-char (point-min))
    (forward-line 20)
    (let* ((point (point))
           (new (+my/tiling-split)))
      (should (eq (window-buffer new) (get-buffer "A")))
      (should (= (window-point new) point))
      (should-not (window-prev-buffers new))
      (should-not (window-next-buffers new))
      (should-not (window-parameter new 'tab-line-buffers)))))

(ert-deftest tiling/buffers-shown-in-new-panes ()
  "`+my/tiling-display-buffer': a buffer in a new pane where the strategy puts
it, its only tab; quitting it closes the pane."
  (+test-tiling
    (let* ((main (selected-window))
           (first (display-buffer "B" '(+my/tiling-display-buffer))))
      ;; The second pane: on the right.
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "B")))
      (should (> (car (window-edges first)) 0))
      (should (= (cadr (window-edges first)) (cadr (window-edges main))))
      (should-not (window-prev-buffers first))
      (should-not (window-parameter first 'tab-line-buffers))
      ;; The next: at the bottom of the stack, from whichever pane.
      (select-window main)
      (pop-to-buffer "C" '(+my/tiling-display-buffer))
      (let ((second (selected-window)))
        (should (eq (window-buffer second) (get-buffer "C")))
        (should-not (memq second (list main first)))
        (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "B" "C")))
        (should (> (cadr (window-edges second)) (cadr (window-edges first))))
        (quit-window nil second)
        (should-not (window-live-p second))
        (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "B")))))))

(ert-deftest tiling/focus-follows-the-setting ()
  (+test-tiling
    (let* ((main (selected-window))
           (+my/focus-new-windows nil)
           (new (+my/tiling-split)))
      (should (window-live-p new))
      (should (eq (selected-window) main)))))

(ert-deftest tiling/ratio ()
  (+test-tiling
    (let* ((+my/tiling-tall-ratio 0.7)
           (width (window-total-width))
           (main (selected-window)))
      (+my/tiling-split)
      (should (<= (abs (- (window-total-width main) (round (* 0.7 width)))) 1)))))

(ert-deftest tiling/split-arranges-other-layouts-first ()
  "Panes laid out otherwise (a row on top) become tall, then one more opens."
  (+test-tiling
    (let ((top (selected-window)))
      (set-window-buffer (split-window top nil 'below) "B")
      (set-window-buffer (split-window top nil 'right) "C")
      (+my/tiling-split)
      (should (+my/tiling--tall-p (window-main-window)))
      (should (= (length (+my/tiling--panes)) 4))
      ;; The buffers kept, in order, the new one at the bottom of the stack.
      (should (equal (seq-take (mapcar #'car (+test-tiling--layout)) 3) '("A" "C" "B"))))))

(ert-deftest tiling/side-panels-stay-out ()
  (+test-tiling
    (let ((side (display-buffer-in-side-window (+test-buffer "SIDE")
                                               '((side . left) (window-width . 10)))))
      (+my/tiling-split)
      (+my/tiling-split)
      (should (window-live-p side))
      (should (eq (window-buffer side) (get-buffer "SIDE")))
      (should (= (length (+my/tiling--panes)) 3))
      (should (+my/tiling--tall-p (window-main-window))))))

(ert-deftest tiling/not-from-a-side-panel ()
  (+test-tiling
    (let ((side (display-buffer-in-side-window (+test-buffer "SIDE")
                                               '((side . left) (window-width . 10)))))
      (select-window side)
      (should-error (+my/tiling-split) :type 'user-error)
      (should-error (+my/tiling-arrange) :type 'user-error)
      (should (= (length (+my/tiling--panes)) 1)))))

;; ====== SPC w a ======

(ert-deftest tiling/arrange-keeps-what-panes-show ()
  "Arranged tall: each pane shows what it did (buffer, point, tabs, history),
the selected one stays selected."
  (+test-tiling
    (let ((top (selected-window)))
      (set-window-buffer (split-window top nil 'below) "B")
      (let ((right (split-window top nil 'right)))
        (set-window-buffer right "C")
        (with-current-buffer "C" (insert "some\ntext\nhere\n"))
        (set-window-point right 6)
        (set-window-prev-buffers right (list (list (get-buffer "D") 1 1)))
        (set-window-parameter right 'tab-line-buffers (list (get-buffer "C") (get-buffer "D")))
        (select-window right)
        (+my/tiling-arrange)
        (should (+my/tiling--tall-p (window-main-window)))
        (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "C" "B")))
        (let ((c (get-buffer-window "C")))
          (should (eq (selected-window) c))
          (should (= (window-point c) 6))
          (should (eq (car (car (window-prev-buffers c))) (get-buffer "D")))
          (should (equal (window-parameter c 'tab-line-buffers)
                         (list (get-buffer "C") (get-buffer "D")))))))))

(ert-deftest tiling/arrange-one-pane-does-nothing ()
  (+test-tiling
    (let ((window (selected-window)))
      (+my/tiling-arrange)
      (should (eq (selected-window) window))
      (should (= (length (window-list)) 1)))))

(ert-deftest tiling/arrange-resized-stack-is-balanced-again ()
  (+test-tiling
    (+my/tiling-split) (+my/tiling-split) (+my/tiling-split)
    (select-window (nth 2 (+my/tiling--panes)))
    (enlarge-window 3)
    (+my/tiling-arrange)
    (let ((heights (mapcar #'window-total-height (cdr (+my/tiling--panes)))))
      (should (<= (- (apply #'max heights) (apply #'min heights)) 1)))
    (should (eq (selected-window) (nth 2 (+my/tiling--panes))))))

;; ====== A PANE CLOSED ======

(defun +test-tiling--stack-heights ()
  "The heights of the panes stacked on the right (all but the first)."
  (mapcar #'window-total-height (cdr (+my/tiling--panes))))

(defun +test-tiling--even-p (heights)
  (<= (- (apply #'max heights) (apply #'min heights)) 1))

(ert-deftest tiling/a-closed-pane-s-rows-shared-by-the-stack ()
  "Main pane and three stacked: one of the stack closed, the two left at
equal heights again (Emacs gave its rows to its neighbour); the main pane's
width as it was."
  (+test-tiling
    (let ((main (selected-window)))
      (dolist (name '("B" "C" "D"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (should (= (length (+my/tiling--panes)) 4))
      (should (+test-tiling--even-p (+test-tiling--stack-heights)))
      (+my/tiling--closed-h (selected-frame)) ; seen: 4 panes
      (let ((width (window-total-width main)))
        (delete-window (get-buffer-window "C"))
        (should-not (+test-tiling--even-p (+test-tiling--stack-heights)))
        (+my/tiling--closed-h (selected-frame))
        (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "B" "D")))
        (should (+test-tiling--even-p (+test-tiling--stack-heights)))
        (should (= (window-total-width main) width))))))

(ert-deftest tiling/heights-kept-when-no-pane-closed ()
  "Panes resized by hand, none closed (or one added): their heights stay."
  (+test-tiling
    (let ((main (selected-window)))
      (dolist (name '("B" "C" "D"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (+my/tiling--closed-h (selected-frame))
      (with-selected-window (get-buffer-window "B")
        (enlarge-window 2))
      (let ((heights (+test-tiling--stack-heights)))
        (should-not (+test-tiling--even-p heights))
        (+my/tiling--closed-h (selected-frame))
        (should (equal (+test-tiling--stack-heights) heights))))))

(ert-deftest tiling/a-closed-pane-not-laid-out-tall-left-alone ()
  "Panes of one's own (not tall): left as they are; down to one pane: nothing."
  (+test-tiling
    (split-window nil nil 'below)
    (split-window nil nil 'below)
    (+my/tiling--closed-h (selected-frame))
    (delete-window (car (last (window-list))))
    (let ((heights (mapcar #'window-total-height (+my/tiling--panes))))
      (+my/tiling--closed-h (selected-frame))
      (should (equal (mapcar #'window-total-height (+my/tiling--panes)) heights)))
    (delete-other-windows)
    (+my/tiling--closed-h (selected-frame))
    (should (= (length (+my/tiling--panes)) 1))))

(ert-deftest tiling/closed-panes-watched ()
  (should (memq #'+my/tiling--closed-h (default-value 'window-state-change-functions)))
  (should (eq (plist-get (alist-get 'tall +my/tiling-strategies) :closed) #'+my/tiling-tall-closed)))

;; ====== SPC w RET ======

(ert-deftest tiling/swap-main-from-the-stack ()
  "From a stacked pane: its buffer (tabs, point, history) to the main pane, the
main's to its place, the focus on the main pane; the sizes kept."
  (+test-tiling
    (+my/tiling-split) (+my/tiling-split)
    (let* ((panes (+my/tiling--panes))
           (bottom (nth 2 panes))
           (widths (mapcar #'window-total-width panes)))
      (set-window-buffer (nth 1 panes) "B")
      (set-window-buffer bottom "C")
      (with-current-buffer "C" (insert "some\ntext\nhere\n"))
      (set-window-point bottom 6)
      (set-window-prev-buffers bottom (list (list (get-buffer "D") 1 1)))
      (set-window-parameter bottom 'tab-line-buffers (list (get-buffer "C") (get-buffer "D")))
      (set-window-parameter (car panes) 'tab-line-buffers (list (get-buffer "A")))
      (select-window bottom)
      (+my/tiling-swap-main)
      (should (equal (mapcar #'car (+test-tiling--layout)) '("C" "B" "A")))
      (should (equal (+my/tiling--panes) panes))
      (should (equal (mapcar #'window-total-width panes) widths))
      (should (eq (selected-window) (car panes)))
      (should (= (window-point (car panes)) 6))
      (should (eq (car (car (window-prev-buffers (car panes)))) (get-buffer "D")))
      (should (equal (window-parameter (car panes) 'tab-line-buffers)
                     (list (get-buffer "C") (get-buffer "D"))))
      (should (equal (window-parameter bottom 'tab-line-buffers) (list (get-buffer "A")))))))

(ert-deftest tiling/swap-main-from-the-main-pane ()
  "From the main pane: the next pane's buffer to it, the focus kept there."
  (+test-tiling
    (+my/tiling-split)
    (set-window-buffer (nth 1 (+my/tiling--panes)) "B")
    (select-window (car (+my/tiling--panes)))
    (+my/tiling-swap-main)
    (should (equal (mapcar #'car (+test-tiling--layout)) '("B" "A")))
    (should (eq (selected-window) (car (+my/tiling--panes))))))

(ert-deftest tiling/swap-main-needs-two-panes ()
  (+test-tiling
    (should-error (+my/tiling-swap-main) :type 'user-error)))

;; ====== SPC w ] / [ ======

(defun +test-tiling--main-share ()
  "The main pane's share of the frame's width, rounded to a hundredth."
  (/ (round (* 100 (/ (float (window-total-width (car (+my/tiling--panes))))
                      (window-total-width (window-main-window)))))
     100.0))

(ert-deftest tiling/main-bigger-and-smaller ()
  "SPC w ] / [ from any pane: the main pane a step bigger / smaller, the
ratio kept for SPC w a; the focus where it was."
  (+test-tiling
    (+my/tiling-split) (+my/tiling-split)
    (let ((window (selected-window)))
      (+my/tiling-main-bigger)
      (should (= +my/tiling-tall-ratio 0.55))
      (should (< (abs (- (+test-tiling--main-share) 0.55)) 0.02))
      (should (eq (selected-window) window))
      (+my/tiling-main-smaller) (+my/tiling-main-smaller)
      (should (= +my/tiling-tall-ratio 0.45))
      (should (< (abs (- (+test-tiling--main-share) 0.45)) 0.02))
      (+my/tiling-arrange)
      (should (< (abs (- (+test-tiling--main-share) 0.45)) 0.02)))))

(ert-deftest tiling/main-resize-within-limits ()
  (+test-tiling
    (+my/tiling-split)
    (dotimes (_ 20) (+my/tiling-main-bigger))
    (should (= +my/tiling-tall-ratio (cdr +my/tiling-tall-ratio-limits)))
    (dotimes (_ 20) (+my/tiling-main-smaller))
    (should (= +my/tiling-tall-ratio (car +my/tiling-tall-ratio-limits)))))

(ert-deftest tiling/main-resize-arranges-first ()
  "Panes not laid out tall: arranged first, then resized."
  (+test-tiling
    (split-window nil nil 'below)
    (+my/tiling-main-bigger)
    (should (+my/tiling--tall-p (window-main-window)))
    (should (< (abs (- (+test-tiling--main-share) 0.55)) 0.02))))

(ert-deftest tiling/main-resize-needs-two-panes ()
  (+test-tiling
    (should-error (+my/tiling-main-bigger) :type 'user-error)
    (should (= +my/tiling-tall-ratio 0.5))))

;; ====== RESIZING, THE STRATEGY'S ======

(defmacro +test-tiling-resizing (&rest body)
  "BODY with the strategy `stand-in': two panes one above the other, its
main area (the top pane) resized in height, 2 lines a step; the current pane
resized by recording it. What was asked in `asked', what was said in
`said', the repeat map in `repeat'."
  (declare (indent 0))
  `(let* ((asked nil) (said nil) (repeat nil)
          (+my/tiling-strategies
           (cons (list 'stand-in
                       :split (lambda (panes) (split-window (car (last panes)) nil 'below))
                       :arrange #'ignore
                       :resize-main (lambda (panes direction)
                                      (push (list :main panes direction) asked)
                                      (window-resize (car panes) (* 2 direction))
                                      (format "Top pane: %d lines" (window-total-height (car panes))))
                       :resize-pane (lambda (panes pane direction)
                                      (push (list :pane panes pane direction) asked)
                                      "Pane: resized"))
                 +my/tiling-strategies))
          (+my/tiling-strategy 'stand-in))
     (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
               ((symbol-function 'set-transient-map) (lambda (map &rest _) (setq repeat map))))
       ,@body)))

(ert-deftest tiling/resize-main-the-strategys ()
  "SPC w ] / [ ask the strategy's :resize-main (its main area: here a height,
not the width), say what it did, and repeat."
  (+test-tiling
    (+test-tiling-resizing
      (set-window-buffer (split-window nil nil 'below) "B")
      (let* ((panes (+my/tiling--panes))
             (height (window-total-height (car panes))))
        (+my/tiling-main-bigger)
        (should (equal (car asked) (list :main panes 1)))
        (should (= (window-total-height (car panes)) (+ height 2)))
        (should (equal said (format "Top pane: %d lines (] / [ again)" (+ height 2))))
        (+my/tiling-main-smaller)
        (should (equal (car asked) (list :main panes -1)))
        (should (= (window-total-height (car panes)) height))
        ;; ] [ } { again, after either.
        (dolist (key '("]" "[" "}" "{"))
          (should (lookup-key repeat key)))))))

(ert-deftest tiling/resize-pane-the-strategys ()
  "The current pane bigger / smaller: the strategy's :resize-pane, given the
panes, the current one and the direction."
  (+test-tiling
    (+test-tiling-resizing
      (set-window-buffer (split-window nil nil 'below) "B")
      (select-window (cadr (+my/tiling--panes)))
      (+my/tiling-pane-smaller)
      (should (equal (car asked) (list :pane (+my/tiling--panes) (selected-window) -1)))
      (should (equal said "Pane: resized (} / { again)"))
      (+my/tiling-pane-bigger)
      (should (equal (nth 3 (car asked)) 1)))))

(ert-deftest tiling/resize-without-it-said ()
  "A strategy without a resize: said, nothing done; with one pane: said."
  (+test-tiling
    (set-window-buffer (split-window nil nil 'right) "B")
    (let* ((+my/tiling-strategies (cons '(bare :split ignore :arrange ignore) +my/tiling-strategies))
           (+my/tiling-strategy 'bare))
      (should (equal (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))
                     (format-message "The tiling strategy `bare' has no pane to resize")))
      (should (equal (cadr (should-error (+my/tiling-main-bigger) :type 'user-error))
                     (format-message "The tiling strategy `bare' has no main area to resize"))))
    (should (= +my/tiling-tall-ratio 0.5)))
  (+test-tiling
    (+test-tiling-resizing
      (should-error (+my/tiling-main-bigger) :type 'user-error)
      (should-not asked))))

(ert-deftest tiling/tall-resize-main-says-its-share ()
  "Tall's main area: the main pane's width, said as its share."
  (+test-tiling
    (+my/tiling-split)
    (let (said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args)))))
        (+my/tiling-main-bigger))
      (should (equal said "Main pane: 55% of the width (] / [ again)")))
    (should (eq (plist-get (alist-get 'tall +my/tiling-strategies) :resize-main) #'+my/tiling-tall-resize-main))))

;; ====== TALL: A PANE OF THE STACK TALLER / SHORTER ======

(defmacro +test-tiling-stack (&rest body)
  "BODY with A the main pane, B, C and D stacked on the right (seen by the
closed-pane watch); `said' what was said."
  (declare (indent 0))
  `(+test-tiling
     (let ((main (selected-window)) (said nil))
       (dolist (name '("B" "C" "D"))
         (select-window main)
         (pop-to-buffer name '(+my/tiling-display-buffer)))
       (+my/tiling--closed-h (selected-frame))
       (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
                 ((symbol-function 'set-transient-map) #'ignore))
         ,@body))))

(defun +test-tiling--height (name)
  (window-total-height (get-buffer-window name)))

(defun +test-tiling--others-even-p (name)
  "The stack's panes but NAME's at equal heights (within a line)."
  (+test-tiling--even-p (mapcar #'window-total-height
                                (remq (get-buffer-window name) (cdr (+my/tiling--panes))))))

(ert-deftest tiling/stack-pane-taller-and-shorter ()
  "SPC w } on the middle of three stacked panes: it taller, the other two
shorter and equal; } again: taller still; { back; the main pane's width as
it was."
  (+test-tiling-stack
    (let ((before (+test-tiling--height "C"))
          (width (window-total-width main)))
      (select-window (get-buffer-window "C"))
      (+my/tiling-pane-bigger)
      (should (> (+test-tiling--height "C") before))
      (should (+test-tiling--others-even-p "C"))
      (should (< (+test-tiling--height "B") before))
      (should (string-match-p "\\`Pane: [0-9]+% of the stack's height (} / { again)\\'" said))
      (let ((once (+test-tiling--height "C")))
        (+my/tiling-pane-bigger)
        (should (> (+test-tiling--height "C") once))
        (should (+test-tiling--others-even-p "C")))
      (+my/tiling-pane-smaller) (+my/tiling-pane-smaller)
      (should (<= (abs (- (+test-tiling--height "C") before)) 1))
      (should (eq (selected-window) (get-buffer-window "C")))
      (should (= (window-total-width main) width)))))

(ert-deftest tiling/stack-pane-height-kept ()
  "The resized pane keeps its height: SPC w a, a new pane, another pane
closed; the others even out. Closed itself: all even again."
  (+test-tiling-stack
    (select-window (get-buffer-window "C"))
    (+my/tiling-pane-bigger) (+my/tiling-pane-bigger)
    (let ((height (+test-tiling--height "C")))
      (+my/tiling-arrange)
      (should (= (+test-tiling--height "C") height))
      (should (+test-tiling--others-even-p "C"))
      ;; A new pane at the bottom: its height still.
      (select-window main)
      (pop-to-buffer (+test-buffer "E") '(+my/tiling-display-buffer))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "B" "C" "D" "E")))
      (should (= (+test-tiling--height "C") height))
      (should (+test-tiling--others-even-p "C"))
      (+my/tiling--closed-h (selected-frame))
      ;; Another closed.
      (delete-window (get-buffer-window "B"))
      (+my/tiling--closed-h (selected-frame))
      (should (= (+test-tiling--height "C") height))
      (should (+test-tiling--others-even-p "C"))
      ;; Itself closed: the rest even.
      (delete-window (get-buffer-window "C"))
      (+my/tiling--closed-h (selected-frame))
      (should (+test-tiling--even-p (+test-tiling--stack-heights))))))

(ert-deftest tiling/stack-pane-one-resized-at-a-time ()
  "Resizing another pane of the stack: the first evens out with the rest."
  (+test-tiling-stack
    (select-window (get-buffer-window "C"))
    (+my/tiling-pane-bigger) (+my/tiling-pane-bigger)
    (select-window (get-buffer-window "B"))
    (+my/tiling-pane-smaller)
    (should (< (+test-tiling--height "B") (+test-tiling--height "D")))
    (should (+test-tiling--others-even-p "B"))
    (should (window-parameter (get-buffer-window "B") '+my/tiling-share))
    (should-not (window-parameter (get-buffer-window "C") '+my/tiling-share))))

(ert-deftest tiling/stack-pane-within-limits ()
  "However many times: every pane of the stack at least `window-min-height'."
  (+test-tiling-stack
    (select-window (get-buffer-window "C"))
    (dotimes (_ 30) (+my/tiling-pane-bigger))
    (dolist (height (+test-tiling--stack-heights))
      (should (>= height window-min-height)))
    (dotimes (_ 30) (+my/tiling-pane-smaller))
    (should (= (+test-tiling--height "C") window-min-height))
    (should (+test-tiling--others-even-p "C"))))

(ert-deftest tiling/stack-pane-resize-from-the-main-pane-said ()
  "The main pane, or the stack's only pane: as tall as the frame, said;
nothing changes."
  (+test-tiling-stack
    (select-window main)
    (let ((heights (+test-tiling--stack-heights)))
      (should (string-match-p "The main pane is as tall as the frame"
                              (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))))
      (should (equal (+test-tiling--stack-heights) heights))))
  (+test-tiling
    (+my/tiling-split)
    (should (string-match-p "The only pane on the right"
                            (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))))))

;; ====== THE MAIN PANE'S SHARE, TWO PANES ======

(ert-deftest tiling/arrange-two-panes-keeps-the-ratio ()
  "Two panes arranged: the main pane its share of the width, not half (the
stack's one pane balanced with it undid it)."
  (dolist (strategy '(tall tall-right))
    (+test-tiling
      (let ((+my/tiling-strategy strategy)
            (+my/tiling-tall-ratio 0.7))
        (set-window-buffer (split-window nil nil 'below) "B")
        (+my/tiling-arrange)
        (should (< (abs (- (/ (float (window-total-width (car (+my/tiling--ordered-panes))))
                              (window-total-width (window-main-window)))
                           0.7))
                   0.03))))))

(ert-deftest tiling/no-room-for-another-pane-said ()
  "The stack full (each pane at its smallest): SPC w SPC says so, a user
error, and opens nothing."
  (+test-tiling
    (let ((count 0) error)
      (while (and (not error) (< count 50))
        (condition-case err
            (progn (+my/tiling-split) (cl-incf count))
          (user-error (setq error err))))
      (should error)
      (should (equal (cadr error) "No room for another pane"))
      (should (= (length (+my/tiling--panes)) (1+ count))))))

;; ====== TALL-RIGHT ======

(defmacro +test-tiling-tall-right (&rest body)
  "BODY as `+test-tiling', the strategy tall-right."
  (declare (indent 0))
  `(+test-tiling
     (let ((+my/tiling-strategy 'tall-right))
       ,@body)))

(defun +test-tiling--names (panes)
  (mapcar (lambda (pane) (buffer-name (window-buffer pane))) panes))

(defun +test-tiling--right-of-p (a b)
  "Non-nil if window A is on the right of window B, beside it."
  (>= (car (window-edges a)) (nth 2 (window-edges b))))

(ert-deftest tiling/tall-right-is-a-strategy ()
  (let ((strategy (alist-get 'tall-right +my/tiling-strategies)))
    (dolist (key '(:split :arrange :resize-main :resize-pane :closed :order))
      (should (functionp (plist-get strategy key))))))

(ert-deftest tiling/tall-right-first-split-goes-left ()
  "From one pane: the new one on its left, focused; the old one stays the
main pane, on the right, its share of the width; first in order."
  (+test-tiling-tall-right
    (let* ((main (selected-window))
           (width (window-total-width main))
           (new (+my/tiling-split)))
      (should (eq new (selected-window)))
      (should (+test-tiling--right-of-p main new))
      (should (= (cadr (window-edges new)) (cadr (window-edges main))))
      (should (<= (abs (- (window-total-width main) (round (* 0.5 width)))) 1))
      (should (equal (+my/tiling--panes) (list new main)))
      (should (equal (+my/tiling--ordered-panes) (list main new))))))

(ert-deftest tiling/tall-right-next-splits-stack-on-the-left ()
  "The next panes at the bottom of the stack on the left, top to bottom in
the order opened, at equal heights; the main pane on the right, as tall as
the frame."
  (+test-tiling-tall-right
    (let ((main (selected-window)))
      (dolist (name '("B" "C" "D"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("A" "B" "C" "D")))
      (should (equal (+test-tiling--names (+my/tiling--panes)) '("B" "C" "D" "A")))
      (let ((stack (cdr (+my/tiling--ordered-panes))))
        (dolist (pane stack)
          (should (+test-tiling--right-of-p main pane)))
        (should (< (cadr (window-edges (nth 0 stack))) (cadr (window-edges (nth 1 stack)))
                   (cadr (window-edges (nth 2 stack)))))
        (should (+test-tiling--even-p (mapcar #'window-total-height stack))))
      (should (= (window-total-height main) (window-total-height (window-main-window)))))))

(ert-deftest tiling/tall-right-arranges-other-layouts ()
  "From tall (or panes of one's own): SPC w a puts the first pane, the main
one, on the right, the others on the left in order; what they show, the
focus, kept."
  (+test-tiling
    (let ((main (selected-window)))
      (dolist (name '("B" "C"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (select-window (get-buffer-window "C"))
      (let ((+my/tiling-strategy 'tall-right))
        (+my/tiling-arrange)
        (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("A" "B" "C")))
        (should (+test-tiling--right-of-p (get-buffer-window "A") (get-buffer-window "B")))
        (should (equal (buffer-name (window-buffer (selected-window))) "C"))
        ;; And back: tall again.
        (let ((+my/tiling-strategy 'tall))
          (+my/tiling-arrange)
          (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "B" "C")))
          (should (+test-tiling--right-of-p (get-buffer-window "B") (get-buffer-window "A"))))))))

(ert-deftest tiling/the-main-pane-found-without-its-mark ()
  "No pane marked the main one (a workspace switched to makes its windows
anew): tall-right finds it on the right (its :order), tall takes the first."
  (+test-tiling-tall-right
    (let ((main (selected-window)))
      (dolist (name '("B" "C"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (should (window-parameter main '+my/tiling-main))
      (dolist (pane (+my/tiling--panes))
        (set-window-parameter pane '+my/tiling-main nil))
      (should (eq (car (+my/tiling--ordered-panes)) main))
      (let ((+my/tiling-strategy 'tall))
        (should (equal (+my/tiling--ordered-panes) (+my/tiling--panes)))))))

(ert-deftest tiling/tall-right-swap-main ()
  "SPC w RET from a pane on the left: its buffer to the main pane on the
right, the main's to it, the focus to the main pane."
  (+test-tiling-tall-right
    (let ((main (selected-window)))
      (dolist (name '("B" "C"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (select-window (get-buffer-window "C"))
      (+my/tiling-swap-main)
      (should (eq (selected-window) main))
      (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("C" "B" "A"))))))

(ert-deftest tiling/tall-right-resize-main ()
  "SPC w ] / [: the main pane on the right wider / narrower, tall's ratio
kept (switching to tall keeps it)."
  (+test-tiling-tall-right
    (+my/tiling-split) (+my/tiling-split)
    (let (said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
                ((symbol-function 'set-transient-map) #'ignore))
        (+my/tiling-main-bigger))
      (should (equal said "Main pane: 55% of the width (] / [ again)")))
    (should (= +my/tiling-tall-ratio 0.55))
    (let ((main (car (+my/tiling--ordered-panes))))
      (should (eq main (car (last (+my/tiling--panes)))))
      (should (< (abs (- (/ (float (window-total-width main)) (window-total-width (window-main-window))) 0.55))
                 0.02)))))

(ert-deftest tiling/tall-right-resize-pane ()
  "SPC w } / {: a pane on the left taller / shorter, the others even; from
the main pane, or the stack's only one: said."
  (+test-tiling-tall-right
    (let ((main (selected-window)) said)
      (pop-to-buffer "B" '(+my/tiling-display-buffer))
      (select-window main)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
                ((symbol-function 'set-transient-map) #'ignore))
        (select-window (get-buffer-window "B"))
        (should (equal (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))
                       "The only pane on the left is as tall as the frame"))
        (dolist (name '("C" "D"))
          (select-window main)
          (pop-to-buffer name '(+my/tiling-display-buffer)))
        (select-window main)
        (should-error (+my/tiling-pane-bigger) :type 'user-error)
        (select-window (get-buffer-window "C"))
        (let ((before (window-total-height (selected-window))))
          (+my/tiling-pane-bigger)
          (should (> (window-total-height (selected-window)) before))
          (should (string-match-p "\\`Pane: [0-9]+% of the stack's height" said))
          (should (+test-tiling--even-p (mapcar #'window-total-height
                                                (list (get-buffer-window "B") (get-buffer-window "D"))))))))))

(ert-deftest tiling/tall-right-closed-pane-s-rows-shared ()
  "A pane of the stack closed: the stack on the left at equal heights again;
the main pane's width as it was."
  (+test-tiling-tall-right
    (let ((main (selected-window)))
      (dolist (name '("B" "C" "D"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (+my/tiling--closed-h (selected-frame))
      (let ((width (window-total-width main)))
        (delete-window (get-buffer-window "C"))
        (+my/tiling--closed-h (selected-frame))
        (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("A" "B" "D")))
        (should (+test-tiling--even-p (mapcar #'window-total-height (cdr (+my/tiling--ordered-panes)))))
        (should (= (window-total-width main) width))))))

;; ====== WIDE ======

(defmacro +test-tiling-wide (&rest body)
  "BODY as `+test-tiling', the strategy wide (its share of the height 0.5)."
  (declare (indent 0))
  `(+test-tiling
     (let ((+my/tiling-strategy 'wide)
           (+my/tiling-wide-ratio 0.5))
       ,@body)))

(defun +test-tiling--below-p (a b)
  "Non-nil if window A is below window B."
  (>= (cadr (window-edges a)) (nth 3 (window-edges b))))

(defun +test-tiling--height-share (window)
  (/ (float (window-total-height window)) (window-total-height (window-main-window))))

(defun +test-tiling--wide-row (&rest names)
  "A the main pane, NAMES opened after it (each from A, as an application)."
  (let ((main (selected-window)))
    (dolist (name names)
      (select-window main)
      (pop-to-buffer name '(+my/tiling-display-buffer)))
    main))

(ert-deftest tiling/wide-is-a-strategy ()
  (let ((strategy (alist-get 'wide +my/tiling-strategies)))
    (dolist (key '(:split :arrange :resize-main :resize-pane :closed))
      (should (functionp (plist-get strategy key)))))
  (should (= (default-value '+my/tiling-wide-ratio) 0.5)))

(ert-deftest tiling/wide-first-split-goes-below ()
  "From one pane: the new one below it, focused; the old one stays the main
pane on top, its share of the height, as wide as the frame."
  (+test-tiling-wide
    (let* ((main (selected-window))
           (height (window-total-height main))
           (new (+my/tiling-split)))
      (should (eq new (selected-window)))
      (should (+test-tiling--below-p new main))
      (should (= (car (window-edges new)) (car (window-edges main))))
      (should (= (window-total-width main) (window-total-width (window-main-window))))
      (should (<= (abs (- (window-total-height main) (round (* 0.5 height)))) 1))
      (should (equal (+my/tiling--ordered-panes) (list main new))))))

(ert-deftest tiling/wide-next-splits-in-a-row-below ()
  "The next panes at the right end of the row below, left to right in the
order opened, at equal widths; the main pane on top, as wide as the frame."
  (+test-tiling-wide
    (let* ((main (+test-tiling--wide-row "B" "C" "D"))
           (row (cdr (+my/tiling--ordered-panes))))
      (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("A" "B" "C" "D")))
      (dolist (pane row)
        (should (+test-tiling--below-p pane main)))
      (should (= (cadr (window-edges (nth 0 row))) (cadr (window-edges (nth 1 row)))
                 (cadr (window-edges (nth 2 row)))))
      (should (< (car (window-edges (nth 0 row))) (car (window-edges (nth 1 row)))
                 (car (window-edges (nth 2 row)))))
      (should (+test-tiling--even-p (mapcar #'window-total-width row)))
      (should (= (window-total-width main) (window-total-width (window-main-window)))))))

(ert-deftest tiling/wide-arranges-other-layouts ()
  "From tall: SPC w a puts the main pane on top, the others in a row below;
back to tall, the same main pane on the left."
  (+test-tiling
    (let ((main (selected-window)))
      (dolist (name '("B" "C"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (let ((+my/tiling-strategy 'wide)
            (+my/tiling-wide-ratio 0.5))
        (+my/tiling-arrange)
        (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("A" "B" "C")))
        (should (+test-tiling--below-p (get-buffer-window "B") (get-buffer-window "A")))
        (should (+test-tiling--right-of-p (get-buffer-window "C") (get-buffer-window "B")))
        (let ((+my/tiling-strategy 'tall))
          (+my/tiling-arrange)
          (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "B" "C")))
          (should (+test-tiling--right-of-p (get-buffer-window "B") (get-buffer-window "A"))))))))

(ert-deftest tiling/wide-swap-main ()
  (+test-tiling-wide
    (let ((main (+test-tiling--wide-row "B" "C")))
      (select-window (get-buffer-window "C"))
      (+my/tiling-swap-main)
      (should (eq (selected-window) main))
      (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("C" "B" "A"))))))

(ert-deftest tiling/wide-resize-main-its-height ()
  "SPC w ] / [: the main pane taller / shorter, wide's own ratio (tall's
left as it is), said as its share of the height."
  (+test-tiling-wide
    (+test-tiling--wide-row "B" "C")
    (let (said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
                ((symbol-function 'set-transient-map) #'ignore))
        (+my/tiling-main-bigger))
      (should (equal said "Main pane: 55% of the height (] / [ again)")))
    (should (= +my/tiling-wide-ratio 0.55))
    (should (= +my/tiling-tall-ratio 0.5))
    (should (< (abs (- (+test-tiling--height-share (car (+my/tiling--ordered-panes))) 0.55)) 0.05))
    (+my/tiling-arrange)
    (should (< (abs (- (+test-tiling--height-share (car (+my/tiling--ordered-panes))) 0.55)) 0.05))))

(ert-deftest tiling/wide-two-panes-keep-the-ratio ()
  (+test-tiling-wide
    (let ((+my/tiling-wide-ratio 0.7))
      (set-window-buffer (split-window nil nil 'right) "B")
      (+my/tiling-arrange)
      (should (< (abs (- (+test-tiling--height-share (car (+my/tiling--ordered-panes))) 0.7)) 0.05)))))

(ert-deftest tiling/wide-resize-pane-its-width ()
  "SPC w } / {: a pane of the row wider / narrower, the others even; from
the main pane, or the row's only one: said."
  (+test-tiling-wide
    (let ((main (+test-tiling--wide-row "B")) said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
                ((symbol-function 'set-transient-map) #'ignore))
        (select-window (get-buffer-window "B"))
        (should (equal (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))
                       "The only pane below is as wide as the frame"))
        (dolist (name '("C" "D"))
          (select-window main)
          (pop-to-buffer name '(+my/tiling-display-buffer)))
        (select-window main)
        (should (equal (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))
                       "The main pane is as wide as the frame (SPC w ] / [ make it taller, shorter)"))
        (select-window (get-buffer-window "C"))
        (let ((before (window-total-width (selected-window))))
          (+my/tiling-pane-bigger)
          (should (> (window-total-width (selected-window)) before))
          (should (string-match-p "\\`Pane: [0-9]+% of the stack's width" said))
          (should (+test-tiling--even-p (mapcar #'window-total-width
                                                (list (get-buffer-window "B") (get-buffer-window "D")))))
          ;; Kept: SPC w a keeps it wider.
          (let ((width (window-total-width (selected-window))))
            (+my/tiling-arrange)
            (should (<= (abs (- (window-total-width (get-buffer-window "C")) width)) 1))))))))

(ert-deftest tiling/wide-closed-pane-s-columns-shared ()
  "A pane of the row closed: the row at equal widths again; the main pane's
height as it was."
  (+test-tiling-wide
    (let ((main (+test-tiling--wide-row "B" "C" "D")))
      (+my/tiling--closed-h (selected-frame))
      (let ((height (window-total-height main)))
        (delete-window (get-buffer-window "C"))
        (should-not (+test-tiling--even-p (mapcar #'window-total-width (cdr (+my/tiling--ordered-panes)))))
        (+my/tiling--closed-h (selected-frame))
        (should (equal (+test-tiling--names (+my/tiling--ordered-panes)) '("A" "B" "D")))
        (should (+test-tiling--even-p (mapcar #'window-total-width (cdr (+my/tiling--ordered-panes)))))
        (should (= (window-total-height main) height))))))

(ert-deftest tiling/wide-a-full-row-said ()
  "The row full (each pane at its narrowest): SPC w SPC says so, and opens
nothing."
  (+test-tiling-wide
    (let ((count 0) error)
      (while (and (not error) (< count 50))
        (condition-case err
            (progn (+my/tiling-split) (cl-incf count))
          (user-error (setq error err))))
      (should (equal (cadr error) "No room for another pane"))
      (should (> count 2))
      (should (= (length (+my/tiling--panes)) (1+ count)))
      (should (<= window-min-width (apply #'min (mapcar #'window-total-width (cdr (+my/tiling--ordered-panes)))))))))

;; ====== FULLSCREEN ======

(defvar persp-mode)                     ; Doom's workspaces (persp-mode)

(defmacro +test-tiling-fullscreen (&rest body)
  "BODY as `+test-tiling', the strategy fullscreen; no pane hidden before or
after."
  (declare (indent 0))
  `(+test-tiling
     (set-frame-parameter nil '+my/tiling-hidden nil)
     (unwind-protect
         (let ((+my/tiling-strategy 'fullscreen))
           (cl-letf (((symbol-function 'message) #'ignore))
             ,@body))
       (set-frame-parameter nil '+my/tiling-hidden nil))))

(defun +test-tiling--slots ()
  "The panes in order: each one's buffer name, the one on the screen with a *."
  (mapcar (lambda (slot)
            (if (eq slot :shown)
                (concat "*" (buffer-name (window-buffer (car (+my/tiling--panes)))))
              (buffer-name (plist-get slot :buffer))))
          (or (+my/tiling--slots) (list :shown))))

(defun +test-tiling--fullscreen-open (&rest names)
  "Open a pane for each of NAMES (SPC w SPC, then the buffer shown in it)."
  (dolist (name names)
    (+my/tiling-split)
    (switch-to-buffer name)))

(ert-deftest tiling/fullscreen-is-a-strategy ()
  (let ((strategy (alist-get 'fullscreen +my/tiling-strategies)))
    (dolist (key '(:split :arrange :swap-main :show))
      (should (functionp (plist-get strategy key))))
    (should (plist-get strategy :hides))
    (should-not (plist-get strategy :resize-main))
    (should-not (plist-get strategy :resize-pane))))

(ert-deftest tiling/fullscreen-a-new-pane-opens-alone ()
  "SPC w SPC: the new pane alone in the frame, showing the current buffer, the
one before it hidden just before it."
  (+test-tiling-fullscreen
    (let ((window (selected-window)))
      (+my/tiling-split)
      (should (equal (+my/tiling--panes) (list window)))
      (should (equal (+test-tiling--slots) '("A" "*A")))
      (switch-to-buffer "B")
      (+my/tiling-split)
      (switch-to-buffer "C")
      (should (= (length (window-list)) 1))
      (should (equal (+test-tiling--slots) '("A" "B" "*C")))
      ;; From the middle: just after it.
      (+my/tiling-previous-pane)
      (+my/tiling-split)
      (switch-to-buffer "D")
      (should (equal (+test-tiling--slots) '("A" "B" "*D" "C"))))))

(ert-deftest tiling/fullscreen-panes-in-turn ()
  "SPC w w / W: the next / previous pane in front, wrapping, each with its
buffer and point; what's said."
  (+test-tiling-fullscreen
    (with-current-buffer "B" (erase-buffer) (insert "line 1\nline 2\nline 3\n"))
    (+test-tiling--fullscreen-open "B" "C")
    (should (equal (+test-tiling--slots) '("A" "B" "*C")))
    (+my/tiling-previous-pane)
    (should (equal (+test-tiling--slots) '("A" "*B" "C")))
    ;; Point moved in B's pane (as a command would: its buffer current).
    (set-window-point nil (with-current-buffer "B" (goto-char (point-min)) (line-beginning-position 3)))
    (let ((point (window-point)) said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args)))))
        (+my/tiling-next-pane)
        (should (equal said "Pane 3/3"))
        (+my/tiling-next-pane)
        (should (equal said "Pane 1/3")))
      (should (equal (+test-tiling--slots) '("*A" "B" "C")))
      (+my/tiling-next-pane)
      (should (equal (+test-tiling--slots) '("A" "*B" "C")))
      (should (= (window-point) point)))))

(ert-deftest tiling/fullscreen-arranges-other-layouts ()
  "From tall: SPC w a keeps the selected pane alone, the others hidden in
order; back to tall (its SPC w a), all shown again, laid out tall, the main
pane the first."
  (+test-tiling
    (let ((main (selected-window)))
      (dolist (name '("B" "C"))
        (select-window main)
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (select-window (get-buffer-window "B"))
      (unwind-protect
          (progn
            (let ((+my/tiling-strategy 'fullscreen))
              (+my/tiling-arrange)
              (should (= (length (window-list)) 1))
              (should (equal (+test-tiling--slots) '("A" "*B" "C"))))
            (+my/tiling-arrange)
            (should-not (+my/tiling--hidden-p))
            (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "B" "C")))
            (should (+my/tiling--tall-p (window-main-window)))
            (should (equal (buffer-name (window-buffer (selected-window))) "B")))
        (set-frame-parameter nil '+my/tiling-hidden nil)))))

(ert-deftest tiling/fullscreen-left-by-a-new-pane-too ()
  "Another strategy's SPC w SPC shows the hidden panes too, then opens its
own."
  (+test-tiling-fullscreen
    (+test-tiling--fullscreen-open "B")
    (let ((+my/tiling-strategy 'tall))
      (+my/tiling-split)
      (should-not (+my/tiling--hidden-p))
      (should (= (length (+my/tiling--panes)) 3))
      (should (+my/tiling--tall-p (window-main-window)))
      (should (equal (buffer-name (window-buffer (car (+my/tiling--panes)))) "A")))))

(ert-deftest tiling/fullscreen-swap-main ()
  "SPC w RET: the pane on the screen first, the main one tall then lays out."
  (+test-tiling-fullscreen
    (+test-tiling--fullscreen-open "B" "C")
    (let (said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args)))))
        (+my/tiling-swap-main))
      (should (equal said "Pane 1/3, the main one")))
    (should (equal (+test-tiling--slots) '("*C" "A" "B")))
    (let ((+my/tiling-strategy 'tall))
      (+my/tiling-arrange)
      (should (equal (+test-tiling--names (+my/tiling--panes)) '("C" "A" "B"))))))

(ert-deftest tiling/fullscreen-nothing-to-resize ()
  (+test-tiling-fullscreen
    (+test-tiling--fullscreen-open "B")
    (should (equal (cadr (should-error (+my/tiling-main-bigger) :type 'user-error))
                   (format-message "The tiling strategy `fullscreen' has no main area to resize")))
    (should (equal (cadr (should-error (+my/tiling-pane-smaller) :type 'user-error))
                   (format-message "The tiling strategy `fullscreen' has no pane to resize")))))

(ert-deftest tiling/fullscreen-closing-shows-the-next ()
  "SPC w d (`delete-window') on the pane on the screen: the next one shown
(the one before, from the last); down to one, the frame's last window as
ever."
  (+test-tiling-fullscreen
    (+test-tiling--fullscreen-open "B" "C")
    (+my/tiling-previous-pane)
    (delete-window)
    (should (equal (+test-tiling--slots) '("A" "*C")))
    (delete-window)
    (should (equal (+test-tiling--slots) '("*A")))
    (should-not (+my/tiling--hidden-p))
    (should-error (delete-window))))

(ert-deftest tiling/fullscreen-doom-s-spc-w-d-keeps-the-workspace ()
  "Doom's SPC w d (`+workspace/close-window-or-workspace': from a workspace's
only window, it kills the workspace): the pane closed, the next one shown."
  (+test-tiling-fullscreen
    (let ((killed nil))
      (cl-letf* ((original (symbol-function '+workspace/close-window-or-workspace)))
        (unwind-protect
            (progn
              ;; Stands in for Doom's (its module isn't loaded here), the
              ;; tiling's advice kept on it.
              (advice-remove '+workspace/close-window-or-workspace #'+my/tiling-close-shown-not-workspace-a)
              (defalias '+workspace/close-window-or-workspace
                (lambda () (interactive) (setq killed t)))
              (advice-add '+workspace/close-window-or-workspace :before-until
                          #'+my/tiling-close-shown-not-workspace-a)
              (+test-tiling--fullscreen-open "B")
              (call-interactively #'+workspace/close-window-or-workspace)
              (should-not killed)
              (should (equal (+test-tiling--slots) '("*A")))
              ;; Nothing hidden: Doom's, as ever.
              (call-interactively #'+workspace/close-window-or-workspace)
              (should killed))
          (advice-remove '+workspace/close-window-or-workspace #'+my/tiling-close-shown-not-workspace-a)
          (fset '+workspace/close-window-or-workspace original)
          (advice-add '+workspace/close-window-or-workspace :before-until
                      #'+my/tiling-close-shown-not-workspace-a))))))

(ert-deftest tiling/fullscreen-a-pane-closes-with-its-buffer ()
  "Its last tab's buffer killed (SPC b k, a terminal ending): the next pane
shown; a hidden pane's buffer killed: it shows the one it showed before, or
is gone."
  (+test-tiling-fullscreen
    (let ((main (selected-window)))
      (dolist (name '("B" "C" "D"))
        (pop-to-buffer name '(+my/tiling-display-buffer)))
      (should (eq (selected-window) main))
      (should (equal (+test-tiling--slots) '("A" "B" "C" "*D")))
      (kill-buffer "D")
      (should (equal (+test-tiling--slots) '("A" "B" "*C")))
      (kill-buffer "B")
      (should (equal (+my/tiling--show-next 1) "Pane 1/2"))
      (should (equal (+test-tiling--slots) '("*A" "C"))))))

(ert-deftest tiling/fullscreen-quit-closes-the-pane ()
  "q on an application opened in a new pane: the pane closed, the next one
shown; the buffer kept (killed with C-u q)."
  (+test-tiling-fullscreen
    (let ((app (+test-tiling--app "an app")))
      (pop-to-buffer app '(+my/tiling-display-buffer))
      (should (equal (+test-tiling--slots) '("A" "*an app")))
      (quit-window)
      (should (equal (+test-tiling--slots) '("*A")))
      (should (buffer-live-p app))
      (pop-to-buffer app '(+my/tiling-display-buffer))
      (quit-window t)
      (should-not (buffer-live-p app)))))

(ert-deftest tiling/fullscreen-an-application-hidden-brought-to-the-front ()
  "An application shown while its pane is hidden: that pane in front, no new
one."
  (+test-tiling-first
    (set-frame-parameter nil '+my/tiling-hidden nil)
    (unwind-protect
        (let ((+my/tiling-strategy 'fullscreen)
              (app (+test-tiling--app "an app")))
          (cl-letf (((symbol-function 'message) #'ignore))
            (pop-to-buffer app)
            (switch-to-buffer "B")
            (should (equal (+test-tiling--slots) '("A" "*B")))
            (+my/tiling-previous-pane)
            (pop-to-buffer app)
            (should (equal (+test-tiling--slots) '("A" "*an app")))
            (should (= (length (window-list)) 1))))
      (set-frame-parameter nil '+my/tiling-hidden nil))))

(ert-deftest tiling/fullscreen-hidden-panes-hold-their-buffers ()
  "A hidden pane holds its buffer and tabs (a file's last tab closed
elsewhere doesn't close it: config/editor/tabs.el asks)."
  (+test-tiling-fullscreen
    (+test-tiling--fullscreen-open "B")
    (should (+my/tiling--hidden-holds-p (get-buffer "A")))
    (should-not (+my/tiling--hidden-holds-p (get-buffer "C")))
    (should (memq #'+my/tiling--hidden-holds-p +my/tabs-held-functions))))

(ert-deftest tiling/fullscreen-each-workspace-its-panes ()
  "Doom's workspaces each have their windows: their hidden panes too."
  (+test-tiling-fullscreen
    (let ((persp-mode t) (workspace 'one))
      (cl-letf (((symbol-function 'get-current-persp) (lambda (&rest _) workspace)))
        (+test-tiling--fullscreen-open "B")
        (should (equal (+test-tiling--slots) '("A" "*B")))
        (setq workspace 'two)
        (should-not (+my/tiling--hidden-p))
        (setq workspace 'one)
        (should (equal (+test-tiling--slots) '("A" "*B")))))))

(ert-deftest tiling/next-pane-else-evil-s-next-window ()
  "SPC w w / W, another strategy (or no pane hidden): Evil's next / previous
window."
  (+test-tiling
    (let (called)
      (cl-letf (((symbol-function 'evil-window-next) (lambda (&rest _) (interactive) (push 'next called)))
                ((symbol-function 'evil-window-prev) (lambda (&rest _) (interactive) (push 'prev called))))
        (+my/tiling-split)
        (+my/tiling-next-pane)
        (+my/tiling-previous-pane)
        (should (equal called '(prev next)))))))

;; ====== BSP ======

(defmacro +test-tiling-bsp (&rest body)
  "BODY as `+test-tiling', the strategy bsp. Batch Emacs's frame is a text
terminal's: a line counted as two columns (as a GUI's characters, 8 pixels
wide, 16 tall)."
  (declare (indent 0))
  `(+test-tiling
     (let ((+my/tiling-strategy 'bsp))
       ,@body)))

(defun +test-tiling--bsp-open (&rest names)
  "From the selected pane, a new pane for each of NAMES (SPC w SPC), showing it."
  (dolist (name names)
    (+my/tiling-split)
    (switch-to-buffer name)))

(defun +test-tiling--edges (name)
  (window-edges (get-buffer-window name)))

(ert-deftest tiling/bsp-is-a-strategy ()
  (let ((strategy (alist-get 'bsp +my/tiling-strategies)))
    (dolist (key '(:split :arrange :resize-main :resize-pane :closed))
      (should (functionp (plist-get strategy key))))))

(ert-deftest tiling/bsp-each-new-pane-halves-the-current-one ()
  "SPC w SPC halves the current pane along its longer side in pixels, the new
half on the right or below, focused: the frame side by side; the right half,
taller than wide in pixels, one above the other; each split two halves."
  (+test-tiling-bsp
    (let ((width (window-total-width)))
      (+test-tiling--bsp-open "B")
      (should (equal (buffer-name) "B"))
      (should (+test-tiling--right-of-p (get-buffer-window "B") (get-buffer-window "A")))
      (should (<= (abs (- (window-total-width (get-buffer-window "A")) (/ width 2))) 1))
      ;; B: 40 columns by 23 lines, 320 by 368 pixels: taller.
      (+test-tiling--bsp-open "C")
      (should (+test-tiling--below-p (get-buffer-window "C") (get-buffer-window "B")))
      (should (= (car (+test-tiling--edges "C")) (car (+test-tiling--edges "B"))))
      (should (+my/tiling--bsp-p (window-main-window)))
      (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "B" "C"))))))

(ert-deftest tiling/bsp-the-longer-side-as-seen ()
  "More columns than lines, yet taller as seen: one above the other. In a GUI
frame, in pixels; on a text terminal (a pixel a character), a line counted as
two columns."
  (+test-tiling-bsp
    (split-window nil 30 'right)                         ; A: 30 columns by 23 lines
    (should (> (window-total-width) (window-total-height)))
    (should (eq (+my/tiling--bsp-side (selected-window)) 'below)) ; 30 by 46
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
              ((symbol-function 'window-pixel-height) (lambda (&optional w) (* 16 (window-total-height w)))))
      (cl-letf (((symbol-function 'window-pixel-width) (lambda (&optional w) (* 8 (window-total-width w)))))
        (should (eq (+my/tiling--bsp-side (selected-window)) 'below))) ; 240 by 368 pixels
      (cl-letf (((symbol-function 'window-pixel-width) (lambda (&optional w) (* 16 (window-total-width w)))))
        (should (eq (+my/tiling--bsp-side (selected-window)) 'right)))))) ; 480 by 368

(ert-deftest tiling/bsp-from-any-pane ()
  "The pane SPC w SPC is pressed in is the one halved."
  (+test-tiling-bsp
    (+test-tiling--bsp-open "B")
    (select-window (get-buffer-window "A"))
    (+test-tiling--bsp-open "C")
    (should (+test-tiling--below-p (get-buffer-window "C") (get-buffer-window "A")))
    (should (= (nth 2 (+test-tiling--edges "C")) (nth 2 (+test-tiling--edges "A"))))
    (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "C" "B")))))

(ert-deftest tiling/bsp-arranged-as-a-spiral ()
  "SPC w a: each pane halves the last one, along its longer side, evenly: A |
\(B / (C | D)); what each shows, the focus, kept."
  (+test-tiling-bsp
    (let ((main (selected-window)))
      (let ((+my/tiling-strategy 'tall))
        (dolist (name '("B" "C" "D"))
          (select-window main)
          (pop-to-buffer name '(+my/tiling-display-buffer))))
      (select-window (get-buffer-window "C"))
      (+my/tiling-arrange)
      (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "B" "C" "D")))
      (should (equal (buffer-name (window-buffer (selected-window))) "C"))
      (should (+my/tiling--bsp-p (window-main-window)))
      (let ((a (+test-tiling--edges "A")) (b (+test-tiling--edges "B"))
            (c (+test-tiling--edges "C")) (d (+test-tiling--edges "D"))
            (root (window-edges (window-main-window))))
        (should (= (nth 1 a) (nth 1 root)))                               ; A: the whole height
        (should (= (nth 3 a) (nth 3 root)))
        (should (= (nth 0 b) (nth 2 a)))                                  ; B right of A
        (should (= (nth 1 c) (nth 3 b)))                                  ; C below B
        (should (= (nth 1 d) (nth 1 c)))                                  ; D beside C
        (should (= (nth 0 d) (nth 2 c)))
        ;; Even halves.
        (should (<= (abs (- (- (nth 2 a) (nth 0 a)) (- (nth 2 d) (nth 0 b)))) 1))
        (should (<= (abs (- (- (nth 3 b) (nth 1 b)) (- (nth 3 c) (nth 1 c)))) 1))
        (should (<= (abs (- (- (nth 2 c) (nth 0 c)) (- (nth 2 d) (nth 0 d)))) 1))))))

(ert-deftest tiling/bsp-a-closed-pane-s-space-to-its-sibling ()
  "B closed in A | (B / (C | D)): C | D gets the right half, taller than wide
now: laid out again one above the other, evenly; what each shows kept."
  (+test-tiling-bsp
    (+test-tiling--bsp-open "B" "C")
    (+test-tiling--bsp-open "D")
    (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "B" "C" "D")))
    (+my/tiling--closed-h (selected-frame))
    (delete-window (get-buffer-window "B"))
    (+my/tiling--closed-h (selected-frame))
    (should (equal (+test-tiling--names (+my/tiling--panes)) '("A" "C" "D")))
    (should (+test-tiling--below-p (get-buffer-window "D") (get-buffer-window "C")))
    (should (<= (abs (- (window-total-height (get-buffer-window "C"))
                        (window-total-height (get-buffer-window "D"))))
                1))
    (should (+my/tiling--bsp-p (window-main-window)))))

(ert-deftest tiling/bsp-resize-the-current-split-and-the-one-above ()
  "SPC w ] / [: the current pane's half of its split; } / {: its split's half
of the one above; said. Not kept: SPC w a evens them out."
  (+test-tiling-bsp
    (+test-tiling--bsp-open "B" "C")
    (let (said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (setq said (apply #'format args))))
                ((symbol-function 'set-transient-map) #'ignore))
        (let ((before (window-total-height)))
          (+my/tiling-main-bigger)
          (should (> (window-total-height) before))
          (should (string-match-p "\\`Pane: 5[0-9]% of its split (] / \\[ again)" said)))
        (let ((before (window-total-width)))
          (+my/tiling-pane-bigger)
          (should (> (window-total-width) before))
          (should (string-match-p "\\`Its split: 5[0-9]% of the one above" said)))
        (select-window (get-buffer-window "A"))
        (should (equal (cadr (should-error (+my/tiling-pane-bigger) :type 'user-error))
                       "No split above this one"))
        (+my/tiling-arrange)
        (should (<= (abs (- (window-total-width (get-buffer-window "A"))
                            (window-total-width (get-buffer-window "B"))))
                    1))))))

(ert-deftest tiling/bsp-and-back-to-tall ()
  "Switching tall -> bsp -> tall: SPC w a lays them out each way, the main
pane the same."
  (+test-tiling-bsp
    (+test-tiling--bsp-open "B" "C")
    (select-window (get-buffer-window "B"))
    (+my/tiling-swap-main)
    (should (equal (+test-tiling--names (+my/tiling--panes)) '("B" "A" "C")))
    (let ((+my/tiling-strategy 'tall))
      (+my/tiling-arrange)
      (should (+my/tiling--tall-p (window-main-window)))
      (should (equal (+test-tiling--names (+my/tiling--panes)) '("B" "A" "C"))))))

(ert-deftest tiling/bsp-no-room-said ()
  "Too many panes for the spiral: SPC w a says so and changes nothing; a pane
too small to halve: SPC w SPC says so."
  (+test-tiling-bsp
    ;; Seven panes of one's own: four columns, the last two split in rows.
    (let ((window (selected-window)))
      (dotimes (_ 3) (split-window window nil 'right))
      (let ((right (car (last (+my/tiling--panes)))))
        (split-window right nil 'below)
        (split-window right nil 'below))
      (split-window (nth 2 (+my/tiling--panes)) nil 'below))
    (should (= (length (+my/tiling--panes)) 7))
    (let ((layout (+test-tiling--layout)))
      (should (equal (cadr (should-error (+my/tiling-arrange) :type 'user-error))
                     "No room for 7 panes"))
      (should (equal (+test-tiling--layout) layout)))
    (delete-other-windows)
    (let (error)
      (dotimes (_ 20)
        (unless error
          (condition-case err (+my/tiling-split) (user-error (setq error err)))))
      (should (equal (cadr error) "No room for another pane")))))

;; ====== KEYS ======

(ert-deftest tiling/keys ()
  (should (eq (lookup-key evil-window-map (kbd "SPC")) #'+my/tiling-split))
  (should (eq (lookup-key evil-window-map "a") #'+my/tiling-arrange))
  (should (eq (lookup-key evil-window-map (kbd "RET")) #'+my/tiling-swap-main))
  (should (eq (lookup-key evil-window-map "]") #'+my/tiling-main-bigger))
  (should (eq (lookup-key evil-window-map "[") #'+my/tiling-main-smaller))
  (should (eq (lookup-key evil-window-map "}") #'+my/tiling-pane-bigger))
  (should (eq (lookup-key evil-window-map "{") #'+my/tiling-pane-smaller))
  (should (eq (lookup-key evil-window-map "w") #'+my/tiling-next-pane))
  (should (eq (lookup-key evil-window-map "W") #'+my/tiling-previous-pane)))

;; ====== TILING FIRST ======

(define-derived-mode +test-tiling-app-mode special-mode "App"
  "Stands for an application (Claude Code, the terminal...).")

(define-derived-mode +test-tiling-sub-app-mode +test-tiling-app-mode "Sub-app")

(defun +test-tiling--app (name &optional mode)
  "Application buffer NAME (in MODE, default `+test-tiling-app-mode')."
  (with-current-buffer (get-buffer-create name)
    (funcall (or mode #'+test-tiling-app-mode))
    (current-buffer)))

(defun +test-tiling--file (name)
  "A buffer visiting file NAME (in a temp folder, not written)."
  (let ((file (expand-file-name name (make-temp-file (+test-tmp-file "tiling-") t))))
    (find-file-noselect file)))

(defmacro +test-tiling-first (&rest body)
  "BODY as `+test-tiling', the applications being `+test-tiling-app-mode''s."
  (declare (indent 0))
  `(+test-tiling
     (let ((+my/tiling-known-apps '((test +test-tiling-app-mode)))
           (+my/tiling-apps 'all))
       ,@body)))

(defconst +test-tiling--popup-action
  '((display-buffer-in-side-window) (side . bottom) (window-width . 40) (window-height . 0.25)
    (window-parameters (ttl . 0)))
  "As Doom's popup rules display: a side window of their size.")

(ert-deftest tiling/first-is-on ()
  (should (equal display-buffer-overriding-action '((+my/tiling--display))))
  (should (advice-member-p #'+my/tiling-kill-last-tab-a 'kill-current-buffer))
  ;; Applications are Doom's real buffers (their tabs kept, gone back to).
  (should (memq #'+my/tiling-app-p doom-real-buffer-functions))
  (should (memq #'+my/tiling-close-pane-h (default-value 'kill-buffer-hook)))
  ;; The applications, by name; all of them chosen.
  (should (equal (mapcar #'car +my/tiling-known-apps)
                 '(claude terminal preview drawings magit issues agent-ui html)))
  (should (eq (default-value '+my/tiling-apps) 'all))
  (let ((+my/tiling-apps 'all))
    (should (equal (mapcar (lambda (app) (if (consp app) (car app) app)) (+my/tiling--apps))
                   '(agent-shell-mode ghostel-mode +md-preview-page-mode +my/excalidraw-mode magit-mode
                     beads-list-mode beads-detail-mode beads-detail-vui-mode agent-ui-canvas-mode
                     agent-ui-form-mode +my/html-page-mode)))))

(ert-deftest tiling/apps-chosen-by-name ()
  "A list of names: those applications only, their modes as known (a
predicate kept); all: every one."
  (let ((+my/tiling-apps '(claude magit)))
    (should (equal (+my/tiling--apps) '(agent-shell-mode (magit-mode . +my/tiling-magit-new-pane-p)))))
  (let ((+my/tiling-apps '(issues)))
    (should (equal (mapcar (lambda (app) (if (consp app) (car app) app)) (+my/tiling--apps))
                   '(beads-list-mode beads-detail-mode beads-detail-vui-mode))))
  (let ((+my/tiling-apps nil))
    (should-not (+my/tiling--apps)))
  (let ((+my/tiling-apps 'all))
    (should (= (length (+my/tiling--apps)) 11)))
  ;; Not mended by them: the list known stays whole.
  (let ((+my/tiling-apps '(issues)))
    (setcar (+my/tiling--apps) 'changed)
    (should (eq (nth 1 (assq 'issues +my/tiling-known-apps)) 'beads-list-mode))))

(ert-deftest tiling/an-app-left-out-opens-as-without-tiling ()
  "An application not chosen opens as it asks (Doom's popup, the current
window...), and isn't one otherwise: not Doom's real buffer for it."
  (+test-tiling
    (let ((+my/tiling-known-apps '((test +test-tiling-app-mode) (other +test-tiling-sub-app-mode)))
          (+my/tiling-apps '(other))
          (app (+test-tiling--app "app")))
      (should-not (+my/tiling-app-p app))
      (should-not (+my/tiling--display app nil))
      (let ((window (display-buffer app '(display-buffer-same-window))))
        (should (eq window (selected-window)))
        (should (= (length (+my/tiling--panes)) 1)))
      ;; Chosen: in a new pane.
      (let ((+my/tiling-apps 'all))
        (should (+my/tiling-app-p app))))))

(ert-deftest tiling/apps-unknown-name-warns ()
  "A name tiling doesn't know (config.el's typo): a warning naming it and the
ones it knows; all, or known names: none."
  (let (warned)
    (cl-letf (((symbol-function 'display-warning) (lambda (type message &rest _) (push (list type message) warned))))
      (let ((+my/tiling-apps '(claude termnal)))
        (+my/tiling--check-apps))
      (should (equal (car warned)
                     '(tiling "+my/tiling-apps: no application termnal; it's all, or a list of: claude, terminal, preview, drawings, magit, issues, agent-ui, html")))
      (let ((+my/tiling-apps 'default))
        (+my/tiling--check-apps))
      (should (string-match-p "no application default;" (cadr (car warned))))
      (setq warned nil)
      (let ((+my/tiling-apps 'all)) (+my/tiling--check-apps))
      (let ((+my/tiling-apps '(claude magit))) (+my/tiling--check-apps))
      (should-not warned))))

(ert-deftest tiling/apps-in-customize ()
  "M-x customize-variable +my/tiling-apps: all, or the names ticked."
  (should (equal (get '+my/tiling-apps 'custom-type)
                 '(choice (const :tag "All of them" all)
                          (set :tag "These" (const claude) (const terminal) (const preview) (const drawings)
                               (const magit) (const issues) (const agent-ui) (const html)))))
  (should (custom-variable-p '+my/tiling-apps)))

(ert-deftest tiling/config-el-chooses-the-apps-before-loading ()
  "config.el chooses the applications (all) before it loads config/tiling.el."
  (let (forms)
    (with-temp-buffer
      (insert-file-contents (expand-file-name "config.el" +test-root))
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file)))
    (setq forms (nreverse forms))
    (let ((setq-at (seq-position forms '(setq +my/tiling-apps 'all)))
          (load-at (seq-position forms '(load! "config/tiling"))))
      (should setq-at)
      (should (< setq-at load-at)))))

(ert-deftest tiling/what-is-an-application ()
  (+test-tiling-first
    (should (+my/tiling-app-p (+test-tiling--app "app")))
    ;; Modes derived from one too.
    (should (+my/tiling-app-p (+test-tiling--app "sub" #'+test-tiling-sub-app-mode)))
    (should-not (+my/tiling-app-p (get-buffer "A")))
    ;; (MODE . PREDICATE): MODE's buffers an application's; a new pane when
    ;; PREDICATE says so, in the buffer.
    (let ((+my/tiling-known-apps '((test (+test-tiling-app-mode . (lambda () (string-prefix-p "yes" (buffer-name))))))))
      (should (+my/tiling-app-p (+test-tiling--app "yes-app")))
      (should (+my/tiling-app-p (+test-tiling--app "no-app")))
      (should (+my/tiling--new-pane-p (get-buffer "yes-app")))
      (should-not (+my/tiling--new-pane-p (get-buffer "no-app")))
      (should-not (+my/tiling--new-pane-p (get-buffer "A"))))))

(ert-deftest tiling/an-application-in-a-new-pane ()
  "Where the strategy puts it, not where its rules say, nor their size (a
popup 40 columns wide was the terminal's: narrow)."
  (+test-tiling-first
    (let* ((main (selected-window))
           (app (+test-tiling--app "app"))
           (window (display-buffer app +test-tiling--popup-action)))
      (should-not (window-parameter window 'window-side))
      (should-not (window-parameter window 'ttl))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "app")))
      ;; The tall strategy's half, not the rule's 40 columns.
      (should (<= (abs (- (window-total-width window) (window-total-width main))) 1))
      (should-not (window-prev-buffers window))
      ;; Shown already: its pane.
      (should (eq (display-buffer app +test-tiling--popup-action) window))
      (should (= (length (+my/tiling--panes)) 2))
      ;; Quitting it closes the pane.
      (quit-window nil window)
      (should-not (window-live-p window)))))

(ert-deftest tiling/here-commands-where-they-ask ()
  "From a command of `+my/tiling-here-commands' (Doom's SPC o T), an
application where it asks (the window you're in), what was there kept under
it, no new pane; from any other, in a new pane."
  (should (equal (default-value '+my/tiling-here-commands) '(+ghostel/here)))
  (+test-tiling-first
    (let ((here (selected-window)))
      (let ((this-command '+ghostel/here))
        (should (eq (display-buffer (+test-tiling--app "app") '(display-buffer-same-window)) here)))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("app")))
      (should (eq (car (car (window-prev-buffers here))) (get-buffer "A")))
      (let ((this-command '+ghostel/toggle))
        (should-not (eq (display-buffer (+test-tiling--app "app2") '(display-buffer-same-window)) here)))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("app" "app2"))))))

(ert-deftest tiling/anything-else-as-it-asks ()
  (+test-tiling-first
    (let ((window (display-buffer "B" +test-tiling--popup-action)))
      (should (eq (window-parameter window 'window-side) 'bottom))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A"))))))

(ert-deftest tiling/files-from-an-application-as-its-tab ()
  "A file shown from an application's pane (a link in Claude Code, asked for
this window or another): a tab there, the application still one."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (other (+test-tiling--file "b.txt"))
           (app (display-buffer (+test-tiling--app "app") nil)))
      (select-window app)
      (should (eq (display-buffer file '(display-buffer-same-window)) app))
      (should (eq (window-buffer app) file))
      (should (assq (get-buffer "app") (window-prev-buffers app)))
      ;; From the application again, asked for another window: still there.
      (switch-to-buffer "app")
      (should (eq (display-buffer other '(display-buffer-pop-up-window)) app))
      (should (= (length (+my/tiling--panes)) 2))
      (should (eq (window-buffer left) (get-buffer "A")))
      ;; Shown already in another pane: here too, the current pane's tab.
      (switch-to-buffer "app")
      (set-window-buffer left file)
      (should (eq (display-buffer file '(display-buffer-same-window)) app))
      (should (eq (window-buffer left) file)))))

(ert-deftest tiling/files-from-a-popup-in-the-last-pane-used ()
  "From a popup or a side panel (a link in *Help*): in the pane used last, an
application's too; from a dedicated pane (Doom's terminal), the same."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (app (display-buffer (+test-tiling--app "app") nil))
           (popup (display-buffer "C" +test-tiling--popup-action)))
      ;; The app's pane used last.
      (select-window left)
      (select-window app)
      (select-window popup)
      (should (eq (display-buffer file '((display-buffer-use-some-window))) app))
      ;; From a dedicated pane (Doom's terminal's): there too, as any.
      (set-window-buffer app (get-buffer "app"))
      (select-window left)
      (select-window app)
      (set-window-dedicated-p app t)
      (should (eq (display-buffer (+test-tiling--file "b.txt") '(display-buffer-same-window)) app))
      (should-not (window-dedicated-p app)))))

(ert-deftest tiling/files-in-the-current-pane-always ()
  "From a pane of files too, asked for another window (C-x 4 f, xref's other
window): the current pane, as a tab; no new pane, not another one."
  (+test-tiling-first
    (let ((file (+test-tiling--file "a.txt"))
          (here (selected-window)))
      (should (eq (display-buffer file '(display-buffer-same-window)) here))
      (should (= (length (+my/tiling--panes)) 1))
      (let* ((other (split-window))
             (shown (window-buffer other)))
        (should (eq (display-buffer (+test-tiling--file "b.txt") '(display-buffer-pop-up-window)) here))
        (should (eq (display-buffer (+test-tiling--file "c.txt") '(display-buffer-use-some-window)) here))
        (should (eq (window-buffer other) shown))
        (should (= (length (+my/tiling--panes)) 2)))
      ;; Shown in no window (asked so): none.
      (should-not (+my/tiling--display (+test-tiling--file "d.txt") '((allow-no-window . t)))))))

(ert-deftest tiling/files-switched-to-in-an-application-s-pane ()
  "find-file, SPC SPC (`switch-to-buffer') in an application's pane: the file
there, a tab; the application still one."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (app (display-buffer (+test-tiling--app "app") nil)))
      (select-window app)
      (switch-to-buffer file)
      (should (eq (selected-window) app))
      (should (eq (window-buffer app) file))
      (should (assq (get-buffer "app") (window-prev-buffers app)))
      (should (eq (window-buffer left) (get-buffer "A")))
      (should-not (advice-member-p 'tiling-switch-to-buffer-a 'switch-to-buffer)))))

(ert-deftest tiling/a-pane-closes-with-its-last-buffer ()
  "Killed (SPC b k, a terminal's shell ending): the pane it was the only
buffer of closes; one with others stays; the frame's last stays."
  (+test-tiling-first
    (let* ((app (+test-tiling--app "app"))
           (window (display-buffer app nil)))
      (kill-buffer app)
      (should-not (window-live-p window))
      (should (= (length (+my/tiling--panes)) 1)))
    ;; Another buffer shown there before: it stays, showing it.
    (let* ((app (+test-tiling--app "app2"))
           (window (display-buffer app nil)))
      (with-selected-window window
        (switch-to-buffer "B")
        (switch-to-buffer app))
      (kill-buffer app)
      (should (window-live-p window))
      (should (eq (window-buffer window) (get-buffer "B"))))
    ;; The frame's last pane: stays.
    (delete-other-windows)
    (let ((buffer (+test-buffer "last")))
      (switch-to-buffer buffer)
      (set-window-prev-buffers nil nil)
      (kill-buffer buffer)
      (should (= (length (+my/tiling--panes)) 1)))))

(defun +test-tiling--doom-kill-a (&rest _)
  "As Doom's `kill-current-buffer' advice (lisp/doom-emacs.el): another
buffer shown in the window first, then the buffer killed."
  (let ((buffer (current-buffer)))
    (switch-to-prev-buffer nil t)
    (kill-buffer buffer)
    t))

(ert-deftest tiling/spc-b-k-closes-a-pane-with-its-last-tab ()
  "SPC b k (`kill-current-buffer', Doom's advice on it) on a pane's last tab:
the buffer killed, the pane closed; with other tabs, Doom's (the previous
one shown); the frame's last pane stays."
  (+test-tiling-first
    (advice-add 'kill-current-buffer :before-until #'+test-tiling--doom-kill-a)
    (unwind-protect
        (progn
          (let* ((app (+test-tiling--app "app"))
                 (window (display-buffer app nil)))
            (select-window window)
            (kill-current-buffer)
            (should-not (buffer-live-p app))
            (should-not (window-live-p window))
            (should (= (length (+my/tiling--panes)) 1)))
          ;; Other tabs: Doom's, the pane stays.
          (let* ((app (+test-tiling--app "app2"))
                 (window (display-buffer app nil)))
            (select-window window)
            (switch-to-buffer "B")
            (switch-to-buffer app)
            (kill-current-buffer)
            (should-not (buffer-live-p app))
            (should (window-live-p window))
            (should (eq (window-buffer window) (get-buffer "B"))))
          ;; The frame's last pane: Doom's.
          (delete-other-windows)
          (let ((buffer (+test-buffer "last")))
            (switch-to-buffer buffer)
            (set-window-prev-buffers nil nil)
            (kill-current-buffer)
            (should (= (length (+my/tiling--panes)) 1))))
      (advice-remove 'kill-current-buffer #'+test-tiling--doom-kill-a))))

(ert-deftest tiling/the-minibuffer-open-as-asked ()
  "While the minibuffer is open (a preview, a completion's action): files and
applications shown as asked, switched to where asked."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (app (display-buffer (+test-tiling--app "app") nil)))
      (select-window app)
      (cl-letf (((symbol-function 'active-minibuffer-window) (lambda () (minibuffer-window))))
        ;; A file previewed in the window the minibuffer was entered from.
        (should (eq (display-buffer file '(display-buffer-same-window)) app))
        (set-window-buffer app (get-buffer "app"))
        (switch-to-buffer file)
        (should (eq (selected-window) app))
        (should (eq (window-buffer app) file))
        (set-window-buffer app (get-buffer "app"))
        ;; An application where it asks (a side window).
        (let ((other (display-buffer (+test-tiling--app "app2") +test-tiling--popup-action)))
          (should (eq (window-parameter other 'window-side) 'bottom))))
      (should (eq (window-buffer left) (get-buffer "A"))))))

(ert-deftest tiling/switching-without-recording-where-asked ()
  "`switch-to-buffer' with NORECORD (previews): in the application's pane, as
asked."
  (+test-tiling-first
    (let* ((file (+test-tiling--file "a.txt"))
           (app (display-buffer (+test-tiling--app "app") nil)))
      (select-window app)
      (switch-to-buffer file t)
      (should (eq (selected-window) app))
      (should (eq (window-buffer app) file)))))

(ert-deftest tiling/completions-at-the-bottom-as-asked ()
  "*Completions* (not a file, not an application): at the frame's bottom, as
Emacs puts it, from an application's pane too."
  (+test-tiling-first
    (let* ((app (display-buffer (+test-tiling--app "app") nil))
           (completions (with-current-buffer (get-buffer-create "*Completions*")
                          (completion-list-mode)
                          (current-buffer))))
      (select-window app)
      (let ((window (display-buffer completions '((display-buffer-at-bottom)))))
        (should (window-at-side-p window 'bottom))
        (should (= (window-total-width window) (frame-width)))
        (should (eq (window-buffer app) (get-buffer "app")))))))

;; ====== MAGIT ======

(defun +test-tiling--magit (name mode)
  "A buffer standing for magit's buffer NAME in MODE (its mode only)."
  (with-current-buffer (get-buffer-create name)
    (setq-local major-mode mode)
    (current-buffer)))

(defmacro +test-tiling-magit (&rest body)
  "BODY as `+test-tiling', the applications this config's."
  (declare (indent 0))
  `(+test-tiling
     (let ((+my/tiling-apps 'all)
           (+my/tiling-known-apps (default-value '+my/tiling-known-apps)))
       ,@body)))

(ert-deftest tiling/magit-status-in-a-new-pane ()
  "SPC g g from a file: magit's status in a new pane (Doom: the current
window); shown, its pane."
  (+test-tiling-magit
    (let* ((main (selected-window))
           (status (+test-tiling--magit "magit: test" 'magit-status-mode))
           (window (display-buffer status '(display-buffer-same-window))))
      (should-not (eq window main))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A" "magit: test")))
      (select-window main)
      (should (eq (display-buffer status '(display-buffer-same-window)) window)))))

(ert-deftest tiling/magit-from-outside-in-a-new-pane ()
  "A log, a file's diff (SPC g d) from a file: a new pane."
  (+test-tiling-magit
    (dolist (case '(("magit-log: test" . magit-log-mode) ("magit-diff: test" . magit-diff-mode)))
      (delete-other-windows)
      (switch-to-buffer "A")
      (let* ((from (selected-window))
             (window (display-buffer (+test-tiling--magit (car case) (cdr case)) '(display-buffer-same-window))))
        (should-not (eq window from))
        (should (equal (mapcar #'car (+test-tiling--layout)) (list "A" (car case))))))))

(ert-deftest tiling/magit-inside-its-pane-as-magit-has-it ()
  "From the status pane: a log, a diff in that pane (as magit and Doom have
them); a commit, a stash in a new pane; the process log as Doom has it
(below)."
  (+test-tiling-magit
    (let* ((status-window (display-buffer (+test-tiling--magit "magit: test" 'magit-status-mode) nil)))
      (select-window status-window)
      (let ((log (display-buffer (+test-tiling--magit "magit-log: test" 'magit-log-mode)
                                 '(display-buffer-same-window))))
        (should (eq log status-window)))
      (let ((diff (display-buffer (+test-tiling--magit "magit-diff: test" 'magit-diff-mode)
                                  '(display-buffer-same-window))))
        (should (eq diff status-window)))
      (let ((revision (display-buffer (+test-tiling--magit "magit-revision: test" 'magit-revision-mode)
                                      '(display-buffer-same-window))))
        (should-not (eq revision status-window))
        (should (= (length (+my/tiling--panes)) 3)))
      (select-window status-window)
      (let ((process (display-buffer (+test-tiling--magit "magit-process: test" 'magit-process-mode)
                                     '(display-buffer-below-selected))))
        (should (eq (window-in-direction 'below status-window) process))))))

(ert-deftest tiling/magit-s-panes-get-file-tabs ()
  "RET on a file in magit (or SPC SPC there): the file in magit's pane, a tab."
  (+test-tiling-magit
    (let* ((left (selected-window))
           (file (+test-tiling--file "f.txt"))
           (status (+test-tiling--magit "magit: test" 'magit-status-mode))
           (status-window (display-buffer status nil)))
      (select-window status-window)
      (should (eq (display-buffer file '(display-buffer-same-window)) status-window))
      (should (assq status (window-prev-buffers status-window)))
      (switch-to-buffer (+test-tiling--file "g.txt"))
      (should (eq (selected-window) status-window))
      (should (eq (window-buffer left) (get-buffer "A"))))))

(ert-deftest tiling/git-s-own-files-where-git-opens-them ()
  "A file in .git/ (git's: a commit message, the rebase todo), one edited for
git (with-editor, git-commit-mode): in magit's pane, as git opens them."
  (+test-tiling-magit
    (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "repo-") t)))
           ;; Not COMMIT_EDITMSG itself: git-commit-mode would hold it (only
           ;; a commit closes it).
           (git-file (progn (make-directory (expand-file-name ".git" dir) t)
                            (find-file-noselect (expand-file-name ".git/description" dir))))
           (status-window (display-buffer (+test-tiling--magit "magit: test" 'magit-status-mode) nil)))
      (should-not (+my/tiling--file-p git-file))
      (select-window status-window)
      (switch-to-buffer git-file)
      (should (eq (selected-window) status-window))
      (should (eq (window-buffer status-window) git-file))
      (dolist (mode '(with-editor-mode git-commit-mode))
        (with-current-buffer (+test-tiling--file "msg.txt")
          (set (make-local-variable mode) t)
          (should-not (+my/tiling--file-p (current-buffer)))
          (set (make-local-variable mode) nil))))))
