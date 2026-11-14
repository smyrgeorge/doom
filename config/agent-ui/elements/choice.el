;;; $DOOMDIR/config/agent-ui/elements/choice.el -*- lexical-binding: t; -*-
;; Agent UI's choice: a question for the user, its options to pick from.
;; Loaded from config/agent-ui/elements.el.
;;
;; One option (MULTIPLE false) or several; a note if NOTE (typed in the
;; minibuffer). RET or a click on an option selects it (toggles it); on
;; Answer, the answer goes into the session's prompt, "Answer to choice ID
;; (QUESTION): A, B. Note: ...", sent at once. Then it says the
;; answer, and can't be changed. Its selection is the element's own (saved
;; with the session, in a snapshot). Its buttons work in a canvas. What it
;; shares with the other elements that ask (picking, the note, the answer):
;; config/agent-ui/ask.el.
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
    ;; Else accepted, then drawing it failed.
    (cl-loop for o in options
             for i from 1
             when (and (agent-ui--plist-p o) (plist-get o :detail) (not (stringp (plist-get o :detail))))
             do (agent-ui--fail "choice: option %d's detail must be text" i))
    (let ((labels (mapcar #'car (agent-ui-choice--options props))))
      (when (/= (length labels) (length (delete-dups (copy-sequence labels))))
        (agent-ui--fail "choice: two options have the same label"))
      (agent-ui-ask-check "choice" (plist-get props :selected) labels (plist-get props :multiple))))
  props)

(defun agent-ui-choice--option (props ctx option label-width)
  "OPTION, (LABEL . DETAIL), as lines: its mark, its label and detail
wrapped (`agent-ui-ask-item-lines'), a button choosing it."
  (let* ((multiple (plist-get props :multiple))
         (head (concat " " (agent-ui-ask-mark (agent-ui-ask-picked-p props (car option)) multiple) " ")))
    (agent-ui-ask-pick-button
     (agent-ui-ask-item-lines head (car option) (cdr option) label-width (plist-get ctx :width))
     props ctx (car option) multiple)))

(defun agent-ui-choice--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (options (agent-ui-choice--options props))
         ;; The labels' column, for details after them: as wide as the
         ;; longest of those with one (all of them: a gap before the details).
         (label-width (agent-ui-ask-label-width options 5 width))
         (question (propertize (agent-ui-wrap (plist-get props :question) width) 'face 'bold)))
    (if (agent-ui-ask-answered-p props)
        (concat question "\n" (agent-ui-ask-answered-line props width))
      (string-join
       (append (list question)
               (mapcar (lambda (o) (agent-ui-choice--option props ctx o label-width)) options)
               ;; Its note and Answer, buttons: not in a still picture.
               (unless (plist-get ctx :still)
                 (append
                  (when (plist-get props :note) (list (concat " " (agent-ui-ask-note-button props ctx))))
                  (list (concat " " (agent-ui-ask-answer-button
                                     props ctx
                                     :what (format "choice %s" (plist-get ctx :id))
                                     :question (plist-get props :question)))))))
       "\n"))))

(agent-ui-define choice
  "A question for the user: QUESTION and its OPTIONS (labels, or
{\"label\", \"detail\"}), one to pick (or several, MULTIPLE), a note if
NOTE. The user picks (RET, a click) and presses Answer: \"Answer to choice
ID (QUESTION): A, B. Note: ...\" comes into your prompt (sent at once). Then it shows the answer. For a decision you need from the user:
which approach, approve a plan."
  :props ((question string "The question" :required t)
          (options list "The options: labels, or {\"label\": ..., \"detail\": ...}" :required t)
          (multiple boolean "Several can be chosen" :default :false)
          (note boolean "Let the user add a note" :default :false)
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
