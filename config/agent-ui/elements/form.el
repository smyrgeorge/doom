;;; $DOOMDIR/config/agent-ui/elements/form.el -*- lexical-binding: t; -*-
;; Agent UI's form: several fields answered together (a new ticket's
;; details). Loaded from config/agent-ui/elements.el.
;;
;; On the canvas, its fields and their values, and Fill in: RET opens the form
;; in a buffer of its own, its fields vui.el's (typed, validated as you type:
;; text, a number within a range, yes / no, one of, a file), not inline (the
;; canvas redraws its regions itself: two renderers on one region would
;; fight). There, Send (C-c C-c) puts "Answer to form ID (QUESTION): {JSON of
;; the values}" into the session's prompt (sent at once if SUBMIT); then the
;; form is answered on the canvas, and can't be changed. Cancel (C-c C-k)
;; closes it, what was typed kept. Its values are the element's own (:values,
;; saved with the session), as each one is typed. In a terminal: the same
;; buffer (vui is text).
;;
;;   What should the ticket say?
;;    Title     Fix the parser
;;    Priority  2
;;    Type      bug
;;    Blocking  no
;;    ⏵ Fill in

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-form--types '("text" "integer" "number" "boolean" "select" "file" "directory")
  "A field's types.")

(defconst agent-ui-form--keys '(:name :label :type :required :min :max :options :placeholder :value)
  "What a field has.")

;; ====== ITS FIELDS AND VALUES ======

(defun agent-ui-form--key (name)
  "Field NAME's key in the values (a plist): :NAME."
  (intern (concat ":" name)))

(defun agent-ui-form--type (field)
  (or (plist-get field :type) "text"))

(defun agent-ui-form--label (field)
  (or (plist-get field :label) (plist-get field :name)))

(defun agent-ui-form--values (props)
  "PROPS' values: the user's, else each field's own (its default)."
  (let ((values (copy-sequence (plist-get props :values))))
    (dolist (field (plist-get props :fields))
      (let ((key (agent-ui-form--key (plist-get field :name))))
        (unless (plist-member values key)
          (when (plist-member field :value)
            (setq values (plist-put values key (plist-get field :value)))))))
    values))

(defun agent-ui-form--empty-p (value)
  (or (null value) (eq value :false) (and (stringp value) (string-blank-p value))))

(defun agent-ui-form--missing (props values)
  "PROPS' required fields VALUES leaves empty: their labels (a yes / no one
is never empty)."
  (cl-loop for field in (plist-get props :fields)
           when (and (eq (plist-get field :required) t)
                     (not (equal (agent-ui-form--type field) "boolean"))
                     (agent-ui-form--empty-p (plist-get values (agent-ui-form--key (plist-get field :name)))))
           collect (agent-ui-form--label field)))

