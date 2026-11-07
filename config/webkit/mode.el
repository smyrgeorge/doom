;;; $DOOMDIR/config/webkit/mode.el -*- lexical-binding: t; -*-
;; The mode WebKit pages derive from. Loaded from config/webkit.el.

;; THE MODE
(define-derived-mode +my/webkit-mode special-mode "WebKit"
  "A web page in WebKit, a view per window showing the buffer (see
config/webkit.el). Modes derive from it, saying in their body what their page
is (`+my/webkit-url-function'...)."
  (require 'xwidget)
  (setq-local buffer-read-only t
              cursor-type nil
              ;; (list nil): see Doom's pdf module, emacs-evil/evil#2016.
              evil-normal-state-cursor (list nil)
              evil-motion-state-cursor (list nil)
              left-fringe-width 0
              right-fringe-width 0)
  (with-silent-modifications
    ;; Some text for the views to be shown over (point stays at its start,
    ;; see `+my/webkit--home-h').
    (when (= (point-min) (point-max))
      (let ((inhibit-read-only t))
        (insert " ")
        (goto-char (point-min))))
    ;; Nothing shown but the views (see VIEWS, NO WHITE FLASH in views.el).
    (put-text-property (point-min) (point-max) 'display ""))
  (add-hook 'window-buffer-change-functions #'+my/webkit--shown-h nil t)
  (add-hook 'window-size-change-functions #'+my/webkit--fit-h nil t)
  (add-hook 'post-command-hook #'+my/webkit--home-h nil t)
  ;; Last: a mode's own (keeping its place, say) still see the views.
  (add-hook 'change-major-mode-hook #'+my/webkit--stop 90 t)
  (add-hook 'kill-buffer-hook #'+my/webkit--stop 90 t)
  ;; Already on screen (the mode turned on in a shown buffer): no window will
  ;; change buffer to start a view. Started after this command, once the
  ;; derived mode's body has said what the page is.
  (dolist (window (get-buffer-window-list nil 'nomini 'visible))
    (+my/webkit--shown-h window)))
