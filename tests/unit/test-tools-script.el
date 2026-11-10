;;; tests/unit/test-tools-script.el -*- lexical-binding: t; -*-
;; scripts/tools.sh: what init.el and this config need outside Emacs, from its
;; TOOLS table read against init.el's doom! block (Emacs reads it): a module
;; it doesn't know (or a +lsp without its row) fails it, before installing;
;; only the enabled modules' tools; run again, each is updated (Homebrew's
;; installed, upgraded if outdated, else left; apt-get install, dnf install
;; then upgrade, npm @latest, uv --upgrade, rustup update); --check only
;; checks. Its output: ==> steps, ✔ / ✖ lines, $ commands (scripts/ui.sh).
;; Dry (DRY_RUN=1) or with fake installers that record what they're asked:
;; nothing is installed. As each system (OS=macos|apt|dnf, scripts/os.sh).

(defconst +test-tools-script--script (expand-file-name "scripts/tools.sh" +test-root))

(defun +test-tools-script--init (modules)
  "An init.el whose doom! block is MODULES (a string); its path."
  (let ((file (make-temp-file (+test-tmp-file "tools-script/init-") nil ".el")))
    (with-temp-file file
      (insert ";;; init.el\n\n(doom! " modules ")\n"))
    file))

(defun +test-tools-script--fake-bin (&optional installed outdated)
  "A folder of fake installers (brew, npm, uv, pipx, rustup) noting their
arguments in calls.log there; its path. Homebrew has INSTALLED (names,
formulae and casks), OUTDATED among them (`brew list', `brew outdated')."
  (let ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "tools-script/bin-") t))))
    (dolist (program '("brew" "npm" "uv" "pipx" "rustup"))
      (with-temp-file (expand-file-name program dir)
        (insert "#!/bin/sh\n"
                "echo \"" program " $*\" >> \"$(dirname \"$0\")/calls.log\"\n"
                (if (equal program "brew")
                    (format "case \"$1\" in
  list) printf '%%s\\n' %s ;;
  outdated) printf '%%s\\n' %s ;;
esac\n"
                            (mapconcat #'shell-quote-argument (or installed '("")) " ")
                            (mapconcat #'shell-quote-argument (or outdated '("")) " "))
                  "")
                "exit 0\n"))
      (set-file-modes (expand-file-name program dir) #o755))
    dir))

(defconst +test-tools-script--unset
  '("EMACS_VERSION" "XWIDGETS" "NO_DOOM" "DRY_RUN" "OS" "EMACS" "DOOM_INIT")
  "What the scripts read from their environment, unset for each run (a bare
name in `process-environment'): a test sets what it means to, not what
the shell running the tests had (CI's).")

(defun +test-tools-script--run (os init &rest args)
  "Run scripts/tools.sh as OS on INIT, the strings of ARGS that look like
VAR=value added to its environment, the others its arguments:
(STATUS . OUTPUT, stderr too). A fake Homebrew (nothing installed) unless
ARGS give a PATH."
  (let* ((env (seq-filter (lambda (arg) (string-match-p "\\`[A-Z_]+=" arg)) args))
         (arguments (seq-remove (lambda (arg) (string-match-p "\\`[A-Z_]+=" arg)) args))
         (env (if (seq-some (lambda (var) (string-prefix-p "PATH=" var)) env)
                  env
                (cons (concat "PATH=" (+test-tools-script--fake-bin) ":" (getenv "PATH")) env))))
    (with-temp-buffer
      (let* ((process-environment
              (append env
                      (list (concat "OS=" os) (concat "DOOM_INIT=" init)
                            (concat "EMACS=" (expand-file-name invocation-name invocation-directory)))
                      +test-tools-script--unset
                      process-environment))
             (status (apply #'call-process "bash" nil t nil +test-tools-script--script arguments)))
        (cons status (buffer-string))))))

(defun +test-tools-script--calls (dir)
  (let ((log (expand-file-name "calls.log" dir)))
    (and (file-exists-p log)
         (split-string (with-temp-buffer (insert-file-contents log) (buffer-string)) "\n" t))))

(defconst +test-tools-script--small
  ":completion vertico :checkers (spell +everywhere) :tools (lsp +peek) magit
   :lang emacs-lisp (python +pyright +lsp +uv) (rust +lsp) (web +lsp) (json +lsp)
         (javascript +lsp) (sh +lsp) ;;(yaml +lsp)
   :config (default +bindings)"
  "A small init.el, every module known to tools.sh (yaml commented out).")

;; ====== VALIDATION ======

(ert-deftest tools-script/fails-on-modules-it-doesnt-know ()
  "A new language, a new tool module, +lsp on a language that had none:
each named, nothing installed, exit 2."
  (pcase-let ((`(,status . ,output)
               (+test-tools-script--run
                "macos" (+test-tools-script--init
                         ":tools terraform (lsp +peek) :lang (go +lsp) (org +pretty +lsp) (sh +lsp)")
                "DRY_RUN=1")))
    (should (= status 2))
    (should (string-search "✖ tools.sh: init.el enables modules this script doesn't know" output))
    (should (string-search ":tools terraform: no row in TOOLS or NOTHING" output))
    (should (string-search ":lang go: no row" output))
    (should (string-search ":lang go +lsp: no \":lang go +lsp\" row" output))
    (should (string-search ":lang org +lsp: no \":lang org +lsp\" row" output))
    (should-not (string-search ":lang sh" output))
    (should-not (string-search "$ " output))))

(ert-deftest tools-script/the-real-init-el-passes ()
  "This config's init.el: every module known, on each system (each row's
installers valid there)."
  (dolist (os '("macos" "apt" "dnf"))
    (pcase-let ((`(,status . ,output)
                 (+test-tools-script--run os (expand-file-name "init.el" +test-root) "DRY_RUN=1")))
      (should (equal (list os status) (list os 0)))
      (should (string-match-p "^==> init.el: [0-9]+ modules, every one known" output))
      (should (string-search "==> Checking" output)))))

(ert-deftest tools-script/needs-emacs-to-read-init-el ()
  (pcase-let ((`(,status . ,output)
               (+test-tools-script--run "macos" (+test-tools-script--init ":lang (sh +lsp)")
                                        "DRY_RUN=1" "EMACS=no-such-emacs")))
    (should (= status 1))
    (should (string-search "✖ tools.sh: Emacs isn't installed: run scripts/emacs.sh first" output))))

;; ====== WHAT IT INSTALLS ======

(ert-deftest tools-script/only-what-init-el-enables ()
  "The enabled modules' tools, Doom's and this config's; not those of
modules left out (yaml commented out, no markdown, no kotlin)."
  (pcase-let ((`(,status . ,output)
               (+test-tools-script--run "macos" (+test-tools-script--init +test-tools-script--small)
                                        "DRY_RUN=1")))
    (should (= status 0))
    (dolist (expected '("$ brew install ripgrep" "$ brew install git-delta" "$ brew install aspell"
                        "$ brew install uv" "$ brew install shellcheck"
                        "$ brew install --cask font-jetbrains-mono"
                        "$ rustup component add rust-analyzer rustfmt clippy"
                        "$ uv tool install --upgrade basedpyright" "bash-language-server@latest"
                        "vscode-langservers-extracted@latest" "typescript@latest"))
      (should (string-search expected output)))
    (dolist (absent '("yaml-language-server" "marksman" "pandoc" "kotlin" "ktlint" "lua"
                      "clang" "openjdk" "jq" "texlab" "glslang"))
      (should-not (string-search absent output)))))

