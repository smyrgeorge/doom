;;; $DOOMDIR/config/terminal.el -*- lexical-binding: t; -*-
;; Terminal (tty) Emacs tweaks. Loaded from config.el.

;; TERMINAL
;; Paint the terminal's own background (the strip below the echo area) with the
;; theme's background via OSC 11, and restore it (OSC 111) when Emacs exits.
(defun +my/tty-sync-bg-h (&rest _)
  (dolist (frame (frame-list))
    (when (eq (framep frame) t)         ; tty frame
      (when-let* ((bg (face-background 'default frame))
                  ((string-prefix-p "#" bg)))
        (send-string-to-terminal (format "\e]11;%s\a" bg)
                                 (frame-terminal frame))))))
(defun +my/tty-reset-bg-h (&rest _)
  (dolist (frame (frame-list))
    (when (eq (framep frame) t)
      (send-string-to-terminal "\e]111\a" (frame-terminal frame)))))
(add-hook 'doom-load-theme-hook #'+my/tty-sync-bg-h)
(add-hook 'tty-setup-hook #'+my/tty-sync-bg-h)
(add-hook 'after-make-frame-functions #'+my/tty-sync-bg-h)
(add-hook 'kill-emacs-hook #'+my/tty-reset-bg-h)
;; emacsclient -t: restore the terminal when its frame is closed.
(add-hook 'delete-frame-functions
          (defun +my/tty-reset-frame-bg-h (frame)
            (when (eq (framep frame) t)
              (send-string-to-terminal "\e]111\a" (frame-terminal frame)))))
