;;; tests/unit/test-childframe.el -*- lexical-binding: t; -*-
;; config/childframe.el: child frames laid over a window (the notices, the
;; error stripe, WebKit's cover): a frame's parameters and buffer, deleting it,
;; a frame per window synced with the windows, syncing soon. Batch Emacs can't
;; make frames: they're stood in for here (config/banner.el's and
;; config/stripe.el's tests use them through their own).

(+test-load "config/childframe")

(defvar +test-childframe--frames nil "A feature's (WINDOW FRAME) list.")

(defvar +test-childframe--timer nil)

;; ====== A FRAME ======

(defun +test-childframe--make (parameters)
  "`+my/childframe-make' with PARAMETERS: (FRAME MADE-WITH HOOKS WINDOW), the
frame made (a stand-in) on a window of this frame, the parameters given to
`make-frame' and the hooks then."
  (let* ((window (split-window nil nil 'below))
         (got nil)
         (frame nil))
    (cl-letf (((symbol-function 'make-frame)
               (lambda (made-with)
                 (setq got (list made-with after-make-frame-functions before-make-frame-hook))
                 'child))
              ((symbol-function 'frame-root-window)
               (let ((orig (symbol-function 'frame-root-window)))
                 (lambda (&optional f) (if (eq f 'child) window (funcall orig f))))))
      (setq frame (+my/childframe-make (selected-frame) "test-child" parameters)))
    (list frame (nth 0 got) (cdr got) window)))

(ert-deftest childframe/a-frame-inside-its-parent-without-borders-or-focus ()
  "Inside the parent, without borders, taking no focus, hidden until laid out;
other code isn't told about it."
  (+test-with-reset
    (pcase-let* ((parent (selected-frame))
                 (`(,frame ,parameters ,hooks ,window) (+test-childframe--make nil)))
      (should (eq frame 'child))
      (should (eq (alist-get 'parent-frame parameters) parent))
      (should (eq (alist-get 'minibuffer parameters) (minibuffer-window parent)))
      (dolist (p '(no-accept-focus no-focus-on-map undecorated unsplittable no-other-frame
                   no-special-glyphs desktop-dont-save))
        (should (eq (alist-get p parameters) t)))
      (dolist (p '(border-width internal-border-width child-frame-border-width
                   left-fringe right-fringe menu-bar-lines tool-bar-lines tab-bar-lines
                   line-spacing min-width min-height))
        (should (eql (alist-get p parameters) 0)))
      (should (assq 'visibility parameters))
      (should-not (alist-get 'visibility parameters))
      (should (equal hooks '(nil nil)))
      (kill-buffer (window-buffer window)))))

(ert-deftest childframe/its-buffer-nothing-but-text ()
  "Its window shows a read-only buffer of its own, \" *NAME*\", without any
lines of its own (mode line, header line, tab line) or cursor."
  (+test-with-reset
    (pcase-let* ((`(,_ ,_ ,_ ,window) (+test-childframe--make nil))
                 (buffer (window-buffer window)))
      (unwind-protect
          (progn
            (should (string-prefix-p " *test-child*" (buffer-name buffer)))
            (should (window-dedicated-p window))
            (dolist (p '(mode-line-format header-line-format tab-line-format))
              (should (eq (window-parameter window p) 'none)))
            (with-current-buffer buffer
              (should buffer-read-only)
              (should-not mode-line-format)
              (should-not header-line-format)
              (should-not tab-line-format)
              (should-not cursor-type)
              (should-not display-line-numbers)
              (should truncate-lines)))
        (set-window-dedicated-p window nil)
        (kill-buffer buffer)))))

(ert-deftest childframe/parameters-given-replace-or-add ()
  "A feature's parameters replace the defaults (each parameter once) or are
added to them."
  (+test-with-reset
    (pcase-let ((`(,_ ,parameters ,_ ,window)
                 (+test-childframe--make '((width . 10) (title . "test") (+test-mine . t)))))
      (should (eql (alist-get 'width parameters) 10))
      (should (= (cl-count 'width parameters :key #'car) 1))
      (should (eql (alist-get 'height parameters) 1))
      (should (equal (alist-get 'title parameters) "test"))
      (should (eq (alist-get '+test-mine parameters) t))
      (should (equal (mapcar #'car parameters) (delete-dups (mapcar #'car parameters))))
      (kill-buffer (window-buffer window)))))

(ert-deftest childframe/delete-frame-and-buffer ()
  "Its buffer goes with it; a frame deleted already: nothing."
  (let* ((buffer (generate-new-buffer " *test-child*"))
         (live t)
         (deleted 0)
         (orig (mapcar (lambda (f) (cons f (symbol-function f)))
                       '(frame-live-p frame-root-window window-buffer delete-frame))))
    (cl-flet ((orig (f &rest args) (apply (alist-get f orig) args)))
      (cl-letf (((symbol-function 'frame-live-p)
                 (lambda (f) (if (eq f 'child) live (orig 'frame-live-p f))))
                ((symbol-function 'frame-root-window)
                 (lambda (&optional f) (if (eq f 'child) 'child-root (orig 'frame-root-window f))))
                ((symbol-function 'window-buffer)
                 (lambda (&optional w) (if (eq w 'child-root) buffer (orig 'window-buffer w))))
                ((symbol-function 'delete-frame)
                 (lambda (&optional f force)
                   (if (not (eq f 'child))
                       (orig 'delete-frame f force)
                     (should force)
                     (setq live nil)
                     (cl-incf deleted)))))
        (+my/childframe-delete 'child)
        (should (= deleted 1))
        (should-not (buffer-live-p buffer))
        (+my/childframe-delete 'child)
        (should (= deleted 1))))))

;; ====== ON THE SCREEN ======

(ert-deftest childframe/on-the-screen-only-if-visible-says-t ()
  "On the screen only if `frame-visible-p' says t: `icon' (X: hidden right
after it was shown) is off it, and showing it again shows it."
  (let ((visible nil)
        (made-visible nil))
    (cl-letf (((symbol-function 'frame-visible-p) (lambda (f) (and (eq f 'child) visible)))
              ((symbol-function 'make-frame-visible)
               (lambda (&optional f) (push f made-visible) (setq visible t))))
      (dolist (state '(nil icon))
        (setq visible state
              made-visible nil)
        (should-not (+my/childframe-shown-p 'child))
        (+my/childframe-show 'child)
        (should (equal made-visible '(child)))
        (should (+my/childframe-shown-p 'child)))
      (setq made-visible nil)
      (+my/childframe-show 'child)
      (should-not made-visible))))

;; ====== A FRAME PER WINDOW ======

(ert-deftest childframe/windows-wanting-one ()
  "The windows wanting a frame, in visible graphical frames only, not in
child frames."
  (+test-with-reset
    (let* ((main (selected-window))
           (other (split-window nil nil 'right)))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
        (should (equal (+my/childframe-windows (lambda (w) (eq w other))) (list other)))
        (should (equal (sort (+my/childframe-windows #'always) :key #'window-left-column)
                       (list main other)))
        (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) 'parent)))
          (should-not (+my/childframe-windows #'always)))
        (cl-letf (((symbol-function 'frame-visible-p) (lambda (_) nil)))
          (should-not (+my/childframe-windows #'always))))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
        (should-not (+my/childframe-windows #'always))))))

(ert-deftest childframe/sync ()
  "Windows wanting a frame get theirs laid out; the frames of the others are
hidden, those of closed windows deleted, dead ones forgotten. An error in one
window is a message: the others still get theirs."
  (+test-with-reset
    (let* ((wanted (selected-window))
           (unwanted (split-window nil nil 'right))
           (failing (split-window nil nil 'below))
           (closed (split-window unwanted nil 'below))
           (dead-frame (split-window failing nil 'right))
           (live '(f-wanted f-unwanted f-closed))
           (hidden nil)
           (deleted nil)
           (shown nil)
           (+test-childframe--frames (list (list wanted 'f-wanted)
                                           (list unwanted 'f-unwanted)
                                           (list closed 'f-closed)
                                           (list dead-frame 'f-dead)))
           (frame-live (symbol-function 'frame-live-p))
           (invisible (symbol-function 'make-frame-invisible)))
      (delete-window closed)
      (+test-clear-messages)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                ((symbol-function 'frame-live-p)
                 (lambda (f) (if (symbolp f) (memq f live) (funcall frame-live f))))
                ((symbol-function 'make-frame-invisible)
                 (lambda (&optional f force)
                   (if (symbolp f) (push f hidden) (funcall invisible f force))))
                ((symbol-function '+my/childframe-delete) (lambda (f) (push f deleted))))
        (+my/childframe-sync '+test-childframe--frames
                             (lambda (w) (memq w (list wanted failing dead-frame)))
                             (lambda (w)
                               (if (eq w failing) (error "Boom") (push w shown)))
                             "Test"))
      (should (equal +test-childframe--frames (list (list wanted 'f-wanted)
                                                    (list unwanted 'f-unwanted))))
      (should (equal hidden '(f-unwanted)))
      (should (equal deleted '(f-closed)))
      (should (equal (sort shown :key #'window-left-column) (list wanted dead-frame)))
      (should (= (+test-messages "^Test: Boom$") 1)))))

(ert-deftest childframe/soon-once ()
  "After this redisplay, once however often asked; and again later."
  (let ((calls 0)
        (+test-childframe--timer nil))
    (+my/childframe-soon '+test-childframe--timer (lambda () (cl-incf calls)))
    (let ((timer +test-childframe--timer))
      (should (timerp timer))
      (+my/childframe-soon '+test-childframe--timer (lambda () (cl-incf calls)))
      (should (eq +test-childframe--timer timer)))
    (should (+test-wait-for (lambda () (null +test-childframe--timer)) 2))
    (should (= calls 1))
    (+my/childframe-soon '+test-childframe--timer (lambda () (cl-incf calls)))
    (should (+test-wait-for (lambda () (null +test-childframe--timer)) 2))
    (should (= calls 2))))
