;;; tests/e2e/test-agent-ui.el -*- lexical-binding: t; -*-
;; config/agent-ui in a GUI Emacs: what needs real windows and redisplay
;; (window change functions run: Agent UI's views synced in their session's
;; pane). A question left waiting at the turn's end, below what its view
;; shows: the view shown again, scrolled to it, the cursor on it, the focus
;; left in the session. No agent runs: the session is a buffer, its turn's end
;; agent-shell's event called by hand.

(+test-load "config/emacs/childframe" "config/banner" "config/agent-ui")
(require 'agent-shell)

(ert-deftest e2e-agent-ui/a-question-waiting-brought-into-view ()
  (let* ((session (generate-new-buffer "Claude Agent @ e2e"))
         ;; What the turn's end does, alone: a question shown taking the focus
         ;; once Emacs is idle (test-agent-ui-agent.el) off, as config.el can.
         ;; The tests run while Emacs has been idle for a while, so its timer
         ;; was due at once and fired in the redisplay below.
         (agent-ui-focus-questions nil)
         (on-event nil))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () (list session)))
                  ((symbol-function 'agent-shell-subscribe-to)
                   (lambda (&rest args) (setq on-event (plist-get args :on-event)))))
          (with-current-buffer session
            (setq default-directory "/tmp/")
            (agent-ui--watch-questions-h))
          (delete-other-windows)
          (switch-to-buffer session)
          (let ((name (agent-ui--session-name session)))
            ;; More than its pane shows, then the question.
            (agent-ui-show (list :id "steps" :type "text"
                                 :text (mapconcat (lambda (i) (format "Step %d done" i)) (number-sequence 1 150) "\n"))
                           :canvas name)
            (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?"
                             :options ("Change the test" "Revert the message"))
                           :canvas name)
            (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name))))
              ;; A view in the session's pane, closed (hidden), its top shown
              ;; before.
              (redisplay)
              (should (agent-ui-pane-window-p (get-buffer-window canvas)))
              (with-current-buffer canvas (goto-char (point-min)))
              (delete-window (get-buffer-window canvas))
              (redisplay)
              (should-not (get-buffer-window canvas))
              (with-current-buffer session
                (funcall on-event '((:event . turn-complete))))
              (redisplay)
              (let ((window (get-buffer-window canvas)))
                (should window)
                (should (agent-ui-pane-window-p window))
                ;; The focus where it was.
                (should (eq (window-buffer (selected-window)) session))
                ;; The cursor on the question, in view.
                (should (equal (get-text-property (window-point window) 'agent-ui-id canvas) "fix"))
                (should (pos-visible-in-window-p (window-point window) window))
                (should (> (window-start window) 1)))
              ;; The session's mode line says it.
              (with-current-buffer session
                (should (string-match-p "question waiting" (format-mode-line mode-line-format)))))))
      (kill-buffer session))))

;; A question while the minibuffer is open (a file being found): opened then,
;; its pane took another's place (tiling steps aside while it's open), and
;; taking the focus, it got the keys typed there (q killed it).
(ert-deftest e2e-agent-ui/a-question-waits-for-the-minibuffer ()
  "A question shown while the minibuffer reads: every window as it was, the
minibuffer's window selected; once it's closed, its view opens in the
session's pane, then takes the focus once Emacs is idle a moment."
  (let* ((session (generate-new-buffer "Claude Agent @ e2e-mini"))
         (notes (generate-new-buffer "notes.txt"))
         (agent-ui-focus-questions t)
         (agent-ui-focus-questions-delay 0.2)
         (seen nil))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () (list session))))
          (delete-other-windows)
          (switch-to-buffer session)
          (set-window-buffer (split-window-right) notes)
          (let ((name (concat (agent-ui--session-name session) " / ask")))
            (run-with-timer 0.2 nil (lambda ()
                                      (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?"
                                                       :options ("Change the test" "Revert the message"))
                                                     :canvas name)))
            (run-with-timer 1.2 nil (lambda ()
                                      (setq seen (list (mapcar #'window-buffer (window-list nil 'nomini))
                                                       (minibufferp (window-buffer (selected-window)))))
                                      (exit-minibuffer)))
            (read-from-minibuffer "Find file: ")
            (should (equal seen (list (list session notes) t)))
            (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name))))
              (should (+test-wait-for (lambda () (get-buffer-window canvas)) 2))
              (should (agent-ui-pane-window-p (get-buffer-window canvas)))
              (should (get-buffer-window notes))
              (should (get-buffer-window session))
              (should (+test-wait-for (lambda () (eq (window-buffer (selected-window)) canvas)) 3))
              (should (equal (get-text-property (window-point) 'agent-ui-id canvas) "fix"))
              (kill-buffer canvas))))
      (kill-buffer session)
      (kill-buffer notes))))

