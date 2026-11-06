;;; $DOOMDIR/config/projectile.el -*- lexical-binding: t; -*-
;; Project discovery and file listing. Loaded from config.el.

;; PROJECTILE
;; Discover projects using 'projectile-discover-projects-in-search-path'
(setq projectile-project-search-path '("~/dev"))
;; List project files fresh on every SPC SPC (fd / git ls-files are fast) instead
;; of Doom's persistent cache, which misses files created outside Emacs (CLI,
;; Claude Code, git checkout) until `SPC p i'.
(setq projectile-enable-caching nil)

;; README FIRST
;; Picking a project (SPC p p) opens its README straight away when it has one
;; at its root, instead of asking for a file; otherwise it asks, as Doom does.
;; Several READMEs: Markdown first, then Org, reStructuredText, AsciiDoc, text,
;; none (README); any case (readme.md too).
(defvar +my/project-readme-extensions '("md" "markdown" "org" "rst" "adoc" "txt" "")
  "README file extensions, preferred first (\"\": a README without one).")

(defun +my/project-readme (dir)
  "The README file at DIR's root, if any (see above)."
  (let ((found (seq-filter
                (lambda (file)
                  (and (string-match-p "\\`readme\\(\\.[[:alnum:]]+\\)?\\'" (downcase file))
                       (member (downcase (or (file-name-extension file) ""))
                               +my/project-readme-extensions)
                       (file-regular-p (expand-file-name file dir))))
                (directory-files dir))))
    (when found
      (expand-file-name
       (car (seq-sort-by (lambda (file)
                           (seq-position +my/project-readme-extensions
                                         (downcase (or (file-name-extension file) ""))))
                         #'< found))
       dir))))

(defun +my/project-open-readme (dir)
  "After switching to project DIR: its README, else Doom's file prompt."
  (if-let* ((readme (+my/project-readme dir)))
      (find-file readme)
    (doom-project-find-file dir)))

(setq +workspaces-switch-project-function #'+my/project-open-readme)

;; WORKSPACES REMEMBER THEIR PROJECT
;; What an empty workspace shows is Doom's dashboard, shared by the
;; workspaces, which moves to each one's last project as you switch
;; (`last-project-root'). But leaving a workspace recorded the project of
;; whatever it showed, the dashboard too, still in the previous workspace's
;; project: a workspace whose files were all closed took on another's, and
;; there SPC SPC listed the other project's files and the sidebar followed it.
;; Only files count now, recorded as they're shown; a workspace made for a
;; project (SPC p p) stays in it, one without a file yet starts in ~, never in
;; another's.
(defun +my/workspace-shown-file ()
  "The file buffer the selected window shows, if any. Not the current buffer:
Doom's hook on buffer switches runs in whatever buffer is current, and right
after switching workspace that could still be the previous one's file, whose
project then got recorded as the new workspace's."
  (when-let* (((bound-and-true-p persp-mode))
              ((get-current-persp))
              (buffer (window-buffer)))
    (with-current-buffer buffer
      (and buffer-file-name
           (not (file-remote-p default-directory))
           buffer))))

(defun +my/workspace-record-project-h ()
  "Record the project of the file shown as the current workspace's."
  (when-let* ((buffer (+my/workspace-shown-file))
              (root (with-current-buffer buffer (doom-project-root))))
    (set-persp-parameter 'last-project-root root (get-current-persp))))

(add-hook 'doom-switch-buffer-hook #'+my/workspace-record-project-h)

(defadvice! +my/workspace-record-files-only-a (fn &optional persp &rest args)
  "Leaving a workspace, record its project only from the file it shows (see
above). Not when one is made (PERSP): what's shown is still the previous
workspace's."
  :around #'+dashboard--persp-record-project-h
  (unless (and persp (persp-p persp))
    (when-let* ((buffer (+my/workspace-shown-file)))
      (with-current-buffer buffer
        (apply fn persp args)))))

(defun +my/workspace-project ()
  "The current workspace's project (see above), or nil without workspaces."
  (when (and (bound-and-true-p persp-mode) (get-current-persp))
    (file-name-as-directory
     (expand-file-name (or (persp-parameter '+workspace-project)
                           (persp-parameter 'last-project-root)
                           "~")))))

(defadvice! +my/workspace-own-project-a (&rest _)
  "Entering a workspace, put the dashboard in its project (see above)."
  :override #'+dashboard--persp-detect-project-h
  (when-let* ((project (+my/workspace-project)))
    (+dashboard-update-pwd-h project)))

;; The dashboard's reload also sets its folder, after the above, from the last
;; file visited in any workspace (`+dashboard-pwd-policy' `last-project'):
;; switching with SPC TAB 1, 2... put it back in the previous workspace's
;; project. That's the current workspace's project too now.
(defadvice! +my/workspace-dashboard-pwd-a (fn)
  :around #'+dashboard--pwd
  (or (+my/workspace-project) (funcall fn)))
