;;; tests/unit/test-stripe.el -*- lexical-binding: t; -*-
;; config/stripe.el: the error stripe at the right edge of file
;; windows (flycheck errors, TODO comments, diff-hl's git changes, the band of
;; the part on screen): its marks, its terminal cells, its graphical image and the child
;; frame showing it (faked: batch Emacs makes no child frames), clicks, drags
;; and the wheel on it, the scroll limit past the end.
;;
;; Batch Emacs has a terminal frame: a pixel per row and column. The graphical
;; strip is computed there too with `display-graphic-p' mocked (see
;; `+test-stripe--gui'): its pixels are then rows. tests/e2e/test-stripe.el
;; covers the real child frames.

;; Flycheck's fringe bitmaps as stripe.el's `after!' redefines them, recorded
;; as flycheck loads (after the config, as in Doom).
(defvar +test-stripe--bitmaps nil
  "(NAME ARGS...) of the `define-fringe-bitmap' calls made as flycheck loaded.")

(+test-load "config/childframe" "config/stripe")

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
    (+my/stripe-todo . "#00aaff")
    (+my/stripe-suggestion . "#888800")))

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
  (dolist (parameter '(+my/stripe-key +my/stripe-geometry))
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

(defun +test-stripe--click (window &optional string y)
  "A mouse-1 click on WINDOW's right margin, on STRING ((STRING . INDEX)), Y
pixels from the top of the text."
  `(mouse-1 (,window right-margin (0 . ,y) 0 ,string nil (0 . 0) nil (0 . 0) (1 . 1))))

;; ====== SETTINGS ======

(ert-deftest stripe/settings-defaults ()
  (should (equal (default-value '+my/stripe-diagnostic-levels) '(error warning info)))
  (should (equal (default-value '+my/stripe-todo-keywords) '("TODO" "FIXME" "HACK")))
  (should (= (default-value '+my/stripe-mark-height) 2))
  (should (eql (default-value '+my/stripe-overscroll) 0.25))
  (should (eql (default-value '+my/stripe-padding) 1)))

(ert-deftest stripe/kinds-by-priority ()
  "error > warning > TODO > deleted > changed > added > suggestion (info), each
in its face."
  (should (equal (mapcar #'car (sort (copy-sequence +my/stripe--kinds)
                                     (lambda (a b) (> (cadr a) (cadr b)))))
                 '(error warning todo delete change insert info)))
  (should (equal (mapcar (lambda (kind) (nth 2 kind)) +my/stripe--kinds)
                 '(flycheck-fringe-error flycheck-fringe-warning +my/stripe-todo
                   diff-hl-delete diff-hl-change diff-hl-insert +my/stripe-suggestion))))

(ert-deftest stripe/faces-from-the-theme ()
  "TODO marks the theme's blue, suggestions its warning colour dimmed; nothing
without Doom's colour functions or with colours not in hex."
  (let ((todo (face-attribute '+my/stripe-todo :foreground))
        (suggestion (face-attribute '+my/stripe-suggestion :foreground)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'doom-color) (lambda (name) (and (eq name 'blue) "#0000ee")))
                    ((symbol-function 'doom-blend)
                     (lambda (a b alpha) (format "%s+%s*%s" a b alpha)))
                    ((symbol-function 'face-foreground)
                     (lambda (face &rest _) (and (eq face 'warning) "#eeee00")))
                    ((symbol-function 'face-background)
                     (lambda (face &rest _) (and (eq face 'default) "#000000"))))
            (+my/stripe-faces-h)
            (should (equal (face-attribute '+my/stripe-todo :foreground) "#0000ee"))
            (should (equal (face-attribute '+my/stripe-suggestion :foreground)
                           "#eeee00+#000000*0.5")))
          (set-face-foreground '+my/stripe-todo "#123456")
          (cl-letf (((symbol-function 'doom-color) (lambda (_) "blue"))
                    ((symbol-function 'doom-blend) #'ignore))
            (+my/stripe-faces-h)
            (should (equal (face-attribute '+my/stripe-todo :foreground) "#123456"))))
      (set-face-foreground '+my/stripe-todo todo)
      (set-face-foreground '+my/stripe-suggestion suggestion)))
  (should (memq #'+my/stripe-faces-h doom-load-theme-hook))
  ;; Before the strips are redrawn in the theme's colours.
  (should (< (cl-position #'+my/stripe-faces-h doom-load-theme-hook)
             (cl-position #'+my/stripe--render-all doom-load-theme-hook))))

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

(ert-deftest stripe/marks-errors-warnings-and-suggestions ()
  (+test-stripe (+test-stripe--text 20)
    (+test-stripe--errors '(3 error) '(7 warning) '(9 info) '(12 error))
    (should (equal (car (+my/stripe--marks)) 21))
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((3 3 error) (7 7 warning) (9 9 info) (12 12 error))))))

(ert-deftest stripe/marks-an-error-on-line-0-on-the-first ()
  "Flycheck's Emacs Lisp checker puts unbalanced parens on line 0: marked on
the first line, and a short file's cells drawn (no \"Stripe:\" error)."
  (+test-stripe (+test-stripe--text 5)
    (+test-stripe--errors '(0 error) '(3 warning))
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((1 1 error) (3 3 warning))))
    (+test-clear-messages)
    (+my/stripe--render (selected-window))
    (should (= (+test-messages "Stripe:") 0))
    (let ((overlays (+test-stripe--row-overlays)))
      (should (equal (+test-stripe--cell-color (overlay-get (car overlays) 'before-string))
                     (+test-stripe--color 'error))))))

(ert-deftest stripe/marks-lsp-hints-are-suggestions ()
  "lsp-mode gives flycheck its hints (severity 4) as `info', tagged ones
(unnecessary, deprecated) as levels of their own of the same severity."
  (+test-stripe (+test-stripe--text 20)
    (let ((level '+test-stripe-lsp-flycheck-info-unnecessary))
      (put level 'flycheck-error-severity (get 'info 'flycheck-error-severity))
      (+test-stripe--errors '(4 info) (list 6 level))
      (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                     '((4 4 info) (6 6 info)))))))

(ert-deftest stripe/marks-levels-as-set ()
  (+test-stripe (+test-stripe--text 20)
    (let ((+my/stripe-diagnostic-levels '(error warning)))
      (+test-stripe--errors '(3 error) '(9 info))
      (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                     '((3 3 error))))))
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

(ert-deftest stripe/marks-todo-in-text ()
  "In text: TODO, FIXME, HACK anywhere, as words, in capitals; a line once."
  (+test-stripe (concat "one\n"
                        "TODO: two\n"
                        "three FIXME\n"
                        "todo four\n"            ; case matters
                        "TODOS FIXMEs MY_HACK\n" ; not words of their own
                        "(HACK) and TODO\n"      ; one mark
                        "NOTE seven\n")
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((2 2 todo) (3 3 todo) (6 6 todo))))
    (let ((+my/stripe-todo-keywords '("NOTE")))
      (should (equal (+my/stripe--todo-lines) '(7))))
    (let ((+my/stripe-todo-keywords nil))
      (should-not (+my/stripe--todo-lines))
      (should-not (+my/stripe--todo-regexp)))))

(ert-deftest stripe/marks-todo-in-code-only-in-comments ()
  (+test-with-reset
    (with-current-buffer (+test-buffer "stripe-code"
                                       (concat "(defun f ()\n"
                                               "  ;; TODO: a comment\n"
                                               "  \"TODO in a string\"\n"
                                               "  'FIXME)\n"
                                               "; HACK\n"
                                               "\"HACK\" ; FIXME after a string\n"
                                               "'TODO\n")
                                       #'emacs-lisp-mode)
      (goto-char (point-max))
      (should (equal (+my/stripe--todo-lines) '(2 5 6)))
      (should (= (point) (point-max))))))

(ert-deftest stripe/marks-todo-whole-buffer-when-narrowed ()
  (+test-stripe "TODO\nb\nc\nFIXME\n"
    (narrow-to-region (+test-stripe--line-start 2) (+test-stripe--line-start 3))
    (should (equal (+test-stripe--sorted (cdr (+my/stripe--marks)))
                   '((1 1 todo) (4 4 todo))))))

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
  (dolist (kind '(error warning todo delete change insert info))
    (should (equal (+my/stripe--kind-color kind) (+test-stripe--color kind))))
  (should-not (+my/stripe--kind-color 'unknown))
  (let ((+my/stripe--kinds '((error 6 +test-stripe-no-such-face))))
    (should-not (+my/stripe--kind-color 'error))))

(ert-deftest stripe/palette ()
  "The images' colours by pixel character: blank, ?t the band, ?7..?1 the kinds
(None for a kind without a colour)."
  (should (equal (+my/stripe--palette)
                 `((?\s . "None") (?t . ,(+my/stripe--thumb-color))
                   (?7 . "#ff0000") (?6 . "#ffff00") (?5 . "#00aaff") (?4 . "#aa0000")
                   (?3 . "#ff8800") (?2 . "#00ff00") (?1 . "#888800"))))
  (cl-letf (((symbol-function '+my/stripe--kind-color) #'ignore))
    (should (equal (mapcar #'cdr (nthcdr 2 (+my/stripe--palette))) (make-list 7 "None")))))

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
    (let* ((marks '((1 1 error) (2 2 warning) (3 3 todo) (4 4 delete) (5 5 change)
                    (6 6 insert) (7 7 info)))
           (colors (+test-stripe--cell-colors
                    (+my/stripe--cell-rows (selected-window) (point-min) 9 marks))))
      (should (equal colors (append (mapcar #'+test-stripe--color
                                            '(error warning todo delete change insert info))
                                    '(nil nil)))))))

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

;; ====== GRAPHICAL FRAMES: THE STRIP'S IMAGE ======

(defmacro +test-stripe--small (&rest body)
  "BODY with marks and band a pixel high at least (rows are pixels here)."
  (declare (indent 0))
  `(let ((+my/stripe-mark-height 1)
         (+my/stripe-thumb-min-height 1))
     ,@body))

(defun +test-stripe--strip-pixels (&optional window)
  "(PIXELS SCALE THUMB) of WINDOW's strip as it shows now."
  (let ((window (or window (selected-window))))
    (pcase-let ((`(,lines . ,marks) (+my/stripe--marks)))
      (+my/stripe--pixels window (window-start window) lines marks))))

(ert-deftest stripe/pixels-band-at-the-top-and-marks ()
  "A pixel row each: the band over the lines on screen, marks in their place."
  (+test-stripe (+test-stripe--text 200)
    (+test-stripe--small
      (+test-stripe--errors '(100 error))
      (pcase-let* ((height (window-body-height nil t))
                   (`(,pixels ,scale ,thumb) (+test-stripe--strip-pixels)))
        (should (= (length pixels) height))
        (should (< scale 1))
        (should (= (car thumb) 0))
        (should (string-match-p "\\`t+" pixels))
        (should (= (cdr thumb) (length (car (split-string pixels "[^t]")))))
        (should (eq (aref pixels (floor (* scale 99))) ?7))))))

(ert-deftest stripe/pixels-band-follows-the-scroll ()
  (+test-stripe (+test-stripe--text 400)
    (+test-stripe--small
      (set-window-start nil (+test-stripe--line-start 201))
      (pcase-let ((`(,pixels ,scale ,thumb) (+test-stripe--strip-pixels)))
        (should (= (car thumb) (floor (* scale 200))))
        (should (eq (aref pixels (car thumb)) ?t))
        (should (eq (aref pixels 0) ?\s))))))

(ert-deftest stripe/pixels-most-important-mark-wins ()
  (+test-stripe (+test-stripe--text 50)
    (+test-stripe--small
      (+test-stripe--errors '(20 warning))
      (+test-stripe--hunk 20 20 'change)
      (+test-stripe--hunk 30 30 'insert)
      (+test-stripe--hunk 40 40 'delete)
      (+test-stripe--errors '(20 warning) '(30 info))
      (goto-char (+test-stripe--line-start 40))
      (insert "TODO ")
      (pcase-let ((`(,pixels ,scale) (+test-stripe--strip-pixels)))
        (should (eq (aref pixels (floor (* scale 19))) ?6))  ; warning over change
        (should (eq (aref pixels (floor (* scale 29))) ?2))  ; added over suggestion
        (should (eq (aref pixels (floor (* scale 39))) ?5)))))) ; TODO over deleted

(ert-deftest stripe/pixels-marks-a-thin-line ()
  "A mark of one line is `+my/stripe-mark-height' high, however tall its line
on the strip (lines 10 pixels here); one of several lines spans them."
  (+test-stripe (+test-stripe--text 5)
    (+test-stripe--errors '(2 error))
    (+test-stripe--hunk 3 5 'change)
    (cl-letf (((symbol-function 'window-body-height)
               (lambda (&optional _ pixelwise) (if pixelwise 200 20)))
              ((symbol-function 'window-font-height) (lambda (&rest _) 10))
              ((symbol-function '+my/stripe--text-rows-wanted) (lambda (&rest _) 20)))
      (pcase-let ((`(,pixels ,scale) (+test-stripe--strip-pixels)))
        (should (= scale 10))
        (should (equal (substring pixels 8 52)
                       (concat "  77" (make-string 8 ?\s) (make-string 30 ?3) "  "))))
      (let ((+my/stripe-mark-height 4))
        (should (equal (substring (car (+test-stripe--strip-pixels)) 10 15) "7777 "))))))

(ert-deftest stripe/pixels-short-file ()
  "A file that fits: no band, a line a row (the font's height a line)."
  (+test-stripe (+test-stripe--text 5)
    (+test-stripe--small
      (+test-stripe--hunk 3 3 'insert)
      (pcase-let ((`(,pixels ,scale ,thumb) (+test-stripe--strip-pixels)))
        (should (= scale (window-font-height)))
        (should-not thumb)
        (should (eq (aref pixels 2) ?2))
        (should-not (seq-contains-p pixels ?t))))))

(ert-deftest stripe/pixels-band-reaches-the-bottom-at-the-end ()
  "Scrolled as far as allowed: the band reaches the strip's bottom."
  (+test-stripe (+test-stripe--text 300)
    (+test-stripe--small
      (let ((window (selected-window)))
        (set-window-start window (car (+my/stripe--end-limit window)))
        (pcase-let ((`(,pixels ,_ ,thumb) (+test-stripe--strip-pixels)))
          (should (= (cdr thumb) (length pixels)))
          (should (eq (aref pixels (1- (length pixels))) ?t)))))))

(ert-deftest stripe/pixels-overscroll-setting ()
  "The strip maps the file plus the space past its end the window may show."
  (+test-stripe (+test-stripe--text 200)
    (let ((rows (window-body-height))
          (height (window-body-height nil t)))
      (dolist (case `((0 . 0) (3 . 3) (t . ,(1- rows))))
        (let ((+my/stripe-overscroll (car case)))
          (should (= (nth 1 (+test-stripe--strip-pixels))
                     (/ (float height) (+ 201 (cdr case))))))))))

(ert-deftest stripe/pixels-band-at-least-its-minimum ()
  (+test-stripe (+test-stripe--text 2000)
    (let ((+my/stripe-thumb-min-height 6))
      (pcase-let ((`(,_ ,_ ,thumb) (+test-stripe--strip-pixels)))
        (should (>= (- (cdr thumb) (car thumb)) 6))))))

(ert-deftest stripe/last-line-shown-counted-when-lines-are-cut ()
  "Lines cut off at the edge (Doom's default): a row a line, no layout."
  (+test-stripe (+test-stripe--text 100)
    (setq truncate-lines t)
    (let ((rows (window-body-height)))
      (cl-letf (((symbol-function 'vertical-motion) (lambda (&rest _) (error "Laid out"))))
        (should (equal (+my/stripe--last-line-shown (selected-window) (point-min) rows 101)
                       (cons (1+ rows) 0)))
        ;; The end on screen: the line after it, and the empty rows.
        (should (equal (+my/stripe--last-line-shown (selected-window) (+test-stripe--line-start 95) rows 101)
                       (cons 102 (- (+ 95 rows) 101 1))))))))

(ert-deftest stripe/last-line-shown-laid-out-when-lines-wrap ()
  "Wrapped lines: as many lines as fit, laid out."
  (+test-stripe (mapconcat (lambda (_) (make-string 200 ?x)) (number-sequence 1 30) "\n")
    (setq truncate-lines nil)
    (let* ((rows (window-body-height))
           (shown (+my/stripe--last-line-shown (selected-window) (point-min) rows 30)))
      ;; Each line takes several rows: fewer lines than rows.
      (should (< (car shown) (1+ rows)))
      (should (= (cdr shown) 0))
      (should (= (car shown)
                 (save-excursion (goto-char (point-min)) (vertical-motion rows) (line-number-at-pos)))))))

(ert-deftest stripe/image-xpm ()
  "The strip's image: an XPM WIDTH wide, a pixel row per character, in the
palette's colours, its top on the line's top."
  (let* ((palette '((?\s . "None") (?t . "#111111") (?6 . "#ff0000")))
         (image (+my/stripe--image " t6" 3 palette)))
    (should (eq (car image) 'image))
    (should (eq (plist-get (cdr image) :type) 'xpm))
    (should (eql (plist-get (cdr image) :ascent) 100))
    (should (eql (plist-get (cdr image) :scale) 1))
    (should (equal (plist-get (cdr image) :data)
                   (concat "/* XPM */\nstatic char *stripe[] = {\n"
                           "\"3 3 3 1\",\n\"  c None\",\n\"t c #111111\",\n\"6 c #ff0000\",\n"
                           "\"   \",\n\"ttt\",\n\"666\"};")))
    (should (equal (+test-stripe--pixels image) " t6"))
    ;; Made anew each time: Emacs caches images, the config flushes the old.
    (should-not (eq image (+my/stripe--image " t6" 3 palette)))))

(ert-deftest stripe/pixel-rank ()
  "Marks by priority, then the band, then nothing."
  (should (= (+my/stripe--pixel-rank ?\s) -1))
  (should (= (+my/stripe--pixel-rank ?t) 0))
  (should (= (+my/stripe--pixel-rank ?1) 1))
  (should (= (+my/stripe--pixel-rank ?6) 6))
  (should (< (+my/stripe--pixel-rank ?\s) (+my/stripe--pixel-rank ?t)
             (+my/stripe--pixel-rank ?1) (+my/stripe--pixel-rank ?2))))

(ert-deftest stripe/anchor ()
  "Cells hang at the start of rows that start a line, on the last character of
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
        (should (= (+my/stripe--anchor window last-row) (1- end-line))))))
  (+test-stripe (make-string 200 ?x)
    (setq truncate-lines nil)
    (let ((second (save-excursion (goto-char 1) (vertical-motion 1) (point)))
          (third (save-excursion (goto-char 1) (vertical-motion 2) (point))))
      (should (= (+my/stripe--anchor (selected-window) third) (point-max)))
      (should (= (+my/stripe--anchor (selected-window) second) (1- third))))))

(ert-deftest stripe/anchor-scrolled-sideways ()
  "The window scrolled sideways: cells hang at the first column shown (Emacs
draws no margin string hung on the part scrolled out of view), at the end of
lines shorter than that; back at the start unscrolled. Each row its cell."
  (+test-stripe (mapconcat (lambda (n) (if (cl-oddp n) (make-string 60 ?x) "short"))
                           (number-sequence 1 30) "\n")
    (setq truncate-lines t)
    (let ((window (selected-window))
          (long (+test-stripe--line-start 1))
          (short (+test-stripe--line-start 2)))
      (set-window-hscroll window 12)
      (should (= (+my/stripe--anchor window long) (+ long 13)))
      (should (= (+my/stripe--anchor window short) (+ short 5)))
      (+my/stripe--render window)
      (let ((overlays (+test-stripe--row-overlays window)))
        (should (= (length overlays) (window-body-height window)))
        (should (= (overlay-start (car overlays)) (+ long 13))))
      (set-window-hscroll window 0)
      (should (= (+my/stripe--anchor window long) long))
      (+my/stripe--render window)
      (should (= (overlay-start (car (+test-stripe--row-overlays window))) long)))))

;; ====== GRAPHICAL FRAMES: THE STRIP'S FRAME ======

;; Batch Emacs makes no child frames: they're stand-ins, the frame functions
;; the config calls answering for them.
(cl-defstruct (+test-stripe--frame (:constructor +test-stripe--frame-make))
  buffer parent (params nil) (visible nil) (live t) size position)

(defvar +test-stripe--made nil "The stand-in frames made, the latest first.")
(defvar +test-stripe--flushed nil "The images flushed.")

(defmacro +test-stripe--frames (&rest body)
  "BODY as in a GUI, the strips' frames stand-ins (`+test-stripe--made')."
  (declare (indent 0))
  `(let ((+test-stripe--made nil)
         (+test-stripe--flushed nil)
         (+my/stripe--frames nil)
         (orig (mapcar (lambda (f) (cons f (symbol-function f)))
                       '(frame-live-p frame-root-window window-buffer set-frame-parameter
                         frame-parameter set-frame-size set-frame-position frame-visible-p
                         make-frame-visible make-frame-invisible delete-frame frame-parent
                         redraw-frame))))
     (cl-flet ((orig (f &rest args) (apply (alist-get f orig) args))
               (fake-p (x) (+test-stripe--frame-p x)))
       (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                 ((symbol-function 'display-multi-font-p) #'ignore)
                 ((symbol-function 'image-flush) (lambda (image &rest _) (push image +test-stripe--flushed)))
                 ;; A stand-in has no window to make bare (see stripe/bare).
                 ((symbol-function '+my/stripe--bare) #'ignore)
                 ((symbol-function '+my/stripe--make-frame)
                  (lambda (parent)
                    (car (push (+test-stripe--frame-make
                                :parent parent
                                :buffer (generate-new-buffer " *+my/stripe-test*"))
                               +test-stripe--made))))
                 ((symbol-function 'frame-live-p)
                  (lambda (f) (if (fake-p f) (+test-stripe--frame-live f) (orig 'frame-live-p f))))
                 ;; Drawn anew (config/stripe/gui.el): nothing to draw here.
                 ((symbol-function 'redraw-frame)
                  (lambda (&optional f) (unless (fake-p f) (orig 'redraw-frame f))))
                 ((symbol-function 'frame-root-window)
                  (lambda (&optional f) (if (fake-p f) f (orig 'frame-root-window f))))
                 ((symbol-function 'window-buffer)
                  (lambda (&optional w) (if (fake-p w) (+test-stripe--frame-buffer w) (orig 'window-buffer w))))
                 ((symbol-function 'set-frame-parameter)
                  (lambda (f p v) (if (fake-p f) (setf (alist-get p (+test-stripe--frame-params f)) v)
                                    (orig 'set-frame-parameter f p v))))
                 ((symbol-function 'frame-parameter)
                  (lambda (f p) (if (fake-p f) (alist-get p (+test-stripe--frame-params f))
                                  (orig 'frame-parameter f p))))
                 ((symbol-function 'set-frame-size)
                  (lambda (f w h &optional pixelwise)
                    (if (fake-p f) (setf (+test-stripe--frame-size f) (list w h pixelwise))
                      (orig 'set-frame-size f w h pixelwise))))
                 ((symbol-function 'set-frame-position)
                  (lambda (f x y) (if (fake-p f) (setf (+test-stripe--frame-position f) (list x y))
                                    (orig 'set-frame-position f x y))))
                 ((symbol-function 'frame-visible-p)
                  (lambda (f) (if (fake-p f) (+test-stripe--frame-visible f) (orig 'frame-visible-p f))))
                 ((symbol-function 'make-frame-visible)
                  (lambda (&optional f) (if (fake-p f) (setf (+test-stripe--frame-visible f) t)
                                          (orig 'make-frame-visible f))))
                 ((symbol-function 'make-frame-invisible)
                  (lambda (&optional f force) (if (fake-p f) (setf (+test-stripe--frame-visible f) nil)
                                                (orig 'make-frame-invisible f force))))
                 ((symbol-function 'delete-frame)
                  (lambda (&optional f force) (if (fake-p f) (setf (+test-stripe--frame-live f) nil)
                                                (orig 'delete-frame f force))))
                 ((symbol-function 'frame-parent)
                  (lambda (&optional f) (if (fake-p f) (+test-stripe--frame-parent f) (orig 'frame-parent f)))))
         (unwind-protect (progn ,@body)
           (dolist (frame +test-stripe--made)
             (when (buffer-live-p (+test-stripe--frame-buffer frame))
               (kill-buffer (+test-stripe--frame-buffer frame)))))))))

(defun +test-stripe--frame-of (window)
  (nth 1 (assq window +my/stripe--frames)))

(defun +test-stripe--shown-image (frame)
  "The image FRAME's buffer shows, and the text properties around it."
  (with-current-buffer (+test-stripe--frame-buffer frame)
    (and (> (point-max) (point-min))
         (list (get-text-property (point-min) 'display)
               (get-text-property (point-min) 'keymap)
               (get-text-property (point-min) 'pointer)))))

(ert-deftest stripe/bare ()
  "The strip's window all text: its margins (a file's, the first buffer it
showed), fringes and horizontal scroll taken off. Emacs only changes a window's
margins if it's left two columns wide: a narrower frame is widened first."
  (+test-with-reset
    (let ((window (selected-window))
          (sized nil))
      (set-window-margins window nil 1)
      (set-window-fringes window 8 8)
      (set-window-hscroll window 4)
      (cl-letf (((symbol-function 'set-frame-size) (lambda (&rest args) (push args sized))))
        (+my/stripe--bare (selected-frame)))
      (should (equal (window-margins window) '(nil)))
      (should (equal (seq-take (window-fringes window) 2) '(0 0)))
      (should (= (window-hscroll window) 0))
      (should-not sized)                  ; wide already
      ;; Narrow: widened first, to be placed again.
      (set-window-margins window nil 1)
      (cl-letf (((symbol-function 'window-total-width) (lambda (&rest _) 1))
                ((symbol-function 'set-frame-size) (lambda (&rest args) (push args sized))))
        (+my/stripe--bare (selected-frame)))
      (should (= (length sized) 1))
      (should (= (nth 1 (car sized)) (* 10 (frame-char-width))))
      (should-not (frame-parameter nil '+my/stripe-geometry))
      (set-window-fringes window nil nil))))

(ert-deftest stripe/a-frame-over-the-right-margin ()
  "Synced: the window's strip frame, a child of its frame, laid over its right
margin (beside the text, at the edge), shown, drawing the strip."
  (+test-stripe (+test-stripe--text 100)
    ;; Drawn as cells when the mode came on (the batch frame is a terminal).
    (remove-overlays (point-min) (point-max) '+my/stripe-row t)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let* ((window (selected-window))
             (frame (+test-stripe--frame-of window))
             (geometry (+my/stripe--geometry window)))
        (should (+test-stripe--frame-p frame))
        (should (eq (+test-stripe--frame-parent frame) (window-frame window)))
        (should (+test-stripe--frame-visible frame))
        (should (eq (alist-get '+my/stripe-window (+test-stripe--frame-params frame)) window))
        (should (equal (+test-stripe--frame-position frame) (seq-take geometry 2)))
        (should (equal (+test-stripe--frame-size frame) (list (nth 2 geometry) (nth 3 geometry) t)))
        ;; The margin: a column wide, beside the text, as tall as it.
        (should (= (nth 2 geometry) (frame-char-width)))
        (should (= (+ (nth 0 geometry) (nth 2 geometry))
                   (- (nth 2 (window-pixel-edges window))
                      (window-right-divider-width window) (window-scroll-bar-width window))))
        (should (= (nth 1 geometry) (nth 1 (window-inside-pixel-edges window))))
        (should (= (nth 3 geometry) (window-body-height window t)))
        (pcase-let ((`(,image ,keymap ,pointer) (+test-stripe--shown-image frame)))
          (should (eq (plist-get (cdr image) :type) 'xpm))
          (should (eq keymap +my/stripe--strip-map))
          (should (eq pointer 'hand)))
        ;; Nothing in the window's own rows (a terminal's cells only).
        (should-not (+test-stripe--row-overlays window))))))

(ert-deftest stripe/a-frame-per-window-hidden-and-deleted ()
  "Each window its own; hidden (kept) while its window shows another buffer,
shown again when it's back; deleted with its window."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (let* ((left (selected-window))
             (right (split-window-right)))
        (+my/stripe--sync)
        (let ((a (+test-stripe--frame-of left))
              (b (+test-stripe--frame-of right)))
          (should (and a b (not (eq a b))))
          (set-window-buffer right (get-buffer-create "*scratch*"))
          (+my/stripe--sync)
          (should-not (+test-stripe--frame-visible b))
          (should (+test-stripe--frame-live b))
          (set-window-buffer right "stripe")
          (+my/stripe--sync)
          (should (eq (+test-stripe--frame-of right) b))
          (should (+test-stripe--frame-visible b))
          (delete-window right)
          (+my/stripe--sync)
          (should-not (+test-stripe--frame-live b))
          (should-not (assq right +my/stripe--frames))
          (should (+test-stripe--frame-visible a)))))))

(ert-deftest stripe/a-hidden-frame-x-calls-iconified-is-shown-again ()
  "Hidden right after it was shown, X calls the frame iconified (`icon'), off
the screen all the same: back in the window, it's shown again."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (let ((window (selected-window)))
        (+my/stripe--sync)
        (let ((frame (+test-stripe--frame-of window)))
          (set-window-buffer window (get-buffer-create "*scratch*"))
          (+my/stripe--sync)
          (setf (+test-stripe--frame-visible frame) 'icon)
          (set-window-buffer window "stripe")
          (+my/stripe--sync)
          (should (eq (+test-stripe--frame-visible frame) t)))))))

(ert-deftest stripe/a-dead-frame-is-made-again ()
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let ((first (+test-stripe--frame-of (selected-window))))
        (setf (+test-stripe--frame-live first) nil)
        (+my/stripe--sync)
        (should-not (eq (+test-stripe--frame-of (selected-window)) first))
        (should (+test-stripe--frame-live (+test-stripe--frame-of (selected-window))))))))

(ert-deftest stripe/the-image-made-only-when-the-strip-changes ()
  "Redrawn without a change: the image is left as it is; changed (the band
moved): a new one, the old one flushed from Emacs's image cache."
  (+test-stripe (+test-stripe--text 400)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let* ((window (selected-window))
             (frame (+test-stripe--frame-of window))
             (tick (lambda () (buffer-modified-tick (+test-stripe--frame-buffer frame))))
             (before (funcall tick))
             (image (car (+test-stripe--shown-image frame))))
        (+my/stripe--render window)
        (+my/stripe--render window)
        (should (= (funcall tick) before))
        (should-not +test-stripe--flushed)
        (set-window-start window (+test-stripe--line-start 300))
        (+my/stripe--render window)
        (should (> (funcall tick) before))
        (should (equal +test-stripe--flushed (list image)))
        (should-not (equal (car (+test-stripe--shown-image frame)) image))))))

(ert-deftest stripe/no-frame-yet-one-is-made-after-this-redisplay ()
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (let (scheduled)
        (cl-letf (((symbol-function 'run-at-time)
                   (lambda (time repeat fn &rest _) (push (list time repeat fn) scheduled) 'timer))
                  ((symbol-function 'timerp) (lambda (x) (eq x 'timer))))
          (let ((+my/stripe--sync-timer nil))
            (+my/stripe--render (selected-window))
            (should (equal (mapcar (lambda (s) (seq-take s 2)) scheduled) '((0 nil))))
            ;; Once scheduled, not again.
            (+my/stripe--render (selected-window))
            (should (= (length scheduled) 1))
            ;; Then it syncs.
            (let (synced)
              (cl-letf (((symbol-function '+my/stripe--sync) (lambda () (push t synced))))
                (funcall (nth 2 (car scheduled))))
              (should synced))))))))

(ert-deftest stripe/a-moved-window-s-frame-is-placed-anew ()
  "The window's text moved down (a notice's header line): synced again."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let (synced)
        (cl-letf (((symbol-function '+my/stripe--sync-soon) (lambda (&rest _) (push t synced))))
          (+my/stripe--render (selected-window))
          (should-not synced)
          (setq-local header-line-format "a notice")
          (+my/stripe--render (selected-window))
          (should synced))))))

(ert-deftest stripe/no-margin-no-frame-shown ()
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let ((frame (+test-stripe--frame-of (selected-window))))
        (set-window-margins nil nil 0)
        (+my/stripe--show-in (selected-window))
        (should-not (+test-stripe--frame-visible frame))))))

(ert-deftest stripe/not-in-a-child-frame-s-windows ()
  "A window of a child frame (a popup's, a strip's own): no strip."
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (let (synced)
        (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) 'a-parent))
                  ((symbol-function '+my/stripe--sync-soon) (lambda (&rest _) (push t synced))))
          (+my/stripe--render (selected-window)))
        (should-not synced)
        (should-not +my/stripe--frames)))))

(ert-deftest stripe/no-frames-in-a-terminal ()
  (+test-stripe (+test-stripe--text 100)
    (let ((+my/stripe--frames nil)
          (made nil))
      (cl-letf (((symbol-function '+my/stripe--make-frame) (lambda (&rest _) (push t made))))
        (+my/stripe--sync))
      (should-not made)
      (should-not +my/stripe--frames))))

(ert-deftest stripe/a-theme-gives-the-frames-its-background ()
  (+test-stripe (+test-stripe--text 100)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let ((frame (+test-stripe--frame-of (selected-window))))
        (cl-letf (((symbol-function 'face-background) (lambda (&rest _) "#123456")))
          (+my/stripe--render-all))
        (should (equal (alist-get 'background-color (+test-stripe--frame-params frame)) "#123456"))))))

(ert-deftest stripe/window-change-syncs-soon ()
  (should (memq #'+my/stripe--window-change-h (default-value 'window-state-change-functions)))
  (let (synced)
    (cl-letf (((symbol-function '+my/stripe--sync-soon) (lambda (&rest _) (push t synced))))
      (+my/stripe--window-change-h (selected-frame))
      (should synced)
      (setq synced nil)
      (cl-letf (((symbol-function 'frame-parent) (lambda (&optional _) 'a-parent)))
        (+my/stripe--window-change-h (selected-frame)))
      (should-not synced))))

;; ====== DRAWING ======

(ert-deftest stripe/key ()
  "What a window's strip depends on: buffer, start, vscroll, size, font,
margin, errors, git highlights, line edits, where the window is (its edges,
its header and tab lines: a notice above moves the strip), how far it's
scrolled sideways."
  (+test-stripe (+test-stripe--text 50)
    (+test-stripe--errors '(3 error))
    (let ((window (selected-window)))
      (should (equal (+my/stripe--key window)
                     (append (list (current-buffer) (window-start window) 0
                                   (window-body-height window t) (window-font-height window)
                                   1 flycheck-current-errors +my/stripe--diff-hl-tick
                                   +my/stripe--line-edits
                                   (window-header-line-height window)
                                   (window-tab-line-height window)
                                   (window-hscroll window))
                             (window-pixel-edges window))))
      (should (= (nth 1 (+my/stripe--key window 42)) 42))
      ;; Each part compares with `eq' (no list: edges are its last parts).
      (should (cl-every #'eq (+my/stripe--key window) (+my/stripe--key window)))
      (setq-local header-line-format "a notice")
      (should-not (cl-every #'eq (+my/stripe--key window)
                            (progn (setq-local header-line-format nil) (+my/stripe--key window)))))))

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
    (should (equal (window-parameter nil '+my/stripe-geometry) (list 'cells (window-body-height) 101)))))

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

(ert-deftest stripe/todo-edits-counted ()
  "Edits within a line that add or remove a TODO keyword are counted (the strip
is redrawn for them), as are other edits of lines with one; others aren't."
  (+test-stripe "one\ntwo\n"
    (cl-flet ((counted (fn)
                (let ((count +my/stripe--line-edits))
                  (funcall fn)
                  (> +my/stripe--line-edits count))))
      (goto-char (point-max))
      (should-not (counted (lambda () (insert "TOD"))))
      (should (counted (lambda () (insert "O"))))                 ; added
      (should (counted (lambda ()                                 ; its line
                         (goto-char (+test-stripe--line-start 3))
                         (insert "- "))))
      (should-not (counted (lambda ()                             ; another line
                             (goto-char (point-min))
                             (insert "y"))))
      (should (counted (lambda ()                                 ; removed
                         (goto-char (point-max))
                         (delete-char -1))))
      (let ((+my/stripe-todo-keywords nil))
        (should-not (counted (lambda () (insert "O"))))))))

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
  "When redisplay itself scrolled near the end, the limit is checked right after."
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
        (set-window-parameter window '+my/stripe-key '(old))
        (funcall (nth 2 (car scheduled)))
        (should (= (window-start window) (car (+my/stripe--end-limit window))))
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

;; ====== CLICKS ON THE STRIP ======

;; Events on the strip's frame: its window a stand-in (see the frame tests).
(defun +test-stripe--strip-event (type window y &optional extra)
  "A TYPE event on WINDOW's strip, Y pixels down the image."
  `(,type (strip-window 1 (0 . ,y) 0 nil 1 (0 . 0) nil (0 . ,y) (7 . 600)) ,@extra))

(defmacro +test-stripe--on-strip (window &rest body)
  "BODY with clicks on a strip taken as WINDOW's, focus changes ignored."
  (declare (indent 1))
  `(cl-letf (((symbol-function '+my/stripe--window-of) (lambda (_) ,window))
             ((symbol-function 'select-frame-set-input-focus) #'ignore))
     ,@body))

(ert-deftest stripe/the-strip-s-keys ()
  (should (eq (lookup-key +my/stripe--strip-map [down-mouse-1]) #'+my/stripe-press))
  (dolist (event '(mouse-1 drag-mouse-1 double-mouse-1 mouse-3))
    (should (eq (lookup-key +my/stripe--strip-map (vector event)) #'ignore)))
  (dolist (event '(wheel-up wheel-down double-wheel-down triple-wheel-up))
    (should (eq (lookup-key +my/stripe--strip-map (vector event)) #'+my/stripe-wheel))))

(ert-deftest stripe/window-of-a-strip ()
  (+test-stripe (+test-stripe--text 10)
    (+test-stripe--frames
      (+my/stripe--sync)
      (let* ((window (selected-window))
             (frame (+test-stripe--frame-of window)))
        (cl-letf (((symbol-function 'window-frame) (lambda (&optional w) (if (eq w 'strip-window) frame (selected-frame)))))
          (should (eq (+my/stripe--window-of (+test-stripe--strip-event 'mouse-1 window 3)) window))
          (setf (alist-get '+my/stripe-window (+test-stripe--frame-params frame)) nil)
          (should-not (+my/stripe--window-of (+test-stripe--strip-event 'mouse-1 window 3))))))))

(ert-deftest stripe/press-off-the-band-jumps-there ()
  "A press on the strip off the band: that part of the file, in the middle
of the window, `C-o' going back."
  (+test-stripe (+test-stripe--text 100)
    (let* ((window (selected-window))
           (jumped nil))
      (set-window-parameter window '+my/stripe-geometry '(pixels 1.0 100 (0 . 5)))
      (+test-stripe--on-strip window
        (cl-letf (((symbol-function '+my/stripe--goto-line)
                   (lambda (w line) (setq jumped (list w line)))))
          (+my/stripe-press (+test-stripe--strip-event 'down-mouse-1 window 40))))
      (should (equal jumped (list window 41))))))

(ert-deftest stripe/press-past-the-end-goes-to-the-last-line ()
  (+test-stripe (+test-stripe--text 100)
    (let ((window (selected-window)) jumped)
      (set-window-parameter window '+my/stripe-geometry '(pixels 1.0 100 nil))
      (+test-stripe--on-strip window
        (cl-letf (((symbol-function '+my/stripe--goto-line) (lambda (_ line) (setq jumped line))))
          (+my/stripe-press (+test-stripe--strip-event 'down-mouse-1 window 500))))
      (should (= jumped 100)))))

(ert-deftest stripe/drag-the-band ()
  "A press on the band holds it: as the mouse moves, the window scrolls so the
band follows (where it was grabbed stays under the mouse); the release ends it."
  (+test-stripe (+test-stripe--text 200)
    (let* ((window (selected-window))
           (positions (list '(0 . 1035) '(0 . 1060) '(0 . 1080) '(0 . 1080)))
           (events (list '(mouse-movement (strip-window 1 (0 . 0) 0))
                         '(mouse-movement (strip-window 1 (0 . 0) 0))
                         '(mouse-1 (strip-window 1 (0 . 0) 0))))
           (unread-command-events nil))
      (set-window-parameter window '+my/stripe-geometry '(pixels 1.0 200 (30 . 40)))
      (+test-stripe--on-strip window
        (cl-letf (((symbol-function 'mouse-absolute-pixel-position)
                   (lambda () (if (cdr positions) (pop positions) (car positions))))
                  ((symbol-function 'read-event) (lambda (&rest _) (pop events)))
                  ((symbol-function 'redisplay) #'ignore))
          ;; Pressed 35 px down the strip (5 into the band) with the mouse at
          ;; 1035 on the screen: the strip's top is at 1000.
          (+my/stripe-press (+test-stripe--strip-event 'down-mouse-1 window 35))))
      ;; The last move: the mouse at 1080, the band's top at 1080 - 1000 - 5.
      (should (= (line-number-at-pos (window-start window)) 76))
      (should-not unread-command-events))))

(ert-deftest stripe/drag-ended-by-a-key-keeps-the-key ()
  (+test-stripe (+test-stripe--text 200)
    (let* ((window (selected-window))
           (events (list '(mouse-movement (strip-window 1 (0 . 0) 0)) ?x))
           (unread-command-events nil))
      (set-window-parameter window '+my/stripe-geometry '(pixels 1.0 200 (30 . 40)))
      (+test-stripe--on-strip window
        (cl-letf (((symbol-function 'mouse-absolute-pixel-position) (lambda () '(0 . 1050)))
                  ((symbol-function 'read-event) (lambda (&rest _) (pop events)))
                  ((symbol-function 'redisplay) #'ignore))
          (+my/stripe-press (+test-stripe--strip-event 'down-mouse-1 window 35))))
      (should (equal unread-command-events '(?x))))))

(ert-deftest stripe/pointer-y-on-the-screen-or-in-the-frame ()
  "The mouse's height: the screen's (macOS, X11); on Wayland (pgtk) the
file's frame's, the strip's frame's offset in it added; over another frame,
none."
  (+test-stripe (+test-stripe--text 10)
    (let* ((window (selected-window))
           (frame (selected-frame))
           (strip 'strip-frame)
           (under (cons frame (cons 5 40))))
      (cl-letf (((symbol-function 'mouse-absolute-pixel-position) (lambda () '(3 . 1040))))
        (should (= (+my/stripe--pointer-y window) 1040)))
      (cl-letf* ((framep-fn (symbol-function 'framep))
                 ((symbol-function 'framep) (lambda (f) (if (eq f frame) 'pgtk (funcall framep-fn f))))
                 ((symbol-function 'mouse-absolute-pixel-position) (lambda () (error "No screen")))
                 ((symbol-function 'mouse-pixel-position) (lambda () under))
                 ((symbol-function 'frame-parent) (lambda (f) (and (eq f strip) frame)))
                 ((symbol-function 'frame-position) (lambda (f) (if (eq f strip) '(900 . 30) '(0 . 0)))))
        (should (= (+my/stripe--pointer-y window) 40))
        (setq under (cons strip (cons 2 15)))
        (should (= (+my/stripe--pointer-y window) 45))
        (setq under (cons 'other-frame (cons 2 15)))
        (should-not (+my/stripe--pointer-y window))
        (setq under (cons frame (cons nil nil)))
        (should-not (+my/stripe--pointer-y window))))))

(ert-deftest stripe/drag-the-band-on-wayland ()
  "The same drag with the frame's heights (pgtk): the band follows."
  (+test-stripe (+test-stripe--text 200)
    (let* ((window (selected-window))
           (positions (list 35 60 80 80))
           (events (list '(mouse-movement (strip-window 1 (0 . 0) 0))
                         '(mouse-movement (strip-window 1 (0 . 0) 0))
                         '(mouse-1 (strip-window 1 (0 . 0) 0))))
           (unread-command-events nil))
      (set-window-parameter window '+my/stripe-geometry '(pixels 1.0 200 (30 . 40)))
      (+test-stripe--on-strip window
        (cl-letf (((symbol-function '+my/stripe--pointer-y)
                   (lambda (_) (if (cdr positions) (pop positions) (car positions))))
                  ((symbol-function 'read-event) (lambda (&rest _) (pop events)))
                  ((symbol-function 'redisplay) #'ignore))
          (+my/stripe-press (+test-stripe--strip-event 'down-mouse-1 window 35))))
      (should (= (line-number-at-pos (window-start window)) 76)))))

(ert-deftest stripe/scroll-band-to ()
  (+test-stripe (+test-stripe--text 100)
    (let ((window (selected-window)))
      (+my/stripe--scroll-band-to window 49.5 1.0)
      (should (= (window-start window) (+test-stripe--line-start 50)))
      (+my/stripe--scroll-band-to window 20 0.5)
      (should (= (window-start window) (+test-stripe--line-start 41)))
      (+my/stripe--scroll-band-to window -5 1.0)
      (should (= (window-start window) (point-min))))))

(ert-deftest stripe/press-not-on-a-strip-does-nothing ()
  (+test-stripe (+test-stripe--text 100)
    (let ((window (selected-window)) jumped)
      (cl-letf (((symbol-function '+my/stripe--window-of) #'ignore)
                ((symbol-function '+my/stripe--goto-line) (lambda (&rest _) (setq jumped t))))
        (+my/stripe-press (+test-stripe--strip-event 'down-mouse-1 window 3)))
      (should-not jumped))))

(ert-deftest stripe/the-wheel-scrolls-the-file ()
  "The wheel over the strip: the file's window's wheel command, the event
given that window (its pixel deltas kept)."
  (+test-stripe (+test-stripe--text 100)
    (let ((window (selected-window))
          (got nil))
      (+test-stripe--on-strip window
        (cl-letf (((symbol-function 'key-binding)
                   (lambda (keys &rest _)
                     (should (equal keys [wheel-down]))
                     (lambda (event) (interactive "e") (setq got (list (selected-window) event))))))
          (+my/stripe-wheel (+test-stripe--strip-event 'wheel-down window 3 '(1 (0 . 12))))))
      (pcase-let ((`(,_ ,event) got))
        (should (eq (car event) 'wheel-down))
        (should (eq (posn-window (event-start event)) window))
        (should (equal (nthcdr 2 event) '(1 (0 . 12))))))))

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

(defun +test-stripe--text-click (window column row &optional type)
  "A mouse event (TYPE, default mouse-1) in WINDOW's text area at COLUMN, ROW,
as a terminal reports one."
  (let ((pos (with-current-buffer (window-buffer window) (point-min))))
    `(,(or type 'mouse-1) (,window ,pos (,column . ,row) 0 nil ,pos (,column . ,row) nil (0 . 0) (1 . 1)))))

(ert-deftest stripe/click-on-the-strip-reported-in-the-text-jumps ()
  "A terminal reports a click on the strip of a window with another to its
right as in its text, past its columns: it jumps to its cell's lines. A click
on the text's last column doesn't."
  (+test-stripe (+test-stripe--text 100)
    (let* ((left (selected-window))
           (right (split-window-right 30)))
      (set-window-buffer right (current-buffer))
      (+my/stripe--render left)
      (let* ((rows (window-body-height left))
             (column (window-body-width left))
             (strip (+test-stripe--text-click left column 11))
             (text (+test-stripe--text-click left (1- column) 11)))
        (should (+my/stripe--tty-strip-click-p strip))
        (should-not (+my/stripe--tty-strip-click-p text))
        (should-not (+my/stripe--tty-strip-click-p (+test-stripe--text-click right column 11)))
        (select-window right)
        (+my/stripe-jump text)
        (should (eq (selected-window) right))
        (+my/stripe-jump strip)
        (should (eq (selected-window) left))
        (should (= (line-number-at-pos) (+my/stripe--row-to-line 11 101 rows)))))))

(ert-deftest stripe/clicks-on-the-strip-in-the-text-before-evil ()
  "Those clicks are the stripe's, before Evil's (its region drag, the cursor
moved): the press and a double click do nothing, the release jumps. Clicks in
the text stay Evil's."
  (require 'evil)
  (+test-stripe (+test-stripe--text 100)
    (evil-local-mode 1)
    (unwind-protect
        (let ((left (selected-window)))
          (+my/stripe-mode -1)
          (setq emulation-mode-map-alists (append (delq '+my/stripe--emulation-alist emulation-mode-map-alists)
                                                  '(+my/stripe--emulation-alist)))
          (+my/stripe-mode 1)
          (should (eq (car emulation-mode-map-alists) '+my/stripe--emulation-alist))
          (set-window-buffer (split-window-right 30) (current-buffer))
          (+my/stripe--render left)
          (cl-flet ((binding (type column)
                      (let ((last-input-event (+test-stripe--text-click left column 3 type)))
                        (key-binding (vector type) t nil (event-start last-input-event)))))
            (let ((strip (window-body-width left)))
              (should (eq (binding 'down-mouse-1 strip) #'ignore))
              (should (eq (binding 'mouse-1 strip) #'+my/stripe-jump))
              (should (eq (binding 'double-mouse-1 strip) #'ignore))
              (should (eq (binding 'down-mouse-1 (1- strip)) #'evil-mouse-drag-region))
              (should (eq (binding 'mouse-1 (1- strip)) #'mouse-set-point)))))
      (evil-local-mode -1))))

(ert-deftest stripe/goto-line-selects-the-window-and-marks-the-jump ()
  "A jump from the strip: its window selected, the line in its middle, `C-o'
going back (a better-jumper jump)."
  (+test-stripe (+test-stripe--text 100)
    (let* ((left (selected-window))
           (right (split-window-right))
           (jumps nil)
           (recentered nil))
      (cl-letf (((symbol-function 'better-jumper-set-jump)
                 (lambda (&rest _) (push (cons (selected-window) (point)) jumps)))
                ((symbol-function 'recenter)
                 (lambda (&rest _) (setq recentered (selected-window)))))
        (+my/stripe--goto-line right 41))
      (should (eq (selected-window) right))
      (should (= (line-number-at-pos (window-point right)) 41))
      (should (equal jumps (list (cons right 1))))
      (should (eq recentered right))
      (should (window-live-p left)))))

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
  "A margin column for the strip (its frame lies over it; a terminal's cells),
at the very edge (fringes inside), its hooks, the strip drawn in the windows
showing the buffer, and its frames synced soon."
  (let (scheduled)
    (cl-letf (((symbol-function '+my/stripe--sync-soon) (lambda (&rest _) (push t scheduled))))
      (+test-stripe (+test-stripe--text 50)
        (should (local-variable-p 'right-margin-width))
        (should (= right-margin-width 1))
        (should (local-variable-p 'fringes-outside-margins))
        (should-not fringes-outside-margins)
        (should (equal (cdr (window-margins)) 1))
        (pcase-dolist (`(,hook . ,fn) '((window-scroll-functions . +my/stripe--scrolled)
                                        (window-scroll-functions . +my/stripe--after-scroll)
                                        (before-change-functions . +my/stripe--note-line-edit)
                                        (after-change-functions . +my/stripe--note-line-edit)))
          (should (local-variable-p hook))
          (should (memq fn (symbol-value hook)))
          (should-not (memq fn (default-value hook))))
        ;; No cursor juggling at the end of the buffer any more.
        (should-not (memq '+my/stripe--leave-phantom-line post-command-hook))
        (should (+test-stripe--row-overlays))
        (should scheduled)))))

(ert-deftest stripe/mode-off ()
  "Off: the cells and hooks gone, margin and fringes back to normal, the
strips' frames synced (its window's hidden)."
  (+test-stripe (+test-stripe--text 50)
    (+my/stripe--marks)
    (setq-local left-fringe-width 16)
    (setq-local right-fringe-width 16)
    (let (scheduled)
      (cl-letf (((symbol-function '+my/stripe--sync-soon) (lambda (&rest _) (push t scheduled))))
        (+my/stripe-mode -1))
      (should scheduled))
    (should-not (seq-find (lambda (ov) (overlay-get ov '+my/stripe))
                          (overlays-in (point-min) (point-max))))
    (should-not +my/stripe--cache)
    (dolist (var '(right-margin-width fringes-outside-margins left-fringe-width right-fringe-width))
      (should-not (local-variable-p var)))
    (should-not (cdr (window-margins)))
    (dolist (hook '(window-scroll-functions before-change-functions after-change-functions))
      (dolist (fn '(+my/stripe--scrolled +my/stripe--after-scroll +my/stripe--note-line-edit))
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
