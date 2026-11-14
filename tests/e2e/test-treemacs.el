;;; tests/e2e/test-treemacs.el -*- lexical-binding: t; -*-
;; config/treemacs.el's selection in a GUI Emacs: the sidebar scrolled away
;; from the open file stays where it was (the file still selected), and shows
;; the file again when the buffer changes.

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "treemacs"))))))
  (load (expand-file-name "treemacs/treemacs-autoloads" build) t t))

(setq treemacs-persist-file (+test-tmp-file "treemacs/persist")
      treemacs-last-error-persist-file (+test-tmp-file "treemacs/last-error"))

(+test-load "config/window" "config/treemacs")

(require 'treemacs)
(require 'treemacs-evil)                ; as Doom: j / k in the sidebar
(treemacs-git-mode -1)
(treemacs-filewatch-mode -1)
;; The git poll: not while testing (its buffers changed the buffer list every
;; few seconds, which made the sidebar jump back; the test makes its own).
(when (timerp +my/treemacs--git-poll-timer)
  (cancel-timer +my/treemacs--git-poll-timer))

;; A notch scrolls 3 lines (a bare Emacs: about one).
(setq mouse-wheel-scroll-amount '(3 ((shift) . hscroll))
      mouse-wheel-progressive-speed nil)

;; ====== HELPERS ======

(defvar +test-treemacs--root
  (let ((root (file-name-as-directory (+test-tmp-file "long-project/"))))
    (make-directory root t)
    (dolist (i (number-sequence 1 80))
      (with-temp-file (expand-file-name (format "f%02d.txt" i) root)
        (insert (format "file %d\n" i))))
    (let ((default-directory root))
      (call-process "git" nil nil nil "init" "-q"))
    root))

(defun +test-treemacs--file (n)
  (expand-file-name (format "f%02d.txt" n) +test-treemacs--root))

(defun +test-treemacs--window ()
  (treemacs-get-local-window))

(defun +test-treemacs--label (pos)
  (with-current-buffer (window-buffer (+test-treemacs--window))
    (save-excursion
      (goto-char pos)
      (string-trim (buffer-substring-no-properties (line-beginning-position) (line-end-position))))))

(defun +test-treemacs--highlighted ()
  "The label on the sidebar's highlighted line (hl-line's overlay)."
  (with-current-buffer (window-buffer (+test-treemacs--window))
    (and hl-line-overlay (overlay-buffer hl-line-overlay)
         (+test-treemacs--label (overlay-start hl-line-overlay)))))

(defun +test-treemacs--selected ()
  "The file name of the sidebar's selection (its node, not point's)."
  (with-current-buffer (window-buffer (+test-treemacs--window))
    (and (stringp (car-safe +my/treemacs--selection))
         (file-name-nondirectory (car +my/treemacs--selection)))))

(defun +test-treemacs--shows-p (label)
  "Non-nil if the sidebar's window shows LABEL's line."
  (let ((window (+test-treemacs--window)))
    (with-current-buffer (window-buffer window)
      (save-excursion
        (goto-char (point-min))
        (and (re-search-forward (concat " " (regexp-quote label) "$") nil t)
             (pos-visible-in-window-p (point) window))))))

(defun +test-treemacs--wheel (window n)
  "N wheel notches down over WINDOW, through the command loop."
  (dotimes (_ n)
    (execute-kbd-macro (vector (list 'wheel-down (posn-at-point (window-start window) window))))
    (+test--pump 0.02)))

(defun +test-treemacs--busy ()
  "What Emacs does meanwhile: buffers made and killed (each changes the buffer
list), the sidebar refreshed."
  (dotimes (_ 5)
    (kill-buffer (generate-new-buffer " *busy*"))
    (+test--pump 0.05))
  (+my/treemacs-refresh-all))

(defmacro +test-treemacs (&rest body)
  "BODY with f01.txt open beside the sidebar on the long project, followed."
  (declare (indent 0))
  `(+test-with-reset
     (find-file (+test-treemacs--file 1))
     (save-selected-window
       (let ((inhibit-message t))
         (treemacs-add-and-display-current-project-exclusively)))
     (set-frame-parameter nil '+my/treemacs-followed nil)
     (+my/treemacs-follow-project-soon)
     ;; Followed: f01.txt the selection, the follow's timer done. Not only
     ;; highlighted, which point's line is before (f01.txt's too): the
     ;; follow then came during the test's first steps (its timer later on
     ;; a slow runner, after the first test's startup), and a key in the
     ;; sidebar acted from point.
     (should (+test-wait-for (lambda () (and (equal (+test-treemacs--selected) "f01.txt")
                                             (equal (+test-treemacs--highlighted) "f01.txt")
                                             (not +my/treemacs--follow-timer)))
                             5))
     (unwind-protect (progn ,@body)
       (dolist (buffer (buffer-list))
         (when (with-current-buffer buffer (derived-mode-p 'treemacs-mode))
           (kill-buffer buffer))))))

;; ====== TESTS ======

(ert-deftest e2e-treemacs/scrolled-away-it-stays ()
  "The wheel takes the sidebar to the bottom, away from the open file at the
top: it stays there once scrolling stops, buffers coming and going and the
tree refreshed; the file still highlighted."
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window)))
      (should (+test-treemacs--shows-p "f01.txt"))
      (+test-treemacs--wheel sidebar 30)
      (should (+test-wait-for (lambda () (+test-treemacs--shows-p "f80.txt")) 3))
      (should-not (+test-treemacs--shows-p "f01.txt"))
      (let ((start (window-start sidebar)))
        (+test-treemacs--busy)
        (+test-sleep 1.5)               ; treemacs's follow came 0.2 s idle after
        (should (= (window-start sidebar) start))
        (should-not (+test-treemacs--shows-p "f01.txt"))
        (should (equal (+test-treemacs--highlighted) "f01.txt"))))))

(ert-deftest e2e-treemacs/back-to-the-same-file-it-stays ()
  "Into the sidebar and back to the file (no change of buffer): no jump."
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window))
          (file-window (selected-window)))
      (+test-treemacs--wheel sidebar 30)
      (should (+test-wait-for (lambda () (+test-treemacs--shows-p "f80.txt")) 3))
      (let ((start (window-start sidebar)))
        (select-window sidebar)
        (+test-sleep 0.4)
        (select-window file-window)
        (+test-sleep 1)
        (should (= (window-start sidebar) start))
        (should (equal (+test-treemacs--highlighted) "f01.txt"))))))

(ert-deftest e2e-treemacs/another-buffer-shows-its-file ()
  "Scrolled away, then another file opened: the sidebar shows and selects it;
the first one again: it's shown again."
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window)))
      (+test-treemacs--wheel sidebar 30)
      (should (+test-wait-for (lambda () (+test-treemacs--shows-p "f80.txt")) 3))
      (find-file (+test-treemacs--file 3))
      (should (+test-wait-for (lambda () (and (+test-treemacs--shows-p "f03.txt")
                                              (equal (+test-treemacs--highlighted) "f03.txt")))
                              3))
      (+test-treemacs--wheel sidebar 30)
      (should (+test-wait-for (lambda () (not (+test-treemacs--shows-p "f03.txt"))) 3))
      (switch-to-buffer (get-file-buffer (+test-treemacs--file 1)))
      (should (+test-wait-for (lambda () (and (+test-treemacs--shows-p "f01.txt")
                                              (equal (+test-treemacs--highlighted) "f01.txt")))
                              3)))))

(ert-deftest e2e-treemacs/closing-a-buffer-shows-the-next-file ()
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window)))
      (find-file (+test-treemacs--file 70))
      (should (+test-wait-for (lambda () (equal (+test-treemacs--highlighted) "f70.txt")) 3))
      ;; Scrolled to the top, away from f70.
      (with-selected-window sidebar (goto-char (point-min)) (recenter 0))
      (+test-sleep 0.3)
      (should-not (+test-treemacs--shows-p "f70.txt"))
      ;; Closed: the window shows f01.txt again, which the sidebar shows.
      (kill-buffer (current-buffer))
      (should (+test-wait-for (lambda () (equal (+test-treemacs--highlighted) "f01.txt")) 3))
      (should (+test-treemacs--shows-p "f01.txt")))))

(ert-deftest e2e-treemacs/a-key-in-the-sidebar-acts-on-the-selection ()
  "Scrolled away, then j in the sidebar: from the selection (the file), so the
next file is selected, and shown."
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window)))
      (+test-treemacs--wheel sidebar 30)
      (should (+test-wait-for (lambda () (+test-treemacs--shows-p "f80.txt")) 3))
      (select-window sidebar)
      (execute-kbd-macro "j")
      (should (+test-wait-for (lambda () (equal (+test-treemacs--highlighted) "f02.txt")) 3))
      (should (+test-wait-for (lambda () (+test-treemacs--shows-p "f02.txt")) 3)))))

(ert-deftest e2e-treemacs/a-refresh-after-its-project-switched-under-it ()
  "The sidebar showing two projects, its cursor on a file of the first, which
leaves the workspace without the tree redrawn (as the last workspace's tree,
after SPC p p): a refresh draws the other one, the cursor at the top. It went
up from / forever, Emacs hung (this test then times out)."
  (+test-treemacs
    (let* ((other (let ((root (file-name-as-directory (+test-tmp-file "other-project/"))))
                    (make-directory root t)
                    (with-temp-file (expand-file-name "README.md" root) (insert "# Other\n"))
                    (directory-file-name (file-truename root))))
           (buffer (window-buffer (+test-treemacs--window))))
      (with-selected-window (+test-treemacs--window)
        (let ((inhibit-message t))
          (treemacs-do-add-project-to-workspace other "other-project"))
        (let* ((workspace (treemacs-current-workspace))
               (kept (seq-find (lambda (project) (equal (treemacs-project->path project) other))
                               (treemacs-workspace->projects workspace))))
          (should kept)
          (goto-char (point-min))
          (should (re-search-forward "f01\\.txt$" nil t))
          (should (string-suffix-p "f01.txt" (treemacs-button-get (treemacs-current-button) :path)))
          ;; The first project gone from under the tree, and from its index
          ;; (a tree rebuilt for another project has none of it): walking up
          ;; from f01.txt finds nothing of it.
          (setf (treemacs-workspace->projects workspace) (list kept))
          (let ((first (directory-file-name (file-truename +test-treemacs--root))))
            (maphash (lambda (key _)
                       (when (and (stringp key) (string-prefix-p first key))
                         (remhash key treemacs-dom)))
                     treemacs-dom))
          (treemacs--do-refresh buffer 'all)
          (should (string-match-p "other-project" (+test-treemacs--label (point)))))))))

(defun +test-treemacs--tree-lines ()
  (with-current-buffer (window-buffer (+test-treemacs--window))
    (mapcar #'string-trim (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n" t))))

(ert-deftest e2e-treemacs/back-from-another-project-s-magit ()
  "A deep file, another project's magit (the tree drawn for it), back to the
file: its project's tree drawn again, the file shown and highlighted."
  (require 'magit)
  (+test-with-reset
    (let* ((a (let ((root (file-name-as-directory (+test-tmp-file "magit-a/"))))
                (make-directory (expand-file-name "src/deep" root) t)
                (with-temp-file (expand-file-name "src/deep/x.txt" root) (insert "x\n"))
                (let ((default-directory root)) (call-process "git" nil nil nil "init" "-q"))
                root))
           (b (let ((root (file-name-as-directory (+test-tmp-file "magit-b/"))))
                (make-directory root t)
                (with-temp-file (expand-file-name "b.txt" root) (insert "b\n"))
                (let ((default-directory root)) (call-process "git" nil nil nil "init" "-q"))
                root))
           (x (find-file (expand-file-name "src/deep/x.txt" a)))
           (magit (get-buffer-create "magit: magit-b")))
      (unwind-protect
          (progn
            (save-selected-window
              (let ((inhibit-message t))
                (treemacs-add-and-display-current-project-exclusively)))
            (set-frame-parameter nil '+my/treemacs-followed nil)
            (+my/treemacs-follow-project-soon)
            (should (+test-wait-for (lambda () (equal (+test-treemacs--highlighted) "x.txt")) 5))
            (with-current-buffer magit
              (setq default-directory b)
              (magit-mode))
            (switch-to-buffer magit)
            (should (+test-wait-for (lambda () (member "b.txt" (+test-treemacs--tree-lines))) 5))
            (+test-sleep 0.3)
            (switch-to-buffer x)
            (should (+test-wait-for (lambda () (and (member "x.txt" (+test-treemacs--tree-lines))
                                                    (equal (+test-treemacs--highlighted) "x.txt")))
                                    5))
            ;; Still there a moment later (no follow came after).
            (+test-sleep 2)
            (should (equal (+test-treemacs--highlighted) "x.txt")))
        (kill-buffer magit)
        (dolist (buffer (buffer-list))
          (when (with-current-buffer buffer (derived-mode-p 'treemacs-mode))
            (kill-buffer buffer)))))))

;; ====== WIDTH ======

(defun +test-treemacs--frame-columns (columns)
  "The frame COLUMNS wide, once it is (and redisplayed)."
  (set-frame-width nil columns)
  (should (+test-wait-for (lambda () (= (frame-width) columns)) 3))
  (+test-sleep 0.3))

(ert-deftest e2e-treemacs/width-follows-the-frame-and-the-hand ()
  "At most a quarter of the frame, back to 35 columns as it grows; resized by
hand (SPC w <, its edge dragged): that width, kept once closed and opened
again; panes split beside it leave it."
  (let ((treemacs-width 35)
        (+my/treemacs--width-set-at nil))
    (unwind-protect
        (+test-treemacs
          (+test-treemacs--frame-columns 140)
          (let ((sidebar (+test-treemacs--window)))
            (should (= (window-total-width sidebar) 35))
            (+test-treemacs--frame-columns 60)
            (should (<= (window-total-width sidebar) 15))
            (+test-treemacs--frame-columns 140)
            (should (= (window-total-width sidebar) 35))
            (with-selected-window sidebar
              (let ((this-command 'evil-window-decrease-width))
                (evil-window-decrease-width 5)))
            (+test-sleep 0.3)
            (should (= (window-total-width sidebar) 30))
            (adjust-window-trailing-edge sidebar 10 t)
            (+test-sleep 0.3)
            (should (= (window-total-width sidebar) 40))
            (split-window (window-main-window) nil 'right)
            (balance-windows)
            (+test-sleep 0.3)
            (should (= (window-total-width sidebar) 40))
            (delete-window sidebar)
            (+test-sleep 0.3)
            (save-selected-window
              (let ((inhibit-message t))
                (treemacs-add-and-display-current-project-exclusively)))
            (+test-sleep 0.3)
            (should (= (window-total-width (+test-treemacs--window)) 40))))
      (set-frame-size nil 1000 700 t))))

;; ====== STICKY TITLE ======

(defun +test-treemacs--header (window)
  "WINDOW's header line as shown (nil: none)."
  (when (> (window-header-line-height window) 0)
    (string-trim (+test-treemacs--header-text window))))

(defun +test-treemacs--header-text (window)
  "WINDOW's header line's text, with its properties."
  (format-mode-line (or (window-parameter window 'header-line-format)
                        (buffer-local-value 'header-line-format (window-buffer window)))
                    nil window))

(defun +test-treemacs--wheel-up (window n)
  "N wheel notches up over WINDOW, through the command loop."
  (dotimes (_ n)
    (execute-kbd-macro (vector (list 'wheel-up (posn-at-point (window-start window) window))))
    (+test--pump 0.02)))

(defun +test-treemacs--top (window pos)
  "WINDOW scrolled so POS's line is at its top, the cursor a few lines below
\(out of `scroll-margin', which would scroll it back)."
  (with-selected-window window
    (goto-char pos)
    (let ((start (line-beginning-position)))
      (forward-line 10)
      (set-window-start window start)))
  (+test--pump 0.05))

(defun +test-treemacs--project-name ()
  (file-name-nondirectory (directory-file-name +test-treemacs--root)))

(ert-deftest e2e-treemacs/sticky-title-always ()
  "The project's line is the sidebar's header line: at the top, all the way
while scrolling (never gone, not even for a frame), and back at the top. In
the sidebar's background, starting where the tree does (after the fringe)."
  (+test-treemacs
    (let* ((sidebar (+test-treemacs--window))
           (top (with-current-buffer (window-buffer sidebar) (point-min))))
      (should (+test-wait-for (lambda () (string-match-p "  [^ ]+\\'" (+test-treemacs--label top))) 5))
      (let ((root-line (+test-treemacs--label top)))
        (should (string-prefix-p (+test-treemacs--project-name) root-line))
        (should (equal (+test-treemacs--header sidebar) root-line))
        (dotimes (_ 12)
          (+test-treemacs--wheel sidebar 1)
          (should (equal (+test-treemacs--header sidebar) root-line)))
        (should-not (pos-visible-in-window-p top sidebar))
        (dotimes (_ 14)
          (+test-treemacs--wheel-up sidebar 1)
          (should (equal (+test-treemacs--header sidebar) root-line)))
        (should (+test-wait-for (lambda () (= (window-start sidebar) top)) 3))
        (should (equal (+test-treemacs--header sidebar) root-line)))
      (with-current-buffer (window-buffer sidebar)
        (should (equal (cadr (assq 'header-line-active face-remapping-alist))
                       (list :background (+my/treemacs--background)
                             :box nil :overline nil :underline nil))))
      (should (equal (get-text-property 0 'display (+test-treemacs--header-text sidebar))
                     `(space :width (,(car (window-fringes sidebar)))))))))

(ert-deftest e2e-treemacs/sticky-title-follows-the-branch ()
  "The branch (and ↑↓) changing while scrolled: the title shows it at once."
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window))
          (root (directory-file-name (file-truename +test-treemacs--root))))
      (+test-treemacs--wheel sidebar 5)
      (should (+test-wait-for (lambda () (+test-treemacs--header sidebar)) 3))
      (with-current-buffer (window-buffer sidebar)
        (+my/treemacs--branch-set root (+my/treemacs--branch-suffix "# branch.oid abc\n# branch.head topic\n# branch.ab +3 -0\n")))
      (should (+test-wait-for (lambda () (string-suffix-p "  topic ↑3" (or (+test-treemacs--header sidebar) ""))) 3)))))

(ert-deftest e2e-treemacs/sticky-title-of-the-project-in-view ()
  "Two projects: the title is the one whose files are at the top; a
project's line at the top: that one. (Without following the project,
which would show the current one alone, nor the file, which would scroll back
to it.)"
  (+test-treemacs
    (cl-letf (((symbol-function 'treemacs--do-follow-project) #'ignore)
              ((symbol-function 'treemacs--follow) #'ignore))
      (let* ((other (let ((root (file-name-as-directory (+test-tmp-file "sticky-other/"))))
                      (make-directory root t)
                      (dolist (i (number-sequence 1 60))
                        (with-temp-file (expand-file-name (format "g%02d.txt" i) root) (insert "g\n")))
                      (directory-file-name (file-truename root))))
             (sidebar (+test-treemacs--window))
             (buffer (window-buffer sidebar)))
        (with-selected-window sidebar
          (let ((inhibit-message t))
            (treemacs-do-add-project-to-workspace other "sticky-other"))
          (goto-char (point-min))
          (re-search-forward "sticky-other")
          (unless (eq (treemacs-button-get (treemacs-current-button) :state) 'root-node-open)
            (treemacs-TAB-action)))
        (let ((other-root (with-current-buffer buffer
                            (save-excursion
                              (goto-char (point-min))
                              (re-search-forward "sticky-other")
                              ;; A marker: the branch shown after the first
                              ;; project's name moves the text after it.
                              (copy-marker (line-beginning-position))))))
          (+test-treemacs--top sidebar other-root)
          (should (+test-wait-for (lambda () (equal (+test-treemacs--header sidebar) (+test-treemacs--label other-root))) 3))
          (+test-treemacs--top sidebar (with-current-buffer buffer
                                         (save-excursion (goto-char other-root) (forward-line 5) (point))))
          (+test-wait-for (lambda () (equal (+test-treemacs--header sidebar) (+test-treemacs--label other-root))) 3)
          (should (equal (+test-treemacs--header sidebar) (+test-treemacs--label other-root)))
          (should (equal (+test-treemacs--label (window-start sidebar)) "g05.txt"))
          (+test-treemacs--top sidebar (with-current-buffer buffer
                                         (save-excursion (goto-char other-root) (forward-line -5) (point))))
          (+test-wait-for (lambda () (string-prefix-p (+test-treemacs--project-name)
                                                      (or (+test-treemacs--header sidebar) "")))
                          3)
          (should (string-prefix-p (+test-treemacs--project-name)
                                   (or (+test-treemacs--header sidebar) ""))))))))

(ert-deftest e2e-treemacs/sticky-title-click-goes-to-the-project ()
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window)))
      (+test-treemacs--wheel sidebar 10)
      (should (+test-wait-for (lambda () (+test-treemacs--header sidebar)) 3))
      (should (eq (lookup-key (get-text-property 0 'local-map (+test-treemacs--header-text sidebar))
                              [header-line mouse-1])
                  #'+my/treemacs-sticky-goto))
      (+my/treemacs-sticky-goto (list 'mouse-1 (list sidebar 'header-line '(5 . 5) 0)))
      (should (eq (selected-window) sidebar))
      (should (equal (+test-treemacs--header sidebar) (+test-treemacs--label (point-min))))
      ;; The project's line is hidden: on its first node.
      (should (equal (+test-treemacs--label (point)) ".git"))
      (should (= (window-start sidebar) (point-min))))))

(ert-deftest e2e-treemacs/the-first-project-line-is-hidden ()
  "Not twice at the top: the tree's first line, the project's, hidden (the
title shows it), its first node on the window's first line; still after a
refresh, and when the tree is drawn anew."
  (+test-treemacs
    (let ((sidebar (+test-treemacs--window)))
      (cl-flet ((first-shown ()
                  (with-current-buffer (window-buffer sidebar)
                    (save-excursion
                      (goto-char (window-start sidebar))
                      (while (and (invisible-p (point)) (not (eobp))) (forward-char))
                      (+test-treemacs--label (point))))))
        (should (+test-wait-for (lambda () (equal (first-shown) ".git")) 3))
        (should (string-prefix-p (+test-treemacs--project-name) (+test-treemacs--header sidebar)))
        (+my/treemacs-refresh-all)
        (should (+test-wait-for (lambda () (equal (first-shown) ".git")) 3))
        (with-current-buffer (window-buffer sidebar)
          (let ((inhibit-message t))
            (treemacs--do-refresh (current-buffer) 'all)))
        (should (+test-wait-for (lambda () (equal (first-shown) ".git")) 3))
        ;; Its newline hidden too: no empty line at the top.
        (should (with-current-buffer (window-buffer sidebar)
                  (invisible-p (save-excursion (goto-char (point-min)) (1- (line-beginning-position 2))))))))))
