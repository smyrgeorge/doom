;;; $DOOMDIR/config/tabs.el -*- lexical-binding: t; -*-
;; Tabs per window (Emacs's tab line). Loaded from config.el.

;; ====== VARIABLES ======

;; TABS PER WINDOW
;; Each window has its own tabs, like IntelliJ's split editors: the buffers
;; shown in it, in the order they first were (Emacs's tab line, instead of
;; Doom's centaur-tabs, whose tab groups were per project and shared by every
;; window). A split starts with one tab, the buffer it shows. Files, Claude
;; sessions, dired and magit get tabs; other buffers only while shown.
;; Closing a tab (its ✕, a middle click) takes it off that window, which goes
;; back to the tab it showed before; closing its last tab closes the window
;; (the frame's only one, beside side panels, shows Doom's dashboard instead).
;; A file is closed too once no window has it as a tab any more (asking first
;; if it has unsaved changes). A Claude session only leaves the tab line: close
;; it with its own commands.
;; Tabs look as they did: an icon, a bar on the current one, • when unsaved.
;; Right-clicking a tab: Emacs's Close and Close other tabs, and IntelliJ's
;; Split Vertically (a pane on the right) and Split Horizontally (below): the
;; new pane has only that tab and takes focus; the tab stays where it was too.
(defvar +my/tabs-height 22
  "Height of the tab row in graphical frames, in pixels.")

(defvar +my/tabs-bar-width 2
  "Width of the bar marking the current tab, in pixels.")

;; ====== KEY BINDINGS ======

(map! :n "gt" #'tab-line-switch-to-next-tab
      :n "gT" #'tab-line-switch-to-prev-tab)

;; Cmd+1..8 show the window's tabs 1-8, Cmd+9 its last, as in browsers (Doom
;; had them switch workspaces: M-1..9 and SPC TAB 1..9 still do); where there
;; are no tabs (side panels, popups), they switch workspaces, as before.
(map! :gn "s-1" #'+my/tabs-select-1
      :gn "s-2" #'+my/tabs-select-2
      :gn "s-3" #'+my/tabs-select-3
      :gn "s-4" #'+my/tabs-select-4
      :gn "s-5" #'+my/tabs-select-5
      :gn "s-6" #'+my/tabs-select-6
      :gn "s-7" #'+my/tabs-select-7
      :gn "s-8" #'+my/tabs-select-8
      :gn "s-9" #'+my/tabs-select-9)

;; Cmd+W closes the current tab, like its ✕ (Doom's closed the window, or the
;; workspace with its last window); where there are no tabs (popups, side
;; panels), the window, as before.
(map! "s-w" #'+my/tabs-close-current)

;; The tab menu (right click, see above).
(after! tab-line
  (keymap-set tab-line-tab-map "<tab-line> <down-mouse-3>" #'+my/tabs-context-menu))

;; ====== CODE ======

(defun +my/tabs-p (buffer)
  "Non-nil if BUFFER keeps a tab when it isn't shown (see above)."
  (with-current-buffer buffer
    (or buffer-file-name
        (derived-mode-p 'agent-shell-mode 'dired-mode)
        (doom-real-buffer-p buffer))))

(defun +my/tabs-window-buffers ()
  "The selected window's tabs (see above)."
  (let ((current (window-buffer)))
    (seq-filter (lambda (buffer) (or (eq buffer current) (+my/tabs-p buffer)))
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
  "Take TAB off the selected window's tabs, and close its file if no window
has it any more (see above). Its last tab closes the window, unless it's the
frame's only one (beside side panels), which shows Doom's dashboard instead."
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
    (when (and (buffer-live-p buffer) (buffer-file-name buffer)
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

(after! tab-line
  (setq tab-line-tabs-function #'+my/tabs-window-buffers
        tab-line-tab-name-format-function #'+my/tabs-format
        tab-line-cache-key-function #'+my/tabs-cache-key
        tab-line-close-tab-function #'+my/tabs-close
        tab-line-close-button-show t
        tab-line-new-button-show nil      ; new buffers come from the usual commands
        tab-line-switch-cycling t)
  (dolist (mode '(treemacs-mode +doom-dashboard-mode))
    (add-to-list 'tab-line-exclude-modes mode)))

(add-hook 'doom-first-buffer-hook #'global-tab-line-mode)
