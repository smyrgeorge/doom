;;; tests/e2e/test-banner.el -*- lexical-binding: t; -*-
;; config/banner.el in a GUI Emacs: notices laid over a window's header line by
;; real child frames, under the tabs; splits, other buffers, closing, resizing,
;; narrow windows, clicks on their actions.

(+test-load "config/window" "config/editor" "config/childframe" "config/banner" "config/html")

;; ====== HELPERS ======

(defun +test-banner--frame (window)
  "WINDOW's notices frame, if it has one."
  (nth 1 (assq window +my/banner--frames)))

(defun +test-banner--shown (window)
  "WINDOW's notices frame, once on screen."
  (+test-wait-for (lambda ()
                    (let ((frame (+test-banner--frame window)))
                      (and (frame-live-p frame) (+my/childframe-shown-p frame) frame)))
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
      (should (+test-wait-for (lambda () (not (+my/childframe-shown-p frame))) 3))
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
        (should (+test-wait-for (lambda () (not (+my/childframe-shown-p frame))) 3))
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
      (should (+test-wait-for (lambda () (not (+my/childframe-shown-p frame))) 3)))))

(defun +test-banner--orphans ()
  "The notices' buffers shown in no live frame."
  (seq-filter (lambda (buffer)
                (and (string-prefix-p " *+my/banner*" (buffer-name buffer))
                     (not (get-buffer-window buffer t))))
              (buffer-list)))

