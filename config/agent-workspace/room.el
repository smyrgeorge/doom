;;; $DOOMDIR/config/agent-workspace/room.el -*- lexical-binding: t; -*-
;; The room: one chat for the whole crew. Loaded from
;; config/agent-workspace.el, after app.el. No Doom here.
;;
;; Two windows, the app's right column (78 columns; at the bottom, under the
;; stage, in a frame under 200 columns or by `agent-workspace-room-side'), or
;; the whole stage (the room alone: 2; the stage again: 1):
;; - the feed: a line for each thing that matters, its time, its agent's
;;   avatar and name: a turn's answer (its first lines; RET opens its pane),
;;   an issue filed, claimed or closed by an agent (from its bd commands), an
;;   agent joining, going home, started again, renamed, leaving, stuck, a hand
;;   raised, your messages and where they went. At its end it follows new
;;   lines; scrolled up, it stays. F filters it: all, hands only, the selected
;;   agent's.
;; - the compose line below it, a window of its own (it never scrolls away):
;;   "#ada fix the test" to ada, "#builders ..." to the first free builder (else
;;   queued for the first), "#all ..." to everyone, no # to the selected agent
;;   (its "→ ada" before the text). Busy, an agent gets it after its turn
;;   (agent-shell's queue), said. TAB completes #, M-p / M-n your messages,
;;   typing "#name " selects that agent.
;;
;; Kept per project, per machine: .agent-shell/agent-workspace/room.jsonl, its
;; last `agent-workspace-room-kept' entries.
;;
;; Agents don't talk to each other there (doom-ymv): only you, and them to you.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'map)

(declare-function agent-shell-subscribe-to "agent-shell")

;; ====== VARIABLES ======

(defcustom agent-workspace-room-side 'right
  "Where the room goes: `right' (a column, in frames 200 columns wide or
more; at the bottom in narrower ones), or `bottom'."
  :type '(choice (const right) (const bottom))
  :group 'agent-workspace)

(defcustom agent-workspace-room-width 78
  "The room's width, a column on the right."
  :type 'natnum
  :group 'agent-workspace)

(defcustom agent-workspace-room-height 16
  "The room's height, at the bottom."
  :type 'natnum
  :group 'agent-workspace)

(defcustom agent-workspace-room-kept 500
  "How many of the room's entries are kept, per project."
  :type 'natnum
  :group 'agent-workspace)

(defvar agent-workspace-room-mode-map (make-sparse-keymap)
  "Keys in the room's feed (set in config/agent-workspace.el).")

(defvar agent-workspace-compose-mode-map (make-sparse-keymap)
  "Keys in the room's compose line (set in config/agent-workspace.el).")

(defvar-local agent-workspace--room-project nil "In the room's buffers: its project.")
(defvar-local agent-workspace--room-entries nil "In the feed: its entries, the oldest first.")
(defvar-local agent-workspace--room-filter nil "In the feed: nil (all), `hands', or an agent's name.")
(defvar-local agent-workspace--compose-history nil "In the compose line: what you sent, the latest first.")
(defvar-local agent-workspace--compose-index -1 "In the compose line: where M-p / M-n are in it.")
(defvar-local agent-workspace--compose-prompt nil "In the compose line: its prompt, an overlay.")
(defvar-local agent-workspace--turn-text nil "In an agent's session: its turn's answer so far.")

(defconst agent-workspace--room-indent (+ 1 5 1 2 1 8 1)
  "Where an entry's text starts: after its time, avatar and name.")

;; ====== ITS BUFFERS ======

