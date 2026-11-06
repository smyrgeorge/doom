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

(+test-load "config/merge" "config/examples")

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
