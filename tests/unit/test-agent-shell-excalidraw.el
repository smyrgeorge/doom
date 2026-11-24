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
(+test-load "config/emacs/childframe" "config/banner" "config/webkit" "config/excalidraw" "config/agent-shell")
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

;; DRAWINGS' FILES
;; Excalidraw's scene in an .excalidraw.svg: base64 JSON whose "encoded" is
;; the scene's JSON, zlib's (made by Python's zlib, as Excalidraw's pako).
(defconst +test-ase--blank
  "eyJ2ZXJzaW9uIjoiMSIsImVuY29kaW5nIjoiYnN0cmluZyIsImNvbXByZXNzZWQiOnRydWUsImVuY29kZWQiOiJ4nKtWKqksSFWyUlBKrUhOzMlMKUosV9JRUCpLLSrOzM9cdTAwMDNKXHUwMDE4XHUwMDAxecX5pUXJYFUlqcUlIPnUnNTc1LySYqBYdCyQn1hQXHUwMDEwXFySWFx1MDAwMlJTXVx1MDAwYuSnZeakXHUwMDE2gzm1XHUwMDAwKrlcdTAwMWZ6In0="
  "A scene without elements.")

(defconst +test-ase--rectangle
  "eyJ2ZXJzaW9uIjoiMSIsImVuY29kaW5nIjoiYnN0cmluZyIsImNvbXByZXNzZWQiOnRydWUsImVuY29kZWQiOiJ4nDWMsVx1MDAwZcIwXGZEf6XKzFx1MDAwMIzM/Fx1MDAwMSNiiNJrYymkUWxoqyr/jl3R6fzeWbc5WVx1MDAwYtytc1iCT9RXP7tT576oTFPW4qrE06eG/UvAYj1cdTAwMTLeyMLqnpuj3rpqxTFXXHUwMDExxOcxweSi5qy5/nOmXqLeXHUwMDE3g1xiXHUwMDFho1x1MDAxY0R8122BLVx1MDAwZT4x2kutL+UhXmx5a8pcdTAwMDMl8Fx1MDAwZe1cdTAwMDcxdDpcdTAwMTQifQ=="
  "A scene with a rectangle.")

(defconst +test-ase--deleted
  "eyJ2ZXJzaW9uIjoiMSIsImVuY29kaW5nIjoiYnN0cmluZyIsImNvbXByZXNzZWQiOnRydWUsImVuY29kZWQiOiJ4nDWMsVx1MDAwZcIwXGZEf6XKzFx1MDAwMIzM/Fx1MDAwMSNiiJKjsVx1MDAxNNIocWmrKP+OXdHp/N5Z11xmb1x1MDAxOeY2XHUwMDE4rM5G8sUu5jSYL0qlKUlxXHUwMDE1qtNcXNz+xaisPVwiPkhcXMU9myGvXdHimCtwbNNcdTAwMTihclx1MDAxNXOW3P65kOcg90UhgMbAXHUwMDA3Ub3LNkNcdTAwMTe5zOgvkTbnXHUwMDA3W9bh1oXfXHUwMDE0UXfoP/jQOckifQ=="
  "A scene with a rectangle deleted.")

