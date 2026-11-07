;;; tests/unit/test-agent-shell-excalidraw.el -*- lexical-binding: t; -*-
;; config/agent-shell/excalidraw.el: drawings for Claude. The keys
;; (C-c C-d and SPC m d in agent-shell; C-c C-c, C-c C-k, M-p, M-n in the
;; drawing), the files (named by the time, in .agent-shell/drawings/, the PNG
;; beside), starting one (beside, for which shell), inserting it (saved, its
;; PNG into that shell's prompt, closed), discarding it (files deleted), the
;; earlier drawings, the notice. No agent and no WebKit: Excalidraw's PNG,
;; the drawing's page and agent-shell's prompt are stubbed (the drawing in
;; WebKit, its real PNG: tests/e2e/test-excalidraw.el).

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

(require 'evil)
(+test-load "config/childframe" "config/banner" "config/webkit" "config/excalidraw" "config/agent-shell")
(require 'agent-shell)

;; ====== HELPERS ======

(defun +test-ase--dir ()
  "A new folder, by its true name."
  (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "ase-") t))))

(defun +test-ase--write (file &optional text)
  (with-temp-file file (insert (or text "<svg/>\n")))
  file)

(defun +test-ase--shell ()
  "A buffer standing for an agent-shell (its mode only, no agent)."
  (let ((buffer (generate-new-buffer "*test agent-shell*")))
    (with-current-buffer buffer
      (setq-local major-mode 'agent-shell-mode))
    buffer))

(defmacro +test-ase--drawing (shell file &rest body)
  "BODY in a buffer standing for drawing FILE for Claude, for SHELL (the
minor mode on, no page); the buffer killed after."
  (declare (indent 2))
  `(let ((buffer (generate-new-buffer "*test drawing*")))
     (unwind-protect
         (with-current-buffer buffer
           (setq buffer-file-name ,file)
           (insert "<svg>own</svg>\n")
           (setq +my/agent-shell-excalidraw--shell ,shell)
           (cl-letf (((symbol-function '+my/banner-show) #'ignore))
             (+my/agent-shell-excalidraw-mode 1))
           ,@body)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer (set-buffer-modified-p nil))
         (kill-buffer buffer)))))

;; ====== KEYS ======

(ert-deftest agent-shell-excalidraw/keys-in-agent-shell ()
  "C-c C-d next to agent-shell's own C-c keys; SPC m d."
  (should (eq (lookup-key agent-shell-mode-map (kbd "C-c C-d")) #'+my/agent-shell-excalidraw))
  (should (eq (lookup-key (evil-get-auxiliary-keymap agent-shell-mode-map 'normal) (kbd "SPC m d"))
              #'+my/agent-shell-excalidraw))
  ;; agent-shell's own stay.
  (should (eq (lookup-key agent-shell-mode-map (kbd "C-c C-c")) #'agent-shell-interrupt)))

(ert-deftest agent-shell-excalidraw/keys-in-the-drawing ()
  (pcase-dolist (`(,key . ,command)
                 '(("C-c C-c" . +my/agent-shell-excalidraw-insert)
                   ("C-c C-k" . +my/agent-shell-excalidraw-discard)
                   ("M-p" . +my/agent-shell-excalidraw-previous)
                   ("M-n" . +my/agent-shell-excalidraw-next)))
    (should (eq (lookup-key +my/agent-shell-excalidraw-mode-map (kbd key)) command))
    (should (commandp command)))
  ;; The drawing's page doesn't take them (Excalidraw's keys, config/excalidraw.el).
  (dolist (key '("C-c" "M-p" "M-n"))
    (should-not (lookup-key +my/excalidraw-mode-map (kbd key))))
  (should (eq (cdr (assq '+my/agent-shell-excalidraw-mode minor-mode-map-alist))
              +my/agent-shell-excalidraw-mode-map)))

(ert-deftest agent-shell-excalidraw/commands ()
  (dolist (command '(+my/agent-shell-excalidraw +my/agent-shell-excalidraw-insert
                     +my/agent-shell-excalidraw-discard +my/agent-shell-excalidraw-previous
                     +my/agent-shell-excalidraw-next))
    (should (commandp command))))

;; ====== FILES ======

(ert-deftest agent-shell-excalidraw/drawings-in-agent-shell-s-folder ()
  (should (equal +my/agent-shell-drawings-subdir "drawings")))

(ert-deftest agent-shell-excalidraw/new-file-named-by-the-time ()
  (let* ((dir (+test-ase--dir))
         (file (+my/agent-shell-excalidraw--new-file dir)))
    (should (equal (file-name-directory file) dir))
    (should (string-match-p "\\`drawing-[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\\.excalidraw\\.svg\\'"
                            (file-name-nondirectory file)))
    (should-not (file-exists-p file))
    ;; Taken: -2, then -3.
    (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) "drawing-2026-11-07-13-05-09")))
      (+test-ase--write (expand-file-name "drawing-2026-11-07-13-05-09.excalidraw.svg" dir))
      (should (equal (file-name-nondirectory (+my/agent-shell-excalidraw--new-file dir))
                     "drawing-2026-11-07-13-05-09-2.excalidraw.svg"))
      (+test-ase--write (expand-file-name "drawing-2026-11-07-13-05-09-2.excalidraw.svg" dir))
      (should (equal (file-name-nondirectory (+my/agent-shell-excalidraw--new-file dir))
                     "drawing-2026-11-07-13-05-09-3.excalidraw.svg")))))

