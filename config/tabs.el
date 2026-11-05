;;; $DOOMDIR/config/tabs.el -*- lexical-binding: t; -*-
;; Tab bar (centaur-tabs) labels. Loaded from config.el.

;; TABS
;; Workspaces disable uniquify, so same-named files get buffer names like
;; lib.rs, lib.rs<2>, even when they're in different projects. Label file tabs
;; with the file name instead of the buffer name, and when two tabs in the same
;; tab group share a file name, with the shortest distinguishing path, e.g.
;; crate-a/src/lib.rs.
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
         (file (and (not centaur-tabs--buffer-show-groups) (buffer-file-name buf))))
    (if (not file)
        (funcall fn tab)                ; non-file buffers: the buffer name
      (let* ((name (file-name-nondirectory file))
             (others
              (delq nil (mapcar (lambda (b)
                                  (let ((f (buffer-file-name b)))
                                    (and f (not (eq b buf))
                                         (equal (file-name-nondirectory f) name)
                                         f)))
                                (centaur-tabs-tab-values (centaur-tabs-tab-tabset tab)))))
             (label (if others (+my/tabs-unique-label file others) name)))
        (format " %s" (if (> centaur-tabs-label-fixed-length 0)
                          (centaur-tabs-truncate-string centaur-tabs-label-fixed-length label)
                        label))))))
