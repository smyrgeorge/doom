;;; tests/unit/test-lsp.el -*- lexical-binding: t; -*-
;; config/lsp.el: code lenses (references for Rust and TypeScript/JavaScript,
;; no Debug lens; placed at the end of the line without measuring it),
;; projects imported without asking (only inside a project), file watchers that
;; skip what git ignores, and JetBrains' kotlin-lsp. No language server is ever
;; started: process starts are mocked.

(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)

;; Mocking a primitive (`call-process', `make-process') mustn't natively
;; compile a trampoline for it: that runs another Emacs.
(setq native-comp-enable-subr-trampolines nil)

;; What lsp-mode sees before it loads (the config sets its variables first).
(defvar +test-lsp--before-lsp-mode
  (list :lsp-mode (featurep 'lsp-mode)
        :clients (boundp 'lsp-clients)))

(+test-load "config/lsp")

(defvar +test-lsp--after-config
  (list :lsp-mode (featurep 'lsp-mode)
        :clients (boundp 'lsp-clients)))

(require 'projectile)                   ; Doom loads it at startup
(require 'lsp-mode)
(require 'lsp-lens)

;; ====== HELPERS ======

(defun +test-lsp--dir (name)
  "A new empty folder NAME-XXXX in the temp folder (with a slash)."
  (file-name-as-directory (make-temp-file (+test-tmp-file (concat "lsp/" name "-")) t)))

(defun +test-lsp--project (&rest files)
  "A new git project (a .git folder) with FILES (relative paths, made empty);
return its folder."
  (let ((root (+test-lsp--dir "proj")))
    (make-directory (expand-file-name ".git" root))
    (dolist (file files)
      (let ((path (expand-file-name file root)))
        (make-directory (file-name-directory path) t)
        (unless (string-suffix-p "/" file)
          (with-temp-file path))))
    root))

(defmacro +test-lsp--with-git-output (output exit &rest body)
  "BODY with `call-process' mocked: git prints OUTPUT and exits with EXIT (a
function of no arguments to signal instead). The calls are in `calls' as
(DEFAULT-DIRECTORY PROGRAM INFILE DESTINATION DISPLAY ARGS...)."
  (declare (indent 2))
  `(let ((calls nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program &optional infile destination display &rest args)
                  (push (append (list default-directory program infile destination display) args)
                        calls)
                  (when (functionp ,exit) (funcall ,exit))
                  (when (eq destination t) (insert ,output))
                  ,exit)))
       ,@body)))

(defun +test-lsp--lens-overlay (text contents &optional name)
  "A buffer with TEXT (NAME, default *lsp-lens-test*), and a lens overlay at
the end of its first line showing CONTENTS (as `lsp-lens--show' makes them)."
  (let ((buffer (+test-buffer (or name "*lsp-lens-test*") text)))
    (with-current-buffer buffer
      (let ((ov (save-excursion
                  (goto-char (point-min))
                  (make-overlay (line-end-position) (line-end-position) nil t t))))
        (overlay-put ov 'lsp-lens t)
        (overlay-put ov 'lsp--lens-contents contents)
        ov))))

(defmacro +test-lsp--without-advice (symbol advice &rest body)
  "BODY with ADVICE taken off SYMBOL (put back after)."
  (declare (indent 2))
  `(progn
     (advice-remove ,symbol ,advice)
     (unwind-protect (progn ,@body)
       (advice-add ,symbol :around ,advice))))

;; ====== CODE LENSES ======

(ert-deftest lsp/lens-settings ()
  "Reference counts for Rust (methods, types, traits, enum variants),
TypeScript (and its implementations) and JavaScript; Rust's Debug lens off."
  (should (eq lsp-rust-analyzer-lens-references-method-enable t))
  (should (eq lsp-rust-analyzer-lens-references-adt-enable t))
  (should (eq lsp-rust-analyzer-lens-references-trait-enable t))
  (should (eq lsp-rust-analyzer-lens-references-enum-variant-enable t))
  (should (eq lsp-rust-analyzer-lens-debug-enable nil))
  (should (eq lsp-typescript-references-code-lens-enabled t))
  (should (eq lsp-typescript-implementations-code-lens-enabled t))
  (should (eq lsp-javascript-references-code-lens-enabled t)))

(ert-deftest lsp/lens-settings-set-before-lsp-mode-loads ()
  "config/lsp.el loads before lsp-mode (as in Doom), so its values are what the
packages' defcustoms find."
  (should-not (plist-get +test-lsp--before-lsp-mode :lsp-mode))
  (should-not (plist-get +test-lsp--after-config :lsp-mode)))

(ert-deftest lsp/lens-settings-survive-the-packages-loading ()
  "lsp-rust and lsp-javascript's defaults are the other way round; loading them
keeps the config's values."
  (require 'lsp-rust)
  (require 'lsp-javascript)
  (let ((default (lambda (var) (eval (car (get var 'standard-value)) t))))
    ;; The defaults the config changes.
    (should (eq (funcall default 'lsp-rust-analyzer-lens-references-method-enable) nil))
    (should (eq (funcall default 'lsp-rust-analyzer-lens-debug-enable) t))
    (should (eq (funcall default 'lsp-typescript-references-code-lens-enabled) nil))
    (should (eq (funcall default 'lsp-typescript-implementations-code-lens-enabled) nil))
    (should (eq (funcall default 'lsp-javascript-references-code-lens-enabled) nil)))
  (should (eq lsp-rust-analyzer-lens-references-method-enable t))
  (should (eq lsp-rust-analyzer-lens-references-adt-enable t))
  (should (eq lsp-rust-analyzer-lens-references-trait-enable t))
  (should (eq lsp-rust-analyzer-lens-references-enum-variant-enable t))
  (should (eq lsp-rust-analyzer-lens-debug-enable nil))
  (should (eq lsp-typescript-references-code-lens-enabled t))
  (should (eq lsp-typescript-implementations-code-lens-enabled t))
  (should (eq lsp-javascript-references-code-lens-enabled t)))

(ert-deftest lsp/lens-settings-reach-rust-analyzer ()
  "What rust-analyzer is sent when it starts: references on, Debug off."
  (require 'lsp-rust)
  (let ((lens (plist-get (lsp-rust-analyzer--make-init-options) :lens)))
    (should (eq (plist-get (plist-get lens :debug) :enable) :json-false))
    (let ((references (plist-get lens :references)))
      (dolist (kind '(:adt :enumVariant :method :trait))
        (should (eq (plist-get (plist-get references kind) :enable) t))))))

(ert-deftest lsp/lens-settings-reach-typescript-server ()
  "What typescript-language-server is sent (workspace/configuration)."
  (require 'lsp-javascript)
  (let ((setting (lambda (section key)
                   (gethash "enabled"
                            (gethash key (gethash section (lsp-configuration-section section)))))))
    (should (eq (funcall setting "typescript" "referencesCodeLens") t))
    (should (eq (funcall setting "typescript" "implementationsCodeLens") t))
    (should (eq (funcall setting "javascript" "referencesCodeLens") t))))

;; ====== CODE LENSES, CHEAPER ======

(ert-deftest lsp/lens-at-end-of-line-by-default ()
  "lsp-mode's default placement, the one the shortcut applies to."
  (should (eq (default-value 'lsp-lens-place-position) 'end-of-line))
  (should (advice-member-p #'+my/lsp-lens-end-of-line-a 'lsp-lens--update)))

(ert-deftest lsp/lens-end-of-line-shown-after-the-line ()
  (+test-with-reset
    (let* ((lsp-lens-place-position 'end-of-line)
           (ov (+test-lsp--lens-overlay "fn main() {}\nsecond line\n" "▶ Run | 3 references")))
      (with-current-buffer (overlay-buffer ov)
        (lsp-lens--update ov))
      (let ((after (overlay-get ov 'after-string)))
        (should (equal after " ▶ Run | 3 references"))
        ;; The cursor stays before the lens (at the end of the line).
        (should (eq (get-text-property 0 'cursor after) t))
        (should (eq (get-text-property (1- (length after)) 'cursor after) t)))
      (should (equal (overlay-get ov 'lsp-original) "▶ Run | 3 references"))
      (should-not (overlay-get ov 'before-string)))))

(ert-deftest lsp/lens-end-of-line-does-not-measure-the-line ()
  "Nothing measures where the line starts on screen (which highlighted it)."
  (+test-with-reset
    (let* ((lsp-lens-place-position 'end-of-line)
           (ov (+test-lsp--lens-overlay "    indented() {}\n" "2 references"))
           (measured nil))
      (switch-to-buffer (overlay-buffer ov))
      (cl-letf (((symbol-function 'beginning-of-visual-line)
                 (lambda (&rest _) (setq measured t)))
                ((symbol-function 'lsp-lens--text-width)
                 (lambda (&rest _) (setq measured t) 0)))
        (lsp-lens--update ov))
      (should-not measured)
      (should (equal (overlay-get ov 'after-string) " 2 references")))))

(ert-deftest lsp/lens-end-of-line-same-as-lsp-mode ()
  "The shortcut shows exactly what lsp-mode's own update did."
  (+test-with-reset
    (let* ((lsp-lens-place-position 'end-of-line)
           (ours (+test-lsp--lens-overlay "    let x = 1;\n" "1 reference" "*ours*"))
           (theirs (+test-lsp--lens-overlay "    let x = 1;\n" "1 reference" "*theirs*")))
      (switch-to-buffer (overlay-buffer ours))
      (with-current-buffer (overlay-buffer ours) (lsp-lens--update ours))
      (with-current-buffer (overlay-buffer theirs)
        (+test-lsp--without-advice 'lsp-lens--update #'+my/lsp-lens-end-of-line-a
          (lsp-lens--update theirs)))
      (should (equal-including-properties (overlay-get ours 'after-string)
                                          (overlay-get theirs 'after-string)))
      (should (equal (overlay-get ours 'lsp-original) (overlay-get theirs 'lsp-original))))))

(ert-deftest lsp/lens-update-again-replaces ()
  "New contents (e.g. a count that changed) replace the old ones."
  (+test-with-reset
    (let* ((lsp-lens-place-position 'end-of-line)
           (ov (+test-lsp--lens-overlay "x\n" "1 reference")))
      (lsp-lens--update ov)
      (overlay-put ov 'lsp--lens-contents "2 references")
      (lsp-lens--update ov)
      (should (equal (overlay-get ov 'after-string) " 2 references"))
      (should (equal (overlay-get ov 'lsp-original) "2 references")))))

(ert-deftest lsp/lens-above-line-left-to-lsp-mode ()
  "Lenses above the line still go through lsp-mode (they need the indentation)."
  (+test-with-reset
    (let* ((lsp-lens-place-position 'above-line)
           (ov (+test-lsp--lens-overlay "    indented() {}\n" "2 references")))
      (switch-to-buffer (overlay-buffer ov))
      (lsp-lens--update ov)
      (should (equal (overlay-get ov 'before-string) "    2 references\n"))
      (should (equal (overlay-get ov 'lsp-original) "    2 references"))
      (should-not (overlay-get ov 'after-string)))))

(ert-deftest lsp/lens-advice-calls-through-only-when-not-end-of-line ()
  (let ((called nil)
        (ov (make-overlay 1 1 (get-buffer-create " *lsp-lens-advice*"))))
    (overlay-put ov 'lsp--lens-contents "lens")
    (unwind-protect
        (progn
          (let ((lsp-lens-place-position 'end-of-line))
            (+my/lsp-lens-end-of-line-a (lambda (o) (setq called o)) ov)
            (should-not called))
          (let ((lsp-lens-place-position 'above-line))
            (+my/lsp-lens-end-of-line-a (lambda (o) (setq called o)) ov)
            (should (eq called ov))))
      (kill-buffer " *lsp-lens-advice*"))))

(ert-deftest lsp/lens-empty-contents ()
  "A lens with no text (yet) shows a lone space, as lsp-mode would."
  (+test-with-reset
    (let* ((lsp-lens-place-position 'end-of-line)
           (ov (+test-lsp--lens-overlay "x\n" "")))
      (lsp-lens--update ov)
      (should (equal (overlay-get ov 'after-string) " ")))))

;; ====== PROJECT IMPORT ======

(ert-deftest lsp/import-advice-installed ()
  (should (advice-member-p #'+my/lsp-auto-import-project-a 'lsp--calculate-root)))

(ert-deftest lsp/import-guesses-from-the-file-inside-a-project ()
  "lsp-mode is asked from the file's folder, with `lsp-auto-guess-root' on."
  (let* ((root (+test-lsp--project "src/main.py"))
         (file (expand-file-name "src/main.py" root))
         (seen nil)
         (default-directory (+test-lsp--dir "elsewhere"))
         (before default-directory))
    (should (equal (+my/lsp-auto-import-project-a
                    (lambda (session file-name)
                      (setq seen (list default-directory lsp-auto-guess-root session file-name))
                      'root)
                    'the-session file)
                   'root))
    (should (equal (nth 0 seen) (expand-file-name "src/" root)))
    (should (eq (nth 1 seen) t))
    (should (eq (nth 2 seen) 'the-session))
    (should (equal (nth 3 seen) file))
    ;; Nothing changed for the caller.
    (should (equal default-directory before))
    (should (eq lsp-auto-guess-root nil))))

(ert-deftest lsp/import-asks-outside-a-project ()
  "Outside a project, `lsp-auto-guess-root' is off, even if set globally."
  (let* ((dir (+test-lsp--dir "loose"))
         (file (expand-file-name "notes.py" dir))
         (seen :not-called))
    (should-not (doom-project-root dir))
    (dolist (global '(nil t))
      (let ((lsp-auto-guess-root global))
        (+my/lsp-auto-import-project-a
         (lambda (_session _file) (setq seen lsp-auto-guess-root))
         nil file)
        (should (eq seen nil))
        (should (eq lsp-auto-guess-root global))))))

(ert-deftest lsp/import-project-root-without-prompt ()
  "lsp-mode's own root calculation: the project's root, no question asked."
  (let* ((root (+test-lsp--project "pkg/deep/mod.py"))
         (file (expand-file-name "pkg/deep/mod.py" root))
         (asked nil))
    (cl-letf (((symbol-function 'lsp--find-root-interactively)
               (lambda (&rest _) (setq asked t) nil))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) (setq asked t) nil))
              ((symbol-function 'completing-read) (lambda (&rest _) (setq asked t) nil)))
      ;; From a buffer elsewhere (e.g. *scratch* in ~): the file decides.
      (let ((default-directory (+test-lsp--dir "elsewhere")))
        (should (file-equal-p (lsp--calculate-root (make-lsp-session) file) root))))
    (should-not asked)))

(ert-deftest lsp/import-outside-project-still-asks ()
  "A file in no project: lsp-mode's \"import project root?\" prompt."
  (let* ((dir (+test-lsp--dir "loose"))
         (file (expand-file-name "script.py" dir))
         (asked nil))
    (cl-letf (((symbol-function 'lsp--find-root-interactively)
               (lambda (&rest _) (setq asked t) dir)))
      (should (equal (lsp--calculate-root (make-lsp-session) file) dir)))
    (should asked)))

(ert-deftest lsp/import-outside-project-never-guesses-home ()
  "Even with `lsp-auto-guess-root' set globally, a file outside a project
isn't imported with its folder (or ~) as root: lsp-mode asks."
  (let* ((dir (+test-lsp--dir "loose"))
         (file (expand-file-name "script.py" dir))
         (lsp-auto-guess-root t)
         (asked nil))
    (cl-letf (((symbol-function 'lsp--find-root-interactively)
               (lambda (&rest _) (setq asked t) nil)))
      (should-not (lsp--calculate-root (make-lsp-session) file)))
    (should asked)))

(ert-deftest lsp/import-keeps-the-blocklist ()
  "A blocklisted folder is still refused (no root, no prompt)."
  (let* ((root (+test-lsp--project "a.py"))
         (file (expand-file-name "a.py" root))
         (session (make-lsp-session :folders-blocklist (list root)))
         (asked nil))
    (cl-letf (((symbol-function 'lsp--find-root-interactively)
               (lambda (&rest _) (setq asked t) root))
              ((symbol-function 'lsp--info) #'ignore))
      (should-not (lsp--calculate-root session file)))
    (should-not asked)))

(ert-deftest lsp/import-nested-project-uses-the-innermost ()
  "A repository inside another (e.g. cloned in a workspace): its own root."
  (let* ((outer (+test-lsp--project "inner/src/x.py"))
         (inner (expand-file-name "inner/" outer))
         (file (expand-file-name "inner/src/x.py" outer)))
    (make-directory (expand-file-name ".git" inner))
    (cl-letf (((symbol-function 'lsp--find-root-interactively)
               (lambda (&rest _) (error "Asked"))))
      (should (file-equal-p (lsp--calculate-root (make-lsp-session) file) inner)))))

;; ====== FILE WATCHERS ======

(ert-deftest lsp/gitignored-runs-git-ls-files-in-the-root ()
  (let ((root (+test-lsp--dir "repo")))
    (+test-lsp--with-git-output "" 0
      (+my/lsp-gitignored-directories root)
      (should (= (length calls) 1))
      (pcase-let ((`(,dir ,program ,infile ,destination ,display . ,args) (car calls)))
        (should (equal dir (file-name-as-directory (file-truename root))))
        (should (equal program "git"))
        (should-not infile)
        (should (eq destination t))
        (should-not display)
        (should (equal args '("ls-files" "-z" "--others" "--ignored"
                              "--exclude-standard" "--directory")))))))

(ert-deftest lsp/gitignored-directories-only ()
  "Ignored files (no slash at the end) aren't directories to skip."
  (let* ((root (+test-lsp--dir "repo"))
         (true (file-name-as-directory (file-truename root))))
    (+test-lsp--with-git-output "build/\0debug.log\0node_modules/\0src/gen/\0.env\0" 0
      (should (equal (+my/lsp-gitignored-directories root)
                     (list (concat "\\`" (regexp-quote (concat true "build")) "\\'")
                           (concat "\\`" (regexp-quote (concat true "node_modules")) "\\'")
                           (concat "\\`" (regexp-quote (concat true "src/gen")) "\\'")))))))

(ert-deftest lsp/gitignored-regexps-anchored ()
  "Each regexp matches that folder only: not its subfolders (already skipped
with it), nor folders whose name contains it."
  (let* ((root (+test-lsp--dir "repo"))
         (true (directory-file-name (file-truename root))))
    (+test-lsp--with-git-output "build/\0" 0
      (let ((re (car (+my/lsp-gitignored-directories root))))
        (should (string-match-p re (concat true "/build")))
        (should-not (string-match-p re (concat true "/build/classes")))
        (should-not (string-match-p re (concat true "/mybuild")))
        (should-not (string-match-p re (concat true "/src/build")))
        (should-not (string-match-p re (concat "/other" true "/build")))))))

(ert-deftest lsp/gitignored-regexps-quoted ()
  "Folder names with regexp characters match literally."
  (let* ((root (+test-lsp--dir "repo"))
         (true (directory-file-name (file-truename root))))
    (+test-lsp--with-git-output "c++ (old)/\0a.b/\0[x]*/\0" 0
      (let ((res (+my/lsp-gitignored-directories root)))
        (should (= (length res) 3))
        (should (string-match-p (nth 0 res) (concat true "/c++ (old)")))
        (should-not (string-match-p (nth 0 res) (concat true "/cc (old)")))
        (should (string-match-p (nth 1 res) (concat true "/a.b")))
        (should-not (string-match-p (nth 1 res) (concat true "/axb")))
        (should (string-match-p (nth 2 res) (concat true "/[x]*")))
        (should-not (string-match-p (nth 2 res) (concat true "/x")))))))

(ert-deftest lsp/gitignored-folder-names-taken-literally ()
  "A folder named ~ (a tool that didn't expand ~ made it) or ~user is the
repository's own, not a home folder."
  (let* ((root (+test-lsp--dir "repo"))
         (true (directory-file-name (file-truename root))))
    (+test-lsp--with-git-output "~/\0~root/\0" 0
      (let ((res (+my/lsp-gitignored-directories root)))
        (should (equal res (list (concat "\\`" (regexp-quote (concat true "/~")) "\\'")
                                 (concat "\\`" (regexp-quote (concat true "/~root")) "\\'"))))
        (should-not (string-match-p (car res) (directory-file-name (expand-file-name "~/"))))))))

(ert-deftest lsp/gitignored-uses-the-true-root ()
  "A root reached through a symlink: the regexps name the real path, the one
lsp-mode watches (it watches the root's `file-truename')."
  (let* ((real (+test-lsp--dir "real"))
         (link (concat (directory-file-name (+test-lsp--dir "links")) "/repo")))
    (make-symbolic-link (directory-file-name real) link)
    (+test-lsp--with-git-output "out/\0" 0
      (let ((res (+my/lsp-gitignored-directories link)))
        (should (equal (car (car calls)) (file-name-as-directory (file-truename real))))
        (should (string-match-p (car res) (concat (directory-file-name (file-truename real)) "/out")))
        (should-not (string-match-p (car res) (concat link "/out")))))))

(ert-deftest lsp/gitignored-root-without-slash ()
  (let* ((root (+test-lsp--dir "repo"))
         (true (file-name-as-directory (file-truename root))))
    (+test-lsp--with-git-output "dist/\0" 0
      (should (equal (+my/lsp-gitignored-directories (directory-file-name root))
                     (list (concat "\\`" (regexp-quote (concat true "dist")) "\\'"))))
      (should (equal (car (car calls)) true)))))

(ert-deftest lsp/gitignored-nothing-ignored ()
  (let ((root (+test-lsp--dir "repo")))
    (+test-lsp--with-git-output "" 0
      (should-not (+my/lsp-gitignored-directories root)))))

(ert-deftest lsp/gitignored-not-a-repository ()
  "git fails (e.g. not a repository: exit 128): nothing skipped, whatever it
printed."
  (let ((root (+test-lsp--dir "plain")))
    (+test-lsp--with-git-output "fatal: not a git repository/\0" 128
      (should-not (+my/lsp-gitignored-directories root)))))

(ert-deftest lsp/gitignored-git-killed ()
  "git killed by a signal (`call-process' returns a string): nothing skipped."
  (let ((root (+test-lsp--dir "repo")))
    (+test-lsp--with-git-output "build/\0" "Killed"
      (should-not (+my/lsp-gitignored-directories root)))))

(ert-deftest lsp/gitignored-git-missing ()
  "No git installed: no error, nothing skipped."
  (let ((root (+test-lsp--dir "repo")))
    (+test-lsp--with-git-output "" (lambda () (signal 'file-missing '("Searching for program" "No such file or directory" "git")))
      (should-not (+my/lsp-gitignored-directories root)))))

(ert-deftest lsp/gitignored-leaves-no-buffer ()
  (let ((root (+test-lsp--dir "repo"))
        (buffers (buffer-list)))
    (+test-lsp--with-git-output "build/\0" 0
      (+my/lsp-gitignored-directories root))
    (should (equal (buffer-list) buffers))))

(ert-deftest lsp/gitignored-with-real-git ()
  "Against git itself, in a repository made in the temp folder (no global or
system git config read). A folder holding only ignored files is skipped too
(git lists it as a folder); one with a file git tracks isn't."
  (skip-unless (executable-find "git"))
  (let* ((root (+test-lsp--dir "gitrepo"))
         (home (+test-lsp--dir "githome"))
         (process-environment (append (list (concat "HOME=" home)
                                            "GIT_CONFIG_GLOBAL=/dev/null"
                                            "GIT_CONFIG_NOSYSTEM=1")
                                      process-environment))
         (true (file-name-as-directory (file-truename root))))
    (let ((default-directory root))
      (should (eql 0 (call-process "git" nil nil nil "init" "-q"))))
    (dolist (dir '("src/" "big/a/" "big/b/" "src/gen/" "logs/" "data/"))
      (make-directory (expand-file-name dir root) t))
    (dolist (file '("src/main.rs" "big/a/x" "src/gen/out.rs" "logs/run.log" "notes.tmp"
                    "data/old.log" "data/keep.csv"))
      (with-temp-file (expand-file-name file root) (insert "x")))
    (with-temp-file (expand-file-name ".gitignore" root)
      (insert "big/\nsrc/gen/\n*.log\n*.tmp\n"))
    (let ((res (+my/lsp-gitignored-directories root)))
      (should (equal (sort (copy-sequence res) #'string<)
                     (sort (list (concat "\\`" (regexp-quote (concat true "big")) "\\'")
                                 (concat "\\`" (regexp-quote (concat true "logs")) "\\'")
                                 (concat "\\`" (regexp-quote (concat true "src/gen")) "\\'"))
                           #'string<))))))

(ert-deftest lsp/watch-advice-installed ()
  (should (advice-member-p #'+my/lsp-watch-skip-gitignored-a
                           'lsp--get-ignored-regexes-for-workspace-root)))

(ert-deftest lsp/watch-advice-appends-to-directories-keeps-files ()
  (let ((files '("\\.pyc\\'"))
        (dirs '("[/\\\\]\\.git\\'" "[/\\\\]node_modules\\'"))
        (got nil))
    (cl-letf (((symbol-function '+my/lsp-gitignored-directories)
               (lambda (root) (setq got root) '("\\`/r/big\\'" "\\`/r/out\\'"))))
      (let ((res (+my/lsp-watch-skip-gitignored-a (lambda (_root) (list files dirs)) "/r/")))
        (should (equal got "/r/"))
        (should (eq (nth 0 res) files))
        (should (equal (nth 1 res) (append dirs '("\\`/r/big\\'" "\\`/r/out\\'"))))
        ;; lsp-mode's own list isn't changed in place.
        (should (equal dirs '("[/\\\\]\\.git\\'" "[/\\\\]node_modules\\'")))))))

(ert-deftest lsp/watch-advice-nothing-ignored ()
  (cl-letf (((symbol-function '+my/lsp-gitignored-directories) (lambda (_) nil)))
    (should (equal (+my/lsp-watch-skip-gitignored-a (lambda (_) (list '("f") '("d"))) "/r/")
                   (list '("f") '("d"))))))

(ert-deftest lsp/watch-skips-gitignored-folders ()
  "lsp-mode's list of folders to watch leaves out what git ignores (and still
its own defaults), with the root as lsp-mode gives it."
  (let* ((root (+test-lsp--project "src/a.rs" "big/one/x" "big/two/y" "node_modules/m/z"))
         (true (file-truename root)))
    (+test-lsp--with-git-output "big/\0" 0
      (let* ((ignored (lsp--get-ignored-regexes-for-workspace-root root))
             (watched (lsp--all-watchable-directories (directory-file-name true) (cadr ignored))))
        (should (equal (car ignored) lsp-file-watch-ignored-files))
        (should (cl-subsetp lsp-file-watch-ignored-directories (cadr ignored) :test #'equal))
        (should (member (expand-file-name "src" true) watched))
        (should-not (member (expand-file-name "big" true) watched))
        (should-not (member (expand-file-name "big/one" true) watched))
        (should-not (member (expand-file-name "node_modules" true) watched)) ; lsp-mode's own
        (should-not (member (expand-file-name ".git" true) watched))))))

(ert-deftest lsp/watch-not-a-repository-watches-all ()
  "Outside git, lsp-mode watches as it would (its own skips only)."
  (let ((root (+test-lsp--project "a/x" "b/y")))
    (+test-lsp--with-git-output "" 128
      (let ((ignored (lsp--get-ignored-regexes-for-workspace-root root)))
        (should (equal (cadr ignored) (lsp-file-watch-ignored-directories)))
        (let ((watched (lsp--all-watchable-directories
                        (directory-file-name (file-truename root)) (cadr ignored))))
          (should (member (expand-file-name "a" (file-truename root)) watched))
          (should (member (expand-file-name "b" (file-truename root)) watched)))))))

;; ====== KOTLIN ======

(defun +test-lsp--kotlin-client ()
  (gethash 'kotlin-lsp lsp-clients))

(ert-deftest lsp/kotlin-registered-when-lsp-mode-loads ()
  "Registered in `after! lsp-mode': not before lsp-mode loads."
  (should-not (plist-get +test-lsp--after-config :clients))
  (should (+test-lsp--kotlin-client)))

(ert-deftest lsp/kotlin-client ()
  (let ((client (+test-lsp--kotlin-client)))
    (should (eq (lsp--client-server-id client) 'kotlin-lsp))
    (should (equal (lsp--client-major-modes client) '(kotlin-mode kotlin-ts-mode)))
    (should (eql (lsp--client-priority client) 1))
    (should-not (lsp--client-add-on? client))
    (should-not (lsp--client-remote? client))))

(ert-deftest lsp/kotlin-command ()
  "It would run `kotlin-lsp --stdio' (the process start is mocked)."
  (let* ((connection (lsp--client-new-connection (+test-lsp--kotlin-client)))
         (started nil))
    (cl-letf (((symbol-function 'make-process)
               (lambda (&rest args) (setq started args) (throw '+test-lsp--started nil)))
              ((symbol-function 'lsp-json-rpc-connection)
               (lambda (_workspace command)
                 (setq started (list :command command)) (throw '+test-lsp--started nil))))
      (let ((default-directory (+test-lsp--dir "kt")))
        (catch '+test-lsp--started
          (funcall (plist-get connection :connect) #'ignore #'ignore "kotlin-lsp" nil nil))))
    (should (equal (plist-get started :command) '("kotlin-lsp" "--stdio")))
    (dolist (buffer (buffer-list))      ; the stderr buffer lsp-mode made first
      (when (string-match-p "kotlin-lsp" (buffer-name buffer))
        (kill-buffer buffer)))))

(ert-deftest lsp/kotlin-present-when-kotlin-lsp-is-installed ()
  "lsp-mode looks for the `kotlin-lsp' executable (brew's cask)."
  (let* ((connection (lsp--client-new-connection (+test-lsp--kotlin-client)))
         (looked nil))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (push name looked) nil)))
      (should-not (funcall (plist-get connection :test?))))
    (should (equal looked '("kotlin-lsp")))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and (equal name "kotlin-lsp") "/opt/homebrew/bin/kotlin-lsp"))))
      (should (funcall (plist-get connection :test?))))))

(ert-deftest lsp/kotlin-wins-over-kotlin-language-server ()
  "In a Kotlin buffer with both servers installed, lsp-mode picks kotlin-lsp."
  (require 'lsp-kotlin)
  (require 'kotlin-mode)
  (should (< (lsp--client-priority (gethash 'kotlin-ls lsp-clients))
             (lsp--client-priority (+test-lsp--kotlin-client))))
  (let ((buffer (+test-buffer "Main.kt")))
    (unwind-protect
        (with-current-buffer buffer
          (setq buffer-file-name (expand-file-name "Main.kt" (+test-lsp--dir "kt")))
          (delay-mode-hooks (kotlin-mode))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (name &rest _) (concat "/usr/local/bin/" name))))
            (let ((clients (lsp--find-clients)))
              (should (equal (mapcar #'lsp--client-server-id clients) '(kotlin-lsp)))))
          (setq buffer-file-name nil))
      (kill-buffer buffer))))

(ert-deftest lsp/kotlin-without-kotlin-lsp-falls-back ()
  "Only kotlin-language-server installed: that one is used."
  (require 'lsp-kotlin)
  (require 'kotlin-mode)
  (let ((buffer (+test-buffer "Other.kt")))
    (unwind-protect
        (with-current-buffer buffer
          (setq buffer-file-name (expand-file-name "Other.kt" (+test-lsp--dir "kt")))
          (delay-mode-hooks (kotlin-mode))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (name &rest _)
                       (and (string-suffix-p "kotlin-language-server" name)
                            "/usr/local/bin/kotlin-language-server"))))
            (should (equal (mapcar #'lsp--client-server-id (lsp--find-clients)) '(kotlin-ls))))
          (setq buffer-file-name nil))
      (kill-buffer buffer))))

(ert-deftest lsp/kotlin-not-for-other-modes ()
  (require 'kotlin-mode)
  (let ((buffer (+test-buffer "x.py")))
    (unwind-protect
        (with-current-buffer buffer
          (python-mode)
          (should-not (lsp--supports-buffer? (+test-lsp--kotlin-client))))
      (kill-buffer buffer))))
