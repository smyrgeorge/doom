;;; $DOOMDIR/config/tabs.el -*- lexical-binding: t; -*-
;; Tab bar (centaur-tabs) labels. Loaded from config.el.

;; TABS
;; Workspaces disable uniquify, so same-named files show as lib.rs, lib.rs<2>.
;; When two tabs (in the same tab group) share a file name, label them with the
;; shortest distinguishing path instead, e.g. crate-a/src/lib.rs.
(defun +my/tabs-unique-label (file others)
  "Return the shortest trailing part of FILE's path not shared by OTHERS."
  (let* ((split (lambda (f) (reverse (split-string (abbreviate-file-name f) "/" t))))
         (parts (funcall split file))
         (other-parts (mapcar split others))
         (n 1))
    (while (and (< n (length parts))
                (seq-some (lambda (o) (equal (seq-take o n) (seq-take parts n)))
                          other-parts))
      (setq n (1+ n)))
    (string-join (reverse (seq-take parts n)) "/")))

(defadvice! +my/tabs-label-with-path-a (fn tab)
  :around #'centaur-tabs-buffer-tab-label
  (let* ((buf (car tab))
         (file (buffer-file-name buf))
         (name (and file (file-name-nondirectory file)))
         (others
          (and file (not centaur-tabs--buffer-show-groups)
               (delq nil (mapcar (lambda (b)
                                   (let ((f (buffer-file-name b)))
                                     (and f (not (eq b buf))
                                          (equal (file-name-nondirectory f) name)
                                          f)))
                                 (centaur-tabs-tab-values (centaur-tabs-tab-tabset tab)))))))
    (if others
        (format " %s" (+my/tabs-unique-label file others))
      (funcall fn tab))))
