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
     (should (+test-wait-for (lambda () (equal (+test-treemacs--highlighted) "f01.txt")) 5))
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
