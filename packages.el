;;; $DOOMDIR/packages.el -*- lexical-binding: t; no-byte-compile: t -*-

;; To install a package:
;;
;;   1. Declare them here in a `package!' statement,
;;   2. Run 'doom sync' in the shell,
;;   3. Restart Emacs.
;;
;; Use 'C-h f package\!' to look up documentation for the `package!' macro.


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;; (package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
;; (package! another-package
;;   :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;; (package! this-package
;;   :recipe (:host github :repo "username/repo"
;;            :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
;; (package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;; (package! builtin-package :recipe (:nonrecursive t))
;; (package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see radian-software/straight.el#279)
;; (package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")


;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
;; (unpin! pinned-package)
;; ...or multiple packages
;; (unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;; (unpin! t)

;; Use git-delta (syntax highlighting, word diffs) for diffs in magit.
(package! magit-delta)

;; agent-shell: your coding agent (Claude Code, Codex, Gemini... over ACP) in a
;; native Emacs buffer. Needs its adapter: scripts/tools.sh installs your
;; agent's (config.el's), or those AGENTS names.
;; Pinned: the agent workspace advises agent-shell's internals (its queue, its
;; steering: config/agent-workspace/session.el), checked with these commits
;; (tests/unit/test-agent-workspace-*.el); the tests on GitHub build the same.
(package! shell-maker :pin "6745635b4f5e62c3fe07a0f09b8dd4d92b79839d")
(package! acp :pin "041470ecff003630e03f061584d41071c36f0124")
(package! agent-shell :pin "3f86a162dbb21037bbc2b5d93bd89b1b2b7cf757")

;; Nyan Cat in a session's mode line, where you are in the conversation
;; (config/agent-shell/nyan.el); not in other buffers.
(package! nyan-mode)

;; YAML read as Lisp data: the agent workflows' files (config/agent-workflow/
;; workflows.el). Pinned: the commit they were checked with
;; (tests/unit/test-agent-workflow-files.el).
(package! yaml :pin "5546f36bde24a9a8c1934e0f6ce205cd41d72537")

;; Git: TODOs in magit status.
(package! magit-todos)

;; Cycle snake_case / camelCase / PascalCase / UPPER_CASE / kebab-case.
(package! string-inflection)

;; Rainbow brackets: color (), [] and {} by nesting depth.
(package! rainbow-delimiters)

;; Agent UI: what a coding agent in agent-shell shows you under its session
;; (config/agent-ui.el), its own package (github.com/smyrgeorge/agent-ui);
;; its bin/, skills/ and assets/ with its Lisp. From its working copy in
;; ~/dev/agent-ui where there's one (its changes, as they're made); else
;; from GitHub, not pinned: its latest commit (doom sync -u to update).
(if (file-directory-p "~/dev/agent-ui")
    (package! agent-ui
      :recipe (:local-repo "~/dev/agent-ui" :files (:defaults "bin" "skills" "assets")))
  (package! agent-ui
    :recipe (:host github :repo "smyrgeorge/agent-ui" :files (:defaults "bin" "skills" "assets"))))

;; Beads: a git-backed issue tracker (bd, scripts/tools.sh) in Emacs: SPC o i
;; (config/beads.el). Pinned: config/beads.el mends beads.el for bd 1.x, the
;; commit it was checked with (tests/unit/test-beads.el); vui, its UI library,
;; the one it was checked with too.
(package! vui :recipe (:host github :repo "d12frosted/vui.el")
  :pin "004dd852746d8af838107dd7e3f44c5bbea04d79")
(package! beads :recipe (:host codeberg :repo "ctietze/beads.el" :files ("lisp/*.el"))
  :pin "f7ab243c3bd8c175a5bd9e68847d0d9b1b678735")

;; Mermaid diagrams: mermaid-mode for .mmd / .mermaid files (config/mermaid.el),
;; its compile commands through mmdc (scripts/tools.sh).
(package! mermaid-mode)
