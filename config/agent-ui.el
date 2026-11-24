;;; $DOOMDIR/config/agent-ui.el -*- lexical-binding: t; -*-
;; Agent UI: what a coding agent (yours, in agent-shell) shows you in
;; Emacs beyond its replies: progress bars, tables, charts, at the bottom of
;; its session's pane, updated as things change (docs/agent-ui.md).
;; Loaded from config.el; its code is in config/agent-ui/.

;; ====== VARIABLES ======

;; ELEMENT TYPES
;; An element is data: JSON from the agent, a plist here, of a type defined
;; once with `agent-ui-define' (config/agent-ui/core.el): its properties, a
;; drawing as text and, optionally, one for the GUI. Its drawing failing shows
;; the error in its place. Limits keep drawing quick (Emacs has one thread):
;; `agent-ui-max-chars' (cut at a line's end; a panel's children each, the
;; panel's frame whole, its lines within `agent-ui-panel-max-chars'),
;; `agent-ui-max-rows', `agent-ui-max-cell-lines'.

;; THE CANVAS
;; A buffer per agent session, "Agent UI: NAME" (config/agent-ui/canvas.el):
;; its elements in the order shown, each redrawn in place when it changes,
;; `agent-ui-redraw-delay' after (updates within it drawn together); animated
;; ones every `agent-ui-animation-interval'. In it: g r redraws it, q kills it.
;; At most `agent-ui-max-elements'.

;; IN ITS SESSION'S PANE
;; A session's Agent UI opens in its session's pane when an element is shown,
;; without taking the focus (config/agent-ui/pane.el): the pane split, the
;; conversation on top, Agent UI at the bottom, a quarter of the pane
;; (`agent-ui-pane-share'), more when what it shows needs it, up to half
;; (`agent-ui-pane-max-share'); back to a quarter when that's gone.
;; Its views (the session's canvas, and its others: ask, tests...) are laid
;; out there in a grid: as many columns as fit, `agent-ui-grid-min-width'
;; each, up to the square root of their count, rows filled in turn. Each view
;; is a window of its own, with a bar naming it; a bar under them says what
;; Agent UI is and its keys; the session's mode line stays under the
;; conversation. q closes a view (killed); a view's window closed
;; (SPC w d) hides it until something new is shown in it; SPC m u, in the
;; session or a view, hides Agent UI for the session or shows it again (a
;; question shows it anyway). A session in no window (another workspace,
;; another buffer in its pane): Agent UI waits, shown with it. Tiling lays
;; the pane out as one, Agent UI's windows in it (config/tiling.el, WINDOWS
;; ATTACHED TO A PANE). A pane too short for both halves
;; (`agent-ui-pane-min-lines' each): the view in a pane of its own. A canvas
;; without a session (from a shell), a project panel: a tiled pane of its own
;; (one of tiling's applications).
(setq agent-ui-pane-keys "q close a view · SPC m u hide Agent UI")

;; SOURCES
;; An element can follow what changes by itself (config/agent-ui/source.el):
;; a command Emacs runs for the agent (its output logged for it to read), a
;; file as it grows, a command polled every so many seconds. Rules turn their
;; lines into updates: the agent's tool calls run one after another, so a bar
;; it updated itself would stand still while it waits on a long build.

;; IN THE CONVERSATION
;; agent-shell owns its buffer's text: an element goes there the ways it has
;; (config/agent-ui/snapshot.el). The agent saves one as an image (cmd/agent-ui
;; snapshot ID: an SVG in the session's .agent-shell/images/) and links it in
;; its reply, which agent-shell shows inline and its transcript keeps; a in a
;; canvas puts the element at point into its session's prompt, as text.

;; MCP
;; Each agent-shell session also gets Agent UI as MCP tools, with their
;; schemas (`agent-shell-mcp-servers'): cmd/agent-ui-mcp.el, run by a batch
;; Emacs (this one's binary) the agent starts, each call through
;; cmd/agent-ui. The session's name and directory are passed to it. Its system
;; prompt then says so. (setq +my/agent-ui-mcp nil) in config.el: none.
(defvar +my/agent-ui-mcp t
  "Agent UI as MCP tools in each agent-shell session (see MCP above).")

;; KEPT WITH THE SESSION
;; A session's canvas is saved as it changes, in its .agent-shell/agent-ui/
;; (by its session id), and comes back when the session is resumed, as it was
;; (config/agent-ui/persist.el); its sources aren't started again.

;; THE AGENT'S WAY IN
;; cmd/agent-ui, from the agent's shell: show, update, append, remove... an
;; element as JSON, the reply as JSON (config/agent-ui/request.el), through
;; emacsclient. Each agent-shell session starts its agent with
;; AGENT_UI_SESSION, so its requests go to its own canvas, which closes with
;; it (config/agent-ui/agent.el); without it, the session working in the
;; request's directory.

;; TYPES THE AGENT MAKES
;; When none of the types fits, the agent writes one (cmd/agent-ui define
;; FILE: an `agent-ui-define' and its definitions, named after it). It's
;; checked, compiled and loaded, its example drawn for the agent to see
;; (config/agent-ui/staging.el), and staged: usable at once, kept only if you
;; keep it. A message and the canvas's header say so; R in the canvas (M-x
;; agent-ui-review) lists them (config/agent-ui/review.el): RET its preview
;; (its example drawn, its code), a keeps it, x discards it (its elements
;; removed), v its code. Staged ones wait in `agent-ui-staging-directory' (not
;; loaded again after a restart: the review loads one to preview it); kept ones
;; go to `agent-ui-kept-directory', in this config (git), loaded at each start,
;; and an issue is filed for their tests and documentation (in this config's
;; Beads issues).
(setq agent-ui-staging-directory (expand-file-name "agent-ui/staged/" doom-cache-dir)
      agent-ui-kept-directory (expand-file-name "config/agent-ui/kept/" doom-user-dir))

;; IMAGES FROM URLS: downloaded once, kept in Doom's cache.
(setq agent-ui-image-cache-directory (expand-file-name "agent-ui/images/" doom-cache-dir))
;; The project panels whose code was let run (by content): kept, not a cache's.
(setq agent-ui-panel-trust-file (expand-file-name "agent-ui/trusted-panels.eld" doom-data-dir))

;; BUGS IN AGENT UI
;; When Agent UI itself misbehaves (a wrong drawing, an error, a property
;; missing), from a session in any project: the agent files it (cmd/agent-ui
;; bug, the MCP tool bug: asking you first), or you do, b on the element in
;; its canvas (M-x agent-ui-report-bug anywhere). It goes into this config's
;; Beads issues (a bug, labelled agent-ui), never the project's: found from
;; Agent UI's code, bd run there (config/beads/file.el). The report carries
;; the element shown (its JSON, its drawing), a repro from the agent, and the
;; environment. A similar open bug gets it as a note instead. A message, and
;; a notification while Emacs isn't in front (config/notify/agent-ui.el).
;; Without issues there (or bd): nothing filed, the report given back, written
;; (to the agent; to you, in a buffer, copied), to report by hand.
(setq agent-ui-bug-function
      (lambda (title description library new)
        (+my/beads-file-bug title description :from library :labels '("agent-ui") :new new)))

;; WHAT THE AGENT IS TOLD
;; What every session in agent-shell is told (config/agent-shell/context.el)
;; gets a paragraph on the canvas (`agent-ui-agent-context'): what it's for, the
;; command, and the skill to read before using it (skills/agent-ui/SKILL.md:
;; its types, with examples). Only while Emacs runs a server.

;; ====== KEY BINDINGS ======

;; A PROJECT'S PANELS (config/agent-ui/panels.el): SPC o u opens one of the
;; current project's (.agent-ui/panels/), picked from them, in a pane of its
;; own; SPC o U in the window you're in.
(map! :leader
      :desc "Project panel"       "o u" #'agent-ui-open-panel
      :desc "Project panel, here" "o U" #'agent-ui-open-panel-here)

;; THE CANVAS (see above): Vim's keys, as Doom's other buffers'.
(map! :map agent-ui-canvas-mode-map
      ;; q closes it for good: its buffer killed, its elements with it (a
      ;; session's saved ones come back when it's resumed); in its session's
      ;; pane, the other views laid out again; else its pane closed.
      :gn "q" #'agent-ui-quit
      :n "gr" #'agent-ui-canvas-redraw
      ;; A project panel, read again from its file (edited) and run anew.
      :n "gR" #'agent-ui-panel-reload
      ;; The element at point saved as one of the project's panels.
      :n "S"  #'agent-ui-save-panel
      :n "R"  #'agent-ui-review
      :n "a"  #'agent-ui-send-element
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
      ;; Agent UI hidden in its session's pane, or shown again (see above).
      :localleader
      :desc "Agent UI: hide / show" "u" #'agent-ui-pane-toggle)

;; A FORM, filled in its buffer (config/agent-ui/elements/form.el): typed
;; into, so Emacs's keys there, as beads.el's forms (C-c C-c sends it, C-c
;; C-k cancels, TAB to the next field).
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

;; ====== CODE ======

;; In config/agent-ui/, in this order: each part can use what the ones before
;; it define.
(load! "agent-ui/core")
(load! "agent-ui/canvas")
(load! "agent-ui/request")
(load! "agent-ui/agent")
;; In its session's pane: at the bottom, a grid of its views.
(load! "agent-ui/pane")
(load! "agent-ui/persist")
;; What the elements that ask share (picking, a note, the answer).
(load! "agent-ui/ask")
;; The element types, a file each in agent-ui/elements/.
(load! "agent-ui/elements")
;; A finished element closing itself, a countdown under it.
(load! "agent-ui/finished")
(load! "agent-ui/staging")
(load! "agent-ui/review")
(load! "agent-ui/source")
;; Project panels: kept in a project's repository, opened on demand.
(load! "agent-ui/panels")
(load! "agent-ui/snapshot")
(load! "agent-ui/bug")

;; TYPES THE AGENT MAKES (see above): the ones you kept.
(agent-ui-load-kept)

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
       (format "--description=The agent made the element type %s; it was kept, in %s. Give it tests (tests/unit/test-agent-ui-elements.el expects every type), a section in skills/agent-ui/SKILL.md (its test expects one per type), and a row in docs/agent-ui.md's types."
               name (file-relative-name file doom-user-dir))))))

