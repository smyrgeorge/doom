;;; tests/unit/test-agent-shell.el -*- lexical-binding: t; -*-
;; config/agent-shell.el: Claude Code in Emacs (agent-shell): the CLI login,
;; Claude Code as the default agent, SPC o c / SPC o C (here), what Claude is
;; told about Emacs (appended to its system prompt), image width.
;; No agent ever starts: agent-shell's starting points are mocked, and any
;; process started fails the test.

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

;; Doom's yasnippet setup, before the config's as in Doom (its modules load
;; first): yasnippet on in every buffer as it loads (:editor snippets), its
;; completion added as it turns on or off (:completion corfu).
(with-eval-after-load 'yasnippet
  (yas-global-mode +1))
(defun +test-agent-shell--add-yasnippet-capf-h ()
  "Doom's `+corfu-add-yasnippet-capf-h'."
  (add-hook 'completion-at-point-functions #'yasnippet-capf 30 t))
(add-hook 'yas-minor-mode-hook #'+test-agent-shell--add-yasnippet-capf-h)

(+test-load "config/agent-shell")

;; As config.el left things, before anything loaded agent-shell.
(defconst +test-agent-shell--at-startup
  (list :loaded (featurep 'agent-shell)
        :agent-shell (symbol-function 'agent-shell)
        :start-claude (symbol-function 'agent-shell-anthropic-start-claude-code)
        :preferred-bound (boundp 'agent-shell-preferred-agent-config))
  "What config/agent-shell.el left before agent-shell loaded.")

(require 'agent-shell)

;; What Claude is told of a project's issues (config/agent-shell/beads.el):
;; its own tests (test-agent-shell-beads.el), in projects of their own. Not
;; here: these run in this config's folder, which may track its issues.
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

;; ====== HELPERS ======

(defconst +test-agent-shell--dark
  '((background-mode . dark) (bg . "#282c34") (fg . "#bbc2cf"))
  "doom-one's colours.")

(defconst +test-agent-shell--light
  '((background-mode . light) (bg . "#fafafa") (fg . "#383a42"))
  "doom-one-light's colours.")

(defmacro +test-agent-shell--with-colours (colours themes &rest body)
  "BODY with the frame's background mode and the default face's colours as in
COLOURS (an alist: background-mode, bg, fg) and THEMES enabled."
  (declare (indent 2))
  `(let* ((colours ,colours)
          (custom-enabled-themes ,themes)
          (frame-parameter-fn (symbol-function 'frame-parameter))
          (face-background-fn (symbol-function 'face-background))
          (face-foreground-fn (symbol-function 'face-foreground)))
     (cl-letf (((symbol-function 'frame-parameter)
                (lambda (frame parameter)
                  (if (eq parameter 'background-mode)
                      (alist-get 'background-mode colours)
                    (funcall frame-parameter-fn frame parameter))))
               ((symbol-function 'face-background)
                (lambda (face &rest args)
                  (if (eq face 'default)
                      (alist-get 'bg colours)
                    (apply face-background-fn face args))))
               ((symbol-function 'face-foreground)
                (lambda (face &rest args)
                  (if (eq face 'default)
                      (alist-get 'fg colours)
                    (apply face-foreground-fn face args)))))
       ,@body)))

(defun +test-agent-shell--no-process (&rest args)
  (error "A test tried to start a process: %S" args))

(defmacro +test-agent-shell--mocked (&rest body)
  "BODY with agent-shell's starting points mocked, from a buffer in a project
folder in the temp folder. `calls' collects (FUNCTION . ARGS) in order;
`existing' is the project's shell buffers (none: bind it in BODY);
`started' the buffer a start returns. Starting a process fails."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((calls nil)
            (existing nil)
            (dir (file-name-as-directory (+test-tmp-file "agent-shell-project/")))
            (started (+test-buffer "Claude Agent @ new"))
            (agent-shell-prefer-viewport-interaction nil)
            (agent-shell-session-strategy 'prompt)
            (agent-shell-cwd-function nil)
            (default-directory dir)
            (processes (process-list))
            ;; Mocking primitives below compiles no trampoline (that would
            ;; start an Emacs).
            (native-comp-enable-subr-trampolines nil))
       (ignore existing)
       (cl-letf (((symbol-function 'make-process) #'+test-agent-shell--no-process)
                 ((symbol-function 'start-process) #'+test-agent-shell--no-process)
                 ((symbol-function 'make-pipe-process) #'+test-agent-shell--no-process)
                 ((symbol-function 'make-network-process) #'+test-agent-shell--no-process)
                 ((symbol-function 'call-process) #'+test-agent-shell--no-process)
                 ((symbol-function 'agent-shell-cwd) (lambda () dir))
                 ((symbol-function 'agent-shell-project-buffers)
                  (lambda (&rest _) existing))
                 ((symbol-function 'agent-shell--start)
                  (lambda (&rest args) (push (cons 'start args) calls) started))
                 ((symbol-function 'agent-shell-select-config)
                  (lambda (&rest args) (push (cons 'picker args) calls)
                    (error "Asked which agent to use")))
                 ((symbol-function 'agent-shell--read-shell-buffer)
                  (lambda (&rest args) (push (cons 'read-shell args) calls)
                    (car existing)))
                 ((symbol-function 'agent-shell--context) (lambda (&rest _) nil))
                 ((symbol-function 'agent-shell--display-and-insert-context)
                  (lambda (buffer text) (push (list 'display buffer text) calls)))
                 ((symbol-function 'agent-shell--display-buffer)
                  (lambda (buffer) (push (list 'display buffer nil) calls)))
                 ((symbol-function 'agent-shell-toggle)
                  (lambda () (push (list 'toggle) calls))))
         (with-current-buffer (+test-buffer "code.el" "(foo)\n" #'emacs-lisp-mode)
           (setq default-directory dir)
           ,@body))
       (should (equal (process-list) processes)))))

(defun +test-agent-shell--press (key &optional prefix)
  "Run KEY (after SPC) as pressed, with PREFIX as \\[universal-argument]'s."
  (let ((current-prefix-arg prefix)
        (this-command (lookup-key doom-leader-map (kbd key))))
    (call-interactively this-command)))

(defun +test-agent-shell--calls (calls name)
  "CALLS (newest first) to NAME, oldest first."
  (reverse (seq-filter (lambda (call) (eq (car call) name)) calls)))

(defun +test-agent-shell--system-prompt (config)
  "The text CONFIG appends to Claude Code's system prompt."
  (map-nested-elt config '(:session-meta systemPrompt append)))

;; ====== KEYS ======

(ert-deftest agent-shell/keys ()
  (should (eq (lookup-key doom-leader-map (kbd "o c"))
              #'agent-shell-anthropic-start-claude-code))
  (should (eq (lookup-key doom-leader-map (kbd "o C")) #'+my/agent-shell-claude-here)))

(ert-deftest agent-shell/keys-described-for-which-key ()
  (let ((o (lookup-key doom-leader-map (kbd "o"))))
    (should (equal (alist-get ?c (cdr o))
                   '("Claude Code (agent-shell)" . agent-shell-anthropic-start-claude-code)))
    (should (equal (alist-get ?C (cdr o)) '("Claude Code, here" . +my/agent-shell-claude-here)))))

(ert-deftest agent-shell/keys-are-commands ()
  (should (commandp (lookup-key doom-leader-map (kbd "o c"))))
  (should (commandp (lookup-key doom-leader-map (kbd "o C")))))

;; ====== LOADING ======

(ert-deftest agent-shell/not-loaded-at-startup ()
  "The config doesn't load agent-shell: its commands are autoloads until used."
  (should-not (plist-get +test-agent-shell--at-startup :loaded))
  (dolist (key '(:agent-shell :start-claude))
    (let ((fn (plist-get +test-agent-shell--at-startup key)))
      (should (autoloadp fn))
      (should (equal (nth 1 fn) "agent-shell"))
      (should (nth 3 fn)))))                ; interactive

(ert-deftest agent-shell/settings-wait-for-the-package ()
  "Its settings are in `:config': nothing set before agent-shell loads (its
defcustoms would otherwise keep a value set too early, or be overridden)."
  (should-not (plist-get +test-agent-shell--at-startup :preferred-bound)))

;; ====== SETTINGS ======

(ert-deftest agent-shell/claude-cli-login ()
  "Uses the Claude CLI login (no API key, no OAuth token)."
  (should (equal agent-shell-anthropic-authentication '((:login . t))))
  (should (equal agent-shell-anthropic-authentication
                 (agent-shell-anthropic-make-authentication :login t))))

(ert-deftest agent-shell/login-means-no-api-key-for-claude ()
  "With the login, Claude's process gets an empty ANTHROPIC_API_KEY (the CLI's
login is used), and no OAuth token."
  (let (made)
    (cl-letf (((symbol-function 'agent-shell--make-acp-client)
               (lambda (&rest args) (setq made args) 'client)))
      (with-temp-buffer
        (agent-shell-anthropic-make-claude-client :buffer (current-buffer))))
    (let ((env (plist-get made :environment-variables)))
      (should (member "ANTHROPIC_API_KEY=" env))
      (should-not (seq-some (lambda (var) (string-prefix-p "CLAUDE_CODE_OAUTH_TOKEN" var)) env)))
    (should (equal (plist-get made :command) (car agent-shell-anthropic-claude-acp-command)))))

(ert-deftest agent-shell/claude-code-is-the-default-agent ()
  (should (eq agent-shell-preferred-agent-config 'claude-code))
  (cl-letf (((symbol-function 'agent-shell-select-config)
             (lambda (&rest _) (error "Asked which agent to use"))))
    (let ((config (agent-shell--auto-preferred-config)))
      (should config)
      (should (eq (map-elt config :identifier) 'claude-code))
      ;; Built by the Claude Code maker: what Claude is told comes with it.
      (should (equal (+test-agent-shell--system-prompt config)
                     (string-join (delq nil (list +my/agent-shell-claude-context
                                                  (+my/agent-shell-claude-theme)))
                                  "\n\n"))))))

(ert-deftest agent-shell/sessions-display-as-agent-shell-has-them ()
  "Where a session opens is agent-shell's (its window); tiling, when on,
puts it in a new pane (config/tiling/apps.el)."
  (should (equal agent-shell-display-action '(display-buffer-same-window))))

(ert-deftest agent-shell/images-as-wide-as-the-window ()
  (should (equal agent-shell-markdown-image-max-width 1.0))
  (should (floatp agent-shell-markdown-image-max-width)))

;; ====== WHAT CLAUDE IS TOLD ======

(ert-deftest agent-shell/context-says-where-it-runs ()
  (let ((text +my/agent-shell-claude-context))
    (should (stringp text))
    (should (string-prefix-p "You are running inside Emacs, in an agent-shell buffer" text))
    (should (string-match-p "claude-agent-acp" text))
    (should (string-match-p "not in a terminal" text))))

(ert-deftest agent-shell/context-sections ()
  "Each paragraph is one of the documented sections, in order."
  (let ((paragraphs (split-string +my/agent-shell-claude-context "\n\n")))
    (should (= (length paragraphs) 6))
    (should (equal (mapcar (lambda (p) (car (split-string p ":")))
                           (cdr paragraphs))
                   '("Formatting" "File references" "Images" "Reports" "The editor")))))

(ert-deftest agent-shell/context-formatting ()
  (let ((text +my/agent-shell-claude-context))
    (dolist (thing '("Markdown" "tables" "fenced code blocks" "always name it"))
      (should (string-match-p (regexp-quote thing) text)))
    ;; What doesn't render (Mermaid does: config/agent-shell/mermaid.el).
    (should (string-match-p "HTML and LaTeX math show as plain text: don't use them" text))
    (should-not (string-match-p "Mermaid" text))))

(ert-deftest agent-shell/context-file-references ()
  (let ((text +my/agent-shell-claude-context))
    (dolist (form '("path:line" "path:line-line" "path:line:col"))
      (should (string-match-p (regexp-quote form) text)))
    (should (string-match-p "links that open the file at that line" text))))

(ert-deftest agent-shell/context-images ()
  (let ((text +my/agent-shell-claude-context))
    (should (string-match-p (regexp-quote "![chart](/abs/path/chart.png)") text))
    (should (string-match-p (regexp-quote "{width=50%}") text))
    (should (string-match-p "PNG, JPEG, WebP and SVG" text))
    (should (string-match-p "remote URLs aren't fetched" text))
    (should (string-match-p (regexp-quote ".agent-shell/images/") text))
    (should (string-match-p "kept out of git" text))))

(ert-deftest agent-shell/context-reports ()
  (let ((text +my/agent-shell-claude-context))
    (should (string-match-p "report itself as Markdown in your reply, not as an HTML page or one big image"
                            text))
    (should (string-match-p "each diagram, chart or graph its own image, linked where it belongs" text))
    (should (string-match-p "diagram code too, unless it's drawn in replies" text))))

(ert-deftest agent-shell/context-the-editor ()
  (let ((text +my/agent-shell-claude-context))
    (should (string-match-p "emacsclient --eval" text))
    (should (string-match-p (regexp-quote "~/.config/doom") text))
    (should (string-match-p "keep each eval quick and bounded" text))
    (should (string-match-p "never call anything that waits for input" text))
    (should (string-match-p "only when asked" text))
    (should (string-match-p "check that its buffer isn't modified" text))))

(ert-deftest agent-shell/context-text-is-clean ()
  "The source's line continuations leave single spaces, no stray backslashes
or indentation."
  (let ((text +my/agent-shell-claude-context))
    (should-not (string-match-p "  " text))
    (should-not (string-match-p "\\\\" text))
    (should-not (string-match-p "\n " text))
    (should-not (string-match-p "[ \t]\n" text))
    (should-not (string-match-p "\n\n\n" text))
    (should (string-suffix-p "isn't modified." text))))

;; ====== THE THEME'S COLOURS ======

(ert-deftest agent-shell/theme-dark ()
  (+test-agent-shell--with-colours +test-agent-shell--dark '(doom-one)
    (should (equal (+my/agent-shell-claude-theme)
                   "Emacs uses a dark theme (doom-one): background #282c34, text #bbc2cf. \
Draw images to read well on it: a dark or transparent background, light text and lines."))))

(ert-deftest agent-shell/theme-light ()
  (+test-agent-shell--with-colours +test-agent-shell--light '(doom-one-light)
    (should (equal (+my/agent-shell-claude-theme)
                   "Emacs uses a light theme (doom-one-light): background #fafafa, text #383a42. \
Draw images to read well on it: a light or transparent background, dark text and lines."))))

(ert-deftest agent-shell/theme-without-a-theme-name ()
  (+test-agent-shell--with-colours +test-agent-shell--dark nil
    (should (string-prefix-p "Emacs uses a dark theme: background #282c34,"
                             (+my/agent-shell-claude-theme)))))

(ert-deftest agent-shell/theme-the-first-enabled-one ()
  "Several themes enabled: the latest (first in the list) is named."
  (+test-agent-shell--with-colours +test-agent-shell--dark '(doom-one user)
    (should (string-match-p "dark theme (doom-one):" (+my/agent-shell-claude-theme)))))

(ert-deftest agent-shell/theme-unknown-mode-is-light ()
  "Only a dark background mode says dark."
  (+test-agent-shell--with-colours '((background-mode . nil) (bg . "#ffffff") (fg . "#000000")) nil
    (should (string-match-p "a light theme" (+my/agent-shell-claude-theme)))))

(ert-deftest agent-shell/theme-unknown-colours-say-nothing ()
  "No line when the colours aren't known as #RRGGBB (a terminal, batch...)."
  (dolist (colours '(((background-mode . dark) (bg . "unspecified-bg") (fg . "#bbc2cf"))
                     ((background-mode . dark) (bg . "#282c34") (fg . "unspecified-fg"))
                     ((background-mode . dark) (bg . "black") (fg . "white"))
                     ((background-mode . dark) (bg . nil) (fg . "#bbc2cf"))
                     ((background-mode . dark) (bg . "#282c34") (fg . nil))))
    (+test-agent-shell--with-colours colours '(doom-one)
      (should-not (+my/agent-shell-claude-theme)))))

;; ====== THE SYSTEM PROMPT ======

;; ====== THE PROMPT ======

(defun +test-agent-shell--snippets-buffer (mode)
  "A new buffer in MODE (agent-shell-mode only named), as yasnippet's global
mode turns it on in a buffer whose major mode starts. Its own name:
yasnippet skips temporary buffers."
  (with-current-buffer (generate-new-buffer "yas-test")
    (if (eq mode 'agent-shell-mode)
        (setq-local major-mode 'agent-shell-mode)
      (funcall mode))
    (when (featurep 'yasnippet)
      (yas-minor-mode-on))
    (current-buffer)))

(defun +test-agent-shell--snippets (buffer)
  "In BUFFER: yasnippet on, and its completion there, as (YAS CAPF)."
  (with-current-buffer buffer
    (list (and (bound-and-true-p yas-minor-mode) t)
          (and (memq #'yasnippet-capf completion-at-point-functions) t))))

(ert-deftest agent-shell/no-snippets-in-the-prompt ()
  "yasnippet stays off in Claude Code's buffers, its completion out (Doom's
`yasnippet-capf' stalled typing in long sessions), in a session opened before
yasnippet loads too; elsewhere as ever."
  ;; Nothing here loaded it yet: the sessions opened at startup.
  (should-not (featurep 'yasnippet))
  (let* ((claude-before (+test-agent-shell--snippets-buffer 'agent-shell-mode))
         (text-before (+test-agent-shell--snippets-buffer 'text-mode))
         (_ (require 'yasnippet))
         (claude-after (+test-agent-shell--snippets-buffer 'agent-shell-mode))
         (text-after (+test-agent-shell--snippets-buffer 'text-mode))
         (buffers (list claude-before text-before claude-after text-after)))
    (unwind-protect
        (progn
          (should yas-global-mode)
          (should (memq #'+my/agent-shell-no-snippets-p yas-dont-activate-functions))
          ;; yasnippet's own still there.
          (should (memq #'minibufferp yas-dont-activate-functions))
          (should (equal (+test-agent-shell--snippets claude-before) '(nil nil)))
          (should (equal (+test-agent-shell--snippets claude-after) '(nil nil)))
          (should (equal (+test-agent-shell--snippets text-before) '(t t)))
          (should (equal (+test-agent-shell--snippets text-after) '(t t)))
          ;; yasnippet turned off again in a session, by hand: its completion
          ;; doesn't come back with it.
          (with-current-buffer claude-after
            (yas-minor-mode -1))
          (should (equal (+test-agent-shell--snippets claude-after) '(nil nil))))
      (mapc #'kill-buffer buffers))))

;; ====== CONTEXT FROM THE CURRENT BUFFER ======

(ert-deftest agent-shell/context-from-a-buffer-with-dated-lines ()
  "SPC o c from a buffer whose lines start with a date (Beads' issue list):
no error (dired took the line for a file's), no files."
  (with-temp-buffer
    (insert "    t-1 2026-11-08 open  P0 task  An issue\n")
    (goto-char (point-min))
    (forward-char 6)
    (should-not (agent-shell--buffer-files))
    (should-not (agent-shell--buffer-files :obvious t))
    (let ((agent-shell-context-sources '(files)))
      (should-not (agent-shell--context)))))

(ert-deftest agent-shell/a-new-session-s-prompt-starts-empty ()
  "SPC o c and SPC o C from a file, nothing selected: nothing carried into
the new prompt (agent-shell's default sources took the line you were on); a
selection still is. With config.el's sources (test-config.el checks them)."
  (let ((context (symbol-function 'agent-shell--context))
        (agent-shell-context-sources '(files region))
        (transient-mark-mode t))
    (dolist (key '("o c" "o C"))
      (+test-agent-shell--mocked
        (cl-letf (((symbol-function 'agent-shell--context) context))
          (setq buffer-file-name (expand-file-name "code.el" dir))
          (goto-char (point-min))
          (+test-agent-shell--press key)
          (should (equal (+test-agent-shell--calls calls 'display)
                         (list (list 'display started nil))))
          ;; A selection.
          (setq calls nil)
          (set-mark (point))
          (end-of-line)
          (activate-mark)
          (+test-agent-shell--press key)
          (let ((text (nth 2 (car (+test-agent-shell--calls calls 'display)))))
            (should (stringp text))
            (should (string-match-p "(foo)" text))))))))

(ert-deftest agent-shell/context-dired-s-files-in-dired ()
  "In dired: its file at point, as agent-shell has it."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "ctx-") t)))
         (file (expand-file-name "x.txt" dir)))
    (with-temp-file file (insert "x\n"))
    (let ((buffer (dired-noselect dir)))
      (unwind-protect
          (with-current-buffer buffer
            (goto-char (point-min))
            (should (search-forward "x.txt" nil t))
            (should (equal (agent-shell--buffer-files) (list file))))
        (kill-buffer buffer)))))

(ert-deftest agent-shell/context-an-image-buffer-s-file ()
  (let ((file (expand-file-name "pic.png" (make-temp-file (+test-tmp-file "ctx-") t))))
    (with-temp-buffer
      (setq buffer-file-name file)
      (should (equal (agent-shell--buffer-files :obvious t) (list file)))
      (should-not (agent-shell--buffer-files))
      (set-buffer-modified-p nil))))

(ert-deftest agent-shell/advice-installed ()
  (should (advice-member-p #'+my/agent-shell-claude-context-a
                           #'agent-shell-anthropic-make-claude-code-config)))

(ert-deftest agent-shell/advice-appends-to-session-meta ()
  "systemPrompt's append goes first in the session metadata; what was there
(Claude Code's thinking options) stays."
  (+test-agent-shell--with-colours '((bg . nil)) nil
    (let* ((meta '((claudeCode . ((options . x)))))
           (config (list (cons :identifier 'claude-code) (cons :session-meta meta)))
           (result (+my/agent-shell-claude-context-a config)))
      (should (eq result config))
      (should (equal (alist-get :session-meta result)
                     `((systemPrompt . ((append . ,+my/agent-shell-claude-context)))
                       (claudeCode . ((options . x))))))
      ;; The package's metadata isn't changed, only consed onto.
      (should (equal meta '((claudeCode . ((options . x)))))))))

(ert-deftest agent-shell/advice-without-session-meta ()
  (+test-agent-shell--with-colours '((bg . nil)) nil
    (let ((result (+my/agent-shell-claude-context-a (list (cons :identifier 'claude-code)))))
      (should (eq (alist-get :identifier result) 'claude-code))
      (should (equal (alist-get :session-meta result)
                     `((systemPrompt . ((append . ,+my/agent-shell-claude-context)))))))))

(ert-deftest agent-shell/advice-adds-the-theme-line ()
  (+test-agent-shell--with-colours +test-agent-shell--dark '(doom-one)
    (let ((text (+test-agent-shell--system-prompt
                 (+my/agent-shell-claude-context-a (list (cons :session-meta nil))))))
      (should (equal text (concat +my/agent-shell-claude-context "\n\n"
                                  (+my/agent-shell-claude-theme))))
      (should (string-suffix-p "light text and lines." text)))))

(ert-deftest agent-shell/advice-follows-the-variable ()
  "The text is read when the config is built: a changed variable counts; nil
leaves only the theme line."
  (+test-agent-shell--with-colours +test-agent-shell--dark nil
    (let ((+my/agent-shell-claude-context "Be brief."))
      (should (string-prefix-p "Be brief.\n\nEmacs uses a dark theme"
                               (+test-agent-shell--system-prompt
                                (+my/agent-shell-claude-context-a (list))))))
    (let ((+my/agent-shell-claude-context nil))
      (should (string-prefix-p "Emacs uses a dark theme"
                               (+test-agent-shell--system-prompt
                                (+my/agent-shell-claude-context-a (list))))))))

(ert-deftest agent-shell/claude-code-config-carries-it ()
  "The real Claude Code config: our text appended, its thinking options kept."
  (+test-agent-shell--with-colours +test-agent-shell--dark '(doom-one)
    (let* ((config (agent-shell-anthropic-make-claude-code-config))
           (meta (map-elt config :session-meta)))
      (should (eq (map-elt config :identifier) 'claude-code))
      (should (eq (caar meta) 'systemPrompt))
      (should (equal (+test-agent-shell--system-prompt config)
                     (concat +my/agent-shell-claude-context "\n\n"
                             (+my/agent-shell-claude-theme))))
      (should (equal (map-nested-elt meta '(claudeCode options thinking display))
                     "summarized")))))

(ert-deftest agent-shell/each-session-gets-it-once ()
  "Built anew for each session: never twice, and the colours of the theme of
the moment (dark, then light)."
  (let ((dark (+test-agent-shell--with-colours +test-agent-shell--dark '(doom-one)
                (agent-shell-anthropic-make-claude-code-config)))
        (light (+test-agent-shell--with-colours +test-agent-shell--light '(doom-one-light)
                 (agent-shell-anthropic-make-claude-code-config))))
    (dolist (config (list dark light))
      (should (= (cl-count 'systemPrompt (map-elt config :session-meta) :key #'car) 1)))
    (should (string-match-p "a dark theme (doom-one)" (+test-agent-shell--system-prompt dark)))
    (should (string-match-p "a light theme (doom-one-light)" (+test-agent-shell--system-prompt light)))
    (should-not (string-match-p "dark theme" (+test-agent-shell--system-prompt light)))))

(ert-deftest agent-shell/sent-on-new-resumed-and-loaded-sessions ()
  "agent-shell sends the config's metadata as _meta when it starts, resumes or
loads a session: as JSON, {\"systemPrompt\": {\"append\": TEXT}}."
  (+test-agent-shell--with-colours '((bg . nil)) nil
    (let ((meta (map-elt (agent-shell-anthropic-make-claude-code-config) :session-meta)))
      (dolist (request (list (acp-make-session-new-request :cwd "/tmp/" :meta meta)
                             (acp-make-session-resume-request :session-id "s" :cwd "/tmp/" :meta meta)
                             (acp-make-session-load-request :session-id "s" :cwd "/tmp/" :meta meta)))
        (let* ((params (map-elt request :params))
               (json (json-parse-string (json-serialize (map-elt params '_meta))
                                        :object-type 'alist)))
          (should (equal (map-nested-elt json '(systemPrompt append))
                         +my/agent-shell-claude-context)))))))

;; ====== SPC o c ======

(ert-deftest agent-shell/spc-o-c-starts-a-new-claude-code-session ()
  (+test-agent-shell--mocked
    (setq existing (list (+test-buffer "Claude Agent @ old")))
    (+test-agent-shell--press "o c")
    (let ((starts (+test-agent-shell--calls calls 'start)))
      (should (= (length starts) 1))
      (let ((args (cdar starts)))
        (should (eq (map-elt (plist-get args :config) :identifier) 'claude-code))
        (should (plist-get args :new-session))
        (should (equal (+test-agent-shell--system-prompt (plist-get args :config))
                       (string-join (delq nil (list +my/agent-shell-claude-context
                                                    (+my/agent-shell-claude-theme)))
                                    "\n\n")))))
    (should (equal (+test-agent-shell--calls calls 'display)
                   (list (list 'display started nil))))
    (should-not (+test-agent-shell--calls calls 'picker))
    (should-not (+test-agent-shell--calls calls 'read-shell))))

(ert-deftest agent-shell/spc-o-c-another-one-each-time ()
  (+test-agent-shell--mocked
    (+test-agent-shell--press "o c")
    (+test-agent-shell--press "o c")
    (should (= (length (+test-agent-shell--calls calls 'start)) 2))))

;; ====== SPC o C ======

(ert-deftest agent-shell/spc-o-C-starts-claude-code-as-spc-o-c ()
  "As SPC o c: a new Claude Code session, agent-shell asking which (the
project's sessions to resume or a new one), though the project has one."
  (+test-agent-shell--mocked
    (setq existing (list (+test-buffer "Claude Agent @ old")))
    (+test-agent-shell--press "o C")
    (let ((starts (+test-agent-shell--calls calls 'start)))
      (should (= (length starts) 1))
      (let ((args (cdar starts)))
        (should (eq (map-elt (plist-get args :config) :identifier) 'claude-code))
        (should (plist-get args :new-session))
        (should (equal (+test-agent-shell--system-prompt (plist-get args :config))
                       (string-join (delq nil (list +my/agent-shell-claude-context
                                                    (+my/agent-shell-claude-theme)))
                                    "\n\n")))))
    (should (equal (+test-agent-shell--calls calls 'display)
                   (list (list 'display started nil))))
    (should-not (+test-agent-shell--calls calls 'picker))
    (should-not (+test-agent-shell--calls calls 'read-shell))))

(ert-deftest agent-shell/spc-o-C-shows-it-here ()
  "While SPC o C shows the session (agent-shell keeping the override for
when a session is picked), the here action comes first, the override there
was after it; then the override is as it was."
  (+test-agent-shell--mocked
    (let ((display-buffer-overriding-action '((+test-agent-shell--other) (some . thing)))
          seen)
      (cl-letf (((symbol-function 'agent-shell--display-and-insert-context)
                 (lambda (&rest _) (setq seen (copy-tree display-buffer-overriding-action)))))
        (+test-agent-shell--press "o C"))
      (should (equal seen '((+my/agent-shell-here-display +test-agent-shell--other) (some . thing))))
      (should (equal display-buffer-overriding-action '((+test-agent-shell--other) (some . thing))))
      ;; Without an override, or one function alone.
      (should (equal (+my/agent-shell--here-action nil) '((+my/agent-shell-here-display))))
      (should (equal (+my/agent-shell--here-action '(ignore)) '((+my/agent-shell-here-display ignore)))))))

(ert-deftest agent-shell/here-display-a-session-in-the-selected-window ()
  "The here action: a session in the selected window, what it showed kept
under it; any other buffer, or a window dedicated to its own, nil."
  (+test-with-reset
    (let ((file (+test-buffer "code.el" "(foo)\n" #'emacs-lisp-mode))
          (session (+test-buffer "Claude Agent @ here")))
      (with-current-buffer session (setq-local major-mode 'agent-shell-mode))
      (switch-to-buffer file)
      (should-not (+my/agent-shell-here-display (+test-buffer "other") nil))
      (should (eq (window-buffer) file))
      (set-window-dedicated-p nil t)
      (should-not (+my/agent-shell-here-display session nil))
      (set-window-dedicated-p nil nil)
      (should (eq (+my/agent-shell-here-display session nil) (selected-window)))
      (should (eq (window-buffer) session))
      (should (eq (car (car (window-prev-buffers))) file)))))

;;; test-agent-shell.el ends here