(defun agent-ui-form--answer (id props values)
  "VALUES as the agent reads them: \"Answer to form ID (QUESTION): {JSON}\",
each field there (yes / no as true / false, an empty one null)."
  (let ((object (cl-loop for field in (plist-get props :fields)
                         for name = (plist-get field :name)
                         for value = (plist-get values (agent-ui-form--key name))
                         nconc (list (agent-ui-form--key name)
                                     (cond ((equal (agent-ui-form--type field) "boolean") (if (eq value t) t :false))
                                           ((agent-ui-form--empty-p value) :null)
                                           (t value))))))
    (format "Answer to form %s%s: %s" id
            (if-let* ((question (plist-get props :question))) (format " (%s)" question) "")
            (decode-coding-string (json-serialize object) 'utf-8))))

;; ====== CHECKING ======

(defun agent-ui-form--check-field (field i)
  (cl-flet ((bad (fmt &rest args) (agent-ui--fail "form: field %d %s" i (apply #'format fmt args))))
    (unless (agent-ui--plist-p field)
      (bad "must be {\"name\": ..., \"type\": ...}"))
    (cl-loop for (k _) on field by #'cddr
             unless (memq k agent-ui-form--keys)
             do (bad "has %s: a field has name, label, type, required, min, max, options, placeholder, value"
                     (agent-ui--show-value (substring (symbol-name k) 1))))
    (let ((name (plist-get field :name))
          (type (agent-ui-form--type field)))
      (unless (and (stringp name) (string-match-p "\\`[A-Za-z_][A-Za-z0-9_-]*\\'" name))
        (bad "has no name, or not one of letters, digits, _ and -"))
      (unless (member type agent-ui-form--types)
        (bad "has type %s; one of: %s" (agent-ui--show-value type) (string-join agent-ui-form--types ", ")))
      (dolist (k '(:label :placeholder))
        (when (and (plist-get field k) (not (stringp (plist-get field k))))
          (bad "has a %s that isn't text" (substring (symbol-name k) 1))))
      (dolist (k '(:min :max))
        (when (plist-member field k)
          (unless (member type '("integer" "number"))
            (bad "has %s: only a number has one" (substring (symbol-name k) 1)))
          (unless (numberp (plist-get field k))
            (bad "has a %s that isn't a number" (substring (symbol-name k) 1)))))
      (if (equal type "select")
          (let ((options (plist-get field :options)))
            (unless (and options (listp options) (cl-every (lambda (o) (and (stringp o) (not (string-blank-p o)))) options))
              (bad "is a select: give its options, [\"bug\", \"task\"]")))
        (when (plist-member field :options)
          (bad "has options: only a select has them")))
      (unless (memq (plist-get field :required) '(nil t :false))
        (bad "has required that isn't true or false")))))

(defun agent-ui-form--check (props)
  (let ((fields (plist-get props :fields)))
    (unless fields
      (agent-ui--fail "form: give its fields: [{\"name\": \"title\", \"type\": \"text\"}, ...]"))
    (cl-loop for field in fields for i from 1 do (agent-ui-form--check-field field i))
    (let ((names (mapcar (lambda (f) (plist-get f :name)) fields)))
      (when (/= (length names) (length (delete-dups (copy-sequence names))))
        (agent-ui--fail "form: two fields have the same name"))
      (let ((values (plist-get props :values)))
        (unless (or (null values) (agent-ui--plist-p values))
          (agent-ui--fail "form: values are an object, {\"title\": ...}"))
        (cl-loop for (k _) on values by #'cddr
                 unless (member (substring (symbol-name k) 1) names)
                 do (agent-ui--fail "form: values has %s, not a field" (substring (symbol-name k) 1))))))
  props)

;; ====== ON THE CANVAS ======

(defun agent-ui-form--shown (field value)
  "VALUE of FIELD as the canvas shows it."
  (cond
   ((equal (agent-ui-form--type field) "boolean") (if (eq value t) "yes" "no"))
   ((agent-ui-form--empty-p value) (propertize "—" 'face 'agent-ui-muted))
   ((numberp value) (agent-ui-format-number value))
   (t (replace-regexp-in-string "[\n\r]+" " " (format "%s" value)))))

(defun agent-ui-form--draw (props ctx)
  (let* ((width (plist-get ctx :width))
         (values (agent-ui-form--values props))
         (fields (plist-get props :fields))
         (label-width (min (apply #'max 0 (mapcar (lambda (f) (string-width (agent-ui-form--label f))) fields))
                           (max 6 (/ width 3))))
         (question (plist-get props :question)))
    (string-join
     (append
      (and question (list (propertize (agent-ui-wrap question width) 'face 'bold)))
      (mapcar (lambda (field)
                (concat " " (propertize (agent-ui-pad (agent-ui-truncate (agent-ui-form--label field) label-width)
                                                      label-width)
                                        'face 'agent-ui-muted)
                        "  "
                        (agent-ui-truncate (agent-ui-form--shown field (plist-get values (agent-ui-form--key (plist-get field :name))))
                                           (max 1 (- width label-width 3)))))
              fields)
      (cond
       ((agent-ui-ask-answered-p props)
        (list (concat " " (propertize "✓ " 'face 'agent-ui-success) (propertize "Sent" 'face 'agent-ui-muted))))
       ((plist-get ctx :still) nil)
       (t
        (let ((canvas (current-buffer))
              (id (plist-get ctx :id)))
          (list (concat " " (agent-ui-button (propertize "⏵ Fill in" 'face 'agent-ui-action)
                                             (lambda () (agent-ui-form-open canvas id))
                                             "RET: fill the form in, in a buffer of its own")))))))
     "\n")))

;; ====== ITS BUFFER (vui) ======

(defvar-local agent-ui-form--canvas nil "In a form's buffer: its canvas.")
(defvar-local agent-ui-form--id nil "In a form's buffer: its element's id.")

(defvar agent-ui-form-keys-mode-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "C-c C-c" #'agent-ui-form-send)
    (keymap-set map "C-c C-k" #'agent-ui-form-cancel)
    map)
  "Keys of a form's buffer: a minor mode's, above its fields' own maps.")

(define-minor-mode agent-ui-form-keys-mode
  "A form's keys: C-c C-c sends it, C-c C-k cancels it."
  :keymap agent-ui-form-keys-mode-map)

(defun agent-ui-form--self-insert ()
  "Typing in a field; outside one, nothing (vui's mode is special-mode's)."
  (interactive)
  (if (widget-field-at (point))
      (call-interactively #'self-insert-command)
    (undefined)))

(defvar agent-ui-form-mode-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<remap> <self-insert-command>" #'agent-ui-form--self-insert)
    map))

(declare-function agent-ui-form-mode "form")

;; vui's mode is the parent: TAB to the next field, a field's keys. Defined
;; once vui is loaded (`agent-ui-form-open' loads it).
(with-eval-after-load 'vui
  (define-derived-mode agent-ui-form-mode vui-mode "Agent UI form"
    "A form of Agent UI's, filled in: its fields vui's (TAB to the next).
\\{agent-ui-form-keys-mode-map}"
    (agent-ui-form-keys-mode 1)))

(defun agent-ui-form--buffer-name (id)
  (format "*Agent UI form: %s*" id))

(defun agent-ui-form--set-value (canvas id name value)
  "Field NAME's VALUE typed: the form's own state, and its element's values
on CANVAS (the canvas follows, it's saved)."
  (vui-set-state :values (lambda (old) (plist-put (copy-sequence old) (agent-ui-form--key name) value)))
  (when (buffer-live-p canvas)
    (ignore-errors
      (let ((element (agent-ui-get id :canvas canvas)))
        (unless (plist-get element :answered)
          (agent-ui-update id (list :values (plist-put (copy-sequence (plist-get element :values))
                                                       (agent-ui-form--key name) value))
                           :canvas canvas))))))

(defun agent-ui-form--set-error (name message)
  "Field NAME's error (MESSAGE), or none (nil)."
  (vui-set-state :errors (lambda (old)
                           (let ((old (cl-remove name old :key #'car :test #'equal)))
                             (if message (cons (cons name message) old) old)))))

(defun agent-ui-form--input (canvas id field value)
  "FIELD's input, vui's, VALUE in it."
  (let* ((name (plist-get field :name))
         (type (agent-ui-form--type field))
         (set (lambda (v) (agent-ui-form--set-value canvas id name v)))
         (on-error (lambda (message _raw) (agent-ui-form--set-error name message))))
    (pcase type
      ("text" (vui-field :value (if (stringp value) value "") :size 40 :key name
                         :placeholder (plist-get field :placeholder) :on-change set))
      ("boolean" (vui-checkbox :checked (eq value t) :key name :on-change (lambda (v) (funcall set (and v t)))))
      ("select" (vui-select :value value :options (plist-get field :options) :key name
                            :prompt (concat (agent-ui-form--label field) ": ") :on-change set))
      (_ (vui-typed-field :type (intern type) :value value :key name :size (if (member type '("file" "directory")) 40 10)
                          :min (plist-get field :min) :max (plist-get field :max)
                          :placeholder (plist-get field :placeholder)
                          :show-error 'inline :on-change set :on-error on-error)))))

(defun agent-ui-form--hint (field)
  "What FIELD takes, after its input: its range, required."
  (let ((min (plist-get field :min)) (max (plist-get field :max)))
    (string-join
     (delq nil (list (cond ((and min max) (format "%s to %s" min max))
                           (min (format "%s or more" min))
                           (max (format "%s at most" max)))
                     (and (eq (plist-get field :required) t)
                          (not (equal (agent-ui-form--type field) "boolean"))
                          "required")))
     ", ")))

(declare-function vui-component "vui")
(declare-function vui-mount "vui")
(declare-function vui-get-instance "vui")
(declare-function vui-get-state "vui")
(declare-function vui-set-state "vui")

(with-eval-after-load 'vui-components
  (vui-defcomponent agent-ui-form--view (canvas id title question fields initial)
    :state ((values initial) (errors nil) (problem nil))
    :render
    (let ((label-width (apply #'max 0 (mapcar (lambda (f) (string-width (agent-ui-form--label f))) fields))))
      ;; Its question, its fields, its buttons: a blank line between.
      (vui-vstack
       :spacing 1
       (and (or title question)
            (vui-vstack (and title (vui-text title :face 'agent-ui-title))
                        (and question (vui-text question :face 'bold))))
       (vui-vstack
        (mapcar (lambda (field)
                  (let ((hint (agent-ui-form--hint field)))
                    (vui-hstack
                     :spacing 2
                     (vui-text (string-pad (agent-ui-form--label field) label-width) :face 'agent-ui-muted)
                     (agent-ui-form--input canvas id field (plist-get values (agent-ui-form--key (plist-get field :name))))
                     (and (not (string-empty-p hint)) (vui-text hint :face 'agent-ui-muted)))))
                fields))
       (vui-vstack
        (and problem (vui-text problem :face 'agent-ui-error))
        (vui-hstack
         :spacing 3
         (vui-button "Send" :on-click #'agent-ui-form-send :face 'agent-ui-action)
         (vui-button "Cancel" :on-click #'agent-ui-form-cancel))
        (vui-text "C-c C-c sends it, C-c C-k cancels (what you typed is kept), TAB goes to the next field"
                  :face 'agent-ui-muted))))))

(defun agent-ui-form-open (canvas id)
  "Open form ID of CANVAS in a buffer of its own, selected; again: that one."
  (require 'vui)
  (require 'vui-components)
  (let* ((element (agent-ui-get id :canvas canvas))
         (props (agent-ui-check "form" element))
         (name (agent-ui-form--buffer-name id))
         (open (get-buffer name)))
    (when (agent-ui-ask-answered-p props)
      (user-error "This form is answered"))
    (if (and open (eq (buffer-local-value 'agent-ui-form--canvas open) canvas))
        (pop-to-buffer open)
      (let ((buffer (get-buffer-create name)))
        (with-current-buffer buffer
          (agent-ui-form-mode)
          (setq agent-ui-form--canvas canvas
                agent-ui-form--id id))
        (vui-mount (vui-component 'agent-ui-form--view
                                  :canvas canvas :id id
                                  :title (plist-get element :title)
                                  :question (plist-get props :question)
                                  :fields (plist-get props :fields)
                                  :initial (agent-ui-form--values props))
                   name t)
        (pop-to-buffer buffer)
        ;; On its first field.
        (goto-char (point-min))
        (ignore-errors (widget-forward 1))))))

(defun agent-ui-form--close ()
  "The form's buffer killed, its window closed (as it was before)."
  (let ((buffer (current-buffer)))
    (quit-window nil)
    (kill-buffer buffer)))

(defun agent-ui-form-cancel ()
  "Close the form, nothing sent: what was typed is kept in its element."
  (interactive)
  (agent-ui-form--close))

(defun agent-ui-form-send ()
  "Send the form: its answer into its session's prompt (sent at once if it
says submit); the form answered on its canvas. Required fields empty, or a
field wrong: said in the form, nothing sent."
  (interactive)
  (let* ((instance (vui-get-instance))
         (values (vui-get-state instance :values))
         (errors (vui-get-state instance :errors))
         (canvas agent-ui-form--canvas)
         (id agent-ui-form--id))
    (unless (and instance (buffer-live-p canvas))
      (user-error "This form's canvas is gone"))
    (let* ((element (condition-case nil (agent-ui-get id :canvas canvas)
                      (agent-ui-error (user-error "This form is gone from its canvas"))))
           (props (agent-ui-check "form" element))
           (missing (agent-ui-form--missing props values)))
      (cond
       ((agent-ui-ask-answered-p props) (user-error "This form is answered"))
       (errors
        (vui-set-state :problem (format "Fix %s first: %s" (caar errors) (cdar errors)) instance))
       (missing
        (vui-set-state :problem (format "Fill in %s first" (string-join missing ", ")) instance))
       (t
        (let ((answer (agent-ui-form--answer id props values)))
          (with-current-buffer canvas
            (funcall agent-ui-action-function answer (plist-get props :submit))
            (agent-ui-update id (list :values values :answered answer) :canvas canvas))
          (agent-ui-form--close)))))))

(agent-ui-define form
  "Several fields the user answers together (a new ticket's details): FIELDS,
each {\"name\", \"label\", \"type\", \"required\", \"min\", \"max\", \"options\",
\"placeholder\", \"value\"}, type text (the default), integer, number (min,
max), boolean (yes / no), select (one of its options), file, directory. The
user fills it in, in a buffer of its own (typed and checked as they type),
and sends it: \"Answer to form ID (QUESTION): {\\\"name\\\": value, ...}\"
comes into your prompt (sent at once if SUBMIT). Then it shows the values,
answered. Show it, say so in a line, end your turn."
  :props ((question string "What it's for")
          (fields list "The fields: {\"name\": ..., \"type\": ..., ...}" :required t)
          (submit boolean "Send the answer at once (else it waits in the prompt)" :default :false)
          (values any "The values so far, {\"name\": value}: defaults, or the user's")
          (answered string "The answer given (then it can't be changed)"))
  :example (:title "New ticket"
            :question "What should the ticket say?"
            :fields ((:name "title" :label "Title" :required t :value "Fix the parser")
                     (:name "priority" :label "Priority" :type "integer" :min 0 :max 4 :value 2)
                     (:name "type" :label "Type" :type "select" :options ("bug" "task" "feature") :value "bug")
                     (:name "blocking" :label "Blocking" :type "boolean")))
  :check #'agent-ui-form--check
  :text #'agent-ui-form--draw)
