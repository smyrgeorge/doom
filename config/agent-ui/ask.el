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

(defvar agent-ui-ask-types '("choice" "confirm" "form" "rank")
  "The types whose elements are questions (until answered), see
`agent-ui-ask-waiting-p'.")

(defun agent-ui-ask-waiting-p (element)
  "Whether ELEMENT asks the user and isn't answered yet: of a type that asks
\(`agent-ui-ask-types': a choice, a confirm, a form, a rank), with
select (a table, files, issues), approve (a plan, steps) or accept (a
diff's hunks)."
  (and (not (plist-get element :answered))
       (or (member (plist-get element :type) agent-ui-ask-types)
           (plist-get element :select)
           (not (memq (plist-get element :approve) '(nil :false)))
           (not (memq (plist-get element :accept) '(nil :false))))
       t))

(defun agent-ui-ask-question (element)
  "ELEMENT's question (a choice's, its select's), or nil."
  (or (plist-get element :question) (plist-get (plist-get element :select) :question)))

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

;; ====== SELECT: A LIST ELEMENT ASKING ======
;; A list element (a table, files, issues) asks with select: {"question",
;; "multiple", "note", "submit"}: marks before its items, the question above,
;; the note and Send / All / None under it (`agent-ui-ask-around').

(defun agent-ui-ask-select-check (what select)
  "SELECT (an element's select) checked: {question, multiple, note, submit},
its question text; else an error naming WHAT."
  (unless (agent-ui--plist-p select)
    (agent-ui--fail "%s: select is {\"question\": ..., \"multiple\", \"note\", \"submit\"}, not %s"
                    what (agent-ui--show-value select)))
  (cl-loop for (k _) on select by #'cddr
           unless (memq k '(:question :multiple :note :submit))
           do (agent-ui--fail "%s: select has %s: it has question, multiple, note, submit"
                              what (agent-ui--show-value (substring (symbol-name k) 1))))
  (unless (stringp (plist-get select :question))
    (agent-ui--fail "%s: select's question is required (text)" what)))

(defun agent-ui-ask-multiple-p (select)
  "Whether SELECT lets several be picked."
  (eq (plist-get select :multiple) t))

(defun agent-ui-ask-around (props ctx body all)
  "BODY (an element drawn, its items marked) asking as PROPS' select says:
its question above; under it the note, Send (N chosen) and, for several,
All / None; once answered, the answer, locked; in a still picture, nothing
under it. ALL: every item's answer, in order (what's picked answered so)."
  (let* ((select (plist-get props :select))
         (width (plist-get ctx :width))
         (all (delete-dups (copy-sequence all)))
         (answers (seq-filter (lambda (answer) (agent-ui-ask-picked-p props answer)) all))
         (submit (eq (plist-get select :submit) t)))
    (concat (propertize (agent-ui-wrap (plist-get select :question) width) 'face 'bold)
            "\n" body
            (cond
             ((agent-ui-ask-answered-p props) (concat "\n" (agent-ui-ask-answered-line props width)))
             ((plist-get ctx :still) "")
             (t (concat
                 (if (eq (plist-get select :note) t) (concat "\n " (agent-ui-ask-note-button props ctx)) "")
                 "\n "
                 (agent-ui-ask-answer-button props ctx
                                             :what (plist-get ctx :id) :question (plist-get select :question)
                                             :submit submit :answers answers
                                             :label (format "⏵ %s (%d chosen)" (if submit "Send" "Answer")
                                                            (length answers)))
                 (if (agent-ui-ask-multiple-p select) (concat "   " (agent-ui-ask-all-none ctx all)) "")))))))

(defun agent-ui-ask-group-mark (props items multiple ctx &optional plain)
  "The mark of a group of ITEMS (a folder's files): [x] all picked, [-] some,
[ ] none; a button picking them all, or none if all were (several only;
PLAIN: not a button, answered or in a still picture)."
  (let* ((picked (seq-filter (lambda (item) (agent-ui-ask-picked-p props item)) items))
         (all (and items (= (length picked) (length items))))
         (mark (propertize (cond (all "[x]") (picked "[-]") (t "[ ]"))
                           'face (if picked 'agent-ui-accent 'agent-ui-muted))))
    (cond
     ((not multiple) "   ")
     (plain mark)
     (t
      (agent-ui-button mark
                       (lambda ()
                         (agent-ui-ask-change
                          ctx (list :selected (if all
                                                  (seq-remove (lambda (s) (member s items)) (plist-get props :selected))
                                                (append (plist-get props :selected)
                                                        (seq-remove (lambda (item) (agent-ui-ask-picked-p props item))
                                                                    items))))))
                       "RET: (un)check them all")))))

;; ====== MOVING ITEMS ======
;; An element whose items the user puts in order (a rank) marks each item's
;; line: `agent-ui-move', a function of a direction (-1 up, 1 down) moving it;
;; `agent-ui-item', the item's key. M-up / M-down (K / J in Vim's normal state)
;; move the item at the cursor, the cursor staying on it.

(defun agent-ui-move-item (direction)
  "Move the item on point's line DIRECTION places (-1: up, 1: down), point
on it after."
  ;; The current drawing's (what changed drawn first).
  (agent-ui--flush)
  (let* ((at (or (text-property-not-all (line-beginning-position) (line-end-position) 'agent-ui-move nil)
                 (point)))
         (move (get-text-property at 'agent-ui-move))
         (id (or (get-text-property at 'agent-ui-child) (get-text-property at 'agent-ui-id)))
         (item (get-text-property at 'agent-ui-item))
         (column (current-column)))
    (unless move
      (user-error "No item to move here"))
    (funcall move direction)
    (agent-ui--flush)
    ;; Back on it, where it went.
    (let ((pos (point-min)) found)
      (while (and (not found) (setq pos (text-property-not-all pos (point-max) 'agent-ui-item nil)))
        (if (and (equal (get-text-property pos 'agent-ui-item) item)
                 (equal (or (get-text-property pos 'agent-ui-child) (get-text-property pos 'agent-ui-id)) id))
            (setq found pos)
          (setq pos (or (next-single-property-change pos 'agent-ui-item) (point-max)))))
      (when found
        (goto-char found)
        (move-to-column column)))))

(defun agent-ui-move-item-up ()
  "Move the item at point up (an element whose items are put in order)."
  (interactive)
  (agent-ui-move-item -1))

(defun agent-ui-move-item-down ()
  "Move the item at point down (an element whose items are put in order)."
  (interactive)
  (agent-ui-move-item 1))

(keymap-set agent-ui-canvas-mode-map "M-<up>" #'agent-ui-move-item-up)
(keymap-set agent-ui-canvas-mode-map "M-<down>" #'agent-ui-move-item-down)

;; ====== DROPPING, EDITING ITEMS ======
;; An element whose items the user drops or rewords before answering (a plan
;; to approve) marks each item's line: `agent-ui-drop', a function of no
;; argument dropping it (or bringing it back); `agent-ui-edit', one rewording
;; it. x / e on the line call them.

(defun agent-ui--item-action (prop what)
  "The function PROP on point's line, or a user-error naming WHAT: the
current drawing's (what changed drawn first)."
  (agent-ui--flush)
  (or (get-text-property (or (text-property-not-all (line-beginning-position) (line-end-position) prop nil)
                             (point))
                         prop)
      (user-error "No %s here" what)))

(defun agent-ui-drop-item ()
  "Drop the item on point's line (a plan's step), or bring it back."
  (interactive)
  (funcall (agent-ui--item-action 'agent-ui-drop "item to drop"))
  ;; Drawn at once: pressed again, it acts on what it shows.
  (agent-ui--flush))

(defun agent-ui-edit-item ()
  "Reword the item on point's line (a plan's step), in the minibuffer."
  (interactive)
  (funcall (agent-ui--item-action 'agent-ui-edit "item to edit"))
  (agent-ui--flush))

(keymap-set agent-ui-canvas-mode-map "x" #'agent-ui-drop-item)
(keymap-set agent-ui-canvas-mode-map "e" #'agent-ui-edit-item)

;; ====== REVIEW COMMENTS ======
;; On an element showing code (code, diff): the user writes comments on its
;; lines (c on a line, or on a region's lines; c on a comment edits it, d
;; removes it), shown under them; Send the review puts them all into the
;; session's prompt, each with its place ("Review of ID: src/x.c:42: rename
;; this; ..."), then the element is answered (locked). Its lines say where they
;; are (text properties agent-ui-file, agent-ui-line), its comments' lines which
;; they are (agent-ui-comment, an index). Its state, its own: :comments
;; ((:file F :line L :end E :text T)...), :answered.

(defun agent-ui-review-check (what comments)
  "COMMENTS (an element's :comments) checked: each {line, end, file, text};
else an error naming WHAT."
  (cl-loop for c in comments
           for i from 1
           unless (and (agent-ui--plist-p c) (natnump (plist-get c :line)) (stringp (plist-get c :text))
                       (or (null (plist-get c :end)) (natnump (plist-get c :end)))
                       (or (null (plist-get c :file)) (stringp (plist-get c :file))))
           do (agent-ui--fail "%s: comment %d must be {\"line\": N, \"text\": ..., \"end\", \"file\"}" what i)))

(defun agent-ui-review-place (comment)
  "COMMENT's place: file:line (or file:line-end), or line N without a file."
  (let ((lines (if (and (plist-get comment :end) (/= (plist-get comment :end) (plist-get comment :line)))
                   (format "%d-%d" (plist-get comment :line) (plist-get comment :end))
                 (format "%d" (plist-get comment :line)))))
    (if (plist-get comment :file)
        (format "%s:%s" (plist-get comment :file) lines)
      (concat "line " lines))))

(defun agent-ui-review-lines (props file line indent width)
  "PROPS' comments ending at LINE of FILE, drawn under it: each after INDENT,
wrapped to WIDTH, its index on it; \"\" if none (each line led by a newline)."
  (cl-loop for c in (plist-get props :comments)
           for i from 0
           when (and (eql (or (plist-get c :end) (plist-get c :line)) line)
                     (equal (plist-get c :file) file))
           concat (propertize
                   (mapconcat (lambda (part) (concat "\n" indent part))
                              (split-string (agent-ui-wrap (concat "✎ " (plist-get c :text))
                                                           (max 10 (- width (string-width indent))))
                                            "\n")
                              "")
                   'face 'agent-ui-accent 'agent-ui-comment i)))

(defun agent-ui-review-text (id comments)
  "COMMENTS as the agent reads them: Review of ID: place: text; ..."
  (concat (format "Review of %s: " id)
          (mapconcat (lambda (c) (format "%s: %s" (agent-ui-review-place c) (plist-get c :text))) comments "; ")))

(defun agent-ui-review-footer (props ctx)
  "Under an element with comments: Send the review and Discard (\"\" without
comments, or in a still picture); once sent, saying so. Led by a newline."
  (let ((comments (plist-get props :comments))
        (count (lambda (n) (format "%d comment%s" n (if (= n 1) "" "s")))))
    (cond
     ((agent-ui-ask-answered-p props)
      (concat "\n" (propertize "✓ " 'face 'agent-ui-success)
              (propertize (format "Review sent (%s)" (plist-get props :answered)) 'face 'agent-ui-muted)))
     ((or (null comments) (plist-get ctx :still)) "")
     (t (concat "\n "
                (agent-ui-button
                 (propertize (format "⏵ Send the review (%s)" (funcall count (length comments))) 'face 'agent-ui-action)
                 (lambda ()
                   (funcall agent-ui-action-function (agent-ui-review-text (plist-get ctx :id) comments) nil)
                   (agent-ui-ask-change ctx (list :answered (funcall count (length comments)))))
                 "RET: put the review into the prompt")
                "   "
                (agent-ui-button (propertize "⏵ Discard" 'face 'agent-ui-action)
                                 (lambda () (agent-ui-ask-change ctx (list :comments nil)))
                                 "RET: drop its comments"))))))

(defun agent-ui--review-target ()
  "The element at point taking comments, and its props: (ID . PROPS); its
review not sent yet."
  (let* ((id (agent-ui--element-at-point))
         (props (agent-ui-get id :canvas (current-buffer))))
    (when (plist-get props :answered)
      (user-error "Its review was sent"))
    (cons id props)))

(defun agent-ui-comment (beg end)
  "Comment on the line at point, or the region's lines (BEG to END), of an
element showing code in a canvas (code, a diff): the comment shown under
them, sent with the others (Send the review). On a comment: edit it (empty:
removed)."
  (interactive (if (use-region-p) (list (region-beginning) (region-end)) (list (point) (point))))
  (pcase-let* ((`(,id . ,props) (agent-ui--review-target))
               (comments (plist-get props :comments))
               (ctx (list :id id))
               (index (get-text-property beg 'agent-ui-comment)))
    (if index
        (let ((text (read-string "Comment: " (plist-get (nth index comments) :text))))
          (agent-ui-ask-change ctx (list :comments (if (string-blank-p text)
                                                        (append (seq-take comments index) (nthcdr (1+ index) comments))
                                                      (append (seq-take comments index)
                                                              (list (plist-put (copy-sequence (nth index comments)) :text text))
                                                              (nthcdr (1+ index) comments))))))
      (let ((file (get-text-property beg 'agent-ui-file))
            (lines nil))
        (save-excursion
          (goto-char beg)
          (while (progn (when-let* ((n (get-text-property (point) 'agent-ui-line))) (push n lines))
                        (and (zerop (forward-line 1)) (< (point) (max end (1+ beg)))))))
        (unless lines
          (user-error "Comment on a line of code or of a diff"))
        (let* ((comment (append (list :line (apply #'min lines))
                                (when (> (apply #'max lines) (apply #'min lines)) (list :end (apply #'max lines)))
                                (when file (list :file file))))
               (text (read-string (format "Comment on %s: " (agent-ui-review-place comment)))))
          (unless (string-blank-p text)
            (agent-ui-ask-change ctx (list :comments (append comments (list (plist-put comment :text text)))))))))))

(defun agent-ui-uncomment ()
  "Remove the comment at point (see `agent-ui-comment')."
  (interactive)
  (pcase-let* ((`(,id . ,props) (agent-ui--review-target))
               (index (or (get-text-property (point) 'agent-ui-comment) (user-error "No comment here")))
               (comments (plist-get props :comments)))
    (agent-ui-ask-change (list :id id) (list :comments (append (seq-take comments index) (nthcdr (1+ index) comments))))))

(declare-function agent-ui--element-at-point "agent-ui/snapshot")
(keymap-set agent-ui-canvas-mode-map "c" #'agent-ui-comment)
(keymap-set agent-ui-canvas-mode-map "d" #'agent-ui-uncomment)
