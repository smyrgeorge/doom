;;; $DOOMDIR/config/editor/tabs.el -*- lexical-binding: t; -*-
;; Tabs per window (Emacs's tab line).
;; Loaded from config/editor.el.

(defun +my/tabs-p (buffer)
  "Non-nil if BUFFER keeps a tab when it isn't shown (see above)."
  (with-current-buffer buffer
    (or buffer-file-name
        (derived-mode-p 'agent-shell-mode 'dired-mode)
        (doom-real-buffer-p buffer))))

;; A NEW BUFFER (SPC b N: evil-buffer-new, *new*): no file, and a name
;; starting with *, so Doom called it unreal: shown, then gone from its tabs
;; once another was shown, nor listed by SPC b b, nor gone back to. Real now,
;; kept through a change of mode (M-x markdown-mode on what you wrote).
(defvar-local +my/tabs--new-buffer nil
  "Non-nil in a buffer SPC b N made (see above).")
(put '+my/tabs--new-buffer 'permanent-local t)

(defun +my/tabs-new-buffer-a (&optional file)
  "After `evil-buffer-new': the new buffer (not FILE's) marked (see above)."
  (unless file
    (with-current-buffer (window-buffer)
      (setq +my/tabs--new-buffer t))))

(defun +my/tabs-new-buffer-real-p (buffer)
  "For `doom-real-buffer-functions': BUFFER made by SPC b N (see above)."
  (buffer-local-value '+my/tabs--new-buffer buffer))

(advice-add 'evil-buffer-new :after #'+my/tabs-new-buffer-a)
(add-hook 'doom-real-buffer-functions #'+my/tabs-new-buffer-real-p)

;; THE BUFFER LIST (SPC b i: ibuffer, *Ibuffer*) and the other modes of
;; `+my/tabs-real-modes': unreal for Doom too (no file, a *name*), so shown,
;; then gone from its tabs once another tab was clicked, though still open:
;; Doom's workspaces add only real buffers, and a tab not shown is kept only
;; for one (and only in its workspace). Real now: kept, in the workspace,
;; listed by SPC b b. Closed as a file is: killed once no window has it as a
;; tab, its tab closed (see CLOSING A TAB below) or q (`quit-window', which
;; only buried it).
(defun +my/tabs-real-mode-p (buffer)
  "For `doom-real-buffer-functions': BUFFER in a mode of `+my/tabs-real-modes'."
  (provided-mode-derived-p (buffer-local-value 'major-mode buffer) +my/tabs-real-modes))

(add-hook 'doom-real-buffer-functions #'+my/tabs-real-mode-p)

(defun +my/tabs-quit-window-a (fn &optional kill window)
  "`quit-window': a buffer of `+my/tabs-real-modes' quit is killed once no
window has it as a tab (see above)."
  (let ((buffer (window-buffer (window-normalize-window window))))
    (funcall fn kill window)
    (when (and (buffer-live-p buffer) (+my/tabs-real-mode-p buffer)
               (not (+my/tabs-held-p buffer)))
      (kill-buffer buffer))))

(advice-add 'quit-window :around #'+my/tabs-quit-window-a)

(defun +my/tabs-in-workspace-p (buffer)
  "Non-nil if BUFFER is the current workspace's (Doom's workspaces), or
without workspaces."
  (or (not (bound-and-true-p persp-mode))
      (not (fboundp 'persp-contain-buffer-p))
      (persp-contain-buffer-p buffer)))

(defun +my/tabs-window-buffers ()
  "The selected window's tabs (see above): the buffers it showed that keep a
tab, the current workspace's only. A new workspace (SPC p p) starts in the
window the last one showed, its buffers in the window's history: their tabs
are the other workspace's."
  (let ((current (window-buffer)))
    (seq-filter (lambda (buffer)
                  (or (eq buffer current)
                      (and (+my/tabs-p buffer) (+my/tabs-in-workspace-p buffer))))
                (tab-line-tabs-fixed-window-buffers))))

;; LABELS
;; Workspaces disable uniquify, so same-named files get buffer names like
;; lib.rs, lib.rs<2>, even when they're in different projects. Label file tabs
;; with the file name instead of the buffer name, and when two tabs in the same
;; window share a file name, with the shortest distinguishing path, e.g.
;; crate-a/src/lib.rs.
(defun +my/tabs-unique-label (file others)
  "Return the shortest trailing part of FILE's path not shared by OTHERS."
  (let* ((split (lambda (f) (reverse (split-string (abbreviate-file-name f) "/" t))))
         (parts (funcall split file))
         (other-parts (mapcar split others))
         (n 1))
    (while (and (< n (length parts))
                (seq-some (lambda (o) (equal (seq-take o n) (seq-take parts n)))
                          other-parts))
      (setq n (1+ n)))
    (string-join (reverse (seq-take parts n)) "/")))

(defun +my/tabs-label (buffer buffers)
  "BUFFER's tab label among BUFFERS (see above)."
  (if-let* ((file (buffer-file-name buffer)))
      (let* ((name (file-name-nondirectory file))
             (others (delq nil (mapcar (lambda (b)
                                         (let ((f (and (not (eq b buffer))
                                                       (buffer-file-name b))))
                                           (and f (equal (file-name-nondirectory f) name)
                                                f)))
                                       buffers))))
        (if others (+my/tabs-unique-label file others) name))
    (buffer-name buffer)))

;; THE BAR
;; An image as tall as the tab row: in the accent colour on the current tab,
;; in the tab's own colour on the others (it makes the row that tall).
(defvar +my/tabs--bars (make-hash-table :test #'equal))

(defun +my/tabs-bar (color)
  "An image +my/tabs-bar-width wide and +my/tabs-height tall, in COLOR."
  (let ((key (list color +my/tabs-bar-width +my/tabs-height)))
    (or (gethash key +my/tabs--bars)
        (puthash key
                 (propertize
                  " " 'display
                  (create-image (concat (format "P1\n%d %d\n" +my/tabs-bar-width
                                                +my/tabs-height)
                                        (make-string (* +my/tabs-bar-width
                                                        +my/tabs-height)
                                                     ?1))
                                'pbm t :foreground color :background color
                                :ascent 'center))
                 +my/tabs--bars))))

(defun +my/tabs-format (tab tabs)
  "TAB's text in the tab line (see above), for `tab-line-tab-name-format-function'."
  (let* ((selected (eq tab (window-buffer)))
         (face (cond ((not selected) 'tab-line-tab-inactive)
                     ((mode-line-window-selected-p) 'tab-line-tab-current)
                     (t 'tab-line-tab)))
         (icon (and (display-graphic-p) (fboundp 'nerd-icons-icon-for-buffer)
                    (with-current-buffer tab
                      (ignore-errors (nerd-icons-icon-for-buffer)))))
         (text (concat " "
                       (if (stringp icon) (concat icon " ") "")
                       (+my/tabs-label tab tabs)
                       (if (and (buffer-file-name tab) (buffer-modified-p tab))
                           " •" "")
                       " "))
         (close (copy-sequence tab-line-close-button))
         (bar (and (display-graphic-p)
                   (+my/tabs-bar (if selected
                                     (face-background 'highlight nil t)
                                   (face-background face nil t))))))
    ;; Appended, so the icon keeps its own colour.
    (add-face-text-property 0 (length text) face t text)
    (add-face-text-property 0 (length close) face t close)
    (propertize (concat (or bar "")
                        (propertize text
                                    'keymap tab-line-tab-map
                                    'help-echo (if selected "Current tab"
                                                 "Click to select tab")
                                    'follow-link 'ignore)
                        close
                        (propertize " " 'face face))
                'tab tab
                'selected selected
                'mouse-face 'tab-line-highlight)))

;; THE CACHE
;; Tab-line draws a window's tabs again only when its cache key changes, and
;; that key watches the current tab alone for unsaved changes: saving the
;; others (save all, magit saving the repository's files) left their • on, and
;; changes made elsewhere (another window, a rename by the language server)
;; didn't show one. The key watches every file tab.
(defun +my/tabs-cache-key (tabs)
  "TABS' cache key (`tab-line-cache-key-function'): tab-line's own, and which
of them have unsaved changes."
  (cons (mapcar (lambda (tab) (and (bufferp tab) (buffer-file-name tab) (buffer-modified-p tab)))
                tabs)
        (tab-line-cache-key-default tabs)))

;; A theme loaded: every window's tabs drawn again. Their bars are images in
;; the old theme's colours, which the cache kept (their text, in faces,
;; follows by itself).
(add-hook 'doom-load-theme-hook
          (defun +my/tabs-theme-h ()
            (when (fboundp 'tab-line-force-update)
              (tab-line-force-update t))))

;; CLOSING A TAB (see above)
(defun +my/tabs-held-p (buffer)
  "Non-nil if a window shows BUFFER or has it as a tab."
  (seq-some (lambda (window)
              (or (eq (window-buffer window) buffer)
                  (assq buffer (window-prev-buffers window))))
            (window-list-1 nil 'nomini t)))

(defun +my/tabs-close (tab)
  "Take TAB off the selected window's tabs, and close its file (or kill its
buffer of `+my/tabs-real-modes') if no window has it any more (see above).
Its last tab closes the window, unless it's the frame's only one (beside side
panels), which shows Doom's dashboard instead."
  (let* ((buffer (if (bufferp tab) tab (cdr (assq 'buffer tab))))
         (window (selected-window))
         (last (equal (+my/tabs-window-buffers) (list buffer))))
    (cond ((and last (eq (window-deletable-p window) t))
           (delete-window window))
          (last
           (switch-to-buffer (doom-fallback-buffer) nil t)
           (set-window-prev-buffers nil nil)
           (set-window-next-buffers nil nil)
           (set-window-parameter nil 'tab-line-buffers nil))
          (t
           (if (eq buffer (window-buffer))
               (bury-buffer)            ; back to the tab shown before
             (set-window-prev-buffers nil (assq-delete-all buffer (window-prev-buffers)))
             (set-window-next-buffers nil (delq buffer (window-next-buffers))))
           (set-window-parameter nil 'tab-line-buffers
                                 (delq buffer (window-parameter nil 'tab-line-buffers)))))
    (when (and (buffer-live-p buffer)
               (or (buffer-file-name buffer) (+my/tabs-real-mode-p buffer))
               (not (+my/tabs-held-p buffer)))
      (kill-buffer buffer))))

(defun +my/tabs-select (n)
  "Show the selected window's Nth tab, its last for 9 (see above); without
tabs, switch to the Nth workspace, as Doom's Cmd+N did."
  (if (bound-and-true-p tab-line-mode)
      (let ((tabs (+my/tabs-window-buffers)))
        (when-let* ((buffer (if (= n 9) (car (last tabs)) (nth (1- n) tabs))))
          (switch-to-buffer buffer nil t)))
    (call-interactively (if (= n 9)
                            #'+workspace/switch-to-final
                          (intern (format "+workspace/switch-to-%d" (1- n)))))))

(dotimes (i 9)
  (let ((n (1+ i)))
    (defalias (intern (format "+my/tabs-select-%d" n))
      (lambda () (interactive) (+my/tabs-select n))
      (format "Show the window's %s tab (`+my/tabs-select')."
              (if (= n 9) "last" (format "%d." n))))))

(defun +my/tabs-close-current ()
  "Close the current tab (see above); without tabs, the window, as Doom does."
  (interactive)
  (if (bound-and-true-p tab-line-mode)
      (+my/tabs-close (window-buffer))
    (call-interactively (or (command-remapping #'delete-window) #'delete-window))))

;; THE TAB MENU (see above)
(defun +my/tabs-split (event side)
  "Show the tab EVENT is on in a new pane on SIDE (`right', `below') of its
own, which takes focus."
  (let* ((posn (tab-line-event-start event))
         (window (posn-window posn))
         (tab (and (posn-string posn)
                   (tab-line--get-tab-property 'tab (car (posn-string posn)))))
         (buffer (if (bufferp tab) tab (cdr (assq 'buffer tab)))))
    (when (and (window-live-p window) (buffer-live-p buffer))
      (let ((new (split-window window nil side)))
        (set-window-buffer new buffer)
        ;; Only that tab: the split showed the old pane's buffer first, which
        ;; `set-window-buffer' left in the new pane's history, so its tabs.
        (set-window-prev-buffers new nil)
        (set-window-next-buffers new nil)
        (set-window-parameter new 'tab-line-buffers nil)
        (select-window new)))))

(defun +my/tabs-split-right (&optional event)
  "Split Vertically: show this tab in a new pane on the right."
  (interactive (list last-nonmenu-event))
  (+my/tabs-split event 'right))

(defun +my/tabs-split-below (&optional event)
  "Split Horizontally: show this tab in a new pane below."
  (interactive (list last-nonmenu-event))
  (+my/tabs-split event 'below))

(defun +my/tabs-context-menu (&optional event)
  "The menu of the tab EVENT is on (see above)."
  (interactive "e")
  (let ((menu (make-sparse-keymap (propertize "Context Menu" 'hide t))))
    (define-key-after menu [close]
      '(menu-item "Close" tab-line-close-tab :help "Close the tab"))
    (define-key-after menu [close-other]
      '(menu-item "Close other tabs" tab-line-close-other-tabs
                  :help "Close all other tabs"))
    (define-key-after menu [split-separator] menu-bar-separator)
    (define-key-after menu [split-right]
      '(menu-item "Split Vertically" +my/tabs-split-right
                  :help "Show this tab in a new pane on the right"))
    (define-key-after menu [split-below]
      '(menu-item "Split Horizontally" +my/tabs-split-below
                  :help "Show this tab in a new pane below"))
    (popup-menu menu event)))

;; No tab line where Doom had none: popups (help, *Messages*...), the dashboard,
;; side panels (treemacs' and LSP's lists).
(defun +my/tabs-off-h ()
  (setq-local tab-line-exclude t)
  (when (bound-and-true-p tab-line-mode)
    (tab-line-mode -1)))

(add-hook '+popup-buffer-mode-hook
          (defun +my/tabs-popup-h ()
            (when +popup-buffer-mode (+my/tabs-off-h))))

(add-hook '+doom-dashboard-mode-hook #'+my/tabs-off-h)
