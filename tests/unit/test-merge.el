;;; tests/unit/test-merge.el -*- lexical-binding: t; -*-
;; config/merge.el: conflicts resolved in three panes (Yours, the Result,
;; Theirs) under a bar. Real git in temp repos (a temp HOME and global
;; gitconfig: the user's never read), a file conflicting each way: a change
;; only one side made, a conflict, the same change on both sides, lines
;; removed and added. The versions from Git's index, the changes (Ediff's), the
;; panes and their buttons, applying, ignoring, keeping both, undo, Accept
;; Left / Right, Apply non-conflicting, Done (written, staged; with changes
;; left: conflict markers), Abort, the fallback to Ediff, Magit's e.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/merge")

;; As config/emacs/compile.el does once Emacs is idle a moment after it started:
;; the functions byte-compiled before Magit, Ediff or smerge loaded. A
;; function loading its package then using the package's macro or binding its
;; variable, compiled so, failed the first time it ran (compile.el puts a
;; function back to its source once the package loads, for its next call
;; only): the merge example's first run, "You have killed a vital Ediff
;; buffer".
(defconst +test-merge--packages-before (list (featurep 'magit) (featurep 'ediff) (featurep 'smerge-mode))
  "Magit, Ediff, smerge loaded as the functions were compiled (none).")

(let ((byte-compile-warnings nil)
      (inhibit-message t))
  (mapatoms (lambda (symbol)
              (when (and (string-prefix-p "+my/merge" (symbol-name symbol))
                         (interpreted-function-p (symbol-function symbol)))
                (byte-compile symbol)))))

(require 'magit)
(require 'magit-ediff)

;; ====== A REPO WITH A CONFLICT ======

(defun +test-merge--git (&rest args)
  "Run git with ARGS in `default-directory'; its output (error if it failed)."
  (with-temp-buffer
    (let ((status (apply #'call-process "git" nil t nil args)))
      (unless (zerop status)
        (error "git %s: %s" (string-join args " ") (buffer-string)))
      (buffer-string))))

(defun +test-merge--git-may-fail (&rest args)
  (with-temp-buffer (apply #'call-process "git" nil t nil args)))

(defun +test-merge--write (file content &optional coding)
  (make-directory (file-name-directory (expand-file-name file)) t)
  (let ((coding-system-for-write (or coding 'utf-8-unix)))
    (with-temp-file (expand-file-name file) (insert content))))

(defun +test-merge--read (file)
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix))
      (insert-file-contents (expand-file-name file)))
    (buffer-string)))

(defun +test-merge--lines (&rest lines)
  (mapconcat (lambda (line) (concat line "\n")) lines ""))

(defconst +test-merge--base
  (+test-merge--lines "one" "two" "three" "four" "five" "six" "seven" "eight" "nine" "ten" "eleven" "twelve"))

(defconst +test-merge--yours
  ;; two changed (only yours), six (conflict), eight (the same on both), ten removed.
  (+test-merge--lines "one" "TWO" "three" "four" "five" "six yours" "seven" "EIGHT" "nine" "eleven" "twelve"))

(defconst +test-merge--theirs
  ;; four changed (only theirs), six (conflict), eight (the same), thirteen added.
  (+test-merge--lines "one" "two" "three" "FOUR" "five" "six theirs" "seven" "EIGHT" "nine" "ten" "eleven" "twelve"
                      "thirteen"))

(defmacro +test-merge-with-repo (&rest body)
  "BODY in a new git repo (`default-directory') on main, a temp HOME and
global gitconfig; one window on *scratch*, and again after."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "merge-home-") t)))
            (repo (file-name-as-directory (make-temp-file (+test-tmp-file "merge-repo-") t)))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1"
                           (concat "XDG_CONFIG_HOME=" home ".config")
                           "GIT_TERMINAL_PROMPT=0" "GIT_EDITOR=true")
                     process-environment))
            (default-directory repo))
       (with-temp-file (expand-file-name ".gitconfig" home)
         (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                 "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
       (+test-merge--git "init" "-q")
       (unwind-protect
           ;; A question no test answers fails it (batch Emacs would wait on stdin).
           (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (error "Asked: %s" prompt)))
                     ((symbol-function 'yes-or-no-p) (lambda (prompt) (error "Asked: %s" prompt))))
             ,@body)
         ;; A merge left open (the test failed): closed, none to come, so the
         ;; tests after start clean.
         (setq +my/merge--then nil)
         (dolist (buffer (buffer-list))
           (when-let* ((session (buffer-local-value '+my/merge--session buffer)))
             (+my/merge--finish session)))
         (+test-merge--fire #'+my/merge--finish)
         (dolist (buffer (buffer-list))
           (with-current-buffer buffer
             (when (and buffer-file-name (string-prefix-p repo buffer-file-name))
               (set-buffer-modified-p nil))))))))

(defun +test-merge--conflict (file base yours theirs &optional coding)
  "FILE committed as BASE, changed to YOURS on main and THEIRS on feature,
feature merged into main: in conflict."
  (+test-merge--write file base coding)
  (+test-merge--git "add" ".")
  (+test-merge--git "commit" "-qm" "base")
  (+test-merge--git "checkout" "-qb" "feature")
  (+test-merge--write file theirs coding)
  (+test-merge--git "commit" "-qam" "theirs")
  (+test-merge--git "checkout" "-q" "main")
  (+test-merge--write file yours coding)
  (+test-merge--git "commit" "-qam" "yours")
  (should-not (zerop (+test-merge--git-may-fail "merge" "-q" "feature")))
  (should (string-match-p "UU" (+test-merge--git "status" "--porcelain"))))

(defun +test-merge--open (&optional file)
  "Open the merge of FILE (default a.txt): its session."
  (let ((session (+my/merge (or file "a.txt"))))
    (should (+my/merge-p session))
    session))

(defmacro +test-merge (&rest body)
  "BODY with a.txt in conflict (see `+test-merge--base'), its merge open as
`session'."
  (declare (indent 0))
  `(+test-merge-with-repo
     (+test-merge--conflict "a.txt" +test-merge--base +test-merge--yours +test-merge--theirs)
     (let ((session (+test-merge--open)))
       (unwind-protect (progn ,@body)
         (+my/merge--finish session)))))

(defun +test-merge--fire (function)
  "Run the pending timers calling FUNCTION now, once; return how many."
  (let ((timers (seq-filter (lambda (timer) (eq (timer--function timer) function))
                            (append timer-list timer-idle-list))))
    (mapc #'cancel-timer timers)
    (dolist (timer timers)
      (apply (timer--function timer) (timer--args timer)))
    (length timers)))

(defun +my/merge-take-both-for-test (session)
  "Each change of SESSION: Yours', then Theirs'."
  (seq-doseq (chunk (+my/merge-chunks session))
    (+my/merge--decide chunk 'yours 'applied)
    (+my/merge--decide chunk 'theirs 'applied)))

(defun +test-merge--result (session)
  "SESSION's Result as it'll be saved (without fillers)."
  (+my/merge--result-text session))

(defun +test-merge--clean (buffer)
  (with-current-buffer buffer
    (+my/merge--clean (point-min) (point-max))))

(defun +test-merge--chunk (session n)
  (aref (+my/merge-chunks session) n))

(defun +test-merge--margin (session side)
  "The margin texts in SIDE's pane (yours, theirs), in order: (LINE . TEXT)."
  (let ((buffer (if (eq side 'yours) (+my/merge-yours session) (+my/merge-theirs session))))
    (with-current-buffer buffer
      (sort (delq nil (mapcar (lambda (ov)
                                (when-let* ((before (overlay-get ov 'before-string))
                                            (display (get-text-property 0 'display before))
                                            ((eq (car-safe (car-safe display)) 'margin)))
                                  (cons (line-number-at-pos (overlay-start ov))
                                        (substring-no-properties (cadr display)))))
                              (overlays-in (point-min) (point-max))))
            (lambda (a b) (< (car a) (car b)))))))

;; ====== OPENING ======

(ert-deftest merge/compiled-before-its-packages ()
  "The functions were compiled before Magit, Ediff and smerge loaded, as
config/emacs/compile.el may (the other tests run them so)."
  (should (equal +test-merge--packages-before '(nil nil nil)))
  (should (byte-code-function-p (symbol-function '+my/merge--diff3)))
  (should (byte-code-function-p (symbol-function '+my/merge))))

(ert-deftest merge/magits-e-resolves-with-it ()
  (should (eq magit-ediff-dwim-resolve-function #'+my/merge)))

(ert-deftest merge/three-panes-under-a-bar ()
  (+test-merge
    (pcase-let ((`(,left ,middle ,right ,bar) (list (get-buffer-window (+my/merge-yours session))
                                                     (get-buffer-window (+my/merge-result session))
                                                     (get-buffer-window (+my/merge-theirs session))
                                                     (get-buffer-window (+my/merge-bar session)))))
      (should (and left middle right bar))
      ;; Side by side, the bar above them all, the Result selected.
      (should (< (car (window-edges left)) (car (window-edges middle)) (car (window-edges right))))
      (should (< (cadr (window-edges bar)) (cadr (window-edges middle))))
      (should (= (window-height bar) 1))
      (should (eq (selected-window) middle))
      ;; The buttons' margins, by the Result.
      (should (equal (window-margins left) '(nil . 5)))
      (should (equal (window-margins right) '(5)))
      (should (window-parameter bar 'no-other-window)))
    ;; The versions: Git's.
    (should (equal (+test-merge--clean (+my/merge-yours session)) +test-merge--yours))
    (should (equal (+test-merge--clean (+my/merge-theirs session)) +test-merge--theirs))
    (should (equal (+test-merge--result session) +test-merge--base))
    ;; What they are.
    (should (equal (+my/merge-labels session) (cons "main" "feature")))
    (should (string-match-p "Yours: main" (with-current-buffer (+my/merge-yours session) header-line-format)))
    (should (string-match-p "Theirs: feature" (with-current-buffer (+my/merge-theirs session) header-line-format)))
    ;; The sides read-only, the Result editable; their mode the file's.
    (should (buffer-local-value 'buffer-read-only (+my/merge-yours session)))
    (should-not (buffer-local-value 'buffer-read-only (+my/merge-result session)))
    (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
      (with-current-buffer buffer
        (should +my/merge-mode)
        (should-not buffer-file-name)
        (should (derived-mode-p 'text-mode))))))

(ert-deftest merge/the-changes-and-what-they-are ()
  (+test-merge
    (should (equal (mapcar #'+my/merge-chunk-kind (+my/merge-chunks session))
                   '(yours theirs conflict same yours theirs)))
    (should (equal (mapcar (lambda (c) (+my/merge-chunk-base c)) (+my/merge-chunks session))
                   '("two\n" "four\n" "six\n" "eight\n" "ten\n" "")))
    (should (equal (mapcar (lambda (c) (+my/merge--side-text c 'yours)) (+my/merge-chunks session))
                   '("TWO\n" "four\n" "six yours\n" "EIGHT\n" "" "")))
    (should (equal (mapcar (lambda (c) (+my/merge--side-text c 'theirs)) (+my/merge-chunks session))
                   '("two\n" "FOUR\n" "six theirs\n" "EIGHT\n" "ten\n" "thirteen\n")))
    (should (equal (+my/merge--counts session) '(6 . 1)))
    ;; The bar says so.
    (+my/merge--render-bar session 200)
    (should (string-match-p "6 changes left, 1 conflict"
                            (with-current-buffer (+my/merge-bar session) (buffer-string))))))

(ert-deftest merge/faces ()
  (+test-merge
    (let ((face (lambda (n side) (overlay-get (+my/merge--overlay (+test-merge--chunk session n) side) 'face))))
      (should (eq (funcall face 0 'yours) '+my/merge-changed))
      (should (null (funcall face 0 'theirs)))
      (should (eq (funcall face 2 'yours) '+my/merge-conflict))
      (should (eq (funcall face 2 'theirs) '+my/merge-conflict))
      (should (eq (funcall face 2 'result) '+my/merge-conflict))
      (should (eq (funcall face 4 'yours) '+my/merge-removed))
      (should (eq (funcall face 5 'theirs) '+my/merge-added))
      (should (eq (funcall face 1 'result) '+my/merge-changed))
      ;; Done: grey on its side, plain in the Result.
      (+my/merge--decide (+test-merge--chunk session 0) 'yours 'applied)
      (should (eq (funcall face 0 'yours) '+my/merge-done))
      (should (null (funcall face 0 'result))))))

(ert-deftest merge/a-mark-where-an-added-change-goes ()
  "A change with nothing in the Result (thirteen, Theirs' added): a triangle
in the Result's fringe where it goes, in the accent's colour (the change's
tint made a blur of it); a conflict's in red; none once done."
  (+test-merge
    (let* ((chunk (+test-merge--chunk session 5))
           (region (+my/merge-chunk-result chunk)))
      (should (= (overlay-start region) (overlay-end region)))
      (should (equal (get-text-property 0 'display (overlay-get region 'before-string))
                     '(left-fringe right-triangle +my/merge-mark)))
      (should (eq (face-attribute '+my/merge-mark :inherit) 'link))
      (should (eq (face-attribute '+my/merge-mark-conflict :inherit) 'error))
      (+my/merge--decide chunk 'theirs 'ignored)
      (should-not (overlay-get region 'before-string)))))

(define-minor-mode +test-merge-margin-thief-mode
  "Takes the margins' clicks, as dap-mode does in code buffers (Doom's
debugger: a breakpoint). Made after the merge's mode: its keymap first."
  :keymap (let ((map (make-sparse-keymap)))
            (dolist (area '(left-margin right-margin))
              (define-key map (vector area 'mouse-1) #'+test-merge--taken)
              (define-key map (vector area 'down-mouse-1) #'+test-merge--taken))
            map))

(defun +test-merge--taken ()
  (interactive))

(ert-deftest merge/margin-clicks-before-other-modes ()
  "A mode binding clicks in the margins on in the panes, its keymap before
the merge's (dap-mode's took Theirs' buttons and the wand's): a click on a
button or the wand is still the merge's; elsewhere, that mode's."
  (+test-merge-wand
    (let ((panes (list (cons (+my/merge-yours session) 'right-margin)
                       (cons (+my/merge-theirs session) 'left-margin)
                       (cons (+my/merge-result session) 'left-margin))))
      (pcase-dolist (`(,buffer . ,area) panes)
        (with-current-buffer buffer
          (+test-merge-margin-thief-mode 1)
          (let* ((window (get-buffer-window buffer))
                 (ov (seq-find (lambda (ov)
                                 (eq (car-safe (car-safe (get-text-property
                                                          0 'display (or (overlay-get ov 'before-string) " "))))
                                     'margin))
                               (overlays-in (point-min) (point-max))))
                 (text (cadr (get-text-property 0 'display (overlay-get ov 'before-string))))
                 (index (cl-loop for i below (length text)
                                 when (get-text-property i '+my/merge-action text) return i))
                 (posn (list window area '(0 . 0) 0 (cons text index) nil '(0 . 0) nil '(0 . 0) '(1 . 1)))
                 (bare (list window area '(0 . 0) 0 nil nil '(0 . 0) nil '(0 . 0) '(1 . 1))))
            (should (get-text-property index '+my/merge-action text))
            (should (eq (key-binding (vector area 'mouse-1) nil nil posn) #'+my/merge-click))
            (should (eq (key-binding (vector area 'down-mouse-1) nil nil posn) #'ignore))
            ;; Not on a string of the merge's: the mode's, as anywhere.
            (should (eq (key-binding (vector area 'mouse-1) nil nil bare) #'+test-merge--taken))))))))

(ert-deftest merge/buttons-in-the-margins-by-the-result ()
  (+test-merge
    ;; Yours' changes: lines 2 (two), 6, 8, and where ten was (eleven's line).
    ;; In a terminal (batch), off the right margin's first column: a click
    ;; there comes as one on the text.
    (should (equal (+test-merge--margin session 'yours)
                   '((2 . " >> x") (6 . " >> x") (8 . " >> x") (10 . " >> x"))))
    (should (equal (+test-merge--margin session 'theirs)
                   '((4 . "x <<") (6 . "x <<") (8 . "x <<") (13 . "x <<"))))
    ;; Each button says what it does.
    (with-current-buffer (+my/merge-yours session)
      (let* ((ov (seq-find (lambda (ov) (overlay-get ov 'before-string)) (overlays-in 1 8)))
             (text (cadr (get-text-property 0 'display (overlay-get ov 'before-string)))))
        (should-not (get-text-property 0 '+my/merge-action text))
        (should (equal (get-text-property 1 '+my/merge-action text)
                       (list (+test-merge--chunk session 0) 'yours 'applied)))
        (should (equal (get-text-property 4 '+my/merge-action text)
                       (list (+test-merge--chunk session 0) 'yours 'ignored)))
        (should (get-text-property 1 'mouse-face text))
        ;; The hand over the buttons.
        (should (eq (get-text-property 1 'pointer text) 'hand))
        (should (eq (get-text-property 4 'pointer text) 'hand))))
    ;; Done: a check (applied), nothing (ignored).
    (+my/merge--decide (+test-merge--chunk session 0) 'yours 'applied)
    (+my/merge--decide (+test-merge--chunk session 1) 'theirs 'ignored)
    (should (equal (assq 2 (+test-merge--margin session 'yours)) '(2 . " ok")))
    (should (equal (assq 4 (+test-merge--margin session 'theirs)) '(4 . " ")))))

(ert-deftest merge/right-margin-padded ()
  "Yours' buttons after a space: off the code, as Theirs' are; in a terminal
also off the margin's first column (a click there comes as one on the text,
xterm-mouse-mode). The margin fits it: in a terminal its 5 columns; in the
GUI, where an icon is wider than a column, one more."
  (should (equal (+my/merge--right-margin-text ">> x") " >> x"))
  (should (= (string-width (+my/merge--right-margin-text ">> x")) (+my/merge--yours-margin-columns) 5))
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
    (should (equal (+my/merge--right-margin-text "»x") " »x"))
    (should (= (+my/merge--yours-margin-columns) 6))))

(defun +test-merge--actions-in (text)
  "The buttons' actions in margin TEXT (applied, ignored), each once."
  (let (actions)
    (dotimes (i (length text))
      (when-let* ((action (nth 2 (get-text-property i '+my/merge-action text))))
        (cl-pushnew action actions)))
    actions))

(ert-deftest merge/margins-fit-their-buttons ()
  "In the GUI a margin is as wide as its buttons draw (their icons' font may be
wider than the code's: 45 pixels in 6 columns of 7 cut the x off), never
narrower than its columns; in a terminal, its columns."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            ((symbol-function 'frame-char-width) (lambda (&rest _) 7)))
    (cl-letf (((symbol-function 'string-pixel-width) (lambda (&rest _) 45)))
      (should (= (+my/merge--yours-margin-columns) 7))
      (should (= (+my/merge--theirs-margin-columns) 7)))
    (cl-letf (((symbol-function 'string-pixel-width) (lambda (&rest _) 20)))
      (should (= (+my/merge--yours-margin-columns) 6))
      (should (= (+my/merge--theirs-margin-columns) 5))))
  ;; Measured: the buttons as they show.
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            (measured nil))
    (cl-letf (((symbol-function 'string-pixel-width) (lambda (text &rest _) (push text measured) 0)))
      (+my/merge--yours-margin-columns)
      (+my/merge--theirs-margin-columns))
    (should (string-prefix-p " " (cadr measured)))       ; Yours': after its space
    (dolist (text measured)
      (should (equal (sort (+test-merge--actions-in text) #'string<) '(applied ignored)))))
  (should (= (+my/merge--yours-margin-columns) 5))
  (should (= (+my/merge--theirs-margin-columns) 5)))

(ert-deftest merge/fringes-outside-the-margins ()
  "The panes' margins (buttons, the wand) by the code, their fringes at the
window's edges, whatever the default (Doom's vc-gutter sets it so)."
  (let ((fringes-outside-margins nil))
    (+test-merge
      (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
        (with-current-buffer buffer
          (should (local-variable-p 'fringes-outside-margins))
          (should (eq fringes-outside-margins t)))))))

(ert-deftest merge/no-current-line-over-a-change ()
  "Doom's current line, in every window, over a change's colour: not on a
change's coloured lines; elsewhere, as anywhere."
  (+test-merge
    (require 'hl-line)
    (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session)
                          (+my/merge-theirs session)))
      (with-current-buffer buffer
        (should (eq hl-line-range-function #'+my/merge--hl-line-range))))
    (let ((chunk (+test-merge--chunk session 0)))
      (with-current-buffer (+my/merge-yours session)
        ;; On the change (two's line): none.
        (goto-char (overlay-start (+my/merge-chunk-yours chunk)))
        (let ((range (+my/merge--hl-line-range)))
          (should (= (car range) (cdr range))))
        ;; The line before it (one): the whole line.
        (forward-line -1)
        (should (equal (+my/merge--hl-line-range)
                       (cons (line-beginning-position) (line-beginning-position 2)))))
      ;; Done (grey, no background): the current line again.
      (+my/merge--decide chunk 'yours 'applied)
      (with-current-buffer (+my/merge-yours session)
        (goto-char (overlay-start (+my/merge-chunk-yours chunk)))
        (should (equal (+my/merge--hl-line-range)
                       (cons (line-beginning-position) (line-beginning-position 2))))))
    ;; Doom's window highlight asks for it.
    (with-current-buffer (+my/merge-theirs session)
      (+my/merge-mode -1)
      (should-not (local-variable-p 'hl-line-range-function)))))

(ert-deftest merge/faces-by-colours ()
  "The tints: the theme's colour blended into its background with true
colours, the palette's tint with 256, diff-mode's faces with fewer."
  (require 'doom-themes)
  (let ((doom-themes--colors '((bg "#282c34" "black" "black")
                               (blue "#51afef" "#51afef" "brightblue")
                               (green "#98be65" "#98be65" "green")
                               (red "#ff6c6b" "#ff6c6b" "red")
                               (base5 "#5B6268" "#525252" "brightblack"))))
    (unwind-protect
        (progn
          (+my/merge-faces-h)
          (let ((spec (get '+my/merge-changed 'face-override-spec)))
            (should (equal (face-spec-choose spec nil) nil))  ; batch: no colours
            (cl-letf (((symbol-function 'display-color-cells) (lambda (&rest _) 16777216)))
              (should (equal (plist-get (face-spec-choose spec) :background)
                             (doom-blend "#51afef" "#282c34" 0.25))))
            (cl-letf (((symbol-function 'display-color-cells) (lambda (&rest _) 256)))
              (should (equal (plist-get (face-spec-choose spec) :background) "#00005f"))
              (should (memq :inherit (face-spec-choose spec)))))
          (should (equal (plist-get (cl-letf (((symbol-function 'display-color-cells) (lambda (&rest _) 256)))
                                      (face-spec-choose (get '+my/merge-conflict 'face-override-spec)))
                                    :background)
                         "#5f0000"))
          ;; A light theme: the palette's lightest.
          (setf (alist-get 'bg doom-themes--colors) '("#fafafa" "white" "white"))
          (+my/merge-faces-h)
          (cl-letf (((symbol-function 'display-color-cells) (lambda (&rest _) 256)))
            (should (equal (plist-get (face-spec-choose (get '+my/merge-changed 'face-override-spec)) :background)
                           "#d7d7ff"))))
      (dolist (face '(+my/merge-changed +my/merge-added +my/merge-removed +my/merge-conflict +my/merge-filler))
        (put face 'face-override-spec nil)))))

(ert-deftest merge/icons-in-the-gui ()
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
    (require 'nerd-icons nil t)
    (if (not (featurep 'nerd-icons))
        (ert-skip "No nerd-icons")
      (should (equal (+my/merge--icon "nf-cod-close" "x") (nerd-icons-codicon "nf-cod-close")))
      (should (equal (+my/merge--icon "nf-md-chevron_double_right" ">>")
                     (nerd-icons-mdicon "nf-md-chevron_double_right")))
      (should (equal (+my/merge--icon "nf-cod-no-such-icon" "?") "?"))))
  (should (equal (+my/merge--icon "nf-cod-close" "x") "x")))

;; ====== APPLYING, IGNORING ======

(ert-deftest merge/a-change-into-the-result ()
  (+test-merge
    (+my/merge--decide (+test-merge--chunk session 0) 'yours 'applied)
    (+my/merge--decide (+test-merge--chunk session 1) 'theirs 'applied)
    (+my/merge--decide (+test-merge--chunk session 4) 'yours 'applied)    ; ten removed
    (+my/merge--decide (+test-merge--chunk session 5) 'theirs 'applied)   ; thirteen added
    (should (equal (+test-merge--result session)
                   (+test-merge--lines "one" "TWO" "three" "FOUR" "five" "six" "seven" "eight" "nine"
                                       "eleven" "twelve" "thirteen")))
    (should (equal (+my/merge--counts session) '(2 . 1)))
    (+my/merge--render-bar session 200)
    (should (string-match-p "2 changes left, 1 conflict"
                            (with-current-buffer (+my/merge-bar session) (buffer-string))))
    ;; The Result's regions follow their text.
    (let ((ov (+my/merge-chunk-result (+test-merge--chunk session 5))))
      (should (equal (with-current-buffer (+my/merge-result session)
                       (buffer-substring-no-properties (overlay-start ov) (overlay-end ov)))
                     "thirteen\n")))))

(ert-deftest merge/the-same-change-once ()
  (+test-merge
    (let ((chunk (+test-merge--chunk session 3)))
      (+my/merge--decide chunk 'theirs 'applied)
      (should (eq (+my/merge-chunk-yours-state chunk) 'applied))
      (should (eq (+my/merge-chunk-theirs-state chunk) 'applied))
      (should (+my/merge--resolved-p chunk))
      (should (string-match-p "^EIGHT\nnine" (+test-merge--result session)))
      (should-not (string-match-p "EIGHT\nEIGHT" (+test-merge--result session))))))

(ert-deftest merge/a-conflict-keep-both ()
  "One side in, the other's >> adds after it: in the order they came."
  (+test-merge
    (let ((chunk (+test-merge--chunk session 2)))
      (+my/merge--decide chunk 'yours 'applied)
      (should (string-match-p "five\nsix yours\nseven" (+test-merge--result session)))
      (should-not (+my/merge--resolved-p chunk))
      (should (equal (+my/merge--counts session) '(6 . 1)))
      ;; Its tooltip says so.
      (let ((theirs (seq-find (lambda (ov) (overlay-get ov 'before-string))
                              (with-current-buffer (+my/merge-theirs session)
                                (overlays-in (overlay-start (+my/merge-chunk-theirs chunk))
                                             (overlay-end (+my/merge-chunk-theirs chunk)))))))
        (should (string-match-p "keep both"
                                (get-text-property 2 'help-echo (cadr (get-text-property 0 'display (overlay-get theirs 'before-string)))))))
      (+my/merge--decide chunk 'theirs 'applied)
      (should (string-match-p "five\nsix yours\nsix theirs\nseven" (+test-merge--result session)))
      (should (+my/merge--resolved-p chunk))
      ;; Theirs out again: Yours alone.
      (+my/merge--decide chunk 'theirs 'ignored)
      (should (string-match-p "five\nsix yours\nseven" (+test-merge--result session)))
      ;; Theirs first, then Yours.
      (+my/merge--decide chunk 'yours 'ignored)
      (should (string-match-p "five\nsix\nseven" (+test-merge--result session)))
      (+my/merge--decide chunk 'theirs 'applied)
      (+my/merge--decide chunk 'yours 'applied)
      (should (string-match-p "five\nsix theirs\nsix yours\nseven" (+test-merge--result session))))))

(ert-deftest merge/ignoring ()
  (+test-merge
    (let ((chunk (+test-merge--chunk session 2)))
      (+my/merge--decide chunk 'yours 'ignored)
      (should-not (+my/merge--resolved-p chunk))
      (+my/merge--decide chunk 'theirs 'applied)
      (should (string-match-p "five\nsix theirs\nseven" (+test-merge--result session)))
      (should (+my/merge--resolved-p chunk)))
    ;; A change only one side made, ignored: done, the Result as it was.
    (let ((chunk (+test-merge--chunk session 0)))
      (+my/merge--decide chunk 'yours 'ignored)
      (should (+my/merge--resolved-p chunk))
      (should (string-prefix-p "one\ntwo\n" (+test-merge--result session))))
    ;; A side that made no change has nothing to decide.
    (let ((chunk (+test-merge--chunk session 1)))
      (+my/merge--decide chunk 'yours 'applied)
      (should-not (+my/merge-chunk-yours-state chunk)))))

(ert-deftest merge/undo-and-redo ()
  "u in the Result undoes a button (its text and its state), C-r redoes it."
  (+test-merge
    (let ((chunk (+test-merge--chunk session 2)))
      (+my/merge--decide chunk 'yours 'applied)
      (+my/merge--decide chunk 'theirs 'applied)
      (with-current-buffer (+my/merge-result session)
        (undo-boundary)
        (let ((last-command nil))
          (undo))
        (should (string-match-p "five\nsix yours\nseven" (+test-merge--result session)))
        (should (eq (+my/merge-chunk-theirs-state chunk) nil))
        (should (eq (+my/merge-chunk-yours-state chunk) 'applied))
        (undo-boundary)                   ; as the command loop does
        (let ((last-command 'undo))
          (undo))
        (should (string-match-p "five\nsix\nseven" (+test-merge--result session)))
        (should-not (+my/merge-chunk-yours-state chunk))
        (should (equal (overlay-get (+my/merge-chunk-yours chunk) 'face) '+my/merge-conflict))
        ;; Redo: undo the undos.
        (undo-boundary)
        (let ((last-command 'test))
          (undo))
        (should (string-match-p "five\nsix yours\nseven" (+test-merge--result session)))
        (should (eq (+my/merge-chunk-yours-state chunk) 'applied))))))

(ert-deftest merge/editing-the-result ()
  "The Result is a buffer to edit: a change's region follows edits before it."
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (goto-char (point-min))
      (insert "zero\n"))
    (+my/merge--decide (+test-merge--chunk session 2) 'theirs 'applied)
    (should (string-prefix-p "zero\none\n" (+test-merge--result session)))
    (should (string-match-p "five\nsix theirs\nseven" (+test-merge--result session)))))

(defun +test-merge--edit (session chunk text)
  "CHUNK's lines in SESSION's Result replaced by TEXT by hand, as a command:
a step of undo of its own, the panes lined up after."
  (with-current-buffer (+my/merge-result session)
    (let ((ov (+my/merge-chunk-result chunk)))
      (undo-boundary)
      (save-excursion
        (goto-char (overlay-start ov))
        (insert text)
        (delete-region (point) (overlay-end ov)))
      (+my/merge--post-command-h)
      (undo-boundary))))

(defun +test-merge--undo (session &optional again)
  "u in SESSION's Result (AGAIN: right after another u), as a command."
  (with-current-buffer (+my/merge-result session)
    (undo-boundary)
    (let ((last-command (and again 'undo)))
      (undo))
    (+my/merge--post-command-h)))

(ert-deftest merge/edited-by-hand-is-done ()
  "A change's lines in the Result edited by hand: done (not red any more, its
sides grey, one less left, the bar says so); the edit undone, not done
again."
  (+test-merge
    (let ((chunk (+test-merge--chunk session 2))
          (bar (lambda () (with-current-buffer (+my/merge-bar session) (buffer-string)))))
      (+test-merge--edit session chunk "six yours+theirs by hand\n")
      (should (string-match-p "five\nsix yours\\+theirs by hand\nseven" (+test-merge--result session)))
      (should (+my/merge--resolved-p chunk))
      (should (equal (+my/merge--counts session) '(5 . 0)))
      (should-not (overlay-get (+my/merge-chunk-result chunk) 'face))
      (should (eq (overlay-get (+my/merge-chunk-yours chunk) 'face) '+my/merge-done))
      (should (eq (overlay-get (+my/merge-chunk-theirs chunk) 'face) '+my/merge-done))
      (should (string-match-p "5\\( changes\\)? left, 0 conflicts" (funcall bar)))
      (+test-merge--undo session)
      (should (string-match-p "five\nsix\nseven" (+test-merge--result session)))
      (should-not (+my/merge--resolved-p chunk))
      (should (equal (+my/merge--counts session) '(6 . 1)))
      (should (eq (overlay-get (+my/merge-chunk-result chunk) 'face) '+my/merge-conflict))
      (should (eq (overlay-get (+my/merge-chunk-yours chunk) 'face) '+my/merge-conflict))
      (should (string-match-p "6\\( changes\\)? left, 1 conflict" (funcall bar)))
      ;; Redone: done again.
      (+test-merge--undo session)
      (should (string-match-p "five\nsix yours\\+theirs by hand\nseven" (+test-merge--result session)))
      (should (+my/merge--resolved-p chunk))
      ;; Undone, then a button: its lines in place of the base's, none left over.
      (+test-merge--undo session)
      (should (string-match-p "five\nsix\nseven" (+test-merge--result session)))
      (+my/merge--decide chunk 'yours 'applied)
      (should (string-match-p "five\nsix yours\nseven" (+test-merge--result session)))
      (should (+test-merge--lined-up-p session)))))

(ert-deftest merge/x-keeps-what-was-edited-by-hand ()
  "x on a change edited by hand: the Result keeps the edit (not the base
again), the change done; u undoes x, the edit still there, then the edit."
  (+test-merge
    ;; A conflict: SPC m x, both sides ignored.
    (let ((chunk (+test-merge--chunk session 2)))
      (+test-merge--edit session chunk "HAND six\n")
      (with-current-buffer (+my/merge-result session)
        (goto-char (overlay-start (+my/merge-chunk-result chunk)))
        (+my/merge-ignore))
      (should (string-match-p "five\nHAND six\nseven" (+test-merge--result session)))
      (should (eq (+my/merge-chunk-yours-state chunk) 'ignored))
      (should (eq (+my/merge-chunk-theirs-state chunk) 'ignored))
      (should (+my/merge--resolved-p chunk)))
    ;; A change Yours made alone: its x button, then undone.
    (let ((chunk (+test-merge--chunk session 0)))
      (+test-merge--edit session chunk "two by hand\n")
      (+my/merge--decide chunk 'yours 'ignored)
      (should (string-prefix-p "one\ntwo by hand\nthree\n" (+test-merge--result session)))
      (should (+my/merge--resolved-p chunk))
      (+test-merge--undo session)
      (should-not (+my/merge-chunk-yours-state chunk))
      (should (string-prefix-p "one\ntwo by hand\nthree\n" (+test-merge--result session)))
      (should (+my/merge--resolved-p chunk))
      (+test-merge--undo session t)
      (should (string-prefix-p "one\ntwo\nthree\n" (+test-merge--result session)))
      (should-not (+my/merge--resolved-p chunk)))
    ;; Yours in, edited, Theirs ignored: the edit stays.
    (let ((chunk (+test-merge--chunk session 3)))
      (+my/merge--decide chunk 'yours 'applied)
      (+test-merge--edit session chunk "EIGHT, by hand\n")
      (+my/merge--decide chunk 'theirs 'ignored)
      (should (string-match-p "seven\nEIGHT, by hand\nnine" (+test-merge--result session))))))

(ert-deftest merge/accepting-leaves-what-was-edited-by-hand ()
  "Accept Left / Right and Apply non-conflicting leave a change edited by
hand as it is (done)."
  (+test-merge
    (+test-merge--edit session (+test-merge--chunk session 2) "six by hand\n")
    (+test-merge--edit session (+test-merge--chunk session 1) "four by hand\n")
    (+my/merge-apply-non-conflicting)
    (should (string-match-p "three\nfour by hand\nfive\nsix by hand\nseven" (+test-merge--result session)))
    (+my/merge-accept-left)
    (should (equal (+test-merge--result session)
                   (+test-merge--lines "one" "TWO" "three" "four by hand" "five" "six by hand" "seven" "EIGHT"
                                       "nine" "eleven" "twelve" "thirteen")))))

;; ====== THE BAR ======

(ert-deftest merge/apply-non-conflicting ()
  (+test-merge
    (+my/merge-apply-non-conflicting)
    (should (equal (+test-merge--result session)
                   (+test-merge--lines "one" "TWO" "three" "FOUR" "five" "six" "seven" "EIGHT" "nine"
                                       "eleven" "twelve" "thirteen")))
    (should (equal (+my/merge--counts session) '(1 . 1)))
    (should-not (+my/merge--resolved-p (+test-merge--chunk session 2)))
    ;; Not again what's done.
    (+my/merge--decide (+test-merge--chunk session 0) 'yours 'ignored)
    (+my/merge-apply-non-conflicting)
    (should (string-prefix-p "one\ntwo\n" (+test-merge--result session)))))

(ert-deftest merge/accept-left-and-right ()
  (+test-merge
    (+my/merge-accept-left)
    (should (equal (+test-merge--result session) +test-merge--yours))
    (should (equal (+my/merge--counts session) '(0 . 0)))
    (+my/merge--render-bar session 200)
    (should (string-match-p "All changes done" (with-current-buffer (+my/merge-bar session) (buffer-string)))))
  (+test-merge
    (+my/merge-accept-right)
    (should (equal (+test-merge--result session) +test-merge--theirs)))
  ;; What's done stays.
  (+test-merge
    (+my/merge--decide (+test-merge--chunk session 2) 'theirs 'applied)
    (+my/merge--decide (+test-merge--chunk session 2) 'yours 'ignored)
    (+my/merge-accept-left)
    (should (string-match-p "five\nsix theirs\nseven" (+test-merge--result session)))
    (should (string-prefix-p "one\nTWO\n" (+test-merge--result session)))))

(ert-deftest merge/bar-fits ()
  "Long labels where they fit, short ones else (a terminal's 80 columns)."
  (+test-merge
    (let ((text (lambda () (with-current-buffer (+my/merge-bar session) (buffer-string)))))
      (+my/merge--render-bar session 200)
      (should (string-match-p "\\` Accept Left  Accept Right  ✨ Apply non-conflicting   6 changes left, 1 conflict   Done  Abort \\'"
                              (funcall text)))
      ;; Not a button last: its highlight went on to the window's edge.
      (with-current-buffer (+my/merge-bar session)
        (should-not (get-char-property (1- (point-max)) 'mouse-face))
        (should-not (button-at (1- (point-max)))))
      (+my/merge--render-bar session 80)
      (should (equal (funcall text) " Left  Right  ✨ Non-conflicting   6 left, 1 conflict   Done  Abort "))
      (should (<= (string-width (funcall text)) 80))
      (+my/merge-accept-left)
      (+my/merge--render-bar session 80)
      (should (string-match-p "All done" (funcall text)))
      ;; Its window resized: redrawn to fit.
      (should (memq #'+my/merge--bar-resized-h
                    (buffer-local-value 'window-size-change-functions (+my/merge-bar session)))))))

(ert-deftest merge/bar-buttons ()
  (+test-merge
    (+my/merge--render-bar session 200)
    (with-current-buffer (+my/merge-bar session)
      (let ((labels nil))
        (goto-char (point-min))
        (while-let ((button (next-button (point))))
          (push (button-label button) labels)
          (goto-char (button-end button)))
        (should (equal (nreverse labels)
                       '("Accept Left" "Accept Right" "✨ Apply non-conflicting" "Done" "Abort")))
        ;; The hand over them.
        (goto-char (point-min))
        (while-let ((button (next-button (point))))
          (should (eq (get-text-property (button-start button) 'pointer) 'hand))
          (goto-char (button-end button))))
      ;; Pressed from the bar: as from the Result.
      (goto-char (point-min))
      (push-button (next-button (point-min) t))
      (should (equal (+test-merge--result session) +test-merge--yours))
      (should (eq (window-buffer (selected-window)) (+my/merge-result session))))))

;; ====== DONE, ABORT ======

(ert-deftest merge/done-writes-and-stages ()
  (+test-merge
    (let ((winconf-buffers (list (current-buffer))))
      (ignore winconf-buffers)
      (+my/merge-accept-right)
      (+my/merge-done)
      (should (equal (+test-merge--read "a.txt") +test-merge--theirs))
      ;; Staged: no conflict left.
      (should (string-empty-p (+test-merge--git "ls-files" "-u")))
      (should (string-match-p "^M  a.txt" (+test-merge--git "status" "--porcelain")))
      ;; Closed, the windows as they were.
      (should (+my/merge-finished session))
      (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)
                            (+my/merge-base session) (+my/merge-bar session)))
        (should-not (buffer-live-p buffer)))
      (should (one-window-p)))))

(ert-deftest merge/done-with-changes-left ()
  "Asked first; the changes left as Git's conflict markers; not staged."
  (+test-merge
    (+my/merge-apply-non-conflicting)
    (let ((asked nil))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) nil)))
        (+my/merge-done))
      (should (equal asked '("1 change is not done: save a.txt with conflict markers there, not staged? ")))
      (should-not (+my/merge-finished session))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (+my/merge-done)))
    (should (equal (+test-merge--read "a.txt")
                   (+test-merge--lines "one" "TWO" "three" "FOUR" "five"
                                       "<<<<<<< main" "six yours" "=======" "six theirs" ">>>>>>> feature"
                                       "seven" "EIGHT" "nine" "eleven" "twelve" "thirteen")))
    (should (string-match-p "a.txt" (+test-merge--git "ls-files" "-u")))
    (should (+my/merge-finished session))))

(ert-deftest merge/done-saves-what-was-edited-by-hand ()
  "Done with a change edited by hand: the edit saved there, no conflict
markers; nothing else left: staged, nothing asked. Others left: markers for
those only."
  (+test-merge
    (+my/merge-apply-non-conflicting)
    (+test-merge--edit session (+test-merge--chunk session 2) "six yours+theirs by hand\n")
    (+my/merge-done)
    (should (equal (+test-merge--read "a.txt")
                   (+test-merge--lines "one" "TWO" "three" "FOUR" "five" "six yours+theirs by hand" "seven"
                                       "EIGHT" "nine" "eleven" "twelve" "thirteen")))
    (should (string-empty-p (+test-merge--git "ls-files" "-u")))
    (should (+my/merge-finished session)))
  (+test-merge
    (+test-merge--edit session (+test-merge--chunk session 2) "six by hand\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
      (+my/merge-done))
    (let ((file (+test-merge--read "a.txt")))
      (should (string-match-p "\nfive\nsix by hand\nseven\n" file))
      (should-not (string-match-p "six yours\\|six theirs" file))
      (should (string-match-p "\n<<<<<<< main\nTWO\n=======\ntwo\n>>>>>>> feature\n" file)))))

(ert-deftest merge/abort-leaves-the-file ()
  (+test-merge
    (let ((before (+test-merge--read "a.txt")))
      (+my/merge-accept-left)
      (+my/merge-abort)
      (should (equal (+test-merge--read "a.txt") before))
      (should (string-match-p "<<<<<<<" before))
      (should (string-match-p "a.txt" (+test-merge--git "ls-files" "-u")))
      (should-not (buffer-live-p (+my/merge-result session)))
      (should (one-window-p)))))

(ert-deftest merge/closing-a-pane-aborts ()
  (+test-merge
    (let ((kill-buffer-query-functions nil))
      (kill-buffer (+my/merge-theirs session)))
    (should (= (+test-merge--fire #'+my/merge--finish) 1))
    (should (+my/merge-finished session))
    (should-not (buffer-live-p (+my/merge-result session)))))

(ert-deftest merge/done-shows-in-the-files-buffer ()
  (+test-merge-with-repo
    (+test-merge--conflict "a.txt" +test-merge--base +test-merge--yours +test-merge--theirs)
    (let ((file-buffer (find-file-noselect "a.txt"))
          (session (+test-merge--open)))
      (+my/merge-accept-left)
      (+my/merge-done)
      (should (equal (with-current-buffer file-buffer (buffer-string)) +test-merge--yours))
      (should-not (buffer-modified-p file-buffer))
      ;; One with changes not saved: asked first.
      (ignore session))))

(ert-deftest merge/encoding-and-line-ends-kept ()
  (+test-merge-with-repo
    (+test-merge--conflict "w.txt"
                           "αλφα\nβήτα\nγάμμα\n" "αλφα\nΒΉΤΑ\nγάμμα\n" "αλφα\nβήτα\nΓΆΜΜΑ\n"
                           'utf-8-dos)
    (let ((session (+test-merge--open "w.txt")))
      (should (eq (coding-system-eol-type (+my/merge-coding session)) 1))
      (should (equal (+test-merge--result session) "αλφα\nβήτα\nγάμμα\n"))
      ;; Lines next to each other: one conflict (as Git has it).
      (should (equal (mapcar #'+my/merge-chunk-kind (+my/merge-chunks session)) '(conflict)))
      (+my/merge-take-both-for-test session)
      (+my/merge-done))
    (should (equal (with-temp-buffer
                     (set-buffer-multibyte nil)
                     (insert-file-contents-literally "w.txt")
                     (buffer-string))
                   (encode-coding-string "αλφα\r\nΒΉΤΑ\r\nγάμμα\r\nβήτα\r\nΓΆΜΜΑ\r\n" 'utf-8)))))

(ert-deftest merge/no-newline-at-the-end ()
  (+test-merge-with-repo
    (+test-merge--conflict "n.txt" "a\nb" "a\nyours" "a\ntheirs")
    (let ((session (+test-merge--open "n.txt")))
      (let ((chunk (+test-merge--chunk session 0)))
        (should (eq (+my/merge-chunk-kind chunk) 'conflict))
        (+my/merge--decide chunk 'yours 'applied)
        (+my/merge--decide chunk 'theirs 'applied))
      (should (equal (+test-merge--result session) "a\nyours\ntheirs"))
      (+my/merge--finish session))))

;; ====== LINING UP ======

(defun +test-merge--rows (session)
  "Each change's first row in Yours, the Result, Theirs: ((Y R T)...)."
  (mapcar (lambda (chunk)
            (mapcar (lambda (side)
                      (let ((ov (+my/merge--overlay chunk side)))
                        (with-current-buffer (overlay-buffer ov)
                          (line-number-at-pos (overlay-start ov)))))
                    '(yours result theirs)))
          (+my/merge-chunks session)))

(defun +test-merge--lined-up-p (session)
  "Non-nil if SESSION's panes line up: each change on the same row in all
three, the same number of rows."
  (and (seq-every-p (lambda (rows) (= (car rows) (nth 1 rows) (nth 2 rows)))
                    (+test-merge--rows session))
       (apply #'= (mapcar (lambda (buffer) (with-current-buffer buffer
                                             (count-lines (point-min) (point-max))))
                          (list (+my/merge-yours session) (+my/merge-result session)
                                (+my/merge-theirs session))))))

(defun +test-merge--fillers (buffer)
  "The filler lines in BUFFER: (LINE . COUNT)..."
  (with-current-buffer buffer
    (let ((pos (point-min)) fillers)
      (while (< pos (point-max))
        (let ((next (next-single-property-change pos '+my/merge-filler nil (point-max))))
          (when (get-text-property pos '+my/merge-filler)
            (push (cons (line-number-at-pos pos) (- next pos)) fillers))
          (setq pos next)))
      (nreverse fillers))))

(ert-deftest merge/panes-line-up ()
  (+test-merge
    (should (+test-merge--lined-up-p session))
    ;; Where Yours removed ten (a row for it), and where Theirs added
    ;; thirteen (a row in Yours and the Result).
    (should (equal (+test-merge--fillers (+my/merge-yours session)) '((10 . 1) (13 . 1))))
    (should (equal (+test-merge--fillers (+my/merge-result session)) '((13 . 1))))
    (should-not (+test-merge--fillers (+my/merge-theirs session)))
    ;; Changes into the Result: still.
    (+my/merge--decide (+test-merge--chunk session 5) 'theirs 'applied)
    (should (equal (+test-merge--fillers (+my/merge-result session)) nil))
    (should (+test-merge--lined-up-p session))
    (let ((chunk (+test-merge--chunk session 2)))
      (+my/merge--decide chunk 'yours 'applied)
      (+my/merge--decide chunk 'theirs 'applied)
      ;; Two lines in the Result: a row more in the sides.
      (should (equal (+test-merge--fillers (+my/merge-yours session)) '((7 . 1) (11 . 1) (14 . 1))))
      (should (+test-merge--lined-up-p session)))
    (+my/merge-accept-left)
    (should (+test-merge--lined-up-p session))
    (should (equal (+test-merge--result session)
                   (+test-merge--lines "one" "TWO" "three" "four" "five" "six yours" "six theirs" "seven"
                                       "EIGHT" "nine" "eleven" "twelve" "thirteen")))))

(ert-deftest merge/lined-up-after-editing-the-result ()
  "An edit of the Result (lines added in a change, removed): the panes line
up again after the command, in the same step of its undo."
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (goto-char (overlay-start (+my/merge-chunk-result (+test-merge--chunk session 2))))
      (insert "added 1\nadded 2\n")
      (+my/merge--post-command-h)
      (should (+test-merge--lined-up-p session))
      (should (string-match-p "five\nadded 1\nadded 2\nsix\nseven" (+test-merge--result session)))
      ;; Undone: the lines and the fillers.
      (undo-boundary)
      (let ((last-command nil)) (undo))
      (+my/merge--post-command-h)
      (should (equal (+test-merge--result session) +test-merge--base))
      (should (+test-merge--lined-up-p session))
      (should (equal (+test-merge--fillers (+my/merge-yours session)) '((10 . 1) (13 . 1)))))))

(ert-deftest merge/fillers-are-not-text ()
  "Fillers: read-only, the cursor skips them, not copied, not saved."
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (let ((filler (save-excursion (goto-char (point-min)) (forward-line 12) (point))))
        (should (get-text-property filler '+my/merge-filler))
        (should (get-text-property filler 'cursor-intangible))
        (should (eq (get-text-property filler 'face) '+my/merge-filler))
        (should cursor-intangible-mode)
        (should-error (let ((inhibit-read-only nil))
                        (goto-char (1+ filler))
                        (delete-char -1))
                      :type 'text-read-only)
        ;; Typed after them: not read-only.
        (let ((kill-ring nil) (kill-ring-yank-pointer nil) (interprogram-cut-function nil))
          (copy-region-as-kill (point-min) (point-max))
          (should (equal (car kill-ring) +test-merge--base)))
        (should truncate-lines)))
    (should (equal (+test-merge--result session) +test-merge--base))))

(ert-deftest merge/side-panes-have-no-undo ()
  (+test-merge
    (should (eq (buffer-local-value 'buffer-undo-list (+my/merge-yours session)) t))
    (should (eq (buffer-local-value 'buffer-undo-list (+my/merge-theirs session)) t))
    (should-not (eq (buffer-local-value 'buffer-undo-list (+my/merge-result session)) t))))

;; ====== SCROLLING TOGETHER ======

(ert-deftest merge/the-pane-scrolled-scrolls-the-others ()
  (+test-merge
    (let ((yours (get-buffer-window (+my/merge-yours session)))
          (result (get-buffer-window (+my/merge-result session)))
          (theirs (get-buffer-window (+my/merge-theirs session)))
          (first-line (lambda (window)
                        (with-current-buffer (window-buffer window)
                          (line-number-at-pos (window-start window))))))
      ;; Nothing scrolled: nothing done.
      (+my/merge--sync-h)
      (should (= (funcall first-line result) 1))
      ;; Theirs scrolled to its line 6: the others to theirs.
      (set-window-start theirs (with-current-buffer (+my/merge-theirs session)
                                 (save-excursion (goto-char (point-min)) (forward-line 5) (point))))
      (set-window-hscroll theirs 3)
      (+my/merge--sync-h theirs)
      (should (= (funcall first-line yours) 6))
      (should (= (funcall first-line result) 6))
      (should (= (window-hscroll yours) 3))
      (should (= (window-hscroll result) 3))
      ;; Each pane's text there: the same row (lined up).
      (should (equal (with-current-buffer (+my/merge-result session)
                       (buffer-substring-no-properties (window-start result) (+ (window-start result) 3)))
                     "six"))
      ;; The Result then: it leads.
      (set-window-start result (with-current-buffer (+my/merge-result session)
                                 (save-excursion (goto-char (point-min)) (forward-line 1) (point))))
      (+my/merge--sync-h)
      (should (= (funcall first-line yours) 2))
      (should (= (funcall first-line theirs) 2))
      ;; Without a window: all the merge's.
      (set-window-start yours (with-current-buffer (+my/merge-yours session)
                                (save-excursion (goto-char (point-min)) (forward-line 3) (point))))
      (+my/merge--sync-h nil)
      (should (= (funcall first-line theirs) 4))
      (should (memq #'+my/merge--sync-h (default-value 'pre-redisplay-functions))))))

;; ====== THE WAND ======

(ert-deftest merge/words-one-a-line ()
  (should (equal (+my/merge--words "foo(a, b);\n")
                 "foo\n(\na\n,\n \nb\n)\n;\n\\n\n"))
  (dolist (text '("" "a" "a\nb  c\t(d)\n\n é" "back\\slash \\n literal\n" "  lead\n\n\ntrail  "
                  "αβγ δ_ε 12.5e-3"))
    (should (equal (+my/merge--unwords (+my/merge--words text)) text))))

(ert-deftest merge/words-merged ()
  (should (equal (+my/merge--merge-words "foo(a, b);\n" "foo(a, c);\n" "bar(a, b);\n") "bar(a, c);\n"))
  ;; Lines next to each other (a conflict for Git): merged.
  (should (equal (+my/merge--merge-words "x = 1\ny = 2\n" "x = 10\ny = 2\n" "x = 1\ny = 20\n")
                 "x = 10\ny = 20\n"))
  ;; The same word changed: no.
  (should-not (+my/merge--merge-words "a b\n" "a c\n" "a d\n"))
  ;; A side that removed it all, the other that changed it: no.
  (should-not (+my/merge--merge-words "a b\n" "" "a c\n")))

(defconst +test-merge--wand-base
  (+test-merge--lines "start" "call(first, second);" "x = 1" "y = 2" "end"))

(defmacro +test-merge-wand (&rest body)
  "BODY with w.txt in conflict, its merge open as `session': a conflict
whose sides changed different words (call/first; x, y), one whose sides
changed the same word."
  (declare (indent 0))
  `(+test-merge-with-repo
     (+test-merge--conflict "w.txt" +test-merge--wand-base
                            (+test-merge--lines "start" "call(FIRST, second);" "x = 10" "y = 2" "end")
                            (+test-merge--lines "start" "invoke(first, second);" "x = 1" "y = 20" "end"))
     (let ((session (+test-merge--open "w.txt")))
       (unwind-protect (progn ,@body)
         (+my/merge--finish session)))))

(ert-deftest merge/the-wand-merges-the-words ()
  (+test-merge-wand
    (let ((chunk (+test-merge--chunk session 0)))
      (should (eq (+my/merge-chunk-kind chunk) 'conflict))
      (should (equal (+my/merge-chunk-wand chunk) "invoke(FIRST, second);\nx = 10\ny = 20\n"))
      ;; In the Result's margin.
      (should (equal (window-margins (get-buffer-window (+my/merge-result session))) '(2)))
      (with-current-buffer (+my/merge-result session)
        (let* ((ov (seq-find (lambda (ov) (overlay-get ov 'before-string))
                             (overlays-in (overlay-start (+my/merge-chunk-result chunk))
                                          (1+ (overlay-start (+my/merge-chunk-result chunk))))))
               (display (get-text-property 0 'display (overlay-get ov 'before-string))))
          (should (equal (car display) '(margin left-margin)))
          (should (equal (get-text-property 0 '+my/merge-action (cadr display)) (list chunk 'both 'merged)))
          (should (eq (get-text-property 0 'pointer (cadr display)) 'hand))
          (should (string-match-p "wand" (get-text-property 0 'help-echo (cadr display))))))
      (+my/merge--decide chunk 'both 'merged)
      (should (equal (+test-merge--result session)
                     (+test-merge--lines "start" "invoke(FIRST, second);" "x = 10" "y = 20" "end")))
      (should (+my/merge--resolved-p chunk))
      (should (equal (+my/merge--counts session) '(0 . 0)))
      (should (+test-merge--lined-up-p session))
      ;; Done: no wand; the sides marked.
      (with-current-buffer (+my/merge-result session)
        (should-not (seq-find (lambda (ov) (overlay-get ov 'before-string))
                              (overlays-in (point-min) (point-max)))))
      (should (equal (cdar (+test-merge--margin session 'yours)) " *"))
      ;; Undone: as it was.
      (with-current-buffer (+my/merge-result session)
        (undo-boundary)
        (let ((last-command nil)) (undo))
        (+my/merge--post-command-h))
      (should (equal (+test-merge--result session) +test-merge--wand-base))
      (should-not (+my/merge-chunk-yours-state chunk))
      (should (+test-merge--lined-up-p session)))))

(ert-deftest merge/the-wand-at-point ()
  (+test-merge-wand
    (with-current-buffer (+my/merge-result session)
      (goto-char (overlay-start (+my/merge-chunk-result (+test-merge--chunk session 0))))
      (+my/merge-wand)
      (should (string-match-p "invoke(FIRST" (+test-merge--result session)))))
  ;; No wand where the same words changed.
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (goto-char (overlay-start (+my/merge-chunk-result (+test-merge--chunk session 2))))
      (should-not (+my/merge-chunk-wand (+test-merge--chunk session 2)))
      (should-error (+my/merge-wand) :type 'user-error)
      (should-not (seq-find (lambda (chunk) (+my/merge-chunk-wand chunk))
                            (+my/merge-chunks session))))))

(ert-deftest merge/the-wand-key ()
  (should (eq (lookup-key (evil-get-auxiliary-keymap +my/merge-mode-map 'normal) (kbd "SPC m w"))
              #'+my/merge-wand)))

;; ====== LINE NUMBERS ======

(defun +test-merge--numbers (buffer)
  "BUFFER's lines, numbered first: each one's number as its prefix shows it,
nil for a blank one (a filler)."
  (with-current-buffer buffer
    (+my/merge--number (point-min) (point-max))
    (save-excursion
      (goto-char (point-min))
      (let (numbers)
        (while (not (eobp))
          (let ((prefix (get-text-property (point) 'line-prefix)))
            (should prefix)
            (push (and (not (string-blank-p prefix)) (string-to-number prefix)) numbers))
          (forward-line 1))
        (nreverse numbers)))))

(ert-deftest merge/line-numbers-of-each-version ()
  "Each pane's lines numbered as in its version, the fillers not counted
(blank), the same width in the three; Emacs's own numbers off."
  (+test-merge
    (pcase-dolist (`(,buffer . ,text) (list (cons (+my/merge-yours session) +test-merge--yours)
                                            (cons (+my/merge-result session) +test-merge--base)
                                            (cons (+my/merge-theirs session) +test-merge--theirs)))
      (let ((numbers (+test-merge--numbers buffer)))
        (should (equal (remq nil numbers) (number-sequence 1 (length (split-string text "\n" t)))))
        (with-current-buffer buffer
          (should (= (seq-count #'null numbers) (+my/merge--fillers-before (point-max))))
          (should (= +my/merge--number-width 3))
          (should (equal (get-text-property 1 'face (get-text-property (point-min) 'line-prefix))
                         'line-number))
          (should-not (bound-and-true-p display-line-numbers-mode))
          (should (memq #'+my/merge--number jit-lock-functions)))))
    ;; Yours and the Result have fillers (Theirs' thirteen; Yours' ten, removed).
    (should (memq nil (+test-merge--numbers (+my/merge-yours session))))
    (should (memq nil (+test-merge--numbers (+my/merge-result session))))
    ;; A row: Yours' eleven is its 10th line (ten removed), the Result's 11th.
    (dolist (spec (list (list (+my/merge-yours session) "eleven" 10)
                        (list (+my/merge-result session) "eleven" 11)
                        (list (+my/merge-theirs session) "thirteen" 13)))
      (with-current-buffer (nth 0 spec)
        (goto-char (point-min))
        (search-forward (nth 1 spec))
        (should (= (+my/merge--line-at (point)) (nth 2 spec)))
        (should (= (string-to-number (get-text-property (line-beginning-position) 'line-prefix))
                   (nth 2 spec)))))))

(ert-deftest merge/the-current-line-number ()
  "The current line's number, in each pane's window, in
`line-number-current-line', above the line's own (hl-line copies that one)."
  (+test-merge
    (let ((window (get-buffer-window (+my/merge-yours session))))
      (with-current-buffer (+my/merge-yours session)
        (set-window-point window (save-excursion (goto-char (point-min)) (search-forward "eleven") (point)))
        (+my/merge--current-number-h window)
        (let* ((ov (alist-get window +my/merge--current-numbers))
               (prefix (overlay-get ov 'line-prefix)))
          (should (eq (overlay-get ov 'window) window))
          (should (> (overlay-get ov 'priority) 0))
          (should (= (string-to-number prefix) 10))
          (should (eq (get-text-property 1 'face prefix) 'line-number-current-line))
          ;; Moved with point, the same overlay.
          (set-window-point window (point-min))
          (+my/merge--current-number-h window)
          (should (eq (alist-get window +my/merge--current-numbers) ov))
          (should (= (string-to-number (overlay-get ov 'line-prefix)) 1))
          (should (= (overlay-start ov) (point-min))))))
    ;; Not in the bar.
    (with-current-buffer (+my/merge-bar session)
      (+my/merge--current-number-h (get-buffer-window (current-buffer)))
      (should-not +my/merge--current-numbers))))

(ert-deftest merge/the-result-renumbered-after-an-edit ()
  "An edit that changes the Result's lines: it's numbered again (jit-lock,
when shown), not the others."
  (+test-merge
    (let ((refontified nil))
      (cl-letf (((symbol-function 'jit-lock-refontify)
                 (lambda (&rest _) (push (current-buffer) refontified))))
        (with-current-buffer (+my/merge-result session)
          (goto-char (point-min))
          (insert "zero\n")
          (+my/merge--post-command-h)))
      (should (equal refontified (list (+my/merge-result session))))
      (should (equal (remq nil (+test-merge--numbers (+my/merge-result session))) (number-sequence 1 13))))))

(ert-deftest merge/line-numbers-as-wide-in-the-three ()
  "A pane with 1000 lines or more: four digits in each of the three."
  (+test-merge
    (let ((refontified nil))
      (cl-letf (((symbol-function 'jit-lock-refontify)
                 (lambda (&rest _) (push (current-buffer) refontified)))
                ((symbol-function '+my/merge--line-at)
                 (let ((real (symbol-function '+my/merge--line-at)))
                   (lambda (pos) (if (eq (current-buffer) (+my/merge-result session)) 1200 (funcall real pos))))))
        (+my/merge--renumber session))
      (should (= (length refontified) 3))
      (dolist (buffer (list (+my/merge-yours session) (+my/merge-result session) (+my/merge-theirs session)))
        (with-current-buffer buffer
          (should (= +my/merge--number-width 4))
          (should (equal (+my/merge--number-string 7 'line-number) "    7 ")))))))

(ert-deftest merge/copies-without-line-numbers ()
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (+test-merge--numbers (current-buffer))
      (let ((copy (filter-buffer-substring (point-min) (point-max))))
        (should (equal copy +test-merge--base))
        (should-not (text-property-not-all 0 (length copy) 'line-prefix nil copy))))))

;; ====== ONE FILE AFTER THE OTHER ======

(defun +test-merge--session-open ()
  "The merge open, if one is."
  (seq-some (lambda (buffer) (buffer-local-value '+my/merge--session buffer)) (buffer-list)))

(defun +test-merge--two-conflicts ()
  "a.txt and b.txt in conflict (feature merged into main)."
  (dolist (file '("a.txt" "b.txt"))
    (+test-merge--write file (+test-merge--lines "one" "two" "three")))
  (+test-merge--git "add" ".")
  (+test-merge--git "commit" "-qm" "base")
  (+test-merge--git "checkout" "-qb" "feature")
  (dolist (file '("a.txt" "b.txt"))
    (+test-merge--write file (+test-merge--lines "one" "theirs" "three")))
  (+test-merge--git "commit" "-qam" "theirs")
  (+test-merge--git "checkout" "-q" "main")
  (dolist (file '("a.txt" "b.txt"))
    (+test-merge--write file (+test-merge--lines "one" "yours" "three")))
  (+test-merge--git "commit" "-qam" "yours")
  (+test-merge--git-may-fail "merge" "-q" "feature"))

(ert-deftest merge/files-one-after-the-other ()
  "Each file's merge once the last one's closed (done, aborted); then the
function given, with the files still in conflict."
  (+test-merge-with-repo
    (+test-merge--two-conflicts)
    (+test-merge--write "clean.txt" "clean\n")
    (let ((left 'not-yet))
      (+my/merge-files (list "a.txt" "clean.txt" "b.txt") (lambda (files) (setq left files)))
      (let ((session (+test-merge--session-open)))
        (should (equal (+my/merge-path session) "a.txt"))
        (with-current-buffer (+my/merge-result session)
          (+my/merge-accept-right)
          (+my/merge-done)))
      (sleep-for 0.1)                     ; the next after this one's closed
      (let ((session (+test-merge--session-open)))
        (should (equal (+my/merge-path session) "b.txt"))
        ;; Its panes where you are, the Result selected.
        (should (eq (window-buffer (selected-window)) (+my/merge-result session)))
        (should (eq left 'not-yet))
        (with-current-buffer (+my/merge-result session)
          (+my/merge-abort)))
      (sleep-for 0.1)
      (should-not (+test-merge--session-open))
      (should (equal left (list (expand-file-name "b.txt"))))
      ;; The file not in conflict, skipped, said why.
      (should (= (+test-messages "^Skipped: clean\\.txt (Not in conflict)") 1)))))

(ert-deftest merge/files-the-panes-cant-show-skipped ()
  (+test-merge-with-repo
    (+test-merge--conflict "b.bin" "a\0b\n" "a\0yours\n" "a\0theirs\n")
    (let ((left 'not-yet)
          (ediffed nil))
      (cl-letf (((symbol-function 'magit-ediff-resolve-rest) (lambda (file) (push file ediffed))))
        (+my/merge-files (list "b.bin") (lambda (files) (setq left files))))
      ;; Not Ediff (it'd hold up the files after): skipped.
      (should-not ediffed)
      (should (equal left (list (expand-file-name "b.bin"))))
      (should (= (+test-messages "^Skipped: b\\.bin (A binary file)") 1)))))

(ert-deftest merge/all-of-the-repository ()
  (+test-merge-with-repo
    (+test-merge--two-conflicts)
    (+my/merge-all)
    (dotimes (_ 2)
      (let ((session (+test-merge--session-open)))
        (should session)
        (with-current-buffer (+my/merge-result session)
          (+my/merge-accept-left)
          (+my/merge-done)))
      (sleep-for 0.1))
    (should-not (+test-merge--session-open))
    (should (string-empty-p (+test-merge--git "ls-files" "-u")))
    (should (= (+test-messages "^All conflicts resolved$") 1))
    (should-error (+my/merge-all) :type 'user-error)
    (should (commandp #'+my/merge-all))))

(ert-deftest merge/then-once-closed ()
  (+test-merge
    (let ((called 0))
      (+my/merge-then session (lambda () (cl-incf called)))
      (should (= called 0))
      (+my/merge-abort)
      (sleep-for 0.05)
      (should (= called 1))
      (should-not (assq session +my/merge--then)))))

(ert-deftest merge/its-frame-closed-aborts-it ()
  "The frame a merge is in deleted (a terminal's, cmd/diff's): aborted,
no windows put back (they're gone)."
  (+test-merge
    (should (eq (+my/merge-frame session) (selected-frame)))
    (should (memq #'+my/merge--frame-deleted-h delete-frame-functions))
    (let ((restored nil))
      (cl-letf (((symbol-function 'set-window-configuration) (lambda (&rest _) (setq restored t))))
        (+my/merge--frame-deleted-h 'another-frame)
        (should-not (+my/merge-finished session))
        (+my/merge--frame-deleted-h (selected-frame)))
      (should (+my/merge-finished session))
      (should-not restored)
      (should-not (buffer-live-p (+my/merge-result session))))))

;; ====== OTHER CONFLICTS ======

(ert-deftest merge/a-rebase ()
  (+test-merge-with-repo
    (+test-merge--write "a.txt" +test-merge--base)
    (+test-merge--git "add" ".")
    (+test-merge--git "commit" "-qm" "base")
    (+test-merge--git "checkout" "-qb" "feature")
    (+test-merge--write "a.txt" +test-merge--theirs)
    (+test-merge--git "commit" "-qam" "Their change")
    (+test-merge--git "checkout" "-q" "main")
    (+test-merge--write "a.txt" +test-merge--yours)
    (+test-merge--git "commit" "-qam" "yours")
    (+test-merge--git "checkout" "-q" "feature")
    (should-not (zerop (+test-merge--git-may-fail "rebase" "main")))
    (let ((session (+test-merge--open)))
      ;; In a rebase, :2: is what's rebased onto, :3: the commit replayed.
      (should (string-match-p "(rebasing onto)" (car (+my/merge-labels session))))
      (should (string-match-p "Their change (being rebased)" (cdr (+my/merge-labels session))))
      (should (equal (+test-merge--clean (+my/merge-theirs session)) +test-merge--theirs))
      (+my/merge-accept-right)
      (+my/merge-done))
    (should (string-empty-p (+test-merge--git "ls-files" "-u")))))

(ert-deftest merge/a-cherry-pick ()
  (+test-merge-with-repo
    (+test-merge--write "a.txt" +test-merge--base)
    (+test-merge--git "add" ".")
    (+test-merge--git "commit" "-qm" "base")
    (+test-merge--git "checkout" "-qb" "feature")
    (+test-merge--write "a.txt" +test-merge--theirs)
    (+test-merge--git "commit" "-qam" "Picked")
    (+test-merge--git "checkout" "-q" "main")
    (+test-merge--write "a.txt" +test-merge--yours)
    (+test-merge--git "commit" "-qam" "yours")
    (should-not (zerop (+test-merge--git-may-fail "cherry-pick" "feature")))
    (let ((session (+test-merge--open)))
      (should (equal (car (+my/merge-labels session)) "main"))
      (should (string-match-p "Picked (cherry-picked)" (cdr (+my/merge-labels session))))
      (+my/merge--finish session))))

(ert-deftest merge/what-ediff-gets-instead ()
  "Binary files, added on both sides, deleted on one: Magit's Ediff."
  (+test-merge-with-repo
    (let ((ediffed nil))
      (cl-letf (((symbol-function 'magit-ediff-resolve-rest) (lambda (file) (push file ediffed))))
        ;; Binary.
        (+test-merge--conflict "b.bin" "a\0b\n" "a\0yours\n" "a\0theirs\n")
        (should (equal (+my/merge--why-not "b.bin") "A binary file"))
        (+my/merge "b.bin")
        (should (equal ediffed '("b.bin")))
        (+test-merge--git "merge" "--abort")
        ;; Added on both sides.
        (+test-merge--git "checkout" "-qb" "add-theirs")
        (+test-merge--write "new.txt" "theirs\n")
        (+test-merge--git "add" ".")
        (+test-merge--git "commit" "-qm" "add theirs")
        (+test-merge--git "checkout" "-q" "main")
        (+test-merge--write "new.txt" "yours\n")
        (+test-merge--git "add" ".")
        (+test-merge--git "commit" "-qm" "add yours")
        (+test-merge--git-may-fail "merge" "add-theirs")
        (should (equal (+my/merge--why-not "new.txt") "Added on both sides"))
        (+my/merge "new.txt")
        (should (equal (car ediffed) "new.txt"))
        (should (= (+test-messages "new.txt: Added on both sides, so Ediff") 1))
        (+test-merge--git "merge" "--abort")
        ;; Deleted on their side.
        (+test-merge--git "checkout" "-qb" "delete-theirs")
        (+test-merge--git "rm" "-q" "new.txt")
        (+test-merge--git "commit" "-qm" "delete")
        (+test-merge--git "checkout" "-q" "main")
        (+test-merge--write "new.txt" "yours changed\n")
        (+test-merge--git "commit" "-qam" "change")
        (+test-merge--git-may-fail "merge" "delete-theirs")
        (should (equal (+my/merge--why-not "new.txt") "Deleted on their side"))
        ;; Not in conflict.
        (should-error (+my/merge "b.bin") :type 'user-error)))))

;; ====== COMMANDS ======

(ert-deftest merge/clicking-a-button ()
  (+test-merge
    (let* ((window (get-buffer-window (+my/merge-yours session)))
           (ov (seq-find (lambda (ov) (overlay-get ov 'before-string))
                         (with-current-buffer (+my/merge-yours session) (overlays-in 1 8))))
           (text (cadr (get-text-property 0 'display (overlay-get ov 'before-string))))
           ;; A terminal's click on the margin's Ith character, as Emacs 31
           ;; makes it: its column, from the window's left edge, and the
           ;; string's position one less (see `+my/merge--clicked-index').
           (margin (- (nth 2 (window-body-edges window)) (nth 0 (window-edges window))))
           (event (lambda (i) (list 'mouse-1 (list window 'right-margin (cons (+ margin i) 0) 0
                                                   (cons text (1- i)) nil (cons (+ margin i) 0)
                                                   nil '(0 . 0) '(1 . 1))))))
      ;; The pad before the buttons: nothing; x, the next button's.
      (+my/merge-click (funcall event 1))
      (should (eq (+my/merge-chunk-yours-state (+test-merge--chunk session 0)) 'applied))
      (should (eq (selected-window) window))
      (should (string-prefix-p "one\nTWO\n" (+test-merge--result session)))
      (with-current-buffer (+my/merge-result session)
        (undo-boundary)
        (let ((last-command nil)) (undo)))
      (should-not (+my/merge-chunk-yours-state (+test-merge--chunk session 0)))
      (+my/merge-click (funcall event 4))
      (should (eq (+my/merge-chunk-yours-state (+test-merge--chunk session 0)) 'ignored))
      (with-current-buffer (+my/merge-result session)
        (undo-boundary)
        (let ((last-command nil)) (undo)))
      (+my/merge-click (funcall event 3))   ; the space between
      (should-not (+my/merge-chunk-yours-state (+test-merge--chunk session 0)))
      ;; In the GUI, or a left margin: the string's position, as given.
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
        (should (= (+my/merge--clicked-index (list window 'right-margin '(0 . 0) 0 (cons text 2)
                                                   nil '(0 . 0) nil '(0 . 0) '(0 . 0)))
                   2)))
      (should (= (+my/merge--clicked-index (list window 'left-margin '(9 . 0) 0 (cons text 2)
                                                 nil '(9 . 0) nil '(0 . 0) '(0 . 0)))
                 2))
      (+my/merge-click (funcall event 2))
      (should (eq (+my/merge-chunk-yours-state (+test-merge--chunk session 0)) 'applied))
      (should (eq (selected-window) window))
      (should (string-prefix-p "one\nTWO\n" (+test-merge--result session)))
      ;; Elsewhere in the margin: nothing.
      (+my/merge-click (list 'mouse-1 (list window 'right-margin '(0 . 0) 0 nil nil '(0 . 0) nil '(0 . 0) '(0 . 0)))))))

(ert-deftest merge/keys-at-point ()
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (goto-char (overlay-start (+my/merge-chunk-result (+test-merge--chunk session 2))))
      (+my/merge-take-left)
      (+my/merge-take-right)
      (should (string-match-p "six yours\nsix theirs" (+test-merge--result session))))
    (with-current-buffer (+my/merge-theirs session)
      (goto-char (overlay-start (+my/merge-chunk-theirs (+test-merge--chunk session 1))))
      (+my/merge-ignore)
      (should (+my/merge--resolved-p (+test-merge--chunk session 1))))
    (with-current-buffer (+my/merge-result session)
      (goto-char (point-min))
      (should-error (+my/merge-take-left) :type 'user-error))))

(ert-deftest merge/next-and-previous ()
  (+test-merge
    (with-current-buffer (+my/merge-result session)
      (goto-char (point-min))
      (+my/merge-next)
      (should (= (line-number-at-pos) 2))
      (+my/merge-next)
      (should (= (line-number-at-pos) 4))
      (should (= (with-current-buffer (+my/merge-theirs session) (line-number-at-pos)) 4))
      (+my/merge-previous)
      (should (= (line-number-at-pos) 2)))))

(ert-deftest merge/keys ()
  (let ((map +my/merge-mode-map))
    (should (eq (lookup-key map (kbd "C-c C-c")) #'+my/merge-done))
    (should (eq (lookup-key map (kbd "C-c C-k")) #'+my/merge-abort))
    (should (eq (lookup-key map (kbd "s-s")) #'+my/merge-done))
    (should (eq (lookup-key map [right-margin mouse-1]) #'+my/merge-click))
    (should (eq (lookup-key map [left-margin mouse-1]) #'+my/merge-click))
    (let ((normal (evil-get-auxiliary-keymap map 'normal)))
      (should (eq (lookup-key normal (kbd "]c")) #'+my/merge-next))
      (should (eq (lookup-key normal (kbd "[c")) #'+my/merge-previous))
      (pcase-dolist (`(,key . ,command) '(("l" . +my/merge-take-left) ("r" . +my/merge-take-right)
                                          ("x" . +my/merge-ignore) ("L" . +my/merge-accept-left)
                                          ("R" . +my/merge-accept-right) ("a" . +my/merge-apply-non-conflicting)
                                          ("d" . +my/merge-done) ("q" . +my/merge-abort)))
        (should (eq (lookup-key normal (kbd (concat "SPC m " key))) command))))))

(ert-deftest merge/words-refined ()
  (+test-merge
    (let ((refined (lambda (buffer)
                     (with-current-buffer buffer
                       (mapcar (lambda (ov) (buffer-substring-no-properties (overlay-start ov) (overlay-end ov)))
                               (seq-filter (lambda (ov) (overlay-get ov '+my/merge-refined))
                                           (overlays-in (point-min) (point-max))))))))
      ;; A conflict: its sides against each other.
      (should (member "yours" (funcall refined (+my/merge-yours session))))
      (should (member "theirs" (funcall refined (+my/merge-theirs session)))))))
