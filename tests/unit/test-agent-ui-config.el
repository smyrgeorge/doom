;;; tests/unit/test-agent-ui-config.el -*- lexical-binding: t; -*-
;; config/agent-ui.el: this config's layer over the agent-ui package (its own
;; tests are the package's, ~/dev/agent-ui/tests): Vim's keys, where its
;; files go, what a session is told (through config/agent-shell/context.el),
;; Mermaid's diagrams drawn by config/mermaid.el, the bugs it files into this
;; config's Beads issues (config/beads/file.el), the panel's PDF notice, the
;; package's mode on.

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(+test-load "config/agent-shell" "config/emacs" "config/webkit" "config/mermaid" "config/agent-ui" "config/beads")
(require 'agent-shell)

;; Bound by the tests: dynamically.
(defvar agent-shell-elicitation--experimental-feature-enabled)
(defvar +my/agent-shell-context-config)

;; ====== ON, AND WHERE ======

(ert-deftest agent-ui-config/the-package-on ()
  (should (featurep 'agent-ui))
  (should agent-ui-mode)
  ;; Its own command, skill and MCP server: the package's.
  (should (file-executable-p agent-ui-command))
  (should (file-exists-p agent-ui-skill))
  (should (file-exists-p (expand-file-name "agent-ui-mcp.el" agent-ui-directory))))

(ert-deftest agent-ui-config/where-its-files-go ()
  (should (equal agent-ui-staging-directory (expand-file-name "agent-ui/staged/" doom-cache-dir)))
  (should (equal agent-ui-kept-directory (expand-file-name ".agent-ui/kept/" doom-user-dir)))
  (should (equal agent-ui-image-cache-directory (expand-file-name "agent-ui/images/" doom-cache-dir)))
  (should (equal agent-ui-mermaid-cache-directory (expand-file-name "agent-ui/mermaid/" doom-cache-dir)))
  (should (equal agent-ui-panel-trust-file (expand-file-name "agent-ui/trusted-panels.eld" doom-data-dir))))

(ert-deftest agent-ui-config/under-its-views-dooms-mode-line ()
  (should (eq agent-ui-pane-mode-line t))
  (should-not agent-ui-pane-keys))

;; ====== KEYS ======

(ert-deftest agent-ui-config/vims-keys ()
  (let ((normal (evil-get-auxiliary-keymap agent-ui-canvas-mode-map 'normal)))
    (dolist (binding '(("q" . agent-ui-quit) ("gr" . agent-ui-canvas-redraw) ("gR" . agent-ui-panel-reload)
                       ("S" . agent-ui-save-panel) ("R" . agent-ui-review) ("a" . agent-ui-send-component)
                       ("b" . agent-ui-report-bug) ("c" . agent-ui-comment) ("d" . agent-ui-uncomment)
                       ("s" . agent-ui-table-sort) ("K" . agent-ui-move-item-up) ("J" . agent-ui-move-item-down)
                       ("x" . agent-ui-drop-item) ("e" . agent-ui-edit-item)))
      (should (eq (lookup-key normal (kbd (car binding))) (cdr binding)))))
  (let ((review (evil-get-auxiliary-keymap agent-ui-review-mode-map 'normal)))
    (should (eq (lookup-key review "x") #'agent-ui-review-discard))
    (should (eq (lookup-key review "a") #'agent-ui-review-keep)))
  ;; A form typed into: Emacs's keys.
  (should (eq (evil-initial-state 'agent-ui-form-mode) 'emacs))
  ;; SPC o u: a project's panel.
  (should (eq (lookup-key doom-leader-map "ou") #'agent-ui-open-panel))
  (should (eq (lookup-key doom-leader-map "oU") #'agent-ui-open-panel-here))
  ;; C-c C-q in a session: the question waiting.
  (require 'agent-shell)
  (should (eq (keymap-lookup agent-shell-mode-map "C-c C-q") #'agent-ui-goto-question)))

;; ====== WHAT A SESSION IS TOLD ======

(ert-deftest agent-ui-config/told-once-by-this-config ()
  "Agent UI's paragraph in what this config tells every session, not in the
package's own system prompt too (said twice)."
  (should-not agent-ui-system-prompt)
  (should (memq #'+my/agent-ui-context +my/agent-shell-context-functions))
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
    (should (string-search "Agent UI: in this session's pane" (+my/agent-shell-context-text)))
    ;; The command and the skill: the package's.
    (should (string-search (abbreviate-file-name agent-ui-command) (+my/agent-ui-context)))
    ;; Claude Code asks quick questions with AskUserQuestion; another agent
    ;; with its own tool (the session's config says which).
    (let ((agent-shell-elicitation--experimental-feature-enabled t))
      (let ((+my/agent-shell-context-config '((:identifier . claude-code))))
        (should (string-search "AskUserQuestion" (+my/agent-ui-context))))
      (let ((+my/agent-shell-context-config '((:identifier . codex))))
        (should-not (string-search "AskUserQuestion" (+my/agent-ui-context)))
        (should (string-search "with your own tool for asking the user" (+my/agent-ui-context)))))))

(ert-deftest agent-ui-config/its-mcp-tools ()
  (should agent-ui-mcp)
  (should (seq-find (lambda (s) (equal (alist-get 'name s) "agent-ui")) agent-shell-mcp-servers)))

;; ====== MERMAID ======

(ert-deftest agent-ui-config/diagrams-drawn-by-this-config ()
  (should (eq agent-ui-mermaid-render-function #'+my/mermaid-render))
  (should (eq agent-ui-mermaid-key-function #'+my/mermaid-theme-json))
  (should (memq #'agent-ui-mermaid-theme-changed +my/mermaid-theme-hook)))

;; ====== HOOKS ======

(ert-deftest agent-ui-config/a-panels-notice-offers-a-pdf ()
  (should (memq '+my/agent-ui-panel-pdf-notice agent-ui-panel-open-hook))
  (let (shown)
    (cl-letf (((symbol-function '+my/banner-show) (lambda (&rest args) (setq shown args))))
      (+my/agent-ui-panel-pdf-notice))
    (should (eq (car shown) 'agent-ui-panel-pdf))
    (should (equal (plist-get (cddr shown) :actions) '(("Export PDF" . agent-ui-export-pdf))))))

(ert-deftest agent-ui-config/the-rest-of-its-wiring ()
  (should (memq #'agent-ui-canvas-label +my/tabs-label-functions))
  (should (memq #'+my/agent-ui-kept-issue agent-ui-kept-functions))
  (should (eq agent-ui-open-page-function #'+my/agent-ui-open-page))
  (should (eq agent-ui-open-issue-function #'+my/agent-ui-open-issue)))

;; ====== BUGS IN AGENT UI ======
;; Filed into this config's Beads issues, whatever the session's project.

(ert-deftest agent-ui-config/bugs-filed-into-this-configs-issues ()
  (let (given)
    (cl-letf (((symbol-function '+my/beads-file-bug) (lambda (&rest args) (setq given args) '(:id "doom-x" :new t))))
      (should (equal (funcall agent-ui-bug-function "Agent UI: x" "y" "/elsewhere/" t) '(:id "doom-x" :new t))))
    (should (equal given (list "Agent UI: x" "y" :from doom-user-dir :labels '("agent-ui") :new t)))))

(defmacro +test-auc-with-projects (&rest body)
  "BODY with two git repos tracking their issues with bd, `library' (prefix
lib) and `other' (prefix oth, the session's directory), a temp HOME;
skipped without bd."
  (declare (indent 0))
  `(progn
     (unless (executable-find "bd") (ert-skip "No bd"))
     (let* ((home (file-name-as-directory (make-temp-file (+test-tmp-file "auc-home-") t)))
            (process-environment (append (list (concat "HOME=" home) (concat "GIT_CONFIG_GLOBAL=" home ".gitconfig")
                                               "GIT_CONFIG_NOSYSTEM=1" "BD_ACTOR=Tester")
                                         process-environment))
            (library nil) (other nil))
       (with-temp-file (expand-file-name ".gitconfig" home)
         (insert "[user]\n\tname = T\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n"))
       (dolist (prefix '("lib" "oth"))
         (let ((default-directory (file-name-as-directory
                                   (file-truename (make-temp-file (+test-tmp-file (concat prefix "-")) t)))))
           (+test-bd-init "--quiet" "--prefix" prefix)
           (if (equal prefix "lib") (setq library default-directory) (setq other default-directory))))
       ,@body)))

(defun +test-auc-issues (dir &rest args)
  "DIR's issues (bd list --json ARGS, run there without the BEADS_DIR a test
set for another project's session)."
  (let ((default-directory dir)
        (process-environment (seq-remove (lambda (v) (string-prefix-p "BEADS_DIR=" v)) process-environment)))
    (json-parse-string (with-temp-buffer
                         (apply #'call-process "bd" nil '(t nil) nil "list" "--json" "--all" "--limit" "0" args)
                         (buffer-string))
                       :object-type 'plist :array-type 'list :null-object nil)))

(ert-deftest beads-file/similar-titles ()
  (should (+my/beads-similar-titles-p "Agent UI: a stats tile's label overlaps the next tile"
                                      "stats tile label overlaps the next tile"))
  (should (+my/beads-similar-titles-p "Agent UI: The spinner doesn't spin" "Agent UI: the spinner doesn't spin!"))
  (should-not (+my/beads-similar-titles-p "Agent UI: a stats tile's label overlaps the next tile"
                                          "Agent UI: a chart's legend overlaps its plot"))
  (should-not (+my/beads-similar-titles-p "Agent UI: " "Agent UI: x")))

(ert-deftest beads-file/filed-in-the-issues-found-from-the-code ()
  "Filed from another project's session (its BEADS_DIR set): in the issues
found from FROM, a bug with its labels; a similar open one gets a note
\(unless new); no issues there or no bd: an error saying so."
  (+test-auc-with-projects
    (let* ((process-environment (cons (concat "BEADS_DIR=" other ".beads") process-environment))
           (default-directory other)
           (from library)
           (filed (+my/beads-file-bug "Agent UI: a tile's label overlaps" "Long labels.\n\n## Repro\n\nx"
                                      :from from :labels '("agent-ui"))))
      (should (plist-get filed :new))
      (should (equal (plist-get filed :dir) library))
      (should (string-prefix-p "lib-" (plist-get filed :id)))
      (let ((issue (car (+test-auc-issues library))))
        (should (equal (plist-get issue :id) (plist-get filed :id)))
        (should (equal (plist-get issue :issue_type) "bug"))
        (should (equal (plist-get issue :labels) '("agent-ui")))
        (should (equal (plist-get issue :description) "Long labels.\n\n## Repro\n\nx")))
      (should-not (+test-auc-issues other))
      ;; Again, alike: a note on it.
      (let ((again (+my/beads-file-bug "Agent UI: a tile label overlaps!" "Seen again." :from from :labels '("agent-ui"))))
        (should (equal again (list :id (plist-get filed :id) :new nil :dir library)))
        (should (string-match-p "Reported again, .*: Agent UI: a tile label overlaps!\n\nSeen again."
                                (plist-get (car (+test-auc-issues library)) :notes))))
      ;; New anyway; another, unlike it.
      (should (plist-get (+my/beads-file-bug "Agent UI: a tile label overlaps" "x" :from from :new t) :new))
      (should (plist-get (+my/beads-file-bug "Agent UI: the legend hides the plot" "x" :from from :labels '("agent-ui")) :new))
      (should (= (length (+test-auc-issues library)) 3))
      ;; Not set up.
      (let ((bare (make-temp-file (+test-tmp-file "bare-") t)))
        (should (string-match-p "no Beads issues (.beads) in .* or above"
                                (error-message-string (should-error (+my/beads-file-bug "x" "y" :from bare))))))
      (cl-letf (((symbol-function 'executable-find) #'ignore))
        (should (equal (error-message-string (should-error (+my/beads-file-bug "x" "y" :from from)))
                       "bd isn't installed"))))))
