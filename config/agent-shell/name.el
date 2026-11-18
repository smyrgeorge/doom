;;; $DOOMDIR/config/agent-shell/name.el -*- lexical-binding: t; -*-
;; An agent's buffer named after the agent alone (see AGENT BUFFERS in
;; config/agent-shell.el). Loaded from config/agent-shell.el.

(defun +my/agent-shell-buffer-name (agent _project)
  "An agent-shell buffer's name, as `agent-shell-buffer-name-format' asks:
AGENT, the agent's own name (its config's :buffer-name: \"Claude\",
\"Codex\", \"Gemini\"...), alone. Every session runs in a project, so the
project's name says nothing. A second session is AGENT<2>: shell-maker
makes a new session's name unique (`generate-new-buffer-name'), as Emacs
does same-named files."
  agent)
