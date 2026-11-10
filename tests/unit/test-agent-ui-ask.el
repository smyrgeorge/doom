;;; tests/unit/test-agent-ui-ask.el -*- lexical-binding: t; -*-
;; config/agent-ui/ask.el: what the elements that ask share. Each part on its
;; own (the selection checked, toggled, marked; the answer's text), then a
;; type made of them alone (`asker') answered on a canvas: picked, All / None,
;; a note, answered into the session's prompt, locked, kept through a redraw
;; and in its saved JSON.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-aua-canvas (&rest body)
  "BODY with a canvas of its own (`canvas'), no window shown, the type
`asker' defined (killed and forgotten after); what the answers sent in
`sent' ((PROMPT SUBMIT)..., the latest first)."
  (declare (indent 0))
  `(let* ((agent-ui--types (copy-hash-table agent-ui--types))
          (agent-ui-default-canvas (make-temp-name "ask-"))
          (agent-ui-display-function #'ignore)
          (sent nil)
          (agent-ui-action-function (lambda (prompt submit) (push (list prompt submit) sent)))
          (canvas (agent-ui-canvas)))
     (ignore sent)
     (agent-ui-define asker
       "A question made of ask.el's parts alone."
       :props ((question string "The question" :required t)
               (items list "What can be picked" :required t)
               (multiple boolean "Several" :default :false)
               (selected list "Picked")
               (note-text string "The note")
               (answered string "The answer"))
       :check (lambda (props)
                (agent-ui-ask-check "asker" (plist-get props :selected) (plist-get props :items)
                                    (plist-get props :multiple))
                props)
       :text (lambda (props ctx)
               (if (agent-ui-ask-answered-p props)
                   (agent-ui-ask-answered-line props (plist-get ctx :width))
                 (string-join
                  (append (mapcar (lambda (item)
                                    (agent-ui-ask-pick-button
                                     (concat (agent-ui-ask-mark (agent-ui-ask-picked-p props item)
                                                                (plist-get props :multiple))
                                             " " item)
                                     props ctx item (plist-get props :multiple)))
                                  (plist-get props :items))
                          (list (agent-ui-ask-all-none ctx (plist-get props :items))
                                (agent-ui-ask-note-button props ctx)
                                (agent-ui-ask-answer-button props ctx :what (format "asker %s" (plist-get ctx :id))
                                                            :question (plist-get props :question) :submit t)))
                  "\n"))))
     (unwind-protect (with-current-buffer canvas ,@body)
       (kill-buffer canvas))))

(defun +test-aua-press (text)
  "Press the button on TEXT in the current canvas."
  (agent-ui--flush)
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0))
  (agent-ui-button-press)
  (agent-ui--flush))

(defun +test-aua-text ()
  (agent-ui--flush)
  (buffer-substring-no-properties (point-min) (point-max)))

;; ====== EACH PART ======

(ert-deftest agent-ui-ask/the-selection-checked ()
  (cl-flet ((err (selected items multiple)
              (agent-ui-error-message
               (should-error (agent-ui-ask-check "it" selected items multiple) :type 'agent-ui-error))))
    (should (equal (err '("c") '("a" "b") t) "it: selected \"c\" isn't an option"))
    (should (equal (err '("a" "b") '("a" "b") nil) "it: one option only can be selected (multiple is false)"))
    (should-not (agent-ui-ask-check "it" '("a" "b") '("a" "b") t))
    (should-not (agent-ui-ask-check "it" nil '("a") nil))))

(ert-deftest agent-ui-ask/toggled-one-or-several ()
  "Several: added in the order picked, taken out again; one: it alone, or
none if it was it."
  (should (equal (agent-ui-ask-toggled '(:selected ("a")) "b" t) '("a" "b")))
  (should (equal (agent-ui-ask-toggled '(:selected ("a" "b")) "a" t) '("b")))
  (should (equal (agent-ui-ask-toggled '(:selected ("a")) "b" nil) '("b")))
  (should-not (agent-ui-ask-toggled '(:selected ("a")) "a" nil))
  (should (equal (agent-ui-ask-toggled nil "a" nil) '("a")))
  (should (agent-ui-ask-picked-p '(:selected ("a")) "a"))
  (should-not (agent-ui-ask-picked-p '(:selected ("a")) "b")))

(ert-deftest agent-ui-ask/marks ()
  (should (equal (mapcar (lambda (case) (apply #'agent-ui-ask-mark case))
                         '((t t) (nil t) (t nil) (nil nil)))
                 '("[x]" "[ ]" "(•)" "( )")))
  (should (eq (get-text-property 0 'face (agent-ui-ask-mark t t)) 'agent-ui-accent))
  (should (eq (get-text-property 0 'face (agent-ui-ask-mark nil t)) 'agent-ui-muted)))

(ert-deftest agent-ui-ask/the-answers-text ()
  (should (equal (agent-ui-ask-answer-text "bugs" "Which?" '("doom-1" "doom-2") "the small ones")
                 "Answer to bugs (Which?): doom-1, doom-2. Note: the small ones"))
  (should (equal (agent-ui-ask-answer-text "choice q" "Which?" nil "") "Answer to choice q (Which?): (none chosen)"))
  (should (equal (agent-ui-ask-answered-text '("a" "b") "why") "a, b · note: why"))
  (should (equal (agent-ui-ask-answered-text nil "why") "note: why"))
  (should (equal (agent-ui-ask-answered-text '("a") nil) "a")))

(ert-deftest agent-ui-ask/only-in-a-canvas ()
  "Its buttons change their element in its canvas: elsewhere (a render's
text), said."
  (with-temp-buffer
    (should-error (agent-ui-ask-change '(:id "x") '(:selected ("a"))) :type 'user-error))
  (should-error (agent-ui-ask-change nil '(:selected ("a"))) :type 'user-error))

;; ====== A TYPE MADE OF THEM ======

(ert-deftest agent-ui-ask/answered-on-a-canvas ()
  "Picked (several), All and None, a note; answered: the answer into the
session's prompt (sent at once), then shown, locked; kept through a redraw
and in its saved JSON."
  (+test-aua-canvas
    (agent-ui-show '(:id "q" :type "asker" :question "Which ones?" :items ("alpha" "beta" "gamma") :multiple t))
    (should (string-search "[ ] alpha\n[ ] beta\n[ ] gamma\n⏵ All   ⏵ None\n✎ Add a note\n⏵ Send the answer"
                           (+test-aua-text)))
    ;; Nothing picked: said.
    (should-error (+test-aua-press "⏵ Send the answer") :type 'user-error)
    (+test-aua-press "beta")
    (+test-aua-press "alpha")
    (should (equal (plist-get (agent-ui-get "q") :selected) '("beta" "alpha")))
    (should (string-search "[x] alpha\n[x] beta\n[ ] gamma" (+test-aua-text)))
    (+test-aua-press "⏵ All")
    (should (equal (plist-get (agent-ui-get "q") :selected) '("alpha" "beta" "gamma")))
    (+test-aua-press "⏵ None")
    (should-not (plist-get (agent-ui-get "q") :selected))
    (+test-aua-press "gamma")
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "only gamma")))
      (+test-aua-press "Add a note"))
    (should (string-search "✎ Note: only gamma" (+test-aua-text)))
    ;; Kept through a redraw; in its JSON (saved with the session).
    (agent-ui-canvas-redraw)
    (should (string-search "[x] gamma" (+test-aua-text)))
    (should (string-search "\"selected\":[\"gamma\"]"
                           (decode-coding-string (json-serialize (agent-ui-to-json (agent-ui-get "q"))) 'utf-8)))
    ;; Answered: sent at once, then locked.
    (+test-aua-press "⏵ Send the answer")
    (should (equal sent '(("Answer to asker q (Which ones?): gamma. Note: only gamma" t))))
    (should (equal (plist-get (agent-ui-get "q") :answered) "gamma · note: only gamma"))
    (should (string-search "✓ Answered: gamma · note: only gamma" (+test-aua-text)))
    (should-not (string-search "⏵" (+test-aua-text)))))

(ert-deftest agent-ui-ask/one-only ()
  "One to pick: another replaces it, itself again: none."
  (+test-aua-canvas
    (agent-ui-show '(:id "q" :type "asker" :question "Which?" :items ("a" "b")))
    (+test-aua-press "( ) a")
    (+test-aua-press "( ) b")
    (should (equal (plist-get (agent-ui-get "q") :selected) '("b")))
    (should (string-search "( ) a\n(•) b" (+test-aua-text)))
    (+test-aua-press "(•) b")
    (should-not (plist-get (agent-ui-get "q") :selected))
    ;; A wrong selection given: refused.
    (should-error (agent-ui-update "q" '(:selected ("a" "b"))) :type 'agent-ui-error)))
