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

;; MAGIT'S Q (Doom's: `magit-mode-quit-window') deletes a window magit made
;; once no other magit buffer is in its history, whatever else is: a file
;; opened there (one of its tabs) was left open in no tab. A window with
;; other tabs is quit as `quit-window' does: kept, showing the tab before.
(defun +my/tabs-magit-quit-a (fn kill-buffer)
  "`magit-mode-quit-window': a window with other tabs kept (see above)."
  (if (and (bound-and-true-p tab-line-mode)
           (seq-some (lambda (buffer) (not (eq buffer (current-buffer))))
                     (+my/tabs-window-buffers)))
      (quit-window kill-buffer)
    (funcall fn kill-buffer)))

(advice-add 'magit-mode-quit-window :around #'+my/tabs-magit-quit-a)

(defun +my/tabs-in-workspace-p (buffer)
  "Non-nil if BUFFER is the current workspace's (Doom's workspaces), or
without workspaces."
  (or (not (bound-and-true-p persp-mode))
      (not (fboundp 'persp-contain-buffer-p))
      (persp-contain-buffer-p buffer)))

;; THE ORDER KEPT
;; A window's tabs keep the order they came in (tab-line's `tab-line-buffers',
;; a window parameter of buffers), but a workspace switched away from and back
;; lost it: Doom's workspaces (persp-mode) keep a workspace's windows as text
;; (`window-state-get' WRITABLE) and put them back with `window-state-put', and
;; tab-line's parameter is kept only in a state that isn't text. Every pane's
;; current tab went last, the others in the order they were last shown. Their
;; buffers' names are kept too, in a parameter text holds (`+my/tabs-order'),
;; and once windows are put back from a state, the order of each that lost
;; it rebuilt from them: buffers gone since left out, one shown since at the
;; end. A workspace saved to a file and loaded again (+workspace/save) keeps
;; it the same way.
(add-to-list 'window-persistent-parameters '(+my/tabs-order . writable))

(defun +my/tabs--order-keep (buffers)
  "BUFFERS, the selected window's in tab-line's order, kept by name (see
above)."
  (let ((names (delq nil (mapcar #'buffer-name buffers))))
    (unless (equal names (window-parameter nil '+my/tabs-order))
      (set-window-parameter nil '+my/tabs-order names))))

(defun +my/tabs--order-restore-a (fn state &optional window ignore)
  "`window-state-put': then, in its frame, each window's tab order lost
\(tab-line's: not in a state that's text) rebuilt from its buffers' names
\(see above). Only there: a window put back has its state's parameters
alone, its names never another's."
  (let ((frame (window-frame (window-normalize-window window))))
    (prog1 (funcall fn state window ignore)
      (when (frame-live-p frame)
        (dolist (window (window-list frame 'nomini))
          (unless (window-parameter window 'tab-line-buffers)
            (when-let* ((names (window-parameter window '+my/tabs-order)))
              (set-window-parameter window 'tab-line-buffers
                                    (delq nil (mapcar #'get-buffer names))))))))))

(advice-add 'window-state-put :around #'+my/tabs--order-restore-a)

(defun +my/tabs-window-buffers ()
  "The selected window's tabs (see above): the buffers it showed that keep a
tab, the current workspace's only, in the order they came (kept through a
workspace switch: see THE ORDER KEPT). A new workspace (SPC p p) starts in
the window the last one showed, its buffers in the window's history: their
tabs are the other workspace's."
  (let ((current (window-buffer))
        (buffers (tab-line-tabs-fixed-window-buffers)))
    (+my/tabs--order-keep buffers)
    (seq-filter (lambda (buffer)
                  (or (eq buffer current)
                      (and (+my/tabs-p buffer) (+my/tabs-in-workspace-p buffer))))
                buffers)))

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

;; NO GAP BEFORE THE FIRST TAB
;; Tab-line puts its separator before every tab: a space in a graphical frame
;; (`|' on a text terminal), so 8 pixels of the tab line's colour stood
;; between the window's edge and the first tab's bar. In a graphical frame,
;; no separator; each tab but the first starts with that space itself
;; (`+my/tabs-format'), so tabs stay as far apart as they were. A text
;; terminal's tab line is as it was.
(defun +my/tabs-no-separator-a (fn tabs)
  "`tab-line-format-template' with no separator in a graphical frame (see
above)."
  (let ((tab-line-separator (if (display-graphic-p) "" tab-line-separator)))
    (funcall fn tabs)))

(advice-add 'tab-line-format-template :around #'+my/tabs-no-separator-a)

;; A PANE BELOW ANOTHER
;; The tab line of a pane below another is where Emacs drags the pane's top
;; edge: wherever its text had no keymap (and past its end), the pointer was
;; the up-down resize one and a press resized the pane: right after a tab's
;; ✕, on its bar, between tabs, after the last (an Agent UI canvas below its
;; session). Every part of it has a keymap now: a tab's bar and the space
;; after its ✕ the tab's own (a press selects it, as on its label), the
;; space between tabs (`+my/tabs-format'), a text terminal's separators and
;; the rest of the line, filled to the window's edge, `+my/tabs-line-map'.
(defun +my/tabs--filler ()
  "The rest of the tab line, after its tabs, to the window's edge (see
above): past the text's right edge, over the right margin and fringe too."
  (propertize " " 'display '(space :align-to (+ right right-fringe right-margin))
              'keymap +my/tabs-line-map))

(defun +my/tabs-whole-line-a (fn tabs)
  "`tab-line-format-template': its separators with `+my/tabs-line-map',
the rest of the line filled (see above)."
  (let ((tab-line-separator (propertize (or tab-line-separator (if (window-system) " " "|"))
                                        'keymap +my/tabs-line-map)))
    (append (funcall fn tabs) (list (+my/tabs--filler)))))

(advice-add 'tab-line-format-template :around #'+my/tabs-whole-line-a)

;; A TAB TOO WIDE
;; A tab wider than its window was never brought into view: tab-line scrolls
;; to the current tab by finding where a tab starts past the window's width,
;; and the current tab alone ran past it (a long file name in a 30-column
;; pane: a sliver of it shown, or the tabs before it). Nor did it count the
;; scroll arrows it puts before the tabs: the current tab's end, its ✕, was
;; cut. A label too long for its window is shortened, its end kept after "…"
;; (the end of a file's name tells it apart), room left for the icon, the ✕
;; and the arrows; tab-line scrolls with room for the arrows.
(defun +my/tabs--width (string)
  "STRING's width in the tab line: pixels, columns on a text terminal."
  (if (display-graphic-p) (string-pixel-width string) (string-width string)))

(defun +my/tabs--around ()
  "What the tab line shows besides its tabs when they don't all fit: its
separators and scroll arrows."
  (let ((separator (or tab-line-separator (if (window-system) " " "|"))))
    (concat separator tab-line-left-button tab-line-right-button separator)))

(defun +my/tabs--line ()
  "How wide the selected window's tab line is as tab-line's scroll measures
it: the window's body (a text terminal's last column its continuation
mark)."
  (- (window-body-width nil t) (if (display-graphic-p) 0 1)))

(defun +my/tabs--room (tabs)
  "How wide one of TABS may be in the selected window's tab line (see above):
the line less the arrows (with other tabs) and its separator."
  (- (+my/tabs--line)
     (if (cdr tabs) (+my/tabs--width (+my/tabs--around)) 0)
     (+my/tabs--width (or tab-line-separator (if (window-system) " " "|")))))

(defun +my/tabs--fit (label make tabs)
  "(funcall MAKE LABEL): a tab of TABS, its LABEL shortened to fit the window
\(see above), its end kept after \"…\"."
  (let ((tab (funcall make label))
        (room (+my/tabs--room tabs)))
    (if (<= (+my/tabs--width tab) room)
        tab
      ;; The most of its end that fits.
      (let ((low 0) (high (1- (length label))) (best 0))
        (while (<= low high)
          (let ((middle (/ (+ low high) 2)))
            (if (<= (+my/tabs--width (funcall make (concat "…" (substring label (- (length label) middle)))))
                    room)
                (setq best middle low (1+ middle))
              (setq high (1- middle)))))
        (funcall make (concat "…" (substring label (- (length label) best))))))))

(defun +my/tabs-format (tab tabs)
  "TAB's text in the tab line (see above), for `tab-line-tab-name-format-function'."
  (let* ((selected (eq tab (window-buffer)))
         (face (cond ((not selected) 'tab-line-tab-inactive)
                     ((mode-line-window-selected-p) 'tab-line-tab-current)
                     (t 'tab-line-tab)))
         (prefix (run-hook-with-args-until-success '+my/tabs-prefix-functions tab))
         (icon (and (display-graphic-p) (fboundp 'nerd-icons-icon-for-buffer)
                    (with-current-buffer tab
                      (ignore-errors (nerd-icons-icon-for-buffer)))))
         (bar (and (display-graphic-p)
                   (+my/tabs-bar (if selected
                                     (face-background 'highlight nil t)
                                   (face-background face nil t)))))
         ;; Between tabs, not before the first (see NO GAP above); never
         ;; dragged (see A PANE BELOW ANOTHER).
         (gap (and (display-graphic-p) (not (eq tab (car tabs)))
                   (propertize " " 'face 'tab-line 'keymap +my/tabs-line-map))))
    (+my/tabs--fit
     (+my/tabs-label tab tabs)
     (lambda (label)
       (let ((text (concat " "
                           (or prefix "")
                           (if (stringp icon) (concat icon " ") "")
                           label
                           (if (and (buffer-file-name tab) (buffer-modified-p tab))
                               " •" "")
                           " "))
             (close (copy-sequence tab-line-close-button)))
         ;; Appended, so the icon keeps its own colour.
         (add-face-text-property 0 (length text) face t text)
         (add-face-text-property 0 (length close) face t close)
         (concat (or gap "")
                 ;; Its bar and the space after its ✕ the tab's too (see A
                 ;; PANE BELOW ANOTHER).
                 (propertize (concat (if bar (propertize bar 'keymap tab-line-tab-map) "")
                                     (propertize text
                                                 'keymap tab-line-tab-map
                                                 'help-echo (if selected "Current tab"
                                                              "Click to select tab")
                                                 'follow-link 'ignore)
                                     close
                                     (propertize " " 'face face 'keymap tab-line-tab-map))
                             'tab tab
                             'selected selected
                             'mouse-face 'tab-line-highlight))))
     tabs)))

(defun +my/tabs-scroll-room-a (fn strings hscroll)
  "`tab-line-auto-hscroll': tabs that don't all fit scrolled to with room for
the arrows before them (see A TAB TOO WIDE above); the current tab first if
it's wider than the window even shortened (a pane a few columns wide), where
tab-line finds nowhere to scroll to."
  (let ((shown (funcall fn strings hscroll)))
    (if (not (car shown))
        shown
      (set-window-parameter nil 'tab-line-hscroll hscroll)
      (setq shown (with-current-buffer tab-line-auto-hscroll-buffer
                    (setq-local line-prefix
                                (propertize " " 'display `(space :width (,(+my/tabs--width (+my/tabs--around))))))
                    (unwind-protect (funcall fn strings hscroll)
                      (kill-local-variable 'line-prefix))))
      (let ((selected (seq-position strings 'selected
                                    (lambda (string property) (tab-line--get-tab-property property string)))))
        (if (and selected (not (integerp hscroll))
                 (> (+my/tabs--width (nth selected strings))
                    (- (+my/tabs--line) (+my/tabs--width (+my/tabs--around)))))
            (progn (set-window-parameter nil 'tab-line-hscroll (float selected))
                   (list t (float selected)))
          shown)))))

(advice-add 'tab-line-auto-hscroll :around #'+my/tabs-scroll-room-a)

;; THE CACHE
;; Tab-line draws a window's tabs again only when its cache key changes, and
;; that key watches the current tab alone for unsaved changes: saving the
;; others (save all, magit saving the repository's files) left their • on, and
;; changes made elsewhere (another window, a rename by the language server)
;; didn't show one. The key watches every file tab, and the window's width: a
;; pane resized (tiling resizes every pane when one opens or closes) kept the
;; tabs laid out for its old width, the current one off screen until the next
;; tab switch. Laid out for a new width, the tab line scrolls to the current
;; tab afresh (a pane widened showed only the tabs from where it had scrolled
;; to); a scroll of your own (its arrows) stays.
(defun +my/tabs-cache-key (tabs)
  "TABS' cache key (`tab-line-cache-key-function'): tab-line's own first (it
reads them by place), which of them have unsaved changes, and the width the
window's tabs are laid out for."
  (append (tab-line-cache-key-default tabs)
          (list (mapcar (lambda (tab) (and (bufferp tab) (buffer-file-name tab) (buffer-modified-p tab)))
                        tabs)
                (window-body-width nil t))))

(defun +my/tabs-resized-a (&rest _)
  "Before `tab-line-format-template': in a window laid out for another width
\(see above), the tab line's own scroll (a float; one of yours is an integer)
afresh."
  (let ((width (window-body-width nil t)))
    (unless (eql width (window-parameter nil '+my/tabs-width))
      (when (floatp (window-parameter nil 'tab-line-hscroll))
        (set-window-parameter nil 'tab-line-hscroll nil))
      (set-window-parameter nil '+my/tabs-width width))))

(advice-add 'tab-line-format-template :before #'+my/tabs-resized-a)

;; A theme loaded: every window's tabs drawn again. Their bars are images in
;; the old theme's colours, which the cache kept (their text, in faces,
;; follows by itself).
(add-hook 'doom-load-theme-hook
          (defun +my/tabs-theme-h ()
            (when (fboundp 'tab-line-force-update)
              (tab-line-force-update t))))

;; CLOSING A TAB (see above)
(defvar +my/tabs-held-functions nil
  "Functions given a buffer: non-nil if something besides the windows holds
it as a tab (a pane kept hidden: the tiling's fullscreen), so closing its
last tab in a window doesn't close its file.")

(defun +my/tabs-held-p (buffer)
  "Non-nil if a window shows BUFFER or has it as a tab, or something else holds
it so (`+my/tabs-held-functions')."
  (or (seq-some (lambda (window)
                  (or (eq (window-buffer window) buffer)
                      (assq buffer (window-prev-buffers window))))
                (window-list-1 nil 'nomini t))
      (run-hook-with-args-until-success '+my/tabs-held-functions buffer)))

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
