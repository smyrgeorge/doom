;;; $DOOMDIR/config/agent-workflow/pane-answer.el -*- lexical-binding: t; -*-
;; A run's pane's Needs you: what the run waits for you on, as a question
;; you answer there; its buttons, what pressing them does.
;; Loaded from config/agent-workflow.el, after pane.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'map)


;; ====== NEEDS YOU ======

(defun agent-workflow--pane-question (run job ask why)
  "What RUN asks you of JOB (ASK, its question: nil, a wait with none), WHY
in words: Agent UI elements, the question first (its id ask), what to look
at with it."
  (let ((kind (plist-get ask :kind)))
    (cond
     ((and ask (null kind))
      ;; The loop guard: what now, a note for each.
      (let ((other (plist-get ask :other)))
        (list (list :id "ask" :type "form" :title "The loop guard" :question why
                    :fields (list (list :name "choice" :label "What now" :type "select" :required t
                                        :options '("go on" "accept it as it is" "stop") :value "go on")
                                  (list :name "note-job" :label (format "Note for %s (it sends it back)" job))
                                  (list :name "note-other" :label (format "Note for %s (it's sent back)" other))))
              (when-let* ((notes (append (plist-get ask :notes) nil)))
                (list :id "rounds" :type "text" :with "ask" :face "muted"
                      :text (mapconcat (lambda (note) (format "· %s" note)) notes "\n"))))))
     ((eq kind 'budget)
      (list (list :id "ask" :type "form" :title "Its budget" :question why
                  :fields '((:name "choice" :label "What now" :type "select" :required t
                                   :options ("go on, with more" "stop") :value "go on, with more")
                            (:name "cost" :label "More dollars" :type "number" :min 0)
                            (:name "tokens" :label "More tokens" :type "integer" :min 0)
                            (:name "time" :label "More time (45m, 1h)")))))
     (t
      ;; A line, its answers buttons; one ending in … asks its note.
      (let ((options (pcase kind
                       ('approve '("Approve" "Reject…"))
                       ('retries '("Go on" "Go on, with a note…" "Skip its step" "Stop"))
                       ((or 'broke 'interrupted) '("Go on" "Skip its step" "Stop"))
                       ((or 'merge 'moved 'protected) '("Go on" "Stop"))
                       ('closed '("Go on (the issue in progress again)" "Cancel the run"))
                       (_ '("Run its step again" "Run it again, with a note…" "Cancel the run")))))
        (cons (agent-workflow--pane-ask-line why options)
              (when (eq kind 'approve)
                (let ((look (agent-workflow-to-look-at run job)))
                  (list (list :id "look" :type "text" :with "ask"
                              :text (string-join
                                     (delq nil (list (format "Outcome: %s" (or (plist-get look :outcome) "done"))
                                                     (and (plist-get look :notes) (concat "Notes: " (plist-get look :notes)))
                                                     (and (plist-get look :diff) (not (string-empty-p (plist-get look :diff)))
                                                          (concat "Its changes:\n" (plist-get look :diff)))
                                                     (and (plist-get look :log) (concat "Its script's output: "
                                                                                       (abbreviate-file-name (plist-get look :log))))))
                                     "\n")))))))))))

(defconst agent-workflow--pane-go-to-it "Go to it"
  "The option of an agent's question in Needs you showing its session.")

(defun agent-workflow--pane-ask-line (text options)
  "Needs you's question: TEXT in a line, ◆ before it, OPTIONS its buttons
\(each its label, as its answer)."
  (list :id "ask" :type "text" :face "warning" :text (concat "◆ " text)
        :actions (mapcar (lambda (option) (list :label option :prompt option)) options)))

;; AN AGENT'S QUESTION, ANSWERED HERE: its form in its session (agent-shell's
;; elicitation: Claude Code's AskUserQuestion's, any agent's), as Agent UI's own: one question with
;; options a choice (several, a multi-select; a note, its free answer), more
;; a form (selects, text, numbers, yes or no); answered as its form's Submit
;; does (agent-shell's own: its required answers checked). One it can't draw
;; (a multi-select among others): Go to it. Go to it, always too.

(defun agent-workflow--pane-elicitation (run job asks)
  "The form JOB of RUN's agent asks (ASKS: its :request) in its session,
still waiting: (BUFFER STATE ELICITATION), or nil."
  (when-let* ((request (plist-get asks :request))
              (agent (plist-get (agent-workflow--job run job) :agent))
              (buffer (agent-workflow-agent-buffer agent))
              ((buffer-live-p buffer))
              ((fboundp 'agent-shell-elicitation--get))
              (state (buffer-local-value 'agent-shell--state buffer))
              (elicitation (agent-shell-elicitation--get state request))
              ((eq (map-elt elicitation :status) 'pending)))
    (list buffer state elicitation)))

(defun agent-workflow--pane-elicitation-fields (elicitation)
  "ELICITATION's fields asked (a free answer's own folded into its select's)."
  (seq-remove (lambda (field) (map-elt field :folded-into)) (map-elt elicitation :fields)))

(defun agent-workflow--pane-option-label (option)
  "An elicitation's OPTION as its label: its title, else its value."
  (format "%s" (or (map-elt option :title) (map-elt option :value))))

(defun agent-workflow--pane-elicitation-question (run job asks)
  "JOB of RUN's agent's form (ASKS) as Agent UI's question (see above), or
nil if it can't be drawn."
  (when-let* ((found (agent-workflow--pane-elicitation run job asks))
              (elicitation (nth 2 found))
              (fields (agent-workflow--pane-elicitation-fields elicitation)))
    (let* ((message (or (map-elt elicitation :message) (plist-get asks :what)))
           (question (concat job " asks: " (or message "its question")))
           (actions (list (list :label agent-workflow--pane-go-to-it :prompt agent-workflow--pane-go-to-it)))
           (one (car fields)))
      (cond
       ((and (null (cdr fields)) (memq (map-elt one :type) '(single-select multi-select)))
        (list :id "ask" :type "choice" :title (map-elt one :title)
              :question (if (and (map-elt one :description) (not message))
                            (concat job " asks: " (map-elt one :description))
                          question)
              :options (mapcar (lambda (option)
                                 (append (list :label (agent-workflow--pane-option-label option))
                                         (and (map-elt option :description)
                                              (list :detail (map-elt option :description)))))
                               (map-elt one :options))
              :multiple (if (eq (map-elt one :type) 'multi-select) t :false)
              :note (if (map-elt one :custom-key) t :false)
              :actions actions))
       ((seq-every-p (lambda (field) (memq (map-elt field :type) '(single-select boolean string number integer)))
                     fields)
        (list :id "ask" :type "form" :question question
              :fields (mapcar (lambda (field)
                                (append (list :name (map-elt field :key)
                                              :label (or (map-elt field :title) (map-elt field :description)
                                                         (map-elt field :key))
                                              :type (pcase (map-elt field :type)
                                                      ('single-select "select") ('boolean "boolean")
                                                      ('number "number") ('integer "integer") (_ "text")))
                                        (and (eq (map-elt field :type) 'single-select)
                                             (list :options (mapcar #'agent-workflow--pane-option-label
                                                                    (map-elt field :options))))
                                        (and (map-elt field :required) (list :required t))))
                              fields)
              :actions actions))))))

(defun agent-workflow--pane-elicitation-answer (elicitation element)
  "ELEMENT's answer (a choice's, a form's: see above) as ELICITATION's
values, ((KEY . VALUE)...); a user error if it gives none."
  (let ((fields (agent-workflow--pane-elicitation-fields elicitation)))
    (cl-flet ((value-of (field label)
                (if-let* ((option (seq-find (lambda (option)
                                              (equal (agent-workflow--pane-option-label option) label))
                                            (map-elt field :options))))
                    (map-elt option :value)
                  label)))
      (if (equal (plist-get element :type) "choice")
          (let* ((field (car fields))
                 (selected (plist-get element :selected))
                 (note (let ((note (plist-get element :note-text)))
                         (and (stringp note) (not (string-blank-p note)) (string-trim note)))))
            (cond ((and note (map-elt field :custom-key)) (list (cons (map-elt field :custom-key) note)))
                  (selected
                   (let ((values (mapcar (lambda (label) (value-of field label)) selected)))
                     (list (cons (map-elt field :key)
                                 (if (eq (map-elt field :type) 'multi-select) values (car values))))))
                  (t (user-error "Choose one first"))))
        (let ((values (plist-get element :values)))
          (or (delq nil
                    (mapcar (lambda (field)
                              (let ((value (plist-get values (intern (concat ":" (map-elt field :key))))))
                                (unless (or (null value) (equal value ""))
                                  (cons (map-elt field :key)
                                        (pcase (map-elt field :type)
                                          ('single-select (value-of field value))
                                          ('boolean (if (memq value '(nil :false)) :false t))
                                          (_ value))))))
                            fields))
              (user-error "Answer it first")))))))

(defun agent-workflow--pane-answer-elicitation (run job asks answer)
  "JOB of RUN's agent's form (ASKS) answered with ANSWER (its values), as
its Submit does (agent-shell's: its required answers checked)."
  (pcase-let ((`(,buffer ,state ,elicitation) (or (agent-workflow--pane-elicitation run job asks)
                                                  (user-error "%s's agent no longer asks that" job))))
    (ignore elicitation)
    (with-current-buffer buffer
      (let ((id (plist-get asks :request)))
        (pcase-dolist (`(,key . ,value) answer)
          (agent-shell-elicitation--set-values
           state id (agent-shell-elicitation--clearing (agent-shell-elicitation--get state id) key value)))
        (agent-shell-elicitation--submit :state state :id id)))))

(defun agent-workflow--pane-agent-answer-action (run job element pressed)
  "What answering JOB of RUN's agent's question with ELEMENT (PRESSED: the
label of its button pressed, or its answer) does: a function of no
argument (see `agent-workflow--pane-answer-action')."
  (let ((asks (plist-get (agent-workflow--job run job) :agent-asks)))
    (if (and (member (plist-get element :type) '("choice" "form"))
             (not (equal pressed agent-workflow--pane-go-to-it)))
        (let* ((found (or (agent-workflow--pane-elicitation run job asks)
                          (user-error "%s's agent no longer asks that" job)))
               (answer (agent-workflow--pane-elicitation-answer (nth 2 found) element)))
          (lambda () (agent-workflow--pane-answer-elicitation run job asks answer)))
      (lambda () (agent-workflow--pane-answer-agent run job (plist-get asks :kind) pressed)))))

(defun agent-workflow--pane-agent-question (run job asks why)
  "What JOB of RUN's agent asks you in its session (ASKS, as
`agent-workflow-agent-asking' has it), WHY in words: its form as Agent
UI's own (see above); else a line, a permission's options agent-shell's
own buttons, and Go to it."
  (ignore why)
  (if-let* ((question (agent-workflow--pane-elicitation-question run job asks)))
      (list question)
    (let* ((agent (plist-get (agent-workflow--job run job) :agent))
           (buffer (and agent (agent-workflow-agent-buffer agent)))
           (what (plist-get asks :what))
           (buttons (and (eq (plist-get asks :kind) 'permission)
                         (buffer-live-p buffer)
                         (fboundp '+my/agent-shell-permission-buttons)
                         (mapcar #'car (+my/agent-shell-permission-buttons buffer)))))
      (list (agent-workflow--pane-ask-line
             (concat job (if (eq (plist-get asks :kind) 'permission) " asks for your permission" " asks you")
                     (if what (concat ": " what) ""))
             (append buttons (list agent-workflow--pane-go-to-it)))))))

(defun agent-workflow--pane-answer-agent (run job kind picked)
  "JOB of RUN's agent's question (KIND: permission, question) answered in
its pane with PICKED: a permission's button pressed, or its session shown
at the question (asked again here: it still is)."
  (let* ((agent (plist-get (agent-workflow--job run job) :agent))
         (buffer (and agent (agent-workflow-agent-buffer agent))))
    (unless (buffer-live-p buffer)
      (user-error "%s has no agent working now" job))
    (if (equal picked agent-workflow--pane-go-to-it)
        (progn
          (agent-workflow--pane-open-session run job)
          (with-current-buffer buffer
            (ignore-errors
              (if (eq kind 'permission)
                  (agent-shell-jump-to-latest-permission-button-row)
                (agent-shell-elicitation-jump-to-latest-form))))
          (agent-workflow--pane-changed run))
      (unless (and (fboundp '+my/agent-shell-press-permission)
                   (+my/agent-shell-press-permission buffer picked))
        (user-error "%s's agent no longer asks that" job)))))

(defun agent-workflow--pane-needs (run pane)
  "RUN's Needs you, in PANE: shown while it waits for you (its question,
shown again only when it's another), gone once it doesn't."
  (with-current-buffer pane
    (let* ((waiting (eq (agent-workflow-run-state run) 'waiting))
           (asking (agent-workflow-asking run))
           (agent-asking (and (not asking) (agent-workflow-agent-asking run)))
           (job (or (car asking)
                    (car agent-asking)
                    (car (seq-find (lambda (job) (eq (plist-get (cdr job) :status) 'waiting))
                                   (agent-workflow-run-jobs run)))))
           (ask (cdr asking))
           (why (or (and job (plist-get (agent-workflow--job run job) :why)) (agent-workflow-run-why run)))
           (asked (and waiting job (list job (cond (ask (or (plist-get ask :kind) 'guard))
                                                   (agent-asking 'agent))
                                         why))))
      (cond
       ((not asked)
        (when (agent-ui--find-section "needs-you")
          (agent-ui-remove-section pane "needs-you"))
        (setq agent-workflow--pane-asked nil))
       ((not (equal asked agent-workflow--pane-asked))
        (if (agent-ui--find-section "needs-you")
            (agent-ui-clear :canvas pane :section "needs-you")
          (agent-ui-section pane "needs-you" :title "Needs you" :state 'needs-you :after "run"))
        (agent-ui-section pane "needs-you" :note job)
        (setq agent-workflow--pane-asked asked)
        (dolist (element (if agent-asking
                             (agent-workflow--pane-agent-question run job (cdr agent-asking) why)
                           (agent-workflow--pane-question run job ask why)))
          (agent-ui-show element :canvas pane :section "needs-you")))))))

(defun agent-workflow--pane-answer (prompt _submit key)
  "A button of a run's pane pressed (`agent-ui-answer-function'): its
header's Cancel (asked first), a job's live box's Show session or Show
output, git's
\(PROMPT worktree, magit: its worktree opened), or a question's answer
\(PROMPT the button's label; a form's, read from its element, KEY's), given
to the run (approved, rejected, confirmed, sent back, cancelled) once the
button's own command is done. An answer that can't be given: said, the
question left as it was."
  (let* ((run agent-workflow--pane-run)
         (pane (current-buffer)))
    (cond ((equal key "git") (agent-workflow--pane-open-worktree run prompt))
          ((equal key "run") (agent-workflow--pane-cancel run))
          ((equal key "commits") (agent-workflow--pane-show-commit run prompt))
          ((equal key "removal") (agent-workflow-keep-worktree run))
          ;; A job's live box: Show session, Show output (PROMPT: what, its job).
          ((string-prefix-p "now-" (agent-ui--key-id key))
           (pcase (split-string prompt " ")
             (`("session" ,job) (agent-workflow--pane-go-to-agent run job))
             (`("output" ,job) (agent-workflow--pane-show-output run job))))
          (t (agent-workflow--pane-answer-question run pane prompt key)))))

(defun agent-workflow--pane-show-commit (run commit)
  "COMMIT (a hash) of RUN shown, from its pane's commits: magit's, else
git show's, read where its work is (its worktree, else its project)."
  (let* ((where (agent-workflow-run-where run))
         (worktree (plist-get where :worktree))
         (default-directory (file-name-as-directory
                             (if (and worktree (file-directory-p worktree))
                                 worktree
                               (agent-workflow-run-project run)))))
    (unless (and (stringp commit) (string-match-p "\\`[0-9a-f]+\\'" commit))
      (user-error "Not a commit: %s" commit))
    (if (fboundp 'magit-show-commit)
        (magit-show-commit commit)
      (let ((buffer (get-buffer-create (format "*git show %s*" commit))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (call-process "git" nil t nil "show" commit))
          (goto-char (point-min))
          (diff-mode)
          (view-mode 1))
        (pop-to-buffer buffer)))))

(defun agent-workflow--pane-cancel (run)
  "RUN cancelled from its pane's Cancel, asked first; over already: said."
  (when (memq (agent-workflow-run-state run) agent-workflow--ended)
    (user-error "%s is over already" (agent-workflow-run-name run)))
  (agent-workflow-cancel-asked run :by "you, in its pane"))

(defun agent-workflow--pane-open-worktree (run how)
  "RUN's worktree opened, HOW: worktree (dired), magit (its status); or
removed, remove (a run over: `agent-workflow-remove-worktree', asked
first)."
  (let ((dir (plist-get (agent-workflow-run-where run) :worktree)))
    (unless (and dir (file-directory-p dir))
      (user-error "%s has no worktree now" (agent-workflow-run-name run)))
    (cond ((equal how "remove") (agent-workflow-remove-worktree run))
          ((and (equal how "magit") (fboundp 'magit-status)) (magit-status dir))
          (t (pop-to-buffer (dired-noselect dir))))))

(defun agent-workflow--pane-answer-question (run pane prompt key)
  "RUN's question in PANE answered with PROMPT, its button pressed on KEY's
element (see `agent-workflow--pane-answer')."
  (let* ((asked agent-workflow--pane-asked)
         (job (car asked))
         (kind (nth 1 asked))
         (by "you, in its pane")
         (give (progn
                 (unless (and run asked (equal (agent-ui--key-section key) "needs-you"))
                   (user-error "This run asks nothing here"))
                 (agent-workflow--pane-answer-action run job kind (agent-ui-get key :canvas pane) by prompt))))
    ;; Answered: the next question shown, even if it's the same again.
    (setq agent-workflow--pane-asked nil)
    (run-at-time 0 nil (lambda ()
                         (condition-case err
                             (funcall give)
                           (error (message "%s: %s" (agent-workflow-run-name run) (error-message-string err))
                                  (when (buffer-live-p pane)
                                    (agent-workflow--pane-changed run))))))))

(defun agent-workflow--pane-answer-action (run job kind element by &optional pressed)
  "What answering RUN's question on JOB (KIND: its :ask's, `guard' for the
loop guard's, `agent' for its agent's, nil for a wait with no question) with
ELEMENT (the question, answered; a line's: the label of the button
PRESSED, one ending in … asking its note) does: a function of no argument,
BY you. A user error if the answer can't be given (nothing chosen, a
rejection without a note)."
  (cond
   ((eq kind 'agent) (agent-workflow--pane-agent-answer-action run job element pressed))
   ((equal (plist-get element :type) "form")
    (let* ((values (plist-get element :values))
           (choice (plist-get values :choice))
           (text (lambda (key) (let ((value (plist-get values key)))
                                 (and (stringp value) (not (string-blank-p value)) (string-trim value))))))
      (if (eq kind 'budget)
          (let ((more (list :cost (let ((n (plist-get values :cost))) (and (numberp n) n))
                            :tokens (let ((n (plist-get values :tokens))) (and (numberp n) n))
                            :time (let ((time (funcall text :time)))
                                    (and time (agent-workflow--duration time))))))
            (if (equal choice "stop")
                (lambda () (agent-workflow--confirm run "stop" :by by))
              (lambda () (agent-workflow--confirm run "go" :by by :more more))))
        (let* ((other (plist-get (cdr (agent-workflow-asking run)) :other))
               (notes (delq nil (list (and (funcall text :note-job) (cons job (funcall text :note-job)))
                                      (and (funcall text :note-other) (cons other (funcall text :note-other))))))
               (choice (pcase choice ("accept it as it is" "accept") ("stop" "stop") (_ "go"))))
          (lambda () (agent-workflow--confirm run choice :by by :notes notes))))))
   (t
    (let* ((line (equal (plist-get element :type) "text"))
           (picked (if line pressed (car (plist-get element :selected))))
           (note (let ((note (if (and line picked (string-suffix-p "…" picked))
                                 (read-string (if (eq kind 'approve)
                                                  (format "Why (%s's agent is told it): " job)
                                                (format "Your note for %s: " job)))
                               (plist-get element :note-text))))
                   (and (stringp note) (not (string-blank-p note)) (string-trim note)))))
      (unless picked
        (user-error "Choose one first"))
      (when (and line (string-suffix-p "…" picked) (not note))
        (user-error "No note: nothing answered"))
      (pcase kind
        ('approve
         (if (equal picked "Approve")
             (lambda () (agent-workflow--approve run :by by))
           (unless note (user-error "Say why in a note: the agent's told it"))
           (lambda () (agent-workflow--reject run note :by by))))
        ('nil
         (if (string-prefix-p "Cancel" picked)
             (lambda () (agent-workflow--cancel run :by by))
           (lambda () (agent-workflow--back run job :step (or (plist-get (agent-workflow--job run job) :step) 0)
                                           :note note :by by))))
        (_
         (let ((choice (cond ((string-prefix-p "Go on" picked) "go")
                             ((string-prefix-p "Skip" picked) "skip")
                             ((string-prefix-p "Cancel" picked) "cancel")
                             (t "stop"))))
           (lambda () (agent-workflow--confirm run choice :by by :notes (and note (list (cons job note))))))))))))
