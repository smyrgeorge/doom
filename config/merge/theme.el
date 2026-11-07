;;; $DOOMDIR/config/merge/theme.el -*- lexical-binding: t; -*-
;; The changes tinted with the theme's colours. Loaded from config/merge.el.

;; THEME
;; The changes tinted with the theme's colours: the colour
;; blended into the theme's background, where colours are true (the GUI, a
;; terminal with 24-bit colour). With 256 colours a blend comes out as the
;; palette's nearest (teal, salmon): the palette's darkest tint of the colour
;; instead (a light theme's: lightest). With fewer, the faces they inherit.
;; The theme's colours, not a frame's: the GUI's server makes terminal frames
;; too, and a daemon's first frame has none.
(defconst +my/merge--tints
  '((+my/merge-changed  blue  0.25 "#00005f" "#d7d7ff")
    (+my/merge-added    green 0.25 "#005f00" "#d7ffd7")
    (+my/merge-removed  base5 0.35 "#3a3a3a" "#d0d0d0")
    (+my/merge-conflict red   0.25 "#5f0000" "#ffd7d7")
    (+my/merge-filler   base5 0.12 "#1c1c1c" "#e4e4e4"))
  "(FACE THEME-COLOUR AMOUNT DARK-256 LIGHT-256): see above.")

(defun +my/merge-faces-h ()
  "The changes tinted with the theme's colours (see above)."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (doom-color 'bg)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (let ((dark (color-dark-p (color-name-to-rgb bg))))
          (pcase-dolist (`(,face ,colour ,amount ,dark-256 ,light-256) +my/merge--tints)
            (when-let* ((tint (doom-color colour))
                        ((stringp tint))
                        ((string-prefix-p "#" tint)))
              (face-spec-set
               ;; Not inheriting diff-mode's faces then: their foregrounds
               ;; would hide the code's colours.
               face `((((min-colors 257)) :inherit nil :background ,(doom-blend tint bg amount))
                      (((min-colors 256)) :inherit nil :background ,(if dark dark-256 light-256))
                      (t))))))))))

(+my/merge-faces-h)
(add-hook 'doom-load-theme-hook #'+my/merge-faces-h)
