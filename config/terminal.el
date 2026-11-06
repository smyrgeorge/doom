;;; $DOOMDIR/config/terminal.el -*- lexical-binding: t; -*-
;; Terminal (tty) Emacs tweaks. Loaded from config.el.

;; TERMINAL
;; Paint the terminal's own background (the strip below the echo area) with the
;; theme's background via OSC 11, and give the terminal its own back when Emacs
;; exits or an emacsclient -t frame closes. Its own: asked before the first
;; paint (OSC 11 ?), set back with OSC 11. OSC 111 (reset) only where it didn't
;; answer: iTerm2 ignores 111, and the theme's colour stayed after Emacs (after
;; cmd/diff.sh, emacs -nw). Only once the terminal is set up (its
;; term/xterm.el loaded, which makes the query): `emacs -nw' loads Doom's
;; theme before that, and tty-setup-hook paints then.
(defun +my/tty--query (frame query handler)
  "Send QUERY to FRAME's terminal; HANDLER reads the reply (after its first
characters, \e]11;). Asynchronous: the reply is read with the input, nothing
waited for, nothing typed ahead lost."
  (with-selected-frame frame
    (let ((xterm-query-timeout nil))
      (xterm--query query `(("\e]11;" . ,handler))))))

(defun +my/tty--ask-bg (frame)
  "Ask FRAME's terminal its background, once, before it's painted: the
terminal answers in order, before the paint (see above)."
  (let ((terminal (frame-terminal frame)))
    (unless (terminal-parameter terminal '+my/tty-bg-asked)
      (set-terminal-parameter terminal '+my/tty-bg-asked t)
      (when (fboundp 'xterm--query)
        (+my/tty--query frame "\e]11;?\e\\"
                        (lambda () (+my/tty--bg-reply terminal)))))))

(defun +my/tty--bg-reply (terminal)
  "Read TERMINAL's reply to the background query (rgb:R/G/B, up to ST or
BEL), and keep the colour to give back."
  (let ((reply "")
        chr)
    (while (and (setq chr (read-event nil nil 0.5))
                (characterp chr)
                (not (eq chr ?\a))
                (not (and (eq chr ?\\) (string-suffix-p "\e" reply))))
      (setq reply (concat reply (string chr))))
    (when (string-match "rgb:[[:xdigit:]]+/[[:xdigit:]]+/[[:xdigit:]]+" reply)
      (set-terminal-parameter terminal '+my/tty-bg (match-string 0 reply)))))

(defun +my/tty--give-back-bg (terminal)
  "Give TERMINAL its own background back (see above)."
  (send-string-to-terminal
   (if-let* ((bg (terminal-parameter terminal '+my/tty-bg)))
       (format "\e]11;%s\a" bg)
     "\e]111\a")
   terminal))

(defun +my/tty-sync-bg-h (&rest _)
  (dolist (frame (frame-list))
    (when (eq (framep frame) t)         ; tty frame
      (when-let* (((terminal-parameter (frame-terminal frame) 'terminal-initted))
                  (bg (face-background 'default frame))
                  ((string-prefix-p "#" bg)))
        (+my/tty--ask-bg frame)
        (send-string-to-terminal (format "\e]11;%s\a" bg)
                                 (frame-terminal frame))))))
(defun +my/tty-reset-bg-h (&rest _)
  (dolist (frame (frame-list))
    (when (eq (framep frame) t)
      (+my/tty--give-back-bg (frame-terminal frame)))))
(add-hook 'doom-load-theme-hook #'+my/tty-sync-bg-h)
(add-hook 'tty-setup-hook #'+my/tty-sync-bg-h)
(add-hook 'after-make-frame-functions #'+my/tty-sync-bg-h)
(add-hook 'kill-emacs-hook #'+my/tty-reset-bg-h)
;; emacsclient -t: restore the terminal when its frame is closed. When the
;; terminal itself went away (its window closed), the frame is already dead
;; here: nothing to restore. Nor while another frame of that terminal stays
;; (C-x 5 0 of one of two): it still shows the theme's background. First of
;; the hook (depth -90): the server's `server-handle-delete-frame', added
;; after this when the server starts, closes the client's terminal, and
;; after it nothing reached the terminal (cmd/diff.sh: the theme's stayed).
(defun +my/tty-reset-frame-bg-h (frame)
  (when (and (frame-live-p frame) (eq (framep frame) t)
             (not (seq-some (lambda (other)
                              (and (not (eq other frame))
                                   (eq (frame-terminal other) (frame-terminal frame))))
                            (frame-list))))
    (ignore-errors
      (+my/tty--give-back-bg (frame-terminal frame)))))
(add-hook 'delete-frame-functions #'+my/tty-reset-frame-bg-h -90)

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

;; TOOLTIPS
;; Hover help (e.g. a warning's message on its text) shows in the echo area,
;; never in a tooltip: Doom turns tooltips off. But it also turns on
;; `tty-tip-mode' (tips in a small child frame) when a terminal frame opens,
;; and that mode is global: after an `emacsclient -t', GUI frames drew their
;; tips the terminal's way, at the frame's top-left corner. Not anywhere.
(remove-hook 'tty-setup-hook #'tty-tip-mode)