(ert-deftest e2e-agent-ui/redrawn-when-its-text-is-scaled ()
  "Its text scaled (C-x C-+, C-x C-0): drawn again, within a moment, at its
window's new width, to its last column in the GUI (37 columns of zoomed text
were drawn at 67 until g r)."
  (let ((agent-ui-display-function #'switch-to-buffer)
        (agent-ui-default-canvas "e2e-scale"))
    (delete-other-windows)
    (agent-ui-show (list :id "t" :type "text"
                         :text (mapconcat (lambda (i) (format "word%d" i)) (number-sequence 1 60) " ")))
    (let* ((canvas (agent-ui-canvas))
           (window (get-buffer-window canvas))
           (drawn-for-it
            (lambda ()
              (redisplay t)
              (with-current-buffer canvas
                (and (not agent-ui--dirty)
                     ;; In the GUI, to its last column (a terminal's: one short).
                     (equal agent-ui--width (window-max-chars-per-line window))
                     (cl-every (lambda (line) (<= (string-width line) agent-ui--width))
                               (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n")))))))
      (unwind-protect
          (with-current-buffer canvas
            (agent-ui--flush)
            (should (+test-wait-for drawn-for-it 2))
            (let ((before agent-ui--width))
              (text-scale-increase 3)
              (should (+test-wait-for drawn-for-it 0.5))
              (should (< agent-ui--width before))
              (text-scale-set 0)
              (should (+test-wait-for drawn-for-it 0.5))
              (should (= agent-ui--width before))))
        (kill-buffer canvas)))))

(defun +test-e2e-aui--borders-in-line (canvas)
  "CANVAS's borders at their columns' pixels, its lines a line high, as its
window shows them; how many borders."
  (let* ((window (get-buffer-window canvas))
         (cw (frame-char-width))
         (lh (frame-char-height))
         (borders 0))
    (with-current-buffer canvas
      (set-window-start window (point-min))
      (redisplay t)
      (goto-char (point-min))
      ;; Side by side, the glyphs on its lines.
      (should (search-forward "│  ✎ Add a note" nil t))
      (should (search-forward "⏵ Answer" nil t))
      (goto-char (point-min))
      (while (not (eobp))
        (let ((bol (line-beginning-position)) (eol (line-end-position)))
          (unless (= bol eol)
            (should (equal (list (line-number-at-pos) (cdr (window-text-pixel-size window bol eol)))
                           (list (line-number-at-pos) lh))))
          (while (re-search-forward "[│╭╮╰╯]" eol t)
            (cl-incf borders)
            (let ((before (buffer-substring-no-properties bol (match-beginning 0))))
              (should (equal (list (line-number-at-pos) (car (window-text-pixel-size window bol (match-beginning 0))))
                             (list (line-number-at-pos) (* cw (string-width before))))))))
        (forward-line 1)))
    borders))

(ert-deftest e2e-agent-ui/borders-in-line-whatever-the-glyphs ()
  "A panel's borders and the │ between a row's children at their columns'
pixels, on lines as high as the others, beside glyphs the default font
lacks (✎ and ⏵ from fallback fonts were pixels wider or narrower than a
column, their lines higher: the borders out of line, with gaps); again
after the font's size changed (the frame's size in pixels kept, as Doom
does: no window size change, the canvas was left drawn for the old cells)."
  (let ((agent-ui-display-function #'switch-to-buffer)
        (agent-ui-default-canvas "e2e-glyphs")
        (frame-inhibit-implied-resize t)
        (font (frame-parameter nil 'font)))
    (delete-other-windows)
    (set-frame-size (selected-frame) 100 40)
    ;; On X, the frame takes its size at the next redisplay: the canvas would
    ;; be drawn for the one before (a test's before it: wider), its lines
    ;; wrapping once it's resized.
    (should (+test-wait-for (lambda () (= (frame-width) 100)) 5))
    (agent-ui-show '(:id "row" :type "panel" :layout "row"
                     :children ((:id "pick" :type "choice" :question "Which?" :options ("A" "B") :note t)
                                (:id "order" :type "rank" :question "Order?" :items ("x" "y") :note t))))
    (let ((canvas (agent-ui-canvas)))
      (unwind-protect
          (progn
            (with-current-buffer canvas (agent-ui--flush))
            (should (> (+test-e2e-aui--borders-in-line canvas) 20))
            ;; Settled: its window shown (a size change), drawn for it.
            (with-current-buffer canvas
              (agent-ui--flush)
              (redisplay t)
              (should-not agent-ui--dirty))
            (let ((size (frame-char-height)))
              (set-frame-font (font-spec :size (+ (font-get (font-spec :name font) :size) 4)) nil t)
              (should (> (frame-char-height) size)))
            (with-current-buffer canvas (agent-ui--flush))
            (should (> (+test-e2e-aui--borders-in-line canvas) 20)))
        (set-frame-font font nil t)
        (kill-buffer canvas)))))

(ert-deftest e2e-agent-ui/dividers-in-line-whatever-their-marks ()
  "A canvas's sections' dividers in the GUI: each as wide as the canvas's
columns in pixels, a line high, whatever its fold's arrow and its state's
mark (▾ ▸ ● ◆ ○ ‖ ✓ ✗, from fallback fonts some); folded, its section's
elements hidden, its divider still there."
  (let ((agent-ui-display-function #'switch-to-buffer)
        (agent-ui-default-canvas "e2e-sections"))
    (delete-other-windows)
    (dolist (state '(running needs-you waiting paused done failed nil))
      (let ((name (if state (symbol-name state) "none")))
        (agent-ui-section nil name :title name :state state :note "3m")
        (agent-ui-show (list :id "x" :type "text" :text (concat "in " name)) :section name)))
    (agent-ui-section nil "done" :folded t)
    (let* ((canvas (agent-ui-canvas))
           (window (get-buffer-window canvas))
           (cw (frame-char-width))
           (lh (frame-char-height))
           (dividers 0))
      (unwind-protect
          (with-current-buffer canvas
            (agent-ui--flush)
            (set-window-start window (point-min))
            (redisplay t)
            (goto-char (point-min))
            (while (not (eobp))
              (when (get-text-property (point) 'agent-ui-section)
                (cl-incf dividers)
                (let ((bol (line-beginning-position)) (eol (line-end-position)))
                  (should (equal (list (line-number-at-pos) (window-text-pixel-size window bol eol))
                                 (list (line-number-at-pos)
                                       (cons (* cw (string-width (buffer-substring bol eol))) lh))))))
              (forward-line 1))
            (should (= dividers 7))
            (goto-char (point-min))
            (should (search-forward "▸ done ✓ 3m · 1 hidden" nil t))
            (should (search-forward "in done" nil t))
            (should (invisible-p (match-beginning 0))))
        (kill-buffer canvas)))))

(ert-deftest e2e-agent-ui/a-panel-offers-its-pdf ()
  "A project panel opened in a GUI frame: its notice offering its PDF over
it; exported, a real PDF beside its file, its charts drawn in it as images
(its SVG nests theirs)."
  (skip-unless (executable-find "rsvg-convert"))
  (let* ((root (file-name-as-directory (make-temp-file "panel-pdf-" t)))
         (default-directory root)
         (agent-ui-panel-allow-function (lambda (_panel) nil))
         (svg nil)
         (canvas nil))
    (unwind-protect
        (progn
          (make-directory (expand-file-name agent-ui-panel-directory root) t)
          (with-temp-file (expand-file-name "dash.el" (expand-file-name agent-ui-panel-directory root))
            (insert "(agent-ui-panel :version 1
 :ui (:type \"panel\" :id \"dash\" :title \"Dash\" :layout \"row\"
      :children ((:type \"chart\" :id \"load\" :title \"Load\" :values (3 5 4 8 6))
                 (:type \"gauge\" :id \"busy\" :title \"Busy\" :value 40 :max 100))))\n"))
          (delete-other-windows)
          (setq canvas (agent-ui-open-panel "dash"))
          (redisplay t)
          (with-current-buffer canvas
            (should (assq 'agent-ui-panel-pdf +my/banner--list))
            (should header-line-format))
          (advice-add 'agent-ui-snapshot-svg :filter-return (lambda (text) (setq svg text)) '((name . e2e-svg)))
          (let ((pdf (with-current-buffer canvas (agent-ui-export-pdf))))
            (should (string-prefix-p (expand-file-name agent-ui-panel-directory root) pdf))
            (should (equal (with-temp-buffer
                             (set-buffer-multibyte nil)
                             (insert-file-contents-literally pdf nil 0 5)
                             (buffer-string))
                           "%PDF-"))
            ;; The chart and the gauge drawn as images in it.
            (should (> (with-temp-buffer (insert svg) (how-many "<svg\\b" (point-min) (point-max))) 2))))
      (advice-remove 'agent-ui-snapshot-svg 'e2e-svg)
      (when (buffer-live-p canvas) (kill-buffer canvas))
      (delete-directory root t))))
