;;; tests/unit/test-tiling.el -*- lexical-binding: t; -*-
;; config/tiling.el: SPC w SPC opens a pane where the tiling strategy puts it
;; (tall), SPC w a arranges the panes.

(+test-load "config/window" "config/tiling")

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

;; ====== KEYS ======

(ert-deftest tiling/keys ()
  (should (eq (lookup-key evil-window-map (kbd "SPC")) #'+my/tiling-split))
  (should (eq (lookup-key evil-window-map "a") #'+my/tiling-arrange)))
