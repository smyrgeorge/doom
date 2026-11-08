;;; tests/unit/test-lsp-script.el -*- lexical-binding: t; -*-
;; scripts/lsp.sh: it installs the servers of the languages init.el enables
;; with +lsp (read from its doom! block by Emacs), nothing for the others;
;; run again it updates them (brew upgrade, apt / dnf upgrade, npm @latest,
;; uv --upgrade). Run with DRY_RUN=1 (its commands printed, none run), as
;; each system (OS=macos|apt|dnf), on small init.el files; PATH without
;; rustup, so Rust's server is the package manager's.

(defconst +test-lsp-script--script (expand-file-name "scripts/lsp.sh" +test-root))

(defun +test-lsp-script--init (lang &optional tools)
  "An init.el whose doom! block has LANG (a string: :lang's modules) and
TOOLS (:tools's); its path."
  (let ((file (make-temp-file (+test-tmp-file "lsp-script/init-") nil ".el")))
    (with-temp-file file
      (insert ";;; init.el\n\n(doom! :completion vertico\n"
              "       :tools " (or tools "(lsp +peek) (format +onsave +lsp)") "\n"
              "       :os (:if (featurep :system 'macos) macos) (tty +osc)\n"
              "       :lang " lang "\n"
              "       :config (default +bindings +smartparens))\n"))
    file))

(defun +test-lsp-script--run (os init &rest env)
  "Run scripts/lsp.sh dry, as OS, on INIT, ENV (\"VAR=value\") added:
(STATUS . OUTPUT)."
  (with-temp-buffer
    (let* ((emacs (expand-file-name invocation-name invocation-directory))
           (process-environment
            (append env
                    (list "DRY_RUN=1" (concat "OS=" os) (concat "DOOM_INIT=" init)
                          (concat "EMACS=" emacs)
                          ;; No rustup, no npm-installed servers: the system's tools.
                          "PATH=/usr/bin:/bin")
                    process-environment))
           (status (call-process "bash" nil t nil +test-lsp-script--script)))
      (cons status (buffer-string)))))

(defun +test-lsp-script--lines (output regexp)
  "OUTPUT's lines matching REGEXP."
  (seq-filter (lambda (line) (string-match-p regexp line)) (split-string output "\n")))

;; ====== WHAT IT INSTALLS ======

(ert-deftest lsp-script/only-the-languages-enabled-with-lsp ()
  "Python and Rust with +lsp: their servers; Markdown without +lsp, YAML
commented out: nothing for them."
  (pcase-let ((`(,status . ,output)
               (+test-lsp-script--run
                "macos" (+test-lsp-script--init
                         "(python +lsp +pyright) (rust +lsp) markdown ;;(yaml +lsp)\n emacs-lisp"))))
    (should (= status 0))
    (should (string-match-p "^Languages with \\+lsp in init.el: python rust $" output))
    (should (string-search "+ uv tool install --upgrade basedpyright" output))
    (should (string-search "+ uv tool install --upgrade black" output))
    (should (string-search "rust-analyzer" output))
    (dolist (absent '("marksman" "pandoc" "yaml-language-server" "kotlin" "clang" "npm install"))
      (should-not (string-search absent output)))))

(ert-deftest lsp-script/the-real-init-el ()
  "This config's init.el: each of its +lsp languages, Docker's (:tools)
too; LaTeX, not enabled, not."
  (pcase-let ((`(,status . ,output)
               (+test-lsp-script--run "macos" (expand-file-name "init.el" +test-root))))
    (should (= status 0))
    (should (string-match-p
             "^Languages with \\+lsp in init.el: docker cc gdscript json java javascript kotlin lua markdown python rust sh web yaml $"
             output))
    (dolist (server '("basedpyright" "bash-language-server" "dockerfile-language-server-nodejs"
                      "typescript" "vscode-langservers-extracted" "yaml-language-server" "marksman"
                      "rust-analyzer" "kotlin-lsp" "lua-language-server" "clang-format" "gdtoolkit"))
      (should (string-search server output)))
    (should-not (string-search "texlab" output))))

