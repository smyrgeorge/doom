;;; $DOOMDIR/config/agent-workspace/room.el -*- lexical-binding: t; -*-
;; The room: one chat for the whole crew. Loaded from
;; config/agent-workspace.el, after app.el. No Doom here.
;;
;; Two windows, the app's right column (78 columns; at the bottom, under the
;; stage, in a frame under 200 columns or by `agent-workspace-room-side'), or
;; the whole stage (the room alone: 2; the stage again: 1):
;; - the feed: a line for each thing that matters, its time, its agent's
;;   avatar and name: a turn's answer (its first lines; RET opens its pane),
;;   an issue filed, claimed, handed on or closed by an agent (its issues
;;   compared, fetched before and after: issues.el), an agent joining,
;;   going home, started again, renamed, leaving, stuck, a hand raised, your
;;   messages and where they went (from the compose line, or typed in an
;;   agent's session: yours too). Its cursor on its last line, it follows
;;   new lines; elsewhere (scrolled up, a line clicked), it stays
;;   where it is, its cursor on the same line. F filters it: all, hands only,
;;   the selected agent's.
;; - the compose line below it, a window of its own (it never scrolls away):
;;   "#ada fix the test" to ada, "#builders ..." to the first free builder (else
;;   queued for the first), "#all ..." to everyone, no # to the selected agent
;;   (its "→ ada" before the text). Busy, an agent gets it after its turn
;;   (agent-shell's queue), said. # at its start offers the agents, their roles
;;   and all as it's typed (Corfu; TAB completes it too), a # further on is
;;   text; M-p / M-n your messages; typing "#name " selects that agent. 3
;;   lines of text, more as its text needs them (wrapped, its newlines), its
;;   rows the feed's: up to `agent-workspace-compose-max-lines' or half the
;;   room, scrolling past them; 3 again once sent. The app's own change, not a
;;   border dragged: not laid out again for it, and a layout keeps it.
;;
;; Kept per project, per machine: .agent-shell/agent-workspace/room.jsonl, its
;; last `agent-workspace-room-kept' entries.
;;
;; Agents don't talk to each other there (doom-ymv): only you, and them to you.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'text-property-search)
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
  "The room's height, at the bottom: less in a frame too low for it and
an agent's pane above it (`agent-workspace--room-height-now'); none if not
even its least fits (2 shows it alone)."
  :type 'natnum
  :group 'agent-workspace)

