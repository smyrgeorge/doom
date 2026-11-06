;;; tests/unit/test-magit.el -*- lexical-binding: t; -*-
;; config/magit.el: the commit graph like tig (box-drawing lines, lanes in
;; colour, the date and author in the margin), git-delta diffs without the
;; delta settings of ~/.gitconfig (--no-gitconfig: its line numbers broke
;; staging / discarding hunks, "corrupt patch"), TODOs in the status buffer.
;; Real git (and delta, rg when installed) in temp repos, with a temp HOME and
;; global gitconfig: the user's are never read.

;; ====== LOADING ======

(defun +test-magit--autoloads (&rest packages)
  "Load PACKAGES' autoloads from Doom's build folder, as Doom does."
  (let ((build (file-name-directory
                (directory-file-name (file-name-directory (locate-library "magit"))))))
    (dolist (package packages)
      (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t))))

(+test-magit--autoloads "magit" "magit-section" "magit-delta" "magit-todos")
(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's core)

(+test-load "config/magit")

(defconst +test-magit--before-magit
  (list :magit (featurep 'magit)
        :delta (featurep 'magit-delta)
        :todos (featurep 'magit-todos)
        :hook (and (boundp 'magit-mode-hook) (memq 'magit-delta-mode magit-mode-hook) t))
  "What loading config/magit.el did before magit loaded (as at Doom's startup).")

(require 'magit)
(require 'magit-log)
(require 'magit-status)
(require 'ansi-color)

;; ====== HELPERS ======

(defun +test-magit--git (&rest args)
  "Run git with ARGS in `default-directory'; its output (error if it failed)."
  (with-temp-buffer
    (let ((status (apply #'call-process "git" nil t nil args)))
      (unless (zerop status)
        (error "git %s: %s" (string-join args " ") (buffer-string)))
      (buffer-string))))

(defun +test-magit--write (file content)
  (with-temp-file (expand-file-name file) (insert content)))

(defun +test-magit--read (file)
  (with-temp-buffer (insert-file-contents (expand-file-name file)) (buffer-string)))

(defmacro +test-magit-with-repo (gitconfig &rest body)
  "BODY in a new git repo (`default-directory'), with a temp HOME whose global
gitconfig has GITCONFIG too (the user's gitconfig is never read)."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "magit-home-") t)))
            (repo (file-name-as-directory (make-temp-file (+test-tmp-file "magit-repo-") t)))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1"
                           (concat "XDG_CONFIG_HOME=" home ".config")
                           "TERM=dumb"          ; as in a GUI Emacs (rg: no colours)
                           "GIT_TERMINAL_PROMPT=0")
                     process-environment))
            (default-directory repo))
       (with-temp-file (expand-file-name ".gitconfig" home)
         (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n"
                 "[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"
                 (or ,gitconfig "")))
       (+test-magit--git "init" "-q")
       ,@body)))

(defun +test-magit--graph-repo ()
  "Two branches merged: a graph with lanes (and a message with graph chars)."
  (+test-magit--write "f.txt" "a\nb\nc\n")
  (+test-magit--git "add" ".")
  (+test-magit--git "commit" "-qm" "first * commit | with - chars / \\")
  (+test-magit--git "checkout" "-qb" "side")
  (+test-magit--write "g.txt" "g\n")
  (+test-magit--git "add" ".")
  (+test-magit--git "commit" "-qm" "on side")
  (+test-magit--git "checkout" "-q" "main")
  (+test-magit--write "h.txt" "h\n")
  (+test-magit--git "add" ".")
  (+test-magit--git "commit" "-qm" "on main")
  (+test-magit--git "merge" "-q" "--no-edit" "side"))

(defun +test-magit--displays (&optional start end)
  "The `display' strings on single characters between START and END:
((POS CHAR DISPLAY)...)."
  (let (found (pos (or start (point-min))) (end (or end (point-max))))
    (while (< pos end)
      (let ((display (get-text-property pos 'display)))
        (when (stringp display)
          (push (list pos (char-after pos) display) found)))
      (setq pos (1+ pos)))
    (nreverse found)))

(defun +test-magit--section (type)
  "The current magit buffer's top-level section of TYPE."
  (seq-find (lambda (section) (eq (oref section type) type))
            (oref magit-root-section children)))

(defun +test-magit--wait (predicate &optional timeout)
  "Let processes run until PREDICATE (at most TIMEOUT seconds, default 10)."
  (let ((end (+ (float-time) (or timeout 10))) value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defmacro +test-magit-with-delta (&rest body)
  "BODY, or a skip without delta."
  (declare (indent 0))
  `(if (not (executable-find "delta"))
       (ert-skip "delta isn't installed")
     ,@body))

(defun +test-magit--delta (input args)
  "Pipe git's diff INPUT through delta with ARGS, as magit-delta does; the
text (colours removed) as lines."
  (with-temp-buffer
    (insert input)
    (apply #'call-process-region (point-min) (point-max) "delta" t t nil args)
    (split-string (ansi-color-filter-apply (buffer-string)) "\n")))

;; ====== THE COMMIT GRAPH: SETTINGS ======

(ert-deftest magit/graph-glyphs ()
  (should (equal +my/magit-graph-glyphs
                 '((?* . "●") (?| . "│") (?/ . "╱") (?\\ . "╲") (?- . "─")))))

(ert-deftest magit/log-shows-the-graph-with-colours ()
  "The log (l l): graph, lanes in colour, 256 commits, refs; date + author in
the margin."
  (should (equal (get 'magit-log-mode 'magit-log-default-arguments)
                 '("--graph" "--color" "-n256" "--decorate")))
  (should (equal magit-log-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width t 18))))

(ert-deftest magit/status-commits-open-with-the-graph ()
  "The status buffer's commits: the same graph, 20 of them, recent and
unpushed ones open."
  (should (equal (get 'magit-status-mode 'magit-log-default-arguments)
                 '("--graph" "--color" "-n256" "--decorate")))
  (should (equal magit-status-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width t 18)))
  (should (= magit-log-section-commit-count 20))
  (should (eq (alist-get 'recent magit-section-initial-visibility-alist) 'show))
  (should (eq (alist-get 'unpushed magit-section-initial-visibility-alist) 'show)))

(ert-deftest magit/settings-wait-for-magit ()
  "Loading the file doesn't load magit (Doom loads it on first use); the delta
hook is there already."
  (should-not (plist-get +test-magit--before-magit :magit))
  (should-not (plist-get +test-magit--before-magit :delta))
  (should-not (plist-get +test-magit--before-magit :todos))
  (should (plist-get +test-magit--before-magit :hook)))

;; ====== THE COMMIT GRAPH: FACES ======

(ert-deftest magit/graph-face-p ()
  "Graph characters: a lane's colour (a face plist, alone or in a list),
`magit-log-graph', ansi-color faces. Not other faces (commit messages)."
  (dolist (face '((:foreground "red3")
                  ((:foreground "green3"))
                  (bold (:foreground "red3"))
                  magit-log-graph
                  (magit-log-graph)
                  (bold magit-log-graph)
                  ansi-color-red
                  (ansi-color-bold ansi-color-blue)))
    (should (+my/magit--graph-face-p face)))
  (dolist (face '(nil magit-hash (magit-hash bold) bold
                  font-lock-comment-face (font-lock-string-face)
                  "magit-log-graph"))
    (should-not (+my/magit--graph-face-p face))))

;; ====== THE COMMIT GRAPH: DRAWING ======

(defun +test-magit--graph-buffer (mode)
  "A MODE buffer: graph characters marked with graph faces, then a message
with the same characters, unmarked or in other faces."
  (let ((buffer (+test-buffer "*test-graph*")))
    (with-current-buffer buffer
      (let ((home (+test-tmp-file "magit-home-modes/")))
        ;; A magit mode may ask git: not with the user's gitconfig.
        (let ((process-environment (append (list (concat "HOME=" home)
                                                 (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                                                 "GIT_CONFIG_NOSYSTEM=1")
                                           process-environment)))
          (funcall mode)))
      (let ((inhibit-read-only t))
        (insert (propertize "*" 'font-lock-face 'magit-log-graph)
                (propertize "|" 'font-lock-face '(:foreground "red3"))
                (propertize "/" 'font-lock-face '(ansi-color-bold (:foreground "green3")))
                (propertize "\\" 'font-lock-face 'ansi-color-blue)
                (propertize "-" 'font-lock-face '((:foreground "blue")))
                " "
                (propertize "abc123" 'font-lock-face 'magit-hash)
                " msg * | / \\ -"
                (propertize " *-" 'font-lock-face 'magit-hash)
                "\n")
        (set-buffer-modified-p nil)
        (goto-char 3)))
    buffer))

(ert-deftest magit/pretty-graph-draws-the-graph-only ()
  (+test-with-reset
    (with-current-buffer (+test-magit--graph-buffer #'magit-log-mode)
      (let ((undo buffer-undo-list))
        (+my/magit-pretty-graph-h)
        (should (equal (+test-magit--displays)
                       '((1 ?* "●") (2 ?| "│") (3 ?/ "╱") (4 ?\\ "╲") (5 ?- "─"))))
        ;; The text is the same, unmodified (no undo, no save prompt).
        (should (string-prefix-p "*|/\\- abc123 msg * | / \\ -"
                                 (buffer-substring-no-properties (point-min) (point-max))))
        (should-not (buffer-modified-p))
        (should (eq buffer-undo-list undo))
        (should (= (point) 3))))))

(ert-deftest magit/pretty-graph-follows-the-glyphs-setting ()
  (+test-with-reset
    (with-current-buffer (+test-magit--graph-buffer #'magit-log-mode)
      (let ((+my/magit-graph-glyphs '((?* . "o") (?| . "!") (?/ . "/") (?\\ . "\\") (?- . "="))))
        (+my/magit-pretty-graph-h))
      (should (equal (mapcar #'caddr (+test-magit--displays)) '("o" "!" "/" "\\" "="))))))

(ert-deftest magit/pretty-graph-in-status-buffers ()
  (+test-with-reset
    (with-current-buffer (+test-magit--graph-buffer #'magit-status-mode)
      (+my/magit-pretty-graph-h)
      (should (= (length (+test-magit--displays)) 5)))))

(ert-deftest magit/pretty-graph-not-elsewhere ()
  "Other buffers (diffs: - and + lines, any other mode) are left alone."
  (+test-with-reset
    (dolist (mode (list #'magit-diff-mode #'magit-process-mode #'fundamental-mode))
      (with-current-buffer (+test-magit--graph-buffer mode)
        (+my/magit-pretty-graph-h)
        (should-not (+test-magit--displays))))))

(ert-deftest magit/pretty-graph-runs-on-refresh ()
  (should (memq #'+my/magit-pretty-graph-h magit-refresh-buffer-hook)))

(ert-deftest magit/pretty-graph-in-the-log ()
  "l l in a repo with a merge: the graph drawn with box-drawing characters,
each lane in a colour; commit messages untouched; date and author in the
margin."
  (+test-magit-with-repo nil
    (+test-magit--graph-repo)
    (magit-log-setup-buffer (list "--all") (get 'magit-log-mode 'magit-log-default-arguments) nil)
    (with-current-buffer (magit-get-mode-buffer 'magit-log-mode)
      (let ((displays (+test-magit--displays)))
        (should displays)
        (dolist (glyph '("●" "│" "╱" "╲"))
          (should (seq-find (lambda (d) (equal (nth 2 d) glyph)) displays)))
        ;; Every one is a graph character drawn with its glyph.
        (dolist (d displays)
          (should (equal (nth 2 d) (alist-get (nth 1 d) +my/magit-graph-glyphs))))
        ;; Lanes in colour: graph characters with a colour of their own.
        (should (seq-find (lambda (d)
                            (let ((face (get-text-property (car d) 'font-lock-face)))
                              (and (consp face) (keywordp (car face)))))
                          displays))
        ;; The commit message with graph characters is left as it is.
        (goto-char (point-min))
        (should (search-forward "first * commit | with - chars / \\" nil t))
        (should-not (+test-magit--displays (match-beginning 0) (match-end 0)))
        ;; Date and author in the margin.
        (should (seq-find
                 (lambda (ov)
                   (let ((display (get-text-property 0 'display (or (overlay-get ov 'before-string) ""))))
                     (and (equal (car-safe display) '(margin right-margin))
                          (string-match-p "Tester +[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] "
                                          (cadr display)))))
                 (overlays-in (point-min) (point-max))))))))

(ert-deftest magit/status-recent-commits-open-with-the-graph ()
  "SPC g g without an upstream: \"Recent commits\" (magit makes it an
`unpushed' section, folded) open, 20 of them, the graph drawn."
  (+test-magit-with-repo nil
    (dotimes (i 25)
      (+test-magit--git "commit" "-q" "--allow-empty" "-m" (format "commit %d" i)))
    (magit-status-setup-buffer default-directory)
    (with-current-buffer (magit-get-mode-buffer 'magit-status-mode)
      (let ((recent (+test-magit--section 'unpushed)))
        (should recent)
        (should (string-prefix-p "Recent commits"
                                 (buffer-substring-no-properties (oref recent start) (oref recent end))))
        (should-not (oref recent hidden))
        (should (= (length (oref recent children)) 20))
        (should (equal (mapcar #'cadr (+test-magit--displays (oref recent start) (oref recent end)))
                       (make-list 20 ?*))))
      ;; Magit's own default: folded.
      (let ((magit-section-initial-visibility-alist
             (seq-remove (lambda (e) (memq (car e) '(recent unpushed)))
                         magit-section-initial-visibility-alist)))
        (setq magit-section-visibility-cache nil)
        (magit-refresh)
        (should (oref (+test-magit--section 'unpushed) hidden))))))

(ert-deftest magit/status-unpushed-commits-open ()
  (+test-magit-with-repo nil
    (let ((bare (make-temp-file (+test-tmp-file "magit-remote-") t)))
      (+test-magit--git "commit" "-q" "--allow-empty" "-m" "pushed")
      (+test-magit--git "init" "-q" "--bare" bare)
      (+test-magit--git "remote" "add" "origin" bare)
      (+test-magit--git "push" "-q" "-u" "origin" "main")
      (+test-magit--git "commit" "-q" "--allow-empty" "-m" "not pushed")
      (magit-status-setup-buffer default-directory)
      (with-current-buffer (magit-get-mode-buffer 'magit-status-mode)
        (let ((unpushed (+test-magit--section 'unpushed)))
          (should unpushed)
          (should-not (oref unpushed hidden))
          (should (= (length (oref unpushed children)) 1)))))))

;; ====== DELTA ======

(ert-deftest magit/delta-mode-in-magit-buffers ()
  (should (memq 'magit-delta-mode magit-mode-hook))
  (+test-magit-with-repo nil
    (+test-magit--git "commit" "-q" "--allow-empty" "-m" "x")
    (magit-status-setup-buffer default-directory)
    (with-current-buffer (magit-get-mode-buffer 'magit-status-mode)
      (should magit-delta-mode)
      (should (memq 'magit-delta-call-delta-and-convert-ansi-escape-sequences
                    magit-diff-wash-diffs-hook)))))

(ert-deftest magit/delta-ignores-the-gitconfig ()
  "--no-gitconfig appended to magit-delta's arguments (theirs kept), once,
even when the file is loaded again."
  (require 'magit-delta)
  (should (equal (car (last magit-delta-delta-args)) "--no-gitconfig"))
  (should (member "--color-only" magit-delta-delta-args))
  (should (member "--max-line-distance" magit-delta-delta-args))
  (+test-load "config/magit")
  (should (= (seq-count (lambda (a) (equal a "--no-gitconfig")) magit-delta-delta-args) 1))
  (let ((args (magit-delta--make-delta-args)))
    (should (member "--no-gitconfig" args))
    (should (member "--color-only" args))))

(ert-deftest magit/delta-gitconfig-line-numbers-and-no-gitconfig ()
  "Why --no-gitconfig: with `delta.line-numbers' in the gitconfig, delta writes
line numbers into the text of the diff even in --color-only mode; with
--no-gitconfig the lines stay git's."
  (+test-magit-with-delta
    (+test-magit-with-repo "[delta]\n\tline-numbers = true\n\tside-by-side = true\n"
      (+test-magit--write "f.txt" "a\nb\nc\n")
      (+test-magit--git "add" ".")
      (+test-magit--git "commit" "-qm" "f")
      (+test-magit--write "f.txt" "a\nB\nc\n")
      (require 'magit-delta)
      (let* ((diff (+test-magit--git "diff"))
             (args (magit-delta--make-delta-args))
             (fixed (+test-magit--delta diff args))
             (unfixed (+test-magit--delta diff (remove "--no-gitconfig" args))))
        (should (equal (seq-drop-while (lambda (l) (not (string-prefix-p "@@" l))) fixed)
                       '("@@ -1,3 +1,3 @@" " a" "-b" "+B" " c" "")))
        ;; Without it: the gitconfig's line numbers in the text.
        (should (seq-find (lambda (l) (string-match-p "⋮" l)) unfixed))
        (should-not (member "-b" unfixed))))))

(ert-deftest magit/delta-discard-and-stage-hunks ()
  "x (discard) and s (stage) on a hunk work with delta rendering the diff,
whatever the gitconfig's delta settings."
  (+test-magit-with-delta
    (+test-magit-with-repo "[delta]\n\tline-numbers = true\n"
      (+test-magit--write "f.txt" "a\nb\nc\n")
      (+test-magit--write "g.txt" "1\n2\n3\n")
      (+test-magit--git "add" ".")
      (+test-magit--git "commit" "-qm" "f")
      (+test-magit--write "f.txt" "a\nB\nc\n")
      (+test-magit--write "g.txt" "1\n2\n3\n4\n")
      (magit-diff-unstaged)
      (with-current-buffer (magit-get-mode-buffer 'magit-diff-mode)
        (should magit-delta-mode)
        ;; delta rendered it (its colours as overlays), git's text kept.
        (should (seq-find (lambda (ov) (overlay-get ov 'face)) (overlays-in (point-min) (point-max))))
        (goto-char (point-min))
        (should (re-search-forward "^-b$" nil t))
        (let ((magit-no-confirm t))
          ;; Discard f.txt's hunk.
          (goto-char (point-min))
          (re-search-forward "^@@")
          (should (equal (oref (oref (magit-current-section) parent) value) "f.txt"))
          (magit-discard)
          (should (equal (+test-magit--read "f.txt") "a\nb\nc\n"))
          ;; Stage g.txt's.
          (goto-char (point-min))
          (re-search-forward "^@@")
          (should (equal (oref (oref (magit-current-section) parent) value) "g.txt"))
          (magit-stage)
          (should (equal (+test-magit--git "diff" "--cached" "--name-only") "g.txt\n"))
          (should (equal (+test-magit--read "g.txt") "1\n2\n3\n4\n")))))))

(ert-deftest magit/delta-without-no-gitconfig-corrupts-patches ()
  "The bug --no-gitconfig fixes: without it, the gitconfig's line numbers end
up in the hunk magit sends to git, and discarding it fails."
  (+test-magit-with-delta
    (+test-magit-with-repo "[delta]\n\tline-numbers = true\n"
      (+test-magit--write "f.txt" "a\nb\nc\n")
      (+test-magit--git "add" ".")
      (+test-magit--git "commit" "-qm" "f")
      (+test-magit--write "f.txt" "a\nB\nc\n")
      (require 'magit-delta)
      (let ((magit-delta-delta-args (remove "--no-gitconfig" magit-delta-delta-args))
            (magit-no-confirm t))
        (magit-diff-unstaged)
        (with-current-buffer (magit-get-mode-buffer 'magit-diff-mode)
          (goto-char (point-min))
          (re-search-forward "^@@")
          (should (string-match-p "⋮" (buffer-substring-no-properties (point) (point-max))))
          (ignore-errors (magit-discard))))
      (should (equal (+test-magit--read "f.txt") "a\nB\nc\n")))))

;; ====== TODOS ======

(ert-deftest magit/todos-mode-on-with-magit ()
  (should (featurep 'magit-todos))
  (should magit-todos-mode)
  (should (memq 'magit-todos--insert-todos magit-status-sections-hook))
  (should (equal magit-todos-rg-extra-args '("--color=never"))))

(ert-deftest magit/todos-in-the-status-buffer ()
  "The repo's TODO/FIXME comments listed in the status buffer (rg), also when
TERM allows colours (terminal Emacs: rg runs on a pty)."
  (unless (executable-find "rg") (ert-skip "rg isn't installed"))
  (+test-magit-with-repo nil
    (setq process-environment (cons "TERM=xterm-256color" process-environment))
    (+test-magit--write "a.kt" "fun a() {\n    // TODO: handle errors\n}\n")
    (+test-magit--write "b.py" "x = 1  # FIXME: wrong value\nplain line\n")
    (+test-magit--git "add" ".")
    (+test-magit--git "commit" "-qm" "code")
    (magit-status-setup-buffer default-directory)
    (with-current-buffer (magit-get-mode-buffer 'magit-status-mode)
      (should (+test-magit--wait (lambda () (string-match-p "^TODOs (2)" (buffer-string)))))
      (should (string-match-p "a\\.kt.*TODO.*handle errors" (buffer-string)))
      (should (string-match-p "b\\.py.*FIXME.*wrong value" (buffer-string))))))