(add-hook 'agent-ui-kept-functions #'+my/agent-ui-kept-issue)

;; PAGES AND FILES an element opens (RET on an html card, an image): a page in
;; WebKit in a pane where it can (config/html.el), else the browser.
(defun +my/agent-ui-open-page (page)
  "Open PAGE, an html element's file or URL (see above)."
  (if (fboundp '+my/html-open-in-emacs)
      (+my/html-open-in-emacs page)
    (agent-ui-html-browse page)))

(setq agent-ui-open-page-function #'+my/agent-ui-open-page)

;; MCP (see above): the server, for each session started from now on.
(defun +my/agent-ui-mcp-server ()
  "Agent UI's MCP server, as `agent-shell-mcp-servers' has them: its
session's name and directory read when the session starts (in its buffer)."
  `((name . "agent-ui")
    (command . ,(expand-file-name invocation-name invocation-directory))
    (args . ("--batch" "-Q" "-l" ,(expand-file-name "cmd/agent-ui-mcp.el" doom-user-dir)
             "-f" "agent-ui-mcp-main"))
    (env . (((name . "AGENT_UI_SESSION")
             (value . ,(lambda () (agent-ui--session-name (current-buffer)))))
            ((name . "AGENT_UI_DIR")
             (value . ,(lambda () (if (fboundp 'agent-shell-cwd) (agent-shell-cwd) default-directory))))))))

(defun +my/agent-ui-mcp-register ()
  "Add (or replace) Agent UI's MCP server in `agent-shell-mcp-servers'."
  (setq agent-shell-mcp-servers
        (append (seq-remove (lambda (server) (equal (alist-get 'name server) "agent-ui"))
                            (bound-and-true-p agent-shell-mcp-servers))
                (list (+my/agent-ui-mcp-server)))
        agent-ui-agent-mcp t))

(when +my/agent-ui-mcp
  (with-eval-after-load 'agent-shell
    (+my/agent-ui-mcp-register)))

;; A BUG FILED (b on an element, see BUGS IN AGENT UI above): RET right after
;; opens it in Emacs's issue view (config/beads.el).
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
      (agent-ui-bug-show-issue id dir))))

(setq agent-ui-open-issue-function #'+my/agent-ui-open-issue)

;; A QUESTION WAITING: a session's turn ended with a question on its canvas
;; (config/agent-ui/agent.el): C-c C-q in the session goes there.
(map! :after agent-shell
      :map agent-shell-mode-map
      "C-c C-q" #'agent-ui-goto-question
      :localleader
      :desc "Question waiting" "q" #'agent-ui-goto-question
      ;; IN ITS SESSION'S PANE (see above): hidden, or shown again.
      :desc "Agent UI: hide / show" "u" #'agent-ui-pane-toggle)

;; WHAT THE AGENT IS TOLD (see above), after what's there (the theme's line, the
;; project's issues).
(add-hook '+my/agent-shell-context-functions #'agent-ui-agent-context t)