(defconst agent-workspace--room-least 8
  "The room's least height at the bottom: its feed's 4 rows and its compose
line.")

(defconst agent-workspace--stage-least 12
  "The rows the stage keeps for an agent's open pane, above the room at
the bottom.")

(defun agent-workspace--room-height-now (app area)
  "The room's height at the bottom of window AREA (APP's stage): its own,
less if the stage would keep fewer rows than its bars and an open pane
need, nil if not even `agent-workspace--room-least' fits."
  (let* ((bars (max 0 (1- (length (agent-workspace-agents (agent-workspace--app-project app))))))
         (room (min agent-workspace-room-height
                    (- (window-total-height area) bars agent-workspace--stage-least))))
    (and (>= room agent-workspace--room-least) room)))

(defcustom agent-workspace-compose-lines 3
  "The compose line's lines of text, at least: it grows as its text needs."
  :type 'natnum
  :group 'agent-workspace)

(defcustom agent-workspace-compose-max-lines 10
  "The most lines of text the compose line grows to (half the room at most):
past them, it scrolls."
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
(defvar-local agent-workspace--room-folded nil "In the feed: the threads folded (their ids).")
(defvar-local agent-workspace--room-drawn nil "In the feed: its entries when it was last drawn.")
(defvar-local agent-workspace--room-soon nil
  "In the feed: a timer drawing it all again in a moment (changes in a
burst: once); its text until then as it was, a post appended to it.")
(defvar-local agent-workspace--compose-history nil "In the compose line: what you sent, the latest first.")
(defvar-local agent-workspace--compose-index -1 "In the compose line: where M-p / M-n are in it.")
(defvar-local agent-workspace--compose-prompt nil "In the compose line: its prompt, an overlay.")
(defvar-local agent-workspace--turn-text nil "In an agent's session: its turn's answer so far.")

(defconst agent-workspace--room-indent (+ 1 5 1 2 1 8 1)
  "Where an entry's text starts: after its time, avatar and name.")

;; ====== ITS BUFFERS ======

(define-derived-mode agent-workspace-room-mode special-mode "Room"
  "The room's feed: what the crew does and says."
  ;; Drawn again and again: no undo kept of it.
  (buffer-disable-undo)
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
  (add-hook 'post-command-hook #'agent-workspace--compose-typed nil t)
  (add-hook 'corfu-mode-hook #'agent-workspace--compose-corfu nil t))

(defun agent-workspace--room-name (project what)
  "The name of PROJECT's room's WHAT buffer."
  (format "*%s · %s*" what (file-name-nondirectory (directory-file-name project))))

(defun agent-workspace--room-buffer (project)
  "PROJECT's room's feed (made the first time, its kept entries read), drawn
as it is now (a redraw to come done)."
  (let ((name (agent-workspace--room-name project "room")))
    (or (when-let* ((buffer (seq-find (lambda (buffer) (and (equal (buffer-local-value 'agent-workspace--room-project buffer)
                                                                   (agent-workspace--root project))
                                                            (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-room-mode)))
                                      (agent-workspace--app-buffers project))))
          (when (buffer-local-value 'agent-workspace--room-soon buffer)
            (agent-workspace--room-redraw project))
          buffer)
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

(defvar agent-workspace--room-id-floors (make-hash-table :test #'equal)
  "A project's highest event and message ids in its kept room, as this
Emacs first read them: (:event N :message M).")

(defun agent-workspace-room-id-floor (project key)
  "The highest id of KEY (:event, :message) in PROJECT's kept room as this
Emacs first read it, else 0: a new event's or message's goes above it, so
an old line (its buttons drawn by id) never names a new one."
  (let* ((root (agent-workspace--root project))
         (floors (or (gethash root agent-workspace--room-id-floors)
                     (puthash root (agent-workspace--room-id-scan project) agent-workspace--room-id-floors))))
    (or (plist-get floors key) 0)))

(defun agent-workspace--room-id-scan (project)
  "PROJECT's kept room's highest event and message ids: (:event N :message M)."
  (let ((event 0) (message 0)
        (file (agent-workspace--room-file project)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        ;; Keys only: a quote in a text is \" in JSON.
        (while (re-search-forward "\"\\(event\\|message\\)\":\\([0-9]+\\)" nil t)
          (let ((n (string-to-number (match-string 2))))
            (if (equal (match-string 1) "event")
                (setq event (max event n))
              (setq message (max message n)))))))
    (list :event event :message message)))

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
      (let* ((before (buffer-local-value 'agent-workspace--room-entries buffer))
             (after (last (append before (list entry)) agent-workspace-room-kept))
             (dropped (seq-take before (- (1+ (length before)) (length after)))))
        (with-current-buffer buffer
          (setq agent-workspace--room-entries after))
        ;; Its lines appended, nothing above them changed; else drawn again
        ;; in a moment.
        (unless (agent-workspace--room-append project buffer entry before dropped)
          (agent-workspace--room-redraw-soon project))))
    entry))

(defun agent-workspace--room-append (project buffer entry before dropped)
  "ENTRY, just posted in PROJECT's feed BUFFER, its lines appended, those of
DROPPED (the oldest, gone from it) deleted; each window following the end
follows it. Non-nil if done; nil, the feed must be drawn again: drawn from
other entries than BEFORE (the feed's before ENTRY), or a redraw to come,
ENTRY in a thread folded, a thread among DROPPED."
  (with-current-buffer buffer
    (let ((thread (plist-get entry :thread)))
      (when (and (not agent-workspace--room-soon)
                 (eq agent-workspace--room-drawn before)
                 (not (and thread (member thread agent-workspace--room-folded)))
                 (not (seq-some (lambda (old) (plist-get old :thread)) dropped)))
        (let* ((inhibit-read-only t)
               (windows (get-buffer-window-list buffer nil t))
               (following (seq-filter (lambda (window) (agent-workspace--room-last-line-p (window-point window)))
                                      windows)))
          ;; The oldest gone: their lines, at the top.
          (when dropped
            (save-excursion
              (goto-char (point-min))
              (while (and (< (point) (point-max))
                          (memq (get-text-property (point) 'agent-workspace-entry) dropped))
                (forward-line 1))
              (delete-region (point-min) (point))))
          (when (agent-workspace--room-shown-p entry agent-workspace--room-filter)
            (save-excursion
              (goto-char (point-max))
              (let ((start (point)))
                (dolist (line (agent-workspace--room-entry-lines
                               project entry (if windows (window-body-width (car windows)) agent-workspace-room-width)))
                  (insert line "\n"))
                (put-text-property start (point) 'agent-workspace-entry entry))))
          (setq agent-workspace--room-drawn agent-workspace--room-entries)
          (dolist (window following)
            (set-window-point window (point-max))
            (with-selected-window window
              (goto-char (point-max))
              (recenter -1)))
          t)))))

(defun agent-workspace--room-shown-p (entry filter)
  "Non-nil if ENTRY is shown with FILTER."
  (pcase filter
    ('nil t)
    ('hands (eq (plist-get entry :kind) 'hand))
    (_ (or (equal (plist-get entry :agent) filter) (equal (plist-get entry :to) filter)))))

(defun agent-workspace--room-entry-lines (project entry _width &optional more)
  "ENTRY's lines in PROJECT's room (wrapped by Emacs, under its text). MORE:
its thread folded, how many lines of it it stands for."
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
                 ('offer (propertize "◆ " 'face 'shadow))
                 (_ "")))
         (text (plist-get entry :text))
         (text (pcase kind
                 ((or 'joined 'home 'restarted 'renamed 'left 'note 'event-done) (propertize text 'face 'shadow))
                 ('stuck (propertize text 'face 'error))
                 ('hand (propertize text 'face 'warning))
                 (_ text)))
         ;; The issue its sender is on (a message between agents).
         (text (if-let* ((issue (plist-get entry :issue)))
                   (concat text (propertize (concat " · " issue) 'face 'shadow))
                 text))
         (text (if more
                   (concat text (propertize (format "  ▸ %d more (TAB)" more) 'face 'shadow))
                 text))
         (first (concat " " (propertize (or (plist-get entry :time) "") 'face 'shadow) " " who " " lead text)))
    (delq nil
          (list (propertize first 'agent-workspace-entry entry
                            'wrap-prefix (make-string agent-workspace--room-indent ?\s))
                ;; A hand's buttons, while it's raised (hands.el).
                (and (eq kind 'hand) (fboundp 'agent-workspace--room-hand-line)
                     (agent-workspace--room-hand-line project entry))
                ;; A ready issue offered to a free agent (handover.el).
                (and (eq kind 'offer) (fboundp 'agent-workspace--room-offer-line)
                     (agent-workspace--room-offer-line project entry))
                ;; A queued event's buttons, while it waits (inbox.el).
                (and (eq kind 'event) (fboundp 'agent-workspace--room-event-line)
                     (agent-workspace--room-event-line project entry))))))

(defun agent-workspace--pad (text width)
  "TEXT padded to WIDTH columns."
  (concat text (make-string (max 0 (- width (string-width text))) ?\s)))

(defun agent-workspace--room-redraw (project)
  "PROJECT's room's feed drawn again. Each window showing it: its cursor on
the last line, it follows the end; else it stays where it was, its start
and its cursor on the same lines, kept by their entries (positions shift:
the oldest entries dropped, a thread folded, a hand's buttons gone)."
  (when-let* ((buffer (seq-find (lambda (buffer) (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-room-mode))
                                (agent-workspace--app-buffers project))))
    (with-current-buffer buffer
      (when (timerp agent-workspace--room-soon) (cancel-timer agent-workspace--room-soon))
      (setq agent-workspace--room-soon nil)
      (let* ((windows (get-buffer-window-list buffer nil t))
             (places (mapcar (lambda (window)
                               (list window
                                     (agent-workspace--room-last-line-p (window-point window))
                                     (agent-workspace--room-mark (window-start window))
                                     (agent-workspace--room-mark (window-point window))))
                             windows))
             (drawn (make-hash-table :test #'eq))
             (inhibit-read-only t)
             (width (if windows (window-body-width (car windows)) agent-workspace-room-width)))
        (erase-buffer)
        (let ((seen nil))
          (dolist (entry agent-workspace--room-entries)
            (when (agent-workspace--room-shown-p entry agent-workspace--room-filter)
              (let* ((thread (plist-get entry :thread))
                     (folded (and thread (member thread agent-workspace--room-folded)))
                     (start (point)))
                ;; A folded thread: its first line only, saying how many more.
                (unless (and folded (member thread seen))
                  (when thread (push thread seen))
                  (dolist (line (agent-workspace--room-entry-lines
                                 project entry width
                                 (and folded
                                      (1- (seq-count (lambda (other) (equal (plist-get other :thread) thread))
                                                     agent-workspace--room-entries)))))
                    (insert line "\n"))
                  ;; Each of its lines carries it: where a window is, kept by it.
                  (put-text-property start (point) 'agent-workspace-entry entry)
                  (puthash entry (cons start (point)) drawn))))))
        (setq agent-workspace--room-drawn agent-workspace--room-entries)
        (pcase-dolist (`(,window ,following ,start ,point) places)
          (if following
              (progn
                (set-window-point window (point-max))
                (with-selected-window window
                  (goto-char (point-max))
                  (recenter -1)))
            ;; Both put back, its start forced: redisplay has no reason to
            ;; move it (its cursor is on the screen).
            (set-window-point window (agent-workspace--room-find point drawn))
            (set-window-start window (agent-workspace--room-find start drawn))))))))

