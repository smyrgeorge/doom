;;; $DOOMDIR/config/agent-shell.el -*- lexical-binding: t; -*-
;; A coding agent inside Emacs (agent-shell, via ACP): yours chosen in
;; config.el (`agent-shell-preferred-agent-config'). Loaded from config.el;
;; its code is in config/agent-shell/.

;; ====== VARIABLES ======

;; INSIDE EMACS
;; Every session is told where it runs and what that allows, whatever its
;; agent: appended to its system prompt (its own stays) where it takes one
;; from Emacs, else before its first message (config/agent-shell/context.el).
;; What agent-shell shows (its Markdown: tables, highlighted code;
;; file references as links that open the file at that line; local images
;; inline, saved next to agent-shell's transcripts so they keep showing),
;; reports as Markdown with only their diagrams as images, and the editor
;; itself: the agent can ask Emacs (`emacsclient', the server runs) what you're
;; looking at, carefully. A line on the theme's colours is added when the
;; session starts, so the images it draws suit it.
(define-obsolete-variable-alias '+my/agent-shell-claude-context '+my/agent-shell-context "2026-11-24")
(defvar +my/agent-shell-context
  "You are running inside Emacs, in an agent-shell buffer (the agent-shell \
package, through ACP), not in a terminal. The \
user reads your replies in Emacs and works on the same files there.

Formatting: agent-shell renders Markdown: headings, bold, italic, \
strikethrough, inline code, links, task lists, horizontal rules, tables \
(aligned columns with borders, wrapped to the window's width, so keep them \
to a few columns) and fenced code blocks, highlighted by the Emacs mode of \
their language, so always name it. HTML and LaTeX math show as plain \
text: don't use them.

File references: path:line (also path:line-line or path:line:col), relative \
or absolute, bare or in backticks, become links that open the file at that line.

Images: a Markdown image link to a local file (![chart](/abs/path/chart.png)), \
or an image's absolute path alone on a line, shows inline, up to the window's \
width ({width=50%} right after the link caps it at half). PNG, JPEG, WebP and \
SVG; remote URLs aren't fetched: download an image first. Save the images you \
make under .agent-shell/images/ in your working directory (kept out of git), so \
they still show when a transcript is read later. SVG written directly needs no \
tools; check that others (Graphviz, matplotlib) are installed before relying \
on them.

Reports: write the report itself as Markdown in your reply, not as an HTML \
page or one big image; each diagram, chart or graph its own image, linked where \
it belongs (diagram code too, unless it's drawn in replies).

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
  "What every session is told (see above), the theme's line after it
\(`+my/agent-shell-theme-context'): config/agent-shell/context.el.")

;; DRAWINGS FOR THE AGENT
;; In an agent-shell buffer, C-c C-d (SPC m d) opens a new drawing on its left
;; (in the window there, which shows its own buffer again once the drawing
;; closes; without one, in a new window), in Excalidraw (config/excalidraw.el),
;; saved in the project's .agent-shell/drawings/ (agent-shell's folder, next to
;; its screenshots, out of git). Like agent-shell's artist mode (M-x
;; agent-shell-artist-insert-text-drawing: text art), with Excalidraw. In it:
;;   C-c C-c    insert it into that shell's prompt: saved, exported as a PNG
;;              beside its file (what agents read: not SVG), shown as
;;              agent-shell shows a screenshot; the drawing closes
;;   C-c C-k    discard it: closed, its files deleted
;;   M-p / M-n  an earlier drawing of the folder instead of this one (newest
;;              first, blank ones left out; M-n back past the newest: this
;;              one again), to change and insert again
;; A notice at its top says so, with buttons. Closed otherwise (its tab,
;; SPC b k) with nothing drawn, it leaves no file. It needs what drawings
;; need: a GUI Emacs with xwidgets, and Excalidraw.
(defvar +my/agent-shell-drawings-subdir "drawings"
  "Where drawings for the agent go, in the project's .agent-shell/ folder.")

(defvar +my/agent-shell-excalidraw-mode-map (make-sparse-keymap)
  "Keys of a drawing for the agent (see DRAWINGS FOR THE AGENT above).")

;; ISSUES FOR THE AGENT
;; In a project tracking its issues with Beads (config/beads.el: a .beads/
;; folder, SPC o i), the agent works with them through bd, its command line:
;; - a session started there is told so (`+my/agent-shell-beads-context'),
;;   with Beads' own guide for agents (`bd prime': finding work, claiming,
;;   creating, closing issues, dependencies), with what it's told; the guide
;;   left out for Claude Code where the project's Claude Code settings give
;;   it already (a SessionStart hook running bd prime, as this config's has);
;; - each bd command the agent runs refreshes the issue lists and issues open in
;;   Emacs for that project, so its changes show as it makes them;
;; - C-c C-i (SPC m i) in agent-shell picks one of the project's open issues
;;   (ready ones first) and puts it in the prompt, as its id and title;
;;   C-c C-a (SPC m a) on an issue, in the list or its own buffer, puts it in
;;   the prompt of the project's session.
(defvar +my/agent-shell-beads-context
  "This project tracks its issues with Beads: the bd command line, its \
.beads/ folder. Use bd for the project's tasks. The user \
sees the same issues in Emacs (SPC o i): the issue lists and issues they \
have open there refresh after each bd command you run, so they follow your \
changes. They may hand you an issue as \"Beads issue ID: title\": read it \
with bd show ID. Add --json when you read bd's output. Never run bd edit: it \
opens an editor and waits."
  "Told to a session in a project tracking its issues with Beads (see ISSUES
FOR THE AGENT above), before `bd prime''s guide.")

(defvar +my/agent-shell-beads-prime t
  "Non-nil: Beads' guide for agents (`bd prime') follows
`+my/agent-shell-beads-context' in what a session is told, unless it's Claude
Code's and the project's Claude Code settings run it as a session starts.")

;; DIAGRAMS IN REPLIES
;; ```mermaid blocks in an agent's replies are drawn as diagrams, in the theme's
;; colours (config/mermaid.el: mmdc, in the background), once a block is
;; closed; meanwhile, or for an error (its message under it) or without mmdc,
;; its source. Copying as Markdown, and the transcript, keep the block's
;; source. A theme switch draws them again; they resize with the window, as
;; images do, no taller than it; RET or a click opens one at full size, as an
;; image. Sessions are told so (below), where config/mermaid.el is loaded.
(defvar +my/agent-shell-mermaid-context
  "Diagrams: fenced mermaid blocks (```mermaid) are drawn as diagrams in \
your replies, in the user's theme's colours: use them for flowcharts, \
sequence, state, class and ER diagrams, Gantt charts, mind maps and the \
like, in reports too, instead of rendering diagram code to an image. Mermaid \
11's syntax; keep labels short. A diagram is shrunk to the width of the \
user's pane, often narrow: prefer top-down layouts (flowchart TD) to wide \
left-to-right ones."
  "Told to every session where diagrams are drawn (see
DIAGRAMS IN REPLIES above).")

;; EVIL KEYS
;; With Evil, RET sends the prompt in normal state too (it only moved down a
;; line there), and in insert state as before, S-RET a newline. Or, with
;; `+my/agent-shell-insert-ret-newline' set in config.el, RET in insert state
;; is a newline, the prompt sent from normal state (agent-shell's README,
;; evil-collection's REPLs). In a diff the agent shows (*agent-shell-diff*), the
;; keys its header line names work in normal state, where it opens: n / p the
;; next / previous hunk, y accept, RET open the file (C-c C-c reject and q
;; quit already did). evil-collection's own keys stay: in normal state, while
;; the agent waits for a permission, y allows it, n rejects it (and interrupts
;; it), ! always allows, v views its diff.
(defvar +my/agent-shell-insert-ret-newline nil
  "With Evil, RET in insert state in agent-shell: nil sends the prompt (S-RET
a newline), non-nil inserts a newline (RET in normal state sends). See EVIL
KEYS above.")

;; ====== KEY BINDINGS ======

;; YOUR AGENT HERE (config/agent-shell/here.el): SPC o c starts a session with
;; your agent (`agent-shell-preferred-agent-config', chosen in config.el;
;; none: agent-shell asks which), agent-shell asking which session (a new
;; one, one to resume), shown where agent-shell shows it (with tiling,
;; config/tiling.el: a new pane); SPC o C the same, shown in the window
;; you're in, what it showed kept as a tab.
(map! :leader
      :desc "Agent (agent-shell)" "o c" #'+my/agent-shell-start
      :desc "Agent, here"         "o C" #'+my/agent-shell-here)

;; DRAWINGS FOR THE AGENT (see above): C-c C-d next to agent-shell's own C-c keys.
(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c C-d" #'+my/agent-shell-excalidraw
      :localleader
      :desc "Draw for the agent" "d" #'+my/agent-shell-excalidraw)

;; ISSUES FOR THE AGENT (see above): an issue into the prompt, from agent-shell
;; or from Beads' list and issues.
(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c C-i" #'+my/agent-shell-beads-insert
      :localleader
      :desc "Issue for the agent" "i" #'+my/agent-shell-beads-insert)

(map! :after beads-list
      :map beads-list-mode-map
      "C-c C-a" #'+my/agent-shell-beads-send
      :localleader
      :desc "To the agent" "a" #'+my/agent-shell-beads-send)

(map! :after beads-detail
      :map (beads-detail-mode-map beads-detail-vui-mode-map)
      "C-c C-a" #'+my/agent-shell-beads-send
      :localleader
      :desc "To the agent" "a" #'+my/agent-shell-beads-send)

(map! :map +my/agent-shell-excalidraw-mode-map
      "C-c C-c" #'+my/agent-shell-excalidraw-insert
      "C-c C-k" #'+my/agent-shell-excalidraw-discard
      "M-p"     #'+my/agent-shell-excalidraw-previous
      "M-n"     #'+my/agent-shell-excalidraw-next)

;; EVIL KEYS (see above).
(map! :after agent-shell
      :map agent-shell-mode-map
      :n "RET" #'agent-shell-submit
      (:when +my/agent-shell-insert-ret-newline
       :i "RET" #'newline))

(map! :after agent-shell-diff
      :map agent-shell-diff-mode-map
      :n "n"   #'diff-hunk-next
      :n "p"   #'diff-hunk-prev
      :n "y"   #'agent-shell-diff-accept-all
      :n "RET" #'agent-shell-diff-open-file)

;; ====== CODE ======

;; AGENT-SHELL (coding agents via ACP): which agent, and its login, are
;; chosen in config.el.
(use-package! agent-shell
  :commands (agent-shell)
  :config
  ;; AGENT BUFFERS: a session's buffer is named after its agent alone
  ;; (config/agent-shell/name.el): "Claude", a second one "Claude<2>" (in any
  ;; project: buffer names are Emacs's, not a project's), and so every agent
  ;; ("Codex", "Gemini"...), not "Claude Agent @ doom".
  (setq agent-shell-buffer-name-format #'+my/agent-shell-buffer-name
        ;; Images (screenshots, charts) as wide as the window (beside a
        ;; reply's indent: config/agent-shell/images.el): agent-shell shrinks
        ;; them to 40% of it. Smaller ones keep their own size.
        ;; One image only: {width=100%} after its link; the ones on screen:
        ;; M-x agent-shell-markdown-image-scale-increase / -decrease.
        agent-shell-markdown-image-max-width 1.0))

;; In config/agent-shell/, in this order: each part can use what the ones
;; before it define.
(load! "agent-shell/name")
(load! "agent-shell/context")
(load! "agent-shell/images")
(load! "agent-shell/excalidraw")
(load! "agent-shell/beads")
(load! "agent-shell/mermaid")
(load! "agent-shell/prompt")
(load! "agent-shell/indent-guides")
(load! "agent-shell/nyan")
(load! "agent-shell/here")
(load! "agent-shell/permissions")
