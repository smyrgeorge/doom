;;; tests/unit/test-git.el -*- lexical-binding: t; -*-
;; config/git.el, config/git/diff-pane.el: SPC g d shows the current file's git diff in a pane on the
;; right (focused, on the hunk of the line you were on); from another file it
;; switches the pane to that one (the pane found by its diff, marked: shown,
;; or a tab under a file); in the pane SPC g d, q or Esc closes it; it
;; refreshes when the file is saved. Real git and magit in temp repos, with a
;; temp HOME and global gitconfig (the user's are never read).

;; ====== LOADING ======

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section" "magit-delta" "magit-todos"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/git")

(defconst +test-git--magit-before (featurep 'magit-diff)
  "Whether loading config/git.el loaded magit (it mustn't).")

(require 'magit)

;; ====== HELPERS ======

(defun +test-git--git (&rest args)
  "Run git with ARGS in `default-directory'; its output (error if it failed)."
  (with-temp-buffer
    (let ((status (apply #'call-process "git" nil t nil args)))
      (unless (zerop status)
        (error "git %s: %s" (string-join args " ") (buffer-string)))
      (buffer-string))))

(defun +test-git--write (file content)
  (make-directory (file-name-directory (expand-file-name file)) t)
  (with-temp-file (expand-file-name file) (insert content)))

(defun +test-git--lines (n &optional changed)
  "N lines \"line I\", those in CHANGED (line numbers) \"CHANGED I\"."
  (mapconcat (lambda (i) (format "%s %d\n" (if (memq i changed) "CHANGED" "line") i))
             (number-sequence 1 n) ""))

(defun +test-git--environment (home)
  "`process-environment' for git with HOME (a temp folder) and its global
gitconfig: the user's never read."
  (append (list (concat "HOME=" home)
                (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                "GIT_CONFIG_NOSYSTEM=1"
                (concat "XDG_CONFIG_HOME=" home ".config")
                "GIT_TERMINAL_PROMPT=0")
          process-environment))

(defmacro +test-git-with-repo (&rest body)
  "BODY in a new git repo (`default-directory') with a.txt, b.txt and
sub/c.txt committed (30 lines each); a temp HOME and global gitconfig; one
window on *scratch*, and again after (the repo's buffers killed)."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "git-home-") t)))
            (repo (file-name-as-directory (make-temp-file (+test-tmp-file "git-repo-") t)))
            (process-environment (+test-git--environment home))
            (default-directory repo)
            (this-command 'test))
       (with-temp-file (expand-file-name ".gitconfig" home)
         (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                 "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
       (+test-git--git "init" "-q")
       (dolist (file '("a.txt" "b.txt" "sub/c.txt"))
         (+test-git--write file (+test-git--lines 30)))
       (+test-git--git "add" ".")
       (+test-git--git "commit" "-qm" "files")
       (unwind-protect (progn ,@body)
         (dolist (buffer (buffer-list))
           (with-current-buffer buffer
             (when (and buffer-file-name (string-prefix-p repo buffer-file-name))
               (set-buffer-modified-p nil))))))))

(defun +test-git--visit (file &optional line)
  "Visit FILE (of the repo) in the selected window, at LINE."
  (find-file (expand-file-name file))
  (goto-char (point-min))
  (when line (forward-line (1- line)))
  (current-buffer))

(defun +test-git--pane-files ()
  "The files the pane shows the diff of."
  (when-let* ((pane (+my/git-diff-pane--window)))
    (buffer-local-value 'magit-buffer-diff-files (window-buffer pane))))

(defun +test-git--hunk-at-point ()
  "The hunk section at point in the diff (its new-file range), or nil."
  (let ((section (magit-current-section)))
    (while (and section (not (eq (oref section type) 'hunk)))
      (setq section (oref section parent)))
    (and section (oref section to-range))))

;; ====== KEYS ======

(ert-deftest git/keys ()
  (should (eq (lookup-key doom-leader-map (kbd "g d")) #'+my/git-diff-pane))
  (should (eq (lookup-key (evil-get-auxiliary-keymap magit-diff-mode-map 'normal) [escape])
              #'+my/git-diff-pane-escape)))

(ert-deftest git/esc-in-diff-buffers ()
  "Esc in a magit diff buffer (normal state) is the pane's Esc."
  (+test-with-reset
    (with-current-buffer (+test-buffer "*test-diff*")
      (let ((process-environment (+test-git--environment (+test-tmp-file "git-home-esc/"))))
        (magit-diff-mode))
      (evil-normal-state)
      (should (eq (key-binding [escape]) #'+my/git-diff-pane-escape)))))

(ert-deftest git/loading-does-not-load-magit ()
  (should-not +test-git--magit-before))

(ert-deftest git/refreshes-on-save-hook ()
  (should (memq #'+my/git-diff-pane-refresh-h after-save-hook)))

;; ====== FINDING THE PANE AND THE FILE ======

(ert-deftest git/file-relative-to-the-repo ()
  (+test-git-with-repo
    (with-current-buffer (+test-git--visit "sub/c.txt")
      (should (equal (+my/git-diff-pane--file) "sub/c.txt")))
    (with-current-buffer (+test-git--visit "a.txt")
      (should (equal (+my/git-diff-pane--file) "a.txt")))))

(ert-deftest git/file-none-without-a-repo-file ()
  (+test-git-with-repo
    ;; Not a file.
    (with-current-buffer (+test-buffer "*no file*")
      (should-not (+my/git-diff-pane--file)))
    ;; A file outside any repo.
    (let ((outside (+test-file "git-outside/x.txt" "x\n")))
      (with-current-buffer (find-file-noselect outside)
        (should-not (+my/git-diff-pane--file))))))

(ert-deftest git/window-is-a-single-file-diff ()
  "The pane: the window showing SPC g d's diff; not another magit diff (the
whole repo's)."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(3)))
    (should-not (+my/git-diff-pane--window))
    (magit-diff-unstaged)                 ; the whole repo's diff
    (should (derived-mode-p 'magit-diff-mode))
    (should-not (+my/git-diff-pane--window))
    (+test-reset)
    (+test-git--visit "a.txt" 3)
    (+my/git-diff-pane)
    (should (eq (+my/git-diff-pane--window) (selected-window)))))

;; ====== SPC g d ======

(ert-deftest git/pane-outside-a-repo-is-a-user-error ()
  (+test-git-with-repo
    (find-file (+test-file "git-outside/y.txt" "y\n"))
    (should-error (+my/git-diff-pane) :type 'user-error)
    (should (= (length (window-list)) 1))
    (switch-to-buffer (+test-buffer "*no file*"))
    (should-error (+my/git-diff-pane) :type 'user-error)
    (should (= (length (window-list)) 1))))

(ert-deftest git/pane-opens-on-the-right-focused ()
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(5)))
    (let* ((code (selected-window))
           (width (window-total-width code))
           (buffer (+test-git--visit "a.txt" 5)))
      (+my/git-diff-pane)
      (let ((pane (selected-window)))
        (should (= (length (window-list)) 2))
        (should-not (eq pane code))
        (should (eq (window-buffer code) buffer))
        (should (eq (+my/git-diff-pane--window) pane))
        ;; On the right, half the width.
        (should (> (car (window-edges pane)) (car (window-edges code))))
        (should (= (cadr (window-edges pane)) (cadr (window-edges code))))
        (should (<= (abs (- (window-total-width pane) (/ width 2))) 1))
        ;; The file's diff, working tree vs HEAD.
        (with-current-buffer (window-buffer pane)
          (should (derived-mode-p 'magit-diff-mode))
          (should (equal magit-buffer-diff-files '("a.txt")))
          (should (equal magit-buffer-diff-range "main"))
          (should (string-match-p "^\\+CHANGED 5$" (buffer-substring-no-properties (point-min) (point-max)))))))))

(ert-deftest git/pane-halves-its-window-not-the-frame ()
  "Beside another window, on either side: the diff takes half of the window
it's opened from, not half of the frame; the other window keeps its width."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(5)))
    (dolist (side '(right left))
      (+test-reset)
      (let* ((first (selected-window))
             (second (split-window-right))
             (code (if (eq side 'right) second first))
             (other (if (eq side 'right) first second))
             (width (window-total-width code))
             (other-width (window-total-width other)))
        (select-window code)
        (+test-git--visit "a.txt" 5)
        (+my/git-diff-pane)
        (let ((pane (selected-window)))
          (should (= (length (window-list)) 3))
          (should (= (window-total-width other) other-width))
          (should (<= (abs (- (window-total-width pane) (/ width 2))) 1))
          (should (<= (abs (- (window-total-width code) (/ width 2))) 1))
          (should (> (car (window-edges pane)) (car (window-edges code)))))))))

(ert-deftest git/pane-cursor-on-the-hunk-of-the-line ()
  "The cursor goes to the hunk of the line you were on (also below the --stat
summary magit starts the diff with)."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(3 25)))
    (dolist (case '((25 . 25) (3 . 3) (24 . 25)))
      (+test-reset)
      (+test-git--visit "a.txt" (car case))
      (+my/git-diff-pane)
      (with-current-buffer (window-buffer (selected-window))
        (should (= (point) (window-point (selected-window))))
        (save-excursion
          (goto-char (point-min))
          (should (re-search-forward "1 file changed" nil t)))   ; the --stat
        (let ((range (+test-git--hunk-at-point)))
          (should range)
          (should (<= (car range) (cdr case) (+ (car range) (cadr range)))))))))

(ert-deftest git/pane-cursor-on-the-hunk-of-the-line-narrowed ()
  "In a narrowed buffer: the hunk of the line you're on, counted from the
file's start, not the narrowing's."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(6 25)))
    (let ((buffer (+test-git--visit "a.txt" 20)))
      (narrow-to-region (point) (point-max))
      (forward-line 5)                  ; line 25, the 6th of the narrowing
      (should (= (line-number-at-pos nil t) 25))
      (+my/git-diff-pane)
      (with-current-buffer (window-buffer (selected-window))
        (let ((range (+test-git--hunk-at-point)))
          (should range)
          (should (<= (car range) 25 (+ (car range) (cadr range))))))
      (with-current-buffer buffer
        (should (buffer-narrowed-p))))))

(defun +test-git--stat-width ()
  "The widest line of the diff's --stat summary (in the current buffer): the
lines after \"N file changed\" down to the first empty one."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "file changed")
    (forward-line 1)
    (let ((widest 0))
      (while (not (or (eobp) (looking-at-p "$")))
        (setq widest (max widest (string-width (buffer-substring (point) (line-end-position)))))
        (forward-line 1))
      widest)))

(ert-deftest git/pane-stat-as-wide-as-the-pane ()
  "The diff's --stat summary no wider than the pane (git's is 80 columns), in
panes of 40 and 60 columns; the pane resized, a save fits it again."
  (+test-git-with-repo
    (let ((file (expand-file-name "a/long/path/to-a-file-with-a-long-name.el"))
          (size (window-total-width (frame-root-window))))
      (+test-git--write file (+test-git--lines 200))
      (+test-git--git "add" ".")
      (+test-git--git "commit" "-qm" "long")
      (+test-git--write file (+test-git--lines 200 (number-sequence 1 200 2)))
      (unwind-protect
          (dolist (width '(80 120))
            (+test-reset)
            (set-frame-size nil width (frame-height))
            (let ((code (selected-window))
                  (buffer (+test-git--visit file 1)))
              (+my/git-diff-pane)
              (let ((pane (selected-window)))
                (should (<= (abs (- (window-total-width pane) (/ width 2))) 1))
                (with-current-buffer (window-buffer pane)
                  (should (> (+test-git--stat-width) 20))
                  (should (<= (+test-git--stat-width) (window-body-width pane))))
                ;; Narrower, then the file saved.
                (window-resize pane -10 t)
                (select-window code)
                (with-current-buffer buffer
                  (goto-char (point-max))
                  (insert "more\n")
                  (save-buffer))
                (with-current-buffer (window-buffer pane)
                  (should (<= (+test-git--stat-width) (window-body-width pane)))))))
        (set-frame-size nil size (frame-height))))))

(ert-deftest git/pane-saves-the-buffer-first ()
  "Magit diffs the file on disk: the buffer is saved first."
  (+test-git-with-repo
    (let ((buffer (+test-git--visit "a.txt" 7)))
      (delete-region (line-beginning-position) (line-end-position))
      (insert "EDITED 7")
      (should (buffer-modified-p buffer))
      (+my/git-diff-pane)
      (should-not (buffer-modified-p buffer))
      (with-current-buffer (window-buffer (selected-window))
        (should (string-match-p "^\\+EDITED 7$" (buffer-substring-no-properties (point-min) (point-max))))
        (should (equal (+test-git--hunk-at-point) '(4 7)))))))

(ert-deftest git/pane-without-changes ()
  "A file without changes: the pane opens (an empty diff), no error."
  (+test-git-with-repo
    (+test-git--visit "b.txt" 10)
    (+my/git-diff-pane)
    (should (= (length (window-list)) 2))
    (should (equal (+test-git--pane-files) '("b.txt")))))

(ert-deftest git/pane-switches-to-another-file ()
  "SPC g d from another file: the same pane shows that one."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (+test-git--write "sub/c.txt" (+test-git--lines 30 '(20)))
    (let ((code (selected-window)))
      (+test-git--visit "a.txt" 2)
      (+my/git-diff-pane)
      (let ((pane (selected-window)))
        (select-window code)
        (+test-git--visit "sub/c.txt" 20)
        (+my/git-diff-pane)
        (should (= (length (window-list)) 2))
        (should (eq (selected-window) pane))
        (should (eq (+my/git-diff-pane--window) pane))
        (should (equal (+test-git--pane-files) '("sub/c.txt")))
        (with-current-buffer (window-buffer pane)
          (should (string-match-p "^\\+CHANGED 20$" (buffer-substring-no-properties (point-min) (point-max))))
          (should (equal (+test-git--hunk-at-point) '(17 7))))))))

(defun +test-git--diff-buffers ()
  "The magit diff buffers alive."
  (seq-filter (lambda (buffer) (with-current-buffer buffer (derived-mode-p 'magit-diff-mode)))
              (buffer-list)))

(ert-deftest git/pane-keeps-one-diff ()
  "SPC g d on a.txt, sub/c.txt, then b.txt: the pane shows b.txt's diff, the
others gone from its buffers and killed; q closes the pane, not showing the
one before."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (+test-git--write "sub/c.txt" (+test-git--lines 30 '(20)))
    (+test-git--write "b.txt" (+test-git--lines 30 '(8)))
    (let ((code (selected-window))
          (files (mapcar #'expand-file-name '("a.txt" "sub/c.txt" "b.txt")))
          pane)
      (dolist (file files)
        (select-window code)
        (+test-git--visit file 8)
        (+my/git-diff-pane)
        (should (or (not pane) (eq (selected-window) pane)))
        (setq pane (selected-window)))
      (should (equal (+test-git--pane-files) '("b.txt")))
      (should (equal (+test-git--diff-buffers) (list (window-buffer pane))))
      (should-not (seq-some (lambda (entry) (not (eq (car entry) (window-buffer pane))))
                            (seq-filter (lambda (entry) (buffer-live-p (car entry)))
                                        (window-prev-buffers pane))))
      (call-interactively #'magit-mode-bury-buffer)
      (should (= (length (window-list)) 1))
      (should (eq (selected-window) code))
      (should-not (+my/git-diff-pane--window)))))

(ert-deftest git/pane-same-file-again ()
  "SPC g d again from the same file: the same diff, kept."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window)))
      (+test-git--visit "a.txt" 2)
      (+my/git-diff-pane)
      (let ((diff (window-buffer)))
        (select-window code)
        (+my/git-diff-pane)
        (should (buffer-live-p diff))
        (should (eq (window-buffer) diff))
        (should (equal (+test-git--diff-buffers) (list diff)))))))

(ert-deftest git/pane-under-a-file-reused ()
  "A file shown over the diff in its pane (as RET there): SPC g d on another
file from the code's window shows its diff in that pane, the file kept."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (+test-git--write "b.txt" (+test-git--lines 30 '(9)))
    (let ((code (selected-window))
          (a (expand-file-name "a.txt"))
          (b (expand-file-name "b.txt")))
      (+test-git--visit a 2)
      (+my/git-diff-pane)
      (let ((pane (selected-window))
            (diff (window-buffer)))
        (switch-to-buffer (find-file-noselect a))
        (should-not (+my/git-diff-pane--window))
        (select-window code)
        (+test-git--visit b 9)
        (+my/git-diff-pane)
        (should (= (length (window-list)) 2))
        (should (eq (selected-window) pane))
        (should (equal (+test-git--pane-files) '("b.txt")))
        (should-not (buffer-live-p diff))
        (should (assq (get-file-buffer a) (window-prev-buffers pane)))))))

(ert-deftest git/a-commit-of-a-file-is-not-the-pane ()
  "A commit limited to a file (as from its log) is a diff of that file, not
the pane: Esc there is Doom's, nothing closed; SPC g d opens a pane of its
own, the commit still shown."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(4)))
    (+test-git--git "commit" "-qam" "change a")
    (+test-git--write "b.txt" (+test-git--lines 30 '(9)))
    (let ((code (selected-window))
          (escaped 0))
      (+test-git--visit "a.txt" 4)
      (let ((magit-display-buffer-function
             (lambda (buffer)
               (let ((window (split-window-right)))
                 (set-window-buffer window buffer)
                 window))))
        (magit-show-commit "HEAD" nil '("a.txt")))
      (let ((commit (window-buffer))
            (window (selected-window)))
        (should (derived-mode-p 'magit-revision-mode))
        (should (equal magit-buffer-diff-files '("a.txt")))
        (should-not (+my/git-diff-pane--window))
        (cl-letf (((symbol-function 'doom/escape)
                   (lambda (&rest _) (interactive) (cl-incf escaped))))
          (+my/git-diff-pane-escape))
        (should (= escaped 1))
        (should (= (length (window-list)) 2))
        (select-window code)
        (+test-git--visit "b.txt" 9)
        (+my/git-diff-pane)
        (should (= (length (window-list)) 3))
        (should-not (eq (selected-window) window))
        (should (eq (window-buffer window) commit))
        (should (equal (+test-git--pane-files) '("b.txt")))))))

(ert-deftest git/pane-closes-from-itself ()
  "SPC g d in the pane closes it, the diff killed; the code's window stays."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window))
          (buffer (+test-git--visit "a.txt" 2)))
      (+my/git-diff-pane)
      (+my/git-diff-pane)
      (should (= (length (window-list)) 1))
      (should (eq (selected-window) code))
      (should (eq (window-buffer code) buffer))
      (should-not (+my/git-diff-pane--window))
      (should-not (+test-git--diff-buffers)))))

(ert-deftest git/pane-alone-quits ()
  "The pane as the only window: closing it shows what was there before."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((buffer (+test-git--visit "a.txt" 2)))
      (+my/git-diff-pane)
      (delete-other-windows)
      (+my/git-diff-pane)
      (should (= (length (window-list)) 1))
      (should-not (+my/git-diff-pane--window))
      (should (eq (window-buffer (selected-window)) buffer)))))

(ert-deftest git/pane-beside-a-side-panel-closes ()
  "The pane the frame's only window beside a side panel (a sidebar): SPC g d
or Esc there shows what it showed before, no error; the diff killed, the
panel kept."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (dolist (close (list #'+my/git-diff-pane #'+my/git-diff-pane-escape))
      (+test-reset)
      (let* ((code (selected-window))
             (buffer (+test-git--visit (expand-file-name "a.txt") 2))
             (side (display-buffer-in-side-window (+test-buffer "*side*") '((side . left)))))
        (+my/git-diff-pane)
        (delete-window code)
        (let ((pane (selected-window))
              (diff (window-buffer)))
          (should (window-live-p side))
          (should-not (eq (window-deletable-p pane) t))
          (cl-letf (((symbol-function 'doom/escape) (lambda (&rest _) (interactive) (error "Doom's Esc"))))
            (funcall close))
          (should (window-live-p pane))
          (should (window-live-p side))
          (should (eq (window-buffer pane) buffer))
          (should-not (buffer-live-p diff)))))))

;; ====== Q ======

(ert-deftest git/q-closes-the-pane ()
  "q (magit's bury) closes the pane: it was made for the diff."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window)))
      (+test-git--visit "a.txt" 2)
      (+my/git-diff-pane)
      (should (eq (lookup-key magit-mode-map "q") #'magit-mode-bury-buffer))
      (call-interactively #'magit-mode-bury-buffer)
      (should (= (length (window-list)) 1))
      (should (eq (selected-window) code))
      (should-not (+my/git-diff-pane--window)))))

;; ====== ESC ======

(ert-deftest git/esc-closes-the-pane ()
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window))
          (escaped nil))
      (+test-git--visit "a.txt" 2)
      (+my/git-diff-pane)
      (cl-letf (((symbol-function 'doom/escape) (lambda (&rest _) (interactive) (setq escaped t))))
        (+my/git-diff-pane-escape))
      (should-not escaped)
      (should (= (length (window-list)) 1))
      (should (eq (selected-window) code)))))

(ert-deftest git/esc-in-other-diffs-as-usual ()
  "Esc in other magit diffs (the whole repo's, or with the pane elsewhere):
Doom's Esc, nothing closed."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((escaped 0))
      (cl-letf (((symbol-function 'doom/escape)
                 (lambda (&rest _) (interactive) (cl-incf escaped))))
        (magit-diff-unstaged)
        (let ((windows (length (window-list))))
          (+my/git-diff-pane-escape)
          (should (= escaped 1))
          (should (= (length (window-list)) windows)))
        ;; The pane open, Esc in another window.
        (+test-reset)
        (+test-git--visit "a.txt" 2)
        (+my/git-diff-pane)
        (other-window 1)
        (should-not (eq (selected-window) (+my/git-diff-pane--window)))
        (+my/git-diff-pane-escape)
        (should (= escaped 2))
        (should (+my/git-diff-pane--window))))))

;; ====== REFRESH ON SAVE ======

(defmacro +test-git-counting-refreshes (var &rest body)
  "BODY, counting `magit-refresh' calls in VAR."
  (declare (indent 1))
  `(let* ((,var 0)
          (counter (lambda (&rest _) (cl-incf ,var))))
     (advice-add 'magit-refresh :before counter)
     (unwind-protect (progn ,@body)
       (advice-remove 'magit-refresh counter))))

(ert-deftest git/pane-refreshes-when-its-file-is-saved ()
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window))
          (buffer (+test-git--visit "a.txt" 2)))
      (+my/git-diff-pane)
      (select-window code)
      (with-current-buffer buffer
        (goto-char (point-min))
        (forward-line 19)
        (delete-region (line-beginning-position) (line-end-position))
        (insert "SAVED 20")
        (+test-git-counting-refreshes refreshes
          (save-buffer)
          (should (= refreshes 1))))
      (with-current-buffer (window-buffer (+my/git-diff-pane--window))
        (should (string-match-p "^\\+SAVED 20$" (buffer-substring-no-properties (point-min) (point-max))))))))

(ert-deftest git/pane-not-refreshed-by-other-saves ()
  "Saving another file (of the repo, of none), or without the pane: no refresh."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window))
          (other (find-file-noselect (expand-file-name "b.txt")))
          (outside (find-file-noselect (+test-file "git-outside/z.txt" "z\n"))))
      ;; No pane.
      (+test-git-counting-refreshes refreshes
        (with-current-buffer other
          (insert "x")
          (save-buffer))
        (should (= refreshes 0)))
      (+test-git--visit "a.txt" 2)
      (+my/git-diff-pane)
      (select-window code)
      (+test-git-counting-refreshes refreshes
        (with-current-buffer other
          (insert "y")
          (save-buffer))
        (with-current-buffer outside
          (insert "y")
          (save-buffer))
        (should (= refreshes 0))))))