(defun +test-ase--svg (payload)
  "An .excalidraw.svg's text with PAYLOAD as its scene."
  (format "<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\">
  <!-- svg-source:excalidraw -->
  <!-- payload-type:application/vnd.excalidraw+json --><!-- payload-version:2 --><!-- payload-start -->%s<!-- payload-end -->
</svg>
" payload))

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

(ert-deftest agent-shell-excalidraw/blank-drawings ()
  "Nothing drawn: no elements in its scene, or only deleted ones. A file it
can't tell of (no scene in it, a broken one): not blank."
  (let ((dir (+test-ase--dir)))
    (cl-flet ((blank-p (name text)
                (+my/agent-shell-excalidraw--blank-p (+test-ase--write (expand-file-name name dir) text))))
      (should (blank-p "blank.excalidraw.svg" (+test-ase--svg +test-ase--blank)))
      (should (blank-p "deleted.excalidraw.svg" (+test-ase--svg +test-ase--deleted)))
      (should-not (blank-p "drawn.excalidraw.svg" (+test-ase--svg +test-ase--rectangle)))
      ;; Not compressed.
      (should (blank-p "plain.excalidraw.svg"
                       (+test-ase--svg (base64-encode-string
                                        "{\"version\":\"1\",\"encoding\":\"bstring\",\"compressed\":false,\"encoded\":\"{\\\"elements\\\":[]}\"}"
                                        t))))
      (should-not (blank-p "none.excalidraw.svg" "<svg/>\n"))
      (should-not (blank-p "broken.excalidraw.svg" (+test-ase--svg "bm90IGpzb24=")))
      (should-not (+my/agent-shell-excalidraw--blank-p (expand-file-name "missing.excalidraw.svg" dir))))))

(ert-deftest agent-shell-excalidraw/earlier-drawings-not-blank-ones ()
  (let* ((dir (+test-ase--dir))
         (own (+test-ase--write (expand-file-name "drawing-3.excalidraw.svg" dir))))
    (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir) (+test-ase--svg +test-ase--rectangle))
    (+test-ase--write (expand-file-name "drawing-2.excalidraw.svg" dir) (+test-ase--svg +test-ase--blank))
    (+test-ase--drawing nil own
      (should (equal (mapcar #'file-name-nondirectory (+my/agent-shell-excalidraw--earlier-files))
                     '("drawing-1.excalidraw.svg"))))))

(ert-deftest agent-shell-excalidraw/closed-blank-leaves-no-file ()
  "Closed without being inserted (its tab, SPC b k): its file deleted if
nothing is drawn in it; kept if something is, or once inserted."
  (let ((dir (+test-ase--dir)))
    (pcase-dolist (`(,name ,text ,inserted ,kept)
                   `(("blank" ,(+test-ase--svg +test-ase--blank) nil nil)
                     ("drawn" ,(+test-ase--svg +test-ase--rectangle) nil t)
                     ("inserted" ,(+test-ase--svg +test-ase--blank) t t)))
      (let ((file (+test-ase--write (expand-file-name (concat name ".excalidraw.svg") dir) text)))
        (+test-ase--drawing nil file
          (setq +my/agent-shell-excalidraw--inserted inserted)
          (set-buffer-modified-p nil)
          (kill-buffer))
        (should (equal (list name (file-exists-p file)) (list name kept)))))
    ;; Not a drawing for the agent (the mode off): nothing deleted.
    (let ((file (+test-ase--write (expand-file-name "other.excalidraw.svg" dir) (+test-ase--svg +test-ase--blank))))
      (+test-ase--drawing nil file
        (cl-letf (((symbol-function '+my/banner-close) #'ignore))
          (+my/agent-shell-excalidraw-mode -1))
        (set-buffer-modified-p nil)
        (kill-buffer))
      (should (file-exists-p file)))))

(ert-deftest agent-shell-excalidraw/earlier-drawings-never-itself ()
  "The drawing itself is never among its earlier ones, though its file is
read meanwhile (its access time changing between two looks at it: it was
listed, file-equal-p comparing every attribute)."
  (let* ((dir (+test-ase--dir))
         (own (expand-file-name "drawing-2026-11-07-10-00-00.excalidraw.svg" dir))
         (other (expand-file-name "drawing-2026-11-07-09-00-00.excalidraw.svg" dir))
         (attributes (symbol-function 'file-attributes))
         (reads 0))
    (+test-ase--write other)
    (+test-ase--write own)
    (+test-ase--drawing nil own
      ;; Each look at it: a later access time, as if read meanwhile.
      (cl-letf (((symbol-function 'file-attributes)
                 (lambda (file &rest args)
                   (let ((attrs (apply attributes file args)))
                     (when attrs
                       (setf (nth 4 attrs) (time-add (nth 4 attrs) (cl-incf reads))))
                     attrs))))
        (should (equal (+my/agent-shell-excalidraw--earlier-files) (list other)))))))

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
                       "Drawing: C-c C-c inserts, C-c C-k discards, M-p / M-n earlier drawings"))
        (should (equal (plist-get (nth 2 shown) :actions)
                       '(("Insert" . +my/agent-shell-excalidraw-insert)
                         ("Discard" . +my/agent-shell-excalidraw-discard))))
        (+my/agent-shell-excalidraw-mode -1)
        (should (equal closed '(agent-shell-excalidraw)))))))

(ert-deftest agent-shell-excalidraw/its-notice-fits-its-pane ()
  "At 70 columns (it opens in half a frame): both keys beside the buttons.
At 40 (on two rows): the buttons and ✕ whole."
  (let ((shown nil))
    (cl-letf (((symbol-function '+my/banner-show)
               (lambda (id text &rest args) (setq shown (list id text (plist-get args :actions) 'info))))
              ((symbol-function '+my/banner-close) #'ignore)
              ((symbol-function 'nerd-icons-codicon) (lambda (_) "I")))
      (with-temp-buffer
        (+my/agent-shell-excalidraw-mode 1)
        (let ((row (substring-no-properties (+my/banner--row shown (current-buffer) nil nil 70))))
          (should-not (string-search "\n" row))
          (should (string-match-p "C-c C-c .*C-c C-k.*Insert    Discard  ✕" row)))
        (let ((rows (split-string (substring-no-properties
                                   (+my/banner--row shown (current-buffer) nil nil 40))
                                  "\n")))
          (should (string-match-p "\\`      Insert    Discard +✕ +\\'" (cadr rows))))))))

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

(ert-deftest agent-shell-excalidraw/inserted-with-a-change-made-just-before ()
  "A change made just before C-c C-c, not marked modified yet: the page's
last change brought into the buffer first, then saved."
  (let* ((dir (+test-ase--dir))
         (file (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir)))
         (shell (+test-ase--shell))
         (calls nil))
    (unwind-protect
        (+test-ase--drawing shell file
          (set-buffer-modified-p nil)
          (cl-letf (((symbol-function '+my/excalidraw-flush)
                     (lambda () (push 'flushed calls) (set-buffer-modified-p t) t))
                    ((symbol-function 'save-buffer)
                     (lambda (&rest _) (push 'saved calls) (set-buffer-modified-p nil)))
                    ((symbol-function '+my/excalidraw-png) (lambda (png) (push 'png calls) png))
                    ((symbol-function '+my/agent-shell-excalidraw--close) #'ignore)
                    ((symbol-function 'agent-shell--get-files-context) (lambda (&rest _) "<the image>"))
                    ((symbol-function 'agent-shell-insert) #'ignore))
            (+my/agent-shell-excalidraw-insert)
            (should (equal (reverse calls) '(flushed saved png)))))
      (kill-buffer shell))))

(ert-deftest agent-shell-excalidraw/not-inserted-when-it-can-t-be ()
  (let* ((dir (+test-ase--dir))
         (file (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir)))
         (shell (+test-ase--shell)))
    ;; Not a drawing for the agent.
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

(ert-deftest agent-shell-excalidraw/earlier-drawings-keep-a-change-made-just-before ()
  "M-p right after a change: the page's last change brought into the buffer
first (its export on its way would be dropped), so M-n shows it again. Only
when its own drawing is taken: not from one earlier drawing to the next."
  (let* ((dir (+test-ase--dir))
         (own (+test-ase--write (expand-file-name "drawing-3.excalidraw.svg" dir)))
         (shown nil)
         (flushes 0))
    (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir) "<svg>one</svg>\n")
    (+test-ase--write (expand-file-name "drawing-2.excalidraw.svg" dir) "<svg>two</svg>\n")
    (+test-ase--drawing nil own
      (cl-letf (((symbol-function '+my/excalidraw-replace)
                 (lambda (text)
                   (setq shown text)
                   (let ((inhibit-read-only t)) (erase-buffer) (insert text))))
                ((symbol-function '+my/excalidraw-flush)
                 (lambda ()
                   (cl-incf flushes)
                   ;; The page's last change, come in.
                   (let ((inhibit-read-only t)) (erase-buffer) (insert "<svg>changed</svg>\n"))
                   t)))
        (+my/agent-shell-excalidraw-previous)
        (should (= flushes 1))
        (should (equal shown "<svg>two</svg>\n"))
        (+my/agent-shell-excalidraw-previous)
        (should (= flushes 1))
        (+my/agent-shell-excalidraw-next)
        (+my/agent-shell-excalidraw-next)
        (should (equal shown "<svg>changed</svg>\n"))
        (should (= flushes 1))))))

(ert-deftest agent-shell-excalidraw/no-earlier-drawings ()
  (let* ((dir (+test-ase--dir))
         (own (+test-ase--write (expand-file-name "drawing-1.excalidraw.svg" dir))))
    (+test-ase--drawing nil own
      (cl-letf (((symbol-function '+my/excalidraw-replace) (lambda (_) (error "Replaced"))))
        (should (equal (cadr (should-error (+my/agent-shell-excalidraw-previous) :type 'user-error))
                       "No earlier drawings"))))
    (with-temp-buffer
      (should-error (+my/agent-shell-excalidraw-previous) :type 'user-error))))
