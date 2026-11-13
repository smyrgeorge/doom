;;; $DOOMDIR/config/agent-ui/elements/steps.el -*- lexical-binding: t; -*-
;; Agent UI's checklist: steps whose state changes as work goes on. Loaded from
;; config/agent-ui/elements.el. Appending a step whose name is there changes
;; it in its place. A step may have steps of its own, drawn under it;
;; appended to by its "parent" name. Its time: how long it ran (from running
;; to done or failed, or given), counting while it runs.
;;
;;   ✓ Run the tests      41s  412 passed
;;   ▛ Build              12s
;;     ✓ compile           8s
;;     ▛ link              4s
;;   ○ Publish

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-steps--statuses '(pending running done failed skipped))

(defconst agent-ui-steps--keys '(:name :status :detail :seconds :started :steps)
  "What a step has (started: when it began running, noted).")

(defconst agent-ui-steps-max-depth 4
  "How deep steps nest.")

(defun agent-ui-steps--name (step)
  "STEP's name: STEP itself (a string), or its :name."
  (if (stringp step) step (and (agent-ui--plist-p step) (plist-get step :name))))

;; ====== CHECKING ======

(defun agent-ui-steps--normalize (step where depth)
  "STEP (\"name\", or (:name :status :detail :seconds :steps)) as a plist,
its status a symbol, its sub-steps too. An error naming WHERE (\"step 2\",
\"step 2.1\") if it's wrong; DEPTH, how deep it is (0: not a sub-step)."
  (cl-flet ((bad (what) (agent-ui--fail "steps: %s %s" where what)))
    (cond
     ((stringp step) (list :name step :status 'pending))
     ((agent-ui--plist-p step)
      (cl-loop for (k _) on step by #'cddr
               unless (memq k agent-ui-steps--keys)
               do (bad (format "has %s: a step has name, status, detail, seconds, steps"
                               (agent-ui--show-value (substring (symbol-name k) 1)))))
      (let* ((name (plist-get step :name))
             (status (or (plist-get step :status) "pending"))
             (sym (if (stringp status) (intern-soft status) status))
             (detail (plist-get step :detail))
             (seconds (plist-get step :seconds))
             (started (plist-get step :started))
             (steps (plist-get step :steps)))
        (unless (stringp name) (bad "has no name"))
        (unless (memq sym agent-ui-steps--statuses)
          (bad (format "has status %s; one of: pending, running, done, failed, skipped"
                       (agent-ui--show-value status))))
        (when (and detail (not (stringp detail)))
          (setq detail (agent-ui-cell detail)))
        (unless (or (null seconds) (and (numberp seconds) (>= seconds 0)))
          (bad (format "has seconds %s: a number, 0 or more" (agent-ui--show-value seconds))))
        (unless (or (null started) (numberp started))
          (bad (format "has started %s: a time, in seconds" (agent-ui--show-value started))))
        (unless (listp steps)
          (bad "has steps that aren't a list"))
        (when (and steps (> (+ depth 2) agent-ui-steps-max-depth))
          (bad (format "has steps %d deep: %d at most" (+ depth 2) agent-ui-steps-max-depth)))
        (append (list :name name :status sym)
                (when detail (list :detail detail))
                (when seconds (list :seconds seconds))
                (when started (list :started started))
                (when steps
                  (list :steps (cl-loop for s in steps
                                        for i from 1
                                        collect (agent-ui-steps--normalize
                                                 s (format "%s.%d" where i) (1+ depth))))))))
     (t (bad (format "is %s: a name, or {\"name\": ..., \"status\": ...}"
                     (agent-ui--show-value step)))))))

;; ====== ITS TIMES ======

(defun agent-ui-steps--timed (steps now)
  "STEPS (as given) with their times noted at NOW: when one began running;
how long it ran, once done or failed. A step noted already: as it is."
  (mapcar (lambda (step)
            (if (not (agent-ui--plist-p step))
                step
              (let ((status (format "%s" (or (plist-get step :status) "pending")))
                    (step (copy-sequence step)))
                (cond
                 ((and (equal status "running") (not (plist-get step :started)))
                  (setq step (plist-put step :started now)))
                 ((and (member status '("done" "failed")) (plist-get step :started)
                       (not (plist-get step :seconds)))
                  (setq step (plist-put step :seconds (- now (plist-get step :started))))))
                (if (listp (plist-get step :steps))
                    (plist-put step :steps (agent-ui-steps--timed (plist-get step :steps) now))
                  step))))
          steps))

;; ====== DRAWING ======

(defface agent-ui-steps-dropped '((t :inherit agent-ui-muted :strike-through t))
  "A plan's step the user dropped, while the plan is decided on: struck
through, unlike the steps kept."
  :group 'agent-ui)

(defun agent-ui-steps--icon (status ctx)
  (pcase status
    ('done (propertize "✓" 'face 'agent-ui-success))
    ('failed (propertize "✗" 'face 'agent-ui-error))
    ('running (agent-ui-spinner ctx 'agent-ui-accent))
    ('skipped (propertize "–" 'face 'agent-ui-muted))
    (_ (propertize "○" 'face 'agent-ui-muted))))

(defun agent-ui-steps--flat (steps depth)
  "STEPS and their sub-steps, in order: ((DEPTH . STEP) ...)."
  (mapcan (lambda (step)
            (cons (cons depth step) (agent-ui-steps--flat (plist-get step :steps) (1+ depth))))
          steps))

(defun agent-ui-steps--time (step)
  "STEP's time as text: how long it ran, or has been running; \"\" if none."
  (let ((seconds (plist-get step :seconds))
        (started (plist-get step :started)))
    (cond
     ((memq (plist-get step :status) '(pending skipped)) "")
     (seconds (agent-ui-format-duration seconds))
     ((and started (eq (plist-get step :status) 'running))
      (agent-ui-format-duration (max 0 (- (funcall agent-ui-clock) started))))
     (t ""))))

(defun agent-ui-steps--one-line (text)
  "TEXT on one line: its line breaks as ⏎, its tabs as a space (a failing
test's detail ran onto lines of its own, at column 0)."
  (and text (replace-regexp-in-string "\t" " " (replace-regexp-in-string "\r?\n" "⏎" text))))

(defun agent-ui-steps--name-face (status asked)
  "The face of the name of a step in STATUS: one not started yet, or
skipped, muted. In a plan being decided on (ASKED), its steps are what's
decided on: a kept one in the text's colour, a dropped one struck through."
  (pcase status
    ('pending (unless asked 'agent-ui-muted))
    ('skipped (if asked 'agent-ui-steps-dropped 'agent-ui-muted))))

(defun agent-ui-steps--detail-face (status)
  (if (eq status 'failed) 'agent-ui-error 'agent-ui-muted))

(defun agent-ui-steps--line (entry time names time-width width ctx asked)
  "ENTRY, a (DEPTH . STEP), on one line of WIDTH: its name in a column
NAMES wide (indents in it), its TIME right-aligned in one TIME-WIDTH wide,
its detail after them; each cut with … to its room."
  (let* ((depth (car entry))
         (step (cdr entry))
         (indent (make-string (* 2 depth) ?\s))
         (status (plist-get step :status))
         (detail (or (plist-get step :detail) ""))
         (face (agent-ui-steps--name-face status asked))
         (name (if face (propertize (plist-get step :name) 'face face) (plist-get step :name))))
    (if (and (string-empty-p detail) (= time-width 0))
        (concat indent (agent-ui-steps--icon status ctx) " "
                (agent-ui-truncate name (max 1 (- width 2 (length indent)))))
      (string-trim-right
       (concat indent (agent-ui-steps--icon status ctx) " "
               (agent-ui-pad name (max 1 (- names (length indent))))
               (if (> time-width 0)
                   (concat "  " (propertize (agent-ui-pad time time-width 'right) 'face 'agent-ui-muted))
                 "")
               (if (string-empty-p detail)
                   ""
                 (concat "  " (propertize (agent-ui-truncate detail (max 0 (- width names time-width 6)))
                                          'face (agent-ui-steps--detail-face status)))))))))

(defun agent-ui-steps--wrapped (entry time width ctx asked)
  "ENTRY, a (DEPTH . STEP), its name wrapped at WIDTH, not cut: its lines
after the first under its words (past its icon). Its TIME and detail after
its last line, or on lines of their own (wrapped too) where they don't fit."
  (let* ((depth (car entry))
         (step (cdr entry))
         (indent (make-string (* 2 depth) ?\s))
         (under (concat indent "  "))
         (room (max 1 (- width (length under))))
         (status (plist-get step :status))
         (face (agent-ui-steps--name-face status asked))
         (detail (or (plist-get step :detail) ""))
         (note (string-join
                (append (unless (string-empty-p time) (list (propertize time 'face 'agent-ui-muted)))
                        (unless (string-empty-p detail)
                          (list (propertize detail 'face (agent-ui-steps--detail-face status)))))
                "  "))
         (lines (mapcar (lambda (line) (if face (propertize line 'face face) line))
                        (split-string (agent-ui-wrap (plist-get step :name) room) "\n"))))
    (unless (string-empty-p note)
      (let ((last (car (last lines))))
        (if (<= (+ (string-width last) 2 (string-width note)) room)
            (setcar (last lines) (concat last "  " note))
          (setq lines (append lines (split-string (agent-ui-wrap note room) "\n"))))))
    (concat indent (agent-ui-steps--icon status ctx) " "
            (string-join lines (concat "\n" under)))))

(defun agent-ui-steps--drawn (props ctx &optional wrap asked)
  "PROPS' steps drawn at CTX's width: (TEXTS . MORE), TEXTS a text for each
step shown, in `agent-ui-steps--flat''s order, MORE the line saying how many
more there are, or nil. Each step on its line, its name, time and detail in
columns, cut with … where they don't fit; or, with WRAP, wrapped on lines of
their own instead (see `agent-ui-steps--wrapped'). ASKED: a plan being
decided on (see `agent-ui-steps--name-face')."
  (let* ((all (agent-ui-steps--flat (plist-get props :steps) 0))
         (shown (mapcar (lambda (s)
                          (let ((step (copy-sequence (cdr s))))
                            (setq step (plist-put step :name (agent-ui-steps--one-line (plist-get step :name))))
                            (when (plist-get step :detail)
                              (setq step (plist-put step :detail (agent-ui-steps--one-line (plist-get step :detail)))))
                            (cons (car s) step)))
                        (seq-take all agent-ui-max-rows)))
         (width (plist-get ctx :width))
         (times (mapcar (lambda (s) (agent-ui-steps--time (cdr s))) shown))
         ;; The times' column, right-aligned; left out where it can't fit.
         (time-width (let ((w (apply #'max 0 (mapcar #'string-width times))))
                       (if (> (+ w 5) width) 0 w)))
         (longest (apply #'max 0 (mapcar (lambda (s) (+ (* 2 (car s)) (string-width (plist-get (cdr s) :name))))
                                         shown)))
         ;; Each step whole on its line, the names' column as wide as the
         ;; longest name (it was cut to half the width though it fit).
         (whole (cl-every (lambda (s)
                            (let ((detail (or (plist-get (cdr s) :detail) "")))
                              (if (and (string-empty-p detail) (= time-width 0))
                                  (<= (+ 2 (* 2 (car s)) (string-width (plist-get (cdr s) :name))) width)
                                (and (<= longest (- width 4 time-width))
                                     (<= (string-width detail) (- width longest time-width 6))))))
                          shown))
         ;; Else the names' column half the width, the details the rest, no
         ;; wider than the width leaves (it was 10 at least: past the width
         ;; under ~20 columns).
         (names (max 1 (if whole
                           longest
                         (min longest (max 10 (/ width 2)) (- width 4 time-width))))))
    (cons (cl-mapcar (lambda (s time)
                       (if (and wrap (not whole))
                           (agent-ui-steps--wrapped s time width ctx asked)
                         (agent-ui-steps--line s time names time-width width ctx asked)))
                     shown times)
          (when (> (length all) (length shown))
            (propertize (format "… %d steps more" (- (length all) (length shown))) 'face 'agent-ui-muted)))))

(defun agent-ui-steps--text (props ctx)
  "PROPS' steps, a checklist: a line each (cut with … where too long: what
changes is glanced at, its times and details in columns)."
  (if (null (plist-get props :steps))
      (propertize "no steps yet" 'face 'agent-ui-muted)
    (let ((drawn (agent-ui-steps--drawn props ctx)))
      (string-join (append (car drawn) (and (cdr drawn) (list (cdr drawn)))) "\n"))))

;; ====== APPENDING ======

(defun agent-ui-steps--merge (steps new)
  "STEPS with NEW ones: one whose name is there changes it (its own steps
merged so too), the others after."
  (let ((steps (copy-sequence steps)))
    (dolist (step new)
      (let* ((name (agent-ui-steps--name step))
             (at (and name (cl-position name steps :key #'agent-ui-steps--name :test #'equal))))
        (if (not at)
            (setq steps (append steps (list step)))
          (let ((old (nth at steps)))
            (setf (nth at steps)
                  (cond
                   ((stringp step) old)
                   ((stringp old) step)
                   (t
                    ;; Running again (after done, failed...): timed anew,
                    ;; not with its last run's start and time.
                    (when (and (equal (format "%s" (plist-get step :status)) "running")
                               (not (equal (format "%s" (plist-get old :status)) "running"))
                               (not (plist-member step :started)))
                      (setq old (agent-ui--plist-delete (agent-ui--plist-delete old :started) :seconds)))
                    (cl-loop for (k v) on step by #'cddr
                               do (setq old (plist-put (copy-sequence old) k
                                                       (if (eq k :steps)
                                                           (agent-ui-steps--merge (plist-get old :steps) v)
                                                         v))))
                      old)))))))
    steps))

(defun agent-ui-steps--under (steps parent new)
  "STEPS with NEW merged into the sub-steps of the one named PARENT, at
any depth; nil if there's none."
  (let ((found nil))
    (cl-labels ((walk (steps)
                  (mapcar (lambda (step)
                            (cond
                             (found step)
                             ((equal (agent-ui-steps--name step) parent)
                              (setq found t)
                              (let ((step (if (stringp step) (list :name step) step)))
                                (plist-put (copy-sequence step) :steps
                                           (agent-ui-steps--merge (plist-get step :steps) new))))
                             ((and (agent-ui--plist-p step) (plist-get step :steps))
                              (plist-put (copy-sequence step) :steps (walk (plist-get step :steps))))
                             (t step)))
                          steps)))
      (let ((result (walk steps)))
        (and found result)))))

(defun agent-ui-steps--append (element patch)
  "ELEMENT with PATCH's steps: one whose name is there replaces it (its
status and detail changed, its steps merged), the others after; one with
a \"parent\" goes among that step's own."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :steps))
           do (agent-ui--fail "steps: only steps can be appended to"))
  (let ((steps (plist-get element :steps)))
    (dolist (step (plist-get patch :steps))
      (let ((parent (and (agent-ui--plist-p step) (plist-get step :parent))))
        (if (not parent)
            (setq steps (agent-ui-steps--merge steps (list step)))
          (setq steps (or (agent-ui-steps--under steps parent (list (agent-ui--plist-delete step :parent)))
                          (agent-ui--fail "steps: no step %s to put %s under"
                                          (agent-ui--show-value parent)
                                          (agent-ui--show-value (agent-ui-steps--name step))))))))
    (plist-put (copy-sequence element) :steps steps)))

;; ====== APPROVING THE PLAN ======
;; With approve: the steps are a plan the user approves before the work
;; starts. They drop steps (x on one; again: back) and reword them (e), add a
;; note, then Approve: the steps become the plan as approved (dropped ones
;; gone, reworded ones renamed: the agent's appends use those names), and
;; "Answer to steps ID (QUESTION): approved: 1. A; 2. B (edited, was: X).
;; Dropped: C. Note: ..." goes into the session's prompt (sent at once). Or Reject: "...: rejected. Note: why".
;; Then it's answered, and runs as usual. The user's changes are the
;; element's own (:dropped, :edits), saved with the session.

(defconst agent-ui-steps--question "Go ahead with this plan?")

(defun agent-ui-steps--approve-props (props)
  "PROPS' approve as (:question), or nil if it has none: its answer sent at
once."
  (let ((approve (plist-get props :approve)))
    (cond ((memq approve '(nil :false)) nil)
          ((eq approve t) (list :question agent-ui-steps--question))
          (t (list :question (or (plist-get approve :question) agent-ui-steps--question))))))

(defun agent-ui-steps--check-approve (props)
  (let ((approve (plist-get props :approve)))
    (unless (or (memq approve '(nil t :false))
                (and (agent-ui--plist-p approve)
                     (cl-every (lambda (k) (eq k :question))
                               (cl-loop for (k _) on approve by #'cddr collect k))
                     (or (null (plist-get approve :question)) (stringp (plist-get approve :question)))))
      (agent-ui--fail "steps: approve is true, or {\"question\": ...} (its answer sent at once)"))
    (unless (cl-every #'stringp (plist-get props :dropped))
      (agent-ui--fail "steps: dropped is the steps' names"))
    (unless (cl-every (lambda (e) (and (agent-ui--plist-p e) (stringp (plist-get e :name)) (stringp (plist-get e :text))))
                      (plist-get props :edits))
      (agent-ui--fail "steps: edits are {\"name\": ..., \"text\": ...}"))
    (when (and (plist-get props :answered) (not (member (plist-get props :answered) '("approved" "rejected"))))
      (agent-ui--fail "steps: answered is \"approved\" or \"rejected\""))))

(defun agent-ui-steps--edited (props name)
  "Step NAME's rewording in PROPS' edits, or nil."
  (plist-get (seq-find (lambda (e) (equal (plist-get e :name) name)) (plist-get props :edits)) :text))

(defun agent-ui-steps--as-planned (props)
  "PROPS' steps as the user has them: a dropped one skipped, \"dropped\";
a reworded one renamed, \"edited\"."
  (mapcar (lambda (step)
            (let* ((name (plist-get step :name))
                   (dropped (member name (plist-get props :dropped)))
                   (text (agent-ui-steps--edited props name))
                   (step (copy-sequence step)))
              (when text
                (setq step (plist-put step :name text)))
              (when (or dropped text)
                (setq step (plist-put step :detail
                                      (string-join (delq nil (list (and dropped "dropped") (and text "edited")
                                                                   (plist-get step :detail)))
                                                   " · "))))
              (when dropped
                (setq step (plist-put step :status 'skipped)))
              step))
          (plist-get props :steps)))

(defun agent-ui-steps--toggle-drop (props ctx name)
  (let ((dropped (plist-get props :dropped)))
    (agent-ui-ask-change ctx (list :dropped (if (member name dropped)
                                                (remove name dropped)
                                              (append dropped (list name)))))))

(defun agent-ui-steps--edit (props ctx name)
  (let ((text (string-trim (read-string "Step: " (or (agent-ui-steps--edited props name) name)))))
    (when (string-empty-p text)
      (user-error "A step needs words: x drops it"))
    (agent-ui-ask-change
     ctx (list :edits (append (seq-remove (lambda (e) (equal (plist-get e :name) name)) (plist-get props :edits))
                              (unless (equal text name) (list (list :name name :text text))))))))

(defun agent-ui-steps--note (props)
  (let ((note (plist-get props :note-text)))
    (and note (not (string-blank-p note)) note)))

(defun agent-ui-steps--approved (props ctx)
  "Approve: the plan as the user has it into the session's prompt; the steps
become it."
  (let* ((approve (agent-ui-steps--approve-props props))
         (dropped (plist-get props :dropped))
         (kept (seq-remove (lambda (s) (member (plist-get s :name) dropped)) (plist-get props :steps)))
         (gone (seq-filter (lambda (s) (member (plist-get s :name) dropped)) (plist-get props :steps)))
         (note (agent-ui-steps--note props)))
    (unless kept
      (user-error "Every step is dropped: reject the plan instead"))
    (funcall agent-ui-action-function
             (concat (format "Answer to steps %s (%s): approved: " (plist-get ctx :id) (plist-get approve :question))
                     (string-join
                      (cl-loop for step in kept
                               for n from 1
                               collect (let* ((name (plist-get step :name))
                                              (text (agent-ui-steps--edited props name)))
                                         (if text
                                             (format "%d. %s (edited, was: %s)" n text name)
                                           (format "%d. %s" n name))))
                      "; ")
                     (if gone (concat ". Dropped: " (mapconcat (lambda (s) (plist-get s :name)) gone "; ")) "")
                     (if note (concat ". Note: " note) ""))
             t)
    (agent-ui-ask-change
     ctx (list :steps (mapcar (lambda (step)
                                (if-let* ((text (agent-ui-steps--edited props (plist-get step :name))))
                                    (plist-put (copy-sequence step) :name text)
                                  step))
                              kept)
               :dropped nil :edits nil :answered "approved"))))

(defun agent-ui-steps--rejected (props ctx)
  "Reject: said in the session's prompt, with a note (asked if none)."
  (let* ((approve (agent-ui-steps--approve-props props))
         (note (or (agent-ui-steps--note props)
                   (let ((why (string-trim (read-string "Why not (for the agent; empty: no note): "))))
                     (and (not (string-empty-p why)) why)))))
    (funcall agent-ui-action-function
             (format "Answer to steps %s (%s): rejected%s" (plist-get ctx :id) (plist-get approve :question)
                     (if note (concat ". Note: " note) ""))
             t)
    (agent-ui-ask-change ctx (list :note-text note :answered "rejected"))))

(defun agent-ui-steps--approve-text (props ctx)
  "PROPS' steps with approve: its question, the plan as the user has it
\(x and e on a step), Approve and Reject; answered, what was. Its steps
whole, wrapped where long (what's approved is read in full), in the
text's colour until it's answered."
  (let* ((approve (agent-ui-steps--approve-props props))
         (width (plist-get ctx :width))
         (answered (plist-get props :answered))
         (still (or answered (plist-get ctx :still)))
         (drawn (agent-ui-steps--drawn
                 (if answered props (plist-put (copy-sequence props) :steps (agent-ui-steps--as-planned props)))
                 ctx t (not answered)))
         (texts (car drawn))
         (flat (agent-ui-steps--flat (plist-get props :steps) 0)))
    (unless still
      ;; A plan's step (not a sub-step): x drops it, e rewords it, on any of
      ;; its lines.
      (setq texts (cl-loop for text in texts
                           for entry = (pop flat)
                           collect (if (and entry (= (car entry) 0))
                                       (let ((name (plist-get (cdr entry) :name)))
                                         (propertize text
                                                     'agent-ui-drop (lambda () (agent-ui-steps--toggle-drop props ctx name))
                                                     'agent-ui-edit (lambda () (agent-ui-steps--edit props ctx name))
                                                     'help-echo "x: drop it (again: back), e: reword it"))
                                     text))))
    (string-join
     (append
      (unless answered
        (list (propertize (agent-ui-wrap (plist-get approve :question) width) 'face 'bold)))
      (if (plist-get props :steps) texts (list (propertize "no steps yet" 'face 'agent-ui-muted)))
      (and (cdr drawn) (list (cdr drawn)))
      (cond
       (answered
        (let ((note (agent-ui-steps--note props)))
          (list (concat (if (equal answered "approved")
                            (propertize "✓ " 'face 'agent-ui-success)
                          (propertize "✗ " 'face 'agent-ui-muted))
                        (propertize (agent-ui-truncate
                                     (concat (if (equal answered "approved") "Approved" "Rejected")
                                             (if note (concat " · note: " note) ""))
                                     (- width 2))
                                    'face 'agent-ui-muted)))))
       ((plist-get ctx :still) nil)
       (t
        (list (propertize (agent-ui-wrap "x drops the step at the cursor (again: back), e rewords it" width)
                          'face 'agent-ui-muted)
              (agent-ui-ask-note-button props ctx)
              (concat (agent-ui-button (propertize "⏵ Approve" 'face 'agent-ui-action)
                                       (lambda () (agent-ui-steps--approved props ctx))
                                       "RET: approve the plan as it is now")
                      "   "
                      (agent-ui-button (propertize "⏵ Reject" 'face 'agent-ui-action)
                                       (lambda () (agent-ui-steps--rejected props ctx))
                                       "RET: reject it, saying why"))))))
     "\n")))

(defun agent-ui-steps--draw (props ctx)
  (if (agent-ui-steps--approve-props props)
      (agent-ui-steps--approve-text props ctx)
    (agent-ui-steps--text props ctx)))

(agent-ui-define steps
  "A checklist whose steps change state as work goes on. A step is a name
\(pending), or {\"name\", \"status\", \"detail\", \"seconds\", \"steps\"}:
status one of pending, running (a spinner), done, failed, skipped; detail a
note after it; seconds how long it took (else timed from running to done);
steps its own, drawn under it. Appending a step whose name is there changes
it in its place: append {\"steps\": [{\"name\": \"Build\", \"status\":
\"done\"}]}; with \"parent\": \"Build\", among that step's own. With APPROVE,
a plan the user approves first (dropping, rewording steps): \"Answer to steps
ID (QUESTION): approved: 1. A; 2. B (edited, was: X). Dropped: C. Note: ...\"
\(or rejected) comes into your prompt; the steps are then the approved ones,
and the plan may close (as every question answered): to tick them, show
them again, without APPROVE."
  :props ((steps list "The steps, in order")
          (approve any "A plan for the user to approve first: true, or {\"question\": ...}")
          (dropped list "The steps the user dropped (theirs)")
          (edits list "The steps the user reworded, {\"name\": ..., \"text\": ...} (theirs)")
          (note-text string "The user's note")
          (answered string "approved or rejected (then it can't be changed)"))
  :example (:title "Release"
            :steps ((:name "Run the tests" :status "done" :detail "412 passed" :seconds 41)
                    (:name "Build the release" :status "running"
                     :steps ((:name "compile" :status "done" :seconds 8) (:name "link" :status "running")))
                    "Publish"))
  :animated (lambda (props)
              (seq-some (lambda (s) (eq (plist-get (cdr s) :status) 'running))
                        (agent-ui-steps--flat (plist-get props :steps) 0)))
  :check (lambda (props)
           (agent-ui-steps--check-approve props)
           (plist-put props :steps
                      (cl-loop for step in (plist-get props :steps)
                               for i from 1
                               collect (agent-ui-steps--normalize step (format "step %d" i) 0))))
  :append #'agent-ui-steps--append
  ;; Finished: every step (its own too) done or skipped; one failed: failed.
  ;; A plan to approve isn't, nor is one without steps.
  :finished (lambda (props)
              (let ((statuses (mapcar (lambda (s) (plist-get (cdr s) :status))
                                      (agent-ui-steps--flat (plist-get props :steps) 0))))
                (cond ((or (null statuses) (agent-ui-steps--approve-props props)) nil)
                      ((memq 'failed statuses) 'failed)
                      ((seq-every-p (lambda (s) (memq s '(done skipped))) statuses) 'done))))
  :prepare (lambda (element)
             (let ((steps (plist-get element :steps)))
               (if (listp steps)
                   (plist-put (copy-sequence element) :steps
                              (agent-ui-steps--timed steps (funcall agent-ui-clock)))
                 element)))
  :text #'agent-ui-steps--draw)
