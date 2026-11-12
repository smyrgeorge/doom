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
(require 'color)
(require 'svg)

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

(defconst agent-ui--reserved '(:id :type :title :source :actions :close)
  "Keys every element may have; no type's property is named so. :close only
on a type that finishes (its :finished).")

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
  name doc props example animated text gui append check prepare extend file finished whole)

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

(cl-defun agent-ui--register (name doc &key props example animated text gui append check prepare extend finished
                                   whole file)
  "Define the element type NAME (see `agent-ui-define'); replaces one so named."
  (unless (and (symbolp name) (string-match-p "\\`[a-z][a-z0-9-]*\\'" (symbol-name name)))
    (agent-ui--fail "%S: a type's name is a symbol of a-z, 0-9 and -" name))
  (unless (stringp doc)
    (agent-ui--fail "%s: no documentation string" name))
  (unless (functionp text)
    (agent-ui--fail "%s: no :text function drawing it" name))
  (dolist (fn (list gui append check prepare extend finished (and (not (eq animated t)) animated)))
    (when (and fn (not (functionp fn)))
      (agent-ui--fail "%s: %S isn't a function" name fn)))
  (let* ((props (mapcar (lambda (entry) (agent-ui--parse-prop name entry)) props))
         (keys (mapcar #'agent-ui-prop-key props))
         (type (agent-ui--make-type :name name :doc doc :props props :example example
                                    :animated animated :text text :gui gui
                                    :append append :check check :prepare prepare :extend extend
                                    :finished finished :whole whole :file file)))
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
  :extend   (lambda (OLD NEW CTX) ...) when it was drawn as OLD and is now
            NEW (lines appended to it, say), both checked: the edits making
            OLD's drawing NEW's, or nil to draw it again (optional: else it's
            drawn again). Edits, a list done in order on its drawing's lines
            (from 0): (replace LINE TEXT), (delete LINE COUNT), (insert
            BEFORE-END TEXT), TEXT lines put before its last BEFORE-END lines
            (0: at its end). For drawing only what's appended to a long one.
  :finished (lambda (PROPS) ...) whether it finished: `done' (all of it
            went well), `failed' (some of it didn't), nil (not yet). A type
            that finishes takes :close, and closes itself once done (see
            config/agent-ui/finished.el).
  :whole    t: its drawing isn't cut at `agent-ui-max-chars' as a whole
            (each element it draws in it is: a panel's children); it keeps
            its own size in bounds (a panel cuts its lines inside its frame).

Defining a type again replaces it."
  (declare (indent defun) (doc-string 2))
  (let ((unknown (cl-loop for (k _) on args by #'cddr
                          unless (memq k '(:props :example :text :gui :animated :append :check :prepare :extend
                                               :finished :whole))
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
                       :extend ,(plist-get args :extend)
                       :finished ,(plist-get args :finished)
                       :whole ,(plist-get args :whole)
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

(cl-defun agent-ui-context (&key (width 80) graphic (tick 0) (char-width 8) (line-height 16) font-size font-ascent
                                 id still)
  "What an element's drawing knows of where it's drawn: WIDTH in characters,
GRAPHIC (a graphic frame, else a terminal), TICK (counts up, for
animations), and in a graphic frame a character's CHAR-WIDTH and a line's
LINE-HEIGHT in pixels (for images sized to the text), the text's
FONT-SIZE and FONT-ASCENT in pixels if known (an image drawing a character
as the text does). STILL: a still picture of it (a snapshot), where
buttons would do nothing: none drawn."
  (append (list :width width :graphic graphic :tick tick
                :char-width char-width :line-height line-height)
          (when (and font-size font-ascent) (list :font-size font-size :font-ascent font-ascent))
          ;; The element's id, in a canvas: its buttons may change it.
          (when id (list :id id))
          (when still (list :still t))))

(defun agent-ui-finished (element)
  "Whether ELEMENT finished (its type's :finished): `done', `failed', or nil
\(not yet, wrong, or of a type that doesn't finish)."
  (condition-case nil
      (let* ((type (agent-ui-type (plist-get element :type)))
             (finished (agent-ui-type-finished type)))
        (and finished (funcall finished (agent-ui-check type element))))
    (error nil)))

(defun agent-ui-check-close (close type)
  "CLOSE, an element's :close (seconds after it finished, true, or false),
of TYPE: an error saying what's wrong, else itself."
  (unless (or (memq close '(t :false)) (and (numberp close) (>= close 0)))
    (agent-ui--fail "close: seconds after it finished (10), true, or false to keep it; not %s"
                    (agent-ui--show-value close)))
  (unless (agent-ui-type-finished (agent-ui-type type))
    (agent-ui--fail "close: a %s doesn't finish (steps, todo and progress do)"
                    (agent-ui-type-name (agent-ui-type type))))
  close)

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
  "TEXT, cut at `agent-ui-max-chars' with a line saying what was left out:
at the end of the last line that fits (a line longer than it all: in it)."
  (if (<= (length text) agent-ui-max-chars)
      text
    (let* ((end (or (cl-position ?\n text :end (1+ agent-ui-max-chars) :from-end t)
                    agent-ui-max-chars)))
      (concat (substring text 0 end)
              "\n"
              (propertize (format "… %d characters more" (- (length text) end))
                          'face 'agent-ui-muted)))))

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
     ;; One line, cut to the width (never cut: 56 columns at 20).
     (when (and title (not (equal title "")))
       (let ((title (replace-regexp-in-string "[\n\r]+" " " title))
             (width (plist-get ctx :width)))
         (concat (propertize (if width (agent-ui-truncate title width) title) 'face 'agent-ui-title) "\n")))
     (condition-case err
         (let* ((type (agent-ui-type (plist-get element :type)))
                (props (agent-ui-check type element))
                (draw (or (and (plist-get ctx :graphic) (agent-ui-type-gui type))
                          (agent-ui-type-text type)))
                (text (funcall draw props ctx)))
           (unless (stringp text)
             (agent-ui--fail "%s: its drawing returned %s, not text"
                             (agent-ui-type-name type) (agent-ui--show-value text)))
           ;; A type keeping its own size in bounds (`:whole'): as drawn.
           (if (agent-ui-type-whole type)
               (string-trim-right text "\n+")
             (agent-ui--cap (string-trim-right text "\n+"))))
       (error
        (propertize (concat "⚠ " (agent-ui-error-message err)) 'face 'agent-ui-error)))
     ;; Its actions, buttons: not in a still picture (CTX's :still).
     (when-let* (((not (plist-get ctx :still)))
                 (buttons (agent-ui--actions (plist-get element :actions))))
       (concat "\n" buttons)))))

;; ====== HELPERS FOR TYPES ======

(defface agent-ui-accent '((t :inherit font-lock-keyword-face))
  "What's going on: a bar filling, a step running.")

(defcustom agent-ui-spinner-frames '("▟" "▙" "▛" "▜")
  "A spinner's frames, one per animation tick: a gap going round a square,
clockwise. Block elements, which coding and terminal fonts have (braille,
⠋⠙⠹..., came from a fallback font whose dots are tiny: every frame looked
the same)."
  :type '(repeat string))

(defun agent-ui-spinner (ctx)
  "The spinner's frame for CTX's tick."
  (elt agent-ui-spinner-frames
       (mod (or (plist-get ctx :tick) 0) (length agent-ui-spinner-frames))))

(defun agent-ui-truncate (string width)
  "STRING cut to WIDTH columns, with … if it's cut."
  (if (<= (string-width string) width)
      string
    (truncate-string-to-width string (max 0 width) nil nil (if (> width 0) "…" ""))))

(defun agent-ui-truncate-middle (string width)
  "STRING cut to WIDTH columns in its middle, with …: its start and its end
kept (a path's folder and its file's name)."
  (if (<= (string-width string) width)
      string
    (let* ((room (max 0 (1- width)))
           (head (truncate-string-to-width string (- room (/ room 2))))
           (tail (truncate-string-to-width (reverse string) (/ room 2))))
      (if (> width 0) (concat head "…" (reverse tail)) ""))))

(defun agent-ui-truncate-start (string width)
  "STRING cut to WIDTH columns at its start, with …: its end kept (a path's
file name: …/parser.c)."
  (cond ((<= (string-width string) width) string)
        ((< width 1) "")
        (t (concat "…" (reverse (truncate-string-to-width (reverse string) (1- width)))))))

(defun agent-ui-untabify (string &optional width)
  "STRING with its tabs as spaces up to the next tab stop, every WIDTH
columns (`tab-width''s default, 8): tab-aligned text stays aligned (each
tab 4 spaces, whatever its column, it didn't)."
  (if (not (string-search "\t" string))
      string
    (let ((width (or width (default-value 'tab-width))))
      (mapconcat
       (lambda (line)
         (let ((column 0) (parts (split-string line "\t")) (out nil))
           (while parts
             (push (car parts) out)
             (setq column (+ column (string-width (car parts))))
             (when (cdr parts)
               (let ((spaces (- width (% column width))))
                 (push (make-string spaces ?\s) out)
                 (setq column (+ column spaces))))
             (setq parts (cdr parts)))
           (apply #'concat (nreverse out))))
       (split-string string "\n")
       "\n"))))

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

;; A click on a button is mouse-2 (as button.el's): one on a link (follow-link)
;; quicker than `mouse-1-click-follows-link' is made mouse-2, Evil's
;; down-mouse-1 selecting again the window clicked from. Unbound, it was the
;; global `mouse-yank-primary': the selection pasted at point there (with
;; `mouse-yank-at-point', a session's prompt), the button not pressed.
;; The press (down-mouse-1) is the global drag's, or Evil's (which win over a
;; text property's keymap): it leaves an active mark at the click, a region
;; the button's press drops (`agent-ui-button-press'; the action's redraw
;; moved that mark to the element's start: everything above the button
;; highlighted, a visual selection with Evil).
(defvar-keymap agent-ui-button-map
  :doc "Keys of an element's button: its action."
  "RET" #'agent-ui-button-press
  "<mouse-1>" #'agent-ui-button-press
  "<mouse-2>" #'agent-ui-button-press
  "<follow-link>" 'mouse-face)

(defun agent-ui-button (text action &optional help)
  "TEXT, a button: RET or a click on it calls ACTION (a function of no
argument); HELP said in the echo area."
  (propertize text
              'agent-ui-action action
              'keymap agent-ui-button-map
              'mouse-face 'highlight
              'help-echo (or help "RET: open")))

(defvar agent-ui-before-press-hook nil
  "Run in a button's buffer before its action is looked up: a canvas draws
what changed first (canvas.el), so the action is its current drawing's, not
the one before a change just made (pressed again at once).")

(defun agent-ui-button-press (&optional event)
  "Call the action of the button at point (or EVENT's). A click: the region
its press left (see `agent-ui-button-map') dropped first."
  (interactive (list last-nonmenu-event))
  (let ((buffer (if (mouse-event-p event) (window-buffer (posn-window (event-end event))) (current-buffer))))
    (with-current-buffer buffer
      (when (mouse-event-p event)
        (deactivate-mark))
      (run-hooks 'agent-ui-before-press-hook)))
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

;; ====== BADGES ======
;; A pill (a rounded tag: PASSED, P1, a label, a count in it) and a pie (a
;; compact progress), for any type. Their text, as wide in a terminal as in
;; the GUI, where an SVG (svg.el, sized from the context's :char-width and
;; :line-height, in the theme's colours) shows over it: the text stays
;; underneath (searched, copied, a snapshot's).

(defun agent-ui-color (face)
  "FACE's foreground as a colour for SVG (a grey where faces have none: in
batch)."
  (let ((color (face-foreground face nil 'default)))
    (if (and (stringp color) (not (string-prefix-p "unspecified" color))) color "#888888")))

(defun agent-ui-background ()
  "The default face's background, for SVG (black where there's none)."
  (let ((color (face-background 'default nil t)))
    (if (and (stringp color) (not (string-prefix-p "unspecified" color))) color "#000000")))

(defun agent-ui-blend (a b share)
  "Colour A with SHARE (0 to 1) of colour B in it."
  (let ((ra (color-name-to-rgb a)) (rb (color-name-to-rgb b)))
    (if (and ra rb)
        (apply #'color-rgb-to-hex (append (cl-mapcar (lambda (x y) (+ (* x (- 1 share)) (* y share))) ra rb)
                                          '(2)))
      a)))

(defun agent-ui-image (image)
  "IMAGE (`create-image''s) without a background of its own: its transparent
parts show what's behind them, the buffer's background, or a selection's
\(solaire-mode gives every image its buffer's background: a selection left
it out, gaps in it)."
  (cons (car image) (agent-ui--plist-delete (cdr image) :background)))

(defun agent-ui-svg-image (svg)
  "SVG as an image on its line (centred on it), without a background of its
own (`agent-ui-image')."
  (agent-ui-image (svg-image svg :scale 1 :ascent 'center)))

(defun agent-ui--svg-font ()
  "The default face's family, for SVG text."
  (let ((family (face-attribute 'default :family nil t)))
    (if (and (stringp family) (not (member family '("default" "unspecified")))) family "monospace")))

;; ====== GLYPHS IN THEIR CELLS ======
;; In the GUI, a character the default font lacks comes from another font,
;; often wider or narrower than its columns (✎ 17 pixels where a column is
;; 11, ⏵ 10), and taller (⏵'s font: a line 28 pixels high, not 25): what
;; follows it on its line moved by as much, a panel's border, the │ between
;; a row's children a few pixels out of line, with a gap in it on that line.
;; Text going into a buffer is evened out: such a glyph drawn as large as a
;; line holds (its line as high as the others), the space beside it as much
;; narrower or wider as it is, what follows it at its column again.

(defvar agent-ui--glyphs (make-hash-table :test #'equal)
  "How glyphs are shown, measured: (CHAR FACE) to (WIDTH . HEIGHT), its
width in pixels at HEIGHT, the size it's drawn at (nil: its own).")

(defvar agent-ui--glyphs-font nil
  "The font the glyphs in `agent-ui--glyphs' were measured with.")

(defconst agent-ui--glyph-heights '(0.95 0.9 0.85 0.8 0.75 0.7 0.65 0.6 0.55 0.5)
  "The sizes a glyph taller than a line is tried at, the largest first.")

(defun agent-ui--glyph-measure (char face buffer)
  "How CHAR with FACE is shown in BUFFER (its face remappings): (WIDTH .
HEIGHT), HEIGHT the largest of `agent-ui--glyph-heights' drawing it no
taller than a line of the default font, nil if it is no taller (or none
does), WIDTH in pixels at that size."
  (let ((remapping (and (buffer-live-p buffer) (buffer-local-value 'face-remapping-alist buffer))))
    (with-current-buffer (get-buffer-create " *agent-ui-glyphs*")
      (setq-local face-remapping-alist remapping)
      (cl-flet ((size (&optional glyph height)
                  ;; Beside a character of the default font: the line's
                  ;; height is the taller of both.
                  (erase-buffer)
                  (insert "x")
                  (when glyph
                    (insert (propertize (string glyph) 'face face 'display (and height `(height ,height)))))
                  (buffer-text-pixel-size nil nil t)))
        (let* ((x (size))
               (line (cdr x))
               (own (size char)))
          (if (<= (cdr own) line)
              (cons (- (car own) (car x)) nil)
            (or (cl-loop for height in agent-ui--glyph-heights
                         for (width . high) = (size char height)
                         when (<= high line) return (cons (- width (car x)) height))
                (cons (- (car own) (car x)) nil))))))))

(defun agent-ui--glyph (char face buffer)
  "How CHAR with FACE is shown in BUFFER: (WIDTH . HEIGHT), as
`agent-ui--glyph-measure' says, measured once a font."
  (let ((font (list (frame-char-width) (frame-char-height) (face-font 'default))))
    (unless (equal font agent-ui--glyphs-font)
      (clrhash agent-ui--glyphs)
      (setq agent-ui--glyphs-font font)))
  (let ((key (list char face)))
    (or (gethash key agent-ui--glyphs)
        (puthash key (agent-ui--glyph-measure char face buffer) agent-ui--glyphs))))

(defun agent-ui--plain-space-p (text pos)
  "Whether TEXT has a space at POS, showing nothing else (not an image's)."
  (and (>= pos 0) (< pos (length text))
       (eq (aref text pos) ?\s)
       (not (get-text-property pos 'display text))))

(defun agent-ui-even-glyphs (text &optional buffer)
  "TEXT, going into BUFFER (default: the current one), evened out in the GUI:
a glyph taller than a line drawn smaller, as large as a line holds; what
follows a glyph of another width than its columns at its column again, the
space after it (else before it) as much narrower or wider; a narrower one
with no space beside it padded to its columns. A copy; TEXT itself in a
terminal, where a glyph is its cell."
  (if (not (display-graphic-p))
      text
    (let ((text (copy-sequence text))
          (buffer (or buffer (current-buffer)))
          (cw (frame-char-width))
          (spaces nil)
          (pos 0))
      (while (setq pos (string-match "[^\000-\177]" text pos))
        (let ((char (aref text pos)))
          (unless (get-text-property pos 'display text)
            (pcase-let* ((columns (* cw (char-width char)))
                         (`(,width . ,height) (agent-ui--glyph char (get-text-property pos 'face text) buffer))
                         (delta (- columns width))
                         (space (and (/= delta 0)
                                     (cond ((agent-ui--plain-space-p text (1+ pos)) (1+ pos))
                                           ((agent-ui--plain-space-p text (1- pos)) (1- pos)))))
                         (display
                          (delq nil (list (and height `(height ,height))
                                          ;; Its own list: `min-width' tells
                                          ;; its ranges apart by it.
                                          (and (not space) (> delta 0)
                                               (list 'min-width (list (list columns))))))))
              (when space
                (setf (alist-get space spaces) (+ delta (alist-get space spaces 0))))
              (when display
                (put-text-property pos (1+ pos) 'display (if (cdr display) display (car display)) text)))))
        (setq pos (1+ pos)))
      (pcase-dolist (`(,space . ,delta) spaces)
        (put-text-property space (1+ space) 'display `(space :width (,(max 0 (+ cw delta)))) text))
      text)))

(defun agent-ui--gui-p (ctx)
  "Whether CTX draws for the GUI (and knows its cells' size)."
  (and (plist-get ctx :graphic) (plist-get ctx :char-width) (plist-get ctx :line-height) t))

(defun agent-ui-face (name)
  "The face a type's face NAME says (a symbol or a string): plain, muted,
success, warning, error, accent; nil for plain or another."
  (pcase (if (stringp name) (intern-soft name) name)
    ('muted 'agent-ui-muted)
    ('success 'agent-ui-success)
    ('warning 'agent-ui-warning)
    ('error 'agent-ui-error)
    ('accent 'agent-ui-accent)
    (_ nil)))

(cl-defun agent-ui-pill (label ctx &key (face 'agent-ui-accent) filled count)
  "LABEL as a pill in FACE (a face, or a colour: \"#d19a66\"): FILLED (its
colour behind it) or outlined; COUNT after it. Its text \" LABEL COUNT \"
\(filled: FACE's colour behind) or \"[LABEL COUNT]\", as wide either way; in
the GUI (CTX), a rounded tag over it."
  (let* ((count (and count (format "%s" (if (numberp count) (agent-ui-format-number count) count))))
         (inner (concat label (if count (concat " " count) "")))
         (color (and (stringp face) face))
         (face (if color `(:foreground ,color) face))
         (on (if color `(:foreground ,color :inverse-video t) `(:inherit ,face :inverse-video t)))
         (text (if filled
                   (propertize (concat " " inner " ") 'face on)
                 (concat (propertize "[" 'face 'agent-ui-muted)
                         (propertize label 'face face)
                         (if count (propertize (concat " " count) 'face 'agent-ui-muted) "")
                         (propertize "]" 'face 'agent-ui-muted)))))
    (if (not (agent-ui--gui-p ctx))
        text
      (let* ((cw (plist-get ctx :char-width))
             (lh (plist-get ctx :line-height))
             (w (* cw (string-width text)))
             (color (or color (agent-ui-color face)))
             (bg (agent-ui-background))
             (svg (svg-create w lh)))
        (svg-rectangle svg 0.5 1.5 (- w 1) (- lh 3) :rx (/ (- lh 3) 2.0)
                       :fill (if filled color (agent-ui-blend bg color 0.14))
                       :stroke color :stroke-width 1)
        (svg-text svg inner :x (/ w 2.0) :y (* 0.72 lh) :text-anchor "middle"
                  :font-size (round (* 0.7 lh)) :font-family (agent-ui--svg-font)
                  :fill (if filled bg color))
        (propertize text 'display (agent-ui-svg-image svg))))))

(defun agent-ui-pie (fraction ctx &optional face)
  "FRACTION (0 to 1) as a pie in FACE (the accent's by default), two columns:
its text a quarter's glyph (○◔◑◕●) and a space; in the GUI (CTX), a pie
over it."
  (let* ((face (or face 'agent-ui-accent))
         (f (max 0.0 (min 1.0 (float fraction))))
         (text (concat (propertize (string (aref "○◔◑◕●" (round (* f 4)))) 'face face) " ")))
    (if (not (agent-ui--gui-p ctx))
        text
      (let* ((cw (plist-get ctx :char-width))
             (lh (plist-get ctx :line-height))
             (w (* 2 cw))
             (r (- (/ (min w lh) 2.0) 1.5))
             (cx (/ w 2.0)) (cy (/ lh 2.0))
             (color (agent-ui-color face))
             (svg (svg-create w lh)))
        (svg-circle svg cx cy r :fill (agent-ui-blend (agent-ui-background) color 0.2)
                    :stroke color :stroke-width 1)
        (cond
         ((>= f 1.0) (svg-circle svg cx cy r :fill color))
         ((> f 0.0)
          (let* ((angle (* 2 float-pi f))
                 (ex (+ cx (* r (sin angle))))
                 (ey (- cy (* r (cos angle)))))
            (svg-node svg 'path :fill color
                      :d (format "M %.2f %.2f L %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f Z"
                                 cx cy cx (- cy r) r r (if (> f 0.5) 1 0) ex ey)))))
        (propertize text 'display (agent-ui-svg-image svg))))))

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
