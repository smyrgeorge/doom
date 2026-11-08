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

;; ====== KEYS ======

(ert-deftest tiling/keys ()
  (should (eq (lookup-key evil-window-map (kbd "SPC")) #'+my/tiling-split))
  (should (eq (lookup-key evil-window-map "a") #'+my/tiling-arrange))
  (should (eq (lookup-key evil-window-map (kbd "RET")) #'+my/tiling-swap-main))
  (should (eq (lookup-key evil-window-map "]") #'+my/tiling-main-bigger))
  (should (eq (lookup-key evil-window-map "[") #'+my/tiling-main-smaller)))

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
     (let ((+my/tiling-apps '(+test-tiling-app-mode)))
       ,@body)))

(defconst +test-tiling--popup-action
  '((display-buffer-in-side-window) (side . bottom) (window-width . 40) (window-height . 0.25)
    (window-parameters (ttl . 0)))
  "As Doom's popup rules display: a side window of their size.")

(ert-deftest tiling/first-is-on ()
  (should (equal display-buffer-overriding-action '((+my/tiling--display))))
  (should (advice-member-p #'+my/tiling-switch-to-buffer-a 'switch-to-buffer))
  (should (memq #'+my/tiling-close-pane-h (default-value 'kill-buffer-hook)))
  ;; The applications.
  (should (equal (mapcar (lambda (app) (if (consp app) (car app) app)) +my/tiling-apps)
                 '(agent-shell-mode ghostel-mode +md-preview-page-mode +my/excalidraw-mode magit-mode
                   beads-list-mode beads-detail-mode beads-detail-vui-mode))))

(ert-deftest tiling/what-is-an-application ()
  (+test-tiling-first
    (should (+my/tiling-app-p (+test-tiling--app "app")))
    ;; Modes derived from one too.
    (should (+my/tiling-app-p (+test-tiling--app "sub" #'+test-tiling-sub-app-mode)))
    (should-not (+my/tiling-app-p (get-buffer "A")))
    ;; (MODE . PREDICATE): MODE's buffers an application's; a new pane when
    ;; PREDICATE says so, in the buffer.
    (let ((+my/tiling-apps '((+test-tiling-app-mode . (lambda () (string-prefix-p "yes" (buffer-name)))))))
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

(ert-deftest tiling/anything-else-as-it-asks ()
  (+test-tiling-first
    (let ((window (display-buffer "B" +test-tiling--popup-action)))
      (should (eq (window-parameter window 'window-side) 'bottom))
      (should (equal (mapcar #'car (+test-tiling--layout)) '("A"))))))

(ert-deftest tiling/files-from-an-application-in-the-last-pane-of-files ()
  "A file shown from an application's pane: as a tab in the last selected
pane of files, the one already showing it first; none: a new pane."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (other (+test-tiling--file "b.txt"))
           (app (display-buffer (+test-tiling--app "app") nil)))
      (set-window-buffer left other)
      (select-window app)
      ;; Asked for the same window (a link in Claude Code): not the app's.
      (let ((window (display-buffer file '(display-buffer-same-window))))
        (should (eq window left))
        (should (eq (window-buffer app) (get-buffer "app")))
        ;; A tab: b.txt is still one.
        (should (assq other (window-prev-buffers left))))
      ;; Shown already in a pane of files: that one.
      (let ((right-of-app (progn (select-window left) (+my/tiling-split))))
        (set-window-buffer right-of-app other)
        (select-window app)
        (should (eq (display-buffer other '(display-buffer-same-window)) right-of-app)))
      ;; No pane of files: a new one.
      (delete-other-windows app)
      (should (equal (mapcar #'car (+test-tiling--layout)) '("app")))
      (let ((window (display-buffer file '(display-buffer-same-window))))
        (should-not (eq window app))
        (should (equal (mapcar #'car (+test-tiling--layout)) '("app" "a.txt")))))))

(ert-deftest tiling/files-from-a-popup-in-the-last-pane-of-files ()
  "From a popup or a side panel (a link in *Help*), not in an application's
pane."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (app (display-buffer (+test-tiling--app "app") nil))
           (popup (display-buffer "C" +test-tiling--popup-action)))
      ;; The app's pane used last.
      (select-window app)
      (select-window popup)
      (should (eq (display-buffer file '((display-buffer-use-some-window))) left)))))

(ert-deftest tiling/files-from-a-pane-of-files-as-asked ()
  (+test-tiling-first
    (let ((file (+test-tiling--file "a.txt")))
      (should (eq (display-buffer file '(display-buffer-same-window)) (selected-window)))
      (should (= (length (+my/tiling--panes)) 1)))))

(ert-deftest tiling/files-switched-to-in-an-application-s-pane ()
  "find-file, the sidebar (`switch-to-buffer') in an application's pane: the
file in the last pane of files, selected; elsewhere, in the pane."
  (+test-tiling-first
    (let* ((left (selected-window))
           (file (+test-tiling--file "a.txt"))
           (app (display-buffer (+test-tiling--app "app") nil)))
      (select-window app)
      (switch-to-buffer file)
      (should (eq (selected-window) left))
      (should (eq (window-buffer left) file))
      (should (eq (window-buffer app) (get-buffer "app")))
      ;; Not a file: in the app's pane, as asked.
      (select-window app)
      (switch-to-buffer "B")
      (should (eq (window-buffer app) (get-buffer "B")))
      ;; In a pane of files: there.
      (select-window left)
      (switch-to-buffer (+test-tiling--file "b.txt"))
      (should (eq (selected-window) left)))))

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
     (let ((+my/tiling-apps (default-value '+my/tiling-apps)))
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

(ert-deftest tiling/magit-s-panes-get-no-file-tabs ()
  "RET on a file in magit (or SPC SPC there): the file in the pane of files."
  (+test-tiling-magit
    (let* ((left (selected-window))
           (file (+test-tiling--file "f.txt"))
           (status-window (display-buffer (+test-tiling--magit "magit: test" 'magit-status-mode) nil)))
      (select-window status-window)
      (should (eq (display-buffer file '(display-buffer-same-window)) left))
      (select-window status-window)
      (switch-to-buffer (+test-tiling--file "g.txt"))
      (should (eq (selected-window) left)))))

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
