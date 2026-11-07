;;; tests/e2e/test-banner.el -*- lexical-binding: t; -*-
;; config/banner.el in a GUI Emacs: notices laid over a window's header line by
;; real child frames, under the tabs; splits, other buffers, closing, resizing,
;; clicks on their actions.

(+test-load "config/window" "config/editor" "config/childframe" "config/banner")

;; ====== HELPERS ======

(defun +test-banner--frame (window)
  "WINDOW's notices frame, if it has one."
  (nth 1 (assq window +my/banner--frames)))

(defun +test-banner--shown (window)
  "WINDOW's notices frame, once on screen."
  (+test-wait-for (lambda ()
                    (let ((frame (+test-banner--frame window)))
                      (and (frame-live-p frame) (frame-visible-p frame) frame)))
                  5))

(defun +test-banner--text (frame)
  (with-current-buffer (window-buffer (frame-root-window frame))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-banner--over-p (frame window rows)
  "Non-nil if FRAME covers WINDOW's top ROWS notice rows, under its tab line."
  (let* ((edges (window-pixel-edges window))
         (position (frame-position frame)))
    (and (= (car position) (nth 0 edges))
         (= (cdr position) (+ (nth 1 edges) (window-tab-line-height window)))
         (= (frame-pixel-width frame)
            (- (window-pixel-width window)
               (window-right-divider-width window)
               (window-scroll-bar-width window)))
         (= (frame-pixel-height frame) (* rows (+my/banner--row-height window))))))

(defun +test-banner--file (name)
  "A file buffer NAME in the selected window."
  (find-file (+test-file (concat "banner/" name) "Some text.\n"))
  (current-buffer))

(defvar +test-banner--ran nil
  "(BUFFER WINDOW FRAME) where the last action ran.")

(defun +test-banner--action ()
  (setq +test-banner--ran (list (current-buffer) (selected-window) (selected-frame))))

(defun +test-banner--click (frame label)
  "Click LABEL on FRAME's rows, as a mouse click does: FRAME selected, its
mouse-1 command run."
  (let* ((window (frame-root-window frame))
         (command (with-current-buffer (window-buffer window)
                    (goto-char (point-min))
                    (search-forward label)
                    (lookup-key (get-text-property (match-beginning 0) 'keymap) [mouse-1]))))
    (select-frame frame)
    (call-interactively command)))

(defmacro +test-banner (&rest body)
  "BODY from one window, the notices closed and their frames gone after."
  (declare (indent 0))
  `(+test-with-reset
     (setq +test-banner--ran nil)
     (unwind-protect (progn ,@body)
       (dolist (buffer (buffer-list))
         (with-current-buffer buffer
           (while +my/banner--list (+my/banner-close))))
       (+test-sleep 0.2))))

;; ====== SHOWING ======

(ert-deftest e2e-banner/a-notice-lies-over-the-header-line ()
  (+test-banner
    (+test-banner--file "a.txt")
    (+my/banner-show 'hello "Hello from a notice" :actions '(("Do it" . +test-banner--action)))
    (let* ((window (selected-window))
           (frame (+test-banner--shown window)))
      (should frame)
      (should (eq (frame-parent frame) (selected-frame)))
      (should (string-match-p "Hello from a notice" (+test-banner--text frame)))
      (should (string-match-p "Do it" (+test-banner--text frame)))
      (should (+test-wait-for (lambda () (+test-banner--over-p frame window 1)) 3))
      ;; The header line made room: a row per notice, its own under them.
      (should (+my/banner--ours-p))
      ;; The keyboard stays with the window.
      (should (eq (selected-frame) (frame-parent frame))))))

(ert-deftest e2e-banner/under-the-tabs ()
  (+test-banner
    (global-tab-line-mode 1)
    (unwind-protect
        (progn
          (+test-banner--file "tabs.txt")
          (should (> (window-tab-line-height) 0))
          (+my/banner-show 'hello "Under the tabs")
          (let ((frame (+test-banner--shown (selected-window))))
            (should (+test-wait-for (lambda () (+test-banner--over-p frame (selected-window) 1)) 3))))
      (global-tab-line-mode -1))))

(ert-deftest e2e-banner/two-notices-two-rows ()
  (+test-banner
    (+test-banner--file "two.txt")
    (+my/banner-show 'first "First notice")
    (+my/banner-show 'second "Second notice" :type 'warning)
    (let ((frame (+test-banner--shown (selected-window))))
      (should (+test-wait-for (lambda () (+test-banner--over-p frame (selected-window) 2)) 3))
      (should (string-match-p "First notice.*\n.*Second notice" (+test-banner--text frame)))
      ;; Closing the first: one row, the second.
      (+my/banner-close 'first)
      (should (+test-wait-for (lambda () (+test-banner--over-p frame (selected-window) 1)) 3))
      (should-not (string-match-p "First notice" (+test-banner--text frame))))))

(ert-deftest e2e-banner/closing-the-last-hides-the-frame ()
  (+test-banner
    (+test-banner--file "close.txt")
    (setq-local header-line-format "the file's own header")
    (+my/banner-show 'hello "Closing soon")
    (let ((frame (+test-banner--shown (selected-window))))
      (+my/banner-close)
      (should (+test-wait-for (lambda () (not (frame-visible-p frame))) 3))
      ;; Kept for the window's next notices; the header line as it was.
      (should (frame-live-p frame))
      (should (equal header-line-format "the file's own header"))
      (+my/banner-show 'again "Back again")
      (should (eq (+test-banner--shown (selected-window)) frame)))))

;; ====== WINDOWS ======

(ert-deftest e2e-banner/each-window-of-the-buffer-has-its-own ()
  (+test-banner
    (+test-banner--file "split.txt")
    (+my/banner-show 'hello "In both windows")
    (let* ((left (selected-window))
           (right (split-window-right))
           (a (+test-banner--shown left))
           (b (+test-banner--shown right)))
      (should a)
      (should b)
      (should-not (eq a b))
      (should (+test-wait-for (lambda () (and (+test-banner--over-p a left 1)
                                              (+test-banner--over-p b right 1)))
                              3)))))

(ert-deftest e2e-banner/another-buffer-in-the-window-hides-them ()
  (+test-banner
    (let ((buffer (+test-banner--file "away.txt")))
      (+my/banner-show 'hello "Only for away.txt")
      (let ((frame (+test-banner--shown (selected-window))))
        (switch-to-buffer "*scratch*")
        (should (+test-wait-for (lambda () (not (frame-visible-p frame))) 3))
        (switch-to-buffer buffer)
        (should (eq (+test-banner--shown (selected-window)) frame))))))

(ert-deftest e2e-banner/a-closed-window-s-frame-goes ()
  (+test-banner
    (+test-banner--file "gone.txt")
    (+my/banner-show 'hello "Window closing")
    (let* ((right (split-window-right))
           (frame (+test-banner--shown right)))
      (should frame)
      (delete-window right)
      (should (+test-wait-for (lambda () (not (frame-live-p frame))) 3))
      (should-not (assq right +my/banner--frames)))))

(ert-deftest e2e-banner/follows-the-window-s-size ()
  (+test-banner
    (+test-banner--file "size.txt")
    (+my/banner-show 'hello "Resizing")
    (let* ((left (selected-window))
           (right (split-window-right))
           (frame (+test-banner--shown left)))
      (should (+test-wait-for (lambda () (+test-banner--over-p frame left 1)) 3))
      (delete-window right)
      (should (+test-wait-for (lambda () (+test-banner--over-p frame left 1)) 3))
      (should (> (frame-pixel-width frame) 600)))))

(ert-deftest e2e-banner/a-new-major-mode-drops-them ()
  (+test-banner
    (+test-banner--file "mode.txt")
    (+my/banner-show 'hello "Until the mode changes")
    (let ((frame (+test-banner--shown (selected-window))))
      (emacs-lisp-mode)
      (should-not +my/banner--list)
      (should (+test-wait-for (lambda () (not (frame-visible-p frame))) 3)))))

;; ====== CLICKS ======

(ert-deftest e2e-banner/an-action-runs-in-the-window-it-s-about ()
  (+test-banner
    (let ((buffer (+test-banner--file "action.txt")))
      (+my/banner-show 'hello "Click the action" :actions '(("Do it" . +test-banner--action)))
      (let* ((left (selected-window))
             (right (split-window-right))
             (frame (+test-banner--shown right)))
        (select-window left)
        (+test-banner--click frame "Do it")
        ;; In the buffer, the clicked notice's window selected, the keyboard
        ;; back with the main frame.
        (should (equal +test-banner--ran (list buffer right (frame-parent frame))))
        (should (eq (selected-frame) (frame-parent frame)))))))

(ert-deftest e2e-banner/x-closes-its-notice ()
  (+test-banner
    (+test-banner--file "x.txt")
    (+my/banner-show 'first "First, to close")
    (+my/banner-show 'second "Second stays")
    (let ((frame (+test-banner--shown (selected-window))))
      (should (+test-wait-for (lambda () (+test-banner--over-p frame (selected-window) 2)) 3))
      (+test-banner--click frame "✕")
      (should (equal (mapcar #'car +my/banner--list) '(second)))
      (should (+test-wait-for (lambda () (+test-banner--over-p frame (selected-window) 1)) 3)))))
