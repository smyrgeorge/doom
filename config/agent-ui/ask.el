;;; $DOOMDIR/config/agent-ui/ask.el -*- lexical-binding: t; -*-
;; Agent UI's elements that ask: what they share. Loaded from
;; config/agent-ui.el, before the element types. No Doom here (see
;; docs/agent-ui.md).
;;
;; An element that asks (choice; a table, files or issues with select; a form,
;; a rank...) lets the user pick items (one, or several), add a note, and
;; answer: "Answer to WHAT (QUESTION): A, B. Note: ..." goes into the session's
;; prompt (`agent-ui-action-function'), sent at once if it says so; then the
;; element shows the answer, locked. Its state lives in the element's own
;; properties, so it survives a redraw, a sort, an append, a resumed session,
;; and a snapshot draws it (without its buttons):
;;
;;   :selected   the items picked (each as the answer names it: a label, a key)
;;   :note-text  the user's note
;;   :answered   the answer given, as shown (then it can't be changed)
;;
;; Its settings (the question, multiple, note, submit) are the type's: choice's
;; own properties, a table's select. Its buttons work in a canvas only.

(require 'cl-lib)
(require 'subr-x)

;; ====== THE STATE ======

(defun agent-ui-ask-check (what selected items multiple)
  "SELECTED (an element's :selected) checked against ITEMS (the answers it can
pick): each one of them, one only unless MULTIPLE; else an error naming WHAT
\(the type: \"choice\")."
  (dolist (item selected)
    (unless (member item items)
      (agent-ui--fail "%s: selected %s isn't an option" what (agent-ui--show-value item))))
  (when (and (not multiple) (cdr selected))
    (agent-ui--fail "%s: one option only can be selected (multiple is false)" what)))

(defun agent-ui-ask-picked-p (props item)
  "Whether ITEM is picked in PROPS (its :selected)."
  (and (member item (plist-get props :selected)) t))

(defun agent-ui-ask-toggled (props item multiple)
  "PROPS' :selected with ITEM toggled: added or taken out if MULTIPLE (in the
order picked); else ITEM alone, or nothing if it was it."
  (let ((selected (plist-get props :selected)))
    (cond (multiple (if (member item selected) (remove item selected) (append selected (list item))))
          ((member item selected) nil)
          (t (list item)))))

(defun agent-ui-ask-mark (on multiple)
  "The mark of an item, ON or not: [x] / [ ] if MULTIPLE, else (•) / ( ),
in its face."
  (propertize (if multiple (if on "[x]" "[ ]") (if on "(•)" "( )"))
              'face (if on 'agent-ui-accent 'agent-ui-muted)))

(defun agent-ui-ask-answered-p (props)
  "Whether PROPS' answer was given (then it's locked)."
  (and (plist-get props :answered) t))

;; ====== CHANGING IT ======

(defun agent-ui-ask-change (ctx patch)
  "Change the element asking (CTX's :id) by PATCH, in its canvas: its
buttons work there only (a render's are text)."
  (let ((id (plist-get ctx :id)))
    (unless (and id (derived-mode-p 'agent-ui-canvas-mode))
      (user-error "A question is answered in its canvas"))
    (agent-ui-update id patch :canvas (current-buffer))))

(defun agent-ui-ask-pick-button (text props ctx item multiple)
  "TEXT as a button picking ITEM (toggling it if MULTIPLE)."
  (agent-ui-button text
                   (lambda () (agent-ui-ask-change ctx (list :selected (agent-ui-ask-toggled props item multiple))))
                   (if multiple "RET: (un)check it" "RET: choose it")))

(defun agent-ui-ask-all-none (ctx items)
  "The All and None buttons: every one of ITEMS picked, or none."
  (concat (agent-ui-button (propertize "⏵ All" 'face 'agent-ui-action)
                           (lambda () (agent-ui-ask-change ctx (list :selected items)))
                           "RET: pick them all")
          "   "
          (agent-ui-button (propertize "⏵ None" 'face 'agent-ui-action)
                           (lambda () (agent-ui-ask-change ctx (list :selected nil)))
                           "RET: pick none")))

(defun agent-ui-ask-note-button (props ctx)
  "The note's line: a button writing it (the minibuffer), the note shown."
  (let ((note (plist-get props :note-text)))
    (agent-ui-button
     (concat (propertize "✎ " 'face 'agent-ui-accent)
             (if (and note (not (string-empty-p note)))
                 (concat "Note: " (agent-ui-truncate note (- (plist-get ctx :width) 10)))
               (propertize "Add a note" 'face 'agent-ui-muted)))
     (lambda () (agent-ui-ask-change ctx (list :note-text (read-string "Note: " note))))
     "RET: write a note")))

;; ====== THE ANSWER ======

(defun agent-ui-ask-answer-text (what question picked note)
  "The answer as the agent reads it: \"Answer to WHAT (QUESTION): PICKED.
Note: NOTE\" (PICKED a list of what each picked item answers)."
  (concat (format "Answer to %s (%s): " what question)
          (if picked (string-join picked ", ") "(none chosen)")
          (if (and note (not (string-empty-p note))) (concat ". Note: " note) "")))

(defun agent-ui-ask-answered-text (picked note)
  "The answer as the element shows it once given: PICKED, then NOTE."
  (concat (string-join picked ", ")
          (if (and note (not (string-empty-p note)))
              (concat (if picked " · " "") "note: " note)
            "")))

(cl-defun agent-ui-ask-answer-button (props ctx &key what question submit (answers (plist-get props :selected))
                                            (label (if submit "⏵ Send the answer" "⏵ Answer")))
  "The Answer button (LABEL): nothing picked nor noted, said; else the answer
\(`agent-ui-ask-answer-text' of WHAT, QUESTION, ANSWERS and the note) into the
session's prompt, sent at once if SUBMIT; then the element answered (locked)."
  (agent-ui-button
   (propertize label 'face 'agent-ui-action)
   (lambda ()
     (unless (or answers (plist-get props :note-text))
       (user-error "Choose an option first"))
     (funcall agent-ui-action-function
              (agent-ui-ask-answer-text what question answers (plist-get props :note-text))
              submit)
     (agent-ui-ask-change ctx (list :answered (agent-ui-ask-answered-text answers (plist-get props :note-text)))))
   "RET: put the answer into the prompt"))

(defun agent-ui-ask-answered-line (props width)
  "The answer given (PROPS' :answered), as a line WIDTH wide: ✓ Answered:
..., wrapped."
  (concat (propertize "✓ " 'face 'agent-ui-success)
          (propertize (agent-ui-wrap (concat "Answered: " (plist-get props :answered)) (- width 2))
                      'face 'agent-ui-muted)))
