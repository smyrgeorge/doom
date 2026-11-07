;;; $DOOMDIR/config/banner/theme.el -*- lexical-binding: t; -*-
;; The rows tinted with the theme's colours. Loaded from config/banner.el.

(defun +my/banner-faces-h ()
  "Each type's row tinted with its theme colour."
  (when (and (fboundp 'doom-blend) (fboundp 'doom-color))
    (let ((bg (face-background 'default nil t)))
      (when (and (stringp bg) (string-prefix-p "#" bg))
        (pcase-dolist (`(,type ,_ ,colour) +my/banner-types)
          (when-let* ((tint (doom-color colour))
                      ((stringp tint)))
            (set-face-attribute (+my/banner--face type) nil
                                :inherit 'header-line
                                :background (doom-blend tint bg 0.2)
                                :foreground (face-foreground 'default nil t)))))))
  (cl-incf +my/banner--theme)
  (+my/banner--sync-soon))

(+my/banner-faces-h)

(add-hook 'doom-load-theme-hook #'+my/banner-faces-h)
