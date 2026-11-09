;;; $DOOMDIR/config/agent-ui/elements/text.el -*- lexical-binding: t; -*-
;; Agent UI's text: a paragraph, its lines wrapped to the width, in a face
;; saying what it is (a success, a warning...). Loaded from
;; config/agent-ui/elements.el.

(require 'subr-x)

(defun agent-ui-text--text (props ctx)
  (let ((face (pcase (plist-get props :face)
                ('muted 'agent-ui-muted)
                ('success 'agent-ui-success)
                ('warning 'agent-ui-warning)
                ('error 'agent-ui-error)
                (_ nil)))
        (text (agent-ui-wrap (plist-get props :text) (plist-get ctx :width))))
    (if face (propertize text 'face face) text)))

(agent-ui-define text
  "Plain text, its lines wrapped to the width: a note, a result, a status
line. FACE says what it is: plain, muted (secondary), success, warning,
error. For formatting (headings, lists, code), use markdown."
  :props ((text string "The text; newlines kept" :required t)
          (face (choice plain muted success warning error) "What it is, its colour"
                :default plain))
  :example (:id "status" :text "All 412 tests pass." :face "success")
  :text #'agent-ui-text--text)
