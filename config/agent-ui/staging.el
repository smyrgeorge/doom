;;; $DOOMDIR/config/agent-ui/staging.el -*- lexical-binding: t; -*-
;; Agent UI's element types made by the agent: staged, then kept or
;; discarded by the user. Loaded from config/agent-ui.el. No Doom here.
;;
;; The agent sends a type's code (cmd/agent-ui define FILE): one
;; `agent-ui-define' and the definitions it uses, named after it. It's
;; checked (its forms, its name), written to `agent-ui-staging-directory',
;; byte-compiled (errors refuse it, warnings go back to the agent), loaded,
;; and its example drawn: the agent gets that drawing back, to see what it
;; made. The type can be used at once. The user then reviews it
;; (`agent-ui-review'): keeping it moves its file to
;; `agent-ui-kept-directory', loaded at each start; discarding it deletes it,
;; and the elements of it. A staged type isn't loaded again after a restart:
;; it waits in its folder for the review.

(require 'cl-lib)
(require 'subr-x)
(require 'bytecomp)

;; ====== VARIABLES ======

(defcustom agent-ui-staging-directory (locate-user-emacs-file "agent-ui/staged/")
  "Where the types the agent made wait for the user's review."
  :type 'directory :group 'agent-ui)

(defcustom agent-ui-kept-directory (locate-user-emacs-file "agent-ui/kept/")
  "Where the types the user kept are, loaded at each start
\(`agent-ui-load-kept')."
  :type 'directory :group 'agent-ui)

(defcustom agent-ui-staging-requires '(cl-lib subr-x seq map pcase rx svg)
  "What a type the agent made may `require'."
  :type '(repeat symbol) :group 'agent-ui)

(defvar agent-ui-staged-functions nil
  "Called with a type's name (a symbol) once the agent staged it.")

(defvar agent-ui-kept-functions nil
  "Called with a type's name and its file once the user kept it.")

(defconst agent-ui--definers
  '(defun defsubst cl-defun defmacro defconst defvar defvar-local defface defcustom
    declare-function)
  "What a type's other forms may be: definitions, named after it.")

;; ====== WHERE TYPES ARE ======

(defun agent-ui--in-directory-p (file dir)
  (and file (string-prefix-p (file-name-as-directory (file-truename dir)) (file-truename file))))

(defun agent-ui-staged-p (name)
  "Whether the type NAME is one the agent made, not yet reviewed."
  (let ((type (gethash name agent-ui--types)))
    (and type (agent-ui--in-directory-p (agent-ui-type-file type) agent-ui-staging-directory))))

(defun agent-ui-staged-files ()
  "The staged types' files, loaded or not (after a restart), newest first."
  (when (file-directory-p agent-ui-staging-directory)
    (sort (directory-files agent-ui-staging-directory t "\\`[a-z][a-z0-9-]*\\.el\\'")
          (lambda (a b) (time-less-p (file-attribute-modification-time (file-attributes b))
                                     (file-attribute-modification-time (file-attributes a)))))))

(defun agent-ui-load-kept ()
  "Load the types the user kept (`agent-ui-kept-directory'); one that fails
to load is said, the others go on."
  (when (file-directory-p agent-ui-kept-directory)
    (dolist (file (directory-files agent-ui-kept-directory t "\\`[a-z][a-z0-9-]*\\.el\\'"))
      (condition-case err
          (load file nil t)
        (error (message "Agent UI: the kept type %s doesn't load: %s"
                        (file-name-base file) (error-message-string err)))))))

;; ====== CHECKING THE CODE ======

(defun agent-ui--read-forms (code)
  "CODE's top-level forms; an error saying where it doesn't read."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (let (forms)
      (condition-case err
          (while (progn (forward-comment (buffer-size)) (not (eobp)))
            (push (read (current-buffer)) forms))
        (end-of-file
         (agent-ui--fail "define: the code ends inside a form (a parenthesis or quote missing?)"))
        (error (agent-ui--fail "define: the code doesn't read, at line %d: %s"
                               (line-number-at-pos) (cadr err))))
      (nreverse forms))))

(defun agent-ui--check-forms (forms)
  "The type FORMS define, its name; an error for a form a type's code
mustn't have (see `agent-ui-stage')."
  (let* ((defines (seq-filter (lambda (f) (eq (car-safe f) 'agent-ui-define)) forms))
         (name (cadr (car defines))))
    (unless (= (length defines) 1)
      (agent-ui--fail "define: the code must define one type (one agent-ui-define), not %d"
                      (length defines)))
    (unless (and (symbolp name) (string-match-p "\\`[a-z][a-z0-9-]*\\'" (symbol-name name)))
      (agent-ui--fail "define: a type's name is a symbol of a-z, 0-9 and -, not %S" name))
    (let ((prefix (format "agent-ui-%s-" name)))
      (dolist (form forms)
        (pcase form
          (`(agent-ui-define . ,_))
          (`(require ',(and feature (pred symbolp)) . ,_)
           (unless (memq feature agent-ui-staging-requires)
             (agent-ui--fail "define: a type may require only %s, not %s"
                             (mapconcat #'symbol-name agent-ui-staging-requires ", ") feature)))
          (`(,(and definer (pred (lambda (d) (memq d agent-ui--definers))))
             ,(and def (pred symbolp)) . ,_)
           (unless (or (eq definer 'declare-function)
                       (string-prefix-p prefix (symbol-name def)))
             (agent-ui--fail "define: %s is named %s: a type's definitions are named %s..., after it"
                             definer def prefix)))
          (_ (agent-ui--fail "define: only definitions belong in a type's code, not %s"
                             (truncate-string-to-width (format "%S" form) 60 nil nil "…"))))))
    name))

;; ====== STAGING ======

(defun agent-ui--byte-compile (file &optional offset what)
  "Byte-compile FILE (nothing written, no log shown); its warnings, as
strings, their lines OFFSET less (lines added before the agent's code).
Signals `agent-ui-error' with its errors if it doesn't compile, led by WHAT
\(default \"define\")."
  (let* ((messages nil)
         (dest (make-temp-file "agent-ui-" nil ".elc"))
         (ok (let ((byte-compile-dest-file-function (lambda (_) dest))
                   (byte-compile-log-warning-function
                    (lambda (string position &optional _fill level)
                      (push (list (or level :warning)
                                  (format "%s%s"
                                          (if position
                                              (with-temp-buffer
                                                (insert-file-contents file)
                                                (format "line %d: " (- (line-number-at-pos
                                                                        (min (point-max) (max 1 position)))
                                                                       (or offset 0))))
                                            "")
                                          string))
                            messages)))
                   (inhibit-message t))
               (unwind-protect
                   (condition-case err
                       (byte-compile-file file)
                     (error (push (list :error (error-message-string err)) messages) nil))
                 (delete-file dest))))
         (messages (nreverse messages)))
    (unless (and ok (not (assq :error messages)))
      (agent-ui--fail "%s: it doesn't compile: %s" (or what "define")
                      (string-join (or (mapcar #'cadr (seq-filter (lambda (m) (eq (car m) :error)) messages))
                                       '("(no message)"))
                                   "; ")))
    (mapcar #'cadr messages)))

(defun agent-ui--forget-type (name)
  "Forget the type NAME, and remove the elements of it from every canvas."
  (agent-ui-undefine name)
  (dolist (canvas (agent-ui-canvases))
    (dolist (element (agent-ui-elements :canvas canvas))
      (when (equal (plist-get element :type) (symbol-name name))
        (agent-ui-remove (plist-get element :id) :canvas canvas)))))

(defun agent-ui--redraw-type (name)
  "Redraw the elements of the type NAME, everywhere."
  (dolist (canvas (agent-ui-canvases))
    (with-current-buffer canvas
      (agent-ui--dirty (cl-loop for id in agent-ui--order
                                when (equal (plist-get (agent-ui--entry-element (gethash id agent-ui--entries)) :type)
                                            (symbol-name name))
                                collect id)))))

(defun agent-ui-stage (code)
  "Stage the element type CODE defines: checked, compiled, loaded, its
example drawn (see the top of this file). Returns (:type NAME :file FILE
:warnings LIST :preview TEXT). Signals `agent-ui-error' if it's refused;
then nothing of it stays."
  (let* ((name (agent-ui--check-forms (agent-ui--read-forms code)))
         (existing (gethash name agent-ui--types)))
    (when (and existing (not (agent-ui-staged-p name)))
      (agent-ui--fail "define: %s is a type already (built in or kept): name yours otherwise" name))
    (make-directory agent-ui-staging-directory t)
    (let* ((file (expand-file-name (format "%s.el" name) agent-ui-staging-directory))
           (temp (make-temp-file (format "agent-ui-%s-" name) nil ".el"))
           (header (not (string-match-p "lexical-binding: *t" (car (split-string code "\n")))))
           (text (if (not header)
                     code
                   (format ";;; %s.el --- Agent UI type %s, made by the agent -*- lexical-binding: t; -*-\n%s"
                           name name code))))
      (unwind-protect
          (progn
            (with-temp-file temp
              (setq-local coding-system-for-write 'utf-8)
              (insert text))
            (let ((warnings (agent-ui--byte-compile temp (if header 1 0)))
                  (previous existing))
              (condition-case err
                  (progn
                    (agent-ui-undefine name)
                    (load temp nil t t)
                    (let ((type (gethash name agent-ui--types)))
                      (unless type
                        (agent-ui--fail "define: loaded, it defined no type %s" name))
                      (unless (agent-ui-type-example type)
                        (agent-ui--fail "define: %s has no :example (the user's preview, the agent's catalog)" name))
                      (let ((preview (agent-ui-render (append (list :type (symbol-name name))
                                                              (agent-ui-type-example type))
                                                      (agent-ui-context :width 80))))
                        (when (eq (get-text-property (max 0 (1- (length preview))) 'face preview) 'agent-ui-error)
                          (agent-ui--fail "define: its example doesn't draw: %s"
                                          (substring-no-properties preview)))
                        ;; Right: its file in the staging folder, where it's from.
                        (rename-file temp file t)
                        (setf (agent-ui-type-file type) file)
                        (agent-ui--redraw-type name)
                        (run-hook-with-args 'agent-ui-staged-functions name)
                        (list :type (symbol-name name) :file file
                              :warnings (vconcat warnings)
                              :preview (substring-no-properties preview)))))
                (error
                 ;; Refused: the type it replaced, back (or none).
                 (agent-ui-undefine name)
                 (when previous (puthash name previous agent-ui--types))
                 (signal (car err) (cdr err))))))
        (when (file-exists-p temp) (delete-file temp))))))

(defun agent-ui-stage-file (file)
  "Stage the type in FILE again (after a restart: for its review)."
  (agent-ui-stage (with-temp-buffer
                    (insert-file-contents file)
                    (buffer-string))))

;; ====== KEEPING, DISCARDING ======

(defun agent-ui--staged-file (name)
  (let ((file (expand-file-name (format "%s.el" name) agent-ui-staging-directory)))
    (unless (file-exists-p file)
      (agent-ui--fail "no staged type %s" name))
    file))

(defun agent-ui-keep (name)
  "Keep the staged type NAME: its file moved to `agent-ui-kept-directory',
loaded from there from now on. Returns its new file."
  (let* ((file (agent-ui--staged-file name))
         (kept (expand-file-name (format "%s.el" name) agent-ui-kept-directory)))
    (unless (agent-ui-staged-p name)
      (agent-ui-stage-file file))
    (make-directory agent-ui-kept-directory t)
    (rename-file file kept t)
    (setf (agent-ui-type-file (agent-ui-type name)) kept)
    (run-hook-with-args 'agent-ui-kept-functions name kept)
    kept))

(defun agent-ui-discard (name)
  "Discard the staged type NAME: its file deleted, the type forgotten, the
elements of it removed."
  (let ((file (agent-ui--staged-file name)))
    (when (agent-ui-staged-p name)
      (agent-ui--forget-type name))
    (delete-file file)
    name))
