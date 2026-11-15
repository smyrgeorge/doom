;;; $DOOMDIR/config/agent-workspace/saved.el -*- lexical-binding: t; -*-
;; The crew's configuration, saved in the project and committed. Loaded from
;; config/agent-workspace.el, after app.el. No Doom here.
;;
;; .agent-workspace/crew.el holds one form, read as data and never evaluated:
;;
;;   (agent-workspace-crew
;;    :version 1
;;    :agents ((:name "ada" :role "builder" :colour "blue" :loop t :panels ("logs" "tests"))
;;             (:name "ken" :role "builder" :colour "green" :asleep t))
;;    :layout (:view stage :room right :selected "ada" :open t :minimap t :talk ask
;;             :sources-off (("ci" . "#reviewer"))))
;;
;; What each agent is (its name, role, colour; its model and mode when not its
;; role's; whether it's asleep; whether it loops (loops.el); its kind when not
;; Claude Code; its open panels, by name, never their data) and the layout;
;; never its session, its state or its issue. Written when the crew changes
;; (debounced), in a stable order (role order, then name), one agent a line,
;; only if it differs; its crew closing leaves it as it was (written first,
;; before any agent stops and its panels close). When the app opens with no
;; crew running, every agent in it starts again, fresh, in its worktree, with
;; its role as it is now, its panels opened again there; asleep ones stay
;; asleep, looping ones are asleep (reopening never starts work by itself:
;; woken, they loop); each waits for you. One that can't start is stuck,
;; saying why; the others start. Read again by hand (gR): it asks before
;; starting or stopping one, or turning a loop on.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-crew-file ".agent-workspace/crew.el"
  "The crew's configuration, in its project."
  :type 'string
  :group 'agent-workspace)

