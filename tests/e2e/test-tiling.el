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
  (dolist (package '("magit" "magit-section" "ghostel"))
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
  (+test-tiling
    (+test-tiling--doom-projects
      (call-interactively #'+ghostel/toggle)
      (let* ((terminal (window-buffer))
             (window (selected-window)))
        (should (with-current-buffer terminal (derived-mode-p 'ghostel-mode)))
        (kill-buffer terminal)
        (should-not (window-live-p window))
        (should (equal (+test-tiling--layout) '("a.txt")))))))

;; ====== CLAUDE CODE ======

(ert-deftest e2e-tiling/claude-code-in-a-new-pane-its-links-in-the-files-pane ()
  "agent-shell shows a session (SPC o c) in a new pane; shown, it's selected
there. Its links to files open them as tabs in the pane of files, not over
the session."
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
        (should (eq (selected-window) left))
        (should (eq (window-buffer left) file))
        (should (eq (window-buffer pane) session))
        (should (equal (+test-tiling--tabs left) '("a.txt" "b.txt")))
        (should (equal (+test-tiling--tabs pane) (list (buffer-name session))))))))

(ert-deftest e2e-tiling/files-found-in-an-application-s-pane-go-to-the-files ()
  "SPC SPC (find-file) in Claude Code's pane: the file in the pane of files, as
a tab, selected."
  (+test-tiling
    (let ((left (selected-window))
          (session (+test-tiling--session))
          (file (+test-tiling--file "c.txt")))
      (agent-shell--display-buffer session)
      (let ((pane (selected-window)))
        (find-file (buffer-file-name file))
        (should (eq (selected-window) left))
        (should (eq (window-buffer left) file))
        (should (eq (window-buffer pane) session))
        (should (equal (+test-tiling--tabs left) '("a.txt" "c.txt")))))))

(ert-deftest e2e-tiling/a-session-alone-files-in-a-new-pane ()
  "No pane of files (the session alone): a file opens in a new one."
  (+test-tiling
    (let ((session (+test-tiling--session))
          (file (+test-tiling--file "d.txt")))
      (switch-to-buffer session)
      (find-file (buffer-file-name file))
      (should (equal (+test-tiling--layout) (list (buffer-name session) "d.txt")))
      (should (eq (window-buffer) file)))))

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

(ert-deftest e2e-tiling/file-diff-in-a-new-pane-ret-in-the-files-pane ()
  "SPC g d: the diff in a new pane; RET on a line opens the file in the pane
of files, the diff staying; SPC g d there closes it."
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
        (let ((diff (selected-window)))
          (should-not (eq diff left))
          (should (with-current-buffer (window-buffer diff) (derived-mode-p 'magit-diff-mode)))
          (set-buffer (window-buffer diff))
          (should (= (length (+my/tiling--panes)) 2))
          ;; RET on the added line.
          (goto-char (point-min))
          (should (search-forward "+four" nil t))
          (call-interactively #'magit-diff-visit-file)
          (should (eq (selected-window) left))
          (should (eq (window-buffer left) file))
          (should (with-current-buffer (window-buffer diff) (derived-mode-p 'magit-diff-mode)))
          ;; Closed from it.
          (select-window diff)
          (+my/git-diff-pane)
          (should-not (window-live-p diff))
          (should (= (length (+my/tiling--panes)) 1)))))))

;; ====== POPUPS, TABS ======

(ert-deftest e2e-tiling/a-help-link-opens-in-the-files-pane ()
  "A link to a file in a popup (*Help*): in the pane of files, not in the
application's pane used last."
  (+test-tiling
    (let ((left (selected-window))
          (session (+test-tiling--session)))
      (agent-shell--display-buffer session)
      (let ((pane (selected-window))
            (help (display-buffer (get-buffer-create "*test help*")
                                  '((display-buffer-in-side-window) (side . bottom)))))
        (select-window help)
        (pop-to-buffer (+test-tiling--file "e.txt"))
        (should (eq (selected-window) left))
        (should (eq (window-buffer pane) session))))))

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
asked. Picked after, the file goes to the pane of files."
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
        ;; Picked: the pane of files.
        (find-file (buffer-file-name file))
        (should (eq (selected-window) left))
        (should (eq (window-buffer pane) session))))))

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
