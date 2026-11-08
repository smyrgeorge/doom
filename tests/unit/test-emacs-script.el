;;; tests/unit/test-emacs-script.el -*- lexical-binding: t; -*-
;; scripts/emacs.sh: Emacs installed, or updated to its latest release, then
;; Doom synced: `doom sync --rebuild' when Doom's packages aren't built for
;; this Emacs (no .local/straight/build-VERSION), else `doom sync'; NO_DOOM=1,
;; Emacs only. macOS: the emacs-plus cask, installed or upgraded; Linux:
;; GNU's latest release built from source, not again if it's installed.
;; And scripts/tools.sh says to run it when Emacs is missing or too old. With
;; fake brew, git, curl, doom and Emacs, which record what they're asked (or
;; dry, DRY_RUN=1): nothing is installed.

(defconst +test-emacs-script--script (expand-file-name "scripts/emacs.sh" +test-root))

(defun +test-emacs-script--fakes (&rest options)
  "A folder of fakes; its path. OPTIONS (a plist): :version, the fake Emacs's
version (nil: no Emacs, version.txt absent); :cask t, emacs-plus-app
installed; :formula t, Homebrew's emacs formula installed; :upgrade-to, the
version `brew upgrade --cask' brings (its install too); :releases, the
versions GNU's list has (nil: curl fails); :built, the Emacs version Doom's
packages are built for (its .local/straight/build-VERSION). Homebrew says the
cask is outdated when :upgrade-to is given. Each fake notes its arguments
in calls.log; the fake Emacs is bin/emacs, Doom's command doom/bin/doom."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "emacs-script/") t)))
         (bin (expand-file-name "bin/" dir))
         (log (expand-file-name "calls.log" dir))
         (version-file (expand-file-name "version.txt" dir)))
    (make-directory bin t)
    (make-directory (expand-file-name "doom/bin/" dir) t)
    (when (plist-get options :built)
      (make-directory (expand-file-name (concat "doom/.local/straight/build-" (plist-get options :built)) dir) t))
    (when (plist-get options :version)
      (with-temp-file version-file (insert (plist-get options :version))))
    (cl-flet ((fake (path body)
                (with-temp-file path
                  (insert "#!/bin/sh\necho \"" (file-name-nondirectory path) " $*\" >> " log "\n" body))
                (set-file-modes path #o755)))
      (fake (expand-file-name "emacs" bin)
            (format "[ -f %s ] || exit 127
case \"$*\" in
  *emacs-major-version*) cut -d. -f1 %s | tr -d '\\n' ;;
  *) tr -d '\\n' < %s ;;
esac\n" version-file version-file version-file))
      (fake (expand-file-name "brew" bin)
            (format "case \"$1 $2 $3\" in
  'list --cask emacs-plus-app') exit %d ;;
  'list --formula emacs') exit %d ;;
  'outdated --cask --quiet') %s ;;
  'upgrade --cask emacs-plus-app'|'install --cask emacs-plus-app') %s ;;
esac
exit 0\n"
                    (if (plist-get options :cask) 0 1)
                    (if (plist-get options :formula) 0 1)
                    (if (plist-get options :upgrade-to) "echo emacs-plus-app" ":")
                    (if (plist-get options :upgrade-to)
                        (format "printf %s > %s" (plist-get options :upgrade-to) version-file)
                      ":")))
      (fake (expand-file-name "git" bin) "exit 0\n")
      (fake (expand-file-name "doom/bin/doom" dir) "exit 0\n")
      (fake (expand-file-name "curl" bin)
            (if (plist-get options :releases)
                (concat "cat <<'LIST'\n"
                        (mapconcat (lambda (v) (format "<a href=\"emacs-%s.tar.xz\">emacs-%s.tar.xz</a>\n<a href=\"emacs-%s.tar.xz.sig\">" v v v))
                                   (plist-get options :releases) "\n")
                        "\nLIST\n")
              "exit 22\n")))
    dir))

(defun +test-emacs-script--run (os dir &rest env)
  "Run scripts/emacs.sh as OS with DIR's fakes, ENV added: (STATUS . OUTPUT)."
  (with-temp-buffer
    (let* ((process-environment
            (append env
                    (list (concat "OS=" os)
                          (concat "PATH=" dir "bin:" (getenv "PATH"))
                          (concat "EMACS_BIN=" dir "bin/emacs")
                          (concat "DOOM_BIN=" dir "doom/bin/doom")
                          (concat "TMPDIR=" (+test-tmp-file "emacs-script/tmp/")))
                    process-environment))
           (status (call-process "bash" nil t nil +test-emacs-script--script)))
      (cons status (buffer-string)))))

(defun +test-emacs-script--calls (dir)
  (let ((log (expand-file-name "calls.log" dir)))
    (and (file-exists-p log)
         (seq-remove (lambda (call) (string-prefix-p "emacs " call))
                     (split-string (with-temp-buffer (insert-file-contents log) (buffer-string)) "\n" t)))))

;; ====== MACOS ======

(ert-deftest emacs-script/macos-installs-then-rebuilds-doom ()
  "No Emacs: the cask installed; Emacs new, Doom's packages built for it."
  (let ((dir (+test-emacs-script--fakes :upgrade-to "31.1")))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "macos" dir)))
      (should (= status 0))
      (should (string-search "✔ Emacs installed" output))
      (let ((calls (+test-emacs-script--calls dir)))
        (should (member "brew install --cask emacs-plus-app" calls))
        (should-not (member "brew upgrade --cask emacs-plus-app" calls))
        (should (member "doom sync --rebuild" calls))))))

(ert-deftest emacs-script/macos-updates-and-rebuilds-when-it-changed ()
  "Installed: the cask upgraded; a new version: Doom rebuilt for it."
  (let ((dir (+test-emacs-script--fakes :version "31.1" :cask t :upgrade-to "31.2")))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "macos" dir)))
      (should (= status 0))
      (should (string-search "✔ Emacs 31.1 upgraded" output))
      (should (string-search "Doom's packages aren't built for Emacs 31.2: rebuilding them" output))
      (should (string-search "==> ✔ Emacs 31.2 and Doom ready" output))
      (let ((calls (+test-emacs-script--calls dir)))
        (should (member "brew upgrade --cask emacs-plus-app" calls))
        (should-not (member "brew install --cask emacs-plus-app" calls))
        (should (member "doom sync --rebuild" calls))))))

(ert-deftest emacs-script/macos-up-to-date-only-syncs ()
  "Up to date (Homebrew says it's not outdated): left, said so; Doom synced,
not rebuilt."
  (let ((dir (+test-emacs-script--fakes :version "31.1" :cask t :built "31.1")))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "macos" dir)))
      (should (= status 0))
      (should (string-search "✔ Emacs 31.1 up to date" output))
      (let ((calls (+test-emacs-script--calls dir)))
        (should-not (member "brew upgrade --cask emacs-plus-app" calls))
        (should (member "doom sync" calls))
        (should-not (member "doom sync --rebuild" calls))
        (should (seq-some (lambda (call) (string-match-p "^git -C .* submodule update --init --recursive$" call))
                          calls))))))

(ert-deftest emacs-script/macos-removes-the-emacs-formula ()
  "Homebrew's terminal-only emacs formula (it conflicts): uninstalled."
  (let ((dir (+test-emacs-script--fakes :version "31.1" :cask t :formula t)))
    (+test-emacs-script--run "macos" dir)
    (should (member "brew uninstall emacs" (+test-emacs-script--calls dir)))))

(ert-deftest emacs-script/doom-rebuilt-when-not-built-for-this-emacs ()
  "Emacs up to date but Doom's packages built for no Emacs (a new machine,
CI) or for another (Emacs updated by hand): rebuilt; built for it: synced."
  (dolist (case '((nil . "doom sync --rebuild") ("31.0" . "doom sync --rebuild") ("31.1" . "doom sync")))
    (let ((dir (+test-emacs-script--fakes :version "31.1" :cask t :built (car case))))
      (pcase-let ((`(,status . ,_) (+test-emacs-script--run "macos" dir)))
        (should (= status 0))
        (should (equal (list (car case) (seq-find (lambda (call) (string-prefix-p "doom " call))
                                                  (+test-emacs-script--calls dir)))
                       (list (car case) (cdr case))))))))

