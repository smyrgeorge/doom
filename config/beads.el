;;; $DOOMDIR/config/beads.el -*- lexical-binding: t; -*-
;; Issues: Beads (bd, a git-backed issue tracker that coding agents use as
;; their memory) in Emacs, by beads.el (packages.el). Loaded from config.el;
;; its code is in config/beads/.

;; ====== KEY BINDINGS ======

;; SPC o i: the current project's issues (its .beads/; without one, a
;; terminal offered with bd init typed); SPC o I: a new one.
(map! :leader
      :desc "Issues (Beads)" "o i" #'+my/beads-project
      :desc "New issue"      "o I" #'+my/beads-new-issue)

;; ====== SETTINGS ======

;; bd's command line: bd 1.x runs no daemon (config/beads/bd.el).
(setq beads-client-connection-strategy 'cli)

;; What SPC o i types (not runs) in a terminal where a project's issues aren't
;; tracked yet (config/beads/project.el). bd init commits what it adds (and
;; what's staged). Flags to add here, or before running it: --skip-hooks, no
;; git hooks (else bd's become the repository's core.hooksPath, run on every
;; commit, merge, push); --skip-agents, no CLAUDE.md, AGENTS.md, .claude/,
;; .codex/, .cursor/ (Claude Code in Emacs is told of the issues anyway, by
;; config/agent-shell/beads.el).
(defvar +my/beads-init-command "bd init"
  "The command SPC o i types in a terminal to start tracking a project's issues.")

;; ====== CODE ======

(load! "beads/project")                 ; SPC o i, SPC o I
(load! "beads/bd")                      ; mended for bd 1.x
(load! "beads/refresh")                 ; in the background
(load! "beads/evil")                    ; its keys over Vim's
(load! "beads/theme")                   ; the theme's colours
