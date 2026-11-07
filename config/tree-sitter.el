;;; $DOOMDIR/config/tree-sitter.el -*- lexical-binding: t; -*-
;; Tree-sitter grammars built ahead of time, which ones are there remembered.
;; Loaded from config.el.

;; ====== VARIABLES ======

;; TREE-SITTER GRAMMARS
;; The first file of a language asked to download and build its tree-sitter
;; grammar (Doom's "Missing tree-sitter grammars: ... Install now?"). Instead,
;; once Emacs has started and been idle a moment, every grammar the enabled
;; languages need (what their modules in init.el register with
;; `set-tree-sitter!') that isn't there yet is downloaded and built, with the
;; same recipes, into Doom's grammar folder (.local/etc/tree-sitter). In the
;; background: another Emacs (`emacs --batch') builds them, as building them
;; here would freeze Emacs for minutes. Its output is in *tree-sitter
;; grammars*; a message says when it starts and ends. A language enabled later
;; (init.el, `doom sync') gets its grammars at the next start.
;; M-x +my/tree-sitter-install-grammars does it now.
(defvar +my/tree-sitter-install-delay 10
  "Idle seconds after startup before missing grammars get built; nil: never.")

(defconst +my/tree-sitter-buffer "*tree-sitter grammars*"
  "Where the build's output goes.")

;; ====== CODE ======

;; AVAILABLE GRAMMARS, REMEMBERED
;; Every check that a grammar is available, and every parser made, loads its
;; library again (dlopen), and with this many libraries loaded (each natively
;; compiled package is one) that takes ~10 ms on macOS. Opening a Markdown file
;; checked its grammars ~9 times (a missing one: 36 paths tried each time).
;; Remember the answers (cleared when a grammar gets installed).
(defvar +my/treesit--available (make-hash-table :test #'equal)
  "LANGUAGE -> its `treesit-language-available-p' answer with DETAIL.")

(defadvice! +my/treesit-remember-available-a (fn language &optional detail)
  :around #'treesit-language-available-p
  (let ((answer (or (gethash language +my/treesit--available)
                    (puthash language (funcall fn language t) +my/treesit--available))))
    (if detail answer (car answer))))

(defadvice! +my/treesit-forget-available-a (&rest _)
  :after #'treesit-install-language-grammar
  (clrhash +my/treesit--available))

(defvar +my/tree-sitter--process nil
  "The Emacs building grammars, while it runs.")

(defvar treesit-language-source-alist)

(defun +my/tree-sitter--grammars ()
  "The grammars the enabled languages need (see above)."
  (let (grammars)
    (mapatoms (lambda (mode)
                (let ((ts (get mode '+tree-sitter)))
                  (when (consp ts)
                    (dolist (grammar (cdr ts))
                      (unless (memq grammar grammars)
                        (push grammar grammars)))))))
    (sort grammars #'string<)))

(defun +my/tree-sitter--recipe (grammar)
  "GRAMMAR's recipe in `treesit-language-source-alist', loading the
tree-sitter modes that bring theirs when loaded, as Doom does on first use."
  (or (assq grammar treesit-language-source-alist)
      (progn
        (mapatoms
         (lambda (mode)
           (let ((ts (get mode '+tree-sitter)))
             (when (and (consp ts) (memq grammar (cdr ts))
                        (autoloadp (symbol-function mode)))
               ;; As Doom: a ts-mode loading mustn't take over file names.
               (let ((auto-mode-alist auto-mode-alist)
                     (interpreter-mode-alist interpreter-mode-alist))
                 (ignore-errors (autoload-do-load (symbol-function mode) mode)))))))
        (assq grammar treesit-language-source-alist))))

(defun +my/tree-sitter--missing ()
  "The grammars needed (see above) that aren't there."
  (require 'treesit)
  (seq-remove #'treesit-language-available-p (+my/tree-sitter--grammars)))

(defun +my/tree-sitter--done (process _event)
  "The build's end: say what got built, what failed."
  (when (memq (process-status process) '(exit signal))
    (setq +my/tree-sitter--process nil)
    (let ((dir (process-get process 'init-dir)))
      (when (and dir (file-directory-p dir))
        (delete-directory dir t)))
    ;; New grammars: forget the "not available" answers (see AVAILABLE
    ;; GRAMMARS, REMEMBERED).
    (clrhash +my/treesit--available)
    (let* ((wanted (process-get process 'grammars))
           (failed (seq-remove #'treesit-language-available-p wanted)))
      (if failed
          (message "Tree-sitter grammars: %d built, %s failed (see %s)"
                   (- (length wanted) (length failed))
                   (mapconcat #'symbol-name failed ", ") +my/tree-sitter-buffer)
        (message "Tree-sitter grammars built: %s"
                 (mapconcat #'symbol-name wanted ", "))))))

(defun +my/tree-sitter-install-grammars (&optional quiet)
  "Build the missing grammars of the enabled languages, in the background
(see above). QUIET: say nothing when none are missing."
  (interactive)
  (require 'treesit)
  (cond
   ((not (treesit-available-p))
    (unless quiet (message "This Emacs has no tree-sitter")))
   ((process-live-p +my/tree-sitter--process)
    (unless quiet (message "Tree-sitter grammars: still building (see %s)" +my/tree-sitter-buffer)))
   (t
    (let* ((missing (+my/tree-sitter--missing))
           (recipes (delq nil (mapcar #'+my/tree-sitter--recipe missing)))
           (grammars (mapcar #'car recipes))
           (unknown (seq-difference missing grammars))
           (out-dir (doom-profile-data-dir t "tree-sitter"))
           (init-dir (make-temp-file "tree-sitter-build-" t)))
      (cond
       ((null grammars)
        (delete-directory init-dir t)
        (cond (unknown
               (message "Tree-sitter grammars: no recipe for %s"
                        (mapconcat #'symbol-name unknown ", ")))
              ((not quiet)
               (message "Tree-sitter grammars: all there"))))
       (t
        (message "Building tree-sitter grammars in the background: %s%s"
                 (mapconcat #'symbol-name grammars ", ")
                 (if unknown
                     (format " (no recipe for %s)" (mapconcat #'symbol-name unknown ", "))
                   ""))
        (with-current-buffer (get-buffer-create +my/tree-sitter-buffer)
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert (format "\n%s: building %s into %s\n"
                            (format-time-string "%F %T")
                            (mapconcat #'symbol-name grammars " ") out-dir))))
        ;; A plain Emacs (-Q), its own empty init directory: it mustn't make
        ;; ~/.emacs.d, which would take over from Doom's. Started from there
        ;; too: the current buffer's folder may be gone (deleted outside
        ;; Emacs), and the process couldn't start.
        (let* ((default-directory (file-name-as-directory init-dir))
               (process
               (make-process
                :name "tree-sitter-grammars"
                :buffer +my/tree-sitter-buffer
                :noquery t
                :command
                (list (expand-file-name invocation-name invocation-directory)
                      "--batch" "-Q" (concat "--init-directory=" init-dir)
                      "--eval"
                      (prin1-to-string
                       `(progn
                          (require 'treesit)
                          (setq treesit-language-source-alist ',recipes)
                          (dolist (grammar ',grammars)
                            (message "Building %s..." grammar)
                            (condition-case err
                                (progn (treesit-install-language-grammar grammar ,out-dir)
                                       (message "Built %s" grammar))
                              (error (message "FAILED %s: %s" grammar
                                              (error-message-string err))))))))
                :sentinel #'+my/tree-sitter--done)))
          (process-put process 'grammars grammars)
          (process-put process 'init-dir init-dir)
          (setq +my/tree-sitter--process process))))))))

(when +my/tree-sitter-install-delay
  (add-hook 'emacs-startup-hook
            (defun +my/tree-sitter-install-later-h ()
              (run-with-idle-timer +my/tree-sitter-install-delay nil
                                   #'+my/tree-sitter-install-grammars 'quiet))))
