;;; $DOOMDIR/config/agent-ui/elements/choice.el -*- lexical-binding: t; -*-
;; Agent UI's choice: a question for the user, its options to pick from.
;; Loaded from config/agent-ui/elements.el.
;;
;; One option (MULTIPLE false) or several; a note if NOTE (typed in the
;; minibuffer). RET or a click on an option selects it (toggles it); on
;; Answer, the answer goes into the session's prompt, "Answer to choice ID
;; (QUESTION): A, B. Note: ...", sent at once if SUBMIT. Then it says the
;; answer, and can't be changed. Its selection is the element's own (saved
;; with the session, in a snapshot). Its buttons work in a canvas.
;;
;;   Which fix?
;;    (•) Change the test's message   keeps the new error text
;;    ( ) Revert the error change
;;    ⏵ Answer

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-choice--options (props)
  "PROPS' options as (LABEL . DETAIL)."
  (mapcar (lambda (o) (if (stringp o) (cons o nil) (cons (plist-get o :label) (plist-get o :detail))))
          (plist-get props :options)))

(defun agent-ui-choice--check (props)
  (let ((options (plist-get props :options)))
    (unless options
      (agent-ui--fail "choice: give options: [\"A\", \"B\"] or [{\"label\": ..., \"detail\": ...}]"))
    (cl-loop for o in options
             for i from 1
             unless (or (and (stringp o) (not (string-blank-p o)))
                        (and (agent-ui--plist-p o) (stringp (plist-get o :label))
                             (not (string-blank-p (plist-get o :label)))
                             (cl-every (lambda (k) (memq k '(:label :detail)))
                                       (cl-loop for (k _) on o by #'cddr collect k))))
             do (agent-ui--fail "choice: option %d must be a label, or {\"label\": ..., \"detail\": ...}" i))
    (let ((labels (mapcar #'car (agent-ui-choice--options props))))
      (when (/= (length labels) (length (delete-dups (copy-sequence labels))))
        (agent-ui--fail "choice: two options have the same label"))
      (dolist (s (plist-get props :selected))
        (unless (member s labels)
          (agent-ui--fail "choice: selected %s isn't an option" (agent-ui--show-value s))))
      (when (and (not (plist-get props :multiple)) (cdr (plist-get props :selected)))
        (agent-ui--fail "choice: one option only can be selected (multiple is false)"))))
  props)

(defun agent-ui-choice--change (ctx patch)
  "Change this choice (CTX's element) by PATCH, in its canvas."
  (let ((id (plist-get ctx :id)))
    (unless (and id (derived-mode-p 'agent-ui-canvas-mode))
      (user-error "A choice is answered in its canvas"))
    (agent-ui-update id patch :canvas (current-buffer))))

(defun agent-ui-choice--answer-text (props id)
  (let ((picked (plist-get props :selected))
        (note (plist-get props :note)))
    (concat (format "Answer to choice %s (%s): " id (plist-get props :question))
            (if picked (string-join picked ", ") "(none chosen)")
            (if (and note (not (string-empty-p note))) (concat ". Note: " note) ""))))

(defun agent-ui-choice--option (props ctx option label-width)
  "OPTION, (LABEL . DETAIL), as a line: its mark, a button choosing it."
  (let* ((width (plist-get ctx :width))
         (multiple (plist-get props :multiple))
         (selected (plist-get props :selected))
         (on (member (car option) selected))
         (mark (if multiple (if on "[x]" "[ ]") (if on "(•)" "( )")))
         (head (concat " " (propertize mark 'face (if on 'agent-ui-accent 'agent-ui-muted)) " "))
         ;; Wrapped in what's after its mark, its lines under the label's
         ;; start (a label was never cut nor wrapped: 66 columns at 30).
         (hang (lambda (text)
                 (string-join (split-string (agent-ui-wrap text (- width 5)) "\n")
                              (concat "\n" (make-string 5 ?\s)))))
         (room (- width 5 label-width 2))
         (line (cond
                ;; Its detail in a column after the labels, if there's room.
                ((and (cdr option) (>= room 10))
                 (concat head (agent-ui-pad (car option) label-width) "  "
                         (propertize (agent-ui-truncate (cdr option) room) 'face 'agent-ui-muted)))
                ;; Else its label wrapped, its detail under it.
                (t (concat head (funcall hang (car option))
                           (if (cdr option)
                               (concat "\n" (make-string 5 ?\s)
                                       (propertize (funcall hang (cdr option)) 'face 'agent-ui-muted))
                             "")))))
         (picked (cond (multiple (if on (remove (car option) selected) (append selected (list (car option)))))
                       (on nil)
                       (t (list (car option))))))
    (agent-ui-button line (lambda () (agent-ui-choice--change ctx (list :selected picked)))
                     (if multiple "RET: (un)check it" "RET: choose it"))))

(defun agent-ui-choice--note (props ctx)
  "The note's line: a button writing it."
  (let ((note (plist-get props :note-text)))
    (agent-ui-button
     (concat (propertize "✎ " 'face 'agent-ui-accent)
             (if (and note (not (string-empty-p note)))
                 (concat "Note: " (agent-ui-truncate note (- (plist-get ctx :width) 10)))
               (propertize "Add a note" 'face 'agent-ui-muted)))
     (lambda () (agent-ui-choice--change ctx (list :note-text (read-string "Note: " note))))
     "RET: write a note")))

(defun agent-ui-choice--answered (props)
  "What PROPS' answer says, once given: the options chosen, the note."
  (let ((selected (plist-get props :selected))
        (note (plist-get props :note-text)))
    (concat (string-join selected ", ")
            (if (and note (not (string-empty-p note)))
                (concat (if selected " · " "") "note: " note)
              ""))))

(defun agent-ui-choice--answer (props ctx)
  "The Answer button: the answer into the prompt, then shown as given."
  (agent-ui-button
   (propertize (if (plist-get props :submit) "⏵ Send the answer" "⏵ Answer") 'face 'agent-ui-action)
   (lambda ()
     (unless (or (plist-get props :selected) (plist-get props :note-text))
       (user-error "Choose an option first"))
     (funcall agent-ui-action-function
              (agent-ui-choice--answer-text
               (list :question (plist-get props :question) :selected (plist-get props :selected)
                     :note (plist-get props :note-text))
               (plist-get ctx :id))
              (plist-get props :submit))
     (agent-ui-choice--change ctx (list :answered (agent-ui-choice--answered props))))
   "RET: put the answer into the prompt"))

(defun agent-ui-choice--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (options (agent-ui-choice--options props))
         ;; The labels' column, for details after them: as wide as the
         ;; longest of those with one (all of them: a gap before the details).
         (label-width (min (apply #'max 0 (mapcar (lambda (o) (string-width (car o)))
                                                  (seq-filter #'cdr options)))
                           (/ width 2)))
         (question (propertize (agent-ui-wrap (plist-get props :question) width) 'face 'bold)))
    (if-let* ((answered (plist-get props :answered)))
        (concat question "\n"
                (propertize "✓ " 'face 'agent-ui-success)
                (propertize (agent-ui-wrap (concat "Answered: " answered) (- width 2)) 'face 'agent-ui-muted))
      (string-join
       (append (list question)
               (mapcar (lambda (o) (agent-ui-choice--option props ctx o label-width)) options)
               ;; Its note and Answer, buttons: not in a still picture.
               (unless (plist-get ctx :still)
                 (append
                  (when (plist-get props :note) (list (concat " " (agent-ui-choice--note props ctx))))
                  (list (concat " " (agent-ui-choice--answer props ctx))))))
       "\n"))))

(agent-ui-define choice
  "A question for the user: QUESTION and its OPTIONS (labels, or
{\"label\", \"detail\"}), one to pick (or several, MULTIPLE), a note if
NOTE. The user picks (RET, a click) and presses Answer: \"Answer to choice
ID (QUESTION): A, B. Note: ...\" comes into your prompt (sent at once if
SUBMIT). Then it shows the answer. For a decision you need from the user:
which approach, approve a plan."
  :props ((question string "The question" :required t)
          (options list "The options: labels, or {\"label\": ..., \"detail\": ...}" :required t)
          (multiple boolean "Several can be chosen" :default :false)
          (note boolean "Let the user add a note" :default :false)
          (submit boolean "Send the answer at once (else it waits in the prompt)" :default :false)
          (selected list "The options chosen so far (labels): a default, or the user's")
          (note-text string "The user's note")
          (answered string "The answer given (then it can't be changed)"))
  :example (:title "Before I go on"
            :question "The checker test expects the old error message. Which fix?"
            :options ((:label "Change the test" :detail "keeps the new message")
                      (:label "Revert the message" :detail "as it was before"))
            :note t)
  :check #'agent-ui-choice--check
  :text #'agent-ui-choice--draw)
