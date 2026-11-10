;;; $DOOMDIR/config/agent-ui/core.el -*- lexical-binding: t; -*-
;; Agent UI's element types: the registry, `agent-ui-define', checking an
;; element's properties, drawing it with its errors contained. Loaded from
;; config/agent-ui.el. No Doom here (see docs/agent-ui.md).
;;
;; An element is a plist, as `json-parse-string' makes it from the agent's JSON
;; (`agent-ui-parse-json'): (:id "build" :type "progress" :value 3 :max 12).
;; Its type, defined once with `agent-ui-define', lists its properties and
;; draws it as text (and, optionally, for the GUI).

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defgroup agent-ui nil
  "What a coding agent shows the user in Emacs."
  :group 'tools
  :prefix "agent-ui-")

(defcustom agent-ui-max-chars 20000
  "The most characters an element's drawing may have; the rest is left out,
with a line saying so."
  :type 'natnum)

(defcustom agent-ui-max-rows 500
  "The most rows (a table's) or values (a chart's) an element draws."
  :type 'natnum)

(defface agent-ui-title '((t :inherit bold))
  "An element's title, the line above it.")

(defface agent-ui-error '((t :inherit error))
  "An element that couldn't be drawn: the error in its place.")

(defface agent-ui-muted '((t :inherit shadow))
  "Secondary text: what was left out, a hint.")

(defface agent-ui-success '((t :inherit success))
  "What went well: a step done, a test passed.")

(defface agent-ui-warning '((t :inherit warning))
  "What needs a look.")

(define-error 'agent-ui-error "Agent UI")

(defconst agent-ui--reserved '(:id :type :title :source :actions)
  "Keys every element may have; no type's property is named so.")

(defvar agent-ui-file-directory nil
  "The directory a `file' property's relative name is in (nil: the current
buffer's): while a request is answered, the agent's.")

(defconst agent-ui--kinds '(string number integer boolean list any file)
  "The kinds of property, with (choice SYMBOL...).")

(cl-defstruct (agent-ui-prop (:constructor agent-ui--make-prop))
  "A property of an element type."
  key kind doc default required)

(cl-defstruct (agent-ui-type (:constructor agent-ui--make-type))
  "An element type (see `agent-ui-define')."
  name doc props example animated text gui append check prepare file)

(defvar agent-ui--types (make-hash-table :test #'eq)
  "The element types, by name (a symbol).")

;; ====== ERRORS ======

(defun agent-ui--fail (format-string &rest args)
  "Signal `agent-ui-error' with a message: FORMAT-STRING with ARGS."
  (signal 'agent-ui-error (list (apply #'format format-string args))))

