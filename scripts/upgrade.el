;;; scripts/upgrade.el -*- lexical-binding: t; -*-
;; packages.el's pins moved to each package's latest commit upstream, for
;; scripts/upgrade.sh. Run by Doom's doomscript (its CLI loaded):
;;
;;   doomscript scripts/upgrade.el PACKAGES-FILE REPORT-FILE
;;
;; PACKAGES-FILE rewritten as M-x doom/bump-packages-in-buffer would: each
;; `package!' with a :pin, its pin the commit `git ls-remote' gives for its
;; recipe's branch; one without a :pin left alone. REPORT-FILE gets a line
;; per pin moved: PACKAGE OLD NEW REPO (its straight repository's folder, for
;; the commits between). Exit status: 0 done, 1 not (PACKAGES-FILE then as
;; it was), the reason on stderr.

(defun +upgrade-pins (file)
  "FILE's `package!' forms with a :pin: an alist (PACKAGE . PIN), in order."
  (with-temp-buffer
    (insert-file-contents file)
    (let (pins)
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (and (eq (car-safe form) 'package!)
                         (plist-get (cddr form) :pin))
                (push (cons (cadr form) (plist-get (cddr form) :pin)) pins))))
        (end-of-file))
      (nreverse pins))))

(defun +upgrade-repo (package)
  "PACKAGE's straight repository folder, or \"-\" when it has none."
  (or (ignore-errors (directory-file-name
                      (straight--repos-dir (doom-package-recipe-repo package))))
      "-"))

(defun +upgrade-bump (file report)
  "Move FILE's pins to their packages' latest commits; REPORT the moved ones.
A pin that isn't a commit after (`git ls-remote' failing, its error taken
for one) is an error, and FILE is left as it was."
  (let ((before (+upgrade-pins file))
        (text (with-temp-buffer (insert-file-contents file) (buffer-string))))
    (with-current-buffer (find-file-noselect file)
      (emacs-lisp-mode)
      (doom/bump-packages-in-buffer)
      (save-buffer)
      (kill-buffer))
    (let ((after (+upgrade-pins file)))
      (when-let* ((bad (seq-remove (lambda (pin) (string-match-p "\\`[0-9a-f]\\{40\\}\\'" (cdr pin)))
                                   after)))
        (with-temp-file file (insert text))
        (error "No commit found for %s"
               (mapconcat (lambda (pin) (format "%s (%s)" (car pin) (cdr pin))) bad ", ")))
      (with-temp-file report
        (dolist (pin after)
          (let ((old (alist-get (car pin) before)))
            (unless (equal old (cdr pin))
              (insert (format "%s %s %s %s\n" (car pin) old (cdr pin)
                              (+upgrade-repo (car pin)))))))))))

;; Run by doomscript (its arguments after a "--"), not when a test loads it.
(when (and noninteractive (bound-and-true-p doom-emacs-dir)
           (equal (car command-line-args-left) "--"))
  (condition-case err
      (progn
        (dolist (lib '("text" "process" "packages"))
          (load (expand-file-name (concat "lisp/lib/" lib) doom-emacs-dir) nil t))
        (+upgrade-bump (nth 1 command-line-args-left) (nth 2 command-line-args-left))
        (kill-emacs 0))
    (error
     (princ (format "upgrade.el: %s\n" (error-message-string err)) #'external-debugging-output)
     (kill-emacs 1))))
