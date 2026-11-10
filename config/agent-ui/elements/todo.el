;;; $DOOMDIR/config/agent-ui/elements/todo.el -*- lexical-binding: t; -*-
;; Agent UI's todo: a checklist the agent and the user both tick. Loaded from
;; config/agent-ui/elements.el.
;;
;; The agent lists what's to do and ticks items by appending them (by their
;; label: one that's there changes in its place). The user ticks them too
;; (RET, a click) and adds some (Add). The user's changes are the element's
;; own (:changes, saved with the session) until Send puts them into the
;; session's prompt, "Changes to todo ID by the user: done: A; not done: B;
;; added: C" (sent at once); then they're cleared, and both go on
;; ticking: it's never locked. Who ticked an item, or added it, shows after
;; it. Its buttons work in a canvas (as the elements that ask:
;; config/agent-ui/ask.el).
;;
;;   [x] Parse the config
;;   [x] Write the tests       you
;;   [ ] Update the docs
;;   [ ] Check Windows paths   added by you
;;   ✚ Add an item
;;   ⏵ Send your changes (2)

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-todo--keys '(:label :done :by :added)
  "What an item has: by, who ticked it (\"user\" or \"agent\"); added, the
user added it.")

;; ====== CHECKING ======

(defun agent-ui-todo--label (item)
  "ITEM's label: ITEM itself (a string), or its :label."
  (if (stringp item) item (and (agent-ui--plist-p item) (plist-get item :label))))

(defun agent-ui-todo--true (value)
  "VALUE, JSON's true or false (or null), as t or nil."
  (eq value t))

