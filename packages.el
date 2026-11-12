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

;; agent-shell: Claude Code (and other ACP agents) in a native Emacs buffer.
;; Needs: npm install -g @agentclientprotocol/claude-agent-acp (scripts/tools.sh)
(package! shell-maker)
(package! acp)
(package! agent-shell)

;; Git: TODOs in magit status.
(package! magit-todos)

;; Cycle snake_case / camelCase / PascalCase / UPPER_CASE / kebab-case.
(package! string-inflection)

;; Rainbow brackets: color (), [] and {} by nesting depth.
(package! rainbow-delimiters)

;; Beads: a git-backed issue tracker (bd, scripts/tools.sh) in Emacs: SPC o i
;; (config/beads.el). Pinned: config/beads.el mends beads.el for bd 1.x, the
;; commit it was checked with (tests/unit/test-beads.el); vui, its UI library,
;; the one it was checked with too.
(package! vui :recipe (:host github :repo "d12frosted/vui.el")
  :pin "9e9ffa2f631cf5f99ef28bccc1a667922ddd71c5")
(package! beads :recipe (:host codeberg :repo "ctietze/beads.el" :files ("lisp/*.el"))
  :pin "f7ab243c3bd8c175a5bd9e68847d0d9b1b678735")

;; Mermaid diagrams: mermaid-mode for .mmd / .mermaid files (config/mermaid.el),
;; its compile commands through mmdc (scripts/tools.sh).
(package! mermaid-mode)