(ert-deftest tools-script/java-is-openjdk ()
  "Java's JDK: Homebrew's openjdk on macOS (not Temurin), the distributions'
OpenJDK on Linux."
  (let ((init (+test-tools-script--init ":lang (java +lsp)")))
    (let ((output (cdr (+test-tools-script--run "macos" init "DRY_RUN=1"))))
      (should (string-search "$ brew install openjdk" output))
      (should-not (string-search "temurin" output)))
    (should (string-search "default-jdk" (cdr (+test-tools-script--run "apt" init "DRY_RUN=1"))))
    (should (string-search "java-21-openjdk-devel" (cdr (+test-tools-script--run "dnf" init "DRY_RUN=1"))))))

(ert-deftest tools-script/each-npm-package-once ()
  "web, json and javascript share vscode-langservers-extracted: once, in one
npm call."
  (pcase-let ((`(,_ . ,output)
               (+test-tools-script--run "macos" (+test-tools-script--init +test-tools-script--small)
                                        "DRY_RUN=1")))
    (let ((npm (seq-filter (lambda (line) (string-prefix-p "  $ npm install" line))
                           (split-string output "\n"))))
      (should (= (length npm) 1))
      (with-temp-buffer
        (insert (car npm))
        (should (= (how-many "vscode-langservers-extracted@" (point-min) (point-max)) 1))
        (should (= (how-many "prettier@" (point-min) (point-max)) 1))))))

;; ====== RUN AGAIN: UPDATED ======

(ert-deftest tools-script/macos-installs-upgrades-or-leaves ()
  "Homebrew: what isn't installed installed, what's outdated upgraded, what's
up to date left (said so), one package a call; casks the same; npm
@latest; uv --upgrade; rustup's components, then rustup update."
  (let ((bin (+test-tools-script--fake-bin
              '("git" "ripgrep" "fd" "fontconfig" "git-delta" "imagemagick" "node" "coreutils"
                "uv" "shellcheck" "shfmt" "tidy-html5" "font-symbols-only-nerd-font")
              '("ripgrep" "font-symbols-only-nerd-font"))))
    (pcase-let ((`(,status . ,output)
                 (+test-tools-script--run "macos" (+test-tools-script--init +test-tools-script--small)
                                          (concat "PATH=" bin ":" (getenv "PATH")))))
      (should (= status 0))
      (let ((calls (+test-tools-script--calls bin)))
        ;; Not installed: installed.
        (should (member "brew install aspell" calls))
        (should (member "brew install --cask font-jetbrains-mono" calls))
        ;; Outdated: upgraded.
        (should (member "brew upgrade ripgrep" calls))
        (should (member "brew upgrade --cask font-symbols-only-nerd-font" calls))
        ;; Up to date: left.
        (should-not (seq-some (lambda (call) (string-match-p "^brew \\(install\\|upgrade\\) git$" call)) calls))
        ;; One package a call.
        (should-not (seq-some (lambda (call)
                                (string-match-p "^brew \\(upgrade\\|install\\) \\(--cask \\)?[^ -][^ ]* [^ ]" call))
                              calls))
        (should (seq-some (lambda (call) (string-match-p "^npm install -g .*bash-language-server@latest" call)) calls))
        (should (member "uv tool install --upgrade basedpyright" calls))
        (should (member "rustup component add rust-analyzer rustfmt clippy" calls))
        (should (member "rustup update" calls)))
      ;; Said, per package.
      (should (string-match-p "✔ aspell +installed" output))
      (should (string-match-p "✔ ripgrep +upgraded" output))
      (should (string-match-p "✔ git +up to date" output))
      (should (string-match-p "✔ basedpyright +at its latest" output)))))

