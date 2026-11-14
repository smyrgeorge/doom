;;; tests/e2e/test-tiling.el -*- lexical-binding: t; -*-
;; Tiling first (config/tiling/apps.el) in a GUI Emacs, with the real
;; features: the terminal (Doom's SPC o t, a real shell, its popup rule
;; standing in: the pane as wide as the strategy makes it, not the rule's 40
;; columns), Claude Code's sessions (agent-shell's own display, a stand-in
;; session: no agent) and the files its links open, the Markdown preview
;; (pandoc, WebKit), drawings (Excalidraw) and the drawing for Claude, a
;; file's diff (magit) and RET in it, files opened from an application's
;; pane, a popup's links, tabs closing their pane, popups left alone.

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section" "magit-delta" "magit-todos" "ghostel"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/childframe" "config/banner" "config/window" "config/editor" "config/webkit"
            "config/markdown" "config/excalidraw" "config/git" "config/agent-shell" "config/tiling")
(require 'markdown-mode)
(require 'agent-shell)
(global-tab-line-mode 1)

;; Doom's SPC o t (its term/ghostel module).
(load (expand-file-name "sources/doom+/modules/term/ghostel/autoload.el" +test-doom-emacs-dir) nil t)

(defmacro +test-tiling--doom-projects (&rest body)
  "BODY with what SPC o t asks of Doom's projects (projectile's, not here): no
project root, a name."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'doom-project-root) (lambda (&optional _dir) nil))
             ((symbol-function 'doom-project-name) (lambda (&optional _dir) "test")))
     ,@body))

;; Doom's popup rule for SPC o t's terminal: a side window 40 columns wide, a
;; quarter of the height (`+popup-defaults', the module's rule).
(add-to-list 'display-buffer-alist
             '("^\\*doom:\\(?:v?term\\|e?shell\\|ghostel\\)-popup"
               (display-buffer-in-side-window)
               (side . bottom) (window-width . 40) (window-height . 0.25)
               (window-parameters (ttl . 0) (quit . nil))))

(defvar +test-tiling--excalidraw (+test-excalidraw-dir))

;; ====== HELPERS ======

(defun +test-tiling--layout ()
  "The panes, in order, as buffer names."
  (mapcar (lambda (window) (buffer-name (window-buffer window))) (+my/tiling--panes)))

(defun +test-tiling--dir ()
  (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "tiling-") t))))

(defun +test-tiling--file (name &optional text dir)
  "File NAME (with TEXT) in DIR (default: a new folder), visited."
  (let ((file (expand-file-name name (or dir (+test-tiling--dir)))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert (or text "text\n")))
    (find-file-noselect file)))

(defun +test-tiling--session (&optional name)
  "A stand-in Claude Code session (agent-shell's mode, no agent)."
  (let ((buffer (generate-new-buffer (or name "*claude-code @ test*"))))
    (with-current-buffer buffer
      (setq-local major-mode 'agent-shell-mode))
    buffer))

(defun +test-tiling--tabs (window)
  (with-selected-window window
    (mapcar #'buffer-name (+my/tabs-window-buffers))))

(defun +test-tiling--needs-ghostel ()
  "Skip unless ghostel's native module is built for this system (a .so on
Linux, a .dylib on macOS): without, the terminal asks how to get one."
  (let ((dir (file-name-directory (or (locate-library "ghostel") ""))))
    (unless (and dir (file-exists-p (expand-file-name (concat "ghostel-module" module-file-suffix) dir)))
      (ert-skip (format "No ghostel module (ghostel-module%s): M-x ghostel-module-compile"
                        module-file-suffix)))))

(defmacro +test-tiling (&rest body)
  "BODY from one pane showing a file, a.txt, selected, as commands run (new
windows take focus); the buffers it made killed after."
  (declare (indent 0))
  `(+test-with-reset
     (let ((this-command 'test)
           (+my/tiling-strategy 'tall)
           (+my/tiling-tall-ratio 0.5)
           (+my/focus-new-windows t)
           (kill-buffer-query-functions nil)
           (confirm-kill-processes nil))
       (switch-to-buffer (+test-tiling--file "a.txt"))
       (set-window-prev-buffers nil nil)
       ,@body)))

;; ====== THE TERMINAL (SPC o t) ======

(ert-deftest e2e-tiling/terminal-in-a-pane-as-wide-as-the-strategy-makes-it ()
  "SPC o t: the terminal in a new pane on the right, half the width, not
Doom's popup (40 columns); again, its pane closes."
  (+test-tiling--needs-ghostel)
  (+test-tiling
    (+test-tiling--doom-projects
    (let ((main (selected-window)))
      (call-interactively #'+ghostel/toggle)
      (let* ((terminal (seq-find (lambda (b) (string-prefix-p "*doom:ghostel-popup" (buffer-name b))) (buffer-list)))
             (window (get-buffer-window terminal)))
        (should terminal)
        (should (eq (selected-window) window))
        (should-not (window-parameter window 'window-side))
        (should (equal (+test-tiling--layout) (list "a.txt" (buffer-name terminal))))
        (should (> (window-total-width window) 50))
        (should (<= (abs (- (window-total-width window) (window-total-width main))) 1))
        ;; The terminal's own width is its pane's.
        (should (+test-wait-for (lambda () (with-current-buffer terminal (> (buffer-size) 0))) 10))
        ;; Again: closed.
        (call-interactively #'+ghostel/toggle)
        (should-not (window-live-p window))
        (should (equal (+test-tiling--layout) '("a.txt")))
        (kill-buffer terminal))))))

(ert-deftest e2e-tiling/terminal-killed-its-pane-closes ()
  "The terminal's buffer killed (its shell ended): its pane closes."
  (+test-tiling--needs-ghostel)
  (+test-tiling
    (+test-tiling--doom-projects
      (call-interactively #'+ghostel/toggle)
      (let* ((terminal (window-buffer))
             (window (selected-window)))
        (should (with-current-buffer terminal (derived-mode-p 'ghostel-mode)))
        (kill-buffer terminal)
        (should-not (window-live-p window))
        (should (equal (+test-tiling--layout) '("a.txt")))))))

(ert-deftest e2e-tiling/spc-o-T-a-terminal-here ()
  "SPC o T (Doom's): a new terminal in the pane you're in, not a new pane;
the file there a tab under it, shown again once the terminal's killed."
  (+test-tiling--needs-ghostel)
  (+test-tiling
    (+test-tiling--doom-projects
      (let ((here (selected-window))
            (file (window-buffer)))
        (let ((this-command '+ghostel/here))
          (call-interactively #'+ghostel/here))
        (let ((terminal (window-buffer here)))
          (should (eq (selected-window) here))
          (should (with-current-buffer terminal (derived-mode-p 'ghostel-mode)))
          (should (equal (+test-tiling--layout) (list (buffer-name terminal))))
          (should (equal (+test-tiling--tabs here) (list "a.txt" (buffer-name terminal))))
          (kill-buffer terminal)
          (should (window-live-p here))
          (should (eq (window-buffer here) file)))))))

;; ====== A PANE CLOSED ======

(ert-deftest e2e-tiling/a-closed-pane-s-rows-shared-by-the-stack ()
  "Three sessions stacked beside the file; the middle one closed (its buffer
killed): the two left at equal heights once Emacs redisplays (its
`window-state-change-functions'), with no call of ours."
  (+test-tiling
    (let ((main (selected-window))
          (sessions (mapcar #'+test-tiling--session '("*one*" "*two*" "*three*"))))
      (dolist (session sessions)
        (select-window main)
        (display-buffer session))
      (redisplay t)
      (should (equal (+test-tiling--layout) '("a.txt" "*one*" "*two*" "*three*")))
      (kill-buffer (nth 1 sessions))
      (should (equal (+test-tiling--layout) '("a.txt" "*one*" "*three*")))
      (should (+test-wait-for
               (lambda ()
                 (redisplay t)
                 (let ((heights (mapcar #'window-total-height (cdr (+my/tiling--panes)))))
                   (<= (abs (- (car heights) (cadr heights))) 1)))
               3))
      (mapc #'kill-buffer (list (nth 0 sessions) (nth 2 sessions))))))

;; ====== CLAUDE CODE ======

(ert-deftest e2e-tiling/claude-code-in-a-new-pane-its-links-as-its-tabs ()
  "agent-shell shows a session (SPC o c) in a new pane; shown, it's selected
there. Its links to files open them as tabs in its pane, the session one too,
a file shown in another pane too."
  (+test-tiling
    (let* ((left (selected-window))
           (session (+test-tiling--session))
           (file (+test-tiling--file "b.txt" "one\ntwo\n")))
      (agent-shell--display-buffer session)
      (let ((pane (selected-window)))
        (should-not (eq pane left))
        (should (equal (+test-tiling--layout) (list "a.txt" (buffer-name session))))
        ;; Again: there, no new pane.
        (select-window left)
        (agent-shell--display-buffer session)
        (should (eq (selected-window) pane))
        (should (= (length (+my/tiling--panes)) 2))
        ;; A link in it (path:line).
        (funcall agent-shell-markdown-open-file-function (buffer-file-name file))
        (should (eq (selected-window) pane))
        (should (eq (window-buffer pane) file))
        (should (equal (+test-tiling--tabs pane) (list (buffer-name session) "b.txt")))
        (should (equal (+test-tiling--tabs left) '("a.txt")))
        ;; A link to a.txt, shown on the left: here too.
        (switch-to-buffer session)
        (funcall agent-shell-markdown-open-file-function (buffer-file-name (window-buffer left)))
        (should (eq (selected-window) pane))
        (should (equal (buffer-name (window-buffer pane)) "a.txt"))
        (should (equal (buffer-name (window-buffer left)) "a.txt"))))))

(ert-deftest e2e-tiling/files-found-in-an-application-s-pane-as-its-tabs ()
  "SPC SPC (find-file) in Claude Code's pane: the file there, a tab."
  (+test-tiling
    (let ((left (selected-window))
          (session (+test-tiling--session))
          (file (+test-tiling--file "c.txt")))
      (agent-shell--display-buffer session)
      (let ((pane (selected-window)))
        (find-file (buffer-file-name file))
        (should (eq (selected-window) pane))
        (should (eq (window-buffer pane) file))
        (should (equal (+test-tiling--tabs pane) (list (buffer-name session) "c.txt")))
        (should (equal (+test-tiling--tabs left) '("a.txt")))))))

(ert-deftest e2e-tiling/a-session-alone-files-as-its-tabs ()
  "The session alone: a file opens in its pane, a tab, no new pane."
  (+test-tiling
    (let ((session (+test-tiling--session))
          (file (+test-tiling--file "d.txt")))
      (switch-to-buffer session)
      (find-file (buffer-file-name file))
      (should (equal (+test-tiling--layout) '("d.txt")))
      (should (equal (+test-tiling--tabs (selected-window)) (list "a.txt" (buffer-name session) "d.txt"))))))

(defmacro +test-tiling--starting-sessions (&rest body)
  "BODY with agent-shell starting stand-in sessions (no agent), as it does
before a session is picked: each with a state keeping its subscriptions.
`sessions' holds them, newest first; killed after."
  (declare (indent 0))
  `(let ((sessions nil)
         (agent-shell-prefer-viewport-interaction nil)
         (agent-shell-session-strategy 'prompt))
     (cl-letf (((symbol-function 'agent-shell--start)
                (lambda (&rest _)
                  (let ((session (+test-tiling--session
                                  (format "*claude-code @ test %d*" (length sessions)))))
                    (with-current-buffer session
                      (setq-local agent-shell--state
                                  (list (cons :buffer session) (cons :event-subscriptions nil))))
                    (push session sessions)
                    session)))
               ((symbol-function 'agent-shell--context) (lambda (&rest _) nil)))
       (unwind-protect (progn ,@body)
         (mapc #'kill-buffer sessions)))))

(defun +test-tiling--session-picked (session)
  "SESSION's prompt answered (a new session, or one to resume): agent-shell
says so, its subscribers show it."
  (with-current-buffer session
    (agent-shell--emit-event :event 'session-selected)))

(ert-deftest e2e-tiling/spc-o-C-claude-code-here-once-a-session-is-picked ()
  "SPC o C: Claude Code started as SPC o c starts it, shown once a session
is picked (after the command, agent-shell's prompt answered): in the pane
you were in, the file there a tab under it, no new pane. SPC o c then: in a
new pane."
  (+test-tiling
    (+test-tiling--starting-sessions
      (let ((here (selected-window)))
        (+my/agent-shell-claude-here)
        (should (= (length sessions) 1))
        ;; Not shown before a session's picked.
        (should (equal (+test-tiling--layout) '("a.txt")))
        (+test-tiling--session-picked (car sessions))
        (let ((name (buffer-name (car sessions))))
          (should (eq (selected-window) here))
          (should (equal (+test-tiling--layout) (list name)))
          (should (equal (+test-tiling--tabs here) (list "a.txt" name))))
        ;; SPC o c: a new pane.
        (agent-shell-anthropic-start-claude-code)
        (+test-tiling--session-picked (car sessions))
        (should-not (eq (selected-window) here))
        (should (equal (+test-tiling--layout) (reverse (mapcar #'buffer-name sessions))))))))

;; ====== THE MARKDOWN PREVIEW ======

(ert-deftest e2e-tiling/markdown-preview-in-a-new-pane ()
  "SPC m p: the preview in a new pane (the stack's bottom with one there
already), the cursor staying in the file; off, its pane closes."
  (+test-tiling
    (let* ((left (selected-window))
           (readme (+test-tiling--file "README.md" "# Title\n\nText.\n")))
      (switch-to-buffer readme)
      (markdown-mode)
      (agent-shell--display-buffer (+test-tiling--session))
      (select-window left)
      (+md-preview-mode 1)
      (should (eq (selected-window) left))
      (let ((preview (get-buffer-window +md-preview--buffer)))
        (should (window-live-p preview))
        (should-not (window-parameter preview 'window-side))
        (should (= (length (+my/tiling--panes)) 3))
        ;; The stack's bottom.
        (should (eq (car (last (+my/tiling--panes))) preview))
        (+md-preview-mode -1)
        (should-not (window-live-p preview))
        (should (= (length (+my/tiling--panes)) 2))))))

(ert-deftest e2e-tiling/markdown-preview-closed-by-its-tab-opens-again ()
  "The preview's pane closed by its tab's ✕ (the pane goes with its last tab,
the preview stays on): the notice's Open preview shows it again, in a new
pane, the notice still there."
  (+test-needs-webkit)
  (+test-tiling
    (let* ((left (selected-window))
           (readme (+test-tiling--file "README.md" "# Title\n\nText.\n"))
           (open (lambda ()
                   (with-current-buffer readme
                     (funcall (cdr (assoc "Open preview" (nth 2 (assq 'markdown-preview +my/banner--list)))))))))
      (switch-to-buffer readme)
      (markdown-mode)
      (should (assq 'markdown-preview +my/banner--list))
      (funcall open)
      (let ((preview (buffer-local-value '+md-preview--buffer readme)))
        (should (= (length (+my/tiling--panes)) 2))
        ;; Its tab's ✕.
        (with-selected-window (get-buffer-window preview)
          (+my/tabs-close-current))
        (should (= (length (+my/tiling--panes)) 1))
        (should (buffer-local-value '+md-preview-mode readme))
        (funcall open)
        (should (eq (buffer-local-value '+md-preview--buffer readme) preview))
        (should (get-buffer-window preview))
        (should (= (length (+my/tiling--panes)) 2))
        (should (eq (selected-window) left))
        (should (assq 'markdown-preview +my/banner--list))
        ;; Again: still one.
        (funcall open)
        (should (= (length (+my/tiling--panes)) 2))
        (with-current-buffer readme (+md-preview-mode -1))))))

;; ====== DRAWINGS ======

(ert-deftest e2e-tiling/drawings-in-a-new-pane ()
  "Option+Enter's new drawing, from Markdown: in a new pane, taking focus; its
link where it was."
  (+test-needs-webkit)
  (unless +test-tiling--excalidraw
    (ert-skip "No Excalidraw in Doom's data folder"))
  (+test-tiling
    (let* ((left (selected-window))
           (notes (+test-tiling--file "notes.md" "# Notes\n\n")))
      (switch-to-buffer notes)
      (markdown-mode)
      (goto-char (point-max))
      (+my/excalidraw-insert "fig")
      (should-not (eq (selected-window) left))
      (should (derived-mode-p '+my/excalidraw-mode))
      (should (equal (+test-tiling--layout) '("notes.md" "fig.excalidraw.svg")))
      (should (string-suffix-p "![](fig.excalidraw.svg)" (with-current-buffer notes (buffer-string))))
      (set-buffer-modified-p nil)
      (kill-buffer)
      (should (equal (+test-tiling--layout) '("notes.md"))))))

(ert-deftest e2e-tiling/drawing-for-claude-in-a-new-pane ()
  "C-c C-d in Claude Code's pane: the drawing in a new pane (not its left);
discarded, the pane closes."
  (+test-needs-webkit)
  (unless +test-tiling--excalidraw
    (ert-skip "No Excalidraw in Doom's data folder"))
  (+test-tiling
    (let ((dir (+test-tiling--dir))
          (session (+test-tiling--session)))
      (agent-shell--display-buffer session)
      (cl-letf (((symbol-function 'agent-shell--dot-subdir)
                 (lambda (subdir) (let ((d (expand-file-name subdir dir))) (make-directory d t) d))))
        (let ((drawing (+my/agent-shell-excalidraw)))
          (should (eq (window-buffer) drawing))
          (should (equal (+test-tiling--layout) (list "a.txt" (buffer-name session) (buffer-name drawing))))
          (should (+test-wait-for (lambda () (file-exists-p (buffer-file-name drawing))) 10))
          (+my/agent-shell-excalidraw-discard)
          (should (equal (+test-tiling--layout) (list "a.txt" (buffer-name session)))))))))

;; ====== A FILE'S DIFF ======

(defun +test-tiling--git (&rest args)
  (should (zerop (apply #'call-process "git" nil nil nil
                        "-c" "user.name=T" "-c" "user.email=t@example.invalid"
                        "-c" "commit.gpgsign=false" "-c" "core.hooksPath=/dev/null" args))))

(ert-deftest e2e-tiling/file-diff-in-a-new-pane-ret-there ()
  "SPC g d: the diff in a new pane; RET on a line opens the file there, a tab
beside the diff's; the diff's tab again, SPC g d closes its pane."
  (+test-tiling
    (let* ((dir (+test-tiling--dir))
           (default-directory dir)
           (left (selected-window)))
      (+test-tiling--git "init" "-q")
      (with-temp-file (expand-file-name "f.txt" dir) (insert "one\ntwo\nthree\n"))
      (+test-tiling--git "add" "f.txt")
      (+test-tiling--git "commit" "-qm" "f")
      (find-file (expand-file-name "f.txt" dir))
      (goto-char (point-max))
      (insert "four\n")
      (save-buffer)
      (let ((file (current-buffer)))
        (+my/git-diff-pane)
        (let* ((diff (selected-window))
               (diff-buffer (window-buffer diff)))
          (should-not (eq diff left))
          (should (with-current-buffer diff-buffer (derived-mode-p 'magit-diff-mode)))
          (set-buffer diff-buffer)
          (should (= (length (+my/tiling--panes)) 2))
          ;; RET on the added line: the file here, a tab.
          (goto-char (point-min))
          (should (search-forward "+four" nil t))
          (call-interactively #'magit-diff-visit-file)
          (should (eq (selected-window) diff))
          (should (eq (window-buffer diff) file))
          (should (equal (+test-tiling--tabs diff) (list (buffer-name diff-buffer) "f.txt")))
          (should (eq (window-buffer left) file))
          ;; Its tab again; SPC g d there closes the pane.
          (switch-to-buffer diff-buffer)
          (+my/git-diff-pane)
          (should-not (window-live-p diff))
          (should (= (length (+my/tiling--panes)) 1)))))))

(ert-deftest e2e-tiling/file-diff-one-tab-whichever-files ()
  "SPC g d on f.txt, g.txt, then h.txt: the diff's pane has one tab, h.txt's
diff (the others killed); q closes the pane."
  (+test-tiling
    (let* ((dir (+test-tiling--dir))
           (default-directory dir)
           (left (selected-window))
           (files (mapcar (lambda (name) (expand-file-name name dir)) '("f.txt" "g.txt" "h.txt")))
           pane)
      (+test-tiling--git "init" "-q")
      (dolist (file files)
        (with-temp-file file (insert "one\ntwo\n")))
      (+test-tiling--git "add" ".")
      (+test-tiling--git "commit" "-qm" "files")
      (dolist (file files)
        (select-window left)
        (find-file file)
        (goto-char (point-max))
        (insert "three\n")
        (+my/git-diff-pane)
        (should (or (not pane) (eq (selected-window) pane)))
        (setq pane (selected-window)))
      (let ((diff (window-buffer pane)))
        (should (= (length (+my/tiling--panes)) 2))
        (should (equal (buffer-local-value 'magit-buffer-diff-files diff) '("h.txt")))
        (should (equal (+test-tiling--tabs pane) (list (buffer-name diff))))
        (should (equal (seq-filter (lambda (buffer) (with-current-buffer buffer (derived-mode-p 'magit-diff-mode)))
                                   (buffer-list))
                       (list diff)))
        (set-buffer diff)
        (call-interactively #'magit-mode-bury-buffer)
        (should-not (window-live-p pane))
        (should (= (length (+my/tiling--panes)) 1))))))

(defun +test-tiling--repo (dir &rest names)
  "A git repo in DIR with files NAMES committed (two lines each), then a
line added to each (not committed)."
  (let ((files (mapcar (lambda (name) (expand-file-name name dir)) names)))
    (+test-tiling--git "init" "-q")
    (dolist (file files)
      (with-temp-file file (insert "one\ntwo\n")))
    (+test-tiling--git "add" ".")
    (+test-tiling--git "commit" "-qm" "files")
    (dolist (file files)
      (with-temp-file file (insert "one\ntwo\nthree\n")))
    files))

(ert-deftest e2e-tiling/file-diff-pane-found-under-a-tab ()
  "RET in the diff (its file a tab over it), then SPC g d on another file from
the first pane: that pane shows its diff, the file's tab kept; no third pane."
  (+test-tiling
    (let* ((dir (+test-tiling--dir))
           (default-directory dir)
           (left (selected-window))
           (files (+test-tiling--repo dir "f.txt" "g.txt")))
      (find-file (car files))
      (+my/git-diff-pane)
      (let ((pane (selected-window)))
        (set-buffer (window-buffer pane))
        (goto-char (point-min))
        (should (search-forward "+three" nil t))
        (call-interactively #'magit-diff-visit-file)
        (should (eq (window-buffer pane) (get-file-buffer (car files))))
        (select-window left)
        (find-file (cadr files))
        (+my/git-diff-pane)
        (should (= (length (+my/tiling--panes)) 2))
        (should (eq (selected-window) pane))
        (should (equal (buffer-local-value 'magit-buffer-diff-files (window-buffer pane)) '("g.txt")))
        (should (seq-set-equal-p (+test-tiling--tabs pane)
                                 (list "f.txt" (buffer-name (window-buffer pane)))))))))

(ert-deftest e2e-tiling/magit-status-and-its-buffers ()
  "SPC g g from a file: magit's status in a new pane; its log in that pane; a
commit from the log in a new pane, q closes it; RET on a file in the status:
the file there, a tab; SPC g g again: the status's tab there."
  (+test-tiling
    (let* ((dir (+test-tiling--dir))
           (default-directory dir)
           (left (selected-window)))
      (+test-tiling--git "init" "-q")
      (with-temp-file (expand-file-name "f.txt" dir) (insert "one\n"))
      (+test-tiling--git "add" "f.txt")
      (+test-tiling--git "commit" "-qm" "first")
      (with-temp-file (expand-file-name "f.txt" dir) (insert "one\ntwo\n"))
      (find-file (expand-file-name "f.txt" dir))
      (revert-buffer t t)
      (let ((file (current-buffer)))
        (magit-status-setup-buffer dir)
        (let ((status (selected-window)))
          (should-not (eq status left))
          (should (with-current-buffer (window-buffer status) (derived-mode-p 'magit-status-mode)))
          (should (= (length (+my/tiling--panes)) 2))
          ;; Its log: in its pane.
          (magit-log-setup-buffer (list "HEAD") nil nil)
          (should (eq (selected-window) status))
          (should (with-current-buffer (window-buffer status) (derived-mode-p 'magit-log-mode)))
          (should (= (length (+my/tiling--panes)) 2))
          ;; A commit from it: a new pane; q closes it.
          (magit-show-commit "HEAD")
          (let ((revision (get-buffer-window (magit-get-mode-buffer 'magit-revision-mode))))
            (should (window-live-p revision))
            (should-not (memq revision (list left status)))
            (should (= (length (+my/tiling--panes)) 3))
            (with-selected-window revision
              (magit-mode-bury-buffer))
            (should-not (window-live-p revision)))
          (should (= (length (+my/tiling--panes)) 2))
          ;; Back to the status; RET on its file.
          (select-window status)
          (magit-mode-bury-buffer)
          (should (eq (window-buffer status) (magit-get-mode-buffer 'magit-status-mode)))
          (goto-char (point-min))
          (should (re-search-forward "^modified +f\\.txt" nil t))
          (call-interactively #'magit-diff-visit-file)
          (should (eq (selected-window) status))
          (should (eq (window-buffer status) file))
          ;; SPC g g again, from the file over it: the status's tab there.
          (magit-status-setup-buffer dir)
          (should (eq (selected-window) status))
          (should (with-current-buffer (window-buffer status) (derived-mode-p 'magit-status-mode)))
          (should (= (length (+my/tiling--panes)) 2)))))))

;; ====== POPUPS, TABS ======

(define-derived-mode +test-tiling-e2e-app-mode special-mode "App"
  "Stands for an application not a file's nor Doom's \"real\" of its own:
Beads' issue list, the Markdown preview.")

(ert-deftest e2e-tiling/an-application-keeps-its-tab-under-a-file ()
  "A file opened in an application's pane (the issue list's): a tab beside
the application's, which stays one; the file's tab closed (Cmd+W) or its
buffer killed: the application shown again. With Doom's frames (their
`buffer-predicate': real buffers only), not another pane's file (README,
the main pane's: the application wasn't real)."
  (dolist (close '(+my/tabs-close kill-buffer))
    (+test-tiling
      (set-frame-parameter nil 'buffer-predicate #'doom-buffer-frame-predicate)
      (unwind-protect
          (let* ((+my/tiling-known-apps (cons '(test +test-tiling-e2e-app-mode) +my/tiling-known-apps))
                 (+my/tiling-apps 'all)
                 (app (with-current-buffer (get-buffer-create "*test app*")
                        (+test-tiling-e2e-app-mode)
                        (current-buffer)))
                 (file (+test-tiling--file "t.txt")))
            (should (doom-real-buffer-p app))
            (pop-to-buffer app)
            (let ((pane (selected-window)))
              (should (equal (+test-tiling--layout) '("a.txt" "*test app*")))
              (find-file (buffer-file-name file))
              (should (eq (selected-window) pane))
              (should (equal (+test-tiling--tabs pane) '("*test app*" "t.txt")))
              (funcall close (window-buffer pane))
              (should (eq (window-buffer pane) app))
              (should (equal (+test-tiling--tabs pane) '("*test app*")))
              (should (equal (+test-tiling--layout) '("a.txt" "*test app*")))
              (kill-buffer app)))
        (set-frame-parameter nil 'buffer-predicate nil)))))

(ert-deftest e2e-tiling/a-help-link-opens-in-the-last-pane-used ()
  "A link to a file in a popup (*Help*): in the pane used last, the
application's too, as a tab."
  (+test-tiling
    (let ((left (selected-window))
          (session (+test-tiling--session)))
      (agent-shell--display-buffer session)
      (let ((pane (selected-window))
            (help (display-buffer (get-buffer-create "*test help*")
                                  '((display-buffer-in-side-window) (side . bottom)))))
        (select-window help)
        (pop-to-buffer (+test-tiling--file "e.txt"))
        (should (eq (selected-window) pane))
        (should (equal (+test-tiling--tabs pane) (list (buffer-name session) "e.txt")))
        (should (equal (+test-tiling--tabs left) '("a.txt")))))))

(ert-deftest e2e-tiling/popups-stay-popups ()
  (+test-tiling
    (let ((window (display-buffer (get-buffer-create "*test popup*")
                                  '((display-buffer-in-side-window) (side . bottom)))))
      (should (eq (window-parameter window 'window-side) 'bottom))
      (should (equal (+test-tiling--layout) '("a.txt"))))))

(ert-deftest e2e-tiling/a-pane-closes-with-its-last-tab ()
  "Cmd+W on a pane's last tab, or its last buffer killed (SPC b k): the pane
closes; with tabs left, it stays; the frame's last pane stays."
  (+test-tiling
    (let* ((left (selected-window))
           (right (+my/tiling-split))
           (b (+test-tiling--file "b.txt"))
           (c (+test-tiling--file "c.txt")))
      ;; The new pane: a.txt, then b.txt.
      (switch-to-buffer b)
      (should (equal (+test-tiling--tabs right) '("a.txt" "b.txt")))
      (+my/tabs-close-current)            ; b.txt
      (should (window-live-p right))
      (+my/tabs-close-current)            ; a.txt, its last
      (should-not (window-live-p right))
      ;; Killed.
      (select-window left)
      (let ((right (+my/tiling-split)))
        (switch-to-buffer c)
        (with-selected-window right
          (set-window-prev-buffers nil nil))
        (should (equal (+test-tiling--tabs right) '("c.txt")))
        (kill-buffer c)
        (should-not (window-live-p right)))
      ;; The last pane stays.
      (should (equal (+test-tiling--layout) '("a.txt")))
      (kill-buffer (window-buffer left))
      (should (window-live-p left)))))

;; ====== THE MINIBUFFER ======

(defun +test-tiling--in-minibuffer (thunk)
  "Call THUNK while `completing-read' waits in the minibuffer (from a timer);
leave it after; THUNK's value."
  (let (value)
    (run-at-time 0.2 nil (lambda ()
                           (unwind-protect (setq value (funcall thunk))
                             (exit-minibuffer))))
    (completing-read "Pick: " '("apple" "apricot" "banana") nil nil "ap")
    value))

(ert-deftest e2e-tiling/completions-at-the-bottom-as-ever ()
  "*Completions*, from Claude Code's pane: at the bottom, where Emacs puts it
without tiling (the same edges), the panes as they were."
  (+test-tiling
    (let ((session (+test-tiling--session)))
      (agent-shell--display-buffer session)
      (let* ((pane (selected-window))
             (where (lambda ()
                      (+test-tiling--in-minibuffer
                       (lambda ()
                         (minibuffer-completion-help)
                         (let ((window (get-buffer-window "*Completions*")))
                           (list (and window (window-at-side-p window 'bottom))
                                 (and window (window-edges window))
                                 (window-buffer pane)))))))
             (tiled (funcall where))
             (alone (let ((display-buffer-overriding-action '(nil . nil)))
                      (funcall where))))
        (should (car tiled))
        (should (equal tiled alone))
        (should (eq (nth 2 tiled) session))
        (should (eq (window-buffer pane) session))))))

(ert-deftest e2e-tiling/a-preview-from-an-application-s-pane-as-asked ()
  "A preview (consult's: the file shown, without recording it, in the window
the minibuffer was entered from, then put back): in Claude Code's pane, as
asked. Picked after, the file opens there, a tab."
  (+test-tiling
    (let* ((left (selected-window))
           (session (+test-tiling--session))
           (file (+test-tiling--file "p.txt")))
      (agent-shell--display-buffer session)
      (let* ((pane (selected-window))
             (previewed (+test-tiling--in-minibuffer
                         (lambda ()
                           (with-selected-window (minibuffer-selected-window)
                             (switch-to-buffer file t)
                             (prog1 (list (selected-window) (window-buffer))
                               (switch-to-buffer session t)))))))
        (should (equal previewed (list pane file)))
        (should (eq (window-buffer pane) session))
        (should (eq (window-buffer left) (get-buffer "a.txt")))
        ;; Picked: in its pane, a tab.
        (find-file (buffer-file-name file))
        (should (eq (selected-window) pane))
        (should (eq (window-buffer pane) file))
        (should (eq (window-buffer left) (get-buffer "a.txt")))))))

(ert-deftest e2e-tiling/a-transient-menu-at-the-bottom-as-ever ()
  "A transient menu (magit's), from Claude Code's pane: at the bottom, not a
pane; quit, the panes as they were."
  (+test-tiling
    (let ((session (+test-tiling--session)))
      (agent-shell--display-buffer session)
      (let ((panes (+my/tiling--panes)))
        (require 'magit)
        (call-interactively #'magit-dispatch)
        (let ((window (get-buffer-window " *transient*")))
          (should (window-live-p window))
          (should (window-at-side-p window 'bottom))
          (should-not (memq window (+my/tiling--panes))))
        (execute-kbd-macro (kbd "C-g"))
        (+test-sleep 0.1)
        (should-not (get-buffer-window " *transient*"))
        (should (equal (+my/tiling--panes) panes))))))

;; ====== FULLSCREEN ======

(defmacro +test-tiling-fullscreen (&rest body)
  "BODY as `+test-tiling', the strategy fullscreen; no pane hidden before or
after."
  (declare (indent 0))
  `(+test-tiling
     (set-frame-parameter nil '+my/tiling-hidden nil)
     (unwind-protect
         (let ((+my/tiling-strategy 'fullscreen))
           ,@body)
       (set-frame-parameter nil '+my/tiling-hidden nil))))

(defun +test-tiling--shown ()
  "The pane on the screen's buffer name; there must be only one."
  (let ((panes (+my/tiling--panes)))
    (should (= (length panes) 1))
    (buffer-name (window-buffer (car panes)))))

(ert-deftest e2e-tiling/fullscreen-panes-hidden-and-shown-again ()
  "Fullscreen in a GUI frame: each new pane alone, its tabs its own; in turn
with SPC w w; tall again, every pane a window, laid out tall, each its tabs."
  (+test-tiling-fullscreen
    (let ((b (+test-tiling--file "b.txt"))
          (c (+test-tiling--file "c.txt")))
      (+my/tiling-split)
      (switch-to-buffer b)
      (should (equal (+test-tiling--tabs (selected-window)) '("a.txt" "b.txt")))
      (+my/tiling-split)
      (switch-to-buffer c)
      (should (equal (+test-tiling--shown) "c.txt"))
      ;; Opened from b.txt's pane: b.txt, then c.txt.
      (should (equal (+test-tiling--tabs (selected-window)) '("b.txt" "c.txt")))
      (+my/tiling-next-pane)                ; wraps: the first
      (should (equal (+test-tiling--shown) "a.txt"))
      (+my/tiling-next-pane)
      (should (equal (+test-tiling--shown) "b.txt"))
      (should (equal (+test-tiling--tabs (selected-window)) '("a.txt" "b.txt")))
      (let ((+my/tiling-strategy 'tall))
        (+my/tiling-arrange)
        (should-not (+my/tiling--hidden-p))
        (should (equal (+test-tiling--layout) '("a.txt" "b.txt" "c.txt")))
        (should (equal (+test-tiling--tabs (nth 1 (+my/tiling--panes))) '("a.txt" "b.txt")))
        (should (equal (buffer-name (window-buffer (selected-window))) "b.txt"))))))

(ert-deftest e2e-tiling/fullscreen-file-diff-pane-reused ()
  "Fullscreen: SPC g d on a second file brings the diff's hidden pane to the
front, showing that file's diff; no pane more."
  (+test-tiling-fullscreen
    (let* ((dir (+test-tiling--dir))
           (default-directory dir)
           (files (+test-tiling--repo dir "f.txt" "g.txt")))
      (find-file (car files))
      (+my/git-diff-pane)
      (let ((diff (window-buffer)))
        (should (= (length (+my/tiling--slots)) 2))
        (+my/tiling-next-pane)
        (should (equal (+test-tiling--shown) "f.txt"))
        (find-file (cadr files))
        (+my/git-diff-pane)
        (should (= (length (+my/tiling--slots)) 2))
        (should (equal (buffer-local-value 'magit-buffer-diff-files (window-buffer)) '("g.txt")))
        (should-not (buffer-live-p diff))))))

(ert-deftest e2e-tiling/fullscreen-the-last-tab-closed-shows-the-next ()
  "Cmd+W on the last tab of the pane on the screen: the next one shown; a file
a hidden pane still has as a tab stays open."
  (+test-tiling-fullscreen
    (let ((b (+test-tiling--file "b.txt")))
      (+my/tiling-split)                    ; a.txt again, alone
      (switch-to-buffer b)
      (+my/tiling-split)
      (should (equal (+test-tiling--tabs (selected-window)) '("b.txt")))
      (+my/tabs-close-current)              ; b.txt, its only tab: the pane closes
      (should (equal (+test-tiling--shown) "b.txt"))
      (should (buffer-live-p b))            ; the pane shown has it
      (should (equal (+test-tiling--tabs (selected-window)) '("a.txt" "b.txt")))
      (+my/tabs-close-current)              ; b.txt: a tab of this pane only now
      (should-not (buffer-live-p b))
      (should (equal (+test-tiling--shown) "a.txt")))))

;; ====== BSP ======

(ert-deftest e2e-tiling/bsp-halves-by-real-pixels ()
  "bsp in a GUI frame: each pane halved along its longer side in pixels (the
frame side by side, its right half one above the other), the tree binary."
  (+test-tiling
    (let ((+my/tiling-strategy 'bsp))
      (let* ((left (selected-window))
             (right (+my/tiling-split)))
        (should (> (window-pixel-width (frame-root-window)) (window-pixel-height (frame-root-window))))
        (should (= (cadr (window-edges right)) (cadr (window-edges left))))
        (should (> (car (window-edges right)) (car (window-edges left))))
        (should (< (window-pixel-width right) (window-pixel-height right)))
        (let ((below (+my/tiling-split)))
          (should (= (car (window-edges below)) (car (window-edges right))))
          (should (> (cadr (window-edges below)) (cadr (window-edges right))))
          (should (+my/tiling--bsp-p (window-main-window))))))))
