;;; tests/unit/test-banner.el -*- lexical-binding: t; -*-
;; config/banner.el: notices at the top of a window: showing, replacing and closing them, per buffer; their rows
;; (icon, message cut short, actions, ✕) and where clicks run; room in the header
;; line; the terminal's header line; the GUI's notices' frames (child frames:
;; stood in for here, batch Emacs can't make frames); theme colours. The long
;; lines notice: test-long-lines.el.

(+test-load "config/childframe" "config/banner")

;; Loading tinted the rows (no theme yet: nothing to do) and asked for a sync.
(defconst +test-banner--theme-at-load +my/banner--theme)
(defconst +test-banner--sync-pending-at-load (timerp +my/banner--sync-timer))

(defun +test-banner--cancel-sync ()
  "No sync left pending (one would run in another test)."
  (when (timerp +my/banner--sync-timer)
    (cancel-timer +my/banner--sync-timer))
  (setq +my/banner--sync-timer nil))

(+test-banner--cancel-sync)

;; ====== HELPERS ======

(defmacro +test-banner (&rest body)
  "BODY from one window on *scratch*, no notices' frames, icons standing in
\(\"I\", \"W\", \"E\": the codicon's first letter after nf-cod-)."
  (declare (indent 0))
  `(+test-with-reset
     (let ((+my/banner--frames nil))
       (cl-letf (((symbol-function 'nerd-icons-codicon)
                  (lambda (name) (upcase (substring name 7 8)))))
         (unwind-protect (progn ,@body)
           (+test-banner--cancel-sync))))))

(defun +test-banner--text (string)
  (substring-no-properties string))

(defun +test-banner--pos (string text)
  "Where TEXT starts in STRING."
  (or (string-search text string) (error "No %S in %S" text string)))

(defun +test-banner--command (row label &optional header)
  "The command a click on LABEL in ROW runs (HEADER: a terminal's header line)."
  (let ((pos (+test-banner--pos row label)))
    (if header
        (lookup-key (get-text-property pos 'local-map row) [header-line mouse-1])
      (lookup-key (get-text-property pos 'keymap row) [mouse-1]))))

(defun +test-banner--mouse-event (window)
  "A click in WINDOW's header line."
  (list 'mouse-1 (list window 'header-line '(0 . 0) 0 nil nil '(0 . 0) nil '(0 . 0) '(0 . 0))))

(defun +test-banner--click (row label &optional header event)
  "Click LABEL in ROW, `last-input-event' EVENT."
  (let ((last-input-event event))
    (call-interactively (+test-banner--command row label header))))

;; NOTICES' FRAMES (stood in for)
(cl-defstruct (+test-banner--frame (:constructor +test-banner--frame-make))
  parent buffer params (visible nil) (live t) size position (resized 0))

(defvar +test-banner--made nil "The notices' frames made, latest first.")

(defun +test-banner--make-frame (parent)
  (let ((frame (+test-banner--frame-make
                :parent parent
                :buffer (with-current-buffer (generate-new-buffer " *+my/banner*")
                          (setq buffer-read-only t)
                          (current-buffer)))))
    (push frame +test-banner--made)
    frame))

(defun +test-banner--frame-text (frame)
  (with-current-buffer (+test-banner--frame-buffer frame)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-banner--frame-ticks (frame)
  (with-current-buffer (+test-banner--frame-buffer frame) (buffer-chars-modified-tick)))

(defun +test-banner--frame-of (window)
  (nth 1 (assq window +my/banner--frames)))

(defmacro +test-banner--gui (&rest body)
  "BODY as in a GUI: graphic frames, notices' frames made (stand-ins,
`+test-banner--made') and moved, shown, hidden, deleted. Rows 20 px tall."
  (declare (indent 0))
  `(let ((+test-banner--made nil)
         (fake-p #'+test-banner--frame-p)
         (orig (mapcar (lambda (f) (cons f (symbol-function f)))
                       '(frame-live-p frame-root-window window-buffer set-frame-parameter
                         frame-parameter set-frame-size set-frame-position frame-visible-p
                         make-frame-visible make-frame-invisible delete-frame frame-parent))))
     (cl-flet ((orig (f &rest args) (apply (alist-get f orig) args)))
       (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                 ((symbol-function '+my/banner--make-frame) #'+test-banner--make-frame)
                 ((symbol-function '+my/banner--row-height) (lambda (&rest _) 20))
                 ((symbol-function 'frame-live-p)
                  (lambda (f) (if (funcall fake-p f) (+test-banner--frame-live f) (orig 'frame-live-p f))))
                 ((symbol-function 'frame-root-window)
                  (lambda (&optional f) (if (funcall fake-p f) f (orig 'frame-root-window f))))
                 ((symbol-function 'window-buffer)
                  (lambda (&optional w) (if (funcall fake-p w) (+test-banner--frame-buffer w)
                                          (orig 'window-buffer w))))
                 ((symbol-function 'set-frame-parameter)
                  (lambda (f p v) (if (funcall fake-p f)
                                      (setf (alist-get p (+test-banner--frame-params f)) v)
                                    (orig 'set-frame-parameter f p v))))
                 ((symbol-function 'frame-parameter)
                  (lambda (f p) (if (funcall fake-p f) (alist-get p (+test-banner--frame-params f))
                                  (orig 'frame-parameter f p))))
                 ((symbol-function 'set-frame-size)
                  (lambda (f w h &optional pixelwise)
                    (if (funcall fake-p f)
                        (progn (setf (+test-banner--frame-size f) (list w h pixelwise))
                               (cl-incf (+test-banner--frame-resized f)))
                      (orig 'set-frame-size f w h pixelwise))))
                 ((symbol-function 'set-frame-position)
                  (lambda (f x y) (if (funcall fake-p f) (setf (+test-banner--frame-position f) (list x y))
                                    (orig 'set-frame-position f x y))))
                 ((symbol-function 'frame-visible-p)
                  (lambda (f) (if (funcall fake-p f) (+test-banner--frame-visible f)
                                (orig 'frame-visible-p f))))
                 ((symbol-function 'make-frame-visible)
                  (lambda (&optional f) (if (funcall fake-p f) (setf (+test-banner--frame-visible f) t)
                                          (orig 'make-frame-visible f))))
                 ((symbol-function 'make-frame-invisible)
                  (lambda (&optional f force) (if (funcall fake-p f) (setf (+test-banner--frame-visible f) nil)
                                                (orig 'make-frame-invisible f force))))
                 ((symbol-function 'delete-frame)
                  (lambda (&optional f force) (if (funcall fake-p f) (setf (+test-banner--frame-live f) nil)
                                                (orig 'delete-frame f force))))
                 ((symbol-function 'frame-parent)
                  (lambda (&optional f) (if (funcall fake-p f) (+test-banner--frame-parent f)
                                          (orig 'frame-parent f)))))
         (unwind-protect (progn ,@body)
           (dolist (frame +test-banner--made)
             (kill-buffer (+test-banner--frame-buffer frame))))))))

;; ====== SETTINGS ======

(ert-deftest banner/types ()
  (should (equal +my/banner-types
                 '((info    "nf-cod-info"    blue)
                   (warning "nf-cod-warning" yellow)
                   (error   "nf-cod-error"   red)))))

(ert-deftest banner/faces ()
  (dolist (face '(+my/banner-info +my/banner-warning +my/banner-error))
    (should (facep face))
    (should (eq (face-attribute face :inherit) 'header-line)))
  (should (eq (face-attribute '+my/banner-action :inherit) 'link))
  (should (eq (face-attribute '+my/banner-action :underline) nil))
  (should (eq (face-attribute '+my/banner-action :weight) 'bold)))

(ert-deftest banner/face-per-type ()
  (should (eq (+my/banner--face 'info) '+my/banner-info))
  (should (eq (+my/banner--face 'warning) '+my/banner-warning))
  (should (eq (+my/banner--face 'error) '+my/banner-error))
  ;; Unknown types look like info.
  (should (eq (+my/banner--face 'bogus) '+my/banner-info))
  (should (eq (+my/banner--face nil) '+my/banner-info)))

(ert-deftest banner/hooks ()
  (should (memq '+my/banner--window-change-h window-state-change-functions))
  (should (memq '+my/banner--sync-soon change-major-mode-hook))
  (should (memq '+my/banner-faces-h doom-load-theme-hook)))

(ert-deftest banner/loading-tints-and-syncs ()
  (should (= +test-banner--theme-at-load 1))
  (should +test-banner--sync-pending-at-load))

;; ====== SHOWING AND CLOSING ======

(ert-deftest banner/show ()
  (+test-banner
    (with-current-buffer (+test-buffer "B" "text\n")
      (+my/banner-show 'one "First")
      (should (equal +my/banner--list '((one "First" nil info))))
      (+my/banner-show 'two "Second" :type 'warning :actions '(("Do" . ignore)))
      ;; In the order shown, top first.
      (should (equal +my/banner--list '((one "First" nil info)
                                        (two "Second" (("Do" . ignore)) warning)))))))

(ert-deftest banner/show-again-replaces-in-place ()
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (+my/banner-show 'a "A")
      (+my/banner-show 'b "B")
      (+my/banner-show 'c "C")
      (+my/banner-show 'b "B again" :type 'error)
      (should (equal (mapcar #'car +my/banner--list) '(a b c)))
      (should (equal (assq 'b +my/banner--list) '(b "B again" nil error))))))

(ert-deftest banner/show-makes-room-in-the-header-line ()
  "The header line's own content stays, after the notices' room."
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (setq-local header-line-format "path/to/file")
      (+my/banner-show 'one "First")
      (should (equal header-line-format (list +my/banner--header "path/to/file")))
      (should (equal +my/banner--saved-header "path/to/file"))
      ;; Once only.
      (+my/banner-show 'two "Second")
      (+my/banner-show 'one "First again")
      (should (equal header-line-format (list +my/banner--header "path/to/file"))))))

(ert-deftest banner/close-by-id ()
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (setq-local header-line-format "hdr")
      (+my/banner-show 'a "A")
      (+my/banner-show 'b "B")
      (+my/banner-show 'c "C")
      (+my/banner-close 'b)
      (should (equal (mapcar #'car +my/banner--list) '(a c)))
      ;; An unknown one: nothing closes.
      (+my/banner-close 'zzz)
      (should (equal (mapcar #'car +my/banner--list) '(a c)))
      (should (equal header-line-format (list +my/banner--header "hdr"))))))

(ert-deftest banner/close-the-first-by-default ()
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (+my/banner-show 'a "A")
      (+my/banner-show 'b "B")
      (+my/banner-close)
      (should (equal (mapcar #'car +my/banner--list) '(b))))))

(ert-deftest banner/close-command ()
  "M-x +my/banner-close closes the first."
  (should (commandp '+my/banner-close))
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (+my/banner-show 'a "A")
      (+my/banner-show 'b "B")
      (call-interactively #'+my/banner-close)
      (should (equal (mapcar #'car +my/banner--list) '(b))))))

(ert-deftest banner/closing-the-last-gives-the-header-line-back ()
  (+test-banner
    (dolist (header '("path" nil (:eval "sticky") ("a" "b")))
      (with-current-buffer (+test-buffer "B")
        (setq-local header-line-format header)
        (+my/banner-show 'a "A")
        (+my/banner-show 'b "B")
        (+my/banner-close 'a)
        (should (+my/banner--ours-p))
        (+my/banner-close 'b)
        (should (equal header-line-format header))
        (should-not +my/banner--list)))))

(ert-deftest banner/closing-when-none-is-harmless ()
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (setq-local header-line-format "hdr")
      (+my/banner-close)
      (+my/banner-close 'a)
      (should-not +my/banner--list)
      (should (equal header-line-format "hdr")))))

(ert-deftest banner/header-line-set-anew-meanwhile ()
  "A mode set the header line since: room is made again in front of the new
one, and closing the notices leaves the new one."
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (setq-local header-line-format "old")
      (+my/banner-show 'a "A")
      (setq-local header-line-format "new")
      (should-not (+my/banner--ours-p))
      (+my/banner-show 'b "B")
      (should (equal header-line-format (list +my/banner--header "new")))
      (+my/banner-close 'a)
      (+my/banner-close 'b)
      (should (equal header-line-format "new"))))
  ;; Set anew, then all closed: it stays.
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (+my/banner-show 'a "A")
      (setq-local header-line-format "new")
      (+my/banner-close 'a)
      (should (equal header-line-format "new")))))

(ert-deftest banner/notices-are-per-buffer ()
  (+test-banner
    (let ((a (+test-buffer "A"))
          (b (+test-buffer "B")))
      (with-current-buffer b (setq-local header-line-format "b's"))
      (with-current-buffer a (+my/banner-show 'one "For A"))
      (should (buffer-local-value '+my/banner--list a))
      (should-not (buffer-local-value '+my/banner--list b))
      (should (equal (buffer-local-value 'header-line-format b) "b's"))
      ;; The same ID in another buffer is another notice.
      (with-current-buffer b (+my/banner-show 'one "For B"))
      (with-current-buffer a (+my/banner-close 'one))
      (should-not (buffer-local-value '+my/banner--list a))
      (should (equal (buffer-local-value '+my/banner--list b) '((one "For B" nil info))))
      ;; Kept while the buffer is shown, hidden and shown again.
      (switch-to-buffer b)
      (switch-to-buffer a)
      (switch-to-buffer b)
      (should (equal (buffer-local-value '+my/banner--list b) '((one "For B" nil info)))))))

(ert-deftest banner/a-new-major-mode-drops-the-notices ()
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (+my/banner-show 'one "A notice")
      (text-mode)
      (should-not +my/banner--list)
      (should-not (+my/banner--ours-p))
      ;; The frames follow (soon: a sync).
      (should (timerp +my/banner--sync-timer)))))

;; ====== A NOTICE'S ROW ======

(ert-deftest banner/row-text ()
  (+test-banner
    (let ((buffer (+test-buffer "B")))
      (should (equal (+test-banner--text
                      (+my/banner--row '(id "Message" (("Do" . ignore) ("Undo" . ignore)) warning) buffer))
                     "  W  Message    Do    Undo  ✕  "))
      (should (equal (+test-banner--text (+my/banner--row '(id "Plain" nil info) buffer))
                     "  I  Plain  ✕  "))
      (should (equal (+test-banner--text (+my/banner--row '(id "Bad" nil error) buffer))
                     "  E  Bad  ✕  ")))))

(ert-deftest banner/row-properties ()
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (row (+my/banner--row '(id "Message" (("Do" . ignore)) warning) buffer))
           (do (+test-banner--pos row "Do"))
           (close (+test-banner--pos row "✕")))
      ;; The message: the type's face; clicks and the wheel do nothing.
      (should (eq (get-text-property 0 'face row) '+my/banner-warning))
      (should (eq (get-text-property 6 'face row) '+my/banner-warning))
      (should (eq (get-text-property 6 'keymap row) +my/banner--row-map))
      ;; The icon: in the row's face (after its own), same keys.
      (should (memq '+my/banner-warning (ensure-list (get-text-property 2 'face row))))
      (should (eq (get-text-property 2 'keymap row) +my/banner--row-map))
      ;; An action.
      (should (equal (get-text-property do 'face row) '(+my/banner-action +my/banner-warning)))
      (should (eq (get-text-property do 'mouse-face row) 'highlight))
      (should (eq (get-text-property do 'pointer row) 'hand))
      (should (equal (get-text-property do 'help-echo row) "mouse-1: Do"))
      (should (eq (keymap-parent (get-text-property do 'keymap row)) +my/banner--row-map))
      (should (commandp (+test-banner--command row "Do")))
      ;; ✕, 4 columns from the right edge, and the row's colour to the edge.
      (should (equal (get-text-property close 'help-echo row) "mouse-1: close"))
      (should (equal (get-text-property (- close 2) 'display row) '(space :align-to (- right 4))))
      (should (equal (get-text-property (1- (length row)) 'display row) '(space :align-to right)))
      (should (eq (get-text-property (1- (length row)) 'face row) '+my/banner-warning))
      ;; Not in a header line: no header line keys.
      (should-not (text-property-not-all 0 (length row) 'local-map nil row)))))

(ert-deftest banner/row-help-echo-trims-the-label ()
  (+test-banner
    (let ((row (+my/banner--row '(id "M" ((" Spaced " . ignore)) info) (+test-buffer "B"))))
      (should (equal (get-text-property (+test-banner--pos row " Spaced ") 'help-echo row)
                     "mouse-1: Spaced")))))

(ert-deftest banner/row-map-ignores-clicks-and-the-wheel ()
  (dolist (event '(down-mouse-1 mouse-1 double-mouse-1 triple-mouse-1 drag-mouse-1
                   down-mouse-2 mouse-2 down-mouse-3 mouse-3
                   wheel-up wheel-down wheel-left wheel-right
                   double-wheel-up double-wheel-down triple-wheel-up triple-wheel-down))
    (should (eq (lookup-key +my/banner--row-map (vector event)) #'ignore))))

(ert-deftest banner/row-in-the-header-line ()
  "A terminal's header line: its own keys (header-line mouse-1), up to the
window's edge past the margin and fringe, and how many more notices."
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (row (+my/banner--row '(id "Message" (("Do" . ignore)) warning) buffer t 2)))
      (should (equal (+test-banner--text row) "  W  Message    Do    (2 more)  ✕  "))
      (should-not (text-property-not-all 0 (length row) 'keymap nil row))
      (should (commandp (+test-banner--command row "Do" t)))
      (should (commandp (+test-banner--command row "✕" t)))
      (should (equal (get-text-property (+test-banner--pos row "(2 more)") 'face row)
                     '(shadow +my/banner-warning)))
      (should (equal (get-text-property (1- (length row)) 'display row)
                     '(space :align-to (+ right right-margin right-fringe)))))
    ;; No others: not mentioned.
    (should-not (string-search "more" (+my/banner--row '(id "M" nil info) (+test-buffer "B") t 0)))
    (should-not (string-search "more" (+my/banner--row '(id "M" nil info) (+test-buffer "B") t nil)))))

(ert-deftest banner/row-message-cut-short-to-fit ()
  "WIDTH columns: the message cut (…) so that the icon, actions, more, ✕ fit."
  (+test-banner
    (let ((buffer (+test-buffer "B"))
          (message (lambda (row) (let ((start 5))
                                   (substring (+test-banner--text row) start
                                              (string-search "  " (+test-banner--text row) start))))))
      ;; 40 columns, nothing else: 28 for the message.
      (let ((row (+my/banner--row (list 'id (make-string 30 ?x) nil 'info) buffer nil nil 40)))
        (should (string-suffix-p "…" (funcall message row)))
        (should (= (string-width (funcall message row)) 28)))
      (let ((row (+my/banner--row (list 'id (make-string 28 ?x) nil 'info) buffer nil nil 40)))
        (should (equal (funcall message row) (make-string 28 ?x))))
      ;; An action takes its label and 4 more.
      (let ((row (+my/banner--row (list 'id (make-string 30 ?x) '(("Do" . ignore)) 'info) buffer nil nil 40)))
        (should (= (string-width (funcall message row)) 22)))
      ;; "(N more)" too.
      (let ((row (+my/banner--row (list 'id (make-string 30 ?x) nil 'info) buffer t 3 40)))
        (should (= (string-width (funcall message row)) 16))
        (should (string-search "(3 more)" row)))
      ;; Wide characters count their width.
      (let ((row (+my/banner--row (list 'id (make-string 20 ?日) nil 'info) buffer nil nil 40)))
        (should (<= (string-width (funcall message row)) 28))
        (should (string-suffix-p "…" (funcall message row))))
      ;; No room at all: the … still.
      (let ((row (+my/banner--row (list 'id "Message" '(("Action" . ignore)) 'info) buffer nil nil 10)))
        (should (equal (funcall message row) "…"))
        (should (string-search "Action" row)))
      ;; No width: never cut.
      (let ((row (+my/banner--row (list 'id (make-string 300 ?x) nil 'info) buffer)))
        (should (string-search (make-string 300 ?x) row))))))

(ert-deftest banner/icon ()
  (+test-banner
    (should (equal (+test-banner--text (+my/banner--icon 'info '+my/banner-info)) "I"))
    (should (equal (+test-banner--text (+my/banner--icon 'warning '+my/banner-warning)) "W"))
    (should (equal (+test-banner--text (+my/banner--icon 'error '+my/banner-error)) "E"))
    ;; Unknown types: info's.
    (should (equal (+test-banner--text (+my/banner--icon 'bogus '+my/banner-info)) "I"))
    ;; Its colour: the type's theme colour.
    (cl-letf (((symbol-function 'doom-color) (lambda (colour) (format "#%s" colour))))
      (let ((icon (+my/banner--icon 'warning '+my/banner-warning)))
        (should (equal (get-text-property 0 'face icon)
                       '((:foreground "#yellow") +my/banner-warning)))))))

(ert-deftest banner/icon-without-nerd-icons ()
  (+test-banner
    (cl-letf (((symbol-function 'nerd-icons-codicon) (lambda (_) (error "No such icon"))))
      (let ((icon (+my/banner--icon 'warning '+my/banner-warning)))
        (should (equal (+test-banner--text icon) "!"))
        (should (eq (get-text-property 0 'face icon) '+my/banner-warning))))
    (cl-letf (((symbol-function 'nerd-icons-codicon) nil))
      (should (equal (+test-banner--text (+my/banner--icon 'info '+my/banner-info)) "!")))))

(ert-deftest banner/icon-from-nerd-icons ()
  "With the real nerd-icons (Doom has it): a codicon glyph, in the row's face."
  (skip-unless (require 'nerd-icons nil t))
  (let ((icon (+my/banner--icon 'warning '+my/banner-warning)))
    (should (equal icon (let ((glyph (nerd-icons-codicon "nf-cod-warning")))
                          (add-face-text-property 0 (length glyph) '+my/banner-warning t glyph)
                          (when (fboundp 'doom-color)
                            (add-face-text-property 0 (length glyph)
                                                    `(:foreground ,(doom-color 'yellow)) nil glyph))
                          glyph)))
    (should-not (equal (+test-banner--text icon) "!"))))

;; ====== ACTIONS ======

(ert-deftest banner/action-runs-in-the-buffer-and-window ()
  "An action runs in the notice's buffer, in the window clicked (the one the
notice is about), selected."
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (got nil)
           (main (selected-window))
           (other (split-window nil nil 'right))
           (row (+my/banner--row (list 'id "M" (list (cons "Do" (lambda () (setq got (list (current-buffer)
                                                                                          (selected-window))))))
                                       'info)
                                 buffer t)))
      (set-window-buffer other buffer)
      (+test-banner--click row "Do" t (+test-banner--mouse-event other))
      (should (equal got (list buffer other)))
      (should (eq (selected-window) other))
      (ignore main))))

(ert-deftest banner/action-from-the-notices-frame ()
  "Clicked on a notices' frame (selected by the click): the window it's over."
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (got nil)
           (other (split-window nil nil 'right))
           (row (+my/banner--row (list 'id "M" (list (cons "Do" (lambda () (setq got (selected-window))))) 'info)
                                 buffer)))
      (set-window-buffer other buffer)
      (let ((+my/banner--frames (list (list other (selected-frame) nil))))
        (+test-banner--click row "Do"))
      (should (eq got other)))))

(ert-deftest banner/action-gives-input-back-to-the-window ()
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (focused nil)
           (row (+my/banner--row '(id "M" (("Do" . ignore)) info) buffer)))
      (cl-letf (((symbol-function 'select-frame-set-input-focus) (lambda (frame) (setq focused frame))))
        ;; From a notices' frame: its parent gets the keyboard.
        (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) 'the-parent)))
          (+test-banner--click row "Do"))
        (should (eq focused 'the-parent))
        ;; Not from a child frame: nothing to give back.
        (setq focused nil)
        (+test-banner--click row "Do")
        (should-not focused)))))

(ert-deftest banner/clicked-window ()
  (+test-banner
    (let ((main (selected-window))
          (other (split-window nil nil 'right)))
      ;; A notices' frame selected: its window.
      (let ((+my/banner--frames (list (list 'elsewhere 'another-frame nil)
                                      (list other (selected-frame) nil))))
        (should (eq (+my/banner--clicked-window) other)))
      ;; A click in a header line: its window.
      (let ((last-input-event (+test-banner--mouse-event other)))
        (should (eq (+my/banner--clicked-window) other)))
      ;; Its window gone, or not a click: the selected one.
      (let ((last-input-event (+test-banner--mouse-event other)))
        (delete-window other)
        (should (eq (+my/banner--clicked-window) main)))
      (let ((last-input-event ?a))
        (should (eq (+my/banner--clicked-window) main))))))

(ert-deftest banner/action-in-a-killed-buffer-does-nothing ()
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (called nil)
           (row (+my/banner--row (list 'id "M" (list (cons "Do" (lambda () (setq called t)))) 'info) buffer)))
      (kill-buffer buffer)
      (+test-banner--click row "Do")
      (should-not called))))

(ert-deftest banner/close-button-closes-its-notice ()
  "✕ closes its own notice, not the first."
  (+test-banner
    (let ((buffer (+test-buffer "B")))
      (switch-to-buffer buffer)
      (+my/banner-show 'a "A")
      (+my/banner-show 'b "B")
      (let ((row (+my/banner--row (assq 'b +my/banner--list) buffer)))
        (+test-banner--click row "✕"))
      (should (equal (mapcar #'car +my/banner--list) '(a)))
      ;; In a terminal's header line too.
      (let ((row (+my/banner--row (assq 'a +my/banner--list) buffer t 0)))
        (+test-banner--click row "✕" t (+test-banner--mouse-event (selected-window))))
      (should-not +my/banner--list))))

;; ====== THE HEADER LINE ======

(ert-deftest banner/header-line-in-a-terminal ()
  "The first notice, how many more, cut to the window's width."
  (+test-banner
    (with-current-buffer (+test-buffer "B")
      (switch-to-buffer (current-buffer))
      (should-not (+my/banner--header-line))
      (+my/banner-show 'a (make-string 200 ?x) :type 'error :actions '(("Fix" . ignore)))
      (+my/banner-show 'b "Second")
      (+my/banner-show 'c "Third")
      (let ((row (+my/banner--header-line)))
        (should (string-prefix-p "  E  xxx" (+test-banner--text row)))
        (should (string-search "(2 more)" row))
        (should (string-search "Fix" row))
        (should (string-search "…" row))
        (should (<= (string-width (+test-banner--text row)) (window-body-width)))
        (should (commandp (+test-banner--command row "Fix" t))))
      (+my/banner-close 'a)
      (should (string-prefix-p "  I  Second" (+test-banner--text (+my/banner--header-line))))
      (+my/banner-close 'b)
      (+my/banner-close 'c)
      (should-not (+my/banner--header-line)))))

(ert-deftest banner/header-line-in-the-gui ()
  "Room for each notice: a spacer as tall as their rows, the header line's own
text below (or none)."
  (+test-banner
    (let ((got nil))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                ((symbol-function '+my/banner--spacer)
                 (lambda (rows alone) (setq got (list rows alone)) "SPACER")))
        (with-current-buffer (+test-buffer "B")
          (setq-local header-line-format "path")
          (+my/banner-show 'a "A")
          (+my/banner-show 'b "B")
          (should (equal (+my/banner--header-line) "SPACER"))
          (should (equal got '(2 nil))))
        (with-current-buffer (+test-buffer "C")
          (+my/banner-show 'a "A")
          (+my/banner--header-line)
          (should (equal got '(1 t))))))))

(ert-deftest banner/spacer-height ()
  (+test-banner
    (let ((+my/banner--spacers (make-hash-table :test #'equal))
          (height (lambda (spacer)
                    (let ((data (image-property (get-text-property 0 'display spacer) :data)))
                      (string-match "\"1 \\([0-9]+\\) 1 1\"" data)
                      (string-to-number (match-string 1 data))))))
      (cl-letf (((symbol-function '+my/banner--row-height) (lambda (&rest _) 20))
                ((symbol-function '+my/banner--descent) (lambda (&rest _) 5)))
        ;; With the header line's text below: the rows, and its line down to
        ;; the baseline.
        (should (= (funcall height (+my/banner--spacer 1 nil)) 35))
        (should (= (funcall height (+my/banner--spacer 2 nil)) 55))
        ;; Alone: the rows, the image on the baseline.
        (should (= (funcall height (+my/banner--spacer 1 t)) 15))
        (should (= (funcall height (+my/banner--spacer 3 t)) 55))
        ;; Not scaled (a HiDPI X11 screen scaled it up).
        (should (eql (image-property (get-text-property 0 'display (+my/banner--spacer 1 nil)) :scale) 1))
        (let* ((spacer (+my/banner--spacer 2 t))
               (image (get-text-property 0 'display spacer)))
          (should (equal (substring-no-properties spacer) " "))
          (should (eq (image-property image :type) 'xpm))
          (should (eq (image-property image :ascent) 100))
          ;; 1 pixel wide, transparent, a row per pixel.
          (should (string-search "\". c None\"" (image-property image :data)))
          (should (= (cl-count ?. (image-property image :data)) (1+ 35)))
          ;; Made once per height.
          (should (eq (+my/banner--spacer 2 t) spacer))
          (should (eq (+my/banner--spacer 1 nil) (+my/banner--spacer 2 t))))))
    ;; Never less than a pixel.
    (let ((+my/banner--spacers (make-hash-table :test #'equal)))
      (cl-letf (((symbol-function '+my/banner--row-height) (lambda (&rest _) 2))
                ((symbol-function '+my/banner--descent) (lambda (&rest _) 5)))
        (should (string-search "\"1 1 1 1\"" (image-property (get-text-property 0 'display (+my/banner--spacer 1 t))
                                                            :data)))))))

(ert-deftest banner/row-height-and-descent ()
  (cl-letf (((symbol-function 'window-font-height) (lambda (&rest _) 23)))
    (should (= (+my/banner--row-height) 23)))
  ;; No font height: the frame's line height.
  (cl-letf (((symbol-function 'window-font-height) (lambda (&rest _) (error "No font")))
            ((symbol-function 'frame-char-height) (lambda (&rest _) 17)))
    (should (= (+my/banner--row-height) 17)))
  ;; The descent of the header line's font; 0 without one (a terminal).
  (should (= (+my/banner--descent) 0))
  (cl-letf (((symbol-function 'face-font) (lambda (&rest _) "font"))
            ((symbol-function 'font-info) (lambda (&rest _) (vector 0 1 2 3 4 5 6 7 8 4))))
    (should (= (+my/banner--descent) 4))))

;; ====== THE NOTICES' FRAMES (GUI) ======

(ert-deftest banner/frame-per-window-showing-notices ()
  (+test-banner
    (+test-banner--gui
      (let* ((buffer (+test-buffer "B"))
             (main (selected-window))
             (other (split-window nil nil 'right))
             (third (split-window other nil 'below)))
        (set-window-buffer main buffer)
        (set-window-buffer other buffer)
        (set-window-buffer third (+test-buffer "C"))
        (with-current-buffer buffer
          (+my/banner-show 'a "First" :type 'warning)
          (+my/banner-show 'b "Second"))
        (should (= (length +test-banner--made) 2))
        (should (equal (sort (mapcar #'car +my/banner--frames)
                             (lambda (x y) (< (window-pixel-left x) (window-pixel-left y))))
                       (list main other)))
        (dolist (window (list main other))
          (let ((frame (+test-banner--frame-of window)))
            (should (+test-banner--frame-visible frame))
            (should (eq (+test-banner--frame-parent frame) (selected-frame)))
            ;; Its rows, top first.
            (should (equal (+test-banner--frame-text frame)
                           (+test-banner--text
                            (mapconcat (lambda (n) (+my/banner--row n buffer nil nil (window-pixel-width window)))
                                       (buffer-local-value '+my/banner--list buffer) "\n"))))
            ;; Its background: the first notice's colour.
            (should (equal (frame-parameter frame 'background-color)
                           (face-background '+my/banner-warning nil t)))))
        (should-not (+test-banner--frame-of third))))))

(ert-deftest banner/frame-over-the-header-line ()
  "Over the window's header line, under its tab line, as wide as its text
area (no divider, no scroll bar), a row per notice."
  (+test-banner
    (+test-banner--gui
      (let* ((buffer (+test-buffer "B"))
             (main (selected-window))
             (right (split-window nil nil 'right)))
        (set-window-buffer right buffer)
        (cl-letf (((symbol-function 'window-tab-line-height) (lambda (&rest _) 3))
                  ((symbol-function 'window-right-divider-width) (lambda (&rest _) 1))
                  ((symbol-function 'window-scroll-bar-width) (lambda (&rest _) 2)))
          (with-current-buffer buffer
            (+my/banner-show 'a "A")
            (+my/banner-show 'b "B")
            (+my/banner-show 'c "C")))
        (let ((frame (+test-banner--frame-of right))
              (edges (window-pixel-edges right)))
          (should (equal (+test-banner--frame-position frame) (list (nth 0 edges) (+ (nth 1 edges) 3))))
          (should (equal (+test-banner--frame-size frame)
                         (list (- (window-pixel-width right) 3) (* 3 20) t)))
          (should (equal (frame-parameter frame '+my/banner-geometry)
                         (list (nth 0 edges) (+ (nth 1 edges) 3) (- (window-pixel-width right) 3) 60))))
        (ignore main)))))

(ert-deftest banner/frame-rows-fit-the-columns ()
  "The rows are cut to the window's columns (its width over the font's)."
  (+test-banner
    (+test-banner--gui
      (let ((buffer (+test-buffer "B"))
            (columns nil))
        (switch-to-buffer buffer)
        (cl-letf (((symbol-function 'frame-char-width) (lambda (&rest _) 2))
                  ((symbol-function '+my/banner--row)
                   (lambda (_notice _buffer &optional _header _more width)
                     (setq columns width) "row")))
          (+my/banner-show 'a "A"))
        (should (= columns (/ (window-pixel-width) 2)))))))

(ert-deftest banner/frame-redrawn-only-when-needed ()
  "Same notices, theme, width: nothing redone; else its rows written again
and (moved or resized) laid out again."
  (+test-banner
    (+test-banner--gui
      (let ((buffer (+test-buffer "B")))
        (switch-to-buffer buffer)
        (with-current-buffer buffer (+my/banner-show 'a "A"))
        (let* ((frame (+test-banner--frame-of (selected-window)))
               (ticks (+test-banner--frame-ticks frame))
               (resized (+test-banner--frame-resized frame)))
          (+my/banner--sync)
          (+my/banner--sync)
          (should (= (+test-banner--frame-ticks frame) ticks))
          (should (= (+test-banner--frame-resized frame) resized))
          ;; A new notice: rows and size.
          (with-current-buffer buffer (+my/banner-show 'b "B"))
          (should (> (+test-banner--frame-ticks frame) ticks))
          (should (= (+test-banner--frame-resized frame) (1+ resized)))
          (should (equal (+test-banner--frame-text frame) (concat (+test-banner--text (+my/banner--row (car (buffer-local-value '+my/banner--list buffer)) buffer nil nil 80))
                                                                  "\n"
                                                                  (+test-banner--text (+my/banner--row (cadr (buffer-local-value '+my/banner--list buffer)) buffer nil nil 80)))))
          ;; A new theme: rows again, same place.
          (setq ticks (+test-banner--frame-ticks frame)
                resized (+test-banner--frame-resized frame))
          (let ((+my/banner--theme (1+ +my/banner--theme)))
            (+my/banner--sync))
          (should (> (+test-banner--frame-ticks frame) ticks))
          (should (= (+test-banner--frame-resized frame) resized))
          ;; Narrower: rows and size.
          (setq ticks (+test-banner--frame-ticks frame))
          (let ((new (split-window nil nil 'right)))
            (+my/banner--sync)
            (should (> (+test-banner--frame-ticks frame) ticks))
            (should (= (+test-banner--frame-resized frame) (1+ resized)))
            ;; Still its frame; the new window (on B too) has its own.
            (should (eq (+test-banner--frame-of (selected-window)) frame))
            (should (= (length +test-banner--made) 2))
            (should (eq (+test-banner--frame-of new) (car +test-banner--made)))))))))

(ert-deftest banner/frame-hidden-when-the-window-has-none ()
  "Another buffer in the window, or its notices closed: hidden, kept for later."
  (+test-banner
    (+test-banner--gui
      (let ((buffer (+test-buffer "B"))
            (window (selected-window)))
        (switch-to-buffer buffer)
        (with-current-buffer buffer (+my/banner-show 'a "A"))
        (let ((frame (+test-banner--frame-of window)))
          (switch-to-buffer (+test-buffer "C"))
          (+my/banner--sync)
          (should-not (+test-banner--frame-visible frame))
          (should (+test-banner--frame-live frame))
          (should (eq (+test-banner--frame-of window) frame))
          ;; Back: the same frame, shown.
          (switch-to-buffer buffer)
          (+my/banner--sync)
          (should (+test-banner--frame-visible frame))
          (should (= (length +test-banner--made) 1))
          ;; Closed.
          (with-current-buffer buffer (+my/banner-close))
          (should-not (+test-banner--frame-visible frame))
          (should (+test-banner--frame-live frame)))))))

(ert-deftest banner/frame-deleted-with-its-window ()
  (+test-banner
    (+test-banner--gui
      (let* ((buffer (+test-buffer "B"))
             (other (split-window nil nil 'right)))
        (set-window-buffer other buffer)
        (with-current-buffer buffer (+my/banner-show 'a "A"))
        (let* ((frame (+test-banner--frame-of other))
               (frame-buffer (+test-banner--frame-buffer frame)))
          (delete-window other)
          (+my/banner--sync)
          (should-not (+test-banner--frame-live frame))
          (should-not (buffer-live-p frame-buffer))
          (should-not (assq other +my/banner--frames)))))))

(ert-deftest banner/frame-made-again-if-it-died ()
  (+test-banner
    (+test-banner--gui
      (let ((buffer (+test-buffer "B")))
        (switch-to-buffer buffer)
        (with-current-buffer buffer (+my/banner-show 'a "A"))
        (let ((dead (+test-banner--frame-of (selected-window))))
          (setf (+test-banner--frame-live dead) nil)
          (+my/banner--sync)
          (let ((frame (+test-banner--frame-of (selected-window))))
            (should-not (eq frame dead))
            (should (+test-banner--frame-live frame))
            (should (+test-banner--frame-visible frame))
            (should (= (length +my/banner--frames) 1))))))))

(ert-deftest banner/frame-reinstalls-the-header-room ()
  "The header line set anew (by a mode) since: room made again."
  (+test-banner
    (+test-banner--gui
      (let ((buffer (+test-buffer "B")))
        (switch-to-buffer buffer)
        (with-current-buffer buffer
          (+my/banner-show 'a "A")
          (setq-local header-line-format "new"))
        (+my/banner--sync)
        (should (equal (buffer-local-value 'header-line-format buffer)
                       (list +my/banner--header "new")))))))

(ert-deftest banner/no-frames-in-a-terminal ()
  "A terminal's header line shows the notice: no frame, and frames of the
windows hidden."
  (+test-banner
    (let ((buffer (+test-buffer "B")))
      (switch-to-buffer buffer)
      (+test-banner--gui
        (with-current-buffer buffer (+my/banner-show 'a "A"))
        (let ((frame (+test-banner--frame-of (selected-window))))
          (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
            (+my/banner--sync)
            (should-not (+test-banner--frame-visible frame))
            (with-current-buffer buffer (+my/banner-show 'b "B"))
            (should (= (length +test-banner--made) 1))))))))

(ert-deftest banner/no-frames-for-child-or-hidden-frames ()
  (+test-banner
    (let ((buffer (+test-buffer "B"))
          (shown nil))
      (switch-to-buffer buffer)
      (with-current-buffer buffer (setq-local +my/banner--list '((a "A" nil info))))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                ((symbol-function '+my/banner--show-in) (lambda (window) (push window shown))))
        (+my/banner--sync)
        (should (equal shown (list (selected-window))))
        (setq shown nil)
        (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) 'parent)))
          (+my/banner--sync))
        (should-not shown)
        (cl-letf (((symbol-function 'frame-visible-p) (lambda (_) nil)))
          (+my/banner--sync))
        (should-not shown)))))

(ert-deftest banner/sync-error-in-one-window-leaves-the-others ()
  (+test-banner
    (let* ((buffer (+test-buffer "B"))
           (main (selected-window))
           (other (split-window nil nil 'right))
           (shown nil))
      (set-window-buffer main buffer)
      (set-window-buffer other buffer)
      (with-current-buffer buffer (setq-local +my/banner--list '((a "A" nil info))))
      (+test-clear-messages)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                ((symbol-function '+my/banner--show-in)
                 (lambda (window)
                   (if (eq window main) (error "Boom") (push window shown)))))
        (+my/banner--sync))
      (should (equal shown (list other)))
      (should (= (+test-messages "^Notices: Boom$") 1)))))

(ert-deftest banner/make-frame ()
  "A frame inside the parent, without borders, taking no focus, hidden until
laid out; its window shows a read-only buffer without any lines of its own."
  (+test-with-reset
    (let* ((parent (selected-frame))
           (window (split-window nil nil 'below))
           (got nil)
           (frame nil))
      (cl-letf (((symbol-function 'make-frame)
                 (lambda (parameters)
                   (setq got (list parameters after-make-frame-functions before-make-frame-hook))
                   'notices))
                ((symbol-function 'frame-root-window)
                 (lambda (&optional f) (if (eq f 'notices) window (frame-root-window f)))))
        (setq frame (+my/banner--make-frame parent)))
      (should (eq frame 'notices))
      (let ((parameters (car got)))
        (should (eq (alist-get 'parent-frame parameters) parent))
        (dolist (p '(no-accept-focus no-focus-on-map undecorated unsplittable no-other-frame
                     no-special-glyphs desktop-dont-save))
          (should (eq (alist-get p parameters) t)))
        (dolist (p '(border-width internal-border-width child-frame-border-width
                     left-fringe right-fringe menu-bar-lines tool-bar-lines tab-bar-lines
                     line-spacing min-width min-height))
          (should (eql (alist-get p parameters) 0)))
        (should (assq 'visibility parameters))
        (should-not (alist-get 'visibility parameters))
        (should (eq (alist-get 'minibuffer parameters) (minibuffer-window parent))))
      ;; Other code isn't told about the frame.
      (should-not (nth 1 got))
      (should-not (nth 2 got))
      (let ((buffer (window-buffer window)))
        (unwind-protect
            (progn
              (should (string-prefix-p " *+my/banner*" (buffer-name buffer)))
              (should (window-dedicated-p window))
              (dolist (p '(mode-line-format header-line-format tab-line-format))
                (should (eq (window-parameter window p) 'none)))
              (with-current-buffer buffer
                (should buffer-read-only)
                (should-not mode-line-format)
                (should-not header-line-format)
                (should-not cursor-type)
                (should truncate-lines)))
          (set-window-dedicated-p window nil)
          (kill-buffer buffer))))))

;; ====== SYNCING SOON ======

(ert-deftest banner/sync-soon-once ()
  "After this redisplay, once however often asked."
  (+test-banner
    (let ((syncs 0))
      (cl-letf (((symbol-function '+my/banner--sync) (lambda () (cl-incf syncs))))
        (+test-banner--cancel-sync)
        (+my/banner--sync-soon)
        (let ((timer +my/banner--sync-timer))
          (should (timerp timer))
          (+my/banner--sync-soon 'any 'args)
          (should (eq +my/banner--sync-timer timer)))
        (should (+test-wait-for (lambda () (null +my/banner--sync-timer)) 2))
        (should (= syncs 1))
        ;; And again later.
        (+my/banner--sync-soon)
        (should (+test-wait-for (lambda () (null +my/banner--sync-timer)) 2))
        (should (= syncs 2))))))

(ert-deftest banner/window-changes-sync ()
  (+test-banner
    (let ((asked 0))
      (cl-letf (((symbol-function '+my/banner--sync-soon) (lambda (&rest _) (cl-incf asked))))
        (+my/banner--window-change-h (selected-frame))
        (should (= asked 1))
        ;; Not the notices' own frames.
        (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) 'parent)))
          (+my/banner--window-change-h (selected-frame)))
        (should (= asked 1))))))

;; ====== THEME COLOURS ======

(ert-deftest banner/faces-tinted-by-the-theme ()
  "Each type's row: its theme colour blended into the background (20%)."
  (+test-banner
    (let ((blends nil)
          (theme +my/banner--theme)
          (synced 0))
      (unwind-protect
          (cl-letf (((symbol-function 'doom-color)
                     (lambda (colour) (alist-get colour '((blue . "#0000ff") (yellow . "#ffff00")
                                                          (red . "#ff0000")))))
                    ((symbol-function 'doom-blend)
                     (lambda (a b alpha) (push (list a b alpha) blends) "#123456"))
                    ((symbol-function 'face-background)
                     (lambda (face &rest _) (and (eq face 'default) "#282c34")))
                    ((symbol-function 'face-foreground)
                     (lambda (face &rest _) (and (eq face 'default) "#bbc2cf")))
                    ((symbol-function '+my/banner--sync-soon) (lambda (&rest _) (cl-incf synced))))
            (+my/banner-faces-h)
            (should (equal (reverse blends) '(("#0000ff" "#282c34" 0.2)
                                              ("#ffff00" "#282c34" 0.2)
                                              ("#ff0000" "#282c34" 0.2))))
            (dolist (face '(+my/banner-info +my/banner-warning +my/banner-error))
              (should (equal (face-attribute face :background t) "#123456"))
              (should (equal (face-attribute face :foreground t) "#bbc2cf"))
              (should (eq (face-attribute face :inherit t) 'header-line)))
            ;; The frames redrawn.
            (should (= +my/banner--theme (1+ theme)))
            (should (= synced 1)))
        (dolist (face '(+my/banner-info +my/banner-warning +my/banner-error))
          (set-face-attribute face nil :background 'unspecified :foreground 'unspecified))))))

(ert-deftest banner/faces-left-without-a-theme ()
  "No doom-themes, no colour background (a terminal's), or a colour missing."
  (+test-banner
    (let ((before (mapcar (lambda (f) (face-attribute f :background t))
                          '(+my/banner-info +my/banner-warning +my/banner-error)))
          (theme +my/banner--theme))
      (unwind-protect
          (cl-letf (((symbol-function '+my/banner--sync-soon) #'ignore))
            ;; No doom-themes.
            (cl-letf (((symbol-function 'doom-blend) nil)
                      ((symbol-function 'doom-color) nil))
              (+my/banner-faces-h))
            ;; A terminal's default background.
            (cl-letf (((symbol-function 'doom-blend) (lambda (&rest _) "#123456"))
                      ((symbol-function 'doom-color) (lambda (_) "#ff0000"))
                      ((symbol-function 'face-background) (lambda (&rest _) "unspecified-bg")))
              (+my/banner-faces-h))
            (should (equal (mapcar (lambda (f) (face-attribute f :background t))
                                   '(+my/banner-info +my/banner-warning +my/banner-error))
                           before))
            ;; One colour missing in the theme: that type left alone.
            (cl-letf (((symbol-function 'doom-blend) (lambda (&rest _) "#123456"))
                      ((symbol-function 'doom-color) (lambda (c) (unless (eq c 'red) "#ff0000")))
                      ((symbol-function 'face-background)
                       (lambda (face &rest _) (and (eq face 'default) "#282c34"))))
              (+my/banner-faces-h))
            (should (equal (face-attribute '+my/banner-info :background t) "#123456"))
            (should (equal (face-attribute '+my/banner-error :background t) (nth 2 before)))
            ;; Redrawn each time all the same.
            (should (= +my/banner--theme (+ theme 3))))
        (dolist (face '(+my/banner-info +my/banner-warning +my/banner-error))
          (set-face-attribute face nil :background 'unspecified :foreground 'unspecified))))))

;; ====== LOADED ======

(ert-deftest banner/config-el-loads-it ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (should (member '(load! "config/banner") forms)))))
