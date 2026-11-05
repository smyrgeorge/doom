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
;; emacsclient -t: restore the terminal when its frame is closed. When the
;; terminal itself went away (its window closed), the frame is already dead
;; here: nothing to restore.
(add-hook 'delete-frame-functions
          (defun +my/tty-reset-frame-bg-h (frame)
            (when (and (frame-live-p frame) (eq (framep frame) t))
              (ignore-errors
                (send-string-to-terminal "\e]111\a" (frame-terminal frame))))))

;; MENU BAR
;; Doom hides the menu bar except in macOS GUI frames, where it lives in the
;; system's menu bar. With `menu-bar-mode' on, terminal frames got one too: a
;; "File Edit Options ..." row at the top. Not in terminal frames.
(defun +my/tty-no-menu-bar-h (&optional frame)
  (let ((frame (or frame (selected-frame))))
    (when (and (eq (framep frame) t)
               (not (eql (frame-parameter frame 'menu-bar-lines) 0)))
      (set-frame-parameter frame 'menu-bar-lines 0))))
(add-hook 'after-make-frame-functions #'+my/tty-no-menu-bar-h)
(add-hook 'tty-setup-hook #'+my/tty-no-menu-bar-h) ; emacs -nw: the first frame
