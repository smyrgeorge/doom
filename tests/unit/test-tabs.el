;;; tests/unit/test-tabs.el -*- lexical-binding: t; -*-
;; config/editor/tabs.el: tabs per window (Emacs's tab line): which buffers keep tabs, labels, closing (✕, Cmd+W), Cmd+1..9,
;; gt/gT, the right-click menu (Close, Close other tabs, Split Vertically,
;; Split Horizontally), no tab line in popups and the dashboard.

(+test-load "config/editor")
(require 'tab-line)
(require 'dired)

;; ====== HELPERS ======

(defun +test-tabs--on (buffer)
  "BUFFER, its tab line on (as `global-tab-line-mode' does in Doom)."
  (with-current-buffer buffer (tab-line-mode 1))
  buffer)

(defun +test-tabs--file (name &optional content)
  "A buffer visiting NAME (in the temp folder), its tab line on."
  (+test-tabs--on (find-file-noselect (+test-file name (or content (concat name "\n"))))))

(defun +test-tabs--plain (name)
  "A buffer NAME visiting no file, its tab line on."
  (+test-tabs--on (+test-buffer name "text\n")))

(defun +test-tabs--show (&rest buffers)
  "Show BUFFERS in the selected window, one after the other."
  (dolist (buffer buffers)
    (switch-to-buffer (+test-tabs--on buffer))))

(defun +test-tabs--only (window buffer)
  "Show BUFFER in WINDOW (a new split) as its only tab."
  (set-window-buffer window (+test-tabs--on buffer))
  (set-window-prev-buffers window nil)
  (set-window-next-buffers window nil)
  (set-window-parameter window 'tab-line-buffers nil))

(defun +test-tabs--tabs (&optional window)
  "WINDOW's tabs (default: the selected one)."
  (with-selected-window (or window (selected-window))
    (+my/tabs-window-buffers)))

(defun +test-tabs--event (window tab &optional type)
  "A mouse event (TYPE, default down-mouse-3) on TAB in WINDOW's tab line."
  (let ((string (with-selected-window window
                  (+my/tabs-format tab (+my/tabs-window-buffers)))))
    (list (or type 'down-mouse-3)
          (list window 'tab-line '(0 . 0) 0 (cons string 1)
                nil '(0 . 0) nil '(0 . 0) '(0 . 0)))))

(defun +test-tabs--event-off-a-tab (window)
  "A right click in WINDOW's tab line, not on a tab."
  (list 'down-mouse-3 (list window 'tab-line '(0 . 0) 0 nil nil '(0 . 0) nil '(0 . 0) '(0 . 0))))

(defmacro +test-tabs (&rest body)
  "BODY from one window on *scratch*, as a command would run, with Doom's frame
buffer predicate (only real buffers are switched to)."
  (declare (indent 0))
  `(+test-with-reset
     (let ((predicate (frame-parameter nil 'buffer-predicate))
           (this-command 'test))
       (set-frame-parameter nil 'buffer-predicate #'doom-buffer-frame-predicate)
       (unwind-protect (progn ,@body)
         (set-frame-parameter nil 'buffer-predicate predicate)))))

(defvar +test-tabs--workspace-calls nil)

(defmacro +test-tabs--with-workspaces (&rest body)
  "BODY with Doom's workspace commands (`+workspace/switch-to-N', -final)
defined, recording their calls in `+test-tabs--workspace-calls'."
  (declare (indent 0))
  `(let ((commands (cons '+workspace/switch-to-final
                         (cl-loop for i from 0 to 8
                                  collect (intern (format "+workspace/switch-to-%d" i)))))
         (+test-tabs--workspace-calls nil))
     (dolist (command commands)
       (let ((command command))
         (defalias command (lambda () (interactive)
                             (push command +test-tabs--workspace-calls)))))
     (unwind-protect (progn ,@body)
       (mapc #'fmakunbound commands))))

;; Stand in for agent-shell's mode (a Claude session; shell-maker derives it
;; from comint's, so Doom counts its buffers as real) and one derived from it.
(unless (fboundp 'agent-shell-mode)
  (put 'agent-shell-mode 'derived-mode-parent 'comint-mode))
(put '+test-tabs--claude-mode 'derived-mode-parent 'agent-shell-mode)
;; Stands in for a magit mode: Doom's magit module counts these as real.
(put '+test-tabs--magit-status-mode 'derived-mode-parent 'magit-mode)

(defun +test-tabs--magit-p (buffer)
  "Doom's `+magit-buffer-p'."
  (provided-mode-derived-p (buffer-local-value 'major-mode buffer) 'magit-mode))

;; ====== SETTINGS ======

(ert-deftest tabs/settings-defaults ()
  (should (= (default-value '+my/tabs-height) 22))
  (should (= (default-value '+my/tabs-bar-width) 2)))

(ert-deftest tabs/tab-line-settings ()
  "Once tab-line loads: our tabs, labels and closing; ✕ shown, no + button,
gt/gT wrap around."
  (should (eq tab-line-tabs-function #'+my/tabs-window-buffers))
  (should (eq tab-line-tab-name-format-function #'+my/tabs-format))
  (should (eq tab-line-close-tab-function #'+my/tabs-close))
  (should (eq tab-line-close-button-show t))
  (should-not tab-line-new-button-show)
  (should (eq tab-line-switch-cycling t)))

(ert-deftest tabs/no-tab-line-in-treemacs-or-the-dashboard ()
  (should (memq 'treemacs-mode tab-line-exclude-modes))
  (should (memq '+doom-dashboard-mode tab-line-exclude-modes))
  (+test-tabs
    (dolist (mode '(treemacs-mode +doom-dashboard-mode))
      (with-current-buffer (+test-buffer (format "*%s*" mode))
        (setq major-mode mode)
        (tab-line-mode--turn-on)
        (should-not tab-line-mode)))
    ;; Other buffers do get it.
    (with-current-buffer (+test-buffer "plain")
      (tab-line-mode--turn-on)
      (should tab-line-mode))))

(ert-deftest tabs/tab-line-on-with-the-first-buffer ()
  (should (memq 'global-tab-line-mode doom-first-buffer-hook))
  (unwind-protect
      (progn (run-hooks 'doom-first-buffer-hook)
             (should global-tab-line-mode))
    (global-tab-line-mode -1)))

;; ====== WHICH BUFFERS KEEP TABS ======

(ert-deftest tabs/files-keep-tabs ()
  (+test-tabs
    (should (+my/tabs-p (+test-tabs--file "a.txt")))))

(ert-deftest tabs/dired-keeps-tabs ()
  (+test-tabs
    (should (+my/tabs-p (dired-noselect +test-tmp)))))

(ert-deftest tabs/claude-sessions-keep-tabs ()
  (+test-tabs
    (let ((session (+test-buffer "*claude*"))
          (derived (+test-buffer "*claude 2*")))
      (with-current-buffer session (setq major-mode 'agent-shell-mode))
      (with-current-buffer derived (setq major-mode '+test-tabs--claude-mode))
      (should (+my/tabs-p session))
      (should (+my/tabs-p derived)))))

(ert-deftest tabs/magit-keeps-tabs ()
  "Magit buffers are real in Doom (its magit module says so), so keep tabs."
  (+test-tabs
    (let ((doom-real-buffer-functions (list #'+test-tabs--magit-p))
          (magit (+test-buffer "magit: project")))
      (with-current-buffer magit (setq major-mode '+test-tabs--magit-status-mode))
      (should (+my/tabs-p magit)))))

(ert-deftest tabs/other-buffers-dont-keep-tabs ()
  (+test-tabs
    (dolist (name '("*Help*" "*Messages*" "notes" " hidden"))
      (should-not (+my/tabs-p (get-buffer-create name))))
    ;; A buffer marked real (Doom's `doom-real-buffer-p') does.
    (with-current-buffer (+test-buffer "*real*")
      (setq-local doom-real-buffer-p t)
      (should (+my/tabs-p (current-buffer))))))

(ert-deftest tabs/a-new-buffer-keeps-its-tab ()
  "SPC b N's *new* (`evil-buffer-new'): Doom calls a buffer named *... without
a file unreal; this one is real, through a change of mode too: its tab kept
when another is shown, shown again when that one closes. A file it opens:
not marked."
  (+test-tabs
    (require 'evil)
    (should (memq #'+my/tabs-new-buffer-real-p doom-real-buffer-functions))
    (should-not (doom-real-buffer-p (+test-tabs--plain "*new-ish*")))
    (let ((a (+test-tabs--file "a.txt")))
      (+test-tabs--show a)
      (evil-buffer-new nil)
      (let ((new (+test-tabs--on (window-buffer))))
        (should (string-prefix-p "*new*" (buffer-name new)))
        (should (doom-real-buffer-p new))
        (with-current-buffer new
          (insert "Some notes")
          (text-mode))
        (should (doom-real-buffer-p new))
        (should (+my/tabs-p new))
        (+test-tabs--show a)
        (should (memq new (+test-tabs--tabs)))
        (should (memq a (+test-tabs--tabs)))
        (+my/tabs-close a)
        (should (eq (window-buffer) new))))
    (evil-buffer-new (+test-file "b.txt" "b\n"))
    (should-not (buffer-local-value '+my/tabs--new-buffer (window-buffer)))))

(ert-deftest tabs/the-buffer-list-keeps-its-tab ()
  "SPC b i's *Ibuffer*: Doom calls a buffer named *... without a file unreal,
so its tab went once another tab was clicked, and Doom's workspaces (which
add only real buffers) left it out. A mode of `+my/tabs-real-modes', it's
real: its tab kept, shown again by its tab; q closes it (killed)."
  (+test-tabs
    (require 'ibuffer)
    (let ((a (+test-tabs--file "a.txt")))
      ;; The tabs looked at after each step, as the tab line is drawn: their
      ;; order is fixed then.
      (+test-tabs--show a)
      (should (equal (+test-tabs--tabs) (list a)))
      (ibuffer)
      (let ((list (+test-tabs--on (window-buffer))))
        (should (eq (buffer-local-value 'major-mode list) 'ibuffer-mode))
        (should (equal (+test-tabs--tabs) (list a list)))
        (+test-tabs--show a)
        (should (equal (+test-tabs--tabs) (list a list)))
        (should (doom-real-buffer-p list))
        (should-not (doom-unreal-buffer-p list)) ; what Doom's workspaces add
        (+test-tabs--show list)
        (should (equal (+test-tabs--tabs) (list a list)))
        (quit-window)
        (should (eq (window-buffer) a))
        (should (equal (+test-tabs--tabs) (list a)))
        (should-not (buffer-live-p list))))
    (should (memq #'+my/tabs-real-mode-p doom-real-buffer-functions))
    ;; Another mode: still unreal, its tab only while shown.
    (should-not (doom-real-buffer-p (+test-tabs--plain "*Ibuffer-ish*")))))

(ert-deftest tabs/the-buffer-list-closes-with-its-tab ()
  "The buffer list (a mode of `+my/tabs-real-modes') is closed as a file is:
killed once no window has it as a tab, by its ✕, a middle click or q; kept
while another window still has it. Other buffers aren't."
  (+test-tabs
    (require 'ibuffer)
    (let ((a (+test-tabs--file "a.txt"))
          (help (+test-tabs--plain "*Help*")))
      (+test-tabs--show a)
      ;; Its ✕ (it not shown), then a middle click (it shown).
      (dolist (click '(mouse-1 mouse-2))
        (ibuffer)
        (let ((list (+test-tabs--on (window-buffer))))
          (should (equal (+test-tabs--tabs) (list a list)))
          (when (eq click 'mouse-1) (+test-tabs--show a))
          (tab-line-close-tab (+test-tabs--event (selected-window) list click))
          (should (eq (window-buffer) a))
          (should (equal (+test-tabs--tabs) (list a)))
          (should-not (buffer-live-p list))))
      ;; Another window has it as a tab too: q here keeps it; its tab closed
      ;; there (the window's last), it goes.
      (ibuffer)
      (let ((list (+test-tabs--on (window-buffer)))
            (other (split-window nil nil 'right)))
        (+test-tabs--only other list)
        (quit-window)
        (should (eq (window-buffer) a))
        (should (buffer-live-p list))
        (with-selected-window other (+my/tabs-close list))
        (should-not (window-live-p other))
        (should-not (buffer-live-p list)))
      ;; Any other buffer: q and its tab closed only take it off the tabs.
      (+test-tabs--show help)
      (quit-window)
      (should (buffer-live-p help))
      (+test-tabs--show help a)
      (+my/tabs-close help)
      (should (buffer-live-p help)))))

(ert-deftest tabs/magit-s-q-keeps-a-window-with-other-tabs ()
  "Magit's q (Doom's: `magit-mode-quit-window') in a window magit made: a file
opened there (a tab), the window kept, showing it, no file left in no tab;
no other tab, the window closed as magit has it."
  (should (advice-member-p #'+my/tabs-magit-quit-a 'magit-mode-quit-window))
  (+test-tabs
    (require 'magit)
    (let* ((doom-real-buffer-functions (list #'+test-tabs--magit-p))
           (a (+test-tabs--file "a.txt"))
           (b (+test-tabs--file "b.txt"))
           (status (with-current-buffer (get-buffer-create "magit: test")
                     (magit-status-mode)
                     (+test-tabs--on (current-buffer)))))
      (+test-tabs--show a)
      (dolist (other (list b nil))
        (let ((main (selected-window))
              (window (display-buffer status '(display-buffer-pop-up-window))))
          ;; As magit's display does: the window made for it, its only tab.
          (+test-tabs--only window status)
          (set-window-parameter window 'magit-dedicated t)
          (select-window window)
          (when other
            (switch-to-buffer other)
            (switch-to-buffer status)
            (should (seq-set-equal-p (+test-tabs--tabs) (list status other))))
          (magit-mode-quit-window nil)
          (if other
              (progn (should (window-live-p window))
                     (should (eq (window-buffer window) b))
                     ;; Magit quit there (buried: off its tabs).
                     (should (equal (+test-tabs--tabs window) (list b)))
                     (select-window main)
                     (delete-other-windows))
            (should-not (window-live-p window))
            (should (eq (selected-window) main)))
          (should (buffer-live-p status)))))))

(ert-deftest tabs/tabs-in-the-order-first-shown ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (should (equal (+test-tabs--tabs) (list a b c)))
      ;; Showing one again doesn't move it.
      (+test-tabs--show a)
      (should (equal (+test-tabs--tabs) (list a b c)))
      (+test-tabs--show b)
      (should (equal (+test-tabs--tabs) (list a b c))))))

(ert-deftest tabs/other-buffers-only-while-shown ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (help (+test-tabs--plain "*Help*"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a help b)
      (should (equal (+test-tabs--tabs) (list a b)))
      (+test-tabs--show help)
      (should (memq help (+test-tabs--tabs)))
      (should (memq a (+test-tabs--tabs)))
      (should (memq b (+test-tabs--tabs)))
      (+test-tabs--show a)
      (should (equal (+test-tabs--tabs) (list a b))))))

(ert-deftest tabs/the-shown-buffer-is-always-a-tab ()
  (+test-tabs
    (let ((notes (+test-tabs--plain "notes")))
      (+test-tabs--show notes)
      (should (equal (+test-tabs--tabs) (list notes))))))

(ert-deftest tabs/killed-buffers-leave-the-tabs ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (kill-buffer b)
      (should (equal (+test-tabs--tabs) (list a c))))))

(defvar persp-mode)                     ; Doom's workspaces (persp-mode)

(defmacro +test-tabs--in-workspace (buffers &rest body)
  "BODY with Doom's workspaces on, the current one's buffers BUFFERS (a form)."
  (declare (indent 1))
  `(let ((persp-mode t)
         (in ,buffers))
     (cl-letf (((symbol-function 'persp-contain-buffer-p)
                (lambda (&optional buffer &rest _) (memq (get-buffer buffer) in))))
       ,@body)))

(ert-deftest tabs/the-current-workspace-s-tabs-only ()
  "SPC p p made a workspace in the window the last one showed: its README
there, the other workspace's in the window's history. Its tabs: this
workspace's buffers (and the one shown); without workspaces, all."
  (+test-tabs
    (let ((theirs (+test-tabs--file "pas/README.md"))
          (ours (+test-tabs--file "rskit/README.md"))
          (notes (+test-tabs--file "rskit/notes.md")))
      (+test-tabs--show theirs notes ours)
      (+test-tabs--in-workspace (list ours notes)
        (should (equal (+test-tabs--tabs) (list notes ours))))
      ;; The shown one, even if not the workspace's (yet).
      (+test-tabs--in-workspace (list notes)
        (should (equal (+test-tabs--tabs) (list notes ours))))
      (should (equal (+test-tabs--tabs) (list theirs notes ours))))))

(ert-deftest tabs/the-workspace-s-last-tab-closes-the-pane ()
  "Its only tab in this workspace closed: the window's last, whatever other
workspaces' buffers its history has."
  (+test-tabs
    (let* ((theirs (+test-tabs--file "pas/README.md"))
           (ours (+test-tabs--file "rskit/README.md"))
           (left (selected-window))
           (right (split-window-right)))
      (select-window right)
      (+test-tabs--show theirs ours)
      (+test-tabs--in-workspace (list ours)
        (should (equal (+test-tabs--tabs) (list ours)))
        (+my/tabs-close-current))
      (should-not (window-live-p right))
      (should (window-live-p left)))))

(ert-deftest tabs/each-window-has-its-own-tabs ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b)
      (let ((other (split-window nil nil 'right)))
        (+test-tabs--only other c)
        (should (equal (+test-tabs--tabs) (list a b)))
        (should (equal (+test-tabs--tabs other) (list c)))))))

;; ====== LABELS ======

(ert-deftest tabs/unique-label ()
  (should (equal (+my/tabs-unique-label "/w/crate-a/src/lib.rs" '("/w/crate-b/src/lib.rs"))
                 "crate-a/src/lib.rs"))
  (should (equal (+my/tabs-unique-label "/w/a/lib.rs" '("/w/b/lib.rs")) "a/lib.rs"))
  ;; Enough parts to differ from every other one.
  (should (equal (+my/tabs-unique-label "/w/x/a/lib.rs" '("/w/y/a/lib.rs" "/w/b/lib.rs"))
                 "x/a/lib.rs"))
  ;; No others: the file name.
  (should (equal (+my/tabs-unique-label "/w/a/lib.rs" nil) "lib.rs"))
  ;; A path that's the end of another one: as much as there is.
  (should (equal (+my/tabs-unique-label "/b/lib.rs" '("/a/b/lib.rs")) "b/lib.rs"))
  (should (equal (+my/tabs-unique-label "/a/b/lib.rs" '("/b/lib.rs")) "a/b/lib.rs"))
  ;; Under home: ~ abbreviated.
  (should (equal (+my/tabs-unique-label (expand-file-name "~/p/a/lib.rs")
                                        (list (expand-file-name "~/p/a/lib.rs")))
                 "~/p/a/lib.rs")))

(ert-deftest tabs/label-is-the-file-name ()
  "Workspaces turn uniquify off: buffers lib.rs<2>... The label is the file's name."
  (+test-tabs
    (let ((a (+test-tabs--file "one/x.txt"))
          (b (+test-tabs--file "two/y.txt")))
      (with-current-buffer a (rename-buffer "x.txt<2>"))
      (should (equal (+my/tabs-label a (list a b)) "x.txt"))
      (should (equal (+my/tabs-label b (list a b)) "y.txt")))))

(ert-deftest tabs/same-named-files-get-the-shortest-distinguishing-path ()
  (+test-tabs
    (let ((a (+test-tabs--file "crate-a/src/lib.rs"))
          (b (+test-tabs--file "crate-b/src/lib.rs"))
          (c (+test-tabs--file "main.rs"))
          (notes (+test-tabs--plain "lib.rs")))
      (should (equal (+my/tabs-label a (list a b c notes)) "crate-a/src/lib.rs"))
      (should (equal (+my/tabs-label b (list a b c notes)) "crate-b/src/lib.rs"))
      (should (equal (+my/tabs-label c (list a b c notes)) "main.rs"))
      ;; Only among the tabs given: alone, the file name.
      (should (equal (+my/tabs-label a (list a c)) "lib.rs")))))

(ert-deftest tabs/label-of-other-buffers-is-their-name ()
  (+test-tabs
    (let ((help (+test-tabs--plain "*Help*")))
      (should (equal (+my/tabs-label help (list help)) "*Help*")))))

;; ====== HOW TABS LOOK ======

(ert-deftest tabs/format-text-and-properties ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let* ((tabs (+test-tabs--tabs))
             (current (+my/tabs-format b tabs))
             (other (+my/tabs-format a tabs))
             (close (substring-no-properties tab-line-close-button)))
        (should (equal (substring-no-properties current) (concat " b.txt " close " ")))
        (should (equal (substring-no-properties other) (concat " a.txt " close " ")))
        ;; The whole tab: its buffer, selected or not, highlighted under the mouse.
        (dotimes (i (length current))
          (should (eq (get-text-property i 'tab current) b))
          (should (eq (get-text-property i 'selected current) t))
          (should (eq (get-text-property i 'mouse-face current) 'tab-line-highlight)))
        (should (eq (get-text-property 1 'tab other) a))
        (should-not (get-text-property 1 'selected other))
        ;; The name: clicks select the tab (or open its menu).
        (should (eq (get-text-property 1 'keymap current) tab-line-tab-map))
        (should (equal (get-text-property 1 'help-echo current) "Current tab"))
        (should (equal (get-text-property 1 'help-echo other) "Click to select tab"))
        (should (eq (get-text-property 1 'follow-link current) 'ignore))
        ;; The ✕ keeps its own keys (closing).
        (let ((at (length " b.txt ")))
          (should (equal (get-text-property at 'keymap current)
                         (get-text-property 0 'keymap tab-line-close-button))))))))

(ert-deftest tabs/format-faces ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let ((face-at (lambda (string pos)
                       (let ((face (get-text-property pos 'face string)))
                         (if (listp face) (car (last face)) face)))))
        ;; The current tab, in the selected window.
        (cl-letf (((symbol-function 'mode-line-window-selected-p) (lambda () t)))
          (let ((tab (+my/tabs-format b (+test-tabs--tabs))))
            (should (eq (funcall face-at tab 1) 'tab-line-tab-current))
            ;; The ✕ and the space after it too.
            (should (memq 'tab-line-tab-current
                          (ensure-list (get-text-property (length " b.txt ") 'face tab))))
            (should (eq (funcall face-at tab (1- (length tab))) 'tab-line-tab-current))))
        ;; The current tab, in another window.
        (cl-letf (((symbol-function 'mode-line-window-selected-p) (lambda () nil)))
          (should (eq (funcall face-at (+my/tabs-format b (+test-tabs--tabs)) 1) 'tab-line-tab)))
        ;; The others.
        (should (eq (funcall face-at (+my/tabs-format a (+test-tabs--tabs)) 1)
                    'tab-line-tab-inactive))))))

(ert-deftest tabs/format-dot-when-unsaved ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (notes (+test-tabs--plain "notes")))
      (+test-tabs--show notes a)
      (should-not (string-search "•" (+my/tabs-format a (+test-tabs--tabs))))
      (with-current-buffer a (insert "change"))
      (should (string-prefix-p " a.txt • " (+my/tabs-format a (+test-tabs--tabs))))
      ;; Only files: a buffer without one isn't "unsaved".
      (with-current-buffer notes (insert "change"))
      (should (buffer-modified-p notes))
      (should-not (string-search "•" (+my/tabs-format notes (+test-tabs--tabs)))))))

;; Text a tab starts with, from `+my/tabs-prefix-functions' (an agent's avatar on
;; its worktree's files: config/agent-workspace.el).
(ert-deftest tabs/format-prefix-from-its-functions ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (+my/tabs-prefix-functions
           (list #'ignore (lambda (buffer) (and (string-match-p "a\\.txt" (buffer-name buffer)) "▌A "))
                 (lambda (_) "second "))))
      (+test-tabs--show a b)
      (should (string-prefix-p " ▌A a.txt " (substring-no-properties (+my/tabs-format a (+test-tabs--tabs)))))
      (should (string-prefix-p " second b.txt " (substring-no-properties (+my/tabs-format b (+test-tabs--tabs)))))
      (let ((+my/tabs-prefix-functions nil))
        (should (string-prefix-p " a.txt " (substring-no-properties (+my/tabs-format a (+test-tabs--tabs)))))))))

(defun +test-tabs--tab-line ()
  "The selected window's tab line, as text (tab-line's cache used)."
  (mapconcat #'substring-no-properties
             (seq-filter #'stringp (flatten-tree (tab-line-format)))
             ""))

(ert-deftest tabs/dot-follows-other-tabs-saved-or-changed ()
  "The tab line is drawn again when a tab other than the current one is saved
(save all, magit saving the repository's files) or changed elsewhere."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show b)
      (with-current-buffer b (insert "change"))
      (+test-tabs--show a)
      (should (string-search "b.txt •" (+test-tabs--tab-line)))
      (with-current-buffer b (save-buffer))
      (should-not (string-search "•" (+test-tabs--tab-line)))
      (with-current-buffer b (insert "again"))
      (should (string-search "b.txt •" (+test-tabs--tab-line)))
      ;; The current tab, as tab-line did.
      (with-current-buffer b (save-buffer))
      (with-current-buffer a (insert "change"))
      (should (string-search "a.txt •" (+test-tabs--tab-line)))
      (should-not (string-search "b.txt •" (+test-tabs--tab-line))))))

(ert-deftest tabs/cache-key ()
  (should (eq tab-line-cache-key-function #'+my/tabs-cache-key))
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (notes (+test-tabs--plain "notes")))
      (+test-tabs--show notes a)
      (with-current-buffer notes (insert "change"))
      (let* ((own (tab-line-cache-key-default (list notes a)))
             (key (+my/tabs-cache-key (list notes a))))
        ;; tab-line's own key kept, first: it reads its scroll (3rd) and the
        ;; buffer's name (2nd) by place.
        (should (equal (seq-take key (length own)) own))
        (should (eq (nth 2 key) (window-parameter nil 'tab-line-hscroll)))
        ;; Unsaved files only.
        (should (equal (nth (length own) key) '(nil nil)))
        ;; The width the tabs are laid out for.
        (should (equal (car (last key)) (window-body-width nil t))))
      (with-current-buffer a (insert "change"))
      (should (equal (car (last (+my/tabs-cache-key (list notes a)) 2)) '(nil t)))
      ;; Tabs of tab-line's other form (alists): no error.
      (should (equal (car (last (+my/tabs-cache-key (list `((name . "a") (buffer . ,a)))) 2))
                     '(nil))))))

(defun +test-tabs--shown ()
  "The selected window's tab line as tab-line lays it out (its cache used):
the tabs it shows, as buffer names, and its width in columns."
  (let ((parts (seq-filter #'stringp (flatten-tree (tab-line-format)))))
    (list (delete-dups (delq nil (mapcar (lambda (part)
                                           (when-let* ((tab (tab-line--get-tab-property 'tab part)))
                                             (buffer-name tab)))
                                         parts)))
          (string-width (apply #'concat parts)))))

(ert-deftest tabs/a-resized-window-lays-out-its-tabs-again ()
  "Shrunk, the current tab still shown whole, no tab switch needed; widened
again, all the tabs that fit shown (not only those from where it scrolled
to); a scroll of your own (an integer) kept."
  (+test-tabs
    (let ((files (mapcar (lambda (i) (+test-tabs--file (format "file%02d.txt" i))) (number-sequence 1 12)))
          (window (selected-window)))
      (apply #'+test-tabs--show files)
      (pcase-let ((`(,wide ,_) (+test-tabs--shown)))
        (should (equal (car (last wide)) "file12.txt"))
        (should (< (length wide) 12))
        ;; Shrunk: the current tab whole, within the window.
        (split-window-right 30)
        (should (= (window-total-width window) 30))
        (pcase-let ((`(,narrow ,width) (+test-tabs--shown)))
          (should (equal (car (last narrow)) "file12.txt"))
          (should (< (length narrow) (length wide)))
          (should (<= width (window-body-width window))))
        ;; Widened: as many as before.
        (delete-other-windows)
        (should (equal (car (+test-tabs--shown)) wide))
        ;; A scroll of your own (the tab line's arrows) stays.
        (set-window-parameter nil 'tab-line-hscroll 2)
        (let ((mine (car (+test-tabs--shown))))
          (should (equal (car mine) "file03.txt"))
          (split-window-right 30)
          (should (eql (window-parameter window 'tab-line-hscroll) 2))
          (should (equal (car (car (+test-tabs--shown))) "file03.txt")))))))

(ert-deftest tabs/a-new-theme-draws-every-window-s-tabs-again ()
  "The bars are images in the theme's colours, kept in tab-line's cache: a
theme loaded drops every window's cache."
  (should (memq #'+my/tabs-theme-h (default-value 'doom-load-theme-hook)))
  (+test-tabs
    (let* ((left (selected-window))
           (right (split-window-right)))
      (set-window-parameter left 'tab-line-cache '(key . "old bars"))
      (set-window-parameter right 'tab-line-cache '(key . "old bars"))
      (run-hooks 'doom-load-theme-hook)
      (should-not (window-parameter left 'tab-line-cache))
      (should-not (window-parameter right 'tab-line-cache)))))

(ert-deftest tabs/format-leaves-the-close-button-alone ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (before (copy-sequence tab-line-close-button)))
      (+test-tabs--show a)
      (+my/tabs-format a (+test-tabs--tabs))
      (should (equal-including-properties tab-line-close-button before)))))

(ert-deftest tabs/format-terminal-no-icon-no-bar ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (called nil))
      (+test-tabs--show a)
      (cl-letf (((symbol-function 'nerd-icons-icon-for-buffer)
                 (lambda () (setq called t) "ICON")))
        (let ((tab (+my/tabs-format a (+test-tabs--tabs))))
          (should-not called)
          (should (string-prefix-p " a.txt " tab))
          (should-not (text-property-not-all 0 (length tab) 'display nil tab)))))))

(ert-deftest tabs/format-gui-icon-and-bar ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (bars nil))
      (+test-tabs--show a b)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                ((symbol-function 'nerd-icons-icon-for-buffer)
                 (lambda () (propertize (if (eq (current-buffer) a) "A" "B") 'face 'error)))
                ((symbol-function 'face-background)
                 (lambda (face &rest _) (format "bg-%s" face)))
                ((symbol-function '+my/tabs-bar)
                 (lambda (color) (push color bars) (propertize "|" 'display 'bar))))
        (let* ((tabs (+test-tabs--tabs))
               (current (+my/tabs-format b tabs))
               (other (+my/tabs-format a tabs)))
          ;; The bar first, then the icon, the tab's own one; a tab but the
          ;; first after a space of the tab line's.
          (should (equal (substring-no-properties current 0 6) " | B b"))
          (should (eq (get-text-property 0 'face current) 'tab-line))
          (should-not (get-text-property 0 'tab current))
          (should (equal (substring-no-properties other 0 5) "| A a"))
          ;; The icon keeps its colour (the tab's face comes after it).
          (should (eq (car (get-text-property 3 'face current)) 'error))
          ;; The bar: the accent colour on the current tab, the tab's own on others.
          (should (equal (reverse bars) '("bg-highlight" "bg-tab-line-tab-inactive")))
          ;; Clicks still find the tab.
          (should (eq (tab-line--get-tab-property 'tab current) b)))))))

(ert-deftest tabs/no-gap-before-the-first-tab ()
  "A graphical frame's tab line: the first tab's bar at the window's edge (no
separator before it), a space between tabs as before. A text terminal's:
tab-line's `|' separators, as ever."
  (should (advice-member-p #'+my/tabs-no-separator-a 'tab-line-format-template))
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (cl-letf (((symbol-function '+my/tabs-bar) (lambda (_) (propertize "|" 'display 'bar)))
                ((symbol-function 'face-background) (lambda (&rest _) "black")))
        (let ((tty (tab-line-format-template (+test-tabs--tabs))))
          (should (string-prefix-p "| a.txt" (substring-no-properties (car tty))))
          (should (string-prefix-p "| b.txt" (substring-no-properties (cadr tty)))))
        (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                  ((symbol-function 'nerd-icons-icon-for-buffer) (lambda () nil)))
          (let* ((gui (tab-line-format-template (+test-tabs--tabs)))
                 (first (car gui))
                 (second (cadr gui)))
            ;; The first tab's bar first: its own, the tab clicked there.
            (should (eq (get-text-property 0 'display first) 'bar))
            (should (eq (get-text-property 0 'tab first) a))
            ;; The second: a space of the tab line's, then its bar.
            (should (equal (substring-no-properties second 0 2) " |"))
            (should-not (get-text-property 0 'tab second))
            (should (eq (get-text-property 1 'display second) 'bar))
            (should (eq (tab-line--get-tab-property 'tab second) b))))))))

(ert-deftest tabs/every-part-of-the-tab-line-has-a-keymap ()
  "The tab line of a pane below another never drags its pane (Emacs drags
from wherever it has no keymap): every position of it has one, in a
graphical frame and on a text terminal, scrolled or not. A tab's bar and
the space after its ✕ are the tab's (a press selects it); between tabs,
the separators and the rest of the line, filled to the window's edge, a
press does nothing but select the window. A press on a ✕ doesn't drag
either; its click closes the tab."
  (should (advice-member-p #'+my/tabs-whole-line-a 'tab-line-format-template))
  (should (eq (keymap-lookup +my/tabs-line-map "<tab-line> <down-mouse-1>") #'ignore))
  (should (eq (keymap-lookup +my/tabs-line-map "<tab-line> <mouse-1>") #'mouse-select-window))
  (should (eq (keymap-lookup tab-line-tab-close-map "<tab-line> <down-mouse-1>") #'ignore))
  (should (eq (keymap-lookup tab-line-tab-close-map "<tab-line> <mouse-1>") #'tab-line-close-tab))
  (+test-tabs
    (let* ((files (mapcar (lambda (i) (+test-tabs--file (format "file%02d.txt" i))) (number-sequence 1 12)))
           (a (car files))
           (b (cadr files)))
      (apply #'+test-tabs--show files)
      (cl-letf (((symbol-function '+my/tabs-bar) (lambda (_) (propertize "|" 'display 'bar)))
                ((symbol-function 'face-background) (lambda (&rest _) "black")))
        (cl-flet ((check (graphic)
                    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) graphic))
                              ((symbol-function 'window-system) (lambda (&rest _) (and graphic 'ns)))
                              ((symbol-function 'nerd-icons-icon-for-buffer) (lambda () nil)))
                      (dolist (hscroll '(nil 3))
                        (set-window-parameter nil 'tab-line-hscroll hscroll)
                        (let* ((parts (seq-filter (lambda (part) (and (stringp part) (> (length part) 0)))
                                                  (tab-line-format-template (+test-tabs--tabs))))
                               (filler (car (last parts))))
                          (dolist (part parts)
                            (dotimes (i (length part))
                              (should (get-text-property i 'keymap part))))
                          (should (equal (get-text-property 0 'display filler) '(space :align-to (+ right right-fringe right-margin))))
                          (should (eq (get-text-property 0 'keymap filler) +my/tabs-line-map))))
                      (set-window-parameter nil 'tab-line-hscroll nil))))
          (check nil)
          (check t)
          ;; A tab's bar (first) and its last space: the tab's own map.
          (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                    ((symbol-function 'nerd-icons-icon-for-buffer) (lambda () nil)))
            (let ((tab (+my/tabs-format b (+test-tabs--tabs))))
              ;; The space between tabs, then its bar.
              (should (eq (get-text-property 0 'keymap tab) +my/tabs-line-map))
              (should (eq (get-text-property 1 'display tab) 'bar))
              (should (eq (get-text-property 1 'keymap tab) tab-line-tab-map))
              (should (eq (get-text-property (1- (length tab)) 'keymap tab) tab-line-tab-map))
              (should (eq (get-text-property (1- (length tab)) 'tab tab) b)))
            (should (eq (get-text-property 0 'keymap (+my/tabs-format a (+test-tabs--tabs)))
                        tab-line-tab-map))))))))

(ert-deftest tabs/format-gui-icon-failing-or-missing ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt")))
      (+test-tabs--show a)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
                ((symbol-function '+my/tabs-bar) (lambda (_) "")))
        (cl-letf (((symbol-function 'nerd-icons-icon-for-buffer) (lambda () (error "No icon"))))
          (should (string-prefix-p " a.txt " (+my/tabs-format a (+test-tabs--tabs)))))
        (cl-letf (((symbol-function 'nerd-icons-icon-for-buffer) (lambda () nil)))
          (should (string-prefix-p " a.txt " (+my/tabs-format a (+test-tabs--tabs)))))
        (cl-letf (((symbol-function 'nerd-icons-icon-for-buffer) nil))
          (should (string-prefix-p " a.txt " (+my/tabs-format a (+test-tabs--tabs)))))))))

;; A TAB TOO WIDE
(defconst +test-tabs--long "AgreementControllerIntegrationTest.kt")

(ert-deftest tabs/a-label-too-long-for-its-window-is-shortened ()
  "Its end kept after …, the tab as wide as the window allows (room left for
the arrows and the separator), drawn whole by the tab line."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (long (+test-tabs--file +test-tabs--long)))
      (+test-tabs--show a long)
      (split-window-right 30)
      (let* ((tabs (+test-tabs--tabs))
             (tab (substring-no-properties (+my/tabs-format long tabs)))
             (room (+my/tabs--room tabs)))
        ;; The window's body, less its continuation column, the arrows and
        ;; separators (tab-line's) and its own separator.
        (should (= room (- (window-body-width) 1 (string-width "|") (string-width (+my/tabs--around)))))
        (should (string-match "\\` …\\([A-Za-z]+\\)Test\\.kt " tab))
        (should (<= (string-width tab) room))
        ;; As much of it as fits.
        (should (> (string-width tab) (- room 1)))
        ;; Still the tab, clicked or closed.
        (should (eq (tab-line--get-tab-property 'tab (+my/tabs-format long tabs)) long))
        ;; Drawn whole, scrolled to.
        (pcase-let ((`(,shown ,width) (+test-tabs--shown)))
          (should (equal (car (last shown)) +test-tabs--long))
          (should (<= width (1- (window-body-width)))))
        ;; Alone: no arrows to leave room for.
        (should (= (+my/tabs--room (list long)) (+ room (string-width (+my/tabs--around)))))))))

(ert-deftest tabs/labels-that-fit-are-as-they-are ()
  "Short labels, a long one in a window wide enough, same-named files' paths."
  (+test-tabs
    (let ((a (+test-tabs--file "crate-a/src/lib.rs"))
          (b (+test-tabs--file "crate-b/src/lib.rs"))
          (long (+test-tabs--file +test-tabs--long)))
      (+test-tabs--show a b long)
      (let ((tabs (+test-tabs--tabs)))
        (should (string-prefix-p " crate-a/src/lib.rs " (+my/tabs-format a tabs)))
        (should (string-prefix-p " crate-b/src/lib.rs " (+my/tabs-format b tabs)))
        (should (string-prefix-p (concat " " +test-tabs--long " ") (+my/tabs-format long tabs)))))))

(ert-deftest tabs/a-tab-wider-than-its-window-even-shortened-is-scrolled-to ()
  "A pane a few columns wide: the current tab first, cut, not out of view."
  (+test-tabs
    (let ((files (mapcar (lambda (i) (+test-tabs--file (format "file%02d.txt" i))) (number-sequence 1 6))))
      (apply #'+test-tabs--show files)
      (switch-to-buffer (nth 2 files))
      (split-window-right 12)
      (should (equal (car (car (+test-tabs--shown))) "file03.txt")))))

(ert-deftest tabs/scrolled-with-room-for-the-arrows ()
  "tab-line's scroll measures the tabs with the arrows' room before them,
once they don't all fit (arrows to show); as it was when they do."
  (should (advice-member-p #'+my/tabs-scroll-room-a 'tab-line-auto-hscroll))
  (+test-tabs
    (let ((tab (propertize "tab" 'tab (current-buffer) 'selected t))
          calls)
      (set-window-parameter nil 'tab-line-hscroll 3.0)
      ;; They fit: once, no room taken.
      (should (equal (+my/tabs-scroll-room-a
                      (lambda (strings hscroll)
                        (push (list strings hscroll (buffer-local-value 'line-prefix tab-line-auto-hscroll-buffer))
                              calls)
                        (list nil hscroll))
                      (list tab) 3.0)
                     '(nil 3.0)))
      (should (equal calls `(((,tab) 3.0 nil))))
      ;; They don't: again, from the scroll it had, the arrows' room first.
      (setq calls nil)
      (should (equal (+my/tabs-scroll-room-a
                      (lambda (strings hscroll)
                        (push (list hscroll (window-parameter nil 'tab-line-hscroll)
                                    (buffer-local-value 'line-prefix tab-line-auto-hscroll-buffer))
                              calls)
                        (set-window-parameter nil 'tab-line-hscroll 1.0)
                        (list t 1.0))
                      (list tab) 3.0)
                     '(t 1.0)))
      (pcase-let ((`((,hscroll ,parameter ,prefix) (,_ ,_ ,first)) calls))
        (should-not first)
        (should (equal hscroll 3.0))
        (should (equal parameter 3.0))
        (should (equal (get-text-property 0 'display prefix)
                       `(space :width (,(string-width (+my/tabs--around)))))))
      ;; Left as it was.
      (should-not (buffer-local-value 'line-prefix tab-line-auto-hscroll-buffer)))))

(ert-deftest tabs/format-tab-found-by-tab-line ()
  "Clicks find the tab from the string (`tab-line--get-tab-property')."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt")))
      (+test-tabs--show a)
      (should (eq (tab-line--get-tab-property 'tab (+my/tabs-format a (+test-tabs--tabs))) a)))))

(ert-deftest tabs/bar-image ()
  (let ((+my/tabs--bars (make-hash-table :test #'equal))
        (+my/tabs-bar-width 2)
        (+my/tabs-height 22))
    (let* ((bar (+my/tabs-bar "#51afef"))
           (image (get-text-property 0 'display bar)))
      (should (equal (substring-no-properties bar) " "))
      (should (eq (car image) 'image))
      (should (eq (image-property image :type) 'pbm))
      (should (equal (image-property image :data)
                     (concat "P1\n2 22\n" (make-string 44 ?1))))
      (should (equal (image-property image :foreground) "#51afef"))
      (should (equal (image-property image :background) "#51afef"))
      (should (eq (image-property image :ascent) 'center))
      ;; Made once per colour and size.
      (should (eq (+my/tabs-bar "#51afef") bar))
      (should-not (eq (+my/tabs-bar "#ff0000") bar))
      (let ((+my/tabs-height 30))
        (let ((taller (+my/tabs-bar "#51afef")))
          (should-not (eq taller bar))
          (should (string-prefix-p "P1\n2 30\n"
                                   (image-property (get-text-property 0 'display taller) :data))))))))

;; ====== CLOSING A TAB ======

(ert-deftest tabs/close-current-goes-back-to-the-tab-before ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (+my/tabs-close c)
      (should (eq (window-buffer) b))
      (should (equal (+test-tabs--tabs) (list a b)))
      (should (= (length (window-list)) 1)))))

(ert-deftest tabs/close-skips-buffers-that-arent-tabs ()
  "Back to the tab shown before, not to a buffer shown in between that isn't
one (Doom's frame buffer predicate)."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (help (+test-tabs--plain "*Help*"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a help b)
      (+my/tabs-close b)
      (should (eq (window-buffer) a))
      (should (equal (+test-tabs--tabs) (list a))))))

(ert-deftest tabs/close-another-tab-keeps-the-current-one ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (+my/tabs-close a)
      (should (eq (window-buffer) c))
      (should (equal (+test-tabs--tabs) (list b c)))
      (should-not (assq a (window-prev-buffers)))
      (should-not (memq a (window-next-buffers)))
      (should-not (memq a (window-parameter nil 'tab-line-buffers))))))

(ert-deftest tabs/close-another-tab-from-next-buffers ()
  "A tab the window went back from (in its next buffers) closes too."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (switch-to-prev-buffer)
      (should (eq (window-buffer) a))
      (should (memq b (window-next-buffers)))
      (+my/tabs-close b)
      (should-not (memq b (window-next-buffers)))
      (should (equal (+test-tabs--tabs) (list a))))))

(ert-deftest tabs/close-file-no-window-has-closes-it ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (+my/tabs-close c)
      (should-not (buffer-live-p c))
      (+my/tabs-close a)
      (should-not (buffer-live-p a))
      (should (buffer-live-p b)))))

(ert-deftest tabs/close-file-another-window-shows-keeps-it ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let ((other (split-window nil nil 'right)))
        (set-window-buffer other b)
        (+my/tabs-close b)
        (should (eq (window-buffer) a))
        (should (buffer-live-p b))
        (should (eq (window-buffer other) b))))))

(ert-deftest tabs/close-file-another-window-has-as-a-tab-keeps-it ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b)
      (let ((other (split-window nil nil 'right)))
        (with-selected-window other
          (+test-tabs--show c a)            ; c a tab there, not shown
          (should (memq c (+test-tabs--tabs))))
        (+test-tabs--show c)
        (+my/tabs-close c)
        (should (buffer-live-p c))
        (should (memq c (+test-tabs--tabs other)))))))

(ert-deftest tabs/held-p ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b)
      (should (+my/tabs-held-p b))          ; shown
      (should (+my/tabs-held-p a))          ; a tab
      (should-not (+my/tabs-held-p c))
      ;; Shown in a side panel counts too.
      (display-buffer-in-side-window c '((side . left)))
      (should (+my/tabs-held-p c)))))

(ert-deftest tabs/close-last-tab-closes-the-window ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a)
      (let ((other (split-window nil nil 'right)))
        (select-window other)
        (+test-tabs--only other b)
        (should (equal (+test-tabs--tabs) (list b)))
        (+my/tabs-close b)
        (should-not (window-live-p other))
        (should (= (length (window-list)) 1))
        (should (eq (window-buffer) a))
        (should-not (buffer-live-p b))))))

(ert-deftest tabs/close-last-tab-of-another-window-by-click ()
  "The ✕ on the last tab of a window that isn't selected closes that window;
the selected one stays selected."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a)
      (let ((main (selected-window))
            (other (split-window nil nil 'right)))
        (+test-tabs--only other b)
        (tab-line-close-tab (+test-tabs--event other b 'mouse-1))
        (should-not (window-live-p other))
        (should (eq (selected-window) main))
        (should (eq (window-buffer main) a))
        (should-not (buffer-live-p b))))))

(ert-deftest tabs/close-last-tab-of-the-only-window-shows-the-fallback ()
  "The frame's only window stays, on Doom's fallback buffer (the dashboard),
with no tabs from before."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (help (+test-tabs--plain "*Help*")))
      (+test-tabs--show help a)
      (should (equal (+test-tabs--tabs) (list a)))
      (let ((window (selected-window)))
        (+my/tabs-close a)
        (should (eq (selected-window) window))
        (should (= (length (window-list)) 1))
        (should (eq (window-buffer) (doom-fallback-buffer)))
        (should-not (window-prev-buffers))
        (should-not (window-next-buffers))
        (should-not (buffer-live-p a))))))

(ert-deftest tabs/close-last-tab-beside-a-side-panel-shows-the-fallback ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (side (display-buffer-in-side-window (+test-buffer "SIDE") '((side . left)))))
      (+test-tabs--show a)
      (+my/tabs-close a)
      (should (window-live-p side))
      (should (eq (window-buffer) (doom-fallback-buffer)))
      (should (= (length (window-list)) 2)))))

(ert-deftest tabs/close-other-buffers-only-leave-the-tab-line ()
  "Only files close: dired, a Claude session, *Help* stay alive."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (dir (+test-tabs--on (dired-noselect +test-tmp)))
          (session (+test-tabs--plain "*claude*"))
          (help (+test-tabs--plain "*Help*")))
      (with-current-buffer session (setq major-mode 'agent-shell-mode))
      (+test-tabs--show a dir session help)
      (should (equal (+test-tabs--tabs) (list a dir session help)))
      (+my/tabs-close help)
      (should (eq (window-buffer) session))
      (+my/tabs-close session)
      (should (eq (window-buffer) dir))
      (+my/tabs-close dir)
      (should (equal (+test-tabs--tabs) (list a)))
      (should (buffer-live-p help))
      (should (buffer-live-p session))
      (should (buffer-live-p dir)))))

(ert-deftest tabs/close-unsaved-file-asks-first ()
  "The file is killed the usual way (`kill-buffer-query-functions'), so it
asks: answering no keeps it, unsaved."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (asked nil))
      (+test-tabs--show a b)
      (with-current-buffer b (insert "unsaved"))
      (let ((kill-buffer-query-functions
             (list (lambda () (setq asked (buffer-name)) nil))))
        (+my/tabs-close b))
      (should (equal asked "b.txt"))
      (should (buffer-live-p b))
      (should (buffer-modified-p b))
      (should (eq (window-buffer) a)))))

(ert-deftest tabs/close-alist-tabs ()
  "Tabs given as alists (tab-line's other form) close too."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (+my/tabs-close `((name . "a.txt") (buffer . ,a)))
      (should (equal (+test-tabs--tabs) (list b)))
      (should-not (buffer-live-p a)))))

(ert-deftest tabs/close-with-the-x-or-a-middle-click ()
  (should (eq (keymap-lookup tab-line-tab-map "<tab-line> <mouse-2>") #'tab-line-close-tab))
  (should (eq (keymap-lookup tab-line-tab-close-map "<tab-line> <mouse-1>") #'tab-line-close-tab))
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      ;; ✕ on a tab that isn't the current one.
      (tab-line-close-tab (+test-tabs--event (selected-window) a 'mouse-1))
      (should (eq (window-buffer) c))
      (should (equal (+test-tabs--tabs) (list b c)))
      (should-not (buffer-live-p a))
      ;; A middle click on the current one.
      (tab-line-close-tab (+test-tabs--event (selected-window) c 'mouse-2))
      (should (eq (window-buffer) b))
      (should (equal (+test-tabs--tabs) (list b))))))

(ert-deftest tabs/close-in-another-window-by-click ()
  "A click closes the tab in the window it's in, not the selected one."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a)
      (let ((main (selected-window))
            (other (split-window nil nil 'right)))
        (+test-tabs--only other b)
        (with-selected-window other (+test-tabs--show a))
        (tab-line-close-tab (+test-tabs--event other a 'mouse-1))
        (should (eq (window-buffer other) b))
        (should (eq (window-buffer main) a))
        (should (equal (+test-tabs--tabs main) (list a)))
        (should (buffer-live-p a))))))

;; ====== CMD+W ======

(ert-deftest tabs/cmd-w-closes-the-current-tab ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (call-interactively #'+my/tabs-close-current)
      (should (eq (window-buffer) a))
      (should (equal (+test-tabs--tabs) (list a)))
      (should-not (buffer-live-p b)))))

(ert-deftest tabs/cmd-w-without-tabs-closes-the-window ()
  "Where there's no tab line (a popup...), the window."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (popup (+test-buffer "*popup*")))
      (+test-tabs--show a)
      (let ((window (split-window nil nil 'below)))
        (set-window-buffer window popup)
        (select-window window)
        (should-not (buffer-local-value 'tab-line-mode popup))
        (call-interactively #'+my/tabs-close-current)
        (should-not (window-live-p window))
        (should (buffer-live-p popup))
        (should (eq (window-buffer) a))))))

(ert-deftest tabs/cmd-w-without-tabs-uses-dooms-close-window ()
  "Doom remaps `delete-window' (e.g. closing the workspace with its last window)."
  (+test-tabs
    (let ((popup (+test-buffer "*popup*"))
          (called nil)
          (map (make-sparse-keymap)))
      (define-key map [remap delete-window] (lambda () (interactive) (setq called t)))
      (switch-to-buffer popup)
      (use-local-map map)
      (call-interactively #'+my/tabs-close-current)
      (should called))))

;; ====== CMD+1..9 ======

(ert-deftest tabs/cmd-n-shows-the-nth-tab ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (+my/tabs-select-1)
      (should (eq (window-buffer) a))
      (+my/tabs-select-2)
      (should (eq (window-buffer) b))
      (+my/tabs-select-3)
      (should (eq (window-buffer) c))
      ;; The order stays.
      (should (equal (+test-tabs--tabs) (list a b c))))))

;; ====== THE ORDER KEPT THROUGH A WORKSPACE SWITCH ======

(defun +test-tabs--show-drawn (&rest buffers)
  "Show BUFFERS in the selected window one after the other, its tab line
drawn after each, as after each command (its tabs computed: tab-line
records their order then)."
  (dolist (buffer buffers)
    (switch-to-buffer (+test-tabs--on buffer))
    (+test-tabs--tabs)))

(defun +test-tabs--workspace-away-and-back (&optional between)
  "The frame's windows put away and back as Doom's workspaces (persp-mode)
do: `window-state-get' WRITABLE, another workspace's buffer shown in one
window, BETWEEN called (a function), `window-state-put'. The state, as text
read back (persp's file): it must hold no buffer object."
  (let ((state (window-state-get (frame-root-window) t)))
    (should-not (string-search "#<" (prin1-to-string state)))
    (setq state (car (read-from-string (prin1-to-string state))))
    (delete-other-windows)
    (switch-to-buffer (+test-tabs--plain "elsewhere"))
    (set-window-prev-buffers nil nil)
    (when between (funcall between))
    (window-state-put state (frame-root-window) t)))

(ert-deftest tabs/the-order-kept-through-a-workspace-switch ()
  "A B C D E, C shown with Cmd+3 (or SPC b b, a click: a buffer switched
to): another workspace and back, A B C D E, C current. Before, C went last
\(doom-djc.14): tab-line's order is kept in no text state."
  (dolist (show '(+my/tabs-select-3 switch-to-buffer))
    (ert-info ((format "C shown with %s" show))
      (+test-tabs
        (let ((tabs (mapcar (lambda (name) (+test-tabs--file (concat name ".txt"))) '("a" "b" "c" "d" "e"))))
          (apply #'+test-tabs--show-drawn tabs)
          (if (eq show '+my/tabs-select-3)
              (+my/tabs-select-3)
            (+test-tabs--show-drawn (nth 2 tabs)))
          (should (equal (+test-tabs--tabs) tabs))
          (+test-tabs--workspace-away-and-back)
          (should (eq (window-buffer) (nth 2 tabs)))
          (should (equal (+test-tabs--tabs) tabs)))))))

(ert-deftest tabs/each-pane-keeps-its-order ()
  "Two panes, each its own tabs in its own order: another workspace and
back, each as it was."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt")) (b (+test-tabs--file "b.txt")) (c (+test-tabs--file "c.txt"))
          (x (+test-tabs--file "x.txt")) (y (+test-tabs--file "y.txt")) (z (+test-tabs--file "z.txt")))
      (+test-tabs--show-drawn a b c a)
      (let ((right (split-window nil nil 'right)))
        (+test-tabs--only right x)
        (with-selected-window right
          (+test-tabs--show-drawn x y z x)))
      (should (equal (+test-tabs--tabs) (list a b c)))
      (should (equal (+test-tabs--tabs (window-in-direction 'right)) (list x y z)))
      (+test-tabs--workspace-away-and-back)
      (let ((left (frame-first-window)))
        (should (eq (window-buffer left) a))
        (should (equal (+test-tabs--tabs left) (list a b c)))
        (should (eq (window-buffer (window-in-direction 'right left)) x))
        (should (equal (+test-tabs--tabs (window-in-direction 'right left)) (list x y z)))))))

(ert-deftest tabs/the-order-kept-a-buffer-killed-meanwhile ()
  "A tab's buffer killed while in the other workspace: gone from the tabs
when back, no error, the others in their order; a buffer shown after, at
the end."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt")) (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")) (d (+test-tabs--file "d.txt")))
      (+test-tabs--show-drawn a b c d b)
      (+test-tabs--workspace-away-and-back (lambda () (kill-buffer c)))
      (should (eq (window-buffer) b))
      (should (equal (+test-tabs--tabs) (list a b d)))
      (let ((e (+test-tabs--file "e.txt")))
        (+test-tabs--show-drawn e)
        (should (equal (+test-tabs--tabs) (list a b d e)))))))

(ert-deftest tabs/cmd-9-shows-the-last-tab ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (+my/tabs-select-1)
      (+my/tabs-select-9)
      (should (eq (window-buffer) c))))
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt")))
      (+test-tabs--show a)
      (+my/tabs-select-9)
      (should (eq (window-buffer) a)))))

(ert-deftest tabs/cmd-n-past-the-last-tab-does-nothing ()
  (+test-tabs
    (+test-tabs--with-workspaces
      (let ((a (+test-tabs--file "a.txt"))
            (b (+test-tabs--file "b.txt")))
        (+test-tabs--show a b)
        (+my/tabs-select-5)
        (+my/tabs-select-8)
        (should (eq (window-buffer) b))
        (should-not +test-tabs--workspace-calls)))))

(ert-deftest tabs/cmd-n-without-tabs-switches-workspaces ()
  "Where there are no tabs (side panels, popups), Doom's Cmd+N."
  (+test-tabs
    (+test-tabs--with-workspaces
      (switch-to-buffer (+test-buffer "*popup*"))
      (should-not tab-line-mode)
      (+my/tabs-select-1)
      (+my/tabs-select-4)
      (+my/tabs-select-8)
      (+my/tabs-select-9)
      (should (equal (reverse +test-tabs--workspace-calls)
                     '(+workspace/switch-to-0 +workspace/switch-to-3
                       +workspace/switch-to-7 +workspace/switch-to-final))))))

(ert-deftest tabs/cmd-n-commands ()
  (dotimes (i 9)
    (let ((command (intern (format "+my/tabs-select-%d" (1+ i)))))
      (should (commandp command))
      (should (string-match-p (if (= i 8) "last tab" (format "%d\\. tab" (1+ i)))
                              (documentation command))))))

;; ====== GT / GT (NEXT / PREVIOUS TAB) ======

(ert-deftest tabs/gt-gT-go-round-the-tabs ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (+my/tabs-select-2)
      (call-interactively #'tab-line-switch-to-next-tab)
      (should (eq (window-buffer) c))
      (call-interactively #'tab-line-switch-to-next-tab)     ; wraps around
      (should (eq (window-buffer) a))
      (call-interactively #'tab-line-switch-to-prev-tab)     ; and back
      (should (eq (window-buffer) c))
      (call-interactively #'tab-line-switch-to-prev-tab)
      (should (eq (window-buffer) b))
      (should (equal (+test-tabs--tabs) (list a b c))))))

(ert-deftest tabs/gt-skips-buffers-that-arent-tabs ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (help (+test-tabs--plain "*Help*"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a help b)
      (call-interactively #'tab-line-switch-to-next-tab)
      (should (eq (window-buffer) a))
      (call-interactively #'tab-line-switch-to-next-tab)
      (should (eq (window-buffer) b)))))

;; ====== THE TAB MENU ======

(ert-deftest tabs/menu-items ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (got nil))
      (+test-tabs--show a)
      (let ((event (+test-tabs--event (selected-window) a)))
        (cl-letf (((symbol-function 'popup-menu)
                   (lambda (menu &optional position &rest _) (setq got (list menu position)))))
          (+my/tabs-context-menu event))
        (should (eq (cadr got) event))
        (let ((items nil))
          (map-keymap (lambda (key item) (push (cons key item) items)) (car got))
          (setq items (nreverse items))
          (should (equal (mapcar #'car items)
                         '(close close-other split-separator split-right split-below)))
          (should (equal (mapcar (lambda (item) (and (eq (cadr item) 'menu-item)
                                                     (list (nth 2 item) (nth 3 item))))
                                 items)
                         '(("Close" tab-line-close-tab)
                           ("Close other tabs" tab-line-close-other-tabs)
                           nil
                           ("Split Vertically" +my/tabs-split-right)
                           ("Split Horizontally" +my/tabs-split-below)))))))))

(ert-deftest tabs/menu-close ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (tab-line-close-tab (+test-tabs--event (selected-window) b))
      (should (eq (window-buffer) c))
      (should (equal (+test-tabs--tabs) (list a c)))
      (should-not (buffer-live-p b)))))

(ert-deftest tabs/menu-close-other-tabs ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (tab-line-close-other-tabs (+test-tabs--event (selected-window) b))
      (should (eq (window-buffer) b))
      (should (equal (+test-tabs--tabs) (list b)))
      (should (= (length (window-list)) 1))
      (should-not (buffer-live-p a))
      (should-not (buffer-live-p c)))))

(ert-deftest tabs/split-right-shows-only-the-clicked-tab ()
  "Split Vertically: a new pane on the right, with only that tab, takes focus;
the tab stays in its own pane too."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt"))
          (c (+test-tabs--file "c.txt")))
      (+test-tabs--show a b c)
      (let* ((old (selected-window))
             (event (+test-tabs--event old b)))
        (+my/tabs-split-right event)
        (let ((new (selected-window)))
          (should-not (eq new old))
          (should (= (length (window-list)) 2))
          (should (eq (window-buffer new) b))
          (should (equal (+test-tabs--tabs new) (list b)))
          (should-not (window-prev-buffers new))
          (should-not (window-next-buffers new))
          ;; On the right of the old pane.
          (should (> (car (window-edges new)) (car (window-edges old))))
          (should (= (cadr (window-edges new)) (cadr (window-edges old))))
          ;; The old pane: as it was.
          (should (eq (window-buffer old) c))
          (should (equal (+test-tabs--tabs old) (list a b c))))))))

(ert-deftest tabs/split-below-shows-only-the-clicked-tab ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let ((old (selected-window)))
        (+my/tabs-split-below (+test-tabs--event old a))
        (let ((new (selected-window)))
          (should-not (eq new old))
          (should (eq (window-buffer new) a))
          (should (equal (+test-tabs--tabs new) (list a)))
          (should (> (cadr (window-edges new)) (cadr (window-edges old))))
          (should (= (car (window-edges new)) (car (window-edges old))))
          (should (eq (window-buffer old) b))
          (should (equal (+test-tabs--tabs old) (list a b))))))))

(ert-deftest tabs/split-the-current-tab ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let ((old (selected-window)))
        (+my/tabs-split-right (+test-tabs--event old b))
        (should (eq (window-buffer) b))
        (should (equal (+test-tabs--tabs) (list b)))
        (should (eq (window-buffer old) b))))))

(ert-deftest tabs/split-from-a-window-not-selected ()
  "The pane opens beside the window clicked in, not the selected one."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a)
      (let* ((main (selected-window))
             (below (split-window nil nil 'below)))
        (+test-tabs--only below b)
        (+my/tabs-split-right (+test-tabs--event below b))
        (let ((new (selected-window)))
          (should-not (memq new (list main below)))
          (should (= (cadr (window-edges new)) (cadr (window-edges below))))
          (should (> (car (window-edges new)) (car (window-edges below))))
          (should (eq (window-buffer main) a)))))))

(ert-deftest tabs/split-from-the-menu ()
  "The menu runs its command with the click as `last-nonmenu-event'."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let* ((old (selected-window))
             (event (+test-tabs--event old a)))
        (cl-letf (((symbol-function 'popup-menu)
                   (lambda (menu &rest _)
                     ;; The user picks Split Vertically.
                     (let ((last-nonmenu-event event))
                       (call-interactively (lookup-key menu [split-right]))))))
          (+my/tabs-context-menu event))
        (should-not (eq (selected-window) old))
        (should (eq (window-buffer) a))
        (should (equal (+test-tabs--tabs) (list a)))))))

(ert-deftest tabs/split-alist-tab ()
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let* ((old (selected-window))
             (event (list 'down-mouse-3
                          (list old 'tab-line '(0 . 0) 0
                                (cons (propertize "a.txt" 'tab `((name . "a.txt") (buffer . ,a))) 1)
                                nil '(0 . 0) nil '(0 . 0) '(0 . 0)))))
        (+my/tabs-split-right event)
        (should (eq (window-buffer) a))
        (should-not (eq (selected-window) old))))))

(ert-deftest tabs/split-does-nothing-off-a-tab ()
  "A click not on a tab, on a tab whose buffer is gone, or in a window that
closed: no pane."
  (+test-tabs
    (let ((a (+test-tabs--file "a.txt"))
          (b (+test-tabs--file "b.txt")))
      (+test-tabs--show a b)
      (let ((window (selected-window)))
        (+my/tabs-split-right (+test-tabs--event-off-a-tab window))
        (should (= (length (window-list)) 1))
        (let ((event (+test-tabs--event window a)))
          (kill-buffer a)
          (+my/tabs-split-below event)
          (should (= (length (window-list)) 1))
          (should (eq (selected-window) window)))
        (let* ((other (split-window nil nil 'right))
               (event (+test-tabs--event other b)))
          (delete-window other)
          (+my/tabs-split-right event)
          (should (= (length (window-list)) 1))
          (should (eq (selected-window) window)))))))

;; ====== NO TAB LINE ======

(ert-deftest tabs/off-h ()
  (+test-tabs
    (with-current-buffer (+test-tabs--plain "*popup*")
      (should tab-line-mode)
      (+my/tabs-off-h)
      (should-not tab-line-mode)
      (should tab-line-exclude)
      ;; Global tab line mode leaves it off.
      (tab-line-mode--turn-on)
      (should-not tab-line-mode)
      ;; Off already: stays so.
      (+my/tabs-off-h)
      (should-not tab-line-mode))))

(ert-deftest tabs/popups-have-no-tab-line ()
  (should (memq '+my/tabs-popup-h (bound-and-true-p +popup-buffer-mode-hook)))
  (+test-tabs
    (with-current-buffer (+test-tabs--plain "*Help*")
      (setq-local +popup-buffer-mode t)
      (run-hooks '+popup-buffer-mode-hook)
      (should-not tab-line-mode)
      (should tab-line-exclude))
    ;; The popup mode turning off leaves the tab line be.
    (with-current-buffer (+test-tabs--plain "notes")
      (setq-local +popup-buffer-mode nil)
      (run-hooks '+popup-buffer-mode-hook)
      (should tab-line-mode)
      (should-not tab-line-exclude))))

(ert-deftest tabs/dashboard-has-no-tab-line ()
  (should (memq '+my/tabs-off-h (bound-and-true-p +doom-dashboard-mode-hook)))
  (+test-tabs
    (with-current-buffer (+test-tabs--plain "*doom*")
      (run-hooks '+doom-dashboard-mode-hook)
      (should-not tab-line-mode)
      (should tab-line-exclude))))

;; ====== KEYS ======

(ert-deftest tabs/keys ()
  (should (eq (lookup-key evil-normal-state-map "gt") #'tab-line-switch-to-next-tab))
  (should (eq (lookup-key evil-normal-state-map "gT") #'tab-line-switch-to-prev-tab))
  (dotimes (i 9)
    (let ((key (kbd (format "s-%d" (1+ i))))
          (command (intern (format "+my/tabs-select-%d" (1+ i)))))
      (should (eq (lookup-key global-map key) command))
      (should (eq (lookup-key evil-normal-state-map key) command))))
  (should (eq (lookup-key global-map (kbd "s-w")) #'+my/tabs-close-current))
  (should (eq (keymap-lookup tab-line-tab-map "<tab-line> <down-mouse-3>")
              #'+my/tabs-context-menu)))

(ert-deftest tabs/keys-in-a-buffer ()
  "What the keys run in a buffer in normal state (evil's own gt is a tab-bar's)."
  (+test-tabs
    (with-current-buffer (+test-tabs--file "a.txt")
      (evil-local-mode 1)
      (evil-normal-state)
      (should (eq (key-binding "gt") #'tab-line-switch-to-next-tab))
      (should (eq (key-binding "gT") #'tab-line-switch-to-prev-tab))
      (should (eq (key-binding (kbd "s-1")) #'+my/tabs-select-1))
      (should (eq (key-binding (kbd "s-9")) #'+my/tabs-select-9))
      (should (eq (key-binding (kbd "s-w")) #'+my/tabs-close-current))
      (evil-insert-state)
      (should (eq (key-binding (kbd "s-1")) #'+my/tabs-select-1))
      (should (eq (key-binding (kbd "s-w")) #'+my/tabs-close-current)))))

;; ====== LOADED ======

(defun +test-tabs--forms (file)
  "FILE's (of this config) top-level forms."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      forms)))

(ert-deftest tabs/config-el-loads-it ()
  "config.el loads the editor, which loads it."
  (should (member '(load! "config/editor") (+test-tabs--forms "config.el")))
  (should (member '(load! "editor/tabs") (+test-tabs--forms "config/editor.el"))))
