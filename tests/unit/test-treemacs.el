;;; tests/unit/test-treemacs.el -*- lexical-binding: t; -*-
;; config/treemacs.el: the project sidebar. It
;; opens on a workspace's first project file, follows the current buffer
;; (projects' buffers only: files, dired, magit), keeps its git colours fresh
;; (on save, on revert, on focus, .git changes, a git status poll), arrows in
;; the tree (also in lsp-treemacs' lists), zR / zM expand / collapse
;; all. Real treemacs on temp projects (its git and file-watch modes off),
;; real git for the poll; workspaces are persp-mode structs.

;; ====== LOADING ======

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "treemacs"))))))
  (dolist (package '("treemacs" "persp-mode" "winum"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(setq treemacs-persist-file (+test-tmp-file "treemacs/persist")
      treemacs-last-error-persist-file (+test-tmp-file "treemacs/last-error"))

(+test-load "config/treemacs")

(defconst +test-treemacs--at-load
  (list :treemacs (featurep 'treemacs)
        :timer +my/treemacs--git-poll-timer
        :timer-active (and (memq +my/treemacs--git-poll-timer timer-list) t))
  "What loading config/treemacs.el did (before treemacs loaded).")

;; The poll runs only when the tests ask.
(when (timerp +my/treemacs--git-poll-timer)
  (cancel-timer +my/treemacs--git-poll-timer))

(defconst +test-treemacs--functions
  (let (fns)
    (mapatoms (lambda (sym)
                (when (and (fboundp sym)
                           (string-match-p "\\`\\(\\+my/\\(lsp-\\)?treemacs\\|treemacs-\\(expand\\|collapse\\)-all\\'\\)"
                                           (symbol-name sym)))
                  (push sym fns))))
    fns)
  "The functions config/treemacs.el defines.")

(require 'treemacs)
(require 'treemacs-evil)
(require 'persp-mode)
;; lsp-treemacs' panels (SPC c X, SPC c S), without lsp-mode: the config's
;; advice wraps them once they're defined.
(dolist (fn '(lsp-treemacs-errors-list lsp-treemacs-symbols))
  (unless (fboundp fn) (defalias fn #'ignore)))
(treemacs-git-mode -1)
(treemacs-filewatch-mode -1)

;; ====== HELPERS ======

(defun +test-treemacs--dir (name &rest files)
  "A new folder NAME in the temp folder with FILES (\"x/\": a folder); its
truename, as a directory name."
  (let ((dir (file-name-as-directory
              (file-truename (make-temp-file (+test-tmp-file (concat name "-")) t)))))
    (dolist (file files)
      (let ((path (expand-file-name file dir)))
        (if (directory-name-p file)
            (make-directory path t)
          (make-directory (file-name-directory path) t)
          (with-temp-file path (insert file "\n")))))
    dir))

(defun +test-treemacs--git-environment ()
  "`process-environment' for git with a temp HOME and global gitconfig (the
user's never read)."
  (let ((home (+test-tmp-file "treemacs-git-home/")))
    (append (list (concat "HOME=" home)
                  (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                  "GIT_CONFIG_NOSYSTEM=1"
                  (concat "XDG_CONFIG_HOME=" home ".config"))
            process-environment)))

(defun +test-treemacs--project (name &rest files)
  "A git project NAME with FILES; its root."
  (let ((root (apply #'+test-treemacs--dir name files)))
    (let ((default-directory root)
          (process-environment (+test-treemacs--git-environment)))
      (call-process "git" nil nil nil "init" "-q"))
    root))

(defun +test-treemacs--reload ()
  "Load config/treemacs.el again, then put its functions back as Doom loaded
them (before treemacs: loaded after, treemacs' inline functions, e.g.
`treemacs-current-visibility', get inlined, and tests can't replace them)."
  (let ((saved (mapcar (lambda (fn) (cons fn (symbol-function fn))) +test-treemacs--functions)))
    (+test-load "config/treemacs")
    (dolist (fn saved) (fset (car fn) (cdr fn)))))

(defun +test-treemacs--cleanup ()
  "No treemacs buffer, no project in its workspace."
  (dolist (buffer (buffer-list))
    (when (with-current-buffer buffer (derived-mode-p 'treemacs-mode))
      (kill-buffer buffer)))
  (ignore-errors
    (setf (treemacs-workspace->projects (treemacs-current-workspace)) nil)))

(defmacro +test-treemacs (&rest body)
  "BODY from one window on *scratch*, without treemacs; the same after."
  (declare (indent 0))
  `(+test-with-reset
     (+test-treemacs--cleanup)
     (let ((treemacs-collapse-dirs 0)
           (this-command 'test))
       (unwind-protect (progn ,@body)
         (+test-treemacs--cleanup)))))

(defun +test-treemacs--show-project (root &optional file)
  "Show FILE (default README.md) of ROOT, treemacs on ROOT; the file's
window selected again. Treemacs' buffer."
  (find-file (expand-file-name (or file "README.md") root))
  (save-selected-window
    (let ((inhibit-message t))
      (treemacs-add-and-display-current-project-exclusively)))
  (treemacs-get-local-buffer))

(defun +test-treemacs--lines ()
  "Treemacs' lines, as shown (trimmed)."
  (with-current-buffer (treemacs-get-local-buffer)
    (mapcar #'string-trim
            (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n" t))))

(defun +test-treemacs--goto (label)
  "Point (in treemacs' buffer, its window selected) on LABEL's line."
  (select-window (treemacs-get-local-window))
  (goto-char (point-min))
  (re-search-forward (concat "^ *[-+]? *" (regexp-quote label) "$"))
  (forward-line 0)
  (treemacs--evade-image))

(defun +test-treemacs--state ()
  "The state of the node at point."
  (treemacs-button-get (treemacs-current-button) :state))

(defun +test-treemacs--states ()
  "The states of all nodes in treemacs' buffer."
  (with-current-buffer (treemacs-get-local-buffer)
    (save-excursion
      (goto-char (point-min))
      (let (states)
        (while (not (eobp))
          (when-let* ((button (treemacs-current-button)))
            (push (treemacs-button-get button :state) states))
          (forward-line 1))
        (nreverse states)))))

(defun +test-treemacs--current-root ()
  "The path of treemacs' (first) project."
  (treemacs-project->path (car (treemacs-workspace->projects (treemacs-current-workspace)))))

(defmacro +test-treemacs-instead-of (fn args &rest body)
  "BODY with FN's original replaced by (lambda ARGS ...) (FN's advice from
the config still runs around it)."
  (declare (indent 2))
  `(let ((replacement (lambda ,args ,@body)))
     (advice-add ',fn :override replacement '((depth . 100)))
     replacement))

(defmacro +test-treemacs-with-original (fn args replacement-body &rest body)
  "BODY with FN's original as (lambda ARGS REPLACEMENT-BODY); the config's
advice around it kept."
  (declare (indent 3))
  `(let ((replacement (lambda ,args ,replacement-body)))
     (advice-add ',fn :override replacement '((depth . 100)))
     (unwind-protect (progn ,@body)
       (advice-remove ',fn replacement))))

(defmacro +test-treemacs-recording (fns &rest body)
  "BODY with FNS replaced by recorders: `calls' gets (FN ARGS...) in order."
  (declare (indent 1))
  `(let ((calls nil))
     (cl-letf ,(mapcar (lambda (fn)
                         `((symbol-function ',fn)
                           (lambda (&rest args) (push (cons ',fn args) calls) nil)))
                       fns)
       ,@body)
     (setq calls (nreverse calls))))

;; ====== SETTINGS ======

(ert-deftest treemacs/settings ()
  (should (eq +treemacs-git-mode 'deferred))
  (should (eq treemacs-user-mode-line-format 'none))
  (should (eql (default-value '+my/treemacs-git-poll-interval) 3))
  (should (eql (default-value '+my/treemacs-expand-all-warn) 300)))

(ert-deftest treemacs/after-treemacs-loads ()
  "Reachable with SPC w w; follows the current file and the current project."
  (should-not (plist-get +test-treemacs--at-load :treemacs))
  (should-not treemacs-is-never-other-window)
  (should treemacs-follow-mode)
  (should treemacs-project-follow-mode))

(ert-deftest treemacs/no-mode-line ()
  (+test-treemacs
    (let ((root (+test-treemacs--project "modeline" "README.md")))
      (with-current-buffer (+test-treemacs--show-project root)
        (should-not mode-line-format)))))

(ert-deftest treemacs/numbered-by-winum ()
  "Treemacs gets a window number (SPC w 1): not in winum's ignored buffers."
  (require 'winum)
  (should-not (member (regexp-quote treemacs-buffer-name-prefix) winum-ignored-buffers-regexp))
  ;; winum's other ignored buffers stay.
  (let ((winum-ignored-buffers-regexp (list "\\*foo\\*" (regexp-quote treemacs-buffer-name-prefix))))
    (+test-treemacs--reload)
    (should (equal winum-ignored-buffers-regexp '("\\*foo\\*"))))
  (when (timerp +my/treemacs--git-poll-timer) (cancel-timer +my/treemacs--git-poll-timer)))

;; ====== KEYS ======

(ert-deftest treemacs/keys ()
  (should (eq (lookup-key evil-treemacs-state-map [left]) #'+my/treemacs-left))
  (should (eq (lookup-key evil-treemacs-state-map [right]) #'+my/treemacs-right))
  (should (eq (lookup-key evil-treemacs-state-map [up]) #'treemacs-previous-line))
  (should (eq (lookup-key evil-treemacs-state-map [down]) #'treemacs-next-line))
  (should (eq (lookup-key evil-treemacs-state-map "zR") #'treemacs-expand-all))
  (should (eq (lookup-key evil-treemacs-state-map "zM") #'treemacs-collapse-all))
  (should (commandp #'+my/treemacs-left))
  (should (commandp #'+my/treemacs-right))
  (should (commandp #'treemacs-expand-all))
  (should (commandp #'treemacs-collapse-all)))

(ert-deftest treemacs/keys-in-the-sidebar ()
  "In treemacs (its evil state), the arrows are ours."
  (+test-treemacs
    (let ((root (+test-treemacs--project "keys" "README.md")))
      (with-current-buffer (+test-treemacs--show-project root)
        (should (eq evil-state 'treemacs))
        (should (eq (key-binding [left]) #'+my/treemacs-left))
        (should (eq (key-binding [right]) #'+my/treemacs-right))
        (should (eq (key-binding [up]) #'treemacs-previous-line))
        (should (eq (key-binding [down]) #'treemacs-next-line))
        (should (eq (key-binding (kbd "zR")) #'treemacs-expand-all))
        (should (eq (key-binding (kbd "zM")) #'treemacs-collapse-all))
        (should (eq (key-binding (kbd "s-c")) #'treemacs-copy-absolute-path-at-point))
        ;; h / l: treemacs' own.
        (should (eq (key-binding "h") #'treemacs-COLLAPSE-action))
        (should (eq (key-binding "l") #'treemacs-RET-action))))))

(ert-deftest treemacs/clicks ()
  "A click goes to the line (focus, selection); a double click opens."
  (should (eq (lookup-key treemacs-mode-map [down-mouse-1]) #'treemacs-leftclick-action))
  (should (eq (lookup-key treemacs-mode-map [mouse-1]) #'ignore))
  (should (eq (lookup-key treemacs-mode-map [double-mouse-1]) #'treemacs-doubleclick-action)))

(ert-deftest treemacs/copy-copies-the-path ()
  "Cmd+C on a file copies its absolute path (to the kill ring, so the
clipboard)."
  (+test-treemacs
    (let ((root (+test-treemacs--project "copy" "README.md"))
          (kill-ring nil)
          (interprogram-cut-function nil))
      (with-current-buffer (+test-treemacs--show-project root)
        (goto-char (point-min))
        (should (re-search-forward "README\\.md" nil t))
        (let ((inhibit-message t))
          (call-interactively (key-binding (kbd "s-c"))))
        (should (equal (current-kill 0) (expand-file-name "README.md" root)))))))

;; ====== HOOKS, ADVICE, TIMERS ======

(ert-deftest treemacs/hooks ()
  (dolist (fn '(+my/treemacs-follow-project-soon +my/treemacs-auto-open-h +my/treemacs-watch-git-h))
    (should (memq fn (default-value 'window-buffer-change-functions))))
  (should (memq #'+my/treemacs-follow-project-soon (default-value 'window-selection-change-functions)))
  (should (memq #'+my/treemacs-git-update-on-save-h (default-value 'after-save-hook)))
  (should (memq #'+my/treemacs-git-update-on-save-h (default-value 'after-revert-hook)))
  (should (advice-function-member-p #'+my/treemacs-focus-refresh after-focus-change-function)))

(ert-deftest treemacs/advice ()
  (should (advice-member-p #'+my/lsp-treemacs-select-panel-a 'lsp-treemacs-errors-list))
  (should (advice-member-p #'+my/lsp-treemacs-select-panel-a 'lsp-treemacs-symbols))
  (should (advice-member-p #'+my/treemacs-follow-project-buffers-a #'treemacs--do-follow-project))
  (should (advice-member-p #'+my/treemacs-stale-annotations-a #'treemacs--apply-annotations-deferred))
  (should (advice-member-p #'+my/treemacs-follow-guard-a #'treemacs--follow)))

(ert-deftest treemacs/git-poll-timer ()
  "Every 3 s (while Emacs runs), the poll."
  (let ((timer (plist-get +test-treemacs--at-load :timer)))
    (should (timerp timer))
    (should (plist-get +test-treemacs--at-load :timer-active))
    (should (eql (timer--repeat-delay timer) 3))
    (should (eq (timer--function timer) #'+my/treemacs--git-poll))
    (should-not (timer--idle-delay timer))))

(ert-deftest treemacs/git-poll-timer-reload-and-off ()
  "Loading the file again replaces the timer; an interval of nil: none."
  (unwind-protect
      (let ((+my/treemacs-git-poll-interval 3))
        (+test-treemacs--reload)
        (let ((first +my/treemacs--git-poll-timer))
          (should (memq first timer-list))
          (+test-treemacs--reload)
          (should-not (memq first timer-list))
          (should (memq +my/treemacs--git-poll-timer timer-list)))
        (let ((old +my/treemacs--git-poll-timer)
              (+my/treemacs-git-poll-interval nil))
          (+test-treemacs--reload)
          (should-not (memq old timer-list))
          (should-not +my/treemacs--git-poll-timer)))
    (when (timerp +my/treemacs--git-poll-timer)
      (cancel-timer +my/treemacs--git-poll-timer))))

;; ====== ← / → ======

(defun +test-treemacs--fake-buttons (&rest specs)
  "A buffer of treemacs-like buttons, one per line: SPECS are (LABEL . PROPS),
PROPS' :parent the index of another spec. Returns the buttons' markers."
  (let ((buffer (+test-buffer "*fake tree*"))
        markers)
    (with-current-buffer buffer
      (dolist (spec specs)
        (let ((start (point)))
          (insert (propertize (car spec) 'button '(t) 'category 'default-button) "\n")
          (push (copy-marker start) markers)))
      (setq markers (nreverse markers))
      (cl-loop for spec in specs for marker in markers
               do (let ((props (copy-sequence (cdr spec))))
                    (when-let* ((parent (plist-get props :parent)))
                      (setq props (plist-put props :parent (nth parent markers))))
                    (add-text-properties marker (+ marker (length (car spec))) props)))
      (goto-char (point-min)))
    (switch-to-buffer buffer)
    markers))

(defmacro +test-treemacs-arrow (fn line &rest specs)
  "Call FN (← / →) on LINE (0-based) of fake buttons SPECS; the treemacs
actions it ran: ((ACTION ARGS...)...)."
  `(+test-treemacs
     (let ((markers (+test-treemacs--fake-buttons ,@specs)))
       (goto-char (nth ,line markers))
       (+test-treemacs-recording (treemacs-COLLAPSE-action treemacs-TAB-action treemacs-RET-action
                                  treemacs-goto-parent-node treemacs-next-line)
         (funcall ,fn)))))

(ert-deftest treemacs/node ()
  "The node at point: (BUTTON STATE-NAME); nil on the hidden first line, or
off the buttons."
  (+test-treemacs
    (let ((markers (+test-treemacs--fake-buttons '("hidden" :state treemacs-root-open :depth -1)
                                                 '("root" :state root-node-open :depth 0)
                                                 '("no depth" :state dir-node-closed))))
      (goto-char (nth 0 markers))
      (should-not (+my/treemacs--node))
      (goto-char (nth 1 markers))
      (should (equal (cadr (+my/treemacs--node)) "root-node-open"))
      (should (= (car (+my/treemacs--node)) (nth 1 markers)))
      (goto-char (nth 2 markers))
      (should (equal (cadr (+my/treemacs--node)) "dir-node-closed"))
      (goto-char (point-max))
      (should-not (+my/treemacs--node)))
    (with-current-buffer (+test-buffer "*no buttons*" "plain text\n")
      (should-not (+my/treemacs--node)))))

(ert-deftest treemacs/leaf-p ()
  "An lsp-treemacs node without children (an error): a leaf."
  (+test-treemacs
    (let ((markers (+test-treemacs--fake-buttons
                    '("error" :item (:key "e" :label "error"))
                    '("file" :item (:key "f" :children (1 2)))
                    '("async" :item (:key "a" :children-async ignore))
                    '("path" :item "/tmp/x.kt")
                    '("nothing"))))
      (should (+my/treemacs--leaf-p (nth 0 markers)))
      (dolist (i '(1 2 3 4))
        (should-not (+my/treemacs--leaf-p (nth i markers)))))))

(ert-deftest treemacs/left-on-project-nodes-collapses ()
  "← on treemacs' own nodes (root, folders, files, tags): its collapse (which
goes to the parent of a closed one)."
  (dolist (state '(root-node-open root-node-closed dir-node-open dir-node-closed
                   file-node-open file-node-closed tag-node-open tag-node-closed tag-node))
    (should (equal (+test-treemacs-arrow #'+my/treemacs-left 0 `("node" :state ,state :depth 1))
                   '((treemacs-COLLAPSE-action))))))

(ert-deftest treemacs/left-in-lsp-lists ()
  "← in lsp-treemacs' lists: an open node closes, a closed one goes to its
parent (not up to the hidden first line)."
  (let ((hidden '("hidden" :state treemacs-root-open :depth -1)))
    ;; Open: close it.
    (should (equal (+test-treemacs-arrow #'+my/treemacs-left 1 hidden
                                         '("file" :state treemacs-file-open :depth 0 :parent 0))
                   '((treemacs-TAB-action))))
    ;; Closed, its parent shown: go there.
    (should (equal (+test-treemacs-arrow #'+my/treemacs-left 2 hidden
                                         '("file" :state treemacs-file-open :depth 0 :parent 0)
                                         '("error" :state treemacs-error-closed :depth 1 :parent 1))
                   '((treemacs-goto-parent-node))))
    ;; Closed, its parent the hidden line: stay.
    (should-not (+test-treemacs-arrow #'+my/treemacs-left 1 hidden
                                      '("file" :state treemacs-file-closed :depth 0 :parent 0)))
    ;; No parent: stay.
    (should-not (+test-treemacs-arrow #'+my/treemacs-left 0
                                      '("top" :state treemacs-file-closed :depth 0)))
    ;; A parent without a depth counts as shown.
    (should (equal (+test-treemacs-arrow #'+my/treemacs-left 1 '("parent" :state x-open)
                                         '("child" :state x-closed :depth 1 :parent 0))
                   '((treemacs-goto-parent-node))))
    ;; On the hidden line, or off the buttons: nothing.
    (should-not (+test-treemacs-arrow #'+my/treemacs-left 0 hidden))))

(ert-deftest treemacs/right ()
  "→: a closed file opens, an error (leaf) is jumped to, a closed node
expands, an open one goes to its first child; others: RET."
  (let ((cases
         `((("f" :state file-node-closed :depth 1) . treemacs-RET-action)
           (("e" :state treemacs-error-closed :depth 1 :item (:key "e")) . treemacs-RET-action)
           (("d" :state dir-node-closed :depth 1) . treemacs-TAB-action)
           (("r" :state root-node-closed :depth 0) . treemacs-TAB-action)
           (("l" :state treemacs-file-closed :depth 0 :item (:key "l" :children (1))) . treemacs-TAB-action)
           (("d" :state dir-node-open :depth 1) . treemacs-next-line)
           (("r" :state root-node-open :depth 0) . treemacs-next-line)
           (("l" :state treemacs-file-open :depth 0 :item (:key "l" :children (1))) . treemacs-next-line)
           (("f" :state file-node-open :depth 1) . treemacs-RET-action)
           (("t" :state tag-node :depth 2) . treemacs-RET-action))))
    (dolist (case cases)
      (let ((calls (+test-treemacs-arrow #'+my/treemacs-right 0 (car case))))
        (should (equal (cons (car case) (mapcar #'car calls))
                       (cons (car case) (list (cdr case)))))
        (when (eq (cdr case) 'treemacs-next-line)
          (should (equal (cdar calls) '(1))))))
    ;; The hidden first line: down to the first shown one.
    (should (equal (+test-treemacs-arrow #'+my/treemacs-right 0
                                         '("hidden" :state treemacs-root-open :depth -1))
                   '((treemacs-next-line 1))))))

(ert-deftest treemacs/arrows-in-the-project-view ()
  "In a real sidebar: → expands a folder, → again goes into it, → on a file
opens it; ← goes back to the folder, ← collapses it, ← on the root collapses
the project, → opens it again."
  (+test-treemacs
    (let ((root (+test-treemacs--project "arrows" "README.md" "docs/guide.md" "src/A.kt")))
      (+test-treemacs--show-project root)
      (+test-treemacs--goto "docs")
      (should (eq (+test-treemacs--state) 'dir-node-closed))
      (+my/treemacs-right)
      (should (eq (+test-treemacs--state) 'dir-node-open))
      (should (member "guide.md" (+test-treemacs--lines)))
      (+my/treemacs-right)
      (should (equal (treemacs-button-get (treemacs-current-button) :path)
                     (expand-file-name "docs/guide.md" root)))
      (let ((sidebar (selected-window)))
        (+my/treemacs-right)                   ; opens the file
        (should (get-file-buffer (expand-file-name "docs/guide.md" root)))
        (should (get-buffer-window (get-file-buffer (expand-file-name "docs/guide.md" root))))
        (select-window sidebar))
      (+test-treemacs--goto "guide.md")
      (+my/treemacs-left)                      ; to the folder
      (should (equal (treemacs-button-get (treemacs-current-button) :path)
                     (expand-file-name "docs" root)))
      (+my/treemacs-left)                      ; collapse it
      (should (eq (+test-treemacs--state) 'dir-node-closed))
      (should-not (member "guide.md" (+test-treemacs--lines)))
      (goto-char (point-min))
      (+my/treemacs-left)
      (should (eq (+test-treemacs--state) 'root-node-closed))
      (+my/treemacs-right)
      (should (eq (+test-treemacs--state) 'root-node-open)))))

;; ====== LSP PANELS ======

(defun +test-treemacs--lsp-panel (name)
  "Show an lsp-treemacs-like list NAME at the bottom (a side window), point
on its hidden first line, as lsp-treemacs does; its window."
  (let ((buffer (+test-buffer name)))
    (with-current-buffer buffer
      (dolist (spec '(("hidden" :state treemacs-root-open :depth -1)
                      ("A.kt" :state treemacs-file-open :depth 0)
                      ("error one" :state treemacs-error-closed :depth 1)))
        (insert (apply #'propertize (car spec) 'button '(t) 'category 'default-button (cdr spec)) "\n"))
      (goto-char (point-min)))
    (display-buffer-in-side-window buffer '((side . bottom)))))

(ert-deftest treemacs/lsp-panels-get-the-cursor ()
  "SPC c X / SPC c S: the panel selected, on its first shown line."
  (dolist (case '((lsp-treemacs-errors-list . "*LSP Error List*")
                  (lsp-treemacs-symbols . "*LSP Symbols List*")))
    (+test-treemacs
      (let* ((code (selected-window))
             (panel nil)
             (fn (car case))
             (replacement (lambda (&rest _) (setq panel (+test-treemacs--lsp-panel (cdr case))))))
        (advice-add fn :override replacement '((depth . 100)))
        (unwind-protect (funcall fn)
          (advice-remove fn replacement))
        (should (window-live-p panel))
        (should-not (eq panel code))
        (should (eq (selected-window) panel))
        (should (= (window-point panel) (point)))
        (should (equal (buffer-substring-no-properties (line-beginning-position) (line-end-position))
                       "A.kt"))))))

(ert-deftest treemacs/lsp-panel-cursor-kept ()
  "The cursor already on a shown line stays; no panel: nothing."
  (+test-treemacs
    (let ((panel (+test-treemacs--lsp-panel "*LSP Error List*")))
      (with-current-buffer (window-buffer panel)
        (goto-char (point-min))
        (forward-line 2))
      (set-window-point panel (with-current-buffer (window-buffer panel) (point)))
      (+my/lsp-treemacs-select-panel-a)
      (should (eq (selected-window) panel))
      (should (equal (buffer-substring-no-properties (line-beginning-position) (line-end-position))
                     "error one"))))
  (+test-treemacs
    (let ((window (selected-window)))
      (+my/lsp-treemacs-select-panel-a)
      (should (eq (selected-window) window)))))

;; ====== FOLLOW: RIGHT AWAY ======

(defmacro +test-treemacs-following (&rest body)
  "BODY with project follow on, `treemacs--do-follow-project' recorded in
`followed' (the buffer it ran in), the config's advice around it."
  (declare (indent 0))
  `(let ((followed nil)
         (treemacs-project-follow-mode t)
         (+my/treemacs--follow-timer nil))
     (+test-treemacs-with-original treemacs--do-follow-project () (push (current-buffer) followed)
       (unwind-protect (progn ,@body)
         (when (timerp +my/treemacs--follow-timer)
           (cancel-timer +my/treemacs--follow-timer))))))

(defun +test-treemacs--fire-follow ()
  "Run the follow timer now."
  (let ((timer +my/treemacs--follow-timer))
    (should (timerp timer))
    (cancel-timer timer)
    (apply (timer--function timer) (timer--args timer))))

(ert-deftest treemacs/follow-soon-after-a-switch ()
  "A buffer or window switch: the project follows 0.1 s later; several
switches in a row: one follow."
  (+test-treemacs
    (+test-treemacs-following
      (let ((file (find-file (+test-file "follow/a.txt" "a\n"))))
        (+my/treemacs-follow-project-soon (selected-frame))
        (let ((first +my/treemacs--follow-timer))
          (should (memq first timer-list))
          (should-not (timer--repeat-delay first))
          (should (< 0 (float-time (time-subtract (timer--time first) nil)) 0.2))
          (+my/treemacs-follow-project-soon (selected-window))
          (should-not (memq first timer-list))
          (should (memq +my/treemacs--follow-timer timer-list)))
        ;; It follows the selected window's buffer, whatever's current.
        (with-temp-buffer (+test-treemacs--fire-follow))
        (should (equal followed (list file)))
        (should-not +my/treemacs--follow-timer)))))

(ert-deftest treemacs/follow-soon-not-from-the-minibuffer ()
  "M-x and the like: treemacs stays."
  (+test-treemacs
    (+test-treemacs-following
      (find-file (+test-file "follow/b.txt" "b\n"))
      (+my/treemacs-follow-project-soon)
      (cl-letf (((symbol-function 'window-buffer)
                 (let ((real (symbol-function 'window-buffer)))
                   (lambda (&optional window)
                     (if (eq window (selected-window))
                         (window-buffer (minibuffer-window))
                       (funcall real window))))))
        (+test-treemacs--fire-follow))
      (should-not followed))))

(ert-deftest treemacs/follow-soon-only-with-project-follow ()
  (+test-treemacs
    (+test-treemacs-following
      (find-file (+test-file "follow/c.txt" "c\n"))
      (+my/treemacs-follow-project-soon)
      (let ((treemacs-project-follow-mode nil))
        (+test-treemacs--fire-follow))
      (should-not followed))))

(ert-deftest treemacs/follow-soon-errors-ignored ()
  (+test-treemacs
    (let ((treemacs-project-follow-mode t)
          (+my/treemacs--follow-timer nil))
      (find-file (+test-file "follow/d.txt" "d\n"))
      (+test-treemacs-with-original treemacs--do-follow-project () (error "Broken follow")
        (+my/treemacs-follow-project-soon)
        (+test-treemacs--fire-follow)
        (should-not +my/treemacs--follow-timer)))))

;; ====== SELECTION: SCROLL AWAY, FOLLOW ON A BUFFER CHANGE ======

(defun +test-treemacs--long-project ()
  "A project with 30 files, a.txt first: its root."
  (apply #'+test-treemacs--project "long" "README.md"
         (mapcar (lambda (i) (format "f%02d.txt" i)) (number-sequence 1 30))))

(defun +test-treemacs--sidebar ()
  (treemacs-get-local-buffer))

(defun +test-treemacs--selected ()
  "The sidebar's selected path."
  (car (buffer-local-value '+my/treemacs--selection (+test-treemacs--sidebar))))

(defun +test-treemacs--line-label (pos)
  "The label on POS's line in the sidebar."
  (with-current-buffer (+test-treemacs--sidebar)
    (save-excursion
      (goto-char pos)
      (string-trim (buffer-substring-no-properties (line-beginning-position) (line-end-position))))))

(defun +test-treemacs--highlighted ()
  "The label on the line the sidebar would highlight."
  (with-current-buffer (+test-treemacs--sidebar)
    (+test-treemacs--line-label (car (funcall hl-line-range-function)))))

(defmacro +test-treemacs-selecting (&rest body)
  "BODY with a long project in the sidebar, f01.txt open and followed (so
selected): ROOT bound."
  (declare (indent 0))
  `(+test-treemacs
     (let* ((treemacs-follow-mode t)
            (root (+test-treemacs--long-project)))
       (+test-treemacs--show-project root "f01.txt")
       (set-frame-parameter nil '+my/treemacs-followed nil)
       (+my/treemacs--follow-file (current-buffer))
       ,@body)))

(ert-deftest treemacs/no-follow-on-any-buffer-list-change ()
  "Treemacs's own trigger (any change to the buffer list: a temp buffer, the
git poll's) follows no more: it scrolled the sidebar back to the file."
  (let ((treemacs--follow-timer nil)
        (treemacs--ready-to-follow t))
    (treemacs--follow-after-buffer-list-update)
    (generate-new-buffer " *any*")
    (should-not treemacs--follow-timer)))

(ert-deftest treemacs/follow-file-once-per-buffer ()
  "The file is shown when the selected window's buffer is new since the last
time: not again for the same buffer (back from the sidebar, a popup)."
  (+test-treemacs
    (let ((treemacs-follow-mode t)
          (follows nil))
      (set-frame-parameter nil '+my/treemacs-followed nil)
      (+test-treemacs-with-original treemacs--follow () (push (current-buffer) follows)
        (let ((a (find-file-noselect (+test-file "sel/a.txt" "a\n")))
              (b (find-file-noselect (+test-file "sel/b.txt" "b\n"))))
          (+my/treemacs--follow-file a)
          (+my/treemacs--follow-file a)
          (should (equal follows (list a)))
          (+my/treemacs--follow-file b)
          (+my/treemacs--follow-file a)
          (should (equal follows (list a b a)))
          ;; Not a file: no follow, and the next file still counts as new.
          (+my/treemacs--follow-file (get-buffer-create "*scratch*"))
          (should (eq (frame-parameter nil '+my/treemacs-followed) a))
          (let ((dir (dired-noselect (+test-tmp-file "sel/"))))
            (+my/treemacs--follow-file dir)
            (should (eq (car follows) dir)))
          ;; Follow mode off: nothing followed.
          (let ((treemacs-follow-mode nil))
            (+my/treemacs--follow-file b))
          (should (= (length follows) 4)))))))

(ert-deftest treemacs/follow-soon-shows-the-file ()
  "A moment after a switch, the selected window's file is shown too."
  (+test-treemacs
    (+test-treemacs-following
      (let ((shown nil))
        (cl-letf (((symbol-function '+my/treemacs--follow-file)
                   (lambda (buffer) (push buffer shown))))
          (let ((file (find-file (+test-file "sel/c.txt" "c\n"))))
            (+my/treemacs-follow-project-soon)
            (+test-treemacs--fire-follow)
            (should (equal shown (list file)))
            ;; Also with project follow off.
            (let ((treemacs-project-follow-mode nil))
              (+my/treemacs-follow-project-soon)
              (+test-treemacs--fire-follow))
            (should (equal shown (list file file)))))))))

(ert-deftest treemacs/scroll-commands ()
  (dolist (command '(mwheel-scroll ultra-scroll ultra-scroll-mac pixel-scroll-precision
                     evil-scroll-down evil-scroll-up scroll-up-command scroll-down-command))
    (should (+my/treemacs--scroll-command-p command)))
  (dolist (command '(treemacs-next-line treemacs-previous-line evil-next-line
                     treemacs-RET-action +my/treemacs-left nil "scroll" (lambda ())))
    (should-not (+my/treemacs--scroll-command-p command))))

(ert-deftest treemacs/the-followed-file-is-selected ()
  (+test-treemacs-selecting
    (should (equal (+test-treemacs--selected) (expand-file-name "f01.txt" root)))
    (should (equal (+test-treemacs--highlighted) "f01.txt"))
    (with-current-buffer (+test-treemacs--sidebar)
      (should (eq hl-line-range-function #'+my/treemacs--highlight-range))
      (should (memq #'+my/treemacs--select-h post-command-hook))
      (should (memq #'+my/treemacs--to-selection-h pre-command-hook)))))

(ert-deftest treemacs/scrolling-keeps-the-selection ()
  "Point moved off the file (as a scroll moves it, Emacs keeping it on screen):
the file stays selected and highlighted; a scroll command doesn't change it."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (goto-char (point-max))
      (forward-line -1)
      (should-not (equal (+test-treemacs--line-label (point)) "f01.txt"))
      (should (equal (+test-treemacs--highlighted) "f01.txt"))
      (let ((this-command 'ultra-scroll))
        (+my/treemacs--select-h))
      (should (equal (+test-treemacs--selected) (expand-file-name "f01.txt" root)))
      ;; hl-line draws it there.
      (hl-line-highlight)
      (should (equal (+test-treemacs--line-label (overlay-start hl-line-overlay)) "f01.txt")))))

(ert-deftest treemacs/navigating-selects ()
  "A command that moves in the sidebar (keys, a click) selects where it went."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (let ((this-command 'treemacs-next-line)
            (last-input-event ?j))
        (+test-treemacs--goto "f04.txt")
        (+my/treemacs--to-selection-h)    ; back to f01.txt (the selection)
        (+test-treemacs--goto "f05.txt")  ; the command went to f05.txt
        (+my/treemacs--select-h))
      (should (equal (+test-treemacs--selected) (expand-file-name "f05.txt" root)))
      (should (equal (+test-treemacs--highlighted) "f05.txt"))
      ;; A click: where it clicked (its pre-command ran in another buffer).
      (+test-treemacs--goto "f09.txt")
      (let ((this-command 'treemacs-single-click-expand-action)
            (last-input-event (list 'mouse-1 (list (selected-window) (point) '(0 . 0) 0))))
        (+my/treemacs--select-h))
      (should (equal (+test-treemacs--selected) (expand-file-name "f09.txt" root))))))

(ert-deftest treemacs/a-command-that-went-nowhere-keeps-it ()
  "Emacs runs `post-command-hook' again as its command loop restarts (after
C-g, an error) with no command before: nothing's selected then. Nor by a
command that left point where it was."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (+test-treemacs--goto "f20.txt")     ; where a scroll left point
      (let ((this-command 'keyboard-quit)
            (last-input-event ?\C-g))
        (+my/treemacs--select-h))
      (should (equal (+test-treemacs--selected) (expand-file-name "f01.txt" root)))
      (let ((this-command 'treemacs-TAB-action)
            (last-input-event ?\t))
        (+my/treemacs--to-selection-h)
        (+my/treemacs--select-h))
      (should (equal (+test-treemacs--selected) (expand-file-name "f01.txt" root))))))

(ert-deftest treemacs/keys-act-on-the-selection ()
  "Scrolled away, a key's command starts from the selection; a scroll or a
click doesn't move point there."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (let ((away (progn (+test-treemacs--goto "f20.txt") (point))))
        (let ((this-command 'ultra-scroll))
          (+my/treemacs--to-selection-h))
        (should (= (point) away))
        (let ((this-command 'treemacs-RET-action)
              (last-input-event (aref (kbd "<mouse-1>") 0)))
          (cl-letf (((symbol-function 'mouse-event-p) (lambda (_) t)))
            (+my/treemacs--to-selection-h)))
        (should (= (point) away))
        (let ((this-command 'treemacs-next-line)
              (last-input-event ?j))
          (+my/treemacs--to-selection-h))
        (should (equal (+test-treemacs--line-label (point)) "f01.txt"))))))

(ert-deftest treemacs/the-selection-survives-a-redraw ()
  "The tree drawn anew (a refresh, a folder opened above): the selection is
found again by its path."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (+test-treemacs--goto "f30.txt")
      (let ((inhibit-message t))
        (treemacs--do-refresh (current-buffer) 'all))
      (should (equal (+test-treemacs--highlighted) "f01.txt"))
      ;; Its marker moved there.
      (should (equal (+test-treemacs--line-label (cdr +my/treemacs--selection)) "f01.txt")))))

(ert-deftest treemacs/no-selection-drawn-highlights-point ()
  "The selection isn't drawn (its folder closed): point's line is highlighted."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (setq +my/treemacs--selection (cons (expand-file-name "gone/x.txt" root)
                                          (copy-marker (point-min))))
      (+test-treemacs--goto "f07.txt")
      (should-not (+my/treemacs--selection-start))
      (should (equal (+test-treemacs--highlighted) "f07.txt"))
      (setq +my/treemacs--selection nil)
      (should (equal (+test-treemacs--highlighted) "f07.txt")))))

(ert-deftest treemacs/the-fringe-arrow-on-the-selection ()
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (unless treemacs--fringe-indicator-overlay
        (treemacs--enable-fringe-indicator))
      (+test-treemacs--goto "f12.txt")
      (treemacs--move-fringe-indicator-to-point)
      (should (equal (+test-treemacs--line-label (overlay-start treemacs--fringe-indicator-overlay))
                     "f01.txt"))
      ;; No selection drawn: on point, as treemacs does.
      (setq +my/treemacs--selection nil)
      (treemacs--move-fringe-indicator-to-point)
      (should (equal (+test-treemacs--line-label (overlay-start treemacs--fringe-indicator-overlay))
                     "f12.txt")))))

(ert-deftest treemacs/a-new-buffer-shows-its-file ()
  "Another file switched to: it's shown (point on it) and selected."
  (+test-treemacs-selecting
    (with-current-buffer (+test-treemacs--sidebar)
      (+test-treemacs--goto "f02.txt"))
    (select-window (get-buffer-window (get-file-buffer (expand-file-name "f01.txt" root))))
    (find-file (expand-file-name "f25.txt" root))
    (+my/treemacs--follow-file (current-buffer))
    (should (equal (+test-treemacs--selected) (expand-file-name "f25.txt" root)))
    (should (equal (+test-treemacs--line-label (window-point (treemacs-get-local-window))) "f25.txt"))))

(ert-deftest treemacs/only-the-sidebar-gets-a-selection ()
  "lsp-treemacs' lists (treemacs buffers too) keep treemacs's own highlight."
  (with-current-buffer (get-buffer-create "*LSP Test List*")
    (treemacs-mode)
    (should-not (local-variable-p 'hl-line-range-function))
    (should-not (memq #'+my/treemacs--select-h post-command-hook))
    (kill-buffer)))

;; ====== FOLLOW: PROJECT BUFFERS ONLY ======

(ert-deftest treemacs/follow-only-project-buffers ()
  "Files, dired and magit buffers switch the sidebar's project; popups and
logs don't."
  (require 'magit)
  (+test-treemacs
    (let* ((process-environment (+test-treemacs--git-environment))
           (ran 0)
           (fn (lambda () (cl-incf ran) 'followed)))
      (with-current-buffer (find-file-noselect (+test-file "follow/e.txt" "e\n"))
        (should (eq (+my/treemacs-follow-project-buffers-a fn) 'followed)))
      (with-current-buffer (dired-noselect (+test-tmp-file "follow/"))
        (+my/treemacs-follow-project-buffers-a fn))
      (with-current-buffer (+test-buffer "*magit-like*")
        (magit-status-mode)
        (+my/treemacs-follow-project-buffers-a fn))
      (should (= ran 3))
      (with-current-buffer (+test-buffer "*doom reload*" "log\n")
        (should-not (+my/treemacs-follow-project-buffers-a fn)))
      (with-current-buffer (+test-buffer "*help-like*" nil #'special-mode)
        (+my/treemacs-follow-project-buffers-a fn))
      (should (= ran 3)))))

(ert-deftest treemacs/follow-switches-projects ()
  "The real follow: another project's file switches the sidebar to it; a log
in a third project's folder doesn't; a dired buffer does."
  (+test-treemacs
    (let ((a (+test-treemacs--project "follow-a" "README.md"))
          (b (+test-treemacs--project "follow-b" "README.md" "src/B.kt"))
          (c (+test-treemacs--project "follow-c" "README.md")))
      (+test-treemacs--show-project a)
      (should (equal (file-name-as-directory (+test-treemacs--current-root)) a))
      (with-current-buffer (find-file (expand-file-name "src/B.kt" b))
        (treemacs--do-follow-project))
      (should (equal (file-name-as-directory (+test-treemacs--current-root)) b))
      (with-current-buffer (switch-to-buffer (+test-buffer "*log*" "doom/reload\n"))
        (setq default-directory c)
        (treemacs--do-follow-project))
      (should (equal (file-name-as-directory (+test-treemacs--current-root)) b))
      (with-current-buffer (switch-to-buffer (dired-noselect c))
        (treemacs--do-follow-project))
      (should (equal (file-name-as-directory (+test-treemacs--current-root)) c)))))

;; ====== RACES ======

(ert-deftest treemacs/stale-annotations-skipped ()
  "Git colours for a folder redrawn meanwhile: skipped, not an error; other
errors still are."
  (+test-treemacs-with-original treemacs--apply-annotations-deferred (&rest _)
      (signal 'wrong-type-argument '(number-or-marker-p nil))
    (should-not (treemacs--apply-annotations-deferred nil nil nil nil)))
  (+test-treemacs-with-original treemacs--apply-annotations-deferred (&rest _) (error "Other")
    (should-error (treemacs--apply-annotations-deferred nil nil nil nil)))
  (+test-treemacs-with-original treemacs--apply-annotations-deferred (&rest args) (cons 'done args)
    (should (equal (treemacs--apply-annotations-deferred 1 2 3 4) '(done 1 2 3 4)))))

(ert-deftest treemacs/follow-race-skipped ()
  "The follow looking in a tree not redrawn yet: skipped, not an error."
  (+test-treemacs-with-original treemacs--follow () (signal 'wrong-type-argument '(arrayp nil))
    (should-not (treemacs--follow)))
  (+test-treemacs-with-original treemacs--follow () (error "Other")
    (should-error (treemacs--follow)))
  (+test-treemacs-with-original treemacs--follow () 'followed
    (should (eq (treemacs--follow) 'followed))))

;; ====== GIT STATUS ON SAVE / REVERT ======

(ert-deftest treemacs/git-state-on-save-and-revert ()
  "Saving or reverting a file updates its git state, in each treemacs window."
  (+test-treemacs
    (let* ((root (+test-treemacs--project "save" "README.md" "a.txt"))
           (file (expand-file-name "a.txt" root))
           (updates nil))
      (+test-treemacs--show-project root "a.txt")
      (cl-letf (((symbol-function 'treemacs-update-single-file-git-state)
                 (lambda (f) (push (list f (derived-mode-p 'treemacs-mode)
                                         (eq (selected-window) (treemacs-get-local-window)))
                                   updates))))
        (with-current-buffer (get-file-buffer file)
          (insert "more\n")
          (save-buffer)
          (should (equal updates (list (list file 'treemacs-mode t))))
          (setq updates nil)
          (with-temp-file file (insert "changed outside\n"))
          (revert-buffer t t)
          (should (equal updates (list (list file 'treemacs-mode t)))))))))

(ert-deftest treemacs/git-state-on-save-not-without-treemacs ()
  "No treemacs window, treemacs not loaded, no file: nothing; errors in the
update don't stop saving."
  (+test-treemacs
    (let ((updates 0)
          (file (+test-file "save-none/x.txt" "x\n")))
      (cl-letf (((symbol-function 'treemacs-update-single-file-git-state)
                 (lambda (_) (cl-incf updates))))
        (with-current-buffer (find-file-noselect file)
          (insert "y")
          (save-buffer)
          (dlet ((features (remq 'treemacs features)))
            (+my/treemacs-git-update-on-save-h)))
        (with-current-buffer (+test-buffer "*no file*")
          (+my/treemacs-git-update-on-save-h))
        (should (= updates 0)))
      ;; With treemacs shown, a failing update.
      (let ((root (+test-treemacs--project "save-error" "README.md" "b.txt")))
        (+test-treemacs--show-project root "b.txt")
        (cl-letf (((symbol-function 'treemacs-update-single-file-git-state)
                   (lambda (_) (error "Git broke"))))
          (with-current-buffer (get-file-buffer (expand-file-name "b.txt" root))
            (insert "z")
            (save-buffer)
            (should-not (buffer-modified-p))))))))

;; ====== OPENS ON A WORKSPACE'S FIRST PROJECT FILE ======

(defmacro +test-treemacs-with-workspaces (&rest body)
  "BODY with workspaces on, `persp' the current one; `doom-project-root' the
git root above `default-directory'."
  (declare (indent 0))
  `(let ((persp-mode t)
         (persp (make-persp :name "one")))
     (cl-letf (((symbol-function 'get-current-persp) (lambda (&rest _) persp))
               ((symbol-function 'doom-project-root)
                (lambda (&optional dir)
                  (when-let* ((root (locate-dominating-file (or dir default-directory) ".git")))
                    (file-name-as-directory (file-truename root))))))
       ,@body)))

(ert-deftest treemacs/opens-on-the-first-project-file ()
  "The first project file shown in a workspace opens treemacs on its project;
the file keeps the cursor."
  (+test-treemacs
    (+test-treemacs-with-workspaces
      (let ((root (+test-treemacs--project "auto" "README.md")))
        (find-file (expand-file-name "README.md" root))
        (let ((window (selected-window)))
          (+my/treemacs-auto-open-h (selected-frame))
          (should (eq (treemacs-current-visibility) 'visible))
          (should (eq (selected-window) window))
          (should (equal (file-name-as-directory (+test-treemacs--current-root)) root))
          (should (persp-parameter '+my/treemacs-opened persp)))))))

(ert-deftest treemacs/closed-stays-closed-in-that-workspace ()
  "Closed (SPC o p) after: it stays closed there; another workspace opens it."
  (+test-treemacs
    (+test-treemacs-with-workspaces
      (let ((root (+test-treemacs--project "auto-closed" "README.md" "a.txt")))
        (find-file (expand-file-name "README.md" root))
        (+my/treemacs-auto-open-h)
        (delete-window (treemacs-get-local-window))
        (should (eq (treemacs-current-visibility) 'exists))
        (find-file (expand-file-name "a.txt" root))
        (+my/treemacs-auto-open-h)
        (should-not (eq (treemacs-current-visibility) 'visible))
        ;; Another workspace.
        (+test-treemacs--cleanup)
        (setq persp (make-persp :name "two"))
        (+my/treemacs-auto-open-h)
        (should (eq (treemacs-current-visibility) 'visible))))))

(ert-deftest treemacs/opens-only-for-project-files ()
  "Not for buffers without a file, files outside projects, without
workspaces; already shown: just remembered."
  (+test-treemacs
    (+test-treemacs-with-workspaces
      (let ((displays 0))
        (+test-treemacs-with-original treemacs-add-and-display-current-project-exclusively ()
            (cl-incf displays)
          (switch-to-buffer (+test-buffer "*notes*"))
          (+my/treemacs-auto-open-h)
          (find-file (+test-file "auto-none/loose.txt" "x\n"))
          (+my/treemacs-auto-open-h)
          (should-not (persp-parameter '+my/treemacs-opened persp))
          (let ((root (+test-treemacs--project "auto-only" "README.md")))
            (find-file (expand-file-name "README.md" root))
            (let ((persp-mode nil))
              (+my/treemacs-auto-open-h))
            (cl-letf (((symbol-function 'get-current-persp) #'ignore))
              (+my/treemacs-auto-open-h))
            (should (= displays 0))
            (should-not (persp-parameter '+my/treemacs-opened persp))
            ;; Shown already: remembered, not shown again.
            (cl-letf (((symbol-function 'treemacs-current-visibility) (lambda () 'visible)))
              (+my/treemacs-auto-open-h))
            (should (= displays 0))
            (should (persp-parameter '+my/treemacs-opened persp))))))))

;; ====== REFRESH: .git CHANGES, FOCUS ======

(ert-deftest treemacs/watches-each-projects-git-folder ()
  "A project file shown: its .git folder watched (once), changes schedule a
refresh. Not without .git, a file or a project."
  (+test-treemacs
    (+test-treemacs-with-workspaces
      (let ((+my/treemacs--git-watches (make-hash-table :test #'equal))
            (watches nil)
            (root (+test-treemacs--project "watch" "README.md" "a.txt")))
        (cl-letf (((symbol-function 'file-notify-add-watch)
                   (lambda (&rest args) (push args watches) (list 'descriptor (length watches)))))
          (find-file (expand-file-name "README.md" root))
          (+my/treemacs-watch-git-h)
          (find-file (expand-file-name "a.txt" root))
          (+my/treemacs-watch-git-h)
          (should (equal watches (list (list (expand-file-name ".git" root) '(change)
                                             #'+my/treemacs-schedule-refresh))))
          (should (equal (gethash (expand-file-name ".git" root) +my/treemacs--git-watches)
                         '(descriptor 1)))
          ;; No .git (another kind of project), no file, no project.
          (let ((plain (+test-treemacs--dir "watch-plain" ".projectile" "x.txt")))
            (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) plain)))
              (find-file (expand-file-name "x.txt" plain))
              (+my/treemacs-watch-git-h)))
          (switch-to-buffer (+test-buffer "*notes*"))
          (+my/treemacs-watch-git-h)
          (find-file (+test-file "watch-none/y.txt" "y\n"))
          (+my/treemacs-watch-git-h)
          (should (= (length watches) 1)))))))

(defmacro +test-treemacs-refresh-state (&rest body)
  "BODY with the refresh timer and the last refresh's time its own."
  (declare (indent 0))
  `(let ((+my/treemacs--refresh-timer nil)
         (+my/treemacs--last-refresh 0))
     (unwind-protect (progn ,@body)
       (when (timerp +my/treemacs--refresh-timer)
         (cancel-timer +my/treemacs--refresh-timer)))))

(ert-deftest treemacs/schedule-refresh ()
  "A refresh 1 s later (several: one); none within 3 s of the last one (git
status rewriting the index would loop)."
  (+test-treemacs-refresh-state
    (+my/treemacs-schedule-refresh "event")
    (let ((first +my/treemacs--refresh-timer))
      (should (memq first timer-list))
      (should (eq (timer--function first) #'+my/treemacs-refresh-all))
      (should-not (timer--repeat-delay first))
      (should (< 0.8 (float-time (time-subtract (timer--time first) nil)) 1.1))
      (+my/treemacs-schedule-refresh)
      (should-not (memq first timer-list))
      (should (memq +my/treemacs--refresh-timer timer-list)))
    ;; Right after a refresh: nothing.
    (cancel-timer +my/treemacs--refresh-timer)
    (setq +my/treemacs--refresh-timer nil
          +my/treemacs--last-refresh (- (float-time) 1))
    (+my/treemacs-schedule-refresh)
    (should-not +my/treemacs--refresh-timer)))

(ert-deftest treemacs/focus-refreshes ()
  (let ((scheduled 0))
    (cl-letf (((symbol-function '+my/treemacs-schedule-refresh) (lambda (&rest _) (cl-incf scheduled))))
      (cl-letf (((symbol-function 'frame-focus-state) (lambda (&rest _) t)))
        (+my/treemacs-focus-refresh))
      (should (= scheduled 1))
      (cl-letf (((symbol-function 'frame-focus-state) (lambda (&rest _) nil)))
        (+my/treemacs-focus-refresh))
      (should (= scheduled 1)))))

(ert-deftest treemacs/refresh-all-quietly ()
  "Every treemacs buffer refreshed (all projects), without recentering, and
without \"Refresh complete\"; files made outside show up."
  (+test-treemacs
    (+test-treemacs-refresh-state
      (let ((root (+test-treemacs--project "refresh" "README.md"))
            (calls nil))
        (+test-treemacs--show-project root)
        (let ((real (symbol-function 'treemacs--do-refresh)))
          (cl-letf (((symbol-function 'treemacs--do-refresh)
                     (lambda (buffer project)
                       (push (list buffer project treemacs-silent-refresh treemacs--no-recenter
                                   (current-buffer))
                             calls)
                       (funcall real buffer project))))
            (with-temp-file (expand-file-name "made-outside.txt" root) (insert "x\n"))
            (+test-clear-messages)
            (let ((before (float-time)))
              (+my/treemacs-refresh-all)
              (should (<= before +my/treemacs--last-refresh (float-time))))))
        (let ((buffer (treemacs-get-local-buffer)))
          (should (equal calls (list (list buffer 'all t t buffer)))))
        (should (member "made-outside.txt" (+test-treemacs--lines)))
        (should (= (+test-messages "Refresh complete") 0))))))

(ert-deftest treemacs/refresh-all-without-treemacs-or-failing ()
  (+test-treemacs-refresh-state
    (dlet ((features (remq 'treemacs features)))
      (+my/treemacs-refresh-all)
      (should (= +my/treemacs--last-refresh 0))))
  (+test-treemacs
    (+test-treemacs-refresh-state
      (let ((root (+test-treemacs--project "refresh-error" "README.md")))
        (+test-treemacs--show-project root)
        (cl-letf (((symbol-function 'treemacs--do-refresh) (lambda (&rest _) (error "Broken"))))
          (+my/treemacs-refresh-all))
        (should (> +my/treemacs--last-refresh 0))))))

;; ====== REFRESH: THE GIT STATUS POLL ======

(defmacro +test-treemacs-with-git-env (&rest body)
  "BODY with a temp HOME and global gitconfig (the user's never read)."
  (declare (indent 0))
  `(let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "treemacs-home-") t)))
          (process-environment
           (append (list (concat "HOME=" home)
                         (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                         "GIT_CONFIG_NOSYSTEM=1"
                         (concat "XDG_CONFIG_HOME=" home ".config"))
                   process-environment)))
     (with-temp-file (expand-file-name ".gitconfig" home)
       (insert "[user]\n\tname = Tester\n\temail = tester@example.invalid\n[commit]\n\tgpgsign = false\n"))
     ,@body))

(defmacro +test-treemacs-polling (&rest body)
  "BODY with the poll's state (last statuses, running checks, refresh timer)
its own."
  (declare (indent 0))
  `(let ((+my/treemacs--git-poll-state (make-hash-table :test #'equal))
         (+my/treemacs--git-poll-running (make-hash-table :test #'equal)))
     (+test-treemacs-refresh-state
       (+test-treemacs-with-git-env
         ,@body))))

(defun +test-treemacs--poll (root)
  "Check ROOT's git status; wait for the check's end."
  (+my/treemacs--git-poll-project root)
  (let ((end (+ (float-time) 10)))
    (while (and (gethash root +my/treemacs--git-poll-running) (< (float-time) end))
      (accept-process-output nil 0.02)))
  (should-not (gethash root +my/treemacs--git-poll-running)))

(defun +test-treemacs--poll-buffers ()
  (seq-filter (lambda (b) (string-prefix-p " *treemacs-git-poll*" (buffer-name b))) (buffer-list)))

(ert-deftest treemacs/poll-command ()
  "`git status' of the project, without taking git's locks (no write to .git:
no loop, no clash with a commit)."
  (+test-treemacs-polling
    (let (args)
      (cl-letf (((symbol-function 'make-process) (lambda (&rest a) (setq args a) nil)))
        (+my/treemacs--git-poll-project "/some/project/"))
      (should (equal (plist-get args :command)
                     '("git" "--no-optional-locks" "-C" "/some/project/" "status" "--porcelain" "-z")))
      (should (eq (plist-get args :noquery) t))
      (should (eq (plist-get args :connection-type) 'pipe))
      (should (functionp (plist-get args :sentinel)))
      (should (gethash "/some/project/" +my/treemacs--git-poll-running))
      (kill-buffer (plist-get args :buffer)))))

(ert-deftest treemacs/poll-refreshes-on-changes-only ()
  "The first check remembers; the same status again: nothing; a change: a
refresh 0.3 s later (the cooldown doesn't drop it)."
  (+test-treemacs-polling
    (let* ((root (+test-treemacs--project "poll" "a.txt"))
           (buffers (length (+test-treemacs--poll-buffers))))
      (+test-treemacs--poll root)
      (should (stringp (gethash root +my/treemacs--git-poll-state)))
      (should-not +my/treemacs--refresh-timer)
      (+test-treemacs--poll root)
      (should-not +my/treemacs--refresh-timer)
      (with-temp-file (expand-file-name "b.txt" root) (insert "new\n"))
      (setq +my/treemacs--last-refresh (float-time))   ; just refreshed
      (+test-treemacs--poll root)
      (let ((timer +my/treemacs--refresh-timer))
        (should (memq timer timer-list))
        (should (eq (timer--function timer) #'+my/treemacs-refresh-all))
        (should (< 0.1 (float-time (time-subtract (timer--time timer) nil)) 0.4))
        ;; Another change: that refresh replaced.
        (with-temp-file (expand-file-name "c.txt" root) (insert "new\n"))
        (+test-treemacs--poll root)
        (should-not (memq timer timer-list))
        (should (memq +my/treemacs--refresh-timer timer-list)))
      (should (string-match-p "c\\.txt" (gethash root +my/treemacs--git-poll-state)))
      ;; Its output buffers don't pile up.
      (should (= (length (+test-treemacs--poll-buffers)) buffers)))))

(ert-deftest treemacs/poll-never-writes-to-git ()
  "A file touched (git's index out of date): the check leaves .git alone."
  (+test-treemacs-polling
    (let* ((root (+test-treemacs--project "poll-index" "a.txt"))
           (default-directory root)
           (index (expand-file-name ".git/index" root)))
      (call-process "git" nil nil nil "add" ".")
      (call-process "git" nil nil nil "commit" "-qm" "a")
      (set-file-times (expand-file-name "a.txt" root) (time-add nil 100))
      (let ((before (file-attribute-modification-time (file-attributes index)))
            (bytes (with-temp-buffer (set-buffer-multibyte nil)
                                     (insert-file-contents-literally index) (buffer-string))))
        (+test-treemacs--poll root)
        (should (equal (gethash root +my/treemacs--git-poll-state) ""))   ; it ran: clean
        (should (equal (file-attribute-modification-time (file-attributes index)) before))
        (should (equal (with-temp-buffer (set-buffer-multibyte nil)
                                         (insert-file-contents-literally index) (buffer-string))
                       bytes))
        ;; A plain `git status' would have rewritten it.
        (call-process "git" nil nil nil "status" "--porcelain")
        (should-not (equal (with-temp-buffer (set-buffer-multibyte nil)
                                             (insert-file-contents-literally index) (buffer-string))
                           bytes))))))

(ert-deftest treemacs/poll-from-a-buffer-whose-folder-is-gone ()
  "The current buffer's folder deleted (outside Emacs): the check still runs
(from the project)."
  (+test-treemacs-polling
    (let ((root (+test-treemacs--project "poll-gone" "a.txt"))
          (gone (+test-treemacs--dir "poll-deleted")))
      (delete-directory gone)
      (with-temp-buffer
        (setq default-directory gone)
        (+test-treemacs--poll root))
      (should (stringp (gethash root +my/treemacs--git-poll-state))))))

(ert-deftest treemacs/poll-one-check-at-a-time ()
  (+test-treemacs-polling
    (puthash "/busy/" t +my/treemacs--git-poll-running)
    (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "Not twice"))))
      (+my/treemacs--git-poll-project "/busy/"))
    (should (gethash "/busy/" +my/treemacs--git-poll-running))))

(ert-deftest treemacs/poll-failures ()
  "Not a repo (git fails): nothing remembered, no refresh; git missing: the
check ends, its buffer killed."
  (+test-treemacs-polling
    (let ((plain (+test-treemacs--dir "poll-plain" "x.txt"))
          (buffers (length (+test-treemacs--poll-buffers))))
      (+test-treemacs--poll plain)
      (should (eq (gethash plain +my/treemacs--git-poll-state 'none) 'none))
      (should-not +my/treemacs--refresh-timer)
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest _) (signal 'file-missing '("Searching for program" "No such file" "git")))))
        (+my/treemacs--git-poll-project plain))
      (should-not (gethash plain +my/treemacs--git-poll-running))
      (should (= (length (+test-treemacs--poll-buffers)) buffers)))))

(ert-deftest treemacs/poll-the-shown-projects ()
  "While Emacs has focus and treemacs is shown: each of its projects (that
exists) checked."
  (let* ((a (+test-treemacs--dir "poll-a"))
         (b (+test-treemacs--dir "poll-b"))
         (workspace (treemacs-workspace->create!
                     :name "test"
                     :projects (list (treemacs-project->create! :name "a" :path a :path-status 'local-readable)
                                     (treemacs-project->create! :name "gone" :path "/no/such/dir/" :path-status 'local-readable)
                                     (treemacs-project->create! :name "b" :path b :path-status 'local-readable))))
         (focus t) (visibility 'visible) (polled nil))
    (cl-letf (((symbol-function 'frame-focus-state) (lambda (&rest _) focus))
              ((symbol-function 'treemacs-current-visibility) (lambda () visibility))
              ((symbol-function 'treemacs-current-workspace) (lambda () workspace))
              ((symbol-function '+my/treemacs--git-poll-project) (lambda (root) (push root polled))))
      (+my/treemacs--git-poll)
      (should (equal (nreverse polled) (list a b)))
      (setq polled nil focus nil)
      (+my/treemacs--git-poll)
      (setq focus t visibility 'exists)
      (+my/treemacs--git-poll)
      (setq visibility 'visible)
      (dlet ((features (remq 'treemacs features)))
        (+my/treemacs--git-poll))
      (should-not polled)
      (cl-letf (((symbol-function 'treemacs-current-workspace) (lambda () (error "No workspace"))))
        (+my/treemacs--git-poll))
      (should-not polled))))

;; ====== zR / zM ======

(ert-deftest treemacs/count-dirs ()
  "Folders below (not .git, not links), stopping once past the limit."
  (let ((root (+test-treemacs--dir "count" "a/b/c/" "a/d/" "e/" ".github/workflows/"
                                   ".git/objects/x/" "file.txt" "a/file.txt")))
    (make-symbolic-link (expand-file-name "a" root) (expand-file-name "link" root))
    ;; a, a/b, a/b/c, a/d, e, .github, .github/workflows.
    (should (= (+my/treemacs--count-dirs root 100) 7))
    (should (= (+my/treemacs--count-dirs (+test-treemacs--dir "count-empty") 100) 0)))
  ;; Wide: stops after the first folder past the limit.
  (let ((wide (+test-treemacs--dir "count-wide")))
    (dotimes (i 10)
      (dotimes (j 10)
        (make-directory (expand-file-name (format "d%d/e%d" i j) wide) t)))
    (should (= (+my/treemacs--count-dirs wide 1000) 110))
    (should (= (+my/treemacs--count-dirs wide 5) 10))
    (should (<= 6 (+my/treemacs--count-dirs wide 15) 30))))

(ert-deftest treemacs/expand-collapse-need-treemacs ()
  (+test-treemacs
    (should-error (treemacs-expand-all) :type 'user-error)
    (should-error (treemacs-collapse-all) :type 'user-error)))

(defun +test-treemacs--tree-project (name)
  (+test-treemacs--project name "README.md" "docs/guide.md" "src/main/kotlin/A.kt"
                           "src/test/T.kt" "build/"))

(ert-deftest treemacs/expand-all-then-collapse-all ()
  "zR: every folder open; zM: all closed again, the project open at its top
level."
  (+test-treemacs
    (let ((root (+test-treemacs--tree-project "expand")))
      (+test-treemacs--show-project root)
      (with-current-buffer (treemacs-get-local-buffer)
        (treemacs-expand-all)
        (should-not (memq 'dir-node-closed (+test-treemacs--states)))
        (should (equal (seq-filter (lambda (l) (string-match-p "\\.\\(kt\\|md\\)\\'" l)) (+test-treemacs--lines))
                       '("guide.md" "A.kt" "T.kt" "README.md")))
        (treemacs-collapse-all)
        (should-not (memq 'dir-node-open (+test-treemacs--states)))
        (should (eq (car (+test-treemacs--states)) 'root-node-open))
        (should (equal (cdr (+test-treemacs--lines)) '("+ build" "+ docs" "+ src" "README.md")))))))

(ert-deftest treemacs/expand-collapse-a-closed-project ()
  "A project folded down to its name: zR opens all of it, zM opens it at its
top level."
  (+test-treemacs
    (let ((root (+test-treemacs--tree-project "expand-closed")))
      (+test-treemacs--show-project root)
      (with-current-buffer (treemacs-get-local-buffer)
        (goto-char (point-min))
        (treemacs-toggle-node)
        (should (equal (+test-treemacs--states) '(root-node-closed)))
        (treemacs-collapse-all)
        (should (equal (+test-treemacs--states)
                       '(root-node-open dir-node-closed dir-node-closed dir-node-closed file-node-closed)))
        (goto-char (point-min))
        (treemacs-toggle-node)
        (treemacs-expand-all)
        (should (member "A.kt" (+test-treemacs--lines)))))))

(ert-deftest treemacs/expand-all-every-project ()
  (+test-treemacs
    (let ((a (+test-treemacs--tree-project "expand-a"))
          (b (+test-treemacs--tree-project "expand-b")))
      (+test-treemacs--show-project a)
      (let ((inhibit-message t))
        (treemacs-do-add-project-to-workspace (directory-file-name b) "expand-b"))
      (with-current-buffer (treemacs-get-local-buffer)
        (treemacs-expand-all)
        (should (= (seq-count (lambda (l) (equal l "A.kt")) (+test-treemacs--lines)) 2))
        (treemacs-collapse-all)
        (should (= (seq-count (lambda (s) (eq s 'root-node-open)) (+test-treemacs--states)) 2))
        (should-not (member "A.kt" (+test-treemacs--lines)))))))

(ert-deftest treemacs/expand-all-asks-above-the-limit ()
  "More folders than `+my/treemacs-expand-all-warn': asks first; no: nothing
opened."
  (+test-treemacs
    (let ((root (+test-treemacs--tree-project "expand-ask"))
          (prompts nil)
          (answer nil))
      (+test-treemacs--show-project root)
      (with-current-buffer (treemacs-get-local-buffer)
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt prompts) answer)))
          (let ((+my/treemacs-expand-all-warn 2))
            (treemacs-expand-all)
            (should (equal prompts (list (format "%s has more than 2 folders. Expand them all? "
                                                 (file-name-nondirectory (directory-file-name root))))))
            (should-not (memq 'dir-node-open (+test-treemacs--states)))
            (setq answer t)
            (treemacs-expand-all)
            (should-not (memq 'dir-node-closed (+test-treemacs--states))))
          ;; Below the limit: no question.
          (setq prompts nil)
          (treemacs-collapse-all)
          (treemacs-expand-all)
          (should-not prompts)
          (should-not (memq 'dir-node-closed (+test-treemacs--states))))))))
