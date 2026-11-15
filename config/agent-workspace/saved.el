;;; $DOOMDIR/config/agent-workspace/saved.el -*- lexical-binding: t; -*-
;; The crew's configuration, saved per project on this machine, never
;; committed. Loaded from config/agent-workspace.el, after app.el. No Doom here.
;;
;; .agent-shell/agent-workspace/crew.json, beside the room and the inbox,
;; holds one JSON object, read with Emacs's JSON parser, never evaluated:
;;
;;   {"version": 2,
;;    "agents": [
;;     {"name": "ada", "role": "builder", "colour": "blue", "loop": true, "panels": ["logs", "tests"]},
;;     {"name": "ken", "role": "builder", "colour": "green", "asleep": true}
;;    ],
;;    "layout": {"view": "stage", "room": "right", "selected": "ada", "open": true, "minimap": true,
;;               "talk": "ask", "sources_off": [["ci", "#reviewer"]]}}
;;
;; What each agent is (its name, role, colour; its model and mode when not its
;; role's; whether it's asleep; whether it loops (loops.el); its kind when not
;; Claude Code; its open panels, by name, never their data) and the layout;
;; never its session, its state, its issue or its branch (its worktree keeps
;; the one it's on: worktree.el). Written when the crew changes
;; (debounced), in a stable order (role order, then name), one agent a line,
;; only if it differs; its crew closing leaves it as it was (written first,
;; before any agent stops and its panels close). When the app opens with no
;; crew running, every agent in it starts again, fresh, in its worktree, with
;; its role as it is now, its panels opened again there; asleep ones stay
;; asleep, looping ones are asleep (reopening never starts work by itself:
;; woken, they loop); each waits for you. One that can't start is stuck,
;; saying why; the others start. A wrong agent is left out, said by its place
;; and name; a file that isn't JSON, or not a crew, is said, nothing starts,
;; and it's kept as it is (for you to mend) until an agent is made. Read
;; again by hand (gR): it asks before starting or stopping one, or turning a
;; loop on.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-crew-file ".agent-shell/agent-workspace/crew.json"
  "The crew's configuration, in its project (per machine, not committed)."
  :type 'string
  :group 'agent-workspace)

(defvar agent-workspace--crew-timers (make-hash-table :test #'equal)
  "A project's crew.json to write: its timer.")

(defvar agent-workspace--crew-closed (make-hash-table :test #'equal)
  "The projects whose crew was closed, or whose crew.json wasn't a crew as it
opened (no agent made since): crew.json kept as it was then, whatever changes
in their app after.")

(defvar agent-workspace--crew-panels (make-hash-table :test #'eq :weakness 'key)
  "An agent started again asleep (or stuck): its panels in crew.json, kept
there and opened once its session starts.")

(defvar agent-workspace--crew-loading nil
  "Non-nil while a crew starts from its crew.json: nothing written meanwhile.")

;; ====== JSON ======

(defun agent-workspace--crew-path (project)
  "PROJECT's crew.json."
  (expand-file-name agent-workspace-crew-file project))

(defun agent-workspace--crew-file-name ()
  "The crew's file as its problems and questions name it: crew.json."
  (file-name-nondirectory agent-workspace-crew-file))

(defun agent-workspace--crew-json (value)
  "VALUE as JSON text, spaced to read (\", \" and \": \"): a plist an object
\(its keys without their colon), a vector an array, t true, :false false, nil
null; a string, a number as `json-serialize' has them."
  (cond ((eq value t) "true")
        ((eq value :false) "false")
        ((null value) "null")
        ((vectorp value) (concat "[" (mapconcat #'agent-workspace--crew-json value ", ") "]"))
        ((and (consp value) (keywordp (car value)))
         (concat "{"
                 (mapconcat (lambda (pair)
                              (concat (agent-workspace--crew-json (substring (symbol-name (car pair)) 1))
                                      ": " (agent-workspace--crew-json (cadr pair))))
                            (seq-partition value 2) ", ")
                 "}"))
        ;; Its UTF-8 bytes, decoded: text again.
        (t (decode-coding-string (json-serialize value) 'utf-8 t))))

;; ====== READING ======

(defun agent-workspace-crew-read (project)
  "Read PROJECT's crew.json (JSON, never evaluated): (CREW . PROBLEMS), CREW
a plist (:agents, a list of agent plists that are right, :layout) as the code
takes them (symbols where it takes symbols, false and null nil), nil without
a file or with one that isn't JSON or isn't a crew; PROBLEMS, each
\"crew.json: what\". An agent entry that's wrong is left out, said by its
place and name."
  (let ((file (agent-workspace--crew-path project)))
    (when (file-readable-p file)
      (let* ((problems nil)
             (agents nil)
             (layout nil)
             ;; Not JSON: t, or the line where it isn't.
             (not-json nil)
             (data (with-temp-buffer
                     (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
                     (condition-case err
                         (json-parse-string (buffer-string) :object-type 'plist :array-type 'array
                                            :null-object nil :false-object nil)
                       (json-error (setq not-json (if (integerp (cadr err)) (cadr err) t)) nil)))))
        (cl-flet ((problem (format &rest args)
                    (push (concat (agent-workspace--crew-file-name) ": " (apply #'format format args)) problems)))
          (cond
           (not-json
            (problem "not a crew: not JSON%s" (if (integerp not-json) (format " (line %d)" not-json) ""))
            (setq layout :wrong))
           ((not (and (consp data) (keywordp (car data))))
            (problem "not a crew: not a JSON object")
            (setq layout :wrong))
           ((not (vectorp (plist-get data :agents)))
            (problem "not a crew: its \"agents\" aren't a list")
            (setq layout :wrong))
           (t
            (cl-loop for key in data by #'cddr
                     unless (memq key '(:version :agents :layout))
                     do (problem "unknown key %s: ignored"
                                 (agent-workspace--crew-json (substring (symbol-name key) 1))))
            (seq-do-indexed
             (lambda (entry i)
               (let ((why (agent-workspace--crew-entry-problem entry agents))
                     (name (and (consp entry) (plist-get entry :name))))
                 (if why
                     (problem "agent %d%s: %s: left out" (1+ i)
                              (if (agent-workspace-name-valid-p name) (format " (%s)" name) "")
                              why)
                   (push (agent-workspace--crew-entry-read entry) agents))))
             (plist-get data :agents))
            (let ((json (plist-get data :layout)))
              (cond ((null json))
                    ((not (and (consp json) (keywordp (car json))))
                     (problem "its layout isn't an object: ignored"))
                    (t (setq layout (agent-workspace--crew-layout-read json #'problem))))))))
        (cons (unless (eq layout :wrong)
                (list :agents (nreverse agents) :layout layout))
              (nreverse problems))))))

(defun agent-workspace--crew-entry-problem (entry before)
  "What's wrong with ENTRY, an agent of crew.json as JSON has it (BEFORE: the
ones read already), or nil."
  (let* ((name (and (consp entry) (plist-get entry :name)))
         (shown #'agent-workspace--crew-json)
         (not-boolean (and (consp entry)
                           (seq-find (lambda (key) (not (memq (plist-get entry key) '(t nil))))
                                     '(:asleep :loop)))))
    (cond ((not (and (consp entry) (keywordp (car entry))))
           "an agent is an object: {\"name\": ..., \"role\": ...}")
          ((not (agent-workspace-name-valid-p name))
           (format "not a name: %s" (funcall shown name)))
          ((seq-find (lambda (other) (equal (plist-get other :name) name)) before)
           "its name twice")
          ((not (stringp (plist-get entry :role))) "no role")
          ((and (plist-member entry :colour) (not (member (plist-get entry :colour) agent-workspace-colours)))
           (format "its colour %s isn't one of %s" (funcall shown (plist-get entry :colour))
                   (string-join agent-workspace-colours ", ")))
          ((and (plist-member entry :mode) (not (member (plist-get entry :mode) agent-workspace-modes)))
           (format "its mode %s isn't one of %s" (funcall shown (plist-get entry :mode))
                   (string-join agent-workspace-modes ", ")))
          ((let ((kind (plist-get entry :kind)))
             (and (plist-member entry :kind)
                  (not (and (stringp kind) (assq (intern kind) agent-workspace-kinds)))))
           (format "its kind %s isn't one of %s" (funcall shown (plist-get entry :kind))
                   (mapconcat (lambda (kind) (symbol-name (car kind))) agent-workspace-kinds ", ")))
          ((and (plist-get entry :model) (not (stringp (plist-get entry :model))))
           (format "its model %s isn't a string" (funcall shown (plist-get entry :model))))
          (not-boolean
           (format "its %s %s isn't true or false" (substring (symbol-name not-boolean) 1)
                   (funcall shown (plist-get entry not-boolean))))
          ((let ((panels (plist-get entry :panels)))
             (not (and (or (null panels) (vectorp panels))
                       (seq-every-p (lambda (name) (and (stringp name) (not (string-empty-p name)))) panels))))
           (format "its panels %s aren't a list of names" (funcall shown (plist-get entry :panels)))))))

(defun agent-workspace--crew-entry-read (entry)
  "ENTRY, a right agent of crew.json, as the code takes it: only what it says
\(nothing false or null), its kind a symbol, its panels a list."
  (cl-loop for key in '(:name :role :colour :model :mode :asleep :loop :kind :panels)
           for value = (plist-get entry key)
           when (and value (not (equal value [])))
           append (list key (pcase key
                              (:kind (intern value))
                              (:panels (append value nil))
                              (_ value)))))

(defun agent-workspace--crew-layout-read (layout problem)
  "LAYOUT, crew.json's, as the code takes it: view, room and talk symbols,
sources_off an alist ((SOURCE . TARGET)...) under :sources-off; PROBLEM, a
function as `format', said of what's wrong (left out)."
  (cl-loop for (key value) on layout by #'cddr
           append (pcase key
                    ((or :view :room :talk)
                     (if (stringp value)
                         (list key (intern value))
                       (funcall problem "its layout's %s %s isn't a name: ignored"
                                (substring (symbol-name key) 1) (agent-workspace--crew-json value))
                       nil))
                    (:sources_off
                     (if (and (or (null value) (vectorp value))
                              (seq-every-p (lambda (pair)
                                             (and (vectorp pair) (= (length pair) 2)
                                                  (stringp (aref pair 0)) (stringp (aref pair 1))))
                                           value))
                         (list :sources-off (mapcar (lambda (pair) (cons (aref pair 0) (aref pair 1))) value))
                       (funcall problem "its layout's sources_off %s isn't a list of [source, target]: ignored"
                                (agent-workspace--crew-json value))
                       nil))
                    (_ (list key value)))))

;; ====== WRITING ======

(defun agent-workspace--crew-entry (agent)
  "AGENT as crew.json has it, for `agent-workspace--crew-json': only what
isn't its role's."
  (let ((role (agent-workspace-role agent)))
    (append (list :name (agent-workspace-agent-name agent)
                  :role (agent-workspace-agent-role agent)
                  :colour (agent-workspace-agent-colour agent))
            (let ((model (agent-workspace-agent-model agent)))
              (and model (not (equal model (plist-get role :model))) (list :model model)))
            ;; Its own mode, unless it's the one it would have anyway.
            (let ((mode (agent-workspace-agent-mode agent)))
              (and mode (not (equal mode (or (plist-get role :mode) agent-workspace-mode))) (list :mode mode)))
            (and (eq (agent-workspace-agent-state agent) 'asleep) (list :asleep t))
            (and (agent-workspace-agent-loop agent) (list :loop t))
            ;; Not Claude Code (the example's stand-in): said, so it starts again as it was.
            (unless (eq (agent-workspace-agent-kind agent) 'claude-code)
              (list :kind (symbol-name (agent-workspace-agent-kind agent))))
            (let ((panels (or (agent-workspace-agent-panel-names agent)
                              (gethash agent agent-workspace--crew-panels))))
              (and panels (list :panels (vconcat panels)))))))

(defun agent-workspace-crew-text (project)
  "PROJECT's crew as crew.json's text: one agent a line."
  (let* ((roles (mapcar #'car (agent-workspace-roles project)))
         (agents (seq-sort (lambda (a b)
                             (let ((ra (or (cl-position (agent-workspace-agent-role a) roles :test #'equal) 99))
                                   (rb (or (cl-position (agent-workspace-agent-role b) roles :test #'equal) 99)))
                               (if (= ra rb)
                                   (string< (agent-workspace-agent-name a) (agent-workspace-agent-name b))
                                 (< ra rb))))
                           (agent-workspace-agents project)))
         (app (and (fboundp 'agent-workspace--app) (agent-workspace--app project)))
         (selected (and app (agent-workspace--app-selected app))))
    (concat "{\"version\": 2,\n"
            " \"agents\": ["
            (and agents
                 (concat "\n"
                         (mapconcat (lambda (agent)
                                      (concat "  " (agent-workspace--crew-json (agent-workspace--crew-entry agent))))
                                    agents ",\n")
                         "\n "))
            "],\n"
            " \"layout\": "
            (agent-workspace--crew-json
             (list :view "stage" :room "right"
                   :selected (and selected (agent-workspace-agent-name selected))
                   :open (if (and app (agent-workspace--app-open app)) t :false)
                   :minimap (if (and (fboundp 'agent-workspace-minimap-shown-p)
                                     (agent-workspace-minimap-shown-p project))
                                t
                              :false)
                   ;; As it says, even while agents may not talk.
                   :talk (symbol-name (if (fboundp 'agent-workspace--talk-switch)
                                          (agent-workspace--talk-switch project)
                                        'ask))
                   :sources_off (vconcat (mapcar (lambda (pair) (vector (car pair) (cdr pair)))
                                                 (and (fboundp 'agent-workspace-inbox-sources-off)
                                                      (agent-workspace-inbox-sources-off project))))))
            "}\n")))

(defun agent-workspace-crew-save (&optional project)
  "Write PROJECT's crew.json now (default: the current project's), if what
it holds changed. Not for a crew closed (its app open or not, until an agent
is made there again): crew.json keeps it as it was."
  (interactive)
  (let* ((project (or project (agent-workspace-project) (user-error "Not in a project")))
         (file (agent-workspace--crew-path project))
         (text (agent-workspace-crew-text project)))
    (remhash (agent-workspace--root project) agent-workspace--crew-timers)
    (unless (or (gethash (agent-workspace--root project) agent-workspace--crew-closed)
                (and (not (agent-workspace-agents project))
                     (not (and (fboundp 'agent-workspace--app) (agent-workspace--app project))))
                (and (file-readable-p file)
                     (equal text (with-temp-buffer (insert-file-contents file) (buffer-string)))))
      (make-directory (file-name-directory file) t)
      (let ((coding-system-for-write 'utf-8-unix))
        (write-region text nil file nil 'silent)))))

(defun agent-workspace--crew-save-soon (project)
  "PROJECT's crew.json written in a moment (changes in a burst: once)."
  (unless agent-workspace--crew-loading
    (let ((key (agent-workspace--root project)))
      (when-let* ((timer (gethash key agent-workspace--crew-timers)))
        (cancel-timer timer))
      (puthash key (run-at-time 0.5 nil #'agent-workspace-crew-save key) agent-workspace--crew-timers))))

(defun agent-workspace--crew-changed-h (agent what)
  "AGENT's WHAT changed: what crew.json holds, written. In
`agent-workspace-change-functions'."
  ;; An agent made: the crew running again, written again.
  (when (eq what 'created)
    (remhash (agent-workspace--root (agent-workspace-agent-project agent)) agent-workspace--crew-closed))
  (when (or (memq what '(created renamed colour role settings loop forgotten))
            ;; A panel opened or closed; not one closing as its crew closes
            ;; (the agent out of it already): crew.json keeps what was open.
            (and (eq what 'panels)
                 (memq agent (agent-workspace-agents (agent-workspace-agent-project agent)))))
    (agent-workspace--crew-save-soon (agent-workspace-agent-project agent))))

(defun agent-workspace--crew-state-h (agent old new)
  "AGENT put to sleep or woken: crew.json written. In
`agent-workspace-state-change-functions'."
  (when (and (or (eq old 'asleep) (eq new 'asleep))
             (memq agent (agent-workspace-agents (agent-workspace-agent-project agent))))
    (agent-workspace--crew-save-soon (agent-workspace-agent-project agent))))

(defun agent-workspace--crew-layout-h (project)
  "PROJECT's app's selection changed: crew.json written. In
`agent-workspace-layout-functions'."
  (agent-workspace--crew-save-soon project))

(defun agent-workspace--crew-closing-h (project)
  "PROJECT's crew closing: a write still to come, done now, before any agent
stops (its panels still open, in it); then nothing written for it (its app
changing after, still open) until an agent is made there again. In
`agent-workspace-closing-functions'."
  (let ((key (agent-workspace--root project)))
    (when-let* ((timer (gethash key agent-workspace--crew-timers)))
      (cancel-timer timer)
      (agent-workspace-crew-save project))
    (remhash key agent-workspace--crew-timers)
    (puthash key t agent-workspace--crew-closed)))

(add-hook 'agent-workspace-closing-functions #'agent-workspace--crew-closing-h)
(add-hook 'agent-workspace-change-functions #'agent-workspace--crew-changed-h)
(add-hook 'agent-workspace-state-change-functions #'agent-workspace--crew-state-h)
(add-hook 'agent-workspace-layout-functions #'agent-workspace--crew-layout-h)

;; ====== STARTING AGAIN ======

(defun agent-workspace--restore (project entry)
  "The agent ENTRY of PROJECT's crew.json, in its crew again: fresh, in its
worktree, its panels opened again there; asleep if it was, or if it loops
\(none opened; woken, it loops); stuck, saying why, if it can't start."
  (let* ((name (plist-get entry :name))
         (role (plist-get entry :role))
         (agent (agent-workspace--make-agent
                 :name name :role role
                 :kind (let ((kind (plist-get entry :kind)))
                         (if (and kind (symbolp kind) (assq kind agent-workspace-kinds)) kind 'claude-code))
                 :colour (or (plist-get entry :colour) (agent-workspace-free-colour project))
                 :model (plist-get entry :model) :mode (plist-get entry :mode)
                 :project (agent-workspace--root project)
                 :loop (and (plist-get entry :loop) t)
                 ;; Looping, asleep: reopening never starts work by itself.
                 :state (if (or (plist-get entry :asleep) (plist-get entry :loop)) 'asleep 'waking)))
         (key (agent-workspace--root project)))
    (puthash key (append (gethash key agent-workspace--crews) (list agent)) agent-workspace--crews)
    (cond
     ((not (assoc role (agent-workspace-roles project)))
      (setf (agent-workspace-agent-state agent) 'stuck
            (agent-workspace-agent-error agent) (format "its role %s is gone" role)))
     ((condition-case err
          (progn (agent-workspace-worktree-ensure agent) nil)
        (error (setf (agent-workspace-agent-state agent) 'stuck
                     (agent-workspace-agent-error agent) (concat "its worktree: " (error-message-string err)))
               t))))
    (agent-workspace--changed agent 'created)
    (if (and (eq (agent-workspace-agent-state agent) 'waking)
             (agent-workspace--start agent))
        (agent-workspace-open-panels agent (plist-get entry :panels))
      ;; Asleep or stuck: opened once it starts.
      (when (plist-get entry :panels)
        (puthash agent (plist-get entry :panels) agent-workspace--crew-panels)))
    agent))

(defun agent-workspace--crew-panels-h (agent what)
  "AGENT's session started (woken, restarted): its panels from crew.json
opened, if it was started again asleep or stuck. In
`agent-workspace-change-functions'."
  (when-let* (((eq what 'session))
              (names (gethash agent agent-workspace--crew-panels)))
    (remhash agent agent-workspace--crew-panels)
    (agent-workspace-open-panels agent names)))

(add-hook 'agent-workspace-change-functions #'agent-workspace--crew-panels-h)

(defun agent-workspace--crew-start (project)
  "PROJECT's crew started again from its crew.json, if it has one: non-nil.
In `agent-workspace-open-functions'."
  (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
    (dolist (problem problems)
      (display-warning 'agent-workspace problem))
    ;; Not a crew: kept as it is, for you to mend, until an agent is made.
    (when (and problems (not crew))
      (puthash (agent-workspace--root project) t agent-workspace--crew-closed))
    (when (plist-get crew :agents)
      (let ((agent-workspace--crew-loading t))
        (dolist (entry (plist-get crew :agents))
          (agent-workspace--restore project entry))
        (when-let* ((layout (plist-get crew :layout))
                    ((plist-member layout :minimap))
                    ((fboundp 'agent-workspace--minimap-set)))
          (agent-workspace--minimap-set project (plist-get layout :minimap)))
        (when-let* ((layout (plist-get crew :layout))
                    ((memq (plist-get layout :talk) '(off ask on)))
                    ((fboundp 'agent-workspace--talk-set)))
          (agent-workspace--talk-set project (plist-get layout :talk)))
        (when-let* ((layout (plist-get crew :layout))
                    (off (plist-get layout :sources-off))
                    ((and (proper-list-p off)
                          (seq-every-p (lambda (pair) (and (consp pair) (stringp (car pair)) (stringp (cdr pair))))
                                       off)))
                    ((fboundp 'agent-workspace--inbox-set-sources-off)))
          (agent-workspace--inbox-set-sources-off project off))
        (when-let* ((app (agent-workspace--app project))
                    (layout (plist-get crew :layout))
                    (selected (agent-workspace-agent (plist-get layout :selected) project)))
          (setf (agent-workspace--app-selected app) selected
                (agent-workspace--app-open app) (and (plist-get layout :open) selected))))
      t)))

(add-hook 'agent-workspace-open-functions #'agent-workspace--crew-start)

(defun agent-workspace-crew-reload ()
  "Read crew.json again (after a hand edit): an agent added there is
started, one taken out forgotten (each asked first); a colour changed
applied, its panels as listed (opened, closed; an asleep one's when it
wakes), its loop turned off, or on (asked first)."
  (interactive)
  (let* ((app (agent-workspace--here-or-error))
         (project (agent-workspace--app-project app)))
    (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
      (dolist (problem problems) (display-warning 'agent-workspace problem))
      (unless crew (user-error "No crew in %s" agent-workspace-crew-file))
      (let ((entries (plist-get crew :agents))
            (agent-workspace--crew-loading t))
        (dolist (entry entries)
          (let ((agent (agent-workspace-agent (plist-get entry :name) project)))
            (cond
             ((not agent)
              (when (y-or-n-p (format "Start %s (%s), new in %s? " (plist-get entry :name) (plist-get entry :role)
                                       (agent-workspace--crew-file-name)))
                (agent-workspace--restore project entry)))
             (t
              (when (and (plist-get entry :colour)
                         (not (equal (plist-get entry :colour) (agent-workspace-agent-colour agent))))
                (agent-workspace-recolour agent (plist-get entry :colour)))
              (let ((loop (and (plist-get entry :loop) t)))
                (unless (eq loop (agent-workspace-agent-loop agent))
                  (if (not loop)
                      (agent-workspace-loop-set agent nil)
                    (when (y-or-n-p (format "Turn %s's loop on, as %s says? " (agent-workspace-agent-name agent)
                                               (agent-workspace--crew-file-name)))
                      (condition-case err
                          (agent-workspace-loop-set agent t)
                        (user-error (message "%s" (error-message-string err))))))))
              (let ((panels (plist-get entry :panels)))
                (if (agent-workspace-live-p agent)
                    (unless (equal (sort (copy-sequence panels) #'string<)
                                   (agent-workspace-agent-panel-names agent))
                      (agent-workspace-set-panels agent panels))
                  (if panels
                      (puthash agent panels agent-workspace--crew-panels)
                    (remhash agent agent-workspace--crew-panels))))))))
        (dolist (agent (agent-workspace-agents project))
          (unless (seq-find (lambda (entry) (equal (plist-get entry :name) (agent-workspace-agent-name agent))) entries)
            (when (y-or-n-p (format "Forget %s, gone from %s (its worktree kept)? " (agent-workspace-agent-name agent)
                                    (agent-workspace--crew-file-name)))
              (agent-workspace-forget agent 'keep)))))
      (agent-workspace--crew-save-soon project))))
