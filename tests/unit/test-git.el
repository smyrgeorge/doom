;;; tests/unit/test-git.el -*- lexical-binding: t; -*-
;; config/git.el, config/git/diff-pane.el: SPC g d shows the current file's git diff in a pane on the
;; right (focused, on the hunk of the line you were on); from another file it
;; switches the pane to that one; in the pane SPC g d, q or Esc closes it; it
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
  "The pane: a window showing a magit diff of files; not a whole-repo diff."
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

(ert-deftest git/pane-closes-from-itself ()
  "SPC g d in the pane closes it; the code's window stays."
  (+test-git-with-repo
    (+test-git--write "a.txt" (+test-git--lines 30 '(2)))
    (let ((code (selected-window))
          (buffer (+test-git--visit "a.txt" 2)))
      (+my/git-diff-pane)
      (+my/git-diff-pane)
      (should (= (length (window-list)) 1))
      (should (eq (selected-window) code))
      (should (eq (window-buffer code) buffer))
      (should-not (+my/git-diff-pane--window)))))

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
