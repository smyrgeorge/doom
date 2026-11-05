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

;; CLAUDE AND ITS PROJECT IN ONE TAB GROUP
;; Each window's tab bar shows the tabs of its buffer's group: a file's
;; project, else "Common". The Claude buffer (agent-shell) visits no file, so
;; it sat alone in "Common", while what it links to (its charts saved in the
;; project, `path:line' references) opens in the project's group: clicking an
;; image swapped the whole tab bar for the project's, like another workspace.
;; Claude buffers now join their project's group, and a file opened from one
;; that belongs to no project (e.g. a pasted screenshot in agent-shell's cache)
;; joins Claude's group: either way it opens as a tab next to Claude.
(defvar-local +my/tabs-group nil
  "This buffer's tab group, when it was opened from a Claude buffer (above).")

(defadvice! +my/tabs-agent-shell-project-a (fn)
  :around #'centaur-tabs-project-name
  (or (funcall fn)
      (and (derived-mode-p 'agent-shell-mode)
           (when-let* ((project (project-current nil default-directory)))
             (format "Project: %s"
                     (expand-file-name (project-root project)))))))

(defadvice! +my/tabs-own-group-a (fn)
  :around #'centaur-tabs-buffer-groups
  (if +my/tabs-group (list +my/tabs-group) (funcall fn)))

(defadvice! +my/tabs-follow-claude-a (fn &rest args)
  :around #'agent-shell-markdown-visit-file
  (let* ((group (and (bound-and-true-p centaur-tabs-mode)
                     (car (centaur-tabs-buffer-groups))))
         (window (apply fn args))
         (buffer (and (window-live-p window) (window-buffer window))))
    (when (and group buffer)
      (with-current-buffer buffer
        (unless (or +my/tabs-group (centaur-tabs-project-name))
          (setq +my/tabs-group group)
          (centaur-tabs-buffer-update-groups)
          (centaur-tabs-display-update))))
    window))

;; CLOSING A TAB
;; Closing the shown tab showed the next one in its group (centaur-tabs), not
;; the one you came from: close an image opened from Claude and another file
;; came up. It goes back to the tab this window showed before now, if that's
;; in the same group; otherwise to the next one, as before.
(defadvice! +my/tabs-close-back-a (fn)
  :around #'centaur-tabs-buffer-track-killed
  (let* ((buffer (current-buffer))
         (window (selected-window))
         (group (car (centaur-tabs-buffer-groups)))
         (tabs (and (eq buffer (window-buffer window))
                    (funcall centaur-tabs-buffer-list-function)))
         (previous
          (seq-find (lambda (b)
                      (and (buffer-live-p b) (not (eq b buffer)) (memq b tabs)
                           (equal (with-current-buffer b
                                    (car (centaur-tabs-buffer-groups)))
                                  group)))
                    (mapcar #'car (window-prev-buffers window)))))
    (if previous
        (save-current-buffer (switch-to-buffer previous))
      (funcall fn))))
