;;; $DOOMDIR/config/agent-shell.el -*- lexical-binding: t; -*-
;; Claude Code inside Emacs (agent-shell, via ACP). Loaded from config.el.

;; ====== VARIABLES ======

;; INSIDE EMACS
;; Claude Code is told where it runs and what that allows, appended to its
;; system prompt (Claude Code's own stays) in every session it starts or
;; resumes. What agent-shell shows (its Markdown: tables, highlighted code;
;; file references as links that open the file at that line; local images
;; inline, saved next to agent-shell's transcripts so they keep showing),
;; reports as Markdown with only their diagrams as images, and the editor
;; itself: Claude can ask Emacs (`emacsclient', the server runs) what you're
;; looking at, carefully. A line on the theme's colours is added when the
;; session starts, so the images it draws suit it.
(defvar +my/agent-shell-claude-context
  "You are running inside Emacs, in an agent-shell buffer (the agent-shell \
package, through the claude-agent-acp ACP adapter), not in a terminal. The \
user reads your replies in Emacs and works on the same files there.

Formatting: agent-shell renders Markdown: headings, bold, italic, \
strikethrough, inline code, links, task lists, horizontal rules, tables \
(aligned columns with borders, wrapped to the window's width, so keep them \
to a few columns) and fenced code blocks, highlighted by the Emacs mode of \
their language, so always name it. HTML, LaTeX math and Mermaid show as \
plain text: don't use them.

File references: cite code as path:line (also path:line-line or \
path:line:col), bare or in backticks, with paths relative to your working \
directory or absolute. agent-shell turns references to existing files into \
links that open the file at that line.

Images: a Markdown image link to a local file, such as \
![chart](/abs/path/chart.png), or an image's absolute path alone on a line, \
is shown inline, up to the window's width ({width=50%} right after the link \
caps it at half). PNG, JPEG, WebP and SVG work; remote URLs aren't fetched, \
so download an image first. Save the images you make under \
.agent-shell/images/ in your working directory, next to agent-shell's \
transcripts (kept out of git), so they still show when a transcript is read \
later. Show charts, diagrams and screenshots this way. SVG written directly \
needs no tools; check that others (e.g. Graphviz, matplotlib) are installed \
before relying on them.

Reports: when asked for a report with diagrams, charts or graphs, write the \
report itself as Markdown in your reply, not as an HTML page or one big \
image. Render each diagram or graph as its own image and link it where it \
belongs; render diagram code such as Mermaid to an image too.

The editor: the user's Emacs (Doom Emacs, configured in ~/.config/doom) \
runs a server, so emacsclient reaches it from your shell. emacsclient --eval \
can tell you what the user is looking at (the buffers in their windows, the \
file and line at point, the active region, flycheck or LSP diagnostics), and \
can open a file at a line in another window when they ask to see something. \
Your Lisp runs inside the editor the user is typing in, and Emacs is \
single-threaded: keep each eval quick and bounded, never call anything that \
waits for input, and change windows, buffers or settings only when asked. \
Emacs reloads a file you edit when its buffer is next shown, unless the \
buffer has unsaved changes: before editing a file the user has open, check \
that its buffer isn't modified."
  "Appended to Claude Code's system prompt in agent-shell (see above), with
`+my/agent-shell-claude-theme'.")

;; ====== KEY BINDINGS ======

(map! :leader
      :desc "Claude Code (agent-shell)" "o c" #'agent-shell-anthropic-start-claude-code
      :desc "Agent shell"               "o C" #'agent-shell)

;; ====== CODE ======

;; AGENT-SHELL (Claude Code via ACP)
;; Uses the Claude CLI login (run `claude` once in a terminal to log in).
(use-package! agent-shell
  :commands (agent-shell agent-shell-anthropic-start-claude-code)
  :config
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t)
        ;; New shells (e.g. from the Option+Enter Claude actions) start Claude
        ;; Code without asking which agent to use.
        agent-shell-preferred-agent-config 'claude-code
        ;; Images (screenshots, charts) as wide as the window: agent-shell
        ;; shrinks them to 40% of it. Smaller ones keep their own size.
        ;; One image only: {width=100%} after its link; the ones on screen:
        ;; M-x agent-shell-markdown-image-scale-increase / -decrease.
        agent-shell-markdown-image-max-width 1.0))

;; INSIDE EMACS (see above). agent-shell builds the agent's config each time a
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
