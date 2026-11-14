;;; $DOOMDIR/config/agent-ui/elements/compare.el -*- lexical-binding: t; -*-
;; Agent UI's compare: alternatives side by side (code versions, texts,
;; approaches, diffs) for the user to pick the better one, with a note why.
;; Loaded from config/agent-ui/elements.el.
;;
;; Each option a label and an element (any type), drawn in its column under
;; its mark, the columns as a panel's row (stacked when a column would be
;; narrower than `agent-ui-compare-min-width'; images too, in the GUI, to be
;; seen). RET or a click on a mark picks it (MULTIPLE: several); Answer puts
;; "Answer to compare ID (QUESTION): B. Note: ..." into the session's prompt
;; (sent at once); then it shows the answer, and can't be changed.
;; Its choice is the element's own (config/agent-ui/ask.el).
;;
;;   Which version reads better?
;;    (•) A: a loop             │  ( ) B: a fold
;;    for x in xs:              │  total = sum(xs)
;;        total += x            │
;;    ✎ Add a note
;;    ⏵ Answer

(require 'cl-lib)
(require 'subr-x)

(defvar agent-ui-compare-min-width 24
  "The narrowest a compare's column may be before its options stack.")

(defun agent-ui-compare--labels (props)
  (mapcar (lambda (o) (plist-get o :label)) (plist-get props :options)))

(defun agent-ui-compare--check (props)
  (let ((options (plist-get props :options)))
    (unless (<= 2 (length options) 4)
      (agent-ui--fail "compare: give 2 to 4 options: [{\"label\": ..., \"element\": {\"type\": ..., ...}}, ...]"))
    (cl-loop for o in options
             for i from 1
             do (unless (and (agent-ui--plist-p o) (stringp (plist-get o :label))
                             (not (string-blank-p (plist-get o :label))))
                  (agent-ui--fail "compare: option %d must be {\"label\": ..., \"element\": {...}}" i))
             (cl-loop for (k _) on o by #'cddr
                      unless (memq k '(:label :element))
                      do (agent-ui--fail "compare: option %d has %s: an option has label, element"
                                         i (agent-ui--show-value (substring (symbol-name k) 1))))
             (let ((element (plist-get o :element)))
               (unless (and (agent-ui--plist-p element) (stringp (plist-get element :type)))
                 (agent-ui--fail "compare: option %d's element must be an element: {\"type\": ..., ...}" i))
               ;; Its own errors, named by its option.
               (condition-case err
                   (agent-ui-check (plist-get element :type) element)
                 (agent-ui-error
                  (agent-ui--fail "compare: option %d: %s" i (agent-ui-error-message err))))))
    (let ((labels (agent-ui-compare--labels props)))
      (when (/= (length labels) (length (delete-dups (copy-sequence labels))))
        (agent-ui--fail "compare: two options have the same label"))
      (agent-ui-ask-check "compare" (plist-get props :selected) labels (plist-get props :multiple))))
  props)

(defun agent-ui-compare--head (props ctx option width still &optional indent)
  "OPTION's lines over its column, WIDTH wide after INDENT: its mark and
label (wrapped, its lines under the label's start), a button picking it."
  (let* ((label (plist-get option :label))
         (multiple (plist-get props :multiple))
         (line (agent-ui-ask-item-lines
                (concat indent (agent-ui-ask-mark (agent-ui-ask-picked-p props label) multiple) " ")
                (propertize label 'face 'bold) nil 0 (+ width (length indent)))))
    (if still line (agent-ui-ask-pick-button line props ctx label multiple))))

(defun agent-ui-compare--image-p (option)
  (member (plist-get (plist-get option :element) :type) '("image" "chart" "heatmap")))

(defun agent-ui-compare--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (options (plist-get props :options))
         (n (length options))
         (answered (agent-ui-ask-answered-p props))
         (still (or answered (plist-get ctx :still)))
         (column (/ (- width 1 (* 3 (1- n))) n))
         (side-by-side (and (>= column agent-ui-compare-min-width)
                            ;; Images shown, in the GUI: one under another.
                            (not (and (plist-get ctx :graphic) (seq-some #'agent-ui-compare--image-p options)))))
         (body
          (if side-by-side
              ;; Each in its column, as text, line by line.
              (let* ((text-ctx (plist-put (copy-sequence ctx) :graphic nil))
                     (columns (mapcar (lambda (option)
                                        (agent-ui-panel--lines
                                         (concat (agent-ui-compare--head props ctx option column still) "\n"
                                                 (agent-ui-panel--child (plist-get option :element) text-ctx column))
                                         column text-ctx))
                                      options))
                     (height (apply #'max (mapcar #'length columns))))
                (cl-loop for i below height
                         collect (agent-ui-panel--trim-right
                                  (concat " " (mapconcat #'identity
                                                         (mapcar (lambda (lines) (or (nth i lines) (make-string column ?\s)))
                                                                 columns)
                                                         (propertize " │ " 'face 'agent-ui-muted))))))
            ;; One under another, a blank line between, each indented.
            (cdr (apply #'append
                        (mapcar (lambda (option)
                                  (cons ""
                                        (cons (agent-ui-compare--head props ctx option (- width 1) still " ")
                                              (mapcar (lambda (line) (concat "   " line))
                                                      (split-string (agent-ui-panel--child (plist-get option :element)
                                                                                           ctx (- width 3))
                                                                    "\n")))))
                                options))))))
    (string-join
     (append
      (list (propertize (agent-ui-wrap (plist-get props :question) width) 'face 'bold))
      body
      (cond
       (answered (list (concat " " (agent-ui-ask-answered-line props (- width 1)))))
       ((plist-get ctx :still) nil)
       (t
        (append
         (when (plist-get props :note) (list (concat " " (agent-ui-ask-note-button props ctx))))
         (list (concat " " (agent-ui-ask-answer-button
                            props ctx
                            :what (format "compare %s" (plist-get ctx :id))
                            :question (plist-get props :question))))))))
     "\n")))

(agent-ui-define compare
  "Alternatives side by side for the user to pick the better one, when they
need showing, not naming (code versions, texts, approaches, diffs): QUESTION
and 2 to 4 OPTIONS, each {\"label\", \"element\"} (an element of any type,
drawn in its column); several picked if MULTIPLE; a note if NOTE. The user
picks and presses Answer: \"Answer to compare ID (QUESTION): B. Note: ...\"
comes into your prompt (sent at once). Show it, say so in a line,
end your turn."
  :props ((question string "The question" :required t)
          (options list "The alternatives: [{\"label\": ..., \"element\": {\"type\": ..., ...}}]" :required t)
          (multiple boolean "Several can be picked" :default :false)
          (note boolean "Let the user add a note (why)" :default t)
          (selected list "The options picked so far (labels)")
          (note-text string "The user's note")
          (answered string "The answer given (then it can't be changed)"))
  :example (:title "Two ways"
            :question "Which version reads better?"
            :options ((:label "A: a loop"
                       :element (:type "code" :language "python"
                                 :code "total = 0\nfor x in xs:\n    total += x"))
                      (:label "B: sum"
                       :element (:type "code" :language "python" :code "total = sum(xs)"))))
  :check #'agent-ui-compare--check
  :whole t                              ; 2 to 4 options, each cut: its buttons kept
  :text #'agent-ui-compare--draw)