(ert-deftest e2e-banner/a-frame-closed-takes-its-notices-buffers ()
  "Another frame with notices in two windows, closed (Emacs deletes the
notices' frames with it): their buffers go too."
  (+test-banner
    (let* ((buffer (+test-banner--file "frames.txt"))
           (frame (make-frame `((left . ,(car (frame-position)))
                                (top . ,(cdr (frame-position)))
                                (width . 80) (height . 20)
                                (z-group . above)))))
      (unwind-protect
          (progn
            (+my/banner-show 'hello "In another frame")
            (let* ((one (frame-first-window frame))
                   (two (with-selected-frame frame (split-window one nil 'below))))
              (set-window-buffer one buffer)
              (set-window-buffer two buffer)
              (should (+test-banner--shown one))
              (should (+test-banner--shown two))
              (let ((buffers (mapcar (lambda (w) (window-buffer (frame-root-window (+test-banner--frame w))))
                                     (list one two))))
                (delete-frame frame t)
                (+test-sleep 0.3)
                (should-not (seq-some #'buffer-live-p buffers))
                (should-not (+test-banner--orphans)))))
        (when (frame-live-p frame) (delete-frame frame t))))))

(ert-deftest e2e-banner/a-notices-frame-deleted-directly ()
  "A notices' frame deleted by other code: its buffer goes, and the next
window change makes the window a new one."
  (+test-banner
    (+test-banner--file "deleted.txt")
    (+my/banner-show 'hello "Deleted under it")
    (let* ((window (selected-window))
           (frame (+test-banner--shown window))
           (buffer (window-buffer (frame-root-window frame))))
      (delete-frame frame t)
      (should-not (buffer-live-p buffer))
      (split-window-right)
      (let ((new (+test-wait-for (lambda ()
                                   (let ((new (+test-banner--frame window)))
                                     (and (frame-live-p new) (+my/childframe-shown-p new) new)))
                                 3)))
        (should new)
        (should-not (eq new frame)))
      (should-not (+test-banner--orphans)))))

;; ====== NARROW WINDOWS ======

(defconst +test-banner--narrow
  '((drawing "Drawing for Claude: C-c C-c inserts it into the prompt, C-c C-k discards it"
             (("Insert into the prompt" . +test-banner--action) ("Discard" . +test-banner--action)) info)
    (long-lines "Very long lines: opened plain and unwrapped, as scrolling them can be slow"
                (("Wrap lines" . +test-banner--action) ("Open normally" . +test-banner--action)) warning))
  "The Drawing for Claude's notice and the long lines', standing in.")

(defun +test-banner--inside (frame help)
  "Positions on FRAME's rows whose help is HELP, each drawn whole inside the
frame: nil if one is off it (or none has it)."
  (let ((window (frame-root-window frame))
        (found nil))
    (with-current-buffer (window-buffer window)
      (cl-loop for pos from (point-min) below (point-max)
               when (equal (get-text-property pos 'help-echo) help)
               do (push pos found)
               and unless (let ((posn (posn-at-point pos window)))
                            (and posn
                                 (<= (+ (car (posn-x-y posn)) (car (posn-object-width-height posn)))
                                     (window-body-width window t))))
               return nil
               finally return found))))

(defun +test-banner--room-p (frame window)
  "Non-nil if WINDOW's header line has room for FRAME's rows, its own text
\(if it has one) under them."
  (= (window-header-line-height window)
     (+ (frame-pixel-height frame)
        (if (buffer-local-value '+my/banner--saved-header (window-buffer window))
            (+my/banner--row-height window)
          0))))

(defun +test-banner--laid-out-p (frame window)
  "Non-nil once FRAME lies over WINDOW with as many rows as its notices take
there, and the header line has room for them."
  (let ((rows (+my/banner--rows (buffer-local-value '+my/banner--list (window-buffer window))
                                (+my/banner--columns window))))
    (and (+test-banner--over-p frame window rows)
         (+test-banner--room-p frame window))))

(ert-deftest e2e-banner/narrow-windows-keep-the-actions-and-x ()
  "At 100, 60, 40 and 25 columns every action and ✕ of the Drawing for
Claude's notice and the long lines' inside the frame, clickable; the header
line's room as tall as the frame's rows."
  (+test-banner
    (+test-banner--file "narrow.txt")
    (pcase-dolist (`(,id ,text ,actions ,type) +test-banner--narrow)
      (+my/banner-show id text :type type :actions actions))
    (let ((window (selected-window)))
      (dolist (columns '(100 60 40 25))
        (delete-other-windows window)
        (split-window window columns 'right)
        (let ((frame (+test-banner--shown window)))
          (should (+test-wait-for (lambda () (+test-banner--laid-out-p frame window)) 3))
          ;; Each notice on two rows at 40 and 25, on one at 100.
          (when (/= columns 60)
            (should (= (frame-pixel-height frame)
                       (* (if (< columns 50) 4 2) (+my/banner--row-height window)))))
          (pcase-dolist (`(,_ ,_ ,actions) +test-banner--narrow)
            (dolist (action actions)
              (should (+test-banner--inside frame (concat "mouse-1: " (car action))))))
          (should (= (length (+test-banner--inside frame "mouse-1: close")) (* 3 2)))
          ;; Clicking a cut label runs its action.
          (setq +test-banner--ran nil)
          (let ((pos (car (last (+test-banner--inside frame "mouse-1: Discard")))))
            (call-interactively
             (lookup-key (get-text-property pos 'keymap (window-buffer (frame-root-window frame)))
                         [mouse-1])))
          (should (eq (nth 1 +test-banner--ran) window)))))))

(ert-deftest e2e-banner/resized-the-room-follows ()
  "Narrowed to 25 columns and widened again: the frame's rows and the header
line's room follow, both ways."
  (+test-banner
    (+test-banner--file "resized.txt")
    (setq-local header-line-format "the file's own header")
    (pcase-let ((`(,id ,text ,actions ,type) (car +test-banner--narrow)))
      (+my/banner-show id text :type type :actions actions))
    (let* ((window (selected-window))
           (other (split-window window 100 'right))
           (frame (+test-banner--shown window))
           (row (+my/banner--row-height window)))
      (should (+test-wait-for (lambda () (+test-banner--laid-out-p frame window)) 3))
      (should (= (frame-pixel-height frame) row))
      (window-resize window (- 25 (window-total-width window)) t)
      (should (+test-wait-for (lambda () (and (= (frame-pixel-height frame) (* 2 row))
                                              (+test-banner--laid-out-p frame window)))
                              3))
      (window-resize window (- 100 (window-total-width window)) t)
      (should (+test-wait-for (lambda () (and (= (frame-pixel-height frame) row)
                                              (+test-banner--laid-out-p frame window)))
                              3))
      (ignore other))))

;; ====== MESSAGES ======

(ert-deftest e2e-banner/a-line-break-hides-nothing ()
  "A message with a line break: one row, its action and ✕ on screen, the next
notice under it."
  (+test-banner
    (+test-banner--file "break.txt")
    (+my/banner-show 'first "Export failed: TypeError: broke\n    at foo (x.js:1)"
                     :type 'error :actions '(("Retry" . +test-banner--action)))
    (+my/banner-show 'second "Second notice")
    (let ((frame (+test-banner--shown (selected-window))))
      (should (+test-wait-for (lambda () (+test-banner--over-p frame (selected-window) 2)) 3))
      (should (+test-banner--inside frame "mouse-1: Retry"))
      (should (= (length (+test-banner--inside frame "mouse-1: close")) (* 3 2)))
      (with-current-buffer (window-buffer (frame-root-window frame))
        (goto-char (point-min))
        (should (search-forward "Second notice" nil t))
        (should (pos-visible-in-window-p (match-beginning 0) (frame-root-window frame)))))))

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

;; ====== AN HTML FILE (config/html.el) ======

(ert-deftest e2e-banner/an-html-file-offers-the-browser ()
  "An HTML file: its notice on screen; Open in browser opens the file in the
browser (recorded), the notice staying; its ✕ closes it."
  (+test-banner
    (let ((+test-browsed nil))
      (find-file (+test-file "banner/page.html" "<!doctype html><p>Hi</p>\n"))
      (let ((frame (+test-banner--shown (selected-window))))
        (should (string-match-p "Open this file in your browser\\." (+test-banner--text frame)))
        (should (string-match-p "Open in browser" (+test-banner--text frame)))
        (+test-banner--click frame "Open in browser")
        (should (= (length +test-browsed) 1))
        (should (string-match-p "\\`file://.*/banner/page\\.html\\'" (car +test-browsed)))
        (should (assq 'html-browser +my/banner--list))
        (+test-banner--click frame "✕")
        (should-not (assq 'html-browser +my/banner--list))))))
