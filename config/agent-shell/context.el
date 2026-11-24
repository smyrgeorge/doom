;;; $DOOMDIR/config/agent-shell/context.el -*- lexical-binding: t; -*-
;; What every session is told about Emacs, whatever its agent. Loaded from
;; config/agent-shell.el.

;; WHAT A SESSION IS TOLD (see INSIDE EMACS in config/agent-shell.el): worked
;; out as a session starts (`agent-shell--start': where it starts, a crew's
;; or a run's agent bound), kept in its config (:+my/context). An agent that
;; takes a system prompt from Emacs (ACP's systemPrompt session capability:
;; Claude Code's adapter does) has it appended to its own, in every session
;; it starts or resumes (agent-shell's `agent-shell--system-prompt'). One that
;; doesn't is told it once, before the first message of a new session, a
;; block of its own (a resumed one has it in its history already).
(defun +my/agent-shell-theme-context ()
  "A line on the theme's colours, for the images the agent draws (nil if
unknown)."
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

(define-obsolete-function-alias '+my/agent-shell-claude-theme #'+my/agent-shell-theme-context "2026-11-24")

(define-obsolete-variable-alias '+my/agent-shell-claude-context-functions
  '+my/agent-shell-context-functions "2026-11-24")

(defvar +my/agent-shell-context-functions (list #'+my/agent-shell-theme-context)
  "Functions each returning more of what a session is told, or nil,
appended after `+my/agent-shell-context' in this order: the theme's line; a
project's issues (config/agent-shell/beads.el); Mermaid's diagrams
\(config/agent-shell/mermaid.el); the Agent UI canvas (config/agent-ui.el);
a crew's agent (config/agent-workspace.el); a run's agent
\(config/agent-workflow.el).")

(defvar +my/agent-shell-context-config nil
  "While what a session is told is worked out: its config (agent-shell's:
its :identifier, claude-code, codex...), for what is its agent's own.")

(defun +my/agent-shell-context-text (&optional config)
  "What a session starting now is told: `+my/agent-shell-context', then
what `+my/agent-shell-context-functions' return; CONFIG, the session's
\(`+my/agent-shell-context-config' while they run)."
  (let ((+my/agent-shell-context-config config))
    (string-join (delq nil (cons +my/agent-shell-context
                                 (mapcar #'funcall +my/agent-shell-context-functions)))
                 "\n\n")))

(defadvice! +my/agent-shell-context-start-a (args)
  "A session starting (`agent-shell--start''s ARGS): what it's told, worked
out now, kept in its config (:+my/context); one given it already keeps it."
  :filter-args #'agent-shell--start
  (let ((config (plist-get args :config)))
    (if (or (null config) (assq :+my/context config))
        args
      (plist-put (copy-sequence args) :config
                 (cons (cons :+my/context (+my/agent-shell-context-text config)) config)))))

(defadvice! +my/agent-shell-system-prompt-a (fn)
  "agent-shell's system prompt (FN's: `agent-shell-system-prompt', its
config's), then what the session is told, for an agent taking one."
  :around #'agent-shell--system-prompt
  (let ((own (funcall fn)))
    (if-let* (((map-elt agent-shell--state :supports-system-prompt))
              (told (map-nested-elt agent-shell--state '(:agent-config :+my/context))))
        (string-join (delq nil (list own told)) "\n\n")
      own)))

(defvar-local +my/agent-shell--context-pending nil
  "In a new session whose agent takes no system prompt: what it's told,
until its first message goes (before it, a block of its own).")

(defadvice! +my/agent-shell-context-new-session-a (&rest args)
  "A new session (ARGS, `agent-shell--initiate-new-session''s): its agent
taking no system prompt, what it's told waits for its first message."
  :before #'agent-shell--initiate-new-session
  (with-current-buffer (or (plist-get args :shell-buffer) (current-buffer))
    (setq +my/agent-shell--context-pending
          (and (not (map-elt agent-shell--state :supports-system-prompt))
               (map-nested-elt agent-shell--state '(:agent-config :+my/context))))))

(defun +my/agent-shell--context-block (text)
  "TEXT, what a session is told, as its first message's first block."
  `((type . "text")
    (text . ,(concat "What follows is this session's system prompt from Emacs (your agent takes \
none from it): follow it for the whole session. The user's first message comes \
after it.\n\n<system-prompt>\n" text "\n</system-prompt>"))))

(defadvice! +my/agent-shell-context-blocks-a (blocks)
  "A message's content BLOCKS: the first of a new session whose agent takes
no system prompt, what it's told first (`+my/agent-shell--context-pending')."
  :filter-return #'agent-shell--prompt-content-blocks
  (if-let* ((text +my/agent-shell--context-pending))
      (progn
        (setq +my/agent-shell--context-pending nil)
        (vconcat (vector (+my/agent-shell--context-block text)) blocks))
    blocks))

;; CONTEXT FROM THE CURRENT BUFFER
;; Starting a session (SPC o c), agent-shell takes what's at point as context:
;; a region, an error, files: dired's marked ones, asked of dired in any buffer.
;; Outside dired, dired takes a line starting with a date (an issue in Beads'
;; list: 2026-11-08 ...) for a file's, then fails (no subdir-alist): the
;; session never opened. Dired's files only in dired; elsewhere, the image
;; you're on (image-mode: its file), not any buffer of an image file's: an
;; SVG's source, its selection replaced by the whole file. In dired, those of
;; the region, else the marked ones: with none marked, dired gives the file at
;; point (even . or .., the folder itself or its parent), which went into
;; every session started there. Sending a file to Claude
;; (agent-shell-send-file) is as agent-shell has it: the file at point too.
(defun +my/agent-shell--dired-files ()
  "Dired's files for a session: the region's, else the marked ones; nil with
none marked; never . or .. (see above)."
  (seq-remove (lambda (file) (member (file-name-nondirectory file) '("." "..")))
              (or (agent-shell--dired-paths-in-region)
                  (and (save-excursion
                         (goto-char (point-min))
                         (re-search-forward (dired-marker-regexp) nil t))
                       (dired-get-marked-files)))))

(defun +my/agent-shell-buffer-files-a (fn &rest args)
  "`agent-shell--buffer-files': dired's files in dired only, for a session
only those chosen; elsewhere the image shown (see above)."
  (cond ((not (derived-mode-p 'dired-mode))
         (let ((file (buffer-file-name)))
           (and (plist-get args :obvious)
                file
                (derived-mode-p 'image-mode)
                (image-supported-file-p file)
                (list file))))
        ((plist-get args :obvious)
         (+my/agent-shell--dired-files))
        (t
         (apply fn args))))

(advice-add 'agent-shell--buffer-files :around #'+my/agent-shell-buffer-files-a)
