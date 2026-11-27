;;; $DOOMDIR/config/agent-ui.el -*- lexical-binding: t; -*-
;; Agent UI: what a coding agent (yours, in agent-shell) shows you in
;; Emacs beyond its replies, at the bottom of its session's pane. Loaded from
;; config.el. Its own package now (~/dev/agent-ui, packages.el; its docs:
;; docs/ there); here, this config's layer over it: its look, its keys,
;; where its files go, the bugs it files, and what it's tied to here
;; (Beads, Mermaid, tiling, the banner, WebKit).

(require 'agent-ui)

;; ====== VARIABLES ======

;; IN ITS SESSION'S PANE
;; Under the views, Doom's mode line (as tall as the windows' beside them),
;; saying what Agent UI's bar said (config/editor/modeline.el): what it is,
;; its views; no keys.
(setq agent-ui-pane-mode-line t
      agent-ui-pane-keys nil)

;; WHAT THE AGENT IS TOLD
;; This config tells every session about Emacs itself (config/agent-shell/
;; context.el: also the agents that take no system prompt), Agent UI's
;; paragraph among it, after what's there (the theme's line, the project's
;; issues): not the package's own (`agent-ui-system-prompt'), which would
;; say it twice. The agent's name (its quick questions' tool) from the
;; session's config.
(setq agent-ui-system-prompt nil)

(defun +my/agent-ui-context ()
  "Agent UI's paragraph of what a session is told (see above)."
  (let ((agent-ui-agent-identifier
         (map-elt (bound-and-true-p +my/agent-shell-context-config) :identifier)))
    (agent-ui-agent-context)))

(add-hook '+my/agent-shell-context-functions #'+my/agent-ui-context t)

