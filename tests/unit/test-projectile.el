;;; tests/unit/test-projectile.el -*- lexical-binding: t; -*-
;; config/projectile.el: no search path of its own (config.el's); the project's
;; files listed without a cache; a project (SPC p p) opens on its README; each workspace
;; remembers its project (the dashboard is in the current workspace's one) and
;; keeps the buffers shown in it. Projects are temp folders (with a .git);
;; workspaces are persp-mode structs, `get-current-persp' mocked, but real
;; persp-mode for the buffers kept and SPC p p; Doom's dashboard functions and
;; its SPC p p come from its source.

;; ====== LOADING ======

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "projectile"))))))
  (dolist (package '("projectile" "persp-mode"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(defconst +test-projectile--doom-dashboard
  (seq-find #'file-exists-p
            (list (expand-file-name "sources/doom+/modules/ui/dashboard/config.el" doom-emacs-dir)
                  (expand-file-name "ui/dashboard/config.el" doom-modules-dir)))
  "Doom's dashboard module (the functions the config advises).")

(defun +test-projectile--load-doom-defs (file names)
  "Evaluate the definitions of NAMES (defun, defvar, defcustom) from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (memq (car-safe form) '(defun defvar defcustom))
                       (memq (cadr form) names))
              (eval form t))))
      (end-of-file nil))))

;; As Doom: its modules first, then this config.
(when +test-projectile--doom-dashboard
  (+test-projectile--load-doom-defs
   +test-projectile--doom-dashboard
   '(+dashboard-name +dashboard-pwd-policy +dashboard--last-cwd
     +dashboard--persp-detect-project-h +dashboard--persp-record-project-h
     +dashboard-update-pwd-h +dashboard--pwd)))
(defvar +workspaces-switch-project-function #'doom-project-find-file) ; Doom's workspaces module

(defconst +test-projectile--doom-workspaces
  (seq-find #'file-exists-p
            (list (expand-file-name "sources/doom+/modules/ui/workspaces/autoload/workspaces.el"
                                    doom-emacs-dir)
                  (expand-file-name "ui/workspaces/autoload/workspaces.el" doom-modules-dir)))
  "Doom's workspaces module's functions (SPC p p: `+workspaces-switch-to-project-h').")

(when +test-projectile--doom-workspaces
  ;; Its settings (the module's config.el), as Doom has them.
  (defvar +workspaces-main "main")
  (defvar +workspaces-on-switch-project-behavior 'non-empty)
  (defvar +workspace--last nil)
  (defvar +workspaces-data-file "_workspaces")
  (require 'persp-mode)                 ; its structs' setters, as it's read
  (load +test-projectile--doom-workspaces nil t))

(+test-load "config/projectile")

(require 'projectile)
(require 'persp-mode)

;; ====== HELPERS ======

(defun +test-projectile--dir (name &rest files)
  "A new folder NAME in the temp folder with FILES (\"x/\": a folder); its
path (a directory name, links resolved: /var is /private/var on macOS, and
projectile resolves them)."
  (let ((dir (file-name-as-directory
              (file-truename (make-temp-file (+test-tmp-file (concat name "-")) t)))))
    (dolist (file files)
      (let ((path (expand-file-name file dir)))
        (if (directory-name-p file)
            (make-directory path t)
          (make-directory (file-name-directory path) t)
          (with-temp-file path (insert file "\n")))))
    dir))

(defun +test-projectile--project (name &rest files)
  "A project NAME (a .git folder) with FILES; its root."
  (apply #'+test-projectile--dir name ".git/" files))

(defmacro +test-projectile-need-doom-workspaces ()
  '(unless (fboundp '+workspaces-switch-to-project-h)
     (ert-skip "Doom's workspaces module isn't there")))

(defmacro +test-projectile-need-dashboard ()
  '(unless (fboundp '+dashboard--persp-record-project-h)
     (ert-skip "Doom's dashboard module isn't there")))

(defvar +test-projectile--persp nil "The current workspace (mocked).")

(defmacro +test-projectile-with-workspaces (&rest body)
  "BODY with workspaces on: `+test-projectile--persp' the current one (nil:
none), one window on *scratch* before and after, a dashboard buffer (*doom*,
Doom's fallback buffer)."
  (declare (indent 0))
  `(+test-with-reset
     (let ((persp-mode t)
           (+test-projectile--persp (make-persp :name "one"))
           (doom-fallback-buffer-name "*doom*")
           (projectile-project-root-cache (make-hash-table :test #'equal)))
       (cl-letf (((symbol-function 'get-current-persp)
                  (lambda (&rest _) +test-projectile--persp)))
         ,@body))))

(defun +test-projectile--show (file-or-buffer)
  "Show FILE-OR-BUFFER in the selected window; its buffer."
  (switch-to-buffer (if (bufferp file-or-buffer)
                        file-or-buffer
                      (find-file-noselect file-or-buffer)))
  (current-buffer))

(defun +test-projectile--dashboard ()
  "Doom's dashboard buffer (its fallback buffer), in its own folder."
  (let ((buffer (get-buffer-create "*doom*")))
    (with-current-buffer buffer
      (setq default-directory (file-name-as-directory temporary-file-directory)))
    buffer))

(defun +test-projectile--dashboard-dir ()
  (buffer-local-value 'default-directory (get-buffer "*doom*")))

;; ====== PROJECTS ======

(ert-deftest projectile/no-search-path-of-its-own ()
  "Where projects are is config.el's (test-config.el): loading this sets none,
leaves one set before as it is."
  (let ((projectile-project-search-path '("~/elsewhere")))
    (+test-load "config/projectile")
    (should (equal projectile-project-search-path '("~/elsewhere"))))
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config/projectile.el" +test-root))
    (should-not (search-forward "(setq projectile-project-search-path" nil t))))

(ert-deftest projectile/no-file-cache ()
  "No cache, even after Doom's own setting (its projectile :init, before)."
  (should-not projectile-enable-caching)
  (let ((projectile-enable-caching 'persistent))
    (+test-load "config/projectile")
    (should-not projectile-enable-caching)))

(ert-deftest projectile/file-list-fresh-every-time ()
  "Files made outside Emacs (CLI, Claude Code, git checkout) are listed right
away (with a cache they weren't)."
  (let* ((root (+test-projectile--dir "proj-files" "a.txt" "src/b.kt"))
         (default-directory root)
         (home (+test-tmp-file "projectile-git-home/"))
         (process-environment (append (list (concat "HOME=" home)
                                            (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                                            "GIT_CONFIG_NOSYSTEM=1"
                                            (concat "XDG_CONFIG_HOME=" home ".config"))
                                      process-environment))
         (projectile-projects-cache (make-hash-table :test #'equal))
         (projectile-projects-cache-time (make-hash-table :test #'equal))
         (projectile-cache-file (+test-tmp-file "projectile.cache"))
         (projectile-project-root-cache (make-hash-table :test #'equal)))
    (call-process "git" nil nil nil "init" "-q")
    (should (equal (sort (projectile-project-files root) #'string<) '("a.txt" "src/b.kt")))
    (with-temp-file (expand-file-name "new.txt" root) (insert "made outside\n"))
    (should (member "new.txt" (projectile-project-files root)))
    ;; With a cache (Doom's default) the new file was missing.
    (let ((projectile-enable-caching t))
      (projectile-project-files root)
      (with-temp-file (expand-file-name "newer.txt" root) (insert "x\n"))
      (should-not (member "newer.txt" (projectile-project-files root))))
    (should (member "newer.txt" (projectile-project-files root)))))

;; ====== README FIRST ======

(ert-deftest projectile/readme-extensions ()
  (should (equal +my/project-readme-extensions '("md" "markdown" "org" "rst" "adoc" "txt" ""))))

(ert-deftest projectile/readme-found ()
  (let ((dir (+test-projectile--dir "readme" "README.md" "src/x.kt" "notes.md")))
    (should (equal (+my/project-readme dir) (expand-file-name "README.md" dir)))
    (should (file-name-absolute-p (+my/project-readme dir)))))

(ert-deftest projectile/readme-preferred-kinds ()
  "Several READMEs: Markdown, then Org, reStructuredText, AsciiDoc, text, none."
  (dolist (case '((("README.md" "README.org" "README.txt" "README") . "README.md")
                  (("README.markdown" "README.org") . "README.markdown")
                  (("README.md" "README.markdown") . "README.md")
                  (("README.org" "README.rst" "README") . "README.org")
                  (("README.rst" "README.adoc") . "README.rst")
                  (("README.adoc" "README.txt") . "README.adoc")
                  (("README.txt" "README") . "README.txt")
                  (("README") . "README")))
    (let ((dir (apply #'+test-projectile--dir "readmes" (car case))))
      (should (equal (cons (car case) (+my/project-readme dir))
                     (cons (car case) (expand-file-name (cdr case) dir)))))))

(ert-deftest projectile/readme-any-case ()
  (dolist (name '("readme.md" "Readme.MD" "ReadMe.Org" "readme"))
    (let ((dir (+test-projectile--dir "readme-case" name)))
      (should (equal (+my/project-readme dir) (expand-file-name name dir))))))

(ert-deftest projectile/readme-not-these ()
  "Not a README: other extensions, other names, a folder, below the root."
  (let ((dir (+test-projectile--dir "readme-not" "README.html" "README.pdf" "README-dev.md"
                                    "OLD_README.md" "READMEs.md" "README.md.bak" "README."
                                    "docs/README.md" "README.org/" "notes.md")))
    (should-not (+my/project-readme dir)))
  (should-not (+my/project-readme (+test-projectile--dir "readme-empty"))))

(ert-deftest projectile/readme-a-folder-loses-to-a-file ()
  (let ((dir (+test-projectile--dir "readme-dir" "README.md/" "README.txt")))
    (should (equal (+my/project-readme dir) (expand-file-name "README.txt" dir)))))

(ert-deftest projectile/readme-links ()
  "A link to a README counts; a broken one doesn't."
  (let* ((target (+test-file "readme-target/README.md" "x\n"))
         (dir (+test-projectile--dir "readme-link")))
    (make-symbolic-link target (expand-file-name "README.md" dir))
    (should (equal (+my/project-readme dir) (expand-file-name "README.md" dir)))
    (let ((broken (+test-projectile--dir "readme-broken")))
      (make-symbolic-link (expand-file-name "gone.md" broken) (expand-file-name "README.md" broken))
      (should-not (+my/project-readme broken)))))

(ert-deftest projectile/readme-extensions-setting ()
  (let ((dir (+test-projectile--dir "readme-setting" "README.md" "README.txt")))
    (let ((+my/project-readme-extensions '("txt" "md")))
      (should (equal (+my/project-readme dir) (expand-file-name "README.txt" dir))))
    (let ((+my/project-readme-extensions '("org")))
      (should-not (+my/project-readme dir)))))

(ert-deftest projectile/switch-project-opens-the-readme ()
  "SPC p p into a workspace showing nothing yet (Doom's fallback buffer): the
README, without asking for a file."
  (should (eq +workspaces-switch-project-function #'+my/project-open-readme))
  (+test-with-reset
    (let ((dir (+test-projectile--project "switch" "README.org" "README.txt" "src/a.kt"))
          (doom-fallback-buffer-name "*doom*")
          (asked nil))
      (switch-to-buffer (+test-projectile--dashboard))
      (cl-letf (((symbol-function 'doom-project-find-file)
                 (lambda (&rest args) (setq asked args))))
        (funcall +workspaces-switch-project-function dir))
      (should-not asked)
      (should (equal buffer-file-name (expand-file-name "README.org" dir)))
      (should (eq (window-buffer) (current-buffer))))))

(ert-deftest projectile/switch-project-without-readme-asks ()
  "No README: Doom's file prompt, in that project."
  (+test-with-reset
    (let ((dir (+test-projectile--project "switch-none" "src/a.kt" "docs/README.md"))
          (asked nil))
      (cl-letf (((symbol-function 'doom-project-find-file)
                 (lambda (&rest args) (setq asked args))))
        (+my/project-open-readme dir))
      (should (equal asked (list dir)))
      (should-not buffer-file-name))))

;; ====== WORKSPACES: THE FILE SHOWN ======

(ert-deftest projectile/shown-file-is-the-windows ()
  "The file in the selected window, not the current buffer (right after a
workspace switch, the previous workspace's file is still current)."
  (+test-projectile-with-workspaces
    (let* ((p1 (+test-projectile--project "shown-a" "a.txt"))
           (p2 (+test-projectile--project "shown-b" "b.txt"))
           (a (find-file-noselect (expand-file-name "a.txt" p1)))
           (b (+test-projectile--show (expand-file-name "b.txt" p2))))
      (should (eq (+my/workspace-shown-file) b))
      (with-current-buffer a
        (should (eq (+my/workspace-shown-file) b))))))

(ert-deftest projectile/shown-file-none ()
  "No file: a buffer without one, a remote file, no workspace, no workspaces."
  (+test-projectile-with-workspaces
    (+test-projectile--show (+test-projectile--dashboard))
    (should-not (+my/workspace-shown-file))
    (let ((remote (+test-projectile--show (+test-buffer "remote.txt"))))
      (with-current-buffer remote
        (setq buffer-file-name "/ssh:host:/srv/remote.txt"
              default-directory "/ssh:host:/srv/"))
      (should-not (+my/workspace-shown-file))
      (with-current-buffer remote (setq buffer-file-name nil)))
    (+test-projectile--show (expand-file-name "x.txt" (+test-projectile--project "shown-none" "x.txt")))
    (should (+my/workspace-shown-file))
    (let ((+test-projectile--persp nil))
      (should-not (+my/workspace-shown-file)))
    (let ((persp-mode nil))
      (should-not (+my/workspace-shown-file)))))

;; ====== WORKSPACES: RECORDING THEIR PROJECT ======

(ert-deftest projectile/record-project-on-buffer-switch ()
  (should (memq #'+my/workspace-record-project-h doom-switch-buffer-hook))
  (+test-projectile-with-workspaces
    (let* ((p1 (+test-projectile--project "rec-a" "a.txt"))
           (p2 (+test-projectile--project "rec-b" "b.txt"))
           (a (find-file-noselect (expand-file-name "a.txt" p1))))
      (+test-projectile--show (expand-file-name "b.txt" p2))
      ;; Run, as Doom does, in whatever buffer is current: the window's file counts.
      (with-current-buffer a (+my/workspace-record-project-h))
      (should (equal (persp-parameter 'last-project-root +test-projectile--persp) p2)))))

(ert-deftest projectile/record-project-only-from-files ()
  "The dashboard, a buffer without a file, a file without a project: the
workspace keeps its project."
  (+test-projectile-with-workspaces
    (let ((p1 (+test-projectile--project "rec-keep" "a.txt")))
      (+test-projectile--show (expand-file-name "a.txt" p1))
      (+my/workspace-record-project-h)
      (should (equal (persp-parameter 'last-project-root) p1))
      (+test-projectile--show (+test-projectile--dashboard))
      (+my/workspace-record-project-h)
      (+test-projectile--show (+test-buffer "*popup*"))
      (+my/workspace-record-project-h)
      (+test-projectile--show (+test-file "no-project/loose.txt" "x\n"))
      (should-not (doom-project-root))
      (+my/workspace-record-project-h)
      (should (equal (persp-parameter 'last-project-root) p1))
      ;; Without workspaces: nothing, no error.
      (let ((persp-mode nil))
        (+test-projectile--show (expand-file-name "a.txt" p1))
        (+my/workspace-record-project-h)))))

(ert-deftest projectile/leaving-records-the-shown-files-project ()
  "Leaving a workspace (Doom's `+dashboard--persp-record-project-h' on
`persp-before-switch-functions'): its project from the file it shows, even
when another buffer is current."
  (+test-projectile-need-dashboard)
  (should (advice-member-p #'+my/workspace-record-files-only-a #'+dashboard--persp-record-project-h))
  (+test-projectile-with-workspaces
    (let* ((p1 (+test-projectile--project "leave-a" "a.txt"))
           (p2 (+test-projectile--project "leave-b" "b.txt"))
           (b (find-file-noselect (expand-file-name "b.txt" p2))))
      (+test-projectile--show (expand-file-name "a.txt" p1))
      (with-current-buffer b
        (+dashboard--persp-record-project-h "two" (selected-frame)))
      (should (equal (persp-parameter 'last-project-root) p1))
      ;; From the dashboard (current), the file shown counts.
      (+test-projectile--show b)
      (with-current-buffer (+test-projectile--dashboard)
        (+dashboard--persp-record-project-h "two" (selected-window)))
      (should (equal (persp-parameter 'last-project-root) p2)))))

(ert-deftest projectile/leaving-the-dashboard-records-nothing ()
  "A workspace whose files were all closed (the dashboard shown, still in the
previous workspace's project) keeps its project."
  (+test-projectile-need-dashboard)
  (+test-projectile-with-workspaces
    (let ((p1 (+test-projectile--project "dash-a" "a.txt"))
          (p2 (+test-projectile--project "dash-b" "b.txt")))
      (set-persp-parameter 'last-project-root p1)
      (+test-projectile--show (+test-projectile--dashboard))
      (with-current-buffer "*doom*" (setq default-directory p2))
      (+dashboard--persp-record-project-h "two" (selected-frame))
      (should (equal (persp-parameter 'last-project-root) p1)))))

(ert-deftest projectile/leaving-from-a-file-in-no-project-records-nothing ()
  "Leaving while showing a file outside any project: the workspace keeps its
project (Doom's recorder stored none, and the workspace forgot it)."
  (+test-projectile-need-dashboard)
  (+test-projectile-with-workspaces
    (let ((p1 (+test-projectile--project "loose-a" "a.txt")))
      (+test-projectile--show (expand-file-name "a.txt" p1))
      (+dashboard--persp-record-project-h "two" (selected-frame))
      (should (equal (persp-parameter 'last-project-root) p1))
      (+test-projectile--show (+test-file "no-project-x/loose.txt" "x\n"))
      (should-not (doom-project-root))
      (+dashboard--persp-record-project-h "two" (selected-frame))
      (should (equal (persp-parameter 'last-project-root) p1))
      (should (equal (+my/workspace-project) p1)))))

(ert-deftest projectile/new-workspace-records-nothing ()
  "A workspace being made (`persp-created-functions': PERSP given): what's
shown is the previous workspace's; nothing recorded, in either."
  (+test-projectile-need-dashboard)
  (+test-projectile-with-workspaces
    (let* ((p1 (+test-projectile--project "new-a" "a.txt"))
           (new (make-persp :name "new")))
      (+test-projectile--show (expand-file-name "a.txt" p1))
      (+dashboard--persp-record-project-h new *persp-hash*)
      (should-not (persp-parameter 'last-project-root new))
      (should-not (persp-parameter 'last-project-root)))))

;; ====== WORKSPACES: THEIR PROJECT ======

(ert-deftest projectile/workspace-project ()
  "The project it was made for (SPC p p), else its last file's, else ~."
  (+test-projectile-with-workspaces
    (let ((p1 (+test-projectile--project "ws-a"))
          (p2 (+test-projectile--project "ws-b")))
      (should (equal (+my/workspace-project) (expand-file-name "~/")))
      (set-persp-parameter 'last-project-root (directory-file-name p2))
      (should (equal (+my/workspace-project) p2))   ; a directory name
      (set-persp-parameter '+workspace-project p1)
      (should (equal (+my/workspace-project) p1))
      (set-persp-parameter '+workspace-project "~/somewhere")
      (should (equal (+my/workspace-project) (expand-file-name "~/somewhere/"))))))

(ert-deftest projectile/workspace-project-without-workspaces ()
  (+test-projectile-with-workspaces
    (let ((+test-projectile--persp nil))
      (should-not (+my/workspace-project)))
    (let ((persp-mode nil))
      (should-not (+my/workspace-project)))))

(ert-deftest projectile/entering-puts-the-dashboard-in-its-project ()
  "Entering a workspace (`persp-activated-functions'): the dashboard in its
project, the one it was made for first (Doom's: its last file's only)."
  (+test-projectile-need-dashboard)
  (should (advice-member-p #'+my/workspace-own-project-a #'+dashboard--persp-detect-project-h))
  (+test-projectile-with-workspaces
    (let ((p1 (+test-projectile--project "enter-a"))
          (p2 (+test-projectile--project "enter-b")))
      (+test-projectile--dashboard)
      (set-persp-parameter '+workspace-project p1)
      (set-persp-parameter 'last-project-root p2)
      (+dashboard--persp-detect-project-h)
      (should (equal (+test-projectile--dashboard-dir) p1))
      ;; A workspace without a project yet: ~.
      (setq +test-projectile--persp (make-persp :name "fresh"))
      (+dashboard--persp-detect-project-h)
      (should (equal (+test-projectile--dashboard-dir) (expand-file-name "~/")))
      ;; Without workspaces: left alone.
      (let ((persp-mode nil))
        (with-current-buffer "*doom*" (setq default-directory p2))
        (+dashboard--persp-detect-project-h)
        (should (equal (+test-projectile--dashboard-dir) p2))))))

(ert-deftest projectile/dashboard-reload-keeps-the-workspaces-project ()
  "The dashboard's reload (`+dashboard--pwd', policy `last-project'): the
current workspace's project, not that of the last file visited anywhere;
without workspaces, Doom's."
  (+test-projectile-need-dashboard)
  (should (advice-member-p #'+my/workspace-dashboard-pwd-a #'+dashboard--pwd))
  (+test-projectile-with-workspaces
    (let* ((p1 (+test-projectile--project "pwd-a"))
           (p2 (+test-projectile--project "pwd-b" "sub/"))
           (+dashboard-pwd-policy 'last-project)
           (+dashboard--last-cwd (expand-file-name "sub/" p2)))
      (+test-projectile--dashboard)
      (set-persp-parameter 'last-project-root p1)
      (should (equal (+dashboard--pwd) p1))
      (+dashboard-update-pwd-h)
      (should (equal (+test-projectile--dashboard-dir) p1))
      (let ((persp-mode nil))
        (should (equal (+dashboard--pwd) p2))
        (+dashboard-update-pwd-h)
        (should (equal (+test-projectile--dashboard-dir) p2))))))

(ert-deftest projectile/workspaces-keep-their-projects ()
  "The story: W1 made for P1, W2 showing P2's file; W2's files all closed (the
dashboard, still in P1's folder); back and forth: W2 stays in P2, a new W3
starts in ~, never in another's."
  (+test-projectile-need-dashboard)
  (+test-projectile-with-workspaces
    (let* ((p1 (+test-projectile--project "story-a" "a.txt"))
           (p2 (+test-projectile--project "story-b" "b.txt"))
           (w1 (make-persp :name "w1"))
           (w2 (make-persp :name "w2"))
           (switch (lambda (to)
                     ;; Doom: record on leaving, detect on entering.
                     (+dashboard--persp-record-project-h (persp-name to) (selected-frame))
                     (setq +test-projectile--persp to)
                     (+dashboard--persp-detect-project-h))))
      (+test-projectile--dashboard)
      (setq +test-projectile--persp w1)
      (set-persp-parameter '+workspace-project p1 w1)
      (+test-projectile--show (expand-file-name "a.txt" p1))
      (+my/workspace-record-project-h)
      (funcall switch w2)
      (+test-projectile--show (expand-file-name "b.txt" p2))
      (+my/workspace-record-project-h)
      (should (equal (persp-parameter 'last-project-root w2) p2))
      ;; W2's file closed: the dashboard, in W1's project.
      (kill-buffer (get-file-buffer (expand-file-name "b.txt" p2)))
      (with-current-buffer "*doom*" (setq default-directory p1))
      (+test-projectile--show (get-buffer "*doom*"))
      (+my/workspace-record-project-h)
      (funcall switch w1)
      (should (equal (persp-parameter 'last-project-root w2) p2))
      (should (equal (+test-projectile--dashboard-dir) p1))
      (funcall switch w2)
      (should (equal (+test-projectile--dashboard-dir) p2))
      (should (equal (+dashboard--pwd) p2))
      ;; A new workspace.
      (let ((w3 (make-persp :name "w3")))
        (+dashboard--persp-record-project-h w3 *persp-hash*)
        (funcall switch w3)
        (should (equal (+test-projectile--dashboard-dir) (expand-file-name "~/")))
        (should-not (persp-parameter 'last-project-root w3))))))

;; ====== WORKSPACES KEEP WHAT'S SHOWN IN THEM ======
;; Real persp-mode (Doom's workspaces), nothing saved, Doom's settings and
;; filter (its unreal buffers not added). Batch Emacs never redisplays, so it
;; never runs `window-buffer-change-functions' and has no old buffers:
;; `+test-projectile--redisplay' runs the hook as redisplay would, with the
;; buffers the windows showed at the previous one.

(defvar +test-projectile--old nil
  "Each window's buffer at the last (simulated) redisplay: ((WINDOW . BUFFER)...).")

(defmacro +test-projectile-real-workspaces (&rest body)
  "BODY with persp-mode on, its workspaces A and B (A current); persp-mode off
and the buffers made killed after."
  (declare (indent 0))
  `(+test-with-reset
     (let ((before (buffer-list))
           (+test-projectile--old nil)
           (persp-auto-save-opt 0)
           (persp-auto-resume-time -1)
           (persp-reset-windows-on-nil-window-conf nil) ; Doom's
           (persp-save-dir (file-name-as-directory (+test-tmp-file "persp")))
           (persp-add-buffer-on-after-change-major-mode-filter-functions
            (list #'doom-unreal-buffer-p)))
       (persp-mode 1)
       (persp-add-new "A")
       (persp-add-new "B")
       (persp-frame-switch "A")
       (unwind-protect (progn ,@body)
         (persp-mode -1)
         (let ((kill-buffer-query-functions nil))
           (dolist (buffer (buffer-list))
             (unless (memq buffer before) (kill-buffer buffer))))))))

(defun +test-projectile--redisplay ()
  "Run `window-buffer-change-functions' on the selected frame as redisplay
does (see above), in whatever buffer is current."
  (cl-letf (((symbol-function 'window-old-buffer)
             (lambda (&optional window)
               (alist-get (window-normalize-window window) +test-projectile--old))))
    (run-hook-with-args 'window-buffer-change-functions (selected-frame)))
  (setq +test-projectile--old (mapcar (lambda (window) (cons window (window-buffer window)))
                                      (window-list nil 'nomini))))

(defun +test-projectile--in (buffer)
  "The names of the workspaces BUFFER is in."
  (sort (mapcar #'safe-persp-name (persp--buffer-in-persps buffer)) #'string<))

(defun +test-projectile--real (name)
  "A real buffer NAME (as Doom's are: a Claude session, through tiling)."
  (with-current-buffer (+test-buffer name "text\n")
    (setq-local doom-real-buffer-p t)
    (current-buffer)))

(ert-deftest projectile/a-buffer-shown-later-joins-the-workspace ()
  "A buffer shown from a timer or a callback (Claude Code's session once
picked; SPC o C), the previous buffer current again: it joins the current
workspace, not the one current (Doom's hook took that one), nor another."
  (should (memq #'+my/workspace-add-shown-buffers-h
                (default-value 'window-buffer-change-functions)))
  (+test-projectile-real-workspaces
    (let ((file (find-file-noselect (+test-file "shown.txt" "x\n")))
          (session (+test-projectile--real "Claude Agent @ shown")))
      (switch-to-buffer file)
      (+test-projectile--redisplay)
      (should (equal (+test-projectile--in file) '("A")))
      ;; The callback: the session shown and selected; then the file current.
      (set-window-buffer nil session)
      (with-current-buffer file
        (+test-projectile--redisplay))
      (should (equal (+test-projectile--in session) '("A")))
      ;; In a window not selected (a pane opened without focus) too.
      (let ((canvas (+test-projectile--real "canvas"))
            (other (split-window-right)))
        (set-window-buffer other canvas)
        (+test-projectile--redisplay)
        (should (equal (+test-projectile--in canvas) '("A")))))))

(ert-deftest projectile/only-real-buffers-join-the-workspace ()
  "Doom's filter: its unreal buffers (*Help*, a hidden one) join none."
  (+test-projectile-real-workspaces
    (dolist (name '("*Help*" " hidden"))
      (let ((buffer (+test-buffer name "x\n")))
        (set-window-buffer nil buffer)
        (+test-projectile--redisplay)
        (should-not (+test-projectile--in buffer))))))

(defun +test-projectile--prompt (buffer keys)
  "A command prompting as C-x 4 b does, with consult's preview: <f8> shows
BUFFER in another window (the screen then redisplayed), put back as the
prompt closes; \"pick\" RET shows it there, an empty RET nothing. KEYS
typed into it (`kbd' syntax); the screen redisplayed after."
  (let* ((origin (selected-window))
         (other nil)
         (keys-map (make-sparse-keymap))
         (minibuffer-local-map (make-composed-keymap keys-map minibuffer-local-map))
         (command-map (make-sparse-keymap)))
    (define-key keys-map (kbd "<f8>")
                (lambda ()
                  (interactive)
                  (with-selected-window origin
                    (setq other (or other (split-window-right)))
                    (set-window-buffer other buffer))
                  (+test-projectile--redisplay)))
    (define-key command-map (kbd "<f5>")
                (lambda ()
                  (interactive)
                  (let ((input (minibuffer-with-setup-hook
                                   (lambda ()
                                     (add-hook 'minibuffer-exit-hook
                                               (lambda ()
                                                 (when other
                                                   (set-window-buffer other (window-buffer origin))))
                                               nil t))
                                 (read-from-minibuffer "Buffer: "))))
                    ;; The window the preview opened is gone (Emacs puts
                    ;; the windows back as the prompt closes).
                    (when (equal input "pick")
                      (set-window-buffer (split-window-right) buffer)))))
    (use-local-map command-map)
    (execute-kbd-macro (vconcat (kbd "<f5>") (kbd keys)))
    (use-local-map nil)
    (+test-projectile--redisplay)))

(ert-deftest projectile/a-preview-joins-no-workspace ()
  "While a prompt is open (SPC b b, SPC SPC, C-x 4 b), what the windows show
may be a preview: not added, in another window either, nor once the prompt
closes without picking it (C-x 4 b's preview joined). Picked, it joins."
  (+test-projectile-real-workspaces
    (let ((theirs (+test-projectile--real "theirs only"))
          (here (+test-projectile--real "here")))
      (switch-to-buffer here)
      (+test-projectile--redisplay)
      (+test-projectile--prompt theirs "<f8> RET")
      (should-not (+test-projectile--in theirs))
      (+test-projectile--prompt theirs "<f8> p i c k RET")
      (should (equal (+test-projectile--in theirs) '("A")))
      (should (equal (+test-projectile--in here) '("A"))))))

(ert-deftest projectile/shown-after-prompts-joins-once-the-command-is-done ()
  "A command prompting twice, then showing a buffer: it joins once the
command is done; one shown with no prompt open joins right away."
  (should (memq #'+my/workspace-prompt-opened-h minibuffer-setup-hook))
  (should (memq #'+my/workspace-prompt-closed-h minibuffer-exit-hook))
  (+test-projectile-real-workspaces
    (let ((after (+test-projectile--real "shown after its prompts"))
          (later (+test-projectile--real "shown later")))
      (+test-projectile--redisplay)
      (use-local-map (let ((map (make-sparse-keymap)))
                       (define-key map (kbd "<f5>")
                                   (lambda ()
                                     (interactive)
                                     (read-from-minibuffer "One? ")
                                     (read-from-minibuffer "Two? ")
                                     (set-window-buffer (split-window-right) after)))
                       map))
      (execute-kbd-macro (kbd "<f5> RET RET"))
      (use-local-map nil)
      (should (equal (+test-projectile--in after) '("A")))
      (should-not +my/workspace--before-prompt)
      (should-not (memq #'+my/workspace-after-prompt-h post-command-hook))
      ;; No prompt open: right away.
      (set-window-buffer nil later)
      (+test-projectile--redisplay)
      (should (equal (+test-projectile--in later) '("A"))))))

(ert-deftest projectile/switching-workspaces-mixes-no-buffers ()
  "A new workspace starts in the windows the last one showed (Doom keeps
them): their buffers stay the other's. Each keeps what's shown in it."
  (+test-projectile-real-workspaces
    (let ((a (+test-projectile--real "a's"))
          (b (+test-projectile--real "b's")))
      (switch-to-buffer a)
      (+test-projectile--redisplay)
      (persp-frame-switch "B")
      (should (eq (window-buffer) a))
      (+test-projectile--redisplay)
      (should (equal (+test-projectile--in a) '("A")))
      (switch-to-buffer b)
      (+test-projectile--redisplay)
      (persp-frame-switch "A")
      (+test-projectile--redisplay)
      (should (equal (+test-projectile--in a) '("A")))
      (should (equal (+test-projectile--in b) '("B"))))))

(ert-deftest projectile/a-buffer-shown-without-workspaces ()
  "Without workspaces, nothing done."
  (+test-with-reset
    (let ((persp-mode nil)
          (buffer (+test-projectile--real "no workspaces")))
      (set-window-buffer nil buffer)
      (+my/workspace-add-shown-buffers-h (selected-frame))
      (should (buffer-live-p buffer))
      (kill-buffer buffer))))

;; ====== WORKSPACES: SPC P P ======
;; Doom's SPC p p (`+workspaces-switch-to-project-h'), real persp-mode.

(ert-deftest projectile/spc-p-p-back-to-an-open-project-keeps-its-panes ()
  "SPC p p to a project open in its workspace (Doom runs the README opener
then too): its panes and the buffer you were on stay, Doom's file prompt
instead of its README over them. A new workspace still opens it."
  (+test-projectile-need-doom-workspaces)
  (+test-projectile-real-workspaces
    (let* ((doom-fallback-buffer-name "*doom*")
           (p (+test-projectile--project "open-b" "b.txt" "README.md"))
           (readme (expand-file-name "README.md" p))
           (asked nil))
      (find-file (+test-file "elsewhere.txt" "x\n"))
      (cl-letf (((symbol-function 'doom-project-find-file) (lambda (dir) (push dir asked))))
        (+workspaces-switch-to-project-h p)
        (should (equal (buffer-file-name (window-buffer)) readme))
        (should-not asked)
        (find-file (expand-file-name "b.txt" p))
        (split-window-right)
        (+workspace-switch "A")
        (+workspaces-switch-to-project-h p))
      (should (equal (safe-persp-name (get-current-persp))
                     (file-name-nondirectory (directory-file-name p))))
      (should (= (length (window-list nil 'nomini)) 2))
      (should (equal (buffer-file-name (window-buffer)) (expand-file-name "b.txt" p)))
      (should (equal asked (list p))))))

(ert-deftest projectile/spc-p-p-into-an-empty-workspace-keeps-the-project ()
  "SPC p p from an empty workspace (Doom takes it over, renamed, without
saying whose it is) into a project without a README, its file prompt left
(C-g): the workspace is the project's, its dashboard there after switching
away and back (it went to ~)."
  (+test-projectile-need-doom-workspaces)
  (+test-projectile-need-dashboard)
  (+test-projectile-real-workspaces
    (let* ((doom-fallback-buffer-name "*doom*")
           (p (+test-projectile--project "taken-over" "src.kt"))
           (name (file-name-nondirectory (directory-file-name p)))
           (persp-before-switch-functions (list #'+dashboard--persp-record-project-h))
           (persp-activated-functions (list #'+dashboard--persp-detect-project-h)))
      (switch-to-buffer (+test-projectile--dashboard))
      (should-not (+workspace-buffer-list))
      (cl-letf (((symbol-function 'doom-project-find-file) (lambda (_) (signal 'quit nil))))
        (condition-case nil
            (+workspaces-switch-to-project-h p)
          (quit nil)))
      (should (equal (safe-persp-name (get-current-persp)) name))
      (should (equal (+my/workspace-project) p))
      (persp-frame-switch "B")
      (persp-frame-switch name)
      (should (equal (+my/workspace-project) p))
      (should (equal (+test-projectile--dashboard-dir) p)))))