(ert-deftest tools-script/debian-installs-what-upgrades ()
  "apt: its lists refreshed, one apt-get install (it upgrades); uv through
pipx, upgraded; packages-less servers named, to install by hand."
  (pcase-let ((`(,status . ,output)
               (+test-tools-script--run "apt" (+test-tools-script--init
                                               (concat +test-tools-script--small " :lang (markdown +lsp)"))
                                        ;; Not this machine's tools: marksman not found.
                                        "DRY_RUN=1" "PATH=/usr/bin:/bin")))
    (should (= status 0))
    (should (string-match-p "\\$ \\(sudo \\)?apt-get update" output))
    (should (string-match-p "apt-get install -y -q .*aspell aspell-en" output))
    (should (string-search "fd-find" output))
    (should (string-search "$ pipx upgrade uv" output))
    (should (string-search "$ uv tool install --upgrade basedpyright" output))
    (should (string-match-p "✖ marksman .*(by hand: github.com/artempyanykh/marksman/releases) missing" output))))

(ert-deftest tools-script/fedora-installs-then-upgrades ()
  (pcase-let ((`(,status . ,output)
               (+test-tools-script--run "dnf" (+test-tools-script--init +test-tools-script--small) "DRY_RUN=1")))
    (should (= status 0))
    (should (string-match-p "dnf install -y -q .*ShellCheck" output))
    (should (string-match-p "dnf upgrade -y -q .*ShellCheck" output))))

