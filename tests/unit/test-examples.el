;;; tests/unit/test-examples.el -*- lexical-binding: t; -*-
;; config/examples.el and examples/: M-x +my/example picks one, M-x
;; +my/example-NAME runs it (loaded then). The merge example: a temp repo in
;; conflict every way the panes handle, opened; deleted once the merge is
;; closed, whatever it saved. Real git, with a temp HOME and global gitconfig
;; (the user's never read).

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(+test-load "config/banner" "config/window" "config/tabs" "config/tiling" "config/stripe" "config/smooth"
            "config/merge" "config/examples")
(require 'so-long)
(require 'tab-line)

(defconst +test-examples--loaded-at-start (featurep 'example-merge)
  "Whether loading the config loaded an example (it mustn't).")

(defmacro +test-examples (&rest body)
  "BODY from one window, git with a temp HOME and global gitconfig; the
merges it left open closed after."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "examples-home-") t)))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0")
                     process-environment)))
       (with-temp-file (expand-file-name ".gitconfig" home))
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (error "Asked: %s" prompt))))
         (unwind-protect (progn ,@body)
           (dolist (buffer (buffer-list))
             (when-let* ((session (buffer-local-value '+my/merge--session buffer)))
               (+my/merge--finish session))))))))

(ert-deftest examples/listed-and-each-a-command ()
  (should (member "merge" (+my/examples)))
  (should (equal +my/examples-dir (expand-file-name "examples/" doom-user-dir)))
  ;; M-x +my/example-merge: loads examples/merge.el when first run, not
  ;; before.
  (should-not +test-examples--loaded-at-start)
  (let ((function (symbol-function '+my/example-merge)))
    (should (or (autoloadp function) (featurep 'example-merge)))
    (when (autoloadp function)
      (should (equal (cadr function) (expand-file-name "merge" +my/examples-dir)))
      (should (nth 3 function))))               ; a command
  (should (commandp #'+my/example))
  (should-error (+my/example "no-such-example") :type 'user-error))

(ert-deftest examples/merge-in-conflict-every-way ()
  (+test-examples
    (let* ((session (+my/example "merge"))
           (chunks (append (+my/merge-chunks session) nil)))
      (should (+my/merge-p session))
      (should (string-prefix-p (file-name-as-directory (file-truename temporary-file-directory))
                               (+my/merge-toplevel session)))
      (should (equal (+my/merge-path session) "orders.py"))
      (should (equal (+my/merge-labels session) '("main" . "feature")))
      ;; A conflict over one word, the same change on both, two the wand
      ;; merges, a change of each side alone, lines added, lines removed.
      (should (equal (mapcar #'+my/merge-chunk-kind chunks)
                     '(conflict same conflict conflict yours theirs theirs yours)))
      (should (equal (mapcar (lambda (chunk) (and (+my/merge-chunk-wand chunk) t)) chunks)
                     '(nil nil t t nil nil nil nil)))
      (should (string-empty-p (+my/merge-chunk-base (nth 5 chunks))))      ; added
      (should (string-empty-p (+my/merge--side-text (nth 7 chunks) 'yours))) ; removed
      ;; Open as Magit's e opens it.
      (should (eq (window-buffer (selected-window)) (+my/merge-result session)))
      (should (= (+test-messages "^Merge example (a temp repo, deleted when closed)") 1)))))

(ert-deftest examples/merge-leaves-nothing ()
  "Closed (Abort, Done, a pane closed): its repository deleted, whatever
was saved."
  (+test-examples
    (let* ((session (+my/example-merge))
           (repo (+my/merge-toplevel session)))
      (should (file-directory-p repo))
      (+my/merge-abort)
      (should-not (file-exists-p repo)))
    (let* ((session (+my/example-merge))
           (repo (+my/merge-toplevel session)))
      (+my/merge-accept-right)
      (+my/merge-done)
      (should-not (file-exists-p repo)))
    (let* ((session (+my/example-merge))
           (repo (+my/merge-toplevel session)))
      (+my/merge--finish session)
      (should-not (file-exists-p repo)))
    ;; Nothing left to watch for.
    (should-not (memq #'+my/example-merge--cleanup +my/merge-finished-functions))))

(ert-deftest examples/other-merges-left-alone ()
  "A merge not the example's: its repository isn't touched."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "other-") t)))
         (+my/example-merge--repos (list "/nowhere/")))
    (+my/example-merge--cleanup (+my/merge--make :toplevel dir))
    (should (file-directory-p dir))))

;; ====== EVERY EXAMPLE ======

(ert-deftest examples/each-one-a-command-a-file-and-a-screenshot-to-be ()
  "Each example listed has its file, its command, its line in
config/examples.el's list and docs/examples.md's table."
  (should (equal (sort (+my/examples) #'string<)
                 '("banner" "excalidraw" "markdown" "merge" "pdf" "stripe" "tiling")))
  (let ((listed (with-temp-buffer
                  (insert-file-contents (expand-file-name "config/examples.el" +test-root))
                  (buffer-string)))
        (docs (with-temp-buffer
                (insert-file-contents (expand-file-name "docs/examples.md" +test-root))
                (buffer-string))))
    (dolist (name (+my/examples))
      (should (fboundp (intern (format "+my/example-%s" name))))
      (should (string-match-p (format "^;;   %s " (regexp-quote name)) listed))
      (should (string-match-p (format "^| `%s` |" (regexp-quote name)) docs)))))

;; ====== THE HELPERS ======

(ert-deftest examples/folder-deleted-once-its-buffers-are-closed ()
  "The folder goes with the last of the example's buffers; through a change
of mode too; THEN called then."
  (let* ((dir (+my/example-folder "test"))
         (a (find-file-noselect (+my/example-write dir "a.txt" "a\n")))
         (b (find-file-noselect (+my/example-write dir "sub/b.txt" "b\n")))
         (then 0))
    (should (string-match-p "/test-example-" dir))
    (should (equal dir (file-name-as-directory (file-truename dir))))
    (+my/example-delete-when-closed dir (list a b) (lambda () (cl-incf then)))
    (with-current-buffer a (fundamental-mode))     ; a change of mode
    (kill-buffer a)
    (should (file-exists-p dir))
    (should (= then 0))
    (kill-buffer b)
    (should-not (file-exists-p dir))
    (should (= then 1))))

;; ====== TILING ======

(ert-deftest examples/tiling-a-project-tall ()
  "A project's four files, tall: the first on the left, the others stacked
on the right, the first selected; gone once closed."
  (+test-examples
    (let* ((buffers (+my/example-tiling))
           (windows (window-list nil 'nomini))
           (dir (car (buffer-local-value '+my/example--closing (car buffers)))))
      (should (equal (mapcar #'buffer-name buffers) '("app.py" "cart.py" "prices.py" "test_cart.py")))
      (should (equal (mapcar (lambda (window) (buffer-name (window-buffer window))) windows)
                     '("app.py" "cart.py" "prices.py" "test_cart.py")))
      (should (eq (selected-window) (car windows)))
      ;; Tall: the main pane the full height on the left, the others one
      ;; above the other on the right, as wide.
      (let ((main (car windows)) (stack (cdr windows)))
        (should (= (window-left-column main) 0))
        (should (= (window-total-height main) (window-total-height (frame-root-window))))
        (should (cl-every (lambda (window) (> (window-left-column window) 0)) stack))
        (should (= (length (seq-uniq (mapcar #'window-left-column stack))) 1))
        (should (equal (mapcar #'window-top-line stack)
                       (sort (mapcar #'window-top-line stack) #'<))))
      ;; Each pane its file's tab only (not the one it opened on).
      (dolist (window windows)
        (with-selected-window window
          (should (equal (+my/tabs-window-buffers) (list (window-buffer window))))))
      (should (string-prefix-p (file-name-as-directory (file-truename temporary-file-directory)) dir))
      (mapc #'kill-buffer buffers)
      (should-not (file-exists-p dir)))))

;; ====== NOTICES ======

(ert-deftest examples/banner-a-notice-of-each-kind ()
  "A file of very long lines: shown plain, the config's notice (a warning)
with its actions; an info and an error notice; gone once closed."
  (+test-examples
    (let* ((buffer (+my/example-banner))
           (dir (car (buffer-local-value '+my/example--closing buffer))))
      (with-current-buffer buffer
        (should (derived-mode-p 'so-long-mode))
        (should (> (cadr (buffer-line-statistics)) 10000))
        (should (equal (mapcar (lambda (notice) (list (car notice) (nth 3 notice))) +my/banner--list)
                       '((long-lines warning) (example-info info) (example-error error))))
        ;; Its actions: another notice; close them all.
        (funcall (cdr (assoc "Another one" (nth 2 (assq 'example-info +my/banner--list)))))
        (should (= (length +my/banner--list) 4))
        (funcall (cdr (assoc "Close them all" (nth 2 (assq 'example-error +my/banner--list)))))
        (should-not +my/banner--list))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

;; ====== THE ERROR STRIPE ======

(ert-deftest examples/stripe-errors-warnings-and-changes ()
  "inventory.el in a repository, changed since its commit: flycheck finds
warnings through the file and an error at its end (the byte compiler: the
file trusted while it's open), diff-hl the changes; the strip on; the
repository and the trust gone once closed."
  (+test-examples
    (let* ((trusted trusted-content)
           (buffer (+my/example-stripe))
           (repo (car (buffer-local-value '+my/example--closing buffer))))
      (should (member repo trusted-content))
      (should (+test-wait-for #'+my/example-stripe-ready 60))
      (with-current-buffer buffer
        (should (bound-and-true-p +my/stripe-mode))
        (should (equal (mapcar (lambda (error) (list (flycheck-error-line error) (flycheck-error-level error)))
                               (seq-sort-by #'flycheck-error-line #'< flycheck-current-errors))
                       '((29 warning) (175 warning) (180 warning) (247 warning) (276 error))))
        ;; Changed, removed and added lines.
        (let ((kinds (seq-uniq (mapcar (lambda (ov) (overlay-get ov 'diff-hl-hunk-type))
                                       (seq-filter (lambda (ov) (overlay-get ov 'diff-hl-hunk))
                                                   (overlays-in (point-min) (point-max)))))))
          (should (seq-set-equal-p kinds '(change delete insert)))))
      (kill-buffer buffer)
      (should-not (file-exists-p repo))
      (should (equal trusted-content trusted)))))

;; ====== THE DRAWING ======

(ert-deftest examples/excalidraw-drawing-each-element-its-own ()
  "The drawing's JSON: elements not deleted, each with its own colours (not
the last one's: the template's cells were shared), labels in their boxes."
  (require 'example-excalidraw (expand-file-name "excalidraw" +my/examples-dir))
  (let* ((drawing (json-parse-string (+my/example-excalidraw--drawing)
                                     :object-type 'alist :false-object nil :null-object nil))
         (elements (append (alist-get 'elements drawing) nil))
         (get (lambda (id key) (alist-get key (seq-find (lambda (e) (equal (alist-get 'id e) id)) elements)))))
    (should (> (length elements) 10))
    (should-not (seq-some (lambda (e) (alist-get 'isDeleted e)) elements))
    (should (equal (funcall get "title" 'strokeColor) "#1e1e1e"))
    (should (equal (funcall get "save" 'strokeColor) "#e03131"))
    (should (equal (funcall get "file" 'backgroundColor) "#a5d8ff"))
    (should (equal (funcall get "webkit" 'backgroundColor) "#b2f2bb"))
    (should (equal (funcall get "file" 'fillStyle) "hachure"))
    (should (equal (funcall get "you" 'fillStyle) "solid"))
    (should (equal (funcall get "file-label" 'containerId) "file"))
    (should (equal (funcall get "note" 'strokeColor) "#1e1e1e"))))
