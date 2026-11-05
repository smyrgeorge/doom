;;; $DOOMDIR/config/agent-shell.el -*- lexical-binding: t; -*-
;; Claude Code inside Emacs (agent-shell, via ACP). Loaded from config.el.

;; ====== VARIABLES ======

;; INSIDE EMACS
;; Claude Code is told it runs inside Emacs, in an agent-shell buffer, not in a
;; terminal, and that images show inline there: a Markdown image link to a
;; local file, or an image's path alone on a line (agent-shell renders both;
;; remote images aren't fetched). And that a report with diagrams or graphs
;; comes as Markdown, with only the diagrams rendered as images (not the whole
;; report as one image or a web page), so it reads in the editor. Appended to
;; its system prompt (Claude Code's own stays), in every session it starts or
;; resumes.
(defvar +my/agent-shell-claude-context
  "You are running inside Emacs, in an agent-shell buffer (the agent-shell \
package, through the claude-agent-acp ACP adapter), not in a terminal. \
agent-shell renders Markdown: a Markdown image link to a local file, such as \
![chart](/tmp/chart.png), or a bare image path on its own line, is shown \
inline as an image. Show charts and screenshots that way.

When asked for a report with diagrams, charts or graphs, write the report \
itself as Markdown in your reply: don't render the whole report or page as \
an image, or as an HTML page. Render only each diagram or graph as an image \
file (e.g. PNG) and link it where it belongs with a Markdown image link, so \
it shows inline in the editor. Diagram code such as Mermaid isn't drawn \
here: render it to an image too."
  "Appended to Claude Code's system prompt in agent-shell (see above).")

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
(defadvice! +my/agent-shell-claude-context-a (config)
  "Append `+my/agent-shell-claude-context' to Claude Code's system prompt."
  :filter-return #'agent-shell-anthropic-make-claude-code-config
  (setf (alist-get :session-meta config)
        (cons `(systemPrompt . ((append . ,+my/agent-shell-claude-context)))
              (alist-get :session-meta config)))
  config)