(ert-deftest agent-shell-excalidraw/png-beside-the-drawing ()
  (should (equal (+my/agent-shell-excalidraw--png-file "/p/.agent-shell/drawings/drawing-1.excalidraw.svg")
                 "/p/.agent-shell/drawings/drawing-1.png")))

(ert-deftest agent-shell-excalidraw/earlier-drawings-newest-first ()
  (let* ((dir (+test-ase--dir))
         (own (expand-file-name "drawing-2026-11-07-10-00-00.excalidraw.svg" dir)))
    (dolist (name '("drawing-2026-11-06-09-00-00.excalidraw.svg" "drawing-2026-11-07-09-00-00.excalidraw.svg"
                    "drawing-2026-11-07-12-00-00.excalidraw.svg"
                    ;; Not drawings: PNGs, other files.
                    "drawing-2026-11-07-09-00-00.png" "notes.md"))
      (+test-ase--write (expand-file-name name dir)))
    (+test-ase--write own)
    (+test-ase--drawing nil own
      (should (equal (mapcar #'file-name-nondirectory (+my/agent-shell-excalidraw--earlier-files))
                     '("drawing-2026-11-07-12-00-00.excalidraw.svg" "drawing-2026-11-07-09-00-00.excalidraw.svg"
                       "drawing-2026-11-06-09-00-00.excalidraw.svg"))))))

;; ====== STARTING ======

