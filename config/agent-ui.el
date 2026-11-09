;;; $DOOMDIR/config/agent-ui.el -*- lexical-binding: t; -*-
;; Agent UI: what a coding agent (Claude Code in agent-shell) shows you in
;; Emacs beyond its replies: progress bars, tables, charts, on a canvas beside
;; its session, updated as things change (docs/agent-ui.md). Loaded from
;; config.el; its code is in config/agent-ui/.

;; ====== VARIABLES ======

;; ELEMENT TYPES
;; An element is data: JSON from the agent, a plist here, of a type defined
;; once with `agent-ui-define' (config/agent-ui/core.el): its properties, a
;; drawing as text and, optionally, one for the GUI. Its drawing failing shows
;; the error in its place. Limits keep drawing quick (Emacs has one thread):
;; `agent-ui-max-chars', `agent-ui-max-rows'.

;; THE CANVAS
;; A buffer per agent session, "Agent UI: NAME" (config/agent-ui/canvas.el):
;; its elements in the order shown, each redrawn in place when it changes,
;; `agent-ui-redraw-delay' after (updates within it drawn together); animated
;; ones every `agent-ui-animation-interval'. It opens in a tiled pane (one of
;; tiling's applications, config/tiling.el) when an element is added while
;; it's in no window, without taking the focus. In it: g r redraws it, q hides it. At
;; most `agent-ui-max-elements'.

;; THE AGENT'S WAY IN
;; cmd/agent-ui, from the agent's shell: show, update, append, remove... an
;; element as JSON, the reply as JSON (config/agent-ui/request.el), through
;; emacsclient. Each agent-shell session starts its agent with
;; AGENT_UI_SESSION, so its requests go to its own canvas, which closes with
;; it (config/agent-ui/agent.el); without it, the session working in the
;; request's directory.

;; WHAT THE AGENT IS TOLD
;; Claude Code's system prompt in agent-shell (config/agent-shell/context.el)
;; gets a paragraph on the canvas (`agent-ui-agent-context'): what it's for, the
;; command, and the skill to read before using it (skills/agent-ui/SKILL.md:
;; its types, with examples). Only while Emacs runs a server.

;; ====== KEY BINDINGS ======

;; THE CANVAS (see above): Vim's keys, as Doom's other buffers'.
(map! :map agent-ui-canvas-mode-map
      :n "q"  #'quit-window
      :n "gr" #'agent-ui-canvas-redraw)

;; ====== CODE ======

;; In config/agent-ui/, in this order: each part can use what the ones before
;; it define.
(load! "agent-ui/core")
(load! "agent-ui/canvas")
(load! "agent-ui/request")
(load! "agent-ui/agent")
;; The element types, a file each in agent-ui/elements/.
(load! "agent-ui/elements")

;; WHAT THE AGENT IS TOLD (see above), after what's there (the theme's line, the
;; project's issues).
(add-hook '+my/agent-shell-claude-context-functions #'agent-ui-agent-context t)