(ert-deftest emacs-script/no-doom-emacs-only ()
  "NO_DOOM=1: Emacs installed or updated, Doom left alone."
  (let ((dir (+test-emacs-script--fakes :version "31.1" :cask t :upgrade-to "31.2")))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "macos" dir "NO_DOOM=1")))
      (should (= status 0))
      (should (string-search "✔ Emacs 31.2 ready (Doom left alone: NO_DOOM)" output))
      (let ((calls (+test-emacs-script--calls dir)))
        (should (member "brew upgrade --cask emacs-plus-app" calls))
        (should-not (seq-some (lambda (call) (string-match-p "^\\(doom\\|git\\) " call)) calls))))))

;; ====== LINUX ======

(ert-deftest emacs-script/linux-builds-the-latest-release ()
  "GNU's latest release (by number: 31.10 after 31.2) built, from its
tarball, with xwidgets; Emacs changed: Doom rebuilt."
  (let ((dir (+test-emacs-script--fakes :version "31.1" :releases '("30.2" "31.2" "31.10" "29.4"))))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "apt" dir "DRY_RUN=1")))
      (should (= status 0))
      (should (string-search "• Updating Emacs 31.1 to 31.10, built from source" output))
      (should (string-search "emacs-31.10.tar.xz" output))
      (should (string-match-p "\\$ ./configure .*--with-xwidgets" output))
      (should (string-match-p "\\$ \\(sudo \\)?make install" output))
      (should (string-search "doom sync --rebuild" output)))))

(ert-deftest emacs-script/linux-latest-installed-not-built-again ()
  (let ((dir (+test-emacs-script--fakes :version "31.2" :releases '("31.1" "31.2") :built "31.2")))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "dnf" dir "DRY_RUN=1")))
      (should (= status 0))
      (should (string-search "✔ Emacs 31.2 up to date" output))
      (should-not (string-search "configure" output))
      (should-not (string-search "dnf" output))
      (should (string-match-p "\\$ .*doom sync\n" output))
      (should-not (string-search "--rebuild" output)))))

(ert-deftest emacs-script/linux-a-version-asked-for ()
  "EMACS_VERSION: that one, GNU's list not read; XWIDGETS=no: without."
  (let ((dir (+test-emacs-script--fakes)))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "apt" dir "DRY_RUN=1" "EMACS_VERSION=31.1" "XWIDGETS=no")))
      (should (= status 0))
      (should (string-search "• Installing Emacs 31.1, built from source" output))
      (should-not (string-search "xwidgets" output))
      (should-not (string-search "libwebkit2gtk" output)))))