(defun agent-ui-error-message (err)
  "The message of ERR, a signal's data: its own text for `agent-ui-error'
\(not prefixed with \"Agent UI\")."
  (if (eq (car err) 'agent-ui-error)
      (cadr err)
    (error-message-string err)))

;; ====== DEFINING A TYPE ======

(defun agent-ui--kind-p (kind)
  (or (memq kind agent-ui--kinds)
      (and (eq (car-safe kind) 'choice)
           (cdr kind)
           (cl-every #'symbolp (cdr kind)))))

(defun agent-ui--kind-name (kind)
  "KIND as the catalog says it: \"number\", \"one of: a, b\"."
  (if (eq (car-safe kind) 'choice)
      (concat "one of: " (mapconcat #'symbol-name (cdr kind) ", "))
    (symbol-name kind)))

(defun agent-ui--parse-prop (type entry)
  "ENTRY of TYPE's :props, (NAME KIND DOC [:default VALUE] [:required BOOL]),
as an `agent-ui-prop'."
  (pcase entry
    (`(,(and name (pred symbolp)) ,kind ,(and doc (pred stringp)) . ,keys)
     (let ((key (intern (concat ":" (symbol-name name)))))
       (when (memq key agent-ui--reserved)
         (agent-ui--fail "%s: no property may be named %s (every element has it)" type name))
       (unless (agent-ui--kind-p kind)
         (agent-ui--fail "%s: property %s's kind %S isn't one of %s, (choice ...)"
                         type name kind (mapconcat #'symbol-name agent-ui--kinds ", ")))
       (cl-loop for (k _) on keys by #'cddr
                unless (memq k '(:default :required))
                do (agent-ui--fail "%s: property %s has %S: only :default and :required" type name k))
       (let ((prop (agent-ui--make-prop :key key :kind kind :doc doc
                                        :required (plist-get keys :required))))
         (when-let* ((default (plist-get keys :default)))
           (setf (agent-ui-prop-default prop)
                 ;; A file property's :here: the agent's directory (see
                 ;; `agent-ui-file-directory'), when the element is shown.
                 (if (and (eq default :here) (eq kind 'file))
                     :here
                   (agent-ui--check-value type prop default))))
         prop)))
    (_ (agent-ui--fail "%s: %S isn't a property: (NAME KIND DOC [:default VALUE] [:required t])"
                       type entry))))

(cl-defun agent-ui--register (name doc &key props example animated text gui append check prepare file)
  "Define the element type NAME (see `agent-ui-define'); replaces one so named."
  (unless (and (symbolp name) (string-match-p "\\`[a-z][a-z0-9-]*\\'" (symbol-name name)))
    (agent-ui--fail "%S: a type's name is a symbol of a-z, 0-9 and -" name))
  (unless (stringp doc)
    (agent-ui--fail "%s: no documentation string" name))
  (unless (functionp text)
    (agent-ui--fail "%s: no :text function drawing it" name))
  (dolist (fn (list gui append check prepare (and (not (eq animated t)) animated)))
    (when (and fn (not (functionp fn)))
      (agent-ui--fail "%s: %S isn't a function" name fn)))
  (let* ((props (mapcar (lambda (entry) (agent-ui--parse-prop name entry)) props))
         (keys (mapcar #'agent-ui-prop-key props))
         (type (agent-ui--make-type :name name :doc doc :props props :example example
                                    :animated animated :text text :gui gui
                                    :append append :check check :prepare prepare :file file)))
    (when (/= (length keys) (length (delete-dups (copy-sequence keys))))
      (agent-ui--fail "%s: a property is named twice" name))
    ;; Its example must be right: the agent copies it.
    (when example
      (agent-ui-check type example))
    (puthash name type agent-ui--types)
    name))

(defmacro agent-ui-define (name doc &rest args)
  "Define NAME, an element type, documented by DOC (the agent reads it).

ARGS are keywords:
  :props    its properties, each (NAME KIND DOC [:default VALUE]
            [:required t]). KIND: string, number, integer, boolean, list,
            any, file (a name, relative to the agent's directory), or
            (choice SYMBOL...) (JSON's strings become the symbol). A file
            property's :default :here is the agent's directory.
  :example  an element of it, a plist (:value 3 :max 12): checked, shown in
            the catalog.
  :text     (lambda (PROPS CTX) ...) drawing it as text: a string, maybe
            propertized. PROPS: its properties checked, defaults filled
            (`agent-ui-check'); CTX: `agent-ui-context'.
  :gui      the same, for a graphic frame (optional: else :text).
  :animated t, or (lambda (PROPS) ...) saying whether these are: redrawn as
            time passes, CTX's :tick counting.
  :append   (lambda (ELEMENT PATCH) ...) returning ELEMENT with PATCH's
            lists added (optional: else they're appended, `agent-ui-append-to').
  :check    (lambda (PROPS) ...) checking more than each property's kind
            (a list's items, properties that go together): returns PROPS,
            maybe normalized, or signals `agent-ui-error' (`agent-ui--fail').
            What it returns is drawn; what's kept is the element as given.
  :prepare  (lambda (ELEMENT) ...) returning ELEMENT as it's kept, once
            checked, each time it's shown or changed: for what it notes as
            time passes (a step's start). Called again on what it returned:
            a second call changes nothing.

Defining a type again replaces it."
  (declare (indent defun) (doc-string 2))
  (let ((unknown (cl-loop for (k _) on args by #'cddr
                          unless (memq k '(:props :example :text :gui :animated :append :check :prepare))
                          collect k)))
    (when unknown
      (error "agent-ui-define %s: unknown keys %S" name unknown)))
  `(agent-ui--register ',name ,doc
                       :props ',(plist-get args :props)
                       :example ',(plist-get args :example)
                       :animated ,(plist-get args :animated)
                       :text ,(plist-get args :text)
                       :gui ,(plist-get args :gui)
                       :append ,(plist-get args :append)
                       :check ,(plist-get args :check)
                       :prepare ,(plist-get args :prepare)
                       :file (or load-file-name buffer-file-name)))

(defun agent-ui-undefine (name)
  "Forget the element type NAME."
  (remhash name agent-ui--types))

(defun agent-ui-types ()
  "The element types' names, sorted."
  (sort (hash-table-keys agent-ui--types)
        (lambda (a b) (string< (symbol-name a) (symbol-name b)))))

(defun agent-ui-type (type)
  "The element type TYPE: an `agent-ui-type', its name (a symbol or a string).
Signals `agent-ui-error' if there's none."
  (cond
   ((agent-ui-type-p type) type)
   ((and (or (symbolp type) (stringp type)) type
         (gethash (if (stringp type) (intern type) type) agent-ui--types)))
   ((null type)
    (agent-ui--fail "no type given; types: %s"
                    (mapconcat #'symbol-name (agent-ui-types) ", ")))
   (t
    (agent-ui--fail "unknown type %s; types: %s"
                    (agent-ui--show-value type)
                    (mapconcat #'symbol-name (agent-ui-types) ", ")))))

;; ====== CHECKING AN ELEMENT ======

(defun agent-ui--show-value (value)
  "VALUE as JSON would write it, about, for an error."
  (pcase value
    ('nil "null")
    ('t "true")
    (:false "false")
    ((pred stringp) (format "%S" (truncate-string-to-width value 40 nil nil "…")))
    ((pred symbolp) (format "%S" (symbol-name value)))
    (_ (truncate-string-to-width (format "%S" value) 40 nil nil "…"))))

(defun agent-ui--check-value (type prop value)
  "VALUE of PROP, a property of TYPE (its name), as the type gets it; signals
`agent-ui-error' if it isn't of PROP's kind."
  (let ((kind (agent-ui-prop-kind prop)))
    (cl-flet ((bad ()
                (agent-ui--fail "%s: %s must be %s, not %s"
                                type (substring (symbol-name (agent-ui-prop-key prop)) 1)
                                (pcase kind
                                  ('integer "an integer") ('any "anything") ('list "a list")
                                  ('file "a file's name")
                                  ((pred symbolp) (concat "a " (symbol-name kind)))
                                  (_ (agent-ui--kind-name kind)))
                                (agent-ui--show-value value))))
      (pcase kind
        ('string (if (stringp value) value (bad)))
        ;; Absolute: relative to the agent's directory.
        ('file (if (and (stringp value) (not (string-empty-p value)))
                   (expand-file-name value agent-ui-file-directory)
                 (bad)))
        ('number (if (numberp value) value (bad)))
        ('integer (if (integerp value) value (bad)))
        ('boolean (pcase value ('t t) ((or :false 'nil) nil) (_ (bad))))
        ;; Inside them, false stays :false (a table's cell shows it).
        ('list (if (listp value) value (bad)))
        ('any value)
        (`(choice . ,choices)
         (let ((sym (cond ((stringp value) (intern-soft value))
                          ((symbolp value) value))))
           (if (and sym (memq sym choices)) sym (bad))))))))

(defun agent-ui-check (type element)
  "The properties of ELEMENT (a plist), of TYPE (a type or its name): checked,
each of TYPE's there, its default if ELEMENT doesn't give it. Signals
`agent-ui-error' for a property TYPE doesn't have, one of the wrong kind, a
required one missing, or what the type's :check refuses. ELEMENT's :id,
:type and :title are left out."
  (let* ((type (agent-ui-type type))
         (name (agent-ui-type-name type))
         (props (agent-ui-type-props type))
         (result nil))
    (unless (and (listp element) (cl-evenp (length element)))
      (agent-ui--fail "%s: an element is an object of properties, not %s"
                      name (agent-ui--show-value element)))
    (cl-loop for (key _) on element by #'cddr
             unless (or (memq key agent-ui--reserved)
                        (cl-find key props :key #'agent-ui-prop-key))
             do (agent-ui--fail "%s: unknown property %s; its properties: %s"
                                name (agent-ui--show-value
                                      (if (keywordp key) (substring (symbol-name key) 1) key))
                                (if props
                                    (mapconcat (lambda (p) (substring (symbol-name (agent-ui-prop-key p)) 1))
                                               props ", ")
                                  "none")))
    (dolist (prop props)
      (let* ((key (agent-ui-prop-key prop))
             (value (plist-get element key)))
        (setq result
              (plist-put result key
                         (cond
                          (value (agent-ui--check-value name prop value))
                          ((agent-ui-prop-required prop)
                           (agent-ui--fail "%s: %s is required"
                                           name (substring (symbol-name key) 1)))
                          ((eq (agent-ui-prop-default prop) :here)
                           (file-name-as-directory (expand-file-name (or agent-ui-file-directory default-directory))))
                          (t (agent-ui-prop-default prop)))))))
    (if-let* ((check (agent-ui-type-check type)))
        (funcall check result)
      result)))

;; ====== CHANGING AN ELEMENT ======

(defun agent-ui--plist-delete (plist key)
  (cl-loop for (k v) on plist by #'cddr
           unless (eq k key) nconc (list k v)))

(defun agent-ui--same-type-p (a b)
  (equal (format "%s" a) (format "%s" b)))

(defun agent-ui-merge (element patch)
  "ELEMENT with PATCH's properties: each replaces ELEMENT's, and one PATCH
gives as nil (JSON's null) goes back to its default. A new ELEMENT; checked
when it's drawn. Signals `agent-ui-error' if PATCH changes the type."
  (let ((result (copy-sequence element)))
    (cl-loop for (key value) on patch by #'cddr
             do (cond
                 ((eq key :id))
                 ((eq key :source)
                  (agent-ui--fail "an update can't change a source: show the element again"))
                 ((eq key :type)
                  (unless (agent-ui--same-type-p value (plist-get element :type))
                    (agent-ui--fail "an update can't change the type (%s to %s): show it again"
                                    (plist-get element :type) value)))
                 ((null value) (setq result (agent-ui--plist-delete result key)))
                 (t (setq result (plist-put result key value)))))
    result))

(defun agent-ui-append-to (element patch)
  "ELEMENT with PATCH's lists added to its own: its type's :append, else
each list after ELEMENT's (its default's, if it has none). Signals
`agent-ui-error' for a property that isn't a list."
  (let ((type (agent-ui-type (plist-get element :type))))
    (if-let* ((fn (agent-ui-type-append type)))
        (funcall fn element patch)
      (let ((result (copy-sequence element)))
        (cl-loop for (key value) on patch by #'cddr
                 unless (eq key :id)
                 do (let ((prop (cl-find key (agent-ui-type-props type) :key #'agent-ui-prop-key)))
                      (unless (and prop (eq (agent-ui-prop-kind prop) 'list) (listp value))
                        (agent-ui--fail "%s: only lists can be appended to (%s)"
                                        (agent-ui-type-name type)
                                        (string-join
                                         (delq nil (mapcar (lambda (p)
                                                             (when (eq (agent-ui-prop-kind p) 'list)
                                                               (substring (symbol-name (agent-ui-prop-key p)) 1)))
                                                           (agent-ui-type-props type)))
                                         ", ")))
                      (setq result
                            (plist-put result key
                                       (append (if (plist-member element key)
                                                   (plist-get element key)
                                                 (agent-ui-prop-default prop))
                                               value)))))
        result))))

;; ====== DRAWING AN ELEMENT ======

(cl-defun agent-ui-context (&key (width 80) graphic (tick 0) (char-width 8) (line-height 16) id still)
  "What an element's drawing knows of where it's drawn: WIDTH in characters,
GRAPHIC (a graphic frame, else a terminal), TICK (counts up, for
animations), and in a graphic frame a character's CHAR-WIDTH and a line's
LINE-HEIGHT in pixels (for images sized to the text). STILL: a still
picture of it (a snapshot), where buttons would do nothing: none drawn."
  (append (list :width width :graphic graphic :tick tick
                :char-width char-width :line-height line-height)
          ;; The element's id, in a canvas: its buttons may change it.
          (when id (list :id id))
          (when still (list :still t))))

(defun agent-ui-animated-p (element)
  "Whether ELEMENT is redrawn as time passes (its type's :animated)."
  (condition-case nil
      (let* ((type (agent-ui-type (plist-get element :type)))
             (animated (agent-ui-type-animated type)))
        (if (functionp animated)
            (and (funcall animated (agent-ui-check type element)) t)
          (and animated t)))
    (error nil)))

(defun agent-ui--cap (text)
  "TEXT, cut at `agent-ui-max-chars' with a line saying what was left out."
  (if (<= (length text) agent-ui-max-chars)
      text
    (concat (substring text 0 agent-ui-max-chars)
            "\n"
            (propertize (format "… %d characters more" (- (length text) agent-ui-max-chars))
                        'face 'agent-ui-muted))))

(defface agent-ui-action '((t :inherit link))
  "An element's action: a button putting text into the session's prompt.")

(defvar agent-ui-action-function
  (lambda (_prompt _submit) (user-error "Actions need an agent's session"))
  "Called with an action's PROMPT and SUBMIT when its button is pressed, in
the buffer of the button (config/agent-ui/agent.el: into its canvas's
session's prompt).")

(defun agent-ui-check-actions (actions)
  "ACTIONS, an element's: an error saying what's wrong, else themselves."
  (unless (and (listp actions) (not (agent-ui--plist-p actions)))
    (agent-ui--fail "actions: give an array: [{\"label\": ..., \"prompt\": ...}]"))
  (when (> (length actions) 6)
    (agent-ui--fail "actions: at most 6, not %d" (length actions)))
  (cl-loop for action in actions
           for i from 1
           do (unless (agent-ui--plist-p action)
                (agent-ui--fail "actions: action %d must be {\"label\": ..., \"prompt\": ...}" i))
           (cl-loop for (k _) on action by #'cddr
                    unless (memq k '(:label :prompt :submit))
                    do (agent-ui--fail "actions: action %d has %s: an action has label, prompt, submit"
                                       i (agent-ui--show-value (substring (symbol-name k) 1))))
           (dolist (key '(:label :prompt))
             (let ((value (plist-get action key)))
               (unless (and (stringp value) (not (string-blank-p value)))
                 (agent-ui--fail "actions: action %d's %s must be text" i (substring (symbol-name key) 1)))))
           (unless (memq (plist-get action :submit) '(nil t :false))
             (agent-ui--fail "actions: action %d's submit is true or false" i)))
  actions)

(defun agent-ui--actions (actions)
  "ACTIONS as a line of buttons; nil if there are none (or they're wrong)."
  (when (and actions (ignore-errors (agent-ui-check-actions actions)))
    (mapconcat
     (lambda (action)
       (let ((prompt (plist-get action :prompt))
             (submit (eq (plist-get action :submit) t)))
         (agent-ui-button (propertize (concat "⏵ " (plist-get action :label)) 'face 'agent-ui-action)
                          (lambda () (funcall agent-ui-action-function prompt submit))
                          (format "RET: %s \"%s\"" (if submit "send" "put into the prompt")
                                  (truncate-string-to-width prompt 60 nil nil "…")))))
     actions "   ")))

(defun agent-ui-render (element ctx)
  "ELEMENT drawn as text, its title on a line above: by its type's :gui in a
graphic frame (CTX's :graphic) if it has one, else :text. An error (an
unknown type, a property wrong, the drawing failing) is drawn in its place,
so a canvas goes on with its other elements. No newline at its end."
  (let ((title (plist-get element :title)))
    ;; Only text: a title of another kind is the element's error to show.
    (unless (stringp title) (setq title nil))
    (concat
     (when (and title (not (equal title "")))
       (concat (propertize (format "%s" title) 'face 'agent-ui-title) "\n"))
     (condition-case err
         (let* ((type (agent-ui-type (plist-get element :type)))
                (props (agent-ui-check type element))
                (draw (or (and (plist-get ctx :graphic) (agent-ui-type-gui type))
                          (agent-ui-type-text type)))
                (text (funcall draw props ctx)))
           (unless (stringp text)
             (agent-ui--fail "%s: its drawing returned %s, not text"
                             (agent-ui-type-name type) (agent-ui--show-value text)))
           (agent-ui--cap (string-trim-right text "\n+")))
       (error
        (propertize (concat "⚠ " (agent-ui-error-message err)) 'face 'agent-ui-error)))
     ;; Its actions, buttons: not in a still picture (CTX's :still).
     (when-let* (((not (plist-get ctx :still)))
                 (buttons (agent-ui--actions (plist-get element :actions))))
       (concat "\n" buttons)))))

;; ====== HELPERS FOR TYPES ======

(defface agent-ui-accent '((t :inherit font-lock-keyword-face))
  "What's going on: a bar filling, a step running.")

(defconst agent-ui-spinner-frames ["⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"]
  "A spinner's frames, one per animation tick.")

(defun agent-ui-spinner (ctx)
  "The spinner's frame for CTX's tick."
  (aref agent-ui-spinner-frames
        (mod (or (plist-get ctx :tick) 0) (length agent-ui-spinner-frames))))

(defun agent-ui-truncate (string width)
  "STRING cut to WIDTH columns, with … if it's cut."
  (if (<= (string-width string) width)
      string
    (truncate-string-to-width string (max 0 width) nil nil (if (> width 0) "…" ""))))

(defun agent-ui-wrap (string width)
  "STRING with each line longer than WIDTH columns broken at spaces (a word
wider than WIDTH, within it). Its lines are kept; their properties too. A
line takes a character at least, even one wider than WIDTH (a CJK one in a
column), and WIDTH is 1 at least: it always moves on."
  (setq width (max 1 width))
  (mapconcat
   (lambda (line)
     (let ((lines nil))
       (while (> (string-width line) width)
         (let* ((head (truncate-string-to-width line width))
                (space (string-match-p " [^ ]*\\'" head))
                (cut (max 1 (cond
                             ;; It ends at a word's end.
                             ((eq (aref line (length head)) ?\s) (length head))
                             ((and space (> space 0)) space)
                             (t (length head))))))
           (push (substring line 0 cut) lines)
           (setq line (string-trim-left (substring line cut) " +"))))
       ;; Nothing left after a cut: no empty line for it.
       (string-join (nreverse (if (and lines (string-empty-p line)) lines (cons line lines))) "\n")))
   (split-string string "\n")
   "\n"))

(defun agent-ui-pad (string width &optional align)
  "STRING in WIDTH columns (cut if wider): ALIGN left (default), right or
center."
  (let* ((string (agent-ui-truncate string width))
         (space (max 0 (- width (string-width string)))))
    (pcase align
      ('right (concat (make-string space ?\s) string))
      ('center (concat (make-string (/ space 2) ?\s) string
                       (make-string (- space (/ space 2)) ?\s)))
      (_ (concat string (make-string space ?\s))))))

(defun agent-ui-format-number (number)
  "NUMBER as text: an integer as is, a float with at most 2 decimals; under
1, 3 significant digits (0.004, 0.0112: with 2 decimals they read 0, 0.01)."
  (cond ((integerp number) (number-to-string number))
        ((and (floatp number) (= number (ffloor number)) (< (abs number) 1e15))
         (number-to-string (truncate number)))
        ((floatp number)
         (let ((decimals (if (< (abs number) 1)
                             (+ 2 (ceiling (- (log (abs number) 10))))
                           2)))
           (string-trim-right (string-trim-right (format (format "%%.%df" (min 20 decimals)) number) "0+")
                              "\\.")))
        (t (format "%s" number))))

(defvar agent-ui-clock #'float-time
  "What gives the time now, in seconds (tests stub it): a progress bar's
rate, a step's time.")

(defun agent-ui-format-duration (seconds)
  "SECONDS as a duration: 8s, 2m 05s, 1h 02m."
  (let ((s (round seconds)))
    (cond ((< s 60) (format "%ds" s))
          ((< s 3600) (format "%dm %02ds" (/ s 60) (% s 60)))
          (t (format "%dh %02dm" (/ s 3600) (/ (% s 3600) 60))))))

(defvar-keymap agent-ui-button-map
  :doc "Keys of an element's button: its action."
  "RET" #'agent-ui-button-press
  "<mouse-1>" #'agent-ui-button-press
  "<follow-link>" 'mouse-face)

(defun agent-ui-button (text action &optional help)
  "TEXT, a button: RET or a click on it calls ACTION (a function of no
argument); HELP said in the echo area."
  (propertize text
              'agent-ui-action action
              'keymap agent-ui-button-map
              'mouse-face 'highlight
              'help-echo (or help "RET: open")))

(defun agent-ui-button-press (&optional event)
  "Call the action of the button at point (or EVENT's)."
  (interactive (list last-nonmenu-event))
  (let* ((pos (if (mouse-event-p event) (posn-point (event-end event)) (point)))
         (buffer (if (mouse-event-p event) (window-buffer (posn-window (event-end event))) (current-buffer)))
         (action (get-text-property pos 'agent-ui-action buffer)))
    ;; In the button's buffer: its action may ask it (a canvas: its session).
    (if action
        (with-current-buffer buffer (funcall action))
      (user-error "Nothing to do here"))))

(defun agent-ui-cell (value)
  "VALUE (a JSON scalar) as text: a number formatted, true and false, null
empty."
  (cond ((null value) "")
        ((eq value t) "true")
        ((eq value :false) "false")
        ((numberp value) (agent-ui-format-number value))
        ((stringp value) value)
        (t (format "%s" value))))

;; ====== JSON ======

(defun agent-ui-parse-json (string)
  "STRING, JSON, as Lisp: objects as plists (keys as keywords), arrays as
lists, null as nil, false as :false (see `agent-ui-check')."
  (condition-case err
      (json-parse-string string :object-type 'plist :array-type 'list
                         :null-object nil :false-object :false)
    (json-error
     (agent-ui--fail "bad JSON: %s" (error-message-string err)))))

(defun agent-ui--plist-p (value)
  (and (consp value)
       (keywordp (car value))
       (proper-list-p value)
       (cl-evenp (length value))
       (cl-loop for (k _) on value by #'cddr always (keywordp k))))

(defun agent-ui-to-json (value)
  "VALUE as `json-serialize' takes it: plists as objects, other lists as
arrays, symbols as strings, nil as null."
  (cond
   ((eq value t) t)
   ((memq value '(nil :null)) :null)
   ((eq value :false) :false)
   ((agent-ui--plist-p value)
    (cl-loop for (k v) on value by #'cddr nconc (list k (agent-ui-to-json v))))
   ((consp value) (vconcat (mapcar #'agent-ui-to-json value)))
   ((vectorp value) (vconcat (mapcar #'agent-ui-to-json value)))
   ((keywordp value) (substring (symbol-name value) 1))
   ((symbolp value) (symbol-name value))
   (t value)))

;; ====== THE CATALOG ======

(defun agent-ui-catalog ()
  "The element types, for the agent: a list of plists (:name :doc :props
:example), ready for `agent-ui-to-json'."
  (mapcar
   (lambda (name)
     (let ((type (agent-ui-type name)))
       (append
        (list :name (symbol-name name)
              :doc (agent-ui-type-doc type)
              :props (vconcat
                      (mapcar (lambda (p)
                                (append
                                 (list :name (substring (symbol-name (agent-ui-prop-key p)) 1)
                                       :kind (agent-ui--kind-name (agent-ui-prop-kind p))
                                       :doc (agent-ui-prop-doc p))
                                 (when (agent-ui-prop-required p) (list :required t))
                                 (when (agent-ui-prop-default p)
                                   (list :default (agent-ui-to-json (agent-ui-prop-default p))))))
                              (agent-ui-type-props type))))
        (when (agent-ui-type-example type)
          (list :example (agent-ui-to-json
                          (append (list :type (symbol-name name))
                                  (agent-ui-type-example type))))))))
   (agent-ui-types)))
