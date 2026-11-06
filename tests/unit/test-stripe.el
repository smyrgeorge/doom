;;; tests/unit/test-stripe.el -*- lexical-binding: t; -*-
;; config/stripe.el: the IntelliJ-like error stripe at the right edge of file
;; windows (flycheck errors, diff-hl's git changes, the band of the part on
;; screen), clicks on it, the scroll limit past the end, the filler row after
;; the last line and the cursor kept off the empty line there.
;;
;; Batch Emacs has a terminal frame: a pixel per row and column. The graphical
;; strip (images to the pixel) is drawn there too with `display-graphic-p'
;; mocked (see `+test-stripe--gui'): its pixels are then rows.

;; Flycheck's fringe bitmaps as stripe.el's `after!' redefines them, recorded
;; as flycheck loads (after the config, as in Doom).
(defvar +test-stripe--bitmaps nil
  "(NAME ARGS...) of the `define-fringe-bitmap' calls made as flycheck loaded.")

(+test-load "config/stripe")

(cl-letf* ((define (symbol-function 'define-fringe-bitmap))
           ((symbol-function 'define-fringe-bitmap)
            (lambda (bitmap &rest args)
              (push (cons bitmap args) +test-stripe--bitmaps)
              (apply define bitmap args))))
  (require 'flycheck))
(require 'diff-hl)

;; The marks' colours (faces have none in a batch frame).
(defconst +test-stripe--colors
  '((flycheck-fringe-error . "#ff0000")
    (flycheck-fringe-warning . "#ffff00")
    (diff-hl-delete . "#aa0000")
    (diff-hl-change . "#ff8800")
    (diff-hl-insert . "#00ff00")
    (flycheck-fringe-info . "#0000ff")))

(pcase-dolist (`(,face . ,color) +test-stripe--colors)
  (set-face-foreground face color))

;; ====== HELPERS ======

(defun +test-stripe--text (lines)
  "LINES lines \"line N\", each ending in a newline."
  (mapconcat (lambda (n) (format "line %d\n" n)) (number-sequence 1 lines) ""))

(defun +test-stripe--line-start (line)
  "Where LINE starts in the current buffer."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (forward-line (1- line))
      (point))))

(defun +test-stripe--clear (window)
  "Forget what earlier tests drew in WINDOW (the frame's first window is reused)."
  (dolist (parameter '(+my/stripe-key +my/stripe-geometry +my/stripe-row-cache
                       +my/stripe-filler))
    (set-window-parameter window parameter nil)))

(defmacro +test-stripe (content &rest body)
  "BODY in buffer \"stripe\" showing CONTENT (text-mode, `+my/stripe-mode' on)
in the only window, point at its start."
  (declare (indent 1))
  `(+test-with-reset
     (+test-stripe--clear (selected-window))
     (switch-to-buffer (+test-buffer "stripe" ,content #'text-mode))
     (+my/stripe-mode 1)
     ,@body))

(defmacro +test-stripe--gui (&rest body)
  "BODY as in a graphical frame (`display-graphic-p' says so; fonts stay the
batch frame's: one pixel per row and column)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
             ((symbol-function 'display-multi-font-p) #'ignore))
     ,@body))

(defun +test-stripe--errors (&rest specs)
  "Flycheck on in the current buffer, with errors SPECS: (LINE LEVEL)..."
  (setq-local flycheck-mode t)
  (setq-local flycheck-current-errors
              (mapcar (pcase-lambda (`(,line ,level))
                        (flycheck-error-new :buffer (current-buffer) :line line
                                            :column 1 :level level :message "msg"))
                      specs)))

(defun +test-stripe--hunk (first last type)
  "A diff-hl hunk overlay over lines FIRST..LAST, as diff-hl makes them (and
says it redrew)."
  (let ((ov (make-overlay (+test-stripe--line-start first)
                          (+test-stripe--line-start (1+ last)))))
    (overlay-put ov 'diff-hl t)
    (overlay-put ov 'diff-hl-hunk t)
    (overlay-put ov 'diff-hl-hunk-type type)
    (+my/stripe--after-diff-hl-a)
    ov))

(defun +test-stripe--sorted (marks)
  "MARKS by line, then kind."
  (sort (copy-sequence marks)
        (lambda (a b) (or (< (car a) (car b))
                          (and (= (car a) (car b))
                               (string< (symbol-name (nth 2 a)) (symbol-name (nth 2 b))))))))

(defun +test-stripe--row-overlays (&optional window)
  "WINDOW's row overlays, top to bottom."
  (let ((window (or window (selected-window))))
    (sort (seq-filter (lambda (ov) (and (overlay-get ov '+my/stripe-row)
                                        (eq (overlay-get ov 'window) window)))
                      (overlays-in (point-min) (point-max)))
          (lambda (a b) (< (overlay-start a) (overlay-start b))))))

(defun +test-stripe--margin (string)
  "What STRING (a row's before-string) shows in the right margin."
  (let ((display (get-text-property 0 'display string)))
    (should (equal (car display) '(margin right-margin)))
    (cadr display)))

(defun +test-stripe--cell-color (string)
  "The colour of the terminal cell that STRING (a row's string) shows."
  (plist-get (get-text-property 0 'face (+test-stripe--margin string)) :background))

(defun +test-stripe--cell-colors (rows)
  "The cells' colours of ROWS ((POSITION . STRING)...)."
  (mapcar (lambda (row) (+test-stripe--cell-color (cdr row))) rows))

(defun +test-stripe--color (kind)
  (cdr (assq (nth 2 (assq kind +my/stripe--kinds)) +test-stripe--colors)))

(defun +test-stripe--pixels (image)
  "IMAGE's pixel rows (an XPM of `+my/stripe--image') as a string of palette
characters, one per row."
  (let* ((lines (split-string (plist-get (cdr image) :data) "\n"))
         (header (split-string (substring (nth 2 lines) 1 -2)))
         (height (string-to-number (nth 1 header)))
         (colors (string-to-number (nth 2 header))))
    (mapconcat (lambda (line) (substring line 1 2))
               (seq-take (nthcdr (+ 3 colors) lines) height)
               "")))

(defun +test-stripe--strip (rows)
  "The strip shown by image ROWS ((POSITION . STRING)...), as (LINE . PIXELS)."
  (mapcar (lambda (row)
            (cons (line-number-at-pos (car row))
                  (+test-stripe--pixels (+test-stripe--margin (cdr row)))))
          rows))

(defun +test-stripe--click (window &optional string y)
  "A mouse-1 click on WINDOW's right margin, on STRING ((STRING . INDEX)), Y
pixels from the top of the text."
  `(mouse-1 (,window right-margin (0 . ,y) 0 ,string nil (0 . 0) nil (0 . 0) (1 . 1))))

;; ====== SETTINGS ======

(ert-deftest stripe/settings-defaults ()
  (should (equal (default-value '+my/stripe-diagnostic-levels) '(error warning)))
  (should (= (default-value '+my/stripe-mark-height) 4))
  (should (eql (default-value '+my/stripe-overscroll) 0.25))
  (should (eql (default-value '+my/stripe-padding) 1)))

(ert-deftest stripe/kinds-by-priority ()
  "error > warning > deleted > changed > added > info, each in its face."
  (should (equal (mapcar #'car (sort (copy-sequence +my/stripe--kinds)
                                     (lambda (a b) (> (cadr a) (cadr b)))))
                 '(error warning delete change insert info)))
  (should (equal (mapcar (lambda (kind) (nth 2 kind)) +my/stripe--kinds)
                 '(flycheck-fringe-error flycheck-fringe-warning diff-hl-delete
                   diff-hl-change diff-hl-insert flycheck-fringe-info))))

;; ====== MARKS ======

(ert-deftest stripe/level-by-severity ()
  "Flycheck levels by severity: 100 and up errors, 10 and up warnings, else info."
  (let ((err (lambda (level) (flycheck-error-new :line 1 :level level))))
    (should (eq (+my/stripe--level (funcall err 'error)) 'error))
    (should (eq (+my/stripe--level (funcall err 'warning)) 'warning))
    (should (eq (+my/stripe--level (funcall err 'info)) 'info))
    (pcase-dolist (`(,severity . ,kind) '((200 . error) (100 . error) (99 . warning)
                                          (10 . warning) (9 . info) (-50 . info)))
      (let ((level (intern (format "+test-stripe-level-%d" severity))))
        (put level 'flycheck-error-severity severity)
        (should (eq (+my/stripe--level (funcall err level)) kind))))
    ;; A level flycheck doesn't know: severity 0.
    (should (eq (+my/stripe--level (funcall err '+test-stripe-unknown)) 'info))))

(ert-deftest stripe/marks-empty-buffer ()
  (+test-stripe ""
    (should (equal (+my/stripe--marks) '(1)))))

(ert-deftest stripe/marks-count-lines ()
  "The empty line after a final newline counts: the end of the buffer is there."
  (+test-stripe "a\nb\n"
    (should (= (car (+my/stripe--marks)) 3)))
  (+test-stripe "a\nb"
    (should (= (car (+my/stripe--marks)) 2)))
  (+test-stripe "αβγ\n😀 ✓\n"
    (should (= (car (+my/stripe--marks)) 3))))

(ert-deftest stripe/marks-errors-and-warnings ()
  (+test-stripe (+test-stripe--text 20)
    (+test-stripe--errors '(3 error) '(7 warning) '(9 info) '(12 error))
    (should (equal (car (+my/stripe--marks)) 21))
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((3 3 error) (7 7 warning) (12 12 error))))))

(ert-deftest stripe/marks-info-only-when-asked ()
  (+test-stripe (+test-stripe--text 20)
    (let ((+my/stripe-diagnostic-levels '(error warning info)))
      (+test-stripe--errors '(3 error) '(9 info))
      (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                     '((3 3 error) (9 9 info))))))
  (+test-stripe (+test-stripe--text 20)
    (let ((+my/stripe-diagnostic-levels '(error)))
      (+test-stripe--errors '(3 error) '(5 warning))
      (should (equal (cdr (+my/stripe--marks)) '((3 3 error)))))))

(ert-deftest stripe/marks-skip-errors-without-a-line ()
  (+test-stripe (+test-stripe--text 5)
    (+test-stripe--errors '(nil error) '(2 warning))
    (should (equal (cdr (+my/stripe--marks)) '((2 2 warning))))))

(ert-deftest stripe/marks-no-errors-without-flycheck ()
  "Errors left in `flycheck-current-errors' don't show once flycheck is off."
  (+test-stripe (+test-stripe--text 5)
    (+test-stripe--errors '(2 error))
    (setq-local flycheck-mode nil)
    (should (equal (+my/stripe--marks) '(6)))))

(ert-deftest stripe/marks-git-hunks ()
  "diff-hl hunks: one line, several lines, a zero-length one; other overlays
(diff-hl's per-line ones, anyone's) left out."
  (+test-stripe (+test-stripe--text 20)
    (+test-stripe--hunk 2 2 'insert)
    (+test-stripe--hunk 4 6 'change)
    (let ((ov (make-overlay (+test-stripe--line-start 8) (+test-stripe--line-start 8))))
      (overlay-put ov 'diff-hl-hunk t)
      (overlay-put ov 'diff-hl-hunk-type 'delete))
    (overlay-put (make-overlay (+test-stripe--line-start 10) (+test-stripe--line-start 11))
                 'diff-hl t)
    (overlay-put (make-overlay (+test-stripe--line-start 12) (+test-stripe--line-start 13))
                 'face 'error)
    (+my/stripe--after-diff-hl-a)
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((2 2 insert) (4 6 change) (8 8 delete))))))

(ert-deftest stripe/marks-hunk-on-the-last-line-without-newline ()
  (+test-stripe "a\nb\nc"
    (let ((ov (make-overlay (+test-stripe--line-start 3) (point-max))))
      (overlay-put ov 'diff-hl-hunk t)
      (overlay-put ov 'diff-hl-hunk-type 'insert))
    (+my/stripe--after-diff-hl-a)
    (should (equal (+my/stripe--marks) '(3 (3 3 insert))))))

(ert-deftest stripe/marks-whole-buffer-when-narrowed ()
  (+test-stripe (+test-stripe--text 30)
    (+test-stripe--errors '(3 error))
    (+test-stripe--hunk 25 26 'change)
    (narrow-to-region (+test-stripe--line-start 10) (+test-stripe--line-start 15))
    (should (equal (car (+my/stripe--marks)) 31))
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((3 3 error) (25 26 change))))
    (should (= (point-min) (+test-stripe--line-start 10))))) ; still narrowed

(ert-deftest stripe/marks-cached ()
  "Cached until the text, the error list or diff-hl's highlights change."
  (+test-stripe (+test-stripe--text 10)
    (+test-stripe--errors '(3 error))
    (let ((marks (+my/stripe--marks)))
      (should (eq (+my/stripe--marks) marks))
      ;; A hunk alone isn't seen until diff-hl says it redrew.
      (let ((ov (make-overlay (+test-stripe--line-start 5) (+test-stripe--line-start 6))))
        (overlay-put ov 'diff-hl-hunk t)
        (overlay-put ov 'diff-hl-hunk-type 'insert))
      (should (eq (+my/stripe--marks) marks))
      (+my/stripe--after-diff-hl-a)
      (let ((marks2 (+my/stripe--marks)))
        (should-not (eq marks2 marks))
        (should (member '(5 5 insert) (cdr marks2)))
        ;; A new error list, even one alike, is new errors.
        (setq-local flycheck-current-errors (copy-sequence flycheck-current-errors))
        (let ((marks3 (+my/stripe--marks)))
          (should-not (eq marks3 marks2))
          (should (eq (+my/stripe--marks) marks3))
          ;; An edit.
          (goto-char (point-min))
          (insert "x")
          (should-not (eq (+my/stripe--marks) marks3)))))))

(defun +test-stripe--git (&rest args)
  "Run git with ARGS in `default-directory' (the user's git config left out)."
  (let ((process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
                                     process-environment)))
    (should (zerop (apply #'call-process "git" nil nil nil args)))))

(ert-deftest stripe/marks-git-changes-from-diff-hl ()
  "A file in a git repository, changed since its commit: diff-hl's hunks are the
marks (added, deleted, changed), and its redraws are noticed."
  (skip-unless (executable-find "git"))
  (+test-with-reset
    (let* ((dir (file-name-as-directory (+test-tmp-file "stripe-repo/")))
           (default-directory dir)
           (file (expand-file-name "notes.txt" dir))
           (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
                                        process-environment)))
      (with-temp-file file (insert (+test-stripe--text 10)))
      (+test-stripe--git "init" "-q")
      (+test-stripe--git "config" "user.email" "test@example.com")
      (+test-stripe--git "config" "user.name" "Test")
      (+test-stripe--git "config" "commit.gpgsign" "false")
      (+test-stripe--git "add" "notes.txt")
      (+test-stripe--git "commit" "-q" "-m" "notes")
      (with-temp-file file
        (insert "new top\n")
        (dolist (n '(1 2 3 4 6 7 8 9 10))       ; line 5 deleted
          (insert (format "line %d%s\n" n (if (= n 8) " changed" "")))))
      (find-file file)
      (should +my/stripe-mode)
      (let ((tick +my/stripe--diff-hl-tick)
            (diff-hl-update-async nil))
        (diff-hl-mode 1)
        (diff-hl-update)
        (should (> +my/stripe--diff-hl-tick tick)))
      (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                     '((1 1 insert) (6 6 delete) (8 8 change))))
      (should (= (car (+my/stripe--marks)) 11))
      (diff-hl-mode -1))))

;; ====== ROWS AND LINES ======

(ert-deftest stripe/line-to-row-short-file ()
  "A file no longer than the strip: a row per line."
  (should (= (+my/stripe--line-to-row 1 10 23) 0))
  (should (= (+my/stripe--line-to-row 5 10 23) 4))
  (should (= (+my/stripe--line-to-row 23 23 23) 22)))

(ert-deftest stripe/line-to-row-long-file ()
  "A longer file is scaled onto the rows; lines past the end on the last row."
  (should (= (+my/stripe--line-to-row 1 100 10) 0))
  (should (= (+my/stripe--line-to-row 10 100 10) 0))
  (should (= (+my/stripe--line-to-row 11 100 10) 1))
  (should (= (+my/stripe--line-to-row 50 100 10) 4))
  (should (= (+my/stripe--line-to-row 100 100 10) 9))
  (should (= (+my/stripe--line-to-row 150 100 10) 9)))

(ert-deftest stripe/row-to-line ()
  (should (= (+my/stripe--row-to-line 0 10 23) 1))
  (should (= (+my/stripe--row-to-line 9 10 23) 10))
  (should (= (+my/stripe--row-to-line 15 10 23) 10)) ; below the last line
  ;; Long files: the middle of the row's lines.
  (should (= (+my/stripe--row-to-line 0 100 10) 6))
  (should (= (+my/stripe--row-to-line 9 100 10) 96))
  (should (= (+my/stripe--row-to-line 20 100 10) 100))
  ;; Few lines a row: row 1 of 23 shows line 3 alone (lines 1 and 2 are on
  ;; row 0), so that's where its click goes.
  (should (= (+my/stripe--line-to-row 2 24 23) 0))
  (should (= (+my/stripe--line-to-row 3 24 23) 1))
  (should (= (+my/stripe--row-to-line 1 24 23) 3)))

(ert-deftest stripe/row-to-line-round-trip ()
  "A click on a row jumps to a line that row shows."
  (pcase-dolist (`(,lines . ,rows) '((101 . 23) (1000 . 23) (24 . 23) (61 . 23)
                                     (5000 . 47) (23 . 23) (7 . 23)))
    (dotimes (row (min rows lines))
      (let ((line (+my/stripe--row-to-line row lines rows)))
        (should (<= 1 line lines))
        (should (= (+my/stripe--line-to-row line lines rows) row))))))

;; ====== COLOURS ======

(defmacro +test-stripe--with-faces (colors &rest body)
  "BODY with the faces' colours COLORS ((FACE :fg COLOR :bg COLOR)...)."
  (declare (indent 1))
  `(let ((colors ,colors))
     (cl-letf (((symbol-function 'face-foreground)
                (lambda (face &rest _) (plist-get (alist-get face colors) :fg)))
               ((symbol-function 'face-background)
                (lambda (face &rest _) (plist-get (alist-get face colors) :bg))))
       ,@body)))

(ert-deftest stripe/band-color-blends-the-theme ()
  "The band: the background, 12% toward the text colour (Doom's `doom-blend')."
  (cl-letf (((symbol-function 'doom-blend)
             (lambda (a b alpha) (format "blend %s %s %s" a b alpha))))
    (+test-stripe--with-faces '((default :fg "#ffffff" :bg "#000000"))
      (should (equal (+my/stripe--thumb-color) "blend #ffffff #000000 0.12")))))

(ert-deftest stripe/band-color-without-hex-colours ()
  "Colours that can't be blended (a terminal's names, or no `doom-blend'): the
current line's background, else gray30."
  (require 'hl-line)
  (cl-letf (((symbol-function 'doom-blend) (lambda (&rest _) "blended")))
    (+test-stripe--with-faces '((default :fg "unspecified-fg" :bg "unspecified-bg")
                                (hl-line :bg "#222222"))
      (should (equal (+my/stripe--thumb-color) "#222222")))
    (+test-stripe--with-faces '((default :fg "white" :bg "#000000"))
      (should (equal (+my/stripe--thumb-color) "gray30"))))
  (cl-letf (((symbol-function 'doom-blend) nil))
    (+test-stripe--with-faces '((default :fg "#ffffff" :bg "#000000") (hl-line :bg "#333333"))
      (should (equal (+my/stripe--thumb-color) "#333333")))
    (+test-stripe--with-faces '((default :fg "#ffffff" :bg "#000000"))
      (should (equal (+my/stripe--thumb-color) "gray30")))))

(ert-deftest stripe/kind-colors ()
  "Each kind in its face's colour (the gutter's for git changes)."
  (dolist (kind '(error warning delete change insert info))
    (should (equal (+my/stripe--kind-color kind) (+test-stripe--color kind))))
  (should-not (+my/stripe--kind-color 'unknown))
  (let ((+my/stripe--kinds '((error 6 +test-stripe-no-such-face))))
    (should-not (+my/stripe--kind-color 'error))))

(ert-deftest stripe/palette ()
  "The images' colours by pixel character: blank, ?t the band, ?6..?1 the kinds
(None for a kind without a colour)."
  (should (equal (+my/stripe--palette)
                 `((?\s . "None") (?t . ,(+my/stripe--thumb-color))
                   (?6 . "#ff0000") (?5 . "#ffff00") (?4 . "#aa0000")
                   (?3 . "#ff8800") (?2 . "#00ff00") (?1 . "#0000ff"))))
  (cl-letf (((symbol-function '+my/stripe--kind-color) #'ignore))
    (should (equal (mapcar #'cdr (nthcdr 2 (+my/stripe--palette))) (make-list 6 "None")))))

;; ====== TERMINAL: CELLS ======

(ert-deftest stripe/cells-one-per-row-with-text ()
  "In a terminal a cell per row with text: the rows past the end keep `~'."
  (+test-stripe "a\nb\nc\n"
    (let ((rows (+my/stripe--cell-rows (selected-window) (point-min) 4 nil)))
      (should (equal (mapcar #'car rows) '(1 3 5 7)))
      (should (equal (+test-stripe--cell-colors rows) '(nil nil nil nil)))
      (should (equal (window-parameter nil '+my/stripe-geometry) '(cells 4 4))))))

(ert-deftest stripe/cells-fill-the-window ()
  (+test-stripe (+test-stripe--text 100)
    (let ((rows (+my/stripe--cell-rows (selected-window) (point-min) 101 nil)))
      (should (= (length rows) (window-body-height)))
      (should (equal (mapcar #'car rows)
                     (mapcar #'+test-stripe--line-start
                             (number-sequence 1 (window-body-height)))))
      (should (equal (window-parameter nil '+my/stripe-geometry)
                     (list 'cells (window-body-height) 101))))))

(ert-deftest stripe/cells-clickable ()
  "Each cell: its row, the click keymap (it wins over modes' margin keys), a
hand pointer and a hint."
  (+test-stripe (+test-stripe--text 30)
    (let ((rows (+my/stripe--cell-rows (selected-window) (point-min) 31 nil)))
      (cl-loop for (_pos . string) in rows
               for row from 0
               for cell = (+test-stripe--margin string)
               do (should (equal string " "))
               (should (= (get-text-property 0 '+my/stripe-row cell) row))
               (should (eq (get-text-property 0 'keymap cell) +my/stripe-margin-map))
               (should (eq (get-text-property 0 'pointer cell) 'hand))
               (should (equal (get-text-property 0 'help-echo cell)
                              "mouse-1: jump to this part of the file"))))))

(ert-deftest stripe/cells-show-marks-in-their-colours ()
  (+test-stripe "1\n2\n3\n4\n5\n6\n7\n8\n"
    (let* ((marks '((1 1 error) (2 2 warning) (3 3 delete) (4 4 change) (5 5 insert) (6 6 info)))
           (colors (+test-stripe--cell-colors
                    (+my/stripe--cell-rows (selected-window) (point-min) 9 marks))))
      (should (equal colors (append (mapcar #'+test-stripe--color
                                            '(error warning delete change insert info))
                                    '(nil nil nil)))))))

(ert-deftest stripe/cells-most-important-mark-wins ()
  "Overlapping marks: error > warning > deleted > changed > added > info, in
whatever order they come."
  (+test-stripe "1\n2\n3\n4\n5\n6\n"
    (dolist (marks '(((2 6 change) (4 4 error) (3 3 insert) (5 5 info) (6 6 delete))
                     ((6 6 delete) (5 5 info) (3 3 insert) (4 4 error) (2 6 change))))
      (should (equal (+test-stripe--cell-colors
                      (+my/stripe--cell-rows (selected-window) (point-min) 7 marks))
                     (list nil
                           (+test-stripe--color 'change)
                           (+test-stripe--color 'change)
                           (+test-stripe--color 'error)
                           (+test-stripe--color 'change)
                           (+test-stripe--color 'delete)
                           nil))))
    (should (equal (car (+test-stripe--cell-colors
                         (+my/stripe--cell-rows (selected-window) (point-min) 7
                                                '((1 1 warning) (1 1 delete)))))
                   (+test-stripe--color 'warning)))))

(ert-deftest stripe/cells-ignore-unknown-and-out-of-range-marks ()
  (+test-stripe "1\n2\n3\n"
    (should (equal (+test-stripe--cell-colors
                    (+my/stripe--cell-rows (selected-window) (point-min) 4
                                           '((2 2 bogus) (9 9 error))))
                   '(nil nil nil nil)))
    ;; A mark running past the end stops at the last line.
    (should (equal (+test-stripe--cell-colors
                    (+my/stripe--cell-rows (selected-window) (point-min) 4 '((3 50 insert))))
                   (list nil nil (+test-stripe--color 'insert) (+test-stripe--color 'insert))))))

(ert-deftest stripe/cells-long-file-scaled ()
  "A long file maps onto the rows: a mark lands on its line's row; a mark past
the end on the last row."
  (+test-stripe (+test-stripe--text 100)
    (let* ((rows (window-body-height))
           (colors (+test-stripe--cell-colors
                    (+my/stripe--cell-rows (selected-window) (point-min) 101
                                           '((50 50 error) (101 101 insert))))))
      (should (equal (nth (+my/stripe--line-to-row 50 101 rows) colors) "#ff0000"))
      (should (equal (car (last colors)) (+test-stripe--color 'insert)))
      (should (= (seq-count (lambda (c) (equal c "#ff0000")) colors) 1)))))

(ert-deftest stripe/cells-band-shows-the-lines-on-screen ()
  (+test-stripe (+test-stripe--text 100)
    (let* ((rows (window-body-height))
           (thumb (+my/stripe--thumb-color))
           (band (lambda (first last)
                   (cl-loop for row below rows
                            collect (and (<= (+my/stripe--line-to-row first 101 rows) row
                                             (+my/stripe--line-to-row last 101 rows))
                                         thumb)))))
      ;; At the top.
      (should (equal (+test-stripe--cell-colors
                      (+my/stripe--cell-rows (selected-window) (point-min) 101 nil))
                     (funcall band 1 rows)))
      ;; Scrolled to the middle.
      (let ((start (+test-stripe--line-start 51)))
        (should (equal (+test-stripe--cell-colors
                        (+my/stripe--cell-rows (selected-window) start 101 nil))
                       (funcall band 51 (+ 50 rows)))))
      ;; Marks show over the band.
      (should (equal (car (+test-stripe--cell-colors
                           (+my/stripe--cell-rows (selected-window) (point-min) 101
                                                  '((1 1 warning)))))
                     "#ffff00")))))

(ert-deftest stripe/cells-no-band-when-the-whole-file-fits ()
  (+test-stripe (+test-stripe--text 10)
    (should-not (delq nil (+test-stripe--cell-colors
                           (+my/stripe--cell-rows (selected-window) (point-min) 11 nil))))))

(ert-deftest stripe/cells-end-on-screen ()
  "With the end in view, the whole file maps onto the rows with text only."
  (+test-stripe (+test-stripe--text 100)
    (let* ((start (+test-stripe--line-start 90))
           (rows (+my/stripe--cell-rows (selected-window) start 101 '((100 100 error)))))
      (should (= (length rows) 12))           ; lines 90..100 and the last, empty one
      (should (equal (window-parameter nil '+my/stripe-geometry) '(cells 12 101)))
      (let ((colors (+test-stripe--cell-colors rows)))
        (should (equal (nth (+my/stripe--line-to-row 100 101 12) colors) "#ff0000"))
        (should (equal (nth (+my/stripe--line-to-row 90 101 12) colors)
                       (+my/stripe--thumb-color)))))))

(ert-deftest stripe/cells-band-with-wrapped-lines ()
  "The band ends at the line on the last row: wrapped lines take several rows."
  (+test-stripe (concat (make-string 300 ?x) "\n" (+test-stripe--text 40))
    (setq truncate-lines nil)
    (let* ((window-rows (window-body-height))
           (rows (+my/stripe--cell-rows (selected-window) (point-min) 42 nil))
           (last-line (line-number-at-pos (car (car (last rows)))))
           (thumb (+my/stripe--thumb-color))
           (colors (+test-stripe--cell-colors rows)))
      (should (= (length rows) window-rows))
      (should (< last-line window-rows))        ; the long line took rows
      (should (equal colors
                     (cl-loop for row below window-rows
                              collect (and (<= row (+my/stripe--line-to-row last-line 42 window-rows))
                                           thumb)))))))

;; ====== GRAPHICAL FRAMES: IMAGES ======

(ert-deftest stripe/image-xpm ()
  "A row's image: an XPM WIDTH wide, a pixel row per character, in the palette's
colours, on the text's middle line unless told otherwise."
  (let ((+my/stripe--images (make-hash-table :test #'equal))
        (+my/stripe--palette nil)
        (palette '((?\s . "None") (?t . "#111111") (?6 . "#ff0000"))))
    (let ((image (+my/stripe--image " t6" 3 palette)))
      (should (eq (car image) 'image))
      (should (eq (plist-get (cdr image) :type) 'xpm))
      (should (eq (plist-get (cdr image) :ascent) 'center))
      (should (eql (plist-get (cdr image) :scale) 1))
      (should (equal (plist-get (cdr image) :data)
                     (concat "/* XPM */\nstatic char *stripe[] = {\n"
                             "\"3 3 3 1\",\n\"  c None\",\n\"t c #111111\",\n\"6 c #ff0000\",\n"
                             "\"   \",\n\"ttt\",\n\"666\"};")))
      (should (equal (+test-stripe--pixels image) " t6")))
    (should (eql (plist-get (cdr (+my/stripe--image "6" 2 palette 80)) :ascent) 80))))

(ert-deftest stripe/images-cached ()
  "Rows that look alike share an image; a new palette (theme) starts afresh; at
most 3000 kept."
  (let ((+my/stripe--images (make-hash-table :test #'equal))
        (+my/stripe--palette nil)
        (palette '((?\s . "None") (?t . "#111111"))))
    (let ((image (+my/stripe--image "tt" 1 palette)))
      (should (eq (+my/stripe--image "tt" 1 palette) image))
      (should-not (eq (+my/stripe--image "tt" 2 palette) image))
      (should-not (eq (+my/stripe--image "tt" 1 palette 50) image))
      (should (= (hash-table-count +my/stripe--images) 3))
      ;; A new theme.
      (let ((new (+my/stripe--image "tt" 1 '((?\s . "None") (?t . "#222222")))))
        (should-not (eq new image))
        (should (= (hash-table-count +my/stripe--images) 1))
        (should (string-match-p "#222222" (plist-get (cdr new) :data)))))
    (clrhash +my/stripe--images)
    (setq +my/stripe--palette palette)
    (dotimes (i 3000) (puthash (list i) t +my/stripe--images))
    (+my/stripe--image "t" 1 palette)
    (should (= (hash-table-count +my/stripe--images) 1))))

(ert-deftest stripe/pixel-rank ()
  "Marks by priority, then the band, then nothing."
  (should (= (+my/stripe--pixel-rank ?\s) -1))
  (should (= (+my/stripe--pixel-rank ?t) 0))
  (should (= (+my/stripe--pixel-rank ?1) 1))
  (should (= (+my/stripe--pixel-rank ?6) 6))
  (should (< (+my/stripe--pixel-rank ?\s) (+my/stripe--pixel-rank ?t)
             (+my/stripe--pixel-rank ?1) (+my/stripe--pixel-rank ?2))))

(ert-deftest stripe/char-rise ()
  "How far a glyph rises above its font's ascent, cached; 0 when it can't tell."
  (let ((+my/stripe--rises (make-hash-table :test #'equal))
        (calls 0))
    (should (= (+my/stripe--char-rise 'no-font ?a) 0))
    (should (eql (gethash (cons 'no-font ?a) +my/stripe--rises) 0))
    (cl-letf (((symbol-function 'font-get-glyphs)
               (lambda (_font _from _to string)
                 (cl-incf calls)
                 (vector (pcase (aref string 0)
                           (?│ (vector 0 0 ?│ 0 10 0 10 18 4 nil)) ; ascent 18
                           (?a (vector 0 0 ?a 0 10 0 10 10 4 nil))
                           (_ nil)))))
              ((symbol-function 'query-font)
               (lambda (_font) (vector "font" nil 20 20 14 4 10 0 0 0 0))))
      (should (= (+my/stripe--char-rise 'font ?│) 4))
      (should (= (+my/stripe--char-rise 'font ?│) 4))
      (should (= calls 1))
      (should (= (+my/stripe--char-rise 'font ?a) 0)) ; below the ascent
      (should (= (+my/stripe--char-rise 'font ?z) 0))))) ; no glyph

(ert-deftest stripe/first-row-rise ()
  "The top row grows by the most any of its glyphs rises (display strings
included)."
  (+test-stripe "ab│c\nxyz\n"
    (cl-letf (((symbol-function 'font-at) (lambda (&rest _) 'font))
              ((symbol-function '+my/stripe--char-rise)
               (lambda (_font char) (pcase char (?│ 3) (?★ 5) (_ 0)))))
      (should (= (+my/stripe--first-row-rise (selected-window) 1 5) 3))
      (should (= (+my/stripe--first-row-rise (selected-window) 6 9) 0))
      (put-text-property 7 8 'display "★")
      (should (= (+my/stripe--first-row-rise (selected-window) 6 9) 5))
      ;; A display that isn't a string: the buffer's character.
      (put-text-property 7 8 'display '(space :width 2))
      (should (= (+my/stripe--first-row-rise (selected-window) 6 9) 0)))
    ;; No font (a terminal): nothing.
    (cl-letf (((symbol-function 'font-at) (lambda (&rest _) (error "No font"))))
      (should (= (+my/stripe--first-row-rise (selected-window) 1 5) 0)))))

(ert-deftest stripe/layout-signature ()
  "Overlays that can change the rows are counted, the stripe's own left out."
  (+test-stripe "one\ntwo\nthree\nfour\nfive\n"
    (should (= (+my/stripe--layout-signature) 0))
    (overlay-put (make-overlay 1 3) 'invisible t)
    (overlay-put (make-overlay 5 6) 'display "X")
    (overlay-put (make-overlay 9 9) 'before-string "B")
    (overlay-put (make-overlay 10 12) 'after-string "A")
    (overlay-put (make-overlay 15 18) 'face 'bold)
    (let ((ours (make-overlay 20 20)))
      (overlay-put ours '+my/stripe t)
      (overlay-put ours 'before-string "S"))
    (should (= (+my/stripe--layout-signature) 4))))

(ert-deftest stripe/rows-cache ()
  "Measured rows are kept per window until the text, width, font or folds change."
  (+test-stripe (+test-stripe--text 10)
    (let ((cache (+my/stripe--rows-cache (selected-window))))
      (should (hash-table-p cache))
      (should (eq (+my/stripe--rows-cache (selected-window)) cache))
      (should (eq (cdr (window-parameter nil '+my/stripe-row-cache)) cache))
      (overlay-put (make-overlay 1 5) 'invisible t)
      (let ((folded (+my/stripe--rows-cache (selected-window))))
        (should-not (eq folded cache))
        (insert "x")
        (should-not (eq (+my/stripe--rows-cache (selected-window)) folded))))))

(ert-deftest stripe/row-measures ()
  "A row: where the next starts (nil at the end) and how tall it is; cached."
  (+test-stripe "one\ntwo\nthree"
    (let ((cache (make-hash-table)))
      (should (equal (+my/stripe--row (selected-window) cache 1 0 1) '(5 . 1)))
      (should (equal (+my/stripe--row (selected-window) cache 5 0 1) '(9 . 1)))
      (should (equal (+my/stripe--row (selected-window) cache 9 0 1) '(nil . 1)))
      (should (eq (+my/stripe--row (selected-window) cache 1 0 1) (gethash 1 cache)))))
  ;; With a final newline the empty line after it is the last row.
  (+test-stripe "one\ntwo\n"
    (let ((cache (make-hash-table)))
      (should (equal (car (+my/stripe--row (selected-window) cache 5 0 1)) 9))
      (should (equal (car (+my/stripe--row (selected-window) cache 9 0 1)) nil))
      ;; Nothing measured (here: less than the offset): a line high.
      (should (equal (+my/stripe--row (selected-window) (make-hash-table) 1 5 7) '(5 . 7))))))

(ert-deftest stripe/row-last-line-before-the-filler ()
  "Without a final newline the filler after the end (it holds a line break)
isn't a row of its own."
  (+test-stripe "one\ntwo"
    (let ((ov (make-overlay (point-max) (point-max))))
      (overlay-put ov 'before-string "x\ny")
      (should (equal (car (+my/stripe--row (selected-window) (make-hash-table) 5 0 1)) nil)))))

(ert-deftest stripe/row-wrapped-line ()
  (+test-stripe (concat (make-string 200 ?x) "\nend\n")
    (setq truncate-lines nil)
    (let* ((cache (make-hash-table))
           (next (car (+my/stripe--row (selected-window) cache 1 0 1))))
      (should (< 1 next 200))
      (should (= next (save-excursion (goto-char 1) (vertical-motion 1) (point)))))))

(ert-deftest stripe/anchor ()
  "Strings hang at the start of rows that start a line, on the last character of
rows that continue a wrapped one, at the end on the last row."
  (+test-stripe (concat (make-string 200 ?x) "\nend\n")
    (setq truncate-lines nil)
    (let* ((window (selected-window))
           (starts (save-excursion
                     (goto-char (point-min))
                     (let (starts)
                       (while (progn (push (point) starts)
                                     (= (vertical-motion 1) 1)))
                       (nreverse starts))))
           (end-line (+test-stripe--line-start 2)))
      (should (> (length starts) 3))            ; the long line wraps
      (should (= (+my/stripe--anchor window (point-min)) (point-min)))
      (should (= (+my/stripe--anchor window end-line) end-line))
      ;; The second row: on its last character.
      (should (= (+my/stripe--anchor window (nth 1 starts)) (1- (nth 2 starts))))
      ;; The last row of the long line: on its newline.
      (let ((last-row (car (last (seq-filter (lambda (p) (< p end-line)) starts)))))
        (should (= (+my/stripe--anchor window last-row) (1- end-line))))
      ;; A one-character row: its start. (Measured rows come from the cache.)
      (puthash (nth 1 starts) (cons (1+ (nth 1 starts)) 1) (+my/stripe--rows-cache window))
      (should (= (+my/stripe--anchor window (nth 1 starts)) (nth 1 starts)))))
  (+test-stripe (make-string 200 ?x)
    (setq truncate-lines nil)
    (let ((second (save-excursion (goto-char 1) (vertical-motion 1) (point)))
          (third (save-excursion (goto-char 1) (vertical-motion 2) (point))))
      (should (= (+my/stripe--anchor (selected-window) third) (point-max)))
      (should (= (+my/stripe--anchor (selected-window) second) (1- third))))))

(ert-deftest stripe/image-rows-band-and-marks ()
  "The strip spans the window, mapping the file plus the allowed overscroll
onto it: the band at the top, the error at its place, marks at least
`+my/stripe-mark-height' pixels tall; rows with nothing get no image."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--gui
      (let* ((window (selected-window))
             (body (window-body-height window t))
             (overscroll (- (window-body-height window) (+my/stripe--text-rows-wanted window)))
             (scale (/ (float body) (+ 101 overscroll)))
             (result (+my/stripe--image-rows window (point-min) 101 '((50 50 error))))
             (error-top (floor (* scale 49))))
        (should (= overscroll 5))
        (should (equal (window-parameter window '+my/stripe-geometry) (list 'pixels scale 101)))
        (should-not (cdr result))               ; no filler: the end isn't in view
        (should (equal (+test-stripe--strip (car result))
                       (append (mapcar (lambda (line) (cons line "t"))
                                       (number-sequence 1 (round (* scale body))))
                               (mapcar (lambda (line) (cons line "6"))
                                       (number-sequence (1+ error-top) (+ error-top 4))))))
        ;; Clickable, like the cells.
        (let ((string (cdr (car (car result)))))
          (should (eq (get-text-property 0 'keymap string) +my/stripe-margin-map))
          (should (eq (get-text-property 0 'pointer string) 'hand)))
        ;; A taller minimum.
        (let ((+my/stripe-mark-height 6))
          (should (= (seq-count (lambda (row) (equal (cdr row) "6"))
                                (+test-stripe--strip
                                 (car (+my/stripe--image-rows window (point-min) 101
                                                              '((50 50 error))))))
                     6)))))))

(ert-deftest stripe/image-rows-priority ()
  "Overlapping marks: the most important wins; the band never hides a mark."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--gui
      (let* ((strip (+test-stripe--strip
                     (car (+my/stripe--image-rows (selected-window) (point-min) 101
                                                  '((1 1 insert)
                                                    (40 40 info) (40 40 change)
                                                    (80 80 warning) (80 80 error))))))
             (pixels (mapcar #'cdr strip)))
        (should (equal (seq-take pixels 4) '("2" "2" "2" "2"))) ; over the band
        (should (member "t" pixels))
        (should (member "3" pixels))
        (should (member "6" pixels))
        (should-not (member "1" pixels))
        (should-not (member "5" pixels))))))

(ert-deftest stripe/image-rows-short-file ()
  "A file shorter than the window: a line height per line, no band; below the
last line the rest of the strip is on the filler."
  (+test-stripe "a\nb\nc\nd\ne\n"
    (+test-stripe--gui
      (let* ((result (+my/stripe--image-rows (selected-window) (point-min) 6 '((3 3 error))))
             (filler (cdr result)))
        (should (equal (window-parameter nil '+my/stripe-geometry) '(pixels 1.0 6)))
        ;; Lines 3..5 (the 4-pixel mark goes on below the text).
        (should (equal (+test-stripe--strip (car result)) '((3 . "6") (4 . "6") (5 . "6"))))
        (should (stringp filler))
        ;; The filler takes the place of the empty last line: no line break, and
        ;; the strip's rest (the mark's last pixel) in its margin.
        (should-not (string-search "\n" filler))
        (let ((image (+test-stripe--filler-image filler)))
          (should (string-prefix-p "6" (+test-stripe--pixels image))))))))

(defun +test-stripe--filler-image (filler)
  "The image in FILLER's margin, or nil."
  (cl-loop for i below (length filler)
           for display = (get-text-property i 'display filler)
           when (equal (car-safe display) '(margin right-margin))
           return (cadr display)))

(ert-deftest stripe/image-rows-end-in-view ()
  "Scrolled to the end: the marks stay where they were, the band reaches the
bottom, and the strip below the last line is on the filler."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--gui
      (let* ((window (selected-window))
             (top (+my/stripe--image-rows window (point-min) 101 '((50 50 error))))
             (start (+test-stripe--line-start 86))
             (end (+my/stripe--image-rows window start 101 '((50 50 error) (100 100 warning))))
             (error-rows (lambda (strip first)
                           (mapcar (lambda (row) (- (car row) first))
                                   (seq-filter (lambda (row) (equal (cdr row) "6")) strip)))))
        ;; The error is on the same screen rows.
        (should (equal (funcall error-rows (+test-stripe--strip (car top)) 1)
                       (funcall error-rows (+test-stripe--strip (car end)) 86)))
        ;; Below the text (lines 86..100, then the empty one): the filler, with
        ;; the band down to the bottom and the warning over it.
        (let* ((filler (cdr end))
               (pixels (+test-stripe--pixels (+test-stripe--filler-image filler))))
          (should (= (length pixels) (- (window-body-height window t) 15)))
          (should (string-suffix-p "5" pixels))
          (should (string-match-p "t5+\\'" pixels)))))))

(ert-deftest stripe/image-rows-without-final-newline ()
  "No final newline: the filler starts after the last line (a line break), the
cursor stays on that line."
  (+test-stripe "a\nb\nc"
    (+test-stripe--gui
      (let ((filler (cdr (+my/stripe--image-rows (selected-window) (point-min) 3 nil))))
        (should (stringp filler))
        (should (string-search "\n" filler))
        (should (get-text-property 0 'cursor filler))))))

(ert-deftest stripe/image-rows-overscroll-setting ()
  "The strip maps the file plus the allowed empty space past its end."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--gui
      (let ((window (selected-window)))
        (dolist (case `((0 . 0) (3 . 3) (t . ,(1- (window-body-height window)))
                        (0.5 . ,(floor (* 0.5 (window-body-height window))))))
          (let ((+my/stripe-overscroll (car case)))
            (+my/stripe--image-rows window (point-min) 101 nil)
            (should (equal (window-parameter window '+my/stripe-geometry)
                           (list 'pixels (/ (float (window-body-height window t))
                                            (+ 101 (cdr case)))
                                 101)))))))))

(ert-deftest stripe/tilde ()
  "The empty-line `~' as a fringe bitmap repeating every PERIOD pixels: only
with `indicate-empty-lines' and vi-tilde-fringe's bitmap."
  (let ((indicate-empty-lines nil))
    (should-not (+my/stripe--tilde 10)))
  (let ((indicate-empty-lines t))
    (unless (boundp 'vi-tilde-fringe-bitmap-array)
      (should-not (+my/stripe--tilde 10)))
    (let (defined)
      (cl-letf* ((define (symbol-function 'define-fringe-bitmap))
                 ((symbol-function 'define-fringe-bitmap)
                  (lambda (&rest args) (push args defined) (apply define args))))
        (cl-progv '(vi-tilde-fringe-bitmap-array) (list [1 2 3 4])
          (should (eq (+my/stripe--tilde 10) '+my/stripe--tilde-10))
          (should (equal (car defined)
                         '(+my/stripe--tilde-10 [0 0 0 1 2 3 4 0 0 0] 10 8 (top t))))
          (should (fringe-bitmap-p '+my/stripe--tilde-10))
          ;; Defined once.
          (should (eq (+my/stripe--tilde 10) '+my/stripe--tilde-10))
          (should (= (length defined) 1))
          ;; Rows shorter than the `~': its middle.
          (should (eq (+my/stripe--tilde 2) '+my/stripe--tilde-2))
          (should (equal (cadr (car defined)) [2 3])))))))

(ert-deftest stripe/filler ()
  "The filler: the cursor's place, a row the rest of the window high, the `~',
the strip's rest in the margin (clickable)."
  (let* ((palette '((?\s . "None") (?t . "#111111")))
         (click (list 'keymap +my/stripe-margin-map 'pointer 'hand))
         (indicate-empty-lines nil))
    ;; After the last line: a line break first, the row's baseline at its bottom.
    (let ((filler (+my/stripe--filler "  tt" 8 1 palette 1 click)))
      (should (get-text-property 0 'cursor filler))
      (should (equal (substring-no-properties filler 1 2) "\n"))
      (should (equal (get-text-property 2 'display filler)
                     '(space :width (1) :height (8) :ascent 100)))
      (let ((image (+test-stripe--filler-image filler)))
        (should (equal (+test-stripe--pixels image) "  tt"))
        (should (eql (plist-get (cdr image) :ascent) 100)))
      (should (eq (get-text-property (1- (length filler)) 'keymap filler) +my/stripe-margin-map)))
    ;; In place of the empty last line: baseline ASCENT pixels down.
    (let ((filler (+my/stripe--filler "t" 20 1 palette 1 click 4)))
      (should-not (string-search "\n" filler))
      (should (equal (get-text-property 1 'display filler)
                     '(space :width (1) :height (20) :ascent 20)))
      (should (eql (plist-get (cdr (+test-stripe--filler-image filler)) :ascent) 20)))
    (should (equal (nth 6 (get-text-property 1 'display (+my/stripe--filler "t" 8 1 palette 1 click 14)))
                   100))
    (should (equal (nth 6 (get-text-property 1 'display (+my/stripe--filler "t" 8 1 palette 1 click -3)))
                   1))
    ;; Nothing to show: no image.
    (should-not (+test-stripe--filler-image (+my/stripe--filler "    " 8 1 palette 1 click)))
    ;; The `~', in the fringe face.
    (cl-letf (((symbol-function '+my/stripe--tilde) (lambda (_) 'tilde-bitmap)))
      (let ((filler (+my/stripe--filler "  " 8 1 palette 1 click)))
        (should (cl-loop for i below (length filler)
                         thereis (equal (get-text-property i 'display filler)
                                        '(left-fringe tilde-bitmap fringe))))))))

;; ====== DRAWING ======

(ert-deftest stripe/key ()
  "What a window's strip depends on: buffer, start, vscroll, size, font,
margin, errors, git highlights, line edits."
  (+test-stripe (+test-stripe--text 50)
    (+test-stripe--errors '(3 error))
    (let ((window (selected-window)))
      (should (equal (+my/stripe--key window)
                     (list (current-buffer) (window-start window) 0
                           (window-body-height window t) (window-font-height window)
                           1 flycheck-current-errors +my/stripe--diff-hl-tick
                           +my/stripe--line-edits)))
      (should (= (nth 1 (+my/stripe--key window 42)) 42)))))

(ert-deftest stripe/render-terminal ()
  "Drawn as row overlays (one per row, its cell in the margin)."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--errors '(50 error))
    (+my/stripe--render (selected-window))
    (let ((overlays (+test-stripe--row-overlays)))
      (should (= (length overlays) (window-body-height)))
      (should (equal (mapcar #'overlay-start overlays)
                     (mapcar #'+test-stripe--line-start (number-sequence 1 (window-body-height)))))
      (dolist (ov overlays)
        (should (overlay-get ov '+my/stripe))
        (should (= (overlay-start ov) (overlay-end ov))))
      (should (equal (+test-stripe--cell-color
                      (overlay-get (nth (+my/stripe--line-to-row 50 101 (window-body-height)) overlays)
                                   'before-string))
                     "#ff0000")))
    (should (equal (window-parameter nil '+my/stripe-key) (+my/stripe--key (selected-window))))
    (should (equal (window-parameter nil '+my/stripe-geometry) (list 'cells (window-body-height) 101)))
    (should-not (window-parameter nil '+my/stripe-filler))))

(ert-deftest stripe/render-reuses-its-overlays ()
  (+test-stripe (+test-stripe--text 100)
    (+my/stripe--render (selected-window))
    (let ((overlays (+test-stripe--row-overlays)))
      (+my/stripe--render (selected-window))
      (should (seq-set-equal-p (+test-stripe--row-overlays) overlays #'eq))
      ;; Fewer rows (the end in view): the rest go.
      (set-window-start nil (+test-stripe--line-start 95))
      (+my/stripe--render (selected-window))
      (should (= (length (+test-stripe--row-overlays)) 7))
      (should (= (seq-count (lambda (ov) (overlay-get ov '+my/stripe-row))
                            (overlays-in (point-min) (point-max)))
                 7))
      (should (memq (car (+test-stripe--row-overlays)) overlays)))))

(ert-deftest stripe/render-start-given ()
  "Drawn from START (window-scroll-functions say where the window will start)."
  (+test-stripe (+test-stripe--text 100)
    (+my/stripe--render (selected-window) (+test-stripe--line-start 30))
    (should (= (overlay-start (car (+test-stripe--row-overlays))) (+test-stripe--line-start 30)))
    (should (= (nth 1 (window-parameter nil '+my/stripe-key)) (+test-stripe--line-start 30)))))

(ert-deftest stripe/render-per-window ()
  "Each window showing the buffer has its strip; a window that no longer shows
it (or is gone) loses its."
  (+test-stripe (+test-stripe--text 100)
    (let* ((top (selected-window))
           (bottom (split-window top nil 'below)))
      (+test-stripe--clear bottom)
      (+my/stripe--render top)
      (+my/stripe--render bottom)
      (should (= (length (+test-stripe--row-overlays top)) (window-body-height top)))
      (should (= (length (+test-stripe--row-overlays bottom)) (window-body-height bottom)))
      ;; The bottom window shows another buffer now.
      (set-window-buffer bottom (+test-buffer "other" "x\n"))
      (+my/stripe--render top)
      (should-not (+test-stripe--row-overlays bottom))
      (should (+test-stripe--row-overlays top))
      ;; ...or is gone.
      (set-window-buffer bottom (get-buffer "stripe"))
      (+my/stripe--render bottom)
      (should (+test-stripe--row-overlays bottom))
      (delete-window bottom)
      (+my/stripe--render top)
      (should-not (seq-find (lambda (ov) (and (overlay-get ov '+my/stripe-row)
                                              (not (eq (overlay-get ov 'window) top))))
                            (overlays-in (point-min) (point-max)))))))

(ert-deftest stripe/render-only-in-stripe-mode ()
  (+test-with-reset
    (+test-stripe--clear (selected-window))
    (switch-to-buffer (+test-buffer "plain" (+test-stripe--text 10) #'text-mode))
    (+my/stripe--render (selected-window))
    (should-not (overlays-in (point-min) (point-max)))
    (should-not (window-parameter nil '+my/stripe-key))))

(ert-deftest stripe/render-dead-window ()
  (+test-stripe (+test-stripe--text 10)
    (let ((window (split-window)))
      (delete-window window)
      (should-not (+my/stripe--render window)))))

(ert-deftest stripe/render-never-signals ()
  "It runs from redisplay hooks: errors become messages."
  (+test-stripe (+test-stripe--text 10)
    (+test-clear-messages)
    (cl-letf (((symbol-function '+my/stripe--marks) (lambda () (error "Boom"))))
      (let ((debug-on-error nil))
        (+my/stripe--render (selected-window))))
    (should (= (+test-messages "^Stripe: (error \"Boom\")") 1))))

(ert-deftest stripe/render-graphical ()
  "In a graphical frame: images on the rows that show something, the fringes
padded, and the filler once the end is in view."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--errors '(50 error))
    (+test-stripe--gui
      (+my/stripe--render (selected-window))
      (should (local-variable-p 'left-fringe-width))
      (should (= left-fringe-width (+ 8 (frame-char-width))))
      (let ((overlays (+test-stripe--row-overlays)))
        (should (< 0 (length overlays) (window-body-height)))
        (dolist (ov overlays)
          (should (eq (car (+test-stripe--margin (overlay-get ov 'before-string))) 'image))))
      (should-not (window-parameter nil '+my/stripe-filler))
      ;; The end in view: the filler, after the last line, for this window only.
      (set-window-start nil (+test-stripe--line-start 90))
      (+my/stripe--render (selected-window))
      (let ((filler (window-parameter nil '+my/stripe-filler)))
        (should (overlayp filler))
        (should (= (overlay-start filler) (point-max)))
        (should (eq (overlay-get filler 'window) (selected-window)))
        (should (stringp (overlay-get filler 'before-string))))
      ;; Back at the top: no filler.
      (set-window-start nil 1)
      (+my/stripe--render (selected-window))
      (should-not (window-parameter nil '+my/stripe-filler)))))

(ert-deftest stripe/render-graphical-pads-once ()
  (+test-stripe (+test-stripe--text 10)
    (let ((pads 0))
      (cl-letf* ((pad (symbol-function '+my/stripe--pad))
                 ((symbol-function '+my/stripe--pad)
                  (lambda (&rest args) (cl-incf pads) (apply pad args))))
        (+test-stripe--gui
          (+my/stripe--render (selected-window))
          (+my/stripe--render (selected-window))
          (should (= pads 1))
          ;; Not with `+my/stripe-padding' nil.
          (kill-local-variable 'left-fringe-width)
          (let ((+my/stripe-padding nil))
            (+my/stripe--render (selected-window)))
          (should (= pads 1)))))))

(ert-deftest stripe/pre-redisplay-redraws-what-changed ()
  "Before each redisplay: redrawn when what the strip shows changed (scrolled,
errors, lines added or removed), not otherwise (edits within a line)."
  (+test-stripe (+test-stripe--text 100)
    (let ((renders 0))
      (cl-letf* ((render (symbol-function '+my/stripe--render))
                 ((symbol-function '+my/stripe--render)
                  (lambda (&rest args) (cl-incf renders) (apply render args))))
        ;; Not drawn yet (turning the mode on drew it: forget that).
        (set-window-parameter nil '+my/stripe-key nil)
        (remove-overlays (point-min) (point-max) '+my/stripe-row t)
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 1))
        (should (+test-stripe--row-overlays))
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 1))
        ;; An edit within a line.
        (goto-char (+test-stripe--line-start 3))
        (insert "abc")
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 1))
        ;; A line added.
        (insert "\n")
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 2))
        ;; Scrolled.
        (set-window-start nil (+test-stripe--line-start 10))
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 3))
        ;; New errors.
        (+test-stripe--errors '(5 error))
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 4))
        ;; Git highlights redrawn.
        (+my/stripe--after-diff-hl-a)
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 5))
        ;; Not a window (all windows), or not a stripe buffer.
        (+my/stripe--pre-redisplay t)
        (+my/stripe-mode -1)
        (set-window-parameter nil '+my/stripe-key nil)
        (+my/stripe--pre-redisplay (selected-window))
        (should (= renders 5))))))

(ert-deftest stripe/pre-redisplay-holds-the-scroll-limit ()
  (+test-stripe (+test-stripe--text 100)
    (set-window-start nil (+test-stripe--line-start 99))
    (+my/stripe--pre-redisplay (selected-window))
    (should (= (window-start) (car (+my/stripe--end-limit (selected-window)))))
    (should (= (overlay-start (car (+test-stripe--row-overlays))) (window-start)))))

(ert-deftest stripe/scrolled-redraws-only-once-drawn ()
  "Redisplay's own scrolls redraw; not when the window was just given the buffer."
  (+test-stripe (+test-stripe--text 50)
    (let (renders)
      (cl-letf (((symbol-function '+my/stripe--render)
                 (lambda (window start) (push (cons window start) renders))))
        (set-window-parameter nil '+my/stripe-key nil)
        (+my/stripe--scrolled (selected-window) 10)
        (should-not renders)
        (set-window-parameter nil '+my/stripe-key (list (+test-buffer "other")))
        (+my/stripe--scrolled (selected-window) 10)
        (should-not renders)
        (set-window-parameter nil '+my/stripe-key (list (current-buffer)))
        (+my/stripe--scrolled (selected-window) 10)
        (should (equal renders (list (cons (selected-window) 10))))))))

(ert-deftest stripe/line-edits-counted ()
  "Edits that add or remove line breaks are counted (they move the strip's
strings); others aren't."
  (+test-stripe "one\ntwo\nthree\n"
    (let ((count (lambda () +my/stripe--line-edits)))
      (should (= (funcall count) 0))
      (+my/stripe--note-line-edit 1 1)
      (+my/stripe--note-line-edit 1 4)
      (should (= (funcall count) 0))
      (+my/stripe--note-line-edit 1 6 0)
      (should (= (funcall count) 1))
      ;; Through edits.
      (goto-char 2)
      (insert "x")
      (should (= (funcall count) 1))
      (insert "\n")                             ; added
      (should (= (funcall count) 2))
      (delete-region 1 3)                       ; within a line
      (should (= (funcall count) 2))
      (delete-region 1 (+test-stripe--line-start 3)) ; removed
      (should (= (funcall count) 3))
      (goto-char (point-min))
      (insert "a\nb")
      (should (= (funcall count) 4)))))

(ert-deftest stripe/render-all ()
  "Every window redrawn (e.g. after a theme change)."
  (+test-stripe (+test-stripe--text 10)
    (let ((other (split-window))
          rendered)
      (cl-letf (((symbol-function '+my/stripe--render) (lambda (window) (push window rendered))))
        (+my/stripe--render-all))
      (should (memq other rendered))
      (should (memq (selected-window) rendered)))))

(ert-deftest stripe/filler-overlay ()
  "The filler hangs after the end of the buffer, in its window, after text typed
at the end; taken out while rows are measured."
  (+test-stripe "one\ntwo\n"
    (let ((window (selected-window)))
      (+my/stripe--set-filler window "FILLER")
      (let ((ov (window-parameter window '+my/stripe-filler)))
        (should (overlayp ov))
        (should (= (overlay-start ov) (point-max)))
        (should (equal (overlay-get ov 'before-string) "FILLER"))
        (should (= (overlay-get ov 'priority) 100))
        (should (eq (overlay-get ov 'window) window))
        (should (overlay-get ov '+my/stripe))
        ;; Text typed at the end goes before it.
        (goto-char (point-max))
        (insert "three")
        (should (= (overlay-start ov) (point-max)))
        ;; Set again: the same overlay, at the (new) end.
        (delete-region 5 (point-max))
        (+my/stripe--set-filler window "AGAIN")
        (should (eq (window-parameter window '+my/stripe-filler) ov))
        (should (= (overlay-start ov) (point-max)))
        (should (equal (overlay-get ov 'before-string) "AGAIN"))
        ;; Hidden.
        (+my/stripe--hide-filler window)
        (should-not (overlay-get ov 'before-string))
        (should (overlay-buffer ov))
        ;; Removed.
        (+my/stripe--set-filler window nil)
        (should-not (overlay-buffer ov))
        (should-not (window-parameter window '+my/stripe-filler))
        (+my/stripe--hide-filler window)       ; nothing to hide
        (+my/stripe--set-filler window nil)))))

(ert-deftest stripe/filler-overlay-of-another-buffer ()
  "The window now shows another buffer: its filler moves there."
  (+test-stripe "one\n"
    (let ((window (selected-window)))
      (+my/stripe--set-filler window "OLD")
      (let ((old (window-parameter window '+my/stripe-filler)))
        (with-current-buffer (+test-buffer "other" "two\nthree\n")
          (+my/stripe--set-filler window "NEW")
          (let ((new (window-parameter window '+my/stripe-filler)))
            (should-not (eq new old))
            (should-not (overlay-buffer old))
            (should (eq (overlay-buffer new) (current-buffer)))))))))

(ert-deftest stripe/plain-last-line-number ()
  "With the cursor on the last line (the filler's), its line number keeps the
plain face."
  (+test-stripe "one\ntwo\n"
    (setq-local display-line-numbers t)
    (+my/stripe--set-filler (selected-window) "FILLER")
    (let ((remapped (lambda () (assq 'line-number-current-line face-remapping-alist))))
      (goto-char 1)
      (+my/stripe--plain-last-number)
      (should-not +my/stripe--number-cookie)
      (goto-char (point-max))
      (+my/stripe--plain-last-number)
      (should +my/stripe--number-cookie)
      (should (funcall remapped))
      (+my/stripe--plain-last-number)           ; once
      (should (= (seq-count (lambda (e) (eq (car e) 'line-number-current-line))
                            face-remapping-alist)
                 1))
      (goto-char 1)
      (+my/stripe--plain-last-number)
      (should-not +my/stripe--number-cookie)
      (should-not (funcall remapped))
      ;; No line numbers, or no filler: nothing.
      (goto-char (point-max))
      (setq-local display-line-numbers nil)
      (+my/stripe--plain-last-number)
      (should-not +my/stripe--number-cookie)
      (setq-local display-line-numbers t)
      (+my/stripe--set-filler (selected-window) nil)
      (+my/stripe--plain-last-number)
      (should-not +my/stripe--number-cookie))))

;; ====== SCROLLING PAST THE END ======

(ert-deftest stripe/text-rows-wanted ()
  "All rows but the allowed overscroll: a fraction, rows, none; at least one."
  (+test-stripe "x\n"
    (let ((rows (window-body-height)))
      (dolist (case `((0.25 . ,(- rows (floor (* rows 0.25))))
                      (0.5 . ,(- rows (floor (* rows 0.5))))
                      (3 . ,(- rows 3))
                      (0 . ,rows)
                      (1.0 . 1)
                      (100 . 1)))
        (let ((+my/stripe-overscroll (car case)))
          (should (= (+my/stripe--text-rows-wanted (selected-window)) (cdr case))))))))

(ert-deftest stripe/end-pixels-wanted ()
  "The empty line after a final newline counts as a row."
  (+test-stripe (+test-stripe--text 50)
    (let ((rows (+my/stripe--text-rows-wanted (selected-window)))
          (lh (window-default-line-height)))
      (should (= (+my/stripe--end-pixels-wanted (selected-window)) (* lh (1- rows))))
      (goto-char (point-max))
      (delete-char -1)
      (should (= (+my/stripe--end-pixels-wanted (selected-window)) (* lh rows)))))
  (+test-stripe ""
    (should (= (+my/stripe--end-pixels-wanted (selected-window))
               (* (window-default-line-height) (+my/stripe--text-rows-wanted (selected-window)))))))

(ert-deftest stripe/end-limit ()
  "As far as the window may scroll: the last line the allowed rows down, the
empty line after it, then the empty space."
  (+test-stripe (+test-stripe--text 100)
    (let* ((rows (window-body-height))
           (wanted (+my/stripe--text-rows-wanted (selected-window))))
      (should (equal (+my/stripe--end-limit (selected-window))
                     ;; WANTED rows: lines up to 100, then the empty line 101.
                     (cons (+test-stripe--line-start (- 101 (1- wanted))) 0)))
      (should (< wanted rows))
      (let ((+my/stripe-overscroll 0))
        (should (equal (+my/stripe--end-limit (selected-window))
                       (cons (+test-stripe--line-start (- 101 (1- rows))) 0)))))))

(ert-deftest stripe/clamp-start ()
  "A window scrolled further than allowed is scrolled back; within the limit,
or with no limit, it's left alone."
  (+test-stripe (+test-stripe--text 100)
    (let* ((window (selected-window))
           (limit (car (+my/stripe--end-limit window))))
      (set-window-start window (+test-stripe--line-start 98))
      (+my/stripe--clamp-start window)
      (should (= (window-start window) limit))
      (set-window-start window (+test-stripe--line-start 40))
      (+my/stripe--clamp-start window)
      (should (= (window-start window) (+test-stripe--line-start 40)))
      (set-window-start window limit)
      (+my/stripe--clamp-start window)
      (should (= (window-start window) limit))
      (let ((+my/stripe-overscroll t))
        (set-window-start window (+test-stripe--line-start 100))
        (+my/stripe--clamp-start window)
        (should (= (window-start window) (+test-stripe--line-start 100))))
      ;; No overscroll: the last line at the bottom.
      (let ((+my/stripe-overscroll 0))
        (set-window-start window (+test-stripe--line-start 100))
        (+my/stripe--clamp-start window)
        (should (= (count-lines (window-start window) (point-max))
                   (1- (window-body-height window))))))))

(ert-deftest stripe/clamp-start-short-buffer ()
  "A buffer shorter than the window stays at its top; one that was scrolled
goes back up."
  (+test-stripe (+test-stripe--text 5)
    (+my/stripe--clamp-start (selected-window))
    (should (= (window-start) 1))
    (set-window-start nil (+test-stripe--line-start 4))
    (+my/stripe--clamp-start (selected-window))
    (should (= (window-start) 1)))
  (+test-stripe ""
    (+my/stripe--clamp-start (selected-window))
    (should (= (window-start) 1))))

(ert-deftest stripe/after-scroll-checks-the-limit-later ()
  "When redisplay itself scrolled near the end, the limit is checked right after
(the filler can't be taken out mid-redisplay)."
  (+test-stripe (+test-stripe--text 100)
    (let ((window (selected-window))
          scheduled)
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (time repeat fn) (push (list time repeat fn) scheduled))))
        ;; Far from the end: nothing.
        (+my/stripe--after-scroll window (+test-stripe--line-start 10))
        (should-not scheduled)
        (let ((+my/stripe-overscroll t))
          (+my/stripe--after-scroll window (+test-stripe--line-start 99))
          (should-not scheduled))
        (set-window-start window (+test-stripe--line-start 99))
        (+my/stripe--after-scroll window (+test-stripe--line-start 99))
        (should (= (length scheduled) 1))
        (should (equal (seq-take (car scheduled) 2) '(0 nil)))
        (+my/stripe--set-filler window "FILLER")
        (set-window-parameter window '+my/stripe-key '(old))
        (funcall (nth 2 (car scheduled)))
        (should (= (window-start window) (car (+my/stripe--end-limit window))))
        (should-not (overlay-get (window-parameter window '+my/stripe-filler) 'before-string))
        (should-not (window-parameter window '+my/stripe-key))))))

(ert-deftest stripe/after-scroll-later-check-is-safe ()
  "The window gone, or the stripe off, by the time the check runs: nothing."
  (+test-stripe (+test-stripe--text 100)
    (let ((window (split-window))
          scheduled)
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _repeat fn) (push fn scheduled))))
        (set-window-start window (+test-stripe--line-start 99))
        (+my/stripe--after-scroll window (+test-stripe--line-start 99))
        (+my/stripe--after-scroll window (+test-stripe--line-start 99))
        (should (= (length scheduled) 2))
        (+my/stripe-mode -1)
        (funcall (pop scheduled))
        (should (= (window-start window) (+test-stripe--line-start 99)))
        (delete-window window)
        (funcall (pop scheduled))))))

;; ====== THE EMPTY LAST LINE ======

(defmacro +test-stripe--command (before &rest body)
  "BODY as a command run from position BEFORE (pre/post-command hooks)."
  (declare (indent 1))
  `(progn
     (goto-char ,before)
     (+my/stripe--note-point)
     ,@body
     (+my/stripe--leave-phantom-line)))

(ert-deftest stripe/cursor-off-the-empty-last-line ()
  "In normal state the cursor doesn't stay on the empty line after the final
newline: to the last line's text (`G'), or back where it was on the last
line (`j' there stays put)."
  (+test-stripe "  one\n  two\n"
    (evil-normal-state)
    (let ((last-input-event ?G))
      (+test-stripe--command 1 (goto-char (point-max)))
      (should (= (point) (+ (+test-stripe--line-start 2) 2)))
      (+test-stripe--command (+ (+test-stripe--line-start 2) 4) (goto-char (point-max)))
      (should (= (point) (+ (+test-stripe--line-start 2) 4)))
      ;; Nothing noted: to the text.
      (setq +my/stripe--point-before nil)
      (goto-char (point-max))
      (+my/stripe--leave-phantom-line)
      (should (= (point) (+ (+test-stripe--line-start 2) 2))))))

(ert-deftest stripe/cursor-may-go-to-the-empty-last-line-in-insert-state ()
  (+test-stripe "one\ntwo\n"
    (let ((last-input-event ?o))
      (dolist (state '(insert replace emacs))
        (evil-change-state state)
        (+test-stripe--command 1 (goto-char (point-max)))
        (should (= (point) (point-max))))
      (evil-normal-state))))

(ert-deftest stripe/cursor-elsewhere-left-alone ()
  "Not at the empty last line: nothing to do (no final newline, an empty buffer,
the middle of the text)."
  (+test-stripe "one\ntwo"
    (evil-normal-state)
    (let ((last-input-event ?G))
      (+test-stripe--command 1 (goto-char (point-max)))
      (should (= (point) (point-max)))))
  (+test-stripe ""
    (evil-normal-state)
    (let ((last-input-event ?G))
      (+test-stripe--command 1 nil)
      (should (= (point) 1))))
  (+test-stripe "one\ntwo\n"
    (evil-normal-state)
    (let ((last-input-event ?j))
      (+test-stripe--command 1 (forward-line 1))
      (should (= (point) 5)))))

(defmacro +test-stripe--clicked (y target &rest body)
  "BODY with a click Y pixels down (from the text's top) as the last event, and
`posn-at-x-y' finding TARGET (the last line's row is 3 pixels down)."
  (declare (indent 2))
  `(let* ((asked nil)
          (last-input-event
           (list 'mouse-1 (list (selected-window) (point-max) (cons 7 ,y) 0 nil (point-max)
                                '(7 . 0) nil '(0 . 0) '(1 . 1)))))
     (cl-letf (((symbol-function 'posn-at-point)
                (lambda (&rest _) (list (selected-window) (point) '(0 . 3) 0)))
               ((symbol-function 'posn-at-x-y)
                (lambda (x y &rest _) (setq asked (cons x y))
                  (list (selected-window) ,target (cons x y) 0))))
       ,@body)))

(ert-deftest stripe/click-below-the-text ()
  "A click below the text puts the cursor on the last line, at the clicked
column (on the last character in normal state)."
  (+test-stripe "first\nlast line\n"
    (evil-normal-state)
    (let ((last-line (+test-stripe--line-start 2)))
      (+test-stripe--clicked 10 (+ last-line 3)
        (+test-stripe--command 1 (goto-char (point-max)))
        (should (= (point) (+ last-line 3)))
        ;; Asked at the click's column, on the last line's row.
        (should (equal asked (cons 7 (+ 3 (window-tab-line-height) (window-header-line-height))))))
      ;; Past the end of the line: its last character...
      (+test-stripe--clicked 10 (1- (point-max))
        (+test-stripe--command 1 (goto-char (point-max)))
        (should (= (point) (- (point-max) 2))))
      ;; ...or after it, in insert state.
      (evil-insert-state)
      (+test-stripe--clicked 10 (1- (point-max))
        (+test-stripe--command 1 (goto-char (point-max)))
        (should (= (point) (1- (point-max)))))
      (evil-normal-state)
      ;; Not on the last line: its start.
      (+test-stripe--clicked 10 2
        (+test-stripe--command 1 (goto-char (point-max)))
        (should (= (point) last-line))))))

(ert-deftest stripe/click-in-another-window ()
  "A click event from another window: as for keys."
  (+test-stripe "one\n  two\n"
    (evil-normal-state)
    (let ((other (split-window)))
      (let ((last-input-event (list 'mouse-1 (list other 1 '(0 . 0) 0))))
        (+test-stripe--command 1 (goto-char (point-max)))
        (should (= (point) (+ (+test-stripe--line-start 2) 2)))))))

;; ====== CLICKS ON THE STRIP ======

(ert-deftest stripe/click-on-a-cell-jumps ()
  "A click on a cell jumps to the middle of its lines."
  (+test-stripe (+test-stripe--text 100)
    (+my/stripe--render (selected-window))
    (let* ((rows (window-body-height))
           (ov (nth 11 (+test-stripe--row-overlays)))
           (cell (+test-stripe--margin (overlay-get ov 'before-string))))
      (+my/stripe-jump (+test-stripe--click (selected-window) (cons cell 0)))
      (should (= (line-number-at-pos) (+my/stripe--row-to-line 11 101 rows)))
      (should (= (+my/stripe--line-to-row (line-number-at-pos) 101 rows) 11))
      (should (bolp)))))

(ert-deftest stripe/click-on-an-image-jumps ()
  "A click on the graphical strip: the line at the clicked pixel."
  (+test-stripe (+test-stripe--text 100)
    (set-window-parameter nil '+my/stripe-geometry '(pixels 0.5 100))
    (dolist (case '((21 . 43) (0 . 1) (1000 . 100) (-3 . 1)))
      (goto-char (point-min))
      (+my/stripe-jump (+test-stripe--click (selected-window) nil (car case)))
      (should (= (line-number-at-pos) (cdr case))))
    ;; No y: nothing.
    (goto-char (point-min))
    (+my/stripe-jump (+test-stripe--click (selected-window) nil nil))
    (should (= (point) 1))))

(ert-deftest stripe/click-selects-the-window-and-marks-the-jump ()
  "The clicked window is selected; `C-o' goes back (a better-jumper jump)."
  (+test-stripe (+test-stripe--text 100)
    (let* ((left (selected-window))
           (right (split-window-right))
           (jumps nil))
      (+test-stripe--clear right)
      (set-window-parameter right '+my/stripe-geometry '(pixels 1.0 100))
      (cl-letf (((symbol-function 'better-jumper-set-jump)
                 (lambda (&rest _) (push (cons (selected-window) (point)) jumps))))
        (+my/stripe-jump (+test-stripe--click right nil 40)))
      (should (eq (selected-window) right))
      (should (= (line-number-at-pos (window-point right)) 41))
      (should (equal jumps (list (cons right 1))))
      ;; A window without a strip: nothing.
      (select-window left)
      (set-window-parameter right '+my/stripe-geometry nil)
      (+my/stripe-jump (+test-stripe--click right nil 10))
      (should (eq (selected-window) left)))))

(ert-deftest stripe/click-in-a-dead-window ()
  (+test-stripe (+test-stripe--text 10)
    (let ((window (split-window)))
      (set-window-parameter window '+my/stripe-geometry '(pixels 1.0 11))
      (delete-window window)
      (+my/stripe-jump (+test-stripe--click window nil 5))
      (should (= (point) 1)))))

(ert-deftest stripe/keys ()
  "mouse-1 on the strip jumps (its press does nothing); on the fringe next to it,
nothing (not \"is undefined\")."
  (dolist (map (list +my/stripe-margin-map +my/stripe-mode-map))
    (should (eq (lookup-key map [right-margin mouse-1]) #'+my/stripe-jump))
    (should (eq (lookup-key map [right-margin down-mouse-1]) #'ignore)))
  (should (eq (lookup-key +my/stripe-mode-map [right-fringe mouse-1]) #'ignore))
  (should (eq (lookup-key +my/stripe-mode-map [right-fringe down-mouse-1]) #'ignore))
  (should (commandp #'+my/stripe-jump)))

;; ====== THE MODE ======

(ert-deftest stripe/mode-on ()
  "A margin column for the strip, at the very edge (fringes inside), its hooks,
and the strip drawn in the windows showing the buffer."
  (+test-stripe (+test-stripe--text 50)
    (should (local-variable-p 'right-margin-width))
    (should (= right-margin-width 1))
    (should (local-variable-p 'fringes-outside-margins))
    (should-not fringes-outside-margins)
    (should (equal (cdr (window-margins)) 1))
    (pcase-dolist (`(,hook . ,fn) '((window-scroll-functions . +my/stripe--scrolled)
                                    (window-scroll-functions . +my/stripe--after-scroll)
                                    (before-change-functions . +my/stripe--note-line-edit)
                                    (after-change-functions . +my/stripe--note-line-edit)
                                    (post-command-hook . +my/stripe--plain-last-number)
                                    (pre-command-hook . +my/stripe--note-point)
                                    (post-command-hook . +my/stripe--leave-phantom-line)))
      (should (local-variable-p hook))
      (should (memq fn (symbol-value hook)))
      (should-not (memq fn (default-value hook))))
    (should (+test-stripe--row-overlays))))

(ert-deftest stripe/mode-off ()
  "Off: the strip, filler and hooks gone, margin and fringes back to normal."
  (+test-stripe (+test-stripe--text 50)
    (setq-local display-line-numbers t)
    (+my/stripe--set-filler (selected-window) "FILLER")
    (goto-char (point-max))
    (+my/stripe--plain-last-number)
    (should +my/stripe--number-cookie)
    (+my/stripe--marks)
    (setq-local left-fringe-width 16)
    (setq-local right-fringe-width 16)
    (+my/stripe-mode -1)
    (should-not (seq-find (lambda (ov) (overlay-get ov '+my/stripe))
                          (overlays-in (point-min) (point-max))))
    (should-not +my/stripe--cache)
    (should-not +my/stripe--number-cookie)
    (should-not (assq 'line-number-current-line face-remapping-alist))
    (dolist (var '(right-margin-width fringes-outside-margins left-fringe-width right-fringe-width))
      (should-not (local-variable-p var)))
    (should-not (cdr (window-margins)))
    (dolist (hook '(window-scroll-functions before-change-functions after-change-functions
                    post-command-hook pre-command-hook))
      (dolist (fn '(+my/stripe--scrolled +my/stripe--after-scroll +my/stripe--note-line-edit
                    +my/stripe--plain-last-number +my/stripe--note-point
                    +my/stripe--leave-phantom-line))
        (should-not (memq fn (symbol-value hook)))))))

(ert-deftest stripe/pad ()
  "Fringes a column wider each side (graphical frames); the right one may be
padded already."
  (+test-stripe "x\n"
    ;; A terminal session: nothing (done when a graphical window shows it).
    (+my/stripe--pad)
    (should-not (local-variable-p 'left-fringe-width))
    (+test-stripe--gui
      (cl-letf* ((parameter (symbol-function 'frame-parameter))
                 (right 8)
                 ((symbol-function 'frame-char-width) (lambda (&optional _) 8))
                 ((symbol-function 'frame-parameter)
                  (lambda (frame name)
                    (pcase name
                      ('left-fringe 8)
                      ('right-fringe right)
                      (_ (funcall parameter frame name))))))
        (+my/stripe--pad)
        (should (equal (list left-fringe-width right-fringe-width) '(16 16)))
        (setq right 16)                         ; config/window.el's padding
        (+my/stripe--pad)
        (should (equal (list left-fringe-width right-fringe-width) '(16 16)))
        (let ((+my/stripe-padding 2))
          (+my/stripe--pad)
          (should (equal (list left-fringe-width right-fringe-width) '(24 24))))
        (kill-local-variable 'left-fringe-width)
        (let ((+my/stripe-padding nil))
          (+my/stripe--pad)
          (should-not (local-variable-p 'left-fringe-width)))))
    ;; A given frame is measured even if it's not graphical.
    (+my/stripe--pad (selected-frame))
    (should (= left-fringe-width (+ 8 (frame-char-width))))))

(ert-deftest stripe/set-fringes ()
  (+test-stripe "x\n"
    (let (args)
      (cl-letf (((symbol-function 'set-window-fringes) (lambda (&rest a) (setq args a))))
        (setq-local left-fringe-width 16 right-fringe-width 12)
        (+my/stripe--set-fringes (selected-window)))
      (should (equal args (list (selected-window) 16 12 nil))))))

(ert-deftest stripe/on-in-file-buffers ()
  "On in file buffers of code, text and config modes (and so-long-mode); not in
other buffers."
  (+test-with-reset
    (pcase-dolist (`(,name . ,on) '(("stripe-files/a.py" . t) ("stripe-files/a.el" . t)
                                    ("stripe-files/a.txt" . t) ("stripe-files/a.ini" . t)
                                    ("stripe-files/a.unknown-ext" . nil)))
      (with-current-buffer (find-file-noselect (+test-file name "x\n"))
        (should (eq (and +my/stripe-mode t) on))))
    (should +my/stripe-global-mode)
    ;; Not without a file.
    (with-current-buffer (+test-buffer "no-file" "x\n" #'prog-mode)
      (should-not +my/stripe-mode))
    ;; Files with very long lines.
    (require 'so-long)
    (with-current-buffer (find-file-noselect (+test-file "stripe-files/long.js" "x\n"))
      (so-long-mode)
      (should (eq major-mode 'so-long-mode))
      (should +my/stripe-mode))
    ;; The rule itself.
    (with-current-buffer (+test-buffer "rule" "x\n" #'special-mode)
      (setq buffer-file-name (+test-tmp-file "stripe-files/special"))
      (+my/stripe--maybe-enable)
      (should-not +my/stripe-mode)
      (conf-mode)
      (+my/stripe--maybe-enable)
      (should +my/stripe-mode)
      (+my/stripe-mode -1)
      (set-buffer-modified-p nil)
      (setq buffer-file-name nil))))

;; ====== HOOKS AND ADVICE ======

(ert-deftest stripe/hooks-and-advice ()
  (should (memq #'+my/stripe--pre-redisplay (default-value 'pre-redisplay-functions)))
  (should (memq #'+my/stripe--render-all (default-value 'doom-load-theme-hook)))
  (should (advice-member-p #'+my/stripe--after-diff-hl-a 'diff-hl--update-overlays))
  (should (advice-member-p #'+my/stripe--after-diff-hl-a 'diff-hl-remove-overlays)))

(ert-deftest stripe/diff-hl-redraws-noticed ()
  "diff-hl's redraws bump the stripe buffer's tick (so it's redrawn); not in
other buffers."
  (+test-stripe (+test-stripe--text 5)
    (let ((tick +my/stripe--diff-hl-tick))
      (diff-hl-remove-overlays)
      (should (= +my/stripe--diff-hl-tick (1+ tick)))))
  (with-temp-buffer
    (diff-hl-remove-overlays)
    (should (= +my/stripe--diff-hl-tick 0))))

(ert-deftest stripe/flycheck-keeps-small-centred-markers ()
  "In fringes 16 px wide flycheck would use its big markers: its hi-res ones are
the small ones, centred."
  (should (equal (assq 'flycheck-fringe-bitmap-double-arrow-hi-res +test-stripe--bitmaps)
                 '(flycheck-fringe-bitmap-double-arrow-hi-res [16 48 112 240 112 48 16]
                                                              nil nil center)))
  (should (equal (assq 'flycheck-fringe-bitmap-fixable-hi-res +test-stripe--bitmaps)
                 (list 'flycheck-fringe-bitmap-fixable-hi-res flycheck-fringe-bitmap-fixable
                       nil nil 'center))))

;; ====== END TO END (TERMINAL) ======

(ert-deftest stripe/marks-errors-and-changes-at-the-right-edge ()
  "A code file with errors and changes: before redisplay its window gets the
strip (cells in the margin), a click on the error's cell goes there."
  (+test-with-reset
    (+test-stripe--clear (selected-window))
    (find-file (+test-file "stripe-e2e/app.py"
                           (mapconcat (lambda (n) (format "x%d = %d\n" n n))
                                      (number-sequence 1 60) "")))
    (should +my/stripe-mode)
    (+test-stripe--errors '(30 error) '(45 warning))
    (+test-stripe--hunk 10 12 'insert)
    (run-hook-with-args 'pre-redisplay-functions (selected-window))
    (let* ((rows (window-body-height))
           (overlays (+test-stripe--row-overlays))
           (colors (mapcar (lambda (ov) (+test-stripe--cell-color (overlay-get ov 'before-string)))
                           overlays))
           (error-row (+my/stripe--line-to-row 30 61 rows)))
      (should (= (length overlays) rows))
      (should (equal (nth error-row colors) "#ff0000"))
      (should (equal (nth (+my/stripe--line-to-row 45 61 rows) colors) "#ffff00"))
      (should (equal (nth (+my/stripe--line-to-row 11 61 rows) colors) "#00ff00"))
      (+my/stripe-jump (+test-stripe--click
                        (selected-window)
                        (cons (+test-stripe--margin (overlay-get (nth error-row overlays)
                                                                 'before-string))
                              0)))
      (should (= (+my/stripe--line-to-row (line-number-at-pos) 61 rows) error-row))
      (should (<= (abs (- (line-number-at-pos) 30)) 2)))))

;;; test-stripe.el ends here
