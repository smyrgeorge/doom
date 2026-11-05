;;; $DOOMDIR/config/agent-shell.el -*- lexical-binding: t; -*-
;; Claude Code inside Emacs (agent-shell, via ACP). Loaded from config.el.

;; AGENT-SHELL (Claude Code via ACP)
;; Uses the Claude CLI login (run `claude` once in a terminal to log in).
(use-package! agent-shell
  :commands (agent-shell agent-shell-anthropic-start-claude-code)
  :config
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t)
        ;; New shells (e.g. from the Option+Enter Claude actions) start Claude
        ;; Code without asking which agent to use.
        agent-shell-preferred-agent-config 'claude-code))

(map! :leader
      :desc "Claude Code (agent-shell)" "o c" #'agent-shell-anthropic-start-claude-code
      :desc "Agent shell"               "o C" #'agent-shell)
