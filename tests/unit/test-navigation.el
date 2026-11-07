;;; tests/unit/test-navigation.el -*- lexical-binding: t; -*-
;; config/navigation.el: Cmd+B (declaration or usages), Cmd+[ / Cmd+] (back /
;; forward), M-[ / M-] (buffers, GUI only).

(+test-load "config/navigation")

;; ====== HELPERS ======

(defmacro +test-navigation--visiting (name content &rest body)
  "BODY in a buffer visiting NAME (in the temp folder) with CONTENT, killed
after. No version control (nothing runs git)."
  (declare (indent 2))
  `(let* ((vc-handled-backends nil)
          (file (+test-file ,name ,content))
          (buffer (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buffer ,@body)
       (when (buffer-live-p buffer)
         (let ((kill-buffer-query-functions nil))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

;; ====== KEYS ======

(ert-deftest navigation/keys-global ()
  "Cmd+B, Cmd+[ and Cmd+] in the global map."
  (should (eq (lookup-key global-map (kbd "s-b")) #'+my/goto-declaration-or-usages))
  (should (eq (lookup-key global-map (kbd "s-[")) #'better-jumper-jump-backward))
  (should (eq (lookup-key global-map (kbd "s-]")) #'better-jumper-jump-forward)))

(ert-deftest navigation/keys-in-every-evil-state ()
  "No evil state shadows them (code, normal / insert / visual)."
  (+test-with-reset
    (switch-to-buffer (+test-buffer "code.el" "(foo bar)\n" #'emacs-lisp-mode))
    (dolist (state '(normal insert visual emacs))
      (evil-change-state state)
      (should (eq (key-binding (kbd "s-b")) #'+my/goto-declaration-or-usages))
      (should (eq (key-binding (kbd "s-[")) #'better-jumper-jump-backward))
      (should (eq (key-binding (kbd "s-]")) #'better-jumper-jump-forward)))))

(ert-deftest navigation/gui-only-menu-item ()
  "A menu item whose filter gives the command in the GUI, nothing in a terminal."
  (let* ((item (+my/gui-only #'previous-buffer))
         (filter (plist-get (nthcdr 3 item) :filter)))
    (should (eq (car item) 'menu-item))
    (should (equal (nth 1 item) ""))
    (should (eq (nth 2 item) #'previous-buffer))
    (should (functionp filter))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (should (eq (funcall filter #'previous-buffer) #'previous-buffer)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
      (should-not (funcall filter #'previous-buffer)))))

(ert-deftest navigation/buffer-keys-gui-only ()
  "M-[ / M-]: previous / next buffer in the GUI; unbound in a terminal, where
they're ESC [ / ESC ], the start of escape sequences."
  (+test-with-reset
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (should (eq (key-binding (kbd "M-[")) #'previous-buffer))
      (should (eq (key-binding (kbd "M-]")) #'next-buffer)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) nil)))
      (should-not (key-binding (kbd "M-[")))
      (should-not (key-binding (kbd "M-]")))
      (should-not (key-binding [27 ?\[]))
      (should-not (key-binding [27 ?\]])))))

(ert-deftest navigation/buffer-keys-switch-buffers ()
  (+test-with-reset
    (let ((a (+test-buffer "A")) (b (+test-buffer "B")))
      (switch-to-buffer a)
      (switch-to-buffer b)
      (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
        (call-interactively (key-binding (kbd "M-[")))
        (should (eq (current-buffer) a))
        (call-interactively (key-binding (kbd "M-]")))
        (should (eq (current-buffer) b))))))

;; ====== BACK / FORWARD ======

(ert-deftest navigation/back-and-forward-through-jumps ()
  "Cmd+[ goes back to where the cursor jumped from, Cmd+] forward again."
  (require 'better-jumper)
  (+test-with-reset
    (better-jumper-mode 1)
    (unwind-protect
        (+test-navigation--visiting "jumps.txt" (mapconcat #'number-to-string
                                                       (number-sequence 1 50) "\n")
          (switch-to-buffer (current-buffer))
          (goto-char (point-min))
          (forward-line 4)
          (let ((from (point)))
            (better-jumper-set-jump)
            (goto-char (point-max))
            (let ((to (point)))
              (call-interactively (lookup-key global-map (kbd "s-[")))
              (should (= (point) from))
              (call-interactively (lookup-key global-map (kbd "s-]")))
              (should (= (point) to)))))
      (better-jumper-mode -1))))

;; ====== GO TO DECLARATION OR USAGES (Cmd+B) ======

;; A backend whose definitions a test chooses, and one standing for lsp-mode's.
(defvar +test-navigation--definitions nil
  "What the test backends return as definitions (a function of the id).")

(cl-defmethod xref-backend-identifier-at-point ((_ (eql '+test-navigation)))
  (thing-at-point 'symbol t))

(cl-defmethod xref-backend-definitions ((_ (eql '+test-navigation)) id)
  (funcall +test-navigation--definitions id))

(unless (featurep 'lsp-mode)
  (cl-defmethod xref-backend-identifier-at-point ((_ (eql 'xref-lsp)))
    (thing-at-point 'symbol t))
  (cl-defmethod xref-backend-definitions ((_ (eql 'xref-lsp)) id)
    (funcall +test-navigation--definitions id)))

(defmacro +test-navigation--with-backend (backend definitions &rest body)
  "BODY with BACKEND the buffer's xref backend, DEFINITIONS (a function of
the id) its definitions."
  (declare (indent 2))
  `(let ((+test-navigation--definitions ,definitions))
     (setq-local xref-backend-functions (list (lambda () ,backend)))
     ,@body))