(defun agent-ui-todo--normalize (item i)
  "ITEM (a label, or {label, done, by, added}) as (:label :done [:by] [:added]),
done t or nil; an error naming it (the I-th) if it's wrong."
  (cond
   ((and (stringp item) (not (string-blank-p item))) (list :label item :done nil))
   ((agent-ui--plist-p item)
    (cl-loop for (k _) on item by #'cddr
             unless (memq k agent-ui-todo--keys)
             do (agent-ui--fail "todo: item %d has %s: an item has label, done, by, added"
                                i (agent-ui--show-value (substring (symbol-name k) 1))))
    (let ((label (plist-get item :label))
          (by (plist-get item :by)))
      (unless (and (stringp label) (not (string-blank-p label)))
        (agent-ui--fail "todo: item %d has no label" i))
      (dolist (k '(:done :added))
        (unless (memq (plist-get item k) '(nil t :false))
          (agent-ui--fail "todo: item %d's %s must be true or false" i (substring (symbol-name k) 1))))
      (unless (member by '(nil "user" "agent"))
        (agent-ui--fail "todo: item %d's by must be \"user\" or \"agent\"" i))
      (let ((done (agent-ui-todo--true (plist-get item :done))))
        (append (list :label label :done done)
                ;; Who ticked it: only while it's done.
                (and done by (list :by by))
                (and (agent-ui-todo--true (plist-get item :added)) (list :added t))))))
   (t (agent-ui--fail "todo: item %d must be a label, or {\"label\": ..., \"done\": ...}" i))))

(defun agent-ui-todo--check (props)
  (let ((items (cl-loop for item in (plist-get props :items)
                        for i from 1
                        collect (agent-ui-todo--normalize item i))))
    (let ((labels (mapcar (lambda (i) (plist-get i :label)) items)))
      (when (/= (length labels) (length (delete-dups (copy-sequence labels))))
        (agent-ui--fail "todo: two items have the same label")))
    (cl-loop for change in (plist-get props :changes)
             for i from 1
             unless (and (agent-ui--plist-p change)
                         (stringp (plist-get change :label))
                         (member (plist-get change :change) '("done" "undone" "added")))
             do (agent-ui--fail "todo: change %d must be {\"label\": ..., \"change\": \"done\", \"undone\" or \"added\"}" i))
    (plist-put (plist-put props :items items) :changes (plist-get props :changes))))

;; ====== THE USER'S CHANGES ======

(defun agent-ui-todo--changed (changes label change)
  "CHANGES with LABEL's CHANGE (\"done\", \"undone\", \"added\"): an item
the user added stays added; a tick undone (done then undone) is no change."
  (let ((old (seq-find (lambda (c) (equal (plist-get c :label) label)) changes)))
    (cond
     ((null old) (append changes (list (list :label label :change change))))
     ((equal (plist-get old :change) "added") changes)
     (t (remq old changes)))))

(defun agent-ui-todo--changes-text (id items changes)
  "CHANGES as the agent reads them: \"Changes to todo ID by the user: done:
A, B; not done: C; added: D (done).\""
  (cl-flet ((labels (change)
              (cl-loop for c in changes
                       when (equal (plist-get c :change) change)
                       collect (let ((label (plist-get c :label)))
                                 (if (and (equal change "added")
                                          (plist-get (seq-find (lambda (i) (equal (plist-get i :label) label)) items)
                                                     :done))
                                     (concat label " (done)")
                                   label)))))
    (concat (format "Changes to todo %s by the user: " id)
            (string-join
             (cl-loop for (change . name) in '(("done" . "done") ("undone" . "not done") ("added" . "added"))
                      for these = (labels change)
                      when these collect (concat name ": " (string-join these ", ")))
             "; ")
            ".")))

(defun agent-ui-todo--toggle (props ctx label)
  "The user ticks LABEL's item (or unticks it)."
  (let* ((item (seq-find (lambda (i) (equal (plist-get i :label) label)) (plist-get props :items)))
         (done (not (plist-get item :done))))
    (agent-ui-ask-change
     ctx (list :items (mapcar (lambda (i)
                                (if (eq i item)
                                    (append (list :label label :done done)
                                            (and done (list :by "user"))
                                            (and (plist-get i :added) (list :added t)))
                                  i))
                              (plist-get props :items))
               :changes (agent-ui-todo--changed (plist-get props :changes) label (if done "done" "undone"))))))

(defun agent-ui-todo--add (props ctx)
  "The user adds an item (its label read in the minibuffer)."
  (let ((label (string-trim (read-string "Add to the todo: "))))
    (unless (string-empty-p label)
      (when (seq-find (lambda (i) (equal (plist-get i :label) label)) (plist-get props :items))
        (user-error "Already there: %s" label))
      (agent-ui-ask-change
       ctx (list :items (append (plist-get props :items) (list (list :label label :done nil :added t)))
                 :changes (agent-ui-todo--changed (plist-get props :changes) label "added"))))))

(defun agent-ui-todo--send (props ctx)
  "The user's changes into the session's prompt (sent at once);
then cleared."
  (funcall agent-ui-action-function
           (agent-ui-todo--changes-text (plist-get ctx :id) (plist-get props :items) (plist-get props :changes))
           t)
  (agent-ui-ask-change ctx (list :changes nil)))

;; ====== DRAWING ======

(defun agent-ui-todo--tag (item)
  "Who did what to ITEM, after it: \"you\", \"added by you\"..., or \"\"."
  (let ((ticked (equal (plist-get item :by) "user"))
        (added (plist-get item :added)))
    (cond ((and ticked added) "added and done by you")
          (added "added by you")
          (ticked "you")
          (t ""))))

(defun agent-ui-todo--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (still (plist-get ctx :still))
         (all (plist-get props :items))
         (items (seq-take all agent-ui-max-rows))
         (tags (mapcar #'agent-ui-todo--tag items))
         (tag-width (apply #'max 0 (mapcar #'string-width tags)))
         ;; The labels' column: as wide as the longest, or what's left
         ;; beside the tags; tags left out where there's no room.
         (room (- width 5))
         (tag-width (if (and (> tag-width 0) (>= (- room tag-width 2) 10)) tag-width 0))
         (label-width (min (apply #'max 0 (mapcar (lambda (i) (string-width (plist-get i :label))) items))
                           (if (> tag-width 0) (- room tag-width 2) room)))
         (changes (plist-get props :changes))
         (lines
          (cl-loop
           for item in items
           for tag in tags
           collect
           (let* ((done (plist-get item :done))
                  (label (agent-ui-truncate (plist-get item :label) (max 1 label-width)))
                  (line (concat " " (agent-ui-ask-mark done t) " "
                                (if (or (> tag-width 0) (string-empty-p tag))
                                    (if (string-empty-p tag)
                                        label
                                      (concat (agent-ui-pad label label-width) "  "
                                              (propertize tag 'face 'agent-ui-muted)))
                                  label))))
             (if still
                 line
               (let ((label (plist-get item :label)))
                 (agent-ui-button line (lambda () (agent-ui-todo--toggle props ctx label))
                                  (if done "RET: untick it" "RET: tick it"))))))))
    (string-join
     (append
      (if all lines (list (propertize " nothing to do yet" 'face 'agent-ui-muted)))
      (when (> (length all) (length items))
        (list (propertize (format " … %d items more" (- (length all) (length items))) 'face 'agent-ui-muted)))
      (unless still
        (append
         (list (concat " " (agent-ui-button (concat (propertize "✚ " 'face 'agent-ui-accent)
                                                    (propertize "Add an item" 'face 'agent-ui-muted))
                                            (lambda () (agent-ui-todo--add props ctx))
                                            "RET: add an item")))
         (when changes
           (list (concat " " (agent-ui-button
                              (propertize (format "⏵ Send your changes (%d)" (length changes))
                                          'face 'agent-ui-action)
                              (lambda () (agent-ui-todo--send props ctx))
                              "RET: tell the agent what you changed")))))))
     "\n")))

;; ====== APPENDING ======

(defun agent-ui-todo--append (element patch)
  "ELEMENT with PATCH's items: one whose label is there changes in its place
\(ticked by the agent, unless it says by), the others after. The agent
ticking or unticking an item drops the user's change of it not sent."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :items))
           do (agent-ui--fail "todo: only items can be appended to"))
  (let ((items (copy-sequence (plist-get element :items)))
        (changes (plist-get element :changes)))
    (dolist (new (plist-get patch :items))
      (let* ((label (agent-ui-todo--label new))
             (at (and label (cl-position label items :key #'agent-ui-todo--label :test #'equal))))
        (cond
         ((not at) (setq items (append items (list new))))
         ((stringp new))
         (t
          (let ((old (nth at items)))
            (when (stringp old) (setq old (list :label old)))
            (cl-loop for (k v) on new by #'cddr
                     do (setq old (plist-put (copy-sequence old) k v)))
            (when (and (plist-member new :done) (not (plist-member new :by)))
              (setq old (plist-put old :by "agent")))
            (when (plist-member new :done)
              (setq changes (seq-remove (lambda (c) (and (equal (plist-get c :label) label)
                                                         (member (plist-get c :change) '("done" "undone"))))
                                        changes)))
            (setf (nth at items) old))))))
    (plist-put (plist-put (copy-sequence element) :items items) :changes changes)))

(agent-ui-define todo
  "A checklist you and the user both tick: ITEMS, labels or {\"label\",
\"done\"}. The user ticks them too and adds some; Send puts their changes
into your prompt: \"Changes to todo ID by the user: done: A; not done: B;
added: C.\" (sent at once). Tick one by appending it:
{\"items\": [{\"label\": \"Write the tests\", \"done\": true}]}; a new label
adds it. For a plan you work through together."
  :props ((items list "The items: labels, or {\"label\": ..., \"done\": true}")
          (changes list "The user's changes not sent yet (theirs)"))
  :example (:title "The fix"
            :items ((:label "Reproduce the bug" :done t)
                    (:label "Write a failing test" :done t :by "user")
                    "Fix the parser"
                    (:label "Check Windows paths" :added t)))
  :check #'agent-ui-todo--check
  :append #'agent-ui-todo--append
  :text #'agent-ui-todo--draw)
