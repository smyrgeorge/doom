;;; $DOOMDIR/config/agent-ui.el -*- lexical-binding: t; -*-
;; Agent UI: what a coding agent (Claude Code in agent-shell) shows you in
;; Emacs beyond its replies: progress bars, tables, charts, on a canvas beside
;; its session, updated as things change (docs/agent-ui.md). Loaded from
;; config.el; its code is in config/agent-ui/.

;; ====== VARIABLES ======

;; ELEMENT TYPES
;; An element is data: JSON from the agent, a plist here, of a type defined
;; once with `agent-ui-define' (config/agent-ui/core.el): its properties, a
;; drawing as text and, optionally, one for the GUI. Its drawing failing shows
;; the error in its place. Limits keep drawing quick (Emacs has one thread):
;; `agent-ui-max-chars', `agent-ui-max-rows'.

;; THE CANVAS
;; A buffer per agent session, "Agent UI: NAME" (config/agent-ui/canvas.el):
;; its elements in the order shown, each redrawn in place when it changes,
;; `agent-ui-redraw-delay' after (updates within it drawn together); animated
;; ones every `agent-ui-animation-interval'. It opens in a tiled pane (one of
;; tiling's applications, config/tiling.el) when an element is added while
;; it's in no window, without taking the focus. In it: g r redraws it, q hides it. At
;; most `agent-ui-max-elements'.

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
;; Claude Code's system prompt in agent-shell (config/agent-shell/context.el)
;; gets a paragraph on the canvas (`agent-ui-agent-context'): what it's for, the
;; command, and the skill to read before using it (skills/agent-ui/SKILL.md:
;; its types, with examples). Only while Emacs runs a server.

;; ====== KEY BINDINGS ======

;; THE CANVAS (see above): Vim's keys, as Doom's other buffers'.
(map! :map agent-ui-canvas-mode-map
      :n "q"  #'quit-window
      :n "gr" #'agent-ui-canvas-redraw
      :n "R"  #'agent-ui-review
      :n "a"  #'agent-ui-send-element
      :n "b"  #'agent-ui-report-bug
      :n "s"  #'agent-ui-table-sort)

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
(load! "agent-ui/workspaces")
(load! "agent-ui/persist")
;; What the elements that ask share (picking, a note, the answer).
(load! "agent-ui/ask")
;; The element types, a file each in agent-ui/elements/.
(load! "agent-ui/elements")
(load! "agent-ui/staging")
(load! "agent-ui/review")
(load! "agent-ui/source")
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

;; ISSUES (the issues element): opened in Emacs's issue view (config/beads.el),
;; and boards refreshed when this config refreshes the issue lists (after the
;; agent's bd commands, config/agent-shell/beads.el).
(defun +my/agent-ui-open-issue (id dir)
  "Open issue ID of DIR's project in Beads' issue view."
  (let ((default-directory dir))
    (if-let* (((fboundp 'beads-detail-open))
              (json (with-temp-buffer
                      (and (eql 0 (call-process "bd" nil '(t nil) nil "show" id "--json"))
                           (buffer-string))))
              (issue (ignore-errors (json-parse-string json :object-type 'alist :array-type 'list))))
        ;; bd show --json: an array of one issue.
        (beads-detail-open (if (and (consp issue) (consp (car issue)) (consp (caar issue))) (car issue) issue))
      (agent-ui-issues-show id dir))))

(setq agent-ui-open-issue-function #'+my/agent-ui-open-issue)

(with-eval-after-load 'agent-shell
  (advice-add '+my/agent-shell-beads-refresh :after
              (lambda (root) (agent-ui-issues-refresh root))
              '((name . agent-ui-issues))))

;; WHAT THE AGENT IS TOLD (see above), after what's there (the theme's line, the
;; project's issues).
(add-hook '+my/agent-shell-claude-context-functions #'agent-ui-agent-context t)
