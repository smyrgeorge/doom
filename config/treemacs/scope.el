;;; $DOOMDIR/config/treemacs/scope.el -*- lexical-binding: t; -*-
;; The sidebar of each workspace (persp-mode's: treemacs-persp's scope), its
;; own. Loaded from config/treemacs.el.

;; ITS OWN TREEMACS WORKSPACE, AT ONCE
;; treemacs-persp gives a workspace its treemacs workspace ("Perspective
;; NAME") 0.1 s after it's switched to (a timer). Asked for one before that, a
;; scope with none yet took treemacs's pick: the one holding the buffer's
;; file, else the first in the list, another workspace's ("Perspective
;; doom"). The sidebar opened then (the first project file shown in a new
;; workspace: config/treemacs/follow.el's auto-open, "exclusively") replaced
;; that one's projects: the other workspace's sidebar showed the new project,
;; drawn out of step with it once switched back. The nil workspace (child
;; frames, a new frame not in one yet: "No Perspective") shared it the same
;; way. Now a scope with none gets its own first: treemacs-persp's, by its
;; name, made if missing.
(defvar +my/treemacs--ensuring nil
  "Non-nil while a scope's treemacs workspace is being made (no recursion).")

(defadvice! +my/treemacs-own-workspace-a (fn &rest args)
  :around #'treemacs-current-workspace
  (when (and (not +my/treemacs--ensuring)
             (not (bound-and-true-p treemacs-override-workspace))
             (eq (bound-and-true-p treemacs--current-scope-type) 'treemacs-persp-scope)
             (fboundp 'treemacs-persp--ensure-workspace-exists)
             (not (treemacs-current-scope-shelf)))
    (let ((+my/treemacs--ensuring t))
      (treemacs-persp--ensure-workspace-exists)))
  (apply fn args))

;; NO TWO OF A NAME
;; A workspace renamed (Doom's "#1" named after its project) renamed its
;; treemacs workspace too, even to a name another one had (left from an
;; earlier session, its workspace closed): two "Perspective doom", the first
;; found by name, the other never. Now the one that had the name goes (no
;; workspace open has that name: it's the renamed one's now): the renamed
;; workspace's, shown, keeps its projects.
(defadvice! +my/treemacs-persp-rename-no-duplicate-a (fn perspective old-name new-name)
  :around #'treemacs-persp--on-perspective-rename
  (when-let* ((taken (treemacs--find-workspace-by-name (treemacs-persp--format-workspace-name new-name)))
              (old (treemacs--find-workspace-by-name (treemacs-persp--format-workspace-name old-name)))
              ((not (eq taken old))))
    (setq treemacs--workspaces (delq taken treemacs--workspaces)))
  (funcall fn perspective old-name new-name))
