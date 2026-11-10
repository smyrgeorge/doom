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
                                                            :question (plist-get props :question))))
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
    (should (string-search "[ ] alpha\n[ ] beta\n[ ] gamma\n⏵ All   ⏵ None\n✎ Add a note\n⏵ Answer"
                           (+test-aua-text)))
    ;; Nothing picked: said.
    (should-error (+test-aua-press "⏵ Answer") :type 'user-error)
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
    (+test-aua-press "⏵ Answer")
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

;; ====== REVIEW COMMENTS (doom-ord.10) ======

(defun +test-aua-goto (text)
  (agent-ui--flush)
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0)))

(ert-deftest agent-ui-ask/review-comments-on-code ()
  "c on a line, or a region's lines: a comment under them; c on it edits it
\(empty: gone), d removes it; Send the review puts them all, with their
places, into the prompt; then sent, locked."
  (+test-aua-canvas
    (agent-ui-show '(:id "c" :type "code" :file "/work/x.c" :from 40
                     :code "int parse(void) {\n  return NULL;\n}"))
    (let ((answers nil))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers))))
        (setq answers '("never NULL here"))
        (+test-aua-goto "return NULL")
        (call-interactively #'agent-ui-comment)
        (should (string-search "41 │   return NULL;\n     ✎ never NULL here\n42 │ }" (+test-aua-text)))
        (should (string-search "⏵ Send the review (1 comment)   ⏵ Discard" (+test-aua-text)))
        ;; Two lines: under the last.
        (setq answers '("tidy this"))
        (+test-aua-goto "int parse")
        (let ((beg (point)))
          (+test-aua-goto "return NULL")
          (agent-ui-comment beg (point)))
        (should (equal (plist-get (agent-ui-get "c") :comments)
                       '((:line 41 :file "/work/x.c" :text "never NULL here")
                         (:line 40 :end 41 :file "/work/x.c" :text "tidy this"))))
        ;; Edited, then emptied: gone; d removes.
        (setq answers '("never NULL: it can't be"))
        (+test-aua-goto "✎ never NULL here")
        (call-interactively #'agent-ui-comment)
        (should (string-search "✎ never NULL: it can't be" (+test-aua-text)))
        (setq answers '(""))
        (+test-aua-goto "✎ tidy this")
        (call-interactively #'agent-ui-comment)
        (should-not (string-search "tidy this" (+test-aua-text)))
        (setq answers '("again"))
        (+test-aua-goto "}")
        (call-interactively #'agent-ui-comment)
        (+test-aua-goto "✎ again")
        (call-interactively #'agent-ui-uncomment)
        (should-not (string-search "✎ again" (+test-aua-text))))
      ;; Sent: into the prompt (not sent at once), then locked.
      (+test-aua-press "⏵ Send the review")
      (should (equal sent '(("Review of c: /work/x.c:41: never NULL: it can't be" t))))
      (should (string-search "✓ Review sent (1 comment)" (+test-aua-text)))
      (should-not (string-search "⏵" (+test-aua-text)))
      (+test-aua-goto "int parse")
      (should-error (call-interactively #'agent-ui-comment) :type 'user-error))))

(ert-deftest agent-ui-ask/review-comments-on-a-diff ()
  "On a diff: a comment under its line (a removed line's under the last of
its number), its place the file and the new file's line; Discard drops them."
  (+test-aua-canvas
    (agent-ui-show '(:id "d" :type "diff" :diff "--- a/src/p.c\n+++ b/src/p.c\n@@ -40,3 +40,3 @@\n a\n-old\n+new\n b\n"))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "why this?")))
      (+test-aua-goto "− old")
      (call-interactively #'agent-ui-comment))
    (should (equal (plist-get (agent-ui-get "d") :comments) '((:line 41 :file "src/p.c" :text "why this?"))))
    ;; Under the added line of the same number, not between them.
    (should (string-search "− old\n     41 + new\n        ✎ why this?\n     42   b" (+test-aua-text)))
    (+test-aua-press "⏵ Discard")
    (should-not (plist-get (agent-ui-get "d") :comments))
    (should-not (string-search "Send the review" (+test-aua-text)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "fine")))
      (+test-aua-goto "42   b")
      (call-interactively #'agent-ui-comment))
    (+test-aua-press "⏵ Send the review")
    (should (equal sent '(("Review of d: src/p.c:42: fine" t))))))

(ert-deftest agent-ui-ask/review-comments-on-a-named-canvas ()
  "On a canvas other than the default one (a session's is named after it):
c comments its element, d removes it (the default canvas's was asked for)."
  (let* ((agent-ui-display-function #'ignore)
         (name (make-temp-name "named-"))
         (canvas (progn (agent-ui-show '(:id "d" :type "diff" :diff "--- a/x.c\n+++ b/x.c\n@@ -1 +1 @@\n-a\n+b\n")
                                       :canvas name)
                        (get-buffer (agent-ui-canvas-buffer-name name)))))
    (unwind-protect
        (with-current-buffer canvas
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "+ b")
          (goto-char (match-beginning 0))
          (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "why b?")))
            (agent-ui-comment (point) (point)))
          (should (equal (plist-get (agent-ui-get "d" :canvas canvas) :comments)
                         '((:line 1 :file "x.c" :text "why b?"))))
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "✎ why b?")
          (goto-char (match-beginning 0))
          (agent-ui-uncomment)
          (should-not (plist-get (agent-ui-get "d" :canvas canvas) :comments)))
      (kill-buffer canvas))))

(ert-deftest agent-ui-ask/review-comments-wrong ()
  (+test-aua-canvas
    (agent-ui-show '(:id "t" :type "text" :text "plain"))
    (+test-aua-goto "plain")
    (should-error (agent-ui-comment (point) (point)) :type 'user-error)
    (should-error (agent-ui-show '(:id "c" :type "code" :code "x" :comments ((:text "no line"))))
                  :type 'agent-ui-error)
    (should-error (agent-ui-show '(:id "d" :type "diff" :comments ("x"))) :type 'agent-ui-error)
    (should (equal (agent-ui-review-place '(:line 3 :text "a")) "line 3"))
    (should (equal (agent-ui-review-place '(:line 3 :end 5 :file "a.c")) "a.c:3-5"))))