(defvar agent-workspace--crew-timers (make-hash-table :test #'equal)
  "A project's crew.el to write: its timer.")

(defvar agent-workspace--crew-closed (make-hash-table :test #'equal)
  "The projects whose crew was closed (none made since): crew.el kept as it
was then, whatever changes in their app after.")

(defvar agent-workspace--crew-panels (make-hash-table :test #'eq :weakness 'key)
  "An agent started again asleep (or stuck): its panels in crew.el, kept
there and opened once its session starts.")

(defvar agent-workspace--crew-loading nil
  "Non-nil while a crew starts from its crew.el: nothing written meanwhile.")

;; ====== READING ======

(defun agent-workspace--crew-path (project)
  "PROJECT's crew.el."
  (expand-file-name agent-workspace-crew-file project))

(defun agent-workspace-crew-read (project)
  "Read PROJECT's crew.el as data (never evaluated): (CREW . PROBLEMS), CREW
a plist (:agents, a list of agent plists that are right, :layout), nil
without a file or with a wrong one; PROBLEMS, each \"crew.el:LINE: what\".
An agent entry that's wrong is left out, said."
  (let ((file (agent-workspace--crew-path project))
        (problems nil)
        (agents nil)
        (layout nil))
    (when (file-readable-p file)
      (cl-flet ((problem (pos format &rest args)
                  (push (format "%s:%d: %s" agent-workspace-crew-file (line-number-at-pos pos)
                                (apply #'format format args))
                        problems)))
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          (goto-char (point-min))
          (condition-case err
              (progn
                (forward-comment (buffer-size))
                (let ((start (point)))
                  (unless (looking-at-p "(agent-workspace-crew\\_>")
                    (signal 'invalid-read-syntax (list "it isn't (agent-workspace-crew ...)" start)))
                  (down-list)
                  (forward-sexp)
                  ;; Its keywords and values, each read where it is (an agent's line).
                  (while (progn (forward-comment (buffer-size)) (not (looking-at-p ")")))
                    (let* ((pos (point))
                           (key (read (current-buffer))))
                      (forward-comment (buffer-size))
                      (pcase key
                        (:agents
                         (if (not (looking-at-p "("))
                             (problem (point) ":agents is a list")
                           (down-list)
                           (while (progn (forward-comment (buffer-size)) (not (looking-at-p ")")))
                             (let* ((at (point))
                                    (entry (read (current-buffer)))
                                    (why (agent-workspace--crew-entry-problem project entry agents)))
                               (if why
                                   (problem at "%s: left out" why)
                                 (push entry agents))))
                           (up-list)))
                        (:layout (setq layout (read (current-buffer))))
                        (:version (read (current-buffer)))
                        (_ (read (current-buffer))
                           (problem pos "unknown key %S: ignored" key)))))))
            ((error invalid-read-syntax end-of-file)
             (problem (point) "not a crew: %s" (error-message-string err))
             (setq agents nil layout :wrong)))))
      (cons (unless (eq layout :wrong)
              (list :agents (nreverse agents) :layout (and (listp layout) layout)))
            (nreverse problems)))))

(defun agent-workspace--crew-entry-problem (project entry before)
  "What's wrong with ENTRY, an agent of PROJECT's crew.el (BEFORE: the ones
read already), or nil."
  (cond ((not (and (listp entry) (keywordp (car-safe entry)))) "an agent is a plist: (:name ... :role ...)")
        ((not (agent-workspace-name-valid-p (plist-get entry :name)))
         (format "not a name: %S" (plist-get entry :name)))
        ((seq-find (lambda (other) (equal (plist-get other :name) (plist-get entry :name))) before)
         (format "%s twice" (plist-get entry :name)))
        ((not (stringp (plist-get entry :role))) (format "%s has no role" (plist-get entry :name)))
        ((and (plist-get entry :colour) (not (member (plist-get entry :colour) agent-workspace-colours)))
         (format "%s's colour %S isn't one of %s" (plist-get entry :name) (plist-get entry :colour)
                 (string-join agent-workspace-colours ", ")))
        ((and (plist-get entry :mode) (not (member (plist-get entry :mode) agent-workspace-modes)))
         (format "%s's mode %S isn't one of %s" (plist-get entry :name) (plist-get entry :mode)
                 (string-join agent-workspace-modes ", ")))
        ((and (plist-get entry :kind) (not (assq (plist-get entry :kind) agent-workspace-kinds)))
         (format "%s's kind %S isn't one of %s" (plist-get entry :name) (plist-get entry :kind)
                 (mapconcat (lambda (kind) (symbol-name (car kind))) agent-workspace-kinds ", ")))
        ((and (plist-get entry :model) (not (stringp (plist-get entry :model))))
         (format "%s's model isn't a string" (plist-get entry :name)))
        ((let ((panels (plist-get entry :panels)))
           (not (and (proper-list-p panels)
                     (seq-every-p (lambda (name) (and (stringp name) (not (string-empty-p name)))) panels))))
         (format "%s's panels %S aren't a list of names" (plist-get entry :name) (plist-get entry :panels)))
        (t (ignore project) nil)))

;; ====== WRITING ======

(defun agent-workspace--crew-entry (agent)
  "AGENT as crew.el has it: only what isn't its role's."
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
              (list :kind (agent-workspace-agent-kind agent)))
            (let ((panels (or (agent-workspace-agent-panel-names agent)
                              (gethash agent agent-workspace--crew-panels))))
              (and panels (list :panels panels))))))

(defun agent-workspace-crew-text (project)
  "PROJECT's crew as crew.el's text."
  (let* ((roles (mapcar #'car (agent-workspace-roles project)))
         (agents (seq-sort (lambda (a b)
                             (let ((ra (or (cl-position (agent-workspace-agent-role a) roles :test #'equal) 99))
                                   (rb (or (cl-position (agent-workspace-agent-role b) roles :test #'equal) 99)))
                               (if (= ra rb)
                                   (string< (agent-workspace-agent-name a) (agent-workspace-agent-name b))
                                 (< ra rb))))
                           (agent-workspace-agents project)))
         (app (and (fboundp 'agent-workspace--app) (agent-workspace--app project)))
         (selected (and app (agent-workspace--app-selected app)))
         (print-escape-newlines t))
    (concat ";;; crew.el --- Agent workspace: the crew -*- lexical-binding: t; -*-\n"
            ";; Read as data, never evaluated (config/agent-workspace/saved.el). SPC o w starts it again.\n"
            "(agent-workspace-crew\n"
            " :version 1\n"
            " :agents ("
            (mapconcat (lambda (agent) (prin1-to-string (agent-workspace--crew-entry agent)))
                       agents "\n          ")
            ")\n"
            " :layout " (prin1-to-string
                         (list :view 'stage :room 'right
                               :selected (and selected (agent-workspace-agent-name selected))
                               :open (and app (agent-workspace--app-open app) t)
                               :minimap (and (fboundp 'agent-workspace-minimap-shown-p)
                                             (agent-workspace-minimap-shown-p project)
                                             t)
                               ;; As it says, even while agents may not talk.
                               :talk (if (fboundp 'agent-workspace--talk-switch)
                                         (agent-workspace--talk-switch project)
                                       'ask)
                               :sources-off (and (fboundp 'agent-workspace-inbox-sources-off)
                                                 (agent-workspace-inbox-sources-off project))))
            ")\n")))

(defun agent-workspace-crew-save (&optional project)
  "Write PROJECT's crew.el now (default: the current project's), if what it
holds changed. Not for a crew closed (its app open or not, until an agent is
made there again): crew.el keeps it as it was."
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
  "PROJECT's crew.el written in a moment (changes in a burst: once)."
  (unless agent-workspace--crew-loading
    (let ((key (agent-workspace--root project)))
      (when-let* ((timer (gethash key agent-workspace--crew-timers)))
        (cancel-timer timer))
      (puthash key (run-at-time 0.5 nil #'agent-workspace-crew-save key) agent-workspace--crew-timers))))

(defun agent-workspace--crew-changed-h (agent what)
  "AGENT's WHAT changed: what crew.el holds, written. In
`agent-workspace-change-functions'."
  ;; An agent made: the crew running again, written again.
  (when (eq what 'created)
    (remhash (agent-workspace--root (agent-workspace-agent-project agent)) agent-workspace--crew-closed))
  (when (or (memq what '(created renamed colour role settings loop forgotten))
            ;; A panel opened or closed; not one closing as its crew closes
            ;; (the agent out of it already): crew.el keeps what was open.
            (and (eq what 'panels)
                 (memq agent (agent-workspace-agents (agent-workspace-agent-project agent)))))
    (agent-workspace--crew-save-soon (agent-workspace-agent-project agent))))

(defun agent-workspace--crew-state-h (agent old new)
  "AGENT put to sleep or woken: crew.el written. In
`agent-workspace-state-change-functions'."
  (when (and (or (eq old 'asleep) (eq new 'asleep))
             (memq agent (agent-workspace-agents (agent-workspace-agent-project agent))))
    (agent-workspace--crew-save-soon (agent-workspace-agent-project agent))))

(defun agent-workspace--crew-layout-h (project)
  "PROJECT's app's selection changed: crew.el written. In
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
  "The agent ENTRY of PROJECT's crew.el, in its crew again: fresh, in its
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
  "AGENT's session started (woken, restarted): its panels from crew.el
opened, if it was started again asleep or stuck. In
`agent-workspace-change-functions'."
  (when-let* (((eq what 'session))
              (names (gethash agent agent-workspace--crew-panels)))
    (remhash agent agent-workspace--crew-panels)
    (agent-workspace-open-panels agent names)))

(add-hook 'agent-workspace-change-functions #'agent-workspace--crew-panels-h)

(defun agent-workspace--crew-start (project)
  "PROJECT's crew started again from its crew.el, if it has one: non-nil.
In `agent-workspace-open-functions'."
  (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
    (dolist (problem problems)
      (display-warning 'agent-workspace problem))
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
  "Read crew.el again (after a hand edit, a pull): an agent added there is
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
              (when (y-or-n-p (format "Start %s (%s), new in crew.el? " (plist-get entry :name) (plist-get entry :role)))
                (agent-workspace--restore project entry)))
             (t
              (when (and (plist-get entry :colour)
                         (not (equal (plist-get entry :colour) (agent-workspace-agent-colour agent))))
                (agent-workspace-recolour agent (plist-get entry :colour)))
              (let ((loop (and (plist-get entry :loop) t)))
                (unless (eq loop (agent-workspace-agent-loop agent))
                  (if (not loop)
                      (agent-workspace-loop-set agent nil)
                    (when (y-or-n-p (format "Turn %s's loop on, as crew.el says? " (agent-workspace-agent-name agent)))
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
            (when (y-or-n-p (format "Forget %s, gone from crew.el (its worktree kept)? " (agent-workspace-agent-name agent)))
              (agent-workspace-forget agent 'keep)))))
      (agent-workspace--crew-save-soon project))))