(ert-deftest tools-script/npm-keeps-a-version-given ()
  "npm_global (scripts/os.sh): @latest added, a version given kept."
  (with-temp-buffer
    (call-process "bash" nil t nil "-c"
                  (format "OS=macos DRY_RUN=1; . %s; npm_global a @scope/b c@1.2 @scope/d@3"
                          (shell-quote-argument (expand-file-name "scripts/os.sh" +test-root))))
    (should (equal (string-trim (buffer-string))
                   "$ npm install -g --no-fund --no-audit a@latest @scope/b@latest c@1.2 @scope/d@3"))))

;; ====== CHECK ======

(ert-deftest tools-script/check-only-checks ()
  "--check: nothing installed; each tool that applies, there (✔) or missing
(✖), each once; how many are missing, last."
  (let ((bin (+test-tools-script--fake-bin)))
    (pcase-let ((`(,status . ,output)
                 (+test-tools-script--run "macos" (+test-tools-script--init +test-tools-script--small)
                                          (concat "PATH=" bin ":/usr/bin:/bin") "--check")))
      (should (= status 0))
      ;; Only questions: Homebrew's packages, npm's global modules.
      (should-not (seq-remove (lambda (call) (string-match-p "^\\(brew \\(list\\|outdated\\)\\|npm root -g\\)" call))
                              (+test-tools-script--calls bin)))
      (should (string-match-p "^  ✔ git " output))
      (should (string-match-p "^  ✖ basedpyright .* missing$" output))
      (should (string-match-p "==> ⚠ [0-9]+ of [0-9]+ tools missing (see above)\\'" (string-trim output)))
      (with-temp-buffer
        (insert output)
        (should (= (how-many "^  [✔✖] npm " (point-min) (point-max)) 1))))))

(ert-deftest tools-script/mathjax-for-agent-ui-s-formulas ()
  "MathJax (Agent UI's math): installed by npm, everywhere; checked as a
global npm package (no command), in npm's global modules."
  (let ((bin (+test-tools-script--fake-bin))
        (modules (file-name-as-directory (make-temp-file (+test-tmp-file "tools-script/modules-") t))))
    ;; npm root -g: this folder.
    (with-temp-file (expand-file-name "npm" bin)
      (insert "#!/bin/sh
echo \"npm $*\" >> \"$(dirname \"$0\")/calls.log\"
"
              "[ \"$1\" = root ] && echo " (shell-quote-argument (directory-file-name modules)) "
exit 0
"))
    (set-file-modes (expand-file-name "npm" bin) #o755)
    (pcase-let ((`(,status . ,output)
                 (+test-tools-script--run "macos" (+test-tools-script--init +test-tools-script--small)
                                          (concat "PATH=" bin ":/usr/bin:/bin"))))
      (should (= status 0))
      (should (seq-some (lambda (call) (string-match-p "^npm install -g .*mathjax-full@latest" call))
                        (+test-tools-script--calls bin)))
      (should (string-match-p "^  ✖ node:mathjax-full .*math\\.el) missing$" output)))
    (make-directory (expand-file-name "mathjax-full" modules))
    (pcase-let ((`(,_ . ,output)
                 (+test-tools-script--run "apt" (+test-tools-script--init +test-tools-script--small)
                                          (concat "PATH=" bin ":/usr/bin:/bin") "--check")))
      (should (string-match-p "^  ✔ node:mathjax-full " output)))))

(ert-deftest tools-script/plain-without-a-terminal ()
  "Output to a file or a pipe (a log, these tests): no colour codes."
  (pcase-let ((`(,_ . ,output)
               (+test-tools-script--run "macos" (expand-file-name "init.el" +test-root) "DRY_RUN=1")))
    (should-not (string-search "\e[" output))))

(ert-deftest tools-script/bad-arguments ()
  (pcase-let ((`(,status . ,output)
               (+test-tools-script--run "macos" (+test-tools-script--init ":lang emacs-lisp") "--nope")))
    (should (= status 2))
    (should (string-search "✖ usage:" output))))