(defun +test-navigation--code ()
  "Some code: a declaration on line 2, a use on line 4."
  "// code\nfun answer() = 42\n\nval x = answer()\n")

(defun +test-navigation--goto (string &optional nth)
  "Point on the NTH (default 1st) STRING in the buffer."
  (goto-char (point-min))
  (search-forward string nil nil (or nth 1))
  (goto-char (match-beginning 0)))

(defun +test-navigation--here (line column)
  "A definition in this buffer's file at LINE, COLUMN."
  (xref-make "answer" (xref-make-file-location buffer-file-name line column)))

(ert-deftest navigation/at-declaration-on-the-declaration ()
  (+test-navigation--visiting "decl/a.kt" (+test-navigation--code)
    (+test-navigation--with-backend '+test-navigation (lambda (_) (list (+test-navigation--here 2 4)))
      (+test-navigation--goto "answer")
      (should (+my/at-declaration-p))
      ;; Anywhere on the name.
      (forward-char 5)
      (should (+my/at-declaration-p)))))

(ert-deftest navigation/at-declaration-not-on-a-use ()
  (+test-navigation--visiting "decl/b.kt" (+test-navigation--code)
    (+test-navigation--with-backend '+test-navigation (lambda (_) (list (+test-navigation--here 2 4)))
      (+test-navigation--goto "answer" 2)
      (should-not (+my/at-declaration-p)))))

(ert-deftest navigation/at-declaration-same-line-other-symbol ()
  "A declaration on this line but not where the symbol at point is."
  (+test-navigation--visiting "decl/c.kt" "fun answer() = other()\nfun other() = 1\n"
    (+test-navigation--with-backend '+test-navigation (lambda (_) (list (+test-navigation--here 1 4)))
      (+test-navigation--goto "other")
      (should-not (+my/at-declaration-p)))))

(ert-deftest navigation/at-declaration-elsewhere-never-opens-files ()
  "Declarations in other files (even on the same line number) aren't looked
at closer: their files stay closed."
  (let ((other (+test-file "decl/other.kt" "// other\nfun answer() = 42\n")))
    (+test-navigation--visiting "decl/d.kt" (+test-navigation--code)
      (+test-navigation--with-backend
          '+test-navigation (lambda (_) (list (xref-make "answer" (xref-make-file-location other 2 4))))
        (+test-navigation--goto "answer")
        (should-not (+my/at-declaration-p))
        (should-not (get-file-buffer other))))))

(ert-deftest navigation/at-declaration-one-of-several ()
  (let ((other (+test-file "decl/other2.kt" "fun answer() = 1\n")))
    (+test-navigation--visiting "decl/e.kt" (+test-navigation--code)
      (+test-navigation--with-backend
          '+test-navigation (lambda (_) (list (xref-make "answer" (xref-make-file-location other 1 4))
                                          (+test-navigation--here 2 4)))
        (+test-navigation--goto "answer")
        (should (+my/at-declaration-p))))))

(ert-deftest navigation/at-declaration-no-symbol ()
  (+test-navigation--visiting "decl/f.kt" "   \n"
    (+test-navigation--with-backend '+test-navigation (lambda (_) (error "Not called"))
      (should-not (+my/at-declaration-p)))))

(ert-deftest navigation/at-declaration-no-definitions ()
  "No definitions known: not at the declaration (the jump falls back)..."
  (+test-navigation--visiting "decl/g.kt" (+test-navigation--code)
    (+test-navigation--with-backend '+test-navigation (lambda (_) nil)
      (+test-navigation--goto "answer")
      (should-not (+my/at-declaration-p)))
    ;; ...also when asking fails.
    (+test-navigation--with-backend '+test-navigation (lambda (_) (error "Server error"))
      (+test-navigation--goto "answer")
      (should-not (+my/at-declaration-p)))))

(ert-deftest navigation/at-declaration-lsp-knows-none ()
  "With a language server knowing no declaration (a Markdown heading), list
the usages: counts as the declaration."
  (+test-navigation--visiting "decl/doc.md" "# Heading\n\nSee [the heading](#heading).\n"
    (+test-navigation--with-backend 'xref-lsp (lambda (_) nil)
      (+test-navigation--goto "Heading")
      (should (+my/at-declaration-p)))
    (+test-navigation--with-backend 'xref-lsp (lambda (_) (error "No definition"))
      (+test-navigation--goto "Heading")
      (should (+my/at-declaration-p)))
    ;; A server that knows one elsewhere: a jump.
    (let ((other (+test-file "decl/other.md" "# Heading\n")))
      (+test-navigation--with-backend
          'xref-lsp (lambda (_) (list (xref-make "h" (xref-make-file-location other 1 2))))
        (+test-navigation--goto "Heading")
        (should-not (+my/at-declaration-p))))))

