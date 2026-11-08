;;; $DOOMDIR/config/beads/theme.el -*- lexical-binding: t; -*-
;; beads.el's faces in the theme's colours. Loaded from config/beads.el.

;; THE THEME'S COLOURS
;; beads.el colours statuses, types and events with names ("yellow", "orange
;; red"...): the theme's faces instead (statuses as the theme's success,
;; warning, error; types as its syntax colours), and a P0 row tinted with the
;; theme's red, as the banner's rows are (config/banner/theme.el).
(defconst +my/beads--faces
  '((beads-status-in-progress . warning)
    (beads-status-closed . success)
    (beads-status-blocked . error)
    (beads-status-hooked . font-lock-constant-face)
    (beads-list-deps-blocked . error)
    (beads-list-deps-parent . warning)
    (beads-list-deps-child . success)
    (beads-type-gate . font-lock-warning-face)
    (beads-type-convoy . font-lock-function-name-face)
    (beads-type-agent . font-lock-keyword-face)
    (beads-type-role . font-lock-string-face)
    (beads-type-rig . font-lock-type-face)
    (beads-activity-create . font-lock-function-name-face)
    (beads-activity-update . warning)
    (beads-activity-completed . success)
    (beads-activity-blocked . error)
    (beads-activity-delete . error)
    (beads-activity-comment . shadow))
  "(FACE . THEME-FACE): beads.el's faces with colour names, the theme's
face each one takes instead.")

(defun +my/beads-faces ()
  "beads.el's faces in the theme's colours (see above)."
  (pcase-dolist (`(,face . ,theme-face) +my/beads--faces)
    (when (facep face)
      ;; Its colour name unset: a spec set here is laid over beads.el's own.
      (face-spec-set face `((t :foreground unspecified :inherit ,theme-face)))))
  (when (facep 'beads-list-row-p0)
    (let ((bg (face-background 'default nil t))
          (red (face-foreground 'error nil t)))
      (face-spec-set
       'beads-list-row-p0
       (if (and (fboundp 'doom-blend)
                (stringp bg) (string-prefix-p "#" bg)
                (stringp red) (string-prefix-p "#" red))
           `((t :background ,(doom-blend red bg 0.15) :extend t))
         '((t :background unspecified :inherit error :extend t)))))))

(after! (:any beads-faces beads-list beads-activity)
  (+my/beads-faces))
(add-hook 'doom-load-theme-hook #'+my/beads-faces)