(define-derived-mode agent-workspace-room-mode special-mode "Room"
  "The room's feed: what the crew does and says."
  (setq-local mode-line-format nil
              tab-line-exclude t
              truncate-lines nil
              word-wrap t
              header-line-format '(:eval (agent-workspace--room-header))))

(define-derived-mode agent-workspace-compose-mode text-mode "Compose"
  "The room's compose line: RET sends, #name picks who to."
  (setq-local mode-line-format nil
              tab-line-exclude t
              truncate-lines nil
              word-wrap t
              header-line-format '(:eval (agent-workspace--compose-header))
              completion-at-point-functions (list #'agent-workspace--compose-capf))
  (add-hook 'post-command-hook #'agent-workspace--compose-typed nil t))

(defun agent-workspace--room-name (project what)
  "The name of PROJECT's room's WHAT buffer."
  (format "*%s · %s*" what (file-name-nondirectory (directory-file-name project))))

(defun agent-workspace--room-buffer (project)
  "PROJECT's room's feed (made the first time, its kept entries read)."
  (let ((name (agent-workspace--room-name project "room")))
    (or (seq-find (lambda (buffer) (and (equal (buffer-local-value 'agent-workspace--room-project buffer)
                                               (agent-workspace--root project))
                                        (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-room-mode)))
                  (agent-workspace--app-buffers project))
        (with-current-buffer (generate-new-buffer name)
          (agent-workspace-room-mode)
          (setq agent-workspace--room-project (agent-workspace--root project)
                default-directory (agent-workspace--root project)
                agent-workspace--room-entries (agent-workspace--room-load project))
          (agent-workspace--app-buffer-add project (current-buffer))
          (agent-workspace--room-redraw project)
          (current-buffer)))))

(defun agent-workspace--compose-buffer (project)
  "PROJECT's room's compose line (made the first time)."
  (let ((name (agent-workspace--room-name project "compose")))
    (or (seq-find (lambda (buffer) (and (equal (buffer-local-value 'agent-workspace--room-project buffer)
                                               (agent-workspace--root project))
                                        (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-compose-mode)))
                  (agent-workspace--app-buffers project))
        (with-current-buffer (generate-new-buffer name)
          (agent-workspace-compose-mode)
          (setq agent-workspace--room-project (agent-workspace--root project)
                default-directory (agent-workspace--root project))
          (agent-workspace--app-buffer-add project (current-buffer))
          (agent-workspace--compose-prompt-draw)
          (current-buffer)))))

;; ====== KEPT ======

(defun agent-workspace--room-file (project)
  "Where PROJECT's room is kept."
  (expand-file-name ".agent-shell/agent-workspace/room.jsonl" project))

(defun agent-workspace--room-load (project)
  "PROJECT's room's kept entries (the last `agent-workspace-room-kept'), the
file trimmed to them if it's longer."
  (let ((file (agent-workspace--room-file project)))
    (when (file-readable-p file)
      (let* ((lines (with-temp-buffer
                      (insert-file-contents file)
                      (split-string (buffer-string) "\n" t)))
             (kept (last lines agent-workspace-room-kept)))
        (when (> (length lines) (length kept))
          (with-temp-file file (insert (string-join kept "\n") "\n")))
        (delq nil (mapcar (lambda (line)
                            (ignore-errors
                              (let ((entry (json-parse-string line :object-type 'plist :null-object nil
                                                              :false-object nil)))
                                (plist-put entry :kind (intern (or (plist-get entry :kind) "note"))))))
                          kept))))))

(defun agent-workspace--room-keep (project entry)
  "ENTRY appended to PROJECT's kept room."
  (let ((file (agent-workspace--room-file project)))
    (ignore-errors
      (make-directory (file-name-directory file) t)
      (let ((coding-system-for-write 'utf-8-unix))
        (write-region (concat (json-serialize
                               (cl-loop for (key value) on entry by #'cddr
                                        unless (memq key '(:answered))
                                        append (list key (if (symbolp value) (symbol-name value) value))))
                              "\n")
                      nil file t 'silent)))))

;; ====== THE FEED ======

(defun agent-workspace-room-post (project &rest entry)
  "Post ENTRY in PROJECT's room: a plist, :kind (you, reply, issue, joined,
home, restarted, renamed, left, stuck, hand, note, event, event-done),
:agent (its name, an event's source), :text, :to (who a message of yours or
an event went to), :event (an event's id)."
  (let ((entry (append (list :time (format-time-string "%H:%M")) entry)))
    (agent-workspace--room-keep project entry)
    (when-let* ((app (agent-workspace--app project))
                (buffer (seq-find (lambda (buffer) (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-room-mode))
                                  (agent-workspace--app-buffers project))))
      (with-current-buffer buffer
        (setq agent-workspace--room-entries
              (last (append agent-workspace--room-entries (list entry)) agent-workspace-room-kept)))
      (agent-workspace--room-redraw project))
    entry))

(defun agent-workspace--room-shown-p (entry filter)
  "Non-nil if ENTRY is shown with FILTER."
  (pcase filter
    ('nil t)
    ('hands (eq (plist-get entry :kind) 'hand))
    (_ (or (equal (plist-get entry :agent) filter) (equal (plist-get entry :to) filter)))))

(defun agent-workspace--room-entry-lines (project entry _width)
  "ENTRY's lines in PROJECT's room (wrapped by Emacs, under its text)."
  (let* ((name (plist-get entry :agent))
         (agent (and name (agent-workspace-agent name project)))
         (kind (plist-get entry :kind))
         (who (cond (agent (concat (agent-workspace-agent-avatar agent) " "
                                   (agent-workspace--pad (agent-workspace-agent-name-text agent) 8)))
                    ((eq kind 'you) (concat "   " (agent-workspace--pad (propertize "you" 'face 'bold) 8)))
                    (name (concat (propertize (concat "▌" (upcase (substring name 0 1))) 'face 'shadow) " "
                                  (agent-workspace--pad (propertize name 'face 'shadow) 8)))
                    (t (make-string 11 ?\s))))
         (lead (pcase kind
                 ('you (concat (propertize "→ " 'face 'shadow)
                               (propertize (or (plist-get entry :to) "") 'face 'bold) " "))
                 ('reply (propertize "↳ " 'face 'shadow))
                 ('hand (agent-workspace-glyph 'hand 'warning))
                 ('stuck (agent-workspace-glyph 'stuck 'error))
                 ('issue (propertize "◆ " 'face 'shadow))
                 ('event (concat (propertize "✉ → " 'face 'shadow)
                                 (propertize (or (plist-get entry :to) "") 'face 'bold) " "))
                 ('event-done (propertize "✉ " 'face 'shadow))
                 (_ "")))
         (text (plist-get entry :text))
         (text (pcase kind
                 ((or 'joined 'home 'restarted 'renamed 'left 'note 'event-done) (propertize text 'face 'shadow))
                 ('stuck (propertize text 'face 'error))
                 ('hand (propertize text 'face 'warning))
                 (_ text)))
         (first (concat " " (propertize (or (plist-get entry :time) "") 'face 'shadow) " " who " " lead text)))
    (delq nil
          (list (propertize first 'agent-workspace-entry entry
                            'wrap-prefix (make-string agent-workspace--room-indent ?\s))
                ;; A hand's buttons, while it's raised (hands.el).
                (and (eq kind 'hand) (fboundp 'agent-workspace--room-hand-line)
                     (agent-workspace--room-hand-line project entry))
                ;; A queued event's buttons, while it waits (inbox.el).
                (and (eq kind 'event) (fboundp 'agent-workspace--room-event-line)
                     (agent-workspace--room-event-line project entry))))))

(defun agent-workspace--pad (text width)
  "TEXT padded to WIDTH columns."
  (concat text (make-string (max 0 (- width (string-width text))) ?\s)))

(defun agent-workspace--room-redraw (project)
  "PROJECT's room's feed drawn again: following its end where it was at its
end, kept where it was scrolled up."
  (when-let* ((buffer (seq-find (lambda (buffer) (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-room-mode))
                                (agent-workspace--app-buffers project))))
    (with-current-buffer buffer
      (let* ((windows (get-buffer-window-list buffer nil t))
             (following (or (null windows)
                            (seq-some (lambda (window) (>= (window-point window) (1- (point-max)))) windows)))
             (starts (mapcar (lambda (window) (cons window (window-start window))) windows))
             (inhibit-read-only t)
             (width (if windows (window-body-width (car windows)) agent-workspace-room-width)))
        (erase-buffer)
        (dolist (entry agent-workspace--room-entries)
          (when (agent-workspace--room-shown-p entry agent-workspace--room-filter)
            (dolist (line (agent-workspace--room-entry-lines project entry width))
              (insert line "\n"))))
        (if following
            (dolist (window windows)
              (set-window-point window (point-max))
              (with-selected-window window
                (goto-char (point-max))
                (recenter -1)))
          (pcase-dolist (`(,window . ,start) starts)
            (set-window-start window (min start (point-max)) t)))))))

(defun agent-workspace--room-header ()
  "The feed's header line: ROOM, its filter."
  (string-replace
   "%" "%%"
   (concat " " (propertize "ROOM" 'face 'bold) "  "
           (propertize (pcase agent-workspace--room-filter
                         ('nil "all")
                         ('hands "raised hands only")
                         (name (concat name "'s only")))
                       'face 'shadow)
           (propertize "   F: filter" 'face 'shadow))))

;; ====== WHAT GOES IN IT ======

(defun agent-workspace--room-changed-h (agent what)
  "AGENT's WHAT, said in its room. In `agent-workspace-change-functions'."
  (let ((project (agent-workspace-agent-project agent))
        (name (agent-workspace-agent-name agent)))
    (pcase what
      ('created
       (agent-workspace-room-post project :kind 'joined :agent name
                                  :again (and (bound-and-true-p agent-workspace--crew-loading) t)
                                  :text (format "%s (%s) %s · %s ⑂ %s" name (agent-workspace-agent-role agent)
                                                (if (bound-and-true-p agent-workspace--crew-loading)
                                                    "back, fresh" "joined")
                                                (directory-file-name
                                                 (file-relative-name (or (agent-workspace-agent-worktree agent) project)
                                                                     project))
                                                (or (agent-workspace-agent-branch agent) "")))
       (agent-workspace--compose-prompt-draw project))
      ('renamed (agent-workspace-room-post project :kind 'renamed :agent name :text (format "now %s" name)))
      ('forgotten (agent-workspace-room-post project :kind 'left :agent name :text "left the crew"))
      ('session
       (when (agent-workspace--room-seen-p agent)
         (agent-workspace-room-post project :kind 'restarted :agent name :text "started again, fresh"))))))

(defvar agent-workspace--room-sessions (make-hash-table :test #'eq :weakness 'key)
  "The agents that had a session already: a new one is said as started again.")

(defun agent-workspace--room-seen-p (agent)
  "Non-nil if AGENT had a session before (noted now)."
  (prog1 (gethash agent agent-workspace--room-sessions)
    (puthash agent t agent-workspace--room-sessions)))

(defun agent-workspace--room-state-h (agent old new)
  "AGENT's state changed: a hand raised, gone home, stuck, said. In
`agent-workspace-state-change-functions'."
  (let ((project (agent-workspace-agent-project agent))
        (name (agent-workspace-agent-name agent)))
    (pcase new
      ('hand (agent-workspace-room-post project :kind 'hand :agent name
                                        :text (agent-workspace-state-text agent)
                                        :ask (and (fboundp 'agent-workspace--ask-key)
                                                  (agent-workspace--ask-key (agent-workspace-agent-ask agent)))))
      ('home (unless (eq old 'home)
               (agent-workspace-room-post project :kind 'home :agent name :text "went home")))
      (_ (when (and (eq old 'hand) (agent-workspace--app project))
           ;; A hand answered (here or elsewhere): its buttons go.
           (agent-workspace--room-redraw project))))
    (pcase new
      ('stuck (agent-workspace-room-post project :kind 'stuck :agent name
                                         :text (concat "stuck"
                                                       (if-let* ((error (agent-workspace-agent-error agent)))
                                                           (concat ": " (car (split-string error "\n")))
                                                         "")))))))

(defun agent-workspace--room-watch (agent buffer)
  "AGENT's session BUFFER followed: its turn's answer, its bd commands, said
in its room. In `agent-workspace-session-functions'."
  (let ((project (agent-workspace-agent-project agent))
        (name (agent-workspace-agent-name agent)))
    (agent-shell-subscribe-to
     :shell-buffer buffer
     :on-event
     (lambda (event)
       (pcase (alist-get :event event)
         ('input-submitted
          (setq agent-workspace--turn-text nil))
         ('agent-message-chunk
          (when-let* ((chunk (map-nested-elt event '(:data :text-chunk))))
            (setq agent-workspace--turn-text (concat agent-workspace--turn-text chunk))))
         ('turn-complete
          (let ((text (string-trim (or agent-workspace--turn-text ""))))
            (setq agent-workspace--turn-text nil)
            (unless (string-empty-p text)
              (agent-workspace-room-post project :kind 'reply :agent name
                                         :text (agent-workspace--first-lines text)))))
         ('tool-call-update
          (let* ((tool-call (map-nested-elt event '(:data :tool-call)))
                 (command (map-elt tool-call :command)))
            (when (and (equal (map-elt tool-call :status) "completed") (stringp command))
              (when-let* ((said (agent-workspace--bd-said command)))
                (agent-workspace-room-post project :kind 'issue :agent name :text said))))))))))

(defun agent-workspace--first-lines (text)
  "TEXT's first lines, on one: at most 160 characters."
  (let* ((lines (seq-take (seq-remove #'string-empty-p (mapcar #'string-trim (split-string text "\n"))) 3))
         (line (string-join lines " ")))
    (if (> (length line) 160) (concat (substring line 0 159) "…") line)))

(defun agent-workspace--bd-said (command)
  "What COMMAND, an agent's shell command, did to an issue, in words, or
nil: \"closed doom-a1b\", \"claimed doom-a1b\", \"filed: TITLE\"."
  (cond
   ((string-match "\\(?:\\`\\|[;&|(]\\s-*\\)bd close\\s-+\\([^ ;&|]+\\)" command)
    (format "closed %s" (match-string 1 command)))
   ((string-match "\\(?:\\`\\|[;&|(]\\s-*\\)bd update\\s-+\\([^ ;&|]+\\).*--claim" command)
    (format "claimed %s" (match-string 1 command)))
   ((string-match "\\(?:\\`\\|[;&|(]\\s-*\\)bd create\\b.*--title[= ]\\(?:\"\\([^\"]+\\)\"\\|'\\([^']+\\)'\\|\\([^ ]+\\)\\)" command)
    (format "filed: %s" (or (match-string 1 command) (match-string 2 command) (match-string 3 command))))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--room-changed-h)
(add-hook 'agent-workspace-state-change-functions #'agent-workspace--room-state-h)
(add-hook 'agent-workspace-session-functions #'agent-workspace--room-watch)
(add-hook 'agent-workspace-layout-functions #'agent-workspace--compose-prompt-draw)

;; ====== THE COMPOSE LINE ======

(defun agent-workspace--compose-target (project)
  "Who a message without # goes to: PROJECT's selected agent."
  (when-let* ((app (agent-workspace--app project)))
    (agent-workspace--app-selected app)))

(defun agent-workspace--compose-prompt-draw (&optional project)
  "The compose line's prompt drawn again: \"→ ada \" before its text."
  (when-let* ((buffer (if project
                          (seq-find (lambda (buffer) (eq (buffer-local-value 'major-mode buffer)
                                                         'agent-workspace-compose-mode))
                                    (agent-workspace--app-buffers project))
                        (current-buffer))))
    (with-current-buffer buffer
      (unless (overlayp agent-workspace--compose-prompt)
        (setq agent-workspace--compose-prompt (make-overlay (point-min) (point-min) nil nil t)))
      (move-overlay agent-workspace--compose-prompt (point-min) (point-min))
      (let ((target (agent-workspace--compose-target agent-workspace--room-project)))
        (overlay-put agent-workspace--compose-prompt 'before-string
                     (concat " " (propertize "→ " 'face 'shadow)
                             (if target (agent-workspace-agent-name-text target) (propertize "nobody yet" 'face 'shadow))
                             " "))))))

(defun agent-workspace--compose-header ()
  "The compose line's header line: its hints."
  (propertize "  #name  #role  #all  ·  RET send  TAB complete  M-p / M-n history" 'face 'shadow))

(defun agent-workspace--compose-typed ()
  "After a command in the compose line: \"#name \" typed selects that agent."
  (save-excursion
    (goto-char (point-min))
    (when (looking-at "#\\([a-z][a-z0-9-]*\\) ")
      (when-let* ((agent (agent-workspace-agent (match-string 1) agent-workspace--room-project)))
        (unless (eq agent (agent-workspace--compose-target agent-workspace--room-project))
          (agent-workspace-select agent)
          (agent-workspace--compose-prompt-draw))))))

(defun agent-workspace--compose-capf ()
  "Completion for # in the compose line: the agents, their roles, all."
  (when (save-excursion (skip-chars-backward "a-z0-9-") (eq (char-before) ?#))
    (let* ((end (point))
           (start (save-excursion (skip-chars-backward "a-z0-9-") (point)))
           (project agent-workspace--room-project)
           (agents (agent-workspace-agents project))
           (roles (delete-dups (mapcar (lambda (agent) (concat (agent-workspace-agent-role agent) "s")) agents))))
      (list start end (append (mapcar #'agent-workspace-agent-name agents) roles '("all"))
            :annotation-function
            (lambda (candidate)
              (if-let* ((agent (agent-workspace-agent candidate project)))
                  (format "  %s · %s" (agent-workspace-agent-role agent) (agent-workspace-state-text agent))
                (if (equal candidate "all") "  everyone" "  its first free one")))
            :exclusive 'no))))

(defun agent-workspace--recipients (project text)
  "Who TEXT goes to in PROJECT's crew, and what's left of it: (AGENTS
. MESSAGE), or (nil . WHY)."
  (let ((agents (agent-workspace--ordered project)))
    (if (string-match "\\`#\\([a-z][a-z0-9-]*\\)\\s-*" text)
        (let ((name (match-string 1 text))
              (message (string-trim (substring text (match-end 0)))))
          (cond
           ((equal name "all") (cons (seq-filter #'agent-workspace-live-p agents) message))
           ((agent-workspace-agent name project) (cons (list (agent-workspace-agent name project)) message))
           ((let ((role (string-remove-suffix "s" name)))
              (when-let* ((of (seq-filter (lambda (agent) (equal (agent-workspace-agent-role agent) role)) agents)))
                (cons (list (or (seq-find (lambda (agent) (memq (agent-workspace-agent-state agent) '(desk done))) of)
                                (seq-find #'agent-workspace-live-p of)
                                (car of)))
                      message))))
           (t (cons nil (format "No agent or role named %s" name)))))
      (if-let* ((target (agent-workspace--compose-target project)))
          (cons (list target) (string-trim text))
        (cons nil "No agent yet: c makes one")))))

(defun agent-workspace-compose-send ()
  "Send what's in the compose line (see the top of this file)."
  (interactive)
  (let* ((project agent-workspace--room-project)
         (text (string-trim (buffer-string))))
    (unless (string-empty-p text)
      (pcase-let ((`(,agents . ,message) (agent-workspace--recipients project text)))
        (cond
         ((null agents) (user-error "%s" message))
         ((string-empty-p message) (user-error "Nothing to send"))
         (t
          (let ((how (mapcar (lambda (agent)
                               (cons agent (condition-case err
                                               (agent-workspace-send agent message :submit t)
                                             (user-error (error-message-string err)))))
                             agents)))
            (agent-workspace-room-post
             project :kind 'you :to (if (cdr agents) "all" (agent-workspace-agent-name (car agents)))
             :text (concat message
                           (let ((queued (seq-filter (lambda (entry) (eq (cdr entry) 'queued)) how))
                                 (failed (seq-filter (lambda (entry) (stringp (cdr entry))) how)))
                             (concat
                              (if queued (format "  (queued for %s: busy)"
                                                 (mapconcat (lambda (e) (agent-workspace-agent-name (car e))) queued ", "))
                                "")
                              (if failed (format "  (not sent: %s)" (mapconcat #'cdr failed "; ")) "")))))
            (push text agent-workspace--compose-history)
            (setq agent-workspace--compose-index -1)
            (when (= (length agents) 1) (agent-workspace-select (car agents)))
            (let ((inhibit-read-only t)) (erase-buffer))
            (agent-workspace--compose-prompt-draw))))))))

(defun agent-workspace-compose-previous (&optional n)
  "Your N-th previous message (M-p)."
  (interactive "p")
  (let ((i (max -1 (min (1- (length agent-workspace--compose-history))
                        (+ agent-workspace--compose-index (or n 1))))))
    (setq agent-workspace--compose-index i)
    (erase-buffer)
    (when (>= i 0) (insert (nth i agent-workspace--compose-history)))))

(defun agent-workspace-compose-next (&optional n)
  "Your N-th next message (M-n)."
  (interactive "p")
  (agent-workspace-compose-previous (- (or n 1))))

;; ====== ITS COMMANDS ======

(defun agent-workspace-room-compose (&optional to)
  "The cursor in the room's compose line (TO: \"#NAME \" in it)."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app)))
    (unless (get-buffer-window (agent-workspace--compose-buffer project))
      (setf (agent-workspace--app-view app) 'stage)
      (agent-workspace-layout app))
    (select-window (get-buffer-window (agent-workspace--compose-buffer project)))
    (when (and to (= (point-min) (point-max)))
      (insert "#" to " "))
    (goto-char (point-max))
    (when (fboundp 'evil-insert-state) (evil-insert-state))))

(defun agent-workspace-talk ()
  "Talk to the agent here, in the room (#NAME in its compose line)."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (agent-workspace-select agent)
    (agent-workspace-room-compose (agent-workspace-agent-name agent))))

(defun agent-workspace-room-open ()
  "RET in the feed: the agent of the line at point, its pane open."
  (interactive)
  (when-let* ((entry (get-text-property (point) 'agent-workspace-entry))
              (agent (agent-workspace-agent (or (plist-get entry :agent) (plist-get entry :to))
                                            agent-workspace--room-project)))
    (agent-workspace-select agent t)))

(defun agent-workspace-room-filter ()
  "The feed filtered: all, raised hands only, the selected agent's only."
  (interactive)
  (let ((selected (agent-workspace--compose-target agent-workspace--room-project)))
    (setq agent-workspace--room-filter
          (pcase agent-workspace--room-filter
            ('nil 'hands)
            ('hands (and selected (agent-workspace-agent-name selected)))
            (_ nil)))
    (agent-workspace--room-redraw agent-workspace--room-project)
    (force-mode-line-update)))

(defun agent-workspace-view-stage ()
  "The stage and the room (1)."
  (interactive)
  (let ((app (agent-workspace--here-or-error)))
    (setf (agent-workspace--app-view app) 'stage)
    (agent-workspace-layout app)))

(defun agent-workspace-view-room ()
  "The room alone, the whole stage's room (2)."
  (interactive)
  (let ((app (agent-workspace--here-or-error)))
    (setf (agent-workspace--app-view app) 'room)
    (agent-workspace-layout app)))

;; ====== ITS PLACE IN THE APP ======

(defun agent-workspace--room-place (app area)
  "APP's room in window AREA (the stage's): a column on the right, at the
bottom, or all of it (the room alone). The window left for the stage, or nil."
  (let* ((project (agent-workspace--app-project app))
         (alone (eq (agent-workspace--app-view app) 'room))
         (right (and (eq agent-workspace-room-side 'right)
                     (>= (window-total-width (frame-root-window)) 200)))
         (room (if alone
                   area
                 (condition-case nil
                     (if right
                         (split-window area (- agent-workspace-room-width) 'right)
                       (split-window area (- agent-workspace-room-height) 'below))
                   (error nil)))))
    (when room
      (let* ((window-min-height 2)
             (compose (condition-case nil (split-window room -3 'below) (error nil))))
        (set-window-buffer room (agent-workspace--room-buffer project))
        (dolist (parameter '(mode-line-format tab-line-format))
          (set-window-parameter room parameter 'none))
        (set-window-parameter room 'agent-workspace-room t)
        (when compose
          (set-window-buffer compose (agent-workspace--compose-buffer project))
          (dolist (parameter '(mode-line-format tab-line-format))
            (set-window-parameter compose parameter 'none))
          (set-window-parameter compose 'agent-workspace-room t))
        (agent-workspace--room-redraw project)
        (agent-workspace--compose-prompt-draw project)))
    (unless alone area)))