(ert-deftest lsp-script/npm-servers-once-each ()
  "web, json and javascript share vscode-langservers-extracted: installed
once, with the rest, in one npm call."
  (pcase-let ((`(,_ . ,output)
               (+test-lsp-script--run "macos" (+test-lsp-script--init "(web +lsp) (json +lsp) (javascript +lsp)"))))
    (let ((npm (+test-lsp-script--lines output "npm install")))
      (should (= (length npm) 1))
      (with-temp-buffer
        (insert (car npm))
        (should (= (how-many "vscode-langservers-extracted@" (point-min) (point-max)) 1))
        (should (= (how-many "prettier@" (point-min) (point-max)) 1))))))

(ert-deftest lsp-script/a-language-it-knows-no-server-for ()
  "A +lsp language without a server here: said at the end, the rest still
installed."
  (pcase-let ((`(,status . ,output)
               (+test-lsp-script--run "macos" (+test-lsp-script--init "(go +lsp) (sh +lsp)"))))
    (should (= status 0))
    (should (string-search "bash-language-server" output))
    (should (string-match-p "Not installed (install by hand):\n.*go (\\+lsp): this script knows no server" output))))

(ert-deftest lsp-script/no-languages-nothing-installed ()
  (pcase-let ((`(,status . ,output)
               (+test-lsp-script--run "macos" (+test-lsp-script--init "emacs-lisp (org +pretty)" "magit"))))
    (should (= status 0))
    (should-not (string-search "+ " output))))

(ert-deftest lsp-script/needs-emacs-to-read-init-el ()
  (pcase-let ((`(,status . ,output)
               (+test-lsp-script--run "macos" (+test-lsp-script--init "(sh +lsp)")
                                      "EMACS=no-such-emacs")))
    (should (= status 1))
    (should (string-search "no Emacs to read init.el" output))
    (should-not (string-search "+ " output))))

;; ====== RUN AGAIN: UPDATED ======

(ert-deftest lsp-script/updates-on-macos ()
  "Homebrew: upgraded if installed, else installed; npm @latest; uv
--upgrade."
  (pcase-let ((`(,_ . ,output)
               (+test-lsp-script--run "macos" (+test-lsp-script--init "(sh +lsp) (python +lsp) (kotlin +lsp)"))))
    (should (string-search "+ brew upgrade shellcheck shfmt" output))
    (should (string-search "+ brew upgrade --cask kotlin-lsp" output))
    (should (string-search "+ npm install -g bash-language-server@latest" output))
    (should (string-search "+ uv tool install --upgrade basedpyright" output))))

(ert-deftest lsp-script/updates-on-debian ()
  "apt: apt-get install upgrades what's installed; uv through pipx, kept up
to date; servers without a package listed."
  (pcase-let ((`(,status . ,output)
               (+test-lsp-script--run "apt" (+test-lsp-script--init "(sh +lsp) (python +lsp) (kotlin +lsp) (cc +lsp)"))))
    (should (= status 0))
    (should (string-search "apt-get update" output))
    (should (string-search "apt-get install -y shellcheck shfmt" output))
    (should (string-search "apt-get install -y clangd glslang-tools clang-format" output))
    (should (string-search "+ pipx upgrade uv" output))
    (should (string-search "+ npm install -g bash-language-server@latest" output))
    (should (string-match-p "Not installed (install by hand):\n.*kotlin-lsp" output))))

(ert-deftest lsp-script/updates-on-fedora ()
  "dnf: installed, then upgraded."
  (pcase-let ((`(,_ . ,output)
               (+test-lsp-script--run "dnf" (+test-lsp-script--init "(sh +lsp) (rust +lsp)"))))
    (should (string-search "dnf install -y ShellCheck shfmt" output))
    (should (string-search "dnf upgrade -y ShellCheck shfmt" output))
    (should (string-search "dnf install -y rust-analyzer" output))
    (should (string-search "dnf upgrade -y rust-analyzer" output))))

(ert-deftest lsp-script/npm-keeps-a-version-given ()
  "npm_global (scripts/os.sh): @latest added, a version given kept."
  (with-temp-buffer
    (call-process "bash" nil t nil "-c"
                  (format "OS=macos DRY_RUN=1; . %s; npm_global a @scope/b c@1.2 @scope/d@3"
                          (shell-quote-argument (expand-file-name "scripts/os.sh" +test-root))))
    (should (equal (string-trim (buffer-string))
                   "+ npm install -g a@latest @scope/b@latest c@1.2 @scope/d@3"))))
