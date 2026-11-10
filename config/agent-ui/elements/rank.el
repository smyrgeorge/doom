;;; $DOOMDIR/config/agent-ui/elements/rank.el -*- lexical-binding: t; -*-
;; Agent UI's rank: the user puts items in order (priorities, the order to do
;; things in). Loaded from config/agent-ui/elements.el.
;;
;; Its items numbered in the user's order (:order, the element's own: saved
;; with the session), M-up / M-down (K / J) moving the one at the cursor
;; (config/agent-ui/ask.el's moving items); a note if NOTE. Send puts "Answer
;; to rank ID (QUESTION): in this order: C, A, B. Note: ..." into the
;; session's prompt (sent at once); then it shows the order, and
;; can't be changed.
;;
;;   What should I do first?
;;    1. Fix the parser      the root cause
;;    2. Release
;;    3. Update the docs
;;    M-↑ / M-↓ (K / J) move the item at the cursor
;;    ⏵ Send the order

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-rank--items (props)
  "PROPS' items as (LABEL . DETAIL)."
  (mapcar (lambda (o) (if (stringp o) (cons o nil) (cons (plist-get o :label) (plist-get o :detail))))
          (plist-get props :items)))

(defun agent-ui-rank--order (props)
  "PROPS' items' labels in the user's order: those of :order still there,
then the others as given."
  (let ((labels (mapcar #'car (agent-ui-rank--items props))))
    (append (seq-filter (lambda (l) (member l labels)) (plist-get props :order))
            (seq-remove (lambda (l) (member l (plist-get props :order))) labels))))

(defun agent-ui-rank--check (props)
  (let ((items (plist-get props :items)))
    (unless (cdr items)
      (agent-ui--fail "rank: give two items at least: [\"A\", \"B\"] or [{\"label\": ..., \"detail\": ...}]"))
    (cl-loop for o in items
             for i from 1
             unless (or (and (stringp o) (not (string-blank-p o)))
                        (and (agent-ui--plist-p o) (stringp (plist-get o :label))
                             (not (string-blank-p (plist-get o :label)))
                             (or (null (plist-get o :detail)) (stringp (plist-get o :detail)))
                             (cl-every (lambda (k) (memq k '(:label :detail)))
                                       (cl-loop for (k _) on o by #'cddr collect k))))
             do (agent-ui--fail "rank: item %d must be a label, or {\"label\": ..., \"detail\": ...}" i))
    (let ((labels (mapcar #'car (agent-ui-rank--items props))))
      (when (/= (length labels) (length (delete-dups (copy-sequence labels))))
        (agent-ui--fail "rank: two items have the same label"))
      (unless (cl-every #'stringp (plist-get props :order))
        (agent-ui--fail "rank: order is the items' labels"))))
  props)

(defun agent-ui-rank--moved (order label direction)
  "ORDER with LABEL moved DIRECTION places (-1 up, 1 down), within it."
  (let* ((from (cl-position label order :test #'equal))
         (to (max 0 (min (1- (length order)) (+ from direction))))
         (without (append (seq-take order from) (nthcdr (1+ from) order))))
    (append (seq-take without to) (list label) (nthcdr to without))))

(defun agent-ui-rank--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (items (agent-ui-rank--items props))
         (order (agent-ui-rank--order props))
         (answered (agent-ui-ask-answered-p props))
         (still (or answered (plist-get ctx :still)))
         (number-width (length (number-to-string (length order))))
         (head-width (+ 1 number-width 2))
         (label-width (min (apply #'max 0 (mapcar (lambda (o) (string-width (car o))) (seq-filter #'cdr items)))
                           (/ width 2)))
         (lines
          (cl-loop
           for label in order
           for n from 1
           collect
           ;; Its own label (the loop's is one variable, set again for each).
           (let* ((label label)
                  (detail (cdr (assoc label items)))
                  (room (- width head-width label-width 2))
                  (line (concat " " (propertize (format (format "%%%dd." number-width) n) 'face 'agent-ui-accent) " "
                                (if (and detail (>= room 10))
                                    (concat (agent-ui-pad (agent-ui-truncate label label-width) label-width) "  "
                                            (propertize (agent-ui-truncate detail room) 'face 'agent-ui-muted))
                                  (agent-ui-truncate label (max 1 (- width head-width)))))))
             (if still
                 line
               (propertize line
                           'agent-ui-item label
                           'agent-ui-move (lambda (direction)
                                            (agent-ui-ask-change
                                             ctx (list :order (agent-ui-rank--moved order label direction))))
                           'help-echo "M-up / M-down (K / J): move it"))))))
    (string-join
     (append
      (list (propertize (agent-ui-wrap (plist-get props :question) width) 'face 'bold))
      lines
      (cond
       (answered
        (list (concat " " (propertize "✓ " 'face 'agent-ui-success)
                      (propertize (if (string-empty-p (or (plist-get props :note-text) ""))
                                      "Sent"
                                    (agent-ui-truncate (concat "Sent · note: " (plist-get props :note-text)) (- width 3)))
                                  'face 'agent-ui-muted))))
       ((plist-get ctx :still) nil)
       (t
        (append
         (list (propertize (concat " " (string-join (split-string (agent-ui-wrap "M-↑ / M-↓ (K / J) move the item at the cursor"
                                                                                   (- width 1))
                                                                   "\n")
                                                     "\n "))
                           'face 'agent-ui-muted))
         (when (plist-get props :note) (list (concat " " (agent-ui-ask-note-button props ctx))))
         (list (concat " " (agent-ui-ask-answer-button
                            props ctx
                            :what (format "rank %s" (plist-get ctx :id))
                            :question (plist-get props :question)
                            :answers (list (concat "in this order: " (string-join order ", "))))))))))
     "\n")))

(agent-ui-define rank
  "The user puts ITEMS in order (priorities, the order to do things in):
labels, or {\"label\", \"detail\"}; a note if NOTE. They move items (M-up /
M-down) and press Answer: \"Answer to rank ID (QUESTION): in this order: C, A,
B. Note: ...\" comes into your prompt (sent at once). Then it shows
the order. Show it, say so in a line, end your turn."
  :props ((question string "The question: what to order, by what" :required t)
          (items list "The items, in your order: labels, or {\"label\": ..., \"detail\": ...}" :required t)
          (note boolean "Let the user add a note" :default :false)
          (order list "The user's order so far (labels)")
          (note-text string "The user's note")
          (answered string "The answer given (then it can't be changed)"))
  :example (:title "Priorities"
            :question "What should I do first?"
            :items ((:label "Fix the parser" :detail "the root cause") "Update the docs" "Release"))
  :check #'agent-ui-rank--check
  :text #'agent-ui-rank--draw)