(ert-deftest navigation/at-declaration-here-p-marker-in-another-buffer ()
  "A location on this line whose marker lands in another buffer: no."
  (+test-navigation--visiting "decl/h.kt" (+test-navigation--code)
    (+test-navigation--goto "answer")
    (let* ((other (+test-buffer "elsewhere" "fun answer() = 42\n"))
           (item (xref-make "answer" (xref-make-file-location buffer-file-name 2 4))))
      (cl-letf (((symbol-function 'xref-location-marker)
                 (lambda (_) (with-current-buffer other (copy-marker 5)))))
        (should-not (+my/at-declaration--here-p (bounds-of-thing-at-point 'symbol)
                                                (list item)))))))

(ert-deftest navigation/at-declaration-in-emacs-lisp ()
  "Emacs Lisp: Emacs itself knows where symbols are declared (its locations
carry no line: the line declaring them)."
  (let ((file (+test-file "decl/sample.el"
                          ";;; sample.el -*- lexical-binding: t; -*-\n(defun +test-navigation-sample ()\n  1)\n\n(+test-navigation-sample)\n")))
    (load file nil t)
    (+test-navigation--visiting "decl/sample.el" (with-temp-buffer
                                               (insert-file-contents file)
                                               (buffer-string))
      (should (eq (xref-find-backend) 'elisp))
      (+test-navigation--goto "+test-navigation-sample")
      (should (+my/at-declaration-p))
      (+test-navigation--goto "+test-navigation-sample" 2)
      (should-not (+my/at-declaration-p)))))

(ert-deftest navigation/at-declaration-keeps-point ()
  "Finding where Emacs Lisp declares a symbol moves point in its file: put
back (the usages are then listed for the symbol at point)."
  (let ((file (+test-file "decl/sample3.el"
                          ";;; sample3.el -*- lexical-binding: t; -*-\n(defun +test-navigation-sample3 ()\n  1)\n\n(+test-navigation-sample3)\n")))
    (load file nil t)
    (+test-navigation--visiting "decl/sample3.el" (with-temp-buffer
                                                (insert-file-contents file)
                                                (buffer-string))
      (dolist (nth '(1 2))
        (+test-navigation--goto "+test-navigation-sample3" nth)
        (forward-char 3)
        (let ((point (point)))
          (+my/at-declaration-p)
          (should (= (point) point)))))))

(defmacro +test-navigation--with-lookup (&rest body)
  "BODY with Doom's lookup commands recording into `called'."
  `(let ((called nil))
     (cl-letf (((symbol-function '+lookup/definition)
                (lambda (&rest _) (interactive) (push 'definition called)))
               ((symbol-function '+lookup/references)
                (lambda (&rest _) (interactive) (push 'references called))))
       ,@body)))

(ert-deftest navigation/goto-declaration-or-usages ()
  "On a use: jump (gd); on the declaration: list usages (gD)."
  (+test-navigation--visiting "decl/i.kt" (+test-navigation--code)
    (+test-navigation--with-backend '+test-navigation (lambda (_) (list (+test-navigation--here 2 4)))
      (+test-navigation--with-lookup
       (+test-navigation--goto "answer" 2)
       (call-interactively #'+my/goto-declaration-or-usages)
       (should (equal called '(definition)))
       (+test-navigation--goto "answer")
       (call-interactively #'+my/goto-declaration-or-usages)
       (should (equal called '(references definition)))))))

(ert-deftest navigation/goto-declaration-or-usages-no-symbol ()
  (+test-navigation--visiting "decl/j.kt" "   \n"
    (+test-navigation--with-lookup
     (should-error (call-interactively #'+my/goto-declaration-or-usages) :type 'user-error)
     (should-not called))))

(ert-deftest navigation/goto-declaration-or-usages-emacs-lisp ()
  "In Emacs Lisp, on a defun's name: its usages."
  (let ((file (+test-file "decl/sample2.el"
                          ";;; -*- lexical-binding: t; -*-\n(defun +test-navigation-sample2 () 1)\n(+test-navigation-sample2)\n")))
    (load file nil t)
    (+test-navigation--visiting "decl/sample2.el" (with-temp-buffer
                                                (insert-file-contents file)
                                                (buffer-string))
      (+test-navigation--with-lookup
       (+test-navigation--goto "+test-navigation-sample2")
       (call-interactively #'+my/goto-declaration-or-usages)
       (+test-navigation--goto "+test-navigation-sample2" 2)
       (call-interactively #'+my/goto-declaration-or-usages)
       (should (equal called '(definition references)))))))