(defun agent-workspace--room-redraw-soon (project)
  "PROJECT's feed drawn again in a moment (changes in a burst, posts among
them: once); at once if it's asked for meanwhile (`agent-workspace--room-buffer')."
  (when-let* ((buffer (seq-find (lambda (buffer) (eq (buffer-local-value 'major-mode buffer) 'agent-workspace-room-mode))
                                (agent-workspace--app-buffers project))))
    (with-current-buffer buffer
      (unless agent-workspace--room-soon
        (setq agent-workspace--room-soon
              (run-at-time 0 nil (lambda ()
                                   (when (buffer-live-p buffer)
                                     (agent-workspace--room-redraw project)))))))))

(defun agent-workspace--room-last-line-p (position)
  "Non-nil if POSITION is on the feed's last line (or after it): there, a
window follows new lines."
  (>= position (save-excursion (goto-char (max (point-min) (1- (point-max))))
                               (line-beginning-position))))

(defun agent-workspace--room-mark (position)
  "POSITION in the feed, by its entry: (ENTRY OFFSET . LATER), OFFSET in
ENTRY's lines, LATER the entries after it when it was drawn; nil, none there
\(the end)."
  (when-let* ((entry (get-text-property position 'agent-workspace-entry)))
    (let ((start (if (and (> position (point-min))
                          (eq (get-text-property (1- position) 'agent-workspace-entry) entry))
                     (previous-single-property-change position 'agent-workspace-entry nil (point-min))
                   position)))
      (cl-list* entry (- position start) (cdr (memq entry agent-workspace--room-drawn))))))

(defun agent-workspace--room-find (mark drawn)
  "Where MARK (`agent-workspace--room-mark') is in the feed drawn again,
DRAWN its entries' places (ENTRY to (START . END)): the same offset in its
entry (its lines shorter now, the start of its last one); its entry gone,
the nearest one after it; none, the end."
  (pcase-let ((`(,entry ,offset . ,later) mark))
    (if-let* ((place (and entry (gethash entry drawn))))
        (let ((at (+ (car place) offset)))
          (if (< at (cdr place))
              at
            (save-excursion (goto-char (1- (cdr place))) (line-beginning-position))))
      (or (seq-some (lambda (other) (car (gethash other drawn))) later)
          (point-max)))))

(defun agent-workspace--room-header ()
  "The feed's header line: ROOM, its filter."
  (agent-workspace--percent-escaped
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
    ;; Its lines above as they read now: its name and colour, a lookup by
    ;; name (a rename, an agent gone or made), its buttons.
    (when (memq what '(created renamed forgotten colour))
      (agent-workspace--room-redraw-soon project))
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

(defun agent-workspace--room-hand-h (agent)
  "AGENT raised its hand (a request, a second one too): said, a line of its
own, its buttons under it while it's the one waiting (a hand before it, its
buttons gone). In `agent-workspace-hand-functions'."
  (let ((project (agent-workspace-agent-project agent)))
    (agent-workspace-room-post project
                               :kind 'hand :agent (agent-workspace-agent-name agent)
                               :text (agent-workspace-state-text agent)
                               :ask (and (fboundp 'agent-workspace--ask-key)
                                         (agent-workspace--ask-key (agent-workspace-agent-ask agent))))
    (agent-workspace--room-redraw-soon project)))

(add-hook 'agent-workspace-hand-functions #'agent-workspace--room-hand-h)

(defun agent-workspace--room-state-h (agent old new)
  "AGENT's state changed: a hand raised, gone home, stuck, said. In
`agent-workspace-state-change-functions'."
  (let ((project (agent-workspace-agent-project agent))
        (name (agent-workspace-agent-name agent)))
    (pcase new
      ;; A hand raised: said for each request (`agent-workspace-hand-functions').
      ('hand)
      ('home (unless (eq old 'home)
               (agent-workspace-room-post project :kind 'home :agent name :text "went home")))
      (_ (when (and (eq old 'hand) (agent-workspace--app project))
           ;; A hand answered (here or elsewhere): its buttons go.
           (agent-workspace--room-redraw-soon project))))
    (pcase new
      ('stuck (agent-workspace-room-post project :kind 'stuck :agent name
                                         :text (concat "stuck"
                                                       (if-let* ((error (agent-workspace-agent-error agent)))
                                                           (concat ": " (car (split-string error "\n")))
                                                         "")))))))

(defun agent-workspace--room-watch (agent buffer)
  "AGENT's session BUFFER followed: what you send it there (typed in it, an
answer on its canvas) and its turn's answer, said in its room. In
`agent-workspace-session-functions'."
  (let ((project (agent-workspace-agent-project agent))
        (name (agent-workspace-agent-name agent)))
    (agent-shell-subscribe-to
     :shell-buffer buffer
     :on-event
     (lambda (event)
       (pcase (alist-get :event event)
         ('input-submitted
          (setq agent-workspace--turn-text nil)
          ;; Yours, but what the app sent it (session.el): that the room
          ;; said already (the compose line's), or it isn't yours. Queued,
          ;; said as it's sent.
          (when-let* ((prompt (map-nested-elt event '(:data :prompt)))
                      ((stringp prompt))
                      (yours (agent-workspace--not-sent-by-app buffer prompt)))
            (agent-workspace-room-post project :kind 'you :to (agent-workspace-agent-name agent)
                                       :text (agent-workspace--yours-lines yours))))
         ('agent-message-chunk
          (when-let* ((chunk (map-nested-elt event '(:data :text-chunk))))
            (setq agent-workspace--turn-text (concat agent-workspace--turn-text chunk))))
         ('turn-complete
          (let ((text (string-trim (or agent-workspace--turn-text ""))))
            (setq agent-workspace--turn-text nil)
            (unless (string-empty-p text)
              (agent-workspace-room-post project :kind 'reply :agent name
                                         :text (agent-workspace--first-lines text))))))))))

(defun agent-workspace--first-lines (text)
  "TEXT's first lines, on one: at most 160 characters."
  (let* ((lines (seq-take (seq-remove #'string-empty-p (mapcar #'string-trim (split-string text "\n"))) 3))
         (line (string-join lines " ")))
    (if (> (length line) 160) (concat (substring line 0 159) "…") line)))

(defun agent-workspace--yours-lines (prompt)
  "What the room says of PROMPT, sent in an agent's session: an answer on
its canvas (Agent UI's \"Answer to choice ID (QUESTION): A\"), its first
line; else its first lines, as a reply's."
  (agent-workspace--first-lines
   (if (string-prefix-p "Answer to " prompt) (car (split-string prompt "\n")) prompt)))

;; ====== WHAT AGENTS DID TO ISSUES ======
;; The crew's issues as fetched (issues.el: after an agent's bd command, at
;; its turn's end) compared with the fetch before: what changed, and whose it
;; was, as the issues say it, never as a command looked. The first fetch after
;; the app opens is the baseline.

(declare-function agent-workspace-label-role "agent-workspace/handover")

(defvar-local agent-workspace--room-issues nil
  "In the feed: the crew's issues as last fetched (issues.el's :issues), and
when the first fetch was, the baseline (`float-time'): (TIME . ISSUES); nil
before it.")

(defun agent-workspace--issue-new-p (issue since)
  "Non-nil if ISSUE was made since SINCE (`float-time', a minute's leeway):
not one reopened. No SINCE, or no date it has: made since."
  (or (not since)
      (not (plist-get issue :created))
      (condition-case nil
          (>= (float-time (date-to-time (plist-get issue :created))) (- since 60))
        (error t))))

(defun agent-workspace--handed-to (project name removed added)
  "The role an issue was handed to by the agent NAME of PROJECT's crew, its
labels REMOVED and ADDED: one of NAME's role's labels removed, one of
another role's added (handover.el's way). That role, or nil."
  (when-let* ((agent (agent-workspace-agent name project))
              (role (agent-workspace-agent-role agent))
              ((seq-some (lambda (label) (equal (agent-workspace-label-role project label) role)) removed)))
    (seq-some (lambda (label)
                (let ((to (agent-workspace-label-role project label)))
                  (and to (not (equal to role)) to)))
              added)))

(defun agent-workspace--issues-said (project before after &optional actor since)
  "What PROJECT's crew did to its issues between two fetches, BEFORE and
AFTER (issues.el's :issues): (NAME . TEXT) each, NAME an agent of the crew,
TEXT what the room says, in AFTER's order. ACTOR: the agent whose bd
command led to AFTER, its name. SINCE: when the first fetch was (an issue
made before it, new to AFTER, was reopened: not filed). What's no agent's
\(you, another program) isn't said:
- filed: an issue new to AFTER, by its creator (created_by): \"filed: TITLE\";
- claimed: in progress now, by its assignee: \"claimed ID\";
- handed on, while agents may talk (`agent-workspace-agents-talk'): open
  again, its label moved from the role of its agent (its assignee before;
  no one's, ACTOR) to another role's: \"handed ID to the builders\"
  unassigned, \"handed ID back to ken\" assigned to ken;
- labelled: a label added otherwise, by ACTOR: \"labelled ID build\";
- closed: by its assignee (no one's, ACTOR): \"closed ID\".
An issue assigned to someone outside the crew is theirs: not said."
  (let* ((crew (lambda (name)
                 (and (stringp name) (not (string-empty-p name)) (agent-workspace-agent name project) name)))
         ;; Whose an issue is: its assignee's, if it has one; else ACTOR's.
         (whose (lambda (&rest assignees)
                  (if-let* ((name (seq-find (lambda (name) (and (stringp name) (not (string-empty-p name))))
                                            assignees)))
                      (funcall crew name)
                    (funcall crew actor))))
         (said nil))
    (dolist (issue after)
      (let* ((id (plist-get issue :id))
             (old (seq-find (lambda (old) (equal (plist-get old :id) id)) before))
             (status (plist-get issue :status)))
        (if (not old)
            (when-let* ((by (funcall crew (plist-get issue :created-by)))
                        ((agent-workspace--issue-new-p issue since)))
              (push (cons by (format "filed: %s" (plist-get issue :title))) said))
          (let* ((was (plist-get old :status))
                 (assignee (funcall crew (plist-get issue :assignee)))
                 (by (funcall whose (plist-get old :assignee)))
                 (added (seq-difference (plist-get issue :labels) (plist-get old :labels)))
                 (removed (seq-difference (plist-get old :labels) (plist-get issue :labels)))
                 (handed (and agent-workspace-agents-talk by added removed (eq status 'open)
                              (agent-workspace--handed-to project by removed added))))
            (when (and assignee (eq status 'in_progress) (not (eq was 'in_progress)))
              (push (cons assignee (format "claimed %s" id)) said))
            (cond
             (handed
              (push (cons by (let ((to (plist-get issue :assignee)))
                               (if (and to (not (string-empty-p to)))
                                   (format "handed %s back to %s" id to)
                                 (format "handed %s to the %ss" id handed))))
                    said))
             ((and added (funcall crew actor))
              (push (cons actor (format "labelled %s %s" id (string-join added ", "))) said)))
            (when (and (eq status 'closed) (not (eq was 'closed)))
              (when-let* ((by (funcall whose (plist-get issue :assignee) (plist-get old :assignee))))
                (push (cons by (format "closed %s" id)) said)))))))
    (nreverse said)))

(defun agent-workspace--room-issues-h (project data)
  "PROJECT's issues just fetched (DATA, issues.el's): what its agents did to
them since the fetch before, said in its room; the first fetch, the
baseline, says nothing. In `agent-workspace-issues-fetched-functions'."
  (unless (plist-get data :error)
    (with-current-buffer (agent-workspace--room-buffer project)
      (let ((before agent-workspace--room-issues))
        (setq agent-workspace--room-issues (cons (or (car before) (float-time)) (plist-get data :issues)))
        (when before
          (pcase-dolist (`(,name . ,text) (agent-workspace--issues-said project (cdr before) (plist-get data :issues)
                                                                         (plist-get data :actor) (car before)))
            (agent-workspace-room-post project :kind 'issue :agent name :text text)))))))

(add-hook 'agent-workspace-change-functions #'agent-workspace--room-changed-h)
(add-hook 'agent-workspace-state-change-functions #'agent-workspace--room-state-h)
(add-hook 'agent-workspace-session-functions #'agent-workspace--room-watch)
(add-hook 'agent-workspace-issues-fetched-functions #'agent-workspace--room-issues-h)
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
  "After a command in the compose line: \"#name \" typed selects that agent;
the line sized to its text."
  (save-excursion
    (goto-char (point-min))
    (when (looking-at "#\\([a-z][a-z0-9-]*\\) ")
      (when-let* ((agent (agent-workspace-agent (match-string 1) agent-workspace--room-project)))
        (unless (eq agent (agent-workspace--compose-target agent-workspace--room-project))
          (agent-workspace-select agent)
          (agent-workspace--compose-prompt-draw)))))
  (when-let* ((window (get-buffer-window (current-buffer))))
    (agent-workspace--compose-fit-own window)))

(defun agent-workspace--compose-corfu ()
  "With Corfu, in the compose line: # opens its completion as it's typed, not
after `corfu-auto-prefix' more characters, and what follows narrows it at
once. Corfu's settings elsewhere stay. In its `corfu-mode-hook' there: Corfu
loads its auto completion as it turns on."
  (when (boundp 'corfu-auto-trigger)
    (setq-local corfu-auto-trigger "#"
                corfu-auto-delay 0.05)))

(defun agent-workspace--compose-capf ()
  "Completion for # at the start of the compose line, where it picks who to
\(a # further on is text): the agents, their roles, all. Taking one adds its
space: \"#ada \" selects ada."
  (let ((start (save-excursion (skip-chars-backward "a-z0-9-") (point))))
    (when (and (eq (char-before start) ?#)
               (string-blank-p (buffer-substring-no-properties (point-min) (1- start))))
      (let* ((project agent-workspace--room-project)
             (agents (agent-workspace-agents project))
             (roles (delete-dups (mapcar (lambda (agent) (concat (agent-workspace-agent-role agent) "s")) agents))))
        (list start (point) (append (mapcar #'agent-workspace-agent-name agents) roles '("all"))
              :annotation-function
              (lambda (candidate)
                (if-let* ((agent (agent-workspace-agent candidate project)))
                    (format "  %s · %s" (agent-workspace-agent-role agent) (agent-workspace-state-text agent))
                  (if (equal candidate "all") "  everyone" "  its first free one")))
              ;; Corfu: the list whatever's typed after the #, none or more.
              :company-prefix-length t
              :exit-function
              (lambda (_candidate status)
                (when (eq status 'finished)
                  (if (eq (char-after) ?\s) (forward-char) (insert " "))))
              :exclusive 'no)))))

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
                (cons (list (or (seq-find (lambda (agent) (memq (agent-workspace-agent-state agent) '(desk done nap))) of)
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

;; ====== ITS HEIGHT ======

(defun agent-workspace--compose-text-lines (window)
  "The lines WINDOW's text, the compose line's, takes as shown: wrapped, its
newlines (a last one too)."
  (with-current-buffer (window-buffer window)
    (count-screen-lines (point-min) (point-max) t window)))

(defun agent-workspace--compose-lines (window)
  "The lines of text WINDOW, the compose line's, is to show: its text's
\(`agent-workspace--compose-text-lines'), at least
`agent-workspace-compose-lines', at most `agent-workspace-compose-max-lines'
or as many as keep it within half the room (its feed and it)."
  (let* ((feed (window-prev-sibling window))
         (room (+ (window-pixel-height window) (if feed (window-pixel-height feed) 0)))
         (chrome (- (window-pixel-height window) (window-body-height window t)))
         (half (/ (- (/ room 2) chrome) (window-default-line-height window))))
    (max agent-workspace-compose-lines
         (min (agent-workspace--compose-text-lines window) agent-workspace-compose-max-lines half))))

(defun agent-workspace--compose-fit (window)
  "WINDOW, the compose line's, sized to show its text
\(`agent-workspace--compose-lines'): its rows taken from the feed above it,
or given back. A feed following its end still shows its last line; all the
text fitting, it's shown from its start."
  (when-let* ((feed (window-prev-sibling window))
              ((window-parameter feed 'agent-workspace-room)))
    (let* ((line (window-default-line-height window))
           (delta (- (* (agent-workspace--compose-lines window) line) (window-body-height window t)))
           ;; Never more than the feed can give.
           (delta (min delta (- (window-pixel-height feed) (window-min-size feed nil nil t)))))
      (unless (zerop delta)
        (let ((following (with-current-buffer (window-buffer feed)
                           (and (derived-mode-p 'agent-workspace-room-mode)
                                (agent-workspace--room-last-line-p (window-point feed))))))
          (adjust-window-trailing-edge feed (- delta) nil t)
          (when following
            (with-selected-window feed (recenter -1)))))
      (when (<= (agent-workspace--compose-text-lines window) (/ (window-body-height window t) line))
        (set-window-start window (with-current-buffer (window-buffer window) (point-min)) t)))))

(defun agent-workspace--compose-fit-own (window)
  "WINDOW, the compose line's, sized to its text: the app's own change, not a
border dragged (`agent-workspace--resize-own')."
  (agent-workspace--resize-own (window-frame window)
                               (lambda () (agent-workspace--compose-fit window))))

(defun agent-workspace--compose-resized-h (frame)
  "FRAME's compose line, its width changed (the frame resized, the room
moved): sized to its text again, unless the app's laid out again (that does
it). After `agent-workspace--resized-h' in `window-size-change-functions'."
  (dolist (window (window-list frame 'nomini))
    (when (and (eq (buffer-local-value 'major-mode (window-buffer window)) 'agent-workspace-compose-mode)
               (/= (window-pixel-width window) (window-pixel-width-before-size-change window)))
      (agent-workspace--compose-fit-own window))))

(add-hook 'window-size-change-functions #'agent-workspace--compose-resized-h 90)

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

(defun agent-workspace-room-fold ()
  "The thread of the line here folded to its first line, or unfolded (TAB)."
  (interactive)
  (let ((thread (plist-get (get-text-property (line-beginning-position) 'agent-workspace-entry) :thread)))
    (unless thread (user-error "Not a thread between agents"))
    (setq agent-workspace--room-folded
          (if (member thread agent-workspace--room-folded)
              (delete thread agent-workspace--room-folded)
            (cons thread agent-workspace--room-folded)))
    (agent-workspace--room-redraw agent-workspace--room-project)
    (goto-char (point-min))
    (when-let* ((match (text-property-search-forward
                        'agent-workspace-entry thread
                        (lambda (thread entry) (equal (plist-get entry :thread) thread)))))
      (goto-char (prop-match-beginning match)))))

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
         (height (and (not alone) (not right) (agent-workspace--room-height-now app area)))
         (room (if alone
                   area
                 (condition-case nil
                     (cond (right (split-window area (- agent-workspace-room-width) 'right))
                           ;; Too low for it: none (2 shows it alone).
                           (height (split-window area (- height) 'below)))
                   (error nil)))))
    (when room
      (let* ((window-min-height 2)
             (compose (condition-case nil (split-window room -3 'below) (error nil))))
        (set-window-buffer room (agent-workspace--room-buffer project))
        (dolist (parameter '(mode-line-format tab-line-format))
          (set-window-parameter room parameter 'none))
        (set-window-parameter room 'agent-workspace-room t)
        (agent-workspace--compose-prompt-draw project)
        (when compose
          (set-window-buffer compose (agent-workspace--compose-buffer project))
          (dolist (parameter '(mode-line-format tab-line-format))
            (set-window-parameter compose parameter 'none))
          (set-window-parameter compose 'agent-workspace-room t)
          ;; Its height, its text's (3 lines at least), from the feed.
          (agent-workspace--compose-fit compose))
        (agent-workspace--room-redraw project)))
    (unless alone area)))