(ert-deftest emacs-script/linux-no-release-list ()
  "GNU's list unreachable: said, nothing installed."
  (let ((dir (+test-emacs-script--fakes)))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--run "apt" dir "DRY_RUN=1")))
      (should (= status 1))
      (should (string-search "couldn't read Emacs's latest release" output))
      (should-not (string-search "$ " output)))))

;; ====== TOOLS.SH NEEDS IT ======

(defun +test-emacs-script--tools (dir &rest env)
  (with-temp-buffer
    (let* ((process-environment (append env (list (concat "PATH=" dir "bin:/usr/bin:/bin"))
                                        process-environment))
           (status (call-process "bash" nil t nil (expand-file-name "scripts/tools.sh" +test-root) "--check")))
      (cons status (buffer-string)))))

(ert-deftest emacs-script/tools-sh-asks-for-it-without-emacs ()
  (let ((dir (+test-emacs-script--fakes)))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--tools dir "EMACS=no-such-emacs")))
      (should (= status 1))
      (should (string-search "Emacs isn't installed: run scripts/emacs.sh first" output)))))

(ert-deftest emacs-script/tools-sh-asks-for-it-when-emacs-doesnt-run ()
  (let ((dir (+test-emacs-script--fakes)))      ; bin/emacs, no version: exits 127
    (pcase-let ((`(,status . ,output) (+test-emacs-script--tools dir (concat "EMACS=" dir "bin/emacs"))))
      (should (= status 1))
      (should (string-search "doesn't run: run scripts/emacs.sh first" output)))))

(ert-deftest emacs-script/tools-sh-asks-for-it-with-an-old-emacs ()
  (let ((dir (+test-emacs-script--fakes :version "30.2")))
    (pcase-let ((`(,status . ,output) (+test-emacs-script--tools dir (concat "EMACS=" dir "bin/emacs"))))
      (should (= status 1))
      (should (string-search "Emacs 30 is older than this config needs (31): run scripts/emacs.sh first" output)))))
