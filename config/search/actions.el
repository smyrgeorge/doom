;;; $DOOMDIR/config/search/actions.el -*- lexical-binding: t; -*-
;; Actions: every command M-x offers, recently used ones first.
;; Loaded from config/search.el.

(defun +my/search-everywhere--commands ()
  "Names of all commands M-x would offer here, in its order: recently used
ones first, then the shortest. marginalia aligns their docs after the longest
name shown: alphabetically, long names came first, the docs off a narrow
frame."
  (let* ((buffer (current-buffer))
         (offered-p (lambda (sym)
                      (and (commandp sym)
                           (or (null read-extended-command-predicate)
                               (funcall read-extended-command-predicate sym buffer)))))
         (all nil))
    (mapatoms
     (lambda (sym)
       (when (funcall offered-p sym)
         (push (symbol-name sym) all))))
    (delete-dups
     ;; Recently used ones only where M-x offers them too: a mode's commands
     ;; (e.g. dired's) used there aren't listed in other buffers.
     (append (seq-filter (lambda (name) (funcall offered-p (intern-soft name)))
                         extended-command-history)
             (sort all (lambda (a b)
                         (if (= (length a) (length b))
                             (string< a b)
                           (< (length a) (length b)))))))))

(defun +my/search-everywhere--run-command (name)
  "Run command NAME as M-x would."
  (let ((command (intern name)))
    (add-to-history 'extended-command-history name)
    (setq this-command command
          real-this-command command)
    (command-execute command 'record)))
