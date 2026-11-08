;;; $DOOMDIR/config/beads.el -*- lexical-binding: t; -*-
;; Issues: Beads (bd, a git-backed issue tracker that coding agents use as
;; their memory) in Emacs, by beads.el (packages.el). Loaded from config.el;
;; its code is in config/beads/.

;; ====== KEY BINDINGS ======

;; SPC o i: the current project's issues (its .beads/, started if need be,
;; once asked); SPC o I: a new one.
(map! :leader
      :desc "Issues (Beads)" "o i" #'+my/beads-project
      :desc "New issue"      "o I" #'+my/beads-new-issue)

;; ====== SETTINGS ======

;; bd's command line: bd 1.x runs no daemon (config/beads/bd.el).
(setq beads-client-connection-strategy 'cli)

;; How SPC o i starts tracking a project's issues (config/beads/project.el):
;; no questions (Emacs answers none), no files for agents (CLAUDE.md,
;; AGENTS.md, .claude/, .codex/, .cursor/): Claude Code in Emacs is told of
;; the issues by config/agent-shell/beads.el.
(defvar +my/beads-init-args '("init" "--quiet" "--non-interactive" "--skip-agents")
  "bd's arguments starting a project's issues.")

;; ====== CODE ======

(load! "beads/project")                 ; SPC o i, SPC o I
(load! "beads/bd")                      ; mended for bd 1.x
(load! "beads/evil")                    ; its keys over Vim's
(load! "beads/theme")                   ; the theme's colours
