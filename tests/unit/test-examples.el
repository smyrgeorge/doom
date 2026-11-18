;;; tests/unit/test-examples.el -*- lexical-binding: t; -*-
;; config/examples.el and examples/: M-x +my/example picks one, M-x
;; +my/example-NAME runs it (loaded then). The merge example: a temp repo in
;; conflict every way the panes handle, opened; deleted once the merge is
;; closed, whatever it saved. Real git, with a temp HOME and global gitconfig
;; (the user's never read).
;; run.sh: slow (~65 s: every example, run).

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "magit"))))))
  (dolist (package '("magit" "magit-section"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(+test-load "config/childframe" "config/banner" "config/window" "config/tiling" "config/stripe"
            "config/editor" "config/merge" "config/agent-ui" "config/beads" "config/webkit"
            "config/mermaid" "config/agent-shell" "config/agent-workspace" "config/examples")
(require 'mermaid-mode)
(require 'so-long)
(require 'tab-line)

(defconst +test-examples--loaded-at-start (featurep 'example-merge)
  "Whether loading the config loaded an example (it mustn't).")

(defmacro +test-examples (&rest body)
  "BODY from one window, git with a temp HOME and global gitconfig; the
merges it left open closed after."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "examples-home-") t)))
            (process-environment
             (append (list (concat "HOME=" home)
                           (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                           "GIT_CONFIG_NOSYSTEM=1" "GIT_TERMINAL_PROMPT=0")
                     process-environment)))
       (with-temp-file (expand-file-name ".gitconfig" home))
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (error "Asked: %s" prompt))))
         (unwind-protect (progn ,@body)
           (dolist (buffer (buffer-list))
             (when-let* ((session (buffer-local-value '+my/merge--session buffer)))
               (+my/merge--finish session))))))))

(ert-deftest examples/listed-and-each-a-command ()
  (should (member "merge" (+my/examples)))
  (should (equal +my/examples-dir (expand-file-name "examples/" doom-user-dir)))
  ;; M-x +my/example-merge: loads examples/merge.el when first run, not
  ;; before.
  (should-not +test-examples--loaded-at-start)
  (let ((function (symbol-function '+my/example-merge)))
    (should (or (autoloadp function) (featurep 'example-merge)))
    (when (autoloadp function)
      (should (equal (cadr function) (expand-file-name "merge" +my/examples-dir)))
      (should (nth 3 function))))               ; a command
  (should (commandp #'+my/example))
  (should-error (+my/example "no-such-example") :type 'user-error))

(ert-deftest examples/merge-in-conflict-every-way ()
  (+test-examples
    (let* ((session (+my/example "merge"))
           (chunks (append (+my/merge-chunks session) nil)))
      (should (+my/merge-p session))
      (should (string-prefix-p (file-name-as-directory (file-truename temporary-file-directory))
                               (+my/merge-toplevel session)))
      (should (equal (+my/merge-path session) "orders.py"))
      (should (equal (+my/merge-labels session) '("main" . "feature")))
      ;; A conflict over one word, the same change on both, two the wand
      ;; merges, a change of each side alone, lines added, lines removed.
      (should (equal (mapcar #'+my/merge-chunk-kind chunks)
                     '(conflict same conflict conflict yours theirs theirs yours)))
      (should (equal (mapcar (lambda (chunk) (and (+my/merge-chunk-wand chunk) t)) chunks)
                     '(nil nil t t nil nil nil nil)))
      (should (string-empty-p (+my/merge-chunk-base (nth 5 chunks))))      ; added
      (should (string-empty-p (+my/merge--side-text (nth 7 chunks) 'yours))) ; removed
      ;; Open as Magit's e opens it.
      (should (eq (window-buffer (selected-window)) (+my/merge-result session)))
      (should (= (+test-messages "^Merge example: ") 1)))))

(ert-deftest examples/merge-leaves-nothing ()
  "Closed (Abort, Done, a pane closed): its repository deleted, whatever
was saved."
  (+test-examples
    (let* ((session (+my/example-merge))
           (repo (+my/merge-toplevel session)))
      (should (file-directory-p repo))
      (+my/merge-abort)
      (should-not (file-exists-p repo)))
    (let* ((session (+my/example-merge))
           (repo (+my/merge-toplevel session)))
      (+my/merge-accept-right)
      (+my/merge-done)
      (should-not (file-exists-p repo)))
    (let* ((session (+my/example-merge))
           (repo (+my/merge-toplevel session)))
      (+my/merge--finish session)
      (should-not (file-exists-p repo)))
    ;; Nothing left to watch for.
    (should-not (memq #'+my/example-merge--cleanup +my/merge-finished-functions))))

(ert-deftest examples/other-merges-left-alone ()
  "A merge not the example's: its repository isn't touched."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "other-") t)))
         (+my/example-merge--repos (list "/nowhere/")))
    (+my/example-merge--cleanup (+my/merge--make :toplevel dir))
    (should (file-directory-p dir))))

;; ====== IMAGE ======

(ert-deftest examples/image-a-picture-changed-since-head ()
  "The image example's repository: landscape.png committed, then changed (a
PNG of the same size, other bytes), two smaller pictures beside it; in
images/, always that name."
  (require 'example-image (expand-file-name "examples/image" +test-root))
  (let* ((repo (+my/example-image--repo))
         (default-directory repo)
         (png-size (lambda (bytes)
                     ;; IHDR's width and height, after the signature.
                     (cl-flet ((u32 (at) (+ (ash (aref bytes at) 24) (ash (aref bytes (+ at 1)) 16)
                                            (ash (aref bytes (+ at 2)) 8) (aref bytes (+ at 3)))))
                       (should (equal (substring bytes 0 8) (unibyte-string #x89 ?P ?N ?G 13 10 26 10)))
                       (cons (u32 16) (u32 20)))))
         (read (lambda (file)
                 (with-temp-buffer
                   (set-buffer-multibyte nil)
                   (insert-file-contents-literally file)
                   (buffer-string))))
         (head (with-temp-buffer
                 (set-buffer-multibyte nil)
                 (let ((coding-system-for-read 'binary))
                   (call-process "git" nil t nil "show" "HEAD:landscape.png"))
                 (buffer-string))))
    (unwind-protect
        (progn
          (should (equal (file-name-nondirectory (directory-file-name repo)) "images"))
          (should (equal (funcall png-size head) '(480 . 300)))
          (should (equal (funcall png-size (funcall read "landscape.png")) '(480 . 300)))
          (should-not (equal head (funcall read "landscape.png")))
          (should (equal (funcall png-size (funcall read "night.png")) '(240 . 150)))
          (should (equal (funcall png-size (funcall read "dawn.png")) '(240 . 150)))
          ;; Valid PNGs, as an image tool reads them: macOS's sips, else
          ;; ImageMagick's identify (Linux).
          (with-temp-buffer
            (cond ((executable-find "sips")
                   (should (zerop (call-process "sips" nil t nil "-g" "pixelWidth" "landscape.png")))
                   (should (string-match-p "pixelWidth: 480" (buffer-string))))
                  ((executable-find "identify")
                   (should (zerop (call-process "identify" nil t nil "-format" "%w" "landscape.png")))
                   (should (equal (buffer-string) "480"))))))
      (delete-directory (file-name-directory (directory-file-name repo)) t))))

;; ====== EVERY EXAMPLE ======

(ert-deftest examples/each-one-a-command-a-file-and-a-screenshot-to-be ()
  "Each example listed has its file, its command, its line in
config/examples.el's list and docs/examples.md's table; the docs name the
picker (M-x +my/example) too."
  (should (equal (sort (+my/examples) #'string<)
                 '("agent-ui" "agent-workspace" "banner" "excalidraw" "image" "issues" "markdown" "merge" "mermaid"
                   "panel" "pdf" "stripe" "tiling")))
  (let ((listed (with-temp-buffer
                  (insert-file-contents (expand-file-name "config/examples.el" +test-root))
                  (buffer-string)))
        (docs (with-temp-buffer
                (insert-file-contents (expand-file-name "docs/examples.md" +test-root))
                (buffer-string))))
    (should (string-search "`M-x +my/example`" docs))
    (dolist (name (+my/examples))
      (should (fboundp (intern (format "+my/example-%s" name))))
      (should (string-match-p (format "^;;   %s " (regexp-quote name)) listed))
      (should (string-match-p (format "^| `%s` |" (regexp-quote name)) docs)))))

(ert-deftest examples/messages-fit-80-columns ()
  "What each example says in the echo area fits 80 columns (one line in an
80-column frame; they filled 2 or 3 in 100 and 60, the panes squeezed for
a moment): every one of them, its text known from the code."
  (let ((messages (+test-example-messages)))
    (should (>= (length messages) 14))
    (should (equal (sort (delete-dups (mapcar #'car messages)) #'string<)
                   (sort (+my/examples) #'string<)))
    (dolist (message messages)
      (should (equal (list (car message) (cdr message) (and (cdr message) (<= (string-width (cdr message)) 80)))
                     (list (car message) (cdr message) t))))))

(ert-deftest examples/mermaid-a-diagram-to-preview ()
  "The diagram in mermaid-mode; no preview where there's none (batch Emacs:
no GUI), Mermaid's Live Editor said instead; the file gone once closed."
  (+test-with-reset
    (let* ((said nil)
           (buffer (cl-letf (((symbol-function 'message)
                              (lambda (format-string &rest args)
                                (push (apply #'format format-string args) said))))
                     (+my/example-mermaid)))
           (file (buffer-file-name buffer))
           (dir (car (buffer-local-value '+my/example--closing buffer))))
      (with-current-buffer buffer
        (should (eq major-mode 'mermaid-mode))
        (should (string-prefix-p "%% The fruit shop's week" (buffer-string)))
        (should (string-search "flowchart TD" (buffer-string)))
        (should (string-search "subgraph report" (buffer-string)))
        (should-not +my/mermaid-preview-mode))
      (should (eq (window-buffer (selected-window)) buffer))
      (should (seq-some (lambda (line) (string-search "SPC m o opens Mermaid's Live Editor" line))
                        said))
      (kill-buffer buffer)
      (should-not (file-exists-p file))
      (should-not (file-exists-p dir)))))

;; ====== THE HELPERS ======

(ert-deftest examples/folder-deleted-once-its-buffers-are-closed ()
  "The folder goes with the last of the example's buffers; through a change
of mode too; THEN called then."
  (let* ((dir (+my/example-folder "test"))
         (a (find-file-noselect (+my/example-write dir "a.txt" "a\n")))
         (b (find-file-noselect (+my/example-write dir "sub/b.txt" "b\n")))
         (then 0))
    (should (string-match-p "/test-example-" dir))
    (should (equal dir (file-name-as-directory (file-truename dir))))
    (+my/example-delete-when-closed dir (list a b) (lambda () (cl-incf then)))
    (with-current-buffer a (fundamental-mode))     ; a change of mode
    (kill-buffer a)
    (should (file-exists-p dir))
    (should (= then 0))
    (kill-buffer b)
    (should-not (file-exists-p dir))
    (should (= then 1))))

(ert-deftest examples/folder-kept-while-another-of-its-files-is-open ()
  "A buffer replaced by another file of its folder (`find-alternate-file': J
/ K in the image example, which closes it before visiting the other): the
folder kept, the new buffer one of its own; a file opened from the folder
too; deleted with the last of them, THEN called once."
  (+test-with-reset
    (let* ((dir (+my/example-folder "test"))
           (a (+my/example-write dir "a.txt" "a\n"))
           (b (+my/example-write dir "b.txt" "b\n"))
           (c (+my/example-write dir "sub/c.txt" "c\n"))
           (then 0))
      (find-file a)
      (+my/example-delete-when-closed dir (list (current-buffer)) (lambda () (cl-incf then)))
      (find-alternate-file b)
      (should (equal buffer-file-name b))
      (should (equal (buffer-string) "b\n"))
      (+test-sleep 0.1)
      (should (file-exists-p b))
      (should (equal (car +my/example--closing) dir))
      (let ((other (find-file-noselect c)))
        (kill-buffer (get-file-buffer b))
        (should (file-exists-p c))
        (should (= then 0))
        (kill-buffer other))
      (should-not (file-exists-p dir))
      (should (= then 1))
      (should-not (assoc dir +my/example--folders)))))

(ert-deftest examples/folder-of-no-buffers-deleted-at-once ()
  "Given no buffer (none live): nothing to wait for, deleted now."
  (let ((dir (+my/example-folder "test")))
    (+my/example-delete-when-closed dir nil)
    (should-not (file-exists-p dir))
    (should-not (assoc dir +my/example--folders))))

;; ====== RUN FROM ANYWHERE, NOTHING LEFT ======

(ert-deftest examples/run-from-a-side-window ()
  "From a side window (a file tree, a popup): each example opens in the
frame's other window, the side window kept (the merge's panes take the
frame as Magit's e does)."
  (+test-examples
    (dolist (run (append (list #'+my/example-banner #'+my/example-mermaid #'+my/example-tiling
                               #'+my/example-agent-ui #'+my/example-panel #'+my/example-merge)
                         (and (executable-find "bd") (list #'+my/example-issues))))
      (+test-reset)
      (let* ((side (display-buffer-in-side-window (get-buffer-create "*side*") '((side . left))))
             (made (progn (select-window side)
                          (funcall run))))
        (should-not (window-parameter (selected-window) 'window-side))
        (if (+my/merge-p made)
            (+my/merge--finish made)
          (should (window-live-p side))
          (should (eq (window-buffer side) (get-buffer "*side*")))
          (should (= (length (window-list nil 'nomini))
                     (1+ (length (seq-filter #'get-buffer-window (ensure-list made))))))
          (mapc #'kill-buffer (ensure-list made)))))))

(ert-deftest examples/failing-partway-leaves-no-folder ()
  "An example failing partway (bd, git, a notice): no NAME-example-* folder
left; one with a file left open, once that's closed."
  (+test-examples
    (let ((temporary-file-directory (file-name-as-directory (make-temp-file (+test-tmp-file "examples-tmp-") t)))
          (executable-find (symbol-function 'executable-find)))
      (cl-flet ((left () (directory-files temporary-file-directory nil "-example-")))
        (require 'example-issues (expand-file-name "issues" +my/examples-dir))
        (require 'example-image (expand-file-name "image" +my/examples-dir))
        (require 'example-banner (expand-file-name "banner" +my/examples-dir))
        ;; bd failing.
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (name &rest args) (if (equal name "bd") "/usr/bin/bd" (apply executable-find name args))))
                  ((symbol-function '+my/example-issues--bd) (lambda (&rest _) (error "bd init: failed"))))
          (should-error (+my/example-issues))
          (should-not (left)))
        ;; git failing.
        (cl-letf (((symbol-function '+my/example-image--git) (lambda (&rest _) 1)))
          (should-error (+my/example-image))
          (should-not (left)))
        ;; Its file open, then a notice failing: the folder goes with the file.
        (cl-letf (((symbol-function '+my/banner-show) (lambda (&rest _) (error "No notices"))))
          (should-error (+my/example-banner))
          (should (equal (length (left)) 1))
          (kill-buffer "catalog.min.json")
          (should-not (left)))))))

;; ====== TILING ======

(ert-deftest examples/tiling-a-project-tall ()
  "A project's four files, tall: the first on the left, the others stacked
on the right, the first selected; gone once closed."
  (+test-examples
    (let* ((buffers (+my/example-tiling))
           (windows (window-list nil 'nomini))
           (dir (car (buffer-local-value '+my/example--closing (car buffers)))))
      (should (equal (mapcar #'buffer-name buffers) '("app.py" "cart.py" "prices.py" "test_cart.py")))
      (should (equal (mapcar (lambda (window) (buffer-name (window-buffer window))) windows)
                     '("app.py" "cart.py" "prices.py" "test_cart.py")))
      (should (eq (selected-window) (car windows)))
      ;; Tall: the main pane the full height on the left, the others one
      ;; above the other on the right, as wide.
      (let ((main (car windows)) (stack (cdr windows)))
        (should (= (window-left-column main) 0))
        (should (= (window-total-height main) (window-total-height (frame-root-window))))
        (should (cl-every (lambda (window) (> (window-left-column window) 0)) stack))
        (should (= (length (seq-uniq (mapcar #'window-left-column stack))) 1))
        (should (equal (mapcar #'window-top-line stack)
                       (sort (mapcar #'window-top-line stack) #'<))))
      ;; Each pane its file's tab only (not the one it opened on).
      (dolist (window windows)
        (with-selected-window window
          (should (equal (+my/tabs-window-buffers) (list (window-buffer window))))))
      (should (string-prefix-p (file-name-as-directory (file-truename temporary-file-directory)) dir))
      (mapc #'kill-buffer buffers)
      (should-not (file-exists-p dir)))))

;; ====== NOTICES ======

(ert-deftest examples/banner-a-notice-of-each-kind ()
  "A file of very long lines: shown plain, the config's notice (a warning)
with its actions; an info and an error notice; gone once closed."
  (+test-examples
    (let* ((buffer (+my/example-banner))
           (dir (car (buffer-local-value '+my/example--closing buffer))))
      (with-current-buffer buffer
        (should (derived-mode-p 'so-long-mode))
        (should (> (cadr (buffer-line-statistics)) 10000))
        (should (equal (mapcar (lambda (notice) (list (car notice) (nth 3 notice))) +my/banner--list)
                       '((long-lines warning) (example-info info) (example-error error))))
        ;; Its actions: another notice; close them all.
        (funcall (cdr (assoc "Another one" (nth 2 (assq 'example-info +my/banner--list)))))
        (should (= (length +my/banner--list) 4))
        (funcall (cdr (assoc "Close them all" (nth 2 (assq 'example-error +my/banner--list)))))
        (should-not +my/banner--list))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

;; ====== ISSUES ======

(ert-deftest examples/issues-a-project-s-list ()
  "A project tracked with bd (the real one; skipped without it): its list,
the epics' issues under them, tags, a blocked one, the closed ones hidden
and said; its folder gone once the list is closed."
  (unless (executable-find "bd")
    (ert-skip "No bd (scripts/tools.sh installs it)"))
  (+test-examples
    (let* ((buffer (+my/example-issues))
           (dir (car (buffer-local-value '+my/example--closing buffer))))
      (should (string-prefix-p (file-name-as-directory (file-truename temporary-file-directory)) dir))
      (with-current-buffer buffer
        (should (derived-mode-p 'beads-list-mode))
        (should (eq (window-buffer) buffer))
        (should (one-window-p))
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (should (= (length (split-string text "\n" t)) 12))
          (should (string-match-p "Parser rewrite 1/4 +parser" text))
          (should (string-match-p "└ Parser: recover from syntax errors" text))
          (should (string-match-p "⊘1 .*Release 2.0" text))
          (should (string-match-p "Crash on an empty file +crash +parser" text)))
        (should (equal (mapcar (lambda (notice) (nth 1 notice)) +my/banner--list)
                       '("3 closed issues hidden."))))
      (kill-buffer buffer)
      (should-not (file-exists-p dir)))))

;; ====== THE ERROR STRIPE ======

(ert-deftest examples/stripe-errors-warnings-and-changes ()
  "inventory.el in a repository, changed since its commit: flycheck finds
warnings through the file and an error at its end (the byte compiler: the
file trusted while it's open), diff-hl the changes; TODO comments; the strip
on; the repository and the trust gone once closed."
  (+test-examples
    (let* ((trusted trusted-content)
           (buffer (+my/example-stripe))
           (folder (car (buffer-local-value '+my/example--closing buffer)))
           (repo (expand-file-name "stripe-example/" folder)))
      ;; Always that name (the mode line shows it), in a new temp folder.
      (should (equal (buffer-local-value 'default-directory buffer) repo))
      (should (member repo trusted-content))
      (should (+test-wait-for #'+my/example-stripe-ready 60))
      (with-current-buffer buffer
        (should (bound-and-true-p +my/stripe-mode))
        (should (equal (mapcar (lambda (error) (list (flycheck-error-line error) (flycheck-error-level error)))
                               (seq-sort-by #'flycheck-error-line #'< flycheck-current-errors))
                       '((31 warning) (178 warning) (183 warning) (250 warning) (279 error))))
        ;; A TODO, a HACK and a FIXME comment.
        (should (equal (mapcar (lambda (line)
                                 (save-excursion
                                   (goto-char (point-min))
                                   (forward-line (1- line))
                                   (and (looking-at ";; \\([A-Z]+\\):") (match-string 1))))
                               (+my/stripe--todo-lines))
                       '("TODO" "HACK" "FIXME")))
        ;; Changed, removed and added lines.
        (let ((kinds (seq-uniq (mapcar (lambda (ov) (overlay-get ov 'diff-hl-hunk-type))
                                       (seq-filter (lambda (ov) (overlay-get ov 'diff-hl-hunk))
                                                   (overlays-in (point-min) (point-max)))))))
          (should (seq-set-equal-p kinds '(change delete insert)))))
      (kill-buffer buffer)
      (should-not (file-exists-p folder))
      (should (equal trusted-content trusted)))))

;; ====== THE DRAWING ======

(ert-deftest examples/excalidraw-drawing-each-element-its-own ()
  "The drawing's JSON: elements not deleted, each with its own colours (not
the last one's: the template's cells were shared), labels in their boxes."
  (require 'example-excalidraw (expand-file-name "excalidraw" +my/examples-dir))
  (let* ((drawing (json-parse-string (+my/example-excalidraw--drawing)
                                     :object-type 'alist :false-object nil :null-object nil))
         (elements (append (alist-get 'elements drawing) nil))
         (get (lambda (id key) (alist-get key (seq-find (lambda (e) (equal (alist-get 'id e) id)) elements)))))
    (should (> (length elements) 10))
    (should-not (seq-some (lambda (e) (alist-get 'isDeleted e)) elements))
    (should (equal (funcall get "title" 'strokeColor) "#1e1e1e"))
    (should (equal (funcall get "save" 'strokeColor) "#e03131"))
    (should (equal (funcall get "file" 'backgroundColor) "#a5d8ff"))
    (should (equal (funcall get "webkit" 'backgroundColor) "#b2f2bb"))
    (should (equal (funcall get "file" 'fillStyle) "hachure"))
    (should (equal (funcall get "you" 'fillStyle) "solid"))
    (should (equal (funcall get "file-label" 'containerId) "file"))
    (should (equal (funcall get "note" 'strokeColor) "#1e1e1e"))))

;; ====== AGENT UI ======

(ert-deftest examples/agent-ui-a-canvas-filled-in ()
  "The conversation on the left, the canvas beside it, played out: the
release's steps, the tests (one failed), the build done, the chart; gone
once both are closed."
  (+test-examples
    (pcase-let* ((`(,conversation ,canvas) (+my/example-agent-ui))
                 (dir (car (buffer-local-value '+my/example--closing conversation))))
      (should (equal (buffer-name conversation) "release.md"))
      (should (equal (buffer-name canvas) "Agent UI: example"))
      ;; Beside it, at once, the conversation keeping the focus.
      (should (get-buffer-window canvas))
      (should (eq (window-buffer (selected-window)) conversation))
      (should (+test-wait-for #'+my/example-agent-ui-ready 20))
      (with-current-buffer canvas
        (agent-ui--flush)
        (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas canvas))
                       '("plan" "tests" "build" "times")))
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          ;; Each step its time: the build's given, the tests' timed.
          (should (string-match-p "✗ Run the tests +[0-9]+s +4 passed" text))
          (should (string-match-p "✓ Build +29s" text))
          (should (string-match-p "– Publish +a test failed" text))
          (should (string-match-p " checker │ failed │ 0.7s" text))
          (should (string-match-p "12/12  100%  ✓ built" text))
          (should (string-match-p "● this machine  ● CI" text))
          (should-not (string-match-p "⚠" text))))
      (kill-buffer canvas)
      (should (file-exists-p dir))
      (kill-buffer conversation)
      (should-not (file-exists-p dir)))))

(ert-deftest examples/panel-the-cpu-filled ()
  "This config's cpu panel, in a project of its own, alone in the frame,
filled by its code (not asked: this config's own); its folder gone once
it's closed."
  (+test-examples
    (let* ((canvas (+my/example-panel))
           (dir (car (buffer-local-value '+my/example--closing canvas))))
      (should (equal (buffer-name canvas) "Agent UI: cpu (service)"))
      (should (eq (window-buffer (selected-window)) canvas))
      (should (= (length (window-list)) 1))
      (should (+test-wait-for (lambda () (plist-get (agent-ui-get "processes" :canvas canvas) :rows)) 10))
      (should (numberp (plist-get (agent-ui-get "cpu" :canvas canvas) :value)))
      (should-not (agent-ui-panels--error (buffer-local-value 'agent-ui-panels--state canvas)))
      (kill-buffer canvas)
      (should-not (file-exists-p dir)))))

(ert-deftest examples/agent-ui-stops-when-closed ()
  (+test-examples
    (pcase-let ((`(,conversation ,canvas) (+my/example-agent-ui)))
      (should (timerp +my/example-agent-ui--timer))
      (kill-buffer canvas)
      (should-not +my/example-agent-ui--timer)
      (kill-buffer conversation))))

(ert-deftest examples/agent-workspace-a-crew-offline ()
  "Three stand-in agents in their crew's app, each in its worktree, the
builders on their issue's branch (TYPE/ID-words), the investigator (it can't
edit) on agent/sam: ada working on demo-1, sam's hand raised, ken done; its issues each with its type, two under their epic's heading (with
bd); Q closes it, every agent exiting, and the folder goes; your windows as
they were (doom-51z.16)."
  (+test-examples
    (set-frame-size (selected-frame) 220 40)
    (delete-other-windows)
    (switch-to-buffer (get-buffer-create "*yours*"))
    (set-window-buffer (split-window-right) (get-buffer-create "*yours, right*"))
    (let* ((app (+my/example-agent-workspace))
           (project (agent-workspace--app-project app)))
      (should (equal (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)) '("ada" "sam" "ken")))
      (should (+test-wait-for #'+my/example-agent-workspace-ready 30))
      (dolist (agent (agent-workspace-agents project))
        (should (file-directory-p (agent-workspace-agent-worktree agent))))
      (should (equal (agent-workspace-agent-issue (car (agent-workspace-agents project))) "demo-1"))
      (should (equal (mapcar #'agent-workspace-agent-branch (agent-workspace-agents project))
                     '("feat/demo-1-strings-escapes" "agent/sam" "feat/demo-6-tokens-numbers")))
      ;; Its issues: the builders' ready ones under their epic's heading.
      (when (executable-find "bd")
        (should (+test-wait-for
                 (lambda ()
                   (string-match-p "e demo-7 Error recovery +2 *\n +b demo-2 Parser: recover"
                                   (with-current-buffer (agent-workspace--issues-buffer project)
                                     (buffer-substring-no-properties (point-min) (point-max)))))
                 30)))
      ;; Its minimap: ada reading and editing the lexer, sam asking.
      (should (+test-wait-for (lambda () (equal (plist-get (agent-workspace-activity (car (agent-workspace-agents project)))
                                                           :location)
                                                '("src/lexer.el" . 12)))
                              10))
      ;; In the minute sam asked, which may not be the last one by now: the
      ;; waits above (bd, ada's edit) can take it past a minute's end.
      (should (seq-some (lambda (kinds) (memq 'asked kinds))
                        (agent-workspace-activity-lane (cadr (agent-workspace-agents project)))))
      (should (string-search "wants to run npm install"
                             (with-current-buffer (agent-workspace--room-buffer project) (buffer-string))))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-quit))
      (should-not (agent-workspace-agents project))
      (should (equal (mapcar (lambda (window) (buffer-name (window-buffer window))) (window-list nil 'nomini))
                     '("*yours*" "*yours, right*")))
      (should (+test-wait-for (lambda () (not (file-exists-p project))) 10)))))
