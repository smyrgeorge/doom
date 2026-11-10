;;; $DOOMDIR/config/agent-ui/elements/confirm.el -*- lexical-binding: t; -*-
;; Agent UI's confirm: a yes / no gate before something risky (deploying,
;; deleting, pushing, migrating). Loaded from config/agent-ui/elements.el.
;;
;; Its question, what will happen (DETAILS, a short list; or a DIFF), styled
;; by its DANGER: high, in the error face, Proceed asking to type a WORD (the
;; branch's name; "yes" if none) and refusing another. Proceed or Cancel
;; puts "Answer to confirm ID (QUESTION): proceed" (or cancel) into the
;; session's prompt, sent at once (unless SUBMIT is false: the agent waits
;; for it); then it shows the answer, and can't be changed. No default
;; answer: nothing happens on its own. Its state is the element's own
;; (:answered), as the elements that ask (config/agent-ui/ask.el).
;;
;;   ▲ Force-push to origin/main?
;;     • Rewrites the last 3 commits
;;     • Others' work on main may be lost
;;   ⏵ Proceed   ⏵ Cancel   type "main" to proceed

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-confirm--word (props)
  "The word to type to proceed: PROPS' word; \"yes\" at high danger; else nil."
  (or (plist-get props :word)
      (and (eq (plist-get props :danger) 'high) "yes")))

(defun agent-ui-confirm--check (props)
  (let ((details (plist-get props :details)))
    (unless (cl-every (lambda (d) (and (stringp d) (not (string-blank-p d)))) details)
      (agent-ui--fail "confirm: details are lines of text: [\"Rewrites 3 commits\", ...]"))
    (when (and (plist-get props :word) (string-blank-p (plist-get props :word)))
      (agent-ui--fail "confirm: word, if given, is what to type: not blank"))
    (when (and (plist-get props :answered) (not (member (plist-get props :answered) '("proceed" "cancel"))))
      (agent-ui--fail "confirm: answered is \"proceed\" or \"cancel\"")))
  props)

(defun agent-ui-confirm--answer (props ctx answer)
  "ANSWER (\"proceed\" or \"cancel\") into the session's prompt; then the
element answered (locked). Proceed with a word to type: asked first, a wrong
one refused."
  (when (equal answer "proceed")
    (when-let* ((word (agent-ui-confirm--word props)))
      (let ((typed (string-trim (read-string (format "Type %s to proceed: " word)))))
        (unless (equal typed word)
          (user-error "Not proceeding: type %s to proceed" word)))))
  (funcall agent-ui-action-function
           (agent-ui-ask-answer-text (format "confirm %s" (plist-get ctx :id))
                                     (plist-get props :question) (list answer) nil)
           (plist-get props :submit))
  (agent-ui-ask-change ctx (list :answered answer)))

(defun agent-ui-confirm--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (high (eq (plist-get props :danger) 'high))
         (answered (plist-get props :answered))
         (word (agent-ui-confirm--word props))
         (question (propertize (agent-ui-wrap (concat (if high "▲ " "") (plist-get props :question)) width)
                               'face (if high '(agent-ui-error bold) 'bold)))
         (details (mapcar (lambda (d)
                            (concat "  • " (string-join (split-string (agent-ui-wrap d (- width 4)) "\n")
                                                        "\n    ")))
                          (plist-get props :details)))
         (diff (when-let* ((diff (plist-get props :diff)))
                 (agent-ui-render (list :type "diff" :diff diff) ctx))))
    (string-join
     (append
      (list question)
      details
      (and diff (list diff))
      (cond
       (answered
        (list (if (equal answered "proceed")
                  (concat (propertize "✓ " 'face 'agent-ui-success)
                          (propertize (format "Answered: %s" (or (plist-get props :proceed) "Proceed")) 'face 'agent-ui-muted))
                (concat (propertize "✗ " 'face 'agent-ui-muted)
                        (propertize (format "Answered: %s" (or (plist-get props :cancel) "Cancel")) 'face 'agent-ui-muted)))))
       ((plist-get ctx :still) nil)
       (t
        (let ((buttons
               (concat (agent-ui-button (propertize (concat "⏵ " (plist-get props :proceed))
                                                    'face (if high 'agent-ui-error 'agent-ui-action))
                                        (lambda () (agent-ui-confirm--answer props ctx "proceed"))
                                        (if word (format "RET: type %s, then proceed" word) "RET: proceed"))
                       "   "
                       (agent-ui-button (propertize (concat "⏵ " (plist-get props :cancel)) 'face 'agent-ui-action)
                                        (lambda () (agent-ui-confirm--answer props ctx "cancel"))
                                        "RET: cancel")))
              (hint (and word (format "type %S to proceed" word))))
          (cond
           ((null hint) (list buttons))
           ;; The word to type after the buttons, or under them if it
           ;; doesn't fit there.
           ((<= (+ (string-width buttons) 3 (string-width hint)) width)
            (list (concat buttons "   " (propertize hint 'face 'agent-ui-muted))))
           (t (list buttons (propertize (agent-ui-wrap hint width) 'face 'agent-ui-muted))))))))
     "\n")))

(agent-ui-define confirm
  "A yes / no gate before something risky (deploying, deleting, pushing,
migrating): QUESTION, what will happen (DETAILS, lines; or a DIFF), DANGER
low or high (high: in red, the user types WORD, \"yes\" if none, to
proceed). Proceed or Cancel: \"Answer to confirm ID (QUESTION): proceed\"
(or cancel) comes as your next prompt (sent at once; with submit false, it
waits in the prompt). Show it, say so in a line, end your turn; do the
risky thing only on proceed."
  :props ((question string "The question: what's about to happen" :required t)
          (details list "What will happen: lines of text")
          (diff string "What will change: a unified diff")
          (danger (choice low high) "How risky: high is in red, asks to type the word" :default low)
          (word string "A word to type to proceed (the branch's name); at high danger \"yes\" if none")
          (proceed string "The Proceed button's label" :default "Proceed")
          (cancel string "The Cancel button's label" :default "Cancel")
          (submit boolean "Send the answer at once (else it waits in the prompt)" :default t)
          (answered string "The answer given, proceed or cancel (then it can't be changed)"))
  :example (:title "Before I push"
            :question "Force-push to origin/main?"
            :details ("Rewrites the last 3 commits" "Others' work on main may be lost")
            :danger "high"
            :word "main")
  :check #'agent-ui-confirm--check
  :text #'agent-ui-confirm--draw)
