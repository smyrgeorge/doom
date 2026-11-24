;;; tests/unit/test-window.el -*- lexical-binding: t; -*-
;; config/emacs/window.el: new windows get focus (evil's splits, and windows
;; that `display-buffer' opens for a command), a wider right fringe, the frame
;; maximized at startup.

(+test-load "config/emacs")

;; ====== HELPERS ======

(defmacro +test-window (&rest body)
  "BODY from one window on *scratch*, as a command would run (`this-command'
set), new windows getting focus."
  (declare (indent 0))
  `(+test-with-reset
     (let ((this-command 'test)
           (+my/focus-new-windows t))
       ,@body)))

(defun +test-window--ends ()
  "The command ending, as the command loop has it: `post-command-hook' run."
  (run-hooks 'post-command-hook))

(defun +test-window--fringe-mode-args (&rest bindings)
  "What config/emacs/window.el gives `fringe-mode' when loaded, BINDINGS
\((FUNCTION . DEFINITION)...) standing in meanwhile; :none if not called."
  (let ((got :none)
        (saved (mapcar (lambda (b) (cons (car b) (symbol-function (car b)))) bindings)))
    (unwind-protect
        (progn
          (dolist (b bindings) (fset (car b) (cdr b)))
          (cl-letf (((symbol-function 'fringe-mode) (lambda (value) (setq got value))))
            (+test-load "config/emacs/window")))
      (dolist (s saved) (fset (car s) (cdr s))))
    got))

;; ====== SETTINGS ======

(ert-deftest window/settings-defaults ()
  (should (eq (default-value '+my/focus-new-windows) t))
  (should (= (default-value '+my/right-fringe-padding) 1)))

(ert-deftest window/evil-splits-go-below-and-right ()
  (should (eq evil-split-window-below t))
  (should (eq evil-vsplit-window-right t)))

(ert-deftest window/frame-maximized-at-startup ()
  (should (memq '+my/maximize-frame-h window-setup-hook)))

(ert-deftest window/maximized-not-toggled ()
  "Maximized; already maximized or full screen (a window manager's doing):
left so, not made small again."
  (dolist (case '((nil . maximized) (fullwidth . maximized) (fullheight . maximized)
                  (maximized . maximized) (fullboth . fullboth)))
    (let ((parameter (car case)) set)
      (cl-letf (((symbol-function 'frame-parameter)
                 (lambda (_frame name) (and (eq name 'fullscreen) parameter)))
                ((symbol-function 'set-frame-parameter)
                 (lambda (_frame name value) (when (eq name 'fullscreen) (setq parameter value set t)))))
        (+my/maximize-frame-h)
        (should (eq parameter (cdr case)))
        (should (eq set (not (memq (car case) '(maximized fullboth)))))))))

;; ====== SPLITS (SPC w s / SPC w v) ======

(ert-deftest window/split-focuses-the-window-below ()
  (+test-window
    (let ((old (selected-window)))
      (evil-window-split)
      (should-not (eq (selected-window) old))
      (should (= (length (window-list)) 2))
      (should (> (cadr (window-edges)) (cadr (window-edges old)))))))

(ert-deftest window/vsplit-focuses-the-window-on-the-right ()
  (+test-window
    (let ((old (selected-window)))
      (evil-window-vsplit)
      (should-not (eq (selected-window) old))
      (should (> (car (window-edges)) (car (window-edges old)))))))

;; ====== NEW WINDOWS GET FOCUS ======

(ert-deftest window/advice-on-display-buffer ()
  (should (advice-member-p '+my/focus-new-window-a 'display-buffer)))

(ert-deftest window/new-window-gets-focus ()
  (+test-window
    (let* ((old (selected-window))
           (window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (window-live-p window))
      (should-not (eq window old))
      (+test-window--ends)
      (should (eq (selected-window) window))
      (should (eq (window-buffer) (get-buffer "B"))))))

(ert-deftest window/new-window-below-gets-focus ()
  (+test-window
    (let ((window (display-buffer (+test-buffer "B") '(display-buffer-below-selected))))
      (+test-window--ends)
      (should (eq (selected-window) window)))))

(ert-deftest window/other-window-commands-get-focus ()
  "E.g. `display-buffer' with `inhibit-same-window' (diffs, previews)."
  (+test-window
    (let ((window (display-buffer (+test-buffer "B") '(nil (inhibit-same-window . t)))))
      (should (window-live-p window))
      (+test-window--ends)
      (should (eq (selected-window) window))
      (should (= (length (window-list)) 2)))))

(ert-deftest window/dedicated-new-window-gets-focus ()
  (+test-window
    (let ((window (display-buffer (+test-buffer "B")
                                  '(display-buffer-pop-up-window (dedicated . t)))))
      (should (window-dedicated-p window))
      (+test-window--ends)
      (should (eq (selected-window) window)))))

(ert-deftest window/focus-once-the-command-ends ()
  "While the command runs, its window and buffer stay as they were (it may go
on working in them); the new window selected once it ends, once."
  (+test-window
    (let* ((old (selected-window))
           (a (current-buffer))
           (window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (eq (selected-window) old))
      (should (eq (current-buffer) a))
      (+test-window--ends)
      (should (eq (selected-window) window))
      (should-not +my/focus--pending)
      (should-not (memq #'+my/focus-new-window-h post-command-hook))
      (should-not (memq #'+my/focus-forget-h pre-command-hook))
      ;; The next command's end: nothing more.
      (select-window old)
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/two-new-windows-the-last-one-focused ()
  (+test-window
    (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))
    (let ((last (display-buffer (+test-buffer "C") '(display-buffer-pop-up-window))))
      (+test-window--ends)
      (should (eq (selected-window) last)))))

(ert-deftest window/another-window-the-command-selects-stays ()
  "A command selecting a window of its own after showing one: its choice
kept. The new window gone by its end: nothing selected."
  (+test-window
    (let* ((other (split-window nil nil 'below))
           (window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (window-live-p window))
      (select-window other)
      (+test-window--ends)
      (should (eq (selected-window) other)))
    (let* ((old (selected-window))
           (window (display-buffer (+test-buffer "C") '(display-buffer-pop-up-window))))
      (delete-window window)
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/a-prompt-s-commands-aren-t-its-end ()
  "A command showing a window, then prompting: the commands typed at the
prompt (a level deeper) don't select it; the command's own end does."
  (+test-window
    (let* ((old (selected-window))
           (window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window)))
           (depth (recursion-depth)))
      (cl-letf (((symbol-function 'recursion-depth) (lambda () (1+ depth))))
        (run-hooks 'pre-command-hook)
        (+test-window--ends)
        (should (eq (selected-window) old)))
      (+test-window--ends)
      (should (eq (selected-window) window)))))

(ert-deftest window/a-command-that-failed-forgotten ()
  "A command that never ended (an error: no `post-command-hook'): its window
forgotten as the next command starts, not selected at that one's end."
  (+test-window
    (let ((old (selected-window)))
      (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))
      (run-hooks 'pre-command-hook)
      (should-not +my/focus--pending)
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/the-minibuffer-keeps-the-focus ()
  "A window shown by a command typed in the minibuffer (TAB's
*Completions*): not selected, the focus stays with what's typed."
  (+test-window
    (let* ((old (selected-window))
           (minibuffer-p (symbol-function 'window-minibuffer-p))
           (window nil))
      ;; Shown with the minibuffer selected (asked without a window).
      (cl-letf (((symbol-function 'window-minibuffer-p)
                 (lambda (&optional w) (if w (funcall minibuffer-p w) t))))
        (+my/focus-new-window-a (lambda (&rest _) (setq window (split-window)))
                                (+test-buffer "*Completions*")))
      (should (window-live-p window))
      (should-not +my/focus--pending)
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/checkdoc-reaches-its-prompt ()
  "M-x checkdoc on a file with a docstring problem: its status shown in a new
window, it goes on in the file's (recentring it) up to its prompt, q there."
  (+test-window
    (let ((file (+test-file "window/bad-doc.el"
                            (concat ";;; bad-doc.el --- Test -*- lexical-binding: t; -*-\n\n"
                                    ";;; Commentary:\n\n;;; Code:\n\n"
                                    "(defun bad-doc-f ()\n  \"no capital, no period\")\n\n"
                                    "(provide 'bad-doc)\n;;; bad-doc.el ends here\n"))))
      (with-current-buffer (find-file-noselect file)
        (switch-to-buffer (current-buffer))
        (+test-clear-messages)
        (let ((this-command 'checkdoc)
              (unread-command-events (list ?q)))
          (checkdoc)
          (should (= (+test-messages "should end with punctuation (C-h,f,e,n,p,q)") 1))
          (should-not unread-command-events))
        (set-buffer-modified-p nil)))))

(ert-deftest window/returns-what-display-buffer-does ()
  (+test-window
    (let ((window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (eq window (get-buffer-window "B")))
      (+test-window--ends))
    ;; No window: nil, nothing selected.
    (let ((old (selected-window)))
      (should-not (display-buffer (+test-buffer "C")
                                  '(display-buffer-no-window (allow-no-window . t))))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/a-window-already-there-isnt-selected ()
  "Only windows `display-buffer' creates: one it reuses keeps its place."
  (+test-window
    (let* ((old (selected-window))
           (other (split-window nil nil 'right)))
      (set-window-buffer other (+test-buffer "B"))
      (should (eq (display-buffer "B") other))
      (should (eq (selected-window) old))
      ;; Showing another buffer in it (reused).
      (should (eq (display-buffer (+test-buffer "C") '(display-buffer-use-some-window
                                                       (inhibit-same-window . t)))
                  other))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/same-window-stays-selected ()
  (+test-window
    (let ((old (selected-window)))
      (should (eq (display-buffer (+test-buffer "B") '(display-buffer-same-window)) old))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/side-windows-arent-selected ()
  "Doom's popups, treemacs, which-key, transient menus: side windows."
  (+test-window
    (let* ((old (selected-window))
           (window (display-buffer (+test-buffer "SIDE")
                                   '(display-buffer-in-side-window (side . bottom)))))
      (should (window-live-p window))
      (should (window-parameter window 'window-side))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/child-frames-arent-selected ()
  (+test-window
    (let* ((old (selected-window))
           (frame-parameter (symbol-function 'frame-parameter))
           (window nil))
      ;; The new window's frame: a child frame.
      (cl-letf (((symbol-function 'frame-parameter)
                 (lambda (frame parameter)
                   (if (eq parameter 'parent-frame)
                       (selected-frame)
                     (funcall frame-parameter frame parameter)))))
        (setq window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (window-live-p window))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/no-command-no-focus ()
  "Windows opened from timers or process output (no command running)."
  (+test-window
    (let* ((this-command nil)
           (old (selected-window))
           (window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (window-live-p window))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/from-a-timer-no-focus ()
  (+test-window
    (let ((old (selected-window))
          (window nil))
      (let ((this-command nil))
        (run-at-time 0 nil (lambda ()
                             (setq window (display-buffer (+test-buffer "B")
                                                          '(display-buffer-pop-up-window)))))
        (should (+test-wait-for (lambda () window) 2)))
      (should (window-live-p window))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/setting-off-no-focus ()
  "Code that binds `+my/focus-new-windows' to nil (the Markdown preview)."
  (+test-window
    (let* ((+my/focus-new-windows nil)
           (old (selected-window))
           (window (display-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (window-live-p window))
      (+test-window--ends)
      (should (eq (selected-window) old)))))

(ert-deftest window/pop-to-buffer-still-selects ()
  (+test-window
    (let* ((+my/focus-new-windows nil)
           (window (pop-to-buffer (+test-buffer "B") '(display-buffer-pop-up-window))))
      (should (eq (selected-window) (get-buffer-window window))))))

(ert-deftest window/display-buffer-errors-pass-through ()
  (+test-window
    (let ((old (selected-window)))
      (should-error (display-buffer (+test-buffer "B")
                                    (list (lambda (_buffer _alist) (error "Boom")))))
      (should (eq (selected-window) old))
      (should (= (length (window-list)) 1)))))

;; ====== FRINGES ======

(ert-deftest window/right-fringe-a-character-wider-in-a-terminal ()
  "A terminal has no character width in pixels: 8 more."
  (should (equal (frame-parameter nil 'right-fringe) 16))
  (should (equal (+test-window--fringe-mode-args) '(8 . 16))))

(ert-deftest window/right-fringe-a-character-wider-in-the-gui ()
  (should (equal (+test-window--fringe-mode-args
                  (cons 'display-graphic-p (lambda (&rest _) t))
                  (cons 'frame-char-width (lambda (&rest _) 9)))
                 '(8 . 17))))

(ert-deftest window/right-fringe-padding ()
  (let ((+my/right-fringe-padding 2))
    (should (equal (+test-window--fringe-mode-args) '(8 . 24)))
    (should (equal (+test-window--fringe-mode-args
                    (cons 'display-graphic-p (lambda (&rest _) t))
                    (cons 'frame-char-width (lambda (&rest _) 7)))
                   '(8 . 22))))
  (let ((+my/right-fringe-padding 0))
    (should (equal (+test-window--fringe-mode-args) '(8 . 8))))
  ;; nil: fringes left alone.
  (let ((+my/right-fringe-padding nil))
    (should (eq (+test-window--fringe-mode-args) :none))))

(ert-deftest window/left-fringe-kept ()
  (let ((frame-parameter (symbol-function 'frame-parameter)))
    (should (equal (+test-window--fringe-mode-args
                    (cons 'frame-parameter
                          (lambda (frame parameter)
                            (if (eq parameter 'left-fringe) 12
                              (funcall frame-parameter frame parameter)))))
                   '(12 . 16)))
    ;; None known: Doom's 8.
    (should (equal (+test-window--fringe-mode-args
                    (cons 'frame-parameter
                          (lambda (frame parameter)
                            (unless (eq parameter 'left-fringe)
                              (funcall frame-parameter frame parameter)))))
                   '(8 . 16)))))

(ert-deftest window/right-fringe-once-doom-sets-the-font ()
  "Doom sets the font after config.el: the fringe set again then, and on each
change of font (doom/reload-font, big-font mode), for its width; not in a
terminal, nor with no padding."
  (should (memq #'+my/right-fringe-h after-setting-font-hook))
  (let (got)
    (cl-letf (((symbol-function 'fringe-mode) (lambda (value) (push value got)))
              ((symbol-function 'frame-char-width) (lambda (&rest _) 8)))
      ;; A terminal: nothing.
      (run-hooks 'after-setting-font-hook)
      (should-not got)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
        (run-hooks 'after-setting-font-hook)
        (should (equal got '((8 . 16))))
        ;; Big-font mode: a wider character.
        (cl-letf (((symbol-function 'frame-char-width) (lambda (&rest _) 11)))
          (run-hooks 'after-setting-font-hook))
        (should (equal (car got) '(8 . 19)))
        (let ((+my/right-fringe-padding 2))
          (run-hooks 'after-setting-font-hook))
        (should (equal (car got) '(8 . 24)))
        (let ((+my/right-fringe-padding nil))
          (run-hooks 'after-setting-font-hook))
        (should (= (length got) 3))))))

;; ====== LOADED ======

(ert-deftest window/config-emacs-loads-it ()
  "config.el loads config/emacs.el, which loads this file."
  (dolist (check '(("config.el" load! "config/emacs")
                   ("config/emacs.el" load! "emacs/window")))
    (with-temp-buffer
      (insert-file-contents (expand-file-name (car check) +test-root))
      (let (forms)
        (condition-case nil
            (while t (push (read (current-buffer)) forms))
          (end-of-file))
        (should (member (cdr check) forms))))))