(ert-deftest agent-shell-excalidraw/for-this-shell-or-agent-shell-s ()
  (let ((shell (+test-ase--shell)))
    (unwind-protect
        (progn
          (with-current-buffer shell
            (should (eq (+my/agent-shell-excalidraw--shell-here) shell)))
          ;; Elsewhere: the one agent-shell picks, none if none.
          (with-temp-buffer
            (cl-letf (((symbol-function 'agent-shell--shell-buffer) (lambda (&rest _) shell)))
              (should (eq (+my/agent-shell-excalidraw--shell-here) shell)))
            (cl-letf (((symbol-function 'agent-shell--shell-buffer) (lambda (&rest _) (error "No shell"))))
              (should-not (+my/agent-shell-excalidraw--shell-here)))))
      (kill-buffer shell))))

(ert-deftest agent-shell-excalidraw/needs-a-shell-and-excalidraw ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'agent-shell--shell-buffer) (lambda (&rest _) nil)))
      (should (equal (cadr (should-error (+my/agent-shell-excalidraw) :type 'user-error))
                     "No agent-shell to draw for: SPC o c starts one"))))
  (let ((shell (+test-ase--shell)))
    (unwind-protect
        (with-current-buffer shell
          (cl-letf (((symbol-function '+my/webkit-p) (lambda () nil))
                    ((symbol-function '+my/excalidraw-open) (lambda (&rest _) (error "Opened"))))
            (should (string-match-p "GUI Emacs with xwidgets"
                                    (cadr (should-error (+my/agent-shell-excalidraw) :type 'user-error))))))
      (kill-buffer shell))))

(ert-deftest agent-shell-excalidraw/a-new-drawing-beside ()
  "In agent-shell's drawings folder, opened beside as a new one (saved once its
page made it), the mode on, for this shell."
  (let* ((dir (+test-ase--dir))
         (shell (+test-ase--shell))
         (opened nil)
         (drawing (generate-new-buffer "*test new drawing*")))
    (unwind-protect
        (with-current-buffer shell
          (cl-letf (((symbol-function '+my/webkit-p) (lambda () t))
                    ((symbol-function '+my/excalidraw-ensure) (lambda () t))
                    ((symbol-function 'agent-shell--dot-subdir)
                     (lambda (subdir) (let ((d (expand-file-name subdir dir))) (make-directory d t) d)))
                    ((symbol-function '+my/excalidraw-open)
                     (lambda (file &optional save-new action)
                       (setq opened (list file save-new action))
                       (with-current-buffer drawing (setq buffer-file-name file))
                       drawing))
                    ((symbol-function '+my/banner-show) #'ignore))
            (should (eq (+my/agent-shell-excalidraw) drawing))
            (should (equal (file-name-directory (car opened)) (expand-file-name "drawings/" dir)))
            (should (string-suffix-p ".excalidraw.svg" (car opened)))
            (should (eq (cadr opened) t))
            ;; On the shell's left.
            (should (equal (alist-get 'direction (nth 2 opened)) 'left))
            (with-current-buffer drawing
              (should +my/agent-shell-excalidraw-mode)
              (should (eq +my/agent-shell-excalidraw--shell shell))
              (should-not +my/agent-shell-excalidraw--earlier))))
      (kill-buffer drawing)
      (kill-buffer shell))))

(ert-deftest agent-shell-excalidraw/shown-on-the-shell-s-left ()
  "In the window left of the shell's (it shows its own buffer again after);
without one, a new window split off to the left of the shell's."
  (+test-with-reset
    (let* ((shell (+test-ase--shell))
           (code (generate-new-buffer "*test code*"))
           (drawing (generate-new-buffer "*test drawing on the left*")))
      (unwind-protect
          (let* ((left (selected-window))
                 (right (split-window-right)))
            (set-window-buffer left code)
            (set-window-buffer right shell)
            (select-window right)
            ;; A window on its left: that one.
            (should (eq (display-buffer drawing (+my/agent-shell-excalidraw--where shell)) left))
            (should (eq (window-buffer left) drawing))
            (should (= (length (window-list)) 2))
            (quit-window nil left)
            (should (eq (window-buffer left) code))
            ;; None: a new one, on its left.
            (delete-window left)
            (should (eq (window-buffer (selected-window)) shell))
            (let ((new (display-buffer drawing (+my/agent-shell-excalidraw--where shell))))
              (should (= (length (window-list)) 2))
              (should (eq (window-in-direction 'left (get-buffer-window shell)) new))
              (quit-window nil new)
              (should-not (window-live-p new))))
        (kill-buffer drawing)
        (kill-buffer code)
        (kill-buffer shell)))))

(ert-deftest agent-shell-excalidraw/a-notice-says-what-to-do ()
  (let* ((shown nil)
         (closed nil))
    (cl-letf (((symbol-function '+my/banner-show)
               (lambda (id text &rest args) (setq shown (list id text args))))
              ((symbol-function '+my/banner-close) (lambda (id) (push id closed))))
      (with-temp-buffer
        (+my/agent-shell-excalidraw-mode 1)
        (should (eq (nth 0 shown) 'agent-shell-excalidraw))
        (should (equal (nth 1 shown)
                       "Drawing for Claude: C-c C-c inserts it into the prompt, C-c C-k discards it, M-p / M-n earlier drawings"))
        (should (equal (plist-get (nth 2 shown) :actions)
                       '(("Insert into the prompt" . +my/agent-shell-excalidraw-insert)
                         ("Discard" . +my/agent-shell-excalidraw-discard))))
        (+my/agent-shell-excalidraw-mode -1)
        (should (equal closed '(agent-shell-excalidraw)))))))

;; ====== INSERTING ======

(ert-deftest agent-shell-excalidraw/inserted-into-its-shell-s-prompt ()
  "Saved, its PNG beside it into its shell's prompt (as agent-shell shows a
screenshot), the drawing closed."
  (let* ((dir (+test-ase--dir))
         (file (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir)))
         (shell (+test-ase--shell))
         (saved nil) (png-asked nil) (context nil) (inserted nil) (closed nil))
    (unwind-protect
        (+test-ase--drawing shell file
          (set-buffer-modified-p t)
          (cl-letf (((symbol-function 'save-buffer) (lambda (&rest _) (setq saved t) (set-buffer-modified-p nil)))
                    ((symbol-function '+my/excalidraw-png) (lambda (png) (setq png-asked png) png))
                    ((symbol-function '+my/agent-shell-excalidraw--close) (lambda (buffer) (setq closed buffer)))
                    ((symbol-function 'agent-shell--get-files-context)
                     (lambda (&rest args) (setq context args) "<the image>"))
                    ((symbol-function 'agent-shell-insert)
                     (lambda (&rest args) (setq inserted (cons (current-buffer) args)))))
            (let ((drawing (current-buffer)))
              (should (equal (+my/agent-shell-excalidraw-insert) (expand-file-name "drawing-1.png" dir)))
              (should saved)
              (should (equal png-asked (expand-file-name "drawing-1.png" dir)))
              (should (eq closed drawing))
              (should (equal context (list :files (list (expand-file-name "drawing-1.png" dir)))))
              ;; From the shell, into it.
              (should (eq (car inserted) shell))
              (should (equal (cdr inserted) (list :text "<the image>" :shell-buffer shell))))))
      (kill-buffer shell))))

(ert-deftest agent-shell-excalidraw/not-inserted-when-it-can-t-be ()
  (let* ((dir (+test-ase--dir))
         (file (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir)))
         (shell (+test-ase--shell)))
    ;; Not a drawing for Claude.
    (with-temp-buffer
      (should-error (+my/agent-shell-excalidraw-insert) :type 'user-error))
    ;; Its shell gone.
    (+test-ase--drawing (generate-new-buffer "*gone*") file
      (kill-buffer +my/agent-shell-excalidraw--shell)
      (should (equal (cadr (should-error (+my/agent-shell-excalidraw-insert) :type 'user-error))
                     "Its agent-shell is gone")))
    ;; Nothing drawn (Excalidraw's PNG says so): the drawing stays open,
    ;; nothing inserted.
    (unwind-protect
        (+test-ase--drawing shell file
          (cl-letf (((symbol-function '+my/excalidraw-png) (lambda (_) (user-error "Nothing is drawn")))
                    ((symbol-function 'agent-shell-insert) (lambda (&rest _) (error "Inserted"))))
            (should-error (+my/agent-shell-excalidraw-insert) :type 'user-error)
            (should (buffer-live-p (current-buffer)))
            (should +my/agent-shell-excalidraw-mode)))
      (kill-buffer shell))))

;; ====== DISCARDING ======

(ert-deftest agent-shell-excalidraw/discarded-files-deleted ()
  (let* ((dir (+test-ase--dir))
         (file (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir)))
         (png (+test-ase--write (expand-file-name "drawing-1.png" dir)))
         (other (+test-ase--write (expand-file-name "drawing-0.excalidraw.svg" dir)))
         (drawing nil))
    (+test-ase--drawing nil file
      (setq drawing (current-buffer))
      (set-buffer-modified-p t)
      (+my/agent-shell-excalidraw-discard)
      ;; Closed without asking (its changes dropped), its files gone, the
      ;; others kept.
      (should-not (buffer-live-p drawing)))
    (should-not (file-exists-p file))
    (should-not (file-exists-p png))
    (should (file-exists-p other))))

(ert-deftest agent-shell-excalidraw/closing-closes-its-window ()
  (+test-with-reset
    (let* ((buffer (generate-new-buffer "*test drawing window*"))
           (window (display-buffer buffer '(display-buffer-pop-up-window))))
      (should (window-live-p window))
      (with-current-buffer buffer (set-buffer-modified-p t))
      (+my/agent-shell-excalidraw--close buffer)
      (should-not (buffer-live-p buffer))
      (should-not (window-live-p window)))))

;; ====== EARLIER DRAWINGS ======

(ert-deftest agent-shell-excalidraw/earlier-drawings-in-turn ()
  "M-p shows older ones in turn, M-n newer ones; past the newest, its own
again."
  (let* ((dir (+test-ase--dir))
         (own (+test-ase--write (expand-file-name "drawing-3.excalidraw.svg" dir)))
         (shown nil))
    (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir) "<svg>one</svg>\n")
    (+test-ase--write (expand-file-name "drawing-2.excalidraw.svg" dir) "<svg>two</svg>\n")
    (+test-ase--drawing nil own
      (cl-letf (((symbol-function '+my/excalidraw-replace)
                 (lambda (text)
                   (setq shown text)
                   (let ((inhibit-read-only t)) (erase-buffer) (insert text)))))
        (+test-clear-messages)
        ;; Not past its own.
        (should (equal (cadr (should-error (+my/agent-shell-excalidraw-next) :type 'user-error))
                       "No newer drawing"))
        (+my/agent-shell-excalidraw-previous)
        (should (equal shown "<svg>two</svg>\n"))
        (should (= (+test-messages "^Earlier drawing 1 of 2: drawing-2\\.excalidraw\\.svg$") 1))
        (+my/agent-shell-excalidraw-previous)
        (should (equal shown "<svg>one</svg>\n"))
        (should (equal (cadr (should-error (+my/agent-shell-excalidraw-previous) :type 'user-error))
                       "No older drawing"))
        (+my/agent-shell-excalidraw-next)
        (should (equal shown "<svg>two</svg>\n"))
        ;; Past the newest: its own drawing, as it was.
        (+my/agent-shell-excalidraw-next)
        (should (equal shown "<svg>own</svg>\n"))
        (should-not +my/agent-shell-excalidraw--earlier)
        (should (= (+test-messages "^This drawing again$") 1))))))

(ert-deftest agent-shell-excalidraw/no-earlier-drawings ()
  (let* ((dir (+test-ase--dir))
         (own (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir))))
    (+test-ase--drawing nil own
      (cl-letf (((symbol-function '+my/excalidraw-replace) (lambda (_) (error "Replaced"))))
        (should (equal (cadr (should-error (+my/agent-shell-excalidraw-previous) :type 'user-error))
                       "No earlier drawings"))))
    (with-temp-buffer
      (should-error (+my/agent-shell-excalidraw-previous) :type 'user-error))))
