;;; $DOOMDIR/config/modeline.el -*- lexical-binding: t; -*-
;; Mode line (doom-modeline) tweaks. Loaded from config.el.

;; ====== CODE ======

;; MODE LINE
;; A space after the mode line's last item on the right (e.g. flycheck's
;; checkmark), which touched the window's edge. In every layout doom-modeline
;; has (file buffers, magit, treemacs...).
(after! doom-modeline
  (dolist (modeline doom-modeline--modelines)
    (pcase-let ((`(,name ,lhs ,rhs) modeline))
      (when (and rhs (not (equal (car (last rhs)) " ")))
        (doom-modeline-def-modeline name lhs (append rhs '(" ")))))))
