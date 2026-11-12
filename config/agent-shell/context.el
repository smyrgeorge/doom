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

(defvar +my/agent-shell-claude-context-functions (list #'+my/agent-shell-claude-theme)
  "Functions each returning more for Claude Code's system prompt, or nil,
appended after `+my/agent-shell-claude-context' in this order: the theme's
line; a project's issues (config/agent-shell/beads.el); Mermaid's diagrams
\(config/agent-shell/mermaid.el); the Agent UI canvas (config/agent-ui.el).")

(defadvice! +my/agent-shell-claude-context-a (config)
  "Append `+my/agent-shell-claude-context' (and what
`+my/agent-shell-claude-context-functions' return) to Claude Code's system
prompt."
  :filter-return #'agent-shell-anthropic-make-claude-code-config
  (let ((text (string-join (delq nil (cons +my/agent-shell-claude-context
                                           (mapcar #'funcall
                                                   +my/agent-shell-claude-context-functions)))
                           "\n\n")))
    (setf (alist-get :session-meta config)
          (cons `(systemPrompt . ((append . ,text)))
                (alist-get :session-meta config))))
  config)

;; CONTEXT FROM THE CURRENT BUFFER
;; Starting a session (SPC o c), agent-shell takes what's at point as context:
;; a region, an error, files: dired's marked ones, asked of dired in any buffer.
;; Outside dired, dired takes a line starting with a date (an issue in Beads'
;; list: 2026-11-08 ...) for a file's, then fails (no subdir-alist): the
;; session never opened. Dired's files only in dired; elsewhere, as agent-shell
;; has it (an image file buffer: its file).
(defun +my/agent-shell-buffer-files-a (fn &rest args)
  "`agent-shell--buffer-files': dired's files in dired only (see above)."
  (if (derived-mode-p 'dired-mode)
      (apply fn args)
    (let ((file (buffer-file-name)))
      (and (plist-get args :obvious)
           file
           (image-supported-file-p file)
           (list file)))))

(advice-add 'agent-shell--buffer-files :around #'+my/agent-shell-buffer-files-a)
