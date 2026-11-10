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

;; AN ISSUE (RET on one in the list): q closes it for good, its buffer killed
;; (its pane with it, as config/tiling has a pane's last tab), as on Agent UI's
;; canvas, images, Markdown and PDFs; beads.el's q only hid it, kept in the
;; background. Emacs's key too: beads/evil.el copies a map's own keys into
;; Vim's normal state.
(map! :after beads-detail
      :map (beads-detail-mode-map beads-detail-vui-mode-map)
      :gn "q" #'kill-current-buffer)

;; ====== SETTINGS ======

;; bd's command line: bd 1.x runs no daemon (config/beads/bd.el).
(setq beads-client-connection-strategy 'cli)

;; What SPC o i types (not runs) in a terminal where a project's issues aren't
;; tracked yet (config/beads/project.el). bd init commits what it adds (and
;; what's staged): with --skip-agents, .beads/ and .gitignore only, no files
;; for every AI tool (CLAUDE.md, AGENTS.md, .claude/, .codex/, .cursor/,
;; .agents/): Claude Code in Emacs is told of the issues anyway, by
;; config/agent-shell/beads.el (from a terminal, it is after `bd setup
;; claude'). A flag to add here, or before running it: --skip-hooks, no git
;; hooks (else bd's become the repository's core.hooksPath, run on every
;; commit, merge, push).
(defvar +my/beads-init-command "bd init --skip-agents"
  "The command SPC o i types in a terminal to start tracking a project's issues.")

;; The issue list shows the work still open: its closed issues hidden, a
;; notice over it saying how many, with Show closed (config/beads/hidden.el).
;; t: shown when a list opens.
(defvar +my/beads-closed-shown nil
  "Whether a new issue list shows its closed issues.")

;; ====== CODE ======

(load! "beads/project")                 ; SPC o i, SPC o I
(load! "beads/bd")                      ; mended for bd 1.x
(load! "beads/refresh")                 ; in the background
(load! "beads/hidden")                  ; closed issues, a filter: said
(load! "beads/look")                    ; icons, badges, tags, epics
(load! "beads/place")                   ; kept through a refresh
(load! "beads/evil")                    ; its keys over Vim's
(load! "beads/theme")                   ; the theme's colours
(load! "beads/file")                    ; a bug filed from code (Agent UI's)