;; MCP
;; Each agent-shell session also gets Agent UI as MCP tools (the package's
;; agent-ui-mcp.el, `agent-ui-mcp', on by default). (setq agent-ui-mcp nil)
;; in config.el, before this file loads: none.

;; TYPES THE AGENT MAKES
;; Staged ones wait in Doom's cache (not loaded again after a restart);
;; kept ones go to this config (git), loaded at each start, and an issue
;; is filed for their tests and documentation (in this config's Beads
;; issues, `+my/agent-ui-kept-issue' below).
(setq agent-ui-staging-directory (expand-file-name "agent-ui/staged/" doom-cache-dir)
      agent-ui-kept-directory (expand-file-name ".agent-ui/kept/" doom-user-dir))

;; IMAGES FROM URLS: downloaded once, kept in Doom's cache. Mermaid's
;; diagrams too, when drawn by the package's own renderer.
(setq agent-ui-image-cache-directory (expand-file-name "agent-ui/images/" doom-cache-dir)
      agent-ui-mermaid-cache-directory (expand-file-name "agent-ui/mermaid/" doom-cache-dir))
;; The project dashboards whose code was let run (by content): kept, not a cache's.
(setq agent-ui-dashboard-trust-file (expand-file-name "agent-ui/trusted-dashboards.eld" doom-data-dir))

;; MERMAID: diagrams drawn by config/mermaid.el's renderer (in the theme's
;; colours, as the rest of this config's diagrams), not the package's;
;; drawn again when the theme changes.
(setq agent-ui-mermaid-render-function #'+my/mermaid-render
      agent-ui-mermaid-key-function #'+my/mermaid-theme-json)
(add-hook '+my/mermaid-theme-hook #'agent-ui-mermaid-theme-changed)

;; BUGS IN AGENT UI
;; When Agent UI itself misbehaves (a wrong drawing, an error, a property
;; missing), from a session in any project: the agent files it (bin/agent-ui
;; bug, the MCP tool bug: asking you first), or you do, b on the component
;; in its canvas (M-x agent-ui-report-bug anywhere). It goes into this
;; config's Beads issues (a bug, labelled agent-ui), never the project's
;; (config/beads/file.el). A message, and a notification while Emacs isn't
;; in front (config/notify/agent-ui.el). Without issues here (or bd):
;; nothing filed, the report given back, to report by hand.
(setq agent-ui-bug-function
      (lambda (title description _library new)
        (+my/beads-file-bug title description :from doom-user-dir :labels '("agent-ui") :new new)))

;; ====== KEY BINDINGS ======

;; A PROJECT'S DASHBOARDS: SPC o u opens one of the current project's
;; (.agent-ui/dashboards/), picked from them, in a pane of its own; SPC o U in
;; the window you're in.
(map! :leader
      :desc "Project dashboard"       "o u" #'agent-ui-open-dashboard
      :desc "Project dashboard, here" "o U" #'agent-ui-open-dashboard-here)

;; THE CANVAS: Vim's keys, as Doom's other buffers'.
(map! :map agent-ui-canvas-mode-map
      ;; q closes it for good: its buffer killed, its components with it (a
      ;; session's saved ones come back when it's resumed); in its session's
      ;; pane, the other views laid out again; else its pane closed.
      :gn "q" #'agent-ui-quit
      :n "gr" #'agent-ui-canvas-redraw
      ;; A project dashboard, read again from its file (edited) and run anew.
      :n "gR" #'agent-ui-dashboard-reload
      ;; The component at point saved as one of the project's dashboards.
      :n "S"  #'agent-ui-save-dashboard
      :n "R"  #'agent-ui-review
      :n "a"  #'agent-ui-send-component
      :n "b"  #'agent-ui-report-bug
      :n "c"  #'agent-ui-comment
      :n "d"  #'agent-ui-uncomment
      :n "s"  #'agent-ui-table-sort
      ;; A rank's items moved (M-up / M-down in any state).
      :n "K"  #'agent-ui-move-item-up
      :n "J"  #'agent-ui-move-item-down
      :n "M-<up>"   #'agent-ui-move-item-up
      :n "M-<down>" #'agent-ui-move-item-down
      ;; A plan's steps dropped (again: back), reworded, before approving it.
      :n "x"  #'agent-ui-drop-item
      :n "e"  #'agent-ui-edit-item
      ;; Agent UI hidden in its session's pane, or shown again.
      :localleader
      :desc "Agent UI: hide / show" "u" #'agent-ui-pane-toggle
      ;; What it shows now, a PDF: a session's view's in .agent-shell/pdf/, a
      ;; project dashboard's beside its file (only a dashboard has a notice offering it).
      :desc "Export as a PDF" "e" #'agent-ui-export-pdf)

;; A FORM, filled in its buffer: typed into, so Emacs's keys there, as
;; beads.el's forms (C-c C-c sends it, C-c C-k cancels, TAB to the next field).
(after! evil
  (evil-set-initial-state 'agent-ui-form-mode 'emacs))

;; TYPES THE AGENT MAKES (see above): the list, a preview.
(map! :map agent-ui-review-mode-map
      :n "RET" #'agent-ui-review-preview
      :n "a"   #'agent-ui-review-keep
      :n "x"   #'agent-ui-review-discard
      :n "v"   #'agent-ui-review-source
      :n "gr"  #'revert-buffer
      :n "q"   #'quit-window
      :map agent-ui-review-preview-mode-map
      :n "a"   #'agent-ui-review-keep
      :n "x"   #'agent-ui-review-discard
      :n "v"   #'agent-ui-review-source
      :n "q"   #'quit-window)

;; A QUESTION WAITING: a session's turn ended with a question on its canvas:
;; C-c C-q in the session goes there.
(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c C-q" #'agent-ui-goto-question
      :localleader
      :desc "Question waiting" "q" #'agent-ui-goto-question
      ;; IN ITS SESSION'S PANE (see above): hidden, or shown again.
      :desc "Agent UI: hide / show" "u" #'agent-ui-pane-toggle)

;; ====== CODE ======

(defun +my/agent-ui-kept-issue (name file)
  "An issue in this config's Beads issues for the type NAME just kept (in
FILE): its tests and documentation."
  (when (and (executable-find "bd")
             (file-directory-p (expand-file-name ".beads" doom-user-dir)))
    (let ((default-directory doom-user-dir))
      (start-process
       "agent-ui-kept-issue" nil "bd" "create" "--silent" "--type=task" "--priority=3"
       "--labels=agent-ui"
       (format "--title=Agent UI: tests and docs for the kept type %s" name)
       (format "--description=The agent made the component type %s; it was kept, in %s. Give it tests and documentation (in the agent-ui package, ~/dev/agent-ui, if it belongs there)."
               name (file-relative-name file doom-user-dir))))))

(add-hook 'agent-ui-kept-functions #'+my/agent-ui-kept-issue)

;; A PROJECT DASHBOARD'S NOTICE (config/banner.el): each one opened (SPC o u; not a
;; session's canvas) offers to be exported as a PDF, as it shows now, beside
;; its file (`agent-ui-export-pdf', SPC m e there and in any canvas).
(defun +my/agent-ui-dashboard-pdf-notice ()
  "Offer the project dashboard here as a PDF (see above)."
  (when (fboundp '+my/banner-show)
    (+my/banner-show 'agent-ui-dashboard-pdf
                     "Export this dashboard as a PDF, as it shows now (SPC m e)."
                     :actions '(("Export PDF" . agent-ui-export-pdf)))))

(add-hook 'agent-ui-dashboard-open-hook #'+my/agent-ui-dashboard-pdf-notice)

;; A LONE PANEL'S TITLE: a canvas showing one panel only doesn't
;; draw its title over it: its view's bar says it, and in a pane of its own
;; (a project dashboard), its tab (config/editor/tabs.el).
(add-hook '+my/tabs-label-functions #'agent-ui-canvas-label)

;; PAGES AND FILES a component opens (RET on an html card, an image): a page
;; in WebKit in a pane where it can (config/html.el), else the browser.
(defun +my/agent-ui-open-page (page)
  "Open PAGE, an html component's file or URL (see above)."
  (if (fboundp '+my/html-open-in-emacs)
      (+my/html-open-in-emacs page)
    (agent-ui-html-browse page)))

(setq agent-ui-open-page-function #'+my/agent-ui-open-page)

;; A BUG FILED (b on a component, see BUGS IN AGENT UI above): RET right
;; after opens it in Emacs's issue view (config/beads.el).
(defun +my/agent-ui-open-issue (id dir)
  "Open issue ID of DIR's issues in Beads' issue view."
  (let ((default-directory dir))
    (if-let* (((fboundp 'beads-detail-open))
              (json (with-temp-buffer
                      (and (eql 0 (call-process "bd" nil '(t nil) nil "show" id "--json"))
                           (buffer-string))))
              (issue (ignore-errors (json-parse-string json :object-type 'alist :array-type 'list))))
        ;; bd show --json: an array of one issue.
        (beads-detail-open (if (and (consp issue) (consp (car issue)) (consp (caar issue))) (car issue) issue))
      (message "Agent UI: bug %s filed (in %s)" id (abbreviate-file-name dir)))))

(setq agent-ui-open-issue-function #'+my/agent-ui-open-issue)

;; ON: what ties Agent UI to agent-shell and Emacs's windows (each session's
;; canvas, its MCP tools, a question waiting, canvases kept with their
;; sessions, the views synced with their pane; the kept types loaded).
(agent-ui-mode 1)
