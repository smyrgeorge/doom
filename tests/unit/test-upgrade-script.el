;;; tests/unit/test-upgrade-script.el -*- lexical-binding: t; -*-
;; scripts/upgrade.sh: packages.el's pins moved to their packages' latest
;; commits (scripts/upgrade.el, run by Doom's doomscript), `doom sync -u',
;; the tests; they pass: packages.el committed, its new pins alone; one fails:
;; the old pins put back and `doom sync' (--keep: the new ones left,
;; uncommitted). Run on a copy of the scripts in a throwaway repository, with a
;; fake doom, doomscript and tests/run.sh that note what they're asked: no
;; package is touched. And scripts/upgrade.el's own part, Doom's bump stubbed.

(require 'cl-lib)

(defconst +test-upgrade-script--old "1111111111111111111111111111111111111111")
(defconst +test-upgrade-script--new "2222222222222222222222222222222222222222")

(defun +test-upgrade-script--packages (pin &optional other-pin)
  "A packages.el: package a pinned to PIN, b (its recipe first) to OTHER-PIN
\(default PIN), c unpinned, and a commented-out pinned one."
  (format ";;; packages.el\n
;; (package! old-one :pin \"%s\")
(package! a :pin \"%s\")
(package! b :recipe (:host github :repo \"x/b\")
  :pin \"%s\")
(package! c)\n" pin pin (or other-pin pin)))

(defun +test-upgrade-script--write (file text &optional mode)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert text))
  (when mode (set-file-modes file mode)))

(defun +test-upgrade-script--read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(cl-defun +test-upgrade-script--repo (&key (moved '(a b)) (tests 0) (sync 0) (bump 0))
  "A throwaway config repository (packages.el committed, the scripts copied)
and its fakes; its path. MOVED: the packages whose pin the fake doomscript
moves (old → new); TESTS: tests/run.sh's exit status; SYNC: `doom sync -u''s;
BUMP: doomscript's. Each fake notes its arguments in calls.log."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "upgrade-script/repo-") t)))
         (log (expand-file-name "calls.log" dir))
         (old +test-upgrade-script--old)
         (new +test-upgrade-script--new))
    (make-directory (expand-file-name "scripts" dir) t)
    (dolist (script '("upgrade.sh" "upgrade.el" "ui.sh"))
      (copy-file (expand-file-name (concat "scripts/" script) +test-root)
                 (expand-file-name (concat "scripts/" script) dir) t))
    (+test-upgrade-script--write (expand-file-name "packages.el" dir) (+test-upgrade-script--packages old))
    (+test-upgrade-script--write
     (expand-file-name "tests/run.sh" dir)
     (format "#!/bin/sh\necho \"run.sh $*\" >> %s\nexit %d\n" log tests) #o755)
    (+test-upgrade-script--write
     (expand-file-name "doom/bin/doom" dir)
     (format "#!/bin/sh\necho \"doom $*\" >> %s\n[ \"$*\" = 'sync -u' ] && exit %d\nexit 0\n" log sync) #o755)
    ;; doomscript upgrade.el PACKAGES REPORT: the new packages.el and its report.
    (+test-upgrade-script--write
     (expand-file-name "new-packages.el" dir)
     (+test-upgrade-script--packages (if (memq 'a moved) new old) (if (memq 'b moved) new old)))
    (+test-upgrade-script--write
     (expand-file-name "report" dir)
     (mapconcat (lambda (name) (format "%s %s %s -\n" name old new)) moved ""))
    (+test-upgrade-script--write
     (expand-file-name "doom/bin/doomscript" dir)
     (format "#!/bin/sh\necho \"doomscript $(basename \"$1\")\" >> %s\n[ %d -eq 0 ] || { echo 'no network' >&2; exit %d; }\ncp %s \"$2\"\ncp %s \"$3\"\n"
             log bump bump (expand-file-name "new-packages.el" dir) (expand-file-name "report" dir))
     #o755)
    (+test-upgrade-script--write (expand-file-name ".gitignore" dir)
                                 "calls.log\ndoom/\nnew-packages.el\nreport\n")
    (let ((default-directory dir))
      (+test-bd--call "git" "init" "-q" "-b" "main")
      (+test-git-user)
      (+test-bd--call "git" "add" ".")
      (+test-bd--call "git" "commit" "-q" "-m" "Start"))
    dir))

(defvar +test-upgrade-script--env nil
  "Variables a test sets for the script (\"NAME=VALUE\"), before the rest.")

(defun +test-upgrade-script--run (dir &rest args)
  "Run DIR's scripts/upgrade.sh with ARGS: (STATUS . OUTPUT)."
  (with-temp-buffer
    (let* ((default-directory dir)
           (process-environment
            (append +test-upgrade-script--env
                    (list (concat "DOOM_BIN=" dir "doom/bin/doom")
                          (concat "TMPDIR=" (+test-tmp-file "upgrade-script/tmp/"))
                          "TESTS" "DOOMSCRIPT_BIN" "NO_COLOR=1")
                    process-environment))
           (status (apply #'call-process "bash" nil t nil
                          (expand-file-name "scripts/upgrade.sh" dir) args)))
      (cons status (buffer-string)))))

(defun +test-upgrade-script--calls (dir)
  (let ((log (expand-file-name "calls.log" dir)))
    (and (file-exists-p log)
         (split-string (+test-upgrade-script--read log) "\n" t))))

(defun +test-upgrade-script--git (dir &rest args)
  (let ((default-directory dir))
    (string-trim (with-output-to-string
                   (with-current-buffer standard-output
                     (apply #'call-process "git" nil t nil args))))))

(defun +test-upgrade-script--pins (dir)
  "DIR's packages.el pins: (A-PIN B-PIN)."
  (let ((text (+test-upgrade-script--read (expand-file-name "packages.el" dir))))
    (list (and (string-match "(package! a :pin \"\\([0-9a-f]+\\)\"" text) (match-string 1 text))
          (and (string-match ":repo \"x/b\")\n  :pin \"\\([0-9a-f]+\\)\"" text) (match-string 1 text)))))

;; ====== SCRIPTS/UPGRADE.SH ======

(ert-deftest upgrade-script/tests-pass-commits-the-new-pins ()
  "Pins moved, synced, the tests passing: packages.el committed, alone (a
change elsewhere left as it was), its message naming the packages."
  (let ((dir (+test-upgrade-script--repo)))
    (+test-upgrade-script--write (expand-file-name "other.txt" dir) "not to commit\n")
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 0))
      (should (string-search "✔ a 1111111 → 2222222" output))
      (should (string-search "✔ b 1111111 → 2222222" output))
      (should (equal (+test-upgrade-script--calls dir)
                     '("doomscript upgrade.el" "doom sync -u" "run.sh all")))
      (should (equal (+test-upgrade-script--pins dir)
                     (list +test-upgrade-script--new +test-upgrade-script--new)))
      (should (equal (+test-upgrade-script--git dir "log" "-1" "--format=%s")
                     "Packages: a and b at their latest commits, the tests passing"))
      (should (string-search "- a: 1111111 → 2222222"
                             (+test-upgrade-script--git dir "log" "-1" "--format=%b")))
      (should (equal (+test-upgrade-script--git dir "show" "--name-only" "--format=" "HEAD")
                     "packages.el"))
      (should (equal (+test-upgrade-script--git dir "status" "--porcelain") "?? other.txt"))
      (should (string-search "Restart Emacs" output)))))

(ert-deftest upgrade-script/tests-fail-puts-the-old-pins-back ()
  "A test failing: the old pins in packages.el again, `doom sync' checking
them out, nothing committed."
  (let ((dir (+test-upgrade-script--repo :tests 1)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 1))
      (should (string-search "the tests fail with the new pins: putting them back" output))
      (should (equal (+test-upgrade-script--calls dir)
                     '("doomscript upgrade.el" "doom sync -u" "run.sh all" "doom sync")))
      (should (equal (+test-upgrade-script--pins dir)
                     (list +test-upgrade-script--old +test-upgrade-script--old)))
      (should (equal (+test-upgrade-script--git dir "log" "-1" "--format=%s") "Start"))
      (should (equal (+test-upgrade-script--git dir "status" "--porcelain") "")))))

(ert-deftest upgrade-script/keep-leaves-the-new-pins ()
  "--keep, a test failing: the new pins left in packages.el, uncommitted, no
sync back."
  (let ((dir (+test-upgrade-script--repo :tests 1)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir "--keep")))
      (should (= status 1))
      (should (string-search "kept in packages.el (uncommitted)" output))
      (should (equal (+test-upgrade-script--calls dir)
                     '("doomscript upgrade.el" "doom sync -u" "run.sh all")))
      (should (equal (+test-upgrade-script--pins dir)
                     (list +test-upgrade-script--new +test-upgrade-script--new)))
      (should (equal (+test-upgrade-script--git dir "log" "-1" "--format=%s") "Start"))
      (should (equal (+test-upgrade-script--git dir "status" "--porcelain") "M packages.el")))))

(ert-deftest upgrade-script/one-pin-moved-named-alone ()
  "Only b's pin moved: the commit names b, a's pin as it was."
  (let ((dir (+test-upgrade-script--repo :moved '(b))))
    (pcase-let ((`(,status . ,_output) (+test-upgrade-script--run dir)))
      (should (= status 0))
      (should (equal (+test-upgrade-script--pins dir)
                     (list +test-upgrade-script--old +test-upgrade-script--new)))
      (should (equal (+test-upgrade-script--git dir "log" "-1" "--format=%s")
                     "Packages: b at their latest commits, the tests passing")))))

(ert-deftest upgrade-script/nothing-moved-syncs-tests-commits-nothing ()
  "Each pin already the latest: `doom sync -u' and the tests still run (the
other packages updated), nothing to commit."
  (let ((dir (+test-upgrade-script--repo :moved nil)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 0))
      (should (string-search "each pin already its package's latest commit" output))
      (should (string-search "nothing to commit" output))
      (should (equal (+test-upgrade-script--calls dir)
                     '("doomscript upgrade.el" "doom sync -u" "run.sh all")))
      (should (equal (+test-upgrade-script--git dir "log" "-1" "--format=%s") "Start")))))

(ert-deftest upgrade-script/nothing-moved-tests-fail ()
  "Nothing moved, a test failing: nothing to put back, said so, exit 1."
  (let ((dir (+test-upgrade-script--repo :moved nil :tests 1)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 1))
      (should (string-search "the tests fail with the pins as they were" output))
      (should (equal (+test-upgrade-script--calls dir)
                     '("doomscript upgrade.el" "doom sync -u" "run.sh all"))))))

(ert-deftest upgrade-script/sync-failing-puts-the-old-pins-back ()
  "`doom sync -u' failing: no tests, the old pins back and synced."
  (let ((dir (+test-upgrade-script--repo :sync 1)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 1))
      (should (string-search "doom sync -u failed" output))
      (should (equal (+test-upgrade-script--calls dir)
                     '("doomscript upgrade.el" "doom sync -u" "doom sync")))
      (should (equal (+test-upgrade-script--pins dir)
                     (list +test-upgrade-script--old +test-upgrade-script--old)))
      (should (equal (+test-upgrade-script--git dir "status" "--porcelain") "")))))

(ert-deftest upgrade-script/bump-failing-stops-first ()
  "The pins not moved (no network): its error shown, nothing else run,
packages.el as it was."
  (let ((dir (+test-upgrade-script--repo :bump 1)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 1))
      (should (string-search "the pins couldn't be moved" output))
      (should (string-search "no network" output))
      (should (equal (+test-upgrade-script--calls dir) '("doomscript upgrade.el")))
      (should (equal (+test-upgrade-script--git dir "status" "--porcelain") "")))))

(ert-deftest upgrade-script/refuses-uncommitted-packages ()
  "packages.el changed, uncommitted: refused (exit 2), nothing run."
  (let ((dir (+test-upgrade-script--repo)))
    (+test-upgrade-script--write (expand-file-name "packages.el" dir)
                                 (+test-upgrade-script--packages "3333333333333333333333333333333333333333"))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir)))
      (should (= status 2))
      (should (string-search "packages.el has uncommitted changes" output))
      (should-not (+test-upgrade-script--calls dir)))))

(ert-deftest upgrade-script/tests-kind-and-bad-options ()
  "TESTS names tests/run.sh's kind; an unknown option is refused (exit 2)."
  (let ((dir (+test-upgrade-script--repo :moved nil)))
    (let ((+test-upgrade-script--env '("TESTS=unit")))
      (should (= 0 (car (+test-upgrade-script--run dir)))))
    (should (member "run.sh unit" (+test-upgrade-script--calls dir)))
    (pcase-let ((`(,status . ,output) (+test-upgrade-script--run dir "--force")))
      (should (= status 2))
      (should (string-search "no option --force" output)))))

(ert-deftest upgrade-script/counts-the-commits-between ()
  "A moved pin's line in the commit counts the commits between, read in the
package's repository."
  (let* ((pkg (file-name-as-directory (make-temp-file (+test-tmp-file "upgrade-script/pkg-") t)))
         (default-directory pkg))
    (+test-bd--call "git" "init" "-q")
    (+test-git-user)
    (dolist (n '("1" "2" "3"))
      (+test-bd--call "git" "commit" "-q" "--allow-empty" "-m" n))
    (let* ((old (+test-upgrade-script--git pkg "rev-parse" "HEAD~2"))
           (new (+test-upgrade-script--git pkg "rev-parse" "HEAD"))
           (dir (+test-upgrade-script--repo :moved '(a))))
      ;; The fake doomscript's packages.el and report with these commits.
      (+test-upgrade-script--write (expand-file-name "new-packages.el" dir)
                                   (replace-regexp-in-string
                                    (regexp-quote +test-upgrade-script--old) new
                                    (+test-upgrade-script--read (expand-file-name "new-packages.el" dir))))
      (+test-upgrade-script--write (expand-file-name "packages.el" dir)
                                   (replace-regexp-in-string
                                    (regexp-quote +test-upgrade-script--old) old
                                    (+test-upgrade-script--read (expand-file-name "packages.el" dir))))
      (+test-bd--call "git" "-C" dir "commit" "-q" "-am" "Old pins")
      (+test-upgrade-script--write (expand-file-name "report" dir) (format "a %s %s %s\n" old new pkg))
      (pcase-let ((`(,status . ,_output) (+test-upgrade-script--run dir)))
        (should (= status 0))
        (should (string-search (format "- a: %s → %s (2 commits)" (substring old 0 7) (substring new 0 7))
                               (+test-upgrade-script--git dir "log" "-1" "--format=%b")))))))

;; ====== SCRIPTS/UPGRADE.EL ======

(load (expand-file-name "scripts/upgrade.el" +test-root) nil t)

(defun +test-upgrade-script--bump (file new-pins)
  "Run `+upgrade-bump' on FILE with Doom's bump stubbed: it sets each pin
NEW-PINS names ((PACKAGE . PIN)...); the report's lines."
  (let ((report (make-temp-file (+test-tmp-file "upgrade-script/report-"))))
    (cl-letf (((symbol-function 'doom/bump-packages-in-buffer)
               (lambda (&optional _)
                 (pcase-dolist (`(,package . ,pin) new-pins)
                   (goto-char (point-min))
                   (re-search-forward (format "^(package! %s\\b" package))
                   (re-search-forward ":pin \"\\([^\"]*\\)\"")
                   (replace-match pin t t nil 1))))
              ((symbol-function '+upgrade-repo) (lambda (package) (format "/repos/%s" package))))
      (+upgrade-bump file report))
    (split-string (+test-upgrade-script--read report) "\n" t)))

(ert-deftest upgrade-script/el-reads-the-pins ()
  "`+upgrade-pins': the pinned `package!' forms, a recipe before the pin too;
not an unpinned one, nor a commented-out one."
  (let ((file (make-temp-file (+test-tmp-file "upgrade-script/packages-") nil ".el"
                              (+test-upgrade-script--packages +test-upgrade-script--old
                                                              +test-upgrade-script--new))))
    (should (equal (+upgrade-pins file)
                   `((a . ,+test-upgrade-script--old) (b . ,+test-upgrade-script--new))))))

(ert-deftest upgrade-script/el-reports-the-moved-pins ()
  "`+upgrade-bump': a line per pin moved (PACKAGE OLD NEW REPO), none for one
left; the file rewritten."
  (let ((file (make-temp-file (+test-tmp-file "upgrade-script/packages-") nil ".el"
                              (+test-upgrade-script--packages +test-upgrade-script--old))))
    (should (equal (+test-upgrade-script--bump file `((b . ,+test-upgrade-script--new)))
                   (list (format "b %s %s /repos/b" +test-upgrade-script--old +test-upgrade-script--new))))
    (should (equal (+upgrade-pins file)
                   `((a . ,+test-upgrade-script--old) (b . ,+test-upgrade-script--new))))))

(ert-deftest upgrade-script/el-refuses-a-pin-not-a-commit ()
  "`git ls-remote' failing, its error taken for a pin: an error, the file as
it was."
  (let* ((text (+test-upgrade-script--packages +test-upgrade-script--old))
         (file (make-temp-file (+test-tmp-file "upgrade-script/packages-") nil ".el" text)))
    (should-error (+test-upgrade-script--bump file '((a . "fatal:"))))
    (should (equal (+test-upgrade-script--read file) text))))
