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

;; As config/compile.el does once Emacs is idle a moment after it started:
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
config/compile.el may (the other tests run them so)."
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

(ert-deftest merge/buttons-in-the-margins-by-the-result ()
  (+test-merge
    ;; Yours' changes: lines 2 (two), 6, 8, and where ten was (eleven's line).
    (should (equal (+test-merge--margin session 'yours)
                   '((2 . ">> x") (6 . ">> x") (8 . ">> x") (10 . ">> x"))))
    (should (equal (+test-merge--margin session 'theirs)
                   '((4 . "x <<") (6 . "x <<") (8 . "x <<") (13 . "x <<"))))
    ;; Each button says what it does.
    (with-current-buffer (+my/merge-yours session)
      (let* ((ov (seq-find (lambda (ov) (overlay-get ov 'before-string)) (overlays-in 1 8)))
             (text (cadr (get-text-property 0 'display (overlay-get ov 'before-string)))))
        (should (equal (get-text-property 0 '+my/merge-action text)
                       (list (+test-merge--chunk session 0) 'yours 'applied)))
        (should (equal (get-text-property 3 '+my/merge-action text)
                       (list (+test-merge--chunk session 0) 'yours 'ignored)))
        (should (get-text-property 0 'mouse-face text))
        ;; The hand over the buttons.
        (should (eq (get-text-property 0 'pointer text) 'hand))
        (should (eq (get-text-property 3 'pointer text) 'hand))))
    ;; Done: a check (applied), nothing (ignored).
    (+my/merge--decide (+test-merge--chunk session 0) 'yours 'applied)
    (+my/merge--decide (+test-merge--chunk session 1) 'theirs 'ignored)
    (should (equal (assq 2 (+test-merge--margin session 'yours)) '(2 . "ok")))
    (should (equal (assq 4 (+test-merge--margin session 'theirs)) '(4 . " ")))))

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
      (should (string-match-p "\\` Accept Left  Accept Right  ✨ Apply non-conflicting   6 changes left, 1 conflict   Done  Abort\\'"
                              (funcall text)))
      (+my/merge--render-bar session 80)
      (should (equal (funcall text) " Left  Right  ✨ Non-conflicting   6 left, 1 conflict   Done  Abort"))
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
      (should (equal (cdar (+test-merge--margin session 'yours)) "*"))
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
           (event (lambda (pos) (list 'mouse-1 (list window 'right-margin '(0 . 0) 0 (cons text pos)
                                                     nil '(0 . 0) nil '(0 . 0) '(0 . 0))))))
      (+my/merge-click (funcall event 0))
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
