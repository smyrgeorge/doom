;;; $DOOMDIR/config/agent-ui/elements/tags.el -*- lexical-binding: t; -*-
;; Agent UI's tags: a row of chips (a project's labels, a run's statuses, the
;; filters in use, the versions involved). Loaded from
;; config/agent-ui/elements.el.
;;
;; Each a label in a colour (a face: muted, success, warning, error, accent;
;; or a colour), a count in it: core.el's pills ([bug 3] in a terminal, a
;; rounded tag in the GUI). Wrapped to the width, a chip never split. A chip
;; with a PROMPT is a button putting it into the session's prompt (as an
;; action: queued while the agent works). Appending a tag whose label is
;; there changes it in its place (its count).
;;
;;   [bug 12] [feature 4] [agent-ui 31] [P1 2]

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-tags--keys '(:label :face :color :count :prompt :submit)
  "What a tag has.")

(defun agent-ui-tags--label (tag)
  "TAG's label: TAG itself (a string), or its :label."
  (if (stringp tag) tag (and (agent-ui--plist-p tag) (plist-get tag :label))))

(defun agent-ui-tags--normalize (tag i)
  "TAG (a label, or {label, face, color, count, prompt, submit}) as a plist;
an error naming it (the I-th) if it's wrong."
  (cond
   ((and (stringp tag) (not (string-blank-p tag))) (list :label tag))
   ((agent-ui--plist-p tag)
    (cl-loop for (k _) on tag by #'cddr
             unless (memq k agent-ui-tags--keys)
             do (agent-ui--fail "tags: tag %d has %s: a tag has label, face, color, count, prompt, submit"
                                i (agent-ui--show-value (substring (symbol-name k) 1))))
    (let ((label (plist-get tag :label))
          (face (plist-get tag :face))
          (color (plist-get tag :color))
          (count (plist-get tag :count))
          (prompt (plist-get tag :prompt)))
      (unless (and (stringp label) (not (string-blank-p label)))
        (agent-ui--fail "tags: tag %d has no label" i))
      (unless (or (null face) (member (format "%s" face) '("plain" "muted" "success" "warning" "error" "accent")))
        (agent-ui--fail "tags: tag %d's face is plain, muted, success, warning, error or accent" i))
      (unless (or (null color) (and (stringp color) (color-defined-p color)) (string-prefix-p "#" (format "%s" color)))
        (agent-ui--fail "tags: tag %d's color isn't a colour: %s" i (agent-ui--show-value color)))
      (unless (or (null count) (numberp count) (stringp count))
        (agent-ui--fail "tags: tag %d's count is a number" i))
      (unless (or (null prompt) (and (stringp prompt) (not (string-blank-p prompt))))
        (agent-ui--fail "tags: tag %d's prompt is text" i))
      (append (list :label label)
              (and face (list :face face))
              (and color (list :color color))
              (and count (list :count count))
              (and prompt (list :prompt prompt :submit (eq (plist-get tag :submit) t))))))
   (t (agent-ui--fail "tags: tag %d must be a label, or {\"label\": ..., \"face\": ..., \"count\": ...}" i))))

(defun agent-ui-tags--check (props)
  (let ((tags (cl-loop for tag in (plist-get props :tags)
                       for i from 1
                       collect (agent-ui-tags--normalize tag i))))
    (let ((labels (mapcar (lambda (tag) (plist-get tag :label)) tags)))
      (when (/= (length labels) (length (delete-dups (copy-sequence labels))))
        (agent-ui--fail "tags: two tags have the same label")))
    (plist-put props :tags tags)))

(defun agent-ui-tags--chip (tag ctx width &optional filled)
  "TAG as a chip, its label cut to fit WIDTH; FILLED if so."
  (let* ((count (plist-get tag :count))
         (extra (+ 2 (if count (1+ (string-width (format "%s" count))) 0)))
         (label (agent-ui-truncate (plist-get tag :label) (max 1 (- width extra))))
         (face (cond ((plist-get tag :color))
                     ((equal (format "%s" (plist-get tag :face)) "plain") 'default)
                     ((agent-ui-face (plist-get tag :face)))
                     (t 'agent-ui-accent))))
    (agent-ui-pill label ctx :face face :count count :filled filled)))

(defun agent-ui-tags--rows (chips width)
  "CHIPS on lines WIDTH wide, a space between them, none split."
  (let ((lines nil) (line nil) (used 0))
    (dolist (chip chips)
      (let ((w (string-width chip)))
        (when (and line (> (+ used 1 w) width))
          (push (string-join (nreverse line) " ") lines)
          (setq line nil used 0))
        (setq used (+ used (if line 1 0) w))
        (push chip line)))
    (when line (push (string-join (nreverse line) " ") lines))
    (nreverse lines)))

(defun agent-ui-tags--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (still (plist-get ctx :still))
         (tags (plist-get props :tags)))
    (if (null tags)
        (propertize "no tags" 'face 'agent-ui-muted)
      (string-join
       (agent-ui-tags--rows
        (mapcar (lambda (tag)
                  (let ((chip (agent-ui-tags--chip tag ctx width)))
                    (if (and (plist-get tag :prompt) (not still))
                        (let ((prompt (plist-get tag :prompt))
                              (submit (plist-get tag :submit)))
                          (agent-ui-button chip (lambda () (funcall agent-ui-action-function prompt submit))
                                           (format "RET: %s \"%s\"" (if submit "send" "put into the prompt")
                                                   (truncate-string-to-width prompt 60 nil nil "…"))))
                      chip)))
                tags)
        width)
       "\n"))))

(defun agent-ui-tags--append (element patch)
  "ELEMENT with PATCH's tags: one whose label is there changes in its place
\(its count, its face), the others after."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :tags))
           do (agent-ui--fail "tags: only tags can be appended to"))
  (let ((tags (copy-sequence (plist-get element :tags))))
    (dolist (new (plist-get patch :tags))
      (let* ((label (agent-ui-tags--label new))
             (at (and label (cl-position label tags :key #'agent-ui-tags--label :test #'equal))))
        (cond
         ((not at) (setq tags (append tags (list new))))
         ((stringp new))
         (t (let ((old (nth at tags)))
              (when (stringp old) (setq old (list :label old)))
              (cl-loop for (k v) on new by #'cddr
                       do (setq old (plist-put (copy-sequence old) k v)))
              (setf (nth at tags) old))))))
    (plist-put (copy-sequence element) :tags tags)))

(agent-ui-define tags
  "A row of chips: TAGS, labels or {\"label\", \"face\" (muted, success,
warning, error, accent), \"color\", \"count\", \"prompt\"}: a project's labels,
a run's statuses, the filters in use. A chip with a prompt is a button
putting it into your prompt. Append a tag whose label is there to change it
\(its count)."
  :props ((tags list "The chips: labels, or {\"label\": ..., \"face\": ..., \"count\": ...}"))
  :example (:title "Labels"
            :tags ((:label "bug" :face "error" :count 12)
                   (:label "feature" :face "success" :count 4)
                   (:label "agent-ui" :count 31)
                   (:label "P1" :face "warning" :count 2)
                   (:label "docs" :face "muted")))
  :check #'agent-ui-tags--check
  :append #'agent-ui-tags--append
  :text #'agent-ui-tags--draw)
