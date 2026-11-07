;;; $DOOMDIR/config/agent-shell.el -*- lexical-binding: t; -*-
;; Claude Code inside Emacs (agent-shell, via ACP). Loaded from config.el; its
;; code is in config/agent-shell/.

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

;; DRAWINGS FOR CLAUDE
;; In an agent-shell buffer, C-c C-d (SPC m d) opens a new drawing on its left
;; (in the window there, which shows its own buffer again once the drawing
;; closes; without one, in a new window), in Excalidraw (config/excalidraw.el),
;; saved in the project's .agent-shell/drawings/ (agent-shell's folder, next to
;; its screenshots, out of git). Like agent-shell's artist mode (M-x
;; agent-shell-artist-insert-text-drawing: text art), with Excalidraw. In it:
;;   C-c C-c    insert it into that shell's prompt: saved, exported as a PNG
;;              beside its file (what Claude reads: not SVG), shown as
;;              agent-shell shows a screenshot; the drawing closes
;;   C-c C-k    discard it: closed, its files deleted
;;   M-p / M-n  an earlier drawing of the folder instead of this one (newest
;;              first; M-n back past the newest: this one again), to change
;;              and insert again
;; A notice at its top says so, with buttons. It needs what drawings need: a
;; GUI Emacs with xwidgets, and Excalidraw.
(defvar +my/agent-shell-drawings-subdir "drawings"
  "Where drawings for Claude go, in the project's .agent-shell/ folder.")

(defvar +my/agent-shell-excalidraw-mode-map (make-sparse-keymap)
  "Keys of a drawing for Claude (see DRAWINGS FOR CLAUDE above).")

;; ====== KEY BINDINGS ======

(map! :leader
      :desc "Claude Code (agent-shell)" "o c" #'agent-shell-anthropic-start-claude-code
      :desc "Agent shell"               "o C" #'agent-shell)

;; DRAWINGS FOR CLAUDE (see above): C-c C-d next to agent-shell's own C-c keys.
(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c C-d" #'+my/agent-shell-excalidraw
      :localleader
      :desc "Draw for Claude" "d" #'+my/agent-shell-excalidraw)

(map! :map +my/agent-shell-excalidraw-mode-map
      "C-c C-c" #'+my/agent-shell-excalidraw-insert
      "C-c C-k" #'+my/agent-shell-excalidraw-discard
      "M-p"     #'+my/agent-shell-excalidraw-previous
      "M-n"     #'+my/agent-shell-excalidraw-next)

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
        ;; A session opens in a new pane where the tiling strategy puts it
        ;; (config/tiling.el), as SPC w SPC does; one already shown is
        ;; selected.
        agent-shell-display-action '(+my/tiling-display-buffer)
        ;; Images (screenshots, charts) as wide as the window: agent-shell
        ;; shrinks them to 40% of it. Smaller ones keep their own size.
        ;; One image only: {width=100%} after its link; the ones on screen:
        ;; M-x agent-shell-markdown-image-scale-increase / -decrease.
        agent-shell-markdown-image-max-width 1.0))

;; In config/agent-shell/, in this order: each part can use what the ones
;; before it define.
(load! "agent-shell/context")
(load! "agent-shell/excalidraw")
