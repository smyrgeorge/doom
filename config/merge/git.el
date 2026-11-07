;;; $DOOMDIR/config/merge/git.el -*- lexical-binding: t; -*-
;; The three versions, from Git's index. Loaded from config/merge.el.

;; THE VERSIONS (Git's index)
(defun +my/merge--git (&rest args)
  "Run git with ARGS in the current folder; its output as bytes (unibyte), or
nil if it failed."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'binary)
          (process-environment (cons "GIT_OPTIONAL_LOCKS=0" process-environment)))
      (and (zerop (apply #'process-file (or (bound-and-true-p magit-git-executable) "git")
                         nil t nil args))
           (buffer-string)))))

(defun +my/merge--stages (path)
  "PATH's stages in the index: ((STAGE . MODE)...)."
  (let ((out (+my/merge--git "ls-files" "-u" "--" path))
        stages)
    (dolist (line (and out (split-string out "\n" t)))
      (when (string-match "\\`\\([0-7]+\\) [0-9a-f]+ \\([123]\\)\t" line)
        (push (cons (string-to-number (match-string 2 line)) (match-string 1 line)) stages)))
    (nreverse stages)))

(defun +my/merge--blob (stage path)
  "PATH's version STAGE in the index, as bytes."
  (or (+my/merge--git "show" (format ":%d:%s" stage path))
      (error "Git has no version %d of %s" stage path)))

(defun +my/merge--binary-p (bytes)
  "Non-nil if BYTES look binary, as Git decides: a NUL in their first 8000."
  (string-search "\0" (substring bytes 0 (min 8000 (length bytes)))))

(defun +my/merge--why-not (path)
  "Why PATH's conflict can't be resolved in three panes (a string), or nil."
  (let* ((stages (+my/merge--stages path))
         (modes (mapcar #'cdr stages)))
    (cond ((null stages) "Not in conflict")
          ((not (assq 1 stages)) "Added on both sides")
          ((not (assq 2 stages)) "Deleted on your side")
          ((not (assq 3 stages)) "Deleted on their side")
          ((member "160000" modes) "A submodule")
          ((member "120000" modes) "A link")
          ((seq-some (lambda (stage) (+my/merge--binary-p (+my/merge--blob stage path)))
                     '(1 2 3))
           "A binary file"))))

(defun +my/merge--coding (bytes)
  "The coding system to read BYTES (a version) and write the Result with."
  (let ((coding (car (detect-coding-string bytes))))
    (if (memq (coding-system-base coding) '(undecided prefer-utf-8 raw-text))
        (coding-system-change-text-conversion coding 'utf-8)
      coding)))

(defun +my/merge--labels ()
  "What Yours and Theirs are, (YOURS . THEIRS), from the operation going on."
  (let* ((rev (lambda (name) (and (magit-rev-verify name) name)))
         (subject (lambda (rev) (magit-rev-format "%h %s" rev)))
         (branch (or (magit-get-current-branch) (magit-rev-abbrev "HEAD") "HEAD")))
    (cond ((funcall rev "MERGE_HEAD")
           (cons branch (or (magit-rev-name "MERGE_HEAD" "refs/heads/*")
                            (funcall subject "MERGE_HEAD"))))
          ((funcall rev "REBASE_HEAD")
           (cons (format "%s (rebasing onto)" (funcall subject "HEAD"))
                 (format "%s (being rebased)" (funcall subject "REBASE_HEAD"))))
          ((funcall rev "CHERRY_PICK_HEAD")
           (cons branch (format "%s (cherry-picked)" (funcall subject "CHERRY_PICK_HEAD"))))
          ((funcall rev "REVERT_HEAD")
           (cons branch (format "revert of %s" (funcall subject "REVERT_HEAD"))))
          (t (cons branch "the change applied (a stash...)")))))
