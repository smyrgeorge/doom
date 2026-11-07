;;; $DOOMDIR/config/agent-shell/context.el -*- lexical-binding: t; -*-
;; What Claude Code is told about Emacs. Loaded from config/agent-shell.el.

;; INSIDE EMACS (see config/agent-shell.el). agent-shell builds the agent's config each time a
;; session starts (SPC o c, SPC o C, the Option+Enter Claude actions) and sends
;; its session metadata to claude-agent-acp, which adds the `append' text of
;; its `systemPrompt' to Claude Code's system prompt.
(defun +my/agent-shell-claude-theme ()
  "A line on the theme's colours, for the images Claude draws (nil if unknown)."
  (let ((dark (eq (frame-parameter nil 'background-mode) 'dark))
        (bg (face-background 'default nil t))
        (fg (face-foreground 'default nil t)))
    (when (and (stringp bg) (string-prefix-p "#" bg)
               (stringp fg) (string-prefix-p "#" fg))
      (format "Emacs uses a %s theme%s: background %s, text %s. Draw images \
to read well on it: %s."
              (if dark "dark" "light")
              (if custom-enabled-themes
                  (format " (%s)" (car custom-enabled-themes))
                "")
              bg fg
              (if dark
                  "a dark or transparent background, light text and lines"
                "a light or transparent background, dark text and lines")))))

(defadvice! +my/agent-shell-claude-context-a (config)
  "Append `+my/agent-shell-claude-context' to Claude Code's system prompt."
  :filter-return #'agent-shell-anthropic-make-claude-code-config
  (let ((text (string-join (delq nil (list +my/agent-shell-claude-context
                                           (+my/agent-shell-claude-theme)))
                           "\n\n")))
    (setf (alist-get :session-meta config)
          (cons `(systemPrompt . ((append . ,text)))
                (alist-get :session-meta config))))
  config)
